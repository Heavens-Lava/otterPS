// fs-ops.mjs - Explorer file management for Studio: new file, new folder,
// rename, move, delete (to the Recycle Bin / Trash) and reveal in the OS
// file manager.
//
// Every path is workspace-relative and must stay inside the workspace (the
// same symlink-aware check the file API uses). The workspace root itself,
// `.git` and anything inside it are never renamed, moved or deleted, and
// nothing is ever overwritten: a target that exists is a 409.

import fs from 'node:fs';
import path from 'node:path';
import { execFile, spawn } from 'node:child_process';
import { moveHistory, recordVersion } from './local-history.mjs';

const PROTECTED = /(^|[\\/])\.git([\\/]|$)/;

class FsError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

function resolveInWorkspace(ctx, rel, { mustExist = false, forChange = false } = {}) {
  if (typeof rel !== 'string' || !rel.trim() || rel.includes('\0')) throw new FsError('A path is required.');
  const abs = path.resolve(ctx.repoRoot, rel);
  if (!ctx.isInsideRepo(abs)) throw new FsError('That path is outside the workspace.', 403);
  if (forChange && (abs === path.resolve(ctx.repoRoot) || PROTECTED.test(path.relative(ctx.repoRoot, abs)))) {
    throw new FsError('The workspace root and .git cannot be changed here.', 403);
  }
  if (mustExist && !fs.existsSync(abs)) throw new FsError(`${rel} does not exist.`, 404);
  return abs;
}

