#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# provision_vast.sh — Vast.ai GPU Instance Provisioning
# ═══════════════════════════════════════════════════════════════
#
# Usage: scp this to the instance, then run via SSH:
#   scp -P <PORT> provision_vast.sh root@<HOST>:/tmp/
#   ssh -p <PORT> root@<HOST> 'bash /tmp/provision_vast.sh'
#
# OR pipe directly:
#   ssh -p <PORT> root@<HOST> 'bash -s' < provision_vast.sh
#
# What it does:
#   1. Installs system deps (git, wget, ffmpeg)
#   2. Clones ComfyUI (if not present)
#   3. Installs VHS custom node with opencv-headless fix
#   4. Downloads WAN 2.1 14B models (parallel)
#   5. Starts ComfyUI on port 8188
#
# CRITICAL LEARNINGS (do not modify without understanding):
#   - opencv-python-headless is REQUIRED (not opencv-python)
#     Docker containers lack libxcb.so.1 GUI deps
#   - Model downloads run in parallel to save 5-10 minutes
#   - ComfyUI must listen on 0.0.0.0 for SSH tunnel access
#   - /workspace is persistent storage on Vast.ai
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

COMFYUI_DIR="/workspace/ComfyUI"
LOG_FILE="/tmp/provision.log"

log() { echo "$(date +%H:%M:%S) $1" | tee -a "$LOG_FILE"; }

log "🚀 Provisioning Vast.ai instance..."
log "   GPU: $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo 'unknown')"
log "   Disk: $(df -h /workspace 2>/dev/null | tail -1 | awk '{print $4 " free"}' || echo 'unknown')"

# ─── 0. Hardware Signature Probe ──────────────────────────────
log "🔍 Probing hardware signature..."
HW_GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | xargs || echo "unknown")
HW_GPU_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs || echo "0")
HW_CUDA_VER=$(nvcc --version 2>/dev/null | grep "release" | awk '{print $5}' | tr -d ',' || nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "")
HW_DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | xargs || echo "")
HW_CPU_GHZ=$(lscpu 2>/dev/null | grep "CPU max MHz" | awk '{printf "%.1f", $4/1000}' || echo "0")
HW_HAS_AVX=$(grep -q avx /proc/cpuinfo 2>/dev/null && echo "true" || echo "false")
HW_PCIE_GEN=$(lspci -vv 2>/dev/null | grep -A 20 "NVIDIA" | grep "LnkSta:" | head -1 | grep -oP 'Speed \K[^,]+' | grep -oP '\d+' || echo "0")
HW_INET_UP="${VAST_INET_UP:-0}"
HW_INET_DOWN="${VAST_INET_DOWN:-0}"
HW_DISK_BW=$(dd if=/dev/zero of=/tmp/diskbench bs=1M count=256 oflag=direct 2>&1 | tail -1 | grep -oP '[\d.]+ [MG]B/s' || echo "0 MB/s")
rm -f /tmp/diskbench

# Export as JSON for agent to report to controller
export HW_SIGNATURE=$(cat <<HWEOF
{"gpu_name":"$HW_GPU_NAME","gpu_vram_mb":${HW_GPU_VRAM:-0},"cuda_version":"$HW_CUDA_VER","driver_version":"$HW_DRIVER_VER","cpu_ghz":${HW_CPU_GHZ:-0},"has_avx":$HW_HAS_AVX,"pci_gen":${HW_PCIE_GEN:-0},"inet_up_mbps":${HW_INET_UP:-0},"inet_down_mbps":${HW_INET_DOWN:-0},"disk_bw_mbps":"$HW_DISK_BW"}
HWEOF
)
log "   HW Signature: $HW_SIGNATURE"

# ─── 1. System Dependencies ──────────────────────────────────
log "📦 [1/5] Installing system deps..."
apt-get update -qq
apt-get install -y -qq git wget curl ffmpeg > /dev/null 2>&1
log "  ✅ System deps installed"

