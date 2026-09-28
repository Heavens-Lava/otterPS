// git.test.mjs - Source control (checklist §22), through the real git CLI.
//
// Unit tests cover the parsers, name checks, the Myers line diff and the
// conflict-marker resolver. The live part starts Studio's server and drives
// /api/git/* against a scratch repository with a local bare repository as
// its remote (file:// URL), so push/pull/fetch work offline: stage, commit,
// amend, branches, a real merge conflict resolved through the API, stash,
// tags, remotes, history, blame and file history.
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createScratchFolder } from './test-scratch.mjs';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(studioRoot, '..');
const load = rel => import(pathToFileURL(path.join(studioRoot, ...rel.split('/'))).href);
const { parseStatusV2, parseLog, parseBlamePorcelain, isValidRefName, isValidRemoteName, redactUrl } = await load('server/git.mjs');
const { diffLines, sideBySide, splitLines } = await load('js/scm/line-diff.js');
const { parseConflicts, resolveConflict } = await load('js/scm/conflicts.js');

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`  ✓ ${name}`);
}

console.log('Git parsers and helpers:');

await test('porcelain v2 status: branch, ahead/behind, staged, unstaged, renamed, conflict, untracked', () => {
  const text = [
    '# branch.oid 1234567890abcdef1234567890abcdef12345678',
    '# branch.head main',
    '# branch.upstream origin/main',
    '# branch.ab +2 -1',
    '1 M. N... 100644 100644 100644 aaa bbb src/app.ot',
    '1 .M N... 100644 100644 100644 aaa bbb my file.ot',
    '2 R. N... 100644 100644 100644 aaa bbb R100 new.ot', 'old.ot',
    'u UU N... 100644 100644 100644 100644 a b c conflict.ot',
    '? notes.txt',
    ''
  ].join('\0');
  const s = parseStatusV2(text);
  assert.equal(s.branch, 'main');
  assert.equal(s.upstream, 'origin/main');
  assert.equal(s.ahead, 2);
  assert.equal(s.behind, 1);
  const byPath = Object.fromEntries(s.files.map(f => [f.path, f]));
  assert.equal(byPath['src/app.ot'].staged, true);
  assert.equal(byPath['my file.ot'].unstaged, true, 'paths with spaces survive');
  assert.equal(byPath['new.ot'].from, 'old.ot');
  assert.equal(byPath['conflict.ot'].conflict, true);
  assert.equal(byPath['notes.txt'].untracked, true);
});

await test('log and blame parsers', () => {
  const log = parseLog(['abc123', 'abc', 'Ada', 'ada@example.com', '2026-01-01T00:00:00Z', 'p1 p2', 'HEAD -> main, tag: v1', 'Fix: the | pipes'].join('\x1f') + '\x1e');
  assert.equal(log[0].subject, 'Fix: the | pipes');
  assert.deepEqual(log[0].parents, ['p1', 'p2']);
  assert.deepEqual(log[0].refs, ['HEAD -> main', 'tag: v1']);
  const hash = 'a'.repeat(40);
  const blame = parseBlamePorcelain([`${hash} 1 1 2`, 'author Ada', 'author-time 1700000000', 'summary First', 'filename x.ot', '\tsay 1', `${hash} 2 2`, '\tsay 2', ''].join('\n'));
  assert.equal(blame.length, 2);
  assert.equal(blame[1].author, 'Ada', 'repeated commits reuse the header');
  assert.equal(blame[1].text, 'say 2');
});

await test('branch, tag and remote names are checked; secrets in URLs are hidden', () => {
  for (const good of ['main', 'feature/login', 'v1.0.0', 'fix-123']) assert.ok(isValidRefName(good), good);
  for (const bad of ['-rf', '--upload-pack=x', 'a..b', 'a b', 'a~1', 'x.lock', '.hidden', 'a//b', '', 'a:b']) assert.ok(!isValidRefName(bad), bad);
  assert.ok(isValidRemoteName('origin'));
  assert.ok(!isValidRemoteName('-x'));
  assert.equal(redactUrl('https://user:s3cret@github.com/o/r.git'), 'https://user:***@github.com/o/r.git');
});

