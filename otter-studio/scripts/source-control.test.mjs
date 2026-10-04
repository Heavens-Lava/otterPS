// source-control.test.mjs - End-to-end certification for Otter Studio Source-Control Integration
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
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

const TEST_GIT_PROJECT = 'test-git-sc-app';
const TEST_PROJECT_DIR = path.join(REPO_ROOT, 'projects', TEST_GIT_PROJECT);

try {
  console.log('=== Running Otter Studio Source-Control Integration Certification Suite ===\n');

  // Clean any previous test debris
  if (fs.existsSync(TEST_PROJECT_DIR)) {
    fs.rmSync(TEST_PROJECT_DIR, { recursive: true, force: true });
  }

  // --- 1. Main Workspace Git Status ---
  console.log('--- 1. Main Workspace Repository Detection & Status ---');
  const mainStatusRes = await api('/api/git/status', null, 'GET');
  assert.equal(mainStatusRes.status, 200);
  assert.equal(mainStatusRes.data.isRepo, true, 'Main workspace must be recognized as Git repo');
  assert.ok(mainStatusRes.data.branch, 'Branch must be present');
  console.log(`  ✓ Main repository detected on branch "${mainStatusRes.data.branch}"`);

  // --- 2. Git Log / History API ---
  console.log('\n--- 2. Inspect Git Commit History ---');
  const logRes = await api('/api/git/log?limit=5', null, 'GET');
  assert.equal(logRes.status, 200);
  assert.equal(logRes.data.ok, true);
  assert.ok(logRes.data.commits.length > 0, 'Commit history must not be empty');
  assert.ok(logRes.data.commits[0].hash, 'Commit must have hash');
  assert.ok(logRes.data.commits[0].message, 'Commit must have message');
  console.log(`  ✓ Retrieved latest commit: ${logRes.data.commits[0].hash.slice(0, 7)} - "${logRes.data.commits[0].message}"`);

  // --- 3. Branches API ---
  console.log('\n--- 3. Inspect Branches ---');
  const branchesRes = await api('/api/git/branches', null, 'GET');
  assert.equal(branchesRes.status, 200);
  assert.equal(branchesRes.data.ok, true);
  assert.ok(branchesRes.data.current, 'Current branch must exist');
  assert.ok(branchesRes.data.branches.length > 0);
  console.log(`  ✓ Branches listed with active branch "${branchesRes.data.current}"`);

  // --- 4. Isolated Git Project Workflow (Init, Stage, Diff, Unstage, Commit) ---
  console.log('\n--- 4. Isolated Project Git Lifecycle ---');
  fs.mkdirSync(TEST_PROJECT_DIR, { recursive: true });
  await execFileAsync('git', ['init'], { cwd: TEST_PROJECT_DIR });
  await execFileAsync('git', ['config', 'user.name', 'Otter Studio Test'], { cwd: TEST_PROJECT_DIR });
  await execFileAsync('git', ['config', 'user.email', 'test@otter-lang.org'], { cwd: TEST_PROJECT_DIR });

  const relProjectFolder = `projects/${TEST_GIT_PROJECT}`;
  fs.writeFileSync(path.join(TEST_PROJECT_DIR, 'app.ot'), 'say "Hello Git"\n', 'utf8');

  // Check status (untracked)
  const projStatus1 = await api(`/api/git/status?folder=${encodeURIComponent(relProjectFolder)}`, null, 'GET');
  assert.equal(projStatus1.status, 200);
  assert.equal(projStatus1.data.isRepo, true);
  assert.ok(projStatus1.data.untracked.includes('app.ot'));
  console.log('  ✓ app.ot detected as untracked in new project');

  // Stage app.ot
  const stageRes = await api('/api/git/stage', {
    folder: relProjectFolder,
    path: 'app.ot'
  });
  assert.equal(stageRes.status, 200);
  assert.equal(stageRes.data.ok, true);

  const projStatus2 = await api(`/api/git/status?folder=${encodeURIComponent(relProjectFolder)}`, null, 'GET');
  assert.ok(projStatus2.data.staged.some(s => s.file === 'app.ot'));
  console.log('  ✓ app.ot staged successfully');

  // Query Staged Diff
  const diffRes = await api(`/api/git/diff?folder=${encodeURIComponent(relProjectFolder)}&staged=true`, null, 'GET');
  assert.equal(diffRes.status, 200);
  assert.equal(diffRes.data.ok, true);
  assert.match(diffRes.data.diff, /\+say "Hello Git"/);
  console.log('  ✓ Staged diff accurately displays file changes');

  // Unstage app.ot
  const unstageRes = await api('/api/git/unstage', {
    folder: relProjectFolder,
    path: 'app.ot'
  });
  assert.equal(unstageRes.status, 200);
  assert.equal(unstageRes.data.ok, true);

  const projStatus3 = await api(`/api/git/status?folder=${encodeURIComponent(relProjectFolder)}`, null, 'GET');
  assert.ok(!projStatus3.data.staged.some(s => s.file === 'app.ot'));
  console.log('  ✓ app.ot unstaged cleanly');

  // Stage again and Commit
  await api('/api/git/stage', { folder: relProjectFolder, path: 'app.ot' });
  const commitRes = await api('/api/git/commit', {
    folder: relProjectFolder,
    message: 'Initial project commit via Otter Studio'
  });
  assert.equal(commitRes.status, 200);
  assert.equal(commitRes.data.ok, true);
  assert.ok(commitRes.data.commitHash);
  console.log(`  ✓ Committed successfully: ${commitRes.data.commitHash.slice(0, 7)}`);

  // Query project log
  const projLogRes = await api(`/api/git/log?folder=${encodeURIComponent(relProjectFolder)}&limit=1`, null, 'GET');
  assert.equal(projLogRes.status, 200);
  assert.equal(projLogRes.data.commits[0].message, 'Initial project commit via Otter Studio');
  console.log('  ✓ Project commit log verified on disk');

  console.log('\n========================================');
  console.log('Source-Control Integration Certification: All tests passed cleanly!');
} finally {
  if (fs.existsSync(TEST_PROJECT_DIR)) {
    fs.rmSync(TEST_PROJECT_DIR, { recursive: true, force: true });
  }
}
