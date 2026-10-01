// serve.mjs - Local web server & real development backend for Otter Studio
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { exec, execFile, spawn } from 'node:child_process';
import { handleLaunchRoutes } from './server/launch.mjs';
import { handleFsRoutes } from './server/fs-ops.mjs';
import { listComputerFolder, loadSavedRoots, saveRoot, isDriveRoot } from './server/computer-folders.mjs';
import { createTerminalManager, handleTerminalRoutes } from './server/terminal-sessions.mjs';
import { handleHistoryRoutes, recordVersion } from './server/local-history.mjs';
import { handleEditorConfigRoute } from './server/editorconfig.mjs';
import { handleAssetRoutes } from './server/assets.mjs';
import { handleTrustRoutes } from './server/trust.mjs';
import { handleStylesheetRoute, resolveProjectStylesheet } from './server/stylesheet.mjs';
import { syncMirror, projectRootFor } from './server/project-mirror.mjs';
import { createRenderWorker } from './server/render-worker.mjs';
import { handleGitRoutes } from './server/git.mjs';
import { handleTestRoutes } from './server/tests.mjs';
import { checkRequest, readJsonBody, isInside, LOOPBACK_HOST } from './server/security.mjs';
import {
  createDefaultManifest,
  normalizeManifest,
  validateManifest,
  serializeManifest
} from './js/project/project-manifest.js';
import {
  createDefaultSolution,
  normalizeSolution,
  validateSolution,
  serializeSolution
} from './js/project/workspace-solution.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..');

// An editor host (VS Code) or the desktop shell may start this server with
// ELECTRON_RUN_AS_NODE set. This process is already running; its children
// (Run, the terminal, packaging, Electron previews) must not inherit it, or
// an Electron app launched from Studio starts as plain Node.
delete process.env.ELECTRON_RUN_AS_NODE;

// True when `target` (an absolute path) is the repository root or inside it.
// Two checks:
//  - by path text (path.relative, not startsWith: a bare startsWith(REPO_ROOT)
//    also accepted sibling folders such as C:\src\otterPS-backup);
//  - by where the path really leads on disk, so a symbolic link or junction
//    inside the workspace that points elsewhere cannot be used to read or
//    write outside it. For a path that does not exist yet (a new file), the
//    nearest existing parent folder is resolved.
const REPO_ROOT_REAL = fs.realpathSync(REPO_ROOT);

function realPathOfNearest(target) {
  const missing = [];
  let current = target;
  while (!fs.existsSync(current)) {
    const parent = path.dirname(current);
    if (parent === current) break;
    missing.unshift(path.basename(current));
    current = parent;
  }
  try {
    return path.join(fs.realpathSync(current), ...missing);
  } catch {
    return target;
  }
}

// Folders the user opened Studio on besides the Otter installation itself:
// `otter studio C:\work\my-app` (OTTER_STUDIO_WORKSPACES, separated by the
// platform's path delimiter) or `node serve.mjs --workspace <folder>`.
// A user's projects rarely live inside the Otter install; each of these
// folders gets exactly the same trust as the install folder, no more.
const WORKSPACE_ROOTS = (() => {
  // ...and folders opened through Open Folder > This computer before.
  const named = [...String(process.env.OTTER_STUDIO_WORKSPACES || '').split(path.delimiter), ...loadSavedRoots()];
  for (let i = 2; i < process.argv.length - 1; i++) {
    if (process.argv[i] === '--workspace') named.push(process.argv[i + 1]);
  }
  const roots = [];
  for (const entry of named) {
    if (!entry || !entry.trim()) continue;
    const full = path.resolve(entry.trim());
    try {
      if (fs.statSync(full).isDirectory()) roots.push({ root: full, real: fs.realpathSync(full) });
    } catch { /* a folder that does not exist is simply not opened */ }
  }
  return roots;
})();

// Open Folder > This computer: the chosen folder becomes a workspace root
// (remembered), unless it is already inside one. Returns its workspace path.
function openComputerFolder(folder) {
  const full = path.resolve(String(folder || ''));
  if (!folder || !fs.existsSync(full) || !fs.statSync(full).isDirectory()) {
    const err = new Error('That folder does not exist.');
    err.status = 404;
    throw err;
  }
  if (isDriveRoot(full)) {
    const err = new Error('Choose the project folder itself, not a whole drive.');
    err.status = 400;
    throw err;
  }
  if (!isInsideRepo(full)) {
    WORKSPACE_ROOTS.push({ root: full, real: fs.realpathSync(full) });
    saveRoot(full);
  }
  return path.relative(REPO_ROOT, full).split(path.sep).join('/') || '.';
}

function isInsideRepo(target) {
  const realTarget = realPathOfNearest(target);
  if (isInside(REPO_ROOT, target, path) && isInside(REPO_ROOT_REAL, realTarget, path)) return true;
  return WORKSPACE_ROOTS.some(w => isInside(w.root, target, path) && isInside(w.real, realTarget, path));
}

// The integrated terminal's persistent shells (server/terminal-sessions.mjs);
// they end with the server.
const terminals = createTerminalManager({ repoRoot: REPO_ROOT, isInsideRepo });
for (const signal of ['exit', 'SIGINT', 'SIGTERM']) {
  process.on(signal, () => { terminals.closeAll(); if (signal !== 'exit') process.exit(0); });
}

const PORT = Number(process.env.OTTER_STUDIO_PORT || 4200);
const ANALYZER_PATH = path.join(REPO_ROOT, 'tools', 'vscode-otter', 'scripts', 'analyze.ps1');
const workspaceSymbolCache = new Map();
// The one program started with Run (see server/launch.mjs).
const runState = { process: null, lastLaunch: null };

// Debugger (first slice): sessionId -> { child, events: [], output: [],
// finished: bool, exitCode: number|null, buffer: string }. Each session is a
// real, separate `otter.ps1 debug` process (src/Otter.Debugger.psm1) - this
// map is pure relay bookkeeping, never a second interpreter. See the
// "@@OTTER_DEBUG@@ " line protocol documented in that module: any stdout
// line with that prefix is a debug event (JSON after the prefix), and every
// other line is exactly what the Otter program itself printed via `say`.
const debugSessions = new Map();
const OTTER_DEBUG_EVENT_PREFIX = '@@OTTER_DEBUG@@ ';

// Breakpoints for the debugger: { line, condition?, log? }, valid lines only.
function debugBreakpointList(list) {
  const out = [];
  for (const b of list) {
    const line = Number.isInteger(b) ? b : Number(b && b.line);
    if (!Number.isInteger(line) || line <= 0) continue;
    const entry = { line };
    if (b && typeof b.condition === 'string' && b.condition.trim()) entry.condition = b.condition.replace(/[\r\n]+/g, ' ').trim();
    if (b && typeof b.log === 'string' && b.log.trim()) entry.log = b.log.replace(/[\r\n]+/g, ' ').trim();
    out.push(entry);
  }
  return out;
}

function pumpDebugSessionOutput(session, chunk) {
  session.buffer += chunk;
  const lines = session.buffer.split('\n');
  session.buffer = lines.pop(); // last entry may be a partial line - keep it
  for (const rawLine of lines) {
    const line = rawLine.endsWith('\r') ? rawLine.slice(0, -1) : rawLine;
    if (line.startsWith(OTTER_DEBUG_EVENT_PREFIX)) {
      try {
        session.events.push(JSON.parse(line.slice(OTTER_DEBUG_EVENT_PREFIX.length)));
      } catch {
        // A malformed protocol line is a bug worth seeing, not silently
        // dropping - surface it as ordinary program output instead of
        // pretending it never happened.
        session.output.push(line);
      }
    } else if (line.length > 0) {
      session.output.push(line);
    }
  }
}

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.txt': 'text/plain; charset=utf-8',
  '.ot': 'text/plain; charset=utf-8'
};

