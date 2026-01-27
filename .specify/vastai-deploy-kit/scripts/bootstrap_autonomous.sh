#!/usr/bin/env bash
###############################################################################
# AUTONOMOUS VAST.AI BOOTSTRAP v4 — boost-node hardened
#
# Usage:  bash bootstrap_autonomous.sh <HOST_LABEL> <PROMPTS_FILE> [VAST_API_KEY]
# Example: bash bootstrap_autonomous.sh 3090-a prompts_host0.json
#
# All secrets come from env vars or arguments — NEVER hardcoded.
# Downloads are retried with resume. Outputs are idempotent.
# Instance self-destructs only after drain-safe verification.
###############################################################################
set -euo pipefail
IFS=$'\n\t'

# ── ERR trap: log line number on any failure ──────────────────────────────────
trap 'log "ERROR on line ${LINENO} (exit $?)"' ERR

# ── Arguments & config ────────────────────────────────────────────────────────
HOST_LABEL="${1:?Usage: bootstrap_autonomous.sh <HOST_LABEL> <PROMPTS_FILE>}"
PROMPTS_FILE="${2:?Usage: bootstrap_autonomous.sh <HOST_LABEL> <PROMPTS_FILE>}"

GCS_BUCKET="${GCS_BUCKET:-ph-test-2026}"
GCS_BASE="https://storage.googleapis.com/${GCS_BUCKET}"
GCP_PROJECT="${GCP_PROJECT:-promptharbor-ctrl-2026}"
COMFYUI_DIR="/workspace/ComfyUI"
LOG="/tmp/bootstrap.log"
COMFYUI_PID_FILE="/tmp/comfyui.pid"

# Pin versions for reproducibility
OPENCV_VERSION="4.10.0.84"

# ── Logging (secrets-safe — NEVER log key values) ─────────────────────────────
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
fail() { log "FATAL: $*"; exit 1; }

log "=== BOOTSTRAP v3 START ==="
log "Host: ${HOST_LABEL} | Prompts: ${PROMPTS_FILE} | Bucket: ${GCS_BUCKET}"

# ── Fetch secrets from Google Cloud Secret Manager ────────────────────────────
# All API keys live in Secret Manager, never hardcoded.
# Falls back to env vars if gcloud is unavailable (e.g. CI, local dev).
fetch_secret() {
    local name="$1" env_fallback="$2"
    # Try Secret Manager first
    if command -v gcloud &>/dev/null; then
        local val
        val=$(gcloud secrets versions access latest --secret="$name" --project="$GCP_PROJECT" 2>/dev/null) || true
        if [ -n "$val" ]; then
            echo "$val"
            return 0
        fi
    fi
    # Fall back to env var
    echo "${!env_fallback:-}"
}

VAST_API_KEY=$(fetch_secret "vast-api-key" "VAST_API_KEY")
HF_TOKEN=$(fetch_secret "huggingface-token" "HF_TOKEN")
CIVITAI_KEY=$(fetch_secret "civitai-api-key" "CIVITAI_API_KEY")

# Log presence, NEVER values
[ -n "$VAST_API_KEY" ] && log "✅ vast-api-key: loaded" || log "⚠️  vast-api-key: NOT FOUND (auto-kill disabled)"
[ -n "$HF_TOKEN" ]     && log "✅ huggingface-token: loaded" || log "⚠️  huggingface-token: NOT FOUND (gated model downloads may fail)"
[ -n "$CIVITAI_KEY" ]   && log "✅ civitai-api-key: loaded" || log "⚠️  civitai-api-key: NOT FOUND (optional)"

# ── Export PROMPTS_FILE early (before any Python that needs it) ────────────────
export PROMPTS_FILE GCS_BUCKET GCS_BASE HOST_LABEL

###############################################################################
# 1. Install ComfyUI
###############################################################################
if [ ! -d "${COMFYUI_DIR}" ]; then
    log "Installing ComfyUI..."
    cd /workspace
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git
    cd ComfyUI
    pip install -q -r requirements.txt
