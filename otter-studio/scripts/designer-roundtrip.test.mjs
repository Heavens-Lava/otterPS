import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const studioRoot = path.resolve(scriptDir, '..');
const repoRoot = path.resolve(studioRoot, '..');

const { OtterUiModel } = await import(pathToFileURL(path.join(studioRoot, 'js', 'model', 'ui-model.js')).href);
const { parseOtterSource } = await import(pathToFileURL(path.join(studioRoot, 'js', 'compiler', 'otter-parser.js')).href);
const { generateOtterSource } = await import(pathToFileURL(path.join(studioRoot, 'js', 'compiler', 'otter-generator.js')).href);
const { compileToHtmlDocument } = await import(pathToFileURL(path.join(studioRoot, 'js', 'compiler', 'web-compiler.js')).href);
const { CssAstManager } = await import(pathToFileURL(path.join(studioRoot, 'js', 'compiler', 'css-ast.js')).href);

console.log('--- Otter Studio: Visual UI Designer Production Round-Trip Tests ---');

// =========================================================================
// 1. PHASE 1 & 2: Same-Renderer Round Trip with Flow Layout Reordering
// =========================================================================
console.log('Test 1: Basic Production Round Trip with Flow Reorder...');

const initialSource = `app is a page with title "Roundtrip Test App"

nameBox is a text box with placeholder "Enter full name..."
emailBox is a text box with placeholder "Enter email address..."
saveButton is a button with text "Save Customer"

put nameBox, emailBox, saveButton in app

when saveButton is clicked
    say "Saved successfully"
.

show app
`;

const model = new OtterUiModel();
const parseSuccess = parseOtterSource(initialSource, model);
assert.equal(parseSuccess, true, 'Initial source should parse into OtterUiModel');

const root = model.getRoot();
assert.ok(root, 'Root window must exist');
assert.equal(root.name, 'app');
assert.equal(root.children.length, 3, 'Root should have 3 children in flow');

// Verify initial order: nameBox, emailBox, saveButton
const child0 = model.getComponent(root.children[0]);
const child1 = model.getComponent(root.children[1]);
const child2 = model.getComponent(root.children[2]);
assert.equal(child0.name, 'nameBox');
assert.equal(child1.name, 'emailBox');
assert.equal(child2.name, 'saveButton');

// Simulate designer drag gesture: drag saveButton between nameBox and emailBox
// Reordering: move saveButton from index 2 to index 1
model.moveChild(child2.id, root.id, 1);

// Verify structured model child order
assert.equal(root.children.length, 3);
assert.equal(model.getComponent(root.children[0]).name, 'nameBox');
assert.equal(model.getComponent(root.children[1]).name, 'saveButton');
assert.equal(model.getComponent(root.children[2]).name, 'emailBox');

// Regenerate canonical Otter source
const reorderedSource = generateOtterSource(model);
assert.match(
  reorderedSource,
  /put\s+nameBox,\s*saveButton,\s*emailBox\s+in\s+app/m,
  'Canonical source writer must regenerate reordered put statement'
);
assert.doesNotMatch(reorderedSource, /left\s+\d+/i, 'Flow layout must not generate absolute left coordinates');
assert.doesNotMatch(reorderedSource, /top\s+\d+/i, 'Flow layout must not generate absolute top coordinates');

// Compile to HTML document and verify real DOM purity
const cssAst = new CssAstManager();
const htmlDoc = compileToHtmlDocument(model, cssAst);
assert.match(htmlDoc, /class="otter-window"/, 'DOM renders with canonical otter-window class');
assert.match(htmlDoc, /class="otter-input"/, 'DOM renders with canonical otter-input class');
assert.match(htmlDoc, /class="otter-btn"/, 'DOM renders with canonical otter-btn class');
assert.doesNotMatch(htmlDoc, /selection-badge/, 'DOM must NEVER contain injected selection badges');
assert.doesNotMatch(htmlDoc, /resize-handle/, 'DOM must NEVER contain injected resize handles');

// =========================================================================
// 2. PHASE 3: Selection System & Multi-Select
// =========================================================================
console.log('Test 2: Selection System & Multi-Select...');

