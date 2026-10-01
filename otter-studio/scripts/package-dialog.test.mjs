// Build -> Desktop App certification: the Studio server drives the real
// `otter package --progress` command and streams its steps; the dialog and
// menu are wired in the shell. The packaging itself runs in --dry-run mode
// here so the suite never waits on electron-builder.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const studioRoot = path.resolve(scriptDir, '..');
const repoRoot = path.resolve(studioRoot, '..');
const port = 4300 + ((process.pid + 97) % 500);
const baseUrl = `http://127.0.0.1:${port}`;
const projectRelative = `scratch/studio-package-${process.pid}`;
const projectDir = path.join(repoRoot, projectRelative);

// 1. Shell wiring.
const [indexHtml, shellJs, dialogJs] = await Promise.all([
  fs.readFile(path.join(studioRoot, 'index.html'), 'utf8'),
  fs.readFile(path.join(studioRoot, 'js', 'shell', 'studio-shell.js'), 'utf8'),
  fs.readFile(path.join(studioRoot, 'js', 'shell', 'package-dialog.js'), 'utf8')
]);
const menuBarJs = await fs.readFile(path.join(studioRoot, 'js', 'shell', 'menu-bar.js'), 'utf8');
assert.match(menuBarJs, /id: 'build', label: 'Build'/, 'the menu bar must have a Build menu');
assert.match(menuBarJs, /'build.desktopApp'/, 'Build must offer Desktop App (Windows)');
assert.match(indexHtml, /css\/package-dialog\.css/, 'the dialog stylesheet must be linked');
assert.match(shellJs, /mountPackageDialog\(/, 'the shell must mount the package dialog');
assert.match(dialogJs, /fetch\('\/api\/package'/, 'the dialog must build through /api/package');
assert.match(dialogJs, /\/api\/reveal/, 'the dialog must offer Open Folder');
assert.match(dialogJs, /saveManifestChanges/, 'metadata edits must be saved to the manifest before building');
assert.match(dialogJs, /ide\.isTrusted === false/, 'an untrusted workspace must not be packaged (same rule as Run and Terminal)');

// 2. The server endpoint, against a real project folder.
await fs.mkdir(projectDir, { recursive: true });
await fs.writeFile(path.join(projectDir, 'main.ot'), 'app is a window with title "Dialog Smoke"\ngo is a button with text "Go"\nput go in app\nshow app\n');
await fs.writeFile(path.join(projectDir, 'main.css'), '/* STYLES_CSS_MARKER */\n#go { color: blue; }\n');
await fs.writeFile(path.join(projectDir, 'otter.json'), JSON.stringify({ name: 'Dialog Smoke', version: '1.0.0', archetype: 'desktop', target: 'desktop', entryPoint: 'main.ot' }, null, 2));

const server = spawn(process.execPath, ['serve.mjs'], {
  cwd: studioRoot,
  env: { ...process.env, OTTER_STUDIO_PORT: String(port) },
  stdio: ['ignore', 'pipe', 'pipe']
});
let serverOutput = '';
server.stdout.on('data', chunk => { serverOutput += chunk; });
server.stderr.on('data', chunk => { serverOutput += chunk; });

async function waitForServer() {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    try {
      const response = await fetch(`${baseUrl}/`);
      if (response.ok) return;
    } catch { /* not up yet */ }
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`Otter Studio did not start on port ${port}.\n${serverOutput}`);
}

async function readEvents(response) {
  const text = await response.text();
  return text.split('\n').filter(Boolean).map(line => JSON.parse(line));
}

try {
  await waitForServer();

  const response = await fetch(`${baseUrl}/api/package`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ folder: projectRelative, kinds: ['portable'], dryRun: true, target: 'windows' })
  });
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type') || '', /x-ndjson/, 'progress streams as newline-delimited JSON');
  const events = await readEvents(response);
  const steps = events.filter(e => e.type === 'progress');
  const byStep = Object.fromEntries(steps.map(e => [e.step, e]));
  for (const step of ['check', 'export', 'styles', 'configure', 'done']) {
    assert.ok(byStep[step], `expected a progress event for ${step}; got ${steps.map(e => e.step).join(',')}\n${events.filter(e => e.type === 'log').map(e => e.text).join('\n')}`);
  }
  assert.equal(byStep.export.status, 'done');
  assert.match(byStep.styles.label, /main\.css/, 'the stylesheet step names the embedded file');
  assert.equal(byStep.done.dryRun, true);
  assert.match(byStep.done.outputDir, /packages$/);
  const exit = events.find(e => e.type === 'exit');
  assert.equal(exit && exit.code, 0, `otter package should exit 0; output:\n${events.filter(e => e.type === 'log').map(e => e.text).join('\n')}`);
  const indexPath = path.join(projectDir, 'dist', 'app', 'index.html');
  const built = await fs.readFile(indexPath, 'utf8');
  assert.match(built, /STYLES_CSS_MARKER/, 'the exported page carries main.css');
  console.log('  pass  /api/package streams check, export, styles, configure and done for a dry run');

  // The endpoint refuses folders outside the repository and reports unknown ones.
  const outside = await fetch(`${baseUrl}/api/package`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ folder: '../outside-project', dryRun: true })
  });
  assert.equal(outside.status, 404);
  const missing = await fetch(`${baseUrl}/api/package`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ folder: 'scratch/does-not-exist-' + process.pid, dryRun: true })
  });
  assert.equal(missing.status, 404);

  // A console project is refused by otter package itself, and the stream says why.
  await fs.writeFile(path.join(projectDir, 'otter.json'), JSON.stringify({ name: 'Dialog Smoke', archetype: 'console', target: 'console', entryPoint: 'main.ot' }, null, 2));
  const consoleRun = await fetch(`${baseUrl}/api/package`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ folder: projectRelative, dryRun: true })
  });
  const consoleEvents = await readEvents(consoleRun);
  const consoleExit = consoleEvents.find(e => e.type === 'exit');
  assert.notEqual(consoleExit && consoleExit.code, 0);
  assert.ok(consoleEvents.some(e => e.type === 'log' && /no window to package/.test(e.text)), 'the refusal reaches the dialog as a log line');
  console.log('  pass  /api/package refuses outside folders, unknown folders and console projects readably');

  // Reveal never opens anything outside the repository.
  const revealOutside = await fetch(`${baseUrl}/api/reveal`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: '../../Windows' })
  });
  assert.equal(revealOutside.status, 403);
  const revealMissing = await fetch(`${baseUrl}/api/reveal`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: `${projectRelative}/nope` })
  });
  assert.equal(revealMissing.status, 403);
  console.log('  pass  /api/reveal refuses paths outside the repository and missing folders');

  console.log('Build -> Desktop App certification passed.');
} finally {
  server.kill();
  await fs.rm(projectDir, { recursive: true, force: true });
}
