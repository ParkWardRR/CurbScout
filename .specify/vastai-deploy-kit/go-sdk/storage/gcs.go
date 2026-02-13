package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strings"

	"cloud.google.com/go/storage"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
)

// ParseGCSURI parses a gs://bucket/path/to/object URI.
func ParseGCSURI(uri string) (bucket, object string, err error) {
	if !strings.HasPrefix(uri, "gs://") {
		return "", "", errors.New("invalid GCS URI: must start with gs://")
	}
	parts := strings.SplitN(uri[5:], "/", 2)
	if len(parts) < 2 {
		return "", "", errors.New("invalid GCS URI: missing object path")
	}
	return parts[0], parts[1], nil
}

type GCSStore struct {
	Client     *storage.Client
	BucketName string
	BaseURL    string // e.g. "https://storage.googleapis.com/<bucket>"
}

func NewGCSStore(ctx context.Context, bucketName string, opts ...option.ClientOption) (*GCSStore, error) {
	client, err := storage.NewClient(ctx, opts...)
	if err != nil {
		return nil, fmt.Errorf("create gcs client: %w", err)
	}
	return &GCSStore{
		Client:     client,
		BucketName: bucketName,
		BaseURL:    "https://storage.googleapis.com/" + bucketName,
	}, nil
}

func (s *GCSStore) Backend() string { return "gcs" }

func (s *GCSStore) Upload(ctx context.Context, path string, r io.Reader) error {
	w := s.Client.Bucket(s.BucketName).Object(path).NewWriter(ctx)
	if _, err := io.Copy(w, r); err != nil {
		w.Close()
		return fmt.Errorf("gcs upload copy: %w", err)
	}
	if err := w.Close(); err != nil {
		return fmt.Errorf("gcs upload close: %w", err)
	}
	return nil
}

func (s *GCSStore) Download(ctx context.Context, path string) (io.ReadCloser, error) {
	r, err := s.Client.Bucket(s.BucketName).Object(path).NewReader(ctx)
	if err != nil {
		return nil, fmt.Errorf("gcs download: %w", err)
	}
	return r, nil
}

func (s *GCSStore) List(ctx context.Context, prefix string) ([]string, error) {
	var objects []string
	it := s.Client.Bucket(s.BucketName).Objects(ctx, &storage.Query{Prefix: prefix})
	for {
		attrs, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("gcs list: %w", err)
		}
		objects = append(objects, attrs.Name)
	}
	return objects, nil
}

func (s *GCSStore) URL(path string) string {
	// Assumes public read access if used for public URLs
	return fmt.Sprintf("%s/%s", s.BaseURL, path)
}
