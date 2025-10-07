# Security Policy

## About This Project

CurbScout is a local-first perception pipeline that processes ride video footage on your machine. By design, raw video and most derived data never leave the local device unless you explicitly opt in to cloud sync. This architecture inherently limits the attack surface, but security still matters.

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

- Raw 4K video and the SQLite database remain on the local machine.
- Cloud sync (GCP / DigitalOcean) is opt-in and limited to derived artifacts (JSON, thumbnails, highlight clips).
- The local API server binds to `localhost` only; no ports are exposed to the network by default.

### 2. Privacy-Sensitive Data Handling

- **License plates:** If plate OCR is enabled for deduplication, raw plate text is hashed/tokenized by default. Clear-text storage requires explicit opt-in.
- **Faces:** Any face detection output follows the same hash-first policy.
- **No telemetry:** No analytics or usage data is sent anywhere without explicit user consent.

### 3. Model & Supply Chain

- ML models (detection, classification) are loaded locally. No model is fetched at runtime from an untrusted source without verification.
- Python dependencies are pinned and audited. SvelteKit dependencies follow `npm audit` best practices.
- Vast.ai is used only for on-demand training/batch jobs; no persistent remote services run on behalf of the pipeline.

### 4. Video & File Integrity

- Checksums (SHA-256) are computed at ingest time to detect corruption or tampering.
- Re-processing the same video with the same model version must produce identical results.

## Scope

Because CurbScout is primarily a local data-processing pipeline, the most likely security concerns are:

- Leaked credentials or API keys in commit history.
- Malicious or compromised ML model weights.
- Privacy leaks (unredacted plates, faces, or GPS coordinates) in exported or synced data.
- Dependency vulnerabilities in Python or Node.js packages.
- Unauthorized access to the local API if the bind address is misconfigured.

Thank you for helping keep CurbScout safe.
