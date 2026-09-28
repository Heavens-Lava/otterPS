// security.test.mjs - the Studio server only answers Studio (checklist §29).
//
// Each test plays an attacker the server must refuse: another web page
// (cross-site Origin), a DNS-rebinding page (foreign Host header), another
// computer on the network (non-loopback address), an oversized body, and
// path traversal against the static file server and the file API.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(studioRoot, '..');
const { checkRequest } = await import(pathToFileURL(path.join(studioRoot, 'server', 'security.mjs')).href);

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`  ✓ ${name}`);
}

console.log('Request guard (unit):');

await test('Studio\'s own page is allowed', () => {
  assert.equal(checkRequest({ host: 'localhost:4200', origin: 'http://localhost:4200' }, 4200), null);
  assert.equal(checkRequest({ host: '127.0.0.1:4200' }, 4200), null);
  assert.equal(checkRequest({ host: '[::1]:4200', origin: 'http://[::1]:4200' }, 4200), null);
});

await test('other web pages, other ports and rebinding hosts are refused', () => {
  assert.equal(checkRequest({ host: 'localhost:4200', origin: 'https://evil.example' }, 4200).status, 403);
  assert.equal(checkRequest({ host: 'localhost:4200', origin: 'http://localhost:9999' }, 4200).status, 403);
  assert.equal(checkRequest({ host: 'localhost:4200', origin: 'null' }, 4200).status, 403);
  assert.equal(checkRequest({ host: 'evil.example:4200' }, 4200).status, 421);
  assert.equal(checkRequest({ host: 'localhost:4201' }, 4200).status, 421);
  assert.equal(checkRequest({}, 4200).status, 421);
});

console.log('\nLive server:');

const port = 5900 + (process.pid % 500);
const server = spawn(process.execPath, ['serve.mjs'], { cwd: studioRoot, env: { ...process.env, OTTER_STUDIO_PORT: String(port) }, stdio: 'ignore' });
process.on('exit', () => server.kill());
for (let attempt = 0; ; attempt++) {
  try { if ((await fetch(`http://127.0.0.1:${port}/`)).ok) break; } catch {}
  // 15 s: a cold Node start on Windows after the launch tests can take several seconds.
  if (attempt > 150) throw new Error('Studio server did not start');
  await new Promise(r => setTimeout(r, 100));
}

// Raw HTTP so the test controls every header (fetch forbids setting Host/Origin).
function raw(method, pathname, headers = {}, body = null, host = '127.0.0.1') {
  return new Promise((resolve, reject) => {
    const req = http.request({ host, port, method, path: pathname, headers: { host: `127.0.0.1:${port}`, ...headers } }, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: data }));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

const scratchRel = `scratch/studio-security-${process.pid}.ot`;
const scratchAbs = path.join(repoRoot, scratchRel);
fs.mkdirSync(path.dirname(scratchAbs), { recursive: true });
process.on('exit', () => fs.rmSync(scratchAbs, { force: true }));

try {
  await test('no wildcard CORS header is sent', async () => {
    const res = await raw('GET', '/api/project?folder=examples');
    assert.equal(res.status, 200);
    assert.equal(res.headers['access-control-allow-origin'], undefined);
  });

  await test('a POST from another web page cannot write a file or start a terminal command', async () => {
    const body = JSON.stringify({ path: scratchRel, content: 'say "pwned"\n' });
    const res = await raw('POST', '/api/file', { origin: 'https://evil.example', 'content-type': 'application/json' }, body);
    assert.equal(res.status, 403);
    assert.equal(fs.existsSync(scratchAbs), false);
    const term = await raw('POST', '/api/terminal', { origin: 'https://evil.example', 'content-type': 'application/json' }, JSON.stringify({ command: 'echo pwned' }));
    assert.equal(term.status, 403);
  });

  await test('a DNS-rebinding request (foreign Host) is refused', async () => {
    const res = await raw('GET', '/api/file?path=README.md', { host: `attacker.example:${port}` });
    assert.equal(res.status, 421);
  });

  await test('the server is not reachable on other network addresses', async () => {
    const external = Object.values(os.networkInterfaces()).flat().find(i => i && i.family === 'IPv4' && !i.internal);
    if (!external) { console.log('    (no non-loopback IPv4 address on this machine; skipped)'); return; }
    await assert.rejects(raw('GET', '/', {}, null, external.address), /ECONNREFUSED|EHOSTUNREACH|ETIMEDOUT/);
  });

  await test('an oversized request body is refused with 413', async () => {
    const huge = JSON.stringify({ path: scratchRel, content: 'x'.repeat(33 * 1024 * 1024) });
    const res = await raw('POST', '/api/file', { 'content-type': 'application/json' }, huge);
    assert.equal(res.status, 413);
    assert.equal(fs.existsSync(scratchAbs), false);
  });

  await test('static files cannot escape otter-studio/ or expose server code', async () => {
    for (const p of ['/../otter.ps1', '/%2e%2e/otter.ps1', '/..%2fotter.ps1', '/serve.mjs', '/server/launch.mjs', '/scripts/smoke.mjs']) {
      const res = await raw('GET', p);
      assert.equal(res.status, 404, `${p} must not be served`);
    }
    assert.equal((await raw('GET', '/js/app.js')).status, 200);
  });

  await test('the file API cannot read or write outside the workspace', async () => {
    const read = await raw('GET', `/api/file?path=${encodeURIComponent('../../etc/hosts')}`);
    assert.equal(read.status, 403);
    const write = await raw('POST', '/api/file', { 'content-type': 'application/json' }, JSON.stringify({ path: '../outside-studio-test.ot', content: 'x' }));
    assert.equal(write.status, 403);
    assert.equal(fs.existsSync(path.join(repoRoot, '..', 'outside-studio-test.ot')), false);
  });

  await test('a symlink inside the workspace cannot be used to write outside it', async () => {
    const linkRel = `scratch/studio-link-${process.pid}`;
    const linkAbs = path.join(repoRoot, linkRel);
    const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-studio-outside-'));
    try {
      fs.symlinkSync(outside, linkAbs, 'dir');
    } catch {
      console.log('    (cannot create symlinks here; skipped)');
      return;
    }
    try {
      const res = await raw('POST', '/api/file', { 'content-type': 'application/json' }, JSON.stringify({ path: `${linkRel}/escaped.ot`, content: 'x' }));
      assert.equal(res.status, 403);
      assert.equal(fs.existsSync(path.join(outside, 'escaped.ot')), false);
    } finally {
      // A directory symlink is a directory entry on Windows: unlink fails
      // there, rmdir removes the link itself (never the target).
      try { fs.unlinkSync(linkAbs); } catch { try { fs.rmdirSync(linkAbs); } catch { /* already gone */ } }
      fs.rmSync(outside, { recursive: true, force: true });
    }
  });
} finally {
  server.kill();
}

console.log(`\nSecurity tests passed: ${passed}.`);
