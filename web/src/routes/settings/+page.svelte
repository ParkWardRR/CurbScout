<script lang="ts">
    let { data } = $props();
</script>

<div class="flex-col gap-6">
    <header>
        <h1>Settings & Configuration</h1>
        <p class="text-secondary text-small mt-2">
            System configuration overview. Edit environment variables and
            re-deploy to change settings.
        </p>
    </header>

    <!-- System Status -->
    <section class="card section">
        <h2>System Status</h2>
        <div class="config-grid mt-4">
            <div class="config-item">
                <span class="config-label">Active Model</span>
                <span class="config-value">
                    {#if data.activeModel}
                        {data.activeModel.version}
                        <span class="badge badge-green ml-2">deployed</span>
                    {:else}
                        <span class="text-muted">No model deployed</span>
                    {/if}
                </span>
            </div>
            <div class="config-item">
                <span class="config-label">Registered Workers</span>
                <span class="config-value">{data.workers.length}</span>
            </div>
            <div class="config-item">
                <span class="config-label">Mapbox Maps</span>
                <span class="config-value">
                    {#if data.config.mapboxConfigured}
                        <span class="badge badge-green">Configured</span>
                    {:else}
                        <span class="badge badge-amber">Token Missing</span>
                    {/if}
                </span>
            </div>
        </div>
    </section>

    <!-- Environment Config -->
    <section class="card section">
        <h2>Environment Configuration</h2>
        <p class="text-small text-muted mt-2 mb-4">
            These values are read from environment variables at server startup.
        </p>
        <div class="config-grid">
            <div class="config-item">
                <span class="config-label">AUTO_TRAIN_THRESHOLD</span>
                <span class="config-value mono"
                    >{data.config.autoTrainThreshold} corrections</span
                >
            </div>
            <div class="config-item">
                <span class="config-label">GCS_BUCKET</span>
                <span class="config-value mono">{data.config.gcpBucket}</span>
            </div>
            <div class="config-item">
                <span class="config-label">GCP_HUB_URL</span>
                <span class="config-value mono">{data.config.hubUrl}</span>
            </div>
        </div>
    </section>

    <!-- Fleet Workers -->
    <section class="card section">
        <h2>Registered Workers</h2>
        {#if data.workers.length === 0}
            <p class="text-muted mt-4">No workers registered.</p>
        {:else}
            <div class="workers-table mt-4">
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Hostname</th>
                            <th>Hardware</th>
                            <th>Status</th>
                            <th>Rides</th>
                            <th>Sightings</th>
                        </tr>
                    </thead>
                    <tbody>
                        {#each data.workers as w}
                            <tr>
                                <td class="mono text-small">{w.id}</td>
                                <td>{w.hostname || "—"}</td>
                                <td class="text-small text-muted"
                                    >{w.hardware || "—"}</td
                                >
                                <td>
                                    <span
                                        class="badge {w.status === 'online'
                                            ? 'badge-green'
                                            : 'badge-amber'}"
                                    >
                                        {w.status}
                                    </span>
                                </td>
                                <td>{w.ride_count || 0}</td>
                                <td>{w.sighting_count || 0}</td>
                            </tr>
                        {/each}
                    </tbody>
                </table>
            </div>
        {/if}
    </section>

    <!-- API Endpoints -->
    <section class="card section">
        <h2>API Reference</h2>
        <p class="text-small text-muted mt-2 mb-4">
            Available Hub endpoints for worker integration.
        </p>
        <div class="api-list">
            {#each [{ method: "POST", path: "/api/sync", desc: "Bulk data sync from M4 workers" }, { method: "POST", path: "/api/workers/register", desc: "Register a new fleet worker" }, { method: "POST", path: "/api/workers/heartbeat", desc: "Worker liveness pulse" }, { method: "GET", path: "/api/workers", desc: "List all fleet workers" }, { method: "GET", path: "/api/models/active", desc: "Get currently deployed model" }, { method: "GET", path: "/api/jobs/trigger-auto-train", desc: "Evaluate auto-training threshold" }, { method: "POST", path: "/api/webhooks/vast-export", desc: "Vast.ai model export completion" }, { method: "GET", path: "/api/export?format=csv", desc: "Export sighting data (CSV/JSON)" }, { method: "GET", path: "/api/images/{path}", desc: "GCS image proxy for crop thumbnails" }] as endpoint}
                <div class="api-row">
                    <span
                        class="badge method-badge {endpoint.method === 'GET'
                            ? 'badge-green'
                            : 'badge-amber'}">{endpoint.method}</span
                    >
                    <code class="api-path">{endpoint.path}</code>
                    <span class="text-small text-muted">{endpoint.desc}</span>
                </div>
            {/each}
        </div>
    </section>
</div>

<style>
    .section {
        padding: 1.5rem;
    }

    .mt-2 {
        margin-top: 0.5rem;
    }
    .mt-4 {
        margin-top: 1rem;
    }
    .mb-4 {
        margin-bottom: 1rem;
    }
    .ml-2 {
        margin-left: 0.5rem;
    }

    .config-grid {
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
    }

    .config-item {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 0.6rem 0;
        border-bottom: 1px solid var(--border-light);
    }

    .config-item:last-child {
        border-bottom: none;
    }

    .config-label {
        font-weight: 500;
        font-size: 0.9rem;
        color: var(--text-secondary);
    }

    .config-value {
        font-weight: 600;
        display: flex;
        align-items: center;
    }

    .mono {
        font-family: "SF Mono", "Fira Code", monospace;
        font-size: 0.85rem;
        color: var(--accent-blue);
    }

    /* Workers Table */
    table {
        width: 100%;
        border-collapse: collapse;
    }

    th {
        text-align: left;
        font-weight: 500;
        font-size: 0.8rem;
        color: var(--text-muted);
        padding: 0.5rem 0.75rem;
        border-bottom: 1px solid var(--border-light);
        text-transform: uppercase;
        letter-spacing: 0.05em;
    }

    td {
        padding: 0.65rem 0.75rem;
        border-bottom: 1px solid var(--border-light);
        font-size: 0.9rem;
    }

    tr:hover {
        background: var(--bg-hover);
    }

    /* API Reference */
    .api-list {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
    }

    .api-row {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        padding: 0.5rem 0.75rem;
        border-radius: var(--radius-sm);
        transition: background 100ms ease;
    }

    .api-row:hover {
        background: var(--bg-hover);
    }

    .method-badge {
        min-width: 50px;
        text-align: center;
        font-size: 0.65rem;
    }

    .api-path {
        font-family: "SF Mono", "Fira Code", monospace;
        font-size: 0.8rem;
        color: var(--text-primary);
        min-width: 280px;
    }
</style>