# ─── 2. ComfyUI ──────────────────────────────────────────────
log "🎨 [2/5] Setting up ComfyUI..."
if [ ! -d "$COMFYUI_DIR" ]; then
    cd /workspace
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git
    cd ComfyUI
    pip install -r requirements.txt -q 2>&1 | tail -3
    log "  ✅ ComfyUI installed fresh"
else
    log "  ♻️ ComfyUI already exists, updating..."
    cd "$COMFYUI_DIR"
    git pull --ff-only 2>/dev/null || true
fi

# ─── 3. Custom Nodes ─────────────────────────────────────────
log "🔌 [3/5] Installing custom nodes..."

# VideoHelperSuite (VHS) — REQUIRED for MP4 video output
VHS_DIR="$COMFYUI_DIR/custom_nodes/ComfyUI-VideoHelperSuite"
if [ ! -d "$VHS_DIR" ]; then
    cd "$COMFYUI_DIR/custom_nodes"
    git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
    cd ComfyUI-VideoHelperSuite
    pip install -r requirements.txt -q 2>&1 | tail -3
fi

# ╔══════════════════════════════════════════════════════════╗
# ║ CRITICAL FIX: Must use opencv-python-headless            ║
# ║ Docker containers lack libxcb.so.1 (X11 GUI library)    ║
# ║ Without this fix: "Node 'VHS_VideoCombine' not found"   ║
# ╚══════════════════════════════════════════════════════════╝
pip install opencv-python-headless --force-reinstall -q 2>&1 | tail -2
log "  ✅ VHS node installed (with headless opencv fix)"

# ─── 4. Model Downloads ──────────────────────────────────────
log "📥 [4/5] Downloading models (parallel)..."

CKPT_DIR="$COMFYUI_DIR/models/diffusion_models"
CLIP_DIR="$COMFYUI_DIR/models/text_encoders"
VAE_DIR="$COMFYUI_DIR/models/vae"
mkdir -p "$CKPT_DIR" "$CLIP_DIR" "$VAE_DIR"

# WAN 2.1 Text-to-Video 14B FP8 (~14GB)
DIFF_MODEL="wan2.1_t2v_14B_fp8_scaled.safetensors"
if [ ! -f "$CKPT_DIR/$DIFF_MODEL" ]; then
    log "  ⬇ Diffusion model (14B FP8, ~14GB)..."
    wget -q --show-progress -O "$CKPT_DIR/$DIFF_MODEL" \
        "https://huggingface.co/Kijai/WAN2.1_comfy/resolve/main/$DIFF_MODEL" &
    DIFF_PID=$!
else
    log "  ♻️ Diffusion model exists ($(du -h "$CKPT_DIR/$DIFF_MODEL" | cut -f1))"
    DIFF_PID=""
fi

# Text Encoder (UMT5-XXL FP8, ~10GB)
CLIP_MODEL="umt5_xxl_fp8_e4m3fn_scaled.safetensors"
if [ ! -f "$CLIP_DIR/$CLIP_MODEL" ]; then
    log "  ⬇ Text encoder (~10GB)..."
    wget -q --show-progress -O "$CLIP_DIR/$CLIP_MODEL" \
        "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/$CLIP_MODEL" &
    CLIP_PID=$!
else
    log "  ♻️ Text encoder exists"
    CLIP_PID=""
fi

# VAE (~350MB)
VAE_MODEL="wan_2.1_vae.safetensors"
if [ ! -f "$VAE_DIR/$VAE_MODEL" ]; then
    log "  ⬇ VAE (~350MB)..."
    wget -q --show-progress -O "$VAE_DIR/$VAE_MODEL" \
        "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/$VAE_MODEL" &
    VAE_PID=$!
else
    log "  ♻️ VAE exists"
    VAE_PID=""
fi

# Wait for all downloads
[ -n "${DIFF_PID:-}" ] && { wait $DIFF_PID && log "  ✅ Diffusion model done" || log "  ❌ Diffusion download failed!"; }
[ -n "${CLIP_PID:-}" ] && { wait $CLIP_PID && log "  ✅ Text encoder done" || log "  ❌ Text encoder download failed!"; }
[ -n "${VAE_PID:-}" ] && { wait $VAE_PID && log "  ✅ VAE done" || log "  ❌ VAE download failed!"; }

