import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { makeVideo } from './helpers.js';

process.env.CD_QUIET = '1';
const { add, idFor, load, normalizeFolder } = await import('../src/library.js');

// Each test gets its own library folder; the module reads CD_HOME on every call.
async function fresh() {
	const dir = await mkdtemp(`${tmpdir()}/cd-data-`);
	process.env.CD_HOME = path.join(dir, 'home');
	return dir;
}
const dbPath = () => path.join(process.env.CD_HOME, 'library.json');

test('normalizeFolder tidies paths', () => {
	assert.equal(normalizeFolder(' a / /b '), 'a/b');
	assert.equal(normalizeFolder('Unsorted'), '');
	assert.equal(normalizeFolder('a/'), 'a');
	assert.equal(normalizeFolder('🎬 Demos'), '🎬 Demos');
	assert.throws(() => normalizeFolder('x'.repeat(301)), /Folder names can be at most 300 characters/);
});

test('old library.json loads unchanged', async () => {
	await fresh();
	const { mkdir } = await import('node:fs/promises');
	await mkdir(process.env.CD_HOME, { recursive: true });
	const oldEntry = { id: '0123456789abcdef', file: '/x/y.mp4', title: 'y', project: 'x', kind: 'video', starred: false, notes: '', added: '2026-01-01T00:00:00.000Z' };
	const raw = JSON.stringify({ entries: [oldEntry] }, null, 2);
	await writeFile(dbPath(), raw);
	assert.deepEqual(await load(), { entries: [oldEntry], folders: [], renames: {} });
	assert.equal(await readFile(dbPath(), 'utf8'), raw);
});

test('folders fill in on first save', async () => {
	const dir = await fresh();
	const video = await makeVideo(dir);
	await add(video, { project: 'blog/Post formats' });
	const saved = JSON.parse(await readFile(dbPath(), 'utf8'));
	assert.deepEqual(saved.folders, ['blog', 'blog/Post formats']);
});

test('add records size and url', async () => {
	const dir = await fresh();
	const video = await makeVideo(dir);
	const entry = await add(video, { url: 'https://example.com/' });
	assert.equal(entry.size, (await stat(video)).size);
	assert.equal(entry.url, 'https://example.com/');
});

test('renames send a new entry to the renamed folder', async () => {
	const dir = await fresh();
	const video = await makeVideo(dir);
	const { mkdir } = await import('node:fs/promises');
	await mkdir(process.env.CD_HOME, { recursive: true });
	await writeFile(dbPath(), JSON.stringify({ entries: [], renames: { blog: 'Website' } }));
	const entry = await add(video, { project: 'blog/Post formats' });
	assert.equal(entry.project, 'Website/Post formats');
	// Re-adding an existing entry keeps whatever project it has.
	const again = await add(video, { project: 'blog/Other' });
	assert.equal(again.project, 'Website/Post formats');
});

test('id collision gets a fresh id', async () => {
	const dir = await fresh();
	const video = await makeVideo(dir);
	const { mkdir } = await import('node:fs/promises');
	await mkdir(process.env.CD_HOME, { recursive: true });
	const clash = idFor(path.resolve(video));
	await writeFile(dbPath(), JSON.stringify({ entries: [{ id: clash, file: '/elsewhere.mp4', title: 'e', project: 'p', kind: 'video' }] }));
	const entry = await add(video);
	assert.match(entry.id, /^[0-9a-f]{16}$/);
	assert.notEqual(entry.id, clash);
});
