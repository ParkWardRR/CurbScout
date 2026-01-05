# Vast.ai Deploy Kit

> **Production-grade GPU fleet orchestration for Vast.ai**
> Autonomous bootstrapping, real-time GCS sync, drain-safe auto-kill, budget guardrails, and a Go SDK for programmatic control.

---

## Architecture

```
┌─────────────────────────────┐         ┌──────────────────────────────┐
│  LOCAL MACHINE              │         │  VAST.AI GPU INSTANCE        │
│                             │         │                              │
│  vastctl (Go CLI)           │ ──SSH─► │  bootstrap_autonomous.sh     │
│    ├─ search offers         │         │    ├─ Install deps            │
│    ├─ launch instance       │         │    ├─ Download models (HF)    │
│    ├─ list / destroy        │         │    ├─ Download workflow (GCS) │
│    └─ SSH tunnel + logs     │         │    ├─ Download input images   │
│                             │         │    ├─ Submit jobs to API      │
│  fleet_poll.py (optional)   │ ◄─API─  │    └─ Launch instant sync    │
│    └─ writes fleet_status   │         │                              │
│                             │         │  instant_gcs_sync.sh         │
│  vast-sync-v4.sh (alt)      │ ──SSH─► │    ├─ inotifywait (instant)  │
│    └─ polls + uploads       │         │    ├─ .done.json markers     │
│                             │         │    ├─ gallery_data.json       │
│  auto-shutdown.sh           │ ──SSH─► │    └─ drain-safe auto-kill   │
│    └─ verify + destroy      │         │                              │
└─────────────────────────────┘         └──────────┬───────────────────┘
                                                   │ upload
                                       ┌───────────▼───────────────────┐
                                       │  GCS BUCKET (ph-test-2026)    │
                                       │  ├─ deploy/  (scripts+images) │
                                       │  ├─ outputs/<HOST>/  (videos) │
                                       │  ├─ gallery_data.json         │
                                       │  ├─ fleet_status.json         │
                                       │  └─ secrets/  (SA key)        │
                                       └───────────────────────────────┘
```

## What's Included

| Directory | Purpose |
|-----------|---------|
| [`scripts/`](scripts/) | All deployment shell scripts and Python tools |
| [`go-sdk/`](go-sdk/) | Go packages: Vast.ai API client, SSH, config, providers, budget |
| [`docs/`](docs/) | Operational guides, GPU reference, troubleshooting |
| [`examples/`](examples/) | Config templates and workflow examples |

---

## Quick Start

### Option A: Fully Autonomous (Zero Touch after Launch)

Upload assets to GCS once, then every instance bootstraps itself:

```bash
# 1. Upload scripts + prompt files to GCS
gsutil cp scripts/bootstrap_autonomous.sh gs://YOUR_BUCKET/deploy/
gsutil cp scripts/instant_gcs_sync.sh gs://YOUR_BUCKET/deploy/
gsutil -m cp inputs/* gs://YOUR_BUCKET/deploy/images/

# 2. Launch instance — it does everything else
vastai create instance <OFFER_ID> \
  --image pytorch/pytorch:2.5.1-cuda12.4-cudnn9-devel \
  --disk 100 --label "run1-a" \
  --onstart-cmd "wget -q -O /tmp/boot.sh https://storage.googleapis.com/YOUR_BUCKET/deploy/bootstrap_autonomous.sh && bash /tmp/boot.sh run1-a prompts_run1.json >> /tmp/bootstrap.log 2>&1"

# 3. Walk away. Instance will:
#    ✅ Bootstrap itself (~10–15 min)
#    ✅ Render all jobs 
#    ✅ Upload each output to GCS instantly
#    ✅ Auto-kill when queue empties
```

### Option B: Go CLI (`vastctl`)

```bash
cd go-sdk
go build -o vastctl ./cmd/vastctl/

# Search for GPUs
./vastctl -gpu RTX_4090 -price 0.50 search

# Launch with auto-boot-timeout + SSH tunnel
./vastctl -gpu RTX_4090 -price 0.50 -disk 100 -tunnel launch

# List active instances
./vastctl list

# Destroy an instance
./vastctl destroy <INSTANCE_ID>
```

