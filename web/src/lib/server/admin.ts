import { initializeApp, getApps, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
// In a real environment, you'd load GOOGLE_APPLICATION_CREDENTIALS
// or pass a service account. We'll rely on ADC (Application Default Credentials)
// so that Cloud Run automatically picks up its service account.

if (!getApps().length) {
    initializeApp();
}

export const db = getFirestore();
export const storage = getStorage();

db.settings({ ignoreUndefinedProperties: true });

// Type-safe collection references
export const ridesRef = db.collection('rides');
export const videosRef = db.collection('videos');
export const sightingsRef = db.collection('sightings');
export const correctionsRef = db.collection('corrections');
export const jobsRef = db.collection('jobs');
