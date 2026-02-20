# Research: Local Pipeline MVP

**Feature**: `001-local-pipeline-mvp`
**Date**: 2026-02-21 (updated)
**Purpose**: Technology research to inform implementation plan decisions.

---

## 1. Video Processing on M4 Mac mini

### ffmpeg on Apple Silicon
- ffmpeg with VideoToolbox hardware acceleration is the standard
  approach for frame extraction on macOS/Apple Silicon.
- M4's media engine handles H.264/H.265 decode natively.
- Command pattern: `ffmpeg -hwaccel videotoolbox -i input.mp4 -vf "fps=2" -q:v 2 frame_%06d.jpg`
- For 4K 30fps Insta360 GO 3S footage, expect ~15–25 fps decode
  throughput on M4 (well above real-time for frame sampling).
- GO 3S outputs MP4 with H.264/H.265 codec, 8-bit 4:2:0.

### Insta360 GO 3S File Layout
- USB Drive Mode mounts as external drive.
- Video files in `DCIM/Camera01/` named `VID*.mp4` (stabilized)
  and `PRO*.mp4` (FreeFrame, needs post-processing).
- For MVP, process only `VID*.mp4` (already stabilized).
- `PRO*.mp4` support deferred to later phase.

### Frame Sampling Strategy
- 2 fps default captures most parked/passing cars at cycling speed
  (~10-15 mph) with sufficient temporal coverage.
- At 2 fps sampling from a 30 fps source, we extract 1 in every 15
  frames — processing load is ~6.7% of raw frames.
- 30-minute ride at 2 fps = 3,600 frames to process.
- Can be adjusted per-ride in settings.

---

## 2. Vehicle Detection Models

### YOLOv8 on M4 (CoreML)
- **Recommended**: YOLOv8n (nano) for detection — ~3.2M parameters.
- M4 with Neural Engine achieves ~92.6 FPS on YOLOv8n-640.
- Export to CoreML via `yolo export model=yolov8n.pt format=coreml`.
- CoreML leverages CPU + GPU + Neural Engine transparently.
- At 3,600 frames per ride, detection takes ~39 seconds at 92 fps.

### Detection Classes
- COCO pre-trained YOLOv8 includes: car, truck, bus, motorcycle.
- Filter to vehicle classes only; ignore person, bicycle, etc.
- Confidence threshold: 0.3 (store everything ≥ 0.3; display ≥ 0.5
  by default in UI, with toggle to show low-confidence detections).

### Alternative Models Considered
- **YOLOv11**: Newer but less ecosystem support for CoreML export. Deferred.
- **YOLO-World**: Open-vocabulary detection — interesting for future
  "detect parking signs" use case but overkill for cars now.
- **Apple Vision framework**: Built-in object detection API but less
  control over model selection. Could be explored later.

---

## 3. Pre-Trained Vehicle Make/Model Classification Models

### ⭐ Model Landscape (Available Now — No Training Required)