else
    log "ComfyUI already installed"
fi
cd "${COMFYUI_DIR}"

###############################################################################
# 2. Install ComfyUI-GGUF custom node
###############################################################################
if [ ! -d "${COMFYUI_DIR}/custom_nodes/ComfyUI-GGUF" ]; then
    log "Installing ComfyUI-GGUF..."
    cd "${COMFYUI_DIR}/custom_nodes"
    git clone --depth 1 https://github.com/city96/ComfyUI-GGUF.git
else
    log "ComfyUI-GGUF already installed"
fi
# ALWAYS install gguf (even if dir existed from template)
pip install -q --no-cache-dir gguf 2>/dev/null || pip install -q gguf

###############################################################################
# 3. Install VHS (VideoHelperSuite) + ALL Python deps
#    LESSON LEARNED: Always install deps even if directory exists.
#    Docker templates often pre-clone repos without running pip install.
#    Also, pip sometimes fails silently due to SHA256 hash mismatches on
#    slow/flaky connections — use --no-cache-dir to avoid stale cache.
###############################################################################
if [ ! -d "${COMFYUI_DIR}/custom_nodes/ComfyUI-VideoHelperSuite" ]; then
    log "Installing VideoHelperSuite..."
    cd "${COMFYUI_DIR}/custom_nodes"
    git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
fi

# ALWAYS install VHS deps — retry with --no-cache-dir on failure
log "Installing VHS Python deps..."
pip install -q -r "${COMFYUI_DIR}/custom_nodes/ComfyUI-VideoHelperSuite/requirements.txt" 2>/dev/null \
    || pip install -q --no-cache-dir -r "${COMFYUI_DIR}/custom_nodes/ComfyUI-VideoHelperSuite/requirements.txt" \
    || log "⚠️  VHS requirements.txt install had errors (will verify individually below)"

# EXPLICITLY install imageio (critical for VHS video output)
# This was the #1 cause of boost node failures — VHS requirements.txt
# install can fail silently, leaving imageio uninstalled.
pip install -q --no-cache-dir imageio imageio-ffmpeg 2>/dev/null \
    || pip install -q imageio imageio-ffmpeg

# ALWAYS fix opencv (pytorch docker ships opencv-python which needs X11)
pip uninstall -y opencv-python 2>/dev/null || true
pip install -q "opencv-python-headless==${OPENCV_VERSION}" 2>/dev/null \
    || pip install -q --no-cache-dir opencv-python-headless

# VERIFY all critical Python modules are importable
log "Verifying Python modules..."
for mod in cv2 gguf imageio; do
    if python3 -c "import ${mod}" 2>/dev/null; then
        log "  ✅ ${mod} OK"
    else
        log "  ❌ ${mod} missing — attempting reinstall..."
        pip install -q --no-cache-dir "${mod}" 2>/dev/null || true
        python3 -c "import ${mod}" 2>/dev/null || fail "FATAL: Cannot import ${mod} after reinstall"
        log "  ✅ ${mod} OK (after reinstall)"
    fi
done
log "VHS + all Python deps ready"

###############################################################################
# Helper: wget with retry + resume for large files
###############################################################################
wget_retry() {
    local url="$1" dest="$2" desc="${3:-file}"
    local max_attempts=3
    for attempt in $(seq 1 "$max_attempts"); do
        log "Downloading ${desc} (attempt ${attempt}/${max_attempts})..."
        if wget -q --show-progress --continue -O "$dest" "$url"; then
            return 0
        fi
        log "Download failed, retrying in 10s..."
        sleep 10
    done
    return 1
}

###############################################################################
# 4. Download GGUF model — retry + resume + size verification
###############################################################################
mkdir -p "${COMFYUI_DIR}/models/unet"
MODEL_PATH="${COMFYUI_DIR}/models/unet/wan2.2-i2v-rapid-aio-nsfw-v10-Q5_K.gguf"
MODEL_MIN_BYTES=10000000000  # 10 GB floor (actual ~12 GB)
MODEL_URL="https://huggingface.co/befox/WAN2.2-14B-Rapid-AllInOne-GGUF/resolve/main/v10/wan2.2-i2v-rapid-aio-v10-nsfw-Q5_K.gguf"

