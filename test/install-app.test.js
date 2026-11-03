import { test } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { access, mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { installApp } from '../src/install-app.js';

function hasSwiftToolchain() {
	if (process.platform !== 'darwin') return false;
	try {
		execFileSync('xcrun', ['--find', 'swift'], { stdio: 'ignore' });
		return true;
	} catch {
		return false;
	}
}

test('install-app builds a signed app with the paths it needs', { timeout: 600_000, skip: !hasSwiftToolchain() }, async () => {
	const dir = await mkdtemp(`${tmpdir()}/cd-app-`);
	try {
		const { app } = await installApp({ dir, env: { ...process.env, CD_HOME: '/tmp/cd-home-x' } });
		assert.equal(app, path.join(dir, 'Capture Director.app'));
		const config = JSON.parse(await readFile(path.join(app, 'Contents/Resources/config.json'), 'utf8'));
		assert.equal(config.node, process.execPath);
		assert.equal(config.cli, path.resolve('bin/capture-director.js'));
		assert.equal(config.cdHome, '/tmp/cd-home-x');
		assert.ok(config.path.includes('/usr/bin'));
		await access(path.join(app, 'Contents/Resources/AppIcon.icns'));
		execFileSync('codesign', ['--verify', app]); // throws if unsigned
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});
