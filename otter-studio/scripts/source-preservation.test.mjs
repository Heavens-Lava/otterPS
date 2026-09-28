// source-preservation.test.mjs - designer edits must never destroy source.
//
// Regression tests for the P0 source-destruction bugs:
//   * one designer click (even a selection) regenerated the whole .ot file,
//     deleting functions, variables, comments and formatting;
//   * every save overwrote styles.css with whatever the in-memory CSS model
//     held, usually a blank template.
// Each test reads a real-looking file into the designer model, makes one
// designer change, and asserts that ONLY the affected text changed.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createScratchFolder } from './test-scratch.mjs';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const load = rel => import(pathToFileURL(path.join(studioRoot, 'js', ...rel.split('/'))).href);

const { OtterUiModel } = await load('model/ui-model.js');
const { parseOtterSource } = await load('compiler/otter-parser.js');
const { snapshotDesign, spliceDesignIntoSource, designMatchesBaseline, renameIdentifier } = await load('compiler/source-splice.js');
const { CssAstManager } = await load('compiler/css-ast.js');

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`  ✓ ${name}`);
}

// Read source into a fresh model and return what the tests need.
function open(source) {
  const model = new OtterUiModel();
  assert.equal(parseOtterSource(source, model), true, 'fixture must contain a UI');
  const baseline = snapshotDesign(model);
  const byName = name => [...model.components.values()].find(c => c.name === name);
  const splice = () => spliceDesignIntoSource(source, baseline, model);
  return { model, baseline, byName, splice };
}

// Lines that differ between two texts, as "before => after" strings.
function changedLines(before, after) {
  const a = before.split('\n');
  const b = after.split('\n');
  const out = [];
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    if (a[i] !== b[i]) out.push(`${a[i] ?? '<none>'} => ${b[i] ?? '<none>'}`);
  }
  return out;
}

const program = [
  '# Invoice tool - hand written, keep my comments!',
  'taxRate is 0.2',
  '',
  'to total with amount',
  '    give back amount * (1 + taxRate)',
  '.',
  '',
  'app is a window with title "Invoices", width 600, height 400',
  'amountBox is a text box with placeholder "Amount, in dollars"',
  'saveButton is a button with text "Save", background "#2563eb"',
  'status is a text with value "Ready"',
  '',
  'put amountBox, saveButton, status in app',
  '',
  'when saveButton is clicked',
  '    value of status is total(text of amountBox)',
  '.',
  '',
  'show app',
  ''
].join('\n');

console.log('Source preservation (designer -> .ot):');

await test('selecting a control does not change the source', () => {
  const { model, baseline, byName, splice } = open(program);
  model.select(byName('saveButton').id);
  assert.equal(designMatchesBaseline(baseline, model), true);
  assert.equal(splice(), program);
});

await test('changing one property rewrites only that phrase', () => {
  const { model, byName, splice } = open(program);
  model.setProperty(byName('saveButton').id, 'text', 'Save invoice');
  assert.deepEqual(changedLines(program, splice()), [
    'saveButton is a button with text "Save", background "#2563eb" => saveButton is a button with text "Save invoice", background "#2563eb"'
  ]);
});

await test('functions, variables and comments survive every kind of edit', () => {
  const { model, byName, splice } = open(program);
  model.setProperty(byName('app').id, 'title', 'Billing');
  model.addChild(model.rootId, 'button', { text: 'Clear' });
  model.removeComponent(byName('status').id);
  const out = splice();
  for (const kept of ['# Invoice tool - hand written, keep my comments!', 'taxRate is 0.2', 'to total with amount', '    give back amount * (1 + taxRate)', 'show app']) {
    assert.ok(out.includes(kept), `lost: ${kept}\n${out}`);
  }
});

await test('a string containing a comma is one property, and survives an edit', () => {
  const { model, byName, splice } = open(program);
  assert.equal(byName('amountBox').properties.placeholder, 'Amount, in dollars');
  model.setProperty(byName('saveButton').id, 'background', '#16a34a');
  assert.ok(splice().includes('amountBox is a text box with placeholder "Amount, in dollars"'));
});

await test('the author\'s key spelling is kept (`value` stays `value`)', () => {
  const { model, byName, splice } = open(program);
  model.setProperty(byName('status').id, 'text', 'Saved');
  assert.deepEqual(changedLines(program, splice()), [
    'status is a text with value "Ready" => status is a text with value "Saved"'
  ]);
});

await test('adding a control inserts one declaration and extends the put', () => {
  const { model, splice } = open(program);
  const added = model.addChild(model.rootId, 'button', { text: 'Clear' });
  const out = splice();
  const lines = out.split('\n');
  const declAt = lines.findIndex(l => l.startsWith(`${added.name} is a button with`));
  assert.ok(declAt > lines.indexOf('status is a text with value "Ready"'), out);
  assert.ok(lines.includes(`put amountBox, saveButton, status, ${added.name} in app`), out);
  assert.equal(lines.length, program.split('\n').length + 1, 'exactly one new line');
});

