#!/usr/bin/env bash
# Trigger for local M4 testing

set -e

echo "==========================================="
echo "   CurbScout M4 Local Mac mini Pipeline    "
echo "==========================================="

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_DIR/pipeline"

echo "[1/4] Ensuring macOS uv dependencies..."
uv sync -q

echo "[2/4] Pulling down fresh CoreML active learning weights..."
uv run python3 -c "from curbscout.sync_models import pull_latest_coreml_models; pull_latest_coreml_models()"

echo "[3/4] Ensuring test mock-data directory structure..."
mkdir -p ~/.curbscout/test_data

echo "[4/4] Executing CoreML M4 Inference Daemon Pipeline..."
uv run python3 main.py --source ~/.curbscout/test_data/

echo "Pipeline execution finished successfully. Check GCP UI."
