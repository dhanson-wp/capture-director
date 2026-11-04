import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { access, mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { buildJob, findRecorderApp, recordAppShot, tidyLine } from '../src/native.js';
import { loadShots, record, stoppedLine } from '../src/shots.js';

const BUNDLE = 'io.github.dhanson-wp.capture-director';

// A pretend Capture Director.app, so nothing real is ever launched.
async function fakeApp() {
	const app = path.join(await mkdtemp(`${tmpdir()}/cd-native-`), 'Capture Director.app');
	await mkdir(path.join(app, 'Contents', 'MacOS'), { recursive: true });
	await writeFile(path.join(app, 'Contents', 'MacOS', 'CaptureDirector'), '');
	return app;
}

async function project(extra = '') {
	const dir = await mkdtemp(`${tmpdir()}/cd-native-shots-`);
	const file = path.join(dir, 'shots.yml');
	await writeFile(file, `shots:\n  - id: tour\n    app: ${BUNDLE}\n    env:\n      CD_DEMO: "1"\n    background: "#112233"\n${extra}    actions:\n      - click: Play\n      - 500\n      - press: cmd+o\n`);
	return { dir, file, out: path.join(dir, 'out', 'tour') };
}

// A fake launcher: writes recorder.log and result.json, the way the real recorder would.
const fakeRun = (result, { log } = {}) => async ({ jobFile }) => {
	const dir = path.dirname(jobFile);
	if (log) await writeFile(path.join(dir, 'recorder.log'), log);
	if (result) await writeFile(path.join(dir, 'result.json'), JSON.stringify(result));
};

test('buildJob carries the shot', async () => {
	const { file } = await project();
	const [shot] = (await loadShots(file)).shots;
	const job = buildJob(shot, '/out/tour');
	assert.equal(job.version, 1);
	assert.equal(job.id, 'tour');
	assert.deepEqual(job.app, { bundleId: BUNDLE });
	assert.deepEqual(job.env, { CD_DEMO: '1' });
	assert.equal(job.background, '#112233');
	assert.deepEqual(job.window, { width: 1440, height: 900 });
	assert.equal(job.fps, 60);
	assert.equal(job.settle, 400);
	assert.equal(job.tail, 800);
	assert.equal(job.out, '/out/tour');
	assert.deepEqual(job.steps.map((s) => s.kind), ['click', 'wait', 'press']);
	assert.equal(job.steps[0].target, 'Play');
	assert.equal(job.steps[2].key, 'cmd+o');
	assert.equal('cursorStart' in job, false);
});

test('buildJob uses the keys the Swift decoder reads', async () => {
	const swift = await readFile(new URL('../mac/Sources/CaptureDirectorKit/RecordJob.swift', import.meta.url), 'utf8');
	const keys = swift.match(/enum CodingKeys: String, CodingKey \{\s*case ([^}]+)\}/)[1].split(',').map((k) => k.trim());
	const { file } = await project('    cursor:\n      start: [100, 200]\n');
	const [shot] = (await loadShots(file)).shots;
	assert.deepEqual(Object.keys(buildJob(shot, '/out')).sort(), [...keys].sort());
});

test('findRecorderApp prefers CD_APP', async () => {
	const app = await fakeApp();
	assert.equal(await findRecorderApp({ env: { CD_APP: app } }), app);
});

test('a bad CD_APP fails with the install message', async () => {
	await assert.rejects(findRecorderApp({ env: { CD_APP: '/nowhere/Capture Director.app' } }), /Install it with: capture-director install-app/);
});

test('recordAppShot clears the last take and reads result.json', async () => {
	const { file, out } = await project();
	const [shot] = (await loadShots(file)).shots;
	await mkdir(out, { recursive: true });
	await writeFile(path.join(out, 'result.json'), '{"status":"error","message":"old"}');
	await writeFile(path.join(out, 'job.json.cancel'), 'old cancellation');
	const env = { CD_APP: await fakeApp() };
	const run = async (args) => {
		await assert.rejects(access(`${args.jobFile}.cancel`));
		await fakeRun({ status: 'ok' }, { log: 'ready\n' })(args);
	};
	const result = await recordAppShot(shot, out, { env, run });
	assert.deepEqual(result, { status: 'ok' });
	assert.equal(JSON.parse(await readFile(path.join(out, 'job.json'), 'utf8')).out, out);
});

test('a missing result.json fails plainly', async () => {
	const { file, out } = await project();
	const [shot] = (await loadShots(file)).shots;
	await mkdir(out, { recursive: true });
	await writeFile(path.join(out, 'result.json'), '{"status":"ok"}');
	await assert.rejects(recordAppShot(shot, out, { env: { CD_APP: await fakeApp() }, run: fakeRun(null) }), /The recorder stopped without saying why\./);
});

test('a cancelled take is reported, not processed', async () => {
	const { file, out } = await project();
	const results = await record(file, { platform: 'darwin', env: { CD_APP: await fakeApp() }, run: fakeRun({ status: 'cancelled' }) });
	assert.deepEqual(results, [{ id: 'tour', cancelled: true }]);
	await assert.rejects(access(path.join(out, 'tour.mp4')));
	assert.equal(stoppedLine(results), 'The run stopped at tour. The take was cancelled.');
});

