# Implementation Plan: Local Pipeline MVP

**Branch**: `001-local-pipeline-mvp` | **Date**: 2026-02-21 (updated) | **Status**: Approved
**Spec**: `specs/001-local-pipeline-mvp/spec.md`

## Summary

Build a three-tier perception system with **GCP as the central
orchestration hub**, an M4 Mac mini as the local inference worker,
and Vast.ai as an ephemeral GPU burst tier.

The GCP layer (Cloud Run + Firestore + GCS + Cloud Tasks) hosts
the always-on SvelteKit dashboard and job orchestration API. It
dispatches inference jobs to the M4 Mac mini (CoreML ANE, free)
and training/batch jobs to Vast.ai GPU instances (ephemeral,
auto-destroying). The M4 Mac mini runs the perception pipeline
locally — ingesting Insta360 GO 3S footage, detecting and
classifying vehicles via CoreML — and pushes results back to GCP.
When the user wants to train or reprocess at scale, the M4 or
the dashboard pushes a job to GCP, which provisions an ephemeral
Vast.ai instance, monitors it, and tears it down when complete.

**Build order**: GCP orchestration layer first (dashboard +
job dispatch + Firestore schema). Then M4 pipeline and Vast.ai
worker in parallel, both reporting to GCP.

SwiftUI native app is deferred to Phase 8.

## Technical Context

**Language/Version**: Python 3.11+ (pipeline + FastAPI), TypeScript/Svelte 5 (dashboard)
**Primary Dependencies**: FastAPI, uvicorn, ultralytics, onnxruntime, coremltools, ffmpeg-python, Pillow, imagehash, pydantic (Python); SvelteKit 5, @sveltejs/adapter-node, video.js (frontend); google-cloud-firestore, google-cloud-storage, google-cloud-tasks (orchestration)
**Local Storage**: SQLite 3 with WAL mode at `~/CurbScout/curbscout.db`
**Cloud Storage**: GCS for artifacts + Firestore for metadata + Cloud Tasks for job queue
**Hosting**: GCP Cloud Run (dashboard + orchestration API — always accessible)
**Testing**: pytest (Python), vitest + Playwright (SvelteKit)
**Target Platform**: macOS 14+ M-series (M4 worker); GCP Cloud Run (orchestrator); Vast.ai CUDA (ephemeral GPU worker)
**Project Type**: Orchestrated multi-tier: GCP hub + local worker (M4) + burst worker (Vast.ai)
**Performance Goals**: Process 30-min ride in <10 min on M4; detection at ~93 fps CoreML; review at <5 min for 100 sightings
**Constraints**: Raw video never leaves M4; GCP free tier; Vast.ai ephemeral (auto-destroy)
**Cost Posture**: CoreML inference free (owned hardware); GCP within free tier; Vast.ai on-demand only ($0 when idle)
**Build Order**: GCP orchestration first → M4 pipeline + Vast.ai worker in parallel

## Constitution Check

*GATE: All principles verified ✅ (constitution v2.0.0)*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Local-First | ✅ | Raw video + inference on M4; only derived artifacts flow to GCP |
| II. Privacy-by-Default | ✅ | No plate OCR in MVP; raw video never leaves M4 |
| III. Web-First, Beautiful UX | ✅ | SvelteKit on GCP Cloud Run — always accessible, orchestrates all tiers |
| IV. Solo-Developer Pragmatism | ✅ | GCP free tier, Cloud Tasks for job dispatch, Firestore for state |
| V. Pipeline Correctness | ✅ | Checksums, model versioning, idempotent runs, job deduplication |
| VI. Incremental Delivery | ✅ | GCP first → M4 + Vast.ai in parallel |
| VII. Test-Driven Core | ✅ | Pytest for pipeline logic, vitest for UI |

## Project Structure

### Documentation (this feature)

```text
.specify/specs/001-local-pipeline-mvp/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Technology research + model catalog
├── acceleration.md      # Hardware acceleration & Vast.ai deploy kit
├── data-model.md        # Database schema & file layout
├── quickstart.md        # Getting started guide
└── tasks.md             # Task breakdown
```

### Source Code (repository root)

