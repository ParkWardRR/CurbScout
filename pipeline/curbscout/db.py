import sqlite3
import os
import contextlib
import logging

logger = logging.getLogger(__name__)

DB_PATH = os.path.expanduser('~/CurbScout/curbscout.db')

def get_connection(path: str = DB_PATH) -> sqlite3.Connection:
    """
    Returns a connection to the local SQLite database configured with WAL mode
    to allow concurrent writes from the M4 pipeline and reads from the Sync Daemon.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    conn = sqlite3.connect(path, timeout=5.0)
    conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA journal_mode=WAL;')
    conn.execute('PRAGMA synchronous=NORMAL;')
    conn.execute('PRAGMA busy_timeout=5000;')
    # Foreign keys can be enabled if rigorous, but frequently skipped in big data pipelines
    # We'll enable them for safety
    conn.execute('PRAGMA foreign_keys=ON;')
    return conn

@contextlib.contextmanager
def transaction(conn: sqlite3.Connection):
    """
    Context manager to easily batch inserts within a transaction.
    """
    try:
        conn.execute('BEGIN TRANSACTION;')
        yield conn
        conn.commit()
    except Exception as e:
        conn.rollback()
        logger.error(f"Transaction failed, rolling back: {e}")
        raise

def init_db(path: str = DB_PATH):
    """
    Initializes the SQLite schema locally on the M4.
    """
    conn = get_connection(path)
    schema = """
    CREATE TABLE IF NOT EXISTS RIDE (
        id TEXT PRIMARY KEY,
        start_ts TEXT,
        end_ts TEXT,
        notes TEXT,
        video_count INTEGER,
        sighting_count INTEGER,
        reviewed BOOLEAN DEFAULT 0,
        synced_to_gcp BOOLEAN DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
    );
    CREATE TABLE IF NOT EXISTS VIDEO (
        id TEXT PRIMARY KEY,
        ride_id TEXT REFERENCES RIDE(id),
        file_path TEXT,
        file_name TEXT,
        checksum_sha256 TEXT UNIQUE,
        file_size_bytes INTEGER,
        start_ts TEXT,
        duration_sec REAL,
        fps INTEGER,
        resolution TEXT,
        codec TEXT,
        status TEXT,
        created_at TEXT
    );
    CREATE TABLE IF NOT EXISTS FRAME_ASSET (
        id TEXT PRIMARY KEY,
        video_id TEXT REFERENCES VIDEO(id),
        video_timestamp_sec REAL,
        kind TEXT,
        file_path TEXT,
        phash TEXT,
        width INTEGER,
        height INTEGER,
        synced_to_gcp BOOLEAN DEFAULT 0,
        created_at TEXT
    );
    CREATE TABLE IF NOT EXISTS DETECTION (
        id TEXT PRIMARY KEY,
        frame_asset_id TEXT REFERENCES FRAME_ASSET(id),
        sighting_id TEXT, -- References SIGHTING(id) after dedup
        class TEXT,
        confidence REAL,
        bbox_json TEXT,
        crop_path TEXT,
        model_ver TEXT,
        created_at TEXT
    );
    CREATE TABLE IF NOT EXISTS SIGHTING (
        id TEXT PRIMARY KEY,
        ride_id TEXT REFERENCES RIDE(id),
        best_crop_id TEXT REFERENCES FRAME_ASSET(id),
        timestamp TEXT,
        predicted_make TEXT,
        predicted_model TEXT,
        predicted_year TEXT,
        classification_confidence REAL,
        year_confidence TEXT,
        classifier_model_ver TEXT,
        needs_review BOOLEAN DEFAULT 1,
        sanity_warning BOOLEAN DEFAULT 0,
        sanity_warning_text TEXT,
        review_status TEXT,
        lat REAL,
        lng REAL,
        attrs_json TEXT,
        deleted BOOLEAN DEFAULT 0,
        synced_to_gcp BOOLEAN DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
    );
    CREATE TABLE IF NOT EXISTS CORRECTION (
        id TEXT PRIMARY KEY,
        sighting_id TEXT REFERENCES SIGHTING(id),
        corrected_fields TEXT,
        previous_values TEXT,
        new_values TEXT,
        note TEXT,
        created_at TEXT
    );
    """
    try:
        conn.executescript(schema)
        # Ensure fast lookup of checksums
        conn.execute('CREATE INDEX IF NOT EXISTS idx_video_checksum ON VIDEO(checksum_sha256);')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_sighting_synced ON SIGHTING(synced_to_gcp);')
        conn.commit()
    except Exception as e:
        logger.error(f"Failed to initialize database: {e}")
        conn.rollback()
    finally:
        conn.close()

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    logger.info("Initializing M4 local database schema...")
    init_db()
    logger.info("Done.")
