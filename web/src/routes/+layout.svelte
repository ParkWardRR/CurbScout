<script lang="ts">
	import "../app.css";
	import { page } from "$app/state";
	let { children } = $props();

	const navItems = [
		{ href: "/", label: "Dashboard", icon: "📊" },
		{ href: "/rides", label: "Rides & Reviews", icon: "🚲" },
		{ href: "/analytics", label: "Analytics", icon: "🗺️" },
		{ href: "/jobs", label: "Job Monitor", icon: "⚡" },
		{ href: "/models", label: "Active Learning", icon: "🧠" },
		{ href: "/fleet", label: "Fleet", icon: "📡" },
		{ href: "/settings", label: "Settings", icon: "⚙️" },
	];

	function isActive(href: string): boolean {
		if (href === "/") return page.url.pathname === "/";
		return page.url.pathname.startsWith(href);
	}
</script>

<div class="layout">
	<aside class="sidebar">
		<div class="brand">
			<h1>CurbScout</h1>
			<p class="text-small text-muted">GCP Orchestration Hub</p>
		</div>
		<nav class="nav-links">
			{#each navItems as item}
				<a
					href={item.href}
					class="nav-link"
					class:active={isActive(item.href)}
				>
					<span class="nav-icon">{item.icon}</span>
					{item.label}
				</a>
			{/each}
		</nav>
		<div class="sidebar-footer">
			<a
				href="/api/export?format=csv&type=sightings"
				class="text-small text-muted footer-link"
				download
			>
				📥 Export All Data
			</a>
		</div>
	</aside>

	<main class="content">
		{@render children()}
	</main>
</div>

<style>
	.layout {
		display: flex;
		min-height: 100vh;
	}

	.sidebar {
		width: 260px;
		background-color: var(--bg-card);
		border-right: 1px solid var(--border-light);
		padding: 1.5rem;
		display: flex;
		flex-direction: column;
		gap: 1.5rem;
		position: sticky;
		top: 0;
		height: 100vh;
		overflow-y: auto;
	}

	.brand h1 {
		font-size: 1.35rem;
		letter-spacing: -0.02em;
		background: linear-gradient(
			135deg,
			hsl(210, 100%, 65%),
			hsl(150, 70%, 55%)
		);
		-webkit-background-clip: text;
		-webkit-text-fill-color: transparent;
		background-clip: text;
	}

	.nav-links {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		flex: 1;
	}

	.nav-link {
		color: var(--text-secondary);
		padding: 0.6rem 0.85rem;
		border-radius: var(--radius-sm);
		transition: all var(--duration) var(--ease-out);
		font-weight: 500;
		font-size: 0.9rem;
		display: flex;
		align-items: center;
		gap: 0.6rem;
	}

	.nav-link:hover {
		background-color: var(--bg-hover);
		color: var(--text-primary);
	}

	.nav-link.active {
		background-color: color-mix(
			in srgb,
			var(--accent-blue) 15%,
			transparent
		);
		color: var(--accent-blue);
	}

	.nav-icon {
		font-size: 1rem;
		line-height: 1;
		width: 1.25rem;
		text-align: center;
	}

	.sidebar-footer {
		padding-top: 1rem;
		border-top: 1px solid var(--border-light);
	}

	.footer-link {
		display: block;
		padding: 0.5rem 0;
		transition: color 150ms ease;
	}

	.footer-link:hover {
		color: var(--text-primary) !important;
	}

	.content {
		flex: 1;
		padding: 2rem 3rem;
		max-height: 100vh;
		overflow-y: auto;
	}
</style>
