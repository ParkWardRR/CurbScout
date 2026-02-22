#!/bin/bash
# Hard-stop TTL timer for Ephemeral Vast.ai GPU training nodes (Max 12 hours)
# Prevents runaway costs if the primary pipeline execution hangs or crashes.

MAX_HOURS=12

# Convert to seconds
MAX_SECONDS=$((MAX_HOURS * 3600))

echo "Auto-kill safety timer started for $MAX_HOURS hours ($MAX_SECONDS seconds)."

# Sleep for the maximum allowed duration
sleep $MAX_SECONDS

echo "[WARNING] Primary training script failed to complete in the allocated time."
echo "Auto-kill triggered to prevent runaway billing."

# Self-destruct sequence hitting the Vast.ai API wrapper 
python3 -c "from curbscout.vast_client import VastClient; VastClient().destroy_instance(int(__import__('os').environ.get('VAST_INSTANCE_ID', 0)))"

# Ensure death
shutdown -h now
