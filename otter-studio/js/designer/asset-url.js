// asset-url.js - Where the Designer finds a design's images.
//
// An image's source in Otter is relative to the design's .ot file
// (`source "assets/images/logo.png"`): the compiled app's page is written
// next to it, so that is where the running app looks. Studio's canvas and
// in-place preview are served from Studio's own origin, so they load the same
// file through the server's /api/raw route (server/assets.mjs).

let lastDesignDir = null;

const ABSOLUTE = /^(?:[a-z][a-z0-9+.-]*:|\/|#)/i;

function dirOf(file) {
  const i = file.lastIndexOf('/');
  return i === -1 ? '' : file.slice(0, i);
}

// The workspace folder of the design being edited: its .ot file's folder
// (the file the designer is bound to, else the open .ot file - the last one,
// while a stylesheet is open), else the project's.
export function designDir(ide = globalThis.window?.otterIde, binding = globalThis.window?.otterDesignBinding) {
  const file = String(binding?.file || ide?.currentFile || '').replace(/\\/g, '/');
  if (/\.ot$/i.test(file) && file.includes('/')) lastDesignDir = dirOf(file);
  return lastDesignDir ?? String(ide?.currentProjectFolder || '').replace(/\\/g, '/').replace(/\/+$/, '');
}

// Join and tidy a relative path: no '.', '..' resolved, '/'-separated.
export function joinPath(dir, rel) {
  const parts = [];
  for (const part of `${dir}/${rel}`.split('/')) {
    if (!part || part === '.') continue;
    if (part === '..') parts.pop();
    else parts.push(part);
  }
  return parts.join('/');
}

// What the canvas should load for an image source.
export function assetUrl(source, dir = designDir()) {
  const src = String(source || '').trim();
  if (!src || ABSOLUTE.test(src) || !dir) return src;
  return `/api/raw/${joinPath(dir, src).split('/').map(encodeURIComponent).join('/')}`;
}

// The <base> a compiled page needs so its relative sources load in Studio.
export function withAssetBase(html, dir = designDir()) {
  // A render of a real document already carries the server's <base> (its
  // workspace folder, /workspace-files/): that one is right.
  if (!dir || !html || /<base\s/i.test(html)) return html;
  const base = `<base href="/api/raw/${joinPath(dir, '').split('/').map(encodeURIComponent).join('/')}/">`;
  return /<head[^>]*>/i.test(html) ? html.replace(/<head[^>]*>/i, (m) => `${m}${base}`) : base + html;
}

// A path to `target` (workspace path) from the design's folder, for a source.
export function relativeToDesign(target, dir = designDir()) {
  const from = joinPath(dir, '').split('/').filter(Boolean);
  const to = joinPath(target, '').split('/').filter(Boolean);
  let i = 0;
  while (i < from.length && i < to.length && from[i] === to[i]) i++;
  return [...from.slice(i).map(() => '..'), ...to.slice(i)].join('/');
}
