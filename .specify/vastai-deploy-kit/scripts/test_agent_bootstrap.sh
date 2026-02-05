#!/usr/bin/env bash
###############################################################################
# MINIMAL PH-AGENT TEST BOOTSTRAP
#
# Just downloads ph-agent from GCS and starts it with test data.
# Used to verify Firestore + GCS upload pipeline without ComfyUI overhead.
###############################################################################
set -euo pipefail
LOG="/tmp/bootstrap.log"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== PH-AGENT TEST BOOTSTRAP START ==="

HOST_LABEL="${HOST_LABEL:-test-agent-1}"
GCS_BUCKET="${GCS_BUCKET:-ph-test-2026}"
GCP_PROJECT="${GCP_PROJECT:-promptharbor-ctrl-2026}"
VAST_API_KEY="${VAST_API_KEY:-}"
# The Vast.ai contract ID is in $CONTAINER_ID or we detect it
VAST_INSTANCE_ID="${VAST_INSTANCE_ID:-${CONTAINER_ID:-0}}"
OUTPUT_DIR="/workspace/test-output"

log "Host: ${HOST_LABEL} | Bucket: ${GCS_BUCKET} | Project: ${GCP_PROJECT}"
log "Vast ID: ${VAST_INSTANCE_ID}"

# ── Setup GCP credentials ──────────────────────────────────────────────────────
if [ -n "${GCP_KEY_GZ:-}" ]; then
    log "Decoding GCP key..."
    echo "$GCP_KEY_GZ" | base64 -d | gunzip > /tmp/gcp-sa-key.json
    export GOOGLE_APPLICATION_CREDENTIALS=/tmp/gcp-sa-key.json
    log "✅ GCP credentials written"
fi

# ── Download ph-agent binary from GCS ──────────────────────────────────────────
log "Downloading ph-agent..."
apt-get update -qq && apt-get install -y -qq curl > /dev/null 2>&1 || true

curl -sL "https://storage.googleapis.com/${GCS_BUCKET}/deploy/ph-agent" -o /usr/local/bin/ph-agent
chmod +x /usr/local/bin/ph-agent

# Verify it's a real binary
if file /usr/local/bin/ph-agent | grep -q "ELF"; then
    log "✅ ph-agent downloaded ($(ls -lh /usr/local/bin/ph-agent | awk '{print $5}'))"
else
    log "❌ ph-agent doesn't look like a Linux binary"
    file /usr/local/bin/ph-agent | tee -a "$LOG"
    exit 1
fi

# ── Create test output directory with fake videos ──────────────────────────────
mkdir -p "${OUTPUT_DIR}"
log "Created output dir: ${OUTPUT_DIR}"

# Create a tiny test MP4 (a valid MP4 with a single black frame)
# This lets us test the full upload + Firestore pipeline
python3 -c "
import struct, os

# Minimal MP4 with ftyp + moov + mdat
# This is the smallest technically valid MP4 file
ftyp = b'\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom'
moov = b'\x00\x00\x00\x08moov'
mdat = b'\x00\x00\x00\x08mdat'

for i in range(3):
    name = f'test_i2v_nsfw_output_{i:04d}.mp4'
    with open(os.path.join('${OUTPUT_DIR}', name), 'wb') as f:
        f.write(ftyp + moov + mdat)
    print(f'  Created: {name}')
" 2>&1 | tee -a "$LOG"

# Also create a .png thumbnail for each
for i in 0 1 2; do
    name=$(printf "test_i2v_nsfw_output_%04d.png" $i)
    # Create a minimal 1x1 PNG
    printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' > "${OUTPUT_DIR}/${name}"
    log "  Created: ${name}"
done

log "✅ Test files created (3 mp4 + 3 png)"

# ── Run ph-agent ───────────────────────────────────────────────────────────────
log "Starting ph-agent..."
exec /usr/local/bin/ph-agent \
    --host-label "${HOST_LABEL}" \
    --gcs-bucket "${GCS_BUCKET}" \
    --gcp-project "${GCP_PROJECT}" \
    --vast-instance-id "${VAST_INSTANCE_ID}" \
    --vast-api-key "${VAST_API_KEY}" \
    --output-dir "${OUTPUT_DIR}" \
    --comfyui-url "http://localhost:8188" \
    --gcs-output-path "outputs" \
    --health-port 9090