verify_file_size() {
    local fpath="$1" min_bytes="$2"
    [ -f "$fpath" ] || return 1
    local fsize
    fsize=$(stat -c%s "$fpath" 2>/dev/null || stat -f%z "$fpath" 2>/dev/null || echo 0)
    [ "$fsize" -gt "$min_bytes" ]
}

if verify_file_size "$MODEL_PATH" "$MODEL_MIN_BYTES"; then
    log "✅ GGUF model present ($(ls -lh "$MODEL_PATH" | awk '{print $5}'))"
else
    # Check alternate location
    ALT="${COMFYUI_DIR}/models/diffusion_models/wan2.2-i2v-rapid-aio-nsfw-v10-Q5_K.gguf"
    if verify_file_size "$ALT" "$MODEL_MIN_BYTES"; then
        ln -sf "$ALT" "$MODEL_PATH"
        log "✅ Symlinked GGUF from diffusion_models"
    else
        rm -f "$MODEL_PATH"
        wget_retry "$MODEL_URL" "$MODEL_PATH" "GGUF model (~12GB)" \
            || fail "GGUF download failed after 3 attempts"
        verify_file_size "$MODEL_PATH" "$MODEL_MIN_BYTES" \
            || fail "GGUF truncated: $(ls -lh "$MODEL_PATH" 2>/dev/null | awk '{print $5}') < 10GB"
        log "✅ GGUF downloaded and verified ($(ls -lh "$MODEL_PATH" | awk '{print $5}'))"
    fi
fi

###############################################################################
# 5. Download other models (CLIP, VAE, CLIPVision) — with retry
###############################################################################
mkdir -p "${COMFYUI_DIR}/models/"{text_encoders,vae,clip_vision,clip}

dl_model() {
    local dest="$1" url="$2" desc="$3"
    if [ -f "$dest" ] && [ "$(stat -c%s "$dest" 2>/dev/null || stat -f%z "$dest" 2>/dev/null || echo 0)" -gt 1000 ]; then
        log "✅ ${desc} present"
    else
        wget_retry "$url" "$dest" "$desc" || fail "Failed to download ${desc}"
        log "✅ ${desc} downloaded"
    fi
}

dl_model "${COMFYUI_DIR}/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
    "UMT5 CLIP"
ln -sf "${COMFYUI_DIR}/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
    "${COMFYUI_DIR}/models/clip/umt5_xxl_fp8_e4m3fn_scaled.safetensors" 2>/dev/null || true

dl_model "${COMFYUI_DIR}/models/vae/wan_2.1_vae.safetensors" \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" \
    "WAN VAE"

dl_model "${COMFYUI_DIR}/models/clip_vision/clip_vision_h.safetensors" \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors" \
    "CLIP Vision H"

###############################################################################
# 6. Download workflow + prompts + submit script from GCS
###############################################################################
log "Downloading workflow assets..."
mkdir -p "${COMFYUI_DIR}/input"
cd "${COMFYUI_DIR}"

wget -q -O workflow_nsfw_i2v.json    "${GCS_BASE}/deploy/workflow_nsfw_i2v.json"    || fail "workflow download failed"
wget -q -O submit_from_prompts.py    "${GCS_BASE}/deploy/submit_from_prompts_v2.py" || fail "submit script download failed"
wget -q -O "input/${PROMPTS_FILE}"   "${GCS_BASE}/deploy/${PROMPTS_FILE}"           || fail "prompts download failed"
log "✅ Workflow assets downloaded"

###############################################################################
# 7. Download input images — uses exported PROMPTS_FILE and GCS_BASE
###############################################################################
log "Downloading input images..."
cd "${COMFYUI_DIR}"
python3 - <<'PYEOF'
import json, urllib.request, os, sys, concurrent.futures

