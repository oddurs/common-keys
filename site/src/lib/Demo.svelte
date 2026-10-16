<script lang="ts">
	import { frameAt, type WindowID, type Word } from './demo';

	let { time }: { time: number } = $props();

	const frame = $derived(frameAt(time));
	const titles: Record<WindowID, string> = { notes: 'Notes', chat: 'Chat' };
	// Entrances are drawn from the scene clock, not CSS animations, so recorded frames match it.
	const flagScale = $derived(1 + 0.45 * Math.max(0, 1 - frame.sinceFlag / 450));
	const bubbleIn = $derived(Math.min(1, frame.sinceBubble / 140));
	const order: WindowID[] = $derived(frame.front === 'notes' ? ['chat', 'notes'] : ['notes', 'chat']);

	function lines(words: Word[]): { word: Word; index: number }[][] {
		const result: { word: Word; index: number }[][] = [[]];
		words.forEach((word, index) => {
			if (word.newline) result.push([]);
			result[result.length - 1].push({ word, index });
		});
		return result;
	}
</script>

<!-- Between loops only the words fade; the desktop stays, so the loop never flashes. -->
<div class="stage">
	<div class="menubar">
		<span class="app">{titles[frame.front]}</span>
		<span class="item">File</span>
		<span class="item">Edit</span>
		<span class="item">View</span>
		<span class="spacer"></span>
		<span class="flag" aria-label="Current keyboard" style:transform="scale({flagScale})">{frame.flag}</span>
		<span class="clock">Thu 9:41</span>
	</div>

	{#each order as id (id)}
		{@const front = id === frame.front}
		<section class="window {id}" class:front>
			<header>
				<span class="lights"><i></i><i></i><i></i></span>
				<span class="title">{titles[id]}</span>
			</header>
			<div class="body" style:opacity={frame.opacity}>
				{#each lines(frame.windows[id]) as line, lineIndex (lineIndex)}
					<p>
						{#each line as { word, index }, position (index)}
							{#if position > 0}{' '}{/if}<span class="word" class:fixed={!!word.fixed}
								>{word.text}{#if frame.bubble?.window === id && frame.bubble.index === index && word.fixed}
									<span
										class="bubble"
										style:opacity={bubbleIn}
										style:transform="translateY({(1 - bubbleIn) * -3}px)"
									>
										<span>{word.fixed.flag}</span>
										<b>{word.fixed.replacement}</b>
										<s>{word.fixed.original}</s>
										<kbd>⌘Z</kbd>
									</span>
								{/if}</span
							>{#if front && index === frame.windows[id].length - 1}<span
									class="caret"
									class:on={frame.caretOn}
								></span>{/if}
						{/each}
					</p>
				{/each}
			</div>
		</section>
	{/each}

	{#if frame.keys}
		<div class="keys" aria-label="Keys pressed" style:opacity={frame.opacity}>
			{#each [...frame.keys] as key, index (index)}<kbd>{key}</kbd>{/each}
		</div>
	{/if}

	{#if frame.caption}
		<p class="caption" style:opacity={frame.opacity}>{frame.caption}</p>
	{/if}
</div>

<style>
	.stage {
		position: relative;
		width: 1280px;
		height: 800px;
		overflow: hidden;
		background: linear-gradient(160deg, #c9d6ff 0%, #e4e4ea 55%, #f5d7c4 100%);
		font: 15px/1.4 -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
		color: #1d1d1f;
		-webkit-font-smoothing: antialiased;
	}

	.menubar {
		height: 30px;
		padding: 0 18px;
		display: flex;
		align-items: center;
		gap: 22px;
		background: rgba(246, 246, 246, 0.82);
		backdrop-filter: blur(20px);
		font-size: 14px;
	}
	.app {
		font-weight: 700;
	}
	.spacer {
		flex: 1;
	}
	.flag {
		display: inline-block;
		font-size: 17px;
		line-height: 1;
	}

	.window {
		position: absolute;
		width: 640px;
		height: 430px;
		border-radius: 14px;
		background: #fff;
		box-shadow:
			0 24px 70px rgba(0, 0, 0, 0.22),
			0 0 0 0.5px rgba(0, 0, 0, 0.18);
	}
	.window.notes {
		left: 150px;
		top: 120px;
	}
	.window.chat {
		left: 500px;
		top: 210px;
	}
	.window:not(.front) {
		filter: saturate(0.6) brightness(0.97);
	}
	.window:not(.front) header {
		opacity: 0.6;
	}
	header {
		height: 44px;
		display: flex;
		align-items: center;
		padding: 0 16px;
		border-bottom: 1px solid rgba(0, 0, 0, 0.07);
	}
	.lights {
		display: flex;
		gap: 8px;
	}
	.lights i {
		width: 12px;
		height: 12px;
		border-radius: 50%;
		background: #ff5f57;
	}
	.lights i:nth-child(2) {
		background: #febc2e;
	}
	.lights i:nth-child(3) {
		background: #28c840;
	}
	.window:not(.front) .lights i {
		background: #d6d6d6;
	}
	.title {
		flex: 1;
		text-align: center;
		margin-right: 52px;
		font-weight: 600;
		font-size: 14px;
		color: #4a4a4f;
	}
	.body {
		padding: 26px 30px;
		font-size: 26px;
		line-height: 1.5;
		letter-spacing: -0.01em;
	}
	.body p {
		margin: 0;
		min-height: 1.5em;
	}

	.word {
		position: relative;
		border-radius: 4px;
	}
	.word.fixed {
		background: rgba(0, 113, 227, 0.08);
	}
	.caret {
		display: inline-block;
		width: 2px;
		height: 1.1em;
		margin-left: 1px;
		vertical-align: -0.18em;
		background: #0071e3;
		opacity: 0;
	}
	.caret.on {
		opacity: 1;
	}

	/* The app's own fix bubble: flag, the fixed word, what it was, and how to take it back. */
	.bubble {
		position: absolute;
		left: -8px;
		top: calc(100% + 6px);
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 5px 12px;
		border-radius: 999px;
		white-space: nowrap;
		font-size: 17px;
		line-height: 1.2;
		background: rgba(250, 250, 252, 0.92);
		backdrop-filter: blur(16px);
		box-shadow:
			0 6px 18px rgba(0, 0, 0, 0.16),
			0 0 0 0.5px rgba(0, 0, 0, 0.12);
		z-index: 2;
	}
	.bubble b {
		font-weight: 600;
	}
	.bubble s {
		color: #86868b;
	}
	.bubble kbd {
		font: 600 12px/1 -apple-system, sans-serif;
		color: #aeaeb2;
	}

	.keys {
		position: absolute;
		left: 40px;
		bottom: 40px;
		display: flex;
		gap: 6px;
	}
	.keys kbd {
		min-width: 40px;
		height: 40px;
		padding: 0 8px;
		display: grid;
		place-items: center;
		border-radius: 8px;
		background: rgba(255, 255, 255, 0.9);
		box-shadow:
			0 2px 0 rgba(0, 0, 0, 0.18),
			0 0 0 0.5px rgba(0, 0, 0, 0.15);
		font: 500 19px/1 -apple-system, BlinkMacSystemFont, sans-serif;
		color: #3a3a3c;
	}

	.caption {
		position: absolute;
		left: 50%;
		bottom: 44px;
		transform: translateX(-50%);
		margin: 0;
		padding: 10px 20px;
		border-radius: 999px;
		background: rgba(29, 29, 31, 0.82);
		backdrop-filter: blur(12px);
		color: #f5f5f7;
		font-size: 20px;
		font-weight: 500;
		white-space: nowrap;
	}

</style>
