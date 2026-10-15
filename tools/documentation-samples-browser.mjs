// Presses every Run button on the built documentation site, the way a reader
// does, and prints one JSON result per sample. Used by
// tools/Test-OtterDocumentationSamples.ps1; needs Node and playwright-core
// (OTTER_PLAYWRIGHT_CORE names the folder holding it).
//
// usage: node documentation-samples-browser.mjs <site folder> <page slug>...
import { createRequire } from 'module';
import path from 'path';
import fs from 'fs';
import http from 'http';

const coreFolder = process.env.OTTER_PLAYWRIGHT_CORE;
const require = createRequire(path.join(path.dirname(coreFolder), 'x.js'));
const { chromium } = require(coreFolder);

const [siteRoot, ...slugs] = process.argv.slice(2);

// Serve the built site over HTTP, as visitors get it: pages load their
// styles and images from absolute paths (/static/...), which a file:// page
// cannot resolve - and without its styles a page's layout is not the real one.
const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.json': 'application/json',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.woff2': 'font/woff2' };
const server = http.createServer((request, response) => {
  let relative = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  if (relative.endsWith('/')) relative += 'index.html';
  const file = path.join(siteRoot, relative);
  if (!file.startsWith(path.resolve(siteRoot)) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    response.writeHead(404); response.end(); return;
  }
  response.writeHead(200, { 'Content-Type': types[path.extname(file).toLowerCase()] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(response);
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;

const browser = await chromium.launch();
const results = [];
try {
  for (const slug of slugs) {
    const page = await browser.newPage();
    // A sample that asks a question gets "29" (a number reads as a number and
    // a name reads as text, so every sample can continue).
    page.on('dialog', (dialog) => dialog.accept('29').catch(() => {}));
    const pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
    await page.goto(`${origin}/${slug}/`);
    await page.waitForTimeout(300);
    const ids = await page.$$eval('[data-otter-run]', (buttons) => buttons.map((b) => b.getAttribute('data-otter-run')));
    for (const id of ids) {
      const button = page.locator(`[data-otter-run="${id}"]`);
      // A button a reader cannot press (hidden, or covered by another
      // element) is that sample's failure, not the end of the run.
      try {
        await button.click({ timeout: 10000 });
      } catch (err) {
        results.push({ slug, id, finished: true, error: true, text: 'the Run button could not be pressed: ' + String(err.message).split('\n')[0] });
        continue;
      }
      let finished = false;
      for (let i = 0; i < 100 && !finished; i++) {
        await page.waitForTimeout(100);
        finished = !(await button.isDisabled());
      }
      const output = await page.$eval(`[id="${id}-output"]`, (el) => ({
        text: el.textContent,
        error: el.classList.contains('otter-run-error')
      })).catch(() => ({ text: '(no output area)', error: true }));
      results.push({ slug, id, finished, error: output.error, text: output.text });
    }
    if (pageErrors.length) { results.push({ slug, id: '(page)', finished: true, error: true, text: pageErrors.join(' / ') }); }
    await page.close();
  }
} finally {
  await browser.close();
  server.close();
}
console.log(JSON.stringify(results));
