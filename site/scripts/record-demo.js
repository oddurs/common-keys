// Records the demo scene into static/demo.mp4 and static/poster.jpg.
//
// The scene is a pure function of time, so this steps it frame by frame in headless Chrome and
// hands the stills to ffmpeg: every frame lands, at retina sharpness, the same every run.
// Needs Google Chrome and ffmpeg installed, and `pnpm dev` running (or pass the URL).

import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium } from 'playwright-core';

const url = process.argv[2] ?? 'http://localhost:5173/demo?record';
const fps = 30;
const out = new URL('../static/', import.meta.url).pathname;

function run(command, args) {
	return new Promise((resolve, reject) => {
		const child = spawn(command, args, { stdio: ['ignore', 'ignore', 'inherit'] });
		child.on('error', reject);
		child.on('exit', (code) => (code === 0 ? resolve() : reject(new Error(`${command} exited ${code}`))));
	});
}

const frames = await mkdtemp(join(tmpdir(), 'langsmart-demo-'));
const browser = await chromium.launch({ channel: 'chrome' });
try {
	const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 2 });
	console.log(`==> opening ${url}`);
	await page.goto(url, { waitUntil: 'networkidle' });
	await page.waitForFunction(() => 'window' in globalThis && '__seek' in window);
	const duration = await page.evaluate(() => window.__duration);
	const stage = page.locator('#stage');
	const count = Math.ceil((duration / 1000) * fps);

	console.log(`==> rendering ${count} frames (${(duration / 1000).toFixed(1)} s at ${fps} fps)`);
	for (let index = 0; index < count; index++) {
		await page.evaluate((t) => window.__seek(t), (index * 1000) / fps);
		// Two animation frames: one for Svelte to update the DOM, one for it to paint.
		await page.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))));
		await stage.screenshot({ path: join(frames, `${String(index).padStart(5, '0')}.png`) });
		if (index % 150 === 0) console.log(`    ${index}/${count}`);
	}

	const poster = await page.evaluate(() => window.__poster);
	await page.evaluate((t) => window.__seek(t), poster);
	await page.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))));
	await stage.screenshot({ path: join(out, 'poster.jpg'), type: 'jpeg', quality: 88 });

	console.log('==> encoding static/demo.mp4');
	await run('ffmpeg', [
		'-y', '-loglevel', 'error', '-framerate', String(fps), '-i', join(frames, '%05d.png'),
		// 1920 wide stays sharp on a retina screen at a fraction of the full capture's bytes.
		'-vf', 'scale=1920:1200:flags=lanczos', '-c:v', 'libx264', '-preset', 'slow', '-crf', '22',
		'-pix_fmt', 'yuv420p', '-movflags', '+faststart', join(out, 'demo.mp4')
	]);
	console.log('==> done');
} finally {
	await browser.close();
	await rm(frames, { recursive: true, force: true });
}
