import { db } from '$lib/server/admin';

const OFFLINE_THRESHOLD_MS = 5 * 60 * 1000;

export async function load() {
    const now = Date.now();

    // Aggregate counts
    const [ridesSnap, sightingsSnap, jobsSnap, workersSnap, modelsSnap] = await Promise.all([
        db.collection('rides').count().get(),
        db.collection('sightings').count().get(),
        db.collection('jobs').where('status', '==', 'running').count().get(),
        db.collection('workers').get(),
        db.collection('models').where('status', '==', 'deployed').count().get()
    ]);

    const rideCount = ridesSnap.data().count;
    const sightingCount = sightingsSnap.data().count;
    const activeJobCount = jobsSnap.data().count;
    const deployedModelCount = modelsSnap.data().count;

    // Compute online workers
    const workers = workersSnap.docs.map(d => d.data());
    const onlineWorkers = workers.filter(w => {
        const lastSeen = new Date(w.last_seen as string).getTime();
        return (now - lastSeen) < OFFLINE_THRESHOLD_MS;
    });

    // Pending review count
    const pendingSnap = await db.collection('sightings')
        .where('review_status', '==', 'pending')
        .where('deleted', '==', false)
        .count().get();
    const pendingReviewCount = pendingSnap.data().count;

    // Recent sightings for activity feed
    const recentSnap = await db.collection('sightings')
        .orderBy('created_at', 'desc')
        .limit(8)
        .get();
    const recentSightings = recentSnap.docs.map(d => ({ id: d.id, ...d.data() }));

    return {
        stats: {
            rides: rideCount,
            sightings: sightingCount,
            pendingReview: pendingReviewCount,
            onlineWorkers: onlineWorkers.length,
            totalWorkers: workers.length,
            activeJobs: activeJobCount,
            deployedModels: deployedModelCount
        },
        recentSightings
    };
}
