#!/usr/bin/env node
/**
 * scripts/build-library-thumbnails.mjs
 * Deterministic build-time visual thumbnail generator for Otter Component Library v1.1:
 *   - Web & Styles & Effects components (preview.type === 'iframe-sandbox'):
 *     Renders each component's hardened CSP srcdoc in headless Chromium/Edge at 640x360
 *     with prefers-reduced-motion: reduce (ensuring deterministic static frames) and saves
 *     optimized WebP thumbnails to <outputRoot>/static/library-previews/<slug>.webp.
 *   - Desktop (WPF), Games (Godot/Unity/Roblox), and Otter (Packs, Workflows, Blueprints,
 *     Recipes, Snippets):
 *     Generates crisp, honest, deterministic 640x360 SVG architecture or Schema v2 contract
 *     diagrams under <outputRoot>/static/library-previews/<slug>.svg — never misrepresenting
 *     native/game/backend components as live browser previews.
 *
 * Enriches <outputRoot>/static/library-catalog.json with deterministic `thumbnail` metadata.
 */

import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CATEGORY_META,
  assertSafePreviewMarkup,
  buildSandboxSrcDoc
} from '../static/library-filter.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DOCS_ROOT = resolve(__dirname, '..');

function parseArgs(argv) {
  const opts = { outputRoot: resolve(DOCS_ROOT, 'generated') };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--output-root' && argv[i + 1]) opts.outputRoot = resolve(argv[++i]);
  }
  return opts;
}

function xmlEscape(str) {
  return String(str ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function truncate(str, max) {
  const s = String(str || '').replace(/\s+/g, ' ').trim();
  return s.length > max ? `${s.slice(0, max - 1)}…` : s;
}

function findBrowserBinary() {
  if (process.env.CHROME_BIN && existsSync(process.env.CHROME_BIN)) return process.env.CHROME_BIN;
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

class SimpleCdp {
  constructor(ws) {
    this.ws = ws;
    this.nextId = 1;
    this.pending = new Map();
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(typeof ev.data === 'string' ? ev.data : ev.data.toString('utf8'));
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve: res, reject: rej } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        if (msg.error) rej(new Error(`CDP ${msg.error.code}: ${msg.error.message}`));
        else res(msg.result);
      }
    });
  }
  send(method, params = {}, sessionId = undefined) {
    const id = this.nextId++;
    const payload = sessionId ? { id, method, params, sessionId } : { id, method, params };
    return new Promise((res, rej) => {
      const t = setTimeout(() => {
        this.pending.delete(id);
        rej(new Error(`CDP timeout on ${method}`));
      }, 15000);
      this.pending.set(id, {
        resolve: (v) => { clearTimeout(t); res(v); },
        reject: (e) => { clearTimeout(t); rej(e); }
      });
      this.ws.send(JSON.stringify(payload));
    });
  }
  close() {
    try { this.ws.close(); } catch { /* ignore */ }
  }
}