test('a cancelled take stops the run before the next shot', async () => {
	const dir = await mkdtemp(`${tmpdir()}/cd-native-shots-`);
	const file = path.join(dir, 'shots.yml');
	await writeFile(file, `shots:\n  - id: one\n    app: ${BUNDLE}\n    actions: [500]\n  - id: two\n    app: ${BUNDLE}\n    actions: [500]\n`);
	const launched = [];
	const run = async (args) => {
		launched.push(path.basename(path.dirname(args.jobFile)));
		await fakeRun({ status: 'cancelled', message: 'You pressed Escape, so the take stopped.' })(args);
	};
	const results = await record(file, { platform: 'darwin', env: { CD_APP: await fakeApp() }, run });
	assert.deepEqual(launched, ['one']);
	assert.deepEqual(results, [{ id: 'one', cancelled: true, message: 'You pressed Escape, so the take stopped.' }]);
	assert.equal(stoppedLine(results), 'The run stopped at one. You pressed Escape, so the take stopped.');
	assert.equal(stoppedLine([{ id: 'one', file: 'x.mp4' }]), null);
});

test('a recorder error becomes the command error', async () => {
	const { file } = await project();
	await assert.rejects(record(file, { platform: 'darwin', env: { CD_APP: await fakeApp() }, run: fakeRun({ status: 'error', message: 'The app never opened a window.' }) }), /^Error: tour: The app never opened a window\.$/);
});

test('app shots only record on macOS', async () => {
	const { file } = await project();
	let launched = false;
	await assert.rejects(record(file, { platform: 'linux', env: { CD_APP: await fakeApp() }, run: async () => { launched = true; } }), /^Error: Recording Mac apps only works on macOS\.$/);
	assert.equal(launched, false);
});

test('recorder log lines carry the shot id once', () => {
	assert.equal(tidyLine('[capture-director] tour: opening Notes', 'tour'), 'tour: opening Notes');
	assert.equal(tidyLine('plain line', 'tour'), 'tour: plain line');
});

// Exercise actual OS signals and spawnOpen, with a harmless stand-in for
// LaunchServices. Its recorder runs in a separate process group, just like the app.
for (const signal of ['SIGINT', 'SIGTERM']) {
	test(`${signal} stops the independent recorder and waits for cleanup`, { skip: process.platform === 'win32', timeout: 15000 }, async () => {
		const { file, out } = await project();
		const app = await fakeApp();
		const bin = await mkdtemp(`${tmpdir()}/cd-fake-open-`);
		const worker = `
			const fs = require('node:fs');
			const path = require('node:path');
			const jobFile = process.argv[1];
			const dir = path.dirname(jobFile);
			fs.writeFileSync(path.join(dir, 'worker-ready'), String(process.pid));
			const poll = setInterval(() => {
				if (!fs.existsSync(jobFile + '.cancel')) return;
				clearInterval(poll);
				fs.writeFileSync(path.join(dir, 'cancellation-seen'), 'yes');
				setTimeout(() => {
					fs.writeFileSync(path.join(dir, 'cleaned-up'), 'yes');
					fs.writeFileSync(path.join(dir, 'result.json'), JSON.stringify({status: 'cancelled'}));
				}, 250);
			}, 10);
			setTimeout(() => process.exit(3), 10000).unref();
		`;
		await writeFile(path.join(bin, 'open'), `#!${process.execPath}
			const {spawn} = require('node:child_process');
			const child = spawn(process.execPath, ['-e', ${JSON.stringify(worker)}, process.argv.at(-1)], {detached: true, stdio: 'ignore'});
			child.on('exit', (code) => process.exit(code ?? 1));
		`, { mode: 0o755 });
		const script = `
			import {loadShots} from ${JSON.stringify(new URL('../src/shots.js', import.meta.url).href)};
			import {recordAppShot} from ${JSON.stringify(new URL('../src/native.js', import.meta.url).href)};
			const [shot] = (await loadShots(${JSON.stringify(file)})).shots;
			const result = await recordAppShot(shot, ${JSON.stringify(out)});
			console.log(JSON.stringify(result));
			process.exitCode = result.status === 'cancelled' ? 2 : 1;
		`;
		const child = spawn(process.execPath, ['--input-type=module', '-e', script], {
			detached: true, env: { ...process.env, CD_APP: app, PATH: `${bin}${path.delimiter}${process.env.PATH}` },
			stdio: ['ignore', 'pipe', 'pipe'],
		});
		let stdout = '', stderr = '';
		child.stdout.on('data', (chunk) => { stdout += chunk; });
		child.stderr.on('data', (chunk) => { stderr += chunk; });
		const exited = new Promise((resolve, reject) => {
			child.on('error', reject);
			child.on('exit', (code, signal) => resolve({ code, signal }));
		});
		async function waitFor(name) {
			const deadline = Date.now() + 5000;
			while (Date.now() < deadline) {
				try { return await readFile(path.join(out, name), 'utf8'); } catch {}
				assert.equal(child.exitCode, null, stderr);
				await new Promise((resolve) => setTimeout(resolve, 10));
			}
			assert.fail(`Timed out waiting for ${name}: ${stderr}`);
		}
		let workerPid;
		try {
			workerPid = Number(await waitFor('worker-ready'));
			// Signal the whole CLI process group, as a terminal does for Ctrl-C.
			process.kill(-child.pid, signal);
			await waitFor('cancellation-seen');
			assert.equal(child.exitCode, null, 'the CLI must wait for recorder cleanup');
			process.kill(child.pid, signal); // repeated interrupts must also wait
			assert.deepEqual(await exited, { code: 2, signal: null });
			assert.equal(await readFile(path.join(out, 'cleaned-up'), 'utf8'), 'yes');
			assert.deepEqual(JSON.parse(stdout), { status: 'cancelled' });
		} finally {
			if (child.exitCode === null) child.kill('SIGKILL');
			if (workerPid) { try { process.kill(workerPid, 'SIGKILL'); } catch {} }
		}
	});
}
