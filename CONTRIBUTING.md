# Contributing to CurbScout

> **Audience:** Contributors and maintainers.
> Thank you for your interest in CurbScout! This document explains how to set up, contribute, and get your changes merged.

## How to Contribute

### 1. Fork & Clone

```bash
git clone https://github.com/ParkWardRR/CurbScout.git
cd CurbScout
```

### 2. Set Up the Development Environment

CurbScout has two main components — a **Python pipeline + API backend** and a **SvelteKit review UI**.

#### Python (pipeline + API)

| Tool | Minimum Version | Purpose |
|---|---|---|
| Python | 3.11+ | Pipeline, API backend |
| uv | latest | Virtual environment & dependency management |
| ffmpeg | 6.x+ | Video processing |
| SQLite | 3.35+ | Local persistence |

```bash
# Create virtual environment and install deps
uv venv && source .venv/bin/activate
uv pip install -r requirements.txt

# Verify
python --version
ffmpeg -version
```

#### SvelteKit (review UI)

| Tool | Minimum Version | Purpose |
|---|---|---|
| Node.js | 20+ | JavaScript runtime |
| npm | 10+ | Package manager |

```bash
cd ui
npm install
npm run dev
```

### 3. Create a Branch

```bash
git checkout -b feature/your-feature-name
```

### 4. Make Your Changes

Follow the coding standards below, then open a pull request.

---

## Coding Standards

### Python

- **Formatting:** `ruff format`. No exceptions.
- **Linting:** `ruff check`. All warnings are errors in CI.
- **Type hints:** Required on all public functions and methods.
- **Docstrings:** Google style on all public functions, classes, and modules.
- **No bare `except`.** Always catch specific exceptions.
- **No `print()` in library code.** Use `logging` or `structlog`.

### SvelteKit / JavaScript

- **Formatting:** Prettier with project defaults.
- **Linting:** ESLint with project config.
- **Svelte 5:** Use runes (`$state`, `$derived`, `$effect`) — no legacy reactive stores in new code.
- **Accessibility:** All interactive elements must be keyboard-navigable.

### General

- **Commit messages:** Imperative mood, present tense. First line under 72 characters. Body explains *why*, not *what*.
- **Comments:** Explain *why*, not *what*. Code should be self-documenting.
- **Magic numbers:** Named constants, always.

---

## What to Work On

### Good First Contributions

- Improving documentation or fixing typos.
- Adding test coverage to pipeline stages.
- UI polish — animations, dark mode refinements, accessibility fixes.
- Adding new vehicle make/model entries to the classifier training data.

### Areas That Need Help

- Vehicle detection & classification improvements.
- Deduplication algorithm tuning.
- macOS-specific integration (Core ML, folder watcher).
- Parking sign OCR and rule parsing (Phase 5).

---

## Testing

### Python Tests

```bash
# Run all tests
pytest

# With coverage
pytest --cov=curbscout --cov-report=term-missing
```

### SvelteKit Tests

```bash
cd ui
npm run test
```

### Pre-Commit Checks

Before opening a PR, make sure everything passes:

```bash
ruff format --check .
ruff check .
pytest
cd ui && npm run lint && npm run check
```

---

## Pull Request Guidelines

1. **Keep PRs focused.** One logical change per PR. Under 400 lines of diff is ideal.
2. **Write a clear title and description.** State what changed, why, and how to test it.
3. **Self-review first.** Read your own diff before requesting review.
4. **Link to the roadmap.** Reference the phase/task this PR addresses.
5. **Respect local-first.** Do not introduce cloud dependencies in Phase 1 code paths.
6. **Privacy by default.** Any code handling video, plates, or PII must follow the constitution's privacy principles.

---

## Architecture Notes

CurbScout follows a **local-first, spec-driven** architecture:

- **Pipeline:** ingest → segment → sample frames → detect → crop → classify → dedupe → persist.
- **Storage:** SQLite for structured data; filesystem for video and image assets.
- **UI:** SvelteKit served from `localhost`, communicating with a local Python API.
- **Cloud (later phases):** Only derived artifacts (JSON + thumbnails) sync to GCP/DO.

Read the [constitution](.specify/memory/constitution.md) for the full set of development principles.

---

## License

By contributing, you agree that your contributions will be licensed under the
[Blue Oak Model License 1.0.0](./LICENSE.md).
