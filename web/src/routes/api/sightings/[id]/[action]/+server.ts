import { json } from '@sveltejs/kit';
import { db, sightingsRef, correctionsRef } from '$lib/server/admin';
import { v4 as uuidv4 } from 'uuid';
import type { Correction, Sighting } from '$lib/types';

export async function POST({ params, request }) {
    const { id, action } = params;

    if (!['confirm', 'correct', 'delete'].includes(action)) {
        return json({ error: `Invalid action ${action}` }, { status: 400 });
    }

    try {
        const sightingDoc = await sightingsRef.doc(id).get();
        if (!sightingDoc.exists) {
            return json({ error: 'Sighting not found' }, { status: 404 });
        }

        const sightingData = sightingDoc.data() as Sighting;
        const batch = db.batch();

        let updatePayload: Partial<Sighting> = { updated_at: new Date().toISOString() };
        let correctionData: Partial<Correction> = {
            id: uuidv4(),
            sighting_id: id,
            created_at: new Date().toISOString(),
            previous_values: {
                predicted_make: sightingData.predicted_make,
                predicted_model: sightingData.predicted_model,
                predicted_year: sightingData.predicted_year,
                review_status: sightingData.review_status,
                deleted: sightingData.deleted
            }
        };

        if (action === 'confirm') {
            updatePayload.review_status = 'confirmed';
            correctionData.corrected_fields = { review_status: true };
            correctionData.new_values = { review_status: 'confirmed' };
        }
        else if (action === 'delete') {
            updatePayload.review_status = 'deleted';
            updatePayload.deleted = true;
            correctionData.corrected_fields = { review_status: true, deleted: true };
            correctionData.new_values = { review_status: 'deleted', deleted: true };
        }
        else if (action === 'correct') {
            const body = await request.json();
            const { make, model, year, note } = body;

            updatePayload.review_status = 'corrected';
            updatePayload.predicted_make = make;
            updatePayload.predicted_model = model;
            if (year !== undefined) updatePayload.predicted_year = year;

            correctionData.note = note;
            correctionData.corrected_fields = {
                review_status: true,
                predicted_make: true,
                predicted_model: true,
                ...(year !== undefined ? { predicted_year: true } : {})
            };
            correctionData.new_values = {
                review_status: 'corrected',
                predicted_make: make,
                predicted_model: model,
                ...(year !== undefined ? { predicted_year: year } : {})
            };
        }

        // Apply updates to the sighting
        batch.update(sightingDoc.ref, updatePayload);

        // Save the correction history
        const newCorrectionRef = correctionsRef.doc(correctionData.id!);
        batch.set(newCorrectionRef, correctionData);

        await batch.commit();

        return json({ success: true, sighting: { ...sightingData, ...updatePayload } });
    } catch (err: any) {
        console.error(`Failed to ${action} sighting ${id}:`, err);
        return json({ error: err.message }, { status: 500 });
    }
}
