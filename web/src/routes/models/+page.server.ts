import { db } from '$lib/server/admin';
import type { ModelVersion } from '$lib/types';

export async function load() {
    const modelsSnapshot = await db.collection('models')
        .orderBy('created_at', 'desc')
        .get();

    const models: ModelVersion[] = modelsSnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
    })) as ModelVersion[];

    return {
        models
    };
}
