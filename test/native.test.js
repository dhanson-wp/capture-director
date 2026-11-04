import { test } from 'node:test';
import assert from 'node:assert/strict';
import { access, mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { buildJob, findRecorderApp, recordAppShot } from '../src/native.js';
import { loadShots, record } from '../src/shots.js';

const BUNDLE = 'io.github.dhanson-wp.capture-director';
const mac = process.platform === 'darwin';

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
	const env = { CD_APP: await fakeApp() };
	const result = await recordAppShot(shot, out, { env, run: fakeRun({ status: 'ok' }, { log: 'ready\n' }) });
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

test('a cancelled take is reported, not processed', { skip: !mac }, async () => {
	const { file, out } = await project();
	const results = await record(file, { env: { CD_APP: await fakeApp() }, run: fakeRun({ status: 'cancelled' }) });
	assert.deepEqual(results, [{ id: 'tour', cancelled: true }]);
	await assert.rejects(access(path.join(out, 'tour.mp4')));
});

test('a recorder error becomes the command error', { skip: !mac }, async () => {
	const { file } = await project();
	await assert.rejects(record(file, { env: { CD_APP: await fakeApp() }, run: fakeRun({ status: 'error', message: 'The app never opened a window.' }) }), /The app never opened a window\./);
});
