import { json } from '@sveltejs/kit';
import { db } from '$lib/server/admin';
import type { Worker } from '$lib/types';

const OFFLINE_THRESHOLD_MS = 5 * 60 * 1000; // 5 minutes

/**
 * GET /api/workers
 * Returns all registered workers with computed online/offline status.
 */
export async function GET() {
    try {
        const snapshot = await db.collection('workers').get();
        const now = Date.now();

        const workers: Worker[] = snapshot.docs.map(doc => {
            const data = doc.data() as Worker;
            const lastSeen = new Date(data.last_seen).getTime();
            const isStale = (now - lastSeen) > OFFLINE_THRESHOLD_MS;

            return {
                ...data,
                id: doc.id,
                status: isStale ? 'offline' : 'online'
            };
        });

        // Sort: online first, then by last_seen desc
        workers.sort((a, b) => {
            if (a.status !== b.status) return a.status === 'online' ? -1 : 1;
            return new Date(b.last_seen).getTime() - new Date(a.last_seen).getTime();
        });

        return json({ success: true, workers });
    } catch (err: any) {
        console.error('Failed to list workers:', err);
        return json({ error: err.message }, { status: 500 });
    }
}
