#!/bin/bash
# vast-sync-v4.sh — Syncs ComfyUI outputs to GCS with full metadata
# Captures: prompt, workflow, render time, host label, GPU info
set +e

SSH_PORT="${1:-23142}"
SSH_HOST="${2:-ssh3.vast.ai}"
GCS_BUCKET="${3:-ph-test-2026}"
POLL_INTERVAL="${4:-30}"
HOST_LABEL="${5:-$(echo "${SSH_HOST%%.*}-${SSH_PORT}" | sed 's/[^a-zA-Z0-9_-]/-/g')}"

LOCAL_DIR="/tmp/ph-sync-v4"
SYNCED_LOG="${LOCAL_DIR}/.synced"
GALLERY_DATA="${LOCAL_DIR}/gallery_data.json"
GPU_INFO_CACHE="${LOCAL_DIR}/.gpu_info"

mkdir -p "$LOCAL_DIR"
touch "$SYNCED_LOG"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
SSH_CMD="ssh $SSH_OPTS -p $SSH_PORT root@${SSH_HOST}"

# ── Workflow detection from filename ──
detect_workflow() {
  local name="$1"
  case "$name" in
    wan_v7_*)  echo "T2V-DOLLY" ;;
    wan_v6_*)  echo "T2V-PIN" ;;
    wan_v5_*)  echo "T2V-SPLIT" ;;
    wan_v4_*)  echo "T2V-GGUF" ;;
    wan_v3_*)  echo "T2V-LONG" ;;
    wan_v2_*)  echo "T2V-OPT" ;;
    wan_hires_*) echo "T2V-HR" ;;
    wan_pro_*) echo "T2V-PRO" ;;
    wan_nsfw_*) echo "I2V-NS" ;;
    wan_i2v_*) echo "I2V" ;;
    *)         echo "BENCH" ;;
  esac
}

# ── Extract prompt_id from filename ──
extract_prompt_id() {
  local name="$1"
  local stem="${name%.*}"
  stem="${stem%_}"
  echo "$stem" | sed -E 's/_[0-9]{5}$//' | sed -E 's/^wan_(pro|hires|v[0-9]+|i2v|nsfw|output)_//'
}

log "🎬 Vast Sync V4 started"
log "   SSH: root@${SSH_HOST}:${SSH_PORT}"
log "   GCS: gs://${GCS_BUCKET}/outputs/${HOST_LABEL}/"
log "   Host: ${HOST_LABEL}"
log "   Poll: ${POLL_INTERVAL}s"
log ""

# ── Probe GPU info from the remote host (cached after first successful probe) ──
GPU_NAME=""
GPU_VRAM=""

probe_gpu() {
  if [ -f "$GPU_INFO_CACHE" ]; then
    source "$GPU_INFO_CACHE"
    if [ -n "$GPU_NAME" ]; then
      log "🖥  GPU (cached): ${GPU_NAME} (${GPU_VRAM})"
      return
    fi
  fi

  log "🔍 Probing GPU info..."
  local gpu_raw
  gpu_raw=$($SSH_CMD 'nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1' 2>/dev/null)

  if [ -n "$gpu_raw" ]; then
    GPU_NAME=$(echo "$gpu_raw" | cut -d',' -f1 | sed 's/^ *//;s/ *$//')
    GPU_VRAM=$(echo "$gpu_raw" | cut -d',' -f2 | sed 's/^ *//;s/ *$//')
    # Normalize VRAM to GB
    if [ -n "$GPU_VRAM" ] && [ "$GPU_VRAM" -gt 0 ] 2>/dev/null; then
      GPU_VRAM="$((GPU_VRAM / 1024))GB"
    else
      GPU_VRAM=""
    fi
    # Clean up GPU name (remove "NVIDIA" prefix, "GeForce" prefix for brevity)
    GPU_NAME=$(echo "$GPU_NAME" | sed 's/^NVIDIA //;s/^GeForce //')

    echo "GPU_NAME='${GPU_NAME}'" > "$GPU_INFO_CACHE"
    echo "GPU_VRAM='${GPU_VRAM}'" >> "$GPU_INFO_CACHE"
    log "🖥  GPU: ${GPU_NAME} (${GPU_VRAM})"
  else
    log "⚠️  Could not detect GPU (nvidia-smi failed)"
    # Try lspci as fallback
    gpu_raw=$($SSH_CMD 'lspci 2>/dev/null | grep -i "vga\|3d\|display" | head -1' 2>/dev/null)
    if [ -n "$gpu_raw" ]; then
      GPU_NAME=$(echo "$gpu_raw" | sed 's/.*: //' | sed 's/NVIDIA Corporation //' | head -c 40)
      echo "GPU_NAME='${GPU_NAME}'" > "$GPU_INFO_CACHE"
      echo "GPU_VRAM=''" >> "$GPU_INFO_CACHE"
      log "🖥  GPU (lspci): ${GPU_NAME}"
    fi
  fi
}

