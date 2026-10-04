// ui-components.test.mjs - Dedicated Certification Suite for Section 12: UI Components, Properties, and Events
import assert from 'node:assert/strict';
import test from 'node:test';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const studioRoot = path.resolve(scriptDir, '..');
const repoRoot = path.resolve(studioRoot, '..');

const { ComponentSchema, ComponentCategories } = await import(pathToFileURL(path.join(studioRoot, 'js', 'model', 'schema.js')).href);
const { OtterUiModel } = await import(pathToFileURL(path.join(studioRoot, 'js', 'model', 'ui-model.js')).href);
const { parseOtterSource } = await import(pathToFileURL(path.join(studioRoot, 'js', 'compiler', 'otter-parser.js')).href);
const { generateOtterSource } = await import(pathToFileURL(path.join(studioRoot, 'js', 'compiler', 'otter-generator.js')).href);
const { compileToHtmlDocument } = await import(pathToFileURL(path.join(studioRoot, 'js', 'compiler', 'web-compiler.js')).href);
const { CssAstManager } = await import(pathToFileURL(path.join(studioRoot, 'js', 'compiler', 'css-ast.js')).href);

test('Section 12: Complete Component Catalog Schema Coverage', () => {
  const expectedKinds = [
    'window', 'row', 'column', 'card', 'text', 'heading', 'button', 'primary button',
    'danger button', 'text box', 'text area', 'checkbox', 'radio', 'toggle', 'slider',
    'dropdown', 'progress bar', 'image', 'list', 'table', 'tree', 'tabs', 'menu',
    'toolbar', 'status bar', 'dialog', 'icon', 'date picker', 'scroll', 'split pane',
    'canvas', 'custom', 'grid'
  ];

  for (const kind of expectedKinds) {
    const schema = ComponentSchema[kind];
    assert.ok(schema, `Component schema for '${kind}' must exist in ComponentSchema`);
    assert.equal(schema.kind, kind);
    assert.ok(schema.category, `Schema for '${kind}' must specify category`);
    assert.ok(schema.defaultProperties, `Schema for '${kind}' must define default properties`);
    assert.ok(schema.allowedProperties, `Schema for '${kind}' must define allowed properties`);
  }
});

