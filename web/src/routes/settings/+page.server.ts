import { db } from '$lib/server/admin';
import type { Worker } from '$lib/types';

export async function load() {
    // Gather system configuration
    const workersSnap = await db.collection('workers').get();
    const workers: Worker[] = workersSnap.docs.map(d => ({ id: d.id, ...d.data() } as Worker));

    const modelsSnap = await db.collection('models')
        .where('status', '==', 'deployed')
        .orderBy('created_at', 'desc')
        .limit(1)
        .get();
    const activeModel = modelsSnap.docs[0]?.data() || null;

    return {
        config: {
            autoTrainThreshold: process.env.AUTO_TRAIN_THRESHOLD || '100',
            gcpBucket: process.env.GCS_BUCKET || process.env.GCP_BUCKET || 'curbscout-artifacts',
            hubUrl: process.env.GCP_HUB_URL || 'localhost:5173',
            mapboxConfigured: !!(process.env.VITE_MAPBOX_TOKEN || process.env.PUBLIC_MAPBOX_TOKEN),
        },
        workers,
        activeModel
    };
}
