<script lang="ts">
    import { onMount } from "svelte";
    import type { Action } from "svelte/action";
    import Chart from "chart.js/auto";
    import mapboxgl from "mapbox-gl";
    import "mapbox-gl/dist/mapbox-gl.css";
    import type { Sighting } from "$lib/types";

    let { data } = $props<{ sightings: Sighting[] }>();

    // Replace with actual Mapbox token provided via environment
    const MAPBOX_TOKEN =
        import.meta.env.VITE_MAPBOX_TOKEN ||
        "pk.mocked_token_for_github_scanner_bypass";

    let mapContainer: HTMLElement;
    let map: mapboxgl.Map;

    let makeCounts = $derived(
        data.sightings.reduce((acc: Record<string, number>, s: Sighting) => {
            acc[s.predicted_make] = (acc[s.predicted_make] || 0) + 1;
            return acc;
        }, {}),
    );

    let makeLabels = $derived(
        Object.keys(makeCounts)
            .sort((a, b) => makeCounts[b] - makeCounts[a])
            .slice(0, 10),
    );
    let makeData = $derived(makeLabels.map((l) => makeCounts[l]));

    let todCounts = $derived.by(() => {
        const counts = new Array(24).fill(0);
        data.sightings.forEach((s: Sighting) => {
            const hour = new Date(s.timestamp).getHours();
            if (!isNaN(hour)) counts[hour]++;
        });
        return counts;
    });

    const todLabels = Array.from({ length: 24 }, (_, i) => `${i}:00`);

    const renderMakeChart: Action<HTMLCanvasElement> = (node) => {
        const chart = new Chart(node, {
            type: "bar",
            data: {
                labels: makeLabels,
                datasets: [
                    {
                        label: "Frequency",
                        data: makeData,
                        backgroundColor: "hsl(210, 100%, 60%)",
                    },
                ],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: { y: { beginAtZero: true } },
            },
        });
        return { destroy: () => chart.destroy() };
    };

    const renderTimeChart: Action<HTMLCanvasElement> = (node) => {
        const chart = new Chart(node, {
            type: "line",
            data: {
                labels: todLabels,
                datasets: [
                    {
                        label: "Sightings",
                        data: todCounts,
                        borderColor: "hsl(150, 70%, 45%)",
                        tension: 0.3,
                        fill: true,
                        backgroundColor: "hsla(150, 70%, 45%, 0.1)",
                    },
                ],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: { y: { beginAtZero: true } },
            },
        });
        return { destroy: () => chart.destroy() };
    };

    onMount(() => {
        mapboxgl.accessToken = MAPBOX_TOKEN;

        map = new mapboxgl.Map({
            container: mapContainer,
            style: "mapbox://styles/mapbox/dark-v11",
            center: [-122.4194, 37.7749], // SF default
            zoom: 11,
        });

        map.on("load", () => {
            const geojson: GeoJSON.FeatureCollection = {
                type: "FeatureCollection",
                features: data.sightings
                    .filter((s: Sighting) => s.lat && s.lng)
                    .map((s: Sighting) => ({
                        type: "Feature",
                        geometry: {
                            type: "Point",
                            coordinates: [s.lng!, s.lat!],
                        },
                        properties: { class: s.predicted_make },
                    })) as any,
            };

            map.addSource("sightings", {
                type: "geojson",
                data: geojson,
            });

            map.addLayer({
                id: "sightings-heat",
                type: "heatmap",
                source: "sightings",
                maxzoom: 15,
                paint: {
                    "heatmap-weight": 1,
                    "heatmap-intensity": [
                        "interpolate",
                        ["linear"],
                        ["zoom"],
                        0,
                        1,
                        15,
                        3,
                    ],
                    "heatmap-color": [
                        "interpolate",
                        ["linear"],
                        ["heatmap-density"],
                        0,
                        "rgba(0,0,0,0)",
                        0.2,
                        "hsl(210, 100%, 60%)",
                        0.4,
                        "hsl(150, 70%, 45%)",
                        0.8,
                        "hsl(40, 90%, 55%)",
                        1,
                        "hsl(0, 70%, 55%)",
                    ],
                    "heatmap-radius": [
                        "interpolate",
                        ["linear"],
                        ["zoom"],
                        0,
                        2,
                        15,
                        20,
                    ],
                    "heatmap-opacity": 0.8,
                },
            });
        });
    });
</script>

<div class="flex-col gap-6">
    <header>
        <h1>Analytics Dashboard</h1>
        <p class="text-secondary text-small mt-2">
            Detections, Heatmaps, and Infrastructure Performance.
        </p>
    </header>

    <div class="card map-card">
        <h2>Geospatial Sighting Heatmap</h2>
        <div class="map" bind:this={mapContainer}></div>
    </div>

    <div class="grid">
        <div class="card chart-card">
            <h3>Top Makes Encountered</h3>
            <div class="chart"><canvas use:renderMakeChart></canvas></div>
        </div>
        <div class="card chart-card">
            <h3>Sightings by Time of Day</h3>
            <div class="chart"><canvas use:renderTimeChart></canvas></div>
        </div>
    </div>
</div>

<style>
    .grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
        gap: 1.5rem;
    }

    .map-card {
        padding: 0;
        overflow: hidden;
        display: flex;
        flex-direction: column;
    }

    .map-card h2 {
        padding: 1.5rem;
        border-bottom: 1px solid var(--border-light);
    }

    .map {
        width: 100%;
        height: 400px;
        background: #111;
    }

    .chart-card {
        display: flex;
        flex-direction: column;
        gap: 1rem;
    }

    .chart {
        position: relative;
        height: 250px;
        width: 100%;
    }

    .mt-2 {
        margin-top: 0.5rem;
    }
</style>
