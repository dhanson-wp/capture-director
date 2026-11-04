// Runs the Mac recorder inside Capture Director.app and reads back what it did.
import { spawn } from 'node:child_process';
import { access, mkdir, open, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { normalizeStep } from './record.js';
import { log } from './util.js';

const APP_NAME = 'Capture Director.app';
const EXECUTABLE = path.join('Contents', 'MacOS', 'CaptureDirector');
const NEEDS_APP = 'Recording a Mac app needs the Capture Director app. Install it with: capture-director install-app';
const POLL_MS = 250;
const STALE = ['result.json', 'raw.mov', 'capture.json', 'recorder.log'];

async function isRecorderApp(app) {
	try {
		await access(path.join(app, EXECUTABLE));
		return true;
	} catch {
		return false;
	}
}

/** Find Capture Director.app: CD_APP first, then /Applications, then ~/Applications. */
export async function findRecorderApp({ env = process.env } = {}) {
	if (env.CD_APP) {
		const app = path.resolve(env.CD_APP);
		if (await isRecorderApp(app)) return app;
		throw new Error(NEEDS_APP);
	}
	for (const dir of ['/Applications', path.join(os.homedir(), 'Applications')]) {
		const app = path.join(dir, APP_NAME);
		if (await isRecorderApp(app)) return app;
	}
	throw new Error(NEEDS_APP);
}

/** The job file the recorder reads. Names differ from the shot only at this boundary. */
export function buildJob(shot, dir) {
	const job = {
		version: 1,
		id: shot.id,
		app: shot.app,
		env: shot.env ?? {},
		window: shot.window,
		background: shot.background,
		fps: shot.recordFps,
		countdown: shot.countdown,
		settle: shot.settle,
		tail: shot.tail,
		steps: (shot.actions || []).map(normalizeStep),
		out: dir,
	};
	if (shot.cursor?.start) job.cursorStart = shot.cursor.start;
	return job;
}

// LaunchServices starts the app so it gets screen recording permission under its own name.
// `open -W` returns 0 whatever the recorder's exit code, so callers read result.json instead.
function spawnOpen({ app, jobFile }) {
	return new Promise((resolve, reject) => {
		const child = spawn('open', ['-n', '-W', '-a', app, '--args', '--record', jobFile], { stdio: 'ignore' });
		child.on('error', reject);
		child.on('close', () => resolve());
	});
}

// Print recorder.log lines to stderr as they appear.
function followLog(file, id) {
	let offset = 0;
	let partial = '';
	const flush = async (final) => {
		let handle;
		try {
			handle = await open(file, 'r');
			const { size } = await handle.stat();
			if (size > offset) {
				const buf = Buffer.alloc(size - offset);
				await handle.read(buf, 0, buf.length, offset);
				offset = size;
				partial += buf.toString('utf8');
			}
		} catch {
			// The recorder hasn't made the log yet.
		} finally {
			await handle?.close();
		}
		const lines = partial.split('\n');
		partial = final ? '' : lines.pop();
		for (const line of final ? lines.concat(partial) : lines) if (line.trim()) log(`${id}: ${line}`);
	};
	let busy = Promise.resolve();
	const timer = setInterval(() => { busy = busy.then(() => flush(false)); }, POLL_MS);
	return async () => {
		clearInterval(timer);
		await busy;
		await flush(true);
	};
}

/** Record one app shot into `dir`. Resolves to the recorder's result: { status, message? }. */
export async function recordAppShot(shot, dir, { run = spawnOpen, env = process.env } = {}) {
	const app = await findRecorderApp({ env });
	await mkdir(dir, { recursive: true });
	// Clear the last take so an old result.json is never mistaken for this one's.
	for (const name of STALE) await rm(path.join(dir, name), { force: true });
	// The job file lives with the take, so a job the recorder can't read still reports in the same folder.
	const jobFile = path.join(dir, 'job.json');
	await writeFile(jobFile, JSON.stringify(buildJob(shot, dir), null, 2));

	const stop = followLog(path.join(dir, 'recorder.log'), shot.id);
	try {
		await run({ app, jobFile });
	} finally {
		await stop();
	}

	const bad = () => new Error('The recorder stopped without saying why.');
	let result;
	try {
		result = JSON.parse(await readFile(path.join(dir, 'result.json'), 'utf8'));
	} catch {
		throw bad();
	}
	if (!['ok', 'cancelled', 'error'].includes(result?.status)) throw bad();
	return result;
}
