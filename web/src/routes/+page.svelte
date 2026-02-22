<script lang="ts">
    import type { Sighting } from "$lib/types";

    let { data } = $props<{
        stats: {
            rides: number;
            sightings: number;
            pendingReview: number;
            onlineWorkers: number;
            totalWorkers: number;
            activeJobs: number;
            deployedModels: number;
        };
        recentSightings: Sighting[];
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

    function displayMake(s: Sighting): string {
        if (s.predicted_make === "parking_sign") return "🅿️ Parking Sign";
        if (s.predicted_make === "hazard") return `⚠️ ${s.predicted_model}`;
        return `${s.predicted_make} ${s.predicted_model}`;
    }
</script>

<div class="flex-col gap-6">
    <header class="flex justify-between items-center">
        <div>
            <h1>System Dashboard</h1>
            <p class="text-secondary text-small mt-2">
                GCP Orchestration Hub — Real-Time Status
            </p>
        </div>
        <div class="flex gap-4">
            <a href="/models" class="btn btn-primary">Active Learning Lab</a>
            <a href="/fleet" class="btn btn-secondary">Fleet Status</a>
        </div>
    </header>

    <!-- PRIMARY STATS -->
    <div class="grid stats-grid">
        <div class="card stat-card">
            <h3 class="text-muted text-small">Total Rides</h3>
            <p class="stat">{data.stats.rides}</p>
        </div>
        <div class="card stat-card">
            <h3 class="text-muted text-small">Total Sightings</h3>
            <p class="stat">{data.stats.sightings}</p>
        </div>
        <div class="card stat-card">
            <h3 class="text-muted text-small">Pending Review</h3>
            <p class="stat">{data.stats.pendingReview}</p>
            {#if data.stats.pendingReview > 0}
                <a href="/rides" class="review-link">Review now →</a>
            {:else}
                <span class="badge badge-green mt-2">All clear</span>
            {/if}
        </div>
        <div class="card stat-card">
            <h3 class="text-muted text-small">Active Workers</h3>
            <p class="stat">
                {data.stats.onlineWorkers}<span class="stat-sub"
                    >/{data.stats.totalWorkers}</span
                >
            </p>
            <span
                class="badge {data.stats.onlineWorkers > 0
                    ? 'badge-green'
                    : 'badge-amber'} mt-2"
            >
                {data.stats.onlineWorkers > 0 ? "Online" : "Offline"}
            </span>
        </div>
    </div>

    <!-- SECONDARY STATS -->
    <div class="grid secondary-grid">
        <div class="card stat-card-sm">
            <h3 class="text-muted text-small">Active Jobs</h3>
            <p class="stat-sm">{data.stats.activeJobs}</p>
            <a href="/jobs" class="text-small text-muted">View queue →</a>
        </div>
        <div class="card stat-card-sm">
            <h3 class="text-muted text-small">Deployed Models</h3>
            <p class="stat-sm">{data.stats.deployedModels}</p>
            <a href="/models" class="text-small text-muted">View lineage →</a>
        </div>
    </div>

    <!-- RECENT ACTIVITY -->
    <section>
        <h2>Recent Activity</h2>
        <div class="card mt-4 activity-card">
            {#if data.recentSightings.length === 0}
                <p class="text-muted p-4">
                    No sightings yet. Sync data from an M4 worker to begin.
                </p>
            {:else}
                <div class="activity-list">
                    {#each data.recentSightings as s}
                        <div class="activity-row">
                            <div class="activity-info">
                                <span class="activity-title"
                                    >{displayMake(s)}</span
                                >
                                <span class="text-small text-muted"
                                    >{s.predicted_year || ""}</span
                                >
                            </div>
                            <div class="activity-meta">
                                <span
                                    class="badge {s.review_status === 'pending'
                                        ? 'badge-amber'
                                        : s.review_status === 'confirmed'
                                          ? 'badge-green'
                                          : 'badge-blue'}"
                                    >{s.review_status}</span
                                >
                                <span class="text-small text-muted"
                                    >{timeAgo(s.created_at)}</span
                                >
                            </div>
                        </div>
                    {/each}
                </div>
            {/if}
        </div>
    </section>
</div>

<style>
    .stats-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
        gap: 1.5rem;
    }

    .secondary-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
        gap: 1.5rem;
    }

    .stat-card {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
    }

    .stat-card-sm {
        display: flex;
        flex-direction: column;
        gap: 0.4rem;
    }

    .stat {
        font-size: 2.5rem;
        font-weight: 700;
        line-height: 1;
        color: var(--text-primary);
    }

    .stat-sm {
        font-size: 1.8rem;
        font-weight: 700;
        line-height: 1;
        color: var(--text-primary);
    }

    .stat-sub {
        font-size: 1.2rem;
        font-weight: 400;
        color: var(--text-muted);
    }

    .review-link {
        font-size: 0.8rem;
        color: var(--accent-blue);
        font-weight: 500;
        margin-top: 0.5rem;
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

    .btn {
        padding: 0.75rem 1.25rem;
        border-radius: var(--radius-sm);
        font-weight: 600;
        font-size: 0.875rem;
        transition: all 150ms ease;
        text-decoration: none;
        display: inline-block;
    }

    .btn-primary {
        background-color: var(--accent-blue);
        color: white;
    }

    .btn-primary:hover {
        filter: brightness(1.1);
    }

    .btn-secondary {
        background-color: transparent;
        color: var(--text-primary);
        border: 1px solid var(--border-light);
    }

    .btn-secondary:hover {
        background-color: var(--bg-hover);
    }

    /* Activity Feed */
    .activity-card {
        padding: 0;
        overflow: hidden;
    }

    .activity-list {
        display: flex;
        flex-direction: column;
    }

    .activity-row {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 0.85rem 1.25rem;
        border-bottom: 1px solid var(--border-light);
        transition: background 100ms ease;
    }

    .activity-row:last-child {
        border-bottom: none;
    }
    .activity-row:hover {
        background: var(--bg-hover);
    }

    .activity-info {
        display: flex;
        align-items: center;
        gap: 0.75rem;
    }

    .activity-title {
        font-weight: 600;
        font-size: 0.9rem;
    }

    .activity-meta {
        display: flex;
        align-items: center;
        gap: 0.75rem;
    }
</style>
