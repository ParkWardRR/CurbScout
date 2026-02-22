# Tasks: Local Pipeline MVP (Hub & Spoke Architecture)

**Input**: Design documents from `/specs/001-local-pipeline-mvp/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

**Organization**: Tasks grouped by the new Three-Tier Architecture build order. GCP Orchestration Hub is built first, followed by the M4 Pipeline and Vast.ai Worker in parallel.

---

## Phase 1A: GCP Orchestration Hub (Build First)

**Purpose**: Establish the central control plane, database, job queues, and the always-on web dashboard.

- [x] T001 Create SvelteKit project `web/` using `npx -y sv create` with Svelte 5, TypeScript, adapter-node.
- [x] T002 Configure GCP project, enable Firestore, Cloud Storage, and Cloud Tasks APIs.
- [x] T003 Create Firestore schema: collections for `rides`, `videos`, `sightings`, `corrections`, and `jobs`.
- [x] T004 Implement SvelteKit API endpoints (`web/src/routes/api/`) to handle incoming data syncs from M4 workers and serve the UI.
- [x] T005 Implement Cloud Tasks integration to dispatch inference jobs to M4 and training jobs to Vast.ai.
- [x] T006 Implement Cloud Run deployment pipeline for the SvelteKit dashboard.
- [x] T007 Build the Review UI (`web/src/routes/rides/[id]/review`): sighting grid, keyboard shortcuts (confirm, correct, delete).
- [x] T008 Build the Job Dashboard UI: monitor active pipeline runs on M4 and training runs on Vast.ai.

**Checkpoint**: GCP Cloud Run dashboard is live. Firestore database is ready to accept data. Job queues are configured.

---

## Phase 1B: M4 Pipeline + Vast.ai Worker (Build in Parallel)

### Track 1: M4 Mac mini (Local Worker)

**Purpose**: High-performance local inference using CoreML ANE, syncing derived results to GCP.

- [x] T009 Create Python project `pipeline/pyproject.toml`. Dependencies: fastapi, ultralytics>=8.0, onnxruntime, coremltools, ffmpeg-python, Pillow, imagehash.
- [x] T010 Implement CoreML accelerator module: `pipeline/curbscout/accelerator.py` for ANE processing via `coremltools`.
- [x] T011 Implement Video Ingest: `pipeline/curbscout/ingest.py` to copy MP4s, compute checksums, and extract metadata.
- [x] T012 Implement Frame Sampling: `pipeline/curbscout/sampler.py` to extract 2fps keyframes using VideoToolbox.
- [x] T013 Implement Vehicle Detection: run YOLOv8n (CoreML) to extract crops and bounding boxes.
- [x] T014 Implement Classification: run Jordo23 EfficientNet (CoreML) and VehicleTypeNet fallback on crops.
- [x] T015 Implement Deduplication: temporal, spatial (IoU), and perceptual hash grouping.
- [x] T016 Implement GCP Sync Daemon: background process that pushes Sighting metadata to Firestore and crops/clips to GCS after each run.
- [x] T017 Implement Job Polling: daemon polls GCP Cloud Tasks for inference or reprocessing jobs dispatched by the dashboard.

### Track 2: Vast.ai Ephemeral GPU Worker

**Purpose**: Autonomous burst training on renting GPUs, tearing down immediately upon completion.

- [x] T018 Implement Vast.ai API Client (`pipeline/curbscout/vast_client.py`): functions to search offers, launch instance with setup script, and destroy instance.
- [x] T019 Create Bootstrap Script (`deploy/bootstrap_training.sh`): installs YOLOv8, CoreML/ONNX dependencies, downloads dataset from GCS.
- [x] T020 Create Training Script: fine-tunes YOLOv8n-cls on Stanford Cars + CurbScout corrections.
- [x] T021 Create Export Script: converts trained `best.pt` to CoreML INT8, ONNX FP32, and TensorRT FP16.
- [x] T022 Create Upload & Teardown Script: pushes models to GCS, signals completion to Firestore, and destroys the Vast.ai instance automatically.
- [x] T023 Implement Auto-Kill Safety: hard timeout TTL script (max 12h) to prevent runaway costs.

**Checkpoint**: M4 pipeline runs end-to-end and pushes sightings to GCP. Vast.ai bootstrap launches, trains, exports, and self-destructs.

---

## Phase 2: Analytics + Job Monitoring

**Purpose**: Enrich the dashboard with map visualizations and real-time infrastructure visibility.

- [x] T024 Add Mapbox GL sighting heatmaps to the GCP dashboard.
- [x] T025 Implement time-of-day and make/model frequency charts.
- [x] T026 Add real-time job log streaming using Firestore listeners.
- [x] T027 Implement basic authentication (Firebase Auth or Cloudflare Access).

---

## Phase 3: Active Learning Pipeline

**Purpose**: Close the loop between user corrections and model training.

- [ ] T028 Export corrected labels from Firestore into training dataset format (YOLO classification).
- [ ] T029 Build UI panel to trigger Vast.ai fine-tuning directly from the dashboard.
- [ ] T030 Implement A/B testing framework to compare new Vast.ai model against baseline on held-out data.
- [ ] T031 Implement auto-download on M4: sync daemon periodically pulls new CoreML models from GCS.

---

## Phase 10: Polish & Cross-Cutting Concerns

- [x] T032 Update README with new architecture and cost analysis (completed).
- [x] T033 Update CONTRIBUTING.md (completed).
- [ ] T034 Implement structured JSON logging across GCP, M4, and Vast.ai.
- [ ] T035 Create `scripts/run-pipeline.sh` for easy M4 local testing.

---

## Dependencies & Execution Order

1. **Phase 1A (GCP Hub)** MUST be built first. It provides the datastore, UI, and job queue that the workers rely on.
2. **Phase 1B (M4 Pipeline)** and **Phase 1B (Vast.ai)** can be built simultaneously.
3. **Phase 2 (Analytics)** and **Phase 3 (Active Learning)** depend on Phase 1A and 1B being complete.
