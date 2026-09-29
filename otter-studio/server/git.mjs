// git.mjs - Source control for Otter Studio, backed by the real `git` CLI.
//
// Studio does not implement Git. Every operation runs the `git` command line
// the user already has, the same way they would in a terminal:
//
//   execFile('git', ['-C', <repo>, ...args])     never a shell string
//
// Safety rules applied to every call:
//   * The repository must be inside the workspace (the server's root).
//   * File paths come after `--`, so a path can never be read as an option,
//     and each one must resolve inside the repository.
//   * Branch, tag, remote and stash names are checked before use; a name
//     starting with `-` is always refused.
//   * GIT_TERMINAL_PROMPT=0: git never waits for a password on a console
//     nobody can see. Authentication comes from the user's configured
//     credential helper or SSH agent; if there is none, the command fails
//     with git's own message instead of hanging.
//   * Operations that talk to a remote have a time limit.

import { execFile } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const LOCAL_TIMEOUT_MS = 30 * 1000;
const REMOTE_TIMEOUT_MS = 2 * 60 * 1000;

// ---------------------------------------------------------------------------
// Running git
// ---------------------------------------------------------------------------

/**
 * Run git in `cwd`. Resolves { code, stdout, stderr } (never rejects on a
 * non-zero exit; callers decide). `input` is written to stdin.
 */
export function runGit(cwd, args, { input = null, timeout = LOCAL_TIMEOUT_MS, maxBuffer = 32 * 1024 * 1024 } = {}) {
  return new Promise(resolve => {
    const child = execFile('git', args, {
      cwd,
      timeout,
      maxBuffer,
      windowsHide: true,
      encoding: 'utf8',
      env: {
        ...process.env,
        GIT_TERMINAL_PROMPT: '0',
        // Status and diff should not take locks another git process needs.
        GIT_OPTIONAL_LOCKS: '0',
        // Plain, untranslated output that the parsers below understand.
        LC_ALL: 'C',
        LANG: 'C'
      }
    }, (error, stdout, stderr) => {
      resolve({
        code: error ? (typeof error.code === 'number' ? error.code : 1) : 0,
        stdout: stdout || '',
        stderr: stderr || (error && typeof error.code !== 'number' ? error.message : '')
      });
    });
    if (input !== null) child.stdin.end(input);
  });
}

class GitError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

async function gitOrThrow(cwd, args, options) {
  const result = await runGit(cwd, args, options);
  if (result.code !== 0) {
    throw new GitError((result.stderr || result.stdout).trim() || `git ${args[0]} failed (exit code ${result.code}).`);
  }
  return result.stdout;
}

// ---------------------------------------------------------------------------
// Names and paths
// ---------------------------------------------------------------------------

/**
 * A branch or tag name git will accept. Mirrors git check-ref-format's rules
 * closely enough to refuse anything surprising before git sees it.
 */
