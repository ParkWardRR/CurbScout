import { json } from '@sveltejs/kit';
import { db } from '$lib/server/admin';
import { dispatchTrainingJob } from '$lib/server/tasks';
import { v4 as uuidv4 } from 'uuid';
import type { Job, ModelVersion } from '$lib/types';

/**
 * GET /api/jobs/trigger-auto-train
 * Can be triggered by Cloud Scheduler (e.g., daily at 2AM).
 * Sweeps un-trained corrections and triggers a Vast.ai job if threshold is met.
 */
export async function GET({ url }) {
    try {
        const threshold = parseInt(process.env.AUTO_TRAIN_THRESHOLD || '100', 10);

        // Fetch eligible sightings for training
        const snapshot = await db.collection('sightings')
            .where('review_status', 'in', ['corrected', 'confirmed'])
            .get();

        const eligibleSightings = snapshot.docs
            .map(d => ({ docId: d.id, ...d.data() }))
            .filter((s: any) => !s.trained);

        if (eligibleSightings.length < threshold) {
            return json({
                success: true,
                message: `Threshold not met. Found ${eligibleSightings.length}/${threshold} pending corrections.`,
                threshold_met: false
            });
        }

        // We have enough to train. 
        // 1. Mark them as trained (in batches of 500 max per firestore limits)
        const batch = db.batch();
        const lineageIds: string[] = [];

        // For safety, let's take exactly the threshold or max 500 per epoch
        const trainingSet = eligibleSightings.slice(0, 500);

        for (const s of trainingSet) {
            lineageIds.push(s.docId);
            batch.update(db.collection('sightings').doc(s.docId), { trained: true });
        }
        await batch.commit();

        // 2. Create the ModelVersion tracking document
        const modelId = uuidv4();
        const modelVersion: ModelVersion = {
            id: modelId,
            version: `finetune-v${Date.now()}`,
            status: 'training',
            job_id: uuidv4(), // The ID of the orchestration Job we'll create next
            lineage_ids: lineageIds,
            created_at: new Date().toISOString()
        };
        await db.collection('models').doc(modelId).set(modelVersion);

        // 3. Create Job and Dispatch to Vast.ai
        const job: Job = {
            id: modelVersion.job_id,
            type: 'training',
            status: 'queued',
            target_worker: 'vast.ai',
            payload: {
                model_id: modelId,
                lineage_count: lineageIds.length
            },
            created_at: new Date().toISOString()
        };
        await db.collection('jobs').doc(job.id).set(job);
        await dispatchTrainingJob(job, `${url.origin}/api/worker/vast`);

        return json({
            success: true,
            threshold_met: true,
            message: `Dispatched training job for model ${modelVersion.version} across ${lineageIds.length} corrections.`,
            job_id: job.id,
            model_id: modelVersion.id
        });

    } catch (err: any) {
        console.error('Failed to auto-trigger training:', err);
        return json({ error: err.message }, { status: 500 });
    }
}
