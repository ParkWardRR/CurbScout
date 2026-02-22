# Feature Specification: Active Learning Loop

**Feature Branch**: `003-active-learning-loop`  
**Created**: 2026-02-21  
**Status**: ✅ Implemented  
**Merged**: 2026-02-21  
**Input**: User description: "Implement Phase 5: Active Learning Loop including automated correction-to-training pipeline, user corrections in Firestore auto-queueing for the next training batch, GCP dispatching Vast.ai training jobs, model versioning with data lineage tracking, and new models auto-deploying to M4 via GCS."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automated Training Dispatch (Priority: P1)

As a fleet manager doing normal reviews, I want my corrections to automatically trigger a model retrain once enough corrections have accumulated, without me having to manually click "train", so the system improves continuously in the background.

**Why this priority**: It transforms the system from a manual script-trigger based workflow into a fully autonomous, self-improving pipeline.

**Independent Test**: Can be tested by seeding Firestore with mock `corrected` sightings that exceed the numerical threshold, observing GCP Cloud Scheduler trigger the batch evaluation, and verifying that a Cloud Task payload is dispatched to Vast.ai without manual intervention.

**Acceptance Scenarios**:

1. **Given** the threshold for automated training is 100 corrections, and there are currently 99 un-trained corrections, **When** a reviewer corrects the 100th sighting, **Then** an aggregation job fires that compiles the training payload and sends it to the Cloud Tasks queue.
2. **Given** a cron schedule executes the trigger endpoint, **When** there are insufficient new corrections, **Then** the trigger skips gracefully without spinning up expensive Vast.ai instances.

---

### User Story 2 - Model Data Lineage (Priority: P2)

As a data scientist monitoring the pipeline, I want to know exactly which user-corrected images were included in any given model version's training set, so that I understand what influenced its new behaviors.

**Why this priority**: Critical for tracing regressions or biases in newly deployed models back to their root cause data points.

**Independent Test**: Review a generated model artifact representation in Firestore and verify it enumerates an array of successfully synthesized `sighting_id` references that were compiled into its YOLO dataset.

**Acceptance Scenarios**:

1. **Given** a new training job launches, **When** it queries Firestore for target images, **Then** those image IDs are linked and persisted as the model's `lineage` payload in a new `MODELS` collection.
2. **Given** a trained model, **When** viewing the Active Learning dashboard, **Then** I can see a "Trained On: X Corrections" metric detailing its exact data lineage.

---

### User Story 3 - Full Lifecycle Auto-Deployment (Priority: P3)

As a system admin, I want new model versions to be seamlessly registered in Firestore upon Vast.ai export completion, enabling the M4 worker's sync script to swap to them automatically.

**Why this priority**: Completes the loop mechanically so models don't need manual copying into production buckets or manual database updates.

**Independent Test**: We can test this by mocking a successful completion payload against the GCP return hook, and observing the Firestore model's status switch from `training` to `deployed`, thereby notifying downstream M4 clients.

**Acceptance Scenarios**:

1. **Given** the Vast.ai instance finishes exporting `.onnx` and `.mlmodel` formats to GCS, **When** it explicitly pings the GCP Hub webhook, **Then** the corresponding model document's status updates, making it the active baseline.

---

### Edge Cases

- What happens if the training job fails on Vast.ai? (Instance should self-terminate; GCP Hub should mark the model iteration as `failed` and unlock the pending corrections for the next run).
- How do we handle duplicate triggers (e.g. cron triggers alongside the 100-correction threshold)? (Atomic locking or idempotent dataset generation).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Implement a `/api/jobs/trigger-auto-train` GCP Hub endpoint that evaluates if the pending `corrected` sightings count exceeds the environment variable `$AUTO_TRAIN_THRESHOLD`.
- **FR-002**: Create a `MODELS` Firestore collection natively tracking `version`, `status`, `created_at`, `gcs_path`, and `lineage_ids` (an array of sightings used for training).
- **FR-003**: Update the Vast.ai deployment wrapper to ping a success webhook on the GCP Hub upon upload completion, providing the new model's GCS URI.
- **FR-004**: Add a visual `Model Lineage` breakdown inside the Active Learning dashboard.
- **FR-005**: Mark corrections used in training with a `trained=true` flag to prevent duplicate inclusion in future datasets.

### Key Entities 

- **Model Version**: A record in Firestore tracking the lifecycle (pending -> training -> exported -> deployed) of a specific artifact iteration.
- **Lineage Event**: The relational mapping between a Model Version and the array of specific Sighting IDs that comprised its YOLO dataset.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Reaching the correction threshold seamlessly spins up a training instance on Vast.ai within 60 seconds with no user input.
- **SC-002**: Model lineage accurately tracks 100% of the used correction IDs without duplication.
- **SC-003**: Vast.ai export script correctly transitions Firestore model status upon success, allowing the M4 `sync_models.py` cron to pick it up in its next tick.
