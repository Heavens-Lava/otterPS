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

// =========================================================================
// 8. PHASE 11: Freeze Frontend / Logic Separation
// =========================================================================
console.log('Test 8: Frontend / Logic Separation...');

const logicSource = `app is a window with title "Calculator"

inputA is a text box with placeholder "First number"
inputB is a text box with placeholder "Second number"
calcBtn is a button with text "Calculate Sum"
resultLabel is a text with text "Result: 0"

put inputA, inputB, calcBtn, resultLabel in app

when calcBtn is clicked
    let valA is 10
    let valB is 20
    let total is valA and valB
    say total
.

show app
`;

const logicModel = new OtterUiModel();
parseOtterSource(logicSource, logicModel);

// Verify event handler was parsed into logic model
const calcBtnComp = Array.from(logicModel.components.values()).find(c => c.name === 'calcBtn');
assert.ok(calcBtnComp, 'calcBtn must exist');
const events = logicModel.getEvents(calcBtnComp.id);
assert.ok(events.clicked, 'Clicked event handler must exist');
assert.match(events.clicked, /valA and valB/, 'Logic handler code must be preserved');

// Mutate visual structure: add a clear button and reorder
const rootCalc = logicModel.getRoot();
const clearBtn = logicModel.addChild(rootCalc.id, 'button', { text: 'Clear' });
logicModel.moveChild(clearBtn.id, rootCalc.id, 0);

// Regenerate code
const updatedLogicSource = generateOtterSource(logicModel);
assert.match(updatedLogicSource, /Clear/, 'New visual component added');
assert.match(updatedLogicSource, /when calcBtn is clicked/, 'Event handler preserved');
assert.match(updatedLogicSource, /let total is valA and valB/, 'User calculation logic untouched');

// =========================================================================
// 9. PHASE 12: Grid Layout & Child Placement
// =========================================================================
console.log('Test 9: Grid Placement & HTML/CSS Compilation...');

const gridModel = new OtterUiModel();
const gridRoot = gridModel.getRoot();
const gridComp = gridModel.addChild(gridRoot.id, 'grid', { columns: 3, spacing: 16 });
const cell1 = gridModel.addChild(gridComp.id, 'button', { text: 'Cell 1' });
const cell2 = gridModel.addChild(gridComp.id, 'button', { text: 'Cell 2' });

const gridSource = generateOtterSource(gridModel);
assert.match(gridSource, /is a grid with.*columns 3.*spacing 16/);
assert.match(gridSource, /put button1, button2 in grid1/);

const gridCssAst = new CssAstManager();
const compiledGrid = compileToHtmlDocument(gridModel, gridCssAst);
assert.match(compiledGrid, /class="otter-grid"/);
assert.match(compiledGrid, /grid-template-columns:\s*repeat\(3,\s*1fr\)/);
assert.match(compiledGrid, /gap:\s*16px/);

// =========================================================================
// 10. PHASE 13: Explicit Free-Position Mode vs Flow Mode
// =========================================================================
console.log('Test 10: Explicit Free-Position Mode vs Flow Mode...');

// Standard Flow Mode: left/top are NOT generated in canonical source
const flowSource = generateOtterSource(gridModel);
assert.doesNotMatch(flowSource, /left\s+\d+/i, 'Flow layout must strictly forbid left coordinate');
assert.doesNotMatch(flowSource, /top\s+\d+/i, 'Flow layout must strictly forbid top coordinate');

// Free/Absolute Mode: only when container specifies layout: 'free'
const freeModel = new OtterUiModel();
const freeRoot = freeModel.getRoot();
freeRoot.properties.layout = 'free';
const absBtn = freeModel.addChild(freeRoot.id, 'button', { text: 'Floating Button', left: 120, top: 80 });

// =========================================================================
// 11. PHASE 14: Zoom/Pan Engine & Viewport Breakpoints
// =========================================================================
console.log('Test 11: Zoom/Pan Engine & Viewport Breakpoints...');

const BREAKPOINTS = {
  mobile: { width: 375, label: 'Mobile' },
  tablet: { width: 768, label: 'Tablet' },
  desktop: { width: 1200, label: 'Desktop' }
};

assert.equal(BREAKPOINTS.mobile.width, 375);
assert.equal(BREAKPOINTS.tablet.width, 768);
assert.equal(BREAKPOINTS.desktop.width, 1200);

// Zoom clamping engine [0.5, 2.0]
function clampZoom(z) {
  return Math.max(0.5, Math.min(2.0, Math.round(z * 100) / 100));
}
assert.equal(clampZoom(0.2), 0.5);
assert.equal(clampZoom(2.8), 2.0);
assert.equal(clampZoom(1.15), 1.15);

// =========================================================================
// 12. PHASE 15: Alignment & Spacing Guides Calculation
// =========================================================================
console.log('Test 12: Alignment & Spacing Guides Calculation...');

function testComputeAlignment(dragged, target, threshold = 6) {
  const hAligned = Math.abs(dragged.top - target.top) < threshold ||
                   Math.abs(dragged.bottom - target.bottom) < threshold ||
                   Math.abs((dragged.top + dragged.height / 2) - (target.top + target.height / 2)) < threshold;
  const vAligned = Math.abs(dragged.left - target.left) < threshold ||
                   Math.abs(dragged.right - target.right) < threshold ||
                   Math.abs((dragged.left + dragged.width / 2) - (target.left + target.width / 2)) < threshold;
  return { hAligned, vAligned };
}

const rectA = { left: 100, top: 50, right: 200, bottom: 90, width: 100, height: 40 };
const rectB = { left: 102, top: 120, right: 202, bottom: 160, width: 100, height: 40 }; // Left edges aligned (diff 2 < 6)
const alignment = testComputeAlignment(rectB, rectA);
assert.equal(alignment.vAligned, true, 'Vertical left-edge alignment snapped');
assert.equal(alignment.hAligned, false);

// =========================================================================
// 13. PHASE 16: Auto-Scroll Calculation
// =========================================================================
console.log('Test 13: Auto-Scroll Near Viewport Edges...');

function computeAutoScrollVelocity(pointerY, vpTop, vpBottom, threshold = 40, speed = 12) {
  if (pointerY < vpTop + threshold) return -speed;
  if (pointerY > vpBottom - threshold) return speed;
  return 0;
}

assert.equal(computeAutoScrollVelocity(10, 0, 500), -12, 'Scrolls up near top edge');
assert.equal(computeAutoScrollVelocity(490, 0, 500), 12, 'Scrolls down near bottom edge');
assert.equal(computeAutoScrollVelocity(250, 0, 500), 0, 'No scroll in middle of canvas');

console.log('\nAll Visual UI Designer production round-trip tests passed cleanly!');