await test('removing a control removes its declaration, put entry and handlers only', () => {
  const { model, byName, splice } = open(program);
  model.removeComponent(byName('saveButton').id);
  const out = splice();
  assert.ok(!out.includes('saveButton'), out);
  assert.ok(out.includes('put amountBox, status in app'), out);
  assert.ok(out.includes('to total with amount'), out);
});

await test('renaming a control renames its uses but not strings or comments', () => {
  const { model, byName, splice } = open(program);
  model.setName(byName('status').id, 'statusLine');
  const out = splice();
  assert.ok(out.includes('statusLine is a text with value "Ready"'), out);
  assert.ok(out.includes('value of statusLine is total(text of amountBox)'), out);
  assert.ok(out.includes('put amountBox, saveButton, statusLine in app'), out);
  assert.equal(renameIdentifier('say "status" # status\nstatus2 is status', 'status', 'x'), 'say "status" # status\nstatus2 is x');
});

await test('reordering children rewrites only the put statement', () => {
  const { model, byName, splice } = open(program);
  model.moveChild(byName('status').id, model.rootId, 0);
  assert.deepEqual(changedLines(program, splice()), [
    'put amountBox, saveButton, status in app => put status, amountBox, saveButton in app'
  ]);
});

await test('editing a handler rewrites only that when block', () => {
  const { model, byName, splice } = open(program);
  model.setEvent(byName('saveButton').id, 'clicked', '    say "saving"\n    value of status is "Saved"');
  const expected = program.replace(
    '    value of status is total(text of amountBox)\n',
    '    say "saving"\n    value of status is "Saved"\n'
  );
  assert.equal(splice(), expected);
});

await test('undo after a splice restores the original text', () => {
  const { model, byName } = open(program);
  let baseline = snapshotDesign(model);
  model.setProperty(byName('saveButton').id, 'text', 'Go');
  const edited = spliceDesignIntoSource(program, baseline, model);
  baseline = snapshotDesign(model);
  model.undo();
  assert.equal(spliceDesignIntoSource(edited, baseline, model), program);
});

await test('block-form declarations are edited in place', () => {
  const source = [
    'app is a page',
    '    title is "Portal"',
    '    width is 680',
    '.',
    '',
    'go is a button',
    '    text is "Go"',
    '.',
    '',
    'put go in app',
    'show app',
    ''
  ].join('\n');
  const { model, byName, splice } = open(source);
  model.setProperty(byName('go').id, 'text', 'Launch');
  model.setProperty(byName('go').id, 'foreground', '#fde047');
  const out = splice();
  assert.deepEqual(changedLines(source, out).slice(0, 2), [
    '    text is "Go" =>     text is "Launch"',
    '. =>     foreground is "#fde047"'
  ]);
  assert.ok(out.includes('app is a page'), 'page must not be rewritten as window');
});

await test('CRLF files stay CRLF', () => {
  const crlf = program.replace(/\n/g, '\r\n');
  const { model, byName, splice } = open(crlf);
  model.setProperty(byName('saveButton').id, 'text', 'Go');
  model.addChild(model.rootId, 'button', { text: 'More' });
  const out = splice();
  assert.equal(out.split('\n').filter(l => !l.endsWith('\r')).length, 1, 'only the final empty line lacks \\r');
});

await test('a designer change to a console program appends UI instead of replacing it', () => {
  const consoleProgram = 'say "Hello"\n';
  const model = new OtterUiModel();
  assert.equal(parseOtterSource(consoleProgram, model), false);
  const out = spliceDesignIntoSource(consoleProgram, null, model);
  assert.ok(out.startsWith('say "Hello"\n'), out);
});

console.log('\nCSS preservation (designer -> stylesheet):');

const stylesheet = [
  '/* Brand palette - do not reformat */',
  ':root { --brand: #2563eb; }',
  '',
  '@media (max-width: 600px) {',
  '  #saveButton { width: 100%; }',
  '}',
  '',
  '#saveButton{background:url("data:image/png;base64,AAA;BBB");color:white}',
  '#status {',
  '  color: gray;',
  '}',
  ''
].join('\n');

await test('generateCss returns the stylesheet unchanged when nothing was edited', () => {
  const css = new CssAstManager(stylesheet);
  assert.equal(css.generateCss(), stylesheet);
  assert.equal(css.dirty, false);
});

