# GPU Integration Guide — End-to-End

> How to integrate GPU instances so all outputs flow through GCS automatically.

---

## Architecture

```
┌──────────────────────┐          ┌────────────────────────┐
│   Vast.ai GPU        │          │  GCS Bucket            │
│   Instance           │  ──────► │                        │
│                      │  upload  │  outputs/<HOST>/       │
│   Processing server  │          │  gallery_data.json     │
│   generates outputs  │          │  fleet_status.json     │
│                      │          │                        │
└──────────────────────┘          └───────────┬────────────┘
                                              │ read
                                  ┌───────────▼────────────┐
                                  │  Your Application      │
                                  │  (reads from GCS)      │
                                  └────────────────────────┘
```

## Quick Start (Full Autonomous)

Single command from your laptop:

```bash
ssh -o StrictHostKeyChecking=no -p <SSH_PORT> root@<SSH_HOST> \
  'wget -q -O /tmp/boot.sh https://storage.googleapis.com/BUCKET/deploy/bootstrap_autonomous.sh && bash /tmp/boot.sh <HOST_LABEL> <PROMPTS_FILE>'
```

This does everything:
1. ✅ Installs processing pipeline + deps
2. ✅ Downloads models
3. ✅ Downloads workflow + prompts + input images from GCS
4. ✅ Starts processing server
5. ✅ Submits all jobs
6. ✅ Starts instant GCS sync
7. ✅ Auto-kills instance when queue empty

---

## File Naming Convention

Output files should follow:
```
<prefix>_<job-id>_00001.mp4   ← video output
<prefix>_<job-id>_00001.png   ← thumbnail/still
```

## gallery_data.json Format

```json
{
  "outputs": {
    "output_job-123_00001": {
      "prompt": "Description of the job...",
      "workflow": "I2V-NS",
      "host": "3090-k",
      "gpu": "RTX 3090 (24GB)",
      "render_time_sec": 142,
      "seed": 891234567
    }
  },
  "hosts": {
    "3090-k": { "gpu": "RTX 3090", "first_seen": "...", "last_seen": "..." }
  }
}
```

---

## Manual Sync (Laptop to GCS)

If the instance doesn't have `instant_gcs_sync.sh`, sync manually:

```bash
SSH_PORT=39720
SSH_HOST=ssh6.vast.ai
HOST_LABEL=3090-k
GCS_BUCKET=my-bucket

bash scripts/vast-sync-v4.sh $SSH_PORT $SSH_HOST $GCS_BUCKET 30 $HOST_LABEL
```

Or upload files directly:
```bash
gsutil cp output.mp4 gs://BUCKET/outputs/3090-k/output_job1_00001.mp4
```

---

## Deploying Instant Sync to a Running Instance

```bash
ssh -p <PORT> root@<HOST> 'wget -q -O /workspace/instant_gcs_sync.sh \
  https://storage.googleapis.com/BUCKET/deploy/instant_gcs_sync.sh && \
  chmod +x /workspace/instant_gcs_sync.sh && \
  nohup bash /workspace/instant_gcs_sync.sh <HOST_LABEL> <VAST_API_KEY> >> /tmp/sync.log 2>&1 &'
```

---

## Monitoring

### From GPU Instance
```bash
tail -f /tmp/sync.log       # File uploads
tail -f /tmp/processing.log # Processing status
tail -f /tmp/bootstrap.log  # Bootstrap status
```

### Check sync status
```bash
ssh -p <PORT> root@<HOST> 'wc -l /tmp/synced_files.txt'
```

### From GCS
```bash
# Count outputs per host
gsutil ls 'gs://BUCKET/outputs/3090-k/*.mp4' | wc -l

# All outputs
gsutil ls 'gs://BUCKET/outputs/**/*.mp4' | wc -l
```

---

## Infrastructure Cost

| Component | Monthly Cost |
|-----------|-------------|
| GCS static hosting | ~$0.02 |
| GCS storage (~500MB) | ~$0.01 |
| Trash auto-cleanup (30 days) | $0 |
| **Total** | **~$0.03/mo** |

GPU costs are additional and per-instance. See GPU_GUIDE.md.
