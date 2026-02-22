import os
import uuid
import datetime
import logging
import json
from PIL import Image
from typing import List

from .db import get_connection, transaction
from .accelerator import Backend

# Note: In a production MVP, we'd use ONNX Runtime or CoreML to run Jordo23/vehicle-classifier.
# For this scaffold, we will simulate the classification output to establish the pipeline flow.
# In a real environment, you'd load the model via `accelerator.create_onnx_session()`.

logger = logging.getLogger(__name__)

def load_classifier(model_path: str = "models/vehicle_classifier.onnx"):
    """
    Loads the primary tiered classifier (e.g. Jordo23 EfficientNet).
    Currently mocked to avoid pulling large weights during setup.
    """
    logger.info(f"Loading classifier strategy from {model_path} (mocked for MVP scaffolding)")
    return "MOCK_MODEL"

def check_sanity(make: str, model: str, year: str) -> tuple[bool, str]:
    """
    Validates impossible badge/year combinations.
    """
    if "440i" in model and year and int(year) < 2014:
        return True, "4 Series production started in 2014"
    return False, ""

def classify_vehicle(crop_path: str, classifier_model) -> dict:
    """
    Runs the crop through the classifier to predict make, model, and year.
    Returns mocked results for the scaffolding.
    """
    # Simulated prediction
    if not os.path.exists(crop_path):
        return {
            'make': 'Unknown',
            'model': 'Vehicle',
            'year': None,
            'confidence': 0.1,
            'year_confidence': 'none'
        }
        
    # Dummy mock logic - normally we'd run ONNX inference here
    return {
        'make': 'BMW',
        'model': '3 Series',
        'year': '2020',
        'confidence': 0.85,
        'year_confidence': 'medium'
    }

def get_unclassified_detections() -> List[dict]:
    """Find DETECTION records without an associated SIGHTING."""
    conn = get_connection()
    c = conn.cursor()
    c.execute('''
        SELECT d.id as det_id, d.crop_path, d.frame_asset_id, d.class, 
               f.video_id, f.video_timestamp_sec, v.ride_id
        FROM DETECTION d
        JOIN FRAME_ASSET f ON d.frame_asset_id = f.id
        JOIN VIDEO v ON f.video_id = v.id
        WHERE d.sighting_id IS NULL
        LIMIT 500
    ''')
    rows = c.fetchall()
    conn.close()
    return [dict(r) for r in rows]

def run_classification_batch():
    detections = get_unclassified_detections()
    if not detections:
        logger.info("No unclassified detections found.")
        return
        
    clf = load_classifier()
    conn = get_connection()
    
    now_iso = datetime.datetime.utcnow().isoformat() + 'Z'
    logger.info(f"Classifying {len(detections)} crops...")
    
    with transaction(conn) as t:
        for det in detections:
            preds = classify_vehicle(det['crop_path'], clf)
            
            # Sanity check
            sanity_warn, warn_text = check_sanity(preds['make'], preds['model'], preds['year'])
            
            sighting_id = str(uuid.uuid4())
            
            # Predict a timestamp for the sighting by assuming video start time + offset
            # (In a rigorous system we'd join Video.start_ts, but for MVP scaffolding we use now)
            
            import random
            mock_lat = 37.7749 + (random.uniform(-0.05, 0.05))
            mock_lng = -122.4194 + (random.uniform(-0.05, 0.05))
            
            t.execute('''
                INSERT INTO SIGHTING (
                    id, ride_id, best_crop_id, timestamp, 
                    predicted_make, predicted_model, predicted_year, 
                    classification_confidence, year_confidence, classifier_model_ver,
                    needs_review, sanity_warning, sanity_warning_text, review_status,
                    lat, lng,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, 'pending', ?, ?, ?, ?)
            ''', (
                sighting_id, det['ride_id'], det['frame_asset_id'], now_iso,
                preds['make'], preds['model'], preds['year'],
                preds['confidence'], preds['year_confidence'], 'jordo23-effnet-b4-mock',
                sanity_warn, warn_text,
                mock_lat, mock_lng,
                now_iso, now_iso
            ))
            
            # Update detection
            t.execute('UPDATE DETECTION SET sighting_id = ? WHERE id = ?', (sighting_id, det['det_id']))
            
    logger.info("Classification batch completed.")

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    run_classification_batch()