export function isValidRefName(name) {
  if (typeof name !== 'string' || !name || name.length > 200) return false;
  if (name.startsWith('-') || name.startsWith('/') || name.endsWith('/') || name.endsWith('.') || name.endsWith('.lock')) return false;
  if (name === '@' || name.includes('..') || name.includes('@{') || name.includes('//')) return false;
  if (/[\x00-\x20\x7f~^:?*[\\]/.test(name)) return false;
  return name.split('/').every(part => part && !part.startsWith('.'));
}

export function isValidRemoteName(name) {
  return typeof name === 'string' && /^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/.test(name);
}

/** Paths relative to the repository root, checked to stay inside it. */
function repoPaths(repoRoot, paths) {
  if (!Array.isArray(paths) || paths.length === 0) throw new GitError('No files were given.');
  return paths.map(p => {
    if (typeof p !== 'string' || !p || p.includes('\0')) throw new GitError('Invalid file path.');
    const abs = path.resolve(repoRoot, p);
    const rel = path.relative(repoRoot, abs);
    if (!rel || rel.startsWith('..') || path.isAbsolute(rel)) throw new GitError(`${p} is outside the repository.`);
    return rel.split(path.sep).join('/');
  });
}

// ---------------------------------------------------------------------------
// Parsers (exported for tests)
// ---------------------------------------------------------------------------

const STATUS_WORDS = { M: 'modified', A: 'added', D: 'deleted', R: 'renamed', C: 'copied', T: 'type changed', U: 'conflict', '?': 'untracked', '!': 'ignored' };

/**
 * Parse `git status --porcelain=v2 --branch -z`.
 * Returns { branch, oid, upstream, ahead, behind, files: [...] } where each
 * file is { path, from, index, worktree, staged, unstaged, conflict, untracked }.
 * `index` / `worktree` are single letters ('.' = unchanged).
 */
export function parseStatusV2(text) {
  const result = { branch: null, oid: null, upstream: null, ahead: 0, behind: 0, files: [] };
  const entries = text.split('\0');
  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    if (!entry) continue;
    if (entry.startsWith('# ')) {
      const [, key, ...rest] = entry.split(' ');
      const value = rest.join(' ');
      if (key === 'branch.head') result.branch = value === '(detached)' ? null : value;
      else if (key === 'branch.oid') result.oid = value === '(initial)' ? null : value;
      else if (key === 'branch.upstream') result.upstream = value;
      else if (key === 'branch.ab') {
        const m = /\+(\d+) -(\d+)/.exec(value);
        if (m) { result.ahead = Number(m[1]); result.behind = Number(m[2]); }
      }
      continue;
    }
    const kind = entry[0];
    if (kind === '1') {
      // 1 XY sub mH mI mW hH hI path
      const parts = entry.split(' ');
      result.files.push(fileEntry(parts[1], parts.slice(8).join(' ')));
    } else if (kind === '2') {
      // 2 XY sub mH mI mW hH hI Xscore path \0 origPath
      const parts = entry.split(' ');
      const file = fileEntry(parts[1], parts.slice(9).join(' '));
      file.from = entries[++i] || null;
      result.files.push(file);
    } else if (kind === 'u') {
      // u XY sub m1 m2 m3 mW h1 h2 h3 path
      const parts = entry.split(' ');
      const file = fileEntry(parts[1], parts.slice(10).join(' '));
      file.conflict = true;
      result.files.push(file);
    } else if (kind === '?') {
      result.files.push({ ...fileEntry('?.', entry.slice(2)), untracked: true, index: '.', worktree: '?' });
    }
  }
  return result;
}

function fileEntry(xy, filePath) {
  const index = xy[0];
  const worktree = xy[1];
  return {
    path: filePath,
    from: null,
    index,
    worktree,
    staged: index !== '.' && index !== '?',
    unstaged: worktree !== '.',
    conflict: false,
    untracked: false,
    label: STATUS_WORDS[index !== '.' ? index : worktree] || 'changed'
  };
}

// Commit log: one record per commit, fields split by \x1f, records by \x1e.
const LOG_FORMAT = ['%H', '%h', '%an', '%ae', '%aI', '%P', '%D', '%s'].join('%x1f') + '%x1e';

export function parseLog(text) {
  return text.split('\x1e').map(r => r.replace(/^\n/, '')).filter(Boolean).map(record => {
    const [hash, short, author, email, date, parents, refs, subject] = record.split('\x1f');
    return {
      hash, short, author, email, date,
      parents: parents ? parents.split(' ') : [],
      refs: refs ? refs.split(', ').filter(Boolean) : [],
      subject
    };
  });
}

/** Parse `git blame --porcelain` into one entry per line. */
export function parseBlamePorcelain(text) {
  const commits = new Map();
  const lines = [];
  const rows = text.split('\n');
  let i = 0;
  while (i < rows.length) {
    const header = /^([0-9a-f]{40}) (\d+) (\d+)/.exec(rows[i]);
    if (!header) { i++; continue; }
    const hash = header[1];
    const commit = commits.get(hash) || { hash, author: '', date: null, summary: '' };
    i++;
    while (i < rows.length && !rows[i].startsWith('\t')) {
      const row = rows[i];
      if (row.startsWith('author ')) commit.author = row.slice(7);
      else if (row.startsWith('author-time ')) commit.date = new Date(Number(row.slice(12)) * 1000).toISOString();
      else if (row.startsWith('summary ')) commit.summary = row.slice(8);
      i++;
    }
    commits.set(hash, commit);
    lines.push({ line: Number(header[3]), hash, text: (rows[i] || '').slice(1) });
    i++;
  }
  return lines.map(l => ({ ...l, ...commits.get(l.hash), uncommitted: /^0+$/.test(l.hash) }));
}

