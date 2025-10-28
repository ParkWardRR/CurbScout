<!-- Sync Impact Report
  Version change: 1.0.0 → 2.1.0
  Modified principles:
    - III. Apple-Beautiful UX → III. Web-First, Beautiful UX (MAJOR: UI platform change)
  Added sections:
    - VIII. Hardware Acceleration Maximalism (multi-backend strategy)
  Removed sections: None
  Templates requiring updates:
    - .specify/specs/001-local-pipeline-mvp/spec.md ⚠️ updated
    - .specify/specs/001-local-pipeline-mvp/plan.md ⚠️ updated
    - .specify/specs/001-local-pipeline-mvp/research.md ⚠️ updated
    - .specify/specs/001-local-pipeline-mvp/tasks.md ⚠️ updated
  Follow-up TODOs: None
-->

# CurbScout Constitution

## Core Principles

### I. Local-First Architecture

All raw data (video, frames, crops, database) MUST remain on the
local machine (M4 Mac mini) by default. Cloud sync is opt-in and only
for derived artifacts (JSON, thumbnails, highlight clips). Raw 4K
video MUST NOT leave the machine unless the user explicitly overrides.
This preserves bandwidth on constrained coax uplink, minimizes cloud
cost, and keeps latency for the review loop near zero.

### II. Privacy-by-Default

License plates, faces, and personally identifiable features detected
in video MUST be handled with sensitivity. If plate OCR is added for
deduplication, raw plate text MUST be hashed/tokenized by default;
clear-text storage is opt-in. No telemetry or analytics data leaves
the device without explicit user consent. Raw video never syncs to
cloud unless the user opts in.

### III. Web-First, Beautiful UX

The primary user interface is a **SvelteKit web application**
served locally on `localhost`. It MUST feel premium — polished
typography, smooth animations, dark-mode-first palette, keyboard-
driven review flow (one-keystroke confirm/correct). The web UI
runs in the user's browser but communicates with a local Python
API serving data from SQLite. A native SwiftUI macOS app is a
future enhancement (later phases), not an MVP requirement.
SvelteKit was chosen because it ships faster for a solo developer,
runs cross-platform, and reuses the web dashboard planned for
later cloud-hosted analytics.

### IV. Solo-Developer Pragmatism (YAGNI)

This is a solo project. Every architecture choice MUST justify its
complexity against "could I ship this with a simpler approach?"
Prefer SQLite over Postgres, shell scripts over orchestrators, direct
function calls over message buses, flat file exports over complex APIs.
Scale decisions (multi-user, multi-device) are deferred to later phases.

### V. Pipeline Correctness Over Speed

The perception pipeline (ingest → detect → classify → dedupe → persist)
MUST be deterministic and auditable. Every stage MUST log its inputs,
outputs, and model version. Re-processing the same video MUST yield
identical results given the same model version. Checksums MUST be
computed at ingest time. Idempotent re-runs MUST NOT corrupt state.

### VI. Incremental Delivery

Features ship in thin vertical slices: Phase 1 (local transfer + pipeline
+ review UI) is self-contained and useful without any cloud dependency.
Each subsequent phase (autoupload, dashboard, training loop, curb
intelligence) adds value independently. No phase depends on a future
phase's infrastructure.

### VII. Test-Driven Core Logic

Business-critical logic (deduplication, classification confidence
thresholds, sanity checks for impossible year/badge combos, database
migrations) MUST have automated tests. UI and pipeline integration may
use manual verification initially, but core functions follow
Red → Green → Refactor.

### VIII. Hardware Acceleration Maximalism

Every compute-heavy operation MUST use the best available hardware
accelerator.
- **M4 Mac mini**: CoreML Neural Engine (38 TOPS INT8) for detection
  and classification; ARM NEON SIMD for image processing and hashing;
  VideoToolbox for hardware video decode; Accelerate.framework (vecLib)
  for NumPy/BLAS operations.
- **Vast.ai GPU (CUDA)**: TensorRT FP16/INT8 for bulk inference and
  batch reprocessing; CUDA + cuDNN for model training; AVX-512/AVX2
  on host CPU for data preprocessing.
- **Universal**: ONNX Runtime as cross-platform fallback, automatically
  leveraging oneDNN (AVX-512), NEON, or scalar as available.
- Runtime auto-detection via `accelerator.py` — no hardcoded backends.
- Model exports MUST target all 3 formats: CoreML INT8, ONNX FP32,
  TensorRT FP16.

## Hardware & Infrastructure Constraints

- **Compute**: M4 Mac mini (24 GB unified memory) is the always-on
  factory for ingest, inference, and review.
- **Capture**: Insta360 GO 3S + Action Pod; ~38 min camera-only,
  ~140 min with Action Pod.
- **Cloud (later)**: GCP / DigitalOcean object storage for derived
  artifacts only; no always-on GPU instances.
- **Burst GPU (later)**: Vast.ai for training and large batch jobs;
  on-demand only, budgeted hourly.
- **Uplink**: Coax internet — upload-constrained; design the sync
  budget around derived artifacts (~MBs) not raw video (~GBs).

## Development Workflow

- **Language/Stack**: Python 3.11+ for pipeline + API backend;
  SvelteKit 5 (Svelte 5 with runes) for the review UI; SQLite
  (direct sqlite3 from Python) for persistence; ffmpeg for video
  processing; shell scripts for automation. Swift/SwiftUI is
  deferred to a later phase.
- **Source Control**: Git, single `main` branch with feature branches.
  Commit after each logical task.
- **Linting**: Ruff for Python, eslint + prettier for Svelte/JS,
  shellcheck for Bash scripts.
- **CI**: GitHub Actions for lint + test on push (later phase).
- **Packaging**: Python pipeline + API via `uv` virtual environment
  with pinned deps; SvelteKit UI via `npm run dev` locally or
  `adapter-node` for deployment; no native macOS app in MVP.

## Governance

This constitution is the highest-authority development guide for
CurbScout. All design decisions, code reviews, and architecture
proposals MUST be evaluated against these principles. Amendments
require:

1. A written proposal documenting the change, rationale, and impact.
2. An updated version number following semver:
   - MAJOR: principle removal or backward-incompatible redefinition.
   - MINOR: new principle or materially expanded guidance.
   - PATCH: clarifications, wording, or typo fixes.
3. A migration plan if the amendment invalidates existing code or data.

**Version**: 2.1.0 | **Ratified**: 2026-02-21 | **Last Amended**: 2026-02-21
