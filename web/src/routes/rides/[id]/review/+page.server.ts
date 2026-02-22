import { sightingsRef, ridesRef } from '$lib/server/admin';
import type { Ride, Sighting } from '$lib/types';
import { error } from '@sveltejs/kit';

export async function load({ params }) {
    const rideId = params.id;

    try {
        const rideDoc = await ridesRef.doc(rideId).get();
        if (!rideDoc.exists) {
            error(404, 'Ride not found in GCP Firestore');
        }

        const ride = { ...rideDoc.data(), id: rideDoc.id } as Ride;

        const snapshot = await sightingsRef.where('ride_id', '==', rideId).get();
        const sightings = snapshot.docs.map(doc => ({ ...doc.data(), id: doc.id } as Sighting));

        // Ensure chronological order
        sightings.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());

        return { ride, sightings };
    } catch (e: any) {
        if (e.status === 404) throw e;
        console.error("Failed to load review data", e);
        error(500, 'Database error');
    }
}
