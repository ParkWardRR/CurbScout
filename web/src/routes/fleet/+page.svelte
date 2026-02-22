<script lang="ts">
    import type { Worker } from "$lib/types";

    let { data } = $props<{
        workers: Worker[];
        leaderboard: {
            name: string;
            confirmed: number;
            corrected: number;
            total: number;
        }[];
    }>();

    function timeAgo(iso: string): string {
        const diff = Date.now() - new Date(iso).getTime();
        const mins = Math.floor(diff / 60000);
        if (mins < 1) return "just now";
        if (mins < 60) return `${mins}m ago`;
        const hrs = Math.floor(mins / 60);
        if (hrs < 24) return `${hrs}h ago`;
        return `${Math.floor(hrs / 24)}d ago`;
    }
</script>

<div class="flex-col gap-6">
    <header>
        <h1>Fleet Management</h1>
        <p class="text-secondary text-small mt-2">
            Monitor device health, data provenance, and reviewer throughput.
        </p>
    </header>

    <!-- WORKER CARDS -->
    <section>
        <h2>Registered Workers</h2>
        <div class="worker-grid mt-4">
            {#if data.workers.length === 0}
                <div class="card empty-state">
                    <p class="text-muted">
                        No workers registered yet. Start a pipeline on an M4 to
                        register.
                    </p>
                </div>
            {:else}
                {#each data.workers as worker}
                    <div class="card worker-card">
                        <div class="worker-header">
                            <div class="status-dot {worker.status}"></div>
                            <h3>{worker.hostname}</h3>
                        </div>
                        <div class="worker-meta">
                            <span class="text-small text-muted"
                                >{worker.hardware}</span
                            >
                            <span class="text-small text-muted"
                                >Last seen: {timeAgo(worker.last_seen)}</span
                            >
                        </div>
                        <div class="worker-stats">
                            <div class="stat">
                                <span class="stat-value"
                                    >{worker.ride_count}</span
                                >
                                <span class="stat-label">Rides</span>
                            </div>
                            <div class="stat">
                                <span class="stat-value"
                                    >{worker.sighting_count}</span
                                >
                                <span class="stat-label">Sightings</span>
                            </div>
                            <div class="stat">
                                <span
                                    class="stat-value badge-pill {worker.status ===
                                    'online'
                                        ? 'online-pill'
                                        : 'offline-pill'}">{worker.status}</span
                                >
                                <span class="stat-label">Status</span>
                            </div>
                        </div>
                    </div>
                {/each}
            {/if}
        </div>
    </section>

    <!-- REVIEWER LEADERBOARD -->
    <section>
        <h2>Reviewer Leaderboard</h2>
        <div class="card mt-4">
            {#if data.leaderboard.length === 0}
                <p class="text-muted text-small p-4">No reviews yet.</p>
            {:else}
                <table class="leaderboard-table">
                    <thead>
                        <tr>
                            <th>#</th>
                            <th>Reviewer</th>
                            <th>Confirmed</th>
                            <th>Corrected</th>
                            <th>Total</th>
                        </tr>
                    </thead>
                    <tbody>
                        {#each data.leaderboard as entry, i}
                            <tr>
                                <td class="rank">{i + 1}</td>
                                <td>{entry.name}</td>
                                <td class="text-green">{entry.confirmed}</td>
                                <td class="text-amber">{entry.corrected}</td>
                                <td class="font-bold">{entry.total}</td>
                            </tr>
                        {/each}
                    </tbody>
                </table>
            {/if}
        </div>
    </section>
</div>

<style>
    .worker-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
        gap: 1.5rem;
    }

    .worker-card {
        display: flex;
        flex-direction: column;
        gap: 1rem;
        transition:
            transform 0.15s ease,
            box-shadow 0.15s ease;
    }

    .worker-card:hover {
        transform: translateY(-2px);
        box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4);
    }

    .worker-header {
        display: flex;
        align-items: center;
        gap: 0.75rem;
    }

    .worker-header h3 {
        font-size: 1.1rem;
        font-weight: 600;
    }

    .status-dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        flex-shrink: 0;
    }

    .status-dot.online {
        background: hsl(140, 70%, 50%);
        box-shadow: 0 0 6px hsl(140, 70%, 50%);
    }

    .status-dot.offline {
        background: hsl(0, 0%, 40%);
    }

    .worker-meta {
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
    }

    .worker-stats {
        display: flex;
        gap: 1.5rem;
        padding-top: 0.75rem;
        border-top: 1px solid var(--border-light);
    }

    .stat {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.25rem;
    }

    .stat-value {
        font-size: 1.25rem;
        font-weight: 700;
    }

    .stat-label {
        font-size: 0.7rem;
        text-transform: uppercase;
        color: var(--text-secondary);
        letter-spacing: 0.05em;
    }

    .badge-pill {
        font-size: 0.75rem;
        padding: 0.15rem 0.5rem;
        border-radius: 999px;
        text-transform: uppercase;
        font-weight: 600;
        letter-spacing: 0.04em;
    }

    .online-pill {
        background: hsla(140, 70%, 50%, 0.15);
        color: hsl(140, 70%, 55%);
    }

    .offline-pill {
        background: hsla(0, 0%, 50%, 0.15);
        color: hsl(0, 0%, 60%);
    }

    .empty-state {
        grid-column: 1 / -1;
        text-align: center;
        padding: 3rem;
    }

    /* Leaderboard */
    .leaderboard-table {
        width: 100%;
        border-collapse: collapse;
    }

    .leaderboard-table th,
    .leaderboard-table td {
        padding: 0.75rem 1rem;
        text-align: left;
        border-bottom: 1px solid var(--border-light);
    }

    .leaderboard-table th {
        font-size: 0.75rem;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--text-secondary);
    }

    .leaderboard-table tbody tr:hover {
        background: var(--bg-hover, rgba(255, 255, 255, 0.03));
    }

    .rank {
        color: var(--text-secondary);
        font-weight: 600;
        width: 40px;
    }

    .text-green {
        color: hsl(140, 70%, 55%);
    }
    .text-amber {
        color: hsl(40, 90%, 55%);
    }
    .font-bold {
        font-weight: 700;
    }
    .mt-2 {
        margin-top: 0.5rem;
    }
    .mt-4 {
        margin-top: 1rem;
    }
    .p-4 {
        padding: 1rem;
    }
</style>
