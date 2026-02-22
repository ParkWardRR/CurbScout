import { json } from '@sveltejs/kit';
import { db } from '$lib/server/admin';
import type { Worker } from '$lib/types';

/**
 * POST /api/workers/register
 * Called by M4 workers on first boot to register themselves.
 */
export async function POST({ request }) {
    try {
        const payload = await request.json();
        const { id, hostname, hardware, os_version, capabilities } = payload;

        if (!id || !hostname) {
            return json({ error: 'Missing id or hostname' }, { status: 400 });
        }

        const now = new Date().toISOString();
        const workerRef = db.collection('workers').doc(id);
        const existing = await workerRef.get();

        if (existing.exists) {
            // Re-registration: update last_seen and hardware info
            await workerRef.update({
                hostname,
                hardware: hardware || 'unknown',
                os_version: os_version || '',
                capabilities: capabilities || ['inference'],
                status: 'online',
                last_seen: now
            });
        } else {
            const worker: Worker = {
                id,
                hostname,
                hardware: hardware || 'unknown',
                os_version: os_version || '',
                status: 'online',
                capabilities: capabilities || ['inference'],
                last_seen: now,
                ride_count: 0,
                sighting_count: 0,
                registered_at: now
            };
            await workerRef.set(worker);
        }

        return json({ success: true, worker_id: id });
    } catch (err: any) {
        console.error('Worker registration failed:', err);
        return json({ error: err.message }, { status: 500 });
    }
}
