// Smaller copies of a capture for upload pages with size limits. Copies live in
// <home>/exports, never next to the original, and the original is never touched.

import { randomBytes } from 'node:crypto';
import { mkdir, rename, rm, stat } from 'node:fs/promises';
import path from 'node:path';
import { home, load } from './library.js';
import { ffmpeg, probe } from './util.js';

const PRESETS = {
	web: { width: 1920, crf: '26', audio: '128k' },
	small: { width: 1280, crf: '30', audio: '96k' },
};

export const exportFile = (homeDir, id, preset) => path.join(homeDir, 'exports', `${id}-${preset}.mp4`);

export async function exportEntry(id, { preset = 'web' } = {}) {
	const p = PRESETS[preset];
	if (!Object.hasOwn(PRESETS, preset)) throw new Error('Pick web or small');
	const db = await load();
	const entry = db.entries.find((x) => x.id === id);
	if (!entry) throw new Error(`No capture with id ${id}`);
	const source = await stat(entry.file).catch(() => null);
	if (!source?.isFile()) throw new Error("Couldn't find the original video");

	const dir = path.join(home(), 'exports');
	await mkdir(dir, { recursive: true, mode: 0o700 });
	const file = exportFile(home(), id, preset);

	// A copy is fresh when it's at least as new as the original.
	const made = await stat(file).catch(() => null);
	if (made && made.size > 0 && made.mtimeMs >= source.mtimeMs) return { id, preset, file, size: made.size, reused: true };

	// A name of its own, so two runs for the same copy (app and agent) never write one file.
	const tmp = `${file}.${process.pid}-${randomBytes(4).toString('hex')}.tmp.mp4`;
	const { hasAudio } = await probe(entry.file);
	const args = ['-i', entry.file, '-vf', `scale='min(${p.width},iw)':-2`, '-c:v', 'libx264', '-crf', p.crf, '-preset', 'medium', '-pix_fmt', 'yuv420p'];
	args.push(...(hasAudio ? ['-c:a', 'aac', '-b:a', p.audio] : ['-an']));
	args.push('-movflags', '+faststart', tmp);
	try {
		await ffmpeg(args);
		await rename(tmp, file);
	} catch (err) {
		await rm(tmp, { force: true });
		throw err;
	}
	return { id, preset, file, size: (await stat(file)).size, reused: false };
}
