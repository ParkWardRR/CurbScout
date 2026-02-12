// Package providers defines a common interface for GPU compute providers
// (Vast.ai, RunPod, Lambda, AWS, local). This lets the controller schedule
// across providers without knowing implementation details.
package providers

import (
	"github.com/ParkWardRR/PromptHarbor/pkg/hwprofile"
)

// Offer represents an available GPU machine from any provider.
type Offer struct {
	ProviderName string                      `json:"provider"`       // "vast", "runpod", "lambda", "local"
	OfferID      string                      `json:"offer_id"`       // provider-specific ID
	HostID       string                      `json:"host_id"`        // provider-specific host
	PricePerHour float64                     `json:"price_per_hour"` // $/hr
	GPUName      string                      `json:"gpu_name"`
	GPUCount     int                         `json:"gpu_count"`
	GPUVRAM      int                         `json:"gpu_vram_mb"`
	DiskGB       float64                     `json:"disk_gb"`
	InetUpMbps   float64                     `json:"inet_up_mbps"`
	InetDownMbps float64                     `json:"inet_down_mbps"`
	Reliability  float64                     `json:"reliability"` // 0-1
	DLPerf       float64                     `json:"dlperf"`      // DL benchmark score
	Signature    hwprofile.HardwareSignature `json:"hw_signature"`
}

// Instance represents a running compute instance from any provider.
type Instance struct {
	ProviderName string `json:"provider"`
	InstanceID   string `json:"instance_id"`
	Status       string `json:"status"` // creating, running, exited
	SSHHost      string `json:"ssh_host"`
	SSHPort      int    `json:"ssh_port"`
}

// Provider is the interface all compute providers must implement.
type Provider interface {
	// Name returns the provider identifier (e.g. "vast", "runpod")
	Name() string

	// Search finds available offers matching criteria.
	Search(opts SearchOpts) ([]Offer, error)

	// Launch starts a new instance on the given offer.
	Launch(offerID string, config LaunchConfig) (*Instance, error)

	// GetInstance returns current status of a running instance.
	GetInstance(instanceID string) (*Instance, error)

	// ListInstances returns all active instances.
	ListInstances() ([]Instance, error)

	// Destroy terminates an instance.
	Destroy(instanceID string) error
}

// SearchOpts contains criteria for searching compute offers.
type SearchOpts struct {
	GPUName     string  // empty = any GPU
	MaxPrice    float64 // $/hr
	MinDiskGB   float64
	MinVRAM     int     // MB
	MinInetDown float64 // Mbps
}

// LaunchConfig contains parameters for launching an instance.
type LaunchConfig struct {
	Image         string // Docker image
	DiskGB        float64
	OnStartScript string            // bash script to run on boot
	EnvVars       map[string]string // environment variables
	Labels        map[string]string // metadata labels
}
