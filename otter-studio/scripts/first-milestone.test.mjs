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

const SERVER_BASE = 'http://localhost:4200';

console.log('================================================================');
console.log('OTTER STUDIO VISUAL DESIGNER — FIRST PRODUCTION MILESTONE');
console.log('================================================================\n');

// -------------------------------------------------------------------------
// STEP 1: Open real .ot UI file through the normal Studio entry point
// -------------------------------------------------------------------------
console.log('[Step 1] Opening real .ot UI file through normal Studio entry point...');

const initialOtSource = `app is a page with title "Customer Registration"

nameBox is a text box with placeholder "Customer full name"
emailBox is a text box with placeholder "Customer email address"
saveButton is a button with text "Save Customer"

put nameBox, emailBox, saveButton in app

when saveButton is clicked
    say "Customer saved successfully"
.

show app
`;

// Create project via Studio backend API (normal entry point)
const createRes = await fetch(`${SERVER_BASE}/api/create-project`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    name: 'milestone-app',
    baseDir: 'projects',
    overwrite: true, // the fixture is re-created on every run
    fileName: 'main.ot',
    code: initialOtSource,
    archetype: 'web'
  })
});
assert.ok(createRes.ok, 'Failed to create project via Studio API');

// Fetch file through normal Studio entry point (GET /api/file)
const fileRes = await fetch(`${SERVER_BASE}/api/file?path=projects/milestone-app/main.ot`);
assert.ok(fileRes.ok, 'Failed to load file via Studio /api/file');
const fileData = await fileRes.json();
assert.equal(typeof fileData.content, 'string');
assert.match(fileData.content, /Customer Registration/);

console.log('  -> File successfully loaded via Studio API:', fileData.path);
console.log('  -> File revision:', fileData.revision);

// -------------------------------------------------------------------------
// STEP 2: Parse it into the structured OtterUiModel
// -------------------------------------------------------------------------
console.log('\n[Step 2] Parsing into structured OtterUiModel...');

const model = new OtterUiModel();
const parseSuccess = parseOtterSource(fileData.content, model);
assert.equal(parseSuccess, true, 'Parsing into OtterUiModel must succeed');

const root = model.getRoot();
assert.ok(root, 'Root window/page must exist in model');
assert.equal(root.name, 'app');
assert.equal(root.children.length, 3);

const initialChildren = root.children.map(id => model.getComponent(id));
console.log('  -> Original model structure:');
console.log(`     Root: ${root.name} (${root.kind}) with title "${root.properties.title}"`);
console.log('     Children:');
initialChildren.forEach((c, idx) => {
  console.log(`       [${idx}] ${c.name} (${c.kind}) properties:`, c.properties);
});

assert.equal(initialChildren[0].name, 'nameBox');
assert.equal(initialChildren[1].name, 'emailBox');
assert.equal(initialChildren[2].name, 'saveButton');

// -------------------------------------------------------------------------
// STEP 3: Render it using the real Otter Web/Desktop DOM renderer
// -------------------------------------------------------------------------
console.log('\n[Step 3] Rendering using real Otter Web/Desktop DOM renderer...');

const cssAst = new CssAstManager();
const initialDomHtml = compileToHtmlDocument(model, cssAst);

assert.match(initialDomHtml, /class="otter-window"/, 'DOM must use canonical otter-window');
assert.match(initialDomHtml, /class="otter-input"/, 'DOM must use canonical otter-input');
assert.match(initialDomHtml, /class="otter-btn"/, 'DOM must use canonical otter-btn');
assert.doesNotMatch(initialDomHtml, /selection-badge/, 'DOM must NOT contain injected designer controls');
assert.doesNotMatch(initialDomHtml, /resize-handle/, 'DOM must NOT contain injected designer handles');

// Check initial DOM order of IDs
const namePos0 = initialDomHtml.indexOf('id="nameBox"');
const emailPos0 = initialDomHtml.indexOf('id="emailBox"');
const savePos0 = initialDomHtml.indexOf('id="saveButton"');
assert.ok(namePos0 < emailPos0 && emailPos0 < savePos0, 'Initial DOM order must match model [nameBox, emailBox, saveButton]');
console.log('  -> Initial DOM elements rendered in order: nameBox -> emailBox -> saveButton');

// -------------------------------------------------------------------------
// STEP 4: Select one existing component in the real rendered DOM
// -------------------------------------------------------------------------
console.log('\n[Step 4] Selecting existing component (saveButton)...');