### Option C: Mac-Side Sync (Manual Control)

```bash
# SSH submit → monitor → sync → shutdown
ssh -p <PORT> root@<HOST> 'cd /workspace && python3 submit.py'

# Sync from Mac (polls GPU instance via SSH)
nohup scripts/vast-sync-v4.sh <PORT> <HOST> YOUR_BUCKET 30 <HOST_LABEL> > sync.log 2>&1 &

# Auto-shutdown when done
nohup scripts/auto-shutdown.sh <PORT> <HOST> YOUR_BUCKET <LABEL> <INSTANCE_ID> > shutdown.log 2>&1 &
```

---

## Scripts Reference

| Script | Runs On | Purpose |
|--------|---------|---------|
| [`bootstrap_autonomous.sh`](scripts/bootstrap_autonomous.sh) | GPU instance | Full autonomous pipeline: install → download → submit → sync → kill |
| [`instant_gcs_sync.sh`](scripts/instant_gcs_sync.sh) | GPU instance | inotifywait-based instant upload + drain-safe auto-kill |
| [`vast-sync-v4.sh`](scripts/vast-sync-v4.sh) | Local Mac | SSH-poll sync with metadata + gallery_data.json updates |
| [`auto-shutdown.sh`](scripts/auto-shutdown.sh) | Local Mac | 4-phase: wait → sync → verify → destroy |
| [`ph-autokill.sh`](scripts/ph-autokill.sh) | GPU instance | TTL-based safety guard (12h default, extensible) |
| [`fleet_poll.py`](scripts/fleet_poll.py) | Local Mac | Polls Vast.ai API + GCS, writes fleet_status.json |
| [`gcs-protect.sh`](scripts/gcs-protect.sh) | Local Mac | Apply CORS, lifecycle, logging, billing to GCS bucket |
| [`cf-worker.js`](scripts/cf-worker.js) | Cloudflare | GCS proxy with SPA fallback for static hosting |

---

## Go SDK

A complete Go toolkit for Vast.ai instance management:

| Package | Purpose |
|---------|---------|
| [`vast/`](go-sdk/vast/) | API client — search offers, launch, list, destroy |
| [`ssh/`](go-sdk/ssh/) | SSH client with agent forwarding + port tunneling |
| [`config/`](go-sdk/config/) | YAML config + env override + key file loading |
| [`providers/`](go-sdk/providers/) | Provider-agnostic interface (Vast.ai, RunPod, etc.) |
| [`hwprofile/`](go-sdk/hwprofile/) | Hardware signatures + UCB1 tuning profiles |
| [`storage/`](go-sdk/storage/) | GCS + local storage interface |
| [`budget/`](go-sdk/budget/) | Cost guardrails: daily budget, idle timeout, auto-destroy |

---

## Credentials & Security

All secrets use a layered resolution: **Secret Manager → Environment Variable → Key File**

| Secret | Secret Manager Name | Env Var | Key File |
|--------|-------------------|---------|----------|
| Vast.ai API Key | `vast-api-key` | `VAST_API_KEY` | `~/.config/promptharbor/vast_api_key` |
| HuggingFace Token | `huggingface-token` | `HF_TOKEN` | `~/.config/promptharbor/hf_token` |
| CivitAI API Key | `civitai-api-key` | `CIVITAI_API_KEY` | `~/.config/promptharbor/civitai_api_key` |
| GCP SA Key | — | `GOOGLE_APPLICATION_CREDENTIALS` | `~/.config/promptharbor/gcp-sa-key.json` |

**Security Rules:**
1. NEVER hardcode secrets in scripts or committed files
2. NEVER pass secrets as CLI arguments (visible in `ps`)
3. NEVER log secret values — log "present (redacted)" only
4. ALWAYS use `fetch_secret()` in bootstrap scripts
5. GCS SA key: `ph-vast-uploader@<PROJECT>.iam.gserviceaccount.com`

