import os
import glob
import logging
import httpx
from google.cloud import storage

from curbscout.vast_client import VastClient

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("Upload&Teardown")

GCS_BUCKET = os.environ.get("GCS_BUCKET", "curbscout-artifacts")
GCP_HUB_URL = os.environ.get("GCP_HUB_URL", "http://localhost:5173") 
WORKER_API_KEY = os.environ.get("WORKER_API_KEY", "dev-worker-key")
VAST_INSTANCE_ID = os.environ.get("VAST_INSTANCE_ID")

def upload_models():
    """Identifies export formats and pushes them to GCS iteratively."""
    logger.info("Locating exported artifacts for upload...")
    
    # Normally we grab the latest run based on os.path.getmtime
    search_dirs = glob.glob('/mnt/training_runs/curbscout-finetune*/weights/')
    if not search_dirs:
        logger.warning("No weights directory found. Skipping GCS push.")
        return []
        
    latest_run_dir = max(search_dirs, key=os.path.getmtime)
    
    models_to_upload = glob.glob(os.path.join(latest_run_dir, "best.*"))
    uploaded_gcs_paths = []
    
    try:
        storage_client = storage.Client()
        bucket = storage_client.bucket(GCS_BUCKET)
    except Exception as e:
        logger.warning(f"GCP Storage client uninitialized (mocking for test): {e}")
        return models_to_upload
        
    timestamp = str(int(os.path.getmtime(latest_run_dir)))
    
    for model_path in models_to_upload:
        filename = os.path.basename(model_path)
        blob_name = f"models/cls_{timestamp}/{filename}"
        
        logger.info(f"Uploading {model_path} -> gs://{GCS_BUCKET}/{blob_name}")
        blob = bucket.blob(blob_name)
        blob.upload_from_filename(model_path)
        uploaded_gcs_paths.append(blob_name)
        
    return uploaded_gcs_paths

def log_completion_to_firestore(artifacts: list):
    """
    Ping the API Hub REST interface running on GCP Cloud Run to update the Cloud Task Status
    and register the new model version for inference swapping down on the M4.
    """
    if not GCP_HUB_URL or not artifacts:
        return
        
    logger.info("Reporting task collection to the Hub Webhook API")
    # Retrieve MODEL_ID passed down ideally from the job trigger
    model_id = os.environ.get("MODEL_ID", "mock-model-id-for-tests")
    
    # We use the folder URI for the model bundle
    gcs_uri = f"gs://{GCS_BUCKET}/{artifacts[0].rsplit('/', 1)[0]}/" if artifacts else "unknown"
    
    payload = {
        "model_id": model_id,
        "gcs_uri": gcs_uri
    }
    
    try:
        vast_api_key = os.environ.get("VAST_API_KEY", "vast-dev-key")
        res = httpx.post(
            f"{GCP_HUB_URL}/api/webhooks/vast-export", 
            json=payload, 
            headers={"Authorization": f"Bearer {vast_api_key}"},
            timeout=10.0
        )
        res.raise_for_status()
        logger.info(f"Hub officially registered deploy: {res.json()}")
    except Exception as e:
        logger.error(f"Cannot reach GCP Webhook at {GCP_HUB_URL}: {e}")

def destroy_self():
    """Immediately kill the ephemeral Vast instance via Vast client API."""
    if not VAST_INSTANCE_ID:
        logger.warning("No VAST_INSTANCE_ID passed in environment, cannot inherently kill.")
        return
        
    logger.info(f"Tearing down Ephemeral Unit {VAST_INSTANCE_ID}. Stopping billing.")
    client = VastClient()
    client.destroy_instance(int(VAST_INSTANCE_ID))
    
    # We exit gracefully; the OS will physically die out from under us momentarily
    # Shutdown locally to force process ends if the HTTP call lags
    os.system("shutdown -h now")

if __name__ == "__main__":
    artifacts = upload_models()
    log_completion_to_firestore(artifacts)
    destroy_self()
