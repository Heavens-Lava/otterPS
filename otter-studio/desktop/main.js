// Otter Studio desktop app - a native window around the Studio workbench.
//
// Studio itself is still served from an Otter checkout (it needs otter.ps1
// and the Otter sources to run, check and package programs). This shell:
//   1. starts that checkout's Studio server (otter-studio/serve.mjs) on a
//      free local port,
//   2. shows it in a frameless window whose title-bar buttons are Studio's own,
//   3. stops the server when the window closes.
// Because the UI is loaded from the checkout, updating the checkout updates
// the app - no reinstall.

'use strict';

const { app, BrowserWindow, ipcMain, shell, dialog } = require('electron');
const path = require('node:path');
const fs = require('node:fs');
const net = require('node:net');
const http = require('node:http');
const { spawn, execFileSync } = require('node:child_process');

const PORT_RANGE = [4280, 4299];

// The checkout to serve: OTTER_STUDIO_ROOT, else the one recorded at build time.
function studioRoot() {
  if (process.env.OTTER_STUDIO_ROOT) return path.resolve(process.env.OTTER_STUDIO_ROOT);
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, 'package.json'), 'utf8'));
    if (pkg.otterStudio && pkg.otterStudio.root) return pkg.otterStudio.root;
  } catch { /* fall through */ }
  return path.resolve(__dirname, '..', '..');
}

function portIsFree(port) {
  return new Promise((resolve) => {
    const probe = net.createServer();
    probe.once('error', () => resolve(false));
    probe.once('listening', () => probe.close(() => resolve(true)));
    probe.listen(port, '127.0.0.1');
  });
}

async function findPort() {
  for (let port = PORT_RANGE[0]; port <= PORT_RANGE[1]; port++) {
    if (await portIsFree(port)) return port;
  }
  throw new Error(`No free port between ${PORT_RANGE[0]} and ${PORT_RANGE[1]}.`);
}

// Prefer the system Node.js (what Studio is developed with); fall back to
// running Electron itself as Node.
function nodeCommand() {
  try {
    const found = execFileSync(process.platform === 'win32' ? 'where.exe' : 'which', ['node'], { encoding: 'utf8', windowsHide: true })
      .split(/\r?\n/).map(s => s.trim()).find(Boolean);
    if (found) return { file: found, env: {} };
  } catch { /* not on PATH */ }
  return { file: process.execPath, env: { ELECTRON_RUN_AS_NODE: '1' } };
}

function waitForServer(port, timeoutMs = 20000) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const attempt = () => {
      const req = http.get({ host: '127.0.0.1', port, path: '/', timeout: 1000 }, (res) => {
        res.resume();
        resolve();
      });
      req.on('error', retry);
      req.on('timeout', () => { req.destroy(); retry(); });
    };
    const retry = () => {
      if (Date.now() - started > timeoutMs) reject(new Error('The Studio server did not start in time.'));
      else setTimeout(attempt, 150);
    };
    attempt();
  });
}

let server = null;
let serverLog = '';

function startServer(root, port) {
  const serveScript = path.join(root, 'otter-studio', 'serve.mjs');
  if (!fs.existsSync(serveScript)) throw new Error(`Otter Studio was not found in:\n${root}`);
  const node = nodeCommand();
  const env = { ...process.env, ...node.env, OTTER_STUDIO_PORT: String(port) };
  if (!node.env.ELECTRON_RUN_AS_NODE) delete env.ELECTRON_RUN_AS_NODE;
  // Build -> Desktop App works offline when a toolchain is already on disk.
  if (!env.OTTER_ELECTRON_TOOLCHAIN) {
    const knownToolchain = path.join(path.dirname(root), 'formwright');
    if (fs.existsSync(path.join(knownToolchain, 'node_modules', 'electron-builder'))) env.OTTER_ELECTRON_TOOLCHAIN = knownToolchain;
  }
  server = spawn(node.file, [serveScript], { cwd: path.dirname(serveScript), env, windowsHide: true });
  server.stdout.on('data', (d) => { serverLog = (serverLog + d).slice(-8000); });
  server.stderr.on('data', (d) => { serverLog = (serverLog + d).slice(-8000); });
}

function stopServer() {
  if (!server || server.exitCode !== null) return;
  if (process.platform === 'win32') {
    try { execFileSync('taskkill', ['/pid', String(server.pid), '/t', '/f'], { windowsHide: true, stdio: 'ignore' }); } catch { /* already gone */ }
  } else {
    server.kill();
  }
}

// --- Window state -------------------------------------------------------------

const stateFile = () => path.join(app.getPath('userData'), 'window-state.json');

function loadWindowState() {
  try { return JSON.parse(fs.readFileSync(stateFile(), 'utf8')); } catch { return { width: 1480, height: 920, maximized: false }; }
}

function saveWindowState(win) {
  try {
    const bounds = win.getNormalBounds();
    fs.writeFileSync(stateFile(), JSON.stringify({ ...bounds, maximized: win.isMaximized() }));
  } catch { /* not important */ }
}

let mainWindow = null;

async function createWindow() {
  const state = loadWindowState();
  mainWindow = new BrowserWindow({
    x: state.x, y: state.y, width: state.width || 1480, height: state.height || 920,
    minWidth: 1024, minHeight: 640,
    frame: false,
    show: false,
    backgroundColor: '#05101a',
    title: 'Otter Studio',
    icon: path.join(__dirname, 'build', 'icon.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });
  if (state.maximized) mainWindow.maximize();

  mainWindow.on('close', () => saveWindowState(mainWindow));
  const sendState = () => mainWindow.webContents.send('otter-studio:window-state', { maximized: mainWindow.isMaximized() });
  mainWindow.on('maximize', sendState);
  mainWindow.on('unmaximize', sendState);

  // Links to the web open in the default browser; nothing navigates the app away.
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/i.test(url) && !url.startsWith(`http://127.0.0.1:${currentPort}`)) shell.openExternal(url);
    return { action: 'deny' };
  });
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (!url.startsWith(`http://127.0.0.1:${currentPort}`)) {
      event.preventDefault();
      if (/^https?:/i.test(url)) shell.openExternal(url);
    }
  });

  mainWindow.once('ready-to-show', () => mainWindow.show());
  await mainWindow.loadURL(`http://127.0.0.1:${currentPort}/`);
}

ipcMain.handle('otter-studio:window', (event, action) => {
  const win = BrowserWindow.fromWebContents(event.sender);
  if (!win) return null;
  if (action === 'minimize') win.minimize();
  else if (action === 'maximize') (win.isMaximized() ? win.unmaximize() : win.maximize());
  else if (action === 'close') win.close();
  return { maximized: win.isMaximized() };
});

// --- Lifecycle ----------------------------------------------------------------

let currentPort = null;

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (!mainWindow) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
  });

  app.setAppUserModelId('org.otterlang.studio');

  app.whenReady().then(async () => {
    const root = studioRoot();
    try {
      currentPort = await findPort();
      startServer(root, currentPort);
      await waitForServer(currentPort);
      await createWindow();
    } catch (err) {
      dialog.showErrorBox('Otter Studio could not start', `${err.message}\n\n${serverLog.slice(-1500)}`);
      stopServer();
      app.exit(1);
    }
  });

  app.on('window-all-closed', () => app.quit());
  app.on('before-quit', stopServer);
  process.on('exit', stopServer);
}
