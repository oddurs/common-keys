<script lang="ts">
	import { asset } from '$app/paths';

	const repo = 'https://github.com/oddurs/langsmart';

	const accuracy = [
		['U.S. + Icelandic', '0 of 300', '97% (most words read the same on both)'],
		['U.S. + Russian', '0 of 300', '98% · 100%'],
		['U.S. + Korean 2-Set', '0 of 300', '100% · 100%'],
		['U.S. + Greek', '0 of 300', '99% · 97%'],
		['U.S. + Hebrew', '0 of 300', '93% · 97%'],
		['U.S. + Arabic', '0 of 300', '88% · 98%'],
		['U.S. + French', '0 of 300', '100% · 92%'],
		['U.S. + German', '0 of 300', '97% · 82%']
	];
</script>

<svelte:head>
	<title>LangSmart — fixes words typed on the wrong keyboard</title>
	<meta
		name="description"
		content="A native macOS menu bar app that fixes words typed on the wrong keyboard layout, for every keyboard macOS has. It learns how you type, and nothing leaves your Mac."
	/>
	<meta name="color-scheme" content="light dark" />
</svelte:head>

<main>
	<header>
		<img src={asset('icon.svg')} alt="" width="96" height="96" />
		<h1>LangSmart</h1>
		<p class="lede">Typed it on the wrong keyboard? It's already fixed.</p>
		<div class="actions">
			<a class="button" href="{repo}/releases/latest">Download for Mac</a>
			<a class="link" href={repo}>View on GitHub ›</a>
		</div>
		<p class="fine">Free and open source · macOS 14.4 or later · Every keyboard macOS has</p>
	</header>

	<figure class="video">
		<video
			src={asset('demo.mp4')}
			poster={asset('poster.jpg')}
			autoplay
			muted
			loop
			playsinline
			width="1280"
			height="800"
			aria-label="Typing þetta on the U.S. layout: LangSmart fixes it and switches to Icelandic. Then привет and 안녕하세요 typed on U.S. are fixed the same way, and each app keeps its own keyboard."
		></video>
	</figure>

	<section class="features">
		<div>
			<h2>Every keyboard.</h2>
			<p>
				All 251 layouts in macOS, across 35 scripts, read with the system's own key tables. Korean and
				Vietnamese input compose both ways; Japanese and Chinese get the keys you meant.
			</p>
		</div>
		<div>
			<h2>Learns you.</h2>
			<p>
				Erase a word and type it again on another layout, and it remembers the word and the keys you mix
				up. Press <kbd>⌘Z</kbd> after a fix and it leaves that word alone from then on.
			</p>
		</div>
		<div>
			<h2>Knows your apps.</h2>
			<p>
				Switch apps and you get the layout you last used there, or the one you usually write in. A switch
				in one app never leaks into the next.
			</p>
		</div>
		<div>
			<h2>Careful.</h2>
			<p>
				It changes a word only when the evidence is clear: dictionaries, spelling rules no word breaks, and
				what you've taught it. Paths, links and passwords are left alone.
			</p>
		</div>
		<div>
			<h2>Private.</h2>
			<p>
				Every keystroke stays on your Mac. No network, no telemetry, no account. What it learns is one file
				you can read or delete.
			</p>
		</div>
		<div>
			<h2>Native.</h2>
			<p>
				A flag in the menu bar and a real menu under it. Settings look like System Settings. Judging a word
				takes about 0.13 ms.
			</p>
		</div>
	</section>

	<section class="numbers">
		<h2>Measured, not promised.</h2>
		<p class="intro">
			<code>worldkey eval</code> types 150 dictionary words per language on the right keyboard and on the
			wrong one, and counts what happens.
		</p>
		<table>
			<thead>
				<tr><th>Keyboards</th><th>Correct words changed</th><th>Wrong-keyboard words fixed</th></tr>
			</thead>
			<tbody>
				{#each accuracy as [keyboards, changed, fixed] (keyboards)}
					<tr><td>{keyboards}</td><td>{changed}</td><td>{fixed}</td></tr>
				{/each}
			</tbody>
		</table>
		<p class="note">
			Most misses are short words that are real in both languages, like <em>an</em> and <em>αν</em>, where
			leaving them alone is right.
		</p>
	</section>

	<section class="engine">
		<div>
			<h2>WorldKey inside.</h2>
			<p>
				The engine that reads keys on any keyboard is a Swift library and a command-line tool, so scripts
				and other input tools can use it too.
			</p>
		</div>
		<pre><code
				><span class="prompt">$</span> worldkey convert ghbdtn --from US --to Russian
привет
<span class="prompt">$</span> worldkey detect /etta --from US
þetta	com.apple.keylayout.Icelandic
<span class="prompt">$</span> worldkey convert 안녕하세요 --from 2SetKorean --to US
dkssudgktpdy</code
			></pre>
	</section>

	<footer>
		<span>© 2026 Oddur Sigurdsson · MIT License</span>
		<a href={repo}>github.com/oddurs/langsmart</a>
	</footer>
</main>

<style>
	:global(:root) {
		--bg: #fbfbfd;
		--text: #1d1d1f;
		--secondary: #6e6e73;
		--accent: #0071e3;
		--rule: rgba(0, 0, 0, 0.08);
		--panel: #f2f2f5;
	}
	@media (prefers-color-scheme: dark) {
		:global(:root) {
			--bg: #000;
			--text: #f5f5f7;
			--secondary: #86868b;
			--accent: #2997ff;
			--rule: rgba(255, 255, 255, 0.12);
			--panel: #1c1c1e;
		}
	}
	:global(*) {
		box-sizing: border-box;
	}
	:global(body) {
		margin: 0;
		background: var(--bg);
		color: var(--text);
		font:
			17px/1.47 -apple-system,
			BlinkMacSystemFont,
			'SF Pro Text',
			'Helvetica Neue',
			sans-serif;
		letter-spacing: -0.022em;
		-webkit-font-smoothing: antialiased;
	}
	a {
		color: var(--accent);
		text-decoration: none;
	}
	a:hover {
		text-decoration: underline;
	}
	main {
		max-width: 980px;
		margin: 0 auto;
		padding: 72px 22px 40px;
	}

	header {
		text-align: center;
	}
	h1 {
		margin: 12px 0 0;
		font:
			600 56px/1.07 -apple-system,
			BlinkMacSystemFont,
			'SF Pro Display',
			sans-serif;
		letter-spacing: -0.005em;
	}
	.lede {
		margin: 10px auto 0;
		max-width: 560px;
		font-size: 24px;
		line-height: 1.33;
		color: var(--secondary);
	}
	.actions {
		margin-top: 26px;
		display: flex;
		gap: 14px;
		justify-content: center;
		flex-wrap: wrap;
	}
	.button {
		display: inline-block;
		padding: 11px 22px;
		border-radius: 980px;
		background: var(--accent);
		color: #fff;
	}
	.button:hover {
		text-decoration: none;
		filter: brightness(1.08);
	}
	.link {
		padding: 11px 6px;
	}
	.fine {
		margin-top: 14px;
		font-size: 14px;
		color: var(--secondary);
	}

	.video {
		margin: 56px auto 0;
		max-width: 980px;
		border-radius: 18px;
		overflow: hidden;
		box-shadow: 0 20px 60px rgba(0, 0, 0, 0.18);
		aspect-ratio: 16 / 10;
		background: #e4e4ea;
	}
	.video video {
		display: block;
		width: 100%;
		height: 100%;
	}

	.features {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 40px;
		margin-top: 72px;
		padding-top: 40px;
		border-top: 1px solid var(--rule);
	}
	h2 {
		margin: 0 0 6px;
		font-size: 21px;
		font-weight: 600;
		letter-spacing: 0.011em;
	}
	.features p,
	.engine p,
	.intro,
	.note {
		margin: 0;
		font-size: 15px;
		color: var(--secondary);
	}
	kbd,
	code {
		font:
			13px ui-monospace,
			'SF Mono',
			monospace;
	}

	.numbers {
		margin-top: 72px;
		padding-top: 40px;
		border-top: 1px solid var(--rule);
	}
	table {
		width: 100%;
		margin: 20px 0 12px;
		border-collapse: collapse;
		font-size: 15px;
	}
	th {
		text-align: left;
		font-weight: 600;
		color: var(--secondary);
		font-size: 13px;
	}
	th,
	td {
		padding: 9px 12px 9px 0;
		border-bottom: 1px solid var(--rule);
	}
	td:first-child {
		font-weight: 500;
	}

	.engine {
		display: grid;
		grid-template-columns: 1fr 1.4fr;
		gap: 40px;
		align-items: center;
		margin-top: 72px;
		padding-top: 40px;
		border-top: 1px solid var(--rule);
	}
	pre {
		margin: 0;
		padding: 20px 22px;
		border-radius: 14px;
		background: var(--panel);
		overflow-x: auto;
		font-size: 14px;
		line-height: 1.6;
	}
	pre code {
		font-size: 14px;
	}
	.prompt {
		color: var(--secondary);
		user-select: none;
	}

	footer {
		margin-top: 72px;
		padding-top: 18px;
		border-top: 1px solid var(--rule);
		font-size: 12px;
		color: var(--secondary);
		display: flex;
		justify-content: space-between;
		gap: 12px;
	}

	@media (max-width: 760px) {
		main {
			padding: 48px 16px 32px;
		}
		h1 {
			font-size: 40px;
		}
		.lede {
			font-size: 19px;
		}
		.video {
			margin-top: 40px;
			border-radius: 12px;
		}
		.features,
		.engine {
			grid-template-columns: 1fr;
			gap: 28px;
		}
		table {
			font-size: 13px;
		}
		td:last-child {
			font-size: 12px;
		}
		footer {
			flex-direction: column;
		}
	}
</style>
