import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readdir, stat, utimes, access } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { ffmpeg, probe } from '../src/util.js';

process.env.CD_QUIET = '1';
const { add, forget, relocate } = await import('../src/library.js');
const { exportEntry, exportFile } = await import('../src/export.js');
const run = promisify(execFile);
const CLI = path.join(import.meta.dirname, '..', 'bin', 'capture-director.js');

async function fresh() {
	const dir = await mkdtemp(`${tmpdir()}/cd-export-`);
	process.env.CD_HOME = path.join(dir, 'home');
	return dir;
}

// A short 1080p source at a very high bitrate, with audio, so a web copy has plenty to shed.
async function bigVideo(dir) {
	const file = path.join(dir, 'big.mp4');
	await ffmpeg(['-f', 'lavfi', '-i', 'testsrc2=size=1920x1080:rate=30', '-f', 'lavfi', '-i', 'sine=frequency=440', '-t', '3', '-vf', 'noise=alls=4:allf=t',
		'-c:v', 'libx264', '-b:v', '20M', '-minrate', '20M', '-maxrate', '20M', '-bufsize', '40M', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', file]);
	return file;
}

test('web copy is smaller and plays', async () => {
	const dir = await fresh();
	const video = await bigVideo(dir);
	const entry = await add(video);
	const out = await exportEntry(entry.id);
	assert.equal(out.file, path.join(process.env.CD_HOME, 'exports', `${entry.id}-web.mp4`));
	assert.equal(out.preset, 'web');
	assert.ok(out.size < (await stat(video)).size);
	assert.equal(out.size, (await stat(out.file)).size);
	const info = await probe(out.file);
	assert.ok(info.width <= 1920);
	assert.ok(info.hasAudio);
	assert.equal(out.reused, false);
});

test('small copy is at most 720p wide', async () => {
	const dir = await fresh();
	const entry = await add(await bigVideo(dir));
	const out = await exportEntry(entry.id, { preset: 'small' });
	assert.ok((await probe(out.file)).width <= 1280);
});

test('a fresh copy is reused', async () => {
	const dir = await fresh();
	const video = await bigVideo(dir);
	const entry = await add(video);
	assert.equal((await exportEntry(entry.id)).reused, false);
	assert.equal((await exportEntry(entry.id)).reused, true);
	const later = new Date(Date.now() + 60_000);
	await utimes(video, later, later);
	assert.equal((await exportEntry(entry.id)).reused, false);
});

test('unknown id, bad preset, and a missing original fail plainly', async () => {
	const dir = await fresh();
	await assert.rejects(exportEntry('nope'), /No capture with id nope/);
	const { makeVideo } = await import('./helpers.js');
	const video = await makeVideo(dir);
	const entry = await add(video);
	await assert.rejects(exportEntry(entry.id, { preset: 'huge' }), /Pick web or small/);
	const { rm } = await import('node:fs/promises');
	await rm(video);
	await assert.rejects(exportEntry(entry.id), /Couldn't find the original video/);
});

test('forget clears exports', async () => {
	const dir = await fresh();
	const video = await bigVideo(dir);
	const entry = await add(video);
	const out = await exportEntry(entry.id);
	await forget([entry.id]);
	await assert.rejects(access(out.file));
	assert.ok((await stat(video)).isFile());
});

test('the CLI prints JSON', async () => {
	const dir = await fresh();
	const entry = await add(await bigVideo(dir));
	const { stdout } = await run('node', [CLI, 'library', 'export', entry.id, '--preset', 'small'], { env: process.env });
	const json = JSON.parse(stdout);
	assert.equal(json.preset, 'small');
	assert.equal(json.file, exportFile(process.env.CD_HOME, entry.id, 'small'));
	await assert.rejects(run('node', [CLI, 'library', 'export', entry.id, '--preset', 'huge'], { env: process.env }), /Pick web or small/);
});

test('two exports at once both finish with one playable file and no temp files', async () => {
	const dir = await fresh();
	const entry = await add(await bigVideo(dir));
	const [a, b] = await Promise.all([exportEntry(entry.id), exportEntry(entry.id)]);
	assert.equal(a.file, b.file);
	const info = await probe(a.file);
	assert.ok(info.width <= 1920 && info.duration > 2);
	assert.deepEqual(await readdir(path.dirname(a.file)), [path.basename(a.file)]);
});

test('relocate clears exports', async () => {
	const dir = await fresh();
	const entry = await add(await bigVideo(dir));
	const out = await exportEntry(entry.id);
	const { makeVideo } = await import('./helpers.js');
	const moved = await makeVideo(dir, 'moved.mp4');
	await relocate(entry.id, moved);
	await assert.rejects(access(out.file));
});
