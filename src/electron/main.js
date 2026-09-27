// main.js - Electron shell for a compiled Otter application.
//
// The program itself is app/index.html, produced by Otter's web compiler; this
// file only opens a window for it and answers its requests for things a web
// page cannot do on its own (files, commands, clipboard, dialogs). Those
// requests arrive over IPC from preload.js, which is the only code with a foot
// in both worlds. The renderer never sees Node.
//
// This file is generic: it knows nothing about any particular Otter program.

'use strict';

const { app, BrowserWindow, ipcMain, dialog, clipboard, shell, Notification } = require('electron');
const path = require('node:path');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const os = require('node:os');
const http = require('node:http');
const https = require('node:https');
const { spawn } = require('node:child_process');

const APP_DIR = path.join(__dirname, 'app');
const INDEX_HTML = path.join(APP_DIR, 'index.html');
const COMMAND_TIMEOUT_MS = 120000;

// OTTER_ELECTRON_SMOKE=<file> runs the app hidden, exercises the bridge
// through the program's own window.otter* functions, writes a JSON report
// to <file> and exits. Otter's test suite uses it; users never set it.
const SMOKE_REPORT = process.env.OTTER_ELECTRON_SMOKE || '';

// -----------------------------------------------------------------------------
// Paths
// -----------------------------------------------------------------------------

// Relative paths in the program resolve against the app's working folder:
// next to the executable once packaged, the app folder while developing.
function workingFolder() {
  if (process.env.OTTER_APP_CWD) return path.resolve(process.env.OTTER_APP_CWD);
  return app.isPackaged ? path.dirname(process.execPath) : path.resolve(__dirname);
}

function requireText(value, what) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`A ${what} is required.`);
  }
  return value;
}

function resolvePath(value) {
  const text = requireText(value, 'file or folder path');
  return path.isAbsolute(text) ? path.normalize(text) : path.join(workingFolder(), text);
}

function formatDate(date) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

async function pathKind(fullPath) {
  try {
    const stat = await fsp.stat(fullPath);
    return stat.isDirectory() ? 'folder' : 'file';
  } catch {
    return null;
  }
}

// -----------------------------------------------------------------------------
// Filesystem
// -----------------------------------------------------------------------------

async function readFile(filePath) {
  const fullPath = resolvePath(filePath);
  if ((await pathKind(fullPath)) !== 'file') throw new Error(`File not found: ${filePath}`);
  const content = await fsp.readFile(fullPath, 'utf8');
  return { path: filePath, fullPath, content, size: content.length };
}

async function writeFile(filePath, content) {
  const fullPath = resolvePath(filePath);
  const text = content === undefined || content === null ? '' : String(content);
  await fsp.mkdir(path.dirname(fullPath), { recursive: true });
  await fsp.writeFile(fullPath, text, 'utf8');
  return { path: filePath, fullPath, size: text.length, saved: true };
}

// Otter's "file" and "folder" things, shaped exactly like the PowerShell bridge's.
async function listEntries(folderPath, recursive, wantFolders) {
  const fullPath = resolvePath(folderPath || '.');
  if ((await pathKind(fullPath)) !== 'folder') throw new Error(`Folder not found: ${folderPath}`);
  const results = [];
  const walk = async (dir) => {
    const entries = await fsp.readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      const entryPath = path.join(dir, entry.name);
      const isDir = entry.isDirectory();
      if (isDir === wantFolders) {
        let stat;
        try { stat = await fsp.stat(entryPath); } catch { continue; }
        const props = wantFolders
          ? { name: entry.name, path: entryPath, created: formatDate(stat.birthtime), modified: formatDate(stat.mtime) }
          : { name: entry.name, path: entryPath, extension: path.extname(entry.name), size: stat.size, created: formatDate(stat.birthtime), modified: formatDate(stat.mtime) };
        results.push({ __otterThing: true, typeName: wantFolders ? 'folder' : 'file', props, order: Object.keys(props) });
      }
      if (isDir && recursive) await walk(entryPath);
    }
  };
  await walk(fullPath);
  return results;
}

