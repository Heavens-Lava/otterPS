import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DOCS_ROOT = resolve(__dirname, '..');
const REPO_ROOT = resolve(DOCS_ROOT, '..');

function findBrowserBinary() {
  if (process.env.CHROME_BIN && existsSync(process.env.CHROME_BIN)) {
    return process.env.CHROME_BIN;
  }
  const candidates = [
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/microsoft-edge',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'
  ];
  for (const p of candidates) {
    if (existsSync(p)) return p;
  }
  for (const name of ['google-chrome', 'chromium', 'chromium-browser', 'microsoft-edge', 'msedge']) {
    const whichCmd = process.platform === 'win32' ? 'where' : 'which';
    const r = spawnSync(whichCmd, [name], { encoding: 'utf8' });
    if (r.status === 0 && r.stdout.trim()) return r.stdout.trim().split(/\r?\n/)[0];
  }
  return null;
}

class CdpClient {
  constructor(ws) {
    this.ws = ws;
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Map();
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(typeof ev.data === 'string' ? ev.data : ev.data.toString('utf8'));
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve: res, reject: rej } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        if (msg.error) rej(new Error(`CDP ${msg.error.code}: ${msg.error.message}`));
        else res(msg.result);
      } else if (msg.method) {
        const handlers = this.listeners.get(msg.method) || [];
        for (const h of handlers) h(msg.params, msg.sessionId);
      }
    });
  }
  on(event, fn) {
    if (!this.listeners.has(event)) this.listeners.set(event, []);
    this.listeners.get(event).push(fn);
  }
  send(method, params = {}, sessionId = undefined) {
    const id = this.nextId++;
    const payload = sessionId ? { id, method, params, sessionId } : { id, method, params };
    return new Promise((res, rej) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        rej(new Error(`CDP timeout waiting for ${method}`));
      }, 15000);
      this.pending.set(id, {
        resolve: (val) => { clearTimeout(timer); res(val); },
        reject: (err) => { clearTimeout(timer); rej(err); }
      });
      this.ws.send(JSON.stringify(payload));
    });
  }
  async eval(expression, { sessionId, awaitPromise = true } = {}) {
    const res = await this.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise }, sessionId);
    if (res.exceptionDetails) {
      throw new Error(`Browser eval error: ${res.exceptionDetails.text} ${res.exceptionDetails.exception?.description || ''}`);
    }
    return res.result?.value;
  }
  close() { try { this.ws.close(); } catch { /* ignore */ } }
}

async function startDocsServer(port) {
  const proc = spawn(process.execPath, [join(DOCS_ROOT, 'scripts', 'serve-otter-pages.mjs')], {
    env: { ...process.env, PORT: String(port) },
    stdio: ['ignore', 'pipe', 'pipe']
  });
  await new Promise((res, rej) => {
    const t = setTimeout(() => rej(new Error('Docs server start timeout')), 5000);
    proc.stdout.on('data', (d) => {
      if (d.toString('utf8').includes(`http://localhost:${port}`)) { clearTimeout(t); res(); }
    });
    proc.on('exit', (code) => { clearTimeout(t); rej(new Error(`Docs server exited (${code})`)); });
  });
  return proc;
}

function startExampleServer(htmlPath) {
  const html = readFileSync(htmlPath, 'utf8');
  return new Promise((res) => {
    const srv = http.createServer((_req, resp) => {
      resp.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      resp.end(html);
    });
    srv.listen(0, '127.0.0.1', () => res({ server: srv, port: srv.address().port }));
  });
}

