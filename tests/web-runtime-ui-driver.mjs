// Drives a compiled Otter web page in headless Chromium and prints one JSON
// line with what happened. Used by tests/WebRuntimeUi.Tests.ps1.
//
//   node web-runtime-ui-driver.mjs <playwright-core dir> <page.html> <scenario>
//
// Scenarios live here, next to the page they exercise, so the PowerShell test
// only compares results.
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const [pwDir, pagePath, scenario] = process.argv.slice(2);
const require = createRequire(path.join(pwDir, 'package.json'));
const { chromium } = require('playwright-core');

const scenarios = {
  // examples/v1/tasks.ot: each Add click creates a new line with the typed text.
  async tasks(page) {
    return page.evaluate(async () => {
      const input = document.getElementById('taskInput');
      const btn = document.getElementById('addButton');
      for (const t of ['Buy milk', 'Walk the otter', '']) {
        input.value = t;
        btn.click();
        await new Promise(r => setTimeout(r, 30));
      }
      return {
        items: Array.from(document.getElementById('taskList').children).map(c => c.textContent),
        inputAfter: input.value
      };
    });
  },
  // A function that builds cards (locals), a top-level loop, a handler on
  // each runtime button, and `has` on a top-level element.
  async board(page) {
    return page.evaluate(async () => {
      const cards = () => Array.from(document.getElementById('cards').children)
        .map(c => c.textContent.replace(/\s+/g, ' ').trim());
      const atLoad = cards();
      document.getElementById('titleInput').value = 'gamma';
      document.getElementById('addButton').click();
      await new Promise(r => setTimeout(r, 30));
      const statusAfterAdd = document.getElementById('status').textContent;
      document.getElementById('cards').children[1].querySelector('button').click();
      await new Promise(r => setTimeout(r, 30));
      const first = document.getElementById('cards').children[0];
      return {
        atLoad,
        after: cards(),
        statusAfterAdd,
        statusAfterRemove: document.getElementById('status').textContent,
        cardBackground: first.style.background,
        cardPadding: first.style.padding,
        rowGap: first.querySelector('.otter-row').style.gap
      };
    });
  },
  // A Run-button sample: click Run and read its output box.
  async samples(page) {
    return page.evaluate(async () => {
      document.querySelector('[data-otter-run="thingSample"]').click();
      for (let i = 0; i < 100; i++) {
        const o = document.getElementById('thingSample-output');
        if (o && !o.hidden && o.textContent.trim()) { break; }
        await new Promise(r => setTimeout(r, 30));
      }
      const o = document.getElementById('thingSample-output');
      return { output: o ? o.textContent.trim() : null, isError: !!o && o.classList.contains('otter-run-error') };
    });
  },
  // `put` of something that is not a UI resource: the interpreter's message.
  async putError(page) {
    return page.evaluate(async () => {
      document.getElementById('goButton').click();
      await new Promise(r => setTimeout(r, 30));
      return { errors: window.__otterErrors };
    });
  },
  // Files in a plain browser tab: each operation is caught by try/otherwise.
  async fileErrors(page) {
    await page.waitForTimeout(300);
    return page.evaluate(() => ({ results: document.getElementById('results').textContent }));
  }
};

const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(String(e.message)));
  await page.addInitScript(() => {
    window.__otterErrors = [];
    window.addEventListener('unhandledrejection', e => window.__otterErrors.push(String(e.reason && e.reason.message || e.reason)));
  });
  await page.goto(pathToFileURL(path.resolve(pagePath)).href);
  const result = await scenarios[scenario](page);
  result.pageErrors = errors;
  process.stdout.write(JSON.stringify(result) + '\n');
} finally {
  await browser.close();
}
