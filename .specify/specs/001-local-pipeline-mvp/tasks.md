# Tasks: Local Pipeline MVP

**Input**: Design documents from `/specs/001-local-pipeline-mvp/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

**Tests**: Tests included for core pipeline logic (pytest) and API (pytest + httpx). UI tests deferred to Phase 10 polish.

**Organization**: Tasks grouped by user story for independent implementation and testing.
**Hardware**: See `acceleration.md` for full CoreML/CUDA/AVX-512/NEON strategy.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project scaffolding, tooling, dependencies.

- [ ] T001 Create Python project `pipeline/pyproject.toml` with uv. Dependencies: fastapi, uvicorn[standard], ultralytics>=8.0, onnxruntime, coremltools, ffmpeg-python, Pillow, imagehash, pydantic>=2.0, click, aiosqlite, httpx, pytest, pytest-asyncio, ruff
- [ ] T002 [P] Create SvelteKit project `web/` using `npx -y sv create` with Svelte 5, TypeScript, adapter-node. Add dev dependencies: @sveltejs/adapter-node, video.js
- [ ] T003 [P] Create `scripts/setup.sh` — installs Python deps via uv, creates `~/CurbScout/{raw,derived/frames,derived/crops,exports,models}`, runs `npm install` in web/, downloads models if missing
- [ ] T004 [P] Create `scripts/start.sh` — starts FastAPI on :8000 (`uvicorn curbscout.api:app`) + SvelteKit dev server on :5173 (`npm run dev`) in parallel, with trap for cleanup
- [ ] T005 [P] Create `.gitignore` — exclude `*.mlmodel`, `*.pt`, `*.onnx`, `~/CurbScout/`, `.venv/`, `__pycache__/`, `*.db*`, `node_modules/`, `.svelte-kit/`, build artifacts
- [ ] T006 [P] Configure Ruff (`pipeline/ruff.toml`) and ESLint + Prettier (`web/.eslintrc.cjs`, `web/.prettierrc`)

**Checkpoint**: Both Python and SvelteKit projects runnable independently. `scripts/start.sh` launches both servers.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Database schema, data models, API skeleton, model downloads.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T007 Create Python Pydantic data models in `pipeline/curbscout/models.py` — Ride, Video, FrameAsset, Detection, Sighting, Correction (matching data-model.md)
- [ ] T008 Create `pipeline/curbscout/db.py` — create_tables(), WAL mode, connection factory with busy_timeout=5000, schema_version check
- [ ] T009 [P] Create `pipeline/curbscout/schema.sql` — all CREATE TABLE + CREATE INDEX from data-model.md
- [ ] T010 [P] Create `pipeline/curbscout/config.py` — load from `~/.curbscout/config.toml`, defaults for paths, sampling rate, thresholds, model paths, API port
- [ ] T011 [P] Create `models/README.md` — download instructions for all 3 pre-trained models:
  - YOLOv8n: `pip install ultralytics && yolo export model=yolov8n.pt format=coreml`
  - Jordo23/vehicle-classifier: `huggingface-cli download Jordo23/vehicle-classifier`
  - NVIDIA VehicleTypeNet: `ngc registry model download-version nvidia/tao/vehicletypenet:pruned_onnx_v1.1.0`
- [ ] T012 [P] Create `pipeline/data/sanity_check.json` — top 60 make/model production year ranges
- [ ] T013 Create `pipeline/curbscout/api.py` — FastAPI app skeleton with CORS middleware, static file serving for crops/video, health check endpoint, SQLite connection lifecycle
- [ ] T014 [P] Create `web/src/lib/types.ts` — TypeScript interfaces matching Pydantic models: Ride, Video, Sighting, Correction, Config
- [ ] T015 [P] Create `web/src/lib/api.ts` — fetch wrapper for FastAPI endpoints: getRides, getRide, getSightings, correctSighting, confirmSighting, deleteSighting, exportRide, getConfig, updateConfig
- [ ] T016 [P] Create `web/src/app.css` — global design tokens (dark-mode palette from research.md), Inter font import, CSS reset, utility classes, animation keyframes
- [ ] T017 Write tests: `pipeline/tests/test_db.py` — test create_tables, schema_version, WAL mode, duplicate checksum rejection

**Checkpoint**: Database created, API serves health check, SvelteKit shell loads with design tokens applied.

---

## Phase 2.5: Hardware Acceleration & Vast.ai Deploy Kit

**Purpose**: Multi-backend accelerator module, CoreML/CUDA/AVX-512/NEON auto-detection, model format exports, Vast.ai training infrastructure.

**⚠️ NOTE**: This phase runs IN PARALLEL with Phase 3+ — it enhances but does not block pipeline work.

### Accelerator Module

- [ ] T017.1 [P] Implement `pipeline/curbscout/accelerator.py` — `Backend` enum: COREML_ANE, COREML_GPU, CUDA_TENSORRT, CUDA, ONNX_AVX512, ONNX_AVX2, ONNX_NEON, CPU
- [ ] T017.2 [P] Implement accelerator.py — `detect_best_backend()`: auto-detect CoreML (arm64+Darwin), CUDA (torch.cuda), TensorRT, AVX-512/AVX2 (/proc/cpuinfo or sysctl), ARM NEON
- [ ] T017.3 [P] Implement accelerator.py — `create_onnx_session(model_path)`: CPU session with oneDNN, AVX-512 auto-vectorization, all graph optimizations enabled
- [ ] T017.4 [P] Implement accelerator.py — `create_gpu_session(model_path)`: CUDA + TensorRT execution providers, FP16 enabled, workspace size 2GB, exhaustive conv algo search
- [ ] T017.5 [P] Implement accelerator.py — `load_coreml_model(model_path, compute_units)`: CoreML with CPU_AND_NE for classification, ALL for detection
- [ ] T017.6 [P] Write `pipeline/tests/test_accelerator.py` — test backend detection on current platform, session creation, model loading

### CoreML INT8 Optimization (M4 ANE — 38 TOPS)

- [ ] T017.7 [P] Create `scripts/export_coreml_int8.sh` — convert YOLOv8n.pt → CoreML INT8 `.mlpackage` using `yolo export format=coreml int8=True`
- [ ] T017.8 [P] Create `scripts/export_coreml_classifier.sh` — convert Jordo23 ONNX → CoreML INT8 via `coremltools.converters.onnx`, W8A8 quantization for ANE fast path
- [ ] T017.9 [P] Add CoreML compute unit config to `config.toml`: `coreml_compute_units = "CPU_AND_NE"` (changeable to ALL, CPU_ONLY for debugging)

### NEON / AVX-512 Image Processing

- [ ] T017.10 [P] Verify Accelerate.framework usage: `numpy.show_config()` should show vecLib, NOT OpenBLAS. Add startup check + warning if wrong BLAS.
- [ ] T017.11 [P] Implement NEON-optimized pHash hamming distance: use NumPy `np.unpackbits` + `np.count_nonzero` (auto-vectorized via NEON `vcntq_u8` + `vpaddlq`)
- [ ] T017.12 [P] On x86: verify ONNX Runtime uses oneDNN with AVX-512 VNNI. Add `ORT_LOG_LEVEL=VERBOSE` debug mode to confirm SIMD path.

### Vast.ai Training Deploy Kit (from PromptHarbor)

- [ ] T017.13 Implement `pipeline/curbscout/vast_client.py` — Python port of PromptHarbor `pkg/vast/client.go`: VastClient class with search_offers(), launch_instance(), destroy_instance(), list_instances(), get_instance()
- [ ] T017.14 [P] Create `deploy/bootstrap_training.sh` — autonomous Vast.ai instance bootstrap: install ultralytics+torch, download dataset from GCS, fine-tune YOLOv8n-cls, export .pt→CoreML+ONNX+TensorRT, upload results to GCS, self-destruct
- [ ] T017.15 [P] Create `deploy/training_sync.sh` — upload training metrics + checkpoints to GCS in real-time (adapted from PromptHarbor `instant_gcs_sync.sh`)
- [ ] T017.16 [P] Create `deploy/training_poll.py` — monitor Vast.ai training from local Mac (adapted from PromptHarbor `fleet_poll.py`): poll instance status, training progress, costs
- [ ] T017.17 [P] Create `deploy/training_autokill.sh` — TTL safety guard, max 12hr runtime, auto-destroy if training stalls (adapted from `ph-autokill.sh`)
- [ ] T017.18 [P] Create `deploy/export_all_formats.sh` — convert best.pt → `.mlpackage` (CoreML INT8) + `.onnx` (FP32) + `.engine` (TensorRT FP16), store in `models/formats/`
- [ ] T017.19 [P] Write `pipeline/tests/test_vast_client.py` — test search_offers, launch payload, destroy request (mocked httpx)
- [ ] T017.20 [P] Add CLI command: `curbscout train --dataset <path> --gpu RTX_4090 --epochs 100` — launches Vast.ai training job, polls for completion, downloads results

### Benchmarking

- [ ] T017.21 [P] Create `scripts/benchmark_accel.sh` — benchmark all available backends on 100 sample crops: measure FPS for detection + classification, report per-backend latency

**Checkpoint**: `accelerator.py` auto-detects CoreML ANE on M4. Vast.ai bootstrap script tested. Model format exports for all 3 platforms.

---

**PHASE 2.5 COST**: ~$1-2 for Vast.ai test training run. Zero cost for local CoreML/NEON work.

---

## Phase 3: User Story 1 — Video Ingest & Catalog (Priority: P1) 🎯 MVP

**Goal**: Import camera videos to local storage, create Ride + Video records.

**Independent Test**: Copy sample MP4s → verify files + DB rows, no duplicates on re-run.

### Tests for US1

- [ ] T018 [P] [US1] Write `pipeline/tests/test_ingest.py` — file discovery, checksum, duplicate rejection, partial quarantine, disk space check

### Implementation for US1

- [ ] T019 [US1] Implement `pipeline/curbscout/ingest.py` — `discover_videos(source_path)`: scan for VID*.mp4 in DCIM/Camera01/
- [ ] T020 [US1] Implement ingest.py — `compute_checksum(path)`: streaming SHA-256 (64KB chunks)
- [ ] T021 [US1] Implement ingest.py — `import_video(source, dest_dir, db)`: copy with progress, verify checksum, create VIDEO row, quarantine on failure
- [ ] T022 [US1] Implement ingest.py — `create_ride(videos, db)`: group by date, populate start_ts/end_ts from ffprobe metadata
- [ ] T023 [US1] Implement `pipeline/curbscout/cli.py` — `ingest` command (Click): `--source <path>`, progress bar
- [ ] T024 [US1] Add API endpoints: `GET /api/rides`, `GET /api/rides/{id}` in api.py
- [ ] T025 [US1] Add ffprobe corruption check at ingest, mark `status: corrupted` if fails
- [ ] T026 [US1] Add disk space check: warn if < 1 GB free

**Checkpoint**: `uv run python -m curbscout.cli ingest --source /path` works. API returns ride list.

---

## Phase 4: User Story 2 — Frame Sampling & Vehicle Detection (Priority: P1) 🎯 MVP

**Goal**: Extract keyframes, detect vehicles with bboxes + crops.

**Independent Test**: Process test video → verify frame count, DETECTION rows, crop images.

### Tests for US2

- [ ] T027 [P] [US2] Write `pipeline/tests/test_sampler.py` — frame extraction at 2fps, path naming, count validation
- [ ] T028 [P] [US2] Write `pipeline/tests/test_detector.py` — detection on fixture images, bbox format, confidence range

### Implementation for US2

- [ ] T029 [US2] Implement `pipeline/curbscout/sampler.py` — `extract_frames(video_path, fps, output_dir)`: ffmpeg with VideoToolbox, output JPEGs, return (path, timestamp) list
- [ ] T030 [US2] Implement sampler.py — create FRAME_ASSET rows (kind='keyframe')
- [ ] T031 [US2] Implement `pipeline/curbscout/detector.py` — `detect_vehicles(frame_path, model)`: load YOLOv8n, filter vehicle classes, return (bbox, confidence, class) list
- [ ] T032 [US2] Implement detector.py — `save_crops(frame_path, detections, output_dir)`: crop, save JPEG, create FRAME_ASSET (kind='crop') + DETECTION rows
- [ ] T033 [US2] Implement detector.py — compute pHash for each crop
- [ ] T034 [US2] Implement `cli.py` — `process` command: `--date` or `--ride-id`, orchestrate sampler → detector
- [ ] T035 [US2] Add API endpoint: `GET /api/sightings?ride_id=X` (returns detections before classification)
- [ ] T036 [US2] Add API endpoint: `GET /api/static/crops/{path}` — serve crop images with proper caching headers

**Checkpoint**: `process` creates frames + detections + crops. API serves detection data and images.

---

## Phase 5: User Story 3 — Make/Model Classification (Priority: P2)

**Goal**: Classify each crop using tiered pre-trained models.

**Independent Test**: Feed known crops → verify predictions match expectations.

### Tests for US3

- [ ] T037 [P] [US3] Write `pipeline/tests/test_classifier.py` — tiered classification, output format, fallback logic
- [ ] T038 [P] [US3] Write `pipeline/tests/test_sanity.py` — impossible combo flagging, valid combos pass

### Implementation for US3

- [ ] T039 [US3] Implement `pipeline/curbscout/classifier.py` — `load_classifier(model_path)`: load Jordo23 EfficientNet-B4 via ONNX Runtime or PyTorch
- [ ] T040 [US3] Implement classifier.py — `classify_vehicle(crop_path, classifier)`: preprocess 380×380, run inference, parse class_mapping.csv → (make, model, year, confidence)
- [ ] T041 [US3] Implement classifier.py — `classify_type_fallback(crop_path, type_model)`: load NVIDIA VehicleTypeNet ONNX, return vehicle_type if Tier 1 confidence < 0.5
- [ ] T042 [US3] Implement `pipeline/curbscout/sanity.py` — `check_sanity(make, model, year, lookup)`: load sanity_check.json, return warning if year < production_start
- [ ] T043 [US3] Integrate classification into `cli.py process`: after detection, classify each crop with tiered strategy, create SIGHTING rows
- [ ] T044 [US3] Update API: enrich `GET /api/sightings` response with make/model/confidence/vehicle_type

**Checkpoint**: SIGHTING table populated with make/model/year from pre-trained models. Sanity warnings where applicable.

---

## Phase 6: User Story 4 — Deduplication (Priority: P2)

**Goal**: Merge multiple detections of same car into single sighting.

**Independent Test**: One car visible 10 sec → 1 sighting. Two different cars → 2 sightings.

### Tests for US4

- [ ] T045 [P] [US4] Write `pipeline/tests/test_deduplicator.py` — temporal grouping, IoU, pHash similarity, cross-type rejection

### Implementation for US4

- [ ] T046 [US4] Implement `pipeline/curbscout/deduplicator.py` — `deduplicate(detections, config)`: group by make_model + time_window
- [ ] T047 [US4] Implement IoU check within temporal window, merge if > threshold
- [ ] T048 [US4] Implement pHash comparison, merge if hamming distance < threshold
- [ ] T049 [US4] Select best crop per sighting (highest confidence)
- [ ] T050 [US4] Integrate into `cli.py process`: run after classification, idempotent re-runs

**Checkpoint**: Typical ride: 500 detections → ≤100 sightings.

---

## Phase 7: User Story 5 — SvelteKit Review Web UI (Priority: P1) 🎯 MVP

**Goal**: Premium dark-mode web UI for reviewing and correcting sightings.

**Independent Test**: Open localhost:5173 → browse rides → confirm/correct/delete → verify DB updates.

### Implementation for US5

- [ ] T051 [US5] Implement `web/src/routes/+layout.svelte` — app shell: sidebar (ride list) + content area, dark-mode theme, Inter font, responsive layout
- [ ] T052 [US5] Implement `web/src/routes/+page.svelte` — dashboard: ride cards with date, video count, sighting count, review progress bar, "Start Review" button
- [ ] T053 [US5] Implement `web/src/components/SightingCard.svelte` — crop thumbnail, make/model label, confidence badge (green/yellow/red), sanity warning icon, hover animation
- [ ] T054 [US5] Implement `web/src/components/SightingGrid.svelte` — responsive lazy-loaded grid of SightingCards, keyboard navigation (↑↓), click to select
- [ ] T055 [US5] Implement `web/src/routes/rides/[rideId]/+page.svelte` — ride detail: top = video player, bottom = sighting grid, sighting count + review progress
- [ ] T056 [US5] Implement `web/src/components/VideoPlayer.svelte` — HTML5 `<video>` with seek-to-timestamp on sighting click, play 3-sec clip, custom controls styled to dark theme
- [ ] T057 [US5] Implement `web/src/components/TimelineScrubber.svelte` — custom timeline bar with detection markers, click to seek, current position indicator
- [ ] T058 [US5] Implement `web/src/routes/rides/[rideId]/review/+page.svelte` — sequential review: one sighting at a time, confirm (⏎) / correct (/) / delete (⌫) / skip (→)
- [ ] T059 [US5] Implement `web/src/components/CorrectionModal.svelte` — searchable dropdown for make/model, autocomplete from known list, submit correction via API
- [ ] T060 [US5] Implement `web/src/components/SearchDropdown.svelte` — reusable fuzzy-search dropdown (used by CorrectionModal), keyboard navigable
- [ ] T061 [US5] Implement `web/src/components/ConfidenceBadge.svelte` — color-coded badge: green (≥0.8), yellow (≥0.5), red (<0.5)
- [ ] T062 [US5] Implement `web/src/components/SanityWarning.svelte` — orange warning icon with tooltip
- [ ] T063 [US5] Implement `web/src/components/ReviewProgress.svelte` — progress bar showing N/M reviewed, color change on completion
- [ ] T064 [US5] Implement `web/src/lib/shortcuts.ts` — global keyboard shortcut handler: ⏎ confirm, ⌫ delete, ↑↓ navigate, / correct, e export, Space play/pause
- [ ] T065 [US5] Implement `web/src/lib/stores.ts` — Svelte 5 runes: selectedRide, selectedSighting, reviewQueue, config
- [ ] T066 [US5] Add API endpoints for corrections: `POST /api/sightings/{id}/correct`, `POST /api/sightings/{id}/confirm`, `POST /api/sightings/{id}/delete`
- [ ] T067 [US5] Add API endpoint: `GET /api/static/video/{path}` — serve video with HTTP Range requests for seeking
- [ ] T068 [US5] Apply premium polish: glassmorphism cards, smooth transitions (150ms), hover effects, focus ring on keyboard nav, loading skeletons

**Checkpoint**: Full review loop works in browser. Corrections persist to SQLite.

---

## Phase 8: User Story 6 — Daily Export Bundle (Priority: P3)

**Goal**: Export JSONL + CSV + crops + HTML report.

### Tests for US6

- [ ] T069 [P] [US6] Write `pipeline/tests/test_exporter.py` — JSONL/CSV gen, HTML render, excluded deleted

### Implementation for US6

- [ ] T070 [US6] Implement `pipeline/curbscout/exporter.py` — `export_jsonl()`: one JSON line per sighting
- [ ] T071 [US6] Implement exporter.py — `export_csv()`: flat CSV
- [ ] T072 [US6] Implement exporter.py — `copy_crops()`: copy referenced images to bundle
- [ ] T073 [US6] Implement exporter.py — `generate_html()`: self-contained dark-mode HTML report with inline CSS, responsive crop grid, summary stats
- [ ] T074 [US6] Implement `cli.py` — `export` command: `--date`, `--ride-id`
- [ ] T075 [US6] Add API endpoint: `POST /api/export/{rideId}` — trigger export, return bundle path
- [ ] T076 [US6] Implement `web/src/routes/export/[rideId]/+page.svelte` — export preview, trigger button, "Open in Finder" link

**Checkpoint**: Export produces valid bundle. HTML report renders in browser.

---

## Phase 10: Polish & Cross-Cutting Concerns

- [ ] T077 [P] Create `scripts/run-pipeline.sh` — end-to-end: ingest → process → summary
- [ ] T078 [P] Create `scripts/watch-usb.sh` — auto-detect Insta360 mount, trigger ingest
- [ ] T079 [P] Add structured logging: Python `logging` → `~/CurbScout/pipeline.log`
- [ ] T080 [P] Add pipeline progress API: `GET /api/pipeline/status` for web UI to show processing state
- [ ] T081 Performance audit: profile pipeline on 30-min ride, optimize bottlenecks. Run `benchmark_accel.sh` and report per-platform speedups.
- [ ] T082 [P] Add `web/src/routes/settings/+page.svelte` — UI for config editing (fps, thresholds, model paths, compute backend, Vast.ai API key)
- [ ] T083 [P] Update `readme.md` — architecture diagram (with acceleration matrix), setup instructions, link to quickstart
- [ ] T084 [P] Create `CONTRIBUTING.md` — dev setup, code style, PR process
- [ ] T085 Security review: validate file paths, no directory traversal in API
- [ ] T086 Run quickstart.md validation end-to-end
- [ ] T087 [P] Add `/api/accelerator/info` endpoint — returns detected backend, features (AVX-512, NEON, ANE, CUDA), model formats available

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — BLOCKS all user stories
- **Phase 2.5 (Acceleration)**: Depends on Phase 1 — runs IN PARALLEL with Phases 3–9
- **Phase 3 (US1 Ingest)**: Depends on Phase 2
- **Phase 4 (US2 Detection)**: Depends on Phase 3 (needs ingested videos)
- **Phase 5 (US3 Classification)**: Depends on Phase 4 (needs detections) + Phase 2.5 (accelerator)
- **Phase 6 (US4 Dedup)**: Depends on Phase 5 (needs classifications)
- **Phase 7 (US5 SvelteKit UI)**: Depends on Phase 2 (API skeleton); enriched after Phase 6
- **Phase 8 (US6 Export)**: Depends on Phase 6
- **Phase 9 (Already numbered wrong, renumbered to 10)
- **Phase 10 (Polish)**: After all user stories + Phase 2.5

### Parallel Opportunities

```
Phase 1: [T001] [T002] [T003] [T004] [T005] [T006]  ← all parallel
Phase 2: [T007→T008→T009] + [T010-T016] parallel
Phase 2.5: [T017.1-T017.21] ALL PARALLEL with Phase 3+
Phase 7: Can START at Phase 2 (ride list + empty state), enriched incrementally
Phase 10: All [P] tasks parallel
```

### Critical Path

```
T001 → T007 → T008 → T019 → T029 → T031 → T039 → T046 → T051 → T070
Setup → Models → DB → Ingest → Sample → Detect → Classify → Dedup → Web UI → Export
```

---

## Implementation Strategy

### MVP First: Pipeline → Web UI → Export

1. Phase 1: Setup (0.5 days)
2. Phase 2: Foundational + model downloads (1.5 days)
3. Phase 3: Ingest (1.5 days)
4. Phase 4: Detection (2 days)
5. Phase 7 partial: Minimal SvelteKit (ride list + sighting grid with raw detections) (2 days)
6. **VALIDATE**: Real ride imported, detections visible in browser
7. Phase 5: Classification (1.5 days)
8. Phase 6: Dedup (1 day)
9. Phase 7 complete: Full review UI with corrections (2 days)
10. Phase 8: Export (1 day)
11. Phase 9: Polish (1.5 days)

### Estimated Timeline

| Phase | Duration | Cumulative |
|-------|----------|------------|
| Phase 1: Setup | 0.5 days | 0.5 days |
| Phase 2: Foundational | 1.5 days | 2 days |
| Phase 2.5: Acceleration (parallel) | 2 days | (runs alongside 3-6) |
| Phase 3: Ingest | 1.5 days | 3.5 days |
| Phase 4: Detection | 2 days | 5.5 days |
| Phase 5: Classification | 1.5 days | 7 days |
| Phase 6: Dedup | 1 day | 8 days |
| Phase 7: SvelteKit UI | 4 days | 12 days |
| Phase 8: Export | 1 day | 13 days |
| Phase 10: Polish | 1.5 days | 14.5 days |
| **Total** | **~14.5 working days** | **~3 weeks** |

> **Note**: Phase 2.5 runs in parallel with Phases 3–6 — no timeline impact.
> Vast.ai training run costs ~$1-2 and takes 2-3 hours.
