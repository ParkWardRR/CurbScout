import { json } from '@sveltejs/kit';
import { db } from '$lib/server/admin';
import { dispatchInferenceJob, dispatchTrainingJob } from '$lib/server/tasks';
import { v4 as uuidv4 } from 'uuid';
import type { Job } from '$lib/types';

/**
 * POST /api/jobs
 * Creates a new orchestration job and dispatches it.
 */
export async function POST({ request, url }) {
    try {
        const payload = await request.json();
        const { type, payload: jobPayload } = payload;

        if (!type) {
            return json({ error: 'Job type required' }, { status: 400 });
        }

        const jobId = uuidv4();

        const job: Job = {
            id: jobId,
            type,
            status: 'queued',
            target_worker: type === 'training' ? 'vast.ai' : 'm4',
            payload: jobPayload || {},
            created_at: new Date().toISOString()
        };

        // Persist job metadata in Firestore
        await db.collection('jobs').doc(jobId).set(job);

        // Use Cloud Tasks to route execution
        if (job.target_worker === 'vast.ai') {
            await dispatchTrainingJob(job, `${url.origin}/api/worker/vast`);
        } else {
            await dispatchInferenceJob(job, `${url.origin}/api/worker/m4`);
        }

        return json({
            success: true,
            job_id: jobId,
            status: 'queued'
        });
    } catch (err: any) {
        console.error('Failed to create job:', err);
        return json({ error: err.message }, { status: 500 });
    }
}