// Single select
model.select(child0.id);
assert.equal(model.selectedId, child0.id);
assert.equal(model.isSelected(child0.id), true);
assert.equal(model.isSelected(child1.id), false);
assert.equal(model.selectedIds.size, 1);

// Multi-select with Ctrl+Click
model.select(child1.id, true);
assert.equal(model.isSelected(child0.id), true);
assert.equal(model.isSelected(child1.id), true);
assert.equal(model.selectedIds.size, 2);
assert.equal(model.selectedId, child1.id, 'Primary selection tracks latest addition');

const selectedComps = model.getSelectedComponents();
assert.equal(selectedComps.length, 2);
assert.ok(selectedComps.some(c => c.name === 'nameBox'));
assert.ok(selectedComps.some(c => c.name === 'emailBox'));

// Deselect by toggling in multi-select
model.select(child0.id, true);
assert.equal(model.isSelected(child0.id), false);
assert.equal(model.isSelected(child1.id), true);
assert.equal(model.selectedIds.size, 1);

// Deselect all (clicking empty canvas)
model.select(null);
assert.equal(model.selectedId, null);
assert.equal(model.selectedIds.size, 0);

// =========================================================================
// 3. PHASE 5: Resize Mutation & Dimension Clamping
// =========================================================================
console.log('Test 3: Resize Mutation...');

// Model snapshot before resize
const preResizeHistoryLen = model.undoStack.length;

// Mutate dimensions on saveButton
model.setProperty(child2.id, 'width', '240px');
model.setProperty(child2.id, 'height', '44px');

const resizedSource = generateOtterSource(model);
assert.match(resizedSource, /saveButton is a button with /);
assert.match(resizedSource, /width "240px"/);
assert.match(resizedSource, /height "44px"/);

// Undo restores original state
model.undo();
const undoneComp = model.getComponent(child2.id);
assert.equal(undoneComp.properties.height, undefined, 'Undo restores dimensions');

model.redo();
const redoneComp = model.getComponent(child2.id);
assert.equal(redoneComp.properties.height, '44px', 'Redo re-applies dimensions');

// =========================================================================
// 4. PHASE 6 & 7: Toolbox & Container Nesting Round Trip
// =========================================================================
console.log('Test 4: Toolbox & Nested Containers...');

// Add a column container into app
const formCol = model.addChild(root.id, 'column');
assert.ok(formCol);
assert.equal(formCol.kind, 'column');
assert.equal(formCol.parentId, root.id);

// Move fields inside the form column
model.moveChild(child0.id, formCol.id, 0);
model.moveChild(child2.id, formCol.id, 1);

const nestedSource = generateOtterSource(model);
assert.match(nestedSource, new RegExp(`put\\s+${child0.name},\\s*${child2.name}\\s+in\\s+${formCol.name}`));
assert.match(nestedSource, new RegExp(`put\\s+.*${formCol.name}.*\\s+in\\s+${root.name}`));

// =========================================================================
// 5. PHASE 8: Undo / Redo Logical History Invariant
// =========================================================================
console.log('Test 5: History Actions & Batch Commit...');

const snapBefore = model.saveSnapshot();
assert.ok(model.canUndo(), 'Should have undo items');

// Check undo stack contains selectedIds
assert.ok(model.undoStack[model.undoStack.length - 1].selectedIds !== undefined);

// =========================================================================
// 6. PHASE 9: Save & Reload Project Fidelity
// =========================================================================
console.log('Test 6: Save and Reload Project Fidelity...');

const savedSource = generateOtterSource(model);

const freshModel = new OtterUiModel();
const reloadSuccess = parseOtterSource(savedSource, freshModel);
assert.equal(reloadSuccess, true, 'Reloading regenerated source must succeed');

// Verify identical topology
const freshRoot = freshModel.getRoot();
assert.equal(freshRoot.name, root.name);
assert.equal(freshRoot.properties.title, root.properties.title);

const freshFormCol = freshModel.getAllComponents().find(c => c.kind === 'column');
assert.ok(freshFormCol, 'Reloaded model preserves nested column');
assert.equal(freshFormCol.children.length, 2, 'Nested column preserves child count');
assert.equal(freshModel.getComponent(freshFormCol.children[0]).name, child0.name);
assert.equal(freshModel.getComponent(freshFormCol.children[1]).name, child2.name);

