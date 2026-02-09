package vast

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

const BaseURL = "https://console.vast.ai/api/v0"

type Client struct {
	ApiKey string
	HTTP   *http.Client
}

func NewClient(apiKey string) *Client {
	return &Client{
		ApiKey: apiKey,
		HTTP:   &http.Client{Timeout: 30 * time.Second},
	}
}

type Offer struct {
	ID          int     `json:"id"`
	MachineID   int     `json:"machine_id"`
	HostID      int     `json:"host_id"`
	DphTotal    float64 `json:"dph_total"` // $/hr
	GpuName     string  `json:"gpu_name"`
	NumGpus     int     `json:"num_gpus"`
	GpuRam      int     `json:"gpu_ram"`      // MB
	DlPerf      float64 `json:"dlperf"`       // DL performance score
	Reliability float64 `json:"reliability2"` // 0-1
	InetUp      float64 `json:"inet_up"`      // Mbps
	InetDown    float64 `json:"inet_down"`    // Mbps
	DiskSpace   float64 `json:"disk_space"`   // GB
}

type Instance struct {
	ID              int    `json:"id"`
	Status          string `json:"actual_status"` // 'running', 'loading', 'exited'
	SshHost         string `json:"ssh_host"`
	SshPort         int    `json:"ssh_port"`
	DirectPortStart int    `json:"direct_port_start"`
	DirectPortEnd   int    `json:"direct_port_end"`
	Label           string `json:"label"`
}

// SearchOffers queries the /bundles endpoint with specific criteria
func (c *Client) SearchOffers(gpuName string, maxPrice float64, diskGB float64) ([]Offer, error) {
	qMap := map[string]interface{}{
		"verified":          map[string]interface{}{"eq": true},
		"external":          map[string]interface{}{"eq": false},
		"rentable":          map[string]interface{}{"eq": true},
		"type":              "on-demand",
		"num_gpus":          map[string]interface{}{"eq": 1},
		"dph_total":         map[string]interface{}{"lt": maxPrice},
		"disk_space":        map[string]interface{}{"gt": diskGB},
		"reliability2":      map[string]interface{}{"gt": 0.95},
		"inet_down":         map[string]interface{}{"gt": 200.0},
		"order":             [][]string{{"dph_total", "asc"}},
		"allocated_storage": diskGB,
	}

	if gpuName != "" {
		qMap["gpu_name"] = map[string]interface{}{"eq": gpuName}
	}

	qBytes, _ := json.Marshal(qMap)
	v := url.Values{}
	v.Set("q", string(qBytes))

	u := fmt.Sprintf("%s/bundles?%s", BaseURL, v.Encode())
	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.ApiKey)
	req.Header.Set("Accept", "application/json")

	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("api error %d: %s", resp.StatusCode, string(body))
	}

	var result struct {
		Offers []Offer `json:"offers"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	return result.Offers, nil
}

// LaunchInstance calls PUT /asks/{id}/
func (c *Client) LaunchInstance(offerID int, image string, diskGB float64, onStartCmd string) (*Instance, error) {
	u := fmt.Sprintf("%s/asks/%d/", BaseURL, offerID)

	payload := map[string]interface{}{
		"client_id": "me",
		"image":     image,
		"args_str":  "", // docker args
		"onstart":   onStartCmd,
		"disk":      diskGB,
		"runtype":   "ssh", // usually 'ssh' or 'jupyter' or 'args'
	}

	bodyBytes, _ := json.Marshal(payload)
	req, err := http.NewRequest("PUT", u, bytes.NewBuffer(bodyBytes))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.ApiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("launch failed %d: %s", resp.StatusCode, string(b))
	}

	var res map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&res); err != nil {
		return nil, err
	}

	if val, ok := res["success"].(bool); !ok || !val {
		return nil, fmt.Errorf("launch returned success=false: %v", res)
	}

	contractID := int(res["new_contract"].(float64))
	return &Instance{ID: contractID, Status: "creating"}, nil
}

// DestroyInstance terminates an instance
func (c *Client) DestroyInstance(contractID int) error {
	u := fmt.Sprintf("%s/instances/%d/", BaseURL, contractID)
	req, err := http.NewRequest("DELETE", u, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.ApiKey)
	req.Header.Set("Accept", "application/json")

	resp, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("destroy failed %d: %s", resp.StatusCode, string(b))
	}

	var res map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&res)
	if val, ok := res["success"].(bool); !ok || !val {
		return fmt.Errorf("destroy returned success=false: %v", res)
	}
	return nil
}

// ListInstances fetches all active instances
func (c *Client) ListInstances() ([]Instance, error) {
	u := fmt.Sprintf("%s/instances", BaseURL)
	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.ApiKey)
	req.Header.Set("Accept", "application/json")

	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("list instances failed: %d", resp.StatusCode)
	}

	var result struct {
		Instances []Instance `json:"instances"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	return result.Instances, nil
}

// GetInstance fetches current status of a specific instance
func (c *Client) GetInstance(contractID int) (*Instance, error) {
	instances, err := c.ListInstances()
	if err != nil {
		return nil, err
	}

	for _, inst := range instances {
		if inst.ID == contractID {
			return &inst, nil
		}
	}
	return nil, fmt.Errorf("instance %d not found", contractID)
}
