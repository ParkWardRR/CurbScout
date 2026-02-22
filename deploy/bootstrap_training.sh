#!/bin/bash
# Vast.ai Bootstrap Script - Runs sequentially on startup
# Orchestrates dependencies -> dataset -> train -> export -> upload -> destroy

set -euo pipefail

# Injected environment variables during Vast launch
export VAST_INSTANCE_ID=${VAST_INSTANCE_ID:-"local-test"}
export VAST_API_KEY=${VAST_API_KEY:-""}
export GCP_PROJECT=${GCP_PROJECT:-"curbscout-project"}
export BUCKET_NAME=${BUCKET_NAME:-"curbscout-artifacts"}

echo "===== CurbScout Vast.ai Training Node Triggered ====="
echo "Instance ID: $VAST_INSTANCE_ID"

# 1. Start Auto-Kill Safety Timer (Max 12 hours)
# This prevents runaway costs if the script hangs.
nohup ./autokill.sh > /var/log/autokill.log 2>&1 &
echo "Auto-kill timer active in background."

# 2. Install Dependencies
echo "Installing System Dependencies..."
apt-get update -y
apt-get install -y python3-pip curl unzip jq

echo "Installing Python Dependencies..."
pip3 install ultralytics google-cloud-storage onnxruntime coremltools "firebase-admin==6.*"
# Use TensorRT specific pip wheels on CUDA
pip3 install tensorrt --extra-index-url https://pypi.nvidia.com

# 3. Download Dataset from GCS
echo "Downloading CurbScout Active Learning Dataset..."
mkdir -p /mnt/dataset
# Since gsutil requires auth, we rely on ADC if passed or public bucket for dataset.
# Alternatively, download via Python storage API using ADC injected via vault.
python3 download_dataset.py

# 4. Run Training
echo "Commencing YOLOv8 Finetuning..."
python3 train.py

# 5. Export Models
echo "Exporting best weights to ONNX, TensorRT, and CoreML formats..."
./export.sh

# 6. Upload Results & Signal Firestore
echo "Uploading exported models to GCS..."
python3 upload_teardown.py

echo "Bootstrap completed successfully."
