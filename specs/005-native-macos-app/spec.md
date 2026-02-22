# Feature Specification: Native macOS Application

**Feature Branch**: `005-native-macos-app`  
**Created**: 2026-02-21  
**Status**: Draft

## Overview

Port the SvelteKit review UI to a native SwiftUI application running on the M4 Mac mini. This provides a local-first experience for sighting review, video scrubbing, and pipeline monitoring without requiring a browser or internet connection to the GCP Hub.

## User Scenarios

### User Story 1 — Local Sighting Review (P1)

As a rider reviewing today's ride on my M4 Mac mini, I want a native SwiftUI app that reads directly from the local SQLite database, so I can review sightings instantly without waiting for GCP sync.

### User Story 2 — Video Scrubbing (P1)

As a reviewer, I want to scrub through the original ride video with frame-accurate seeking using AVFoundation, so I can verify detections in their temporal context.

### User Story 3 — Menu Bar Status (P2)

As an operator, I want a menu bar icon that shows pipeline status (idle/processing/syncing), so I can monitor the system at a glance.

### User Story 4 — Auto-Launch on Camera (P3)

As a rider returning from a ride, I want the app to auto-launch when my GoPro/dashcam mounts via USB, so the ingestion pipeline starts automatically.

## Requirements

- **FR-001**: SwiftUI app reading from the existing SQLite database at `~/CurbScout/data/curbscout.db`.
- **FR-002**: Sighting grid with crop thumbnails, classification info, and review actions (confirm/correct/delete).
- **FR-003**: AVFoundation-based video player with frame-accurate scrubbing.
- **FR-004**: Menu bar extra showing pipeline daemon status.
- **FR-005**: DiskArbitration/IOKit observer for external camera mount detection.
- **FR-006**: App uses SwiftData models mirroring the SQLite schema.

## Success Criteria

- **SC-001**: App launches and displays sightings within 500ms of opening.
- **SC-002**: Video scrubbing is frame-accurate with <100ms seek latency.
- **SC-003**: Menu bar indicator reflects real pipeline state within 5 seconds.