prompts_file = os.environ["PROMPTS_FILE"]      # exported before this block
gcs_base = os.environ["GCS_BASE"]              # exported before this block
image_base = f"{gcs_base}/deploy/images"

prompts = json.load(open(f"input/{prompts_file}"))
total = len(prompts)

def download_img(img_file):
    dest = f"input/{img_file}"
    if os.path.exists(dest) and os.path.getsize(dest) > 100:
        return True
    # Search ALL temp folders — images may be in any of them
    for prefix in ["temp7", "temp8", "temp3", "temp5", "temp6"]:
        url = f"{image_base}/{prefix}/{img_file}"
        try:
            urllib.request.urlretrieve(url, dest)
            if os.path.getsize(dest) > 100:
                return True
        except Exception:
            continue
    print(f"  WARN: Could not download {img_file}", file=sys.stderr)
    return False

with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
    results = list(ex.map(download_img, prompts.keys()))

ok = sum(results)
print(f"  Images: {ok}/{total} downloaded")
if ok == 0:
    sys.exit(1)
PYEOF
log "✅ Input images downloaded"

###############################################################################
# 8. PREFLIGHT CHECKS — hard-fail before wasting GPU time
###############################################################################
log "━━━ PREFLIGHT CHECKS ━━━"
PREFLIGHT_OK=true

# Model size
verify_file_size "$MODEL_PATH" "$MODEL_MIN_BYTES" \
    && log "✅ Model: $(ls -lh "$MODEL_PATH" | awk '{print $5}')" \
    || { log "❌ Model missing or truncated"; PREFLIGHT_OK=false; }

# Python modules (pipe to tee but capture exit code properly)
for mod in "cv2" "gguf" "imageio"; do
    if python3 -c "import ${mod}; v=getattr(${mod},'__version__','ok'); print(f'✅ ${mod}: {v}')" 2>&1 | tee -a "$LOG"; then
        :
    else
        log "❌ ${mod} not importable"
        PREFLIGHT_OK=false
    fi
done

# Workflow + prompts valid JSON
python3 -c "
import json, os, sys
for f in ['workflow_nsfw_i2v.json', 'input/${PROMPTS_FILE}']:
    fp = os.path.join('${COMFYUI_DIR}', f)
    if not os.path.exists(fp):
        print(f'❌ {f} missing'); sys.exit(1)
    json.load(open(fp))
    print(f'✅ {f}: valid JSON')
" 2>&1 | tee -a "$LOG" || PREFLIGHT_OK=false

