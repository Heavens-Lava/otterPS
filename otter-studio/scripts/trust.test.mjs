// Restricted Mode trust is remembered on this computer (server/trust.mjs),
// one entry per folder however it is spelled, withdrawals included.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-trust-'));
process.env.OTTER_STUDIO_TRUST_FILE = path.join(dir, 'trusted.json');
const { trustOf, setTrusted, trustKey } = await import('../server/trust.mjs');

let passed = 0;
function test(name, fn) {
  fn();
  passed++;
  console.log(`  ✓ ${name}`);
}

console.log('Workspace trust:');
const project = path.join(dir, 'My Project');
fs.mkdirSync(project);

try {
  test('a folder never seen is neither trusted nor known', () => {
    assert.deepEqual(trustOf(project), { trusted: false, known: false });
  });

  test('trusting it is remembered, whatever the spelling of the path', () => {
    setTrusted(project, true);
    assert.deepEqual(trustOf(project), { trusted: true, known: true });
    assert.equal(trustOf(project + path.sep).trusted, true, 'a trailing separator');
    if (process.platform === 'win32') assert.equal(trustOf(project.toUpperCase()).trusted, true, 'Windows paths ignore case');
    assert.equal(trustOf(path.join(project, '..', 'My Project')).trusted, true, 'a path through ..');
    assert.equal(Object.keys(JSON.parse(fs.readFileSync(process.env.OTTER_STUDIO_TRUST_FILE, 'utf8'))).length, 1, 'one entry');
  });

  test('withdrawing it is remembered too (an old copy cannot revive it)', () => {
    setTrusted(project, false);
    assert.deepEqual(trustOf(project), { trusted: false, known: true });
  });

  test('keys are the real absolute path', () => {
    assert.equal(trustKey(project + path.sep), trustKey(project));
  });
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}

console.log(`\nTrust tests passed: ${passed}.`);
