# Vast.ai Go SDK

A production-grade Go toolkit for programmatic Vast.ai GPU instance management.

## Packages

### `vast/` — API Client
Direct HTTP client for the Vast.ai REST API.

```go
import "your-module/vast"

client := vast.NewClient(apiKey)

// Search offers
offers, _ := client.SearchOffers("RTX_4090", 0.50, 100.0)

// Launch instance
inst, _ := client.LaunchInstance(offers[0].ID, "pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime", 100, onStartScript)

// List all instances
instances, _ := client.ListInstances()

// Destroy
client.DestroyInstance(inst.ID)
```

### `providers/` — Multi-Provider Interface
Abstract interface so your code works with any GPU provider:

```go
import "your-module/providers"

type Provider interface {
    Name() string
    Search(opts SearchOpts) ([]Offer, error)
    Launch(offerID string, config LaunchConfig) (*Instance, error)
    GetInstance(instanceID string) (*Instance, error)
    ListInstances() ([]Instance, error)
    Destroy(instanceID string) error
}
```

The `vast.VastProvider` implements this interface.

### `ssh/` — SSH Client
SSH client with agent forwarding and port tunneling:

```go
import "your-module/ssh"

client, _ := ssh.Connect("ssh2.vast.ai", 37012, "root")
defer client.Close()

// Run command
client.Run("nvidia-smi", os.Stdout, os.Stderr)

// Forward port (local:8188 → remote:8188)
client.Forward(8188, 8188)
```

### `config/` — Configuration
YAML config with cascading overrides (env > config > key files):

```go
import "your-module/config"

cfg, _ := config.Load("config.yaml")
// cfg.VastAI.APIKey  — resolved from env, config, or ~/.config/promptharbor/vast_api_key
// cfg.GCP.CredsPath  — resolved from env, config, or ~/.config/promptharbor/gcp-sa-key.json
```

### `budget/` — Cost Guardrails
Automatic budget enforcement with idle timeout and daily caps:

```go
import "your-module/budget"

guard := budget.NewGuard(
    10.00,              // $10/day max
    0.50,               // $0.50/hr max per instance
    30 * time.Minute,   // idle timeout
)

ok, reason := guard.CanLaunch(0.35)
guard.TrackInstance("inst-123", "vast", 0.35)
guard.RecordActivity("inst-123")

// Background enforcement loop
go guard.EnforceLoop(ctx, destroyFn, 30*time.Second)
```

### `hwprofile/` — Hardware Signatures
Fingerprint GPU hardware and track performance across runs:

```go
import "your-module/hwprofile"

sig := hwprofile.HardwareSignature{
    GPUName: "RTX 4090",
    GPUVRAM: 24576,
    InetDown: 800,
}
sigID := sig.ID() // stable hash for this hardware config

// Track performance
store.RecordRun(ctx, sig, downloadS, renderS, encodeS, uploadS, cost, success)

// Get best hardware for scheduling (UCB1 bandit)
profiles, _ := store.BestSignature(24000)
```

### `storage/` — GCS + Local Storage
Unified interface for local and GCS storage:

```go
import "your-module/storage"

// Local
store, _ := storage.NewLocalStore("./artifacts")

// GCS
gcsStore, _ := storage.NewGCSStore(ctx, "my-bucket")

// Both implement storage.Store interface
store.Upload(ctx, "run/output.mp4", reader)
store.Download(ctx, "run/output.mp4")
store.List(ctx, "run/")
```

## CLI (`vastctl`)

```bash
go build -o vastctl ./cmd/vastctl/

# Search for GPUs
./vastctl -gpu RTX_4090 -price 0.50 search

# Launch with SSH tunnel and log streaming
./vastctl -gpu RTX_4090 -price 0.50 -disk 100 -tunnel launch

# List active instances  
./vastctl list

# Destroy
./vastctl destroy <INSTANCE_ID>
```

### CLI Flags

| Flag | Default | Description |
|------|---------|-------------|
| `-api-key` | env/config | Vast.ai API Key |
| `-gpu` | `RTX_5090` | GPU model to search |
| `-price` | `0.50` | Max $/hr |
| `-disk` | `60` | Disk GB |
| `-image` | `pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime` | Docker image |
| `-gcs` | `ph-test-2026` | GCS bucket |
| `-creds` | auto | GCP service account JSON path |
| `-tunnel` | false | Auto SSH tunnel + log streaming |
| `-script` | `provision.sh` | GCS script to execute |

## Dependencies

```
golang.org/x/crypto         # SSH
cloud.google.com/go/storage  # GCS
gopkg.in/yaml.v3             # Config
modernc.org/sqlite           # Hardware profiles (pure Go SQLite)
```
