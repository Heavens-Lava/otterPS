// The Designer edits the stylesheet the compiler uses (D125):
// <entry>.css, else styles.css beside the entry, else the root's styles.css.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
const { resolveProjectStylesheet } = await import('../server/stylesheet.mjs');

let passed = 0;
function test(name, fn) {
  fn();
  passed++;
  console.log(`  ✓ ${name}`);
}
const project = (files) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-sheet-'));
  for (const [name, text] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(dir, name)), { recursive: true });
    fs.writeFileSync(path.join(dir, name), text);
  }
  return dir;
};
const rel = (dir, p) => path.relative(dir, p).split(path.sep).join('/');

console.log('Project stylesheet:');
const made = [];
try {
  test('the entry\'s own stylesheet first: app.ot -> app.css (OtterBoard)', () => {
    const dir = project({ 'project.json': JSON.stringify({ entryPoint: 'app.ot' }), 'app.ot': '', 'app.css': '', 'styles.css': '' });
    made.push(dir);
    const found = resolveProjectStylesheet(dir);
    assert.equal(rel(dir, found.path), 'app.css');
    assert.equal(found.exists, true);
  });
  test('then styles.css beside the entry', () => {
    const dir = project({ 'otter.json': JSON.stringify({ entryPoint: 'src/main.ot' }), 'src/main.ot': '', 'src/styles.css': '', 'styles.css': '' });
    made.push(dir);
    assert.equal(rel(dir, resolveProjectStylesheet(dir).path), 'src/styles.css');
  });
  test('then the project root\'s styles.css, for an entry in src/', () => {
    const dir = project({ 'otter.json': JSON.stringify({ entryPoint: 'src/main.ot' }), 'src/main.ot': '', 'styles.css': '' });
    made.push(dir);
    assert.equal(rel(dir, resolveProjectStylesheet(dir).path), 'styles.css');
  });
  // <entry>.css: the stylesheet every Otter compiler reads for the entry
  // (the release line's D125 reads no styles.css at all).
  test('none yet: <entry>.css beside the entry', () => {
    const dir = project({ 'project.json': JSON.stringify({ entryPoint: 'main.ot' }), 'main.ot': '' });
    made.push(dir);
    const found = resolveProjectStylesheet(dir);
    assert.equal(rel(dir, found.path), 'main.css');
    assert.equal(found.exists, false);
  });
} finally {
  for (const dir of made) fs.rmSync(dir, { recursive: true, force: true });
}
console.log(`\nStylesheet tests passed: ${passed}.`);
