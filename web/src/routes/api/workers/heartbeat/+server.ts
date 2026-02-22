import { json } from '@sveltejs/kit';
import { db } from '$lib/server/admin';

/**
 * POST /api/workers/heartbeat
 * Called periodically by M4 workers to signal they're alive.
 */
export async function POST({ request }) {
    try {
        const { worker_id } = await request.json();
        if (!worker_id) {
            return json({ error: 'Missing worker_id' }, { status: 400 });
        }

        const ref = db.collection('workers').doc(worker_id);
        const doc = await ref.get();

        if (!doc.exists) {
            return json({ error: 'Worker not registered' }, { status: 404 });
        }

        await ref.update({
            status: 'online',
            last_seen: new Date().toISOString()
        });

        return json({ success: true });
    } catch (err: any) {
        console.error('Heartbeat failed:', err);
        return json({ error: err.message }, { status: 500 });
    }
}
