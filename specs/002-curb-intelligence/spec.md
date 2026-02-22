# Feature Specification: Curb Intelligence

**Feature Branch**: `002-curb-intelligence`  
**Created**: 2026-02-21
**Status**: Draft  
**Input**: User description: "Implement Phase 4: Curb Intelligence including Parking Sign OCR, Hazard Mapping, and Storefront OCR on the M4."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Parking Sign OCR & Rules (Priority: P1)

As a rider scanning the curb, I want the system to automatically read parking signs and determine if parking is currently allowed at that location, so that I can easily find safe parking spots.

**Why this priority**: Parking rules are the most immediate and frequent pain point for riders. Automating the reading of signs provides immediate value.

**Independent Test**: Can be fully tested by feeding existing keyframes of parking signs into the inference module and verifying the OCR text and extracted parking rules in the dashboard without needing live video.

**Acceptance Scenarios**:

1. **Given** a frame containing a clear parking sign, **When** the M4 pipeline processes it, **Then** the OCR text is extracted and stored.
2. **Given** OCR text like "2 HR PARKING 8AM-6PM", **When** the system parses it, **Then** it correctly maps the restriction to a machine-readable time window.
3. **Given** the rider is reviewing the route map, **When** they click on a sign location, **Then** the UI clearly displays whether parking is currently legal based on the parsed rules and current time.

---

### User Story 2 - Hazard Mapping (Priority: P2)

As a fleet manager reviewing routes, I want the system to identify bike lane obstructions and potholes, so that I can proactively warn riders or report them to the city.

**Why this priority**: Focuses on safety and route quality, expanding CurbScout beyond just parking into a full street-level intelligence tool.

**Independent Test**: Can be tested independently by running object detection models optimized for cones, debris, and potholes on existing video frames and verifying the map populates with hazard markers.

**Acceptance Scenarios**:

1. **Given** a video containing a delivery truck parked in a bike lane, **When** processed by the hazard detector, **Then** a "Bike Lane Obstruction" hazard is flagged.
2. **Given** multiple rides pass the same hazard on different days, **When** the pipeline compares them, **Then** it tracks the duration the hazard has existed.
3. **Given** a plotted hazard on the GCP dashboard, **When** viewing the heatmap, **Then** areas with frequent hazards are highlighted distinctly from vehicle parking sightings.

---

### User Story 3 - Storefront Tracking (Priority: P3)

As an analyst, I want the system to extract storefront names and track changes over time, so that I can monitor business turnover along frequent routes.

**Why this priority**: Provides secondary economic data value, though less immediately critical to rider safety/parking than P1 and P2.

**Independent Test**: Can be tested independently by running OCR against storefronts and validating the text output across varying angles.

**Acceptance Scenarios**:

1. **Given** a clear view of a business awning, **When** the OCR pipeline runs, **Then** the business name is recorded as a sighting.
2. **Given** the same address previously recorded as "Joe's Cafe", **When** a new ride captures it as "Sarah's Bakery", **Then** the system logs a storefront change event.

---

### Edge Cases

- What happens when a parking sign is partially obscured by a tree or stickers? (System should flag a low-confidence reading requiring human review).
- How does the system handle conflicting parking signs on the same pole?
- What happens when hazard detection incorrectly identifies shadows as potholes?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The local pipeline MUST execute OCR on detected textual elements (signs, awnings) using the M4 ANE or GPU.
- **FR-002**: The system MUST parse raw OCR text from parking signs into structured temporal rules (e.g., allowed hours, duration limits).
- **FR-003**: The pipeline MUST detect specific hazard classes including "pothole", "construction", and "bike_lane_obstruction".
- **FR-004**: The system MUST correlate temporal hazards (same location across multiple rides) to track resolution time.
- **FR-005**: All generated intelligence (signs, hazards, storefronts) MUST utilize the existing `SIGHTING` schema or an extended variant to persist data via the GCP Sync Daemon.
- **FR-006**: The GCP Dashboard MUST visualize parking rules, hazards, and storefronts on the map with distinct interactive markers.

### Key Entities 

- **Intelligence Event**: An extension of `SIGHTING`. Includes the type (Sign, Hazard, Storefront), the raw extracted text or class, the confidence level, and parsed metadata JSON.
- **Location Rule**: A parsed representation of a parking sign, detailing the spatial boundary and time-based parking allowances.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Parking Sign OCR achieves >85% accuracy on clear, unobstructed signs.
- **SC-002**: Parking rule parser correctly structures >90% of standard municipal format signs in the target operational area.
- **SC-003**: Hazard detection achieves a false positive rate below 15% to prevent dashboard clutter.
- **SC-004**: Intelligence extraction pipeline adds no more than 2 seconds of processing time per second of video ingested on the M4.