async function captureWebThumbnails(webItems, previewsDir) {
  if (!webItems.length) return new Map();
  const browserBin = findBrowserBinary();
  if (!browserBin) {
    throw new Error(
      'Headless Chromium/Chrome/Edge is required to generate Web & CSS visual thumbnails (Option A). Set CHROME_BIN or install Chrome/Edge/Chromium.'
    );
  }

  const userDataDir = mkdtempSync(join(tmpdir(), 'otter-thumb-cdp-'));
  const args = [
    '--headless=new',
    '--disable-gpu',
    '--no-first-run',
    '--no-default-browser-check',
    '--hide-scrollbars',
    '--remote-debugging-port=0',
    `--user-data-dir=${userDataDir}`,
    '--window-size=640,360',
    'about:blank'
  ];
  if (process.platform === 'linux') args.push('--no-sandbox');

  const proc = spawn(browserBin, args, { stdio: ['ignore', 'pipe', 'pipe'] });
  const wsUrl = await new Promise((res, rej) => {
    let stderr = '';
    const t = setTimeout(() => rej(new Error(`Thumbnail browser did not start:\n${stderr}`)), 15000);
    proc.stderr.on('data', (chunk) => {
      stderr += chunk.toString('utf8');
      const m = stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (m) { clearTimeout(t); res(m[1]); }
    });
    proc.on('exit', (code) => { clearTimeout(t); rej(new Error(`Thumbnail browser exited (${code}):\n${stderr}`)); });
  });

  const ws = new WebSocket(wsUrl);
  await new Promise((res, rej) => {
    ws.addEventListener('open', res, { once: true });
    ws.addEventListener('error', rej, { once: true });
  });
  const cdp = new SimpleCdp(ws);
  const sizes = new Map();

  try {
    const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
    await cdp.send('Page.enable', {}, sessionId);
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: 640,
      height: 360,
      deviceScaleFactor: 1,
      mobile: false
    }, sessionId);
    // Freeze CSS animations via prefers-reduced-motion so WebP screenshots are deterministic across runs
    await cdp.send('Emulation.setEmulatedMedia', {
      features: [{ name: 'prefers-reduced-motion', value: 'reduce' }]
    }, sessionId);

    const { frameTree } = await cdp.send('Page.getFrameTree', {}, sessionId);
    const frameId = frameTree.frame.id;

    for (const item of webItems) {
      const p = item.preview || {};
      assertSafePreviewMarkup(p.html || '', p.css || '', p.js || '');
      // Enhance thumbnail framing cleanly so every component fills the 640x360 card stage nicely
      const thumbCss = `${p.css || ''}\nhtml,body{margin:0;padding:0;min-height:360px;height:360px;overflow:hidden;background:#0b162a;}\n.demo-stage,.glass-stage,.tilt-stage,.pal-stage{min-height:360px!important;height:360px!important;box-sizing:border-box;}\n`;
      const srcdoc = buildSandboxSrcDoc({
        html: p.html || '',
        css: thumbCss,
        js: p.js || '',
        channel: `otter-thumb-${item.slug}`
      });

      await cdp.send('Page.setDocumentContent', { frameId, html: srcdoc }, sessionId);
      await new Promise((r) => setTimeout(r, 120));

      const shot = await cdp.send('Page.captureScreenshot', {
        format: 'webp',
        quality: 86,
        clip: { x: 0, y: 0, width: 640, height: 360, scale: 1 }
      }, sessionId);
      const buf = Buffer.from(shot.data, 'base64');
      const outPath = join(previewsDir, `${item.slug}.webp`);
      writeFileSync(outPath, buf);
      sizes.set(item.slug, buf.length);
    }
  } finally {
    cdp.close();
    proc.kill('SIGTERM');
    await new Promise((r) => setTimeout(r, 150));
    rmSync(userDataDir, { recursive: true, force: true });
  }
  return sizes;
}

function buildHonestSvgDiagram(item) {
  const palettes = {
    desktop: { bg1: '#0f172a', bg2: '#1e293b', accent: '#38bdf8', chip: '#0284c7', kind: 'NATIVE WPF ARCHITECTURE' },
    games: { bg1: '#052e2b', bg2: '#0f4c45', accent: '#34d399', chip: '#059669', kind: `${String(item.framework || 'GAME').toUpperCase()} ARCHITECTURE` },
    otter: { bg1: '#0b1d36', bg2: '#163567', accent: '#60a5fa', chip: '#2563eb', kind: item.subcategory === 'Packs' ? 'SCHEMA V2 PACK CONTRACT' : `OTTER ${String(item.subcategory || 'COMPONENT').toUpperCase()}` }
  };
  const pal = palettes[item.category] || palettes.otter;
  const gradId = `g-${item.slug.replace(/[^a-z0-9]/gi, '')}`;

  // Build up to 3 honest nodes/lines describing real architecture or operations
  let nodes = [];
  if (item.contract?.operations?.length) {
    const ops = item.contract.operations.slice(0, 3);
    nodes = ops.map((op) => {
      const params = (op.parameters || []).map((p) => p.name).join(', ');
      return `${op.name}(${params}) -> ${op.returns?.type || 'any'}`;
    });
    if (item.contract.operations.length > 3) {
      nodes[2] = `+ ${item.contract.operations.length - 2} more AST-verified ops (prefix: ${item.contract.variablePrefix || 'none'})`;
    }
  } else if (Array.isArray(item.preview?.architecture) && item.preview.architecture.length) {
    nodes = item.preview.architecture.slice(0, 3).map((s) => truncate(s, 62));
  } else {
    const codeLines = (item.files?.[0]?.content || '')
      .split('\n')
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith('#'))
      .slice(0, 3);
    nodes = codeLines.map((l) => truncate(l, 62));
  }

  const nodeBoxes = nodes.map((text, idx) => {
    const y = 128 + idx * 66;
    const arrow = idx < nodes.length - 1
      ? `<line x1="60" y1="${y + 46}" x2="60" y2="${y + 66}" stroke="${pal.accent}" stroke-width="2" stroke-dasharray="4 3" opacity="0.7"/>`
      : '';
    return `
      <rect x="34" y="${y}" width="572" height="46" rx="10" fill="rgba(15, 23, 42, 0.72)" stroke="rgba(148, 163, 184, 0.28)" stroke-width="1.2"/>
      <circle cx="60" cy="${y + 23}" r="12" fill="${pal.chip}"/>
      <text x="60" y="${y + 27}" fill="#ffffff" font-family="Inter, system-ui, sans-serif" font-size="12" font-weight="700" text-anchor="middle">${idx + 1}</text>
      <text x="86" y="${y + 28}" fill="#e2e8f0" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="13.5">${xmlEscape(truncate(text, 56))}</text>
      ${arrow}`;
  }).join('');

  const fileCount = (item.files || []).length;
  const subLabel = `${item.language} · ${item.framework} · ${fileCount} ${fileCount === 1 ? 'file' : 'files'}`;

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 360" width="640" height="360" role="img" aria-label="${xmlEscape(`${item.name} — ${pal.kind}`)}">
  <defs>
    <linearGradient id="${gradId}" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${pal.bg1}"/>
      <stop offset="100%" stop-color="${pal.bg2}"/>
    </linearGradient>
  </defs>
  <rect width="640" height="360" fill="url(#${gradId})"/>
  <circle cx="590" cy="40" r="110" fill="${pal.accent}" opacity="0.09"/>
  <rect x="34" y="28" width="230" height="26" rx="13" fill="rgba(255,255,255,0.12)"/>
  <text x="48" y="45" fill="${pal.accent}" font-family="Inter, system-ui, sans-serif" font-size="11" font-weight="700" letter-spacing="0.08em">${xmlEscape(truncate(pal.kind, 30))}</text>
  <text x="34" y="88" fill="#ffffff" font-family="Inter, system-ui, sans-serif" font-size="22" font-weight="800">${xmlEscape(truncate(item.name, 42))}</text>
  <text x="34" y="110" fill="#94a3b8" font-family="Inter, system-ui, sans-serif" font-size="13">${xmlEscape(truncate(subLabel, 68))}</text>
  ${nodeBoxes}