await test('Myers line diff reproduces the modified text (fuzz, 300 cases)', () => {
  let seed = 7;
  const rand = n => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed % n; };
  for (let c = 0; c < 300; c++) {
    const words = ['a', 'b', 'c', 'd', 'e'];
    const a = Array.from({ length: rand(20) }, () => words[rand(5)]).join('\n');
    const b = Array.from({ length: rand(20) }, () => words[rand(5)]).join('\n');
    const ops = diffLines(a, b);
    assert.deepEqual(ops.filter(o => o.type !== 'delete').map(o => o.text), splitLines(b));
    assert.deepEqual(ops.filter(o => o.type !== 'insert').map(o => o.text), splitLines(a));
  }
  const rows = sideBySide(diffLines('x\ny\nz\n', 'x\nY\nz\n'));
  assert.deepEqual(rows.map(r => r.type), ['equal', 'change', 'equal']);
});

await test('conflict markers: parse, and resolve each block independently', () => {
  const text = 'top\n<<<<<<< HEAD\nours 1\n=======\ntheirs 1\n>>>>>>> feature\nmiddle\n<<<<<<< HEAD\nours 2\n||||||| base\nbase 2\n=======\ntheirs 2\n>>>>>>> feature\nend\n';
  const { blocks } = parseConflicts(text);
  assert.equal(blocks.length, 2);
  assert.deepEqual(blocks[1].base, ['base 2']);
  assert.equal(blocks[0].theirsLabel, 'feature');
  const once = resolveConflict(text, 0, 'theirs');
  const twice = resolveConflict(once, 0, 'both');
  assert.equal(twice, 'top\ntheirs 1\nmiddle\nours 2\ntheirs 2\nend\n');
});

console.log('\nLive server against a scratch repository:');

const scratch = createScratchFolder(repoRoot, 'git');
const git = (cwd, ...args) => execFileSync('git', args, { cwd, encoding: 'utf8', env: { ...process.env, GIT_TERMINAL_PROMPT: '0' } });
const remoteAbs = path.join(scratch.abs, 'remote.git');
const workAbs = path.join(scratch.abs, 'work');
const workRel = `${scratch.rel}/work`;
fs.mkdirSync(workAbs);
git(scratch.abs, 'init', '--bare', '-q', '-b', 'main', remoteAbs);
git(workAbs, 'init', '-q', '-b', 'main');
git(workAbs, 'config', 'user.name', 'Studio Test');
git(workAbs, 'config', 'user.email', 'studio@example.com');
git(workAbs, 'config', 'commit.gpgsign', 'false');
// Byte-exact checks below: do not let a machine-wide core.autocrlf (the
// Git for Windows default) rewrite line endings on checkout.
git(workAbs, 'config', 'core.autocrlf', 'false');
fs.writeFileSync(path.join(workAbs, 'main.ot'), 'say "hello"\n');