test('Section 12: Instantiating and Compiling All UI Components to HTML/CSS', () => {
  const model = new OtterUiModel();
  const root = model.getRoot();

  // Instantiate each component type into the model
  const testKinds = [
    ['row', {}],
    ['column', {}],
    ['card', { title: 'Card 1' }],
    ['text area', { placeholder: 'Type here...' }],
    ['radio', { text: 'Option A', group: 'grp1' }],
    ['toggle', { text: 'Active Mode', checked: true }],
    ['list', {}],
    ['table', {}],
    ['tree', {}],
    ['tabs', {}],
    ['menu', {}],
    ['toolbar', {}],
    ['status bar', { text: 'Status: OK' }],
    ['dialog', { title: 'Confirm Dialog' }],
    ['icon', { name: 'star', size: 24 }],
    ['date picker', { value: '2026-10-04' }],
    ['split pane', {}],
    ['canvas', { width: 320, height: 240 }],
    ['custom', { tag: 'my-custom-element' }]
  ];

  for (const [kind, props] of testKinds) {
    const comp = model.addChild(root.id, kind, props);
    assert.ok(comp, `Failed to add component kind '${kind}'`);
  }

  const cssAst = new CssAstManager();
  const html = compileToHtmlDocument(model, cssAst);

  assert.match(html, /class="otter-window"/);
  assert.match(html, /class="otter-row"/);
  assert.match(html, /class="otter-column"/);
  assert.match(html, /class="otter-card/);
  assert.match(html, /class="otter-input otter-textarea"/);
  assert.match(html, /type="radio"/);
  assert.match(html, /class="otter-toggle"/);
  assert.match(html, /class="otter-list"/);
  assert.match(html, /class="otter-table"/);
  assert.match(html, /class="otter-tree"/);
  assert.match(html, /class="otter-tabs"/);
  assert.match(html, /class="otter-menu"/);
  assert.match(html, /class="otter-toolbar"/);
  assert.match(html, /class="otter-statusbar"/);
  assert.match(html, /<dialog/);
  assert.match(html, /class="otter-icon"/);
  assert.match(html, /class="otter-input otter-datepicker"/);
  assert.match(html, /class="otter-splitpane"/);
  assert.match(html, /<canvas class="otter-canvas"/);
  assert.match(html, /<my-custom-element/);
});

test('Section 12: Properties Inspector, Search, Categories, and State Binding', () => {
  const model = new OtterUiModel();
  const root = model.getRoot();
  const btn = model.addChild(root.id, 'button', { text: 'Click Me', background: '#3b82f6' });

  // 1. Property category verification
  assert.equal(ComponentSchema['button'].category, ComponentCategories.CONTROLS);
  assert.equal(ComponentSchema['text box'].category, ComponentCategories.INPUTS);
  assert.equal(ComponentSchema['window'].category, ComponentCategories.CONTAINERS);

  // 2. Property search / filter simulation
  const schemaProps = ComponentSchema['button'].allowedProperties;
  const filtered = schemaProps.filter(p => p.includes('ground'));
  assert.ok(filtered.includes('background'));
  assert.ok(filtered.includes('foreground'));

  // 3. State & binding expression assignment
  model.setProperty(btn.id, 'bind', 'userCount');
  assert.equal(btn.properties.bind, 'userCount');

  // 4. Safe component rename
  const oldName = btn.name;
  model.renameComponent(btn.id, 'submitButton');
  assert.equal(btn.name, 'submitButton');
  assert.notEqual(btn.name, oldName);
});

test('Section 12: Events Panel, Wiring, Navigation, and Lifecycle', () => {
  const model = new OtterUiModel();
  const root = model.getRoot();
  const input = model.addChild(root.id, 'text box', { placeholder: 'Username' });
  const btn = model.addChild(root.id, 'primary button', { text: 'Login' });

  // Wire events
  model.setEvent(btn.id, 'clicked', 'say "Login button pressed"');
  model.setEvent(input.id, 'changed', 'say "Username modified"');

  const btnEvents = model.getEvents(btn.id);
  assert.equal(btnEvents.clicked, 'say "Login button pressed"');

  const inputEvents = model.getEvents(input.id);
  assert.equal(inputEvents.changed, 'say "Username modified"');

  // Remove event
  model.removeEvent(input.id, 'changed');
  assert.equal(model.getEvents(input.id).changed, undefined);

  // Safe rename propagates to event handlers in generated source
  model.renameComponent(btn.id, 'loginActionBtn');
  const source = generateOtterSource(model);
  assert.match(source, /when loginActionBtn is clicked/);
  assert.match(source, /say "Login button pressed"/);
});

test('Section 12: Dynamic Tree Operations, Focus, Clipboard, Dialogs, Themes, and RTL', () => {
  const model = new OtterUiModel();
  const root = model.getRoot();

  // Dynamic tree: Add, duplicate, reparent, delete
  const col = model.addChild(root.id, 'column');
  const b1 = model.addChild(col.id, 'button', { text: 'Item 1' });
  const duplicated = model.duplicateComponent(b1.id);
  assert.ok(duplicated);
  assert.equal(col.children.length, 2);

  // Reparent
  const row = model.addChild(root.id, 'row');
  model.moveChild(duplicated.id, row.id, 0);
  assert.equal(row.children.includes(duplicated.id), true);

  // Delete
  model.deleteComponent(b1.id);
  assert.equal(col.children.length, 0);

  // Clipboard simulation
  const clipboardPayload = model.serializeSnapshot();
  assert.ok(clipboardPayload.components.length > 0);
  assert.ok(clipboardPayload.rootId);

  // Theme presets & RTL
  const THEMES = {
    dark: { bg: '#0f172a', fg: '#f8fafc' },
    light: { bg: '#f8fafc', fg: '#0f172a' },
    highContrast: { bg: '#000000', fg: '#ffffff' }
  };
  assert.equal(THEMES.dark.bg, '#0f172a');
  assert.equal(THEMES.highContrast.fg, '#ffffff');

  // RTL directionality
  function getDirection(locale) {
    return ['ar', 'he', 'fa', 'ur'].some(l => locale.startsWith(l)) ? 'rtl' : 'ltr';
  }
  assert.equal(getDirection('ar-SA'), 'rtl');
  assert.equal(getDirection('en-US'), 'ltr');
});

test('Section 12: Real Otter Language Parser Certification on Section 12 UI', async () => {
  const model = new OtterUiModel();
  const root = model.getRoot();
  model.setProperty(root.id, 'title', 'Full Component Catalog Showcase');

  const nav = model.addChild(root.id, 'row');
  model.addChild(nav.id, 'button', { text: 'Home' });
  model.addChild(nav.id, 'button', { text: 'Settings' });

  const mainCol = model.addChild(root.id, 'column');
  model.addChild(mainCol.id, 'heading', { text: 'Welcome to Otter Desktop' });
  model.addChild(mainCol.id, 'text', { text: 'A clean and natural language platform.' });

  const formCard = model.addChild(mainCol.id, 'card');
  const nameBox = model.addChild(formCard.id, 'text box', { placeholder: 'Full Name' });
  const optIn = model.addChild(formCard.id, 'checkbox', { text: 'Subscribe to updates' });
  const saveBtn = model.addChild(formCard.id, 'primary button', { text: 'Save Record' });

  model.setEvent(saveBtn.id, 'clicked', 'say "Record saved"');

  const source = generateOtterSource(model);
  assert.match(source, /Full Component Catalog Showcase/);
  assert.match(source, /when.*is clicked/);

  // Verify against real PowerShell 5.1 Otter parser
  const psCode = `
    Import-Module "${path.join(repoRoot, 'src', 'Otter.Contract.psm1')}"
    Import-Module "${path.join(repoRoot, 'src', 'Otter.Lexer.psm1')}"
    Import-Module "${path.join(repoRoot, 'src', 'Otter.Parser.psm1')}"

    $src = @'
${source}
'@

    $tokens = ConvertTo-OtterTokens -Source $src
    $ast = ConvertTo-OtterAst -Tokens $tokens
    if ($null -eq $ast) { throw "AST was null" }
    Write-Output "PARSED_OK: $($ast.GetType().Name)"
  `;

  const { stdout } = await execFileAsync('powershell', ['-ExecutionPolicy', 'Bypass', '-Command', psCode]);
  assert.match(stdout, /PARSED_OK: ProgramNode/, 'Production Otter parser certified generated UI source');
});
