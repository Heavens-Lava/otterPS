import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { join, extname, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../dist/', import.meta.url));
const types = { '.css': 'text/css', '.js': 'text/javascript', '.json': 'application/json', '.html': 'text/html' };
createServer(async (request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  // Each documentation page is emitted as <slug>/index.html. Redirect the
  // slashless spelling so copied clean URLs work as expected too.
  if (pathname !== '/' && !pathname.endsWith('/') && !extname(pathname)) {
    response.writeHead(308, { location: `${pathname}/` });
    response.end();
    return;
  }
  const local = normalize(join(root, pathname === '/' ? 'index.html' : `${pathname.replace(/^\//, '')}${pathname.endsWith('/') ? 'index.html' : ''}`));
  if (!local.startsWith(normalize(root))) { response.writeHead(403); response.end('Forbidden'); return; }
  try { const content = await readFile(local); response.writeHead(200, { 'content-type': `${types[extname(local)] || 'application/octet-stream'}; charset=utf-8` }); response.end(content); }
  catch { response.writeHead(404); response.end('Not found. Run npm run build first.'); }
}).listen(Number(process.env.PORT || 4173), () => console.log(`Otter docs: http://localhost:${process.env.PORT || 4173}`));
