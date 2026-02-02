addEventListener("fetch", event => {
    event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
    const url = new URL(request.url);
    let path = url.pathname;

    const bucket = "ph-gallery-2026";

    // If path ends with / add index.html
    if (path.endsWith("/")) path += "index.html";

    // If no file extension, treat as directory
    if (!path.match(/\.[a-z0-9]+$/i)) path += "/index.html";

    const gcsUrl = "https://storage.googleapis.com/" + bucket + path;

    let response = await fetch(gcsUrl, {
        cf: { cacheTtl: 300 }
    });

    // If 404/403, serve SPA fallback (200.html)
    if (response.status === 404 || response.status === 403) {
        response = await fetch("https://storage.googleapis.com/" + bucket + "/200.html", {
            cf: { cacheTtl: 60 }
        });
    }

    // Clean up GCS headers
    const newHeaders = new Headers(response.headers);
    newHeaders.set("X-Powered-By", "PromptHarbor");
    for (const h of ["x-goog-generation", "x-goog-metageneration", "x-goog-stored-content-encoding",
        "x-goog-stored-content-length", "x-goog-hash", "x-goog-storage-class", "x-guploader-uploadid"]) {
        newHeaders.delete(h);
    }

    return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: newHeaders
    });
}
