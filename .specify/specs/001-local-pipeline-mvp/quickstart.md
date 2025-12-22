# Quickstart: CurbScout Local Pipeline MVP

## Prerequisites

- macOS 14+ (Sonoma) on Apple Silicon (M1/M2/M3/M4)
- Python 3.11+ (via Homebrew: `brew install python@3.11`)
- Node.js 20+ (via Homebrew: `brew install node`)
- uv (Python package manager: `curl -LsSf https://astral.sh/uv/install.sh | sh`)
- ffmpeg (via Homebrew: `brew install ffmpeg`)
- Insta360 GO 3S camera + USB-C cable

## 1. Clone & Setup

```bash
git clone https://github.com/ParkWardRR/CurbScout.git
cd CurbScout

# Run the setup script (installs deps, creates dirs, downloads models)
chmod +x scripts/setup.sh
./scripts/setup.sh
```

The setup script will:
- Create `~/CurbScout/{raw,derived/frames,derived/crops,exports,models}`
- Install Python dependencies via `uv`
- Install SvelteKit dependencies via `npm install`
- Download pre-trained models (YOLOv8n, Jordo23/vehicle-classifier, VehicleTypeNet)

## 2. Download ML Models (if setup.sh didn't)

```bash
cd models/

# Vehicle detection (YOLOv8 nano, COCO pre-trained)
uv run python -c "from ultralytics import YOLO; m = YOLO('yolov8n.pt'); print('Detection model ready')"

# Vehicle make/model classifier (Jordo23, EfficientNet-B4, 8,949 classes)
uv run pip install huggingface-hub
uv run huggingface-cli download Jordo23/vehicle-classifier --local-dir ./jordo23

# Vehicle type fallback (NVIDIA VehicleTypeNet, ONNX)
# Requires NGC account — see models/README.md for manual download
```

## 3. Import Your First Ride

```bash
# Connect Insta360 GO 3S via USB, select "USB Drive Mode"
# The camera mounts at /Volumes/Insta360GO3S/ (name may vary)

cd pipeline/

# Import videos from camera
uv run python -m curbscout.cli ingest --source /Volumes/Insta360GO3S/DCIM/Camera01/

# Process: sample frames → detect vehicles → classify → deduplicate
uv run python -m curbscout.cli process --date today
```

## 4. Start the Review UI

```bash
# Start both the API server and web UI
chmod +x scripts/start.sh
./scripts/start.sh

# Or start them separately:
# Terminal 1: API server
cd pipeline/ && uv run uvicorn curbscout.api:app --reload --port 8000

# Terminal 2: Web UI
cd web/ && npm run dev
```

Then open **http://localhost:5173** in your browser.

## 5. Review & Correct Sightings

Use these keyboard shortcuts in the review UI:

| Key | Action |
|-----|--------|
| ⏎ Enter | Confirm sighting label |
| ⌫ Delete | Flag as false positive |
| ↑↓ Arrows | Navigate sighting grid |
| / Slash | Open correction search |
| e | Export daily bundle |
| Space | Play/pause video |

## 6. Export a Report

```bash
# From the web UI: press 'e' to export
# Or from CLI:
uv run python -m curbscout.cli export --date 2026-02-21

# View the report
open ~/CurbScout/exports/2026-02-21/index.html
```

## Troubleshooting

- **Camera not detected**: Ensure USB Drive Mode is selected on camera
- **Pipeline errors**: Check `~/CurbScout/pipeline.log`
- **Model download fails**: See `models/README.md` for manual steps
- **API won't start**: Ensure port 8000 is free (`lsof -i :8000`)
- **Web UI won't start**: Ensure port 5173 is free, run `npm install` in web/
- **Database locked**: Ensure only one pipeline instance is running
- **Slow on first run**: Model loading takes ~5-10 sec on first inference
