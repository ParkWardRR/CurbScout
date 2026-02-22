<script lang="ts">
    import SightingCard from "$lib/components/SightingCard.svelte";
    import type { Sighting } from "$lib/types";

    let { data } = $props();
    let sightings = $state<Sighting[]>(data.sightings);

    let selectedIndex = $state(0);
    let isReviewing = $state(false);

    let reviewedCount = $derived(
        sightings.filter((s) => s.review_status !== "pending").length,
    );
    let progress = $derived((reviewedCount / sightings.length) * 100 || 0);

    // Correction modal state
    let showModal = $state(false);
    let correctMake = $state("");
    let correctModel = $state("");

    async function reviewSighting(action: "confirm" | "delete" | "correct") {
        if (sightings.length === 0 || isReviewing) return;
        isReviewing = true;

        const current = sightings[selectedIndex];
        const payload =
            action === "correct"
                ? { make: correctMake, model: correctModel }
                : null;

        try {
            const res = await fetch(`/api/sightings/${current.id}/${action}`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: payload ? JSON.stringify(payload) : undefined,
            });

            if (res.ok) {
                const { sighting } = await res.json();
                sightings[selectedIndex] = sighting; // update local state

                // Auto-advance
                if (selectedIndex < sightings.length - 1) {
                    selectedIndex++;
                }
            } else {
                console.error("Failed action:", await res.text());
            }
        } finally {
            isReviewing = false;
            if (action === "correct") {
                showModal = false;
            }
        }
    }

    function handleKeydown(e: KeyboardEvent) {
        if (showModal) {
            if (e.key === "Escape") showModal = false;
            // If inside modal and Enter pressed, we should submit the modal form implicitly.
            // Handled via standard form submission if using a form button, but we'll intercept here if needed.
            return;
        }

        switch (e.key) {
            case "ArrowRight":
                e.preventDefault();
                if (selectedIndex < sightings.length - 1) selectedIndex++;
                break;
            case "ArrowLeft":
                e.preventDefault();
                if (selectedIndex > 0) selectedIndex--;
                break;
            case "Enter":
                e.preventDefault();
                reviewSighting("confirm");
                break;
            case "Backspace":
                e.preventDefault();
                reviewSighting("delete");
                break;
            case "/":
                e.preventDefault();
                correctMake = sightings[selectedIndex].predicted_make;
                correctModel = sightings[selectedIndex].predicted_model;
                showModal = true;
                break;
        }
    }
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="flex-col gap-6">
    <header class="flex justify-between items-center">
        <div>
            <h1>
                Review: Ride {new Date(data.ride.start_ts).toLocaleDateString()}
            </h1>
            <p class="text-secondary text-small mt-2">
                Use keyboard shortcuts: ⏎ Confirm | ⌫ Delete | / Correct | ← →
                Navigate
            </p>
        </div>
        <div class="flex-col items-center">
            <span class="badge badge-blue mb-2"
                >{reviewedCount} / {sightings.length} Reviewed</span
            >
            <progress value={progress} max="100"></progress>
        </div>
    </header>

    <div class="grid">
        {#each sightings as sighting, i}
            <SightingCard
                {sighting}
                selected={i === selectedIndex}
                onSelect={() => (selectedIndex = i)}
            />
        {/each}
    </div>
</div>

{#if showModal}
    <div class="modal-backdrop">
        <div class="modal-card">
            <h2>Correct Sighting</h2>
            <div class="flex-col gap-4 mt-6">
                <label>
                    Make
                    <input type="text" bind:value={correctMake} autofocus />
                </label>
                <label>
                    Model
                    <input type="text" bind:value={correctModel} />
                </label>
                <div class="flex gap-4 mt-2">
                    <button
                        class="btn btn-primary flex-1"
                        onclick={() => reviewSighting("correct")}
                        >Save (⏎)</button
                    >
                    <button
                        class="btn btn-secondary flex-1"
                        onclick={() => (showModal = false)}>Cancel (Esc)</button
                    >
                </div>
            </div>
        </div>
    </div>
{/if}

<style>
    .grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
        gap: 1.5rem;
        padding-bottom: 2rem;
    }

    progress {
        width: 150px;
        height: 8px;
        appearance: none;
    }

    progress::-webkit-progress-bar {
        background-color: var(--border-light);
        border-radius: 4px;
    }
    progress::-webkit-progress-value {
        background-color: var(--accent-blue);
        border-radius: 4px;
    }

    .badge-blue {
        background-color: var(--accent-blue);
        color: white;
    }

    /* Modal CSS */
    .modal-backdrop {
        position: fixed;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        background: rgba(0, 0, 0, 0.8);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 100;
    }

    .modal-card {
        background: var(--bg-card);
        border: 1px solid var(--border-light);
        padding: 2rem;
        border-radius: var(--radius-md);
        width: 400px;
        max-width: 90vw;
    }

    label {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
        font-size: 0.875rem;
        color: var(--text-secondary);
    }

    input {
        background: var(--bg-app);
        border: 1px solid var(--border-light);
        color: var(--text-primary);
        padding: 0.75rem;
        border-radius: var(--radius-sm);
        font-family: inherit;
        font-size: 1rem;
    }

    .btn {
        padding: 0.75rem;
        border-radius: var(--radius-sm);
        font-weight: 600;
        cursor: pointer;
    }
    .btn-primary {
        background: var(--accent-blue);
        color: white;
        border: none;
    }
    .btn-secondary {
        background: transparent;
        color: var(--text-primary);
        border: 1px solid var(--border-light);
    }

    .mt-6 {
        margin-top: 1.5rem;
    }
</style>
