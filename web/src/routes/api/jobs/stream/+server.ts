import { db } from '$lib/server/admin';

export function GET() {
    const stream = new ReadableStream({
        start(controller) {
            // Set up Firestore realtime listener
            const unsubscribe = db.collection('jobs')
                .orderBy('created_at', 'desc')
                .limit(100)
                .onSnapshot((snapshot) => {
                    const jobs = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));

                    // Send the snapshot data as an SSE message
                    const payload = JSON.stringify(jobs);
                    controller.enqueue(`data: ${payload}\n\n`);
                }, (error) => {
                    console.error("Firestore listener error:", error);
                    controller.error(error);
                });

            // Handle disconnection
            return () => {
                unsubscribe();
            };
        },
        cancel() {
            // This matches standard node stream destruction
            console.log('Stream canceled by client.');
        }
    });

    return new Response(stream, {
        headers: {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive'
        }
    });
}
