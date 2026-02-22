import os
import logging
from google.cloud import storage

from curbscout.db import get_connection, transaction

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("Model.Downloader")

GCS_BUCKET = os.environ.get("GCS_BUCKET", "curbscout-artifacts")
MODEL_DIR = os.path.expanduser('~/CurbScout/models')

def pull_latest_coreml_models():
    """
    Search GCS bucket for new active-learning exported CoreML INT8 model weights, 
    and pull them down dynamically to update the M4 prediction backend.
    """
    logger.info("Checking GCS Orchestration Hub for newly finetuned CoreML weights...")
    try:
        import httpx
        GCP_HUB_URL = os.environ.get("GCP_HUB_URL", "http://localhost:5173")
        res = httpx.get(f"{GCP_HUB_URL}/api/models/active", timeout=10.0)
        res.raise_for_status()
        
        data = res.json()
        if not data.get("has_active"):
            logger.info("No active deployed models tracked by Google Cloud Hub.")
            return

        model_info = data["model"]
        version = model_info.get("version", "unknown")
        gcs_uri = model_info.get("gcs_uri")
        
        if not gcs_uri or not gcs_uri.startswith("gs://"):
            logger.error(f"Malformed GCS URI returned for active model {version}. Got: {gcs_uri}")
            return
            
        logger.info(f"Hub reports deployed active model is version {version} at {gcs_uri}")
        
        bucket_name = gcs_uri.split("gs://")[1].split("/")[0]
        prefix = gcs_uri.split(f"gs://{bucket_name}/")[1]

        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)

        blobs = list(bucket.list_blobs(prefix=prefix))
        if not blobs:
            logger.info("GCS Folder target is empty.")
            return
            
        latest_blob = max(blobs, key=lambda b: b.time_created)
        
        if "best" in latest_blob.name:
            filename = os.path.basename(latest_blob.name)
            # Tag the local file with its lineage version for tracking natively
            local_filename = f"{version}_{filename}"
            local_path = os.path.join(MODEL_DIR, local_filename)
            
            if not os.path.exists(local_path):
                logger.info(f"Downloading newly minted {version} model weights: {filename}")
                latest_blob.download_to_filename(local_path)
                
                # Update symlinks so logic like detector.py automatically loads the newest INT8 CoreML
                active_link_path = os.path.join(MODEL_DIR, "yolov8n-active.pt") # fallback alias
                if os.path.exists(active_link_path) or os.path.islink(active_link_path):
                    os.remove(active_link_path)
                os.symlink(local_path, active_link_path)
                
            else:
                logger.debug(f"Local {version} model already downloaded and active.")
                
    except Exception as e:
        logger.error(f"Failed to pull latest models via Active Hub querying: {e}")

if __name__ == "__main__":
    pull_latest_coreml_models()
