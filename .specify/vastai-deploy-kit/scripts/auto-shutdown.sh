#!/bin/bash
# auto-shutdown.sh — Monitors ComfyUI queue, syncs outputs, then destroys the instance
# 
# PURPOSE: Run this AFTER submitting all jobs. It will:
#   1. Wait for ComfyUI queue to drain completely
#   2. Wait a grace period for final file writes
#   3. Run the sync loop to upload ALL outputs to GCS
#   4. Verify every file made it to GCS
#   5. Destroy the Vast.ai instance via API
#
# USAGE (run from your Mac, NOT on the instance):
#   ./deploy/auto-shutdown.sh <SSH_PORT> <SSH_HOST> <GCS_BUCKET> <HOST_LABEL> <VAST_INSTANCE_ID>
#
# EXAMPLE:
#   ./deploy/auto-shutdown.sh 37012 ssh2.vast.ai ph-test-2026 test-3060 31652717
#
set +e

SSH_PORT="${1:?Usage: auto-shutdown.sh <PORT> <HOST> <BUCKET> <LABEL> <INSTANCE_ID>}"
SSH_HOST="${2:?Missing SSH_HOST}"
GCS_BUCKET="${3:?Missing GCS_BUCKET}"
HOST_LABEL="${4:?Missing HOST_LABEL}"
VAST_INSTANCE_ID="${5:?Missing VAST_INSTANCE_ID}"
VAST_API_KEY="${6:-$(cat "$HOME/.config/promptharbor/vast_api_key" 2>/dev/null)}"

POLL_INTERVAL="${POLL_INTERVAL:-15}"
QUEUE_EMPTY_THRESHOLD="${QUEUE_EMPTY_THRESHOLD:-3}"   # Queue must be empty for this many consecutive checks
GRACE_PERIOD="${GRACE_PERIOD:-30}"                     # Seconds to wait after queue empties for file writes
VERIFY_RETRIES="${VERIFY_RETRIES:-3}"                  # Number of GCS verification attempts

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
SSH_CMD="ssh $SSH_OPTS -p $SSH_PORT root@${SSH_HOST}"

LOCAL_DIR="/tmp/ph-auto-shutdown-${HOST_LABEL}"
SYNCED_LOG="${LOCAL_DIR}/.synced"
GALLERY_DATA="${LOCAL_DIR}/gallery_data.json"

mkdir -p "$LOCAL_DIR"
touch "$SYNCED_LOG"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
err() { echo "[$(date '+%H:%M:%S')] ❌ $*" >&2; }

log "🚀 Auto-Shutdown Monitor Started"
log "   Instance: ${VAST_INSTANCE_ID}"
log "   SSH:      root@${SSH_HOST}:${SSH_PORT}"
log "   GCS:      gs://${GCS_BUCKET}/outputs/${HOST_LABEL}/"
log "   Label:    ${HOST_LABEL}"
log ""

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

extract_prompt_id() {
  local name="$1"
  local stem="${name%.*}"
  stem="${stem%_}"
  echo "$stem" | sed -E 's/_[0-9]{5}$//' | sed -E 's/^wan_(pro|hires|v[0-9]+|i2v|nsfw|output)_//'
}

# ══════════════════════════════════════════════════════════════════
# PHASE 1: Wait for ComfyUI queue to drain
# ══════════════════════════════════════════════════════════════════
log "═══ PHASE 1: Waiting for ComfyUI queue to drain ═══"

