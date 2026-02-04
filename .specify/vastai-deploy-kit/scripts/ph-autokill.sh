#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  PromptHarbor Auto-Kill Safety Guard
#  Prevents runaway billing by auto-destroying the instance after a deadline.
#
#  Features:
#  ├─ Default 12hr TTL from boot
#  ├─ Checks controller for postpone requests (adds 2-4hr extensions)
#  ├─ Saves final status to GCS before shutdown
#  ├─ Notifies controller API before killing
#  ├─ Creates detailed shutdown log
#  └─ Runs as a systemd service (auto-restarts if killed)
#
#  Usage: /opt/ph-autokill.sh [--ttl-hours 12] [--controller-url URL]
#  Updated: 2026-02-21 — controller URL is optional (no backend needed)
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
DEFAULT_TTL_HOURS=12
MAX_EXTENSIONS=3
EXTENSION_HOURS=2
CONTROLLER_URL="${CONTROLLER_URL:-}"  # Optional — leave empty if no controller backend
GCS_BUCKET="${GCS_BUCKET:-gs://ph-test-2026}"
NODE_ID="${NODE_ID:-vast-$(hostname | tr '.' '-')}"
LOGFILE="/var/log/ph-autokill.log"
POSTPONE_FILE="/tmp/ph-postpone-count"
BOOT_TIME_FILE="/tmp/ph-boot-time"

# Parse args
TTL_HOURS=$DEFAULT_TTL_HOURS
while [[ $# -gt 0 ]]; do
    case $1 in
        --ttl-hours) TTL_HOURS="$2"; shift 2 ;;
        --controller-url) CONTROLLER_URL="$2"; shift 2 ;;
        --node-id) NODE_ID="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# ── Logging ───────────────────────────────────────────────────────────────────
log() {
    local msg="[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $1"
    echo "$msg" | tee -a "$LOGFILE"
}

# ── Initialize ────────────────────────────────────────────────────────────────
if [ ! -f "$BOOT_TIME_FILE" ]; then
    date +%s > "$BOOT_TIME_FILE"
fi
echo "0" > "$POSTPONE_FILE" 2>/dev/null || true
BOOT_EPOCH=$(cat "$BOOT_TIME_FILE")

log "═══════════════════════════════════════════════════════════"
log "  PromptHarbor Auto-Kill Safety Guard"
log "  Node:       $NODE_ID"
log "  Controller: $CONTROLLER_URL"
log "  TTL:        ${TTL_HOURS}h (max ${MAX_EXTENSIONS} extensions of ${EXTENSION_HOURS}h)"
log "  Boot:       $(date -d @$BOOT_EPOCH -u '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -r $BOOT_EPOCH -u '+%Y-%m-%d %H:%M:%S UTC')"
log "  Deadline:   $(date -d @$((BOOT_EPOCH + TTL_HOURS * 3600)) -u '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -r $((BOOT_EPOCH + TTL_HOURS * 3600)) -u '+%Y-%m-%d %H:%M:%S UTC')"
log "═══════════════════════════════════════════════════════════"

# ── Notify controller of guard activation ─────────────────────────────────────
if [ -n "$CONTROLLER_URL" ]; then
    curl -s -X POST "${CONTROLLER_URL}/api/nodes/heartbeat/${NODE_ID}" \
        -H "Content-Type: application/json" \
        -d "{\"status\":\"running\",\"autokill_ttl_hours\":${TTL_HOURS},\"autokill_boot_epoch\":${BOOT_EPOCH}}" \
        --max-time 5 > /dev/null 2>&1 || true
fi

# ── Shutdown procedure ────────────────────────────────────────────────────────
perform_shutdown() {
    local reason="$1"
    local uptime_secs=$(( $(date +%s) - BOOT_EPOCH ))
    local uptime_hrs=$(echo "scale=2; $uptime_secs / 3600" | bc 2>/dev/null || echo "$((uptime_secs / 3600))")

    log ""
    log "╔═══════════════════════════════════════════════════════╗"
    log "║  🛑 AUTO-KILL TRIGGERED                              ║"
    log "║  Reason: $reason"
    log "║  Uptime: ${uptime_hrs}h (${uptime_secs}s)"
    log "╚═══════════════════════════════════════════════════════╝"

    # 1. Save final output inventory to GCS (non-blocking, 10s timeout)
    log "  📦 Saving output inventory to GCS..."
    {
        ls -la /workspace/ComfyUI/output/ 2>/dev/null | head -50 > /tmp/ph-final-inventory.txt
        echo "" >> /tmp/ph-final-inventory.txt
        echo "=== GPU Stats ===" >> /tmp/ph-final-inventory.txt
        nvidia-smi 2>/dev/null >> /tmp/ph-final-inventory.txt || true
        echo "" >> /tmp/ph-final-inventory.txt
        echo "=== Shutdown Reason ===" >> /tmp/ph-final-inventory.txt
        echo "$reason" >> /tmp/ph-final-inventory.txt
        echo "Uptime: ${uptime_hrs}h" >> /tmp/ph-final-inventory.txt

        # Try to upload - don't wait more than 10s
        timeout 10 gsutil -q cp /tmp/ph-final-inventory.txt \
            "${GCS_BUCKET}/autokill/${NODE_ID}/shutdown_$(date +%s).txt" 2>/dev/null || true
        timeout 10 gsutil -q cp "$LOGFILE" \
            "${GCS_BUCKET}/autokill/${NODE_ID}/autokill.log" 2>/dev/null || true
    } &
    local gcs_pid=$!

    # 2. Notify controller (non-blocking, 5s timeout)
    if [ -n "$CONTROLLER_URL" ]; then
        log "  📡 Notifying controller..."
        {
            curl -s -X POST "${CONTROLLER_URL}/api/nodes/heartbeat/${NODE_ID}" \
                -H "Content-Type: application/json" \
                -d "{\"status\":\"offline\",\"shutdown_reason\":\"autokill: ${reason}\",\"uptime_hours\":${uptime_hrs}}" \
                --max-time 5 > /dev/null 2>&1 || true
        } &
        local ctrl_pid=$!
    else
        local ctrl_pid=""
    fi

    # 3. Wait briefly for GCS/controller (max 8s total, don't block)
    sleep 2
    kill $gcs_pid 2>/dev/null || true
    [ -n "${ctrl_pid:-}" ] && kill $ctrl_pid 2>/dev/null || true

    log "  💀 Executing shutdown NOW"

    # 4. Kill the instance
    # Try Vast.ai's own shutdown mechanism first
    if command -v vastai &>/dev/null; then
        vastai stop instance 2>/dev/null || true
    fi

    # Nuclear option: halt the instance
    sync
    poweroff -f 2>/dev/null || shutdown -h now 2>/dev/null || halt -f 2>/dev/null || true
}

