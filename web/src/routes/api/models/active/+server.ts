import { json } from '@sveltejs/kit';
import { db } from '$lib/server/admin';

/**
 * GET /api/models/active
 * Used by M4 pipeline sync script to know EXACTLY which
 * version it should run, instead of guessing via GCS timestamps.
 */
export async function GET({ request }) {
    try {
        const snapshot = await db.collection('models')
            .where('status', '==', 'deployed')
            .orderBy('deployed_at', 'desc')
            .limit(1)
            .get();

        if (snapshot.empty) {
            return json({
                success: true,
                has_active: false,
                message: "No deployed models found."
            });
        }

        const activeModel = snapshot.docs[0].data();

        return json({
            success: true,
            has_active: true,
            model: activeModel
        });
    } catch (err: any) {
        console.error('Failed to fetch active model:', err);
        return json({ error: err.message }, { status: 500 });
    }
}
