# Feature Specification: Local Pipeline MVP

**Feature Branch**: `001-local-pipeline-mvp`
**Created**: 2026-02-21
**Status**: Approved
**Input**: User description: "Build a three-tier perception system. GCP is the central orchestration hub handling the review UI on Cloud Run and job dispatch via Cloud Tasks. An M4 Mac mini handles local ingest and zero-cost CoreML inference, syncing derived artifacts to GCP. Vast.ai provides ephemeral GPU burst training on-demand, orchestrated by GCP."

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Video Ingest & Catalog (Priority: P1)

After a bike ride, the user connects the Insta360 GO 3S via USB, and the app automatically detects new MP4 files on the mounted drive, computes SHA-256 checksums, copies them to `~/CurbScout/raw/`, and creates a new Ride + Video record in the local database. Previously-imported files (by checksum) are skipped. The user sees a progress indicator during transfer.

**Why this priority**: Nothing else works without raw video on disk and a database record. This is the literal first step.

**Independent Test**: Connect a USB drive with sample MP4s → verify files appear in `~/CurbScout/raw/`, checksums match, and RIDE/VIDEO rows exist in SQLite. Re-plug the drive → verify no duplicates are created.

**Acceptance Scenarios**:

1. **Given** no prior data, **When** user connects camera with 3 MP4 files, **Then** all 3 are copied to `~/CurbScout/raw/YYYY-MM-DD/`, checksums stored, RIDE + VIDEO rows created, progress bar reaches 100%.
2. **Given** a previous import of the same files, **When** user connects camera again, **Then** 0 new files are imported, user sees "No new videos found."
3. **Given** a mix of 2 new + 1 existing file, **When** user connects camera, **Then** only 2 new files are imported.
4. **Given** 4K MP4 files totaling 12 GB, **When** import runs, **Then** the transfer completes without memory issues (streaming copy, not load-all-into-memory).

---

### User Story 2 — Frame Sampling & Vehicle Detection (Priority: P1)

Once video is ingested, the pipeline extracts keyframes (configurable: default 2 fps), runs a vehicle detection model (YOLOv8 or equivalent) on each frame, and stores bounding-box detections with confidence scores. Cropped vehicle images are saved to `~/CurbScout/derived/crops/`.

**Why this priority**: Detection is the foundation for all downstream classification, dedup, and review. Co-equal with ingest as MVP.

**Independent Test**: Run pipeline on a known test video → verify frames are extracted at the configured rate, bounding boxes are stored in DETECTION table, and crop images exist on disk at the expected paths.

**Acceptance Scenarios**:

1. **Given** a 5-minute ride video at 30 fps, **When** pipeline runs at 2 fps sampling, **Then** ~600 frames are extracted and processed.
2. **Given** a frame containing 3 cars, **When** detection runs, **Then** 3 DETECTION rows are created with bbox, confidence, class='car', and model_ver fields populated.
3. **Given** a frame with no vehicles, **When** detection runs, **Then** 0 DETECTION rows are created for that frame.
4. **Given** a detection with confidence < 0.3, **When** stored, **Then** it is flagged as `low_confidence` for optional review but still persisted.

---

### User Story 3 — Make/Model Classification (Priority: P2)

