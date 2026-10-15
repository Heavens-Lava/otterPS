// Presses every Run button on the built documentation site, the way a reader
// does, and prints one JSON result per sample. Used by
// tools/Test-OtterDocumentationSamples.ps1; needs Node and playwright-core
// (OTTER_PLAYWRIGHT_CORE names the folder holding it).
//
// usage: node documentation-samples-browser.mjs <site folder> <page slug>...
import { createRequire } from 'module';
import path from 'path';
import { pathToFileURL } from 'url';

const coreFolder = process.env.OTTER_PLAYWRIGHT_CORE;
const require = createRequire(path.join(path.dirname(coreFolder), 'x.js'));
const { chromium } = require(coreFolder);

const [siteRoot, ...slugs] = process.argv.slice(2);
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
    await page.goto(pathToFileURL(path.join(siteRoot, slug, 'index.html')).href);
    await page.waitForTimeout(300);
    const ids = await page.$$eval('[data-otter-run]', (buttons) => buttons.map((b) => b.getAttribute('data-otter-run')));
    for (const id of ids) {
      const button = page.locator(`[data-otter-run="${id}"]`);
      await button.click();
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
}
console.log(JSON.stringify(results));
