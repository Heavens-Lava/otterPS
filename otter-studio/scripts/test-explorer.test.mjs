// test-explorer.test.mjs - End-to-end certification for Otter Studio Test Explorer
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const PORT = Number(process.env.OTTER_STUDIO_PORT || 4200);
const BASE_URL = `http://127.0.0.1:${PORT}`;

async function api(pathname, body, method = 'POST') {
  const res = await fetch(`${BASE_URL}${pathname}`, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await res.json().catch(() => ({}));
  return { status: res.status, data };
}

const TEST_PROJECT_NAME = 'test-explorer-app';

try {
  console.log('=== Running Otter Studio Test Explorer Certification Suite ===\n');

  // --- 1. Create Test Project ---
  console.log('--- 1. Create Test Project with Test Suites ---');
  const createRes = await api('/api/create-project', {
    name: TEST_PROJECT_NAME,
    archetype: 'console',
    target: 'console',
    code: 'say "Test Explorer App"\n'
  });
  assert.equal(createRes.status, 200);
  assert.equal(createRes.data.ok, true);
  const projectFolder = createRes.data.folder;
  const projectDir = path.join(REPO_ROOT, projectFolder);
  console.log(`  ✓ Project created on disk at ${projectFolder}`);

  // Create tests directory
  const testsDir = path.join(projectDir, 'tests');
  fs.mkdirSync(testsDir, { recursive: true });

  // Test File 1: math_test.ot
  fs.writeFileSync(path.join(testsDir, 'math_test.ot'), `# Math Operations Test Suite
score is 10
add 5 to score
if score is not 15
    say "FAIL: Expected 15"
.
say "PASS"
`, 'utf8');

  // Test File 2: strings_test.ot
  fs.writeFileSync(path.join(testsDir, 'strings_test.ot'), `# String Handling Test Suite
greeting is "Hello, Otter!"
if greeting is not "Hello, Otter!"
    say "FAIL: Expected Hello, Otter!"
.
say "PASS"
`, 'utf8');

  console.log('  ✓ Created 2 test suites: tests/math_test.ot and tests/strings_test.ot');

  // --- 2. Test Discovery API ---
  console.log('\n--- 2. Discover Tests via GET /api/tests/discover ---');
  const discoverRes = await api(`/api/tests/discover?folder=${encodeURIComponent(projectFolder)}`, null, 'GET');
  assert.equal(discoverRes.status, 200);
  assert.equal(discoverRes.data.ok, true);
  assert.equal(discoverRes.data.count, 2);
  assert.ok(discoverRes.data.tests.some(t => t.name === 'math_test.ot'));
  assert.ok(discoverRes.data.tests.some(t => t.name === 'strings_test.ot'));
  console.log(`  ✓ Discovered ${discoverRes.data.count} test files with suite metadata`);

  // --- 3. Run All Tests API ---
  console.log('\n--- 3. Run All Tests via POST /api/tests/run ---');
  const runAllRes = await api('/api/tests/run', {
    folder: projectFolder
  });
  assert.equal(runAllRes.status, 200);
  assert.equal(runAllRes.data.ok, true);
  assert.equal(runAllRes.data.total, 2);
  assert.equal(runAllRes.data.passed, 2);
  assert.equal(runAllRes.data.failed, 0);
  assert.equal(runAllRes.data.results.length, 2);
  console.log('  ✓ Ran all project tests: 2 passed, 0 failed');

  // --- 4. Run Selected Test API ---
  console.log('\n--- 4. Run Single Selected Test ---');
  const runSingleRes = await api('/api/tests/run', {
    folder: projectFolder,
    file: 'tests/math_test.ot'
  });
  assert.equal(runSingleRes.status, 200);
  assert.equal(runSingleRes.data.ok, true);
  assert.equal(runSingleRes.data.total, 1);
  assert.equal(runSingleRes.data.passed, 1);
  assert.equal(runSingleRes.data.failed, 0);
  assert.equal(runSingleRes.data.results[0].file, 'tests/math_test.ot');
  console.log('  ✓ Ran selected test file: 1 passed, 0 failed');

  // --- 5. Failure Detection & Reporting ---
  console.log('\n--- 5. Detect and Report Failing Tests ---');
  fs.writeFileSync(path.join(testsDir, 'syntax_error_test.ot'), `# Malformed Test
broken statement invalid tokens !@#$%
`, 'utf8');

  const runWithFailureRes = await api('/api/tests/run', {
    folder: projectFolder
  });
  assert.equal(runWithFailureRes.status, 200);
  assert.equal(runWithFailureRes.data.ok, false);
  assert.equal(runWithFailureRes.data.total, 3);
  assert.equal(runWithFailureRes.data.passed, 2);
  assert.equal(runWithFailureRes.data.failed, 1);
  assert.ok(runWithFailureRes.data.results.some(r => r.status === 'fail'));
  console.log('  ✓ Correctly detected and isolated failing test: 2 passed, 1 failed');

  console.log('\n========================================');
  console.log('Test Explorer Certification: All tests passed cleanly!');
} finally {
  const pDir = path.join(REPO_ROOT, 'projects', TEST_PROJECT_NAME);
  if (fs.existsSync(pDir)) {
    fs.rmSync(pDir, { recursive: true, force: true });
  }
}
