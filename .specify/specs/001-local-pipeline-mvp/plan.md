# Implementation Plan: Local Pipeline MVP

**Branch**: `001-local-pipeline-mvp` | **Date**: 2026-02-21 (updated) | **Status**: Approved
**Spec**: `specs/001-local-pipeline-mvp/spec.md`

## Summary

Build a local-first Python ML pipeline + SvelteKit web UI that ingests
Insta360 GO 3S bike ride footage via USB, detects and classifies
vehicles using pre-trained models (Jordo23/vehicle-classifier +
NVIDIA VehicleTypeNet), deduplicates sightings, stores everything in
SQLite, and provides a premium dark-mode SvelteKit review UI on
localhost with keyboard-driven correction. A FastAPI backend bridges
the Python pipeline and the web frontend. Daily export bundles
(JSONL + CSV + crops + HTML) complete the MVP. Everything runs
offline on an M4 Mac mini. SwiftUI native app is deferred to Phase 8.

## Technical Context

**Language/Version**: Python 3.11+ (pipeline + FastAPI backend), TypeScript/Svelte 5 (web UI)
**Primary Dependencies**: FastAPI, uvicorn, ultralytics, onnxruntime, coremltools, ffmpeg-python, Pillow, imagehash, pydantic (Python); SvelteKit 5, @sveltejs/adapter-node, video.js (frontend)
**Storage**: SQLite 3 with WAL mode at `~/CurbScout/curbscout.db`
**Testing**: pytest (Python), vitest + Playwright (SvelteKit)
**Target Platform**: macOS 14+ (Sonoma), M-series Apple Silicon; web UI runs in any modern browser
**Project Type**: CLI pipeline + REST API + web app (all local)
**Performance Goals**: Process 30-min ride in <10 min; detection at ~90 fps; review at <5 min for 100 sightings
**Constraints**: Offline-only, <24 GB memory, coax uplink (no cloud dependency in MVP)
**Scale/Scope**: Single user, ~1-3 rides/day, ~100-500 sightings/ride

## Constitution Check

*GATE: All principles verified ✅ (constitution v2.0.0)*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Local-First | ✅ | All processing on M4; no cloud in MVP |
| II. Privacy-by-Default | ✅ | No plate OCR in MVP; raw video stays local |
| III. Web-First, Beautiful UX | ✅ | SvelteKit is primary UI, dark-mode, keyboard-driven |
| IV. Solo-Developer Pragmatism | ✅ | SQLite, shell scripts, flat exports, no native app yet |
| V. Pipeline Correctness | ✅ | Checksums, model versioning, idempotent runs |
| VI. Incremental Delivery | ✅ | Phase 1 is self-contained, no cloud deps |
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
| Python-only backend (no Swift) | SvelteKit UI replaces SwiftUI; entire backend is Python | Swift would require maintaining two codebases for the same DB |
| FastAPI for REST API | Lightweight, async, auto-docs, excellent DX | Flask works but lacks async + auto OpenAPI docs |
| Three pre-trained models | Tiered classification maximizes Day 1 accuracy | Single model would miss vehicle types when make/model confidence is low |
| SvelteKit 5 | Svelte 5 runes for modern reactivity; reusable for Phase 3 cloud dashboard | React/Next.js is heavier and slower to iterate for a solo dev |
| Multi-backend accelerator | Auto-detect CoreML/CUDA/AVX-512/NEON at runtime | Hardcoding one backend would break on Vast.ai or non-Mac platforms |
| CoreML INT8 quantization | 38 TOPS on M4 ANE; 30% faster than FP16 | FP16 works but leaves ANE INT8 path underutilized |
| Vast.ai training (PromptHarbor kit) | Proven autonomous deploy: bootstrap→train→export→self-destruct | Manual SSH is error-prone; autonomous saves time and prevents cost overruns |
| Multi-format model export | CoreML+ONNX+TensorRT from single .pt | Single format would limit platform portability |
