import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';

process.env.CD_HOME = await mkdtemp(`${tmpdir()}/cd-home-`);
process.env.CD_QUIET = '1';
const { serve } = await import('../src/library.js');

test('the library server only answers its own browser session', async () => {
	const { url, port, server } = await serve({ port: 0, open: false });
	const base = `http://127.0.0.1:${port}`;
	try {
		assert.equal((await fetch(`${base}/api/library`)).status, 403, 'no cookie');
		assert.equal((await fetch(`${base}/open?token=wrong`, { redirect: 'manual' })).status, 403, 'bad token');

		const opened = await fetch(url, { redirect: 'manual' });
		assert.equal(opened.status, 303);
		const cookie = opened.headers.get('set-cookie').split(';')[0];
		assert.match(opened.headers.get('set-cookie'), /HttpOnly; SameSite=Strict/);

		const ok = await fetch(`${base}/api/library`, { headers: { cookie } });
		assert.equal(ok.status, 200);
		assert.deepEqual((await ok.json()).entries, []);
		assert.match(ok.headers.get('content-security-policy'), /default-src 'none'/);

		// DNS rebinding: a page on another hostname that resolves to 127.0.0.1.
		const { request } = await import('node:http');
		const status = await new Promise((resolve) => {
			request({ host: '127.0.0.1', port, path: '/api/library', headers: { host: `evil.example:${port}`, cookie } }, (res) => resolve(res.statusCode)).end();
		});
		assert.equal(status, 421, 'wrong Host header');

		const cross = await fetch(`${base}/api/entries/0123456789abcdef`, {
			method: 'PATCH',
			headers: { cookie, origin: 'https://evil.example', 'content-type': 'application/json' },
			body: '{}',
		});
		assert.equal(cross.status, 403, 'cross-origin write');
		const plain = await fetch(`${base}/api/entries/0123456789abcdef`, { method: 'PATCH', headers: { cookie, 'content-type': 'text/plain' }, body: '{}' });
		assert.equal(plain.status, 415, 'non-JSON write');
		assert.equal((await fetch(`${base}/app.js/../../src/library.js`, { headers: { cookie } })).status, 404);
	} finally {
		server.close();
	}
});