// Same operation names and rules as the PowerShell bridge's /api/fs/operate.
async function fileOperation(operation, payload) {
  const p = payload || {};
  switch (operation) {
    case 'file-exists': {
      return { exists: (await pathKind(resolvePath(p.path))) === 'file' };
    }
    case 'append-file': {
      const fullPath = resolvePath(p.path);
      await fsp.mkdir(path.dirname(fullPath), { recursive: true });
      await fsp.appendFile(fullPath, p.content === undefined || p.content === null ? '' : String(p.content), 'utf8');
      return { completed: true };
    }
    case 'copy-file':
    case 'move-file': {
      const from = resolvePath(p.source);
      let to = resolvePath(p.destination);
      if ((await pathKind(from)) !== 'file') {
        throw new Error(`I could not find a file called "${p.source}" to ${operation === 'copy-file' ? 'copy' : 'move'}.`);
      }
      if ((await pathKind(to)) === 'folder') to = path.join(to, path.basename(from));
      else await fsp.mkdir(path.dirname(to), { recursive: true });
      if (operation === 'copy-file') await fsp.copyFile(from, to);
      else await moveEntry(from, to);
      return { completed: true };
    }
    case 'delete-file': {
      const fullPath = resolvePath(p.path);
      const kind = await pathKind(fullPath);
      if (kind === 'folder') throw new Error(`"${p.path}" is a folder. Otter only deletes files.`);
      if (kind !== 'file') throw new Error(`I could not find a file called "${p.path}" to delete.`);
      await fsp.unlink(fullPath);
      return { completed: true };
    }
    case 'create-folder': {
      await fsp.mkdir(resolvePath(p.path), { recursive: true });
      return { completed: true };
    }
    case 'delete-folder': {
      const fullPath = resolvePath(p.path);
      const kind = await pathKind(fullPath);
      if (kind === 'file') throw new Error(`"${p.path}" is a file, not a folder.`);
      if (kind !== 'folder') throw new Error(`I could not find a folder called "${p.path}" to delete.`);
      if ((await fsp.readdir(fullPath)).length > 0) throw new Error(`The folder "${p.path}" is not empty. Otter only deletes empty folders.`);
      await fsp.rmdir(fullPath);
      return { completed: true };
    }
    case 'copy-folder':
    case 'move-folder': {
      const from = resolvePath(p.source);
      let to = resolvePath(p.destination);
      if ((await pathKind(from)) !== 'folder') throw new Error(`I could not find a folder called "${p.source}".`);
      if ((await pathKind(to)) === 'folder') to = path.join(to, path.basename(from));
      if (operation === 'copy-folder') await fsp.cp(from, to, { recursive: true, force: true });
      else await moveEntry(from, to);
      return { completed: true };
    }
    default:
      throw new Error('That filesystem operation is not available.');
  }
}

// rename() fails across drives; fall back to copy + delete.
async function moveEntry(from, to) {
  await fsp.mkdir(path.dirname(to), { recursive: true });
  try {
    await fsp.rename(from, to);
  } catch (err) {
    if (err.code !== 'EXDEV') throw err;
    await fsp.cp(from, to, { recursive: true, force: true });
    await fsp.rm(from, { recursive: true, force: true });
  }
}

function downloadFile(url, filePath) {
  const target = requireText(url, 'download address');
  const fullPath = resolvePath(filePath);
  return new Promise((resolve, reject) => {
    const attempt = (currentUrl, redirectsLeft) => {
      let parsed;
      try { parsed = new URL(currentUrl); } catch { return reject(new Error(`"${currentUrl}" is not a valid web address.`)); }
      const client = parsed.protocol === 'https:' ? https : parsed.protocol === 'http:' ? http : null;
      if (!client) return reject(new Error('Downloads need an http or https address.'));
      const req = client.get(parsed, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          res.resume();
          if (redirectsLeft === 0) return reject(new Error('The download was redirected too many times.'));
          return attempt(new URL(res.headers.location, parsed).href, redirectsLeft - 1);
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          res.resume();
          return reject(new Error(`The download failed with HTTP ${res.statusCode}.`));
        }
        fsp.mkdir(path.dirname(fullPath), { recursive: true }).then(() => {
          const partial = `${fullPath}.otter-download`;
          const out = fs.createWriteStream(partial);
          res.pipe(out);
          out.on('finish', () => {
            fsp.rename(partial, fullPath)
              .then(() => resolve({ url: target, path: filePath, fullPath, downloaded: true }))
              .catch(reject);
          });
          out.on('error', (err) => { fsp.rm(partial, { force: true }).finally(() => reject(err)); });
        }).catch(reject);
      });
      req.on('error', reject);
    };
    attempt(target, 5);
  });
}

