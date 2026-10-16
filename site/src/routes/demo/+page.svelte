<script lang="ts">
	import { onMount } from 'svelte';
	import Demo from '#lib/Demo.svelte';
	import { duration, posterTime } from '#lib/demo.ts';

	// Plays live, or holds still for the recorder, which steps it with window.__seek.
	let time = $state(0);

	onMount(() => {
		if (new URLSearchParams(location.search).has('record')) {
			Object.assign(window, {
				__seek: (t: number) => (time = t),
				__duration: duration,
				__poster: posterTime
			});
			return;
		}
		let frame = 0;
		const start = performance.now();
		const tick = (now: number) => {
			time = now - start;
			frame = requestAnimationFrame(tick);
		};
		frame = requestAnimationFrame(tick);
		return () => cancelAnimationFrame(frame);
	});
</script>

<svelte:head>
	<title>LangSmart demo</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<div class="center"><div id="stage"><Demo {time} /></div></div>

<style>
	:global(body) {
		margin: 0;
		background: #111;
	}
	.center {
		min-height: 100vh;
		display: grid;
		place-items: center;
	}
	#stage {
		width: 1280px;
		height: 800px;
	}
</style>