| Model | Architecture | Classes | Dataset | Accuracy | Format | Download |
|-------|-------------|---------|---------|----------|--------|----------|
| **Jordo23/vehicle-classifier** | EfficientNet-B4 | 8,949 (make+model+year) | VMMRdb | ~Top-1/Top-5 reported | PyTorch (.pth) + ONNX | [HuggingFace](https://huggingface.co/Jordo23/vehicle-classifier) |
| **NVIDIA VehicleMakeNet** | ResNet-18 | 20 brands | NVIDIA proprietary | Production-grade | ONNX + TensorRT | [NGC Catalog](https://catalog.ngc.nvidia.com/orgs/nvidia/tao/vehiclemakenet) |
| **NVIDIA VehicleTypeNet** | ResNet-18 | 6 types (sedan/SUV/truck/van/coupe/large) | NVIDIA proprietary | Production-grade | ONNX + TensorRT | [NGC Catalog](https://catalog.ngc.nvidia.com/orgs/nvidia/tao/vehicletypenet) |
| **ViT Stanford Cars** | Vision Transformer (ViT) | 196 (make+model+year) | Stanford Cars | ~86% top-1 | PyTorch / HF Transformers | [HuggingFace](https://huggingface.co/dima806/car_models_image_detection) |
| **abdusah/CarViT** | ViT | 40 manufacturers | Custom | Reported high | PyTorch / HF | [HuggingFace](https://huggingface.co/abdusah/CarViT) |
| **GoogLeNet CompCars** | Inception V3 | 431 models | CompCars | 91.2% top-1 | PyTorch | [GitHub](https://github.com/chadlimedamine/cars-classification-CompCars) |

### Recommended MVP Strategy: Tiered Model Approach

**Tier 1 — Use Immediately (Day 1, no training):**
- **Jordo23/vehicle-classifier** (EfficientNet-B4, 8,949 classes)
  - Best coverage: make + model + year in a single model
  - Input: 380×380 px crop images
  - Files: `vehicle_classifier.pth`, `vehicle_classifier.onnx`, `class_mapping.csv`
  - Convert to CoreML: `coremltools` from ONNX
  - Fallback: run via ONNX Runtime (works on M4 CPU/GPU)

**Tier 2 — Supplement for type classification:**
- **NVIDIA VehicleTypeNet** (6 types: sedan/SUV/truck/van/coupe/large)
  - Useful when make/model confidence is low — at least tell the user "it's an SUV"
  - ONNX format, easy to run via `onnxruntime`

**Tier 3 — Fine-Tune Later (Phase 4):**
- Start from YOLOv8n-cls pre-trained on ImageNet
- Fine-tune on Stanford Cars (196 classes) + user corrections from CurbScout
- Train on Vast.ai; export to CoreML; deploy back to Mac
- Target: ≥90% top-1 on clear crops

### Classification Pipeline Design
```
Detection Crop (from YOLOv8)
    │
    ├──> Tier 1: Jordo23/vehicle-classifier (8,949 classes)
    │        Output: make, model, year, confidence
    │        If confidence ≥ 0.5 → accept as primary prediction
    │
    ├──> Tier 2: VehicleTypeNet (fallback if Tier 1 conf < 0.5)
    │        Output: vehicle_type (sedan/SUV/etc)
    │        Stored alongside Tier 1 prediction
    │
    └──> Sanity Checker
             Input: make, model, year_guess
             Check against sanity_check.json
             Flag impossible combos
```

### Datasets for Future Training

| Dataset | Images | Classes | Notes |
|---------|--------|---------|-------|
| **Stanford Cars** | 16,185 | 196 (make+model+year) | High quality, clean labels. [HuggingFace](https://huggingface.co/datasets/tanganke/stanford_cars) |
| **CompCars (web)** | 136,726 | 1,716 models × 163 makes | Larger but noisier. [Kaggle](https://www.kaggle.com/datasets/jessicali9530/compcars-dataset) |
| **VMMRdb** | 291,752 | 9,170 classes | Massive, real-world. Used by Jordo23. |
| **CurbScout corrections** | Growing | Project-specific | User corrections become training data |

### Model Export / Runtime Options on M4
```
PyTorch → CoreML:     coremltools.convert() — best for M4 Neural Engine
PyTorch → ONNX:       torch.onnx.export() — cross-platform, runs via onnxruntime
ONNX  → CoreML:       coremltools.converters.onnx — if source is ONNX-only
Direct ONNX Runtime:  onnxruntime (CPU/GPU on macOS) — works for all models
```

---

## 4. Vehicle Deduplication & Tracking

### Approach: Lightweight Temporal + Spatial Dedup
- **Primary method**: Group detections by (make_model, time_window).
  If same predicted make/model appears within 5-second sliding window,
  merge into single sighting.
- **Secondary method**: IoU (Intersection over Union) of bounding
  boxes between adjacent frames. If IoU > 0.3, same vehicle.
- **Tertiary method**: Perceptual hash (pHash) of crops. If hamming
  distance < 10, same vehicle.

### Why NOT Full Multi-Object Tracking (MOT)
- ByteTrack / BoT-SORT designed for continuous video streams.
- We're working with sampled frames (2 fps), not full frame rate.
- At 2 fps, optical flow between frames is unreliable for tracking.
- Simple temporal + spatial + appearance heuristics are sufficient
  for MVP and much simpler to implement and debug.
- Full MOT deferred to later phase if needed.

### Dedup Parameters (Tunable)
- `TEMPORAL_WINDOW_SEC`: 5.0 (default)
- `IOU_THRESHOLD`: 0.3 (default)
- `PHASH_HAMMING_THRESHOLD`: 10 (default)
- All configurable in settings.

---

## 5. Database Design (SQLite)

### Direct sqlite3 for Everything
- **Recommendation**: Use Python `sqlite3` stdlib for the pipeline
  AND the FastAPI backend. No ORM — direct SQL for simplicity.
- SwiftData/SwiftUI is deferred; we don't need Swift persistence now.
- Web UI reads via FastAPI REST API → no direct DB access from browser.

### WAL Mode
- Enable WAL (Write-Ahead Logging) mode for concurrent read/write:
  FastAPI reading while Python pipeline writes.
- `PRAGMA journal_mode=WAL;`

### Schema Versioning
- Use integer schema version in a `_meta` table.
- Pipeline checks schema version before writing; refuses if
  version mismatch.

---

## 6. SvelteKit Web UI Architecture

### Stack Decision
- **SvelteKit 5** (Svelte 5 with runes) for the review/correction UI.
- Served locally on `localhost:5173` during development.
- Communicates with a **FastAPI** backend on `localhost:8000`.
- Dark-mode-first, premium design with smooth animations.

### Why SvelteKit Over SwiftUI for MVP
1. **Speed**: SvelteKit + vanilla CSS ships in ~3 days vs ~7 for SwiftUI.
2. **Reuse**: Same SvelteKit app becomes the cloud dashboard later (Phase 3).
3. **Cross-platform**: Works on any machine with a browser, not just macOS.
4. **Video**: HTML5 `<video>` element is powerful enough for review scrubbing.
5. **Dev speed**: Hot reload, no Xcode burden, easier to iterate design.

### Component Architecture
```
SvelteKit App (localhost:5173)
├── /                        → Ride list (dashboard)
├── /rides/[rideId]          → Ride detail + sighting grid + video player
├── /rides/[rideId]/review   → Sequential review mode
├── /export/[rideId]         → Export preview + trigger
└── /settings                → Pipeline config (fps, thresholds, model)
```

### FastAPI Backend (localhost:8000)
```
GET  /api/rides              → List rides
GET  /api/rides/{id}         → Ride detail with sightings
GET  /api/sightings          → Query sightings (filters, pagination)
POST /api/sightings/{id}/correct  → Apply correction
POST /api/sightings/{id}/confirm  → Confirm label
POST /api/sightings/{id}/delete   → Soft delete
POST /api/export/{rideId}    → Trigger export
GET  /api/static/crops/{path} → Serve crop images
GET  /api/static/video/{path} → Stream video files
GET  /api/config             → Current config
PUT  /api/config             → Update config
```

### Video Playback in Browser
- HTML5 `<video>` element with JavaScript seek API.
- Use `video.currentTime = timestamp` for frame-level seeking.
- ffmpeg pre-generates a low-res proxy video for smooth scrubbing
  if the raw 4K is too heavy for browser streaming.
- Alternative: serve via HTTP Range requests from FastAPI.

### Keyboard Shortcuts (Web)
- ⏎ Enter: Confirm current sighting label
- ⌫/Delete: Flag as false positive
- ↑↓ Arrows: Navigate sighting grid
- / (slash): Open correction search
- e: Export daily bundle
- Space: Play/pause video

### Design Tokens (Premium Dark-Mode-First)
- Background: `hsl(220, 20%, 8%)` — deep space black
- Surface: `hsl(220, 18%, 13%)` — card backgrounds
- Accent: `hsl(160, 70%, 50%)` — mint green for confirmed
- Warning: `hsl(40, 90%, 55%)` — amber for low confidence
- Danger: `hsl(0, 70%, 55%)` — red for deleted/flagged
- Font: Inter (Google Fonts) — clean, modern sans-serif
- Border radius: 12px — soft, rounded cards
- Transitions: 150ms ease-out — snappy micro-animations

---

## 7. Export Bundle Format

### Structure
```
~/CurbScout/exports/2026-02-21/
├── sightings.jsonl        # One JSON object per line
├── sightings.csv          # Flat CSV with same fields
├── crops/                 # Referenced crop images
│   ├── sighting_001.jpg
│   ├── sighting_002.jpg
│   └── ...
└── index.html             # Self-contained report (inline CSS/JS)
```

### JSONL Schema (per line)
```json
{
  "sighting_id": "uuid",
  "ride_id": "uuid",
  "timestamp": "2026-02-21T14:30:00Z",
  "predicted_make": "BMW",
  "predicted_model": "3 Series",
  "predicted_year": "2020",
  "year_confidence": "low",
  "classification_confidence": 0.87,
  "classifier_model": "jordo23-efficientnet-b4-vmmrdb",
  "vehicle_type": "sedan",
  "corrected_make": null,
  "corrected_model": null,
  "review_status": "confirmed",
  "crop_file": "crops/sighting_001.jpg",
  "video_file": "ride_2026-02-21_001.mp4",
  "video_timestamp_sec": 145.5,
  "sanity_warnings": []
}
```

---

## 8. Detailed Roadmap — All Phases

### Phase 1 — Local Pipeline + SvelteKit Review (THIS FEATURE)
- USB transfer → ingest → sample → detect → classify → dedupe → persist
- SvelteKit web UI for review/correction on localhost
- FastAPI backend serving SQLite data
- Daily export bundles
- Pre-trained models (Jordo23 + VehicleTypeNet), no custom training yet
- **Timeline**: ~3 weeks solo

### Phase 2 — Cloud Sync & Autoupload
- Upload daily bundles to GCS/DO Spaces on home Wi-Fi overnight
- Configurable: Wi-Fi only / opportunistic / manual
- launchd scheduled job or systemd-equivalent
- ~10–50 MB per bundle (JSON + crops, no raw video)
- **Decision required**: Wi-Fi only vs. opportunistic vs. manual
- **Timeline**: ~1 week

### Phase 3 — Cloud Dashboard (SvelteKit)
- Deploy same SvelteKit app to Vercel/Cloudflare (adapter-static)
- Reads sightings from GCS/DO object storage
- Add heatmaps (Mapbox GL / Leaflet) for sighting locations
- Add analytics: most-seen makes/models, time-of-day patterns
- Optional: basic auth or Cloudflare Access
- **Timeline**: ~1.5 weeks

### Phase 4 — Custom Model Training (Vast.ai)
- Export corrected labels from CurbScout DB
- Push labeled dataset to Vast.ai (curated from user corrections)
- Fine-tune YOLOv8n-cls on Stanford Cars + CurbScout corrections
- Training recipe:
  1. Start from `yolov8n-cls.pt` (ImageNet pre-trained)
  2. First stage: fine-tune on Stanford Cars (196 classes)
  3. Second stage: fine-tune on CurbScout corrections (project-specific)
  4. Export best.pt → CoreML/ONNX → deploy back to Mac
- A/B test new model vs. Jordo23 baseline on held-out CurbScout data
- Target: ≥85% top-1 on CurbScout-specific vehicle distribution
- **Budget**: ~$5–20 per training run on Vast.ai (RTX 4090, ~2-4 hours)
- **Timeline**: ~1.5 weeks (including dataset curation)

### Phase 5 — Curb Intelligence (Parking, Hazards)
- **Phase 5A — Parking Sign Detection & OCR**:
  - Deploy YOLOv8 sign detector + PaddleOCR v3 (PP-OCRv5)
  - Detect parking/street-sweeping signs in ride footage
  - Extract text → parse time windows → structured rules
  - Santa Monica municipal code integration for "can I park here?"
- **Phase 5B — Hazard & Obstruction Mapping**:
  - Bike lane obstructions, potholes, construction zones
  - Temporal change detection (same route, different days)
- **Phase 5C — Storefront OCR Diary**:
  - Track business changes on frequently ridden routes
- All reuse the same "event timeline + evidence + corrections" DB design
- **Timeline**: ~4–6 weeks (incremental sub-phases)

### Phase 6 — Active Learning Loop
- Model serves predictions → user corrects → corrections auto-queued
  for next training batch → Vast.ai trains → new model deployed
- Semi-automated: user triggers training, reviews A/B results
- Model versioning: each model tagged with training data hash
- **Timeline**: ~2 weeks

### Phase 7 — Multi-Device & Collaboration
- Sync database across multiple Macs (CRDTs or SQLite changeset sync)
- Multiple riders contributing sightings to a shared dataset
- Web dashboard supports multi-user views
- **Timeline**: ~3–4 weeks

### Phase 8 — Native macOS App (SwiftUI)
- Port the SvelteKit review UI to a native Swift/SwiftUI macOS app
- SwiftData for local persistence (reads same SQLite database)
- Native video scrubber with AVFoundation
- Menu bar status indicator for pipeline progress
- Auto-launch on camera connection via IOKit/DiskArbitration
- Keyboard shortcuts via SwiftUI `.keyboardShortcut()`
- Deferred to end of roadmap — SvelteKit web UI serves as primary review interface
- **Timeline**: ~2–3 weeks

---

## 9. Future Technology Notes

### SvelteKit → Tauri (Optional Desktop Wrapper)
- If native-feeling desktop is wanted without full SwiftUI rewrite,
  Tauri wraps SvelteKit in a lightweight native window.
- Rust backend, tiny binary size, macOS native menus.
- Could be a Phase 8 alternative if SwiftUI feels too heavy.

### GPS/Location Integration
- Insta360 GO 3S has no built-in GPS.
- Could pair with phone GPS via Bluetooth or use Strava/Komoot GPX exports.
- Match video timestamps to GPS tracks for sighting geolocation.
- **Libraries**: gpxpy (Python), Mapbox GL JS (SvelteKit maps).
