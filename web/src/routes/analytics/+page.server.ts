import { sightingsRef } from '$lib/server/admin';
import type { Sighting } from '$lib/types';

export async function load() {
    let sightings: Sighting[] = [];
    try {
        // Load up to 5000 recent sightings for analytics
        const snapshot = await sightingsRef.orderBy('timestamp', 'desc').limit(5000).get();
        sightings = snapshot.docs.map(doc => {
            const data = doc.data() as Sighting;
            return {
                ...data,
                id: doc.id
            };
        });
    } catch (e) {
        console.error("Failed to load analytics data", e);
    }

    return { sightings };
}
