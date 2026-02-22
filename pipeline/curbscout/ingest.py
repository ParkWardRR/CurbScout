import os
import glob
import hashlib
import shutil
import uuid
import datetime
import logging
from typing import List, Tuple
from tqdm import tqdm
from .db import get_connection, transaction

logger = logging.getLogger(__name__)

RAW_DIR = os.path.expanduser('~/CurbScout/raw')

def discover_videos(source_path: str) -> List[str]:
    """Finds all MP4 files from a camera SD card directory."""
    logger.info(f"Scanning for MP4 files in {source_path}")
    pattern = os.path.join(source_path, '**', '*.mp4')
    # Use recursive glob to dig into DCIM/Camera01
    return glob.glob(pattern, recursive=True)

def compute_checksum(filepath: str, chunk_size=65536) -> str:
    """Streaming SHA-256 for large video files."""
    hasher = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(chunk_size), b''):
            hasher.update(chunk)
    return hasher.hexdigest()

def is_duplicate(conn, checksum: str) -> bool:
    cur = conn.cursor()
    cur.execute('SELECT id FROM VIDEO WHERE checksum_sha256 = ?', (checksum,))
    return cur.fetchone() is not None

def get_video_metadata(filepath: str) -> dict:
    """Extract framerate, resolution and duration via ffprobe. Fallback if missing."""
    import ffmpeg
    try:
        probe = ffmpeg.probe(filepath)
        video_stream = next((stream for stream in probe['streams'] if stream['codec_type'] == 'video'), None)
        format_info = probe.get('format', {})
        
        duration = float(format_info.get('duration', 0))
        # Framerate is often returned as '30000/1001'
        r_frame_rate = video_stream.get('r_frame_rate', '30/1')
        num, den = map(int, r_frame_rate.split('/'))
        fps = num // den if den != 0 else 30
        
        return {
            'duration_sec': duration,
            'fps': fps,
            'resolution': f"{video_stream.get('width', 0)}x{video_stream.get('height', 0)}",
            'codec': video_stream.get('codec_name', 'unknown')
        }
    except Exception as e:
        logger.warning(f"Failed to probe {filepath}: {e}")
        return {'duration_sec': 0.0, 'fps': 30, 'resolution': 'unknown', 'codec': 'unknown'}

def import_ride(source_path: str):
    """
    Orchestrates the ingest pipeline: copy video, checksum, create Ride/Video DB rows.
    """
    os.makedirs(RAW_DIR, exist_ok=True)
    conn = get_connection()
    
    videos = discover_videos(source_path)
    if not videos:
        logger.info("No videos found to ingest.")
        return

    today_str = datetime.date.today().isoformat()
    dest_today_dir = os.path.join(RAW_DIR, today_str)
    os.makedirs(dest_today_dir, exist_ok=True)

    imported_count = 0
    ride_id = str(uuid.uuid4())
    now_iso = datetime.datetime.utcnow().isoformat() + 'Z'

    videos_to_insert = []

    for vid in tqdm(videos, desc="Ingesting camera files"):
        checksum = compute_checksum(vid)
        
        if is_duplicate(conn, checksum):
            logger.info(f"Skipping duplicate file (checksum match): {vid}")
            continue
            
        filename = os.path.basename(vid)
        dest_path = os.path.join(dest_today_dir, filename)
        
        # Copy file
        shutil.copy2(vid, dest_path)
        
        size_bytes = os.path.getsize(dest_path)
        meta = get_video_metadata(dest_path)
        
        video_id = str(uuid.uuid4())
        videos_to_insert.append((
            video_id, ride_id, dest_path, filename, checksum,
            size_bytes, now_iso, meta['duration_sec'], meta['fps'],
            meta['resolution'], meta['codec'], 'ok', now_iso
        ))
        imported_count += 1

    if imported_count > 0:
        # Create a single RIDE record for this batch
        with transaction(conn) as c:
            c.execute('''
                INSERT INTO RIDE (id, start_ts, video_count, sighting_count, created_at, updated_at)
                VALUES (?, ?, ?, 0, ?, ?)
            ''', (ride_id, now_iso, imported_count, now_iso, now_iso))
            
            c.executemany('''
                INSERT INTO VIDEO 
                (id, ride_id, file_path, file_name, checksum_sha256, file_size_bytes, start_ts, duration_sec, fps, resolution, codec, status, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', videos_to_insert)
            
        logger.info(f"Successfully imported {imported_count} videos into Ride {ride_id}.")
    else:
        logger.info("No new videos were imported (all duplicates).")