// ---------------------------------------------------------------------------
// Operations
// ---------------------------------------------------------------------------

/** The repository containing `folderAbs`, or null. */
export async function findRepoRoot(folderAbs) {
  const result = await runGit(folderAbs, ['rev-parse', '--show-toplevel']);
  if (result.code !== 0) return null;
  return path.resolve(result.stdout.trim());
}

async function readBlob(repoRoot, spec) {
  const result = await runGit(repoRoot, ['show', spec]);
  return result.code === 0 ? result.stdout : null;
}

/**
 * The two sides of a file's change, for the diff viewer.
 * staged: HEAD -> index. Otherwise: index -> working tree.
 */
async function diffSides(repoRoot, file, staged) {
  const [rel] = repoPaths(repoRoot, [file]);
  const abs = path.join(repoRoot, rel);
  const head = await readBlob(repoRoot, `HEAD:${rel}`);
  const index = await readBlob(repoRoot, `:${rel}`);
  const work = fs.existsSync(abs) && fs.statSync(abs).isFile() ? fs.readFileSync(abs, 'utf8') : null;
  return staged
    ? { path: rel, tracked: head !== null || index !== null, original: head ?? '', modified: index ?? '', originalLabel: 'HEAD', modifiedLabel: 'Staged' }
    : { path: rel, tracked: head !== null || index !== null, original: index ?? head ?? '', modified: work ?? '', originalLabel: index !== null ? 'Staged' : 'HEAD', modifiedLabel: 'Working tree' };
}

/**
 * Handle /api/git/* routes. Returns true when handled.
 * ctx = { repoRoot (workspace root), isInsideRepo, readBody, sendJson }
 */
