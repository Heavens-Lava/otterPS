import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DOCS_ROOT = resolve(__dirname, '..');

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

  async eval(expression, { sessionId, contextId, awaitPromise = true } = {}) {
    const params = { expression, returnByValue: true, awaitPromise };
    if (contextId !== undefined) params.contextId = contextId;
    const res = await this.send('Runtime.evaluate', params, sessionId);
    if (res.exceptionDetails) {
      throw new Error(`Browser eval error: ${res.exceptionDetails.text} ${res.exceptionDetails.exception?.description || ''}`);
    }
    return res.result?.value;
  }

  close() {
    try { this.ws.close(); } catch { /* ignore */ }
  }
}

async function startServer(port) {
  const proc = spawn(process.execPath, [join(DOCS_ROOT, 'scripts', 'serve-otter-pages.mjs')], {
    env: { ...process.env, PORT: String(port) },
    stdio: ['ignore', 'pipe', 'pipe']
  });
  await new Promise((res, rej) => {
    const t = setTimeout(() => rej(new Error('Static server start timeout')), 5000);
    proc.stdout.on('data', (d) => {
      if (d.toString('utf8').includes(`http://localhost:${port}`)) { clearTimeout(t); res(); }
    });
    proc.on('exit', (code) => { clearTimeout(t); rej(new Error(`Static server exited (${code})`)); });
  });
  return proc;
}

async function launchBrowser(browserBin) {
  const userDataDir = mkdtempSync(join(tmpdir(), 'otter-cdp-profile-'));
  const args = [
    '--headless=new',
    '--disable-gpu',
    '--no-first-run',
    '--no-default-browser-check',
    '--remote-debugging-port=0',
    `--user-data-dir=${userDataDir}`,
    '--window-size=1440,900',
    'about:blank'
  ];
  if (process.platform === 'linux') args.push('--no-sandbox');

  const proc = spawn(browserBin, args, { stdio: ['ignore', 'pipe', 'pipe'] });
  const wsUrl = await new Promise((res, rej) => {
    let stderr = '';
    const t = setTimeout(() => rej(new Error(`Browser CDP did not start in 15s:\n${stderr}`)), 15000);
    proc.stderr.on('data', (chunk) => {
      stderr += chunk.toString('utf8');
      const m = stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (m) { clearTimeout(t); res(m[1]); }
    });
    proc.on('exit', (code) => { clearTimeout(t); rej(new Error(`Browser exited (${code}):\n${stderr}`)); });
  });

  // Connect to browser endpoint, create a clean target page
  const browserWs = new WebSocket(wsUrl);
  await new Promise((res, rej) => {
    browserWs.addEventListener('open', res, { once: true });
    browserWs.addEventListener('error', rej, { once: true });
  });
  const browserCdp = new CdpClient(browserWs);
  const { targetId } = await browserCdp.send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await browserCdp.send('Target.attachToTarget', { targetId, flatten: true });

  await browserCdp.send('Page.enable', {}, sessionId);
  await browserCdp.send('Runtime.enable', {}, sessionId);
  await browserCdp.send('Network.enable', {}, sessionId);
  await browserCdp.send('DOM.enable', {}, sessionId);

  return {
    cdp: browserCdp,
    sessionId,
    async navigate(url) {
      const loadDone = new Promise((res) => {
        const handler = (_, sid) => { if (sid === sessionId) res(); };
        browserCdp.on('Page.loadEventFired', handler);
      });
      await browserCdp.send('Page.navigate', { url }, sessionId);
      await loadDone;
    },
    async waitFor(fnExpr, timeoutMs = 6000) {
      const start = Date.now();
      while (Date.now() - start < timeoutMs) {
        const ok = await browserCdp.eval(`Boolean(${fnExpr})`, { sessionId });
        if (ok) return;
        await new Promise((r) => setTimeout(r, 40));
      }
      throw new Error(`Timed out waiting for: ${fnExpr}`);
    },
    async cleanup() {
      browserCdp.close();
      proc.kill('SIGTERM');
      await new Promise((r) => setTimeout(r, 200));
      rmSync(userDataDir, { recursive: true, force: true });
    }
  };
}

