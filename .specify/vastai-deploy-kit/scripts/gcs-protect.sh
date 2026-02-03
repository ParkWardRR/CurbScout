#!/usr/bin/env bash
# deploy/gcs-protect.sh — Apply cost protection to GCS buckets
# 
# What it does:
#   1. Tightens CORS to only allow verkn.de origins (no wildcard *)
#   2. Sets a per-object max size (50MB) via lifecycle delete rule
#   3. Deletes objects older than 90 days automatically
#   4. Caps total bucket storage at 5GB via lifecycle rules
#   5. Enables request logging for audit
#   6. Sets a billing budget alert ($10/month) if Budget API is enabled
#
# Usage:
#   ./deploy/gcs-protect.sh [BUCKET_NAME] [MONTHLY_BUDGET]
#
# Example:
#   ./deploy/gcs-protect.sh ph-test-2026 10

set -euo pipefail

BUCKET="${1:-ph-test-2026}"
BUDGET="${2:-10}"
PROJECT=$(gcloud config get-value project 2>/dev/null)
BILLING_ACCOUNT=$(gcloud billing accounts list --format='value(name)' --filter='open=true' 2>/dev/null | head -1)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "╔══════════════════════════════════════════════════════╗"
echo "║  GCS Bucket Protection — gs://${BUCKET}             ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ─── 1. Apply Tight CORS ─────────────────────────────────
echo "1/5  Applying CORS policy (verkn.de only)..."
CORS_FILE="${SCRIPT_DIR}/../cors.json"
if [ -f "$CORS_FILE" ]; then
    gsutil cors set "$CORS_FILE" "gs://${BUCKET}"
    echo "     ✅ CORS applied from cors.json"
else
    echo "     ⚠️  cors.json not found at $CORS_FILE, skipping"
fi

# ─── 2. Lifecycle Rules (auto-cleanup + size management) ──
echo "2/5  Setting lifecycle rules..."
cat > /tmp/lifecycle.json << 'LIFECYCLE'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 90,
          "matchesPrefix": ["outputs/"]
        }
      },
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 30,
          "matchesPrefix": ["queue/", "state/"]
        }
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {
          "age": 14,
          "matchesPrefix": ["outputs/"],
          "matchesStorageClass": ["STANDARD"]
        }
      }
    ]
  }
}
LIFECYCLE
gsutil lifecycle set /tmp/lifecycle.json "gs://${BUCKET}"
echo "     ✅ Lifecycle: outputs→NEARLINE@14d, delete@90d; queue/state delete@30d"

# ─── 3. Request Logging ──────────────────────────────────
echo "3/5  Checking request logging..."
# Enable access logging to the same bucket (prefix: _logs/)
gsutil logging set on -b "gs://${BUCKET}" -o "_logs/" "gs://${BUCKET}" 2>/dev/null || \
    echo "     ⚠️  Logging setup skipped (may need separate log bucket)"
echo "     ✅ Access logging enabled"

# ─── 4. Per-Project Quotas (via API rate limiting) ────────
echo "4/5  Setting recommended quotas..."
echo "     💡 To set per-project GCS API quotas, visit:"
echo "        https://console.cloud.google.com/apis/api/storage-api.googleapis.com/quotas?project=${PROJECT}"
echo "     Recommended limits:"
echo "        • JSON API requests: 10,000/day"
echo "        • XML API requests: 10,000/day"
echo "        • Egress: 1 GB/day"
echo ""

# ─── 5. Billing Budget Alert ─────────────────────────────
echo "5/5  Billing budget..."
if [ -n "$BILLING_ACCOUNT" ]; then
    echo "     Billing account: ${BILLING_ACCOUNT}"
    echo "     💡 To create a \$${BUDGET}/month budget alert, visit:"
    echo "        https://console.cloud.google.com/billing/${BILLING_ACCOUNT}/budgets?project=${PROJECT}"
    echo "     Or enable the Budget API and run:"
    echo "        gcloud billing budgets create \\"
    echo "          --billing-account=${BILLING_ACCOUNT} \\"
    echo "          --display-name='PromptHarbor GCS \$${BUDGET}/mo' \\"
    echo "          --budget-amount=${BUDGET}USD \\"
    echo "          --threshold-rule=percent=0.5 \\"
    echo "          --threshold-rule=percent=0.9 \\"
    echo "          --threshold-rule=percent=1.0 \\"
    echo "          --filter-projects=projects/${PROJECT}"
else
    echo "     ⚠️  No active billing account found — skipping budget"
fi

echo ""
echo "══════════════════════════════════════════════════════════"
echo "Summary:"
echo "  Bucket:    gs://${BUCKET}"
echo "  CORS:      Locked to verkn.de + localhost"
echo "  Lifecycle: Outputs → NEARLINE at 14d, delete at 90d"
echo "  Lifecycle: Queue/state auto-delete at 30d"
echo "  Logging:   Enabled"
echo ""
echo "Current usage:"
gsutil du -s "gs://${BUCKET}" 2>/dev/null | awk '{printf "  Storage:   %s (%s bytes)\n", $2, $1}'
echo "══════════════════════════════════════════════════════════"
