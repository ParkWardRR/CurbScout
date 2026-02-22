<script lang="ts">
    import type { Ride } from "$lib/types";

    let { data } = $props<{
        rides: (Ride & {
            review_progress?: {
                pending: number;
                confirmed: number;
                corrected: number;
            };
        })[];
    }>();

    let filterStatus = $state("all");

    let filteredRides = $derived(
        filterStatus === "all"
            ? data.rides
            : filterStatus === "reviewed"
              ? data.rides.filter((r: (typeof data.rides)[0]) => r.reviewed)
              : data.rides.filter((r: (typeof data.rides)[0]) => !r.reviewed),
    );

    function progressPercent(ride: (typeof data.rides)[0]): number {
        if (!ride.review_progress || ride.sighting_count === 0) return 0;
        const done =
            ride.review_progress.confirmed + ride.review_progress.corrected;
        return Math.round((done / ride.sighting_count) * 100);
    }
</script>

<div class="flex-col gap-6">
    <header class="flex justify-between items-center">
        <div>
            <h1>Rides & Reviews</h1>
            <p class="text-secondary text-small mt-2">
                Select a ride to review M4 pipeline detections.
            </p>
        </div>
        <div class="flex gap-4 items-center">
            <select class="filter-select" bind:value={filterStatus}>
                <option value="all">All Rides ({data.rides.length})</option>
                <option value="needs_review">Needs Review</option>
                <option value="reviewed">Reviewed</option>
            </select>
            <a
                href="/api/export?type=sightings&format=csv"
                class="btn btn-secondary text-small"
                download
            >
                Export CSV
            </a>
        </div>
    </header>

    {#if filteredRides.length === 0}
        <div class="card">
            <p class="text-muted">
                {filterStatus === "all"
                    ? "No rides have been synced to the GCP Hub yet."
                    : "No rides match this filter."}
            </p>
        </div>
    {:else}
        <div class="rides-grid">
            {#each filteredRides as ride}
                <a
                    href="/rides/{ride.id}/review"
                    class="card ride-card flex-col gap-4"
                >
                    <div class="flex justify-between items-center">
                        <h3>{new Date(ride.start_ts).toLocaleDateString()}</h3>
                        {#if ride.reviewed}
                            <span class="badge badge-green">Reviewed</span>
                        {:else}
                            <span class="badge badge-amber">Needs Review</span>
                        {/if}
                    </div>

                    <div class="flex gap-4 text-small text-muted">
                        <div>
                            <strong>{ride.sighting_count}</strong> Sightings
                        </div>
                        <div>
                            <strong>{ride.video_count}</strong> Videos
                        </div>
                        {#if ride.worker_id}
                            <div class="worker-tag">
                                📡 {ride.worker_id}
                            </div>
                        {/if}
                    </div>

                    {#if ride.review_progress && ride.sighting_count > 0}
                        <div class="progress-section">
                            <div class="progress-bar">
                                <div
                                    class="progress-fill"
                                    style="width: {progressPercent(ride)}%"
                                ></div>
                            </div>
                            <div class="progress-labels text-small">
                                <span class="text-green"
                                    >✓ {ride.review_progress.confirmed}</span
                                >
                                <span class="text-blue"
                                    >✎ {ride.review_progress.corrected}</span
                                >
                                <span class="text-muted"
                                    >⏳ {ride.review_progress.pending}</span
                                >
                            </div>
                        </div>
                    {/if}

                    <div class="mt-2 text-small text-accent">
                        Click to start review &rarr;
                    </div>
                </a>
            {/each}
        </div>
    {/if}
</div>

<style>
    .rides-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
        gap: 1.5rem;
    }

    .ride-card {
        transition:
            transform var(--duration) var(--ease-out),
            border-color var(--duration) var(--ease-out);
        text-decoration: none;
        color: inherit;
        display: block;
    }

    .ride-card:hover {
        transform: translateY(-2px);
        border-color: var(--accent-blue);
    }

    .text-accent {
        color: var(--accent-blue);
        font-weight: 500;
    }

    .mt-2 {
        margin-top: 0.5rem;
    }

    .filter-select {
        background: var(--bg-card);
        color: var(--text-primary);
        border: 1px solid var(--border-light);
        border-radius: var(--radius-sm);
        padding: 0.5rem 0.75rem;
        font-size: 0.875rem;
    }

    .btn {
        padding: 0.5rem 1rem;
        border-radius: var(--radius-sm);
        font-weight: 600;
        text-decoration: none;
        display: inline-block;
    }

    .btn-secondary {
        background-color: transparent;
        color: var(--text-primary);
        border: 1px solid var(--border-light);
    }

    .btn-secondary:hover {
        background-color: var(--bg-hover);
    }

    .worker-tag {
        font-size: 0.7rem;
        background: var(--bg-hover);
        padding: 0.15rem 0.5rem;
        border-radius: 4px;
    }

    .progress-section {
        display: flex;
        flex-direction: column;
        gap: 0.4rem;
    }

    .progress-bar {
        height: 4px;
        background: var(--border-light);
        border-radius: 2px;
        overflow: hidden;
    }

    .progress-fill {
        height: 100%;
        background: linear-gradient(
            90deg,
            hsl(140, 70%, 50%),
            hsl(200, 70%, 50%)
        );
        border-radius: 2px;
        transition: width 300ms ease;
    }

    .progress-labels {
        display: flex;
        gap: 0.75rem;
    }

    .text-green {
        color: hsl(140, 70%, 55%);
    }
    .text-blue {
        color: hsl(210, 70%, 60%);
    }
</style>