// JSON body with a size limit (server/security.mjs). A body over the limit
// rejects with err.status 413, which the request handler turns into a reply.
function readBody(req) {
  return readJsonBody(req);
}

function sendJson(res, data, status = 200) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(data));
}

function readFileSnapshot(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const stats = fs.statSync(filePath);
  const revision = crypto.createHash('sha256').update(content, 'utf8').digest('hex');
  return {
    content,
    revision,
    modifiedAt: stats.mtime.toISOString(),
    size: stats.size
  };
}

const IGNORED_DIR_NAMES = new Set([
  '.git', 'node_modules', 'dist', 'build', 'backup', 'bin', 'obj',
  '.cache', '.playwright-mcp', '.vs', '.vscode', '.system_generated'
]);

function scanDir(dirPath, relativeTo, depth = 0, state = { totalNodes: 0 }) {
  if (depth > 12 || state.totalNodes >= 5000) {
    return [];
  }
  try {
    const entries = fs.readdirSync(dirPath, { withFileTypes: true });
    const result = [];
    for (const entry of entries) {
      if (state.totalNodes >= 5000) break;
      if (entry.isDirectory() && IGNORED_DIR_NAMES.has(entry.name)) {
        continue;
      }
      const fullPath = path.join(dirPath, entry.name);
      const relPath = path.relative(relativeTo, fullPath).replace(/\\/g, '/');
      state.totalNodes++;

      if (entry.isDirectory()) {
        result.push({
          name: entry.name,
          path: relPath,
          isDir: true,
          children: scanDir(fullPath, relativeTo, depth + 1, state)
        });
      } else {
        let size = 0;
        try { size = fs.statSync(fullPath).size; } catch {}
        result.push({
          name: entry.name,
          path: relPath,
          isDir: false,
          size
        });
      }
    }
    return result;
  } catch {
    return [];
  }
}

function collectOtterFiles(dirPath) {
  const ignored = new Set(['.git', 'node_modules', 'dist', 'build', 'backup']);
  const files = [];
  for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
    if (entry.isDirectory() && ignored.has(entry.name)) continue;
    const fullPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) files.push(...collectOtterFiles(fullPath));
    else if (entry.isFile() && entry.name.toLowerCase().endsWith('.ot')) files.push(fullPath);
  }
  return files;
}

function collectWorkspaceTextFiles(dirPath) {
  const ignored = new Set(['.git', 'node_modules', 'dist', 'build', 'backup']);
  const extensions = new Set(['.ot', '.css', '.json', '.md', '.txt', '.html', '.js', '.mjs']);
  const files = [];
  for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
    if (entry.isDirectory() && ignored.has(entry.name)) continue;
    const fullPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) files.push(...collectWorkspaceTextFiles(fullPath));
    else if (entry.isFile() && extensions.has(path.extname(entry.name).toLowerCase())) files.push(fullPath);
  }
  return files;
}

// Real render: compile Otter source with the production web compiler
// (`otter.ps1 web`) so Studio previews exactly what a user's program produces.
// Results are cached by content hash; renders run one at a time.
const renderCache = new Map();
// One compiler process kept loaded for renders (server/render-worker.mjs).
const renderWorker = createRenderWorker({ repoRoot: REPO_ROOT });
process.on('exit', () => renderWorker.stop());
let renderQueue = Promise.resolve();

// A render of a document from a project folder depends on the files it
// imports, not only on its own text: fold their names and modification
// times into the cache key so an edit to components/cards.ot re-renders.
function folderFingerprint(dir) {
  const parts = [];
  const skip = new Set(['node_modules', 'dist', 'dist-electron', '.git', '.otter']);
  const walk = (current, depth) => {
    if (depth > 4) return;
    let entries = [];
    try { entries = fs.readdirSync(current, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) { if (!skip.has(entry.name)) walk(full, depth + 1); continue; }
      if (!/\.(ot|css|svg|json)$/i.test(entry.name)) continue;
      try { parts.push(full + ':' + fs.statSync(full).mtimeMs); } catch { /* removed meanwhile */ }
    }
  };
  walk(dir, 0);
  return parts.sort().join('|');
}

// Workspace folders are served read-only under /workspace-files/<id>/ so a
// rendered page can load its own images: <base href> points there.
function workspaceFilesBase(dir) {
  return '/workspace-files/' + Buffer.from(dir, 'utf8').toString('base64url') + '/';
}

