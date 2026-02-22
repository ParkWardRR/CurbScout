#!/bin/bash
# Converts the `best.pt` file into formats explicitly required by the M4 Mac 
# mini (CoreML INT8) and fallback (ONNX FP32)

set -e

LATEST_RUN=$(ls -td /mnt/training_runs/curbscout-finetune* | head -1)
BEST_PT="$LATEST_RUN/weights/best.pt"

echo "Locating best model: $BEST_PT"
if [ ! -f "$BEST_PT" ]; then
    echo "No best.pt found. Export failed."
    exit 1
fi

echo "Exporting to CoreML (for Apple Neural Engine)..."
# coreml tools execution via ultralytics CLI
yolo export model="$BEST_PT" format=coreml nms=True optimize=True int8=True

echo "Exporting to ONNX..."
yolo export model="$BEST_PT" format=onnx dynamic=True simplify=True

echo "Exporting to Engine (TensorRT) for VAST.ai back-testing..."
yolo export model="$BEST_PT" format=engine half=True workspace=4

echo "All exports complete!"
