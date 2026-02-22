#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
# CurbScout Local CI — Run all checks before pushing
# Usage: ./scripts/ci.sh
# ──────────────────────────────────────────────────────────

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

run_check() {
    local name="$1"
    shift
    echo -e "${YELLOW}▶ ${name}${NC}"
    if "$@" 2>&1; then
        echo -e "  ${GREEN}✓ ${name} passed${NC}\n"
        ((PASS++))
    else
        echo -e "  ${RED}✗ ${name} FAILED${NC}\n"
        ((FAIL++))
    fi
}

echo "═══════════════════════════════════════"
echo "  CurbScout Local CI"
echo "═══════════════════════════════════════"
echo ""

# ── Web (SvelteKit) ──
if [ -d "web" ]; then
    run_check "Svelte Type Check" bash -c "cd web && npm run check"
fi

# ── Python Pipeline ──
if [ -d "pipeline" ]; then
    if command -v uv &> /dev/null; then
        run_check "Ruff Format Check" bash -c "cd pipeline && uv run ruff format --check ."
        run_check "Ruff Lint" bash -c "cd pipeline && uv run ruff check ."
    elif command -v ruff &> /dev/null; then
        run_check "Ruff Format Check" bash -c "cd pipeline && ruff format --check ."
        run_check "Ruff Lint" bash -c "cd pipeline && ruff check ."
    else
        echo -e "${YELLOW}⚠ Skipping Python lint (ruff not found)${NC}\n"
    fi
fi

# ── Docker Build ──
if command -v docker &> /dev/null && [ -f "web/Dockerfile" ]; then
    run_check "Docker Build" docker build -t curbscout-web:ci-local ./web
else
    echo -e "${YELLOW}⚠ Skipping Docker build (docker not available)${NC}\n"
fi

# ── Swift Compile Check ──
if command -v swift &> /dev/null && [ -d "macos/CurbScout/CurbScout" ]; then
    run_check "Swift Syntax Check" bash -c "find macos/CurbScout/CurbScout -name '*.swift' -exec swift -typecheck {} +"
else
    echo -e "${YELLOW}⚠ Skipping Swift check (swift not available or no project)${NC}\n"
fi

# ── Results ──
echo "═══════════════════════════════════════"
echo -e "  ${GREEN}Passed: ${PASS}${NC}  ${RED}Failed: ${FAIL}${NC}"
echo "═══════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
    echo -e "\n${RED}CI FAILED — fix errors before pushing.${NC}"
    exit 1
else
    echo -e "\n${GREEN}All checks passed. Safe to push.${NC}"
fi
