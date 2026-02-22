import { error } from '@sveltejs/kit';
import { Storage } from '@google-cloud/storage';

const GCS_BUCKET = process.env.GCS_BUCKET || 'curbscout-artifacts';

let storage: Storage;
try {
    storage = new Storage();
} catch {
    // Will fail gracefully in dev if no credentials
}

/**
 * GET /api/images/[...path]
 * Proxies GCS crop images so the dashboard can display thumbnails
 * without requiring public GCS access or signed URLs.
 * 
 * Usage: <img src="/api/images/crops/{crop_id}.jpg" />
 */
export async function GET({ params }) {
    const path = params.path;
    if (!path || path.includes('..')) {
        throw error(400, 'Invalid path');
    }

    try {
        const bucket = storage.bucket(GCS_BUCKET);
        const file = bucket.file(path);
        const [exists] = await file.exists();

        if (!exists) {
            throw error(404, 'Image not found');
        }

        const [metadata] = await file.getMetadata();
        const [buffer] = await file.download();

        const contentType = metadata.contentType || 'image/jpeg';

        return new Response(new Uint8Array(buffer), {
            headers: {
                'Content-Type': contentType,
                'Cache-Control': 'public, max-age=86400, immutable',
                'Content-Length': buffer.length.toString()
            }
        });
    } catch (err: any) {
        if (err.status) throw err;
        console.error('GCS image proxy error:', err.message);
        throw error(502, 'Failed to fetch image');
    }
}