const port = 6400 + (process.pid % 500);
const baseUrl = `http://127.0.0.1:${port}`;
const server = spawn(process.execPath, ['serve.mjs'], { cwd: studioRoot, env: { ...process.env, OTTER_STUDIO_PORT: String(port) }, stdio: 'ignore' });
process.on('exit', () => server.kill());
for (let attempt = 0; ; attempt++) {
  try { if ((await fetch(`${baseUrl}/`)).ok) break; } catch {}
  // 15 s: a cold Node start on Windows after the launch tests can take several seconds.
  if (attempt > 150) throw new Error('Studio server did not start');
  await new Promise(r => setTimeout(r, 100));
}
const api = async (method, action, data = {}) => {
  const res = method === 'GET'
    ? await fetch(`${baseUrl}/api/git/${action}?${new URLSearchParams({ folder: workRel, ...data })}`)
    : await fetch(`${baseUrl}/api/git/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ folder: workRel, ...data }) });
  const body = await res.json();
  return { status: res.status, ...body };
};

try {
  await test('status finds the repository and the untracked file', async () => {
    const s = await api('GET', 'status');
    assert.equal(s.isRepo, true);
    assert.equal(s.root, workRel);
    assert.equal(s.files[0].path, 'main.ot');
    assert.equal(s.files[0].untracked, true);
    const log = await api('GET', 'log');
    assert.deepEqual(log.commits, [], 'no commits yet is an empty history, not an error');
  });

  await test('stage, commit (message from stdin keeps newlines), amend', async () => {
    assert.equal((await api('POST', 'stage', { paths: ['main.ot'] })).ok, true);
    const commit = await api('POST', 'commit', { message: 'First commit\n\nWith a body line.' });
    assert.equal(commit.ok, true, commit.error);
    assert.equal(git(workAbs, 'log', '-1', '--format=%B').trim(), 'First commit\n\nWith a body line.');
    fs.writeFileSync(path.join(workAbs, 'main.ot'), 'say "hello, world"\n');
    await api('POST', 'stage', { paths: ['main.ot'] });
    const amend = await api('POST', 'commit', { message: '', amend: true });
    assert.equal(amend.ok, true, amend.error);
    assert.equal(git(workAbs, 'rev-list', '--count', 'HEAD').trim(), '1');
    assert.equal((await api('POST', 'commit', { message: '' })).status, 400, 'an empty message is refused');
  });

  await test('diff sides: working tree against the index', async () => {
    fs.writeFileSync(path.join(workAbs, 'main.ot'), 'say "hello, world"\nsay "more"\n');
    const d = await api('GET', 'diff', { path: 'main.ot', staged: '0' });
    assert.equal(d.original, 'say "hello, world"\n');
    assert.equal(d.modified, 'say "hello, world"\nsay "more"\n');
  });

  await test('discard restores tracked files and needs explicit consent to delete new ones', async () => {
    fs.writeFileSync(path.join(workAbs, 'scratch.ot'), 'say 1\n');
    const refused = await api('POST', 'discard', { paths: ['main.ot', 'scratch.ot'] });
    assert.equal(refused.status, 400);
    const ok = await api('POST', 'discard', { paths: ['main.ot', 'scratch.ot'], deleteUntracked: true });
    assert.equal(ok.ok, true, ok.error);
    assert.equal(fs.readFileSync(path.join(workAbs, 'main.ot'), 'utf8'), 'say "hello, world"\n');
    assert.equal(fs.existsSync(path.join(workAbs, 'scratch.ot')), false);
  });

  await test('paths outside the repository and option-like names are refused', async () => {
    assert.equal((await api('POST', 'stage', { paths: ['../../../etc/passwd'] })).status, 400);
    assert.equal((await api('POST', 'checkout', { branch: '--orphan=x' })).status, 400);
    assert.equal((await api('POST', 'remote', { name: 'evil', url: 'ext::sh -c touch% /tmp/pwned' })).status, 400);
  });

  await test('add a remote, push (publishes and sets upstream), fetch', async () => {
    assert.equal((await api('POST', 'remote', { name: 'origin', url: `file://${remoteAbs.replace(/\\/g, '/')}` })).ok, true);
    const push = await api('POST', 'push');
    assert.equal(push.ok, true, push.error);
    const s = await api('GET', 'status');
    assert.equal(s.upstream, 'origin/main');
    assert.equal(s.ahead, 0);
    assert.equal((await api('POST', 'fetch')).ok, true);
    const remotes = await api('GET', 'remotes');
    assert.equal(remotes.remotes[0].name, 'origin');
  });

  await test('branches: create, switch, merge with a conflict, resolve it, commit', async () => {
    assert.equal((await api('POST', 'checkout', { branch: 'feature', create: true })).ok, true);
    fs.writeFileSync(path.join(workAbs, 'main.ot'), 'say "from feature"\n');
    await api('POST', 'stage', { paths: ['main.ot'] });
    assert.equal((await api('POST', 'commit', { message: 'Feature change' })).ok, true);
    assert.equal((await api('POST', 'checkout', { branch: 'main' })).ok, true);
    fs.writeFileSync(path.join(workAbs, 'main.ot'), 'say "from main"\n');
    await api('POST', 'stage', { paths: ['main.ot'] });
    assert.equal((await api('POST', 'commit', { message: 'Main change' })).ok, true);

    const merge = await api('POST', 'merge', { branch: 'feature' });
    assert.equal(merge.ok, false);
    assert.deepEqual(merge.conflicts, ['main.ot']);
    const s = await api('GET', 'status');
    assert.equal(s.merging, true);
    assert.equal(s.files.find(f => f.path === 'main.ot').conflict, true);

    // What the conflict editor does: resolve blocks, save with the revision, mark resolved.
    const fileRel = `${workRel}/main.ot`;
    const opened = await (await fetch(`${baseUrl}/api/file?path=${encodeURIComponent(fileRel)}`)).json();
    const { blocks } = parseConflicts(opened.content);
    assert.equal(blocks.length, 1);
    const resolved = resolveConflict(opened.content, 0, 'both');
    const save = await fetch(`${baseUrl}/api/file`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ path: fileRel, content: resolved, expectedRevision: opened.revision }) });
    assert.equal(save.status, 200);
    assert.equal((await api('POST', 'resolve', { paths: ['main.ot'] })).ok, true);
    const commit = await api('POST', 'commit', { message: 'Merge feature' });
    assert.equal(commit.ok, true, commit.error);
    assert.equal(fs.readFileSync(path.join(workAbs, 'main.ot'), 'utf8'), 'say "from main"\nsay "from feature"\n');
    assert.equal((await api('GET', 'status')).merging, false);
    const branches = await api('GET', 'branches');
    assert.ok(branches.branches.some(b => b.name === 'feature'));
    assert.equal((await api('POST', 'delete-branch', { branch: 'feature' })).ok, true, 'merged branch deletes');
  });

  await test('stash push, list, pop', async () => {
    fs.writeFileSync(path.join(workAbs, 'wip.ot'), 'say "wip"\n');
    assert.equal((await api('POST', 'stash', { op: 'push', message: 'work in progress' })).ok, true);
    assert.equal(fs.existsSync(path.join(workAbs, 'wip.ot')), false);
    const { stashes } = await api('GET', 'stashes');
    assert.match(stashes[0].message, /work in progress/);
    assert.equal((await api('POST', 'stash', { op: 'pop', ref: stashes[0].ref })).ok, true);
    assert.equal(fs.existsSync(path.join(workAbs, 'wip.ot')), true);
    assert.equal((await api('POST', 'stash', { op: 'pop', ref: '; rm -rf /' })).status, 400);
  });

  await test('tags: annotated create, list, delete', async () => {
    assert.equal((await api('POST', 'tag', { name: 'v1.0.0', message: 'First release' })).ok, true);
    assert.equal((await api('GET', 'tags')).tags[0].name, 'v1.0.0');
    assert.equal((await api('POST', 'tag', { name: 'v1.0.0', delete: true })).ok, true);
    assert.equal((await api('GET', 'tags')).tags.length, 0);
  });

  await test('history, commit details, file history and blame', async () => {
    const { commits } = await api('GET', 'log');
    assert.equal(commits[0].subject, 'Merge feature');
    assert.equal(commits[0].parents.length, 2);
    const details = await api('GET', 'show', { commit: commits[1].hash });
    assert.ok(details.files.some(f => f.path === 'main.ot'));
    assert.match(details.patch, /from main/);
    const fileHistory = await api('GET', 'log', { path: 'main.ot' });
    assert.ok(fileHistory.commits.length >= 3);
    const blame = await api('GET', 'blame', { path: 'main.ot' });
    assert.equal(blame.lines.length, 2);
    assert.equal(blame.lines[1].summary, 'Feature change');
  });

  await test('pull brings in commits pushed from elsewhere', async () => {
    assert.equal((await api('POST', 'push')).ok, true);
    const otherAbs = path.join(scratch.abs, 'other');
    git(scratch.abs, 'clone', '-q', remoteAbs, otherAbs);
    git(otherAbs, 'config', 'user.name', 'Other');
    git(otherAbs, 'config', 'user.email', 'other@example.com');
    git(otherAbs, 'config', 'core.autocrlf', 'false');
    fs.writeFileSync(path.join(otherAbs, 'readme.txt'), 'hi\n');
    git(otherAbs, 'add', 'readme.txt');
    git(otherAbs, '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'From another clone');
    git(otherAbs, 'push', '-q');
    await api('POST', 'fetch');
    assert.equal((await api('GET', 'status')).behind, 1);
    const pull = await api('POST', 'pull');
    assert.equal(pull.ok, true, pull.error);
    assert.equal(fs.existsSync(path.join(workAbs, 'readme.txt')), true);
  });
} finally {
  server.kill();
}

console.log(`\nGit tests passed: ${passed}.`);
