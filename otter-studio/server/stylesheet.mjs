// stylesheet.mjs - Which stylesheet belongs to a project, found the way the
// compiler finds it (Resolve-OtterProjectStylesheet in src/Otter.Web.psm1,
// D125 - the release line's rule, adopted on this line 2026-09-30), so the
// Designer edits the file the app really uses: <entry>.css beside the entry
// (app.ot -> app.css), and nothing else - styles.css is not a stylesheet.
//
// The entry is the project manifest's entryPoint (else main.ot). When it has
// no stylesheet yet, new styles go to <entry>.css.
//
//   GET /api/project-stylesheet?folder=<project> -> { path, exists, entry }
//   (paths are workspace paths, like every other route's)

import fs from 'node:fs';
import path from 'node:path';

const isFile = (p) => { try { return fs.statSync(p).isFile(); } catch { return false; } };

export function projectEntry(folderAbs) {
  for (const name of ['otter.json', 'project.json']) {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(folderAbs, name), 'utf8'));
      const entry = data.entryPoint || data.main;
      if (typeof entry === 'string' && entry.trim()) return path.resolve(folderAbs, entry.trim());
    } catch { /* no manifest, or unreadable */ }
  }
  return path.join(folderAbs, 'main.ot');
}

export function resolveProjectStylesheet(folderAbs) {
  const entry = projectEntry(folderAbs);
  const entryDir = path.dirname(entry);
  const named = path.join(entryDir, `${path.basename(entry, path.extname(entry))}.css`);
  return { entry, path: named, exists: isFile(named) };
}

export function handleStylesheetRoute(req, res, pathname, urlObj, ctx) {
  if (pathname !== '/api/project-stylesheet' || req.method !== 'GET') return false;
  const folder = urlObj.searchParams.get('folder') || '';
  const abs = path.resolve(ctx.repoRoot, folder);
  if (!folder || !ctx.isInsideRepo(abs) || !fs.existsSync(abs)) return ctx.sendJson(res, { error: 'Project folder not found' }, 404), true;
  const found = resolveProjectStylesheet(abs);
  // A workspace path in the same form as the folder that was asked about.
  const toWorkspace = (p) => {
    const rel = path.relative(abs, p).split(path.sep).join('/');
    return `${folder.replace(/[\\/]+$/, '')}/${rel}`;
  };
  ctx.sendJson(res, { path: toWorkspace(found.path), exists: found.exists, entry: toWorkspace(found.entry) });
  return true;
}
