// stylesheet.mjs - Which stylesheet belongs to a project, found the way the
// compiler finds it (Resolve-OtterProjectStylesheet in src/Otter.Web.psm1,
// SPEC-DECISIONS D125), so the Designer edits the file the app really uses:
//
//   1. <entry>.css beside the entry       app.ot -> app.css
//   2. styles.css beside the entry
//   3. styles.css in the project root (the folder with otter.json /
//      project.json), for an entry kept in src/
//
// The entry is the project manifest's entryPoint (else main.ot). When none
// exists yet, new styles go to <entry>.css beside the entry: the stylesheet
// every Otter compiler reads for that entry (styles.css is a fallback only
// some read).
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
  const candidates = [
    path.join(entryDir, `${path.basename(entry, path.extname(entry))}.css`),
    path.join(entryDir, 'styles.css'),
    path.join(folderAbs, 'styles.css')
  ];
  const found = candidates.find(isFile);
  return { entry, path: found || candidates[0], exists: Boolean(found) };
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
