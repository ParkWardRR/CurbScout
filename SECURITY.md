# Security Policy

## About This Project

CurbScout is a hub-and-spoke perception pipeline that processes ride video footage locally on M4 Mac minis and syncs derived intelligence to a GCP-hosted dashboard. Raw video stays local by default. The system includes fleet management with worker registration, automated model training via Vast.ai, and a native macOS app. This multi-tier architecture introduces specific security considerations.

## Supported Versions

| Version | Supported | Notes |
| ------- | ------------------ | ------------------------------------------------------------------ |
| `0.x.y` | :white_check_mark: | Active development. Breaking changes possible. |
| `main`  | :white_check_mark: | Latest development snapshot. |

## Reporting a Vulnerability

Please **do not** report security vulnerabilities through public GitHub issues.

Instead, report them responsibly:

1. Open a [GitHub Security Advisory](https://docs.github.com/en/code-security/security-advisories/working-with-repository-security-advisories/creating-a-repository-security-advisory) on this repository, **or**
2. Contact the project maintainer directly at **[ParkWardRR](https://github.com/ParkWardRR)** via GitHub private messaging.
3. Include a clear description of the concern and steps to reproduce (if applicable).

## Response Timeline

- **Acknowledgement:** within 72 hours.
- **Resolution or update:** within 14 days of acknowledgement.

## Security Posture

### 1. Local-First by Default

- Raw 4K video and the SQLite database remain on the local M4 Mac mini.
- Cloud sync to GCP (Firestore/GCS) is limited to derived artifacts (sighting metadata, crop thumbnails, model weights).
- The local API server binds to `localhost` only; no ports are exposed to the network by default.
- The native macOS app reads directly from local SQLite — no network required for review.

### 2. Privacy-Sensitive Data Handling

- **License plates:** If plate OCR is enabled for deduplication, raw plate text is hashed/tokenized by default. Clear-text storage requires explicit opt-in.
- **Faces:** Any face detection output follows the same hash-first policy.
- **No telemetry:** No analytics or usage data is sent anywhere without explicit user consent.

### 3. Model & Supply Chain

- ML models (detection, classification) are loaded locally. No model is fetched at runtime from an untrusted source without verification.
- Python dependencies are pinned via `uv.lock` and audited. SvelteKit dependencies follow `npm audit` best practices.
- Vast.ai is used only for on-demand training jobs; ephemeral instances auto-destroy after completion.
- The Vast.ai export webhook (`POST /api/webhooks/vast-export`) is authenticated via API key. Model artifacts are verified before deployment.
- The M4 `sync_models.py` only pulls model weights from GCS URIs registered in the Hub's `MODELS` Firestore collection.

### 4. Fleet & Multi-Device

- Worker registration (`POST /api/workers/register`) authenticates workers before accepting sync data.
- All synced data carries `worker_id` provenance for audit trails.
- Heartbeat protocol detects stale/compromised workers within 5 minutes.

### 4. Video & File Integrity

- Checksums (SHA-256) are computed at ingest time to detect corruption or tampering.
- Re-processing the same video with the same model version must produce identical results.

## Scope

Because CurbScout is primarily a local data-processing pipeline, the most likely security concerns are:

- Leaked credentials or API keys in commit history (GCP service accounts, Vast.ai API keys, worker tokens).
- Malicious or compromised ML model weights uploaded via the deployment webhook.
- Privacy leaks (unredacted plates, faces, or GPS coordinates) in exported or synced data.
- Dependency vulnerabilities in Python, Node.js, or Swift packages.
- Unauthorized access to the GCP Hub API endpoints (sync, webhooks, fleet management).
- Rogue worker registration — an unauthorized device syncing poisoned data into the shared dataset.
- Model lineage tampering — corrupted `lineage_ids` pointing to wrong training data.

Thank you for helping keep CurbScout safe.
