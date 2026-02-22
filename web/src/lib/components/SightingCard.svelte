<script lang="ts">
    import type { Sighting } from "$lib/types";

    let { sighting, selected, onSelect } = $props<{
        sighting: Sighting;
        selected: boolean;
        onSelect: () => void;
    }>();

    let imgUrl = $derived(
        sighting.best_crop_id.startsWith("http")
            ? sighting.best_crop_id
            : `/api/crops/${sighting.best_crop_id}`, // fallback proxy if needed
    );

    let confLevel = $derived(
        sighting.classification_confidence >= 0.8
            ? "badge-green"
            : sighting.classification_confidence >= 0.5
              ? "badge-amber"
              : "badge-red",
    );

    let reviewBadge = $derived(
        sighting.review_status === "confirmed"
            ? "badge-green"
            : sighting.review_status === "corrected"
              ? "badge-amber"
              : sighting.review_status === "deleted"
                ? "badge-red"
                : null,
    );
</script>

<div
    class="card sighting-card {selected
        ? 'selected'
        : ''} {sighting.review_status !== 'pending' ? 'reviewed' : ''}"
    onclick={onSelect}
    role="button"
    tabindex="0"
    onkeydown={(e) => e.key === "Enter" && onSelect()}
>
    <div class="img-container">
        <!-- We use a placeholder logic if image fails -->
        <img
            src={imgUrl}
            alt="{sighting.predicted_make} {sighting.predicted_model}"
            onerror={(e) => {
                (e.currentTarget as HTMLImageElement).src =
                    "data:image/svg+xml;utf8,<svg xmlns=\\'http://www.w3.org/2000/svg\\' width=\\'100\\' height=\\'100\\'><rect width=\\'100\\' height=\\'100\\' fill=\\'%23333\\'/></svg>";
            }}
        />

        {#if sighting.sanity_warning}
            <div
                class="sanity-warning"
                title={sighting.sanity_warning_text || "Sanity check failed"}
            >
                ⚠️
            </div>
        {/if}
    </div>

    <div class="details">
        <h3 class="title">
            {sighting.predicted_make}
            {sighting.predicted_model}
        </h3>
        <p class="text-small text-muted">
            {sighting.predicted_year || "Unknown Year"}
        </p>

        <div class="flex items-center justify-between mt-2">
            <span class="badge {confLevel}">
                {(sighting.classification_confidence * 100).toFixed(0)}%
            </span>

            {#if reviewBadge}
                <span class="badge {reviewBadge}">
                    {sighting.review_status}
                </span>
            {/if}
        </div>
    </div>
</div>

<style>
    .sighting-card {
        padding: 0;
        overflow: hidden;
        cursor: pointer;
        transition:
            transform 0.15s ease,
            box-shadow 0.15s ease,
            border-color 0.15s ease;
        display: flex;
        flex-direction: column;
        user-select: none;
    }

    .sighting-card:hover {
        transform: translateY(-2px);
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.5);
    }

    .selected {
        border-color: var(--accent-blue);
        box-shadow: 0 0 0 2px var(--accent-blue);
    }

    .reviewed {
        opacity: 0.7;
    }

    .img-container {
        position: relative;
        height: 140px;
        width: 100%;
        background: #111;
    }

    .img-container img {
        width: 100%;
        height: 100%;
        object-fit: cover;
    }

    .sanity-warning {
        position: absolute;
        top: 8px;
        right: 8px;
        background: var(--status-amber);
        border-radius: 50%;
        width: 24px;
        height: 24px;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 12px;
        box-shadow: 0 2px 4px rgba(0, 0, 0, 0.5);
    }

    .details {
        padding: 1rem;
    }

    .title {
        font-size: 1rem;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
    }

    .mt-2 {
        margin-top: 0.5rem;
    }
</style>
