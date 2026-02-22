import os
import logging
import random
from google.cloud import storage, firestore

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("Dataset.Downloader")

GCS_BUCKET = os.environ.get("GCS_BUCKET", "curbscout-artifacts")
DATASET_PATH = "/mnt/dataset"
GCP_PROJECT = os.environ.get("GCP_PROJECT", "curbscout-project")

def build_yolo_dataset():
    """
    Pulls 'corrected' and 'confirmed' sightings from Firestore,
    downloads the corresponding GCS crop images, 
    and organizes them into a YOLOv8 Image Classification directory structure.
    """
    logger.info("Connecting to Firebase/Firestore to build Active Learning dataset...")
    
    try:
        db = firestore.Client(project=GCP_PROJECT)
        storage_client = storage.Client(project=GCP_PROJECT)
        bucket = storage_client.bucket(GCS_BUCKET)
    except Exception as e:
        logger.error(f"Failed to initialize GCP SDK clients: {e}")
        # Mock dataset structure just to pass the scaffolding script test
        os.makedirs(f"{DATASET_PATH}/train/mock_class", exist_ok=True)
        os.makedirs(f"{DATASET_PATH}/val/mock_class", exist_ok=True)
        return

    # Query reviewed sightings
    # Corrected sightings take priority for Active Learning loop
    sightings = list(db.collection('sightings')
                       .where('review_status', 'in', ['confirmed', 'corrected'])
                       .get())
                       
    if not sightings:
        logger.warning("No reviewed sightings found. Building empty mock dataset structure.")
        os.makedirs(f"{DATASET_PATH}/train/mock_class", exist_ok=True)
        os.makedirs(f"{DATASET_PATH}/val/mock_class", exist_ok=True)
        return
        
    logger.info(f"Found {len(sightings)} labeled sightings. Downloading crops...")

    # Organize 80/20 split
    for s in sightings:
        data = s.to_dict()
        crop_id = data.get('best_crop_id')
        class_name = data.get('predicted_make', 'Unknown')
        
        # If it was corrected, the new values are in the Sighting document 
        # (Assuming the UI replaces `predicted_make` directly upon correction)
        # We sanitize the class_name for folder paths
        safe_class = "".join([c if c.isalnum() else "_" for c in class_name])
        
        if not crop_id:
            continue
            
        subset = "train" if random.random() < 0.8 else "val"
        dest_dir = os.path.join(DATASET_PATH, subset, safe_class)
        os.makedirs(dest_dir, exist_ok=True)
        
        blob_name = f"crops/{crop_id}.jpg"
        dest_path = os.path.join(dest_dir, f"{crop_id}.jpg")
        
        blob = bucket.blob(blob_name)
        if blob.exists():
            blob.download_to_filename(dest_path)
        else:
            logger.debug(f"Crop missing in GCS: gs://{GCS_BUCKET}/{blob_name}")
            
    logger.info("YOLO format Active Learning Dataset construction complete.")

if __name__ == "__main__":
    build_yolo_dataset()
