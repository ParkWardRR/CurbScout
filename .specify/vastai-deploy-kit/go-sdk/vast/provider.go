// Package vast provides the Vast.ai implementation of the providers.Provider interface.
package vast

import (
	"fmt"
	"strconv"

	"github.com/ParkWardRR/PromptHarbor/pkg/hwprofile"
	"github.com/ParkWardRR/PromptHarbor/pkg/providers"
)

// VastProvider implements providers.Provider using the Vast.ai API.
type VastProvider struct {
	client *Client
}

// NewVastProvider creates a Vast.ai provider from an API key.
func NewVastProvider(apiKey string) *VastProvider {
	return &VastProvider{client: NewClient(apiKey)}
}

func (v *VastProvider) Name() string { return "vast" }

func (v *VastProvider) Search(opts providers.SearchOpts) ([]providers.Offer, error) {
	offers, err := v.client.SearchOffers(opts.GPUName, opts.MaxPrice, opts.MinDiskGB)
	if err != nil {
		return nil, err
	}

	result := make([]providers.Offer, 0, len(offers))
	for _, o := range offers {
		sig := hwprofile.HardwareSignature{
			GPUName:  o.GpuName,
			GPUVRAM:  o.GpuRam,
			InetUp:   o.InetUp,
			InetDown: o.InetDown,
		}

		if opts.MinVRAM > 0 && o.GpuRam < opts.MinVRAM {
			continue
		}

		result = append(result, providers.Offer{
			ProviderName: "vast",
			OfferID:      strconv.Itoa(o.ID),
			HostID:       strconv.Itoa(o.HostID),
			PricePerHour: o.DphTotal,
			GPUName:      o.GpuName,
			GPUCount:     o.NumGpus,
			GPUVRAM:      o.GpuRam,
			DiskGB:       o.DiskSpace,
			InetUpMbps:   o.InetUp,
			InetDownMbps: o.InetDown,
			Reliability:  o.Reliability,
			DLPerf:       o.DlPerf,
			Signature:    sig,
		})
	}
	return result, nil
}

func (v *VastProvider) Launch(offerID string, config providers.LaunchConfig) (*providers.Instance, error) {
	id, _ := strconv.Atoi(offerID)
	inst, err := v.client.LaunchInstance(id, config.Image, config.DiskGB, config.OnStartScript)
	if err != nil {
		return nil, err
	}
	return &providers.Instance{
		ProviderName: "vast",
		InstanceID:   strconv.Itoa(inst.ID),
		Status:       inst.Status,
		SSHHost:      inst.SshHost,
		SSHPort:      inst.SshPort,
	}, nil
}

func (v *VastProvider) GetInstance(instanceID string) (*providers.Instance, error) {
	id, _ := strconv.Atoi(instanceID)
	inst, err := v.client.GetInstance(id)
	if err != nil {
		return nil, err
	}
	return &providers.Instance{
		ProviderName: "vast",
		InstanceID:   strconv.Itoa(inst.ID),
		Status:       inst.Status,
		SSHHost:      inst.SshHost,
		SSHPort:      inst.SshPort,
	}, nil
}

func (v *VastProvider) ListInstances() ([]providers.Instance, error) {
	instances, err := v.client.ListInstances()
	if err != nil {
		return nil, err
	}
	result := make([]providers.Instance, len(instances))
	for i, inst := range instances {
		result[i] = providers.Instance{
			ProviderName: "vast",
			InstanceID:   strconv.Itoa(inst.ID),
			Status:       inst.Status,
			SSHHost:      inst.SshHost,
			SSHPort:      inst.SshPort,
		}
	}
	return result, nil
}

func (v *VastProvider) Destroy(instanceID string) error {
	id, err := strconv.Atoi(instanceID)
	if err != nil {
		return fmt.Errorf("invalid instance ID %q: %w", instanceID, err)
	}
	return v.client.DestroyInstance(id)
}