// -----------------------------------------------------------------------------
// Commands
// -----------------------------------------------------------------------------

// The shell used for `run "..."`. One place to grow into per-platform choices.
function defaultShell() {
  if (process.platform === 'win32') {
    return { id: 'cmd', name: 'Command Prompt', file: process.env.ComSpec || 'cmd.exe', args: (cmd) => ['/d', '/s', '/c', cmd] };
  }
  return { id: 'sh', name: 'sh', file: '/bin/sh', args: (cmd) => ['-c', cmd] };
}

function runCommand(command) {
  const text = requireText(command, 'command');
  const sh = defaultShell();
  const cwd = workingFolder();
  return new Promise((resolve) => {
    let stdout = '';
    let stderr = '';
    let finished = false;
    const child = spawn(sh.file, sh.args(text), { cwd, windowsHide: true, env: process.env });
    const timer = setTimeout(() => {
      if (finished) return;
      stderr += `\nThe command did not finish within ${COMMAND_TIMEOUT_MS / 1000} seconds and was stopped.`;
      child.kill();
    }, COMMAND_TIMEOUT_MS);
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    const done = (exitCode) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      resolve({ command: text, shell: sh.name, shellId: sh.id, cwd, exitCode, stdout, stderr, output: stdout + (stderr ? (stdout ? '\n' : '') + stderr : '') });
    };
    child.on('error', (err) => { stderr += String(err.message || err); done(-1); });
    child.on('close', (code) => done(code === null ? -1 : code));
  });
}

// -----------------------------------------------------------------------------
// System
// -----------------------------------------------------------------------------

function systemInfo(name) {
  const varName = typeof name === 'string' && name ? name : null;
  return {
    completed: true,
    name: varName,
    value: varName ? (process.env[varName] ?? null) : null,
    tempFolder: os.tmpdir(),
    appDataFolder: app.getPath('appData'),
    userFolder: os.homedir(),
    currentDirectory: workingFolder()
  };
}

function notify(title, message) {
  const heading = typeof title === 'string' && title ? title : 'Otter Notification';
  const body = typeof message === 'string' ? message : '';
  if (Notification.isSupported()) {
    new Notification({ title: heading, body }).show();
  }
  return { completed: true, title: heading, message: body };
}

async function pickPath(kind, ownerWindow) {
  const defaultPath = workingFolder();
  if (kind === 'save') {
    const result = await dialog.showSaveDialog(ownerWindow, { defaultPath });
    return { path: result.canceled ? '' : result.filePath, cancelled: result.canceled };
  }
  const result = await dialog.showOpenDialog(ownerWindow, {
    defaultPath,
    properties: [kind === 'folder' ? 'openDirectory' : 'openFile']
  });
  const chosen = result.canceled || result.filePaths.length === 0 ? '' : result.filePaths[0];
  return { path: chosen, cancelled: !chosen };
}

// -----------------------------------------------------------------------------
// IPC
// -----------------------------------------------------------------------------

// Every handler answers { value } or { __otterError } so the renderer gets a
// plain, readable message instead of Electron's "Error invoking remote method".
function handle(channel, fn) {
  ipcMain.handle(channel, async (event, ...args) => {
    try {
      return { value: await fn(event, ...args) };
    } catch (err) {
      return { __otterError: String((err && err.message) || err) };
    }
  });
}

