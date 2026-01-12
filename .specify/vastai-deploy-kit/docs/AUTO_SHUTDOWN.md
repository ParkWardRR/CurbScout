# Auto-Shutdown Script — Usage Guide

**Script**: `scripts/auto-shutdown.sh`
**Purpose**: Monitors processing queue, syncs all outputs to GCS, verifies uploads, then destroys the Vast.ai instance automatically.

---

## Overview

The auto-shutdown script runs **on your Mac** (not on the instance) and performs 4 phases:

```
Phase 1: Wait for processing queue to drain (polling)
Phase 2: Sync ALL outputs to GCS (download + upload + metadata)
Phase 3: Verify every file made it to GCS (with re-sync retries)
Phase 4: Destroy the Vast.ai instance via API
```

This ensures you never pay for idle instances and never lose outputs.

---

## Quick Start

```bash
# Basic usage:
./scripts/auto-shutdown.sh <SSH_PORT> <SSH_HOST> <GCS_BUCKET> <HOST_LABEL> <VAST_INSTANCE_ID>

# Example:
./scripts/auto-shutdown.sh 37012 ssh2.vast.ai my-bucket 3090-g 31660001

# Run in background:
nohup ./scripts/auto-shutdown.sh 37012 ssh2.vast.ai my-bucket 3090-g 31660001 \
  > auto-shutdown-3090g.log 2>&1 &
echo "Auto-shutdown PID: $!"
```

---

## Arguments

| # | Argument | Required | Default | Description |
|---|----------|----------|---------|-------------|
| 1 | `SSH_PORT` | ✅ | — | SSH port for the Vast.ai instance |
| 2 | `SSH_HOST` | ✅ | — | SSH host (e.g., `ssh2.vast.ai`) |
| 3 | `GCS_BUCKET` | ✅ | — | GCS bucket name |
| 4 | `HOST_LABEL` | ✅ | — | Human-readable label (e.g., `3090-g`) |
| 5 | `VAST_INSTANCE_ID` | ✅ | — | Vast.ai instance ID |
| 6 | `VAST_API_KEY` | ❌ | Auto from `~/.config/promptharbor/vast_api_key` | API key override |

---

## Environment Variable Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `POLL_INTERVAL` | `15` | Seconds between queue checks |
| `QUEUE_EMPTY_THRESHOLD` | `3` | Queue must be empty for N consecutive checks |
| `GRACE_PERIOD` | `30` | Seconds to wait after queue empties for final writes |
| `VERIFY_RETRIES` | `3` | Number of GCS verification attempts |

### Example with custom timing:

```bash
# Conservative
POLL_INTERVAL=10 QUEUE_EMPTY_THRESHOLD=5 GRACE_PERIOD=60 VERIFY_RETRIES=5 \
  nohup ./scripts/auto-shutdown.sh 37012 ssh2.vast.ai bucket 3090-g 31660001 \
  > auto-shutdown.log 2>&1 &

# Aggressive (quick test runs)
POLL_INTERVAL=5 QUEUE_EMPTY_THRESHOLD=2 GRACE_PERIOD=10 \
  nohup ./scripts/auto-shutdown.sh 37012 ssh2.vast.ai bucket 3090-g 31660001 \
  > auto-shutdown.log 2>&1 &
```

---

## The 4 Phases

### Phase 1: Wait for Queue to Drain
- Polls `http://localhost:8188/queue` on the instance every `POLL_INTERVAL` seconds
- Checks both running and pending queues
- Queue must be empty for N consecutive checks (prevents false positives)
- Waits `GRACE_PERIOD` after confirmation for final file writes

### Phase 2: Sync All Outputs
- Downloads `gallery_data.json` from GCS
- Probes GPU info via `nvidia-smi`
- Downloads each output file from the instance over SSH
- Uploads to `gs://BUCKET/outputs/<HOST_LABEL>/`
- Sets public-read ACL
- Updates `gallery_data.json` with metadata

### Phase 3: Verify GCS Uploads
- Lists all files on remote host vs GCS
- If files missing, attempts re-sync
- Retries up to `VERIFY_RETRIES` times

### Phase 4: Destroy Instance
- Only proceeds if verification passed
- Calls Vast.ai API to destroy
- If verification failed, does NOT destroy (prevents data loss)

---

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| "Could not reach API" repeating | Instance crashed | SSH in and check logs |
| Phase 2 "Download failed" | Disk full or SSH issue | Check disk: `ssh -p PORT root@HOST 'df -h'` |
| Phase 3 verification fails | GCS upload issue | Script retries. Check GCS auth if persists |
| Phase 4 "Could not destroy" | API key expired | Destroy manually via console |
| Script hangs | SSH stalled | Check `ConnectTimeout` (default 10s) |
| "Queue empty" too early | Between-job gap | Increase `QUEUE_EMPTY_THRESHOLD` to 5+ |

### Manual Destruction
```bash
curl -X DELETE -H "Authorization: Bearer $(cat ~/.config/promptharbor/vast_api_key)" \
  "https://console.vast.ai/api/v0/instances/<ID>/"
```
