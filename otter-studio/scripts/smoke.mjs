// Otter Studio V1 smoke certification.
// Exercises the same local HTTP routes the Studio UI uses: project scan,
// open, save, run, terminal output, and parser-backed diagnostics.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const studioRoot = path.resolve(scriptDir, '..');
const repoRoot = path.resolve(studioRoot, '..');
const port = 4300 + (process.pid % 500);
const baseUrl = `http://127.0.0.1:${port}`;
const temporaryRelativePath = `scratch/studio-smoke-${process.pid}.ot`;
const temporaryPath = path.join(repoRoot, temporaryRelativePath);
const symbolWorkspaceRelativePath = `scratch/studio-symbols-${process.pid}`;
const symbolWorkspacePath = path.join(repoRoot, symbolWorkspaceRelativePath);

function wait(milliseconds) {
  return new Promise(resolve => setTimeout(resolve, milliseconds));
}

async function waitForServer() {
  let lastError;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try {
      const response = await fetch(`${baseUrl}/`);
      if (response.ok) return;
    } catch (error) {
      lastError = error;
    }
    await wait(100);
  }
  throw new Error(`Otter Studio did not start on port ${port}. ${lastError?.message || ''}\n${serverOutput}`);
}

async function request(pathname, options) {
  const response = await fetch(`${baseUrl}${pathname}`, options);
  const body = await response.json();
  assert.ok(response.ok, `${pathname} returned ${response.status}: ${body.error || 'unknown error'}`);
  return body;
}

const server = spawn(process.execPath, ['serve.mjs'], {
  cwd: studioRoot,
  env: { ...process.env, OTTER_STUDIO_PORT: String(port) },
  stdio: ['ignore', 'pipe', 'pipe']
});

let serverOutput = '';
server.stdout.on('data', chunk => { serverOutput += chunk; });
server.stderr.on('data', chunk => { serverOutput += chunk; });

try {
  await waitForServer();

  const project = await request('/api/project?folder=examples');
  assert.equal(project.name, 'examples');
  assert.ok(project.tree.length > 0, 'expected the examples workspace to contain files');

  const hello = await request('/api/file?path=examples/hello.ot');
  assert.match(hello.content, /Hello/);

  const source = 'say "Studio smoke works"\n';
  const saved = await request('/api/file', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: temporaryRelativePath, content: source })
  });
  assert.equal(saved.ok, true);
  assert.match(saved.revision, /^[a-f0-9]{64}$/, 'saved files must return a stable content revision');

  const reopened = await request(`/api/file?path=${encodeURIComponent(temporaryRelativePath)}`);
  assert.equal(reopened.content, source, 'save/read-back must preserve the editor source');
  assert.equal(reopened.revision, saved.revision);

  const externalSource = 'say "Changed outside Studio"\n';
  await fs.writeFile(temporaryPath, externalSource, 'utf8');
  const externalStatus = await request(`/api/file-status?path=${encodeURIComponent(temporaryRelativePath)}`);
  assert.equal(externalStatus.exists, true);
  assert.notEqual(externalStatus.revision, saved.revision, 'external edits must change the file revision');

  const staleSaveResponse = await fetch(`${baseUrl}/api/file`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      path: temporaryRelativePath,
      content: 'say "Do not overwrite external changes"\n',
      expectedRevision: saved.revision
    })
  });
  const staleSave = await staleSaveResponse.json();
  assert.equal(staleSaveResponse.status, 409, 'stale saves must be rejected');
  assert.equal(staleSave.conflict, true);
  assert.equal(staleSave.content, externalSource, 'conflicts must return the current disk content');

  const resolvedSave = await request('/api/file', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      path: temporaryRelativePath,
      content: source,
      expectedRevision: externalStatus.revision
    })
  });
  assert.equal(resolvedSave.ok, true);

  const run = await request('/api/run', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: temporaryRelativePath })
  });
  assert.equal(run.exitCode, 0, run.stderr || run.error || 'Otter program failed');
  assert.match(run.stdout, /Studio smoke works/);

  const terminal = await request('/api/terminal', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ command: 'Write-Output studio-terminal-ok' })
  });
  assert.equal(terminal.exitCode, 0, terminal.stderr || 'terminal command failed');
  assert.match(terminal.stdout, /studio-terminal-ok/);

  const failedTerminal = await request('/api/terminal', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ command: 'Write-Error studio-terminal-failure; exit 7' })
  });
  assert.equal(failedTerminal.exitCode, 7, 'terminal failures must preserve their child exit code');
  assert.match(failedTerminal.stderr, /studio-terminal-failure/);

  const diagnostic = await request('/api/lint', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: 'say "lint works"\n' })
  });
  assert.equal(diagnostic.ok, true, diagnostic.message || 'parser rejected valid Otter source');

  const invalidDiagnostic = await request('/api/lint', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: 'if true\nsay "missing indentation"\n' })
  });
  assert.equal(invalidDiagnostic.ok, false, 'invalid Otter must reach Studio as a diagnostic');
  assert.ok(invalidDiagnostic.line > 0, 'Studio diagnostics must identify a source line');

  const symbolSource = `answer is 42

to greet name
    say "Hello" name
.
`;
  const analysis = await request('/api/analyze', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: symbolSource })
  });
  assert.equal(analysis.Ok, true, analysis.Message || 'semantic analysis failed');
  assert.ok(analysis.Symbols.some(symbol => symbol.Name === 'answer' && symbol.Kind === 'variable'));
  assert.ok(analysis.Symbols.some(symbol => symbol.Name === 'greet' && symbol.Kind === 'function'));
  assert.ok(analysis.Symbols.some(symbol => symbol.Name === 'name' && symbol.Kind === 'parameter'));

  await fs.mkdir(symbolWorkspacePath, { recursive: true });
  await fs.writeFile(path.join(symbolWorkspacePath, 'main.ot'), symbolSource, 'utf8');
  await fs.writeFile(path.join(symbolWorkspacePath, 'helper.ot'), 'to helper value\n    return value\n.\n', 'utf8');
  const workspaceIndex = await request(`/api/workspace-symbols?folder=${encodeURIComponent(symbolWorkspaceRelativePath)}`);
  assert.equal(workspaceIndex.files.length, 2);
  assert.ok(workspaceIndex.symbols.some(symbol => symbol.Name === 'greet' && symbol.File.endsWith('/main.ot')));
  assert.ok(workspaceIndex.symbols.some(symbol => symbol.Name === 'helper' && symbol.File.endsWith('/helper.ot')));

  console.log('Otter Studio smoke test passed: scan, open, save, external-change protection, symbols, run, terminal, diagnostics, failures.');
} finally {
  await fs.rm(temporaryPath, { force: true });
  await fs.rm(symbolWorkspacePath, { force: true, recursive: true });
  if (!server.killed) server.kill();
}
