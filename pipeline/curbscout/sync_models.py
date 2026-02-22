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
        storage_client = storage.Client()
        bucket = storage_client.bucket(GCS_BUCKET)
    except Exception as e:
        logger.warning(f"GCP Storage client uninitialized (mocking out download): {e}")
        return
        
    os.makedirs(MODEL_DIR, exist_ok=True)
        
    try:
        # We assume export.sh uploads `best.mlpackage` into models/cls_<timestamp>/
        blobs = list(bucket.list_blobs(prefix="models/"))
        if not blobs:
            logger.info("No remote models found.")
            return
            
        # Example logic looking for coreml zipped packages
        # Since .mlpackage is a directory, vast.ai export_teardown.py should zip it.
        # Here we mock finding a best.pt or best.mlmodel
        latest_blob = max(blobs, key=lambda b: b.time_created)
        
        if "best" in latest_blob.name:
            filename = os.path.basename(latest_blob.name)
            local_path = os.path.join(MODEL_DIR, filename)
            
            if not os.path.exists(local_path):
                logger.info(f"Downloading new model weights: {filename}")
                latest_blob.download_to_filename(local_path)
            else:
                logger.debug("M4 Local models are already up to date with Vast.ai exports.")
                
    except Exception as e:
        logger.error(f"Failed to pull latest models: {e}")

if __name__ == "__main__":
    pull_latest_coreml_models()
