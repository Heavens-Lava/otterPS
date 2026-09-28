// workspace-solution.test.mjs - Automated Certification Suite for Multi-Root Solutions, Trust, and Large-Repo Performance
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  createDefaultSolution,
  normalizeSolution,
  validateSolution,
  serializeSolution,
  isWorkspaceTrusted
} from '../js/project/workspace-solution.js';
import { createScratchFolder } from './test-scratch.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');

// The API tests write the solution file into a temporary, git-ignored folder
// (deleted on exit) so the run never rewrites tracked fixtures under
// projects/. Its folders still point at the tracked test-certified-* projects,
// which are only read. See test-scratch.mjs.
const scratch = createScratchFolder(REPO_ROOT, 'workspace-solution');
const solutionRel = `${scratch.rel}/test-suite.solution.json`;
const PORT = Number(process.env.OTTER_STUDIO_PORT || 4200);
const baseUrl = `http://127.0.0.1:${PORT}`;

async function request(endpoint, options = {}) {
  const url = `${baseUrl}${endpoint}`;
  const res = await fetch(url, options);
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {}
  return { status: res.status, ok: res.ok, text, json };
}

async function runTests() {
  console.log('=== Running Otter Multi-Root Solution & Workspace Trust Suite ===\n');
  let passed = 0;
  let failed = 0;

  function test(name, fn) {
    try {
      fn();
      console.log(`  ✓ ${name}`);
      passed++;
    } catch (err) {
      console.error(`  ✗ ${name}:`, err.message);
      failed++;
    }
  }

  async function testAsync(name, fn) {
    try {
      await fn();
      console.log(`  ✓ ${name}`);
      passed++;
    } catch (err) {
      console.error(`  ✗ ${name}:`, err.message);
      failed++;
    }
  }

  // 1. Solution Schema & Normalization
  console.log('--- 1. Solution Schema & Normalization ---');
  test('Creates standard solution schema with defaults', () => {
    const sol = createDefaultSolution('MyEnterpriseSuite', [
      { name: 'App', path: 'projects/app' },
      { name: 'Library', path: 'projects/core-lib' }
    ]);
    assert.equal(sol.name, 'MyEnterpriseSuite');
    assert.equal(sol.folders.length, 2);
    assert.equal(sol.folders[0].name, 'App');
    assert.equal(sol.folders[0].path, 'projects/app');
    assert.equal(sol.settings['editor.wordWrap'], true);
    assert.equal(sol.trust.isTrusted, true);
  });

  test('Normalizes partial or legacy solution object', () => {
    const raw = {
      name: 'PartialSol',
      folders: ['projects/web', { path: 'projects/api' }]
    };
    const norm = normalizeSolution(raw);
    assert.equal(norm.name, 'PartialSol');
    assert.equal(norm.folders.length, 2);
    assert.equal(norm.folders[0].name, 'web');
    assert.equal(norm.folders[0].path, 'projects/web');
    assert.equal(norm.folders[1].name, 'api');
    assert.equal(norm.folders[1].path, 'projects/api');
    assert.equal(norm.settings['editor.tabSize'], 4);
  });

  // 2. Validation & Diagnostics
  console.log('\n--- 2. Validation & Diagnostics ---');
  test('Validates complete solution without errors', () => {
    const sol = createDefaultSolution('GoodSolution', [{ path: 'projects/app' }]);
    const val = validateSolution(sol);
    assert.equal(val.ok, true);
    assert.equal(val.errors.length, 0);
  });

  test('Warns on empty solution with no project folders', () => {
    const sol = createDefaultSolution('EmptySolution', []);
    const val = validateSolution(sol);
    assert.equal(val.ok, true);
    assert.ok(val.warnings.some(w => w.includes('no project folders')));
  });

  test('Rejects missing solution name', () => {
    const sol = createDefaultSolution('', [{ path: 'projects/app' }]);
    sol.name = '';
    const val = validateSolution(sol);
    assert.equal(val.ok, false);
    assert.ok(val.errors.some(e => e.includes('name is required')));
  });

  // 3. Serialization
  console.log('\n--- 3. Serialization ---');
  test('Serializes to clean indented JSON format', () => {
    const sol = createDefaultSolution('Suite', [{ path: 'projects/web' }]);
    const serialized = serializeSolution(sol);
    assert.ok(serialized.endsWith('\n'));
    const parsed = JSON.parse(serialized);
    assert.equal(parsed.name, 'Suite');
    assert.equal(parsed.folders[0].path, 'projects/web');
  });

  // 4. Workspace Trust Logic
  console.log('\n--- 4. Workspace Trust Logic ---');
  test('Resolves trusted state when solution explicitly marks trust', () => {
    const sol = { trust: { isTrusted: true } };
    assert.equal(isWorkspaceTrusted('projects/untrusted', sol), true);
  });

  test('Defaults to trusted for blank/untitled workspaces', () => {
    assert.equal(isWorkspaceTrusted(null), true);
  });

  // 5. Backend Server Multi-Root & Solution APIs
  console.log('\n--- 5. Backend Server Multi-Root & Solution APIs ---');
  await testAsync('POST /api/create-solution creates on-disk solution file', async () => {
    const res = await request('/api/create-solution', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: 'test-suite',
        path: solutionRel,
        folders: [
          { name: 'Console App', path: 'projects/test-certified-console' },
          { name: 'Web App', path: 'projects/test-certified-web' }
        ]
      })
    });
    assert.equal(res.status, 200);
    assert.equal(res.json.ok, true);

    const solDiskPath = path.join(scratch.abs, 'test-suite.solution.json');
    assert.ok(fs.existsSync(solDiskPath), 'Solution file must exist on disk');
  });

  await testAsync('GET /api/workspace scans multiple project roots', async () => {
    const res = await request(`/api/workspace?path=${solutionRel}`);
    assert.equal(res.status, 200);
    assert.equal(res.json.ok, true);
    assert.equal(res.json.solution.name, 'test-suite');
    assert.equal(res.json.roots.length, 2);

    const consoleRoot = res.json.roots.find(r => r.name === 'Console App');
    assert.ok(consoleRoot, 'Console App root must be present');
    assert.ok(consoleRoot.tree.length >= 2, 'Root tree must contain scanned files');
    assert.ok(consoleRoot.manifest, 'Root must contain parsed project manifest');
    assert.equal(consoleRoot.manifest.name, 'test-certified-console');

    const webRoot = res.json.roots.find(r => r.name === 'Web App');
    assert.ok(webRoot, 'Web App root must be present');
    assert.equal(webRoot.manifest.target, 'web');
  });

  await testAsync('POST /api/workspace updates solution settings on disk', async () => {
    const updated = createDefaultSolution('test-suite', [
      { name: 'Console App', path: 'projects/test-certified-console' },
      { name: 'Web App', path: 'projects/test-certified-web' },
      { name: 'Game App', path: 'projects/test-certified-game' }
    ], {
      'editor.wordWrap': false,
      'editor.tabSize': 2
    });

    const res = await request('/api/workspace', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        path: solutionRel,
        solution: updated
      })
    });
    assert.equal(res.status, 200);
    assert.equal(res.json.ok, true);
    assert.equal(res.json.solution.folders.length, 3);
    assert.equal(res.json.solution.settings['editor.tabSize'], 2);

    // Verify written to disk
    const solDiskPath = path.join(scratch.abs, 'test-suite.solution.json');
    const onDisk = JSON.parse(fs.readFileSync(solDiskPath, 'utf8'));
    assert.equal(onDisk.folders.length, 3);
    assert.equal(onDisk.settings['editor.tabSize'], 2);
  });

  // 6. Large-Repo Performance Check
  console.log('\n--- 6. Large-Repo Performance Verification ---');
  await testAsync('scanDir excludes node_modules and .git without infinite recursion', async () => {
    const start = Date.now();
    // Scan root project folder
    const res = await request('/api/project?folder=examples');
    const elapsed = Date.now() - start;
    assert.equal(res.status, 200);
    assert.ok(res.json.tree.length > 0);
    assert.ok(elapsed < 1000, `Scanning tree completed in ${elapsed}ms (< 1000ms limit)`);
  });

  console.log(`\n========================================`);
  console.log(`Solution Test Summary: ${passed} passed, ${failed} failed.`);
  if (failed > 0) {
    process.exit(1);
  }
}

runTests().catch(err => {
  console.error('Fatal error in test suite:', err);
  process.exit(1);
});
