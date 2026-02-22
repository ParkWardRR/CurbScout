/**
 * Application types matching the Firestore schema models
 * for the GCP Orchestration Hub
 */

export interface Ride {
    id: string; // UUID v4 mapping to Firestore document id
    start_ts: string; // ISO 8601
    end_ts?: string | null; // ISO 8601
    notes?: string | null;
    video_count: number;
    sighting_count: number;
    reviewed: boolean; // default false
    created_at: string;
    updated_at: string;
}

export interface Video {
    id: string; // UUID mapping to Firestore document id
    ride_id: string;
    file_path: string; // local path on M4
    file_name: string;
    checksum_sha256: string;
    file_size_bytes: number;
    start_ts: string; // ISO 8601
    duration_sec: number;
    fps: number;
    resolution: string;
    codec: string;
    status: 'ok' | 'corrupted' | 'partial';
    created_at: string;
}

export interface Sighting {
    id: string; // UUID v4 mapping to Firestore document id
    ride_id: string;
    best_crop_id: string; // reference to a GCS crop
    timestamp: string; // ISO 8601
    predicted_make: string;
    predicted_model: string;
    predicted_year?: string | null;
    classification_confidence: number;
    year_confidence: 'high' | 'medium' | 'low' | 'none';
    classifier_model_ver: string;
    needs_review: boolean;
    sanity_warning: boolean;
    sanity_warning_text?: string | null;
    review_status: 'pending' | 'confirmed' | 'corrected' | 'deleted';
    lat?: number;
    lng?: number;
    attrs_json?: Record<string, any>;
    deleted: boolean;
    created_at: string;
    updated_at: string;
}

export interface Correction {
    id: string;
    sighting_id: string;
    corrected_fields: Record<string, any>;
    previous_values: Record<string, any>;
    new_values: Record<string, any>;
    note?: string | null;
    created_at: string;
}

export interface Job {
    id: string; // Job ID
    type: 'inference' | 'training' | 'reprocessing';
    status: 'queued' | 'running' | 'completed' | 'failed';
    target_worker: 'm4' | 'vast.ai';
    payload: Record<string, any>;
    result?: Record<string, any>;
    created_at: string;
    started_at?: string;
    completed_at?: string;
    error?: string;
}
