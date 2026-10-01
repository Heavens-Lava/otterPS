// terminal.test.mjs - the integrated terminal (checklist: persistent
// terminal): one long-lived shell per terminal (server/terminal-sessions.mjs)
// through Studio's real server.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`  ✓ ${name}`);
}

const port = 5950 + (process.pid % 40);
const baseUrl = `http://127.0.0.1:${port}`;
const server = spawn(process.execPath, ['serve.mjs'], { cwd: studioRoot, env: { ...process.env, OTTER_STUDIO_PORT: String(port) }, stdio: 'ignore' });
process.on('exit', () => server.kill());
for (let attempt = 0; ; attempt++) {
  try { if ((await fetch(`${baseUrl}/`)).ok) break; } catch {}
  if (attempt > 150) throw new Error('Studio server did not start');
  await new Promise(r => setTimeout(r, 100));
}
const post = async (route, body) => {
  const res = await fetch(`${baseUrl}${route}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  return { status: res.status, body: await res.json() };
};
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-terminal-'));
fs.writeFileSync(path.join(scratch, 'ask.ot'), 'ask "Your name?" and call it name\nsay "Hi" name\n');
fs.writeFileSync(path.join(scratch, 'long.ot'), 'say "waiting"\nwait 60 seconds\nsay "not reached"\n');

// Output since the last call; with `until`, wait for that text first;
// without, wait until the shell is idle.
function terminal(id) {
  let seen = '';
  const read = async ({ until = null, timeoutMs = 60000 } = {}) => {
    const start = Date.now();
    let out = '';
    for (;;) {
      const state = await (await fetch(`${baseUrl}/api/terminal/poll?id=${encodeURIComponent(id)}`)).json();
      for (const c of state.chunks || []) { out += c.text; seen += c.text; }
      if (until ? out.includes(until) : !state.busy) return { out, state };
      if (Date.now() - start > timeoutMs) throw new Error(`terminal timed out; got: ${out}`);
      await new Promise(r => setTimeout(r, 100));
    }
  };
  const run = async (text, opts) => { await post('/api/terminal/write', { id, text }); return read(opts); };
  return { read, run, get seen() { return seen; } };
}

console.log('Integrated terminal:');
const opened = await post('/api/terminal/open', {});
assert.ok(opened.body.id, JSON.stringify(opened.body));
const t = terminal(opened.body.id);
try {
  await t.read();

  await test('cd, variables and functions last for the session', async () => {
    await t.run(`cd '${scratch.replace(/'/g, "''")}'`);
    await t.run('$answer = 6 * 7');
    await t.run('function greet($n) { "hello $n" }');
    const { out, state } = await t.run('$answer; greet otter');
    assert.match(out, /42/);
    assert.match(out, /hello otter/);
    assert.equal(state.cwd.toLowerCase(), fs.realpathSync(scratch).toLowerCase());
  });

  await test('UTF-8 both ways, and a command with quotes and a # comment runs as typed', async () => {
    const { out } = await t.run('Write-Output "héllo ✓ Grüße" # a comment');
    assert.match(out, /héllo ✓ Grüße/);
  });

  await test('an Otter program that asks reads the next line typed, shown once', async () => {
    await t.run('otter run ask.ot', { until: 'Your name?' });
    const { out } = await t.run('Grace');
    assert.match(out, /Hi Grace/);
    assert.ok(!/^Grace\s*$/m.test(out), `the program's echo of the typed line is dropped: ${JSON.stringify(out)}`);
  });

  await test('a program\'s exit code and a failing command are reported', async () => {
    const failed = await t.run('cmd /c exit 3');
    assert.equal(failed.state.exitCode, 3);
    const missing = await t.run('nosuchcommandatall');
    assert.equal(missing.state.exitOk, false);
    assert.match(missing.out, /nosuchcommandatall/);
  });

  await test('interrupt ends a running program; the shell and its variables stay', async () => {
    await t.run('otter run long.ot', { until: 'waiting' });
    const stopped = await post('/api/terminal/interrupt', { id: opened.body.id });
    assert.equal(stopped.body.stopped, 'program');
    await t.read();
    const { out } = await t.run('$answer');
    assert.match(out, /42/);
  });

  await test('interrupting a command inside PowerShell starts a new shell in the same folder, and says so', async () => {
    await post('/api/terminal/write', { id: opened.body.id, text: 'Start-Sleep -Seconds 60' });
    await new Promise(r => setTimeout(r, 1500));
    const stopped = await post('/api/terminal/interrupt', { id: opened.body.id });
    assert.equal(stopped.body.stopped, 'shell');
    const { out, state } = await t.read();
    assert.match(out, /new shell/);
    assert.equal(state.cwd.toLowerCase(), fs.realpathSync(scratch).toLowerCase());
    const after = await t.run('"answer is [$answer]"');
    assert.match(after.out, /answer is \[\]/);
  });

  await test('the terminal is refused to other web pages; closed terminals are gone', async () => {
    const evil = await fetch(`${baseUrl}/api/terminal/write`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: 'https://evil.example' }, body: JSON.stringify({ id: opened.body.id, text: 'echo pwned' }) });
    assert.equal(evil.status, 403);
    await post('/api/terminal/close', { id: opened.body.id });
    const after = await post('/api/terminal/write', { id: opened.body.id, text: 'echo hi' });
    assert.equal(after.status, 404);
  });
} finally {
  await post('/api/terminal/close', { id: opened.body.id }).catch(() => {});
  server.kill();
  // The closed shell may still hold its folder for a moment.
  await new Promise(r => setTimeout(r, 1500));
  try { fs.rmSync(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 300 }); } catch { /* the OS removes temp files later */ }
}
console.log(`\nTerminal tests passed: ${passed}.`);
