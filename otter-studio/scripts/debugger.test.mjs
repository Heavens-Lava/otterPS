// otter-studio/scripts/debugger.test.mjs
// Certification test for Otter Studio Debugger (first slice)
// Validates breakpoint arming, process spawning, pause events, locals inspection,
// continue resumption, multi-breakpoint stepping, and session termination.

import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const port = 4900 + (process.pid % 300);
const baseUrl = `http://127.0.0.1:${port}`;

console.log('=== Running Otter Studio Debugger Certification Suite ===\n');

const server = spawn(process.execPath, ['serve.mjs'], {
  cwd: studioRoot,
  env: { ...process.env, OTTER_STUDIO_PORT: String(port) },
  stdio: ['ignore', 'pipe', 'pipe']
});

let serverOutput = '';
server.stdout.on('data', chunk => { serverOutput += chunk; });
server.stderr.on('data', chunk => { serverOutput += chunk; });

async function waitForServer() {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    try {
      if ((await fetch(`${baseUrl}/`)).ok) return;
    } catch { /* not up yet */ }
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`Studio did not start on port ${port}.\n${serverOutput}`);
}

async function postJson(endpoint, data) {
  const res = await fetch(`${baseUrl}${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  });
  return { status: res.status, body: await res.json() };
}

async function getJson(endpoint) {
  const res = await fetch(`${baseUrl}${endpoint}`);
  return { status: res.status, body: await res.json() };
}

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

try {
  await waitForServer();

  // --- 1. Single Breakpoint Pause, Locals Inspection & Continue ---
  console.log('--- 1. Single Breakpoint: Pause, Inspect Locals & Continue ---');
  const start1 = await postJson('/api/debug/start', {
    path: 'examples/debugger-demo.ot',
    breakpoints: [6]
  });
  assert.equal(start1.status, 200);
  assert.ok(start1.body.sessionId, 'Should return valid debug sessionId');
  const session1 = start1.body.sessionId;

  // Poll until paused
  let pausedEvent1 = null;
  for (let i = 0; i < 30; i++) {
    await sleep(250);
    const poll = await getJson(`/api/debug/poll?sessionId=${encodeURIComponent(session1)}`);
    if (poll.status === 200 && poll.body.events) {
      const found = poll.body.events.find(e => e.event === 'paused');
      if (found) {
        pausedEvent1 = found;
        break;
      }
    }
  }

  assert.ok(pausedEvent1, 'Debugger must emit a paused event');
  assert.equal(pausedEvent1.line, 6, 'Debugger must pause at exact breakpoint line 6');
  assert.equal(pausedEvent1.locals.name, 'Jeff', 'Local variable "name" must match expected value');
  assert.equal(pausedEvent1.locals.score, '0', 'Local variable "score" must be 0 prior to line 6 execution');
  console.log('  ✓ Debugger paused at line 6 with locals:', JSON.stringify(pausedEvent1.locals));

  // Continue execution
  const cont1 = await postJson('/api/debug/continue', { sessionId: session1 });
  assert.equal(cont1.status, 200);
  assert.equal(cont1.body.ok, true, 'Continue request must succeed');
  console.log('  ✓ Continued execution successfully');

  // Poll until finished
  let finishedEvent1 = false;
  let finalOutput1 = [];
  let exitCode1 = null;
  for (let i = 0; i < 30; i++) {
    await sleep(250);
    const poll = await getJson(`/api/debug/poll?sessionId=${encodeURIComponent(session1)}`);
    if (poll.status === 200) {
      if (poll.body.output) finalOutput1.push(...poll.body.output);
      if (poll.body.finished) {
        finishedEvent1 = true;
        exitCode1 = poll.body.exitCode;
        break;
      }
    }
  }

  assert.ok(finishedEvent1, 'Debugger session must finish cleanly');
  assert.equal(exitCode1, 0, 'Exit code must be 0');
  assert.ok(finalOutput1.some(l => l.includes('Score is 5')), 'Program output must include "Score is 5"');
  assert.ok(finalOutput1.some(l => l.includes('Final score is 8')), 'Program output must include "Final score is 8"');
  assert.ok(finalOutput1.some(l => l.includes('Done Jeff')), 'Program output must include "Done Jeff"');
  console.log('  ✓ Program finished cleanly with code 0 and verified output');

  // --- 2. Multi-Breakpoint Execution Flow ---
  console.log('\n--- 2. Multi-Breakpoint Flow (Step from Line 6 to Line 8) ---');
  const start2 = await postJson('/api/debug/start', {
    path: 'examples/debugger-demo.ot',
    breakpoints: [6, 8]
  });
  assert.equal(start2.status, 200);
  const session2 = start2.body.sessionId;

  // Poll for first pause at line 6
  let firstPause = null;
  for (let i = 0; i < 30; i++) {
    await sleep(250);
    const poll = await getJson(`/api/debug/poll?sessionId=${encodeURIComponent(session2)}`);
    if (poll.status === 200 && poll.body.events) {
      firstPause = poll.body.events.find(e => e.event === 'paused');
      if (firstPause) break;
    }
  }
  assert.ok(firstPause, 'Must reach first breakpoint');
  assert.equal(firstPause.line, 6);
  assert.equal(firstPause.locals.score, '0');
  console.log('  ✓ First pause at line 6 (score = 0)');

  // Continue to second breakpoint
  const cont2 = await postJson('/api/debug/continue', { sessionId: session2 });
  assert.equal(cont2.status, 200);

  // Poll for second pause at line 8
  let secondPause = null;
  for (let i = 0; i < 30; i++) {
    await sleep(250);
    const poll = await getJson(`/api/debug/poll?sessionId=${encodeURIComponent(session2)}`);
    if (poll.status === 200 && poll.body.events) {
      secondPause = poll.body.events.find(e => e.event === 'paused');
      if (secondPause) break;
    }
  }
  assert.ok(secondPause, 'Must reach second breakpoint');
  assert.equal(secondPause.line, 8);
  assert.equal(secondPause.locals.score, '5', 'Score must have mutated to 5 after executing line 6');
  console.log('  ✓ Second pause at line 8 (score = 5)');

  // Resume to finish
  await postJson('/api/debug/continue', { sessionId: session2 });
  let finished2 = false;
  for (let i = 0; i < 30; i++) {
    await sleep(250);
    const poll = await getJson(`/api/debug/poll?sessionId=${encodeURIComponent(session2)}`);
    if (poll.status === 200 && poll.body.finished) {
      finished2 = true;
      break;
    }
  }
  assert.ok(finished2, 'Session 2 finished cleanly');
  console.log('  ✓ Multi-breakpoint session ran to completion');

  // --- 3. Stop Debug Session (Early Cancellation) ---
  console.log('\n--- 3. Stop Debug Session ---');
  const start3 = await postJson('/api/debug/start', {
    path: 'examples/debugger-demo.ot',
    breakpoints: [6]
  });
  const session3 = start3.body.sessionId;
  await sleep(600);

  const stopRes = await postJson('/api/debug/stop', { sessionId: session3 });
  assert.equal(stopRes.status, 200);
  assert.equal(stopRes.body.stopped, true, 'Stop must confirm process stopped');
  console.log('  ✓ Stop request cleanly terminated debug session');

  const pollAfterStop = await getJson(`/api/debug/poll?sessionId=${encodeURIComponent(session3)}`);
  assert.equal(pollAfterStop.status, 404, 'Polling after stop must return 404 session not found');
  console.log('  ✓ Session purged from active registry');

  console.log('\n========================================');
  console.log('Debugger Certification: 3 suites passed, 0 failed.');
  console.log('========================================');

} finally {
  server.kill('SIGTERM');
}
