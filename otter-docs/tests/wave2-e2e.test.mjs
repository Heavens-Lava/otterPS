/**
 * wave2-e2e.test.mjs
 *
 * Browser-driven E2E tests for Otter Wave 2:
 * - W2.1 Interactive Otter Playground (real .NET 10 WASM Web Worker execution, examples, ask stdin, diagnostics, loop guard, Reset)
 * - W2.2 Otter Pulse Guided Tutorial (screenshot, Schema v2 Pack links, SSRF threat model, Playground deep link)
 * - W2.3 Legacy VS Code extension deprecation notice (non-destructive)
 * - W2.4 Developer onboarding (/download/ interactive OS tabs, /docs/ link fix, /home/ & /first-program/ Playground CTAs, sitemap)
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const docsRoot = path.resolve(__dirname, '..');
const repoRoot = path.resolve(docsRoot, '..');
const generatedRoot = path.join(docsRoot, 'generated');
const PORT = 4196;
const BASE = `http://127.0.0.1:${PORT}`;

function findBrowser() {
  if (process.env.CHROME_BIN && fs.existsSync(process.env.CHROME_BIN)) return process.env.CHROME_BIN;
  if (process.env.CHROME_PATH && fs.existsSync(process.env.CHROME_PATH)) return process.env.CHROME_PATH;
  const candidates = [
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/usr/bin/google-chrome'
  ];
  for (const c of candidates) if (fs.existsSync(c)) return c;
  for (const name of ['google-chrome', 'chromium', 'chromium-browser', 'microsoft-edge']) {
    try {
      const p = execFileSync('which', [name], { encoding: 'utf8' }).trim();
      if (p) return p;
    } catch {}
  }
  throw new Error('No Chromium/Chrome/Edge browser binary found.');
}

async function startServer() {
  const proc = spawn(process.execPath, [path.join(docsRoot, 'scripts/serve-otter-pages.mjs')], {
    cwd: docsRoot,
    env: { ...process.env, PORT: String(PORT) },
    stdio: ['ignore', 'pipe', 'pipe']
  });
  await new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('serve-otter-pages failed to start')), 8000);
    proc.stdout.on('data', (d) => {
      if (d.toString().includes(String(PORT))) {
        clearTimeout(t);
        resolve();
      }
    });
    proc.once('exit', (code) => {
      clearTimeout(t);
      reject(new Error(`Server exited early (${code})`));
    });
  });
  return proc;
}

async function createBrowser() {
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-wave2-e2e-'));
  const proc = spawn(
    findBrowser(),
    [
      '--headless=new',
      '--disable-gpu',
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--window-size=1360,960',
      '--remote-debugging-port=0',
      `--user-data-dir=${userDataDir}`,
      'about:blank'
    ],
    { stdio: ['ignore', 'pipe', 'pipe'] }
  );

  const wsUrl = await new Promise((resolve, reject) => {
    let stderr = '';
    const t = setTimeout(() => reject(new Error(`Browser startup timeout:\n${stderr}`)), 15000);
    proc.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
      const m = stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (m) { clearTimeout(t); resolve(m[1]); }
    });
  });

  const ws = new WebSocket(wsUrl);
  await new Promise((res, rej) => {
    ws.addEventListener('open', res, { once: true });
    ws.addEventListener('error', rej, { once: true });
  });

  let nextId = 1;
  const inflight = new Map();
  const consoleErrors = [];
  ws.addEventListener('message', (ev) => {
    const msg = JSON.parse(ev.data.toString());
    if (msg.id && inflight.has(msg.id)) {
      const { resolve, reject } = inflight.get(msg.id);
      inflight.delete(msg.id);
      if (msg.error) reject(new Error(msg.error.message));
      else resolve(msg.result);
    } else if (msg.method === 'Runtime.exceptionThrown') {
      consoleErrors.push(msg.params?.exceptionDetails?.text || 'Runtime exception');
    } else if (msg.method === 'Runtime.consoleAPICalled' && msg.params?.type === 'error') {
      consoleErrors.push((msg.params.args || []).map((a) => a.value || a.description).join(' '));
    }
  });

  const send = (method, params = {}, sessionId = undefined) =>
    new Promise((resolve, reject) => {
      const id = nextId++;
      inflight.set(id, { resolve, reject });
      ws.send(JSON.stringify(sessionId ? { id, method, params, sessionId } : { id, method, params }));
    });

  const targets = await send('Target.getTargets');
  const pageTarget = targets.targetInfos.find((t) => t.type === 'page');
  const { sessionId } = await send('Target.attachToTarget', { targetId: pageTarget.targetId, flatten: true });
  await send('Runtime.enable', {}, sessionId);
  await send('Page.enable', {}, sessionId);

  const evalJs = async (expression) => {
    const res = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }, sessionId);
    if (res.exceptionDetails) {
      throw new Error(res.exceptionDetails.exception?.description || res.exceptionDetails.text || 'Eval error');
    }
    return res.result?.value;
  };

  const goto = async (url) => {
    consoleErrors.length = 0;
    await send('Page.navigate', { url }, sessionId);
    await new Promise((r) => setTimeout(r, 450));
  };

  const waitFor = async (predicateExpr, timeoutMs = 20000) => {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      const val = await evalJs(predicateExpr);
      if (val) return val;
      await new Promise((r) => setTimeout(r, 150));
    }
    throw new Error(`Timed out waiting for: ${predicateExpr}`);
  };

  const screenshot = async (destPath, fullPage = false) => {
    const { data } = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: fullPage }, sessionId);
    fs.writeFileSync(destPath, Buffer.from(data, 'base64'));
  };

  const setViewport = async (width, height, mobile = false) => {
    await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile }, sessionId);
  };

  const close = async () => {
    try { ws.close(); } catch {}
    proc.kill('SIGTERM');
    await new Promise((r) => setTimeout(r, 250));
    fs.rmSync(userDataDir, { recursive: true, force: true });
  };

  return { evalJs, goto, waitFor, screenshot, setViewport, consoleErrors, close };
}

test('Wave 2 E2E: Playground WASM, Otter Pulse Tutorial, Legacy VS Code Deprecation, and Onboarding', async (t) => {
  const server = await startServer();
  const browser = await createBrowser();

  try {
    await t.test('W2.1 Interactive Playground executes real Otter 1.0.1 in WebAssembly Worker', async () => {
      await browser.goto(`${BASE}/playground/`);
      await browser.waitFor('document.querySelector(".pg-app")?.dataset.pgReady === "true"', 25000);

      // 1. Run default Hello Otter example
      await browser.evalJs('document.getElementById("pgRunBtn").click()');
      const helloOut = await browser.waitFor('(() => { const t = document.getElementById("pgConsole").textContent; return t.includes("Welcome to Otter, Developer") ? t : ""; })()');
      assert.ok(helloOut.includes('Hello, Otter'));
      assert.ok(helloOut.includes('Welcome to Otter, Ada'));
      assert.ok(helloOut.includes('Welcome to Otter, Developer'));

      // 2. Switch to Otter Pulse Health Score Logic example and run
      await browser.evalJs('(() => { const s = document.getElementById("pgExampleSelect"); s.value = "otter-pulse"; s.dispatchEvent(new Event("change")); })()');
      await browser.evalJs('document.getElementById("pgRunBtn").click()');
      const pulseOut = await browser.waitFor('(() => { const t = document.getElementById("pgConsole").textContent; return t.includes("Live Orders API") ? t : ""; })()');
      assert.ok(pulseOut.includes('95.8 / 100'));
      assert.ok(pulseOut.includes('Down Service (503): 0 / 100'));

      // 3. Switch to Interactive Input (ask) example and verify stdin execution
      await browser.evalJs('(() => { const s = document.getElementById("pgExampleSelect"); s.value = "ask-input"; s.dispatchEvent(new Event("change")); })()');
      await browser.evalJs('document.getElementById("pgRunBtn").click()');
      const askOut = await browser.waitFor('(() => { const t = document.getElementById("pgConsole").textContent; return t.includes("3 Hello, Ada") ? t : ""; })()');
      assert.ok(askOut.includes('1 Hello, Ada'));

      // 4. Edit code to trigger real Otter runtime diagnostic
      await browser.evalJs('(() => { const e = document.getElementById("pgEditor"); e.value = "say unknownSymbol\\n"; e.dispatchEvent(new Event("input")); })()');
      await browser.evalJs('document.getElementById("pgRunBtn").click()');
      const diagText = await browser.waitFor('(() => { const d = document.getElementById("pgDiagnostics").textContent; return d.includes("unknownSymbol") ? d : ""; })()');
      assert.ok(diagText.includes('unknownSymbol'));

      // 5. Switch to Sandbox Safety Demo (while true) and verify step/timeout guard aborts cleanly
      await browser.evalJs('(() => { const s = document.getElementById("pgExampleSelect"); s.value = "sandbox-limit"; s.dispatchEvent(new Event("change")); })()');
      await browser.evalJs('document.getElementById("pgRunBtn").click()');
      const limitText = await browser.waitFor('(() => { const d = document.getElementById("pgDiagnostics").textContent; return (d.includes("OTTER_PLAYGROUND_STEP_LIMIT") || d.includes("OTTER_PLAYGROUND_TIMEOUT")) ? d : ""; })()');
      assert.ok(limitText.includes('OTTER_PLAYGROUND_STEP_LIMIT') || limitText.includes('OTTER_PLAYGROUND_TIMEOUT'));

      // 6. Reset clears diagnostics cleanly
      await browser.evalJs('document.getElementById("pgResetBtn").click()');
      const resetDiag = await browser.evalJs('document.getElementById("pgDiagnostics").textContent');
      assert.ok(resetDiag.includes('No syntax or runtime issues'));
      assert.deepEqual(browser.consoleErrors, [], `Playground console errors: ${browser.consoleErrors.join('; ')}`);
    });

    await t.test('W2.2 Otter Pulse Tutorial loads screenshot, Pack links, and SSRF threat model', async () => {
      await browser.goto(`${BASE}/otter-pulse/`);
      const info = await browser.evalJs(`(() => {
        const img = document.querySelector('img[src*="otter-pulse-dashboard.png"]');
        const links = [...document.querySelectorAll('a')].map(a => a.getAttribute('href'));
        const text = document.body.innerText;
        return {
          imgOk: Boolean(img && img.complete && img.naturalWidth > 200),
          links,
          hasThreatModel: text.includes('validateProbeUrl') && text.includes('127.0.0.1:18092')
        };
      })()`);
      assert.equal(info.imgOk, true, 'otter-pulse-dashboard.png must load cleanly');
      assert.equal(info.hasThreatModel, true, 'Tutorial must document loopback SSRF threat model');
      for (const expectedLink of [
        '/playground/#example=otter-pulse',
        '/library/pack-otter-official-file-helpers/',
        '/library/pack-otter-official-text-utils/',
        '/library/pack-otter-official-math-utils/'
      ]) {
        assert.ok(info.links.includes(expectedLink), `Missing expected link on /otter-pulse/: ${expectedLink}`);
      }
      for (const packRoute of [
        '/library/pack-otter-official-file-helpers/',
        '/library/pack-otter-official-text-utils/',
        '/library/pack-otter-official-math-utils/'
      ]) {
        const res = await fetch(`${BASE}${packRoute}`);
        assert.equal(res.status, 200, `Linked pack page failed: ${packRoute}`);
      }
      assert.deepEqual(browser.consoleErrors, []);
    });

    await t.test('W2.4 Onboarding: /download/ OS tabs switch interactively & links are fixed', async () => {
      await browser.goto(`${BASE}/download/`);
      const nextThreeHref = await browser.evalJs('document.getElementById("nextThree")?.getAttribute("href")');
      assert.equal(nextThreeHref, '/docs/', 'nextThree must point to /docs/, not /');

      // Click macOS tab
      await browser.evalJs('document.getElementById("tabMac").click()');
      const macCmd = await browser.evalJs('document.getElementById("runCommand").textContent');
      const macLabel = await browser.evalJs('document.getElementById("runCommandlabel").textContent');
      assert.ok(macCmd.includes('./otter examples/hello.ot'), `macOS tab should show ./otter command, got: ${macCmd}`);
      assert.ok(macLabel.includes('macOS'));

      // Click Linux tab
      await browser.evalJs('document.getElementById("tabLinux").click()');
      const linuxLabel = await browser.evalJs('document.getElementById("runCommandlabel").textContent');
      assert.ok(linuxLabel.includes('Linux'));

      // Click Windows tab
      await browser.evalJs('document.getElementById("tabWindows").click()');
      const winCmd = await browser.evalJs('document.getElementById("runCommand").textContent');
      assert.ok(winCmd.includes('.\\otter.cmd'));
      assert.deepEqual(browser.consoleErrors, []);

      // Check Home & First Program Playground CTAs
      await browser.goto(`${BASE}/`);
      const homePgHref = await browser.evalJs('document.getElementById("heroPlayground")?.getAttribute("href")');
      assert.equal(homePgHref, '/playground/');

      await browser.goto(`${BASE}/first-program/`);
      const fpPgHref = await browser.evalJs('document.getElementById("b2pg")?.getAttribute("href")');
      assert.equal(fpPgHref, '/playground/#example=hello');

      // Mobile 390x844 viewport smoke check on /playground/
      await browser.setViewport(390, 844, true);
      await browser.goto(`${BASE}/playground/`);
      await browser.waitFor('document.querySelector(".pg-app")?.dataset.pgReady === "true"', 20000);
      assert.deepEqual(browser.consoleErrors, []);
    });

    await t.test('W2.3 & SEO: Legacy VS Code deprecation intact and sitemap includes new routes', async () => {
      const legacyReadme = fs.readFileSync(path.join(repoRoot, 'tools/vscode-otter/README.md'), 'utf8');
      assert.ok(legacyReadme.includes('Deprecation Notice') && legacyReadme.includes('Heavens-Lava/otter-net/editors/vscode'));
      assert.ok(fs.existsSync(path.join(repoRoot, 'tools/vscode-otter/package.json')), 'Legacy extension files must not be deleted');

      const sitemap = fs.readFileSync(path.join(generatedRoot, 'sitemap.xml'), 'utf8');
      assert.ok(sitemap.includes('/playground/'), 'sitemap.xml must include /playground/');
      assert.ok(sitemap.includes('/otter-pulse/'), 'sitemap.xml must include /otter-pulse/');
    });
  } finally {
    await browser.close();
    server.kill('SIGTERM');
  }
});
