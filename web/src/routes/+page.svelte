<script lang="ts">
    // Svelte 5 runes for component state
</script>

<div class="flex-col gap-6">
    <header class="flex justify-between items-center">
        <div>
            <h1>System Dashboard</h1>
            <p class="text-secondary text-small mt-2">
                GCP Orchestration Hub Status
            </p>
        </div>
        <div class="flex gap-4">
            <button class="btn btn-primary">Dispatch Vast.ai Training</button>
            <button class="btn btn-secondary">Sync M4</button>
        </div>
    </header>

    <div class="grid">
        <div class="card stat-card">
            <h3 class="text-muted text-small">Total Rides</h3>
            <p class="stat">0</p>
        </div>
        <div class="card stat-card">
            <h3 class="text-muted text-small">Total Sightings</h3>
            <p class="stat">0</p>
        </div>
        <div class="card stat-card">
            <h3 class="text-muted text-small">Active M4 Workers</h3>
            <p class="stat">0</p>
            <div class="badge badge-amber mt-2">Offline</div>
        </div>
        <div class="card stat-card">
            <h3 class="text-muted text-small">Active Vast.ai GPUs</h3>
            <p class="stat">0</p>
            <div class="badge badge-green mt-2">Destroyed</div>
        </div>
    </div>
</div>

<style>
    .grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
        gap: 1.5rem;
    }

    .stat-card {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
    }

    .stat {
        font-size: 2.5rem;
        font-weight: 700;
        line-height: 1;
        color: var(--text-primary);
    }

    .mt-2 {
        margin-top: 0.5rem;
    }

    .btn {
        padding: 0.75rem 1.25rem;
        border-radius: var(--radius-sm);
        font-weight: 600;
        font-size: 0.875rem;
        transition: all 150ms ease;
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
</style>
