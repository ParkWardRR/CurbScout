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

from .ocr import process_sign_crop
from .rules import parse_parking_rules

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
    logger.info(f"Classifying {len(detections)} crops across Intelligence engines...")
    
    with transaction(conn) as t:
        import random
        for det in detections:
            sighting_id = str(uuid.uuid4())
            det_class = det.get('class', 'car')
            
            mock_lat = 37.7749 + (random.uniform(-0.05, 0.05))
            mock_lng = -122.4194 + (random.uniform(-0.05, 0.05))
            
            # Default payload structure
            s_make = "Unknown"
            s_model = "Unknown"
            s_year = None
            s_conf = 1.0
            y_conf = "none"
            s_mod_ver = "coreml-pipeline-v1"
            sanity_warn = False
            warn_text = None
            attrs_json = "{}"
            
            # Intelligence Forking
            if det_class == 'parking_sign':
                # Route to Phase 4a OCR Engine
                raw_text = process_sign_crop(det['crop_path'])
                rules = parse_parking_rules(raw_text)
                
                s_make = "parking_sign"
                s_model = raw_text[:50].replace('\n', ' ') if raw_text else "No Text Detected"
                s_conf = 0.95
                y_conf = "high"
                attrs_json = json.dumps(rules)
                
            elif det_class in ['pothole', 'bike_lane_obstruction']:
                # Route to Phase 4b Hazard Engine
                s_make = "hazard"
                s_model = det_class
                s_conf = 0.92
                y_conf = "high"
                if det_class == 'bike_lane_obstruction':
                    sanity_warn = True
                    warn_text = "Bike Lane Blocked"
                    
            else:
                # Standard Phase 1 Vehicle Classification
                preds = classify_vehicle(det['crop_path'], clf)
                sanity_warn, warn_text = check_sanity(preds['make'], preds['model'], preds['year'])
                s_make = preds['make']
                s_model = preds['model']
                s_year = preds['year']
                s_conf = preds['confidence']
                y_conf = preds['year_confidence']
                s_mod_ver = 'jordo23-effnet-b4-mock'
            
            t.execute('''
                INSERT INTO SIGHTING (
                    id, ride_id, best_crop_id, timestamp, 
                    predicted_make, predicted_model, predicted_year, 
                    classification_confidence, year_confidence, classifier_model_ver,
                    needs_review, sanity_warning, sanity_warning_text, review_status,
                    lat, lng, attrs_json,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, 'pending', ?, ?, ?, ?, ?)
            ''', (
                sighting_id, det['ride_id'], det['frame_asset_id'], now_iso,
                s_make, s_model, s_year,
                s_conf, y_conf, s_mod_ver,
                sanity_warn, warn_text,
                mock_lat, mock_lng, attrs_json,
                now_iso, now_iso
            ))
            
            # Update detection
            t.execute('UPDATE DETECTION SET sighting_id = ? WHERE id = ?', (sighting_id, det['det_id']))
            
    logger.info("Classification batch completed.")

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    run_classification_batch()
