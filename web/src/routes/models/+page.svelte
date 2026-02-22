<script lang="ts">
    let dispatching = $state(false);
    let message = $state("");

    async function dispatchTraining() {
        dispatching = true;
        message = "";
        try {
            const res = await fetch("/api/jobs", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    type: "training",
                    target_worker: "vast.ai",
                    payload: { epochs: 50 },
                }),
            });
            if (res.ok) {
                message =
                    "Vast.ai training job dispatched successfully! Check Job Monitor.";
            } else {
                const error = await res.json();
                message = `Failed: ${error.error}`;
            }
        } catch (err: any) {
            message = `Network error: ${err.message}`;
        }
        dispatching = false;
    }
</script>

<div class="flex-col gap-6">
    <header>
        <h1>Active Learning Lab</h1>
        <p class="text-secondary text-small mt-2">
            Trigger finetuning and A/B test model baseline variations.
        </p>
    </header>

    <div class="grid">
        <div class="card bg-card">
            <h2>Dataset Synchronization & Vast.ai Trigger</h2>
            <p class="text-small text-muted mt-2 mb-4">
                Finetune a newly targeted YOLOv8 classification model using the
                active corrections supplied by the Hub. This provisions a remote
                RTX 4090 on Vast.ai, generates the dataset, runs 50 epochs, and
                builds CoreML INT8 weights seamlessly.
            </p>

            <button
                class="btn btn-primary w-full mt-4"
                onclick={dispatchTraining}
                disabled={dispatching}
            >
                {dispatching
                    ? "Dispatching Job..."
                    : "Deploy Ephemeral Trainer (Vast.ai)"}
            </button>

            {#if message}
                <p class="text-small mt-4 text-accent text-center">{message}</p>
            {/if}
        </div>

        <div class="card bg-card">
            <h2>A/B Baseline Evaluation</h2>
            <p class="text-small text-muted mt-2 mb-4">
                Compare a newly uploaded pipeline model version against the
                current baseline using the held-out validation subset of
                sightings.
            </p>

            <div class="flex items-center gap-4 mt-4">
                <div class="model-select flex-1">
                    <label class="text-small text-muted block mb-1" for="modelA"
                        >Baseline (A)</label
                    >
                    <select id="modelA" class="form-input w-full" disabled>
                        <option>jordo23-effnet-b4-mock</option>
                    </select>
                </div>
                <div class="text-muted font-bold pt-4">VS</div>
                <div class="model-select flex-1">
                    <label class="text-small text-muted block mb-1" for="modelB"
                        >Candidate (B)</label
                    >
                    <select id="modelB" class="form-input w-full">
                        <option>latest-yolo-cls-v8n</option>
                        <option>coreml-custom-v1</option>
                    </select>
                </div>
            </div>

            <button class="btn btn-secondary w-full mt-6" disabled>
                Run Evaluation Sandbox (Coming Soon)
            </button>
        </div>
    </div>
</div>

<style>
    .grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
        gap: 1.5rem;
    }

    .bg-card {
        background-color: var(--bg-card);
        border: 1px solid var(--border-light);
        padding: 2rem;
    }

    .btn {
        padding: 0.75rem 1.5rem;
        border-radius: var(--radius-sm);
        font-weight: 500;
        cursor: pointer;
        transition: all var(--duration) var(--ease-out);
        border: none;
    }

    .btn:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }

    .btn-primary {
        background-color: var(--accent-blue);
        color: white;
    }

    .btn-primary:hover:not(:disabled) {
        filter: brightness(1.1);
    }

    .btn-secondary {
        background-color: transparent;
        color: var(--text-primary);
        border: 1px solid var(--border-light);
    }

    .btn-secondary:hover:not(:disabled) {
        background-color: var(--bg-hover);
    }

    .w-full {
        width: 100%;
    }
    .mt-2 {
        margin-top: 0.5rem;
    }
    .mt-4 {
        margin-top: 1rem;
    }
    .mt-6 {
        margin-top: 1.5rem;
    }
    .mb-1 {
        margin-bottom: 0.25rem;
    }
    .mb-4 {
        margin-bottom: 1rem;
    }
    .pt-4 {
        padding-top: 1rem;
    }

    .block {
        display: block;
    }
    .flex {
        display: flex;
    }
    .flex-1 {
        flex: 1;
    }
    .items-center {
        align-items: center;
    }
    .gap-4 {
        gap: 1rem;
    }

    .text-center {
        text-align: center;
    }
    .text-accent {
        color: var(--accent-blue);
    }

    .form-input {
        background-color: var(--bg-default);
        border: 1px solid var(--border-light);
        padding: 0.75rem;
        border-radius: var(--radius-sm);
        color: var(--text-primary);
        font-family: inherit;
        outline: none;
    }

    .form-input:disabled {
        opacity: 0.5;
    }
</style>
