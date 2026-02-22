# Tasks: Phase 4 Curb Intelligence

**Input**: Design documents from `/specs/002-curb-intelligence/`
**Prerequisites**: M4 Pipeline MVP running. Apple Vision API or PaddleOCR available.

---

## Phase 4A: Mac mini M4 Pipeline Extensibility

**Purpose**: Upgrade the YOLOv8 and classifier orchestrators to handle non-vehicle entities out-of-the-box.

- [x] T001 Update `detector.py` to support multi-model multiplexing. Define `YOLOv8-ParkingSigns.pt` and `YOLOv8-Hazards.pt` parallel inferences over the extracted frames.
- [x] T002 Implement `ocr.py` invoking Apple's `Vision` framework (via PyObjC `Vision` and `CoreImage`) extracting native text directly from MacOS for `parking_sign` crops.
- [x] T003 Implement `rules.py` containing a RegEx parsing engine to transform raw OCR string sequences (e.g. "2 HR PASSENGERS ONLY 8AM-5PM") into structured machine-readable JSON rules.
- [x] T004 Update `classifier.py` and `db.py` logic to format `SIGHTING` records correctly (Make/Model -> Class/Subclass) for Hazard and OCR events, pushing into `attrs_json`.
- [x] T005 Test local OCR natively on M4 extracting bounding boxes and pushing string JSONs into the SQLite DB `SIGHTING` row.

---

## Phase 4B: GCP Hub Dashboard Updates

**Purpose**: Translate structured hazard/sign sightings into interactive Mapbox elements.

- [x] T006 Update `analytics/+page.svelte` Mapbox renderer to query and filter `sightings` by event class (Vehicle, Sign, Hazard, Storefront).
- [x] T007 Add dynamic Mapbox iconography: Red exclamation pins for hazards, green parking "P" icons for legal spots, gray "P" for illegal spots (calculated against client-side current time).
- [x] T008 Enhance the `rides/[id]/review` sighting grid to beautifully handle text-based sightings, allowing the user to `correct` OCR mis-reads or parsed rule mapping errors explicitly to trigger Active Learning.

---

## Output Metrics
Execution of this branch completes Phase 4, turning CurbScout from a simple vehicle identifying pipeline into a comprehensive street intelligence engine leveraging hardware accelerated bounding-box OCR on M4 architecture.