export async function handleGitRoutes(req, res, pathname, urlObj, ctx) {
  if (!pathname.startsWith('/api/git/')) return false;
  const { isInsideRepo, readBody, sendJson } = ctx;
  const action = pathname.slice('/api/git/'.length);
  const body = req.method === 'POST' ? await readBody(req) : {};
  const param = name => (req.method === 'POST' ? body[name] : urlObj.searchParams.get(name));

  try {
    // Locate the repository from the folder the user has open.
    const folderRel = param('folder') || '.';
    const folderAbs = path.resolve(ctx.repoRoot, folderRel);
    if (!isInsideRepo(folderAbs) || !fs.existsSync(folderAbs)) throw new GitError('Folder not found.', 404);
    const startDir = fs.statSync(folderAbs).isDirectory() ? folderAbs : path.dirname(folderAbs);
    const repoRoot = await findRepoRoot(startDir);
    // The file as the editor knows it (`file`, a workspace path - also for a
    // project outside the Otter install, in its own repository) or already
    // as a path in the repository (`path`).
    const fileInRepo = () => {
      const file = param('file');
      if (!file) return param('path');
      const abs = path.resolve(ctx.repoRoot, file);
      if (!isInsideRepo(abs)) throw new GitError('File not found.', 404);
      return path.relative(repoRoot, abs);
    };

    if (action === 'status' && req.method === 'GET') {
      if (!repoRoot) return sendJson(res, { isRepo: false }), true;
      if (!isInsideRepo(repoRoot)) throw new GitError('The repository is outside the workspace.', 403);
      const status = parseStatusV2(await gitOrThrow(repoRoot, ['status', '--porcelain=v2', '--branch', '-z']));
      const stash = await runGit(repoRoot, ['stash', 'list', '--format=%gd']);
      return sendJson(res, {
        isRepo: true,
        root: path.relative(ctx.repoRoot, repoRoot).split(path.sep).join('/') || '.',
        ...status,
        stashCount: stash.code === 0 ? stash.stdout.split('\n').filter(Boolean).length : 0,
        merging: fs.existsSync(path.join(repoRoot, '.git', 'MERGE_HEAD'))
      }), true;
    }

    if (action === 'init' && req.method === 'POST') {
      if (repoRoot) throw new GitError('This folder is already in a Git repository.');
      await gitOrThrow(folderAbs, ['init']);
      return sendJson(res, { ok: true }), true;
    }

    if (!repoRoot) throw new GitError('This folder is not in a Git repository.', 404);
    if (!isInsideRepo(repoRoot)) throw new GitError('The repository is outside the workspace.', 403);

    switch (`${req.method} ${action}`) {
      case 'GET diff': {
        return sendJson(res, await diffSides(repoRoot, fileInRepo(),param('staged') === '1' || param('staged') === true)), true;
      }
      case 'POST stage': {
        await gitOrThrow(repoRoot, ['add', '--', ...repoPaths(repoRoot, body.paths)]);
        return sendJson(res, { ok: true }), true;
      }
      case 'POST unstage': {
        const paths = repoPaths(repoRoot, body.paths);
        const hasHead = (await runGit(repoRoot, ['rev-parse', '--verify', 'HEAD'])).code === 0;
        // Before the first commit there is no HEAD to restore from.
        await gitOrThrow(repoRoot, hasHead ? ['restore', '--staged', '--', ...paths] : ['rm', '--cached', '-q', '--', ...paths]);
        return sendJson(res, { ok: true }), true;
      }
      case 'POST discard': {
        // Throws away working-tree changes. Tracked files return to their
        // staged/committed content; untracked files are deleted only when the
        // client says so explicitly (after asking the user).
        const paths = repoPaths(repoRoot, body.paths);
        const status = parseStatusV2(await gitOrThrow(repoRoot, ['status', '--porcelain=v2', '-z', '--', ...paths]));
        const untracked = status.files.filter(f => f.untracked).map(f => f.path);
        const tracked = paths.filter(p => !untracked.includes(p));
        if (tracked.length) await gitOrThrow(repoRoot, ['restore', '--worktree', '--', ...tracked]);
        if (untracked.length) {
          if (body.deleteUntracked !== true) throw new GitError('Deleting untracked files needs confirmation.');
          await gitOrThrow(repoRoot, ['clean', '-f', '-q', '--', ...untracked]);
        }
        return sendJson(res, { ok: true }), true;
      }
      case 'POST commit': {
        const message = typeof body.message === 'string' ? body.message.trim() : '';
        if (!message && !body.amend) throw new GitError('Write a commit message first.');
        const args = ['commit', '--cleanup=strip'];
        if (body.amend) args.push('--amend');
        if (body.amend && !message) args.push('--no-edit');
        else args.push('-F', '-'); // message from stdin: keeps newlines, no quoting
        if (body.all) args.push('-a');
        const out = await gitOrThrow(repoRoot, args, { input: message ? `${message}\n` : null });
        return sendJson(res, { ok: true, output: out.trim() }), true;
      }
      case 'GET branches': {
        const out = await gitOrThrow(repoRoot, ['for-each-ref', '--format=%(refname)%1f%(refname:short)%1f%(objectname:short)%1f%(upstream:short)%1f%(HEAD)%1f%(committerdate:iso-strict)', 'refs/heads', 'refs/remotes']);
        const branches = out.split('\n').filter(Boolean).map(line => {
          const [ref, name, hash, upstream, head, date] = line.split('\x1f');
          return { name, hash, upstream: upstream || null, current: head === '*', remote: ref.startsWith('refs/remotes/'), date };
        }).filter(b => !b.name.endsWith('/HEAD'));
        return sendJson(res, { branches }), true;
      }
      case 'POST checkout': {
        const name = body.branch;
        if (!isValidRefName(name)) throw new GitError('That is not a valid branch name.');
        if (body.create) {
          const args = ['switch', '-c', name];
          if (body.startPoint) {
            if (!isValidRefName(body.startPoint)) throw new GitError('That is not a valid start point.');
            args.push(body.startPoint);
          }
          await gitOrThrow(repoRoot, args);
        } else {
          // A remote branch ("origin/feature") switches to a local tracking branch.
          await gitOrThrow(repoRoot, ['switch', name]).catch(async err => {
            const remote = name.includes('/') ? name.slice(name.indexOf('/') + 1) : null;
            if (!remote) throw err;
            await gitOrThrow(repoRoot, ['switch', '--track', name]);
          });
        }
        return sendJson(res, { ok: true }), true;
      }
      case 'POST delete-branch': {
        if (!isValidRefName(body.branch)) throw new GitError('That is not a valid branch name.');
        await gitOrThrow(repoRoot, ['branch', body.force ? '-D' : '-d', '--', body.branch]);
        return sendJson(res, { ok: true }), true;
      }
      case 'POST merge': {
        if (!isValidRefName(body.branch)) throw new GitError('That is not a valid branch name.');
        const result = await runGit(repoRoot, ['merge', '--no-edit', body.branch]);
        const conflicts = parseStatusV2((await runGit(repoRoot, ['status', '--porcelain=v2', '-z'])).stdout).files.filter(f => f.conflict).map(f => f.path);
        if (result.code !== 0 && conflicts.length === 0) throw new GitError((result.stderr || result.stdout).trim());
        return sendJson(res, { ok: result.code === 0, conflicts, output: (result.stdout + result.stderr).trim() }), true;
      }
      case 'POST merge-abort': {
        await gitOrThrow(repoRoot, ['merge', '--abort']);
        return sendJson(res, { ok: true }), true;
      }
      case 'POST fetch':
      case 'POST pull':
      case 'POST push': {
        const remote = body.remote || null;
        if (remote !== null && !isValidRemoteName(remote)) throw new GitError('That is not a valid remote name.');
        let args;
        if (action === 'fetch') args = ['fetch', '--prune', ...(remote ? [remote] : ['--all'])];
        else if (action === 'pull') args = ['pull', '--no-rebase', ...(remote ? [remote] : [])];
        else {
          const status = parseStatusV2(await gitOrThrow(repoRoot, ['status', '--porcelain=v2', '--branch', '-z']));
          if (!status.branch) throw new GitError('Switch to a branch before pushing (HEAD is detached).');
          // First push of a branch: publish it and remember the upstream.
          args = status.upstream ? ['push'] : ['push', '--set-upstream', remote || 'origin', status.branch];
          if (body.tags) args.push('--tags');
        }
        const result = await runGit(repoRoot, args, { timeout: REMOTE_TIMEOUT_MS });
        if (result.code !== 0) throw new GitError((result.stderr || result.stdout).trim() || `git ${action} failed.`);
        return sendJson(res, { ok: true, output: (result.stdout + result.stderr).trim() }), true;
      }
      case 'GET log': {
        const limit = Math.min(Math.max(Number(param('limit')) || 100, 1), 1000);
        const skip = Math.max(Number(param('skip')) || 0, 0);
        const args = ['log', `--format=${LOG_FORMAT}`, `-n${limit}`, `--skip=${skip}`];
        const file = param('path');
        if (file) args.push('--follow', '--', ...repoPaths(repoRoot, [file]));
        const result = await runGit(repoRoot, args);
        // A repository with no commits yet has an empty history, not an error.
        if (result.code !== 0 && /does not have any commits|bad default revision/.test(result.stderr)) return sendJson(res, { commits: [] }), true;
        if (result.code !== 0) throw new GitError(result.stderr.trim());
        return sendJson(res, { commits: parseLog(result.stdout) }), true;
      }
      case 'GET show': {
        const commit = param('commit');
        if (!/^[0-9a-f]{4,40}$/i.test(commit || '')) throw new GitError('That is not a commit id.');
        const [meta] = parseLog(await gitOrThrow(repoRoot, ['show', '-s', `--format=${LOG_FORMAT}`, commit]));
        const bodyText = await gitOrThrow(repoRoot, ['show', '-s', '--format=%b', commit]);
        const files = (await gitOrThrow(repoRoot, ['show', '--format=', '--name-status', '-z', commit])).split('\0').filter(Boolean);
        const changed = [];
        for (let i = 0; i < files.length; i++) {
          const status = files[i];
          if (/^[RC]/.test(status)) { changed.push({ status: status[0], from: files[i + 1], path: files[i + 2] }); i += 2; }
          else { changed.push({ status, path: files[i + 1] }); i += 1; }
        }
        const patch = await gitOrThrow(repoRoot, ['show', '--format=', '--patch', '--no-color', commit], { maxBuffer: 8 * 1024 * 1024 }).catch(() => '');
        return sendJson(res, { ...meta, body: bodyText.trim(), files: changed, patch: patch.length > 400000 ? patch.slice(0, 400000) + '\n… (truncated)' : patch }), true;
      }
      case 'GET blame': {
        const [rel] = repoPaths(repoRoot, [fileInRepo()]);
        const result = await runGit(repoRoot, ['blame', '--porcelain', '--', rel]);
        if (result.code !== 0) throw new GitError(result.stderr.trim() || 'Blame is only available for committed files.');
        return sendJson(res, { path: rel, lines: parseBlamePorcelain(result.stdout) }), true;
      }
      case 'GET stashes': {
        const out = await gitOrThrow(repoRoot, ['stash', 'list', '--format=%gd%x1f%s%x1f%cI']);
        const stashes = out.split('\n').filter(Boolean).map(line => {
          const [ref, message, date] = line.split('\x1f');
          return { ref, message, date };
        });
        return sendJson(res, { stashes }), true;
      }
      case 'POST stash': {
        const op = body.op || 'push';
        const ref = body.ref;
        if (ref !== undefined && !/^stash@\{\d+\}$/.test(ref)) throw new GitError('That is not a stash.');
        let args;
        if (op === 'push') {
          args = ['stash', 'push', '--include-untracked'];
          if (typeof body.message === 'string' && body.message.trim()) args.push('-m', body.message.trim());
        } else if (op === 'pop' || op === 'apply' || op === 'drop') {
          args = ['stash', op, ...(ref ? [ref] : [])];
        } else {
          throw new GitError('Unknown stash operation.');
        }
        const out = await gitOrThrow(repoRoot, args);
        return sendJson(res, { ok: true, output: out.trim() }), true;
      }
      case 'GET tags': {
        const out = await gitOrThrow(repoRoot, ['for-each-ref', '--sort=-creatordate', '--format=%(refname:short)%1f%(objectname:short)%1f%(subject)%1f%(creatordate:iso-strict)', 'refs/tags']);
        const tags = out.split('\n').filter(Boolean).map(line => {
          const [name, hash, subject, date] = line.split('\x1f');
          return { name, hash, subject, date };
        });
        return sendJson(res, { tags }), true;
      }
      case 'POST tag': {
        if (!isValidRefName(body.name)) throw new GitError('That is not a valid tag name.');
        if (body.delete) {
          await gitOrThrow(repoRoot, ['tag', '-d', body.name]);
        } else {
          const args = ['tag'];
          if (typeof body.message === 'string' && body.message.trim()) args.push('-a', '-F', '-');
          args.push(body.name);
          if (body.commit) {
            if (!/^[0-9a-f]{4,40}$/i.test(body.commit)) throw new GitError('That is not a commit id.');
            args.push(body.commit);
          }
          await gitOrThrow(repoRoot, args, { input: args.includes('-F') ? `${body.message.trim()}\n` : null });
        }
        return sendJson(res, { ok: true }), true;
      }
      case 'GET remotes': {
        const out = await gitOrThrow(repoRoot, ['remote', '-v']);
        const remotes = new Map();
        for (const line of out.split('\n').filter(Boolean)) {
          const [name, url, kind] = line.split(/\s+/);
          const entry = remotes.get(name) || { name, fetchUrl: null, pushUrl: null };
          if (kind === '(fetch)') entry.fetchUrl = redactUrl(url);
          else entry.pushUrl = redactUrl(url);
          remotes.set(name, entry);
        }
        return sendJson(res, { remotes: [...remotes.values()] }), true;
      }
      case 'POST remote': {
        if (!isValidRemoteName(body.name)) throw new GitError('That is not a valid remote name.');
        if (body.remove) {
          await gitOrThrow(repoRoot, ['remote', 'remove', body.name]);
        } else {
          const url = typeof body.url === 'string' ? body.url.trim() : '';
          // Only ordinary remote URLs; `ext::` and other transports could run commands.
          if (!/^(https?:\/\/|ssh:\/\/|git@[\w.-]+:|file:\/\/)/.test(url) || url.startsWith('-')) {
            throw new GitError('Use an https://, ssh://, git@host: or file:// URL.');
          }
          await gitOrThrow(repoRoot, ['remote', 'add', '--', body.name, url]);
        }
        return sendJson(res, { ok: true }), true;
      }
      case 'POST resolve': {
        // The conflict editor saved the file; mark it resolved.
        await gitOrThrow(repoRoot, ['add', '--', ...repoPaths(repoRoot, body.paths)]);
        return sendJson(res, { ok: true }), true;
      }
      default:
        throw new GitError('Unknown source-control request.', 404);
    }
  } catch (err) {
    sendJson(res, { error: err.message }, err.status || 400);
    return true;
  }
}

/** Hide a password embedded in a remote URL (https://user:secret@host). */
export function redactUrl(url) {
  return String(url || '').replace(/^(\w+:\/\/[^/:@]+):[^@/]*@/, '$1:***@');
}
