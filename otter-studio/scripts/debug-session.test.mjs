// debug-session.test.mjs - the debugger through Studio's server (checklist
// §19): /api/debug/start runs the real `otter debug`, /api/debug/command
// steps, evaluates and changes breakpoints, /api/debug/poll relays events.
// The fixture is examples/debugger-steps.ot (line 14 calls double, lines 3-6).
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`  ✓ ${name}`);
}

const port = 5800 + (process.pid % 150);
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

// Poll until an event matching `want` arrives (or the session ends).
async function until(sessionId, want, seen) {
  for (let i = 0; i < 400; i++) {
    const data = await (await fetch(`${baseUrl}/api/debug/poll?sessionId=${encodeURIComponent(sessionId)}`)).json();
    for (const e of data.events || []) seen.events.push(e);
    for (const o of data.output || []) seen.output.push(o);
    const hit = seen.events.find((e, i) => i >= seen.used && want(e));
    if (hit) { seen.used = seen.events.indexOf(hit) + 1; return hit; }
    if (data.finished) return null;
    await new Promise(r => setTimeout(r, 150));
  }
  throw new Error('timed out waiting for a debug event');
}

console.log('Debugger through Studio\'s server:');
try {
  await test('step into a function, evaluate in its frame, then a conditional breakpoint stops where it is true', async () => {
    const start = await post('/api/debug/start', { path: 'examples/debugger-steps.ot', breakpoints: [{ line: 14 }] });
    assert.ok(start.body.sessionId, JSON.stringify(start.body));
    const id = start.body.sessionId;
    const seen = { events: [], output: [], used: 0 };
    const first = await until(id, e => e.event === 'paused', seen);
    assert.equal(first.line, 14);

    await post('/api/debug/command', { sessionId: id, command: 'step' });
    const inside = await until(id, e => e.event === 'paused', seen);
    assert.equal(inside.line, 4);
    assert.equal(inside.frames[0].function, 'double');

    await post('/api/debug/command', { sessionId: id, command: 'eval', id: 'w0', expression: 'n times 10' });
    const value = await until(id, e => e.event === 'evaluated', seen);
    assert.equal(value.value, '50');

    await post('/api/debug/command', { sessionId: id, command: 'breakpoints', breakpoints: [{ line: 15, condition: 'price is 20' }] });
    await post('/api/debug/command', { sessionId: id, command: 'continue' });
    const conditional = await until(id, e => e.event === 'paused', seen);
    assert.equal(conditional.line, 15);
    assert.equal(conditional.locals.price, '20');

    await post('/api/debug/command', { sessionId: id, command: 'continue' });
    assert.equal(await until(id, e => e.event === 'finished', seen), seen.events.at(-1));
    assert.deepEqual(seen.output.filter(l => l.startsWith('Total')), ['Total is 70']);
  });

  await test('only the debugger\'s own commands pass, one line each', async () => {
    const start = await post('/api/debug/start', { path: 'examples/debugger-steps.ot', breakpoints: [{ line: 7 }] });
    const id = start.body.sessionId;
    const seen = { events: [], output: [], used: 0 };
    await until(id, e => e.event === 'paused', seen);
    const bad = await post('/api/debug/command', { sessionId: id, command: 'say "hi"' });
    assert.equal(bad.status, 400);
    // A newline in an expression cannot become a second command.
    await post('/api/debug/command', { sessionId: id, command: 'eval', id: 'x', expression: 'total\ncontinue' });
    const evaluated = await until(id, e => e.event === 'evaluated', seen);
    assert.equal(evaluated.expression, 'total continue');
    assert.ok(!seen.events.slice(1).some(e => e.event === 'finished'), 'the program is still paused');
    await post('/api/debug/stop', { sessionId: id });
  });

  await test('a breakpoint\'s log message is written without stopping', async () => {
    const start = await post('/api/debug/start', { path: 'examples/debugger-steps.ot', breakpoints: [{ line: 17, log: 'about to say {total}' }] });
    const id = start.body.sessionId;
    const seen = { events: [], output: [], used: 0 };
    const log = await until(id, e => e.event === 'log', seen);
    assert.equal(log.text, 'about to say 70');
    assert.ok(await until(id, e => e.event === 'finished', seen));
    assert.ok(!seen.events.some(e => e.event === 'paused'), 'a logpoint never stops');
  });
} finally {
  server.kill();
}
console.log(`\nDebug session tests passed: ${passed}.`);