async function launchBrowser(browserBin) {
  const userDataDir = mkdtempSync(join(tmpdir(), 'otter-ui-cdp-'));
  const proc = spawn(browserBin, [
    '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--remote-debugging-port=0', `--user-data-dir=${userDataDir}`, '--window-size=1440,900', 'about:blank'
  ], { stdio: ['ignore', 'pipe', 'pipe'] });

  const wsUrl = await new Promise((res, rej) => {
    const timer = setTimeout(() => rej(new Error('Browser DevTools startup timeout')), 15000);
    let buf = '';
    const onData = (chunk) => {
      buf += chunk.toString('utf8');
      const m = buf.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (m) { clearTimeout(timer); res(m[1]); }
    };
    proc.stderr.on('data', onData);
    proc.stdout.on('data', onData);
    proc.on('exit', (code) => { clearTimeout(timer); rej(new Error(`Browser exited (${code})`)); });
  });

  const ws = new WebSocket(wsUrl);
  await new Promise((res, rej) => { ws.addEventListener('open', res); ws.addEventListener('error', rej); });
  return { proc, client: new CdpClient(ws), userDataDir };
}

async function openTab(client, url, width = 1440, height = 900) {
  const { targetId } = await client.send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await client.send('Target.attachToTarget', { targetId, flatten: true });
  await client.send('Page.enable', {}, sessionId);
  await client.send('Runtime.enable', {}, sessionId);
  await client.send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: width < 600 }, sessionId);

  const errors = [];
  client.on('Runtime.exceptionThrown', (params, sid) => {
    if (sid === sessionId) errors.push(params.exceptionDetails?.text || 'uncaught exception');
  });
  client.on('Runtime.consoleAPICalled', (params, sid) => {
    if (sid === sessionId && params.type === 'error') {
      errors.push((params.args || []).map((a) => a.value ?? a.description).join(' '));
    }
  });

  const loaded = new Promise((res) => {
    client.on('Page.loadEventFired', (_p, sid) => { if (sid === sessionId) res(); });
  });
  await client.send('Page.navigate', { url }, sessionId);
  await loaded;
  await new Promise((r) => setTimeout(r, 250));
  return { targetId, sessionId, errors };
}

