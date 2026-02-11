package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// KeyDir is the persistent local directory for API keys.
const KeyDir = ".config/promptharbor"

// Config is the top-level typed configuration for PromptHarbor.
type Config struct {
	Controller  ControllerConfig  `yaml:"controller"`
	Storage     StorageConfig     `yaml:"storage"`
	VastAI      VastAIConfig      `yaml:"vast_ai"`
	CivitAI     CivitAIConfig     `yaml:"civitai"`
	HuggingFace HuggingFaceConfig `yaml:"huggingface"`
	GCP         GCPConfig         `yaml:"gcp"`
	Limits      LimitsConfig      `yaml:"limits"`
}

type ControllerConfig struct {
	Addr    string `yaml:"addr"`     // Listen address, e.g. ":8080"
	DataDir string `yaml:"data_dir"` // Path to ./state
	DBFile  string `yaml:"db_file"`  // e.g. "ph.db"
}

type StorageConfig struct {
	Backend    string `yaml:"backend"`     // "local" or "gcs"
	LocalDir   string `yaml:"local_dir"`   // For local backend
	GCSBucket  string `yaml:"gcs_bucket"`  // e.g. "ph-outputs-2026"
	GCSAssets  string `yaml:"gcs_assets"`  // e.g. "ph-assets-2026"
	GCSGallery string `yaml:"gcs_gallery"` // e.g. "ph-gallery-2026"
}

type VastAIConfig struct {
	APIKey      string  `yaml:"api_key"`
	DefaultGPU  string  `yaml:"default_gpu"`  // e.g. "RTX_5090"
	MaxPriceHr  float64 `yaml:"max_price_hr"` // e.g. 0.50
	DefaultDisk float64 `yaml:"default_disk"` // GB
	DockerImage string  `yaml:"docker_image"` // pinned image tag
}

type CivitAIConfig struct {
	APIKey string `yaml:"api_key"`
}

type HuggingFaceConfig struct {
	Token string `yaml:"token"`
}

type GCPConfig struct {
	CredsPath string `yaml:"creds_path"` // Path to service account JSON
	Project   string `yaml:"project"`    // GCP project ID
}

type LimitsConfig struct {
	MaxConcurrentJobs  int     `yaml:"max_concurrent_jobs"`
	MaxConcurrentNodes int     `yaml:"max_concurrent_nodes"`
	DailyBudget        float64 `yaml:"daily_budget"`       // $ per day
	MaxPricePerHour    float64 `yaml:"max_price_per_hour"` // $/hr per instance
	IdleTimeoutMin     int     `yaml:"idle_timeout_min"`   // minutes before auto-destroy
	PerRunTimeout      int     `yaml:"per_run_timeout"`    // seconds
	MaxInstanceMinutes int     `yaml:"max_instance_minutes"`
}

// DefaultConfig returns sensible defaults.
func DefaultConfig() Config {
	return Config{
		Controller: ControllerConfig{
			Addr:    ":8080",
			DataDir: "./state",
			DBFile:  "ph.db",
		},
		Storage: StorageConfig{
			Backend:    "local",
			LocalDir:   "./state/artifacts",
			GCSBucket:  "ph-outputs-2026",
			GCSAssets:  "ph-assets-2026",
			GCSGallery: "ph-gallery-2026",
		},
		VastAI: VastAIConfig{
			DefaultGPU:  "RTX_5090",
			MaxPriceHr:  0.50,
			DefaultDisk: 60,
			DockerImage: "pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime",
		},
		Limits: LimitsConfig{
			MaxConcurrentJobs:  4,
			MaxConcurrentNodes: 2,
			DailyBudget:        10.00,
			PerRunTimeout:      1800, // 30 min
			MaxInstanceMinutes: 120,  // 2 hours
		},
	}
}

// Load reads a YAML config file and merges with defaults.
func Load(path string) (Config, error) {
	cfg := DefaultConfig()

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return cfg, nil // Use defaults if no config file
		}
		return cfg, fmt.Errorf("read config: %w", err)
	}

	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return cfg, fmt.Errorf("parse config: %w", err)
	}

	// Override with environment variables
	cfg.applyEnvOverrides()

	// Validate
	if err := cfg.Validate(); err != nil {
		return cfg, fmt.Errorf("config validation: %w", err)
	}

	return cfg, nil
}

// loadKeyFile reads a key from ~/.config/promptharbor/<name>, trimming whitespace.
func loadKeyFile(name string) string {
	home, _ := os.UserHomeDir()
	if home == "" {
		return ""
	}
	data, err := os.ReadFile(filepath.Join(home, KeyDir, name))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func (c *Config) applyEnvOverrides() {
	if v := os.Getenv("PH_ADDR"); v != "" {
		c.Controller.Addr = v
	}
	if v := os.Getenv("PH_DATA_DIR"); v != "" {
		c.Controller.DataDir = v
	}
	if v := os.Getenv("PH_STORAGE_BACKEND"); v != "" {
		c.Storage.Backend = v
	}
	if v := os.Getenv("PH_GCS_BUCKET"); v != "" {
		c.Storage.GCSBucket = v
	}

	// Vast.ai key: env > config > ~/.config/promptharbor/vast_api_key
	if v := os.Getenv("VAST_API_KEY"); v != "" {
		c.VastAI.APIKey = v
	} else if c.VastAI.APIKey == "" {
		c.VastAI.APIKey = loadKeyFile("vast_api_key")
	}

	// CivitAI key: env > config > ~/.config/promptharbor/civitai_api_key
	if v := os.Getenv("CIVITAI_API_KEY"); v != "" {
		c.CivitAI.APIKey = v
	} else if c.CivitAI.APIKey == "" {
		c.CivitAI.APIKey = loadKeyFile("civitai_api_key")
	}

	// HuggingFace token: env > config > ~/.config/promptharbor/hf_token
	if v := os.Getenv("HF_TOKEN"); v != "" {
		c.HuggingFace.Token = v
	} else if c.HuggingFace.Token == "" {
		c.HuggingFace.Token = loadKeyFile("hf_token")
	}

	// GCP creds: env > config > ~/.config/promptharbor/gcp-sa-key.json
	if v := os.Getenv("GOOGLE_APPLICATION_CREDENTIALS"); v != "" {
		c.GCP.CredsPath = v
	} else if c.GCP.CredsPath == "" {
		home, _ := os.UserHomeDir()
		candidate := filepath.Join(home, KeyDir, "gcp-sa-key.json")
		if _, err := os.Stat(candidate); err == nil {
			c.GCP.CredsPath = candidate
		}
	}
	if v := os.Getenv("GCP_PROJECT"); v != "" {
		c.GCP.Project = v
	}
}

func (c *Config) Validate() error {
	if c.Controller.Addr == "" {
		return fmt.Errorf("controller.addr is required")
	}
	if c.Controller.DataDir == "" {
		return fmt.Errorf("controller.data_dir is required")
	}
	if c.Storage.Backend != "local" && c.Storage.Backend != "gcs" {
		return fmt.Errorf("storage.backend must be 'local' or 'gcs', got %q", c.Storage.Backend)
	}
	if c.Storage.Backend == "gcs" && c.Storage.GCSBucket == "" {
		return fmt.Errorf("storage.gcs_bucket required when backend=gcs")
	}
	if c.Limits.MaxConcurrentJobs < 1 {
		return fmt.Errorf("limits.max_concurrent_jobs must be >= 1")
	}
	if c.Limits.DailyBudget <= 0 {
		return fmt.Errorf("limits.daily_budget must be > 0")
	}
	return nil
}
