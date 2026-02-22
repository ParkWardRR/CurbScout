<script lang="ts">
    import { onMount, onDestroy } from "svelte";
    import type { Job } from "$lib/types";

    let jobs = $state<Job[]>([]);
    let connectionStatus = $state("connecting...");
    let eventSource: EventSource | null = null;

    onMount(() => {
        try {
            eventSource = new EventSource("/api/jobs/stream");

            eventSource.onmessage = (event) => {
                const parsed = JSON.parse(event.data);
                jobs = parsed;
                connectionStatus = "connected (live)";
            };

            eventSource.onerror = () => {
                connectionStatus = "reconnecting...";
            };
        } catch (e) {
            console.error("SSE Connection Failed", e);
            connectionStatus = "failed";
        }
    });

    onDestroy(() => {
        if (eventSource) {
            eventSource.close();
        }
    });

    function statusColor(status: string) {
        switch (status) {
            case "completed":
                return "badge-green";
            case "running":
                return "badge-blue";
            case "failed":
                return "badge-red";
            default:
                return "badge-amber";
        }
    }
</script>

<div class="flex-col gap-6">
    <header class="flex justify-between items-center">
        <div>
            <h1>Job Monitor</h1>
            <p class="text-secondary text-small mt-2">
                Real-time pipeline orchestration log
            </p>
        </div>
        <div class="flex items-center gap-2">
            <span
                class="status-dot {connectionStatus.includes('connected')
                    ? 'live'
                    : ''}"
            ></span>
            <span class="text-small text-muted">{connectionStatus}</span>
        </div>
    </header>

    <div class="card overflow-hidden">
        <table class="w-full">
            <thead>
                <tr>
                    <th class="text-left py-2 border-b">Job ID</th>
                    <th class="text-left py-2 border-b">Type</th>
                    <th class="text-left py-2 border-b">Target</th>
                    <th class="text-left py-2 border-b">Status</th>
                    <th class="text-right py-2 border-b">Created At</th>
                </tr>
            </thead>
            <tbody>
                {#if jobs.length === 0}
                    <tr>
                        <td colspan="5" class="text-center py-6 text-muted"
                            >No jobs in queue.</td
                        >
                    </tr>
                {/if}
                {#each jobs as job (job.id)}
                    <tr class="hover-row">
                        <td class="py-3 text-small font-mono truncate max-w-xs"
                            >{job.id}</td
                        >
                        <td class="py-3 capitalize">{job.type}</td>
                        <td class="py-3 font-medium text-accent"
                            >{job.target_worker}</td
                        >
                        <td class="py-3">
                            <span class="badge {statusColor(job.status)}"
                                >{job.status}</span
                            >
                        </td>
                        <td class="py-3 text-right text-small text-secondary">
                            {new Date(job.created_at).toLocaleString()}
                        </td>
                    </tr>
                {/each}
            </tbody>
        </table>
    </div>
</div>

<style>
    .w-full {
        width: 100%;
        border-collapse: collapse;
    }
    .py-2 {
        padding-top: 0.5rem;
        padding-bottom: 0.5rem;
    }
    .py-3 {
        padding-top: 0.75rem;
        padding-bottom: 0.75rem;
        border-bottom: 1px solid var(--border-light);
    }
    .border-b {
        border-bottom: 1px solid var(--border-light);
    }

    .hover-row:hover {
        background-color: var(--bg-hover);
    }

    .badge-blue {
        background-color: color-mix(
            in srgb,
            var(--accent-blue) 20%,
            transparent
        );
        color: var(--accent-blue);
    }

    .text-accent {
        color: var(--accent-blue);
    }

    .truncate {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }
    .max-w-xs {
        max-width: 15vw;
    }

    .overflow-hidden {
        overflow-x: auto;
        padding: 1.5rem;
    }

    th {
        color: var(--text-muted);
        font-weight: 500;
        font-size: 0.875rem;
    }

    .status-dot {
        display: inline-block;
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background-color: var(--status-amber);
    }
    .status-dot.live {
        background-color: var(--status-green);
        box-shadow: 0 0 8px var(--status-green);
    }
    .mt-2 {
        margin-top: 0.5rem;
    }
</style>