</svg>
`;
}

export async function buildLibraryThumbnails(options = {}) {
  const outputRoot = resolve(options.outputRoot || resolve(DOCS_ROOT, 'generated'));
  const catalogPath = join(outputRoot, 'static', 'library-catalog.json');
  if (!existsSync(catalogPath)) {
    throw new Error(`Missing catalog JSON at ${catalogPath}. Run build-library-catalog.mjs first.`);
  }

  const previewsDir = join(outputRoot, 'static', 'library-previews');
  mkdirSync(previewsDir, { recursive: true });

  const catalog = JSON.parse(readFileSync(catalogPath, 'utf8'));
  const items = catalog.components || [];

  const webItems = items.filter((it) => it.preview?.type === 'iframe-sandbox');
  const nonWebItems = items.filter((it) => it.preview?.type !== 'iframe-sandbox');

  const webSizes = await captureWebThumbnails(webItems, previewsDir);

  let svgCount = 0;
  for (const item of items) {
    if (item.preview?.type === 'iframe-sandbox') {
      item.thumbnail = {
        url: `/static/library-previews/${item.slug}.webp`,
        kind: 'rendered-preview',
        label: 'Rendered Preview',
        width: 640,
        height: 360,
        bytes: webSizes.get(item.slug) || 0,
        alt: `Rendered browser preview of ${item.name} (${item.language})`
      };
    } else {
      const svg = buildHonestSvgDiagram(item);
      const outPath = join(previewsDir, `${item.slug}.svg`);
      writeFileSync(outPath, svg, 'utf8');
      svgCount++;
      const isContract = item.preview?.type === 'contract-summary';
      const catLabel = CATEGORY_META[item.category]?.label || item.category;
      item.thumbnail = {
        url: `/static/library-previews/${item.slug}.svg`,
        kind: isContract ? 'contract-diagram' : 'architecture-diagram',
        label: isContract ? `${item.contract?.operationsCount || 0} Ops Contract` : 'Architecture Diagram',
        width: 640,
        height: 360,
        bytes: Buffer.byteLength(svg, 'utf8'),
        alt: isContract
          ? `Schema v${item.contract?.schemaVersion || 2} operation contract diagram for ${item.name} (${item.contract?.operationsCount || 0} operations)`
          : `${catLabel} architecture diagram for ${item.name} (${item.framework})`
      };
    }
  }

  writeFileSync(catalogPath, JSON.stringify(catalog, null, 2) + '\n', 'utf8');
  return {
    webpCount: webItems.length,
    svgCount,
    totalThumbnails: items.length,
    webTotalBytes: [...webSizes.values()].reduce((a, b) => a + b, 0)
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const opts = parseArgs(process.argv.slice(2));
  const res = await buildLibraryThumbnails(opts);
  console.log(
    `Generated ${res.totalThumbnails} library thumbnails (${res.webpCount} WebP rendered previews [${Math.round(res.webTotalBytes / 1024)} KB total] + ${res.svgCount} SVG architecture/contract diagrams)`
  );
}
