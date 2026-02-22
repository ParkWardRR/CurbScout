import { CloudTasksClient } from '@google-cloud/tasks';

// Use Application Default Credentials when deployed to GCP
const client = new CloudTasksClient();
const projectId = process.env.GOOGLE_CLOUD_PROJECT || 'curbscout-project';
const location = process.env.GCP_LOCATION || 'us-central1';

// M4 Mac mini processes inference. They poll the queue or get pushed through HTTP proxy / Ngrok.
export const m4QueueName = process.env.M4_QUEUE_NAME || 'm4-inference-queue';
export const m4QueuePath = client.queuePath(projectId, location, m4QueueName);

// Vast.ai training queue.
export const vastQueueName = process.env.VAST_QUEUE_NAME || 'vast-training-queue';
export const vastQueuePath = client.queuePath(projectId, location, vastQueueName);

export async function dispatchInferenceJob(payload: any, url: string) {
    const request = {
        parent: m4QueuePath,
        task: {
            httpRequest: {
                httpMethod: 'POST' as const,
                url,
                body: Buffer.from(JSON.stringify(payload)).toString('base64'),
                headers: {
                    'Content-Type': 'application/json'
                }
            }
        }
    };
    const [response] = await client.createTask(request);
    return response;
}

export async function dispatchTrainingJob(payload: any, url: string) {
    const request = {
        parent: vastQueuePath,
        task: {
            httpRequest: {
                httpMethod: 'POST' as const,
                url, // The endpoint that actually spawns the Vast instance or handles training
                body: Buffer.from(JSON.stringify(payload)).toString('base64'),
                headers: {
                    'Content-Type': 'application/json'
                }
            }
        }
    };
    const [response] = await client.createTask(request);
    return response;
}