function registerBridge() {
  handle('otter:fs:read', (_e, p) => readFile(p));
  handle('otter:fs:write', (_e, p, c) => writeFile(p, c));
  handle('otter:fs:download', (_e, u, p) => downloadFile(u, p));
  handle('otter:fs:files', (_e, p, r) => listEntries(p, Boolean(r), false));
  handle('otter:fs:folders', (_e, p, r) => listEntries(p, Boolean(r), true));
  handle('otter:fs:operate', (_e, op, payload) => fileOperation(String(op || ''), payload));
  handle('otter:terminal:exec', (_e, c) => runCommand(c));
  handle('otter:system:clipboard-write', (_e, text) => {
    const value = text === undefined || text === null ? '' : String(text);
    clipboard.writeText(value);
    return { completed: true, length: value.length };
  });
  handle('otter:system:clipboard-read', () => clipboard.readText());
  handle('otter:system:notify', (_e, t, m) => notify(t, m));
  handle('otter:system:env', (_e, n) => systemInfo(n));
  handle('otter:dialog:open-file', (e) => pickPath('file', BrowserWindow.fromWebContents(e.sender)));
  handle('otter:dialog:save-file', (e) => pickPath('save', BrowserWindow.fromWebContents(e.sender)));
  handle('otter:dialog:folder', (e) => pickPath('folder', BrowserWindow.fromWebContents(e.sender)));
}

// -----------------------------------------------------------------------------
// Window
// -----------------------------------------------------------------------------

// The page was compiled for a browser tab; in its own window it fills it.
const WINDOW_CSS = 'html, body { margin: 0; padding: 0; min-height: 100vh; background: #f0f4f9; }';

function createWindow() {
  const win = new BrowserWindow({
    width: 1200,
    height: 800,
    show: !SMOKE_REPORT,
    autoHideMenuBar: true,
    backgroundColor: '#f0f4f9',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true,
      devTools: !app.isPackaged
    }
  });

  // Links leave the app through the system browser; nothing opens new
  // Electron windows or navigates the app window away from itself.
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/i.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  win.webContents.on('will-navigate', (event, url) => {
    if (url.startsWith('file://')) return;
    event.preventDefault();
    if (/^https?:/i.test(url)) shell.openExternal(url);
  });
  win.webContents.on('dom-ready', () => { win.webContents.insertCSS(WINDOW_CSS).catch(() => {}); });

  if (SMOKE_REPORT) {
    win.webContents.once('did-finish-load', () => { setTimeout(() => runSmoke(win), 400); });
    win.webContents.once('did-fail-load', (_e, code, description) => {
      writeSmokeReport({ ok: false, error: `The page did not load (${code}): ${description}` });
    });
  }

  win.loadFile(INDEX_HTML);
  return win;
}

// -----------------------------------------------------------------------------
// Smoke test (see SMOKE_REPORT above)
// -----------------------------------------------------------------------------

function writeSmokeReport(report) {
  try { fs.writeFileSync(SMOKE_REPORT, JSON.stringify(report, null, 2)); } catch { /* nothing else to do */ }
  app.exit(report.ok ? 0 : 1);
}

async function runSmoke(win) {
  const report = { ok: false };
  try {
    // Runs inside the page and uses only what any Otter program uses.
    report.page = await win.webContents.executeJavaScript(`(async () => {
      const out = {};
      out.nodeInRenderer = (typeof require !== 'undefined') || (typeof process !== 'undefined');
      out.hasNative = !!window.otterNative;
      out.title = document.title;
      out.read = await window.otterReadFile('smoke-input.txt');
      out.write = await window.otterWriteFile('smoke-output.txt', 'written by the Electron shell');
      out.exists = await window.otterFileExists('smoke-output.txt');
      out.missing = await window.otterFileExists('never-there.txt');
      const cmd = await window.otterRunCommand('echo hello-from-shell');
      out.command = { exitCode: cmd.props['exit code'], output: cmd.props.output };
      out.env = await window.otterGetEnv('OTTER_SMOKE_VALUE');
      out.paths = await window.otterGetSystemPaths();
      out.files = (await window.otterGetFiles('.')).map(f => f.props.name).sort();
      let readError = '';
      try { await window.otterReadFile('never-there.txt'); } catch (err) { readError = String(err.message || err); }
      out.readError = readError;
      return out;
    })()`, true);
    report.ok = true;
  } catch (err) {
    report.error = String((err && err.stack) || err);
  }
  writeSmokeReport(report);
}

// -----------------------------------------------------------------------------
// Lifecycle
// -----------------------------------------------------------------------------

if (SMOKE_REPORT) app.disableHardwareAcceleration();

app.whenReady().then(() => {
  registerBridge();
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin' || SMOKE_REPORT) app.quit();
});