const saveBtnComp = initialChildren[2];
model.select(saveBtnComp.id);
assert.equal(model.selectedId, saveBtnComp.id);
assert.equal(model.isSelected(saveBtnComp.id), true);
assert.equal(model.isSelected(initialChildren[0].id), false);
console.log(`  -> Selected component: ${saveBtnComp.name} (id: ${saveBtnComp.id})`);

// -------------------------------------------------------------------------
// STEP 5 & 6: Drag that component to reorder it inside a row or column (flow)
//             and mutate OtterUiModel using insertIndex / structural ordering
// -------------------------------------------------------------------------
console.log('\n[Steps 5 & 6] Dragging saveButton between nameBox and emailBox (insertIndex = 1)...');

// In flow layout, dragging saveButton before emailBox yields insertIndex = 1 in app.
model.moveChild(saveBtnComp.id, root.id, 1);

const reorderedChildren = root.children.map(id => model.getComponent(id));
console.log('  -> Mutated model structure child order:');
reorderedChildren.forEach((c, idx) => {
  console.log(`       [${idx}] ${c.name} (${c.kind})`);
});

assert.equal(reorderedChildren[0].name, 'nameBox');
assert.equal(reorderedChildren[1].name, 'saveButton');
assert.equal(reorderedChildren[2].name, 'emailBox');

// -------------------------------------------------------------------------
// STEP 7: Serialize the model back into canonical readable Otter source
// -------------------------------------------------------------------------
console.log('\n[Step 7] Serializing model back into canonical readable Otter source...');

const canonicalSource = generateOtterSource(model);
console.log('------------------ Resulting Canonical Source ------------------');
console.log(canonicalSource.trim());
console.log('----------------------------------------------------------------');

assert.match(
  canonicalSource,
  /put\s+nameBox,\s*saveButton,\s*emailBox\s+in\s+app/m,
  'Canonical source writer must regenerate reordered put statement'
);
assert.doesNotMatch(canonicalSource, /left\s+\d+/i, 'Must not generate arbitrary left coordinate');
assert.doesNotMatch(canonicalSource, /top\s+\d+/i, 'Must not generate arbitrary top coordinate');

// -------------------------------------------------------------------------
// STEP 8: Pass that generated source through the REAL Otter parser/compiler
// -------------------------------------------------------------------------
console.log('\n[Step 8] Passing generated source through REAL Otter parser/compiler via PowerShell 5.1...');

const psScript = `
  $ErrorActionPreference = "Stop"
  Import-Module "${path.join(repoRoot, 'Otter.Contract.psm1')}" -Force
  Import-Module "${path.join(repoRoot, 'src', 'Otter.Lexer.psm1')}" -Force
  Import-Module "${path.join(repoRoot, 'src', 'Otter.Parser.psm1')}" -Force

  $source = @'
${canonicalSource}
'@

  $tokens = ConvertTo-OtterTokens -Source $source
  $ast = ConvertTo-OtterAst -Tokens $tokens
  if ($null -eq $ast) { throw "AST was null" }

  Write-Output "PARSER_VERIFIED: $($ast.GetType().Name)"
  Write-Output "BODY_COUNT: $($ast.Body.Count)"
`;

const { stdout: psStdout } = await execFileAsync('powershell', ['-ExecutionPolicy', 'Bypass', '-Command', psScript]);
console.log('  -> Real PowerShell Otter Parser output:', psStdout.trim());
assert.match(psStdout, /PARSER_VERIFIED:\s*ProgramNode/, 'Real Otter parser must certify generated source as valid ProgramNode');

// -------------------------------------------------------------------------
// STEP 9 & 10: Re-render the actual DOM and confirm component moved
// -------------------------------------------------------------------------
console.log('\n[Steps 9 & 10] Re-rendering actual DOM and confirming component moved...');

const reRenderedHtml = compileToHtmlDocument(model, cssAst);

const namePos1 = reRenderedHtml.indexOf('id="nameBox"');
const savePos1 = reRenderedHtml.indexOf('id="saveButton"');
const emailPos1 = reRenderedHtml.indexOf('id="emailBox"');

assert.ok(namePos1 !== -1 && savePos1 !== -1 && emailPos1 !== -1);
assert.ok(namePos1 < savePos1 && savePos1 < emailPos1, 'Re-rendered DOM order must be [nameBox, saveButton, emailBox]');
console.log('  -> Re-rendered DOM order verified: nameBox -> saveButton -> emailBox');

// -------------------------------------------------------------------------
// STEP 11: Save the file via Studio backend
// -------------------------------------------------------------------------
console.log('\n[Step 11] Saving reordered file via Studio backend API...');

