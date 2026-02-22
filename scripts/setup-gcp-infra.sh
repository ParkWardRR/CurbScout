#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# CurbScout — GCP Infrastructure Setup
# Run once to provision Cloud Scheduler, Cloud Tasks queues, and IAM.
# Requires: gcloud CLI authenticated with project owner/editor access.
# ──────────────────────────────────────────────────────────────────────

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-curbscout-project}"
REGION="${GCP_REGION:-us-central1}"
CLOUD_RUN_URL="${CLOUD_RUN_URL:-https://curbscout-hub-HASH-uc.a.run.app}"

echo "═══ CurbScout Infrastructure Setup ═══"
echo "Project: ${PROJECT_ID}"
echo "Region:  ${REGION}"
echo ""

# ── Enable Required APIs ──
echo "→ Enabling APIs..."
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  cloudtasks.googleapis.com \
  cloudscheduler.googleapis.com \
  firestore.googleapis.com \
  storage.googleapis.com \
  artifactregistry.googleapis.com \
  --project="${PROJECT_ID}" \
  --quiet

# ── Create Artifact Registry Repo ──
echo "→ Creating Artifact Registry repo..."
gcloud artifacts repositories create curbscout \
  --repository-format=docker \
  --location="${REGION}" \
  --description="CurbScout container images" \
  --project="${PROJECT_ID}" \
  --quiet 2>/dev/null || echo "  (already exists)"

# ── Create Cloud Tasks Queues ──
echo "→ Creating Cloud Tasks queues..."

gcloud tasks queues create m4-inference \
  --location="${REGION}" \
  --max-dispatches-per-second=1 \
  --max-concurrent-dispatches=1 \
  --project="${PROJECT_ID}" \
  --quiet 2>/dev/null || echo "  m4-inference queue exists"

gcloud tasks queues create vast-training \
  --location="${REGION}" \
  --max-dispatches-per-second=1 \
  --max-concurrent-dispatches=1 \
  --max-retry-duration=3600s \
  --project="${PROJECT_ID}" \
  --quiet 2>/dev/null || echo "  vast-training queue exists"

# ── Create Cloud Scheduler Job (Auto-Training Trigger) ──
echo "→ Creating Cloud Scheduler cron job..."

# Delete existing if present (idempotent)
gcloud scheduler jobs delete auto-train-trigger \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --quiet 2>/dev/null || true

gcloud scheduler jobs create http auto-train-trigger \
  --schedule="0 */4 * * *" \
  --uri="${CLOUD_RUN_URL}/api/jobs/trigger-auto-train" \
  --http-method=GET \
  --location="${REGION}" \
  --description="Every 4 hours, evaluate if enough corrections exist to trigger an auto-training job on Vast.ai" \
  --attempt-deadline=120s \
  --project="${PROJECT_ID}" \
  --quiet

echo "  ✅ Scheduled: every 4 hours → /api/jobs/trigger-auto-train"

# ── Deploy Firestore Rules & Indexes ──
echo "→ Deploying Firestore rules and indexes..."
if command -v firebase &> /dev/null; then
  firebase deploy --only firestore --project="${PROJECT_ID}"
  echo "  ✅ Firestore rules and indexes deployed"
else
  echo "  ⚠️  Firebase CLI not installed — run: npm install -g firebase-tools"
  echo "     Then: firebase deploy --only firestore --project=${PROJECT_ID}"
fi

echo ""
echo "═══ Infrastructure Setup Complete ═══"
echo ""
echo "Next steps:"
echo "  1. Set CLOUD_RUN_URL in GitHub Secrets"
echo "  2. Set GCP_PROJECT_ID, WIF_PROVIDER, WIF_SERVICE_ACCOUNT in GitHub Secrets"
echo "  3. Push to main to trigger first CI/CD deploy"
echo "  4. Verify Cloud Scheduler at: https://console.cloud.google.com/cloudscheduler?project=${PROJECT_ID}"
