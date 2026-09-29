// Projects outside the Otter installation, and multi-file projects in the
// designer and Live App.
//
// Studio started with OTTER_STUDIO_WORKSPACES (what `otter studio <folder>`
// does) must open that folder and nothing else outside the install; a
// render of a document from it must resolve the document's `use` imports
// and serve its images; a live render starts at the project's entry point;
// and the generator must keep nested handler bodies valid Otter.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { dedentBody, generateOtterSource } = await import(pathToFileURL(path.join(studioRoot, 'js', 'compiler', 'otter-generator.js')).href);

// --- 1. The generator keeps nested handler bodies one level under `when` ---

assert.deepEqual(
  dedentBody('    if ready\n        say "go"\n    .\n'),
  ['if ready', '    say "go"', '.'],
  'common indentation is removed, relative indentation kept'
);
assert.deepEqual(dedentBody('\n\tsay "tab"\n'), ['say "tab"'], 'tabs count as one level');

const fakeModel = {
  getRoot: () => ({ id: 'r', name: 'app', kind: 'window', properties: {}, children: ['b'] }),
  getComponent: (id) => (id === 'b' ? { id: 'b', name: 'go', kind: 'button', properties: { text: 'Go' }, children: [] } : null),
  events: new Map([['b', { clicked: '    if ready\n        say "go"\n    .' }]])
};
const generated = generateOtterSource(fakeModel);
assert.ok(generated.includes('when go is clicked\n    if ready\n        say "go"\n    .\n.'), generated);

// --- 2. A project folder outside the installation -----------------------

const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-studio-workspace-'));
const elsewhere = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-studio-elsewhere-'));
fs.mkdirSync(path.join(outside, 'parts'));
fs.mkdirSync(path.join(outside, 'images'));
fs.writeFileSync(path.join(outside, 'project.json'), JSON.stringify({ name: 'outside', target: 'web', entryPoint: 'main.ot' }));
// Otter 1.0 syntax (the 1.1 proposal's phrase functions are not on this line).
fs.writeFileSync(path.join(outside, 'parts', 'label.ot'), 'madeLabel is a text with value "made-label"\n');
fs.writeFileSync(path.join(outside, 'main.ot'), [
  'use "parts/label.ot"',
  'use "screen.ot"',
  'app is a page with title "Outside"',
  'put madeLabel in app',
  'show app',
  ''
].join('\n'));
fs.writeFileSync(path.join(outside, 'screen.ot'), [
  'use "parts/label.ot"',
  'logo is a image with source "images/logo.png", alt "Logo"',
  ''
].join('\n'));
const png = Buffer.from('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da63f8ffff3f0005fe02fe0dc7b0e20000000049454e44ae426082', 'hex');
fs.writeFileSync(path.join(outside, 'images', 'logo.png'), png);
fs.writeFileSync(path.join(elsewhere, 'secret.ot'), 'say "not yours"\n');

const port = 5200 + (process.pid % 400);
const baseUrl = `http://127.0.0.1:${port}`;
const server = spawn(process.execPath, ['serve.mjs'], {
  cwd: studioRoot,
  env: { ...process.env, OTTER_STUDIO_PORT: String(port), OTTER_STUDIO_WORKSPACES: outside },
  stdio: ['ignore', 'pipe', 'pipe']
});
let serverOutput = '';
server.stdout.on('data', chunk => { serverOutput += chunk; });
server.stderr.on('data', chunk => { serverOutput += chunk; });

async function waitForServer() {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    try { if ((await fetch(`${baseUrl}/`)).ok) return; } catch { /* not up yet */ }
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`Studio did not start on port ${port}.\n${serverOutput}`);
}

async function render(body) {
  const response = await fetch(`${baseUrl}/api/render`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  return { status: response.status, body: await response.json() };
}

try {
  await waitForServer();

  // The opened folder is a project Studio can show and read...
  const project = await (await fetch(`${baseUrl}/api/project?folder=${encodeURIComponent(outside)}`)).json();
  assert.ok(Array.isArray(project.tree) && project.tree.some(n => n.name === 'main.ot'), JSON.stringify(project));
  const mainRel = path.join(project.rootPath, 'main.ot');
  const file = await fetch(`${baseUrl}/api/file?path=${encodeURIComponent(mainRel)}`);
  assert.equal(file.status, 200, 'a file in the opened folder can be read');

  // ...but a folder it was not opened on stays out of reach.
  const refusedTree = await fetch(`${baseUrl}/api/project?folder=${encodeURIComponent(elsewhere)}`);
  assert.equal(refusedTree.status, 404);
  const refusedFile = await fetch(`${baseUrl}/api/file?path=${encodeURIComponent(path.join(elsewhere, 'secret.ot'))}`);
  assert.equal(refusedFile.status, 403);

  // --- 3. A multi-file document renders with its imports and images ------
  const mainCode = fs.readFileSync(path.join(outside, 'main.ot'), 'utf8');
  const withImports = await render({ code: mainCode, css: '', path: mainRel });
  assert.equal(withImports.status, 200, JSON.stringify(withImports.body).slice(0, 600));
  const html = withImports.body.html;
  assert.ok(html.includes('made-label'), 'the imported component ran');
  const base = /<base href="([^"]+)">/.exec(html);
  assert.ok(base, 'the page is based in the project folder');
  const image = await fetch(`${baseUrl}${base[1]}images/logo.png`);
  assert.equal(image.status, 200, 'the project image is served');
  assert.equal(image.headers.get('content-type'), 'image/png');
  assert.equal((await fetch(`${baseUrl}${base[1]}main.ot`)).status, 404, 'source files are not served as assets');
  assert.equal((await fetch(`${baseUrl}${base[1]}../${path.basename(elsewhere)}/secret.ot`)).status, 404, 'nothing outside the workspace is served');

  // Without a path the old behaviour stands: imports cannot resolve.
  const withoutPath = await render({ code: mainCode, css: '' });
  assert.equal(withoutPath.status, 422);

  // --- 4. Live App starts from the project's entry point ---------------------
  const screenRel = path.join(project.rootPath, 'screen.ot');
  const live = await render({ code: fs.readFileSync(path.join(outside, 'screen.ot'), 'utf8'), css: '', path: screenRel, live: true });
  assert.equal(live.status, 200, JSON.stringify(live.body).slice(0, 600));
  assert.ok(live.body.html.includes('<title>Outside</title>'), 'the live run is the project, not the single file');

  console.log('Workspace project tests passed.');
} finally {
  server.kill();
  fs.rmSync(outside, { recursive: true, force: true });
  fs.rmSync(elsewhere, { recursive: true, force: true });
}
