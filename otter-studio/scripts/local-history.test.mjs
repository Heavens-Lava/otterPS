// Local History (server/local-history.mjs): a version on every save, kept
// outside the workspace, following renames, capped per file.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createScratchFolder } from './test-scratch.mjs';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(studioRoot, '..');
const scratch = createScratchFolder(repoRoot, 'local-history');
const historyDir = process.env.OTTER_STUDIO_HISTORY_DIR; // set by createScratchFolder
assert.ok(historyDir.startsWith(scratch.abs), 'tests never write to the real history');
const port = 4900 + (process.pid % 90);
const base = `http://127.0.0.1:${port}`;
const server = spawn(process.execPath, ['serve.mjs'], {
  cwd: studioRoot,
  env: { ...process.env, OTTER_STUDIO_PORT: String(port), OTTER_STUDIO_TRASH_DIR: path.join(scratch.abs, '.trash') },
  stdio: 'ignore'
});
process.on('exit', () => server.kill());
for (let attempt = 0; ; attempt++) {
  try { if ((await fetch(`${base}/`)).ok) break; } catch {}
  if (attempt > 150) throw new Error('Studio server did not start');
  await new Promise(r => setTimeout(r, 100));
}

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`  ✓ ${name}`);
}
const getJson = async (url) => { const r = await fetch(base + url); return { status: r.status, ...(await r.json()) }; };
const postJson = async (url, body) => {
  const r = await fetch(base + url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  return { status: r.status, ...(await r.json()) };
};
const file = `${scratch.rel}/notes.ot`;
async function save(content) {
  const current = await getJson(`/api/file?path=${encodeURIComponent(file)}`);
  return postJson('/api/file', { path: file, content, expectedRevision: current.revision });
}
const list = async (p = file) => (await getJson(`/api/history/list?path=${encodeURIComponent(p)}`)).entries;

console.log('Local History:');
try {
  await test('each save keeps a version; the text before the first save too', async () => {
    fs.writeFileSync(path.join(scratch.abs, 'notes.ot'), 'say "made outside"\n');
    assert.equal((await save('say "one"\n')).ok, true);
    assert.equal((await save('say "two"\n')).ok, true);
    const entries = await list();
    assert.deepEqual(entries.map(e => e.reason), ['save', 'save', 'before save'], 'newest first');
    const oldest = await getJson(`/api/history/entry?path=${encodeURIComponent(file)}&id=${entries[2].id}`);
    assert.equal(oldest.content, 'say "made outside"\n');
    const middle = await getJson(`/api/history/entry?path=${encodeURIComponent(file)}&id=${entries[1].id}`);
    assert.equal(middle.content, 'say "one"\n');
  });

  await test('saving the same text again adds nothing', async () => {
    const before = (await list()).length;
    await save('say "two"\n');
    assert.equal((await list()).length, before);
  });

  await test('stored outside the workspace', async () => {
    assert.ok(fs.readdirSync(historyDir).length >= 1);
    assert.equal(fs.readdirSync(scratch.abs).filter(n => !n.startsWith('.')).join(','), 'notes.ot', 'nothing next to the file');
  });

  await test('a renamed file keeps its history; a deleted file leaves its last text', async () => {
    const count = (await list()).length;
    const r = await postJson('/api/fs/rename', { path: file, name: 'renamed.ot' });
    assert.equal(r.ok, true);
    const moved = `${scratch.rel}/renamed.ot`;
    assert.equal((await list(moved)).length, count);
    assert.equal((await list(file)).length, 0);
    fs.writeFileSync(path.join(scratch.abs, 'renamed.ot'), 'say "last words"\n');
    assert.equal((await postJson('/api/fs/delete', { path: moved })).ok, true);
    const after = await list(moved);
    assert.equal(after[0].reason, 'before delete');
    assert.equal((await getJson(`/api/history/entry?path=${encodeURIComponent(moved)}&id=${after[0].id}`)).content, 'say "last words"\n');
  });

  await test('outside the workspace and bad ids are refused', async () => {
    assert.equal((await getJson('/api/history/list?path=../elsewhere.ot')).status, 403);
    assert.equal((await getJson(`/api/history/entry?path=${encodeURIComponent(file)}&id=../../x`)).status, 404);
  });

  await test('at most 50 versions per file, oldest dropped', async () => {
    const { recordVersion, listVersions, MAX_ENTRIES } = await import('../server/local-history.mjs');
    const abs = path.join(scratch.abs, 'many.ot');
    for (let i = 0; i < MAX_ENTRIES + 5; i++) recordVersion(abs, `${scratch.rel}/many.ot`, `v${i}`);
    const entries = listVersions(abs);
    assert.equal(entries.length, MAX_ENTRIES);
    const key = fs.readdirSync(historyDir).find(d => fs.readFileSync(path.join(historyDir, d, 'index.json'), 'utf8').includes('many.ot'));
    assert.equal(fs.readdirSync(path.join(historyDir, key)).filter(n => n.endsWith('.txt')).length, MAX_ENTRIES, 'old copies deleted');
  });

  await test('relative times', async () => {
    const { formatWhen } = await import('../js/components/local-history.js');
    const now = Date.UTC(2026, 0, 10, 12);
    assert.equal(formatWhen(now - 10_000, now), 'just now');
    assert.equal(formatWhen(now - 60_000, now), '1 minute ago');
    assert.equal(formatWhen(now - 3 * 3600_000, now), '3 hours ago');
    assert.equal(formatWhen(now - 2 * 86400_000, now), '2 days ago');
  });
} finally {
  server.kill();
}
console.log(`\nLocal History tests passed: ${passed}.`);
