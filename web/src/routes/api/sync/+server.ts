import { json } from '@sveltejs/kit';
import { db } from '$lib/server/admin';
import type { Ride, Video, Sighting } from '$lib/types';

/**
 * POST /api/sync
 * Accepts bulk payloads from the M4 Mac mini sync daemon.
 * 
 * Payload structure:
 * {
 *   rides: Ride[],
 *   videos: Video[],
 *   sightings: Sighting[]
 * }
 */
export async function POST({ request }) {
    try {
        // Authenticate the worker (stub)
        const authHeader = request.headers.get('Authorization');
        if (authHeader !== `Bearer ${process.env.WORKER_API_KEY || 'dev-worker-key'}`) {
            return json({ error: 'Unauthorized' }, { status: 401 });
        }

        const data = await request.json();
        const { rides = [], videos = [], sightings = [] } = data;

        // Use a Firestore batched write
        const batch = db.batch();

        for (const ride of rides as Ride[]) {
            const ref = db.collection('rides').doc(ride.id);
            batch.set(ref, ride, { merge: true });
        }

        for (const video of videos as Video[]) {
            const ref = db.collection('videos').doc(video.id);
            batch.set(ref, video, { merge: true });
        }

        for (const sighting of sightings as Sighting[]) {
            const ref = db.collection('sightings').doc(sighting.id);
            batch.set(ref, sighting, { merge: true });
        }

        await batch.commit();

        return json({
            success: true,
            synced: {
                rides: rides.length,
                videos: videos.length,
                sightings: sightings.length
            }
        });
    } catch (err: any) {
        console.error('Failed to sync data from M4:', err);
        return json({ error: err.message }, { status: 500 });
    }
}
