import type { Handle } from '@sveltejs/kit';

export const handle: Handle = async ({ event, resolve }) => {
    // Simple HTTP Basic Auth check to protect the GCP Hub dashboard
    // You can bypass this by setting it to a Zero Trust proxy (like Cloudflare Access or GCP IAP)

    const authHeader = event.request.headers.get('Authorization');
    const adminUser = process.env.ADMIN_USER || 'admin';
    const adminPass = process.env.ADMIN_PASS || 'curbscout2026';

    const encodedCredentials = Buffer.from(`${adminUser}:${adminPass}`).toString('base64');
    const expectedHeader = `Basic ${encodedCredentials}`;

    // Skip authentication for API endpoints, they use a different Bearer Token strategy
    if (event.url.pathname.startsWith('/api/') || event.url.pathname === '/healthz') {
        return resolve(event);
    }

    if (!authHeader || authHeader !== expectedHeader) {
        return new Response('Unauthorized - CurbScout Hub', {
            status: 401,
            headers: {
                'WWW-Authenticate': 'Basic realm="CurbScout Orchestration Hub"'
            }
        });
    }

    return resolve(event);
};
