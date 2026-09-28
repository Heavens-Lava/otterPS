// Explorer file management API (server/fs-ops.mjs): create, rename, move,
// delete to the trash, and everything that must be refused.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createScratchFolder } from './test-scratch.mjs';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(studioRoot, '..');
const scratch = createScratchFolder(repoRoot, 'explorer');
const trash = path.join(scratch.abs, '.trash');
const port = 4600 + (process.pid % 300);
const base = `http://127.0.0.1:${port}`;
const server = spawn(process.execPath, ['serve.mjs'], {
  cwd: studioRoot,
  env: { ...process.env, OTTER_STUDIO_PORT: String(port), OTTER_STUDIO_TRASH_DIR: trash },
  stdio: 'ignore'
});
process.on('exit', () => server.kill());
for (let attempt = 0; ; attempt++) {
  try { if ((await fetch(`${base}/`)).ok) break; } catch {}
  // 15 s: a cold Node start on Windows after the launch tests can take several seconds.
  if (attempt > 150) throw new Error('Studio server did not start');
  await new Promise(r => setTimeout(r, 100));
}

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`  ✓ ${name}`);
}
const post = async (route, body) => {
  const res = await fetch(`${base}/api/fs/${route}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  return { status: res.status, ...(await res.json()) };
};
const at = (...p) => path.join(scratch.abs, ...p);
const relOf = (...p) => [scratch.rel, ...p].join('/');

console.log('Explorer file management:');
try {
  await test('new file and new folder, never over an existing one', async () => {
    assert.equal((await post('new-folder', { folder: scratch.rel, name: 'src' })).ok, true);
    const made = await post('new-file', { folder: relOf('src'), name: 'main.ot', content: 'say 1\n' });
    assert.equal(made.path, relOf('src', 'main.ot'));
    assert.equal(fs.readFileSync(at('src', 'main.ot'), 'utf8'), 'say 1\n');
    assert.equal((await post('new-file', { folder: relOf('src'), name: 'main.ot' })).status, 409);
    assert.equal(fs.readFileSync(at('src', 'main.ot'), 'utf8'), 'say 1\n', 'not overwritten');
  });

  await test('invalid names are refused', async () => {
    for (const name of ['a/b.ot', '..', 'x:y', 'bad?.ot', 'trailing.']) {
      assert.equal((await post('new-file', { folder: scratch.rel, name })).status, 400, name);
    }
  });

  await test('rename a file and a folder; an existing name is a conflict', async () => {
    const r = await post('rename', { path: relOf('src', 'main.ot'), name: 'app.ot' });
    assert.equal(r.from, relOf('src', 'main.ot'));
    assert.equal(r.path, relOf('src', 'app.ot'));
    assert.ok(fs.existsSync(at('src', 'app.ot')));
    await post('new-file', { folder: relOf('src'), name: 'other.ot' });
    assert.equal((await post('rename', { path: relOf('src', 'other.ot'), name: 'app.ot' })).status, 409);
    assert.equal((await post('rename', { path: relOf('src'), name: 'code' })).path, relOf('code'));
  });

  await test('move into a folder; a folder cannot move into itself', async () => {
    await post('new-folder', { folder: scratch.rel, name: 'lib' });
    const m = await post('move', { path: relOf('code', 'other.ot'), folder: relOf('lib') });
    assert.equal(m.path, relOf('lib', 'other.ot'));
    assert.ok(fs.existsSync(at('lib', 'other.ot')));
    await post('new-folder', { folder: relOf('code'), name: 'inner' });
    assert.equal((await post('move', { path: relOf('code'), folder: relOf('code', 'inner') })).status, 400);
    assert.ok(fs.existsSync(at('code', 'app.ot')), 'nothing moved');
  });

  await test('delete goes to the trash, not away', async () => {
    const d = await post('delete', { path: relOf('lib', 'other.ot') });
    assert.equal(d.trashed, true);
    assert.equal(fs.existsSync(at('lib', 'other.ot')), false);
    assert.ok(fs.readdirSync(trash).some(n => n.endsWith('other.ot')), 'in the trash');
  });

  await test('outside the workspace, the root and .git are refused', async () => {
    assert.equal((await post('delete', { path: '../outside.ot' })).status, 403);
    assert.equal((await post('delete', { path: '.' })).status, 403);
    assert.equal((await post('rename', { path: '.git', name: 'x' })).status, 403);
    // .git is a folder in a clone and a file in a worktree: refused either way.
    assert.ok([400, 403].includes((await post('new-file', { folder: '.git', name: 'x' })).status));
    assert.equal(fs.existsSync(path.join(repoRoot, '.git', 'x')), false);
    assert.equal((await post('move', { path: relOf('code'), folder: '..' })).status, 403);
  });
} finally {
  server.kill();
}
console.log(`\nExplorer tests passed: ${passed}.`);
