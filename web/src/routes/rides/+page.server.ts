import { db } from '$lib/server/admin';
import type { Ride } from '$lib/types';

export async function load() {
    let rides: (Ride & { review_progress?: { pending: number; confirmed: number; corrected: number } })[] = [];
    try {
        const snapshot = await db.collection('rides').orderBy('start_ts', 'desc').limit(50).get();
        rides = snapshot.docs.map(doc => {
            const data = doc.data() as Ride;
            return { ...data, id: doc.id };
        });

        // Enrich with per-ride review progress
        for (const ride of rides) {
            if (ride.sighting_count > 0) {
                const sightingsSnap = await db.collection('sightings')
                    .where('ride_id', '==', ride.id)
                    .get();

                let pending = 0, confirmed = 0, corrected = 0;
                sightingsSnap.docs.forEach(s => {
                    const status = s.data().review_status;
                    if (status === 'confirmed') confirmed++;
                    else if (status === 'corrected') corrected++;
                    else pending++;
                });
                ride.review_progress = { pending, confirmed, corrected };
            }
        }
    } catch (e) {
        console.error("Failed to load rides", e);
    }

    return { rides };
}
