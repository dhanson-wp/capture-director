import { spawn } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import YAML from 'yaml';

export const FFMPEG = process.env.FFMPEG || 'ffmpeg';
export const FFPROBE = process.env.FFPROBE || 'ffprobe';

export function log(...args) {
	if (!process.env.CD_QUIET) console.error('[capture-director]', ...args);
}

// Run a command, collect stderr, and throw with its tail on failure.
export function run(cmd, args, { quiet = true } = {}) {
	return new Promise((resolve, reject) => {
		const child = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] });
		let out = '';
		let err = '';
		child.stdout.on('data', (d) => (out += d));
		child.stderr.on('data', (d) => {
			err += d;
			if (!quiet) process.stderr.write(d);
		});
		child.on('error', reject);
		child.on('close', (code) => {
			if (code === 0) resolve(out);
			else reject(new Error(`${cmd} exited ${code}\n${err.split('\n').slice(-25).join('\n')}`));
		});
	});
}

export function ffmpeg(args) {
	return run(FFMPEG, ['-hide_banner', '-loglevel', 'error', '-y', ...args]);
}

export async function probe(file) {
	const out = await run(FFPROBE, ['-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', file]);
	const json = JSON.parse(out);
	const v = json.streams.find((s) => s.codec_type === 'video');
	return {
		duration: Number(json.format.duration || v?.duration || 0),
		width: v?.width,
		height: v?.height,
		hasAudio: json.streams.some((s) => s.codec_type === 'audio'),
	};
}

export async function loadYaml(file) {
	const text = await readFile(file, 'utf8');
	return YAML.parse(text) || {};
}

export function resolveFrom(baseFile, p) {
	if (!p) return p;
	if (/^https?:\/\//.test(p)) return p;
	if (p.startsWith('~/')) p = path.join(process.env.HOME, p.slice(2));
	return path.resolve(path.dirname(baseFile), p);
}

export function parseSize(s, fallback = [1920, 1080]) {
	if (!s) return fallback;
	if (Array.isArray(s)) return s.map(Number);
	const m = String(s).match(/^(\d+)\s*[x×]\s*(\d+)$/);
	if (!m) throw new Error(`Bad size "${s}", expected WIDTHxHEIGHT`);
	return [Number(m[1]), Number(m[2])];
}

// Deep merge for config defaults. Arrays and scalars replace.
export function merge(base, over) {
	if (over === undefined) return base;
	if (typeof base !== 'object' || base === null || Array.isArray(base)) return over;
	if (typeof over !== 'object' || over === null || Array.isArray(over)) return over;
	const out = { ...base };
	for (const [k, v] of Object.entries(over)) out[k] = merge(base[k], v);
	return out;
}

// easeInOutCubic, shared by the recorder (real mouse moves) and the
// ffmpeg expressions (zoom and cursor), so post-production matches capture.
export function ease(p) {
	p = Math.min(1, Math.max(0, p));
	return p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2;
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function num(n) {
	// Compact, locale-free number formatting for ffmpeg expressions.
	return Number(n.toFixed(4)).toString();
}
