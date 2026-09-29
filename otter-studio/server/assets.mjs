// assets.mjs - The project's assets, for the Designer's Assets tab.
//
//   GET  /api/assets?folder=<project>   images, fonts, styles and data files in
//                                       the project, grouped by kind
//   GET  /api/raw/<workspace path>      an image or font, so the canvas and
//                                       the in-place preview can show it
//   POST /api/assets/import             { folder, name, data (base64) }: a
//                                       new image, saved in assets/images
//
// /api/raw serves images and fonts only, with a sandboxing Content Security
// Policy: an SVG opened directly cannot run script with Studio's origin
// (which could call the rest of the API).

import fs from 'node:fs';
import path from 'node:path';

export const ASSET_KINDS = {
  images: ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.ico', '.bmp', '.avif'],
  fonts: ['.woff', '.woff2', '.ttf', '.otf'],
  styles: ['.css'],
  data: ['.json', '.csv', '.txt', '.xml']
};

const MIME = {
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif',
  '.webp': 'image/webp', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.bmp': 'image/bmp',
  '.avif': 'image/avif', '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf', '.otf': 'font/otf'
};

// Folders that are tooling or build output, not the project's own assets.
const SKIP_DIRS = new Set(['node_modules', '.git', '.otter', '.studio', 'dist', 'build', 'out', 'bin', 'obj']);
const MAX_FILES = 2000;
const MAX_DEPTH = 8;
// Files the project.json manifest and Studio write for themselves.
const SKIP_FILES = new Set(['project.json', 'package.json', 'package-lock.json']);

function kindOf(name) {
  const ext = path.extname(name).toLowerCase();
  return Object.keys(ASSET_KINDS).find(k => ASSET_KINDS[k].includes(ext)) || null;
}

// Every asset under `folderAbs`, as paths relative to it ('/'-separated).
export function listAssets(folderAbs) {
  const out = { images: [], fonts: [], styles: [], data: [] };
  let count = 0;
  const walk = (dir, depth) => {
    if (depth > MAX_DEPTH || count >= MAX_FILES) return;
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    entries.sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      if (count >= MAX_FILES) return;
      if (entry.name.startsWith('.')) continue;
      const abs = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (!SKIP_DIRS.has(entry.name.toLowerCase())) walk(abs, depth + 1);
        continue;
      }
      if (!entry.isFile() || SKIP_FILES.has(entry.name.toLowerCase())) continue;
      const kind = kindOf(entry.name);
      if (!kind) continue;
      let size = 0;
      try { size = fs.statSync(abs).size; } catch { /* vanished */ }
      out[kind].push({ path: path.relative(folderAbs, abs).split(path.sep).join('/'), name: entry.name, size });
      count++;
    }
  };
  walk(folderAbs, 0);
  return out;
}

// A file name that is safe on every platform and not already taken in `dir`.
export function freeImageName(dir, wanted) {
  const ext = path.extname(wanted).toLowerCase();
  let base = path.basename(wanted, path.extname(wanted)).replace(/[^\w.-]+/g, '-').replace(/^-+|-+$/g, '') || 'image';
  let name = `${base}${ext}`;
  for (let i = 2; fs.existsSync(path.join(dir, name)); i++) name = `${base}-${i}${ext}`;
  return name;
}

export async function handleAssetRoutes(req, res, pathname, urlObj, ctx) {
  if (pathname === '/api/assets' && req.method === 'GET') {
    const rel = urlObj.searchParams.get('folder') || '';
    const abs = path.resolve(ctx.repoRoot, rel);
    if (!rel || !ctx.isInsideRepo(abs)) return ctx.sendJson(res, { error: 'Forbidden' }, 403), true;
    if (!fs.existsSync(abs) || !fs.statSync(abs).isDirectory()) return ctx.sendJson(res, { error: 'Project folder not found' }, 404), true;
    ctx.sendJson(res, { folder: rel, assets: listAssets(abs) });
    return true;
  }

  if (pathname.startsWith('/api/raw/') && req.method === 'GET') {
    let rel;
    try { rel = decodeURIComponent(pathname.slice('/api/raw/'.length)); } catch { rel = ''; }
    const abs = path.resolve(ctx.repoRoot, rel);
    const type = MIME[path.extname(abs).toLowerCase()];
    if (!rel || !type || !ctx.isInsideRepo(abs)) {
      res.writeHead(403, { 'Content-Type': 'text/plain' });
      res.end('Only images and fonts in the workspace are served here.');
      return true;
    }
    if (!fs.existsSync(abs) || !fs.statSync(abs).isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found');
      return true;
    }
    res.writeHead(200, {
      'Content-Type': type,
      'Cache-Control': 'no-cache',
      'Content-Security-Policy': "sandbox; default-src 'none'; img-src data:; style-src 'unsafe-inline'"
    });
    fs.createReadStream(abs).pipe(res);
    return true;
  }

  if (pathname === '/api/assets/import' && req.method === 'POST') {
    try {
      const body = await ctx.readBody(req);
      const folderAbs = path.resolve(ctx.repoRoot, String(body.folder || ''));
      if (!body.folder || !ctx.isInsideRepo(folderAbs)) return ctx.sendJson(res, { error: 'Forbidden' }, 403), true;
      if (kindOf(String(body.name || '')) !== 'images') {
        return ctx.sendJson(res, { error: 'Only images can be imported here (png, jpg, gif, webp, svg, ico, bmp, avif).' }, 400), true;
      }
      const dir = path.join(folderAbs, 'assets', 'images');
      fs.mkdirSync(dir, { recursive: true });
      const name = freeImageName(dir, String(body.name));
      fs.writeFileSync(path.join(dir, name), Buffer.from(String(body.data || ''), 'base64'));
      ctx.sendJson(res, { ok: true, path: `assets/images/${name}` });
    } catch (err) {
      ctx.sendJson(res, { error: err.message }, err.status || 500);
    }
    return true;
  }
  return false;
}