# Input image count
MISSING_IMAGES=$(python3 -c "
import json, os
p = json.load(open('input/${PROMPTS_FILE}'))
print(sum(1 for k in p if not os.path.exists(f'input/{k}') or os.path.getsize(f'input/{k}') < 100))
" 2>/dev/null || echo "?")
TOTAL_IMAGES=$(python3 -c "
import json
p = json.load(open('input/${PROMPTS_FILE}'))
print(len(p))
" 2>/dev/null || echo "?")
if [ "${MISSING_IMAGES}" = "0" ]; then
    log "✅ All ${TOTAL_IMAGES} input images present"
elif [ "${MISSING_IMAGES}" = "${TOTAL_IMAGES}" ]; then
    log "❌ ALL input images missing — cannot run any jobs"
    PREFLIGHT_OK=false
else
    # Soft-warn: some images missing is OK, those jobs just get skipped
    log "⚠️  ${MISSING_IMAGES}/${TOTAL_IMAGES} input images missing (those jobs will be skipped)"
fi

[ "$PREFLIGHT_OK" = true ] || fail "PREFLIGHT FAILED — fix errors above and re-run"
log "✅ All preflight checks passed"

###############################################################################
# 9. Start ComfyUI — pidfile-based process management
###############################################################################
log "Starting ComfyUI..."

# Kill previous instance by pidfile (narrow, won't hit other python procs)
if [ -f "$COMFYUI_PID_FILE" ]; then
    OLD_PID=$(cat "$COMFYUI_PID_FILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        log "Killing previous ComfyUI (PID ${OLD_PID})..."
        kill "$OLD_PID" 2>/dev/null || true
        sleep 3
        kill -9 "$OLD_PID" 2>/dev/null || true
    fi
fi

cd "${COMFYUI_DIR}"
nohup python main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch > /tmp/comfyui.log 2>&1 &
echo $! > "$COMFYUI_PID_FILE"
log "ComfyUI PID: $(cat "$COMFYUI_PID_FILE")"

# Wait for ready (5 min hard timeout)
log "Waiting for ComfyUI API..."
COMFY_READY=false
for _ in $(seq 1 150); do
    if curl -sf http://localhost:8188/system_stats > /dev/null 2>&1; then
        COMFY_READY=true
        break
    fi
    sleep 2
done
[ "$COMFY_READY" = true ] || fail "ComfyUI never came up — check /tmp/comfyui.log"
log "✅ ComfyUI is ready"

# Verify critical nodes are loaded — ENFORCED, not advisory
NODES_RESULT=$(curl -sf http://localhost:8188/object_info | python3 -c "
import sys, json
info = json.load(sys.stdin)
needed = ['UnetLoaderGGUF', 'WanImageToVideo', 'VHS_VideoCombine', 'CLIPVisionEncode']
missing = [n for n in needed if n not in info]
for n in needed:
    s = '✅' if n in info else '❌ MISSING'
    print(f'  {n}: {s}')
if missing:
    sys.exit(1)
" 2>&1) || fail "Critical nodes missing:\n${NODES_RESULT}"
echo "$NODES_RESULT" | tee -a "$LOG"

###############################################################################
# 10. Submit jobs — idempotent (skips if output already in local dir)
###############################################################################
log "Submitting jobs..."
cd "${COMFYUI_DIR}"
python3 submit_from_prompts.py "input/${PROMPTS_FILE}" 2>&1 | tee -a "$LOG"

###############################################################################
# 11. Install sync deps — detect package manager
###############################################################################
log "Installing sync dependencies..."
pip install -q google-cloud-storage vastai 2>/dev/null || true

# Package manager detection for inotify-tools
if command -v apt-get &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq inotify-tools 2>/dev/null || true
elif command -v yum &>/dev/null; then
    yum install -y -q inotify-tools 2>/dev/null || true
elif command -v apk &>/dev/null; then
    apk add --quiet inotify-tools 2>/dev/null || true
else
    log "⚠️  Unknown package manager — inotify-tools may be missing (will fall back to polling)"
fi

# Verify inotifywait is available
command -v inotifywait &>/dev/null \
    && log "✅ inotifywait available" \
    || log "⚠️  inotifywait missing — sync will use 5s polling fallback"

###############################################################################
# 12. Launch instant sync (inotifywait + periodic reconciliation + drain-safe)
###############################################################################
log "Downloading instant sync script..."
wget -q -O "${COMFYUI_DIR}/instant_gcs_sync.sh" "${GCS_BASE}/deploy/instant_gcs_sync.sh"
chmod +x "${COMFYUI_DIR}/instant_gcs_sync.sh"

# Write expected job count for drain verification
JOB_COUNT=$(python3 -c "import json; print(len(json.load(open('input/${PROMPTS_FILE}'))))" 2>/dev/null || echo 0)
echo "$JOB_COUNT" > /tmp/expected_job_count.txt
log "Expected job count: ${JOB_COUNT}"

log "Launching instant sync (drain-safe)..."
nohup bash "${COMFYUI_DIR}/instant_gcs_sync.sh" "$HOST_LABEL" "$VAST_API_KEY" >> /tmp/sync.log 2>&1 &
log "Sync PID: $!"

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "=== BOOTSTRAP COMPLETE — fully autonomous ==="
log "  Monitor:   tail -f /tmp/bootstrap.log"
log "  ComfyUI:   tail -f /tmp/comfyui.log"
log "  Sync:      tail -f /tmp/sync.log"
log "  PID file:  cat ${COMFYUI_PID_FILE}"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