---

## GPU Cost Analysis

| GPU | $/hr | Time/Video (480p, 241 frames, 4 steps) | $/Video |
|-----|------|---------------------------------------|---------|
| RTX 3090 | $0.11–0.18 | ~9–15 min | $0.016–0.04 |
| RTX 4090 | $0.27–0.40 | ~5–7 min | $0.023–0.05 |
| A100 80GB | $0.78 | ~5 min (720p, 301 frames, 6 steps) | $0.065 |

**Strategy:** RTX 3090 for bulk parallel renders (best $/video), RTX 4090 for iteration/testing.

---

## GCS Bucket Layout

```
gs://YOUR_BUCKET/
├── deploy/
│   ├── bootstrap_autonomous.sh
│   ├── instant_gcs_sync.sh
│   ├── submit_from_prompts_v2.py
│   ├── workflow.json
│   ├── prompts_*.json
│   └── images/
│       ├── batch1/
│       └── batch2/
├── secrets/
│   └── gcs-uploader-key.json
├── fleet_status.json
├── gallery_data.json
└── outputs/
    ├── <host-label-a>/
    ├── <host-label-b>/
    └── <host-label-c>/
```

---

## Instance Management

### Vast.ai CLI
```bash
VASTAI=~/Library/Python/3.14/bin/vastai

# Search: ≥24GB VRAM, ≥100GB disk, ≥95% reliability
$VASTAI search offers \
  'gpu_name=RTX_4090 num_gpus=1 disk_space>=100 dph<0.40 reliability>=0.95 inet_down>=500' \
  -o 'dph' --limit 10

# Launch (ALWAYS ≥100GB disk)
$VASTAI create instance OFFER_ID \
  --image pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime \
  --disk 100 --ssh --direct

# Check / Destroy
$VASTAI show instances
$VASTAI destroy instance INSTANCE_ID
```

### Race-Launch Strategy
Vast instances are unreliable. Launch 3 on DIFFERENT machines, keep the best:

| Status | Duration | Action |
|--------|----------|--------|
| `loading` | < 3 min | Normal, wait |
| `loading` | > 5 min | Junk — destroy |
| `running` + SSH refused | < 1 min | Normal, SSH booting |
| `running` + SSH refused | > 2 min | Broken — destroy |

### Monitoring
```bash
# Quick status across all hosts
for spec in "ssh2.vast.ai:37012:4090-a" "ssh4.vast.ai:11406:3090-e"; do
  host=$(echo $spec | cut -d: -f1)
  port=$(echo $spec | cut -d: -f2)
  label=$(echo $spec | cut -d: -f3)
  timeout 10 ssh -o ConnectTimeout=3 -p $port root@$host \
    'gpu=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
     echo "'$label': GPU=$gpu, Queue=$(python3 -c "import urllib.request,json; q=json.loads(urllib.request.urlopen(\"http://localhost:8188/queue\").read()); print(len(q.get(\"queue_pending\",[])))" 2>/dev/null) pending"' 2>/dev/null
done
```

---

## Host Label Convention

| Pattern | Meaning |
|---------|---------|
| `4090-a` | First RTX 4090 instance |
| `3090-b` | Second overall, RTX 3090 |
| `run3-a` | Third deployment run, host A |
| `a100-x` | A100 instance |

Labels are embedded in `gallery_data.json` and shown in GCS output paths.

---

## File Deletion Safety

When deleting files from GCS, always:

1. **Delete from instance local output FIRST**
2. **THEN delete from GCS**

Otherwise the sync script re-uploads the local copy.

```bash
# 1. Delete local first
ssh -p <PORT> root@<HOST> 'rm -f /workspace/output/<filename>.*'
# 2. Then GCS
gsutil rm gs://BUCKET/outputs/<HOST>/<filename>.*
```

---

## License

This deploy kit is extracted for reuse in other projects. Adapt bucket names, project IDs, and paths as needed.
