// Package hwprofile provides hardware signature matching and tuning profile
// management for heterogeneous GPU compute (Vast.ai, RunPod, etc.).
//
// Key concepts:
//   - HardwareSignature: normalized fingerprint of GPU/CPU/network/disk
//   - TuningProfile: recommended runtime params + observed performance
//   - ProfileStore: persists profiles in SQLite + GCS for cross-session reuse
package hwprofile

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"strings"
	"time"

	"github.com/ParkWardRR/PromptHarbor/pkg/storage"
)

// ── Hardware Signature ──────────────────────────────────────

// HardwareSignature is a normalized fingerprint of the compute hardware.
// Built from Vast.ai offer attributes + agent runtime probe.
type HardwareSignature struct {
	GPUName   string  `json:"gpu_name"`               // e.g. "RTX 4090"
	GPUVRAM   int     `json:"gpu_vram_mb"`            // MB
	PCIeBW    float64 `json:"pcie_bw_gbps,omitempty"` // GB/s
	PCIeGen   int     `json:"pci_gen,omitempty"`      // 3,4,5
	CPUGHz    float64 `json:"cpu_ghz,omitempty"`      // base clock
	HasAVX    bool    `json:"has_avx,omitempty"`
	DiskBW    float64 `json:"disk_bw_mbps,omitempty"` // sequential MB/s
	InetUp    float64 `json:"inet_up_mbps"`           // Mbps
	InetDown  float64 `json:"inet_down_mbps"`         // Mbps
	CUDAVer   string  `json:"cuda_version,omitempty"` // "12.4"
	DriverVer string  `json:"driver_version,omitempty"`
}

// ID returns a stable, normalized signature hash (first 12 hex chars).
// Two machines with same hardware profile get the same ID.
func (s *HardwareSignature) ID() string {
	// Normalize: lowercase GPU name, round floats to avoid noise
	norm := fmt.Sprintf("%s|%d|%.0f|%d|%.1f|%v|%.0f|%.0f|%.0f",
		strings.ToLower(strings.TrimSpace(s.GPUName)),
		s.GPUVRAM,
		s.PCIeBW,
		s.PCIeGen,
		s.CPUGHz,
		s.HasAVX,
		s.DiskBW,
		math.Round(s.InetUp/50)*50,   // bucket to 50 Mbps
		math.Round(s.InetDown/50)*50, // bucket to 50 Mbps
	)
	h := sha256.Sum256([]byte(norm))
	return fmt.Sprintf("%x", h[:6])
}

// ── Tuning Profile ──────────────────────────────────────────

// TuningProfile stores recommended runtime parameters and observed
// performance for a specific hardware signature.
type TuningProfile struct {
	SignatureID string            `json:"signature_id"`
	Signature   HardwareSignature `json:"signature"`

	// Recommended settings (populated after enough observations)
	RecommendedParams map[string]interface{} `json:"recommended_params,omitempty"` // batch_size, tiling, xformers, etc.

	// Observed performance (rolling averages)
	Observations   int     `json:"observations"`   // total runs on this signature
	AvgDownloadS   float64 `json:"avg_download_s"` // model download time
	AvgRenderS     float64 `json:"avg_render_s"`   // generation time
	AvgEncodeS     float64 `json:"avg_encode_s"`   // FFmpeg encode time
	AvgUploadS     float64 `json:"avg_upload_s"`   // GCS upload time
	AvgTotalS      float64 `json:"avg_total_s"`    // end-to-end
	AvgCostDollars float64 `json:"avg_cost_dollars"`

	// Bandit exploration
	SuccessRate      float64   `json:"success_rate"` // completed / total
	LastUpdated      time.Time `json:"last_updated"`
	ExplorationScore float64   `json:"exploration_score"` // UCB1 score for scheduling
}

// UpdateWithRun incorporates a new run's metrics using exponential moving average.
func (p *TuningProfile) UpdateWithRun(downloadS, renderS, encodeS, uploadS, costDollars float64, success bool) {
	p.Observations++
	n := float64(p.Observations)

	// Exponential moving average (alpha = 2/(n+1), capped at 0.3)
	alpha := math.Min(2.0/(n+1), 0.3)

	ema := func(old, new float64) float64 {
		return old*(1-alpha) + new*alpha
	}

	p.AvgDownloadS = ema(p.AvgDownloadS, downloadS)
	p.AvgRenderS = ema(p.AvgRenderS, renderS)
	p.AvgEncodeS = ema(p.AvgEncodeS, encodeS)
	p.AvgUploadS = ema(p.AvgUploadS, uploadS)
	p.AvgTotalS = ema(p.AvgTotalS, downloadS+renderS+encodeS+uploadS)
	p.AvgCostDollars = ema(p.AvgCostDollars, costDollars)

	if success {
		p.SuccessRate = ema(p.SuccessRate, 1.0)
	} else {
		p.SuccessRate = ema(p.SuccessRate, 0.0)
	}

	// UCB1 exploration score: mean reward + sqrt(2*ln(total)/n_i)
	// Higher = more worth trying (either good performance or under-explored)
	if p.Observations > 0 && p.AvgTotalS > 0 {
		efficiency := 1.0 / p.AvgCostDollars // higher = cheaper
		exploration := math.Sqrt(2.0 * math.Log(n+1) / n)
		p.ExplorationScore = p.SuccessRate*efficiency + exploration
	}

	p.LastUpdated = time.Now()
}

// ── Profile Store (SQLite + GCS) ────────────────────────────

const profileSchema = `
CREATE TABLE IF NOT EXISTS hw_profiles (
	signature_id TEXT PRIMARY KEY,
	signature_json TEXT NOT NULL,
	profile_json TEXT NOT NULL,
	observations INTEGER DEFAULT 0,
	avg_render_s REAL DEFAULT 0,
	avg_cost_dollars REAL DEFAULT 0,
	success_rate REAL DEFAULT 0,
	exploration_score REAL DEFAULT 0,
	last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
`

