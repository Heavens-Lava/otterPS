// serve.mjs - Local web server & real development backend for Otter Studio
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { exec, execFile, spawn } from 'node:child_process';
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

const PORT = Number(process.env.OTTER_STUDIO_PORT || 4200);
const ANALYZER_PATH = path.join(REPO_ROOT, 'tools', 'vscode-otter', 'scripts', 'analyze.ps1');
const workspaceSymbolCache = new Map();
let activeRunProcess = null;

// Debugger (first slice): sessionId -> { child, events: [], output: [],
// finished: bool, exitCode: number|null, buffer: string }. Each session is a
// real, separate `otter.ps1 debug` process (src/Otter.Debugger.psm1) - this
// map is pure relay bookkeeping, never a second interpreter. See the
// "@@OTTER_DEBUG@@ " line protocol documented in that module: any stdout
// line with that prefix is a debug event (JSON after the prefix), and every
// other line is exactly what the Otter program itself printed via `say`.
const debugSessions = new Map();
const OTTER_DEBUG_EVENT_PREFIX = '@@OTTER_DEBUG@@ ';

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

const MAX_BODY_SIZE = 10 * 1024 * 1024; // 10 MB DoS protection ceiling
const SESSION_TOKEN = process.env.OTTER_STUDIO_SESSION_TOKEN || crypto.randomBytes(24).toString('hex');

function isPathContained(candidatePath, rootDir = REPO_ROOT) {
  if (!candidatePath || typeof candidatePath !== 'string') return false;
  if (candidatePath.includes('\0')) return false;
  const normalizedRoot = path.resolve(rootDir);
  const resolved = path.resolve(normalizedRoot, candidatePath);
  if (resolved !== normalizedRoot && !resolved.startsWith(normalizedRoot + path.sep)) {
    return false;
  }
  try {
    if (fs.existsSync(resolved)) {
      const real = fs.realpathSync(resolved);
      const realRoot = fs.realpathSync(normalizedRoot);
      if (real !== realRoot && !real.startsWith(realRoot + path.sep)) {
        return false;
      }
    }
  } catch {
    // If target doesn't exist yet, string containment holds
  }
  return true;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    let size = 0;
    req.on('data', chunk => {
      size += chunk.length;
      if (size > MAX_BODY_SIZE) {
        req.destroy(new Error('PAYLOAD_TOO_LARGE'));
        return;
      }
      body += chunk;
    });
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (e) {
        resolve({ raw: body });
      }
    });
    req.on('error', (err) => {
      if (err && err.message === 'PAYLOAD_TOO_LARGE') {
        const error = new Error('Payload Too Large: maximum body size is 10 MB');
        error.statusCode = 413;
        reject(error);
      } else {
        reject(err);
      }
    });
  });
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
let renderQueue = Promise.resolve();

