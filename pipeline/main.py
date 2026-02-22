import os
import argparse
import logging
import time

import json

from curbscout.db import init_db
from curbscout.accelerator import detect_best_backend
from curbscout.ingest import import_ride
from curbscout.sampler import process_unextracted_videos
from curbscout.detector import process_detections
from curbscout.classifier import run_classification_batch
from curbscout.dedup import deduplicate_sightings
from curbscout.sync import run_sync, register_worker, send_heartbeat
from curbscout.poll import poll_hub_jobs

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s - %(message)s'
)
logger = logging.getLogger("CurbScout.M4")

STATUS_FILE = os.path.expanduser("~/CurbScout/data/pipeline_status.json")

def write_status(state: str, sighting_count: int = 0):
    """Write pipeline status for the macOS MenuBarExtra to read."""
    os.makedirs(os.path.dirname(STATUS_FILE), exist_ok=True)
    status = {
        "state": state,
        "sighting_count": sighting_count,
        "last_sync": time.strftime("%Y-%m-%d %H:%M:%S")
    }
    with open(STATUS_FILE, 'w') as f:
        json.dump(status, f)

def run_pipeline(source_dir: str):
    logger.info("Starting M4 Local Pipeline Execution")
    write_status("Processing")
    
    # Check Hardware capability
    backend = detect_best_backend()
    logger.info(f"Targeting Hardware Accelerator Engine: {backend.name}")
    
    logger.info("Initializing Data Models...")
    init_db()
    
    logger.info("STAGE 1: USB Raw Video Ingest")
    import_ride(source_dir)
    
    logger.info("STAGE 2: Keyframe Sampling (VideoToolbox)")
    process_unextracted_videos()
    
    logger.info("STAGE 3: Vehicle Detection (YOLOv8)")
    process_detections()
    
    logger.info("STAGE 4: Make/Model Classification")
    run_classification_batch()
    
    logger.info("STAGE 5: Deduplication Consolidation")
    deduplicate_sightings()
    
    logger.info("STAGE 6: Synchronizing Results with GCP Hub")
    write_status("Syncing")
    run_sync()
    
    write_status("Idle")
    logger.info("Pipeline Execution Complete. Review UI accessible on Cloud Run.")

def start_daemon(source_dir: str):
    logger.info("Starting background M4 daemon process...")
    register_worker()
    try:
        while True:
            # Detect USB mount and auto-ingest changes
            run_pipeline(source_dir)
            
            # Check for explicitly dispatched jobs from the GCP Dashboard
            poll_hub_jobs()
            
            # Heartbeat to Hub
            send_heartbeat()
            
            write_status("Idle")
            logger.info("Sleeping for 60 seconds...")
            time.sleep(60)
    except KeyboardInterrupt:
        write_status("Idle")
        logger.info("Daemon gracefully shutting down.")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="CurbScout M4 Local Node Execution")
    parser.add_argument("--source", type=str, default=os.path.expanduser('~/.curbscout/test_data/'), help="Path to SD card / DCIM mount")
    parser.add_argument("--daemon", action="store_true", help="Run continuously in the background syncing data")
    
    args = parser.parse_args()
    
    if args.daemon:
        start_daemon(args.source)
    else:
        run_pipeline(args.source)
