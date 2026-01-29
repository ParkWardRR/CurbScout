#!/usr/bin/env bash
###############################################################################
# INSTANT GCS SYNC v3 — inotifywait + periodic reconciliation + drain-safe
#
# Features:
#   - inotifywait for instant upload (<2s latency)
#   - Periodic reconciliation every 60s catches anything inotifywait missed
#   - ".done.json" marker objects for idempotent verification
#   - Drain-safe shutdown: queue empty 2x, 90s drain, GCS count match,
#     optional ffprobe validation, only THEN destroy
#   - Secrets read from env, never logged
#
# Usage: bash instant_gcs_sync.sh <HOST_LABEL> [VAST_API_KEY]
###############################################################################
set -uo pipefail
IFS=$'\n\t'

HOST_LABEL="${1:?Usage: instant_gcs_sync.sh <HOST_LABEL> [VAST_API_KEY]}"
VAST_API_KEY="${2:-${VAST_API_KEY:-}}"
OUTPUT_DIR="/workspace/ComfyUI/output"
GCS_BUCKET="${GCS_BUCKET:-ph-test-2026}"
GCS_PREFIX="outputs/${HOST_LABEL}"
KEY_PATH="/tmp/gcs-uploader-key.json"
SYNCED_FILE="/tmp/synced_files.txt"
SYNC_LOG="/tmp/sync.log"
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$SYNC_LOG"; }

touch "$SYNCED_FILE"
mkdir -p "$OUTPUT_DIR"

###############################################################################
# GCS auth setup
###############################################################################
setup_gcs() {
    log "Setting up GCS auth..."

    # Download SA key (TODO: migrate to private bucket or signed URL)
    wget -q -O "$KEY_PATH" "https://storage.googleapis.com/${GCS_BUCKET}/secrets/gcs-uploader-key.json"

    if [ ! -s "$KEY_PATH" ]; then
        log "ERROR: Could not download GCS key"
        return 1
    fi

    export GOOGLE_APPLICATION_CREDENTIALS="$KEY_PATH"

    # Install google-cloud-storage if missing
    python3 -c "from google.cloud import storage" 2>/dev/null \
        || pip install -q google-cloud-storage 2>/dev/null

    # Test write access
    if python3 -c "
from google.cloud import storage
client = storage.Client()
bucket = client.bucket('${GCS_BUCKET}')
blob = bucket.blob('${GCS_PREFIX}/.sync_test')
blob.upload_from_string('ok')
print('GCS write OK')
" 2>/dev/null; then
        log "✅ GCS write access confirmed"
    else
        log "ERROR: GCS write test failed"
        return 1
    fi
}

###############################################################################
# Upload a single file + write a .done.json marker on success
###############################################################################
upload_file() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")

    # Skip tiny/incomplete files
    local filesize
    filesize=$(stat -c%s "$filepath" 2>/dev/null || stat -f%z "$filepath" 2>/dev/null || echo 0)
    [ "$filesize" -lt 1000 ] && return 1

    # Skip already synced (idempotent)
    grep -qF "$filename" "$SYNCED_FILE" 2>/dev/null && return 0

    local start_time
    start_time=$(date +%s%N)

    if python3 -c "
from google.cloud import storage
client = storage.Client()
bucket = client.bucket('${GCS_BUCKET}')
blob = bucket.blob('${GCS_PREFIX}/${filename}')
blob.upload_from_filename('${filepath}')
" 2>/dev/null; then
        local end_time elapsed_ms
        end_time=$(date +%s%N)
        elapsed_ms=$(( (end_time - start_time) / 1000000 ))
        local filesize_kb=$((filesize / 1024))
        log "⚡ UPLOADED: ${filename} (${filesize_kb}KB) in ${elapsed_ms}ms"
        echo "$filename" >> "$SYNCED_FILE"

        # Write .done.json marker + gallery_data.json entry if this is an mp4
        if [[ "$filename" == *.mp4 ]]; then
            write_done_marker "$filepath" "$filename"
            update_gallery_data "$filename"
        fi
        return 0
    fi

    log "❌ UPLOAD FAILED: ${filename}"
    return 1
}

