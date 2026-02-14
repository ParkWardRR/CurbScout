package storage

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// Store is the interface for artifact storage. Implementations exist for
// local disk and GCS. The controller can work in local-only mode (no GCP).
type Store interface {
	// Upload writes data to the given path. The path is relative to the store root.
	Upload(ctx context.Context, path string, r io.Reader) error

	// Download returns a reader for the given path.
	Download(ctx context.Context, path string) (io.ReadCloser, error)

	// List returns all object paths under the given prefix.
	List(ctx context.Context, prefix string) ([]string, error)

	// URL returns a public/signed URL for the given path.
	URL(path string) string

	// Backend returns the backend type ("local" or "gcs").
	Backend() string
}

// --- Local Disk Implementation ---

type LocalStore struct {
	BaseDir string
	BaseURL string // e.g. "http://localhost:8080/artifacts"
}

func NewLocalStore(baseDir string) (*LocalStore, error) {
	if err := os.MkdirAll(baseDir, 0755); err != nil {
		return nil, fmt.Errorf("create store dir: %w", err)
	}
	return &LocalStore{BaseDir: baseDir, BaseURL: "/artifacts"}, nil
}

func (s *LocalStore) Backend() string { return "local" }

func (s *LocalStore) Upload(ctx context.Context, path string, r io.Reader) error {
	fullPath := filepath.Join(s.BaseDir, path)
	if err := os.MkdirAll(filepath.Dir(fullPath), 0755); err != nil {
		return err
	}

	f, err := os.Create(fullPath)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = io.Copy(f, r)
	return err
}

func (s *LocalStore) Download(ctx context.Context, path string) (io.ReadCloser, error) {
	return os.Open(filepath.Join(s.BaseDir, path))
}

func (s *LocalStore) List(ctx context.Context, prefix string) ([]string, error) {
	var result []string
	root := filepath.Join(s.BaseDir, prefix)
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // skip errors
		}
		if !info.IsDir() {
			rel, _ := filepath.Rel(s.BaseDir, path)
			result = append(result, rel)
		}
		return nil
	})
	return result, err
}

func (s *LocalStore) URL(path string) string {
	return fmt.Sprintf("%s/%s", s.BaseURL, path)
}

// --- Content-Addressed Path Helper ---

// RunPath generates a collision-proof path for a run's artifacts.
// Format: runs/<date>/<run_id>/<filename>
func RunPath(runID string, filename string) string {
	date := time.Now().Format("2006-01-02")
	return fmt.Sprintf("runs/%s/%s/%s", date, runID, filename)
}

// ManifestPath returns the path for a run's manifest.
func ManifestPath(runID string) string {
	return RunPath(runID, "manifest.json")
}