empty_count=0
while true; do
  # Check queue status
  QUEUE_JSON=$($SSH_CMD 'curl -sf http://localhost:8188/queue 2>/dev/null' 2>/dev/null)
  
  if [ -z "$QUEUE_JSON" ]; then
    log "⚠️  Could not reach ComfyUI API, retrying in ${POLL_INTERVAL}s..."
    sleep "$POLL_INTERVAL"
    continue
  fi

  # Parse queue: running + pending
  QUEUE_STATUS=$(python3 -c "
import json, sys
try:
    q = json.loads('''$QUEUE_JSON''')
    running = len(q.get('queue_running', []))
    pending = len(q.get('queue_pending', []))
    print(f'{running} {pending}')
except:
    print('? ?')
" 2>/dev/null)

  RUNNING=$(echo "$QUEUE_STATUS" | cut -d' ' -f1)
  PENDING=$(echo "$QUEUE_STATUS" | cut -d' ' -f2)

  if [ "$RUNNING" = "0" ] && [ "$PENDING" = "0" ]; then
    empty_count=$((empty_count + 1))
    log "✅ Queue empty (${empty_count}/${QUEUE_EMPTY_THRESHOLD})"
    if [ "$empty_count" -ge "$QUEUE_EMPTY_THRESHOLD" ]; then
      log "🏁 Queue confirmed empty!"
      break
    fi
  else
    empty_count=0
    log "⏳ Queue: ${RUNNING} running, ${PENDING} pending — waiting..."
  fi

  sleep "$POLL_INTERVAL"
done

# Grace period for final file writes
log "⏳ Grace period: waiting ${GRACE_PERIOD}s for final file writes..."
sleep "$GRACE_PERIOD"

# ══════════════════════════════════════════════════════════════════
# PHASE 2: Sync ALL outputs to GCS
# ══════════════════════════════════════════════════════════════════
log ""
log "═══ PHASE 2: Syncing all outputs to GCS ═══"

# Download gallery_data.json
gsutil -q cp "gs://${GCS_BUCKET}/gallery_data.json" "$GALLERY_DATA" 2>/dev/null || {
  echo '{"generated":"","workflows":{},"outputs":{},"hosts":{}}' > "$GALLERY_DATA"
}

# Probe GPU
GPU_NAME=""
GPU_VRAM=""
gpu_raw=$($SSH_CMD 'nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1' 2>/dev/null)
if [ -n "$gpu_raw" ]; then
  GPU_NAME=$(echo "$gpu_raw" | cut -d',' -f1 | sed 's/^ *//;s/ *$//' | sed 's/^NVIDIA //;s/^GeForce //')
  GPU_VRAM_RAW=$(echo "$gpu_raw" | cut -d',' -f2 | sed 's/^ *//;s/ *$//')
  if [ -n "$GPU_VRAM_RAW" ] && [ "$GPU_VRAM_RAW" -gt 0 ] 2>/dev/null; then
    GPU_VRAM="$((GPU_VRAM_RAW / 1024))GB"
  fi
  log "🖥  GPU: ${GPU_NAME} (${GPU_VRAM})"
fi

# Register host
python3 -c "
import json
from datetime import datetime, timezone
try:
    with open('$GALLERY_DATA') as f:
        gd = json.load(f)
except:
    gd = {}
gd.setdefault('hosts', {})
gd['hosts']['$HOST_LABEL'] = {
    'label': '$HOST_LABEL',
    'gpu': '$GPU_NAME',
    'vram': '$GPU_VRAM',
    'last_seen': datetime.now(timezone.utc).isoformat()
}
with open('$GALLERY_DATA', 'w') as f:
    json.dump(gd, f, indent=2)
" 2>/dev/null

# Fetch ComfyUI history for metadata
HISTORY_JSON=$($SSH_CMD 'curl -sf http://localhost:8188/history' 2>/dev/null || echo "{}")

# Fetch prompt queue data
PROMPT_QUEUES_JSON=$($SSH_CMD 'python3 -c "
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

# List all remote output files
REMOTE_FILES=$($SSH_CMD \
  'find /workspace/ComfyUI/output -maxdepth 1 \( -name "*.mp4" -o -name "*.webp" -o -name "*.png" \) -type f 2>/dev/null' \
  2>/dev/null || echo "")

TOTAL_FILES=$(echo "$REMOTE_FILES" | grep -c '.' 2>/dev/null || echo 0)
SYNCED_COUNT=0
SKIPPED_COUNT=0
FAILED_FILES=""

log "📦 Found ${TOTAL_FILES} output files on remote host"

while IFS= read -r rfile; do
  [ -z "$rfile" ] && continue
  BASENAME=$(basename "$rfile")
  HASH=$(echo "$rfile" | md5sum | cut -d' ' -f1)

  if grep -q "$HASH" "$SYNCED_LOG" 2>/dev/null; then
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi

  LOCAL_PATH="${LOCAL_DIR}/${BASENAME}"

  log "📥 [${SYNCED_COUNT}/${TOTAL_FILES}] Downloading: $BASENAME"
  scp -o StrictHostKeyChecking=no -P "$SSH_PORT" "root@${SSH_HOST}:${rfile}" "$LOCAL_PATH" >/dev/null 2>&1 || {
    err "Download failed: $BASENAME"
    FAILED_FILES="${FAILED_FILES}${BASENAME}\n"
    continue
  }

  # Upload to GCS
  gsutil -q cp "$LOCAL_PATH" "gs://${GCS_BUCKET}/outputs/${HOST_LABEL}/${BASENAME}" || {
    err "Upload failed: $BASENAME"
    FAILED_FILES="${FAILED_FILES}${BASENAME}\n"
    continue
  }
  gsutil -q acl ch -u AllUsers:R "gs://${GCS_BUCKET}/outputs/${HOST_LABEL}/${BASENAME}" 2>/dev/null

  # Extract metadata
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

  # Update gallery_data.json
  python3 -c "
import json
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
gd.setdefault('hosts', {})
if '$HOST_LABEL' in gd['hosts']:
    gd['hosts']['$HOST_LABEL']['last_seen'] = datetime.now(timezone.utc).isoformat()
with open(gd_path, 'w') as f:
    json.dump(gd, f, indent=2)
" 2>/dev/null

  echo "$HASH" >> "$SYNCED_LOG"
  rm -f "$LOCAL_PATH"
  SYNCED_COUNT=$((SYNCED_COUNT + 1))
  log "✅ Synced: $BASENAME"
done <<< "$REMOTE_FILES"

# Upload gallery_data.json
if [ "$SYNCED_COUNT" -gt 0 ]; then
  gsutil -q -h "Content-Type:application/json" -h "Cache-Control:no-cache,max-age=0" \
    cp "$GALLERY_DATA" "gs://${GCS_BUCKET}/gallery_data.json"
  gsutil -q acl ch -u AllUsers:R "gs://${GCS_BUCKET}/gallery_data.json" 2>/dev/null
  log "📤 gallery_data.json updated on GCS"
fi

log ""
log "📊 Sync Results:"
log "   Synced:  ${SYNCED_COUNT}"
log "   Skipped: ${SKIPPED_COUNT} (already synced)"
if [ -n "$FAILED_FILES" ]; then
  log "   Failed:  $(echo -e "$FAILED_FILES" | grep -c '.')"
  log "   Failed files:"
  echo -e "$FAILED_FILES" | while read -r f; do [ -n "$f" ] && log "     - $f"; done
fi

# ══════════════════════════════════════════════════════════════════
# PHASE 3: Verify all files are in GCS
# ══════════════════════════════════════════════════════════════════
log ""
log "═══ PHASE 3: Verifying GCS uploads ═══"

VERIFY_OK=false
for attempt in $(seq 1 $VERIFY_RETRIES); do
  log "🔍 Verification attempt ${attempt}/${VERIFY_RETRIES}..."

  # List what's on the remote host
  REMOTE_LIST=$($SSH_CMD \
    'find /workspace/ComfyUI/output -maxdepth 1 \( -name "*.mp4" -o -name "*.webp" -o -name "*.png" \) -type f -exec basename {} \; 2>/dev/null | sort' \
    2>/dev/null)

  # List what's in GCS
  GCS_LIST=$(gsutil ls "gs://${GCS_BUCKET}/outputs/${HOST_LABEL}/" 2>/dev/null | xargs -I{} basename {} | sort)

  REMOTE_COUNT=$(echo "$REMOTE_LIST" | grep -c '.' 2>/dev/null || echo 0)
  GCS_COUNT=$(echo "$GCS_LIST" | grep -c '.' 2>/dev/null || echo 0)

  log "   Remote: ${REMOTE_COUNT} files"
  log "   GCS:    ${GCS_COUNT} files"

  # Check for missing files
  MISSING=$(comm -23 <(echo "$REMOTE_LIST") <(echo "$GCS_LIST") 2>/dev/null)
  if [ -z "$(echo "$MISSING" | tr -d '[:space:]')" ]; then
    MISSING_COUNT=0
  else
    MISSING_COUNT=$(echo "$MISSING" | wc -l | tr -d ' ')
  fi

  if [ "$MISSING_COUNT" -eq 0 ]; then
    log "✅ All files verified in GCS!"
    VERIFY_OK=true
    break
  else
    log "⚠️  ${MISSING_COUNT} files missing from GCS:"
    echo "$MISSING" | head -5 | while read -r m; do log "     - $m"; done
    if [ "$MISSING_COUNT" -gt 5 ]; then log "     ... and $((MISSING_COUNT - 5)) more"; fi

    # Try to re-sync the missing files
    if [ "$attempt" -lt "$VERIFY_RETRIES" ]; then
      log "🔄 Re-syncing missing files..."
      echo "$MISSING" | while IFS= read -r mfile; do
        [ -z "$mfile" ] && continue
        LOCAL_PATH="${LOCAL_DIR}/${mfile}"
        scp -o StrictHostKeyChecking=no -P "$SSH_PORT" "root@${SSH_HOST}:/workspace/ComfyUI/output/${mfile}" "$LOCAL_PATH" >/dev/null 2>&1 || continue
        gsutil -q cp "$LOCAL_PATH" "gs://${GCS_BUCKET}/outputs/${HOST_LABEL}/${mfile}" || continue
        gsutil -q acl ch -u AllUsers:R "gs://${GCS_BUCKET}/outputs/${HOST_LABEL}/${mfile}" 2>/dev/null
        rm -f "$LOCAL_PATH"
        log "   ✅ Re-synced: $mfile"
      done
    fi
  fi
done

# ══════════════════════════════════════════════════════════════════
# PHASE 4: Destroy the instance
# ══════════════════════════════════════════════════════════════════
log ""
log "═══ PHASE 4: Instance cleanup ═══"

if [ "$VERIFY_OK" = true ]; then
  log "🗑  Destroying instance ${VAST_INSTANCE_ID}..."

  DESTROY_RESULT=$(python3 -c "
import urllib.request, json
key = '$VAST_API_KEY'
url = f'https://console.vast.ai/api/v0/instances/{$VAST_INSTANCE_ID}/?api_key={key}'
req = urllib.request.Request(url, method='DELETE')
try:
    resp = urllib.request.urlopen(req)
    data = json.loads(resp.read())
    print(json.dumps(data))
except Exception as e:
    print(f'ERROR: {e}')
" 2>/dev/null)

  log "   API Response: ${DESTROY_RESULT}"

  if echo "$DESTROY_RESULT" | grep -q "success"; then
    log "✅ Instance ${VAST_INSTANCE_ID} destroyed successfully!"
    log ""
    log "💰 Cost savings: Instance terminated. No more charges."
  else
    err "Could not destroy instance. Destroy manually:"
    err "  python3 -c \"import urllib.request; urllib.request.urlopen(urllib.request.Request('https://console.vast.ai/api/v0/instances/${VAST_INSTANCE_ID}/?api_key=${VAST_API_KEY}', method='DELETE'))\""
  fi
else
  err "❌ VERIFICATION FAILED — Some files are missing from GCS!"
  err "   NOT destroying instance to prevent data loss."
  err "   Please investigate manually, then destroy with:"
  err "   python3 -c \"import urllib.request; urllib.request.urlopen(urllib.request.Request('https://console.vast.ai/api/v0/instances/${VAST_INSTANCE_ID}/?api_key=${VAST_API_KEY}', method='DELETE'))\""
  exit 1
fi

log ""
log "═══ Auto-Shutdown Complete ═══"
log "   Files synced: ${SYNCED_COUNT}"
log "   Instance:     ${VAST_INSTANCE_ID} (destroyed)"
log "   GCS:          gs://${GCS_BUCKET}/outputs/${HOST_LABEL}/"
log "   Gallery:      https://storage.googleapis.com/${GCS_BUCKET}/index.html"
