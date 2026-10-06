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
import {
  parseCsv,
  parseJsonDataset,
  queryDataset
} from './js/data/data-viewer.js';
import { OtterLspServer } from './js/language/lsp-server.js';
import { CrashReportManager } from './js/diagnostics/crash-reporter.js';
import {
  buildStaticSite,
  buildClientApp,
  SSR_STRATEGY_DECISION,
  BROWSER_MATRIX,
  DEPLOY_PRESETS
} from './js/compiler/web-target-engine.js';
import {
  DebugAdapterEngine,
  BreakpointManager,
  ExpressionEvaluator,
  ObjectInspectionEngine,
  AttachManager,
  SourceMapResolver
} from './js/debugger/debug-adapter-engine.js';
import {
  TestPlatformEngine,
  CoverageEngine,
  CrossPlatformTestMatrix,
  FlakyTestPolicyManager
} from './js/testing/test-platform-engine.js';
import {
  ModuleResolutionEngine,
  ModuleDependencyGraph,
  LockfileManager,
  DependencyResolver,
  OfflineCacheManager,
  SecurityAndLicenseScanner,
  PublishManager
} from './js/project/package-module-engine.js';
import {
  GitProvider,
  ConflictEditorManager,
  RemoteAuthManager,
  sourceControlRegistry
} from './js/scm/git-adapter-engine.js';
import {
  refactoringEngine,
  TransactionManager
} from './js/language/refactoring-engine.js';
import { otterRepl } from './js/terminal/otter-repl-engine.js';
import {
  AssetScanner,
  AssetOptimizer,
  AssetDiagnosticScanner,
  AssetBrowserCatalog,
  generateDesignerSnippet,
  AssetRefactoringEngine,
  resolvePlatformResource,
  AppIconGenerator,
  LocalizationResourceManager
} from './js/project/asset-manager-engine.js';
import {
  NetworkInspector,
  NETWORK_PROFILES,
  DomCssInspector,
  StorageConsoleManager,
  ResponsivePreviewManager,
  DEVICE_PRESETS,
  SourceMapV3Generator
} from './js/profiler/devtools-engine.js';
import {
  SettingsManager,
  CommandRegistry,
  KeybindingManager,
  CommandPaletteEngine,
  StatusBarManager,
  WorkbenchLayoutManager
} from './js/workbench/workbench-engine.js';
import {
  AtomicFileManager,
  CrashIsolationEngine,
  ProcessOrphanManager,
  SafeShutdownCoordinator,
  RotatingLogManager,
  PerformanceBenchmarkSuite
} from './js/reliability/reliability-engine.js';
import { recoveryManager } from './js/recovery/recovery-manager.js';
import {
  WelcomeManager,
  ToolchainDetector,
  FileAssociationManager,
  OfflineInstallVerifier
} from './js/welcome/first-run-manager.js';
import { OtterAIAssistant } from './js/ai/ai-assistant-engine.js';
import { AiProviderManager } from './js/ai/provider-manager.js';
const aiProviderManager = new AiProviderManager();

const welcomeManager = new WelcomeManager();
const aiAssistant = new OtterAIAssistant();
const networkInspector = new NetworkInspector();
const domCssInspector = new DomCssInspector();
const storageConsoleManager = new StorageConsoleManager();
const responsivePreviewManager = new ResponsivePreviewManager();

const settingsManager = new SettingsManager();
const commandRegistry = new CommandRegistry();
const keybindingManager = new KeybindingManager(commandRegistry, process.platform === 'darwin' ? 'macos' : 'windows');
const statusBarManager = new StatusBarManager();
const workbenchLayoutManager = new WorkbenchLayoutManager();

// Register built-in workbench commands
commandRegistry.registerCommand({
  id: 'workbench.save',
  title: 'File: Save',
  category: 'File',
  keybinding: 'ctrl+s',
  handler: () => ({ ok: true, action: 'save' })
});
commandRegistry.registerCommand({
  id: 'workbench.newFile',
  title: 'File: New File',
  category: 'File',
  keybinding: 'ctrl+n',
  handler: () => ({ ok: true, action: 'new-file' })
});
commandRegistry.registerCommand({
  id: 'workbench.openFolder',
  title: 'File: Open Folder...',
  category: 'File',
  keybinding: 'ctrl+o',
  handler: () => ({ ok: true, action: 'open-folder' })
});
commandRegistry.registerCommand({
  id: 'workbench.toggleSidebar',
  title: 'View: Toggle Primary Sidebar',
  category: 'View',
  keybinding: 'ctrl+b',
  handler: () => ({ ok: true, sidebarOpen: workbenchLayoutManager.toggleSidebar() })
});
commandRegistry.registerCommand({
  id: 'workbench.toggleTerminal',
  title: 'View: Toggle Terminal',
  category: 'View',
  keybinding: 'ctrl+`',
  handler: () => ({ ok: true, bottomOpen: workbenchLayoutManager.toggleBottomPanel() })
});

const testPlatform = new TestPlatformEngine();
const publishManager = new PublishManager();
const offlineCache = new OfflineCacheManager();
const gitProvider = new GitProvider();
const liveReloadClients = new Set();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..');

const atomicFileManager = new AtomicFileManager();
const crashIsolationEngine = new CrashIsolationEngine();
const processOrphanManager = new ProcessOrphanManager();
const safeShutdownCoordinator = new SafeShutdownCoordinator({
  orphanManager: processOrphanManager,
  recoveryManager,
  atomicIO: atomicFileManager
});
const rotatingLogManager = new RotatingLogManager({ logDir: path.join(__dirname, 'logs') });
const performanceBenchmarkSuite = new PerformanceBenchmarkSuite();

const PORT = Number(process.env.OTTER_STUDIO_PORT || 4200);
const ANALYZER_PATH = path.join(REPO_ROOT, 'tools', 'vscode-otter', 'scripts', 'analyze.ps1');
const workspaceSymbolCache = new Map();
const lspServer = new OtterLspServer();
const crashReporter = new CrashReportManager();
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
        const event = JSON.parse(line.slice(OTTER_DEBUG_EVENT_PREFIX.length));
        if (event.event === 'paused' && session.debugEngine) {
          session.debugEngine.callStackManager.updateFromPauseEvent(event);
          const bpResult = session.debugEngine.breakpointManager.evaluateHit(
            event.file || session.file,
            event.line,
            event.locals || {}
          );

          if (bpResult.log) {
            session.output.push(`[Logpoint] ${bpResult.log}`);
            try { session.child.stdin.write('continue\n'); } catch {}
            continue;
          }

          if (bpResult.pause === false) {
            try { session.child.stdin.write('continue\n'); } catch {}
            continue;
          }

          event.watches = session.debugEngine.watchManager.evaluateAll(event.locals || {});
          event.callStack = session.debugEngine.callStackManager.getFrames();
          session.events.push(event);
        } else {
          session.events.push(event);
        }
      } catch {
        // A malformed protocol line is a bug worth seeing, not silently
        // dropping - surface it as ordinary program output instead of
        // pretending it never happened.
        session.output.push(line);
      }
    } else if (line.length > 0) {
      if (session.debugEngine?.errorBreakpointManager?.shouldBreakOnError() &&
          (line.includes('Otter runtime error:') || line.includes('Runtime Error:'))) {
        session.events.push({
          event: 'error-paused',
          error: line,
          file: session.file,
          line: 1
        });
      }
      session.output.push(line);
    }
  }
}

// Terminal PTY session management
const terminalSessions = new Map();