# ── Download existing gallery_data.json from GCS ──
log "📦 Fetching existing gallery_data.json..."
gsutil -q cp "gs://${GCS_BUCKET}/gallery_data.json" "$GALLERY_DATA" 2>/dev/null || {
  log "   No existing gallery_data.json, creating new one"
  echo '{"generated":"","workflows":{},"outputs":{},"hosts":{}}' > "$GALLERY_DATA"
}

# Probe GPU on startup
probe_gpu

# ── Register this host in gallery_data.json ──
register_host() {
  python3 -c "
import json, sys
from datetime import datetime, timezone
gd_path = '$GALLERY_DATA'
try:
    with open(gd_path) as f:
        gd = json.load(f)
except:
    gd = {}
gd.setdefault('hosts', {})
host_entry = gd['hosts'].get('$HOST_LABEL', {})
host_entry['label'] = '$HOST_LABEL'
host_entry['ssh'] = 'root@${SSH_HOST}:${SSH_PORT}'
if '$GPU_NAME':
    host_entry['gpu'] = '$GPU_NAME'
if '$GPU_VRAM':
    host_entry['vram'] = '$GPU_VRAM'
host_entry['last_seen'] = datetime.now(timezone.utc).isoformat()
gd['hosts']['$HOST_LABEL'] = host_entry
with open(gd_path, 'w') as f:
    json.dump(gd, f, indent=2)
print(f'Registered host: $HOST_LABEL (${GPU_NAME} ${GPU_VRAM})')
" 2>/dev/null
}

register_host

