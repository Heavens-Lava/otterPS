// trust.mjs - Which workspace folders the user has trusted (Restricted
// Mode), remembered on this computer rather than in the browser.
//
//   GET  /api/trust?folder=<workspace path>   { trusted }
//   POST /api/trust { folder, trusted }       { trusted }
//
// The browser's storage belongs to one origin (http://127.0.0.1:<port>), and
// the desktop app takes the first free port, so a trust kept there was
// forgotten whenever the port changed - and the browser and desktop Studio
// never shared it. Kept in ~/.otter-studio/trusted-workspaces.json (or
// OTTER_STUDIO_TRUST_FILE), keyed by the folder's real absolute path
// (case-insensitive on Windows), so one folder is one entry however it was
// spelled.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const trustFile = () => process.env.OTTER_STUDIO_TRUST_FILE || path.join(os.homedir(), '.otter-studio', 'trusted-workspaces.json');

export function trustKey(folderAbs) {
  let real = path.resolve(folderAbs);
  try { real = fs.realpathSync(real); } catch { /* a folder that is gone keeps its spelling */ }
  real = real.replace(/[\\/]+$/, '') || real;
  return process.platform === 'win32' ? real.toLowerCase() : real;
}

function readAll() {
  try {
    const data = JSON.parse(fs.readFileSync(trustFile(), 'utf8'));
    return data && typeof data === 'object' ? data : {};
  } catch {
    return {};
  }
}

// { trusted, known }: known is false for a folder never trusted or
// distrusted here (a browser may then hand over what it remembers).
export function trustOf(folderAbs) {
  const entry = readAll()[trustKey(folderAbs)];
  return { trusted: Boolean(entry?.trusted), known: Boolean(entry) };
}

export function isTrusted(folderAbs) {
  return trustOf(folderAbs).trusted;
}

export function setTrusted(folderAbs, trusted) {
  const all = readAll();
  const key = trustKey(folderAbs);
  // A withdrawn trust is recorded too, so an old copy elsewhere cannot revive it.
  all[key] = { trusted: Boolean(trusted), time: new Date().toISOString() };
  const file = trustFile();
  fs.mkdirSync(path.dirname(file), { recursive: true });
  // Written whole and renamed into place, so a crash never leaves half a file.
  const temp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temp, JSON.stringify(all, null, 2) + '\n');
  fs.renameSync(temp, file);
  return Boolean(trusted);
}

export async function handleTrustRoutes(req, res, pathname, urlObj, ctx) {
  if (pathname !== '/api/trust') return false;
  try {
    const body = req.method === 'POST' ? await ctx.readBody(req) : {};
    const folder = String((req.method === 'POST' ? body.folder : urlObj.searchParams.get('folder')) || '');
    const abs = path.resolve(ctx.repoRoot, folder);
    if (!folder || !ctx.isInsideRepo(abs)) return ctx.sendJson(res, { error: 'Folder not found.' }, 404), true;
    if (req.method === 'GET') return ctx.sendJson(res, trustOf(abs)), true;
    if (req.method === 'POST') return ctx.sendJson(res, { trusted: setTrusted(abs, body.trusted !== false) }), true;
    ctx.sendJson(res, { error: 'Method not allowed' }, 405);
  } catch (err) {
    ctx.sendJson(res, { error: err.message }, 500);
  }
  return true;
}
