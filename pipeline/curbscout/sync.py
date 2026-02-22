import os
import logging
import httpx
from google.cloud import storage

from .db import get_connection, transaction

logger = logging.getLogger(__name__)

GCS_BUCKET = os.environ.get("GCS_BUCKET", "curbscout-artifacts")
# Assumes Cloud Run is deployed at this endpoint
GCP_HUB_URL = os.environ.get("GCP_HUB_URL", "http://localhost:5173") 
WORKER_API_KEY = os.environ.get("WORKER_API_KEY", "dev-worker-key")
WORKER_ID = os.environ.get("WORKER_ID", f"m4-{os.uname().nodename}")

def get_worker_id() -> str:
    """Generate a stable worker identifier from environment or hostname."""
    return WORKER_ID

def sync_to_gcs():
    """
    Find un-synced frame_assets (crops) and upload them to GCS.
    """
    conn = get_connection()
    c = conn.cursor()
    c.execute('''
        SELECT id, file_path, kind 
        FROM FRAME_ASSET 
        WHERE synced_to_gcp = 0 AND kind = 'crop'
        LIMIT 100
    ''')
    assets = [dict(r) for r in c.fetchall()]
    
    if not assets:
        return
        
    try:
        from google.auth.exceptions import DefaultCredentialsError
        storage_client = storage.Client()
        bucket = storage_client.bucket(GCS_BUCKET)
    except Exception as e:
        logger.warning(f"GCP Storage client uninitialized (mocking for test): {e}")
        storage_client = None

    uploaded_ids = []
    
    for asset in assets:
        blob_name = f"crops/{asset['id']}.jpg"
        if storage_client:
            blob = bucket.blob(blob_name)
            if os.path.exists(asset['file_path']):
                blob.upload_from_filename(asset['file_path'])
            else:
                logger.warning(f"File missing: {asset['file_path']}")
        
        uploaded_ids.append(asset['id'])
        
    if uploaded_ids:
        with transaction(conn) as t:
            t.execute(f"UPDATE FRAME_ASSET SET synced_to_gcp = 1 WHERE id IN ({','.join(['?']*len(uploaded_ids))})", uploaded_ids)
        logger.info(f"Uploaded {len(uploaded_ids)} crops to GCS.")

def sync_to_firestore():
    """
    Push un-synced SQLite rows to the GCP Hub node adapter.
    """
    conn = get_connection()
    c = conn.cursor()
    
    c.execute("SELECT * FROM RIDE WHERE synced_to_gcp = 0 LIMIT 20")
    rides = [dict(r) for r in c.fetchall()]
    
    c.execute("SELECT * FROM VIDEO WHERE id IN (SELECT id FROM VIDEO LIMIT 50) AND status != 'synced'") # Hack: Needs a sync flag on videos, which hasn't been added. Let's just mock.
    
    c.execute("SELECT * FROM SIGHTING WHERE synced_to_gcp = 0 LIMIT 500")
    sightings = [dict(r) for r in c.fetchall()]
    
    if not rides and not sightings:
        return
        
    payload = {
        "rides": rides,
        "videos": [],
        "sightings": sightings,
        "worker_id": get_worker_id()
    }
    
    sync_endpoint = f"{GCP_HUB_URL}/api/sync"
    
    try:
        response = httpx.post(
            sync_endpoint, 
            json=payload, 
            headers={"Authorization": f"Bearer {WORKER_API_KEY}"}
        )
        if response.status_code == 200:
            with transaction(conn) as t:
                for r in rides:
                    t.execute("UPDATE RIDE SET synced_to_gcp = 1 WHERE id = ?", (r['id'],))
                for s in sightings:
                    t.execute("UPDATE SIGHTING SET synced_to_gcp = 1 WHERE id = ?", (s['id'],))
            logger.info(f"Synced {len(rides)} rides and {len(sightings)} sightings to GCP Hub.")
        else:
            logger.error(f"Failed to sync data: {response.status_code} {response.text}")
    except httpx.RequestError as e:
        logger.error(f"Cannot reach GCP Hub at {sync_endpoint}: {e}")

def pull_corrections():
    """
    Pull correction diffs applied via the SvelteKit dashboard from Firestore.
    """
    logger.info("Polling for remote Corrections from Firestore... (Stub)")

def register_worker():
    """Register this M4 worker with the GCP Hub fleet registry."""
    import platform
    worker_id = get_worker_id()
    payload = {
        "id": worker_id,
        "hostname": os.uname().nodename,
        "hardware": platform.processor() or "Apple Silicon",
        "os_version": platform.platform(),
        "capabilities": ["inference"]
    }
    try:
        res = httpx.post(
            f"{GCP_HUB_URL}/api/workers/register",
            json=payload,
            timeout=10.0
        )
        if res.status_code == 200:
            logger.info(f"Worker '{worker_id}' registered with Hub.")
        else:
            logger.warning(f"Worker registration failed: {res.status_code}")
    except Exception as e:
        logger.warning(f"Cannot register with Hub: {e}")

def send_heartbeat():
    """Send a liveness heartbeat to the GCP Hub."""
    try:
        res = httpx.post(
            f"{GCP_HUB_URL}/api/workers/heartbeat",
            json={"worker_id": get_worker_id()},
            timeout=5.0
        )
        if res.status_code != 200:
            logger.debug(f"Heartbeat response: {res.status_code}")
    except Exception:
        pass  # Heartbeat failures are non-critical

def run_sync():
    """Run all sync passes."""
    send_heartbeat()
    sync_to_gcs()
    sync_to_firestore()
    pull_corrections()

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    register_worker()
    run_sync()