test('browser E2E: search caret/focus, filters, URL sync, keyboard tabs, copy-code, mobile nav, and sandboxed preview', async () => {
  const browserBin = findBrowserBinary();
  assert.ok(browserBin, 'No Chromium/Chrome/Edge binary found for browser E2E tests (set CHROME_BIN).');

  const port = 4500 + Math.floor(Math.random() * 400);
  const baseUrl = `http://localhost:${port}`;
  const server = await startServer(port);
  const browser = await launchBrowser(browserBin);

  const consoleErrors = [];
  const pageExceptions = [];
  const failedRequests = [];

  browser.cdp.on('Runtime.consoleAPICalled', (params, sid) => {
    if (sid === browser.sessionId && params.type === 'error') {
      consoleErrors.push(params.args.map((a) => a.value || a.description).join(' '));
    }
  });
  browser.cdp.on('Runtime.exceptionThrown', (params, sid) => {
    if (sid === browser.sessionId) {
      pageExceptions.push(params.exceptionDetails?.text || 'exception');
    }
  });
  browser.cdp.on('Network.responseReceived', (params, sid) => {
    if (sid === browser.sessionId && params.response.status >= 400 && params.response.url.startsWith(baseUrl)) {
      failedRequests.push(`${params.response.status} ${params.response.url}`);
    }
  });

  try {
    // =========================================================================
    // 1. Gallery load + Search caret & focus preservation
    // =========================================================================
    await browser.navigate(`${baseUrl}/library/`);
    await browser.waitFor('document.querySelectorAll(".lib-card").length === 65');

    const initialCards = await browser.cdp.eval('document.querySelectorAll(".lib-card").length', { sessionId: browser.sessionId });
    assert.equal(initialCards, 65, 'Gallery must render all 65 components initially');

    // Focus search input and store DOM identity to confirm it NEVER unmounts while typing
    await browser.cdp.eval(`(() => {
      const inp = document.querySelector('#libSearchInput');
      window.__origInput = inp;
      inp.focus();
    })()`, { sessionId: browser.sessionId });

    await browser.cdp.send('Input.insertText', { text: 'game' }, browser.sessionId);
    await browser.waitFor('new URLSearchParams(location.search).get("q") === "game"');

    // Move caret to index 0 (start of string) and type 'a' — caret MUST stay at 1 (not jump to end!)
    await browser.cdp.eval(`document.querySelector('#libSearchInput').setSelectionRange(0, 0)`, { sessionId: browser.sessionId });
    await browser.cdp.send('Input.insertText', { text: 'a' }, browser.sessionId);

    const caretCheck = await browser.cdp.eval(`(() => {
      const inp = document.querySelector('#libSearchInput');
      return {
        sameNode: inp === window.__origInput,
        stillFocused: document.activeElement === inp,
        value: inp.value,
        selectionStart: inp.selectionStart,
        selectionEnd: inp.selectionEnd
      };
    })()`, { sessionId: browser.sessionId });

    assert.equal(caretCheck.sameNode, true, 'Search input DOM node must persist across input events');
    assert.equal(caretCheck.stillFocused, true, 'Search input must keep focus while typing');
    assert.equal(caretCheck.value, 'agame', 'Mid-string/start-of-string insertion must work');
    assert.equal(caretCheck.selectionStart, 1, 'Caret must remain at index 1 instead of jumping to end');

    // Search by Otter Schema v2 operation name
    await browser.cdp.eval(`(() => {
      const inp = document.querySelector('#libSearchInput');
      inp.value = 'applyDamage';
      inp.dispatchEvent(new Event('input', { bubbles: true }));
    })()`, { sessionId: browser.sessionId });
    await browser.waitFor('document.querySelectorAll(".lib-card").length >= 1');
    const opSearch = await browser.cdp.eval(`({
      search: location.search,
      hrefs: [...document.querySelectorAll('.lib-card')].map(a => a.getAttribute('href'))
    })`, { sessionId: browser.sessionId });
    assert.equal(opSearch.search, '?q=applyDamage');
    assert.ok(opSearch.hrefs.includes('/library/pack-otter-official-game-entity/'));

    // =========================================================================
    // 2. Category / Language filters + URL sync + Reload restoration + Reset
    // =========================================================================
    await browser.cdp.eval(`document.querySelector('#libResetBtn').click()`, { sessionId: browser.sessionId });
    await browser.waitFor('document.querySelectorAll(".lib-card").length === 65');
    assert.equal(await browser.cdp.eval('location.search', { sessionId: browser.sessionId }), '');

    await browser.cdp.eval(`document.querySelector('.lib-cat-tab[data-cat="games"]').click()`, { sessionId: browser.sessionId });
    await browser.waitFor('document.querySelectorAll(".lib-card").length === 3');
    await browser.cdp.eval(`document.querySelector('.lib-lang-pill[data-lang="Luau"]').click()`, { sessionId: browser.sessionId });
    await browser.waitFor('document.querySelectorAll(".lib-card").length === 1');

    const filteredUrl = await browser.cdp.eval('location.search', { sessionId: browser.sessionId });
    assert.equal(filteredUrl, '?category=games&lang=Luau');

    // Reload the exact filtered URL and verify state is restored from URL params
    await browser.navigate(`${baseUrl}/library/${filteredUrl}`);
    await browser.waitFor('document.querySelectorAll(".lib-card").length === 1');
    const restored = await browser.cdp.eval(`({
      catPressed: document.querySelector('.lib-cat-tab[data-cat="games"]').getAttribute('aria-pressed'),
      langPressed: document.querySelector('.lib-lang-pill[data-lang="Luau"]').getAttribute('aria-pressed'),
      firstCard: document.querySelector('.lib-card').getAttribute('href')
    })`, { sessionId: browser.sessionId });
    assert.equal(restored.catPressed, 'true');
    assert.equal(restored.langPressed, 'true');
    assert.equal(restored.firstCard, '/library/games-roblox-quest-tracker/');

    // =========================================================================
    // 3. Keyboard-accessible multi-file tabs & Copy-code controls
    // =========================================================================
    await browser.navigate(`${baseUrl}/library/desktop-wpf-data-grid/`);
    await browser.waitFor('document.querySelectorAll("[role=tab]").length === 3');

    await browser.cdp.eval(`document.getElementById('tab-0').focus()`, { sessionId: browser.sessionId });
    await browser.cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'ArrowRight', code: 'ArrowRight' }, browser.sessionId);
    const afterRight = await browser.cdp.eval(`({
      activeId: document.activeElement.id,
      tab1Selected: document.getElementById('tab-1').getAttribute('aria-selected'),
      panel0Hidden: document.getElementById('panel-0').classList.contains('is-hidden'),
      panel1Hidden: document.getElementById('panel-1').classList.contains('is-hidden')
    })`, { sessionId: browser.sessionId });
    assert.equal(afterRight.activeId, 'tab-1');
    assert.equal(afterRight.tab1Selected, 'true');
    assert.equal(afterRight.panel0Hidden, true);
    assert.equal(afterRight.panel1Hidden, false);

    await browser.cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'End', code: 'End' }, browser.sessionId);
    assert.equal(await browser.cdp.eval('document.activeElement.id', { sessionId: browser.sessionId }), 'tab-2');

    await browser.cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Home', code: 'Home' }, browser.sessionId);
    assert.equal(await browser.cdp.eval('document.activeElement.id', { sessionId: browser.sessionId }), 'tab-0');

    await browser.cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'ArrowLeft', code: 'ArrowLeft' }, browser.sessionId);
    assert.equal(await browser.cdp.eval('document.activeElement.id', { sessionId: browser.sessionId }), 'tab-2');

    // Code copy verification (intercept navigator.clipboard.writeText to assert exact copied contents)
    await browser.cdp.eval(`(() => {
      window.__copied = [];
      Object.defineProperty(navigator, 'clipboard', {
        configurable: true,
        value: { writeText: async (txt) => { window.__copied.push(txt); } }
      });
    })()`, { sessionId: browser.sessionId });

    await browser.cdp.eval(`document.querySelector('[data-copy-target="raw-code-2"]').click()`, { sessionId: browser.sessionId });
    await browser.waitFor('window.__copied.length === 1');
    await browser.cdp.eval(`document.querySelector('[data-copy-all="true"]').click()`, { sessionId: browser.sessionId });
    await browser.waitFor('window.__copied.length === 2');
    await browser.cdp.eval(`document.querySelector('[data-copy-target="raw-install"]').click()`, { sessionId: browser.sessionId });
    await browser.waitFor('window.__copied.length === 3');

    const copyResults = await browser.cdp.eval(`({
      copied: window.__copied,
      btnText: document.querySelector('[data-copy-target="raw-install"]').textContent,
      liveText: document.querySelector('.lib-copy-live').textContent
    })`, { sessionId: browser.sessionId });
    assert.ok(copyResults.copied[0].includes('class DataGridViewModel'), 'Copy file copied DataGridViewModel.cs');
    assert.ok(copyResults.copied[1].includes('FilterableDataGrid.xaml') && copyResults.copied[1].includes('DataGridViewModel.cs'), 'Copy all copied all 3 files');
    assert.ok(copyResults.copied[2].includes('<UseWPF>true</UseWPF>'), 'Copy command copied install command');
    assert.equal(copyResults.btnText, 'Copied!');
    assert.equal(copyResults.liveText, 'Copied to clipboard.');

    // =========================================================================
    // 4. Responsive mobile navigation & zero horizontal overflow (390x844)
    // =========================================================================
    await browser.cdp.send('Emulation.setDeviceMetricsOverride', {
      width: 390,
      height: 844,
      deviceScaleFactor: 2,
      mobile: true
    }, browser.sessionId);

    await browser.navigate(`${baseUrl}/library/`);
    await browser.waitFor('document.querySelectorAll(".lib-card").length === 65');

    const mobileLayout = await browser.cdp.eval(`({
      scrollWidth: document.documentElement.scrollWidth,
      innerWidth: window.innerWidth,
      menuVisible: getComputedStyle(document.querySelector('.site-menu-toggle')).display !== 'none',
      expandedBefore: document.querySelector('.site-menu-toggle').getAttribute('aria-expanded')
    })`, { sessionId: browser.sessionId });
    assert.ok(
      mobileLayout.scrollWidth <= mobileLayout.innerWidth,
      `Mobile horizontal overflow detected: scrollWidth=${mobileLayout.scrollWidth} > innerWidth=${mobileLayout.innerWidth}`
    );
    assert.equal(mobileLayout.menuVisible, true, 'Mobile menu toggle button must be visible at 390px');
    assert.equal(mobileLayout.expandedBefore, 'false');

    await browser.cdp.eval(`document.querySelector('.site-menu-toggle').click()`, { sessionId: browser.sessionId });
    const mobileMenuOpen = await browser.cdp.eval(`({
      hasClass: document.getElementById('topBar').classList.contains('site-menu-open'),
      expanded: document.querySelector('.site-menu-toggle').getAttribute('aria-expanded')
    })`, { sessionId: browser.sessionId });
    assert.equal(mobileMenuOpen.hasClass, true);
    assert.equal(mobileMenuOpen.expanded, 'true');

    await browser.cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape' }, browser.sessionId);
    assert.equal(await browser.cdp.eval(`document.getElementById('topBar').classList.contains('site-menu-open')`, { sessionId: browser.sessionId }), false);

    // Reset viewport to desktop
    await browser.cdp.send('Emulation.clearDeviceMetricsOverride', {}, browser.sessionId);

    // =========================================================================
    // 5. All 5 live-sandboxed previews + Live customizer + Security Isolation
    // =========================================================================
    const sandboxSlugs = [
      'web-animated-gradient-button',
      'web-responsive-navbar',
      'web-command-palette',
      'effects-glassmorphism-card',
      'effects-hover-tilt-card'
    ];
    for (const slug of sandboxSlugs) {
      await browser.navigate(`${baseUrl}/library/${slug}/`);
      await browser.waitFor('Boolean(document.querySelector("iframe.lib-sandbox-frame"))');
      const attrs = await browser.cdp.eval(`(() => {
        const f = document.querySelector('iframe.lib-sandbox-frame');
        return {
          sandbox: f.getAttribute('sandbox'),
          referrer: f.getAttribute('referrerpolicy'),
          channel: f.dataset.previewChannel,
          hasCsp: (f.getAttribute('srcdoc') || '').includes('Content-Security-Policy')
        };
      })()`, { sessionId: browser.sessionId });
      assert.equal(attrs.sandbox, 'allow-scripts', `${slug} iframe must only have sandbox="allow-scripts"`);
      assert.equal(attrs.referrer, 'no-referrer');
      assert.ok(attrs.channel && attrs.channel.includes(slug));
      assert.equal(attrs.hasCsp, true, `${slug} iframe srcdoc must include CSP meta tag`);
    }

    // Deep live customization & opaque-origin security check on web-animated-gradient-button
    await browser.navigate(`${baseUrl}/library/web-animated-gradient-button/`);
    await browser.waitFor('Boolean(document.querySelector("iframe.lib-sandbox-frame"))');
    // Force eager load (since loading="lazy" might wait if below fold, scroll into view)
    await browser.cdp.eval(`document.querySelector('iframe.lib-sandbox-frame').scrollIntoView()`, { sessionId: browser.sessionId });
    await new Promise((r) => setTimeout(r, 350));

    // Change Border Radius slider to 24 and trigger input event
    await browser.cdp.eval(`(() => {
      const slider = document.querySelector('[data-css-var="--btn-radius"]');
      slider.value = '24';
      slider.dispatchEvent(new Event('input', { bubbles: true }));
    })()`, { sessionId: browser.sessionId });

    const outVal = await browser.cdp.eval(`document.querySelector('output[data-var-out="--btn-radius"]').textContent`, { sessionId: browser.sessionId });
    assert.equal(outVal, '24px', 'Customizer output label must update to 24px');

    // Also try sending an UNSAFE CSS injection via postMessage (must be rejected by iframe value whitelist!)
    await browser.cdp.eval(`(() => {
      const f = document.querySelector('iframe.lib-sandbox-frame');
      f.contentWindow.postMessage({
        type: 'otter-lib-vars',
        channel: f.dataset.previewChannel,
        vars: { '--btn-c1': 'url(https://evil.example/exfil.png)' }
      }, '*');
      // Also send wrong channel (must be ignored!)
      f.contentWindow.postMessage({
        type: 'otter-lib-vars',
        channel: 'wrong-channel',
        vars: { '--btn-radius': '99px' }
      }, '*');
    })()`, { sessionId: browser.sessionId });
    await new Promise((r) => setTimeout(r, 150));

    // Inspect INSIDE the sandboxed iframe (handles both OOPIF iframe targets and in-process childFrames)
    const { targetInfos } = await browser.cdp.send('Target.getTargets');
    const iframeTarget = (targetInfos || []).find((t) => t.type === 'iframe' && t.url.startsWith('about:srcdoc'));
    let iframeSessionId = browser.sessionId;
    let iframeContextId;

    if (iframeTarget) {
      const attached = await browser.cdp.send('Target.attachToTarget', {
        targetId: iframeTarget.targetId,
        flatten: true
      });
      iframeSessionId = attached.sessionId;
      await browser.cdp.send('Runtime.enable', {}, iframeSessionId);
    } else {
      const { frameTree } = await browser.cdp.send('Page.getFrameTree', {}, browser.sessionId);
      const childFrame = frameTree.childFrames?.[0]?.frame;
      assert.ok(childFrame, 'Expected sandboxed child iframe in Target.getTargets or Page.getFrameTree');
      const world = await browser.cdp.send('Page.createIsolatedWorld', {
        frameId: childFrame.id,
        worldName: 'e2e-audit'
      }, browser.sessionId);
      iframeContextId = world.executionContextId;
    }

    const iframeAudit = await browser.cdp.eval(`(async () => {
      const btnRadius = getComputedStyle(document.documentElement).getPropertyValue('--btn-radius').trim();
      const btnC1 = getComputedStyle(document.documentElement).getPropertyValue('--btn-c1').trim();
      const origin = window.origin;
      let parentBlocked = false;
      try {
        void window.parent.document.title;
      } catch (e) {
        parentBlocked = true;
      }
      let externalFetchBlocked = false;
      try {
        await fetch('https://example.com/');
      } catch (e) {
        externalFetchBlocked = true;
      }
      const hasButton = Boolean(document.querySelector('.otter-grad-btn'));
      return { btnRadius, btnC1, origin, parentBlocked, externalFetchBlocked, hasButton };
    })()`, { sessionId: iframeSessionId, contextId: iframeContextId });

    assert.equal(iframeAudit.hasButton, true, 'Sandboxed preview must render .otter-grad-btn');
    assert.equal(iframeAudit.btnRadius, '24px', 'Live customizer postMessage must apply valid --btn-radius and ignore wrong channel');
    assert.ok(!iframeAudit.btnC1.includes('evil.example'), 'Unsafe CSS url() value via postMessage must be rejected');
    assert.equal(iframeAudit.origin, 'null', 'Sandboxed iframe must have opaque null origin');
    assert.equal(iframeAudit.parentBlocked, true, 'Sandboxed iframe must not access window.parent.document');
    assert.equal(iframeAudit.externalFetchBlocked, true, 'CSP connect-src none must block external fetch inside iframe');

    assert.deepEqual(failedRequests, [], `Unexpected HTTP >= 400 requests: ${failedRequests.join(', ')}`);
    assert.deepEqual(pageExceptions, [], `Unexpected uncaught page exceptions: ${pageExceptions.join(', ')}`);
    // Filter out expected CSP violation console log from our deliberate external fetch security probe
    const unexpectedConsoleErrors = consoleErrors.filter((m) => !m.includes('Content Security Policy') && !m.includes('example.com'));
    assert.deepEqual(unexpectedConsoleErrors, [], `Unexpected console errors: ${unexpectedConsoleErrors.join(', ')}`);
  } finally {
    await browser.cleanup();
    server.kill('SIGTERM');
  }
});