function renderOtterSource(code, css) {
  const key = crypto.createHash('sha256').update(code + '\u0000' + css).digest('hex').slice(0, 24);
  if (renderCache.has(key)) return Promise.resolve(renderCache.get(key));
  const job = renderQueue.then(() => new Promise(resolve => {
    const dir = path.join(os.tmpdir(), 'otter-studio-render');
    fs.mkdirSync(dir, { recursive: true });
    const sourcePath = path.join(dir, `${key}.ot`);
    const htmlPath = path.join(dir, `${key}.html`);
    fs.writeFileSync(sourcePath, code, 'utf8');
    const cssPath = path.join(dir, `${key}.css`);
    if (css) fs.writeFileSync(cssPath, css, 'utf8'); else fs.rmSync(cssPath, { force: true });
    execFile('powershell.exe', [
      '-NoProfile', '-ExecutionPolicy', 'Bypass',
      '-File', path.join(REPO_ROOT, 'otter.ps1'), 'web', sourcePath, '-NoOpen'
    ], { cwd: REPO_ROOT, windowsHide: true, timeout: 30000 }, (error, stdout, stderr) => {
      let result;
      if (!error && fs.existsSync(htmlPath)) {
        result = { ok: true, html: fs.readFileSync(htmlPath, 'utf8').replace(/^\uFEFF/, '') };
        if (renderCache.size > 50) renderCache.delete(renderCache.keys().next().value);
        renderCache.set(key, result);
      } else {
        const text = String(stdout || stderr || (error && error.message) || 'Render failed.').trim();
        result = { ok: false, message: text };
      }
      for (const f of [sourcePath, htmlPath, cssPath]) fs.rmSync(f, { force: true });
      resolve(result);
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
  const urlObj = new URL(req.url, `http://localhost:${PORT}`);
  const pathname = urlObj.pathname;

  // Origin check - reject untrusted cross-origin requests
  const origin = req.headers.origin;
  const isLoopbackOrigin = !origin || origin.startsWith('http://localhost:') || origin.startsWith('http://127.0.0.1:') || origin === 'null';
  if (origin && !isLoopbackOrigin) {
    res.writeHead(403, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ error: 'Forbidden: untrusted cross-origin request rejected' }));
    return;
  }

  // Security, CSP & CORS headers
  res.setHeader('Access-Control-Allow-Origin', origin || '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Otter-Session-Token');
  res.setHeader('Content-Security-Policy', "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob:; connect-src 'self' http://localhost:* http://127.0.0.1:*; frame-src 'self' blob: data:;");
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'SAMEORIGIN');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // Session Token API for CSRF protection
  if (pathname === '/api/session-token' && req.method === 'GET') {
    return sendJson(res, { token: SESSION_TOKEN });
  }

  // --- Real Folder & File APIs ---
  if (pathname === '/api/project' && req.method === 'GET') {
    try {
      const folderParam = urlObj.searchParams.get('folder');
      if (!folderParam) {
        return sendJson(res, { name: null, rootPath: null, tree: [] });
      }
      const projectRoot = path.resolve(REPO_ROOT, folderParam);
      if (!projectRoot.startsWith(REPO_ROOT) || !fs.existsSync(projectRoot)) {
        return sendJson(res, { error: 'Folder not found' }, 404);
      }
      const tree = scanDir(projectRoot, projectRoot);
      sendJson(res, {
        name: path.basename(projectRoot),
        rootPath: path.relative(REPO_ROOT, projectRoot).replace(/\\/g, '/'),
        tree
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
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
      if (!safePath.startsWith(REPO_ROOT)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }
      if (!fs.existsSync(safePath)) {
        return sendJson(res, { error: 'File not found' }, 404);
      }
      const snapshot = readFileSnapshot(safePath);
      sendJson(res, { path: relPath, ...snapshot });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
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
      if (!safePath.startsWith(REPO_ROOT)) {
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
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/file' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const relPath = body.path || 'examples/file-organizer/main.ot';
      const safePath = path.resolve(REPO_ROOT, relPath);
      if (!safePath.startsWith(REPO_ROOT)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }
      if (body.expectedRevision && fs.existsSync(safePath)) {
        const current = readFileSnapshot(safePath);
        if (current.revision !== body.expectedRevision && body.force !== true) {
          return sendJson(res, {
            error: 'The file changed on disk after it was opened.',
            conflict: true,
            path: relPath,
            ...current
          }, 409);
        }
      }
      fs.writeFileSync(safePath, body.content || '', 'utf8');
      const saved = readFileSnapshot(safePath);
      sendJson(res, { ok: true, path: relPath, ...saved });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/create-file' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const fileName = body.name || 'untitled.ot';
      const targetDir = path.resolve(REPO_ROOT, body.folder || 'examples/file-organizer');
      const safePath = path.join(targetDir, fileName);
      if (!safePath.startsWith(REPO_ROOT)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }
      if (fs.existsSync(safePath)) {
        return sendJson(res, { error: 'File already exists' }, 400);
      }
      fs.writeFileSync(safePath, body.content || '', 'utf8');
      const relPath = path.relative(REPO_ROOT, safePath).replace(/\\/g, '/');
      sendJson(res, { ok: true, path: relPath, name: fileName });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/create-project' && req.method === 'POST') {
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
      if (!projectDir.startsWith(REPO_ROOT)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }
      if (!fs.existsSync(projectDir)) {
        fs.mkdirSync(projectDir, { recursive: true });
      }

      // 1. Write main Otter code file
      const fileName = body.fileName || 'main.ot';
      const mainPath = path.join(projectDir, fileName);
      fs.writeFileSync(mainPath, body.code || `# ${projName}\n\nsay "Hello from ${projName}!"\n`, 'utf8');

      // 2. Write styles.css if present or if desktop/web/game
      if (body.css || body.archetype === 'desktop' || body.archetype === 'web') {
        fs.writeFileSync(path.join(projectDir, 'styles.css'), body.css || '/* Otter Stylesheet */\n', 'utf8');
      }

      // 3. Write rich project.json metadata
      const manifest = createDefaultManifest(projName, body.archetype || 'desktop', fileName, {
        description: body.description,
        author: body.author,
        version: body.version || '1.0.0'
      });
      manifest.main = fileName;
      fs.writeFileSync(path.join(projectDir, 'project.json'), serializeManifest(manifest), 'utf8');

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
      sendJson(res, { error: err.message }, 500);
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

      if (!targetFile.startsWith(REPO_ROOT) || !fs.existsSync(targetFile)) {
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
      sendJson(res, { error: err.message }, 500);
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

      if (!targetFile.startsWith(REPO_ROOT)) {
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
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/workspace' && req.method === 'GET') {
    try {
      const solutionPath = urlObj.searchParams.get('path') || 'solution.json';
      const targetFile = path.resolve(REPO_ROOT, solutionPath);
      if (!targetFile.startsWith(REPO_ROOT) || !fs.existsSync(targetFile)) {
        return sendJson(res, { error: 'Solution file not found' }, 404);
      }

      const raw = fs.readFileSync(targetFile, 'utf8');
      const parsed = JSON.parse(raw);
      const normalized = normalizeSolution(parsed);
      const validation = validateSolution(normalized);

      const roots = [];
      for (const folder of normalized.folders) {
        const rootPath = path.resolve(REPO_ROOT, folder.path);
        if (rootPath.startsWith(REPO_ROOT) && fs.existsSync(rootPath)) {
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
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/workspace' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const solutionPath = body.path || 'solution.json';
      const targetFile = path.resolve(REPO_ROOT, solutionPath);
      if (!targetFile.startsWith(REPO_ROOT)) {
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
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/create-solution' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const solName = (body.name || 'my-solution').trim();
      const solPath = body.path || `${solName}.solution.json`;
      const targetFile = path.resolve(REPO_ROOT, solPath);
      if (!targetFile.startsWith(REPO_ROOT)) {
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
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/render' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const result = await renderOtterSource(String(body.code || ''), String(body.css || ''));
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
      if (!workspaceRoot.startsWith(REPO_ROOT) || !fs.existsSync(workspaceRoot)) {
        return sendJson(res, { error: 'Workspace folder not found' }, 404);
      }
      const otterFiles = collectOtterFiles(workspaceRoot).slice(0, 500);
      const analyses = await mapWithConcurrency(otterFiles, 4, async filePath => ({
        filePath,
        analysis: await analyzeOtterFile(filePath)
      }));
      const symbols = [];
      const diagnostics = [];
      for (const { filePath, analysis } of analyses) {
        const relativePath = path.relative(REPO_ROOT, filePath).replace(/\\/g, '/');
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
        diagnostics
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
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
      if (!workspaceRoot.startsWith(REPO_ROOT) || !fs.existsSync(workspaceRoot)) {
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
      sendJson(res, { error: err.message }, 500);
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
      if (!workspaceRoot.startsWith(REPO_ROOT) || !fs.existsSync(workspaceRoot)) {
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
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Execution & Otter Runner API (with launch profiles, args & env) ---
  if (pathname === '/api/run' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const relPath = body.path || 'examples/file-organizer/main.ot';
      const safePath = path.resolve(REPO_ROOT, relPath);
      if (!safePath.startsWith(REPO_ROOT)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }

      // Save content first if provided
      if (typeof body.content === 'string') {
        fs.writeFileSync(safePath, body.content, 'utf8');
      }

      const runDir = body.cwd ? path.resolve(REPO_ROOT, body.cwd) : path.dirname(safePath);
      const scriptName = path.basename(safePath);
      const otterCmd = path.join(REPO_ROOT, 'otter.cmd');
      const customArgs = Array.isArray(body.args) ? body.args.map(a => `"${String(a).replace(/"/g, '\\"')}"`).join(' ') : (body.args ? ` ${body.args}` : '');
      const mode = body.mode || 'run'; // 'run' | 'check' | 'test'
      const cmd = `"${otterCmd}" ${mode} "${scriptName}"${customArgs ? ' ' + customArgs : ''}`;
      const startTime = Date.now();

      if (activeRunProcess) {
        try {
          if (process.platform === 'win32') exec(`taskkill /pid ${activeRunProcess.pid} /f /t`, () => {});
          else activeRunProcess.kill('SIGTERM');
        } catch {}
        activeRunProcess = null;
      }

      const child = exec(cmd, { cwd: runDir, env: { ...process.env, ...(body.env || {}) }, timeout: 30000 }, (error, stdout, stderr) => {
        activeRunProcess = null;
        const durationMs = Date.now() - startTime;
        sendJson(res, {
          ok: !error,
          exitCode: error ? (error.code || 1) : 0,
          stdout: stdout ? stdout.toString() : '',
          stderr: stderr ? stderr.toString() : '',
          durationMs,
          error: error ? error.message : null
        });
      });
      activeRunProcess = child;
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Stop Running Process API ---
  if (pathname === '/api/stop' && req.method === 'POST') {
    if (activeRunProcess) {
      try {
        if (process.platform === 'win32') exec(`taskkill /pid ${activeRunProcess.pid} /f /t`, () => {});
        else activeRunProcess.kill('SIGTERM');
      } catch {}
      activeRunProcess = null;
      return sendJson(res, { stopped: true });
    }
    return sendJson(res, { stopped: false, message: 'No process currently running' });
  }

  // --- Build & Clean API ---
  if (pathname === '/api/build' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const folderParam = body.folder || body.path || '.';
      const projectDir = path.resolve(REPO_ROOT, folderParam);
      if (!projectDir.startsWith(REPO_ROOT) || !fs.existsSync(projectDir)) {
        return sendJson(res, { error: 'Project folder not found' }, 404);
      }

      const otterCmd = path.join(REPO_ROOT, 'otter.cmd');
      const targetArg = body.target ? ` "${body.target}"` : '';
      const cmd = `"${otterCmd}" build${targetArg}`;
      const startTime = Date.now();

      exec(cmd, { cwd: projectDir, timeout: 60000 }, (error, stdout, stderr) => {
        const durationMs = Date.now() - startTime;
        const exitCode = error ? (error.code || 1) : 0;
        const ok = exitCode === 0;

        let buildMeta = null;
        const metaPath = path.join(projectDir, 'dist', 'otter.build.json');
        if (fs.existsSync(metaPath)) {
          try {
            buildMeta = JSON.parse(fs.readFileSync(metaPath, 'utf8').replace(/^\uFEFF/, ''));
          } catch {}
        }

        sendJson(res, {
          ok,
          exitCode,
          stdout: stdout ? stdout.toString() : '',
          stderr: stderr ? stderr.toString() : '',
          durationMs,
          outputDir: 'dist',
          buildMeta,
          error: error ? error.message : null
        }, ok ? 200 : 422);
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/clean' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const folderParam = body.folder || body.path || '.';
      const projectDir = path.resolve(REPO_ROOT, folderParam);
      if (!projectDir.startsWith(REPO_ROOT) || !fs.existsSync(projectDir)) {
        return sendJson(res, { error: 'Project folder not found' }, 404);
      }

      let outDirName = 'dist';
      const otterJson = path.join(projectDir, 'otter.json');
      const projJson = path.join(projectDir, 'project.json');
      const manifestFile = fs.existsSync(otterJson) ? otterJson : (fs.existsSync(projJson) ? projJson : null);
      if (manifestFile) {
        try {
          const parsed = JSON.parse(fs.readFileSync(manifestFile, 'utf8').replace(/^\uFEFF/, ''));
          if (parsed.build && parsed.build.outputDir) {
            outDirName = parsed.build.outputDir;
          }
        } catch {}
      }

      const outDir = path.resolve(projectDir, outDirName);
      if (!outDir.startsWith(projectDir) || outDir === projectDir) {
        return sendJson(res, { error: 'Output directory must stay inside project' }, 400);
      }

      let cleaned = false;
      if (fs.existsSync(outDir)) {
        const marker = path.join(outDir, 'otter.build.json');
        if (fs.existsSync(marker) || fs.readdirSync(outDir).length === 0) {
          fs.rmSync(outDir, { recursive: true, force: true });
          cleaned = true;
        } else {
          return sendJson(res, { error: 'Directory does not contain otter.build.json; refusal to delete' }, 400);
        }
      }

      sendJson(res, { ok: true, cleaned, outputDir: outDirName });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/publish' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const folderParam = body.folder || body.path || '.';
      const projectDir = path.resolve(REPO_ROOT, folderParam);
      if (!projectDir.startsWith(REPO_ROOT) || !fs.existsSync(projectDir)) {
        return sendJson(res, { error: 'Project folder not found' }, 404);
      }

      const otterCmd = path.join(REPO_ROOT, 'otter.cmd');
      const targetArg = body.target ? ` "${body.target}"` : '';
      const outputArg = body.outputDir ? ` -Output "${body.outputDir}"` : '';
      const cmd = `"${otterCmd}" publish${targetArg}${outputArg}`;
      const startTime = Date.now();

      exec(cmd, { cwd: projectDir, timeout: 60000 }, (error, stdout, stderr) => {
        const durationMs = Date.now() - startTime;
        const exitCode = error ? (error.code || 1) : 0;
        const ok = exitCode === 0;

        let publishMeta = null;
        let archiveName = null;
        let archivePath = null;
        let checksum = null;
        let checksumPath = null;

        const effectivePubDir = body.outputDir
          ? path.resolve(projectDir, body.outputDir)
          : path.join(projectDir, 'publish');

        const metaPath = path.join(effectivePubDir, 'otter.publish.json');
        if (fs.existsSync(metaPath)) {
          try {
            publishMeta = JSON.parse(fs.readFileSync(metaPath, 'utf8').replace(/^\uFEFF/, ''));
          } catch {}
        }

        if (fs.existsSync(effectivePubDir)) {
          try {
            const files = fs.readdirSync(effectivePubDir);
            archiveName = files.find(f => f.endsWith('.zip')) || null;
            if (archiveName) {
              archivePath = path.relative(REPO_ROOT, path.join(effectivePubDir, archiveName)).replace(/\\/g, '/');
              const shaFile = path.join(effectivePubDir, `${archiveName}.sha256`);
              if (fs.existsSync(shaFile)) {
                checksumPath = path.relative(REPO_ROOT, shaFile).replace(/\\/g, '/');
                checksum = fs.readFileSync(shaFile, 'utf8').replace(/^\uFEFF/, '').trim();
              }
            }
          } catch {}
        }

        sendJson(res, {
          ok,
          exitCode,
          stdout: stdout ? stdout.toString() : '',
          stderr: stderr ? stderr.toString() : '',
          durationMs,
          publishMeta,
          archiveName,
          archivePath,
          checksum,
          checksumPath,
          error: error ? error.message : null
        }, ok ? 200 : 422);
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Test Explorer API ---
  if (pathname === '/api/tests/discover' && req.method === 'GET') {
    try {
      const folderParam = urlObj.searchParams.get('folder') || '.';
      const projectDir = path.resolve(REPO_ROOT, folderParam);
      if (!projectDir.startsWith(REPO_ROOT) || !fs.existsSync(projectDir)) {
        return sendJson(res, { error: 'Project folder not found' }, 404);
      }

      const testFiles = [];
      function findTests(dir) {
        if (!fs.existsSync(dir)) return;
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
          if (entry.name === 'node_modules' || entry.name === '.git' || entry.name === 'dist') continue;
          const fullPath = path.join(dir, entry.name);
          if (entry.isDirectory()) {
            findTests(fullPath);
          } else if (entry.isFile()) {
            const lower = entry.name.toLowerCase();
            if (lower.endsWith('_test.ot') || lower.endsWith('.test.ot') || lower.endsWith('.tests.ot') || (lower.startsWith('test_') && lower.endsWith('.ot'))) {
              const rel = path.relative(projectDir, fullPath).replace(/\\/g, '/');
              const content = fs.readFileSync(fullPath, 'utf8');
              const lines = content.split(/\r?\n/);
              const testSuites = [];
              for (let i = 0; i < lines.length; i++) {
                const line = lines[i].trim();
                if (line.startsWith('#') && line.length > 2) {
                  testSuites.push({ line: i + 1, title: line.replace(/^#+\s*/, '') });
                }
              }
              testFiles.push({
                file: rel,
                name: entry.name,
                fullPath: path.relative(REPO_ROOT, fullPath).replace(/\\/g, '/'),
                suites: testSuites
              });
            }
          }
        }
      }
      findTests(projectDir);

      sendJson(res, {
        ok: true,
        project: path.basename(projectDir),
        count: testFiles.length,
        tests: testFiles
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/tests/run' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const folderParam = body.folder || body.path || '.';
      const projectDir = path.resolve(REPO_ROOT, folderParam);
      if (!projectDir.startsWith(REPO_ROOT) || !fs.existsSync(projectDir)) {
        return sendJson(res, { error: 'Project folder not found' }, 404);
      }

      const otterCmd = path.join(REPO_ROOT, 'otter.cmd');
      const targetArg = body.file ? ` "${body.file}"` : '';
      const cmd = `"${otterCmd}" test${targetArg}`;
      const startTime = Date.now();

      exec(cmd, { cwd: projectDir, timeout: 60000 }, (error, stdout, stderr) => {
        const durationMs = Date.now() - startTime;
        const outStr = stdout ? stdout.toString() : '';
        const errStr = stderr ? stderr.toString() : '';
        const lines = outStr.split(/\r?\n/);

        const results = [];
        const seenFiles = new Set();
        let passed = 0;
        let failed = 0;

        for (const rawLine of lines) {
          const line = rawLine.trim();
          if (line.startsWith('PASS ')) {
            const file = line.slice(5).trim();
            if (!seenFiles.has(file)) {
              seenFiles.add(file);
              passed++;
              results.push({ file, status: 'pass' });
            }
          } else if (line.startsWith('FAIL ')) {
            const parts = line.slice(5).trim().split(/\s+/);
            const file = parts[0];
            if (!seenFiles.has(file)) {
              seenFiles.add(file);
              failed++;
              results.push({ file, status: 'fail' });
            }
          }
        }

        const ok = (failed === 0) && (error ? error.code === 0 : true);

        sendJson(res, {
          ok,
          exitCode: error ? (error.code || 1) : 0,
          total: passed + failed,
          passed,
          failed,
          results,
          durationMs,
          stdout: outStr,
          stderr: errStr,
          error: error ? error.message : null
        });
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Git & Source Control API ---
  if (pathname === '/api/git/status' && req.method === 'GET') {
    try {
      const folderParam = urlObj.searchParams.get('folder') || '.';
      const targetDir = path.resolve(REPO_ROOT, folderParam);
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);

      execFile('git', ['rev-parse', '--is-inside-work-tree'], { cwd: targetDir }, (err, isInside) => {
        if (err || isInside.trim() !== 'true') {
          return sendJson(res, { isRepo: false });
        }

        execFile('git', ['status', '--porcelain=v1', '-uall'], { cwd: targetDir }, (err, statusOut) => {
          if (err) return sendJson(res, { error: err.message }, 500);

          execFile('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { cwd: targetDir }, (err, branchOut) => {
            const branch = (branchOut || 'HEAD').trim();
            const lines = (statusOut || '').split(/\r?\n/).filter(Boolean);
            const staged = [];
            const unstaged = [];
            const untracked = [];

            for (const line of lines) {
              const x = line[0];
              const y = line[1];
              const file = line.slice(3).trim();

              if (x === '?' && y === '?') {
                untracked.push(file);
              } else {
                if (x !== ' ' && x !== '?') {
                  staged.push({ file, status: x });
                }
                if (y !== ' ' && y !== '?') {
                  unstaged.push({ file, status: y });
                }
              }
            }

            sendJson(res, {
              isRepo: true,
              branch,
              clean: lines.length === 0,
              staged,
              unstaged,
              untracked
            });
          });
        });
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/diff' && req.method === 'GET') {
    try {
      const folderParam = urlObj.searchParams.get('folder') || '.';
      const targetDir = path.resolve(REPO_ROOT, folderParam);
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);

      const filePath = urlObj.searchParams.get('path');
      const staged = urlObj.searchParams.get('staged') === 'true';
      const args = ['diff'];
      if (staged) args.push('--cached');
      if (filePath) args.push('--', filePath);

      execFile('git', args, { cwd: targetDir }, (err, diffOut) => {
        if (err) return sendJson(res, { error: err.message }, 500);
        sendJson(res, { ok: true, diff: diffOut || '' });
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/stage' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const folderParam = body.folder || '.';
      const targetDir = path.resolve(REPO_ROOT, folderParam);
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);

      const files = Array.isArray(body.files) ? body.files : (body.path ? [body.path] : ['.']);
      execFile('git', ['add', ...files], { cwd: targetDir }, (err, stdout, stderr) => {
        if (err) return sendJson(res, { ok: false, error: stderr || err.message }, 500);
        sendJson(res, { ok: true });
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/unstage' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const folderParam = body.folder || '.';
      const targetDir = path.resolve(REPO_ROOT, folderParam);
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);

      const files = Array.isArray(body.files) ? body.files : (body.path ? [body.path] : ['.']);
      execFile('git', ['reset', 'HEAD', '--', ...files], { cwd: targetDir }, (err, stdout, stderr) => {
        if (err) return sendJson(res, { ok: false, error: stderr || err.message }, 500);
        sendJson(res, { ok: true });
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/commit' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const folderParam = body.folder || '.';
      const targetDir = path.resolve(REPO_ROOT, folderParam);
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);

      const message = String(body.message || '').trim();
      if (!message) return sendJson(res, { error: 'Commit message is required' }, 400);

      execFile('git', ['commit', '-m', message], { cwd: targetDir }, (err, stdout, stderr) => {
        if (err) return sendJson(res, { ok: false, error: stderr || stdout || err.message }, 422);
        execFile('git', ['rev-parse', 'HEAD'], { cwd: targetDir }, (err, hashOut) => {
          sendJson(res, { ok: true, commitHash: (hashOut || '').trim(), stdout: (stdout || '').trim() });
        });
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/log' && req.method === 'GET') {
    try {
      const folderParam = urlObj.searchParams.get('folder') || '.';
      const targetDir = path.resolve(REPO_ROOT, folderParam);
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);

      const limit = Math.min(Number(urlObj.searchParams.get('limit') || 20), 100);
      execFile('git', ['log', `-n${limit}`, '--pretty=format:%H|%an|%ae|%ad|%s'], { cwd: targetDir }, (err, logOut) => {
        if (err) return sendJson(res, { ok: false, commits: [] });
        const commits = (logOut || '').split(/\r?\n/).filter(Boolean).map(line => {
          const [hash, author, email, date, ...rest] = line.split('|');
          return { hash, author, email, date, message: rest.join('|') };
        });
        sendJson(res, { ok: true, count: commits.length, commits });
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/branches' && req.method === 'GET') {
    try {
      const folderParam = urlObj.searchParams.get('folder') || '.';
      const targetDir = path.resolve(REPO_ROOT, folderParam);
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);

      execFile('git', ['branch', '--list'], { cwd: targetDir }, (err, branchOut) => {
        if (err) return sendJson(res, { ok: false, branches: [] });
        const branches = [];
        let current = null;
        for (const rawLine of (branchOut || '').split(/\r?\n/).filter(Boolean)) {
          const isCurrent = rawLine.startsWith('*');
          const name = rawLine.replace(/^\*?\s*/, '').trim();
          if (isCurrent) current = name;
          branches.push({ name, isCurrent });
        }
        sendJson(res, { ok: true, current, branches });
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
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
      if (!safePath.startsWith(REPO_ROOT)) {
        return sendJson(res, { error: 'Forbidden' }, 403);
      }

      if (typeof body.content === 'string') {
        fs.writeFileSync(safePath, body.content, 'utf8');
      }

      const runDir = path.dirname(safePath);
      const scriptName = path.basename(safePath);
      const breakpoints = Array.isArray(body.breakpoints)
        ? body.breakpoints.filter(n => Number.isInteger(n)).join(',')
        : '';
      const otterPs1 = path.join(REPO_ROOT, 'otter.ps1');

      const child = spawn('powershell.exe', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', otterPs1, 'debug', scriptName, '-Breakpoints', breakpoints
      ], { cwd: runDir, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });

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
      sendJson(res, { error: err.message }, 500);
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
      sendJson(res, { error: err.message }, 500);
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
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Interactive Terminal API ---
  if (pathname === '/api/terminal' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const command = body.command || 'otter --version';

      const cmd = `powershell -ExecutionPolicy Bypass -Command "${command.replace(/"/g, '`"')}"`;
      const startTime = Date.now();

      exec(cmd, { cwd: REPO_ROOT, timeout: 15000 }, (error, stdout, stderr) => {
        const durationMs = Date.now() - startTime;
        sendJson(res, {
          exitCode: error ? (error.code || 1) : 0,
          stdout: stdout ? stdout.toString() : '',
          stderr: stderr ? stderr.toString() : '',
          durationMs
        });
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Otter Profiler API ---
  if (pathname === '/api/profile' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const top = Number(body.top || 25);
      let targetPath = null;
      let tempFilePath = null;

      if (body.path) {
        targetPath = path.resolve(REPO_ROOT, body.path);
        if (!targetPath.startsWith(REPO_ROOT) || !fs.existsSync(targetPath)) {
          return sendJson(res, { ok: false, error: { message: `File not found: ${body.path}` } }, 404);
        }
      } else if (typeof body.code === 'string') {
        const scratchDir = path.join(REPO_ROOT, 'scratch');
        if (!fs.existsSync(scratchDir)) fs.mkdirSync(scratchDir, { recursive: true });
        tempFilePath = path.join(scratchDir, `_profile_${Date.now()}_${Math.random().toString(36).slice(2, 8)}.ot`);
        fs.writeFileSync(tempFilePath, body.code, 'utf8');
        targetPath = tempFilePath;
      } else {
        return sendJson(res, { ok: false, error: { message: 'Either path or code must be provided' } }, 400);
      }

      const scriptPath = path.join(__dirname, 'scripts', 'run-profile.ps1');
      const args = [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', scriptPath,
        '-FilePath', targetPath,
        '-Top', String(top)
      ];

      execFile('powershell.exe', args, { cwd: REPO_ROOT, timeout: 30000 }, (error, stdout, stderr) => {
        if (tempFilePath && fs.existsSync(tempFilePath)) {
          try { fs.rmSync(tempFilePath, { force: true }); } catch {}
        }

        if (error && !stdout) {
          return sendJson(res, {
            ok: false,
            error: { message: stderr || error.message }
          }, 500);
        }

        try {
          const parsed = JSON.parse(stdout.trim());
          sendJson(res, parsed);
        } catch (err) {
          sendJson(res, {
            ok: false,
            error: {
              message: 'Failed to parse profiler output JSON',
              raw: stdout || stderr
            }
          }, 500);
        }
      });
    } catch (err) {
      sendJson(res, { ok: false, error: { message: err.message } }, 500);
    }
    return;
  }

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

  const filePath = path.join(__dirname, reqPath);

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('404 Not Found');
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    res.writeHead(200, { 'Content-Type': contentType });
    fs.createReadStream(filePath).pipe(res);
  });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Otter Studio running with Full Interaction Engine at: http://127.0.0.1:${PORT}`);
});
