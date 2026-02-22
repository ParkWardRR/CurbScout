# Tasks: Phase 7 Native macOS Application

---

## Phase 7A: Xcode Project & SwiftData Models

- [x] T001 Create an Xcode project scaffold under `macos/CurbScout/` with SwiftUI app lifecycle.
- [x] T002 Define SwiftData `@Model` classes mirroring RIDE, VIDEO, SIGHTING, DETECTION tables.
- [x] T003 Implement SQLite read-only bridge to map existing `~/CurbScout/data/curbscout.db` into the app.

---

## Phase 7B: Sighting Review UI

- [x] T004 Build `SightingGridView` — a LazyVGrid of sighting thumbnails with classification overlays.
- [x] T005 Build `SightingDetailView` — enlarged crop, Make/Model/Year, confidence badge, and review action buttons.
- [x] T006 Implement review actions (confirm/correct/delete) writing directly to the local SQLite database.

---

## Phase 7C: Video Player

- [x] T007 Build `VideoPlayerView` using AVFoundation `AVPlayer` with frame-accurate seeking via `seekToTime`.
- [x] T008 Overlay detection bounding boxes on the video player at the corresponding timestamps.

---

## Phase 7D: System Integration

- [x] T009 Implement `MenuBarExtra` showing pipeline status (idle/processing/syncing) by reading a status file.
- [x] T010 Implement DiskArbitration observer to detect external camera mount and trigger pipeline auto-start.