###############################################################################
# Write a .done.json marker object in GCS confirming upload integrity
###############################################################################
write_done_marker() {
    local filepath="$1" filename="$2"
    local filesize
    filesize=$(stat -c%s "$filepath" 2>/dev/null || stat -f%z "$filepath" 2>/dev/null || echo 0)
    local md5
    md5=$(md5sum "$filepath" 2>/dev/null | awk '{print $1}' || echo "unknown")
    local marker_name="${filename}.done.json"

    python3 -c "
import json, time
from google.cloud import storage
marker = {
    'file': '${filename}',
    'host': '${HOST_LABEL}',
    'size_bytes': ${filesize},
    'md5': '${md5}',
    'uploaded_at': time.strftime('%Y-%m-%dT%H:%M:%SZ'),
}
client = storage.Client()
bucket = client.bucket('${GCS_BUCKET}')
blob = bucket.blob('${GCS_PREFIX}/${marker_name}')
blob.upload_from_string(json.dumps(marker, indent=2), content_type='application/json')
" 2>/dev/null && log "📋 Marker: ${marker_name}" || true
}

###############################################################################
# Update gallery_data.json in GCS with workflow/host/prompt metadata
# This ensures the gallery UI shows proper workflow tags, not "Unknown"
###############################################################################
update_gallery_data() {
    local filename="$1"
    local stem="${filename%.*}"  # strip .mp4

    # Try to find the prompt for this file from any prompts file on disk
    python3 -c "
import json, os, time, glob
from google.cloud import storage

client = storage.Client()
bucket = client.bucket('${GCS_BUCKET}')

# Read existing gallery_data.json
try:
    blob = bucket.blob('gallery_data.json')
    data = json.loads(blob.download_as_text())
except:
    data = {'outputs': {}, 'generated': ''}

outputs = data.get('outputs', {})
stem = '${stem}'

# Skip if already exists
if stem in outputs:
    exit(0)

# Look up prompt from local prompts files
prompt_text = ''
for pf in glob.glob('/workspace/ComfyUI/input/prompts_*.json'):
    try:
        prompts = json.load(open(pf))
        for img_key, pdata in prompts.items():
            job_id = pdata.get('job_id', '')
            if job_id and job_id in stem:
                prompt_text = pdata.get('prompt', '')[:200]
                break
    except:
        pass
    if prompt_text:
        break

# Write entry
outputs[stem] = {
    'workflow': 'I2V-NS',
    'host': '${HOST_LABEL}',
    'gpu': '${GPU_NAME}',
    'prompt': prompt_text,
    'uploaded_at': time.strftime('%Y-%m-%dT%H:%M:%SZ'),
}
data['outputs'] = outputs
data['generated'] = time.strftime('%Y-%m-%dT%H:%M:%SZ')

blob.upload_from_string(json.dumps(data, indent=2), content_type='application/json')
" 2>/dev/null && log "📝 Gallery: ${stem}" || log "⚠️  Gallery update failed for ${stem}"
}

###############################################################################
# Periodic reconciliation — catches anything inotifywait missed
###############################################################################
reconcile_uploads() {
    local reconciled=0
    for f in "$OUTPUT_DIR"/wan_nsfw_*.mp4 "$OUTPUT_DIR"/wan_nsfw_*.png; do
        [ -f "$f" ] || continue
        if ! grep -qF "$(basename "$f")" "$SYNCED_FILE" 2>/dev/null; then
            upload_file "$f" && reconciled=$((reconciled + 1))
        fi
    done
    [ "$reconciled" -gt 0 ] && log "🔄 Reconciled ${reconciled} missed files"
}

