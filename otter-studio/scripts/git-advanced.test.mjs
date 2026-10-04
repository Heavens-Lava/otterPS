// git-advanced.test.mjs - End-to-end certification for Section 22: Git and Source Control
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

const TEST_DIR_NAME = `test-git-adv-${Date.now()}`;
const TEST_PROJECT_DIR = path.join(REPO_ROOT, 'projects', TEST_DIR_NAME);
const REMOTE_BARE_DIR = path.join(REPO_ROOT, 'projects', `${TEST_DIR_NAME}-remote.git`);
const relFolder = `projects/${TEST_DIR_NAME}`;

async function cleanup() {
  for (const d of [TEST_PROJECT_DIR, REMOTE_BARE_DIR]) {
    if (fs.existsSync(d)) {
      try {
        fs.rmSync(d, { recursive: true, force: true });
      } catch (err) {
        // ignore Windows file locks in cleanup
      }
    }
  }
}

try {
  console.log('=== Running Section 22: Git & Source Control Certification Suite ===\n');
  await cleanup();

  // Initialize test git project
  fs.mkdirSync(TEST_PROJECT_DIR, { recursive: true });
  await execFileAsync('git', ['init', '-b', 'main'], { cwd: TEST_PROJECT_DIR });
  await execFileAsync('git', ['config', 'user.name', 'Otter Advanced Git Test'], { cwd: TEST_PROJECT_DIR });
  await execFileAsync('git', ['config', 'user.email', 'git-test@otter-lang.org'], { cwd: TEST_PROJECT_DIR });

  // --- Test 1: SCM Extension API Providers ---
  console.log('--- 1. SCM Extension API Provider Registry ---');
  const providersRes = await api('/api/scm/providers', null, 'GET');
  assert.equal(providersRes.status, 200);
  assert.equal(providersRes.data.ok, true);
  assert.ok(Array.isArray(providersRes.data.providers));
  const gitProv = providersRes.data.providers.find(p => p.id === 'git');
  assert.ok(gitProv, 'Git provider must be registered');
  assert.equal(gitProv.capabilities.conflictResolution, true);
  assert.equal(gitProv.capabilities.blame, true);
  assert.equal(gitProv.capabilities.stashing, true);
  console.log('  ✓ SCM Extension API exposed with capabilities');

  // --- Test 2: Initial Commit & Status ---
  console.log('\n--- 2. Initial Commit & Status Verification ---');
  fs.writeFileSync(path.join(TEST_PROJECT_DIR, 'hello.ot'), 'say "Initial Otter"\n', 'utf8');
  await api('/api/git/stage', { folder: relFolder, path: 'hello.ot' });
  const commitRes = await api('/api/git/commit', { folder: relFolder, message: 'feat: initial commit' });
  assert.equal(commitRes.status, 200);
  assert.ok(commitRes.data.commitHash);

  const status1 = await api(`/api/git/status?folder=${encodeURIComponent(relFolder)}`, null, 'GET');
  assert.equal(status1.status, 200);
  assert.equal(status1.data.branch, 'main');
  assert.equal(status1.data.clean, true);
  console.log('  ✓ Initial commit created; tree is clean');

  // --- Test 3: Branch Management (create, list, checkout, delete) ---
  console.log('\n--- 3. Branch Management ---');
  const createBranchRes = await api('/api/git/branches', { folder: relFolder, action: 'create', name: 'feature/login' });
  assert.equal(createBranchRes.status, 200);
  assert.equal(createBranchRes.data.ok, true);

  const branchListRes = await api(`/api/git/branches?folder=${encodeURIComponent(relFolder)}`, null, 'GET');
  assert.equal(branchListRes.status, 200);
  assert.ok(branchListRes.data.branches.some(b => b.name === 'feature/login'));
  console.log('  ✓ Branch feature/login created and listed');

  const checkoutRes = await api('/api/git/branches', { folder: relFolder, action: 'checkout', name: 'feature/login' });
  assert.equal(checkoutRes.status, 200);

  const statusAfterCheckout = await api(`/api/git/status?folder=${encodeURIComponent(relFolder)}`, null, 'GET');
  assert.equal(statusAfterCheckout.data.branch, 'feature/login');
  console.log('  ✓ Switched to branch feature/login');

  // --- Test 4: Blame API ---
  console.log('\n--- 4. Blame Engine ---');
  fs.writeFileSync(path.join(TEST_PROJECT_DIR, 'hello.ot'), 'say "Initial Otter"\nsay "Second Line"\n', 'utf8');
  await api('/api/git/stage', { folder: relFolder, path: 'hello.ot' });
  await api('/api/git/commit', { folder: relFolder, message: 'chore: add line 2' });

  const blameRes = await api(`/api/git/blame?folder=${encodeURIComponent(relFolder)}&path=hello.ot`, null, 'GET');
  assert.equal(blameRes.status, 200);
  assert.equal(blameRes.data.ok, true);
  assert.equal(blameRes.data.blame.length, 2);
  assert.equal(blameRes.data.blame[0].author, 'Otter Advanced Git Test');
  assert.match(blameRes.data.blame[0].content, /say "Initial Otter"/);
  assert.match(blameRes.data.blame[1].content, /say "Second Line"/);
  console.log('  ✓ Blame lines parsed with commit hash, author, and line contents');

  // --- Test 5: Stash (push, list, pop) ---
  console.log('\n--- 5. Stash Management ---');
  fs.writeFileSync(path.join(TEST_PROJECT_DIR, 'scratch.ot'), '# WIP scratch file\n', 'utf8');
  const stashPushRes = await api('/api/git/stash', { folder: relFolder, action: 'push', message: 'WIP before switch' });
  assert.equal(stashPushRes.status, 200);

  const stashListRes = await api(`/api/git/stash?folder=${encodeURIComponent(relFolder)}`, null, 'GET');
  assert.equal(stashListRes.status, 200);
  assert.ok(stashListRes.data.stashes.length > 0);
  assert.match(stashListRes.data.stashes[0].message, /WIP before switch/);
  console.log('  ✓ Stashed WIP changes successfully');

  const stashPopRes = await api('/api/git/stash', { folder: relFolder, action: 'pop', index: 0 });
  assert.equal(stashPopRes.status, 200);
  assert.ok(fs.existsSync(path.join(TEST_PROJECT_DIR, 'scratch.ot')));
  fs.unlinkSync(path.join(TEST_PROJECT_DIR, 'scratch.ot'));
  console.log('  ✓ Popped stash and restored WIP file');

  // --- Test 6: Tags (create, list, delete) ---
  console.log('\n--- 6. Tags Management ---');
  const createTagRes = await api('/api/git/tags', { folder: relFolder, action: 'create', name: 'v1.0.0', message: 'Release 1.0.0' });
  assert.equal(createTagRes.status, 200);

  const listTagsRes = await api(`/api/git/tags?folder=${encodeURIComponent(relFolder)}`, null, 'GET');
  assert.equal(listTagsRes.status, 200);
  assert.ok(listTagsRes.data.tags.some(t => t.name === 'v1.0.0'));
  console.log('  ✓ Tag v1.0.0 created and listed');

  const deleteTagRes = await api('/api/git/tags', { folder: relFolder, action: 'delete', name: 'v1.0.0' });
  assert.equal(deleteTagRes.status, 200);
  const listTagsRes2 = await api(`/api/git/tags?folder=${encodeURIComponent(relFolder)}`, null, 'GET');
  assert.ok(!listTagsRes2.data.tags.some(t => t.name === 'v1.0.0'));
  console.log('  ✓ Tag v1.0.0 deleted successfully');

  // --- Test 7: Remotes and Authentication Management ---
  console.log('\n--- 7. Remotes and Authentication Management ---');
  fs.mkdirSync(REMOTE_BARE_DIR, { recursive: true });
  await execFileAsync('git', ['init', '--bare'], { cwd: REMOTE_BARE_DIR });

  const addRemoteRes = await api('/api/git/remotes', { folder: relFolder, action: 'add', name: 'origin', url: REMOTE_BARE_DIR });
  assert.equal(addRemoteRes.status, 200);

  const listRemotesRes = await api(`/api/git/remotes?folder=${encodeURIComponent(relFolder)}`, null, 'GET');
  assert.equal(listRemotesRes.status, 200);
  assert.ok(listRemotesRes.data.remotes.some(r => r.name === 'origin'));
  console.log('  ✓ Remote origin added and queried');

  // Test Auth token endpoint
  const authRes = await api('/api/git/auth', { host: 'github.com', token: 'otter_token_secret_123' });
  assert.equal(authRes.status, 200);
  assert.equal(authRes.data.configured, true);
  console.log('  ✓ Remote auth credentials configured');

  // --- Test 8: Push, Fetch, Pull ---
  console.log('\n--- 8. Remote Sync (Push, Fetch, Pull) ---');
  // Checkout main and push
  await api('/api/git/branches', { folder: relFolder, action: 'checkout', name: 'main' });
  const pushRes = await api('/api/git/push', { folder: relFolder, remote: 'origin', branch: 'main', setUpstream: true });
  assert.equal(pushRes.status, 200);
  console.log('  ✓ Pushed branch main to remote origin');

  const fetchRes = await api('/api/git/fetch', { folder: relFolder, remote: 'origin' });
  assert.equal(fetchRes.status, 200);
  console.log('  ✓ Fetched from remote origin');

  const pullRes = await api('/api/git/pull', { folder: relFolder, remote: 'origin', branch: 'main' });
  assert.equal(pullRes.status, 200);
  console.log('  ✓ Pulled updates from remote origin');

  // --- Test 9: Merge & Conflict Editor ---
  console.log('\n--- 9. Merge and Conflict Resolution ---');
  // Create conflict scenario:
  // Branch A: modify hello.ot line 1 to 'say "Branch A greeting"'
  await api('/api/git/branches', { folder: relFolder, action: 'create', name: 'branch-a', checkout: true });
  fs.writeFileSync(path.join(TEST_PROJECT_DIR, 'hello.ot'), 'say "Branch A greeting"\nsay "Second Line"\n', 'utf8');
  await api('/api/git/stage', { folder: relFolder, path: 'hello.ot' });
  await api('/api/git/commit', { folder: relFolder, message: 'commit on branch A' });

  // Branch B (from main): modify hello.ot line 1 to 'say "Branch B greeting"'
  await api('/api/git/branches', { folder: relFolder, action: 'checkout', name: 'main' });
  await api('/api/git/branches', { folder: relFolder, action: 'create', name: 'branch-b', checkout: true });
  fs.writeFileSync(path.join(TEST_PROJECT_DIR, 'hello.ot'), 'say "Branch B greeting"\nsay "Second Line"\n', 'utf8');
  await api('/api/git/stage', { folder: relFolder, path: 'hello.ot' });
  await api('/api/git/commit', { folder: relFolder, message: 'commit on branch B' });

  // Merge branch-a into branch-b -> triggers conflict
  const mergeRes = await api('/api/git/merge', { folder: relFolder, branch: 'branch-a' });
  assert.equal(mergeRes.data.conflict, true, 'Merge must detect conflict');
  console.log('  ✓ Merge detected conflict accurately');

  // Check conflicts API
  const conflictsRes = await api(`/api/git/conflicts?folder=${encodeURIComponent(relFolder)}&path=hello.ot`, null, 'GET');
  assert.equal(conflictsRes.status, 200);
  assert.equal(conflictsRes.data.hasConflicts, true);
  assert.equal(conflictsRes.data.conflictCount, 1);
  assert.match(conflictsRes.data.sections.find(s => s.type === 'conflict').current, /Branch B greeting/);
  assert.match(conflictsRes.data.sections.find(s => s.type === 'conflict').incoming, /Branch A greeting/);
  console.log('  ✓ Conflict editor parsed conflict markers with current/incoming segments');

  // Resolve conflict using strategy 'ours' (current)
  const resolveRes = await api('/api/git/conflicts', {
    folder: relFolder,
    path: 'hello.ot',
    strategy: 'ours'
  });
  assert.equal(resolveRes.status, 200);
  assert.equal(resolveRes.data.resolved, true);

  // Complete commit of resolved merge
  const resolvedCommitRes = await api('/api/git/commit', { folder: relFolder, message: 'merge: resolved conflict in hello.ot' });
  assert.equal(resolvedCommitRes.status, 200);
  console.log('  ✓ Conflict resolved and merge commit completed');

  // Final status check
  const finalStatus = await api(`/api/git/status?folder=${encodeURIComponent(relFolder)}`, null, 'GET');
  assert.equal(finalStatus.data.clean, true);
  console.log('  ✓ Working tree is clean following merge resolution');

  console.log('\n=== ALL SECTION 22 GIT TESTS PASSED SUCCESSFULLY ===');
} finally {
  await cleanup();
}
