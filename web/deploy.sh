#!/bin/bash
set -eo pipefail

echo "Deploying CurbScout Web Dashboard to GCP Cloud Run..."

PROJECT_ID=${GOOGLE_CLOUD_PROJECT:-"curbscout-project"}
REGION=${GCP_LOCATION:-"us-central1"}
SERVICE_NAME="curbscout-dashboard"

# Ensure gcloud is configured
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud CLI not found. Please install the Google Cloud SDK."
    exit 1
fi

echo "Building and pushing container via Cloud Build..."
gcloud builds submit --tag gcr.io/$PROJECT_ID/$SERVICE_NAME

echo "Deploying to Cloud Run..."
gcloud run deploy $SERVICE_NAME \
    --image gcr.io/$PROJECT_ID/$SERVICE_NAME \
    --platform managed \
    --region $REGION \
    --allow-unauthenticated \
    --port 8080 \
    --max-instances 2 \
    --memory 512Mi \
    --cpu 1 \
    --set-env-vars=GOOGLE_CLOUD_PROJECT=$PROJECT_ID,GCP_LOCATION=$REGION,M4_QUEUE_NAME=m4-inference-queue,VAST_QUEUE_NAME=vast-training-queue

echo "Deployment complete! ✅"