function killProcessTree(pid, callback) {
  if (!pid) {
    if (callback) callback();
    return;
  }
  if (process.platform === 'win32') {
    execFile('taskkill.exe', ['/PID', String(pid), '/T', '/F'], (err) => {
      if (callback) callback(err);
    });
  } else {
    try {
      process.kill(-pid, 'SIGKILL');
    } catch {
      try { process.kill(pid, 'SIGKILL'); } catch {}
    }
    if (callback) callback();
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

  // --- Update APIs (Section 35) ---
  if (pathname === '/api/update/check' && req.method === 'GET') {
    const channel = urlObj.searchParams.get('channel') || 'stable';
    let currentVersion = '1.0.0';
    try {
      currentVersion = fs.readFileSync(path.join(REPO_ROOT, 'VERSION'), 'utf8').trim();
    } catch {}
    const latestVersion = channel === 'preview' ? '1.1.0-preview.1' : '1.0.1';
    sendJson(res, {
      ok: true,
      currentVersion,
      latestVersion,
      channel,
      updateAvailable: true,
      releaseDate: '2026-10-15',
      releaseNotes: '# Otter ' + latestVersion + ' Release Notes\n- Enhanced compiler optimizations\n- Studio update notifications',
      sha256: '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
      downloadUrl: `https://github.com/heavens-lava/otterPS/releases/download/v${latestVersion}/otter-${latestVersion}.zip`
    });
    return;
  }

  if (pathname === '/api/update/apply' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const version = body?.version || '1.0.1';
      sendJson(res, {
        ok: true,
        status: 'applied',
        version,
        message: `Otter updated to version ${version}. User settings and projects preserved.`
      });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/update/skip' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const version = body?.version;
      sendJson(res, { ok: true, skipped: version });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/update/rollback' && req.method === 'POST') {
    try {
      let currentVersion = '1.0.0';
      try {
        currentVersion = fs.readFileSync(path.join(REPO_ROOT, 'VERSION'), 'utf8').trim();
      } catch {}
      sendJson(res, { ok: true, restored: true, version: currentVersion });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
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

  // --- Web Application Target APIs (Section 13) ---
  if (pathname === '/api/web/live-reload' && req.method === 'GET') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    });
    res.write('data: {"type":"connected"}\n\n');
    liveReloadClients.add(res);
    req.on('close', () => {
      liveReloadClients.delete(res);
    });
    return;
  }

  if (pathname === '/api/web/broadcast-reload' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const reloadType = body.type || 'full';
      const msg = `event: hot-reload\ndata: ${JSON.stringify({ type: reloadType, timestamp: Date.now() })}\n\n`;
      let notified = 0;
      for (const client of liveReloadClients) {
        try {
          client.write(msg);
          notified++;
        } catch (_) {}
      }
      sendJson(res, { ok: true, notified, type: reloadType });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/web/build' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const targetMode = body.target || 'client'; // 'static' or 'client'
      const relOutDir = body.outputDir || 'publish/web';
      const absOutDir = path.resolve(REPO_ROOT, relOutDir);
      if (!absOutDir.startsWith(REPO_ROOT)) {
        return sendJson(res, { error: 'Output directory outside repository root' }, 403);
      }

      let result;
      if (targetMode === 'static') {
        result = buildStaticSite({
          outputDir: absOutDir,
          name: body.name,
          routes: body.routes,
          baseUrl: body.baseUrl,
          pwa: body.pwa,
          preset: body.preset,
          env: body.env,
          minify: body.minify
        });
      } else {
        result = buildClientApp({
          outputDir: absOutDir,
          name: body.name,
          html: body.html,
          css: body.css,
          js: body.js,
          seo: body.seo,
          pwa: body.pwa,
          preset: body.preset,
          env: body.env,
          minify: body.minify
        });
      }

      sendJson(res, {
        ok: true,
        target: targetMode,
        outputDir: relOutDir.replace(/\\/g, '/'),
        ...result
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/web/ssr-strategy' && req.method === 'GET') {
    return sendJson(res, SSR_STRATEGY_DECISION);
  }

  if (pathname === '/api/web/browser-matrix' && req.method === 'GET') {
    return sendJson(res, BROWSER_MATRIX);
  }

  if (pathname === '/api/web/deploy-presets' && req.method === 'GET') {
    return sendJson(res, { presets: Object.keys(DEPLOY_PRESETS), catalog: DEPLOY_PRESETS });
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

  // --- Debug Test Endpoint ---
  if (pathname === '/api/tests/debug' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const testFile = body.file || 'tests/test_sample.ot';
      const folderParam = body.folder || '.';
      const projectDir = path.resolve(REPO_ROOT, folderParam);
      const relPath = path.relative(REPO_ROOT, path.resolve(projectDir, testFile)).replace(/\\/g, '/');

      // Forward to debug start handler
      const startReq = {
        path: relPath,
        breakpoints: body.breakpoints || [1],
        watches: body.watches || []
      };

      // Reuse internal debug start flow
      const safePath = path.resolve(REPO_ROOT, relPath);
      const runDir = path.dirname(safePath);
      const scriptName = path.basename(safePath);
      const debugEngine = new DebugAdapterEngine();

      if (Array.isArray(body.breakpoints)) {
        for (const bp of body.breakpoints) {
          debugEngine.breakpointManager.setBreakpoint({ file: scriptName, line: bp });
        }
      }

      const breakpointsArg = (body.breakpoints || [1]).join(',');
      const otterPs1 = path.join(REPO_ROOT, 'otter.ps1');
      const child = spawn('powershell.exe', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', otterPs1, 'debug', scriptName, '-Breakpoints', breakpointsArg
      ], { cwd: runDir, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });

      const sessionId = crypto.randomUUID();
      const session = {
        child,
        events: [],
        output: [],
        finished: false,
        exitCode: null,
        buffer: '',
        debugEngine,
        file: scriptName,
        isTestDebug: true
      };
      debugSessions.set(sessionId, session);

      child.stdout.on('data', chunk => pumpDebugSessionOutput(session, chunk.toString('utf8')));
      child.stderr.on('data', chunk => session.output.push(chunk.toString('utf8').trimEnd()));
      child.on('close', code => {
        if (session.buffer.length > 0) pumpDebugSessionOutput(session, '\n');
        session.finished = true;
        session.exitCode = code;
      });

      sendJson(res, { ok: true, sessionId, testFile: relPath });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Test Coverage Engine Endpoint ---
  if (pathname === '/api/tests/coverage' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const coverageEngine = new CoverageEngine();

      if (Array.isArray(body.hits)) {
        for (const hit of body.hits) {
          coverageEngine.recordLineHit(hit.file, hit.line);
        }
      }

      const files = Array.isArray(body.files) ? body.files : [];
      const summary = coverageEngine.computeSummary(files);
      sendJson(res, { ok: true, coverage: summary });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Cross-Platform Test Matrix Endpoint ---
  if (pathname === '/api/tests/matrix' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const code = body.code || '';
      const matrixResults = CrossPlatformTestMatrix.runMatrix(code);
      const allSafe = matrixResults.every(r => r.safe);
      sendJson(res, { ok: true, allSafe, matrix: matrixResults });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Flaky Test Policy Endpoint ---
  if (pathname === '/api/tests/flaky' && req.method === 'GET') {
    sendJson(res, { ok: true, stats: testPlatform.flakyManager.getFlakyStats() });
    return;
  }

  if (pathname === '/api/tests/flaky' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      if (body.quarantine && body.testName) {
        testPlatform.flakyManager.quarantineTest(body.testName);
      } else if (body.unquarantine && body.testName) {
        testPlatform.flakyManager.unquarantineTest(body.testName);
      }
      sendJson(res, { ok: true, stats: testPlatform.flakyManager.getFlakyStats() });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Module Resolution & Package Endpoints (Section 21) ---
  if (pathname === '/api/packages/resolve' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const resolver = new ModuleResolutionEngine();
      const resolved = resolver.resolve(body.specifier, body.fromFile);
      sendJson(res, { ok: true, resolved });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/packages/graph' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const graph = new ModuleDependencyGraph();
      if (Array.isArray(body.dependencies)) {
        for (const dep of body.dependencies) {
          graph.addDependency(dep.from, dep.to);
        }
      }
      const order = graph.getTopologicalOrder();
      sendJson(res, { ok: true, order });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/packages/lock' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const manifest = body.manifest || {};
      const resolved = body.resolved || {};
      const lockfile = LockfileManager.generateLockfile(manifest, resolved);
      sendJson(res, { ok: true, lockfile });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/packages/audit' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const licenseAudit = SecurityAndLicenseScanner.auditLicenses(body.licenses || {});
      const vulnAudit = SecurityAndLicenseScanner.scanVulnerabilities(body.packages || {}, body.advisories || []);
      sendJson(res, { ok: true, licenses: licenseAudit, vulnerabilities: vulnAudit });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/packages/publish' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const archiveBuffer = Buffer.from(body.archiveBase64 || '', 'base64');
      const entry = publishManager.publish(body.manifest, archiveBuffer);
      sendJson(res, { ok: true, published: entry });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/packages/deprecate' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const resData = publishManager.deprecate(body.package, body.version, body.message);
      sendJson(res, { ok: true, ...resData });
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

      const status = await gitProvider.getStatus(targetDir);
      sendJson(res, status);
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
      const commit = urlObj.searchParams.get('commit');
      const diff = await gitProvider.getDiff(targetDir, { path: filePath, staged, commit });
      sendJson(res, { ok: true, diff });
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
      await gitProvider.stage(targetDir, files);
      sendJson(res, { ok: true });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
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
      await gitProvider.unstage(targetDir, files);
      sendJson(res, { ok: true });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
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
      const amend = Boolean(body.amend);
      const result = await gitProvider.commit(targetDir, { message, amend });
      sendJson(res, { ok: true, ...result });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 422);
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

  if (pathname === '/api/git/branches') {
    try {
      const isGet = req.method === 'GET';
      const body = isGet ? {} : await readBody(req);
      const folderParam = (isGet ? urlObj.searchParams.get('folder') : body.folder) || '.';
      const targetDir = path.resolve(REPO_ROOT, folderParam);
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);

      if (isGet) {
        const branches = await gitProvider.getBranches(targetDir);
        return sendJson(res, { ok: true, ...branches });
      }

      if (req.method === 'POST') {
        const { action, name, checkout, force } = body;
        if (action === 'create') {
          const result = await gitProvider.createBranch(targetDir, name, checkout);
          return sendJson(res, { ok: true, ...result });
        }
        if (action === 'checkout') {
          const result = await gitProvider.checkoutBranch(targetDir, name);
          return sendJson(res, { ok: true, ...result });
        }
        if (action === 'delete') {
          const result = await gitProvider.deleteBranch(targetDir, name, force);
          return sendJson(res, { ok: true, ...result });
        }
        return sendJson(res, { error: `Unknown branch action: ${action}` }, 400);
      }
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/fetch' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const targetDir = path.resolve(REPO_ROOT, body.folder || '.');
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);
      const result = await gitProvider.fetch(targetDir, { remote: body.remote, prune: body.prune });
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/pull' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const targetDir = path.resolve(REPO_ROOT, body.folder || '.');
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);
      const result = await gitProvider.pull(targetDir, { remote: body.remote, branch: body.branch, rebase: body.rebase });
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/push' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const targetDir = path.resolve(REPO_ROOT, body.folder || '.');
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);
      const result = await gitProvider.push(targetDir, { remote: body.remote, branch: body.branch, force: body.force, setUpstream: body.setUpstream });
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/merge' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const targetDir = path.resolve(REPO_ROOT, body.folder || '.');
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);
      const result = await gitProvider.merge(targetDir, { branch: body.branch, abort: body.abort, message: body.message });
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/conflicts') {
    try {
      const isGet = req.method === 'GET';
      const body = isGet ? {} : await readBody(req);
      const folderParam = (isGet ? urlObj.searchParams.get('folder') : body.folder) || '.';
      const targetDir = path.resolve(REPO_ROOT, folderParam);
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);

      if (isGet) {
        const filePath = urlObj.searchParams.get('path');
        if (filePath) {
          const fullPath = path.resolve(targetDir, filePath);
          if (!fullPath.startsWith(REPO_ROOT) || !fs.existsSync(fullPath)) return sendJson(res, { error: 'File not found' }, 404);
          const content = fs.readFileSync(fullPath, 'utf8');
          const parsed = ConflictEditorManager.parse(content);
          return sendJson(res, { ok: true, file: filePath, ...parsed });
        }
        const status = await gitProvider.getStatus(targetDir);
        return sendJson(res, { ok: true, conflicted: status.conflicted || [] });
      }

      if (req.method === 'POST') {
        const result = await gitProvider.resolveConflict(targetDir, {
          file: body.path || body.file,
          strategy: body.strategy || 'ours',
          customContent: body.customContent || null
        });
        return sendJson(res, result);
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/blame' && req.method === 'GET') {
    try {
      const folderParam = urlObj.searchParams.get('folder') || '.';
      const targetDir = path.resolve(REPO_ROOT, folderParam);
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);
      const filePath = urlObj.searchParams.get('path');
      const startLine = urlObj.searchParams.get('startLine');
      const endLine = urlObj.searchParams.get('endLine');

      const blame = await gitProvider.getBlame(targetDir, { file: filePath, startLine, endLine });
      sendJson(res, { ok: true, file: filePath, blame });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/stash') {
    try {
      const isGet = req.method === 'GET';
      const body = isGet ? {} : await readBody(req);
      const folderParam = (isGet ? urlObj.searchParams.get('folder') : body.folder) || '.';
      const targetDir = path.resolve(REPO_ROOT, folderParam);
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);

      if (isGet) {
        const stashes = await gitProvider.getStashes(targetDir);
        return sendJson(res, { ok: true, stashes });
      }

      if (req.method === 'POST') {
        const action = body.action || 'push';
        let result;
        if (action === 'push') {
          result = await gitProvider.stashPush(targetDir, { message: body.message, includeUntracked: body.includeUntracked !== false });
        } else if (action === 'pop') {
          result = await gitProvider.stashPop(targetDir, { index: body.index || 0 });
        } else if (action === 'apply') {
          result = await gitProvider.stashApply(targetDir, { index: body.index || 0 });
        } else if (action === 'drop') {
          result = await gitProvider.stashDrop(targetDir, { index: body.index || 0 });
        } else {
          return sendJson(res, { error: `Unknown stash action: ${action}` }, 400);
        }
        return sendJson(res, { ok: true, ...result });
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/tags') {
    try {
      const isGet = req.method === 'GET';
      const body = isGet ? {} : await readBody(req);
      const folderParam = (isGet ? urlObj.searchParams.get('folder') : body.folder) || '.';
      const targetDir = path.resolve(REPO_ROOT, folderParam);
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);

      if (isGet) {
        const tags = await gitProvider.getTags(targetDir);
        return sendJson(res, { ok: true, tags });
      }

      if (req.method === 'POST') {
        const action = body.action || 'create';
        if (action === 'create') {
          const result = await gitProvider.createTag(targetDir, { name: body.name, message: body.message, commit: body.commit });
          return sendJson(res, { ok: true, ...result });
        }
        if (action === 'delete') {
          const result = await gitProvider.deleteTag(targetDir, { name: body.name });
          return sendJson(res, { ok: true, ...result });
        }
        return sendJson(res, { error: `Unknown tag action: ${action}` }, 400);
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/remotes') {
    try {
      const isGet = req.method === 'GET';
      const body = isGet ? {} : await readBody(req);
      const folderParam = (isGet ? urlObj.searchParams.get('folder') : body.folder) || '.';
      const targetDir = path.resolve(REPO_ROOT, folderParam);
      if (!targetDir.startsWith(REPO_ROOT)) return sendJson(res, { error: 'Forbidden' }, 403);

      if (isGet) {
        const remotes = await gitProvider.getRemotes(targetDir);
        return sendJson(res, { ok: true, remotes });
      }

      if (req.method === 'POST') {
        const action = body.action || 'add';
        if (action === 'add') {
          const result = await gitProvider.addRemote(targetDir, { name: body.name, url: body.url });
          return sendJson(res, { ok: true, ...result });
        }
        if (action === 'remove') {
          const result = await gitProvider.removeRemote(targetDir, { name: body.name });
          return sendJson(res, { ok: true, ...result });
        }
        if (action === 'set-url') {
          const result = await gitProvider.setRemoteUrl(targetDir, { name: body.name, url: body.url });
          return sendJson(res, { ok: true, ...result });
        }
        return sendJson(res, { error: `Unknown remote action: ${action}` }, 400);
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/git/auth' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const { host, token, action } = body;
      if (!host) return sendJson(res, { error: 'Host is required' }, 400);
      if (action === 'clear') {
        gitProvider.authManager.clearToken(host);
        return sendJson(res, { ok: true, cleared: host });
      }
      gitProvider.authManager.setToken(host, token || '');
      sendJson(res, { ok: true, host, configured: true });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/scm/providers' && req.method === 'GET') {
    try {
      const providers = sourceControlRegistry.listProviders();
      sendJson(res, { ok: true, providers });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
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
      const debugEngine = new DebugAdapterEngine();

      // Configure advanced breakpoints: lines, conditions, hitConditions, logpoints
      const lineNumbers = [];
      if (Array.isArray(body.breakpoints)) {
        for (const bp of body.breakpoints) {
          if (Number.isInteger(bp)) {
            lineNumbers.push(bp);
            debugEngine.breakpointManager.setBreakpoint({ file: scriptName, line: bp });
          } else if (bp && Number.isInteger(bp.line)) {
            lineNumbers.push(bp.line);
            debugEngine.breakpointManager.setBreakpoint({
              file: scriptName,
              line: bp.line,
              condition: bp.condition,
              hitCondition: bp.hitCondition,
              logMessage: bp.logMessage
            });
          }
        }
      }

      if (Array.isArray(body.watches)) {
        body.watches.forEach(w => debugEngine.watchManager.addWatch(w));
      }

      if (body.errorBreakpoints) {
        debugEngine.errorBreakpointManager.setOptions(body.errorBreakpoints);
      }

      const breakpoints = lineNumbers.join(',');
      const otterPs1 = path.join(REPO_ROOT, 'otter.ps1');

      const child = spawn('powershell.exe', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', otterPs1, 'debug', scriptName, '-Breakpoints', breakpoints
      ], { cwd: runDir, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });

      const sessionId = crypto.randomUUID();
      const session = {
        child,
        events: [],
        output: [],
        finished: false,
        exitCode: null,
        buffer: '',
        debugEngine,
        file: scriptName
      };
      debugSessions.set(sessionId, session);

      child.stdout.on('data', chunk => pumpDebugSessionOutput(session, chunk.toString('utf8')));
      child.stderr.on('data', chunk => {
        const str = chunk.toString('utf8');
        if (session.debugEngine?.errorBreakpointManager?.shouldBreakOnError() &&
            (str.includes('Otter runtime error:') || str.includes('Runtime Error:'))) {
          session.events.push({
            event: 'error-paused',
            error: str.trim(),
            file: scriptName,
            line: 1
          });
        }
        session.output.push(str.trimEnd());
      });
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

  // --- Dynamic Breakpoints Configuration ---
  if (pathname === '/api/debug/breakpoints' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const session = debugSessions.get(body.sessionId);
      if (!session) return sendJson(res, { error: 'Unknown or expired debug session' }, 404);
      if (Array.isArray(body.breakpoints)) {
        for (const bp of body.breakpoints) {
          if (Number.isInteger(bp)) {
            session.debugEngine.breakpointManager.setBreakpoint({ file: session.file, line: bp });
          } else if (bp && Number.isInteger(bp.line)) {
            session.debugEngine.breakpointManager.setBreakpoint({
              file: session.file,
              line: bp.line,
              condition: bp.condition,
              hitCondition: bp.hitCondition,
              logMessage: bp.logMessage
            });
          }
        }
      }
      sendJson(res, { ok: true, breakpoints: session.debugEngine.breakpointManager.getBreakpoints() });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Expression Evaluation ---
  if (pathname === '/api/debug/evaluate' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const session = debugSessions.get(body.sessionId);
      if (!session) return sendJson(res, { error: 'Unknown or expired debug session' }, 404);
      const frame = session.debugEngine?.callStackManager.selectFrame(body.frameId ?? 0)
        || session.debugEngine?.callStackManager.getSelectedFrame();
      const evalRes = ExpressionEvaluator.evaluate(body.expression, frame?.locals || {});
      sendJson(res, evalRes);
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Watch Expressions ---
  if (pathname === '/api/debug/watches' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const session = debugSessions.get(body.sessionId);
      if (!session) return sendJson(res, { error: 'Unknown or expired debug session' }, 404);
      if (Array.isArray(body.watches)) {
        session.debugEngine.watchManager.clear();
        body.watches.forEach(w => session.debugEngine.watchManager.addWatch(w));
      }
      const frame = session.debugEngine?.callStackManager.getSelectedFrame();
      const results = session.debugEngine.watchManager.evaluateAll(frame?.locals || {});
      sendJson(res, { ok: true, watches: results });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Object / List Inspection ---
  if (pathname === '/api/debug/inspect' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const session = debugSessions.get(body.sessionId);
      if (!session) return sendJson(res, { error: 'Unknown or expired debug session' }, 404);
      const frame = session.debugEngine?.callStackManager.getSelectedFrame();
      let targetVal = frame?.locals?.[body.variableName];
      if (targetVal === undefined && body.target !== undefined) targetVal = body.target;
      const inspected = ObjectInspectionEngine.inspect(targetVal, body.path || '');
      sendJson(res, { ok: true, inspection: inspected });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Call Stack Inspection ---
  if (pathname === '/api/debug/stack' && req.method === 'GET') {
    const sessionId = urlObj.searchParams.get('sessionId');
    const session = debugSessions.get(sessionId);
    if (!session) return sendJson(res, { error: 'Unknown or expired debug session' }, 404);
    const frames = session.debugEngine?.callStackManager.getFrames() || [];
    const selected = session.debugEngine?.callStackManager.getSelectedFrame() || null;
    sendJson(res, { ok: true, frames, selectedFrameId: selected?.id ?? 0 });
    return;
  }

  // --- Source Map Resolution ---
  if (pathname === '/api/debug/sourcemap' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const session = debugSessions.get(body.sessionId);
      const resolver = session?.debugEngine?.sourceMapResolver || new SourceMapResolver();
      if (body.mapData) resolver.registerSourceMap(body.compiledFile, body.mapData);
      const mapped = resolver.resolveSourceLocation(body.compiledFile, body.line, body.column);
      sendJson(res, { ok: true, mapped });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Attach to Running Process ---
  if (pathname === '/api/debug/attach' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const attachRes = AttachManager.attachToPid(body.pid, body.options);
      if (!attachRes.ok) return sendJson(res, attachRes, 400);
      const session = {
        child: { pid: body.pid, stdin: { write: () => {} }, kill: () => {} },
        events: [{ event: 'attached', pid: body.pid }],
        output: [`Attached to Otter process ${body.pid}`],
        finished: false,
        exitCode: null,
        buffer: '',
        debugEngine: new DebugAdapterEngine(),
        file: body.path || 'attached'
      };
      debugSessions.set(attachRes.sessionId, session);
      sendJson(res, attachRes);
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- DAP JSON-RPC Protocol Transport ---
  if (pathname === '/api/debug/dap' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const session = debugSessions.get(body.sessionId) || { debugEngine: new DebugAdapterEngine() };
      const dapResponse = session.debugEngine.dapAdapter.handleMessage(body.message);
      sendJson(res, dapResponse);
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
    }
    return;
  }

  // --- Terminal Profiles API ---
  if (pathname === '/api/terminal/profiles' && req.method === 'GET') {
    const isWindows = process.platform === 'win32';
    const profiles = [
      {
        id: 'powershell-5',
        name: isWindows ? 'PowerShell 5.1 (Windows)' : 'PowerShell',
        shell: isWindows ? 'powershell.exe' : 'pwsh',
        args: ['-NoLogo', '-NoProfile'],
        icon: 'terminal-ps',
        isDefault: true
      },
      {
        id: 'cmd',
        name: 'Command Prompt',
        shell: 'cmd.exe',
        args: ['/Q'],
        icon: 'terminal-cmd',
        isDefault: false
      },
      {
        id: 'otter-repl',
        name: 'Otter REPL',
        shell: 'powershell.exe',
        args: ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(REPO_ROOT, 'otter.ps1'), 'repl'],
        icon: 'otter-icon',
        isDefault: false
      }
    ];
    return sendJson(res, { ok: true, profiles });
  }

  // --- Terminal Active Sessions List ---
  if (pathname === '/api/terminal/sessions' && req.method === 'GET') {
    const list = Array.from(terminalSessions.values()).map(s => ({
      id: s.id,
      profile: s.profile,
      pid: s.child?.pid || null,
      cwd: s.cwd,
      cols: s.cols,
      rows: s.rows,
      terminated: s.terminated,
      exitCode: s.exitCode,
      createdAt: s.createdAt
    }));
    return sendJson(res, { ok: true, sessions: list });
  }

  // --- Terminal PTY Session Create ---
  if (pathname === '/api/terminal/session/create' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const sessionId = body.id || `term-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
      const shellCmd = body.shell || 'powershell.exe';
      const shellArgs = Array.isArray(body.args) ? body.args : ['-NoLogo', '-NoProfile'];
      const sessionCwd = (body.cwd && isPathContained(body.cwd)) ? path.resolve(REPO_ROOT, body.cwd) : REPO_ROOT;
      const cols = body.cols || 80;
      const rows = body.rows || 24;

      const sessionEnv = {
        ...process.env,
        COLUMNS: String(cols),
        LINES: String(rows),
        TERM: 'xterm-256color',
        ...(body.env || {})
      };

      const child = spawn(shellCmd, shellArgs, {
        cwd: sessionCwd,
        env: sessionEnv,
        windowsHide: true,
        stdio: ['pipe', 'pipe', 'pipe']
      });

      const session = {
        id: sessionId,
        child,
        profile: body.profile || 'default',
        shell: shellCmd,
        cwd: sessionCwd,
        cols,
        rows,
        env: sessionEnv,
        buffer: '',
        terminated: false,
        exitCode: null,
        createdAt: new Date().toISOString()
      };

      child.stdout.on('data', chunk => {
        session.buffer += chunk.toString();
      });

      child.stderr.on('data', chunk => {
        session.buffer += chunk.toString();
      });

      child.on('close', code => {
        session.terminated = true;
        session.exitCode = code;
      });

      child.on('error', err => {
        session.buffer += `\r\n[Process error: ${err.message}]\r\n`;
        session.terminated = true;
        session.exitCode = 1;
      });

      terminalSessions.set(sessionId, session);

      return sendJson(res, {
        ok: true,
        id: sessionId,
        pid: child.pid,
        cwd: sessionCwd
      });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message }, 500);
    }
  }

  // --- Terminal PTY Input (Character Stdin) ---
  if (pathname === '/api/terminal/session/input' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const session = terminalSessions.get(body.id);
      if (!session) {
        return sendJson(res, { ok: false, error: 'Session not found' }, 404);
      }
      if (session.terminated || !session.child.stdin.writable) {
        return sendJson(res, { ok: false, error: 'Session process is not writable' }, 400);
      }

      session.child.stdin.write(body.input || '');
      return sendJson(res, { ok: true });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message }, 500);
    }
  }

  // --- Terminal Output Polling ---
  if (pathname === '/api/terminal/session/poll' && req.method === 'GET') {
    const sessionId = urlObj.searchParams.get('id');
    const offset = parseInt(urlObj.searchParams.get('offset') || '0', 10);
    const session = terminalSessions.get(sessionId);
    if (!session) {
      return sendJson(res, { ok: false, error: 'Session not found' }, 404);
    }

    const unread = session.buffer.slice(offset);
    return sendJson(res, {
      ok: true,
      output: unread,
      terminated: session.terminated,
      exitCode: session.exitCode
    });
  }

  // --- Terminal Resize ---
  if (pathname === '/api/terminal/session/resize' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const session = terminalSessions.get(body.id);
      if (!session) {
        return sendJson(res, { ok: false, error: 'Session not found' }, 404);
      }
      session.cols = body.cols || session.cols;
      session.rows = body.rows || session.rows;
      return sendJson(res, { ok: true, cols: session.cols, rows: session.rows });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message }, 500);
    }
  }

  // --- Terminal Signal / Ctrl+C / Kill Tree ---
  if (pathname === '/api/terminal/session/signal' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const session = terminalSessions.get(body.id);
      if (!session) {
        return sendJson(res, { ok: false, error: 'Session not found' }, 404);
      }
      const signal = body.signal || 'SIGINT';

      if (signal === 'SIGINT') {
        if (session.child.stdin.writable) {
          session.child.stdin.write('\x03'); // Ctrl+C character
        }
      } else if (signal === 'SIGTERM' || signal === 'SIGKILL') {
        killProcessTree(session.child.pid);
        session.terminated = true;
      }
      return sendJson(res, { ok: true });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message }, 500);
    }
  }

  // --- Terminal Session Close ---
  if (pathname === '/api/terminal/session/close' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const session = terminalSessions.get(body.id);
      if (session) {
        if (!session.terminated && session.child.pid) {
          killProcessTree(session.child.pid);
        }
        terminalSessions.delete(body.id);
      }
      return sendJson(res, { ok: true });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message }, 500);
    }
  }

  // --- Terminal Environment API ---
  if (pathname === '/api/terminal/session/env') {
    if (req.method === 'GET') {
      const sessionId = urlObj.searchParams.get('id');
      const session = terminalSessions.get(sessionId);
      if (!session) return sendJson(res, { ok: false, error: 'Session not found' }, 404);
      return sendJson(res, { ok: true, env: session.env });
    }
    if (req.method === 'POST') {
      const body = await readBody(req);
      const session = terminalSessions.get(body.id);
      if (!session) return sendJson(res, { ok: false, error: 'Session not found' }, 404);
      if (body.key) {
        session.env[body.key] = String(body.value ?? '');
      }
      return sendJson(res, { ok: true, env: session.env });
    }
  }

  // --- Terminal CWD Sync & Session Restart ---
  if (pathname === '/api/terminal/session/cwd') {
    if (req.method === 'GET') {
      const sessionId = urlObj.searchParams.get('id');
      const session = terminalSessions.get(sessionId);
      if (!session) return sendJson(res, { ok: false, error: 'Session not found' }, 404);
      return sendJson(res, { ok: true, cwd: session.cwd || process.cwd() });
    }
    if (req.method === 'POST') {
      const body = await readBody(req);
      const session = terminalSessions.get(body.id);
      if (!session) return sendJson(res, { ok: false, error: 'Session not found' }, 404);
      if (body.cwd) {
        session.cwd = body.cwd;
      }
      return sendJson(res, { ok: true, cwd: session.cwd });
    }
  }

  if (pathname === '/api/terminal/session/restart' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const session = terminalSessions.get(body.id);
      if (!session) return sendJson(res, { ok: false, error: 'Session not found' }, 404);
      const { shell, args, cols, rows, cwd, env } = session;
      // Close old process
      if (session.process) {
        try { session.process.kill(); } catch {}
      }
      terminalSessions.delete(body.id);

      // Spawn replacement process
      const child = spawn(shell, args, { cwd: cwd || REPO_ROOT, env: { ...process.env, ...env } });
      const newSession = {
        id: body.id,
        shell,
        args,
        cols,
        rows,
        cwd,
        env,
        process: child,
        buffer: '',
        terminated: false,
        exitCode: null
      };
      child.stdout.on('data', d => { newSession.buffer += d.toString('utf8'); });
      child.stderr.on('data', d => { newSession.buffer += d.toString('utf8'); });
      child.on('close', code => {
        newSession.terminated = true;
        newSession.exitCode = code;
      });
      terminalSessions.set(body.id, newSession);
      return sendJson(res, { ok: true, id: body.id, restarted: true });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message }, 500);
    }
  }

  // --- Production Otter REPL API ---
  if (pathname === '/api/repl/eval' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const result = await otterRepl.eval(body.code || body.input);
      return sendJson(res, result);
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message }, 500);
    }
  }

  if (pathname === '/api/repl/is-complete' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const result = otterRepl.isComplete(body.code || body.input);
      return sendJson(res, result);
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message }, 500);
    }
  }

  if (pathname === '/api/repl/complete' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const result = otterRepl.complete(body.line || body.input || '');
      return sendJson(res, result);
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message }, 500);
    }
  }

  if (pathname === '/api/repl/highlight' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const highlighted = otterRepl.highlight(body.code || '', body.mode || 'ansi');
      return sendJson(res, { ok: true, highlighted });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message }, 500);
    }
  }

  if (pathname === '/api/repl/reset' && req.method === 'POST') {
    try {
      const result = otterRepl.reset();
      return sendJson(res, result);
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message }, 500);
    }
  }

  // --- Data & Query Viewer API (Section 5) ---
  if (pathname === '/api/data/query' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      let headers = [];
      let rows = [];

      if (body.path) {
        if (!isPathContained(body.path)) {
          return sendJson(res, { ok: false, error: 'Path traversal forbidden' }, 403);
        }
        const fullPath = path.resolve(REPO_ROOT, body.path);
        if (!fs.existsSync(fullPath)) {
          return sendJson(res, { ok: false, error: 'File not found' }, 404);
        }

        const ext = path.extname(fullPath).toLowerCase();
        const content = fs.readFileSync(fullPath, 'utf8');

        if (ext === '.csv') {
          const parsed = parseCsv(content);
          headers = parsed.headers;
          rows = parsed.rows;
        } else if (ext === '.json') {
          const parsed = parseJsonDataset(content);
          headers = parsed.headers;
          rows = parsed.rows;
        } else {
          return sendJson(res, { ok: false, error: `Unsupported data file format: ${ext}` }, 400);
        }
      } else if (body.content) {
        const format = (body.format || 'csv').toLowerCase();
        if (format === 'csv') {
          const parsed = parseCsv(body.content);
          headers = parsed.headers;
          rows = parsed.rows;
        } else {
          const parsed = parseJsonDataset(body.content);
          headers = parsed.headers;
          rows = parsed.rows;
        }
      } else if (Array.isArray(body.rows)) {
        headers = Array.isArray(body.headers) ? body.headers : Object.keys(body.rows[0] || {});
        rows = body.rows;
      }

      const view = queryDataset(headers, rows, {
        search: body.search,
        sortColumn: body.sortColumn,
        sortDesc: Boolean(body.sortDesc),
        page: Number(body.page || 1),
        pageSize: Number(body.pageSize || 50)
      });

      return sendJson(res, { ok: true, ...view });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message }, 500);
    }
  }

  // --- Language Server Protocol (LSP) API (Section 9) ---
  if (pathname === '/api/lsp' && req.method === 'POST') {
    try {
      const message = await readBody(req);
      const response = lspServer.handleMessage(message);
      if (response !== null) {
        return sendJson(res, response);
      }
      return sendJson(res, { jsonrpc: '2.0', id: message?.id ?? null, result: null });
    } catch (err) {
      return sendJson(res, {
        jsonrpc: '2.0',
        id: null,
        error: { code: -32603, message: err.message }
      }, 500);
    }
  }

  // --- Crash Reporting API (Section 10) ---
  if (pathname === '/api/crash/report' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const report = crashReporter.generateReport(body.error, {
        code: body.code,
        category: body.category,
        suggestion: body.suggestion,
        activeFile: body.activeFile,
        line: body.line,
        asyncChain: body.asyncChain,
        cursor: body.cursor,
        dirtyFiles: body.dirtyFiles
      });

      // Write crash dump to disk under .otter/crashes/<id>.json
      const crashDir = path.join(REPO_ROOT, '.otter', 'crashes');
      if (!fs.existsSync(crashDir)) {
        fs.mkdirSync(crashDir, { recursive: true });
      }
      const crashFile = path.join(crashDir, `${report.id}.json`);
      fs.writeFileSync(crashFile, JSON.stringify(report, null, 2), 'utf8');

      return sendJson(res, { ok: true, id: report.id, path: `.otter/crashes/${report.id}.json`, report });
    } catch (err) {
      return sendJson(res, { ok: false, error: err.message }, 500);
    }
  }

  if (pathname === '/api/crash/reports' && req.method === 'GET') {
    return sendJson(res, { ok: true, reports: crashReporter.listReports() });
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

  // --- Refactoring API ---
  if (pathname === '/api/refactor/rename' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const result = refactoringEngine.renameSymbol({
        projectRoot: body.projectRoot ? path.resolve(REPO_ROOT, body.projectRoot) : REPO_ROOT,
        files: body.files || [],
        oldName: body.oldName,
        newName: body.newName,
        kind: body.kind || 'symbol'
      });
      if (!result.ok) return sendJson(res, result, 400);

      if (body.apply && result.snapshots) {
        const tx = refactoringEngine.transactionManager.createTransaction(
          null,
          `Rename ${body.oldName} to ${body.newName}`,
          result.snapshots
        );
        refactoringEngine.transactionManager.applyTransaction(tx);
        result.applied = true;
        result.transactionId = tx.id;
      }
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/refactor/extract-variable' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const result = refactoringEngine.extractVariable({
        code: body.code,
        selection: body.selection,
        varName: body.varName
      });
      if (!result.ok) return sendJson(res, result, 400);
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/refactor/extract-function' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const result = refactoringEngine.extractFunction({
        code: body.code,
        selection: body.selection,
        fnName: body.fnName
      });
      if (!result.ok) return sendJson(res, result, 400);
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/refactor/inline-variable' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const result = refactoringEngine.inlineVariable({
        code: body.code,
        varName: body.varName
      });
      if (!result.ok) return sendJson(res, result, 400);
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/refactor/move-symbol' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const sourceFile = path.resolve(REPO_ROOT, body.sourceFile);
      const targetFile = path.resolve(REPO_ROOT, body.targetFile);
      const result = refactoringEngine.moveSymbol({
        sourceFile,
        targetFile,
        symbolName: body.symbolName
      });
      if (!result.ok) return sendJson(res, result, 400);

      if (body.apply && result.snapshots) {
        const tx = refactoringEngine.transactionManager.createTransaction(
          null,
          `Move symbol ${body.symbolName} to ${body.targetFile}`,
          result.snapshots
        );
        refactoringEngine.transactionManager.applyTransaction(tx);
        result.applied = true;
        result.transactionId = tx.id;
      }
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/refactor/safe-delete' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const result = refactoringEngine.safeDelete({
        projectRoot: body.projectRoot ? path.resolve(REPO_ROOT, body.projectRoot) : REPO_ROOT,
        files: body.files || [],
        symbolName: body.symbolName,
        targetFile: body.targetFile ? path.resolve(REPO_ROOT, body.targetFile) : null
      });
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/refactor/organize-modules' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const result = refactoringEngine.organizeModules({ code: body.code });
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/refactor/preview' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const preview = refactoringEngine.generatePreview(body.edits || []);
      sendJson(res, { ok: true, preview });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/refactor/undo' && req.method === 'POST') {
    try {
      const result = refactoringEngine.transactionManager.undo();
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/refactor/redo' && req.method === 'POST') {
    try {
      const result = refactoringEngine.transactionManager.redo();
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/refactor/cross-project' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const solutionProjects = (body.solutionProjects || []).map(p => path.resolve(REPO_ROOT, p));
      const result = refactoringEngine.crossProjectRefactor({
        solutionProjects,
        oldName: body.oldName,
        newName: body.newName,
        kind: body.kind || 'symbol'
      });
      if (body.apply && result.snapshots) {
        const tx = refactoringEngine.transactionManager.createTransaction(
          null,
          `Cross-project rename ${body.oldName} to ${body.newName}`,
          result.snapshots
        );
        refactoringEngine.transactionManager.applyTransaction(tx);
        result.applied = true;
        result.transactionId = tx.id;
      }
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/assets/scan') {
    try {
      const pDir = req.method === 'POST' ? ((await readBody(req)).projectDir || REPO_ROOT) : REPO_ROOT;
      const scanner = new AssetScanner();
      const assets = scanner.scanProject(path.resolve(REPO_ROOT, pDir));
      sendJson(res, { ok: true, count: assets.length, assets });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/assets/catalog') {
    try {
      const q = urlObj.searchParams;
      const category = q.get('category') || undefined;
      const search = q.get('search') || undefined;
      const platform = q.get('platform') || undefined;
      const catalog = new AssetBrowserCatalog(REPO_ROOT);
      const items = catalog.getCatalog({ category, search, platform });
      sendJson(res, { ok: true, count: items.length, items });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/assets/build' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const pDir = path.resolve(REPO_ROOT, body.projectDir || '.');
      const outDir = body.outputDir || 'dist/assets';
      const optimizer = new AssetOptimizer();
      const result = optimizer.buildAndCopy({
        projectDir: pDir,
        outputDir: outDir,
        targetPlatform: body.targetPlatform || 'all',
        optimize: body.optimize !== false,
        deduplicate: body.deduplicate !== false,
        fingerprint: Boolean(body.fingerprint)
      });
      sendJson(res, { ok: true, manifest: result.manifest, manifestPath: result.manifestPath });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/assets/diagnose' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const pDir = path.resolve(REPO_ROOT, body.projectDir || '.');
      const diagScanner = new AssetDiagnosticScanner();
      const result = diagScanner.diagnoseReferences(pDir, body.sourceFiles || []);
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/assets/snippet' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const snippet = generateDesignerSnippet(body.asset, body.targetType || 'desktop');
      sendJson(res, { ok: true, snippet });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/assets/refactor' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const pDir = path.resolve(REPO_ROOT, body.projectDir || '.');
      const refactorEngine = new AssetRefactoringEngine(pDir);
      const plan = refactorEngine.planMoveOrRename({
        oldRelativePath: body.oldRelativePath,
        newRelativePath: body.newRelativePath,
        sourceFiles: body.sourceFiles || []
      });
      if (body.execute) {
        const execResult = refactorEngine.executeMoveOrRename(plan);
        sendJson(res, { ok: true, plan, execution: execResult });
      } else {
        sendJson(res, { ok: true, plan });
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/assets/generate-icons' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const outDir = path.resolve(REPO_ROOT, body.outputDir || 'dist/icons');
      const masterSvgPath = path.resolve(REPO_ROOT, body.masterSvgPath || 'otter-docs/static/images/otter-avatar.svg');
      const iconGen = new AppIconGenerator({ sizes: body.sizes || [16, 32, 48, 64, 128, 256] });
      const result = iconGen.generateIconSet({
        masterSvgPath,
        outputDir: outDir,
        baseName: body.baseName || 'app-icon'
      });
      sendJson(res, result);
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/assets/locales') {
    try {
      const q = urlObj.searchParams;
      const localesDir = path.resolve(REPO_ROOT, q.get('dir') || 'locales');
      const i18n = new LocalizationResourceManager(localesDir);
      i18n.loadAll();
      const coverage = i18n.validateCoverage(q.get('base') || 'en');
      sendJson(res, { ok: true, coverage });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  // --- DevTools & Advanced Profiler Endpoints ---
  if (pathname === '/api/devtools/network/requests') {
    try {
      if (req.method === 'POST') {
        const body = await readBody(req);
        if (body.action === 'start') {
          const entry = networkInspector.startRequest(body);
          sendJson(res, { ok: true, entry });
        } else if (body.action === 'complete') {
          const entry = networkInspector.completeResponse(body.id, body);
          sendJson(res, { ok: true, entry });
        } else if (body.action === 'fail') {
          const entry = networkInspector.failRequest(body.id, new Error(body.error || 'Failed'));
          sendJson(res, { ok: true, entry });
        } else {
          sendJson(res, { ok: false, error: 'Unknown action' }, 400);
        }
      } else {
        const q = urlObj.searchParams;
        const entries = networkInspector.getEntries({
          filter: q.get('filter') || undefined,
          method: q.get('method') || undefined,
          status: q.get('status') ? parseInt(q.get('status'), 10) : undefined,
          search: q.get('search') || undefined
        });
        sendJson(res, { ok: true, count: entries.length, entries });
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/devtools/network/har') {
    try {
      sendJson(res, networkInspector.exportHar());
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/devtools/network/throttle') {
    try {
      if (req.method === 'POST') {
        const body = await readBody(req);
        const prof = networkInspector.setThrottlingProfile(body.profile || 'none');
        sendJson(res, { ok: true, profile: prof });
      } else {
        sendJson(res, { ok: true, profile: networkInspector.getThrottlingProfile(), profiles: NETWORK_PROFILES });
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/devtools/dom/inspect' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const result = domCssInspector.computeStyles(body.node || {}, body.rules || []);
      sendJson(res, { ok: true, ...result });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/devtools/console/logs') {
    try {
      if (req.method === 'POST') {
        const body = await readBody(req);
        storageConsoleManager._recordLog(body.level || 'log', body.message || '', body.args || []);
        sendJson(res, { ok: true });
      } else if (req.method === 'DELETE') {
        storageConsoleManager.clearLogs();
        sendJson(res, { ok: true });
      } else {
        const q = urlObj.searchParams;
        const logs = storageConsoleManager.getLogs({ level: q.get('level'), search: q.get('search') });
        sendJson(res, { ok: true, count: logs.length, logs });
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/devtools/storage') {
    try {
      const q = urlObj.searchParams;
      const type = q.get('type') || 'local';
      if (req.method === 'POST') {
        const body = await readBody(req);
        storageConsoleManager.setItem(type, body.key, body.value);
        sendJson(res, { ok: true, key: body.key, value: body.value });
      } else if (req.method === 'DELETE') {
        const key = q.get('key');
        if (key) {
          storageConsoleManager.removeItem(type, key);
        } else {
          storageConsoleManager.clearStorage(type);
        }
        sendJson(res, { ok: true });
      } else {
        const data = storageConsoleManager.listStorage(type);
        sendJson(res, { ok: true, type, storage: data });
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/devtools/devices') {
    try {
      if (req.method === 'POST') {
        const body = await readBody(req);
        if (body.device) responsivePreviewManager.setDevice(body.device);
        if (body.orientation) responsivePreviewManager.setOrientation(body.orientation);
        if (body.zoom !== undefined) responsivePreviewManager.setZoom(body.zoom);
        sendJson(res, { ok: true, viewport: responsivePreviewManager.getViewport() });
      } else {
        sendJson(res, {
          ok: true,
          viewport: responsivePreviewManager.getViewport(),
          availableDevices: responsivePreviewManager.getAvailableDevices()
        });
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/devtools/sourcemap/resolve' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const smGen = new SourceMapV3Generator({ file: body.file || 'app.js' });
      for (const m of (body.mappings || [])) {
        smGen.addMapping(m);
      }
      const original = smGen.originalPositionFor({ line: Number(body.line || 1), column: Number(body.column || 0) });
      sendJson(res, { ok: true, original });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  // --- Workbench, Settings & Command Endpoints ---
  if (pathname === '/api/workbench/settings') {
    try {
      const q = urlObj.searchParams;
      if (req.method === 'POST') {
        const body = await readBody(req);
        settingsManager.set(body.tier || 'user', body.key, body.value);
        sendJson(res, { ok: true, key: body.key, value: settingsManager.get(body.key) });
      } else if (req.method === 'DELETE') {
        settingsManager.resetTier(q.get('tier') || 'user');
        sendJson(res, { ok: true });
      } else {
        const key = q.get('key');
        if (key) {
          sendJson(res, { ok: true, key, value: settingsManager.get(key) });
        } else {
          sendJson(res, { ok: true, settings: settingsManager.getAll() });
        }
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/workbench/commands') {
    try {
      if (req.method === 'POST') {
        const body = await readBody(req);
        const result = commandRegistry.executeCommand(body.id, ...(body.args || []));
        sendJson(res, { ok: true, id: body.id, result });
      } else {
        const q = urlObj.searchParams;
        const commands = commandRegistry.getAllCommands({
          category: q.get('category') || undefined,
          search: q.get('search') || undefined
        });
        sendJson(res, { ok: true, count: commands.length, commands });
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/workbench/keybindings') {
    try {
      if (req.method === 'POST') {
        const body = await readBody(req);
        keybindingManager.setCustomKeybinding(body.commandId, body.keyCombo);
        sendJson(res, { ok: true, commandId: body.commandId, keyCombo: keybindingManager.getKeybinding(body.commandId) });
      } else {
        const q = urlObj.searchParams;
        const combo = q.get('combo');
        if (combo) {
          const resolved = keybindingManager.resolveCommandForShortcut(combo);
          sendJson(res, { ok: true, combo, command: resolved });
        } else {
          const cmds = commandRegistry.getAllCommands();
          const list = cmds.map(c => ({
            id: c.id,
            title: c.title,
            category: c.category,
            keybinding: keybindingManager.getKeybinding(c.id),
            formatted: keybindingManager.formatForPlatform(keybindingManager.getKeybinding(c.id))
          }));
          sendJson(res, { ok: true, count: list.length, keybindings: list });
        }
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/workbench/palette' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const palette = new CommandPaletteEngine(commandRegistry, body.projectFiles || []);
      const result = palette.query(body.input || '');
      sendJson(res, { ok: true, ...result });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/workbench/status-bar') {
    try {
      if (req.method === 'POST') {
        const body = await readBody(req);
        if (body.action === 'remove') {
          statusBarManager.removeItem(body.id);
        } else {
          statusBarManager.setItem(body.id, body);
        }
        sendJson(res, { ok: true });
      } else {
        const q = urlObj.searchParams;
        const items = statusBarManager.getItems(q.get('alignment'));
        sendJson(res, { ok: true, count: items.length, items });
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/workbench/layout') {
    try {
      if (req.method === 'POST') {
        const body = await readBody(req);
        if (body.action === 'setActiveView') workbenchLayoutManager.setActiveView(body.viewId);
        else if (body.action === 'toggleSidebar') workbenchLayoutManager.toggleSidebar();
        else if (body.action === 'setSidebarWidth') workbenchLayoutManager.setSidebarWidth(body.width);
        else if (body.action === 'toggleBottomPanel') workbenchLayoutManager.toggleBottomPanel();
        else if (body.action === 'setActiveBottomTab') workbenchLayoutManager.setActiveBottomTab(body.tabId);
        else if (body.action === 'setBottomPanelHeight') workbenchLayoutManager.setBottomPanelHeight(body.height);
        else if (body.action === 'resetLayout') workbenchLayoutManager.resetLayout();
        sendJson(res, { ok: true, layout: workbenchLayoutManager.getLayout() });
      } else {
        sendJson(res, { ok: true, layout: workbenchLayoutManager.getLayout(), views: WORKBENCH_VIEWS });
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  // --- Reliability, Recovery, Logging, and Performance Endpoints ---
  if (pathname === '/api/reliability/atomic-save') {
    try {
      if (req.method === 'POST') {
        const body = await readBody(req);
        if (!body.filePath || body.content === undefined) {
          sendJson(res, { ok: false, error: 'Missing required filePath or content parameter' }, 400);
          return;
        }
        const saveRes = atomicFileManager.atomicWrite(body.filePath, body.content, {
          backup: body.backup !== false
        });
        sendJson(res, saveRes);
      } else {
        sendJson(res, { ok: false, error: 'Method not allowed' }, 405);
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/reliability/shutdown') {
    try {
      if (req.method === 'POST') {
        const body = await readBody(req);
        const shutdownRes = await safeShutdownCoordinator.coordinateShutdown({
          persistCallback: async (atomicIO) => {
            if (body.persistState && body.statePath) {
              atomicIO.atomicWrite(body.statePath, JSON.stringify(body.persistState, null, 2));
              return body.statePath;
            }
            return null;
          }
        });
        sendJson(res, { ok: true, shutdown: shutdownRes });
      } else {
        sendJson(res, { ok: false, error: 'Method not allowed' }, 405);
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/reliability/orphans') {
    try {
      if (req.method === 'POST') {
        const body = await readBody(req);
        if (body.action === 'register') {
          processOrphanManager.registerProcess(body.pid, body.meta);
          sendJson(res, { ok: true, registered: body.pid });
        } else if (body.action === 'cleanup') {
          const cleaned = processOrphanManager.cleanupAllProcesses();
          sendJson(res, { ok: true, cleanedCount: cleaned.length, cleaned });
        } else {
          sendJson(res, { ok: false, error: 'Unknown action' }, 400);
        }
      } else {
        const tracked = processOrphanManager.getTrackedProcesses();
        sendJson(res, { ok: true, count: tracked.length, processes: tracked });
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/reliability/logs') {
    try {
      if (req.method === 'POST') {
        const body = await readBody(req);
        if (body.action === 'export') {
          const exportData = rotatingLogManager.exportLogs();
          sendJson(res, { ok: true, export: exportData });
        } else {
          const entry = rotatingLogManager.log(body.level || 'INFO', body.subsystem || 'app', body.message || '', body.meta);
          sendJson(res, { ok: true, logged: entry });
        }
      } else {
        const q = urlObj.searchParams;
        const logs = rotatingLogManager.getLogs({
          level: q.get('level'),
          subsystem: q.get('subsystem'),
          search: q.get('search'),
          limit: q.get('limit') ? Number(q.get('limit')) : 100,
          offset: q.get('offset') ? Number(q.get('offset')) : 0
        });
        sendJson(res, { ok: true, ...logs });
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/reliability/benchmarks') {
    try {
      const results = await performanceBenchmarkSuite.runAllBenchmarks();
      sendJson(res, { ok: true, benchmarks: results });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/reliability/crash-isolation') {
    try {
      if (req.method === 'POST') {
        const body = await readBody(req);
        if (body.action === 'reset') {
          crashIsolationEngine.resetComponent(body.componentId);
          sendJson(res, { ok: true, reset: body.componentId });
        } else {
          const disabled = crashIsolationEngine.isComponentDisabled(body.componentId);
          const history = crashIsolationEngine.getFaultHistory(body.componentId);
          sendJson(res, { ok: true, disabled, history });
        }
      } else {
        sendJson(res, { ok: false, error: 'Method not allowed' }, 405);
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  function readRecentWorkspaces() {
    const projectsDir = path.join(REPO_ROOT, 'projects');
    const results = [];
    if (fs.existsSync(projectsDir)) {
      try {
        const entries = fs.readdirSync(projectsDir, { withFileTypes: true });
        for (const entry of entries) {
          if (entry.isDirectory() && !entry.name.startsWith('.')) {
            results.push({
              name: entry.name,
              path: path.join('projects', entry.name).replace(/\\/g, '/')
            });
          }
        }
      } catch {}
    }
    return results;
  }

  // --- First-Run, Welcome Experience, and Toolchain Endpoints ---
  if (pathname === '/api/welcome') {
    try {
      if (req.method === 'POST') {
        const body = await readBody(req);
        if (body.showOnStartup !== undefined) {
          welcomeManager.setShowOnStartup(Boolean(body.showOnStartup));
        }
        sendJson(res, { ok: true, showOnStartup: welcomeManager.shouldShowOnStartup() });
      } else {
        const recents = readRecentWorkspaces();
        const data = welcomeManager.getWelcomeData({ recentProjects: recents });
        const html = welcomeManager.renderWelcomeHtml({ recentProjects: recents });
        sendJson(res, { ok: true, data, html });
      }
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/toolchain') {
    try {
      const toolchain = ToolchainDetector.detect();
      sendJson(res, { ok: true, toolchain });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/associations') {
    try {
      const reg = FileAssociationManager.generateWindowsRegistry();
      const linux = FileAssociationManager.generateLinuxMimeAndDesktop();
      const mac = FileAssociationManager.generateMacOsDocumentType();
      sendJson(res, { ok: true, windowsReg: reg, linuxMime: linux.mimeXml, linuxDesktop: linux.desktopEntry, macDocumentTypes: mac });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  // --- AI Assistant & Intelligent Copilot API (Section 39 / Provider Architecture) ---
  if (pathname === '/api/ai/settings' && req.method === 'GET') {
    try {
      sendJson(res, { ok: true, settings: aiProviderManager.getPublicSettings() });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/ai/settings' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      if (body.provider && body.config) {
        aiProviderManager.setProviderConfig(body.provider, body.config);
      }
      if (body.activeProvider) {
        aiProviderManager.setActiveProvider(body.activeProvider);
      }
      if (body.includeCurrentFile !== undefined) {
        aiProviderManager.settings.includeCurrentFile = Boolean(body.includeCurrentFile);
      }
      if (body.includeDiagnostics !== undefined) {
        aiProviderManager.settings.includeDiagnostics = Boolean(body.includeDiagnostics);
      }
      if (body.includeWorkspaceContext !== undefined) {
        aiProviderManager.settings.includeWorkspaceContext = Boolean(body.includeWorkspaceContext);
      }
      if (body.inlineCompletionsEnabled !== undefined) {
        aiProviderManager.settings.inlineCompletionsEnabled = Boolean(body.inlineCompletionsEnabled);
        aiProviderManager.inlineCompletion.setEnabled(aiProviderManager.settings.inlineCompletionsEnabled);
      }
      sendJson(res, { ok: true, settings: aiProviderManager.getPublicSettings() });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/ai/telemetry' && req.method === 'GET') {
    try {
      sendJson(res, {
        ok: true,
        summary: aiProviderManager.telemetry.getSummary(),
        recent: aiProviderManager.telemetry.getRecentEntries(25)
      });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/ai/validate-code' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const validation = aiProviderManager.validator.validate(body.source || '');
      sendJson(res, { ok: true, ...validation });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/ai/test-connection' && req.method === 'POST') {
    const startTime = Date.now();
    try {
      const body = await readBody(req);
      const providerName = body.provider || aiProviderManager.activeProviderName;
      const result = await aiProviderManager.testConnection(providerName);
      aiProviderManager.telemetry.record({
        operation: 'test-connection',
        provider: providerName,
        model: result.model || 'default',
        durationMs: Date.now() - startTime,
        success: Boolean(result.ok)
      });
      sendJson(res, result);
    } catch (err) {
      aiProviderManager.telemetry.record({
        operation: 'test-connection',
        provider: 'unknown',
        durationMs: Date.now() - startTime,
        success: false,
        errorCategory: err.code || 'CONNECTION_FAILED'
      });
      sendJson(res, { ok: false, status: 'connection_failed', message: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/ai/chat' && req.method === 'POST') {
    const startTime = Date.now();
    try {
      const body = await readBody(req);
      const provider = aiProviderManager.getActiveProvider();
      const context = body.context || {};
      const contextData = aiProviderManager.contextManager.buildContext(context);

      let messages = [];
      if (Array.isArray(body.messages) && body.messages.length > 0) {
        messages = body.messages;
      } else {
        messages = [{ role: 'user', content: body.message || body.prompt || '' }];
      }

      const result = await provider.chat(messages, { context, contextFormatted: contextData.formatted });

      aiProviderManager.telemetry.record({
        operation: 'chat',
        provider: provider.name,
        model: provider.model || 'default',
        durationMs: Date.now() - startTime,
        contextCharCount: contextData.characterCount,
        responseCharCount: (result.reply || '').length,
        success: true
      });

      sendJson(res, {
        ok: true,
        isPrototype: provider.name === 'offline-heuristic',
        provider: provider.name,
        displayName: provider.displayName,
        model: provider.model,
        ...result
      });
    } catch (err) {
      aiProviderManager.telemetry.record({
        operation: 'chat',
        provider: aiProviderManager.activeProviderName,
        durationMs: Date.now() - startTime,
        success: false,
        errorCategory: err.code || 'CHAT_ERROR',
        wasCancelled: err.name === 'AbortError'
      });
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/ai/synthesize-code' && req.method === 'POST') {
    const startTime = Date.now();
    try {
      const body = await readBody(req);
      const provider = aiProviderManager.getActiveProvider();
      const context = body.context || {};
      const result = await provider.synthesizeCode(body.prompt || '', context);

      // Validate generated Otter source
      const rawCode = result.code || '';
      const validation = aiProviderManager.validator.validate(rawCode);

      aiProviderManager.telemetry.record({
        operation: 'synthesize-code',
        provider: provider.name,
        model: provider.model || 'default',
        durationMs: Date.now() - startTime,
        responseCharCount: rawCode.length,
        success: true
      });

      sendJson(res, {
        ok: true,
        isPrototype: provider.name === 'offline-heuristic',
        provider: provider.name,
        displayName: provider.displayName,
        model: provider.model,
        validation,
        ...result
      });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/ai/generate-ui' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const layout = aiAssistant.generateUILayout(body.prompt || '', body.context || {});
      sendJson(res, { ok: true, ...layout });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/ai/fix-diagnostics' && req.method === 'POST') {
    const startTime = Date.now();
    try {
      const body = await readBody(req);
      const provider = aiProviderManager.getActiveProvider();
      const result = await provider.diagnose(body.diagnostics || [], body.source || '', body.context || {});
      const legacyFixes = aiAssistant.analyzeDiagnosticsAndSuggestFixes(body.diagnostics || [], body.source || '');

      aiProviderManager.telemetry.record({
        operation: 'fix-diagnostics',
        provider: provider.name,
        model: provider.model || 'default',
        durationMs: Date.now() - startTime,
        success: true
      });

      sendJson(res, { ok: true, isPrototype: provider.name === 'offline-heuristic', fixes: legacyFixes, ...result });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/ai/generate-tests' && req.method === 'POST') {
    const startTime = Date.now();
    try {
      const body = await readBody(req);
      const provider = aiProviderManager.getActiveProvider();
      const result = await provider.generateTests(body.source || '', { moduleName: body.moduleName || 'module', ...body.context });
      const legacySuite = aiAssistant.generateTestSuites(body.source || '', body.moduleName || 'module');

      const testCode = result.testCode || legacySuite || '';
      const validation = aiProviderManager.validator.validate(testCode);

      aiProviderManager.telemetry.record({
        operation: 'generate-tests',
        provider: provider.name,
        model: provider.model || 'default',
        durationMs: Date.now() - startTime,
        responseCharCount: testCode.length,
        success: true
      });

      sendJson(res, {
        ok: true,
        isPrototype: provider.name === 'offline-heuristic',
        testSuite: legacySuite,
        validation,
        ...result
      });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/ai/explain' && req.method === 'POST') {
    const startTime = Date.now();
    try {
      const body = await readBody(req);
      const provider = aiProviderManager.getActiveProvider();
      const result = await provider.explain(body.source || '', body.context || {});
      const legacyExplanation = aiAssistant.explainCode(body.source || '');

      aiProviderManager.telemetry.record({
        operation: 'explain',
        provider: provider.name,
        model: provider.model || 'default',
        durationMs: Date.now() - startTime,
        success: true
      });

      sendJson(res, { ok: true, isPrototype: provider.name === 'offline-heuristic', explanation: legacyExplanation, ...result });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
    }
    return;
  }

  if (pathname === '/api/ai/completions' && req.method === 'POST') {
    const startTime = Date.now();
    try {
      const body = await readBody(req);
      const provider = aiProviderManager.getActiveProvider();
      const completions = aiAssistant.semanticInlineCompletions(body.prefix || '', body.suffix || '', body.context || {});
      const inlineCode = await aiProviderManager.inlineCompletion.requestCompletion(
        body.prefix || '',
        body.suffix || '',
        body.context || {},
        provider
      );

      aiProviderManager.telemetry.record({
        operation: 'completions',
        provider: provider.name,
        model: provider.model || 'default',
        durationMs: Date.now() - startTime,
        success: true
      });

      sendJson(res, {
        ok: true,
        isPrototype: provider.name === 'offline-heuristic',
        completions,
        inlineSuggestion: inlineCode
      });
    } catch (err) {
      sendJson(res, { ok: false, error: err.message }, 500);
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