For each detected vehicle crop, a classifier (YOLOv8-cls fine-tuned on Stanford Cars or similar) predicts make and model (e.g., "BMW 3 Series", "Honda Civic"). A best-effort year guess is included when available but marked as `year_confidence: low`. A sanity checker flags impossible combos (e.g., "BMW 440i 2004" — the 4 Series didn't exist until 2014).

**Why this priority**: Classification gives the sighting its value. Without it, detections are just anonymous boxes.

**Independent Test**: Feed 20 known vehicle crops → verify ≥ 70% top-1 make/model accuracy. Feed an impossible year/badge combo → verify it's flagged for review.

**Acceptance Scenarios**:

1. **Given** a clear BMW 3 Series crop, **When** classifier runs, **Then** SIGHTING row has make="BMW", model="3 Series", conf ≥ 0.7.
2. **Given** a heavily occluded crop, **When** classifier runs, **Then** SIGHTING row has lower confidence and is flagged `needs_review: true`.
3. **Given** a classification of "BMW 440i" with year_guess="2004", **When** sanity check runs, **Then** the sighting is flagged `sanity_warning: '4 Series production started 2014'`.

---

### User Story 4 — Deduplication & Sighting Consolidation (Priority: P2)

Multiple detections of the same physical car across consecutive frames are consolidated into a single Sighting. Deduplication uses a combination of: temporal proximity (detections within N seconds of the same make/model), spatial overlap (IoU of bounding boxes across adjacent frames), and optional perceptual hash similarity of crops.

**Why this priority**: Without dedup, a car parked for 30 seconds would generate 60+ duplicate "sightings." This makes the review UI usable.

**Independent Test**: Process a video where one car is visible for 10 seconds → verify a single SIGHTING is created (not 20+). Process a video with 2 different BMWs in sequence → verify 2 separate SIGHTINGs.

**Acceptance Scenarios**:

1. **Given** 15 consecutive detections of the same Honda Civic within 8 seconds, **When** dedup runs, **Then** 1 SIGHTING is created with the highest-confidence crop as the primary evidence image.
2. **Given** 2 different Toyota Camrys parked near each other, **When** dedup runs, **Then** 2 separate SIGHTINGs are created (different spatial locations).
3. **Given** a car that appears, disappears behind a tree, then reappears 3 seconds later, **When** dedup runs, **Then** 1 SIGHTING is created (temporal gap within threshold).

---

### User Story 5 — SvelteKit Review & Correction Web UI (Priority: P1)

The user opens the SvelteKit application hosted on **GCP Cloud Run** and sees today's ride with a video player, a scrollable grid of vehicle crops, and sighting details fetched from Firestore. For each sighting, the user can: confirm the label with one keystroke (⏎), correct the make/model via a searchable dropdown, flag as "not a car" (delete), or skip. Corrections are stored in Firestore. The web UI communicates with a Cloud Run API that can also dispatch training jobs to Vast.ai or inference jobs to the M4.

**Why this priority**: Human-in-the-loop corrections are what make the data trustworthy. The GCP-hosted UI ensures the dashboard is always accessible from anywhere, even if the origin Mac is asleep.

**Independent Test**: Open the Cloud Run URL after the M4 pipeline syncs data → scroll through sightings → confirm 5, correct 2, delete 1 → verify Firestore documents are updated with correct `corrected_fields` and `note` values.

**Acceptance Scenarios**:

1. **Given** a ride with 30 sightings, **When** user opens the web app, **Then** they see a grid of 30 vehicle crop thumbnails with predicted make/model labels and confidence badges.
2. **Given** a sighting labeled "Toyota Corolla" that is actually a Honda Civic, **When** user selects the sighting and types "Hond…", **Then** a dropdown autocompletes to "Honda Civic" and the user can confirm with ⏎.
3. **Given** a detection that is actually a mailbox, **When** user presses ⌫ (delete), **Then** the sighting is marked `deleted: true` and hidden from the grid (soft delete, not data loss).
4. **Given** 30 sightings to review, **When** user reviews all, **Then** the app shows "Review complete — 30/30 processed" and the ride is marked `reviewed: true`.
5. **Given** the user clicks a sighting, **When** expanded, **Then** the video player scrubs to the exact timestamp of that detection and plays a 3-second clip centered on it.

---

### User Story 6 — Daily Export Bundle (Priority: P3)

At any time, the user can export a daily report bundle to `~/CurbScout/exports/YYYY-MM-DD/`. The bundle contains: `sightings.jsonl` (one line per sighting with all metadata), `sightings.csv` (flat table), `crops/` directory (referenced images), and an `index.html` summary report. The bundle is self-contained and shareable.

**Why this priority**: Exports are the bridge to later cloud sync and analytics. Lower priority because the app itself is the primary review tool.

**Independent Test**: After completing a review, run export → verify the bundle directory contains all expected files and the HTML report renders correctly in a browser.

**Acceptance Scenarios**:

1. **Given** a reviewed ride with 25 sightings, **When** user exports, **Then** `sightings.jsonl` has 25 lines, `sightings.csv` has 25 rows, `crops/` has ≥ 25 images, and `index.html` loads in Safari.
2. **Given** a sighting that was corrected, **When** exported, **Then** the JSONL record includes both `predicted_label` and `corrected_label` fields.
3. **Given** a sighting that was deleted, **When** exported, **Then** it is excluded from the bundle.

---

### Edge Cases

- What happens when the camera disconnects mid-transfer? → Incomplete files are detected by checksum mismatch, quarantined in `~/CurbScout/raw/.partial/`, and the user is notified.
- What happens when a video is corrupted (unplayable)? → ffprobe validation at ingest flags it; the video is imported but marked `status: corrupted` and skipped by the pipeline.
- What happens when the ML model file is missing or invalid? → Pipeline exits with a clear error message and does not create partial sightings.
- What happens when the SQLite database is locked (concurrent access)? → WAL mode is enabled by default; the pipeline uses a single writer connection with retry logic.
- What happens when disk space is < 1 GB? → Ingest warns the user and pauses transfer with a "Low disk space" alert.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST detect new MP4 files on a mounted Insta360 GO 3S USB drive and import them to `~/CurbScout/raw/`.
- **FR-002**: System MUST compute SHA-256 checksums at ingest and reject duplicate files.
- **FR-003**: System MUST extract frames from ingested video at a configurable rate (default: 2 fps).
- **FR-004**: System MUST run vehicle detection (bounding box + confidence) on extracted frames.
- **FR-005**: System MUST crop detected vehicles and save evidence images to `~/CurbScout/derived/crops/`.
- **FR-006**: System MUST classify detected vehicles by make and model with a confidence score.
- **FR-007**: System MUST flag classifications with impossible year/badge combinations for review.
- **FR-008**: System MUST deduplicate detections of the same physical car across frames into a single sighting.
- **FR-009**: System MUST persist raw data in a local SQLite database, and sync derived metadata to Firestore / crops to GCS.
- **FR-010**: System MUST provide a SvelteKit web UI deployed on GCP Cloud Run for reviewing and correcting sightings.
- **FR-011**: System MUST support one-keystroke confirm and searchable-dropdown correction in the review UI.
- **FR-012**: System MUST support soft deletion (flag, not data destruction) of false-positive sightings.
- **FR-013**: System MUST export daily report bundles as JSONL + CSV + crops + HTML from the local Mac.
- **FR-014**: System MUST orchestrate jobs via GCP Cloud Tasks, allowing dispatch to the M4 or Vast.ai.
- **FR-015**: System MUST run heavy inference locally on the M4 Mac mini while keeping the UI globally accessible via GCP.

### Key Entities

- **Ride**: A single bike ride session; has a start/end timestamp, associated videos, and user notes.
- **Video**: A single MP4 file from the camera; belongs to a Ride, has file path, checksum, duration, fps, resolution.
- **FrameAsset**: An extracted frame or crop image; belongs to a Video, has timestamp, kind (keyframe/crop), file path, perceptual hash.
- **Detection**: A single bounding-box detection in a frame; belongs to a FrameAsset, has class, confidence, bbox coordinates, model version.
- **Sighting**: A consolidated observation of a unique vehicle during a ride; belongs to a Ride, has predicted make/model/year, confidence, and linked to the best Detection/crop.
- **Correction**: A human review action on a Sighting; records corrected fields, new values, and a timestamp.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: User can go from "camera plugged in" to "sightings visible in app" in under 10 minutes for a 30-minute ride.
- **SC-002**: Vehicle detection achieves ≥ 85% recall on standard urban cycling footage (no more than 15% of visible cars missed).
- **SC-003**: Make/model classification achieves ≥ 70% top-1 accuracy on clear, unoccluded crops.
- **SC-004**: Deduplication reduces raw detection count by ≥ 80% (e.g., 500 detections → ≤ 100 sightings for a typical ride).
- **SC-005**: User can review and correct/confirm all sightings from a 30-minute ride in under 5 minutes using keyboard shortcuts.
- **SC-006**: Daily export bundle generates a valid, self-contained report that opens correctly in any modern browser.
- **SC-007**: The review UI is globally accessible via GCP Cloud Run with < 1s page load times.
- **SC-008**: The M4 Mac mini pipeline pushes results to GCP automatically and gracefully handles network disconnects.