```text
CurbScout/
├── readme.md                    # Project overview
├── .specify/                    # Spec Kit artifacts
│
├── pipeline/                    # Python ML pipeline + API
│   ├── pyproject.toml           # Python project config (uv)
│   ├── curbscout/
│   │   ├── __init__.py
│   │   ├── cli.py               # CLI entry point (Click)
│   │   ├── config.py            # Configuration management
│   │   ├── ingest.py            # Video import & checksum
│   │   ├── sampler.py           # Frame extraction (ffmpeg)
│   │   ├── detector.py          # Vehicle detection (YOLOv8)
│   │   ├── classifier.py        # Make/model classification (tiered)
│   │   ├── deduplicator.py      # Sighting consolidation
│   │   ├── sanity.py            # Year/badge sanity checker
│   │   ├── exporter.py          # Bundle generation
│   │   ├── db.py                # SQLite operations
│   │   ├── models.py            # Pydantic data models
│   │   ├── api.py               # FastAPI REST API server
│   │   ├── accelerator.py       # Multi-backend detection (CoreML/CUDA/AVX/NEON)
│   │   └── vast_client.py       # Vast.ai API client (training launch)
│   ├── data/
│   │   └── sanity_check.json    # Make/model/year lookup
│   └── tests/
│       ├── test_accelerator.py
│       ├── test_vast_client.py
│       ├── conftest.py
│       ├── test_ingest.py
│       ├── test_sampler.py
│       ├── test_detector.py
│       ├── test_classifier.py
│       ├── test_deduplicator.py
│       ├── test_sanity.py
│       ├── test_exporter.py
│       ├── test_db.py
│       └── test_api.py
│
├── web/                         # SvelteKit review UI
│   ├── package.json
│   ├── svelte.config.js
│   ├── vite.config.ts
│   ├── tsconfig.json
│   ├── src/
│   │   ├── app.html
│   │   ├── app.css              # Global styles + design tokens
│   │   ├── lib/
│   │   │   ├── api.ts           # FastAPI client
│   │   │   ├── types.ts         # TypeScript types matching Pydantic models
│   │   │   ├── stores.ts        # Svelte 5 runes-based stores
│   │   │   └── shortcuts.ts     # Keyboard shortcut handler
│   │   ├── components/
│   │   │   ├── SightingCard.svelte
│   │   │   ├── SightingGrid.svelte
│   │   │   ├── VideoPlayer.svelte
│   │   │   ├── TimelineScrubber.svelte
│   │   │   ├── CorrectionModal.svelte
│   │   │   ├── ConfidenceBadge.svelte
│   │   │   ├── SanityWarning.svelte
│   │   │   ├── ReviewProgress.svelte
│   │   │   └── SearchDropdown.svelte
│   │   └── routes/
│   │       ├── +layout.svelte   # App shell (sidebar + content)
│   │       ├── +page.svelte     # Dashboard / ride list
│   │       ├── rides/
│   │       │   └── [rideId]/
│   │       │       ├── +page.svelte    # Ride detail + sighting grid
│   │       │       └── review/
│   │       │           └── +page.svelte # Sequential review mode
│   │       ├── export/
│   │       │   └── [rideId]/
│   │       │       └── +page.svelte    # Export preview
│   │       └── settings/
│   │           └── +page.svelte        # Config editor
│   └── static/
│       └── favicon.svg
│
├── deploy/                      # Vast.ai training infrastructure
│   ├── bootstrap_training.sh    # Instance setup + train + export + self-destruct
│   ├── training_sync.sh         # Upload checkpoints/metrics to GCS
│   ├── training_poll.py         # Monitor training from local Mac
│   ├── training_autokill.sh     # TTL safety guard (12hr max)
│   └── export_all_formats.sh    # Convert .pt → CoreML + ONNX + TensorRT
│
├── scripts/                     # Automation scripts
│   ├── setup.sh                 # One-time project setup
│   ├── run-pipeline.sh          # Execute full pipeline on new rides
│   ├── start.sh                 # Start both API + web dev server
│   ├── watch-usb.sh             # Watch for camera USB mount
│   └── benchmark_accel.sh       # Benchmark all backends (CoreML/ONNX/CUDA)
│
└── models/                      # ML model files (git-lfs or .gitignore'd)
    ├── .gitkeep
    ├── README.md                # Model download instructions
    └── formats/                 # Multi-format exports
        ├── yolov8n.mlpackage/   # CoreML INT8 (M4 ANE)
        ├── yolov8n.engine       # TensorRT FP16 (Vast.ai GPU)
        └── yolov8n.onnx         # ONNX FP32 (universal)
```

