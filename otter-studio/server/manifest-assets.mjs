// manifest-assets.mjs - The pictures a website shows reach its build only
// when the project manifest lists them under "assets" (otter build copies
// the declared assets beside the pages, keeping their paths). Studio keeps
// that list in step, so a picture never goes missing from a published site:
//
//   addManifestAssets(projectDir, ['assets/images/team.png']) -> the paths added
//   referencedImages(projectDir) -> the project's own images that its .ot
//     files show (`source "assets/images/team.png"`), as project paths
//
// Web addresses, absolute paths and files outside the project are left alone.
import fs from 'node:fs';
import path from 'node:path';

const MANIFESTS = ['otter.json', 'project.json'];
const IMAGE = /\.(png|jpe?g|gif|webp|svg|ico|bmp|avif)$/i;
const SKIP_DIRS = new Set(['node_modules', 'dist', 'dist-electron', 'packages', 'publish', '.git']);

export function manifestPathFor(projectDir) {
  for (const name of MANIFESTS) {
    const file = path.join(projectDir, name);
    if (fs.existsSync(file)) return file;
  }
  return null;
}

const normal = (rel) => String(rel).replace(/\\/g, '/').replace(/^\.\//, '');

export function addManifestAssets(projectDir, relPaths) {
  const file = manifestPathFor(projectDir);
  if (!file || !relPaths.length) return [];
  let raw;
  let data;
  try {
    raw = fs.readFileSync(file, 'utf8');
    data = JSON.parse(raw);
  } catch {
    return []; // an unreadable manifest is left for the build to report
  }
  const list = Array.isArray(data.assets) ? data.assets : [];
  const have = new Set(list.map(normal));
  const added = [];
  for (const rel of relPaths.map(normal)) {
    if (!rel || have.has(rel)) continue;
    list.push(rel);
    have.add(rel);
    added.push(rel);
  }
  if (added.length) {
    data.assets = list;
    const nl = raw.includes('\r\n') ? '\r\n' : '\n';
    fs.writeFileSync(file, JSON.stringify(data, null, 2).replace(/\n/g, nl) + nl, 'utf8');
  }
  return added;
}

export function referencedImages(projectDir) {
  const root = path.resolve(projectDir);
  const found = new Set();
  const walk = (dir, depth) => {
    if (depth > 4) return;
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      const abs = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (!SKIP_DIRS.has(entry.name) && !entry.name.startsWith('.')) walk(abs, depth + 1);
        continue;
      }
      if (!entry.isFile() || !/\.ot$/i.test(entry.name)) continue;
      const text = fs.readFileSync(abs, 'utf8');
      // An image's source, and a page's icon.
      for (const match of text.matchAll(/\b(?:source|icon)\s+"([^"]+)"/g)) {
        const src = match[1];
        if (/^[a-z][a-z0-9+.-]*:/i.test(src) || src.startsWith('/') || !IMAGE.test(src)) continue;
        const target = path.resolve(dir, src);
        const rel = path.relative(root, target);
        if (!rel || rel.startsWith('..') || path.isAbsolute(rel)) continue;
        if (fs.existsSync(target)) found.add(rel.split(path.sep).join('/'));
      }
    }
  };
  walk(root, 0);
  return [...found].sort();
}