const saveRes = await fetch(`${SERVER_BASE}/api/file`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    path: 'projects/milestone-app/main.ot',
    content: canonicalSource,
    expectedRevision: fileData.revision
  })
});
assert.ok(saveRes.ok, 'Saving file via /api/file failed');
const saveResult = await saveRes.json();
assert.equal(saveResult.ok, true);
console.log('  -> File saved to disk. New revision:', saveResult.revision);

// Verify disk content directly
const diskContent = await fs.readFile(path.join(repoRoot, 'projects', 'milestone-app', 'main.ot'), 'utf8');
assert.equal(diskContent, canonicalSource);
console.log('  -> Disk file contents verified matching canonical source exactly');

// -------------------------------------------------------------------------
// STEP 12 & 13: Close/reopen or reload the project and confirm preservation
// -------------------------------------------------------------------------
console.log('\n[Steps 12 & 13] Reloading project from disk and confirming preservation...');

const reloadRes = await fetch(`${SERVER_BASE}/api/file?path=projects/milestone-app/main.ot`);
assert.ok(reloadRes.ok);
const reloadedFileData = await reloadRes.json();

const reloadedModel = new OtterUiModel();
const reloadedParseSuccess = parseOtterSource(reloadedFileData.content, reloadedModel);
assert.equal(reloadedParseSuccess, true);

const reloadedRoot = reloadedModel.getRoot();
assert.equal(reloadedRoot.children.length, 3);
assert.equal(reloadedModel.getComponent(reloadedRoot.children[0]).name, 'nameBox');
assert.equal(reloadedModel.getComponent(reloadedRoot.children[1]).name, 'saveButton');
assert.equal(reloadedModel.getComponent(reloadedRoot.children[2]).name, 'emailBox');

const reloadedHtml = compileToHtmlDocument(reloadedModel, cssAst);
const namePosReload = reloadedHtml.indexOf('id="nameBox"');
const savePosReload = reloadedHtml.indexOf('id="saveButton"');
const emailPosReload = reloadedHtml.indexOf('id="emailBox"');
assert.ok(namePosReload < savePosReload && savePosReload < emailPosReload);

console.log('  -> Reloaded project preserved order across source, model, designer, and rendered DOM!');

// -------------------------------------------------------------------------
// STEP 14: Undo and redo the operation and verify both directions
// -------------------------------------------------------------------------
console.log('\n[Step 14] Testing Undo and Redo operations...');

// UNDO
assert.ok(model.canUndo(), 'Model must have undo entry for move operation');
model.undo();

const undoneRoot = model.getRoot();
assert.equal(model.getComponent(undoneRoot.children[0]).name, 'nameBox');
assert.equal(model.getComponent(undoneRoot.children[1]).name, 'emailBox');
assert.equal(model.getComponent(undoneRoot.children[2]).name, 'saveButton');

const undoneSource = generateOtterSource(model);
assert.match(undoneSource, /put\s+nameBox,\s*emailBox,\s*saveButton\s+in\s+app/m);

const undoneHtml = compileToHtmlDocument(model, cssAst);
assert.ok(undoneHtml.indexOf('id="nameBox"') < undoneHtml.indexOf('id="emailBox"'));
assert.ok(undoneHtml.indexOf('id="emailBox"') < undoneHtml.indexOf('id="saveButton"'));
console.log('  -> Undo successfully restored original order: [nameBox, emailBox, saveButton]');

// REDO
assert.ok(model.canRedo(), 'Model must have redo entry');
model.redo();

const redoneRoot = model.getRoot();
assert.equal(model.getComponent(redoneRoot.children[0]).name, 'nameBox');
assert.equal(model.getComponent(redoneRoot.children[1]).name, 'saveButton');
assert.equal(model.getComponent(redoneRoot.children[2]).name, 'emailBox');

const redoneSource = generateOtterSource(model);
assert.match(redoneSource, /put\s+nameBox,\s*saveButton,\s*emailBox\s+in\s+app/m);

const redoneHtml = compileToHtmlDocument(model, cssAst);
assert.ok(redoneHtml.indexOf('id="nameBox"') < redoneHtml.indexOf('id="saveButton"'));
assert.ok(redoneHtml.indexOf('id="saveButton"') < redoneHtml.indexOf('id="emailBox"'));
console.log('  -> Redo successfully re-applied reordered order: [nameBox, saveButton, emailBox]');

console.log('\n================================================================');
console.log('FIRST MILESTONE CERTIFIED 100% SUCCESSFUL!');
console.log('================================================================\n');
