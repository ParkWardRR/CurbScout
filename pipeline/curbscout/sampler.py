import os
import uuid
import datetime
import logging
import ffmpeg
from typing import List
from .db import get_connection, transaction

logger = logging.getLogger(__name__)

FRAMES_DIR = os.path.expanduser('~/CurbScout/derived/frames')

def extract_frames(video_id: str, video_path: str, fps: int = 2) -> List[dict]:
    """
    Extracts static keyframes at a specified sample rate (default 2fps)
    using ffmpeg and macOS VideoToolbox hardware acceleration.
    Returns metadata list for database insertion.
    """
    date_str = datetime.date.today().isoformat()
    out_dir = os.path.join(FRAMES_DIR, date_str, video_id)
    os.makedirs(out_dir, exist_ok=True)
    
    out_pattern = os.path.join(out_dir, "frame_%05d.jpg")
    
    logger.info(f"Extracting {fps} FPS frames from {video_path} using VideoToolbox...")
    try:
        (
            ffmpeg
            .input(video_path, hwaccel='videotoolbox')
            .filter('fps', fps=fps)
            .output(out_pattern, vcodec='mjpeg', qscale=2)
            .overwrite_output()
            .run(capture_stdout=True, capture_stderr=True)
        )
    except ffmpeg.Error as e:
        logger.error(f"ffmpeg extraction failed:\n{e.stderr.decode('utf-8')}")
        raise
        
    frames_found = sorted(os.listdir(out_dir))
    assets = []
    
    # Each extracted frame corresponds to 1/fps elapsed time.
    # frame_00001 = 0 sec
    # frame_00002 = 0.5 sec...
    for i, fname in enumerate(frames_found):
        fpath = os.path.join(out_dir, fname)
        # simplistic timestamp assumption based on strict fps extraction
        timestamp_sec = i / fps 
        
        assets.append({
            'file_path': fpath,
            'timestamp': timestamp_sec,
            'kind': 'keyframe'
        })
        
    logger.info(f"Extracted {len(assets)} frames for video {video_id}.")
    return assets

def process_unextracted_videos():
    """Finds imported videos without frames and extracts them."""
    conn = get_connection()
    c = conn.cursor()
    # Find videos that have NO associated FRAME_ASSETs of kind='keyframe'
    c.execute('''
        SELECT id, file_path 
        FROM VIDEO 
        WHERE id NOT IN (
            SELECT video_id FROM FRAME_ASSET WHERE kind = 'keyframe'
        )
    ''')
    pending_videos = c.fetchall()
    
    now_iso = datetime.datetime.utcnow().isoformat() + 'Z'
    
    for row in pending_videos:
        vid_id = row['id']
        vpath = row['file_path']
        
        try:
            extracted_assets = extract_frames(vid_id, vpath, fps=2)
            
            insert_batch = []
            for asset in extracted_assets:
                insert_batch.append((
                    str(uuid.uuid4()), vid_id, asset['timestamp'], 
                    asset['kind'], asset['file_path'], None, 0, 0, 0, now_iso
                ))
            
            with transaction(conn) as t:
                t.executemany('''
                    INSERT INTO FRAME_ASSET 
                    (id, video_id, video_timestamp_sec, kind, file_path, phash, width, height, synced_to_gcp, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', insert_batch)
                
        except Exception as e:
            logger.error(f"Failed to process video {vid_id}: {e}")
            continue
            
    conn.close()
    
if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    process_unextracted_videos()
