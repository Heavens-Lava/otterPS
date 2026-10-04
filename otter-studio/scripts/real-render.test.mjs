// Real-render certification: Studio's /api/render must return the output of the
// production Otter web compiler (`otter web`), not a Studio-side approximation.
// The designer canvas and Live App preview both depend on this contract.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const port = 4800 + (process.pid % 400);
const baseUrl = `http://127.0.0.1:${port}`;

const server = spawn(process.execPath, ['serve.mjs'], {
  cwd: studioRoot,
  env: { ...process.env, OTTER_STUDIO_PORT: String(port) },
  stdio: ['ignore', 'pipe', 'pipe']
});
let serverOutput = '';
server.stdout.on('data', chunk => { serverOutput += chunk; });
server.stderr.on('data', chunk => { serverOutput += chunk; });

async function waitForServer() {
  for (let attempt = 0; attempt < 200; attempt += 1) {
    try {
      if ((await fetch(`${baseUrl}/`)).ok) return;
    } catch { /* not up yet */ }
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`Studio did not start on port ${port}.\n${serverOutput}`);
}

async function render(code, css = '') {
  const response = await fetch(`${baseUrl}/api/render`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, css })
  });
  return { status: response.status, body: await response.json() };
}

try {
  await waitForServer();

  const source = [
    'app is a window with title "Real", width 400, background "#f8fafc"',
    'card is a card with width full, padding 24, background "#1e293b", round',
    'saveButton is a primary button with text "Save", padding 8',
    'put saveButton in card',
    'put card in app',
    'show app',
    ''
  ].join('\n');

  // 1. The response is the real compiler's page: real class names, real
  //    element ids, real inline styles - including the bare `round` -> pill.
  const good = await render(source);
  assert.equal(good.status, 200, JSON.stringify(good.body));
  assert.equal(good.body.ok, true);
  const html = good.body.html;
  assert.ok(!html.startsWith('﻿'), 'byte-order mark must be stripped');
  assert.match(html, /id="app"[^>]*class="otter-window"/, 'window comes from the real compiler');
  assert.match(html, /id="card"[^>]*class="otter-card"/);
  assert.match(html, /id="saveButton"[^>]*class="otter-button otter-button-primary"/);
  assert.match(html, /id="card"[^>]*border-radius: 9999px/, 'bare `round` means a pill in the real runtime');

  // 2. Sidecar CSS is applied exactly as `otter web` applies it.
  const styled = await render(source, '#saveButton { letter-spacing: 3px; }');
  assert.equal(styled.body.ok, true);
  assert.match(styled.body.html, /id="otter-sidecar-style"[\s\S]*letter-spacing: 3px/);

  // 3. Identical input is served from the cache (same object, no recompile).
  const started = Date.now();
  const again = await render(source);
  assert.equal(again.body.html, html);
  assert.ok(Date.now() - started < 500, 'cached render should be near-instant');

  // 4. Invalid source is reported as an error with the compiler's message, not
  //    turned into a page.
  const bad = await render('app is a window with title\nput nothing');
  assert.equal(bad.status, 422);
  assert.equal(bad.body.ok, false);
  assert.ok(bad.body.message.length > 0);

  // 5. Concurrent renders each get their own correct answer.
  const [a, b] = await Promise.all([
    render('one is a window with title "Alpha"\nshow one\n'),
    render('two is a window with title "Beta"\nshow two\n')
  ]);
  assert.match(a.body.html, /id="one"/);
  assert.match(b.body.html, /id="two"/);

  console.log('Studio real-render certification passed (5 checks).');
} finally {
  server.kill();
}