// ProfileStore persists tuning profiles in SQLite (local) and syncs to GCS.
type ProfileStore struct {
	db    *sql.DB
	store storage.Store // GCS for cross-session persistence
}

// NewProfileStore creates/opens the profile database.
func NewProfileStore(db *sql.DB, store storage.Store) (*ProfileStore, error) {
	if _, err := db.Exec(profileSchema); err != nil {
		return nil, fmt.Errorf("create hw_profiles table: %w", err)
	}
	return &ProfileStore{db: db, store: store}, nil
}

// GetProfile returns the tuning profile for a hardware signature.
func (ps *ProfileStore) GetProfile(sigID string) (*TuningProfile, error) {
	var sigJSON, profJSON string
	err := ps.db.QueryRow("SELECT signature_json, profile_json FROM hw_profiles WHERE signature_id = ?", sigID).
		Scan(&sigJSON, &profJSON)
	if err == sql.ErrNoRows {
		return nil, nil // no profile yet
	}
	if err != nil {
		return nil, err
	}

	var profile TuningProfile
	if err := json.Unmarshal([]byte(profJSON), &profile); err != nil {
		return nil, err
	}
	return &profile, nil
}

// SaveProfile persists a tuning profile to SQLite and GCS.
func (ps *ProfileStore) SaveProfile(ctx context.Context, p *TuningProfile) error {
	sigJSON, _ := json.Marshal(p.Signature)
	profJSON, _ := json.Marshal(p)

	_, err := ps.db.Exec(`
		INSERT OR REPLACE INTO hw_profiles 
		(signature_id, signature_json, profile_json, observations, avg_render_s, avg_cost_dollars, success_rate, exploration_score, last_updated)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		p.SignatureID, string(sigJSON), string(profJSON),
		p.Observations, p.AvgRenderS, p.AvgCostDollars, p.SuccessRate, p.ExplorationScore, p.LastUpdated,
	)
	if err != nil {
		return fmt.Errorf("save profile to SQLite: %w", err)
	}

	// Sync to GCS (best-effort, don't block on failure)
	if ps.store != nil && ps.store.Backend() == "gcs" {
		go func() {
			data, _ := json.MarshalIndent(p, "", "  ")
			path := fmt.Sprintf("hw_profiles/%s.json", p.SignatureID)
			if err := ps.store.Upload(ctx, path, strings.NewReader(string(data))); err != nil {
				log.Printf("[HWProfile] GCS sync failed for %s: %v", p.SignatureID, err)
			}
		}()
	}

	return nil
}

// RecordRun updates the profile for a hardware signature with a new run's metrics.
func (ps *ProfileStore) RecordRun(ctx context.Context, sig HardwareSignature, downloadS, renderS, encodeS, uploadS, costDollars float64, success bool) error {
	sigID := sig.ID()

	// Get or create profile
	profile, err := ps.GetProfile(sigID)
	if err != nil {
		return err
	}
	if profile == nil {
		profile = &TuningProfile{
			SignatureID: sigID,
			Signature:   sig,
			SuccessRate: 1.0, // optimistic prior
		}
	}

	profile.UpdateWithRun(downloadS, renderS, encodeS, uploadS, costDollars, success)

	log.Printf("[HWProfile] Updated %s (%s, %dMB VRAM) — obs=%d avg_render=%.1fs avg_cost=$%.4f success=%.0f%%",
		sigID, sig.GPUName, sig.GPUVRAM, profile.Observations,
		profile.AvgRenderS, profile.AvgCostDollars, profile.SuccessRate*100)

	return ps.SaveProfile(ctx, profile)
}

// BestSignature returns the signature with the highest exploration score,
// optionally filtered by GPU constraints.
func (ps *ProfileStore) BestSignature(minVRAM int) ([]TuningProfile, error) {
	rows, err := ps.db.Query(`
		SELECT profile_json FROM hw_profiles 
		WHERE observations > 0
		ORDER BY exploration_score DESC
		LIMIT 10
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var profiles []TuningProfile
	for rows.Next() {
		var profJSON string
		if err := rows.Scan(&profJSON); err != nil {
			continue
		}
		var p TuningProfile
		if err := json.Unmarshal([]byte(profJSON), &p); err != nil {
			continue
		}
		if minVRAM > 0 && p.Signature.GPUVRAM < minVRAM {
			continue
		}
		profiles = append(profiles, p)
	}
	return profiles, nil
}

// ListProfiles returns all known profiles for display/debugging.
func (ps *ProfileStore) ListProfiles() ([]TuningProfile, error) {
	return ps.BestSignature(0)
}

// RestoreFromGCS downloads all profiles from GCS and imports them.
func (ps *ProfileStore) RestoreFromGCS(ctx context.Context) error {
	if ps.store == nil || ps.store.Backend() != "gcs" {
		return nil
	}

	paths, err := ps.store.List(ctx, "hw_profiles/")
	if err != nil {
		log.Printf("[HWProfile] No GCS profiles found: %v", err)
		return nil
	}

	imported := 0
	for _, path := range paths {
		rc, err := ps.store.Download(ctx, path)
		if err != nil {
			continue
		}
		var p TuningProfile
		if err := json.NewDecoder(rc).Decode(&p); err != nil {
			rc.Close()
			continue
		}
		rc.Close()

		if err := ps.SaveProfile(ctx, &p); err == nil {
			imported++
		}
	}

	if imported > 0 {
		log.Printf("[HWProfile] Restored %d profiles from GCS", imported)
	}
	return nil
}
