import { json } from '@sveltejs/kit';
import { db } from '$lib/server/admin';

/**
 * POST /api/webhooks/vast-export
 * Called by Vast.ai upload_teardown.py script when model binaries 
 * securely arrive in GCS. Signals the hub to flip the status so 
 * M4 instances pull it natively.
 */
export async function POST({ request }) {
    try {
        // Authenticate the webhook (simple shared key)
        const authHeader = request.headers.get('Authorization');
        if (authHeader !== `Bearer ${process.env.VAST_API_KEY || 'vast-dev-key'}`) {
            return json({ error: 'Unauthorized' }, { status: 401 });
        }

        const { model_id, gcs_uri } = await request.json();

        if (!model_id || !gcs_uri) {
            return json({ error: 'Missing model_id or gcs_uri' }, { status: 400 });
        }

        const modelRef = db.collection('models').doc(model_id);
        const doc = await modelRef.get();

        if (!doc.exists) {
            return json({ error: `Model ${model_id} not found` }, { status: 404 });
        }

        // Fast update: set deployed enabling M4 pipeline to discover it automatically
        await modelRef.update({
            status: 'deployed',
            gcs_uri,
            deployed_at: new Date().toISOString()
        });

        // Also resolve the downstream job as completed if tied directly
        const modelData = doc.data();
        if (modelData?.job_id) {
            await db.collection('jobs').doc(modelData.job_id).update({
                status: 'completed',
                completed_at: new Date().toISOString(),
                result: { gcs_uri }
            });
        }

        return json({
            success: true,
            message: `Model ${model_id} successfully deployed mapped to ${gcs_uri}`
        });

    } catch (err: any) {
        console.error('Failed to process vast.ai deployment hook:', err);
        return json({ error: err.message }, { status: 500 });
    }
}
