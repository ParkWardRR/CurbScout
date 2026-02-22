import os
import uuid
import datetime
import logging
import json
from PIL import Image
from typing import List
import imagehash
from ultralytics import YOLO

from .db import get_connection, transaction
from .accelerator import detect_best_backend, Backend

logger = logging.getLogger(__name__)

CROPS_DIR = os.path.expanduser('~/CurbScout/derived/crops')

# COCO vehicle classes: 2=car, 3=motorcycle, 5=bus, 7=truck
VEHICLE_CLASSES = {2, 3, 5, 7}

# A global reference for the model
_models = {}

def get_models():
    global _models
    if not _models:
        logger.info("Loading YOLO models (Vehicles, Signs, Hazards)...")
        # In scaffolding, we default all to yolov8n but map them logically
        _models = {
            'vehicles': YOLO("yolov8n.pt"),
            'signs': YOLO("yolov8n.pt"), # Mock fallback
            'hazards': YOLO("yolov8n.pt") # Mock fallback
        }
    return _models

def get_unprocessed_frames() -> List[dict]:
    """Fetch keyframes that don't have detections yet."""
    conn = get_connection()
    c = conn.cursor()
    try:
        c.execute('ALTER TABLE FRAME_ASSET ADD COLUMN processed_for_detections BOOLEAN DEFAULT 0')
        conn.commit()
    except Exception:
        pass # Column might already exist
        
    c.execute('''
        SELECT id, file_path, video_id, video_timestamp_sec 
        FROM FRAME_ASSET 
        WHERE kind = 'keyframe' AND processed_for_detections = 0
        LIMIT 500
    ''')
    rows = c.fetchall()
    conn.close()
    return [dict(r) for r in rows]

def detect_all(frame_info: dict, models: dict, output_dir: str):
    """Run YOLO multiple times, yield detections and crop info."""
    frame_path = frame_info['file_path']
    if not os.path.exists(frame_path):
        return []
        
    detections = []
    
    # Load original image for cropping
    img = Image.open(frame_path)
    img_width, img_height = img.size
    
    for category, model in models.items():
        # Hack for scaffolding: standard yolov8n only tracks vehicles natively
        classes = list(VEHICLE_CLASSES) if category == 'vehicles' else None
        
        results = model.predict(source=frame_path, verbose=False, classes=classes)
        result = results[0] # single image
        boxes = result.boxes
        
        for box in boxes:
            conf = float(box.conf[0])
            cls_id = int(box.cls[0])
            
            # Sub real class names in scaffolding
            if category == 'signs':
                class_name = 'parking_sign'
            elif category == 'hazards':
                class_name = 'bike_lane_obstruction' if cls_id % 2 == 0 else 'pothole'
            else:
                class_name = result.names[cls_id]
                
            # Filter logic: if it's the mock model for signs/hazards running yolov8n, just grab the first bbox to simulate that model found something, otherwise it spawns 40 signs.
            # Real models will only output real signs and hazards.
            
            # [x1, y1, x2, y2]
            xyxy = box.xyxy[0].tolist()
            
            # Crop the image
            crop_img = img.crop(xyxy)
            
            # Calculate perceptual hash
            p_hash = str(imagehash.phash(crop_img))
            
            det_id = str(uuid.uuid4())
            crop_filename = f"{det_id}_crop.jpg"
            crop_filepath = os.path.join(output_dir, crop_filename)
            
            crop_img.save(crop_filepath, quality=85)
            
            # Normalize relative coordinates [x1, y1, x2, y2]
            nx1 = xyxy[0] / img_width
            ny1 = xyxy[1] / img_height
            nx2 = xyxy[2] / img_width
            ny2 = xyxy[3] / img_height
            
            detections.append({
                'det_id': det_id,
                'class_name': class_name,
                'confidence': conf,
                'bbox_json': json.dumps([nx1, ny1, nx2, ny2]),
                'crop_path': crop_filepath,
                'phash': p_hash,
                'width': crop_img.width,
                'height': crop_img.height,
            })
            
            if category in ['signs', 'hazards']:
                break # Just mock 1 sign/hazard max per frame if it hallucinated one from the car model
            
    return detections

def process_detections():
    """Main loop for running the detector."""
    frames = get_unprocessed_frames()
    if not frames:
        logger.info("No new keyframes to process for detection.")
        return
        
    logger.info(f"Running detection on {len(frames)} frames...")
    
    models = get_models()
    
    conn = get_connection()
    
    # Determine date dir
    date_str = datetime.date.today().isoformat()
    out_dir = os.path.join(CROPS_DIR, date_str)
    os.makedirs(out_dir, exist_ok=True)
    
    now_iso = datetime.datetime.utcnow().isoformat() + 'Z'
    
    with transaction(conn) as t:
        for f in frames:
            dets = detect_all(f, models, out_dir)
            
            for d in dets:
                crop_asset_id = str(uuid.uuid4())
                
                # Insert the crop as a new FRAME_ASSET
                t.execute('''
                    INSERT INTO FRAME_ASSET 
                    (id, video_id, video_timestamp_sec, kind, file_path, phash, width, height, created_at)
                    VALUES (?, ?, ?, 'crop', ?, ?, ?, ?, ?)
                ''', (
                    crop_asset_id, f['video_id'], f['video_timestamp_sec'], 
                    d['crop_path'], d['phash'], d['width'], d['height'], now_iso
                ))
                
                # Insert the DETECTION
                t.execute('''
                    INSERT INTO DETECTION 
                    (id, frame_asset_id, class, confidence, bbox_json, crop_path, model_ver, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, 'yolov8n-coco', ?)
                ''', (
                    d['det_id'], crop_asset_id, d['class_name'], d['confidence'], 
                    d['bbox_json'], d['crop_path'], now_iso
                ))
                
            # Mark frame as processed
            t.execute('UPDATE FRAME_ASSET SET processed_for_detections = 1 WHERE id = ?', (f['id'],))
            
    logger.info("Detection batch completed.")

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    process_detections()
