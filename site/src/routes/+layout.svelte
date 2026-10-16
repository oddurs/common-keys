<script lang="ts">
	import { asset } from '$app/paths';
	import type { LayoutProps } from './$types';

	let { children }: LayoutProps = $props();
</script>

<svelte:head>
	<link rel="icon" href={asset('icon.svg')} />
</svelte:head>

{@render children()}
