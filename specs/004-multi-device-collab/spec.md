# Feature Specification: Multi-Device Collaboration

**Feature Branch**: `004-multi-device-collab`  
**Created**: 2026-02-21  
**Status**: ✅ Implemented  
**Merged**: 2026-02-21

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Worker Registration (Priority: P1)

As a fleet operator deploying multiple M4 Mac minis across different vehicles, I want each worker to register itself with the GCP Hub on first boot, so the Hub knows which devices are active and can route jobs accordingly.

**Acceptance Scenarios**:

1. **Given** a fresh M4 worker boots the pipeline for the first time, **When** it calls `POST /api/workers/register`, **Then** a `WORKER` document is created in Firestore with its hardware fingerprint, hostname, and capabilities.
2. **Given** a registered worker pings the Hub periodically, **When** the Hub receives the heartbeat, **Then** it updates the worker's `last_seen` timestamp and marks it `online`.
3. **Given** a worker hasn't heartbeated in 5 minutes, **When** the Hub queries workers, **Then** it marks that worker `offline`.

---

### User Story 2 — Multi-Rider Sighting Pool (Priority: P1)

As a team of riders, we want all of our sighting data to flow into a single shared Firestore dataset, so that our combined coverage creates a richer street-level intelligence map.

**Acceptance Scenarios**:

1. **Given** Worker-A syncs 50 sightings and Worker-B syncs 30, **When** the Hub dashboard loads, **Then** all 80 sightings render on the map and in analytics.
2. **Given** sightings from different workers, **When** viewing a sighting, **Then** the UI shows which worker/rider contributed it.

---

### User Story 3 — Per-User Review Progress (Priority: P2)

As a fleet manager, I want to see each reviewer's individual progress (how many sightings they've confirmed/corrected), so I can track team throughput.

**Acceptance Scenarios**:

1. **Given** multiple reviewers have corrected sightings, **When** viewing the Team dashboard, **Then** a leaderboard shows each reviewer's correction count and confirmation rate.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Implement a `WORKERS` Firestore collection tracking device identity, capabilities, status, and heartbeat.
- **FR-002**: Extend the `/api/sync` endpoint to accept a `worker_id` field, tagging all synced data with its origin device.
- **FR-003**: Add `worker_id` to the `Sighting` and `Ride` interfaces so the Hub can attribute data provenance.
- **FR-004**: Implement a `GET /api/workers` endpoint returning all registered workers and their statuses.
- **FR-005**: Create a Fleet Management dashboard page showing online/offline workers, their last sync time, and contribution counts.
- **FR-006**: Add per-reviewer progress tracking by extending the review actions to log the reviewer's identity.

## Success Criteria *(mandatory)*

- **SC-001**: Two or more workers can simultaneously sync data to the Hub without conflicts.
- **SC-002**: The Fleet dashboard correctly shows online/offline status within 60 seconds of a worker going dark.
- **SC-003**: Sighting provenance (which worker contributed it) is queryable from the dashboard.
