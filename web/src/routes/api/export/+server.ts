import { json } from '@sveltejs/kit';
import { db } from '$lib/server/admin';

/**
 * GET /api/export?format=json|csv&type=sightings|rides&limit=1000
 * Export sighting or ride data for external analysis.
 */
export async function GET({ url }) {
    const format = url.searchParams.get('format') || 'json';
    const type = url.searchParams.get('type') || 'sightings';
    const limit = Math.min(parseInt(url.searchParams.get('limit') || '1000'), 5000);
    const workerFilter = url.searchParams.get('worker_id');

    let query = db.collection(type).orderBy('created_at', 'desc').limit(limit);

    if (workerFilter) {
        query = query.where('worker_id', '==', workerFilter);
    }

    const snapshot = await query.get();
    const records = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));

    if (format === 'csv') {
        if (records.length === 0) {
            return new Response('No data', { status: 204 });
        }
        const headers = Object.keys(records[0]);
        const csvRows = [
            headers.join(','),
            ...records.map(r =>
                headers.map(h => {
                    const val = (r as any)[h];
                    if (val === null || val === undefined) return '';
                    if (typeof val === 'object') return `"${JSON.stringify(val).replace(/"/g, '""')}"`;
                    return `"${String(val).replace(/"/g, '""')}"`;
                }).join(',')
            )
        ];

        return new Response(csvRows.join('\n'), {
            headers: {
                'Content-Type': 'text/csv; charset=utf-8',
                'Content-Disposition': `attachment; filename="curbscout-${type}-${new Date().toISOString().slice(0, 10)}.csv"`,
            }
        });
    }

    return json({
        success: true,
        count: records.length,
        exported_at: new Date().toISOString(),
        data: records
    });
}
