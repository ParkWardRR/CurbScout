# Scripts Reference

## Shell Scripts

### `bootstrap_autonomous.sh`
**Runs on:** GPU Instance (onstart)
**Purpose:** Full autonomous pipeline — install, download, submit, sync, kill.

```bash
# Usage (from Vast.ai onstart-cmd):
wget -q -O /tmp/boot.sh https://storage.googleapis.com/BUCKET/deploy/bootstrap_autonomous.sh
bash /tmp/boot.sh <HOST_LABEL> <PROMPTS_FILE>

# Example:
bash /tmp/boot.sh 3090-a prompts_host0.json
```

**What it does:**
1. Installs GPU processing pipeline + custom nodes
2. Installs Python deps (with retry + --no-cache-dir fallback)
3. Downloads model files from HuggingFace (with resume)
4. Downloads workflow + prompts + input images from GCS
5. Runs preflight checks (model size, Python imports, JSON validity)
6. Starts processing server on :8188
7. Submits all jobs
8. Launches `instant_gcs_sync.sh` for real-time upload + auto-kill

---

### `instant_gcs_sync.sh`
**Runs on:** GPU Instance
**Purpose:** Instant file upload via inotifywait + drain-safe auto-kill.

```bash
bash instant_gcs_sync.sh <HOST_LABEL> [VAST_API_KEY]
```

**Features:**
- `inotifywait` triggers on `close_write` (<2s latency)
- Periodic reconciliation every 60s catches missed files
- `.done.json` markers for idempotent verification
- Drain-safe: queue empty 2x → 90s drain → GCS count match → THEN destroy
- Secrets from env, never logged

---

### `vast-sync-v4.sh`
**Runs on:** Local Mac
**Purpose:** SSH-based polling sync with full metadata capture.

```bash
nohup ./vast-sync-v4.sh <PORT> <HOST> <BUCKET> <POLL_SEC> <HOST_LABEL> > sync.log 2>&1 &
```

**Features:**
- SSH polls remote instance for new output files
- Downloads → uploads to GCS with public ACL
- Captures: prompt, workflow, render time, host label, GPU info
- Updates `gallery_data.json` with per-file metadata
- GPU detection with caching (nvidia-smi → lspci fallback)
- Workflow detection from filename convention

---

### `auto-shutdown.sh`
**Runs on:** Local Mac
**Purpose:** 4-phase auto-shutdown: wait → sync → verify → destroy.

```bash
./auto-shutdown.sh <PORT> <HOST> <BUCKET> <LABEL> <INSTANCE_ID> [API_KEY]
```

See [docs/AUTO_SHUTDOWN.md](../docs/AUTO_SHUTDOWN.md) for full guide.

---

### `ph-autokill.sh`
**Runs on:** GPU Instance
**Purpose:** TTL-based safety guard (prevents runaway billing).

```bash
/opt/ph-autokill.sh [--ttl-hours 12] [--controller-url URL] [--node-id ID]
```

**Features:**
- Default 12hr TTL from boot
- Max 3 postpone extensions of 2hr each
- Saves final status to GCS before shutdown
- Creates detailed shutdown log
- Nuclear fallback: `poweroff -f`

---

### `gcs-protect.sh`
**Runs on:** Local Mac
**Purpose:** Apply cost protection to GCS buckets.

```bash
./gcs-protect.sh [BUCKET_NAME] [MONTHLY_BUDGET]
```

**What it does:**
1. Applies tight CORS policy
2. Sets lifecycle rules (NEARLINE at 14d, delete at 90d)
3. Enables request logging
4. Recommends API quotas
5. Sets billing budget alert

---

### `cf-worker.js`
**Runs on:** Cloudflare
**Purpose:** GCS proxy with SPA fallback for static hosting.

Deploy to Cloudflare Workers for clean URLs backed by GCS.

---

### `gcs-cors.json`
**Purpose:** CORS configuration for GCS buckets.

```bash
gsutil cors set gcs-cors.json gs://BUCKET
```

---

## Python Scripts

### `fleet_poll.py`
**Runs on:** Local Mac
**Purpose:** Polls Vast.ai API + GCS, writes `fleet_status.json` to GCS.

```bash
python3 fleet_poll.py          # polls forever (15s interval)
python3 fleet_poll.py --once   # single poll (for cron)
```

**Output fields:**
- Instance list (GPU, cost, status, SSH, uptime, location)
- Gallery stats (total videos, by host, by workflow)
- GCS video counts per host directory
- Cost summary (hourly rate, active count)

---

### `test_agent_bootstrap.sh`
**Runs on:** GPU Instance
**Purpose:** Test bootstrap for verifying pipeline without full processing overhead.
Creates minimal test output files to validate upload + data flow.
