import path from 'node:path';
import os from 'node:os';
import { execFile, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function hasSwift() {
	return new Promise((resolve) => execFile('xcrun', ['--find', 'swift'], (err) => resolve(!err)));
}

/** Build the Mac app with Command Line Tools and install it into `dir`. */
export async function installApp({ dir = path.join(os.homedir(), 'Applications'), env = process.env } = {}) {
	if (process.platform !== 'darwin') throw new Error('The Mac app only runs on macOS.');
	if (!(await hasSwift())) throw new Error('Command Line Tools are missing. Run xcode-select --install, then try again.');

	const config = {
		node: process.execPath,
		cli: path.join(repo, 'bin', 'capture-director.js'),
		path: env.PATH ?? '',
		cdHome: env.CD_HOME ? path.resolve(env.CD_HOME) : null,
	};
	const out = await new Promise((resolve, reject) => {
		const child = spawn(path.join(repo, 'mac', 'build.sh'), [], {
			env: { ...env, CD_APP_DIR: path.resolve(dir), CD_CONFIG_JSON: JSON.stringify(config) },
			stdio: ['ignore', 'pipe', 'inherit'],
		});
		let text = '';
		child.stdout.on('data', (chunk) => {
			text += chunk;
			process.stderr.write(chunk);
		});
		child.on('error', reject);
		child.on('close', (code) => (code === 0 ? resolve(text) : reject(new Error(`The Mac app build failed (exit ${code}).`))));
	});
	const match = out.match(/^installed (.+) \(signed: (.+)\)$/m);
	if (!match) throw new Error('The Mac app build finished without saying where it installed the app.');
	return { app: match[1], signed: match[2] };
}
