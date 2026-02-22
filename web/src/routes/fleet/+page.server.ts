import { db } from '$lib/server/admin';
import type { Worker, Sighting } from '$lib/types';

const OFFLINE_THRESHOLD_MS = 5 * 60 * 1000;

export async function load() {
    const now = Date.now();

    // Fetch workers
    const workersSnapshot = await db.collection('workers').get();
    const workers: Worker[] = workersSnapshot.docs.map(doc => {
        const data = doc.data() as Worker;
        const lastSeen = new Date(data.last_seen).getTime();
        const isStale = (now - lastSeen) > OFFLINE_THRESHOLD_MS;
        return { ...data, id: doc.id, status: isStale ? 'offline' as const : 'online' as const };
    });

    // Fetch reviewer leaderboard from sightings
    const reviewedSnapshot = await db.collection('sightings')
        .where('review_status', 'in', ['confirmed', 'corrected'])
        .get();

    const reviewerCounts: Record<string, { confirmed: number; corrected: number }> = {};
    reviewedSnapshot.docs.forEach(doc => {
        const s = doc.data() as Sighting;
        const reviewer = s.reviewed_by || 'anonymous';
        if (!reviewerCounts[reviewer]) {
            reviewerCounts[reviewer] = { confirmed: 0, corrected: 0 };
        }
        if (s.review_status === 'confirmed') {
            reviewerCounts[reviewer].confirmed++;
        } else if (s.review_status === 'corrected') {
            reviewerCounts[reviewer].corrected++;
        }
    });

    const leaderboard = Object.entries(reviewerCounts)
        .map(([name, counts]) => ({ name, ...counts, total: counts.confirmed + counts.corrected }))
        .sort((a, b) => b.total - a.total);

    return { workers, leaderboard };
}