while true; do
  # ── 1. List remote output files ──
  REMOTE_FILES=$($SSH_CMD \
    'find /workspace/ComfyUI/output -maxdepth 1 \( -name "*.mp4" -o -name "*.webp" -o -name "*.png" \) -type f 2>/dev/null' \
    2>/dev/null || echo "")

  if [ -z "$REMOTE_FILES" ]; then
    log "⏳ No files found, waiting..."
    sleep "$POLL_INTERVAL"
    continue
  fi

  # ── 2. Fetch ComfyUI history ──
  HISTORY_JSON=$($SSH_CMD \
    'curl -sf http://localhost:8188/history' 2>/dev/null || echo "{}")

  # ── 3. Fetch prompt_queue JSON files ──
  PROMPT_QUEUES_JSON=$($SSH_CMD \
    'python3 -c "
import json, glob, sys
all_prompts = {}
for f in sorted(glob.glob(\"/tmp/prompt_queue*.json\")):
    try:
        data = json.load(open(f))
        for p in data.get(\"prompts\", []):
            pid = p.get(\"id\", \"\")
            if pid:
                all_prompts[pid] = {\"prompt\": p.get(\"prompt\",\"\"), \"seed\": p.get(\"seed\")}
    except: pass
json.dump(all_prompts, sys.stdout)
" 2>/dev/null' 2>/dev/null || echo "{}")

  NEW_COUNT=0

  while IFS= read -r rfile; do
    [ -z "$rfile" ] && continue
    HASH=$(echo "$rfile" | md5sum | cut -d' ' -f1)
    if grep -q "$HASH" "$SYNCED_LOG" 2>/dev/null; then continue; fi

    BASENAME=$(basename "$rfile")
    LOCAL_PATH="${LOCAL_DIR}/${BASENAME}"

    log "📥 Downloading: $BASENAME"
    scp -o StrictHostKeyChecking=no -P "$SSH_PORT" "root@${SSH_HOST}:${rfile}" "$LOCAL_PATH" >/dev/null 2>&1 || continue

    # ── Upload to GCS ──
    log "☁️  Uploading to GCS: outputs/${HOST_LABEL}/${BASENAME}"
    gsutil -q cp "$LOCAL_PATH" "gs://${GCS_BUCKET}/outputs/${HOST_LABEL}/${BASENAME}" || {
      log "❌ Upload failed"
      continue
    }
    gsutil -q acl ch -u AllUsers:R "gs://${GCS_BUCKET}/outputs/${HOST_LABEL}/${BASENAME}" 2>/dev/null

    # ── Extract metadata ──
    WORKFLOW=$(detect_workflow "$BASENAME")
    PROMPT_ID=$(extract_prompt_id "$BASENAME")
    STEM="${BASENAME%.*}"
    STEM="${STEM%_}"

    META_JSON=$(python3 -c "
import json, sys
basename = '$BASENAME'
stem = '$STEM'
prompt_id = '$PROMPT_ID'
workflow = '$WORKFLOW'

prompt_text = None
seed = None
try:
    queues = json.loads('''$PROMPT_QUEUES_JSON''')
    if prompt_id in queues:
        prompt_text = queues[prompt_id].get('prompt')
        seed = queues[prompt_id].get('seed')
except: pass

render_time = None
try:
    history = json.loads('''$HISTORY_JSON''')
    for pid, data in history.items():
        outputs = data.get('outputs', {})
        found = False
        for nid, out in outputs.items():
            for key in ['images', 'gifs', 'videos']:
                for item in out.get(key, []):
                    if item.get('filename') == basename:
                        found = True
                        status = data.get('status', {})
                        msgs = status.get('messages', [])
                        t_start = t_end = None
                        for msg in msgs:
                            if msg[0] == 'execution_start':
                                t_start = msg[1].get('timestamp', 0)
                            elif msg[0] == 'execution_success':
                                t_end = msg[1].get('timestamp', 0)
                        if t_start and t_end:
                            render_time = round((t_end - t_start) / 1000.0, 1)
                        if not prompt_text:
                            prompt_data = data.get('prompt', [None, None])[1] if data.get('prompt') else None
                            if prompt_data:
                                for node_id, node in prompt_data.items():
                                    ct = node.get('class_type', '')
                                    if 'CLIPTextEncode' in ct or 'TextInput' in ct:
                                        txt = node.get('inputs', {}).get('text', '')
                                        if txt and len(txt) > 20:
                                            prompt_text = txt
                                            break
                        break
            if found: break
        if found: break
except: pass

result = {'workflow': workflow, 'prompt_id': prompt_id if prompt_id else None, 'prompt': prompt_text, 'seed': seed, 'render_time_sec': render_time, 'host': '$HOST_LABEL'}
json.dump(result, sys.stdout)
" 2>/dev/null)

    if [ -z "$META_JSON" ]; then
      META_JSON="{\"workflow\":\"$WORKFLOW\",\"prompt_id\":\"$PROMPT_ID\",\"prompt\":null,\"seed\":null,\"host\":\"$HOST_LABEL\"}"
    fi

    # ── Update gallery_data.json ──
    python3 -c "
import json, sys
from datetime import datetime, timezone

gd_path = '$GALLERY_DATA'
stem = '$STEM'

try:
    with open(gd_path) as f:
        gd = json.load(f)
except:
    gd = {'generated':'','workflows':{},'outputs':{},'hosts':{}}

meta = json.loads('''$META_JSON''')
gd['outputs'][stem] = meta
gd['generated'] = datetime.now(timezone.utc).isoformat()

# Update host last_seen timestamp
gd.setdefault('hosts', {})
if '$HOST_LABEL' in gd['hosts']:
    gd['hosts']['$HOST_LABEL']['last_seen'] = datetime.now(timezone.utc).isoformat()

with open(gd_path, 'w') as f:
    json.dump(gd, f, indent=2)
print(f'Updated gallery_data.json: {stem} -> {meta.get(\"workflow\",\"?\")}')
" 2>/dev/null

    echo "$HASH" >> "$SYNCED_LOG"
    rm -f "$LOCAL_PATH"
    NEW_COUNT=$((NEW_COUNT + 1))

    log "✅ Synced: $BASENAME (${WORKFLOW}, prompt_id=${PROMPT_ID:-none})"
  done <<< "$REMOTE_FILES"

  # ── Upload gallery_data.json if new files were synced ──
  if [ "$NEW_COUNT" -gt 0 ]; then
    log "📤 Uploading updated gallery_data.json (${NEW_COUNT} new files)"
    gsutil -q -h "Content-Type:application/json" -h "Cache-Control:no-cache,max-age=0" \
      cp "$GALLERY_DATA" "gs://${GCS_BUCKET}/gallery_data.json"
    gsutil -q acl ch -u AllUsers:R "gs://${GCS_BUCKET}/gallery_data.json" 2>/dev/null
    log "✅ gallery_data.json updated on GCS"
  fi

  sleep "$POLL_INTERVAL"
done
