# Tasks: Phase 6 Multi-Device Collaboration

**Input**: Design documents from `/specs/004-multi-device-collab/`

---

## Phase 6A: Worker Registration & Heartbeat

- [x] T001 Add `Worker` interface to `types.ts` with `id`, `hostname`, `hardware`, `status`, `last_seen`, `sighting_count`, `ride_count`.
- [x] T002 Add `worker_id` field to `Sighting` and `Ride` interfaces.
- [x] T003 Implement `POST /api/workers/register` — creates or updates a worker document in Firestore.
- [x] T004 Implement `POST /api/workers/heartbeat` — updates `last_seen` and marks worker `online`.
- [x] T005 Implement `GET /api/workers` — returns all workers, marking stale ones (>5min since heartbeat) as `offline`.
- [x] T006 Add worker registration and heartbeat calls to the M4 pipeline's `main.py` startup and daemon loop.

---

## Phase 6B: Multi-Rider Data Attribution

- [x] T007 Update `/api/sync` to accept and persist `worker_id` on rides and sightings.
- [x] T008 Update the M4 pipeline `sync.py` to include the local `worker_id` (from env or config) in sync payloads.

---

## Phase 6C: Fleet Management Dashboard

- [x] T009 Create `web/src/routes/fleet/+page.server.ts` loading workers from Firestore.
- [x] T010 Create `web/src/routes/fleet/+page.svelte` — Fleet Management dashboard showing worker cards with status indicators, last sync time, contribution counts.
- [x] T011 Add `/fleet` to the sidebar navigation in `+layout.svelte`.
- [x] T012 Add per-reviewer leaderboard section to the Fleet page showing correction counts by reviewer identity.
