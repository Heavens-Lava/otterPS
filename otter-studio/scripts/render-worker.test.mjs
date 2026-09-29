// Studio's kept-loaded compiler (server/render-worker.mjs) compiles exactly
// as `otter web` does - the same page, the same errors, lines mapped to the
// file that has them - and much faster once loaded.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(studioRoot, '..');
const { createRenderWorker } = await import('../server/render-worker.mjs');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-render-worker-'));
const write = (name, text) => { fs.writeFileSync(path.join(dir, name), text); return path.join(dir, name); };
const worker = createRenderWorker({ repoRoot, timeoutMs: 60000 });
let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`  ✓ ${name}`);
}

console.log('Render worker:');
try {
  const form = write('form.ot', 'app is a window with title "Worker"\nt is a text with text "Hi"\nput t in app\nshow app\n');
  write('form.css', '#t { color: red; }\n');

  await test('the page is the one `otter web` writes', async () => {
    const reply = await worker.compile({ source: form, output: path.join(dir, 'worker.html') });
    assert.equal(reply.ok, true, JSON.stringify(reply));
    execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(repoRoot, 'otter.ps1'), 'web', form, '-NoOpen'], { stdio: 'pipe' });
    assert.equal(fs.readFileSync(path.join(dir, 'worker.html'), 'utf8'), fs.readFileSync(path.join(dir, 'form.html'), 'utf8'));
  });

  await test('once loaded, a compile takes well under a second', async () => {
    const started = Date.now();
    const reply = await worker.compile({ source: form, output: path.join(dir, 'again.html') });
    assert.equal(reply.ok, true);
    assert.ok(Date.now() - started < 1000, `${Date.now() - started} ms`);
  });

  await test('a syntax error is reported as `otter web` reports it (exit code 2)', async () => {
    const bad = write('bad.ot', 'app is a window\n\nx is\n');
    const reply = await worker.compile({ source: bad, output: path.join(dir, 'bad.html') });
    assert.equal(reply.ok, false);
    assert.equal(reply.code, 2);
    assert.match(reply.message, /Otter Syntax Error/);
    assert.doesNotMatch(reply.message, /bug in Otter/);
  });

  await test('an error in a used file names that file and its own line', async () => {
    write('part.ot', 'a is 1\nb is 2\ny is\n');
    const main = write('main.ot', 'use "part.ot"\napp is a window\nshow app\n');
    const reply = await worker.compile({ source: main, output: path.join(dir, 'main.html') });
    assert.equal(reply.ok, false);
    assert.match(reply.message, /In "part\.ot"/);
    assert.match(reply.message, /^Line 1:/m);
  });
} finally {
  worker.stop();
  fs.rmSync(dir, { recursive: true, force: true });
}
console.log(`\nRender worker tests passed: ${passed}.`);