function validName(name) {
  const n = String(name || '').trim();
  if (!n || n === '.' || n === '..' || /[<>:"|?*\\/\0]/.test(n) || /[. ]$/.test(n)) {
    throw new FsError(`"${n}" is not a valid file or folder name.`);
  }
  return n;
}

const rel = (ctx, abs) => path.relative(ctx.repoRoot, abs).split(path.sep).join('/');

// Windows: the Recycle Bin through the .NET VisualBasic file API (no extra
// tools). macOS: Finder's trash. Linux: `gio trash`. When none is available
// the caller is told, and nothing is deleted.
function moveToTrash(abs) {
  // Tests point this at a scratch folder instead of the real Recycle Bin.
  const testTrash = process.env.OTTER_STUDIO_TRASH_DIR;
  if (testTrash) {
    fs.mkdirSync(testTrash, { recursive: true });
    fs.renameSync(abs, path.join(testTrash, `${Date.now()}-${path.basename(abs)}`));
    return Promise.resolve();
  }
  return new Promise((resolve, reject) => {
    const isDir = fs.statSync(abs).isDirectory();
    let cmd;
    let args;
    if (process.platform === 'win32') {
      const method = isDir ? 'DeleteDirectory' : 'DeleteFile';
      const script = `Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::${method}($env:OTTER_TRASH_PATH, 'OnlyErrorDialogs', 'SendToRecycleBin')`;
      cmd = 'powershell.exe';
      args = ['-NoProfile', '-NonInteractive', '-Command', script];
    } else if (process.platform === 'darwin') {
      cmd = 'osascript';
      args = ['-e', 'on run argv', '-e', 'tell application "Finder" to delete POSIX file (item 1 of argv)', '-e', 'end run', abs];
    } else {
      cmd = 'gio';
      args = ['trash', abs];
    }
    execFile(cmd, args, { windowsHide: true, timeout: 30000, env: { ...process.env, OTTER_TRASH_PATH: abs } }, (err, _out, stderr) => {
      if (err) reject(new FsError(`Could not move it to the ${process.platform === 'win32' ? 'Recycle Bin' : 'Trash'}: ${String(stderr || err.message).trim()}`, 500));
      else if (fs.existsSync(abs)) reject(new FsError('It is still there after moving it to the trash.', 500));
      else resolve();
    });
  });
}

// The folders inside one workspace folder, for the Open Folder browser.
// Hidden folders and dependency/build folders are left out; a folder with a
// project.json / otter.json is marked as a project, one with .ot files as
// Otter code.
const SKIP_DIRS = new Set(['node_modules', 'dist', 'build', 'bin', 'obj', 'backup', 'packages']);

export function listDirs(ctx, folder) {
  const abs = resolveInWorkspace(ctx, folder || '.', { mustExist: true });
  if (!fs.statSync(abs).isDirectory()) throw new FsError('That is not a folder.');
  const dirs = [];
  for (const entry of fs.readdirSync(abs, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name.startsWith('.') || SKIP_DIRS.has(entry.name)) continue;
    const childAbs = path.join(abs, entry.name);
    let names = [];
    try { names = fs.readdirSync(childAbs); } catch { continue; }
    dirs.push({
      name: entry.name,
      path: rel(ctx, childAbs),
      isProject: names.includes('project.json') || names.includes('otter.json'),
      hasOtter: names.some(n => n.toLowerCase().endsWith('.ot')),
      hasFolders: names.some(n => !n.startsWith('.') && !SKIP_DIRS.has(n) && (() => { try { return fs.statSync(path.join(childAbs, n)).isDirectory(); } catch { return false; } })())
    });
  }
  dirs.sort((a, b) => (b.isProject - a.isProject) || a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
  const here = rel(ctx, abs) || '.';
  return { path: here === '' ? '.' : here, dirs };
}

export async function handleFsRoutes(req, res, pathname, ctx) {
  if (pathname === '/api/fs/dirs' && req.method === 'GET') {
    try {
      const url = new URL(req.url, 'http://localhost');
      return ctx.sendJson(res, listDirs(ctx, url.searchParams.get('path') || '.')), true;
    } catch (err) {
      return ctx.sendJson(res, { error: err.message }, err.status || 500), true;
    }
  }
  if (!pathname.startsWith('/api/fs/') || req.method !== 'POST') return false;
  const { sendJson } = ctx;
  try {
    const body = await ctx.readBody(req);
    switch (pathname) {
      case '/api/fs/new-file':
      case '/api/fs/new-folder': {
        const folder = resolveInWorkspace(ctx, body.folder || '.', { mustExist: true });
        if (!fs.statSync(folder).isDirectory()) throw new FsError('Create it in a folder.');
        const abs = resolveInWorkspace(ctx, rel(ctx, path.join(folder, validName(body.name))), { forChange: true });
        if (fs.existsSync(abs)) throw new FsError(`${body.name} already exists here.`, 409);
        if (pathname.endsWith('new-folder')) fs.mkdirSync(abs);
        else fs.writeFileSync(abs, typeof body.content === 'string' ? body.content : '', { flag: 'wx' });
        return sendJson(res, { ok: true, path: rel(ctx, abs) }), true;
      }
      case '/api/fs/rename': {
        const from = resolveInWorkspace(ctx, body.path, { mustExist: true, forChange: true });
        const to = resolveInWorkspace(ctx, rel(ctx, path.join(path.dirname(from), validName(body.name))), { forChange: true });
        if (to === from) return sendJson(res, { ok: true, path: rel(ctx, to) }), true;
        // A case-only rename on Windows is the same file: allow it.
        if (fs.existsSync(to) && to.toLowerCase() !== from.toLowerCase()) throw new FsError(`${body.name} already exists here.`, 409);
        fs.renameSync(from, to);
        moveHistory(from, to, rel(ctx, to));
        return sendJson(res, { ok: true, from: rel(ctx, from), path: rel(ctx, to) }), true;
      }
      case '/api/fs/move': {
        const from = resolveInWorkspace(ctx, body.path, { mustExist: true, forChange: true });
        const folder = resolveInWorkspace(ctx, body.folder, { mustExist: true });
        if (!fs.statSync(folder).isDirectory()) throw new FsError('Drop it on a folder.');
        const relToFrom = path.relative(from, folder);
        if (!relToFrom || (!relToFrom.startsWith('..') && !path.isAbsolute(relToFrom))) throw new FsError('A folder cannot move into itself.');
        const to = resolveInWorkspace(ctx, rel(ctx, path.join(folder, path.basename(from))), { forChange: true });
        if (to === from) return sendJson(res, { ok: true, path: rel(ctx, to) }), true;
        if (fs.existsSync(to)) throw new FsError(`${path.basename(from)} already exists in that folder.`, 409);
        fs.renameSync(from, to);
        moveHistory(from, to, rel(ctx, to));
        return sendJson(res, { ok: true, from: rel(ctx, from), path: rel(ctx, to) }), true;
      }
      case '/api/fs/delete': {
        const abs = resolveInWorkspace(ctx, body.path, { mustExist: true, forChange: true });
        // A deleted file's last text stays in Local History too.
        if (fs.statSync(abs).isFile()) recordVersion(abs, rel(ctx, abs), fs.readFileSync(abs, 'utf8'), 'before delete');
        await moveToTrash(abs);
        return sendJson(res, { ok: true, path: rel(ctx, abs), trashed: true }), true;
      }
      case '/api/fs/reveal': {
        const abs = resolveInWorkspace(ctx, body.path, { mustExist: true });
        const isDir = fs.statSync(abs).isDirectory();
        const opener = process.platform === 'win32' ? ['explorer.exe', isDir ? [abs] : [`/select,${abs}`]]
          : process.platform === 'darwin' ? ['open', isDir ? [abs] : ['-R', abs]]
            : ['xdg-open', [isDir ? abs : path.dirname(abs)]];
        spawn(opener[0], opener[1], { detached: true, stdio: 'ignore', windowsHide: true }).unref();
        return sendJson(res, { ok: true }), true;
      }
      default:
        return false;
    }
  } catch (err) {
    sendJson(res, { error: err.message }, err.status || 500);
    return true;
  }
}

export const _internal = { validName, PROTECTED };