log ""
log "📊 Model sizes:"
du -sh "$CKPT_DIR" "$CLIP_DIR" "$VAE_DIR" 2>/dev/null | while read line; do log "  $line"; done

# ─── 5. Start ComfyUI ────────────────────────────────────────
log ""
log "🎬 [5/5] Starting ComfyUI server..."

# Kill any existing ComfyUI
pkill -f "python main.py" 2>/dev/null || true
sleep 2

cd "$COMFYUI_DIR"
nohup python main.py --listen 0.0.0.0 --port 8188 > /tmp/comfyui.log 2>&1 &
COMFY_PID=$!

log "  ComfyUI PID=$COMFY_PID"
log "  Log: /tmp/comfyui.log"

# Wait for ComfyUI to start (up to 120s)
log "  Waiting for ComfyUI to be ready..."
for i in $(seq 1 24); do
    sleep 5
    if curl -s --max-time 2 http://localhost:8188/system_stats > /dev/null 2>&1; then
        GPU_INFO=$(curl -s http://localhost:8188/system_stats | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['devices'][0]['name'])" 2>/dev/null || echo "unknown")
        log "  ✅ ComfyUI ready! GPU: $GPU_INFO"
        break
    fi
    # Check if process is still alive
    if ! kill -0 $COMFY_PID 2>/dev/null; then
        log "  ❌ ComfyUI process died! Check /tmp/comfyui.log"
        tail -20 /tmp/comfyui.log | while read line; do log "    $line"; done
        exit 1
    fi
    log "  ⏳ Still loading... ($((i*5))s)"
done

# Final verification
if curl -s --max-time 2 http://localhost:8188/system_stats > /dev/null 2>&1; then
    # Check VHS node is loaded
    VHS_CHECK=$(grep -c "IMPORT FAILED.*VideoHelper" /tmp/comfyui.log 2>/dev/null || echo "0")
    if [ "$VHS_CHECK" -gt 0 ]; then
        log "  ⚠️ VHS import FAILED — check opencv-headless fix"
        log "  Run: pip install opencv-python-headless --force-reinstall"
    else
        log "  ✅ VHS node loaded successfully"
    fi



    # ─── 6. Start Agent ──────────────────────────────────────────
    # ─── 6. Start Agent ──────────────────────────────────────────
    if [ -n "${CONTROLLER_URL:-}" ] || [ -n "${BUNDLE_URI:-}" ]; then
        if [ -n "${GCP_KEY_GZ:-}" ]; then
            echo "$GCP_KEY_GZ" | base64 -d | gunzip > /root/gcp-key.json
            export GOOGLE_APPLICATION_CREDENTIALS="/root/gcp-key.json"
            log "   🔑 Decoded GCP Credentials (gzip)"
        elif [ -n "${GCP_KEY_B64:-}" ]; then
            echo "$GCP_KEY_B64" | base64 -d > /root/gcp-key.json
            export GOOGLE_APPLICATION_CREDENTIALS="/root/gcp-key.json"
            log "   🔑 Decoded GCP Credentials (base64)"
        fi
        log ""
        log "🤖 [6/6] Starting PromptHarbor Agent..."
        
        # Download Agent
        curl -s -L -o /usr/local/bin/ph-agent "https://storage.googleapis.com/ph-assets-2026/agent"
        chmod +x /usr/local/bin/ph-agent
        
        # Build args
        if [ -n "${BUNDLE_URI:-}" ]; then
            ARGS="-bundle $BUNDLE_URI -provider vast"
            log "   📦 Bundle Mode: $BUNDLE_URI"
        else
            ARGS="-controller $CONTROLLER_URL -provider vast"
            log "   🤖 Controller Mode: $CONTROLLER_URL"
        fi

        if [ -n "${GCS_BUCKET:-}" ]; then
            ARGS="$ARGS -gcs $GCS_BUCKET"
            log "   GCS Bucket: $GCS_BUCKET"
        fi
        # Pass Google Credentials path if set
        if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
            log "   GCS Creds (Injected): $GOOGLE_APPLICATION_CREDENTIALS"
        fi
        
        # Run Agent
        nohup /usr/local/bin/ph-agent $ARGS > /tmp/agent.log 2>&1 &
        AGENT_PID=$!
        log "   ✅ Agent started (PID=$AGENT_PID)"
        log "   Log: /tmp/agent.log"
    else
        log "ℹ️  Skipping Agent start (No CONTROLLER_URL or BUNDLE_URI)"
    fi

    # ─── 7. Auto-Kill Safety Guard ──────────────────────────────
    log ""
    log "🛡️  [7/7] Installing Auto-Kill Safety Guard..."
    AUTOKILL_TTL="${AUTOKILL_TTL_HOURS:-12}"
    AUTOKILL_GCS="${GCS_BUCKET:-gs://ph-test-2026}/deploy/ph-autokill.sh"
    
    # Try to download from GCS, fall back to inline minimal version
    if gsutil -q cp "$AUTOKILL_GCS" /opt/ph-autokill.sh 2>/dev/null; then
        log "   Downloaded autokill guard from GCS"
    else
        log "   Creating inline autokill guard (GCS download failed)"
        cat > /opt/ph-autokill.sh << 'AKEOF'
#!/bin/bash
# Minimal auto-kill: halt after TTL
BOOT=$(date +%s)
TTL_SECS=$((${AUTOKILL_TTL_HOURS:-12} * 3600))
while true; do
    ELAPSED=$(($(date +%s) - BOOT))
    if [ $ELAPSED -ge $TTL_SECS ]; then
        echo "[$(date -u)] AUTO-KILL: TTL expired after ${AUTOKILL_TTL_HOURS:-12}h"
        curl -s -X POST "${CONTROLLER_URL:-http://34.10.249.4:8080}/api/nodes/heartbeat/$(hostname)" \
            -H "Content-Type: application/json" \
            -d '{"status":"offline","shutdown_reason":"autokill"}' --max-time 5 || true
        sync && poweroff -f || halt -f || true
    fi
    sleep 60
done
AKEOF
    fi
    chmod +x /opt/ph-autokill.sh
    
    # Determine node ID
    AKILL_NODE_ID="${NODE_ID:-vast-$(hostname | tr '.' '-')}"
    export NODE_ID="$AKILL_NODE_ID"
    export GCS_BUCKET="${GCS_BUCKET:-gs://ph-test-2026}"
    
    nohup /opt/ph-autokill.sh \
        --ttl-hours "$AUTOKILL_TTL" \
        --controller-url "${CONTROLLER_URL:-http://34.10.249.4:8080}" \
        --node-id "$AKILL_NODE_ID" \
        > /var/log/ph-autokill.log 2>&1 &
    AKILL_PID=$!
    log "   ✅ Auto-Kill guard active (PID=$AKILL_PID, TTL=${AUTOKILL_TTL}h)"
    log "   Deadline: $(date -d "+${AUTOKILL_TTL} hours" -u '+%Y-%m-%d %H:%M UTC' 2>/dev/null || echo "${AUTOKILL_TTL}h from now")"

    log ""
    log "═══════════════════════════════════════════════════"
    log "✅ PROVISIONING COMPLETE"
    if [ -n "${AGENT_PID:-}" ]; then
        log "   Agent:     ONLINE (PID=$AGENT_PID)"
    fi
    log "   ComfyUI:   http://localhost:8188"
    log "   Auto-Kill: ${AUTOKILL_TTL}h TTL (PID=$AKILL_PID)"
    log "   GPU:       $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null)"
    log "   VRAM:      $(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null)"
    log "═══════════════════════════════════════════════════"

else
    log "❌ ComfyUI failed to start within 120s"
    log "Check: /tmp/comfyui.log"
    exit 1
fi