await test('editing one rule leaves every other rule byte-identical', () => {
  const css = new CssAstManager(stylesheet);
  css.setProperty('#status', 'color', 'green');
  assert.equal(css.dirty, true);
  const out = css.generateCss();
  for (const kept of ['/* Brand palette - do not reformat */', ':root { --brand: #2563eb; }', '@media (max-width: 600px) {\n  #saveButton { width: 100%; }\n}', '#saveButton{background:url("data:image/png;base64,AAA;BBB");color:white}']) {
    assert.ok(out.includes(kept), `lost: ${kept}\n${out}`);
  }
  assert.ok(out.includes('color: green'), out);
});

await test('a semicolon inside a url() or string does not split a declaration', () => {
  const css = new CssAstManager(stylesheet);
  assert.equal(css.getProperty('#saveButton', 'background'), 'url("data:image/png;base64,AAA;BBB")');
  css.setProperty('#saveButton', 'color', 'black');
  assert.ok(css.generateCss().includes('#saveButton{background:url("data:image/png;base64,AAA;BBB");color: black}'), css.generateCss());
});

await test('a new rule is appended without touching existing text', () => {
  const css = new CssAstManager(stylesheet);
  css.setProperty('#clearButton', 'margin', '4px');
  const out = css.generateCss();
  assert.ok(out.startsWith(stylesheet.replace(/\n$/, '')), out);
  assert.ok(out.includes('#clearButton {\n    margin: 4px;\n}'), out);
});

console.log('\nServer refuses blind overwrites:');

// A private server on its own port, writing only into a git-ignored scratch
// folder that is removed when the test exits.
const repoRoot = path.resolve(studioRoot, '..');
const scratch = createScratchFolder(repoRoot, 'source-preservation');
const port = 4800 + (process.pid % 500);
const baseUrl = `http://127.0.0.1:${port}`;
const server = spawn(process.execPath, ['serve.mjs'], {
  cwd: studioRoot,
  env: { ...process.env, OTTER_STUDIO_PORT: String(port) },
  stdio: 'ignore'
});
process.on('exit', () => server.kill());

for (let attempt = 0; ; attempt++) {
  try { if ((await fetch(`${baseUrl}/`)).ok) break; } catch {}
  // 15 s: a cold Node start on Windows after the launch tests can take several seconds.
  if (attempt > 150) throw new Error('Studio server did not start');
  await new Promise(r => setTimeout(r, 100));
}
const post = (route, body) => fetch(`${baseUrl}${route}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(body)
});

try {
  const existing = `${scratch.rel}/keep.ot`;
  fs.writeFileSync(path.join(scratch.abs, 'keep.ot'), 'say "mine"\n', 'utf8');

  await test('saving over an existing file without its revision is a conflict', async () => {
    const res = await post('/api/file', { path: existing, content: 'say "Hello from Otter!"\n' });
    assert.equal(res.status, 409);
    assert.equal((await res.json()).conflict, true);
    assert.equal(fs.readFileSync(path.join(scratch.abs, 'keep.ot'), 'utf8'), 'say "mine"\n');
  });

  await test('a save with the current revision still works', async () => {
    const opened = await (await fetch(`${baseUrl}/api/file?path=${encodeURIComponent(existing)}`)).json();
    const res = await post('/api/file', { path: existing, content: 'say "edited"\n', expectedRevision: opened.revision });
    assert.equal(res.status, 200);
    assert.equal(fs.readFileSync(path.join(scratch.abs, 'keep.ot'), 'utf8'), 'say "edited"\n');
  });

  await test('a save with no path is refused (it used to overwrite a shipped example)', async () => {
    const res = await post('/api/file', { content: 'x' });
    assert.equal(res.status, 400);
  });

  await test('a path that only starts with the repository name is outside it', async () => {
    const sibling = `../${path.basename(repoRoot)}-studio-test-${process.pid}/x.ot`;
    const res = await post('/api/file', { path: sibling, content: 'x' });
    assert.equal(res.status, 403);
    assert.equal(fs.existsSync(path.resolve(repoRoot, sibling)), false);
  });

  await test('creating a project over an existing one is refused', async () => {
    const first = await post('/api/create-project', { name: 'demo', baseDir: scratch.rel, archetype: 'desktop', code: 'say "original"\n', css: '#a { color: red; }\n' });
    assert.equal(first.status, 200);
    const again = await post('/api/create-project', { name: 'demo', baseDir: scratch.rel, archetype: 'desktop', code: 'say "template"\n', css: '' });
    assert.equal(again.status, 409);
    const dir = path.join(scratch.abs, 'demo');
    assert.equal(fs.readFileSync(path.join(dir, 'main.ot'), 'utf8'), 'say "original"\n');
    assert.equal(fs.readFileSync(path.join(dir, 'styles.css'), 'utf8'), '#a { color: red; }\n');
  });
} finally {
  server.kill();
}

console.log(`\nSource preservation tests passed: ${passed}.`);
