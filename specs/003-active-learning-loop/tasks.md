# Tasks: Phase 5 Active Learning Loop

**Input**: Design documents from `/specs/003-active-learning-loop/`
**Prerequisites**: Vast.ai export scripts functioning, Cloud Tasks integrated.

---

## Phase 5A: GCP Orchestration Auto-Triggering

**Purpose**: Move away from manual user clicking to background automated thresholds.

- [x] T001 Update `types.ts` to include `trained?: boolean` to the `Sighting` interface, and build the `Model` interface representing `MODELS` collection.
- [x] T002 Update `/api/sync/+server.ts` to default `trained: false` when receiving new sightings.
- [x] T003 Implement `GET /api/jobs/trigger-auto-train`. Query Firestore for all `review_status: 'corrected'` or `'confirmed'` where `trained != true`. If `docs.length >= process.env.AUTO_TRAIN_THRESHOLD || 100`, lock them (`trained = true`), create a `Model` document with `status: 'training'` and `lineage_ids`, and dispatch the Cloud Task to Vast.ai payloading the `model_id`.
- [x] T004 Build the `POST /api/webhooks/vast-export` API. Expect an API key header. Receive `{ model_id, gcs_uri }`. Update the `MODELS` doc to `status: 'deployed'`, activating the new version globally.

---

## Phase 5B: Vast.ai & M4 Deploy Synchronization

**Purpose**: Close the loop mechanically on the edges (Vast.ai pushing, M4 pulling).

- [x] T005 Update the Vast.ai client script (`deploy/upload_teardown.py` or equivalent) to explicitly invoke the `/api/webhooks/vast-export` POST request with the new `model_id` upon successfully copying `.onnx` and `.mlmodel` zips to the GCS bucket.
- [x] T006 Update the M4 Pipeline's `sync_models.py` to query the GCP Hub via HTTP for the `active` model version instead of blindly grabbing the newest blob bucket timestamp. If the local version mismatches the Hub's `deployed` version, download it and overwrite `yolov8n.pt`/`jordo23-effnet` pointers.
- [x] T007 Modify the UI in `web/src/routes/models/+page.svelte` to query the `MODELS` collection, rendering a table/list of previous model permutations and their lineage count so data scientists can audit the platform's self-improvement.

---

## Output Metrics
Execution of this branch finishes the core functionality of Phase 5. The application becomes a truly autonomous edge-to-cloud intelligence scanner. M4 generates data -> humans correct it on Hub -> GCP counts it -> Vast.ai trains it -> Hub registers it -> M4 deploys it. Zero manual developer intervention required.
