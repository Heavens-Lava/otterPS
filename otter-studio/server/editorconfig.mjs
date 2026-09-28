// editorconfig.mjs - GET /api/editorconfig?path=<file>: the .editorconfig
// files that apply to a file, nearest folder first, from its folder up to
// the workspace root, stopping after one that says `root = true`. The
// client resolves them (js/editor/indentation.js).

import fs from 'node:fs';
import path from 'node:path';

const ROOT_LINE = /^\s*root\s*[=:]\s*true\s*$/im;

export function editorConfigChain(repoRoot, fileAbs) {
  const configs = [];
  const top = path.resolve(repoRoot);
  let dir = path.dirname(path.resolve(fileAbs));
  for (;;) {
    const candidate = path.join(dir, '.editorconfig');
    if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
      const text = fs.readFileSync(candidate, 'utf8');
      configs.push({ dir: path.relative(top, dir).split(path.sep).join('/') || '.', text });
      // `root` is only meaningful before the first [section].
      if (ROOT_LINE.test(text.split(/^\s*\[/m)[0])) break;
    }
    // The file is inside the workspace (the route checks), so walking up
    // reaches `top`; the second test only guards a filesystem root.
    const parent = path.dirname(dir);
    if (dir === top || parent === dir) break;
    dir = parent;
  }
  return configs;
}

export function handleEditorConfigRoute(req, res, pathname, urlObj, ctx) {
  if (pathname !== '/api/editorconfig' || req.method !== 'GET') return false;
  const rel = urlObj.searchParams.get('path') || '';
  const abs = path.resolve(ctx.repoRoot, rel);
  if (!rel || !ctx.isInsideRepo(abs)) return ctx.sendJson(res, { error: 'Forbidden' }, 403), true;
  ctx.sendJson(res, { path: rel, configs: editorConfigChain(ctx.repoRoot, abs) });
  return true;
}