**Structure Decision**: Python monorepo — `pipeline/` contains both the ML
pipeline CLI and the FastAPI REST API (in `api.py`). `web/` is a standalone
SvelteKit project. They communicate via REST on localhost. Shared SQLite DB
at `~/CurbScout/curbscout.db`. Automation scripts in `scripts/` orchestrate
both processes. `deploy/` contains Vast.ai training infrastructure adapted
from PromptHarbor's proven autonomous deploy kit.

## Pre-Trained Model Strategy

### Day 1 (No Training Required)

| Model | Purpose | Source | Size |
|-------|---------|--------|------|
| YOLOv8n | Vehicle detection (bbox) | ultralytics (COCO pre-trained) | ~6 MB |
| Jordo23/vehicle-classifier | Make/model/year (8,949 classes) | HuggingFace | ~75 MB (.pth) |
| NVIDIA VehicleTypeNet | Vehicle type fallback (6 types) | NGC Catalog | ~45 MB (.onnx) |

### Future (Phase 4 — Vast.ai Training)

| Model | Purpose | Training Data | GPU | Format Exports |
|-------|---------|---------------|-----|---------------|
| YOLOv8n-cls fine-tuned | CurbScout make/model | Stanford Cars + corrections | RTX 4090 | CoreML INT8 + ONNX + TensorRT |

### Model Format Strategy (All Platforms)

| Platform | Format | Acceleration | Use |
|----------|--------|-------------|-----|
| M4 Mac mini | `.mlpackage` INT8 | CoreML ANE (38 TOPS) | Day-to-day inference |
| Vast.ai GPU | `.engine` FP16 | TensorRT + CUDA | Bulk batch reprocessing |
| Any x86 CPU | `.onnx` FP32 | AVX-512/AVX2 + oneDNN | Portable fallback |
| Any ARM CPU | `.onnx` FP32 | NEON SIMD | Portable fallback |

## Complexity Tracking

> No Constitution Check violations — no justifications needed.

| Decision | Rationale | Simpler Alternative Rejected Because |
|----------|-----------|--------------------------------------|
| GCP as orchestration hub | Central control plane dispatches to M4 + Vast.ai; always accessible | Running orchestration on M4 means no access when Mac is off/sleeping |
| GCP first, then workers | Dashboard + job API is the control plane; workers plug in after | Building workers first means no way to dispatch or monitor them |
| Cloud Tasks for job queue | Free tier, durable, retries, exactly-once dispatch | Direct HTTP calls would lose jobs on worker downtime |
| Python-only backend (no Swift) | SvelteKit UI replaces SwiftUI; entire backend is Python | Swift would require maintaining two codebases for the same DB |
| FastAPI for REST API | Lightweight, async, auto-docs, excellent DX | Flask works but lacks async + auto OpenAPI docs |
| Three pre-trained models | Tiered classification maximizes Day 1 accuracy | Single model would miss vehicle types when make/model confidence is low |
| SvelteKit 5 | Svelte 5 runes for modern reactivity; reusable across GCP + local dev | React/Next.js is heavier and slower to iterate for a solo dev |
| Multi-backend accelerator | Auto-detect CoreML/CUDA/AVX-512/NEON at runtime | Hardcoding one backend would break on Vast.ai or non-Mac platforms |
| CoreML INT8 quantization | 38 TOPS on M4 ANE; 30% faster than FP16 | FP16 works but leaves ANE INT8 path underutilized |
| Vast.ai ephemeral (auto-destroy) | Proven autonomous deploy: bootstrap→train→export→self-destruct→$0 | Persistent GPU instances would burn $ 24/7 |
| Multi-format model export | CoreML+ONNX+TensorRT from single .pt | Single format would limit platform portability |
