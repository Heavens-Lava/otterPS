// test-explorer.test.mjs - Test Explorer (checklist §20), through `otter test`.
//
// Builds a project with `otter new`, adds passing, failing and unparsable
// tests plus files that are not tests, and checks that:
//   * Studio's discovery lists exactly the files `otter test` runs, in the
//     same order (parity with src/Otter.Project.psm1);
//   * running each test through the server gives the CLI's verdict, with
//     the failure message and line, duration and output;
//   * only discovered test files can be run.
import assert from 'node:assert/strict';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createScratchFolder } from './test-scratch.mjs';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(studioRoot, '..');
const { discoverTests, isTestFileName, parseTestFailure } = await import(pathToFileURL(path.join(studioRoot, 'server', 'tests.mjs')).href);
const { formatDuration } = await import(pathToFileURL(path.join(studioRoot, 'js', 'components', 'test-explorer.js')).href);

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`  ✓ ${name}`);
}

const otter = (cwd, ...args) => spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(repoRoot, 'otter.ps1'), ...args], { cwd, encoding: 'utf8' });

console.log('Test discovery and result parsing:');

await test('test file names follow otter test (*_test.ot, test_*.ot)', () => {
  assert.ok(isTestFileName('app_test.ot'));
  assert.ok(isTestFileName('Test_Login.OT'));
  assert.ok(!isTestFileName('helpers.ot'));
  assert.ok(!isTestFileName('app_test.ot.bak'));
  assert.equal(formatDuration(850), '850 ms');
  assert.equal(formatDuration(2345), '2.3 s');
});

await test('failure output gives the message and line', () => {
  assert.deepEqual(parseTestFailure('Running 1 Otter test...\n\nFAIL tests/a_test.ot\n\nFAIL tests/a_test.ot:6\n  Expected score to be 100.\n\n1 failed\n'), { line: 6, message: 'Expected score to be 100.' });
  const syntax = parseTestFailure('FAIL tests/b_test.ot (syntax error)\nOtter Syntax Error\nLine 2:\n    say "x\n        ^\nThis string never closes.\n');
  assert.equal(syntax.line, 2);
  assert.equal(syntax.message, 'This string never closes.');
});

const scratch = createScratchFolder(repoRoot, 'test-explorer');
execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(repoRoot, 'otter.ps1'), 'new', 'console', 'demo'], { cwd: scratch.abs, stdio: 'ignore' });
const projectAbs = path.join(scratch.abs, 'demo');
const projectRel = `${scratch.rel}/demo`;
const testsAbs = path.join(projectAbs, 'tests');
fs.mkdirSync(path.join(testsAbs, 'nested'));
fs.writeFileSync(path.join(testsAbs, 'math_test.ot'), 'total is 2 + 2\nif total is not 4\n    fail with "Math is broken."\n.\nsay "math ok"\n');
fs.writeFileSync(path.join(testsAbs, 'nested', 'test_scores.ot'), 'score is 90\nsay "checking score"\nif score is not 100\n    fail with "Expected 100 but got 90."\n.\n');
fs.writeFileSync(path.join(testsAbs, 'broken_test.ot'), 'say "unterminated\n');
fs.writeFileSync(path.join(testsAbs, 'helpers.ot'), 'say "not a test"\n');

await test('discovery matches the files `otter test` runs, in the same order', () => {
  const discovered = discoverTests(projectAbs).map(f => path.relative(projectAbs, f).split(path.sep).join('/'));
  const cli = otter(projectAbs, 'test', '.');
  // The first block of PASS/FAIL lines is one line per test run; the failure
  // details repeated after it are not.
  const resultBlock = cli.stdout.replace(/\r/g, '').split(/\n\s*\n/).find(block => /^(PASS|FAIL) /m.test(block)) || '';
  const ran = [...resultBlock.matchAll(/^(?:PASS|FAIL) (\S+?)(?: \(syntax error\))?$/gm)].map(m => m[1]);
  assert.deepEqual(discovered, ran, `CLI output:\n${cli.stdout}`);
  assert.equal(discovered.length, 4);
  assert.ok(!discovered.some(f => f.endsWith('helpers.ot')));
});

console.log('\nRunning tests through the server:');

const port = 6900 + (process.pid % 500);
const baseUrl = `http://127.0.0.1:${port}`;
const server = spawn(process.execPath, ['serve.mjs'], { cwd: studioRoot, env: { ...process.env, OTTER_STUDIO_PORT: String(port) }, stdio: 'ignore' });
process.on('exit', () => server.kill());
for (let attempt = 0; ; attempt++) {
  try { if ((await fetch(`${baseUrl}/`)).ok) break; } catch {}
  // 15 s: a cold Node start on Windows after the launch tests can take several seconds.
  if (attempt > 150) throw new Error('Studio server did not start');
  await new Promise(r => setTimeout(r, 100));
}
const run = async testPath => {
  const res = await fetch(`${baseUrl}/api/tests/run`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ folder: projectRel, path: testPath }) });
  return { status: res.status, ...(await res.json()) };
};

try {
  await test('the list endpoint returns workspace paths and project-relative names', async () => {
    const data = await (await fetch(`${baseUrl}/api/tests/list?folder=${encodeURIComponent(projectRel)}`)).json();
    assert.deepEqual(data.tests.map(t => t.name), ['tests/app_test.ot', 'tests/broken_test.ot', 'tests/math_test.ot', 'tests/nested/test_scores.ot']);
    assert.equal(data.tests[0].path, `${projectRel}/tests/app_test.ot`);
  });

  await test('a passing test passes, with its output and a duration', async () => {
    const r = await run(`${projectRel}/tests/math_test.ot`);
    assert.equal(r.status, 'passed', r.output);
    assert.equal(r.exitCode, 0);
    assert.ok(r.durationMs > 0);
    assert.match(r.output, /PASS/);
  });

  await test('a failing test reports `fail with` message and line', async () => {
    const r = await run(`${projectRel}/tests/nested/test_scores.ot`);
    assert.equal(r.status, 'failed');
    assert.equal(r.message, 'Expected 100 but got 90.');
    assert.equal(r.line, 4);
  });

  await test('an unparsable test is reported as such, with its line', async () => {
    const r = await run(`${projectRel}/tests/broken_test.ot`);
    assert.equal(r.status, 'error');
    assert.equal(r.exitCode, 2);
    assert.equal(r.line, 1);
  });

  await test('only discovered tests can be run', async () => {
    assert.equal((await run(`${projectRel}/tests/helpers.ot`)).status, 400);
    assert.equal((await run(`${projectRel}/main.ot`)).status, 400);
    assert.equal((await run('otter.ps1')).status, 400);
  });
} finally {
  server.kill();
}

console.log(`\nTest Explorer tests passed: ${passed}.`);