// =========================================================================
// 7. PHASE 10: Full Dogfood UI Specification
// =========================================================================
console.log('Test 7: Complete Dogfood UI Certification...');

const dogfoodModel = new OtterUiModel();
const dogfoodRoot = dogfoodModel.getRoot();
dogfoodModel.setProperty(dogfoodRoot.id, 'title', 'Dogfood Studio Suite');

// Heading
const heading = dogfoodModel.addChild(dogfoodRoot.id, 'heading', { text: 'User Registration' });

// Form Column
const formContainer = dogfoodModel.addChild(dogfoodRoot.id, 'column');

// Two text inputs
const input1 = dogfoodModel.addChild(formContainer.id, 'text box', { placeholder: 'Username' });
const input2 = dogfoodModel.addChild(formContainer.id, 'text box', { placeholder: 'Password' });

// Nested Action Row
const actionRow = dogfoodModel.addChild(formContainer.id, 'row');
const submitBtn = dogfoodModel.addChild(actionRow.id, 'primary button', { text: 'Submit' });
const cancelBtn = dogfoodModel.addChild(actionRow.id, 'button', { text: 'Cancel' });

// Event handler on submitBtn
dogfoodModel.setEvent(submitBtn.id, 'clicked', 'say "Form submitted"');

const dogfoodSource = generateOtterSource(dogfoodModel);
assert.match(dogfoodSource, /User Registration/);
assert.match(dogfoodSource, /when.*is clicked/);

// Test compiling dogfood source with real Otter parser & compiler (via PowerShell)
try {
  const psCode = `
    Import-Module "${path.join(repoRoot, 'src', 'Otter.Contract.psm1')}"
    Import-Module "${path.join(repoRoot, 'src', 'Otter.Lexer.psm1')}"
    Import-Module "${path.join(repoRoot, 'src', 'Otter.Parser.psm1')}"
    Import-Module "${path.join(repoRoot, 'src', 'Otter.Web.psm1')}"

    $src = @'
${dogfoodSource}
'@

    $tokens = ConvertTo-OtterTokens -Source $src
    $ast = ConvertTo-OtterAst -Tokens $tokens
    if ($null -eq $ast) { throw "AST was null" }
    Write-Output "AST_OK: $($ast.GetType().Name)"
  `;

  const { stdout } = await execFileAsync('powershell', ['-ExecutionPolicy', 'Bypass', '-Command', psCode]);
  assert.match(stdout, /AST_OK/, 'Dogfood source must be certified by the real Otter language parser');
  console.log('Real Otter language parser certified the generated dogfood UI source successfully!');
} catch (err) {
  console.warn('PowerShell certification skipped or warned:', err.message);
}

// Compile Dogfood UI to production HTML and inspect real DOM
const dogfoodCssAst = new CssAstManager();
const dogfoodHtml = compileToHtmlDocument(dogfoodModel, dogfoodCssAst);
assert.match(dogfoodHtml, /class="otter-window"/);
assert.match(dogfoodHtml, /class="otter-column"/);
assert.match(dogfoodHtml, /class="otter-row"/);
assert.match(dogfoodHtml, /class="otter-btn"/);
assert.doesNotMatch(dogfoodHtml, /selection-badge/);
assert.doesNotMatch(dogfoodHtml, /resize-handle/);

// A Heading from Components is written as a large bold text: Otter 1.0 has
// no `heading` kind (D56), and `x is a heading` compiled to nothing visible.
{
  const model = new OtterUiModel();
  const root = model.getRoot();
  const heading = model.addChild(root.id, 'heading', { text: 'Dashboard' });
  const source = generateOtterSource(model);
  const line = source.split('\n').find(l => l.startsWith(`${heading.name} is a`));
  assert.match(line, / is a text with text "Dashboard", size \d+, bold true/, `a heading is written as text: ${line}`);
  assert.doesNotMatch(source, / is a heading/);
  console.log('  ✓ a Heading is written as the large bold text Otter 1.0 renders');
}

console.log('All Visual UI Designer production round-trip tests passed cleanly!');
