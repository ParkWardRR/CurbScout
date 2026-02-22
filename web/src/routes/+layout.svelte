<script lang="ts">
	import '../app.css';
	let { children } = $props();
</script>

<div class="layout">
	<aside class="sidebar">
		<div class="brand">
			<h1>CurbScout</h1>
			<p class="text-small text-muted">GCP Orchestration Hub</p>
		</div>
		<nav class="nav-links">
			<a href="/" class="nav-link active">Dashboard</a>
			<a href="/rides" class="nav-link">Rides & Reviews</a>
			<a href="/jobs" class="nav-link">Job Monitor</a>
			<a href="/models" class="nav-link">Active Learning</a>
		</nav>
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
		width: 280px;
		background-color: var(--bg-card);
		border-right: 1px solid var(--border-light);
		padding: 2rem;
		display: flex;
		flex-direction: column;
		gap: 2rem;
	}

	.brand h1 {
		font-size: 1.5rem;
		letter-spacing: -0.02em;
	}

	.nav-links {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}

	.nav-link {
		color: var(--text-secondary);
		padding: 0.75rem 1rem;
		border-radius: var(--radius-sm);
		transition: all var(--duration) var(--ease-out);
		font-weight: 500;
	}

	.nav-link:hover, .nav-link.active {
		background-color: var(--bg-hover);
		color: var(--text-primary);
	}

	.content {
		flex: 1;
		padding: 2rem 3rem;
		max-height: 100vh;
		overflow-y: auto;
	}
</style>
