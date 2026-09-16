// serve.mjs - Local web server & real development backend for Otter Studio
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { exec, execFile, spawn } from 'node:child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..');

const PORT = Number(process.env.OTTER_STUDIO_PORT || 4200);
const ANALYZER_PATH = path.join(REPO_ROOT, 'tools', 'vscode-otter', 'scripts', 'analyze.ps1');
const workspaceSymbolCache = new Map();

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

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (e) {
        resolve({ raw: body });
      }
    });
    req.on('error', reject);
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

function scanDir(dirPath, relativeTo) {
  const entries = fs.readdirSync(dirPath, { withFileTypes: true });
  const result = [];
  for (const entry of entries) {
    const fullPath = path.join(dirPath, entry.name);
    const relPath = path.relative(relativeTo, fullPath).replace(/\\/g, '/');
    if (entry.isDirectory()) {
      result.push({
        name: entry.name,
        path: relPath,
        isDir: true,
        children: scanDir(fullPath, relativeTo)
      });
    } else {
      result.push({
        name: entry.name,
        path: relPath,
        isDir: false,
        size: fs.statSync(fullPath).size
      });
    }
  }
  return result;
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

  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
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

      // 3. Write project.json metadata
      const manifest = {
        name: projName,
        archetype: body.archetype || 'desktop',
        main: fileName,
        created: new Date().toISOString()
      };
      fs.writeFileSync(path.join(projectDir, 'project.json'), JSON.stringify(manifest, null, 2), 'utf8');

      const relFolder = path.relative(REPO_ROOT, projectDir).replace(/\\/g, '/');
      const tree = scanDir(projectDir, projectDir);

      sendJson(res, {
        ok: true,
        folder: relFolder,
        name: projName,
        mainFile: `${relFolder}/${fileName}`,
        tree
      });
    } catch (err) {
      sendJson(res, { error: err.message }, 500);
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

  // --- Execution & Otter Runner API ---
  if (pathname === '/api/run' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const relPath = body.path || 'examples/file-organizer/main.ot';
      const safePath = path.resolve(REPO_ROOT, relPath);

      // Save content first if provided
      if (typeof body.content === 'string') {
        fs.writeFileSync(safePath, body.content, 'utf8');
      }

      const runDir = path.dirname(safePath);
      const scriptName = path.basename(safePath);
      const otterCmd = path.join(REPO_ROOT, 'otter.cmd');
      const cmd = `"${otterCmd}" run "${scriptName}"`;
      const startTime = Date.now();

      exec(cmd, { cwd: runDir, timeout: 10000 }, (error, stdout, stderr) => {
        const durationMs = Date.now() - startTime;
        sendJson(res, {
          exitCode: error ? (error.code || 1) : 0,
          stdout: stdout ? stdout.toString() : '',
          stderr: stderr ? stderr.toString() : '',
          durationMs,
          error: error ? error.message : null
        });
      });
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
          $suggestion = if ($_.Exception.PSObject.Properties['Suggestion']) { $_.Exception.Suggestion } else { $null }
          $kind = if ($_.Exception.PSObject.Properties['Kind']) { $_.Exception.Kind } else { $null }
          [PSCustomObject]@{
            ok = $false
            message = $_.Exception.Message
            line = $line
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

server.listen(PORT, () => {
  console.log(`Otter Studio running with Full Interaction Engine at: http://localhost:${PORT}`);
});