# ── Check controller for postpone ────────────────────────────────────────────
check_postpone() {
    local extensions_used
    extensions_used=$(cat "$POSTPONE_FILE" 2>/dev/null || echo "0")

    if [ "$extensions_used" -ge "$MAX_EXTENSIONS" ]; then
        log "  ⚠️  Max extensions ($MAX_EXTENSIONS) already used, no more postpones"
        return 1
    fi

    # Ask controller if we should extend
    local response
    response=$(curl -s --max-time 5 \
        "${CONTROLLER_URL}/api/nodes/heartbeat/${NODE_ID}" 2>/dev/null || echo "{}")

    # Check if controller says to extend
    local should_extend
    should_extend=$(echo "$response" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # Controller can set 'postpone': true to extend
    print('yes' if d.get('postpone') or d.get('extend') else 'no')
except:
    print('no')
" 2>/dev/null || echo "no")

    if [ "$should_extend" = "yes" ]; then
        extensions_used=$((extensions_used + 1))
        echo "$extensions_used" > "$POSTPONE_FILE"
        log "  🕐 POSTPONED by ${EXTENSION_HOURS}h (extension $extensions_used/$MAX_EXTENSIONS)"
        return 0
    fi

    return 1
}

# ── Main loop ─────────────────────────────────────────────────────────────────
log "  🟢 Guard active. Checking every 60s..."

while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - BOOT_EPOCH))
    EXTENSIONS_USED=$(cat "$POSTPONE_FILE" 2>/dev/null || echo "0")
    TOTAL_TTL=$(( (TTL_HOURS + EXTENSIONS_USED * EXTENSION_HOURS) * 3600 ))
    REMAINING=$((TOTAL_TTL - ELAPSED))
    REMAINING_MIN=$((REMAINING / 60))
    DEADLINE=$((BOOT_EPOCH + TOTAL_TTL))

    if [ $REMAINING -le 0 ]; then
        perform_shutdown "TTL expired (${TTL_HOURS}h + ${EXTENSIONS_USED}x${EXTENSION_HOURS}h extensions)"
        exit 0
    fi

    # Warning at 30 min
    if [ $REMAINING -le 1800 ] && [ $REMAINING -gt 1740 ]; then
        log "  ⚠️  30 MINUTES remaining before auto-kill"
        log "     Deadline: $(date -d @$DEADLINE -u '+%H:%M:%S UTC' 2>/dev/null || date -r $DEADLINE -u '+%H:%M:%S UTC')"

        # Try to get a postpone from controller
        if check_postpone; then
            continue
        fi
    fi

    # Warning at 5 min
    if [ $REMAINING -le 300 ] && [ $REMAINING -gt 240 ]; then
        log "  🚨 5 MINUTES remaining! Final warning!"

        # Last chance postpone
        if check_postpone; then
            continue
        fi
    fi

    # Heartbeat every 5 minutes
    if [ $((ELAPSED % 300)) -lt 60 ] && [ -n "$CONTROLLER_URL" ]; then
        curl -s -X POST "${CONTROLLER_URL}/api/nodes/heartbeat/${NODE_ID}" \
            -H "Content-Type: application/json" \
            -d "{\"status\":\"running\",\"remaining_min\":${REMAINING_MIN},\"extensions_used\":${EXTENSIONS_USED}}" \
            --max-time 5 > /dev/null 2>&1 || true
    fi

    # Periodic status log (every 10 min)
    if [ $((ELAPSED % 600)) -lt 60 ]; then
        log "  ⏱  ${REMAINING_MIN}m remaining (extensions: ${EXTENSIONS_USED}/${MAX_EXTENSIONS})"
    fi

    sleep 60
done
