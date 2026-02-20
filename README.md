<div align="center">

# CurbScout

**Local-first perception pipeline — ride video to structured city intelligence.**

[![License: Blue Oak 1.0.0](https://img.shields.io/badge/license-Blue%20Oak%201.0.0-2D6EB5?style=for-the-badge)](https://blueoakcouncil.org/license/1.0.0)
[![Python 3.11+](https://img.shields.io/badge/python-3.11+-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![SvelteKit](https://img.shields.io/badge/svelte_kit-5-FF3E00?style=for-the-badge&logo=svelte&logoColor=white)](https://kit.svelte.dev)
[![SQLite](https://img.shields.io/badge/sqlite-3.35+-003B57?style=for-the-badge&logo=sqlite&logoColor=white)](https://sqlite.org)
[![FastAPI](https://img.shields.io/badge/fastapi-0.110+-009688?style=for-the-badge&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Apple Silicon](https://img.shields.io/badge/apple_silicon-M4-000000?style=for-the-badge&logo=apple&logoColor=white)]()
[![CUDA](https://img.shields.io/badge/cuda-12.4-76B900?style=for-the-badge&logo=nvidia&logoColor=white)]()
[![TensorRT](https://img.shields.io/badge/tensorrt-FP16%2FINT8-76B900?style=for-the-badge&logo=nvidia&logoColor=white)]()
[![CoreML](https://img.shields.io/badge/coreml-ANE_INT8-000000?style=for-the-badge&logo=apple&logoColor=white)]()
[![YOLOv8](https://img.shields.io/badge/yolov8-ultralytics-6F42C1?style=for-the-badge)]()
[![Go SDK](https://img.shields.io/badge/go_sdk-fleet_mgmt-00ADD8?style=for-the-badge&logo=go&logoColor=white)]()
[![GCS](https://img.shields.io/badge/gcs-artifact_sync-4285F4?style=for-the-badge&logo=googlecloud&logoColor=white)]()
[![Vast.ai](https://img.shields.io/badge/vast.ai-burst_GPU-9B59B6?style=for-the-badge)]()
[![Status](https://img.shields.io/badge/status-active_development-2ECC71?style=for-the-badge)]()

<br/>

*Ingest daily Insta360 GO 3S cycling footage on an M4 Mac mini.*
*Detect, classify, and catalog every vehicle sighting — entirely offline.*
*Burst to rented NVIDIA GPUs for training. Sync only what matters.*

</div>

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Hardware Platform](#hardware-platform)
- [Capture Device](#capture-device)
- [Camera Placement](#camera-placement)
- [Data Transfer](#data-transfer)
- [Pipeline Stages](#pipeline-stages)
- [Machine Learning Stack](#machine-learning-stack)
- [Hardware Acceleration](#hardware-acceleration)
- [Vast.ai GPU Infrastructure](#vastai-gpu-infrastructure)
- [Database Schema](#database-schema)
- [Review Interface](#review-interface)
- [Export System](#export-system)
- [File System Layout](#file-system-layout)
- [Vehicle Recognition](#vehicle-recognition)
- [Deduplication Strategy](#deduplication-strategy)
- [Security and Privacy](#security-and-privacy)
- [Roadmap](#roadmap)
- [Cost Analysis](#cost-analysis)
- [Specification Kit](#specification-kit)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

CurbScout is a perception pipeline purpose-built for extracting structured urban data from action camera footage. The system processes raw 4K video captured during daily cycling commutes, identifies every vehicle in frame, classifies each by make and model, deduplicates repeated sightings, and persists the results into a queryable local database.

The pipeline operates under a strict **local-first** constraint. All raw footage, derived assets, and database state remain on the origin machine by default. Only lightweight, derived artifacts — structured JSON metadata, cropped thumbnail images, and short highlight clips — are candidates for optional cloud synchronization. This design directly addresses the bandwidth limitations of residential coax internet connections, where upstream throughput makes uploading raw 4K footage impractical.

The project is structured for **incremental delivery**. Phase 1 delivers a fully functional, offline-capable pipeline with a premium web-based review interface. Subsequent phases introduce optional cloud sync, a remote analytics dashboard, GPU-accelerated model training via Vast.ai, and expansion into broader "curb intelligence" use cases including parking sign OCR, street sweeping detection, and hazard mapping.

---

## Architecture

### End-to-End Dataflow

```mermaid
flowchart LR
    A["Ride Capture"] --> B["USB Transfer"]
    B --> C["Ingest + Checksum"]
    C --> D["Frame Sampling"]
    D --> E["Vehicle Detection"]
    E --> F["Crop Generation"]
    F --> G["Make/Model Classification"]
    G --> H["Deduplication"]
    H --> I["SQLite Persistence"]
    I --> J["Review UI"]
    J --> K["Export Bundles"]
    K --> L["Cloud Sync"]
    K --> M["Vast.ai Training"]
```

### Component Architecture

```mermaid
flowchart TB
    subgraph Local["M4 Mac mini — Local First"]
        W["Folder Watcher + Ingest Daemon"]
        P["Pipeline Runner"]
        DB[("SQLite WAL")]
        API["FastAPI Backend"]
        UI["SvelteKit Review UI"]
        EX["Exporter"]
        W --> P --> DB
        DB <--> API
        API <--> UI
        DB --> EX
    end

    subgraph Cloud["Later Phases — Cloud"]
        OBJ[("GCS / DO Spaces")]
        WEB["SvelteKit Dashboard"]
        GPU["Vast.ai GPU Fleet"]
    end

    EX --> OBJ
    OBJ --> WEB
    GPU --> OBJ
```

### Acceleration Dispatch

```mermaid
flowchart TB
    START["Pipeline Input"] --> DETECT["detect_best_backend()"]
    DETECT -->|"arm64 + Darwin"| ANE["CoreML ANE — 38 TOPS INT8"]
    DETECT -->|"CUDA available"| TRT["TensorRT FP16 + cuDNN"]
    DETECT -->|"x86_64 AVX-512"| AVX["ONNX Runtime + oneDNN"]
    DETECT -->|"Fallback"| CPU["ONNX Runtime CPU"]
    ANE --> PIPE["Pipeline Execution"]
    TRT --> PIPE
    AVX --> PIPE
    CPU --> PIPE
```

---

## Hardware Platform

CurbScout targets Apple Silicon as the primary inference platform with NVIDIA CUDA GPUs reserved for training and batch reprocessing workloads.

### Primary: M4 Mac mini (24 GB)

| Component | Specification | Pipeline Role |
|:---|:---|:---|
| **Neural Engine** | 16-core, 38 TOPS (INT8) | YOLOv8 detection, EfficientNet classification |
| **GPU** | 10-core, 4.5 TFLOPS FP32 | Fallback inference, image preprocessing |
| **CPU** | 4P + 6E cores, ARMv9.2-A | Pipeline orchestration, hashing, database I/O |
| **SME** | 512-bit matrix ops, BFloat16 | Custom matrix multiply kernels |
| **NEON SIMD** | 128-bit per core, 4 ALUs | Image resize, pHash, channel conversion |
| **Media Engine** | Hardware H.264/H.265 decode | VideoToolbox frame extraction |
| **Unified Memory** | 24 GB, 120 GB/s bandwidth | Zero-copy transfer between CPU/GPU/ANE |

The M4 Neural Engine delivers approximately **92.6 FPS** on YOLOv8n INT8 detection and over **350 classifications per second** on EfficientNet-B4, making real-time local inference feasible for a 2 FPS sampling rate without any cloud dependency.

### Burst: Vast.ai GPU Fleet (On-Demand)

| GPU | VRAM | Detection FPS | Training Speed | Typical Cost |
|:---|:---|:---|:---|:---|
| **RTX 4090** | 24 GB GDDR6X | ~580 FPS (TensorRT INT8) | ~4 min/epoch | $0.27–0.40/hr |
| **RTX 3090** | 24 GB GDDR6X | ~310 FPS (TensorRT INT8) | ~7 min/epoch | $0.11–0.16/hr |
| **A100 80 GB** | 80 GB HBM2e | ~400 FPS (TensorRT FP16) | ~2.5 min/epoch | $0.50–0.80/hr |

GPU instances are provisioned exclusively for training runs and large-scale batch reprocessing. No persistent cloud compute runs on behalf of the pipeline.

---

## Capture Device

### Insta360 GO 3S

| Attribute | Value |
|:---|:---|
| **Sensor** | 1/2.3-inch CMOS |
| **Max Video Resolution** | 4K (3840×2160) at 24/25/30 fps |
| **Additional Modes** | 2.7K at 50 fps, 1080p at 200 fps (slow motion) |
| **Photo Resolution** | 12 MP (4000×3000 at 4:3) |
| **Codec Output** | H.264 / H.265, 8-bit 4:2:0 |
| **Storage** | Internal (no removable media) |
| **Battery — Camera Only** | ~38 minutes |
| **Battery — With Action Pod** | ~140 minutes |
| **Camera Weight** | 39.1 g (1.38 oz) |
| **Camera + Action Pod Weight** | 135.4 g (4.78 oz) |
| **Stabilization** | FlowState electronic stabilization |
| **Connectivity** | USB-C, Bluetooth 5.0, Wi-Fi |
| **Water Resistance** | IPX8 (10 m) |
| **Transfer Mode** | U-Disk / USB Drive Mode via USB-C |

The GO 3S captures stabilized 4K footage from a magnetic chest mount during cycling. At a typical ride duration of 30–50 minutes, a single commute generates approximately 8–15 GB of raw footage.

---

## Camera Placement

### Recommended: Chest Mount (Centerline)

The chest or torso centerline position is optimal for vehicle-focused data capture. This placement delivers:

- **Stable optical flow** — minimal handlebar vibration transfer
- **Consistent horizon** — reduces per-frame alignment correction
- **Optimal pitch** — a slight downward angle maximizes the capture of license plates, badges, and grilles while reducing sky overexposure
- **Natural gaze following** — the camera tracks the rider's upper body orientation, which naturally tracks traffic

### Alternative: Helmet or Head Mount

Higher vantage points improve visibility over parked vehicles at intersections and in dense urban parking. However, this position introduces additional rotational jitter from head movement that may reduce crop quality for small or distant vehicles.

### Safety Considerations

Magnetic and clip-based wearable mounts have been documented to detach under rough riding conditions. A secondary mechanical tether (lanyard or carabiner backup) is recommended for all on-road use. Verify that the mount does not obstruct peripheral vision or interfere with helmet fit.

---

## Data Transfer

### Phase 1A — USB Drive Mode (Recommended)

The Insta360 GO 3S supports a native U-Disk / USB Drive Mode that presents the camera as an external storage device when connected via USB-C. Video files are located under `DCIM/Camera01/` following the naming convention `VID*.mp4` for stabilized footage and `PRO*.mp4` for FreeFrame (raw/unprocessed) footage.

For MVP, the pipeline processes only `VID*.mp4` files. FreeFrame support is deferred.

```bash
# One-time directory setup
mkdir -p ~/CurbScout/{raw,derived,exports,models}
```

The ingest daemon automatically detects new files on the mounted drive, computes SHA-256 checksums, performs streaming copy to `~/CurbScout/raw/YYYY-MM-DD/`, and creates corresponding `RIDE` and `VIDEO` records in the local database. Previously imported files (matched by checksum) are silently skipped.

### Phase 1B — Quick Reader Accessory (Optional)

For faster offload without relying on camera Wi-Fi, the Insta360 GO 3S Quick Reader provides an SD-card-style removable media workflow. Retail pricing is approximately **$45 USD**.

---

## Pipeline Stages

The pipeline executes as a sequential, deterministic process. Each stage logs its inputs, outputs, timestamps, and model version for full auditability. Re-processing the same video with the same model version produces identical results.

### Stage 1: Ingest

- Detect mounted Insta360 drive or watch `~/CurbScout/raw/` for new files
- Compute SHA-256 checksum (hardware-accelerated via ARM SHA extensions on M4)
- Streaming copy to `~/CurbScout/raw/YYYY-MM-DD/` (no full-file memory load)
- Validate file integrity via `ffprobe`; quarantine corrupted files to `.partial/`
- Create `RIDE` and `VIDEO` database records

### Stage 2: Frame Sampling

- Extract keyframes at a configurable rate (default: 2 FPS)
- Hardware-accelerated decode via VideoToolbox on macOS, software ffmpeg elsewhere
- At 2 FPS from a 30 FPS source, processing load is 6.7% of raw frames
- A 30-minute ride at 2 FPS yields approximately 3,600 frames
- Output: JPEG keyframes in `~/CurbScout/derived/frames/YYYY-MM-DD/`

### Stage 3: Vehicle Detection

- Run YOLOv8n on each extracted frame
- Backend auto-selected: CoreML ANE (M4), TensorRT (CUDA GPU), ONNX Runtime (CPU)
- Filter detections to vehicle classes only: car, truck, bus, motorcycle
- Store bounding box coordinates, confidence score, and model version
- At ~93 FPS on M4 ANE, 3,600 frames process in approximately 39 seconds

### Stage 4: Crop Generation

- Extract and save individual vehicle crops from detection bounding boxes
- Resize to classifier input dimensions (380×380 for Jordo23, 224×224 for VehicleTypeNet)
- Compute perceptual hash (pHash) for deduplication
- NEON SIMD-accelerated image processing on ARM, AVX2/AVX-512 on x86
- Output: cropped JPEG images in `~/CurbScout/derived/crops/YYYY-MM-DD/`

### Stage 5: Make/Model Classification

- Tiered classification strategy (see [Machine Learning Stack](#machine-learning-stack))
- Primary: Jordo23 EfficientNet-B4 (8,949 classes — make, model, year)
- Fallback: NVIDIA VehicleTypeNet (6 broad types when primary confidence is low)
- Sanity checker flags impossible year/badge combinations for review

### Stage 6: Deduplication

- Consolidate multiple detections of the same physical vehicle into a single `SIGHTING`
- Uses temporal proximity, spatial overlap (IoU), and perceptual hash similarity
- Typical reduction: 500+ raw detections → ≤100 unique sightings per ride

### Stage 7: Persist

- Write all entities to SQLite with WAL mode for concurrent read/write
- Batch inserts in transactions (100–500 rows per transaction)
- Record pipeline run metadata: model versions, processing duration, stage counts

---

## Machine Learning Stack

### Pre-Trained Models (Day 1 — No Training Required)

| Model | Architecture | Classes | Input Size | Dataset | Format | Size |
|:---|:---|:---|:---|:---|:---|:---|
| **YOLOv8n** | YOLO v8 Nano | COCO vehicle classes | 640×640 | COCO | CoreML / ONNX / TensorRT | ~6 MB |
| **Jordo23/vehicle-classifier** | EfficientNet-B4 | 8,949 (make+model+year) | 380×380 | VMMRdb | PyTorch / ONNX / CoreML | ~75 MB |
| **NVIDIA VehicleTypeNet** | ResNet-18 | 6 (sedan/SUV/truck/van/coupe/large) | 224×224 | NVIDIA proprietary | ONNX / TensorRT | ~45 MB |

### Classification Pipeline

```
Detection Crop
    │
    ├── Tier 1: Jordo23 EfficientNet-B4 (8,949 classes)
    │     → make, model, year, confidence
    │     → If confidence ≥ 0.5: accept as primary prediction
    │
    ├── Tier 2: VehicleTypeNet (fallback when Tier 1 < 0.5)
    │     → vehicle type: sedan, SUV, truck, van, coupe, large vehicle
    │     → Stored alongside Tier 1 prediction
    │
    └── Sanity Checker
          → Validate year/badge combinations against lookup table
          → Flag impossible combos (e.g., "BMW 440i 2004" — 4 Series began 2014)
```

### Model Format Matrix

Every model is exported to multiple formats from a single `.pt` source to support all deployment targets:

| Platform | Format | Acceleration | Quantization | Use Case |
|:---|:---|:---|:---|:---|
| M4 Mac mini | `.mlpackage` | CoreML ANE | INT8 | Day-to-day inference |
| Vast.ai GPU | `.engine` | TensorRT + CUDA | FP16 | Batch reprocessing |
| Any x86 CPU | `.onnx` | ONNX Runtime + AVX-512/AVX2 | FP32 | Portable fallback |
| Any ARM CPU | `.onnx` | ONNX Runtime + NEON | FP32 | Portable fallback |

### Training Datasets

| Dataset | Images | Classes | Notes |
|:---|:---|:---|:---|
| **Stanford Cars** | 16,185 | 196 (make+model+year) | High-quality, clean labels |
| **VMMRdb** | 291,752 | 9,170 | Massive, real-world distribution |
| **CompCars (web)** | 136,726 | 1,716 models × 163 makes | Large but noisier |
| **CurbScout corrections** | Growing | Project-specific | User corrections feed active learning |

---

## Hardware Acceleration

CurbScout automatically detects and dispatches computations to the optimal hardware backend at runtime. No manual configuration is required.

### Acceleration Matrix

| Pipeline Stage | M4 Mac mini | Vast.ai GPU Instance | x86 CPU Fallback |
|:---|:---|:---|:---|
| Frame Extraction | VideoToolbox HW decode | ffmpeg (software) | ffmpeg (software) |
| Vehicle Detection | CoreML ANE (INT8) | TensorRT + CUDA (FP16) | ONNX Runtime + AVX-512 |
| Classification | CoreML ANE (INT8) | TensorRT + CUDA (FP16) | ONNX Runtime + AVX2 |
| Image Preprocessing | ARM NEON SIMD | AVX-512 / AVX2 | AVX2 |
| Perceptual Hashing | ARM NEON (FMA + popcount) | AVX-512 VPOPCNTDQ | Scalar |
| SHA-256 Checksum | ARM SHA extensions (10×) | x86 SHA-NI | OpenSSL |
| Model Training | Not supported (too slow) | CUDA + cuDNN + Tensor Cores | Not supported |
| Batch Reprocessing | CoreML ANE (if idle) | CUDA TensorRT (bulk) | ONNX Runtime |

### M4 CoreML Performance Benchmarks

| Model | Format | Compute Unit | Throughput | Latency |
|:---|:---|:---|:---|:---|
| YOLOv8n Detection | CoreML INT8 | ANE | 92.6 FPS | 10.8 ms |
| YOLOv8n Detection | CoreML FP16 | ANE | 78.3 FPS | 12.8 ms |
| YOLOv8n Detection | ONNX FP32 | CPU | 42.1 FPS | 23.7 ms |
| EfficientNet-B4 Classification | CoreML INT8 | ANE | ~350/sec | 2.9 ms |
| EfficientNet-B4 Classification | ONNX FP32 | CPU | ~120/sec | 8.3 ms |
| VehicleTypeNet ResNet-18 | ONNX FP32 | CPU + NEON | ~500/sec | 2.0 ms |

### ARM NEON SIMD Operations

The following operations are automatically vectorized on Apple Silicon through well-maintained library integrations (Pillow, NumPy, OpenCV, imagehash):

| Operation | NEON Intrinsics | Speedup vs. Scalar |
|:---|:---|:---|
| Bilinear image resize | `vld1q_u8`, `vmull_u8`, `vaddq_u16` | 4–8× |
| BGR → RGB channel swap | `vld3q_u8` (deinterleave), `vst3q_u8` | 6× |
| Normalize to [0, 1] | `vcvtq_f32_u32`, `vmulq_f32` | 4× |
| Perceptual hash (DCT) | `vfmaq_f32` (fused multiply-add) | 3–5× |
| Hamming distance | `vcntq_u8` (popcount), `vpaddlq` | 8× |
| SHA-256 checksum | Hardware SHA extensions | 10× |

### AVX-512 / AVX2 on Vast.ai Instances

Vast.ai instances typically run on Intel Xeon or AMD EPYC CPUs with AVX2 (256-bit) and in many cases AVX-512 (512-bit) support. While GPU inference is the primary execution path, CPU-side operations benefit from these SIMD extensions:

- **Image preprocessing**: Batch resize and normalization before GPU inference
- **ONNX Runtime CPU**: Fallback inference with AVX-512 + VNNI acceleration
- **Perceptual hashing**: AVX-512 VPOPCNTDQ processes 16 hash comparisons per instruction
- **Data loading**: AVX2-accelerated memory copy for batch tensor assembly

---

## Vast.ai GPU Infrastructure

CurbScout includes a production-grade GPU fleet orchestration toolkit adapted from battle-tested deployment infrastructure. The toolkit supports fully autonomous operation: provision, train, export, sync, and self-destruct — without manual SSH intervention.

### Training Architecture

```
Local Mac (M4 mini)                    Vast.ai Instance (RTX 4090)
───────────────────                    ────────────────────────────
1. Export labeled dataset               onstart → bootstrap_training.sh
   (corrections → training data)        ├── Install ultralytics + deps
                                        ├── Download dataset from GCS
2. Upload dataset to GCS               ├── Download base model
   gs://curbscout/training/v1/          ├── Fine-tune classifier
                                        │   (Stanford Cars + corrections)
3. Launch Vast.ai instance             ├── Export models:
   vastctl launch                       │   → .mlpackage (CoreML INT8)
                                        │   → .engine (TensorRT FP16)
4. Walk away                           │   → .onnx (universal fallback)
                                        ├── Upload results to GCS
5. Download trained model              └── Auto-destroy instance
   from GCS → ~/CurbScout/models/
```

### CUDA + TensorRT Stack

| Component | Version | Purpose |
|:---|:---|:---|
| **CUDA Toolkit** | 12.4 | GPU compute runtime |
| **cuDNN** | 9.x | Deep learning primitives |
| **TensorRT** | 10.x | Inference optimization (FP16/INT8) |
| **PyTorch** | 2.5.1 | Training framework |
| **Ultralytics** | Latest | YOLOv8 training and export |
| **ONNX Runtime** | Latest | Cross-platform inference |

### GPU Instance Performance

| Task | RTX 4090 | RTX 3090 | M4 CoreML |
|:---|:---|:---|:---|
| YOLOv8n Detection (FP16) | ~320 FPS | ~180 FPS | ~93 FPS |
| YOLOv8n Detection (TensorRT INT8) | ~580 FPS | ~310 FPS | ~93 FPS (ANE INT8) |
| EfficientNet-B4 Classification | ~800/sec | ~450/sec | ~350/sec |
| YOLOv8n-cls Training (per epoch) | ~4 min | ~7 min | ~25 min (MPS) |
| Batch 1,000 Crops Classify | ~1.3 sec | ~2.2 sec | ~2.9 sec |

### Deploy Kit Components

The Vast.ai deploy kit provides end-to-end GPU fleet management:

| Component | Description |
|:---|:---|
| [`bootstrap_training.sh`](.specify/vastai-deploy-kit/scripts/bootstrap_autonomous.sh) | Autonomous instance lifecycle: install → download → train → export → upload → self-destruct |
| [`instant_gcs_sync.sh`](.specify/vastai-deploy-kit/scripts/instant_gcs_sync.sh) | inotifywait-based real-time upload with drain-safe auto-kill |
| [`vast-sync-v4.sh`](.specify/vastai-deploy-kit/scripts/vast-sync-v4.sh) | SSH-based polling sync with metadata and gallery integration |
| [`auto-shutdown.sh`](.specify/vastai-deploy-kit/scripts/auto-shutdown.sh) | Four-phase shutdown: wait → sync → verify → destroy |
| [`ph-autokill.sh`](.specify/vastai-deploy-kit/scripts/ph-autokill.sh) | TTL-based safety guard (12-hour default maximum) |
| [`fleet_poll.py`](.specify/vastai-deploy-kit/scripts/fleet_poll.py) | Vast.ai API poller with fleet status JSON output |

### Go SDK for Fleet Management

A typed Go SDK provides programmatic control over GPU fleet operations:

| Package | Purpose |
|:---|:---|
| `vast/` | Vast.ai REST API client — search offers, launch, list, destroy |
| `ssh/` | SSH client with agent forwarding and port tunneling |
| `config/` | YAML configuration with environment variable overrides |
| `providers/` | Provider-agnostic interface (Vast.ai, RunPod, Lambda Labs) |
| `hwprofile/` | GPU hardware signatures and UCB1 tuning profiles |
| `storage/` | GCS and local filesystem storage abstraction |
| `budget/` | Cost guardrails: daily limits, idle timeouts, auto-destroy |
| `cmd/vastctl/` | CLI tool for fleet operations |

```bash
# Search for cost-effective GPUs
vastctl -gpu RTX_4090 -price 0.50 search

# Launch with automatic boot timeout and SSH tunnel
vastctl -gpu RTX_4090 -price 0.50 -disk 100 -tunnel launch

# List all active instances
vastctl list

# Destroy a specific instance
vastctl destroy <INSTANCE_ID>
```

### Credential Management

All secrets use a layered resolution: **Secret Manager → Environment Variable → Key File**.

| Secret | Environment Variable | Key File |
|:---|:---|:---|
| Vast.ai API Key | `VAST_API_KEY` | `~/.config/curbscout/vast_api_key` |
| HuggingFace Token | `HF_TOKEN` | `~/.config/curbscout/hf_token` |
| GCP Service Account | `GOOGLE_APPLICATION_CREDENTIALS` | `~/.config/curbscout/gcp-sa-key.json` |

---

## Database Schema

CurbScout uses SQLite in WAL (Write-Ahead Logging) mode for concurrent read/write access. The Python pipeline writes detection results while the FastAPI backend simultaneously serves the review UI.

### Entity Relationship Diagram

```mermaid
erDiagram
    RIDE ||--o{ VIDEO : contains
    VIDEO ||--o{ FRAME_ASSET : produces
    FRAME_ASSET ||--o{ DETECTION : yields
    RIDE ||--o{ SIGHTING : has
    SIGHTING ||--o{ DETECTION : consolidates
    SIGHTING ||--o{ CORRECTION : refined_by
    SIGHTING }o--|| FRAME_ASSET : best_crop

    RIDE {
        text id PK
        text start_ts
        text end_ts
        text notes
        boolean reviewed
    }
    VIDEO {
        text id PK
        text ride_id FK
        text file_path
        text checksum_sha256
        real duration_sec
        integer fps
        text resolution
        text status
    }
    FRAME_ASSET {
        text id PK
        text video_id FK
        real video_timestamp_sec
        text kind
        text file_path
        text phash
    }
    DETECTION {
        text id PK
        text frame_asset_id FK
        text sighting_id FK
        text class
        real confidence
        text bbox_json
        text model_ver
    }
    SIGHTING {
        text id PK
        text ride_id FK
        text best_crop_id FK
        text predicted_make
        text predicted_model
        text predicted_year
        real classification_confidence
        text review_status
        boolean deleted
    }
    CORRECTION {
        text id PK
        text sighting_id FK
        text corrected_fields
        text previous_values
        text new_values
        text note
    }
```

### Storage Configuration

| Setting | Value | Rationale |
|:---|:---|:---|
| Journal mode | WAL | Concurrent readers + single writer |
| Foreign keys | Enforced | `PRAGMA foreign_keys = ON` |
| Busy timeout | 5,000 ms | Retry on lock contention |
| Timestamps | ISO 8601 UTC | Consistent, sortable, portable |
| Enums | TEXT | Human-readable, grep-friendly |
| Batch size | 100–500 rows/tx | Balance throughput and memory |

---

## Review Interface

The primary review interface is a SvelteKit 5 web application served locally. It communicates with a FastAPI backend on `localhost:8000` that reads and writes the shared SQLite database.

### Design Principles

- **Dark-mode-first** — `hsl(220, 20%, 8%)` deep-space background with `hsl(220, 18%, 13%)` card surfaces
- **Keyboard-driven** — one-keystroke confirm, type-ahead correction search, arrow navigation
- **Modern typography** — Inter (Google Fonts), 12px border radius, 150ms ease-out transitions
- **Confidence visualization** — mint green for confirmed, amber for low confidence, red for flagged/deleted

### Application Routes

| Route | Purpose |
|:---|:---|
| `/` | Dashboard — ride list with summary statistics |
| `/rides/[rideId]` | Ride detail — sighting grid, video player, map |
| `/rides/[rideId]/review` | Sequential review — one sighting at a time, keyboard-driven |
| `/export/[rideId]` | Export preview — trigger daily bundle generation |
| `/settings` | Configuration — FPS, thresholds, model selection |

### Keyboard Shortcuts

| Key | Action |
|:---|:---|
| `Enter` | Confirm current sighting label |
| `Backspace` / `Delete` | Flag as false positive (soft delete) |
| `↑` / `↓` | Navigate sighting grid |
| `/` | Open correction search dropdown |
| `e` | Export daily bundle |
| `Space` | Play / pause video |

### REST API Endpoints

| Method | Path | Description |
|:---|:---|:---|
| `GET` | `/api/rides` | List rides with pagination |
| `GET` | `/api/rides/{id}` | Ride detail with sightings |
| `GET` | `/api/sightings` | Query sightings with filters |
| `POST` | `/api/sightings/{id}/correct` | Apply make/model correction |
| `POST` | `/api/sightings/{id}/confirm` | Confirm predicted label |
| `POST` | `/api/sightings/{id}/delete` | Soft delete false positive |
| `POST` | `/api/export/{rideId}` | Generate daily export bundle |
| `GET` | `/api/config` | Current pipeline configuration |
| `PUT` | `/api/config` | Update pipeline settings |

---

## Export System

### Bundle Structure

```
~/CurbScout/exports/2026-02-21/
├── sightings.jsonl          # One JSON object per sighting
├── sightings.csv            # Flat tabular format
├── crops/                   # Referenced vehicle crop images
│   ├── sighting_001.jpg
│   ├── sighting_002.jpg
│   └── ...
└── index.html               # Self-contained report (inline CSS/JS)
```

### JSONL Record Schema

Each line in `sightings.jsonl` contains a complete sighting record:

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

### Cloud Sync Strategy

The daily bundle is designed for bandwidth-constrained uplinks:

| Artifact | Typical Size | Included in Sync |
|:---|:---|:---|
| Raw 4K MP4 footage | 8–15 GB per ride | Never (local only) |
| Structured metadata (JSONL + CSV) | 50–200 KB | Always |
| Cropped thumbnails | 5–20 MB per ride | Always |
| Highlight clips | 10–50 MB per ride | Optional |
| HTML summary report | 100–500 KB | Always |
| **Total sync payload** | **~15–70 MB per ride** | — |

---

## File System Layout

```
~/CurbScout/
├── curbscout.db                   # SQLite database (WAL mode)
├── curbscout.db-wal               # WAL file (auto-managed)
├── curbscout.db-shm               # Shared memory (auto-managed)
│
├── raw/                           # Raw MP4 files (organized by date)
│   ├── 2026-02-21/
│   │   ├── VID_20260221_143000.mp4
│   │   └── VID_20260221_150000.mp4
│   └── .partial/                  # Quarantine for incomplete transfers
│
├── derived/                       # Pipeline outputs
│   ├── frames/                    # Extracted keyframes
│   │   └── 2026-02-21/
│   └── crops/                     # Cropped vehicle images
│       └── 2026-02-21/
│
├── exports/                       # Daily report bundles
│   └── 2026-02-21/
│       ├── sightings.jsonl
│       ├── sightings.csv
│       ├── crops/
│       └── index.html
│
└── models/                        # ML model files
    ├── yolov8n.mlpackage/         # CoreML INT8 (M4 ANE)
    ├── yolov8n.engine             # TensorRT FP16 (Vast.ai)
    ├── yolov8n.onnx               # ONNX FP32 (universal)
    ├── jordo23-b4.onnx            # Jordo23 classifier
    └── sanity_check.json          # Year/badge validity table
```

---

## Vehicle Recognition

### Scope and Expectations

The MVP targets high reliability for **common vehicle profiles** — "BMW 3 Series," "Honda Civic," "Toyota Camry." These represent the majority of sightings in typical urban cycling footage.

| Classification Level | MVP Accuracy | Method |
|:---|:---|:---|
| **Vehicle vs. non-vehicle** | ≥ 95% | YOLOv8n COCO |
| **Make + model** | ≥ 70% top-1 (clear crops) | Jordo23 EfficientNet-B4 |
| **Vehicle type** | ≥ 85% | NVIDIA VehicleTypeNet (fallback) |
| **Year / trim** | Best-effort | Classifier with sanity checker |

Exact year, trim level, and equipment package identification is frequently not resolvable from street-level footage due to occlusion, angle, lighting, and badge removal. These fields are treated as best-effort predictions subject to human correction and future fine-tuning.

### Sanity Checking

A deterministic validation layer cross-references classified make/model/year combinations against a lookup table of production dates. Detections flagged with impossible combinations (e.g., a "BMW 440i" classified as year 2004 when the 4 Series was not produced until 2014) are automatically surfaced for human review.

---

## Deduplication Strategy

At a 2 FPS sampling rate, a vehicle visible for 10 seconds generates approximately 20 raw detections. Without deduplication, a typical 30-minute ride would produce hundreds of redundant entries.

### Three-Layer Approach

| Layer | Method | Threshold | Description |
|:---|:---|:---|:---|
| **Temporal** | Time-window grouping | 5.0 sec | Same make/model within sliding window → merge |
| **Spatial** | IoU overlap | > 0.3 | Bounding box intersection across adjacent frames → merge |
| **Appearance** | Perceptual hash | Hamming < 10 | Visual similarity of crop images → merge |

All thresholds are user-configurable. Full multi-object tracking (ByteTrack, BoT-SORT) was evaluated and deferred — at 2 FPS, inter-frame optical flow is unreliable, and the lightweight temporal + spatial + appearance heuristic provides sufficient accuracy with dramatically lower implementation complexity.

---

## Security and Privacy

### Local-First Data Residency

Raw video footage never leaves the local machine unless the user explicitly opts in to cloud sync. The pipeline's default configuration stores all raw MP4 files, derived keyframes, cropped images, and the SQLite database exclusively on the origin device.

### Privacy-Sensitive Data Handling

| Data Type | Default Treatment | Clear-Text Access |
|:---|:---|:---|
| License plate text (if OCR enabled) | SHA-256 hashed/tokenized | Requires explicit opt-in |
| Face detections (incidental) | Not stored; discarded at detection | N/A |
| GPS coordinates (if paired) | Stored locally only | Not synced by default |
| Raw video footage | Local filesystem only | Never synced unless user overrides |

### Supply Chain Security

- Python dependencies pinned and audited (`pip audit`)
- SvelteKit dependencies follow `npm audit` best practices
- ML models loaded from verified sources (NGC Catalog, HuggingFace)
- No runtime model fetching from untrusted sources without verification

---

## Roadmap

### Phase 1 — Local Pipeline MVP *(current)*

USB Drive/U-Disk local transfer to Mac. Folder watcher daemon for automated ingest. Full perception pipeline: frame sampling, YOLOv8 detection, tiered make/model classification, temporal+spatial deduplication, SQLite persistence. SvelteKit review UI served on localhost with keyboard-driven correction. FastAPI REST backend. Daily export bundles in JSONL, CSV, and self-contained HTML.

### Phase 2 — Autoupload Behaviors

Configurable cloud sync for derived artifacts. Three modes under evaluation:
- **Home Wi-Fi only** — batch upload overnight on residential network
- **Opportunistic** — JSON metadata via cellular hotspot, defer clips for Wi-Fi
- **As-you-ride** — aggressive queued upload (battery and bandwidth tradeoff)

### Phase 3 — Analytics Dashboard

Deploy the SvelteKit application to Vercel or Cloudflare Pages for remote browsing. Integrate Mapbox GL or Leaflet for sighting heatmaps. Time-of-day patterns, make/model frequency analytics. Optional authentication via Cloudflare Access.

### Phase 4 — Active Learning via Vast.ai

Export corrected labels from CurbScout database. Upload curated datasets to GCS. Fine-tune YOLOv8n-cls on Stanford Cars + CurbScout corrections on RTX 4090 instances. A/B test new model against Jordo23 baseline. Auto-export to CoreML, ONNX, and TensorRT. Model versioning with training data hash.

### Phase 5 — Native macOS Application

Port the SvelteKit review UI to a native SwiftUI application. SwiftData persistence layer reading the shared SQLite database. Native AVFoundation video scrubber. Menu bar status indicator for pipeline progress. Auto-launch on camera connection via IOKit/DiskArbitration.

### Phase 6 — Curb Intelligence

- **6A: Parking Sign OCR** — YOLOv8 sign detector + PaddleOCR for text extraction. Parse time windows and restrictions. Santa Monica municipal code integration for "can I park here?"
- **6B: Hazard Mapping** — bike lane obstructions, potholes, construction zones. Temporal change detection across rides on the same route.
- **6C: Storefront OCR** — track business changes on frequently ridden routes.

All curb intelligence modules reuse the existing event timeline, evidence asset, and human correction database architecture.

### Phase 7 — Active Learning Loop

Automated correction-to-training pipeline: user corrections auto-queue for the next training batch. Semi-automated Vast.ai training runs. Model versioning with data lineage tracking.

### Phase 8 — Multi-Device Collaboration

Database sync across multiple Macs via CRDTs or SQLite changeset extension. Multiple riders contributing to a shared sighting dataset. Multi-user dashboard views with per-user review progress.

---

## Cost Analysis

### Local Pipeline (Phase 1)

| Item | Cost | Frequency |
|:---|:---|:---|
| M4 Mac mini (24 GB) | Existing hardware | One-time |
| Insta360 GO 3S | ~$330 | One-time |
| Quick Reader (optional) | ~$45 | One-time |
| Electricity (~10W idle) | ~$1/month | Ongoing |
| **Total Phase 1** | **~$0/month ongoing** | — |

### GPU Training (Phase 4+)

| GPU | Hourly Rate | Time per Training Run | Cost per Run |
|:---|:---|:---|:---|
| RTX 4090 | $0.27–0.40 | 2–3 hours | **$0.80–1.20** |
| RTX 3090 | $0.11–0.16 | 4–5 hours | **$0.55–0.80** |
| A100 80 GB | $0.50–0.80 | 1.5–2 hours | **$1.00–1.60** |

### Cloud Storage (Phase 2+)

| Provider | Tier | Monthly Estimate |
|:---|:---|:---|
| GCS Standard | ~5 GB derived artifacts | ~$0.10/month |
| DigitalOcean Spaces | ~5 GB derived artifacts | ~$5/month (includes CDN) |

---

## Specification Kit

CurbScout uses a spec-driven development methodology via GitHub Spec Kit. Feature development follows a structured lifecycle: specification → research → planning → task breakdown → implementation → validation.

```bash
uvx --from git+https://github.com/github/spec-kit.git specify init curbscout
```

All design artifacts are maintained under `.specify/`:

| Artifact | Path | Purpose |
|:---|:---|:---|
| Constitution | `.specify/memory/constitution.md` | Core development principles and governance |
| Feature Spec | `.specify/specs/001-local-pipeline-mvp/spec.md` | Requirements and acceptance criteria |
| Research | `.specify/specs/001-local-pipeline-mvp/research.md` | Technology evaluation and model catalog |
| Implementation Plan | `.specify/specs/001-local-pipeline-mvp/plan.md` | Technical design and project structure |
| Task Breakdown | `.specify/specs/001-local-pipeline-mvp/tasks.md` | Dependency-ordered implementation tasks |
| Acceleration | `.specify/specs/001-local-pipeline-mvp/acceleration.md` | Hardware acceleration and Vast.ai strategy |
| Data Model | `.specify/specs/001-local-pipeline-mvp/data-model.md` | SQLite schema and file system layout |
| Quickstart | `.specify/specs/001-local-pipeline-mvp/quickstart.md` | Developer setup guide |
| Vast.ai Deploy Kit | `.specify/vastai-deploy-kit/` | GPU fleet orchestration toolkit |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development environment setup, coding standards, and pull request guidelines.

## License

This project is licensed under the [Blue Oak Model License 1.0.0](LICENSE.md). See <https://blueoakcouncil.org/license/1.0.0> for the full text.

---

<div align="center">
<br/>
<sub>Maintained by <a href="https://github.com/ParkWardRR">ParkWardRR</a></sub>
</div>