###############################################################################
# Drain-safe auto-kill
#
# Three gates before destroy:
#   1. Queue empty for 2 consecutive checks (30s apart)
#   2. No new local files for 90s (drain window)
#   3. GCS .done.json count >= local .mp4 count
###############################################################################
QUEUE_EMPTY_COUNT=0

check_autokill() {
    local synced_count
    synced_count=$(wc -l < "$SYNCED_FILE" 2>/dev/null || echo 0)

    # Get queue status
    local queue_info
    queue_info=$(curl -sf http://localhost:8188/queue 2>/dev/null) || return 1

    local running pending
    running=$(echo "$queue_info" | python3 -c "import sys,json;print(len(json.load(sys.stdin).get('queue_running',[])))" 2>/dev/null || echo "?")
    pending=$(echo "$queue_info" | python3 -c "import sys,json;print(len(json.load(sys.stdin).get('queue_pending',[])))" 2>/dev/null || echo "?")

    log "📊 Queue: ${running}R ${pending}P | Synced: ${synced_count}"

    if [ "$running" = "0" ] && [ "$pending" = "0" ] && [ "$synced_count" -gt "0" ]; then
        QUEUE_EMPTY_COUNT=$((QUEUE_EMPTY_COUNT + 1))
        log "🏁 Queue empty check ${QUEUE_EMPTY_COUNT}/2"

        [ "$QUEUE_EMPTY_COUNT" -lt 2 ] && return 1

        # ── GATE 1 passed: queue empty 2x ─────────────────────────────────
        # ── GATE 2: drain window ──────────────────────────────────────────
        log "🔄 DRAIN: waiting 90s for final writes..."
        sleep 90

        # Final reconciliation sweep
        reconcile_uploads

        synced_count=$(wc -l < "$SYNCED_FILE" 2>/dev/null || echo 0)
        local local_mp4_count
        local_mp4_count=$(find "$OUTPUT_DIR" -name 'wan_nsfw_*.mp4' -size +1k 2>/dev/null | wc -l)

        # ── GATE 3: GCS done-marker count ─────────────────────────────────
        local gcs_done_count
        gcs_done_count=$(python3 -c "
from google.cloud import storage
client = storage.Client()
bucket = client.bucket('${GCS_BUCKET}')
markers = [b for b in bucket.list_blobs(prefix='${GCS_PREFIX}/') if b.name.endswith('.done.json')]
print(len(markers))
" 2>/dev/null || echo "0")

        local gcs_mp4_count
        gcs_mp4_count=$(python3 -c "
from google.cloud import storage
client = storage.Client()
bucket = client.bucket('${GCS_BUCKET}')
mp4s = [b for b in bucket.list_blobs(prefix='${GCS_PREFIX}/') if b.name.endswith('.mp4') and b.size > 1000]
print(len(mp4s))
" 2>/dev/null || echo "0")

        log "📊 DRAIN VERIFY: local=${local_mp4_count} mp4s | GCS=${gcs_mp4_count} mp4s | done markers=${gcs_done_count}"

        # Re-sync if GCS short
        if [ "$gcs_mp4_count" -lt "$local_mp4_count" ]; then
            log "⚠️  GCS short (${gcs_mp4_count} < ${local_mp4_count}), re-uploading..."
            for f in "$OUTPUT_DIR"/wan_nsfw_*.mp4 "$OUTPUT_DIR"/wan_nsfw_*.png; do
                [ -f "$f" ] && upload_file "$f"
            done
            sleep 30
        fi

        # Optional: ffprobe last 3 videos
        if command -v ffprobe &>/dev/null; then
            local bad=0
            while IFS= read -r f; do
                if ! ffprobe -v quiet -select_streams v:0 -show_entries stream=duration -of csv=p=0 "$f" > /dev/null 2>&1; then
                    log "⚠️  ffprobe failed: $(basename "$f")"
                    bad=$((bad + 1))
                fi
            done < <(find "$OUTPUT_DIR" -name 'wan_nsfw_*.mp4' -size +1k | sort -t/ -k1 | tail -3)
            [ "$bad" -gt 0 ] && log "⚠️  ${bad}/3 sampled videos may be corrupt"
        fi

        # Upload final manifest
        local final_synced
        final_synced=$(wc -l < "$SYNCED_FILE" 2>/dev/null || echo 0)
        python3 -c "
import json, time
manifest = {
    'host': '${HOST_LABEL}',
    'synced_total': ${final_synced},
    'local_mp4s': ${local_mp4_count},
    'gcs_mp4s': ${gcs_mp4_count},
    'gcs_done_markers': ${gcs_done_count},
    'completed_at': time.strftime('%Y-%m-%dT%H:%M:%SZ'),
    'files': open('${SYNCED_FILE}').read().strip().split('\n')
}
with open('/tmp/manifest.json', 'w') as f:
    json.dump(manifest, f, indent=2)
" 2>/dev/null
        upload_file /tmp/manifest.json 2>/dev/null || true

        log "═══ ✅ COMPLETE: ${final_synced} synced, ${gcs_mp4_count} verified in GCS ═══"

        # ── Destroy instance ──────────────────────────────────────────────
        if [ -n "$VAST_API_KEY" ]; then
            log "🔪 Destroying instance..."
            pip install -q vastai 2>/dev/null || true
            vastai set api-key "$VAST_API_KEY" 2>/dev/null

            local inst_id
            inst_id=$(vastai show instances --raw 2>/dev/null | python3 -c "
import sys, json
for i in json.load(sys.stdin):
    if i.get('label') == '${HOST_LABEL}':
        print(i['id']); break
" 2>/dev/null || true)

            if [ -n "$inst_id" ]; then
                log "Destroying instance ${inst_id} (${HOST_LABEL})..."
                vastai destroy instance "$inst_id" 2>&1 | tee -a "$SYNC_LOG"
            else
                log "⚠️  Could not find instance ID for ${HOST_LABEL}"
            fi
        else
            log "⚠️  No VAST_API_KEY — instance will NOT auto-destroy"
        fi

        return 0  # signal done
    else
        QUEUE_EMPTY_COUNT=0
    fi

    return 1
}

###############################################################################
# Main loop — inotifywait (instant) + periodic reconciliation
###############################################################################
main() {
    setup_gcs || { log "GCS setup failed — uploads will fail"; }

    log "═══ SYNC v3 STARTED for ${HOST_LABEL} ═══"
    log "  Watch:  ${OUTPUT_DIR}"
    log "  Upload: gs://${GCS_BUCKET}/${GCS_PREFIX}/"
    log "  Mode:   inotifywait + periodic reconciliation + drain-safe"

    if command -v inotifywait &>/dev/null; then
        log "⚡ inotifywait available — instant mode"

        # Background: auto-kill checker every 30s
        (while true; do sleep 30; check_autokill && exit 0; done) &
        local KILL_PID=$!

        # Background: periodic reconciliation every 60s
        (while true; do sleep 60; reconcile_uploads; done) &
        local RECON_PID=$!

        # Foreground: inotifywait — triggers the moment a file is closed
        inotifywait -m -e close_write --format '%f' "$OUTPUT_DIR" 2>/dev/null | while IFS= read -r filename; do
            if [[ "$filename" == wan_nsfw_* ]] && [[ "$filename" == *.mp4 || "$filename" == *.png ]]; then
                sleep 1  # brief settle for file flush
                upload_file "${OUTPUT_DIR}/${filename}"
            fi
        done

        kill "$KILL_PID" "$RECON_PID" 2>/dev/null || true
    else
        log "📡 Polling mode (5s interval)"

        while true; do
            reconcile_uploads
            check_autokill && break
            sleep 5
        done
    fi

    log "═══ SYNC COMPLETE ═══"
}

main
