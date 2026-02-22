<script lang="ts">
    let { data } = $props();
</script>

<div class="flex-col gap-6">
    <header>
        <h1>Rides & Reviews</h1>
        <p class="text-secondary text-small mt-2">
            Select a ride to review M4 pipeline detections.
        </p>
    </header>

    {#if data.rides.length === 0}
        <div class="card">
            <p class="text-muted">
                No rides have been synced to the GCP Hub yet.
            </p>
        </div>
    {:else}
        <div class="rides-grid">
            {#each data.rides as ride}
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
                        <div><strong>{ride.video_count}</strong> Videos</div>
                    </div>

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
        grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
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
</style>
