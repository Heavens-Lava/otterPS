import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { join, normalize, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = normalize(fileURLToPath(new URL('../generated/', import.meta.url)));
const types = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8', '.txt': 'text/plain; charset=utf-8', '.wasm': 'application/wasm',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
  '.mp4': 'video/mp4', '.webm': 'video/webm'
};
const port = Number(process.env.PORT || 4174);

createServer(async (request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, `http://localhost:${port}`).pathname);
  if (pathname !== '/' && !pathname.endsWith('/') && !extname(pathname)) {
    response.writeHead(308, { location: `${pathname}/` }); response.end(); return;
  }
  const isDirectFile = pathname.startsWith('/static/') || Boolean(extname(pathname));
  const relative = isDirectFile
    ? pathname.slice(1)
    : (pathname === '/' ? 'home/index.html' : `${pathname.slice(1)}index.html`);
  const local = normalize(join(root, relative));
  if (!local.startsWith(root)) { response.writeHead(403); response.end('Forbidden'); return; }
  try {
    const content = await readFile(local);
    response.writeHead(200, { 'content-type': types[extname(local)] || 'application/octet-stream' });
    response.end(content);
  } catch {
    response.writeHead(404); response.end('Not found. Build the Otter pages first.');
  }
}).listen(port, () => console.log(`Otter pages: http://localhost:${port}`));
