import { ridesRef } from '$lib/server/admin';
import type { Ride } from '$lib/types';

export async function load() {
    let rides: Ride[] = [];
    try {
        const snapshot = await ridesRef.orderBy('start_ts', 'desc').limit(50).get();
        rides = snapshot.docs.map(doc => {
            const data = doc.data() as Ride;
            // Ensure ID is passed through
            return {
                ...data,
                id: doc.id
            };
        });
    } catch (e) {
        console.error("Failed to load rides", e);
    }

    return { rides };
}
