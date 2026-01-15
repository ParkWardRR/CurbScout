# Autonomous GPU Deployment Guide

> **Pipeline:** Upload assets to GCS → Launch instance → Walk away → Auto-kill when done

## Overview

This system deploys GPU instances on Vast.ai that are **fully autonomous** — they bootstrap themselves from GCS, run all processing jobs, upload results instantly to GCS, and auto-kill when done. **Zero dependency on local machine after initial `vastai create instance`.**

## Architecture

```
Local Machine (one-time)          Vast.ai Instance (autonomous)
─────────────────────────         ─────────────────────────────
vastai create instance ──────→    onstart-cmd runs bootstrap_autonomous.sh
                                  ├── Install GPU pipeline + dependencies
fleet_poll.py (optional) ◄────   ├── Download models (HuggingFace)
reads live stats from vastai      ├── Download CLIP/VAE support models
writes fleet_status.json          ├── Download prompts + workflow (GCS)
                                  ├── Download input images (ALL folders)
                                  ├── Verify Python deps
                                  ├── Start processing server on :8188
                                  ├── Submit all jobs to processing queue
                                  ├── instant_gcs_sync.sh:
                                  │   ├── inotifywait watches output/
                                  │   ├── Upload to GCS the INSTANT file lands
                                  │   └── Auto-kill instance when queue empty
                                  └── DONE (self-destructs)
```

## Key Components

### `bootstrap_autonomous.sh` (v4)
Master orchestration script. Downloads everything from GCS, sets up the full pipeline, launches the processing server, submits jobs, and starts the sync.

**Key v4 improvements:**
- Always installs VHS deps even if directory exists (Docker template issue)
- Explicit `imageio` + `imageio-ffmpeg` install (was #1 failure cause)
- `--no-cache-dir` retry for pip (SHA256 hash mismatch fix)
- Searches all input folders for images
- Soft-warn on partial missing images (doesn't kill the whole run)
- `opencv-python-headless` always installed (X11 fix)

**Args:** `<HOST_LABEL> <PROMPTS_FILE>`
**Example:** `bash bootstrap_autonomous.sh run3-a prompts_run3_host0.json`

### `instant_gcs_sync.sh` (v3)
Uploads completed outputs to GCS with **zero delay** using `inotifywait`.
Falls back to 5-second polling if inotify unavailable.

**Key features:**
- `inotifywait` triggers on `close_write` — uploads start the instant a file is written
- Uses `google-cloud-storage` Python SDK for fastest upload (no gsutil overhead)
- Auto-kills instance via Vast.ai API when all jobs complete
- Writes `.done.json` marker per output with file integrity data
- Updates `gallery_data.json` in GCS (workflow/host/metadata)

### `fleet_poll.py`
Local Mac script that polls Vast.ai API + GCS and writes combined `fleet_status.json`.

**Usage:** `python3 fleet_poll.py` (runs forever, updates every 15s)

### `ph-autokill.sh`
TTL-based safety guard that auto-kills instances after 12 hours. Configurable extensions.

### GCS Service Account
- **Account:** `ph-vast-uploader@<PROJECT>.iam.gserviceaccount.com`
- **Role:** `storage.objectCreator` on `gs://<BUCKET>`
- **Key:** Stored in `gs://<BUCKET>/secrets/gcs-uploader-key.json`

## Deployment Procedure

### 1. Upload Assets (from local Mac)
```bash
# Upload scripts + prompts to GCS (only needed when files change)
gsutil cp scripts/bootstrap_autonomous.sh gs://BUCKET/deploy/
gsutil cp scripts/instant_gcs_sync.sh gs://BUCKET/deploy/
gsutil cp submit_from_prompts_v2.py gs://BUCKET/deploy/
gsutil cp workflow.json gs://BUCKET/deploy/
gsutil cp prompts_*.json gs://BUCKET/deploy/

# Upload input images BEFORE launching instances
gsutil -m cp inputs/batch1/* gs://BUCKET/deploy/images/batch1/
gsutil -m cp inputs/batch2/* gs://BUCKET/deploy/images/batch2/
```

> **⚠️ CRITICAL:** Always upload images to GCS **before** launching instances.

### 2. Rent Instances
```bash
VAST=~/Library/Python/3.14/bin/vastai

# Search for fast GPUs (>500 Mbps download)
$VAST search offers 'gpu_name=RTX_4090 num_gpus=1 disk_space>=100 inet_down>=500 reliability>=0.95' -o 'dph'

# Launch with onstart bootstrap
$VAST create instance <OFFER_ID> \
  --image pytorch/pytorch:2.5.1-cuda12.4-cudnn9-devel \
  --disk 100 --label "run3-a" \
  --onstart-cmd "wget -q -O /tmp/boot.sh https://storage.googleapis.com/BUCKET/deploy/bootstrap_autonomous.sh && bash /tmp/boot.sh run3-a prompts_run3_host0.json >> /tmp/bootstrap.log 2>&1"
```

> **⚠️ CRITICAL:** Ensure `inet_down >= 500` Mbps for fast bootstrapping.

### 3. Start Fleet Poller (optional)
```bash
python3 scripts/fleet_poll.py    # runs forever, updates GCS every 15s
```

### 4. Walk Away
Instances will:
- Bootstrap themselves (~10–15 min on fast connection)
- Process all jobs
- Upload each output to GCS the instant it's done
- Auto-kill themselves when the queue empties

### 5. Check Progress (optional)
```bash
# Via SSH
ssh -p <PORT> root@<HOST> 'tail -20 /tmp/sync.log'
ssh -p <PORT> root@<HOST> 'tail -5 /tmp/processing.log'
```

## GPU Cost Analysis

| GPU | $/hr | Time/Job (480p, 241 frames) | $/Job |
|-----|------|----------------------------|-------|
| RTX 3090 | $0.11 | ~9 min | $0.016 |
| RTX 4090 | $0.27 | ~5 min | $0.023 |
| A100 80GB | $0.78 | ~5 min | $0.065 |

**Winner: RTX 3090/4090 at $0.016–0.023/job**

## Troubleshooting

### Common Failures

| Problem | Root Cause | Fix |
|---------|-----------|-----|
| `imageio` not importable | VHS requirements.txt install failed silently | Explicit install + verify import (v4 bootstrap) |
| SHA256 hash mismatch | Stale pip cache | `pip install --no-cache-dir` retry |
| Input images missing | Only searched some folders | Search ALL input folders |
| `bash -c` swallows output | Vast.ai API returns empty JSON | Use direct command, no `bash -c` wrapper |
| Slow download (30+ min) | Machine < 50 MB/s bandwidth | Filter `inet_down >= 500` |
| `opencv-python` needs X11 | Docker image ships full opencv | Replace with `opencv-python-headless` |
| Gallery shows "Unknown" | Sync didn't update gallery_data | Run backfill script or redeploy sync |

### Proven Settings
- Resolution: 480×832 (portrait) / 832×480 (landscape)
- Frames: 241 (~10s output)
- Steps: 4
- CFG: 1.0, Shift: 8.0