// Where a live run starts: the entry point of the project the document
// belongs to (otter.json / project.json), or the document itself.
function liveEntryFor(documentPath) {
  let dir = path.dirname(documentPath);
  while (isInsideRepo(dir)) {
    for (const name of ['otter.json', 'project.json']) {
      const manifest = path.join(dir, name);
      if (!fs.existsSync(manifest)) continue;
      try {
        const data = JSON.parse(fs.readFileSync(manifest, 'utf8'));
        const entry = data.entryPoint || data.main;
        if (typeof entry === 'string' && entry.trim()) {
          const full = path.resolve(dir, entry.trim());
          if (isInsideRepo(full) && fs.existsSync(full)) return full;
        }
      } catch { /* an unreadable manifest: run the document itself */ }
      return documentPath;
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return documentPath;
}

// sourceDir: the folder the document really lives in (its imports, icons,
// stylesheet and images resolve from there); '' for a document with no file.
// baseDir: where the page's images are served from, when that is not
// sourceDir (a render from the project mirror: server/project-mirror.mjs).
// abandoned(): the requester has gone (a newer render replaced it) - then a
// compile still waiting in the queue is skipped, so a slow project's
// superseded renders do not hold up the one that matters.
// The rule otter build uses (Get-OtterWebPageFiles): a page file declares a
// page and shows it.
function isWebPageSource(code) {
  return /^\s*[A-Za-z_]\w*\s+is\s+an?\s+page\b/m.test(code) && /^\s*show\s+[A-Za-z_]/m.test(code);
}

function renderOtterSource(code, css, sourceDir = '', baseDir = sourceDir, { abandoned = () => false, entryName = '' } = {}) {
  const fingerprint = sourceDir ? sourceDir + '\u0000' + folderFingerprint(sourceDir) : '';
  const key = crypto.createHash('sha256').update(code + '\u0000' + css + '\u0000' + fingerprint).digest('hex').slice(0, 24);
  if (renderCache.has(key)) return Promise.resolve(renderCache.get(key));
  const job = renderQueue.then(() => new Promise(resolve => {
    if (abandoned()) return resolve({ ok: false, message: 'Replaced by a newer render.' });
    // The copy has the entry's own name (main.ot beside main.css), in a
    // folder of its own: a compiler given -SourceDirectory looks for the
    // stylesheet named after the file it compiles.
    const dir = path.join(os.tmpdir(), 'otter-studio-render', key);
    fs.mkdirSync(dir, { recursive: true });
    const stem = /^[A-Za-z0-9_.-]+\.ot$/.test(entryName) ? entryName.slice(0, -3) : 'main';
    const sourcePath = path.join(dir, `${stem}.ot`);
    const htmlPath = path.join(dir, `${stem}.html`);
    fs.writeFileSync(sourcePath, code, 'utf8');
    const cssPath = path.join(dir, `${stem}.css`);
    if (css) fs.writeFileSync(cssPath, css, 'utf8'); else fs.rmSync(cssPath, { force: true });
    // compiled: the page was written; code: the compiler's exit code.
    const settle = (compiled, message, code) => {
      let result;
      if (compiled && fs.existsSync(htmlPath)) {
        let html = fs.readFileSync(htmlPath, 'utf8').replace(/^\uFEFF/, '');
        if (baseDir) html = html.replace(/<head>/i, `<head>\n  <base href="${workspaceFilesBase(baseDir)}">`);
        result = { ok: true, html };
        if (renderCache.size > 50) renderCache.delete(renderCache.keys().next().value);
        renderCache.set(key, result);
      } else {
        result = { ok: false, message: String(message || 'Render failed.').trim() };
        // A program the compiler rejects (exit 2) is rejected the same way
        // next time: the designer re-renders often, and a large project takes
        // seconds per compile. A crash or a timeout is not remembered.
        if (code === 2) {
          if (renderCache.size > 50) renderCache.delete(renderCache.keys().next().value);
          renderCache.set(key, result);
        }
      }
      fs.rmSync(dir, { recursive: true, force: true });
      resolve(result);
    };
    // The compiler process Studio keeps loaded (server/render-worker.mjs);
    // if it cannot be used, a fresh `otter web` process as before.
    renderWorker.compile({ source: sourcePath, output: htmlPath, sourceDir }).then((reply) => {
      if (reply) return settle(reply.ok, reply.message, reply.ok ? 0 : reply.code);
      const args = [
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', path.join(REPO_ROOT, 'otter.ps1'), 'web', sourcePath, '-NoOpen'
      ];
      if (sourceDir) args.push('-SourceDir', sourceDir);
      // A multi-file application takes longer to compile than a one-screen form.
      execFile('powershell.exe', args, { cwd: REPO_ROOT, windowsHide: true, timeout: 180000 }, (error, stdout, stderr) => {
        settle(!error, stdout || stderr || (error && error.message), error ? error.code : 0);
      });
    });
  }));
  renderQueue = job;
  return job;
}

function analyzeOtterSource(source) {
  return new Promise((resolve, reject) => {
    const child = spawn('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy', 'Bypass',
      '-File', ANALYZER_PATH,
      '-Root', REPO_ROOT
    ], { cwd: REPO_ROOT, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', () => {
      try {
        resolve(JSON.parse(stdout.trim()));
      } catch {
        reject(new Error(stderr.trim() || 'Otter symbol analysis did not return valid JSON.'));
      }
    });
    child.stdin.end(source);
  });
}

async function mapWithConcurrency(items, concurrency, worker) {
  const results = new Array(items.length);
  let next = 0;
  async function run() {
    while (next < items.length) {
      const index = next;
      next += 1;
      results[index] = await worker(items[index], index);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, run));
  return results;
}

async function analyzeOtterFile(filePath) {
  const snapshot = readFileSnapshot(filePath);
  const cached = workspaceSymbolCache.get(filePath);
  if (cached?.revision === snapshot.revision) return cached.analysis;
  const analysis = await analyzeOtterSource(snapshot.content);
  workspaceSymbolCache.set(filePath, { revision: snapshot.revision, analysis });
  return analysis;
}

const server = http.createServer(async (req, res) => {
  try {
    await handleRequest(req, res);
  } catch (err) {
    // A body over the size limit (413) or any unexpected failure: answer
    // instead of leaving the connection hanging.
    if (!res.headersSent) sendJson(res, { error: err.message }, err.status || 500);
    else res.end();
  }
});

async function handleRequest(req, res) {
  // Only Studio's own page on this computer may use the server; see
  // server/security.mjs. No CORS headers are sent, so other web pages can
  // neither call the API nor read its answers.
  const refusal = checkRequest(req.headers, PORT);
  if (refusal) return sendJson(res, { error: refusal.error }, refusal.status);

  const urlObj = new URL(req.url, `http://localhost:${PORT}`);
  const pathname = urlObj.pathname;

  // Hardening headers on every reply: no MIME sniffing, no framing of
  // Studio by other sites, and no referrer leaking workspace paths.
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'SAMEORIGIN');
  res.setHeader('Referrer-Policy', 'no-referrer');

  // A rendered program's own images and stylesheets (see workspaceFilesBase):
  // read-only, media types only, and only inside an opened workspace.
  if (pathname.startsWith('/workspace-files/') && req.method === 'GET') {
    const rest = pathname.slice('/workspace-files/'.length);
    const slash = rest.indexOf('/');
    let baseDir = '';
    try { baseDir = slash > 0 ? Buffer.from(rest.slice(0, slash), 'base64url').toString('utf8') : ''; } catch { baseDir = ''; }
    const relative = slash > 0 ? decodeURIComponent(rest.slice(slash + 1)) : '';
    const target = baseDir ? path.resolve(baseDir, relative) : '';
    const ext = path.extname(target).toLowerCase();
    const servable = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.css', '.woff', '.woff2', '.ico']);
    if (!target || !servable.has(ext) || !isInsideRepo(target) || !fs.existsSync(target) || !fs.statSync(target).isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Not found');
      return;
    }
    const types = { '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.webp': 'image/webp', '.woff': 'font/woff', '.woff2': 'font/woff2', '.ico': 'image/x-icon' };
    res.writeHead(200, { 'Content-Type': MIME_TYPES[ext] || types[ext] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
    fs.createReadStream(target).pipe(res);
    return;
  }

  // Explorer: new file/folder, rename, move, delete, reveal (server/fs-ops.mjs).
  if (await handleFsRoutes(req, res, pathname, { repoRoot: REPO_ROOT, isInsideRepo, readBody, sendJson })) return;

  // --- Open Folder > This computer (server/computer-folders.mjs) ---
  if (pathname === '/api/computer/folders' && req.method === 'GET') {
    try {
      return sendJson(res, listComputerFolder(urlObj.searchParams.get('path') || ''));
    } catch (err) {
      return sendJson(res, { error: err.message }, err.status || 500);
    }
  }
  if (pathname === '/api/workspace/open' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      return sendJson(res, { path: openComputerFolder(body.path) });
    } catch (err) {
      return sendJson(res, { error: err.message }, err.status || 500);
    }
  }
  if (handleHistoryRoutes(req, res, pathname, urlObj, { repoRoot: REPO_ROOT, isInsideRepo, sendJson })) return;
  if (handleEditorConfigRoute(req, res, pathname, urlObj, { repoRoot: REPO_ROOT, isInsideRepo, sendJson })) return;
  // The Designer's Assets tab: list, show and import images (server/assets.mjs).
  if (await handleAssetRoutes(req, res, pathname, urlObj, { repoRoot: REPO_ROOT, isInsideRepo, readBody, sendJson })) return;
  // Restricted Mode: trusted folders, remembered on this computer (server/trust.mjs).
  if (await handleTrustRoutes(req, res, pathname, urlObj, { repoRoot: REPO_ROOT, isInsideRepo, readBody, sendJson })) return;
  // The project stylesheet, found as the compiler finds it (server/stylesheet.mjs).
  if (handleStylesheetRoute(req, res, pathname, urlObj, { repoRoot: REPO_ROOT, isInsideRepo, sendJson })) return;

  // Run, launch profiles, build and clean (server/launch.mjs).
  if (await handleLaunchRoutes(req, res, pathname, urlObj, {
    repoRoot: REPO_ROOT, isInsideRepo, readBody, sendJson, readFileSnapshot, runState
  })) return;

  // Test Explorer (server/tests.mjs): discovery and `otter test <file>`.
  if (await handleTestRoutes(req, res, pathname, urlObj, {
    repoRoot: REPO_ROOT, isInsideRepo, readBody, sendJson
  })) return;

  // Source control (server/git.mjs), backed by the git command line.
  if (await handleGitRoutes(req, res, pathname, urlObj, {
    repoRoot: REPO_ROOT, isInsideRepo, readBody, sendJson
  })) return;

  // --- Real Folder & File APIs ---
  if (pathname === '/api/project' && req.method === 'GET') {
    try {
      const folderParam = urlObj.searchParams.get('folder');
      if (!folderParam) {
        return sendJson(res, { name: null, rootPath: null, tree: [] });
      }
      const projectRoot = path.resolve(REPO_ROOT, folderParam);
      if (!isInsideRepo(projectRoot) || !fs.existsSync(projectRoot)) {
        return sendJson(res, { error: 'Folder not found' }, 404);
      }
      const tree = scanDir(projectRoot, projectRoot);
      sendJson(res, {
        name: path.basename(projectRoot),
        rootPath: path.relative(REPO_ROOT, projectRoot).replace(/\\/g, '/'),
        tree
      });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/file' && req.method === 'GET') {
    try {
      const relPath = urlObj.searchParams.get('path');
      if (!relPath) {
        return sendJson(res, { error: 'Path parameter required' }, 400);
      }
      const safePath = path.resolve(REPO_ROOT, relPath);
      if (!isInsideRepo(safePath)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }
      if (!fs.existsSync(safePath)) {
        return sendJson(res, { error: 'File not found' }, 404);
      }
      const snapshot = readFileSnapshot(safePath);
      sendJson(res, { path: relPath, ...snapshot });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/file-status' && req.method === 'GET') {
    try {
      const relPath = urlObj.searchParams.get('path');
      if (!relPath) {
        return sendJson(res, { error: 'Path parameter required' }, 400);
      }
      const safePath = path.resolve(REPO_ROOT, relPath);
      if (!isInsideRepo(safePath)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }
      if (!fs.existsSync(safePath)) {
        return sendJson(res, { path: relPath, exists: false });
      }
      const snapshot = readFileSnapshot(safePath);
      sendJson(res, {
        path: relPath,
        exists: true,
        revision: snapshot.revision,
        modifiedAt: snapshot.modifiedAt,
        size: snapshot.size
      });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/file' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      // A save must name its file. This used to default to
      // examples/file-organizer/main.ot, so a request that lost its path
      // overwrote a shipped example.
      const relPath = typeof body.path === 'string' ? body.path.trim() : '';
      if (!relPath) {
        return sendJson(res, { error: 'A file path is required.' }, 400);
      }
      const safePath = path.resolve(REPO_ROOT, relPath);
      if (!isInsideRepo(safePath) || safePath === REPO_ROOT) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }
      // Overwriting an existing file requires the revision the editor read
      // it at. A save without one (a buffer that never came from disk) could
      // only replace the file blindly, so it is reported as a conflict, like
      // a stale revision. `force: true` is the explicit "overwrite anyway".
      if (fs.existsSync(safePath) && body.force !== true) {
        const current = readFileSnapshot(safePath);
        if (current.revision !== body.expectedRevision) {
          return sendJson(res, {
            error: body.expectedRevision
              ? 'The file changed on disk after it was opened.'
              : 'The file already exists on disk, and this copy was not opened from it.',
            conflict: true,
            path: relPath,
            ...current
          }, 409);
        }
      }
      // Local History: what was on disk (if it was never recorded, e.g. an
      // edit made outside Studio) and what is saved now.
      const historyRel = path.relative(REPO_ROOT, safePath).split(path.sep).join('/');
      if (fs.existsSync(safePath) && fs.statSync(safePath).isFile()) {
        recordVersion(safePath, historyRel, fs.readFileSync(safePath, 'utf8'), 'before save');
      }
      fs.writeFileSync(safePath, body.content || '', 'utf8');
      recordVersion(safePath, historyRel, body.content || '', 'save');
      const saved = readFileSnapshot(safePath);
      sendJson(res, { ok: true, path: relPath, ...saved });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/create-file' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const fileName = body.name || 'untitled.ot';
      const targetDir = path.resolve(REPO_ROOT, body.folder || 'examples/file-organizer');
      const safePath = path.join(targetDir, fileName);
      if (!isInsideRepo(safePath)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }
      if (fs.existsSync(safePath)) {
        return sendJson(res, { error: 'File already exists' }, 400);
      }
      fs.writeFileSync(safePath, body.content || '', 'utf8');
      const relPath = path.relative(REPO_ROOT, safePath).replace(/\\/g, '/');
      sendJson(res, { ok: true, path: relPath, name: fileName });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  // A project name that is not taken yet: my-app, my-app-2, my-app-3...
  if (pathname === '/api/suggest-project-name' && req.method === 'GET') {
    const base = String(urlObj.searchParams.get('name') || 'my-app').trim().replace(/[^a-zA-Z0-9_\-\.]/g, '-') || 'my-app';
    const projectsDir = path.join(REPO_ROOT, 'projects');
    let candidate = base;
    for (let n = 2; fs.existsSync(path.join(projectsDir, candidate)) && n < 1000; n++) candidate = `${base}-${n}`;
    return sendJson(res, { name: candidate });
  }

  if (pathname === '/api/create-project' && req.method === 'POST') {
    // What a new project keeps out of Git: its build output (build.outputDir,
    // "dist" by default), dependencies, and OS/editor files.
    const projectGitignore = (manifest) => {
      const out = String(manifest?.build?.outputDir || 'dist').replace(/\\/g, '/').replace(/^\.?\/+|\/+$/g, '') || 'dist';
      return [
        '# Build output (project.json build.outputDir)',
        `/${out}/`,
        '',
        '# Dependencies',
        'node_modules/',
        '',
        '# Logs and temporary files',
        '*.log',
        '*.tmp',
        '',
        '# Operating system and editor files',
        '.DS_Store',
        'Thumbs.db',
        'desktop.ini',
        '.vscode/',
        '.vs/',
        '*.swp',
        ''
      ].join('\n');
    };
    try {
      const body = await readBody(req);
      const rawName = (body.name || 'my-app').trim();
      const projName = rawName.replace(/[^a-zA-Z0-9_\-\.]/g, '-');
      const baseDirName = body.baseDir || 'projects';
      const targetBase = path.resolve(REPO_ROOT, baseDirName);
      if (!fs.existsSync(targetBase)) {
        fs.mkdirSync(targetBase, { recursive: true });
      }
      const projectDir = path.join(targetBase, projName);
      if (!isInsideRepo(projectDir) || !isInsideRepo(targetBase)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }
      // Never write over an existing project: creating "my-app" twice used to
      // silently replace the first one's files.
      if (fs.existsSync(projectDir) && fs.readdirSync(projectDir).length > 0 && body.overwrite !== true) {
        return sendJson(res, {
          error: `A project named "${projName}" already exists.`,
          exists: true,
          folder: path.relative(REPO_ROOT, projectDir).replace(/\\/g, '/')
        }, 409);
      }
      if (!fs.existsSync(projectDir)) {
        fs.mkdirSync(projectDir, { recursive: true });
      }

      // 1. Write main Otter code file
      const fileName = body.fileName || 'main.ot';
      const mainPath = path.join(projectDir, fileName);
      fs.writeFileSync(mainPath, body.code || `# ${projName}\n\nsay "Hello from ${projName}!"\n`, 'utf8');

      // 2. The stylesheet: <entry>.css beside the entry (main.ot -> main.css),
      // the one stylesheet every Otter compiler reads for it (D125).
      if (body.css || body.archetype === 'desktop' || body.archetype === 'web') {
        const sheet = `${path.basename(fileName, path.extname(fileName))}.css`;
        fs.writeFileSync(path.join(projectDir, sheet), body.css || '/* Otter Stylesheet */\n', 'utf8');
      }

      // 3. Write rich project.json metadata
      const manifest = createDefaultManifest(projName, body.archetype || 'desktop', fileName, {
        description: body.description,
        author: body.author,
        version: body.version || '1.0.0'
      });
      manifest.main = fileName;
      fs.writeFileSync(path.join(projectDir, 'project.json'), serializeManifest(manifest), 'utf8');

      // 4. A .gitignore for the build output and editor clutter (unless the
      // user unticked it, or the folder already has one).
      const gitignorePath = path.join(projectDir, '.gitignore');
      if (body.gitignore !== false && !fs.existsSync(gitignorePath)) {
        fs.writeFileSync(gitignorePath, projectGitignore(manifest), 'utf8');
      }

      const relFolder = path.relative(REPO_ROOT, projectDir).replace(/\\/g, '/');
      const tree = scanDir(projectDir, projectDir);

      sendJson(res, {
        ok: true,
        folder: relFolder,
        name: projName,
        mainFile: `${relFolder}/${fileName}`,
        tree,
        manifest
      });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/project-manifest' && req.method === 'GET') {
    try {
      const folderParam = urlObj.searchParams.get('folder') || '';
      const filePathParam = urlObj.searchParams.get('path');
      let targetFile = null;
      let projectDir = null;

      if (filePathParam) {
        targetFile = path.resolve(REPO_ROOT, filePathParam);
        projectDir = path.dirname(targetFile);
      } else if (folderParam) {
        projectDir = path.resolve(REPO_ROOT, folderParam);
        targetFile = path.join(projectDir, 'project.json');
      } else {
        return sendJson(res, { error: 'Folder or path parameter is required' }, 400);
      }

      if (!isInsideRepo(targetFile) || !fs.existsSync(targetFile)) {
        return sendJson(res, { error: 'project.json not found' }, 404);
      }

      const raw = fs.readFileSync(targetFile, 'utf8');
      const parsed = JSON.parse(raw);
      const normalized = normalizeManifest(parsed);
      const projectTree = scanDir(projectDir, projectDir);
      const validation = validateManifest(normalized, projectTree);

      sendJson(res, {
        ok: true,
        path: path.relative(REPO_ROOT, targetFile).replace(/\\/g, '/'),
        folder: path.relative(REPO_ROOT, projectDir).replace(/\\/g, '/'),
        manifest: normalized,
        validation
      });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/project-manifest' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const folderParam = body.folder || '';
      const filePathParam = body.path;
      let targetFile = null;
      let projectDir = null;

      if (filePathParam) {
        targetFile = path.resolve(REPO_ROOT, filePathParam);
        projectDir = path.dirname(targetFile);
      } else if (folderParam) {
        projectDir = path.resolve(REPO_ROOT, folderParam);
        targetFile = path.join(projectDir, 'project.json');
      } else {
        return sendJson(res, { error: 'Folder or path parameter is required' }, 400);
      }

      if (!isInsideRepo(targetFile)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }

      if (!body.manifest || typeof body.manifest !== 'object') {
        return sendJson(res, { error: 'Manifest object is required' }, 400);
      }

      const normalized = normalizeManifest(body.manifest);
      const projectTree = fs.existsSync(projectDir) ? scanDir(projectDir, projectDir) : [];
      const validation = validateManifest(normalized, projectTree);

      if (!validation.ok && body.force !== true) {
        return sendJson(res, {
          ok: false,
          error: 'Manifest validation failed',
          validation
        }, 422);
      }

      const serialized = serializeManifest(normalized);
      fs.writeFileSync(targetFile, serialized, 'utf8');

      sendJson(res, {
        ok: true,
        path: path.relative(REPO_ROOT, targetFile).replace(/\\/g, '/'),
        manifest: normalized,
        validation
      });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/workspace' && req.method === 'GET') {
    try {
      const solutionPath = urlObj.searchParams.get('path') || 'solution.json';
      const targetFile = path.resolve(REPO_ROOT, solutionPath);
      if (!isInsideRepo(targetFile) || !fs.existsSync(targetFile)) {
        return sendJson(res, { error: 'Solution file not found' }, 404);
      }

      const raw = fs.readFileSync(targetFile, 'utf8');
      const parsed = JSON.parse(raw);
      const normalized = normalizeSolution(parsed);
      const validation = validateSolution(normalized);

      const roots = [];
      for (const folder of normalized.folders) {
        const rootPath = path.resolve(REPO_ROOT, folder.path);
        if (isInsideRepo(rootPath) && fs.existsSync(rootPath)) {
          let manifest = null;
          const projJson = path.join(rootPath, 'project.json');
          if (fs.existsSync(projJson)) {
            try {
              manifest = normalizeManifest(JSON.parse(fs.readFileSync(projJson, 'utf8')));
            } catch {}
          }
          roots.push({
            name: folder.name || path.basename(rootPath),
            path: path.relative(REPO_ROOT, rootPath).replace(/\\/g, '/'),
            manifest,
            tree: scanDir(rootPath, rootPath)
          });
        }
      }

      sendJson(res, {
        ok: true,
        path: path.relative(REPO_ROOT, targetFile).replace(/\\/g, '/'),
        solution: normalized,
        validation,
        roots
      });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/workspace' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const solutionPath = body.path || 'solution.json';
      const targetFile = path.resolve(REPO_ROOT, solutionPath);
      if (!isInsideRepo(targetFile)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }

      if (!body.solution || typeof body.solution !== 'object') {
        return sendJson(res, { error: 'Solution object required' }, 400);
      }

      const normalized = normalizeSolution(body.solution);
      const validation = validateSolution(normalized);
      if (!validation.ok && body.force !== true) {
        return sendJson(res, { ok: false, error: 'Validation failed', validation }, 422);
      }

      const dir = path.dirname(targetFile);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(targetFile, serializeSolution(normalized), 'utf8');

      sendJson(res, {
        ok: true,
        path: path.relative(REPO_ROOT, targetFile).replace(/\\/g, '/'),
        solution: normalized,
        validation
      });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/create-solution' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const solName = (body.name || 'my-solution').trim();
      const solPath = body.path || `${solName}.solution.json`;
      const targetFile = path.resolve(REPO_ROOT, solPath);
      if (!isInsideRepo(targetFile)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }

      const solution = createDefaultSolution(solName, body.folders || [], body.settings || {}, body.trust || {});
      const dir = path.dirname(targetFile);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(targetFile, serializeSolution(solution), 'utf8');

      sendJson(res, {
        ok: true,
        path: path.relative(REPO_ROOT, targetFile).replace(/\\/g, '/'),
        solution
      });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/render' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      // `path` is the document being designed (relative to the Studio
      // root, or absolute inside an opened workspace). With `live`, the
      // run starts from its project's entry point.
      let code = String(body.code || '');
      let sourceDir = '';
      let baseDir = '';
      let entryName = '';
      if (typeof body.path === 'string' && body.path.trim()) {
        const documentPath = path.resolve(REPO_ROOT, body.path);
        if (isInsideRepo(documentPath)) {
          const entry = liveEntryFor(documentPath);
          const projectRoot = projectRootFor(documentPath, isInsideRepo);
          if (projectRoot) {
            // Compile the project's entry (a page like OtterBoard's shell.ot
            // alone lacks what the entry brings together) from a mirror of
            // the project with what is on screen in place: this document's
            // text and the designer's stylesheet, saved or not - for the
            // canvas and for Live App alike.
            const overlay = { [documentPath]: code };
            const sheet = String(body.css || '');
            if (sheet) overlay[resolveProjectStylesheet(projectRoot).path] = sheet;
            const mirror = syncMirror(projectRoot, overlay);
            // A page of a website (about.ot: it declares a page and shows it)
            // is its own page, built to about.html; anything else (a part of
            // a page, a module) runs as the project, from its entry.
            const target = isWebPageSource(String(body.code || '')) ? documentPath : (entry || documentPath);
            const mirrorEntry = path.join(mirror, path.relative(projectRoot, target));
            code = fs.readFileSync(mirrorEntry, 'utf8');
            sourceDir = path.dirname(mirrorEntry);
            baseDir = path.dirname(target);
            entryName = path.basename(target);
          } else {
            sourceDir = path.dirname(documentPath);
            baseDir = sourceDir;
            entryName = path.basename(documentPath);
          }
        }
      }
      let gone = false;
      res.on('close', () => { if (!res.writableFinished) gone = true; });
      const result = await renderOtterSource(code, String(body.css || ''), sourceDir, baseDir, { abandoned: () => gone, entryName });
      if (gone) return;
      sendJson(res, result, result.ok ? 200 : 422);
    } catch (err) {
      sendJson(res, { ok: false, message: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/analyze' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const analysis = await analyzeOtterSource(body.code || '');
      sendJson(res, analysis, analysis.Ok === false ? 422 : 200);
    } catch (err) {
      sendJson(res, { Ok: false, Message: err.message, Line: 1, Column: 0 }, 500);
    }
    return;
  }

  if (pathname === '/api/workspace-symbols' && req.method === 'GET') {
    try {
      const folderParam = urlObj.searchParams.get('folder');
      if (!folderParam) return sendJson(res, { files: [], symbols: [], diagnostics: [] });
      const workspaceRoot = path.resolve(REPO_ROOT, folderParam);
      if (!isInsideRepo(workspaceRoot) || !fs.existsSync(workspaceRoot)) {
        return sendJson(res, { error: 'Workspace folder not found' }, 404);
      }
      const otterFiles = collectOtterFiles(workspaceRoot).slice(0, 500);
      const analyses = await mapWithConcurrency(otterFiles, 4, async filePath => ({
        filePath,
        analysis: await analyzeOtterFile(filePath)
      }));
      const symbols = [];
      const diagnostics = [];
      // The names each file mentions, so a variable declared in one file and
      // read in another (through `use`) is not reported as never read.
      const words = {};
      for (const { filePath, analysis } of analyses) {
        const relativePath = path.relative(REPO_ROOT, filePath).replace(/\\/g, '/');
        try {
          words[relativePath] = [...new Set((fs.readFileSync(filePath, 'utf8').match(/[A-Za-z_][A-Za-z0-9_]*/g) || []).map(w => w.toLowerCase()))];
        } catch { /* unreadable: no names */ }
        if (analysis.Ok === false) {
          diagnostics.push({
            File: relativePath,
            Message: analysis.Message,
            Line: analysis.Line,
            Column: analysis.Column
          });
          continue;
        }
        for (const symbol of analysis.Symbols || []) {
          symbols.push({ ...symbol, File: relativePath });
        }
      }
      symbols.sort((left, right) => left.File.localeCompare(right.File) || Number(left.Line) - Number(right.Line));
      sendJson(res, {
        files: otterFiles.map(filePath => path.relative(REPO_ROOT, filePath).replace(/\\/g, '/')),
        symbols,
        diagnostics,
        words
      });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/search' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const query = String(body.query || '');
      if (!query) return sendJson(res, { results: [], filesSearched: 0, truncated: false });
      const folderParam = body.folder;
      if (!folderParam) return sendJson(res, { error: 'Workspace folder required' }, 400);
      const workspaceRoot = path.resolve(REPO_ROOT, folderParam);
      if (!isInsideRepo(workspaceRoot) || !fs.existsSync(workspaceRoot)) {
        return sendJson(res, { error: 'Workspace folder not found' }, 404);
      }

      const caseSensitive = body.caseSensitive === true;
      const useRegex = body.regex === true;
      let pattern = null;
      if (useRegex) {
        try {
          pattern = new RegExp(query, caseSensitive ? 'g' : 'gi');
        } catch (error) {
          return sendJson(res, { error: `Invalid regular expression: ${error.message}` }, 400);
        }
      }

      const files = collectWorkspaceTextFiles(workspaceRoot);
      const results = [];
      const maxResults = 500;
      for (const filePath of files) {
        if (results.length >= maxResults) break;
        const stats = fs.statSync(filePath);
        if (stats.size > 2 * 1024 * 1024) continue;
        const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
        for (let lineIndex = 0; lineIndex < lines.length && results.length < maxResults; lineIndex += 1) {
          const line = lines[lineIndex];
          const columns = [];
          if (pattern) {
            pattern.lastIndex = 0;
            let match;
            while ((match = pattern.exec(line)) !== null) {
              columns.push(match.index);
              if (match[0].length === 0) pattern.lastIndex += 1;
            }
          } else {
            const source = caseSensitive ? line : line.toLowerCase();
            const needle = caseSensitive ? query : query.toLowerCase();
            let cursor = 0;
            while (cursor <= source.length) {
              const found = source.indexOf(needle, cursor);
              if (found < 0) break;
              columns.push(found);
              cursor = found + Math.max(1, needle.length);
            }
          }
          for (const column of columns) {
            results.push({
              path: path.relative(REPO_ROOT, filePath).replace(/\\/g, '/'),
              line: lineIndex + 1,
              column,
              preview: line.trim()
            });
            if (results.length >= maxResults) break;
          }
        }
      }
      sendJson(res, {
        results,
        filesSearched: files.length,
        truncated: results.length >= maxResults
      });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/replace' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const query = String(body.query || '');
      const replaceWith = String(body.replace ?? '');
      if (!query) return sendJson(res, { error: 'Search query required' }, 400);
      const folderParam = body.folder;
      if (!folderParam) return sendJson(res, { error: 'Workspace folder required' }, 400);
      const workspaceRoot = path.resolve(REPO_ROOT, folderParam);
      if (!isInsideRepo(workspaceRoot) || !fs.existsSync(workspaceRoot)) {
        return sendJson(res, { error: 'Workspace folder not found' }, 404);
      }

      const caseSensitive = body.caseSensitive === true;
      const useRegex = body.regex === true;
      let pattern = null;
      if (useRegex) {
        try {
          pattern = new RegExp(query, caseSensitive ? 'g' : 'gi');
        } catch (error) {
          return sendJson(res, { error: `Invalid regular expression: ${error.message}` }, 400);
        }
      }

      const files = collectWorkspaceTextFiles(workspaceRoot);
      let filesModified = 0;
      let totalReplacements = 0;

      for (const filePath of files) {
        const stats = fs.statSync(filePath);
        if (stats.size > 2 * 1024 * 1024) continue;
        const original = fs.readFileSync(filePath, 'utf8');
        let updated = original;
        let fileMatches = 0;

        if (pattern) {
          pattern.lastIndex = 0;
          const matches = original.match(pattern);
          if (matches && matches.length > 0) {
            fileMatches = matches.length;
            updated = original.replace(pattern, replaceWith);
          }
        } else {
          const needle = caseSensitive ? query : query.toLowerCase();
          let count = 0;
          let idx = 0;
          const searchIn = caseSensitive ? original : original.toLowerCase();
          while ((idx = searchIn.indexOf(needle, idx)) !== -1) {
            count++;
            idx += needle.length;
          }
          if (count > 0) {
            fileMatches = count;
            if (caseSensitive) {
              updated = original.split(query).join(replaceWith);
            } else {
              const esc = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
              updated = original.replace(new RegExp(esc, 'gi'), replaceWith);
            }
          }
        }

        if (fileMatches > 0) {
          fs.writeFileSync(filePath, updated, 'utf8');
          filesModified++;
          totalReplacements += fileMatches;
        }
      }

      sendJson(res, {
        success: true,
        filesModified,
        totalReplacements
      });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  // --- Execution & Otter Runner API ---
  // --- Build -> Desktop App: runs `otter package --progress` and streams its
  // progress events and output as newline-delimited JSON. ---
  if (pathname === '/api/package' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const folder = String(body.folder || '');
      const projectDir = path.resolve(REPO_ROOT, folder);
      if (!folder || !isInsideRepo(projectDir) || !fs.existsSync(projectDir)) {
        return sendJson(res, { error: 'Project folder not found' }, 404);
      }
      const kinds = Array.isArray(body.kinds) ? body.kinds.filter(k => k === 'installer' || k === 'portable') : [];
      const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(REPO_ROOT, 'otter.ps1'),
        'package', projectDir, '--target', String(body.target || 'windows'), '--progress'];
      for (const kind of kinds) args.push('--' + kind);
      if (body.output) {
        // Studio shows repository-relative paths; the CLI resolves relative
        // paths against the folder it runs in, so hand it an absolute one.
        const outputDir = path.resolve(REPO_ROOT, String(body.output));
        if (!isInsideRepo(outputDir)) return sendJson(res, { error: 'The output folder must stay inside the workspace' }, 400);
        args.push('--output', outputDir);
      }
      if (body.dryRun) args.push('--dry-run');

      res.writeHead(200, { 'Content-Type': 'application/x-ndjson; charset=utf-8', 'Cache-Control': 'no-cache', 'X-Content-Type-Options': 'nosniff' });
      const send = (event) => res.write(JSON.stringify(event) + '\n');
      const env = { ...process.env };
      delete env.ELECTRON_RUN_AS_NODE; // an editor host's setting; it would turn Electron into plain Node
      const child = spawn('powershell.exe', args, { cwd: projectDir, windowsHide: true, env });
      let pending = '';
      const emitLine = (line) => {
        if (!line.trim()) return;
        if (line.startsWith('@otter-progress ')) {
          try { send({ type: 'progress', ...JSON.parse(line.slice('@otter-progress '.length)) }); return; } catch { /* fall through as a log line */ }
        }
        send({ type: 'log', text: line });
      };
      const onChunk = (chunk) => {
        pending += chunk.toString();
        let index;
        while ((index = pending.indexOf('\n')) >= 0) {
          emitLine(pending.slice(0, index).replace(/\r$/, ''));
          pending = pending.slice(index + 1);
        }
      };
      child.stdout.on('data', onChunk);
      child.stderr.on('data', onChunk);
      child.on('error', (err) => { send({ type: 'log', text: err.message }); send({ type: 'exit', code: 1 }); res.end(); });
      child.on('close', (code) => { if (pending.trim()) emitLine(pending); send({ type: 'exit', code: code === null ? 1 : code }); res.end(); });
      req.on('close', () => { if (child.exitCode === null) { try { exec(`taskkill /pid ${child.pid} /f /t`, () => {}); } catch {} } });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Show a folder inside the repository in the system file manager ---
  if (pathname === '/api/reveal' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const target = path.resolve(REPO_ROOT, String(body.path || ''));
      if (!body.path || !isInsideRepo(target) || !fs.existsSync(target)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }
      const opener = process.platform === 'win32' ? ['explorer.exe', [target]]
        : process.platform === 'darwin' ? ['open', [target]] : ['xdg-open', [target]];
      spawn(opener[0], opener[1], { detached: true, stdio: 'ignore', windowsHide: true }).unref();
      return sendJson(res, { revealed: true });
    } catch (err) {
      return sendJson(res, { error: err.message }, 500);
    }
  }

  // --- Open a built page (dist/index.html) in the system's browser. Not
  // served from Studio's origin: a built page must not reach Studio's API. ---
  if (pathname === '/api/open-page' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const target = path.resolve(REPO_ROOT, String(body.path || ''));
      if (!body.path || path.extname(target).toLowerCase() !== '.html' || !isInsideRepo(target) || !fs.existsSync(target)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }
      const opener = process.platform === 'win32' ? ['explorer.exe', [target]]
        : process.platform === 'darwin' ? ['open', [target]] : ['xdg-open', [target]];
      spawn(opener[0], opener[1], { detached: true, stdio: 'ignore', windowsHide: true }).unref();
      return sendJson(res, { opened: true });
    } catch (err) {
      return sendJson(res, { error: err.message }, 500);
    }
  }

  // --- Debugger (first slice): start/poll/continue/stop a real otter.ps1
  // debug session. See src/Otter.Debugger.psm1 for the protocol and
  // src/Otter.Interpreter.psm1's Set-OtterStatementHook for how the
  // production interpreter itself exposes the one hook this relies on. ---

  if (pathname === '/api/debug/start' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const relPath = body.path || 'examples/file-organizer/main.ot';
      const safePath = path.resolve(REPO_ROOT, relPath);
      if (!isInsideRepo(safePath)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }

      if (typeof body.content === 'string') {
        fs.writeFileSync(safePath, body.content, 'utf8');
      }

      const runDir = path.dirname(safePath);
      const scriptName = path.basename(safePath);
      // Breakpoints: line numbers, or { line, condition, log } (conditional
      // breakpoints and logpoints), which reach the debugger as JSON in
      // OTTER_DEBUG_BREAKPOINTS before the first statement runs.
      const list = Array.isArray(body.breakpoints) ? body.breakpoints : [];
      const detailed = debugBreakpointList(list);
      const breakpoints = detailed.map(b => b.line).join(',');
      const otterPs1 = path.join(REPO_ROOT, 'otter.ps1');

      const child = spawn('powershell.exe', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', otterPs1, 'debug', scriptName, '-Breakpoints', breakpoints
      ], { cwd: runDir, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, OTTER_DEBUG_BREAKPOINTS: JSON.stringify(detailed) } });

      const sessionId = crypto.randomUUID();
      const session = { child, events: [], output: [], finished: false, exitCode: null, buffer: '' };
      debugSessions.set(sessionId, session);

      child.stdout.on('data', chunk => pumpDebugSessionOutput(session, chunk.toString('utf8')));
      child.stderr.on('data', chunk => { session.output.push(chunk.toString('utf8').trimEnd()); });
      child.on('close', code => {
        if (session.buffer.length > 0) {
          pumpDebugSessionOutput(session, '\n');
        }
        session.finished = true;
        session.exitCode = code;
      });

      sendJson(res, { sessionId });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/debug/poll' && req.method === 'GET') {
    const sessionId = urlObj.searchParams.get('sessionId');
    const session = debugSessions.get(sessionId);
    if (!session) {
      return sendJson(res, { error: 'Unknown or expired debug session' }, 404);
    }

    const events = session.events.splice(0);
    const output = session.output.splice(0);
    const finished = session.finished;
    sendJson(res, { events, output, finished, exitCode: session.exitCode });

    // Nothing left to relay and the process is done - safe to forget it.
    if (finished && session.events.length === 0 && session.output.length === 0) {
      debugSessions.delete(sessionId);
    }
    return;
  }

  // Everything else a paused (or running) session understands - see the
  // command list in src/Otter.Debugger.psm1. Only those verbs pass, one line
  // each (a newline in an expression could smuggle in another command).
  if (pathname === '/api/debug/command' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const session = debugSessions.get(body.sessionId);
      if (!session) return sendJson(res, { error: 'Unknown or expired debug session' }, 404);
      const verb = String(body.command || '');
      let line;
      if (['continue', 'next', 'step', 'out', 'pause'].includes(verb)) line = verb;
      else if (verb === 'breakpoints') line = `breakpoints ${JSON.stringify(debugBreakpointList(Array.isArray(body.breakpoints) ? body.breakpoints : []))}`;
      else if (verb === 'eval') {
        const id = String(body.id || 'e').replace(/[^\w-]/g, '').slice(0, 40) || 'e';
        const expression = String(body.expression || '').replace(/[\r\n]+/g, ' ').trim();
        if (!expression) return sendJson(res, { error: 'Write an expression to evaluate.' }, 400);
        line = `eval ${id} ${expression}`;
      } else return sendJson(res, { error: `Unknown debugger command: ${verb}` }, 400);
      if (session.finished) return sendJson(res, { error: 'The program has finished.' }, 409);
      session.child.stdin.write(`${line}\n`);
      sendJson(res, { ok: true });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/debug/continue' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const session = debugSessions.get(body.sessionId);
      if (!session) {
        return sendJson(res, { error: 'Unknown or expired debug session' }, 404);
      }
      session.child.stdin.write('continue\n');
      sendJson(res, { ok: true });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  if (pathname === '/api/debug/stop' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const session = debugSessions.get(body.sessionId);
      if (!session) {
        return sendJson(res, { stopped: false, message: 'No such debug session' });
      }
      try {
        if (process.platform === 'win32') exec(`taskkill /pid ${session.child.pid} /f /t`, () => {});
        else session.child.kill('SIGTERM');
      } catch {}
      debugSessions.delete(body.sessionId);
      sendJson(res, { stopped: true });
    } catch (err) {
      sendJson(res, { error: err.message }, err.status || 500);
    }
    return;
  }

  // --- Integrated terminal: persistent shells (server/terminal-sessions.mjs).
  // It replaced POST /api/terminal, which ran each command in a new shell
  // through cmd.exe and stopped it after 15 seconds. ---
  if (await handleTerminalRoutes(req, res, pathname, urlObj, { sendJson, readBody }, terminals)) return;

  // --- Otter Diagnostics / Linter API ---
  if (pathname === '/api/lint' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const code = body.code || '';

      // Create a scratch file to parse
      const tempPath = path.join(REPO_ROOT, 'scratch', `_lint_${Date.now()}.ot`);
      fs.writeFileSync(tempPath, code, 'utf8');

      const psScript = `
        Import-Module (Join-Path '${REPO_ROOT}\\src' 'Otter.Lexer.psm1') -Global
        Import-Module (Join-Path '${REPO_ROOT}\\src' 'Otter.Parser.psm1') -Global
        try {
          $src = Get-Content -LiteralPath '${tempPath}' -Raw -Encoding UTF8
          $toks = ConvertTo-OtterTokens -Source $src
          $ast = ConvertTo-OtterAst -Tokens $toks
          [PSCustomObject]@{ ok = $true } | ConvertTo-Json
        } catch {
          # This child PowerShell process imports the Otter modules at runtime.
          # A typed OtterError catch is resolved before that import and can
          # fail to parse, which used to make invalid source look valid.
          $line = if ($_.Exception.PSObject.Properties['Line']) { $_.Exception.Line } else { 1 }
          $column = if ($_.Exception.PSObject.Properties['Column']) { $_.Exception.Column } else { 1 }
          $stage = if ($_.Exception.PSObject.Properties['Stage']) { $_.Exception.Stage } else { 'parser' }
          $sourceLine = if ($_.Exception.PSObject.Properties['SourceLine']) { $_.Exception.SourceLine } else { $null }
          $suggestion = if ($_.Exception.PSObject.Properties['Suggestion']) { $_.Exception.Suggestion } else { $null }
          $kind = if ($_.Exception.PSObject.Properties['Kind']) { $_.Exception.Kind } else { $null }
          [PSCustomObject]@{
            ok = $false
            message = $_.Exception.Message
            line = $line
            column = $column
            stage = $stage
            sourceLine = $sourceLine
            suggestion = $suggestion
            kind = $kind
          } | ConvertTo-Json
        } finally {
          Remove-Item -LiteralPath '${tempPath}' -ErrorAction SilentlyContinue
        }
      `;

      // Use -File instead of embedding PowerShell in a command-shell string.
      // The latter lets cmd.exe reinterpret diagnostics such as $_ and makes
      // Studio silently report an invalid document as valid.
      const lintScriptPath = path.join(REPO_ROOT, 'scratch', `_lint_${Date.now()}.ps1`);
      fs.writeFileSync(lintScriptPath, psScript, 'utf8');
      execFile('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', lintScriptPath], { cwd: REPO_ROOT, timeout: 5000 }, (error, stdout, stderr) => {
        fs.rmSync(lintScriptPath, { force: true });
        try {
          const parsed = JSON.parse(stdout.trim());
          sendJson(res, parsed);
        } catch {
          sendJson(res, {
            ok: false,
            message: stderr || error?.message || 'Otter could not check this document.',
            line: 1
          });
        }
      });
    } catch (err) {
      sendJson(res, { ok: false, message: err.message, line: 1 }, 500);
    }
    return;
  }

  // --- Static File Serving ---
  let reqPath = pathname;
  if (reqPath === '/' || reqPath === '') reqPath = '/index.html';

  // Serve Studio's own files only: never anything outside otter-studio/,
  // and never the server's source or tests.
  const filePath = path.resolve(__dirname, '.' + decodeURIComponent(reqPath));
  const relativeStatic = path.relative(__dirname, filePath).replace(/\\/g, '/');
  if (!isInside(__dirname, filePath, path) || /^(server|scripts|node_modules)\//.test(relativeStatic) || relativeStatic === 'serve.mjs' || relativeStatic.split('/').some(part => part.startsWith('.'))) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('404 Not Found');
    return;
  }

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('404 Not Found');
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    // no-cache = the browser checks back every time (a cheap 304 when the
    // file is unchanged). Without it, Chromium's heuristic cache - kept on
    // disk by the desktop app - could run an old copy of Studio's scripts
    // after the checkout was updated, even across restarts.
    const etag = `"${stats.size.toString(16)}-${Math.floor(stats.mtimeMs).toString(16)}"`;
    if (req.headers['if-none-match'] === etag) {
      res.writeHead(304, { ETag: etag, 'Cache-Control': 'no-cache' });
      res.end();
      return;
    }
    res.writeHead(200, { 'Content-Type': contentType, 'Cache-Control': 'no-cache', ETag: etag });
    fs.createReadStream(filePath).pipe(res);
  });
}

// Loopback only: other computers on the network cannot connect.
server.listen(PORT, LOOPBACK_HOST, () => {
  console.log(`Otter Studio running with Full Interaction Engine at: http://localhost:${PORT}`);
});