test('River Slate UI Showcase (/ui-showcase/) & standalone examples/showcase.html E2E', async () => {
  const browserBin = findBrowserBinary();
  assert.ok(browserBin, 'Chromium/Edge binary is required for UI Showcase E2E verification.');

  const docsPort = 4391;
  const docsServer = await startDocsServer(docsPort);
  const exampleHtmlPath = join(REPO_ROOT, 'examples', 'showcase.html');
  assert.ok(existsSync(exampleHtmlPath), 'Expected compiled examples/showcase.html to exist.');
  const { server: exServer, port: exPort } = await startExampleServer(exampleHtmlPath);
  const { proc: browserProc, client, userDataDir } = await launchBrowser(browserBin);

  try {
    // 1. Verify /ui-showcase/ on otterprogramming.com
    const page1 = await openTab(client, `http://localhost:${docsPort}/ui-showcase/`, 1440, 900);
    const uiCheck = await client.eval(`(() => {
      document.getElementById('s1Primary').click();
      const s1After = document.getElementById('s1Status').textContent;
      const s1Count = document.getElementById('s1CountBadge').textContent;

      const nameBox = document.getElementById('s2NameBox');
      nameBox.value = 'RiverPulse';
      document.getElementById('s2Submit').click();
      const s2After = document.getElementById('s2Out').textContent;

      const errInvalid = document.getElementById('s2ErrBox').getAttribute('aria-invalid');

      const slider = document.getElementById('s4Slider');
      slider.value = '88';
      slider.dispatchEvent(new Event('input', { bubbles: true }));
      const sliderOut = document.querySelector('output[data-otter-slider-for="s4Slider"]').textContent;
      const progVal = document.getElementById('s4Progress').value;

      const lightCard = document.getElementById('s5LightCard');
      const lightBg = getComputedStyle(lightCard).backgroundColor;
      const lightColor = getComputedStyle(lightCard).color;
      const darkBg = getComputedStyle(document.getElementById('app')).backgroundColor;

      return { s1After, s1Count, s2After, errInvalid, sliderOut, progVal, lightBg, lightColor, darkBg };
    })()`, { sessionId: page1.sessionId });

    assert.equal(uiCheck.s1After, 'Last clicked: Primary');
    assert.equal(uiCheck.s1Count, '1');
    assert.equal(uiCheck.s2After, 'Output: Hello, RiverPulse');
    assert.equal(uiCheck.errInvalid, 'true');
    assert.equal(uiCheck.sliderOut, '88');
    assert.equal(uiCheck.progVal, 88);
    assert.equal(uiCheck.darkBg, 'rgb(11, 18, 32)');
    assert.equal(uiCheck.lightBg, 'rgb(255, 255, 255)');
    assert.equal(uiCheck.lightColor, 'rgb(11, 29, 54)');
    assert.deepEqual(page1.errors, [], `Unexpected console/page errors on /ui-showcase/: ${page1.errors.join('; ')}`);

    // Check zero horizontal overflow at 1440px, 768px, 390px on /ui-showcase/
    for (const width of [1440, 768, 390]) {
      await client.send('Emulation.setDeviceMetricsOverride', { width, height: 900, deviceScaleFactor: 1, mobile: width < 600 }, page1.sessionId);
      await new Promise((r) => setTimeout(r, 150));
      const metrics = await client.eval(`({ scrollW: document.documentElement.scrollWidth, innerW: window.innerWidth })`, { sessionId: page1.sessionId });
      assert.ok(metrics.scrollW <= metrics.innerW + 1, `/ui-showcase/ overflow at ${width}px: scrollWidth=${metrics.scrollW}, innerWidth=${metrics.innerW}`);
    }

    // 2. Verify standalone examples/showcase.html
    const page2 = await openTab(client, `http://127.0.0.1:${exPort}/`, 1440, 900);
    const exCheck = await client.eval(`(() => {
      document.getElementById('deployBtn').click();
      const status = document.getElementById('actionStatus').textContent;
      const count = document.getElementById('deployCountBadge').textContent;

      const slider = document.getElementById('thresholdSlider');
      slider.value = '84';
      slider.dispatchEvent(new Event('input', { bubbles: true }));
      const out = document.querySelector('output[data-otter-slider-for="thresholdSlider"]').textContent;
      const prog = document.getElementById('capacityProgress').value;

      const lightBg = getComputedStyle(document.getElementById('lightCard')).backgroundColor;
      const bodyBg = getComputedStyle(document.body).backgroundColor;
      return { status, count, out, prog, lightBg, bodyBg };
    })()`, { sessionId: page2.sessionId });

    assert.equal(exCheck.status, 'Deploy triggered');
    assert.equal(exCheck.count, '1');
    assert.equal(exCheck.out, '84');
    assert.equal(exCheck.prog, 84);
    assert.equal(exCheck.bodyBg, 'rgb(11, 18, 32)');
    assert.equal(exCheck.lightBg, 'rgb(255, 255, 255)');
    assert.deepEqual(page2.errors, [], `Unexpected console/page errors on examples/showcase.html: ${page2.errors.join('; ')}`);

    for (const width of [1440, 768, 390]) {
      await client.send('Emulation.setDeviceMetricsOverride', { width, height: 900, deviceScaleFactor: 1, mobile: width < 600 }, page2.sessionId);
      await new Promise((r) => setTimeout(r, 150));
      const metrics = await client.eval(`({ scrollW: document.documentElement.scrollWidth, innerW: window.innerWidth })`, { sessionId: page2.sessionId });
      assert.ok(metrics.scrollW <= metrics.innerW + 1, `examples/showcase.html overflow at ${width}px: scrollWidth=${metrics.scrollW}, innerWidth=${metrics.innerW}`);
    }
  } finally {
    client.close();
    browserProc.kill();
    docsServer.kill();
    exServer.close();
    await new Promise((r) => setTimeout(r, 150));
    try { rmSync(userDataDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 }); } catch { /* ignore */ }
  }
});
