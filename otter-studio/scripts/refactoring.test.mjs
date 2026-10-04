// refactoring.test.mjs - End-to-end certification for Section 23: Refactoring
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const PORT = Number(process.env.OTTER_STUDIO_PORT || 4200);
const BASE_URL = `http://127.0.0.1:${PORT}`;

async function api(pathname, body, method = 'POST') {
  const res = await fetch(`${BASE_URL}${pathname}`, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await res.json().catch(() => ({}));
  return { status: res.status, data };
}

const TEST_DIR_NAME = `test-refactor-${Date.now()}`;
const TEST_DIR = path.join(REPO_ROOT, 'projects', TEST_DIR_NAME);
const PROJ_A_DIR = path.join(TEST_DIR, 'proj-a');
const PROJ_B_DIR = path.join(TEST_DIR, 'proj-b');

async function cleanup() {
  if (fs.existsSync(TEST_DIR)) {
    try {
      fs.rmSync(TEST_DIR, { recursive: true, force: true });
    } catch {}
  }
}

try {
  console.log('=== Running Section 23: Refactoring Certification Suite ===\n');
  await cleanup();

  fs.mkdirSync(PROJ_A_DIR, { recursive: true });
  fs.mkdirSync(PROJ_B_DIR, { recursive: true });

  const fileA1 = path.join(PROJ_A_DIR, 'calc.ot');
  const fileA2 = path.join(PROJ_A_DIR, 'main.ot');
  const fileB1 = path.join(PROJ_B_DIR, 'client.ot');

  fs.writeFileSync(fileA1, 'to computeTotal\n    make rate is 15\n    return rate\n.\n', 'utf8');
  fs.writeFileSync(fileA2, 'use "./calc.ot"\n\nmake res is computeTotal\nsay res\n', 'utf8');
  fs.writeFileSync(fileB1, 'use "../proj-a/calc.ot"\n\nmake subtotal is computeTotal\n', 'utf8');

  // --- 1. Rename Symbol & Update References ---
  console.log('--- 1. Rename Symbol & Update References ---');
  const renameRes = await api('/api/refactor/rename', {
    files: [fileA1, fileA2],
    oldName: 'computeTotal',
    newName: 'calculateGrandTotal',
    kind: 'function',
    apply: true
  });
  assert.equal(renameRes.status, 200);
  assert.equal(renameRes.data.ok, true);
  assert.equal(renameRes.data.affectedFiles.length, 2);
  assert.equal(renameRes.data.applied, true);

  const updatedA1 = fs.readFileSync(fileA1, 'utf8');
  const updatedA2 = fs.readFileSync(fileA2, 'utf8');
  assert.match(updatedA1, /to calculateGrandTotal/);
  assert.match(updatedA2, /make res is calculateGrandTotal/);
  console.log('  ✓ Renamed computeTotal -> calculateGrandTotal across files and call sites');

  // --- 2. Preview Changes ---
  console.log('\n--- 2. Preview Changes (Unified Diff Engine) ---');
  const previewRes = await api('/api/refactor/preview', {
    edits: renameRes.data.edits
  });
  assert.equal(previewRes.status, 200);
  assert.equal(previewRes.data.ok, true);
  assert.ok(previewRes.data.preview.length > 0);
  assert.match(previewRes.data.preview[0].diff, /@@ Line \d+ @@/);
  console.log('  ✓ Generated unified diff preview for pending refactorings');

  // --- 3. Atomic Undo & Redo ---
  console.log('\n--- 3. Atomic Undo & Redo ---');
  const undoRes = await api('/api/refactor/undo', {});
  assert.equal(undoRes.status, 200);
  assert.equal(undoRes.data.ok, true);

  const revertedA1 = fs.readFileSync(fileA1, 'utf8');
  assert.match(revertedA1, /to computeTotal/, 'Undo must restore original symbol name');
  console.log('  ✓ Atomically reverted multi-file transaction');

  const redoRes = await api('/api/refactor/redo', {});
  assert.equal(redoRes.status, 200);
  assert.equal(redoRes.data.ok, true);

  const redoneA1 = fs.readFileSync(fileA1, 'utf8');
  assert.match(redoneA1, /to calculateGrandTotal/, 'Redo must re-apply transaction');
  console.log('  ✓ Atomically re-applied multi-file transaction');

  // --- 4. Extract Variable ---
  console.log('\n--- 4. Extract Variable ---');
  const codeBeforeExtractVar = 'make total is 10 plus 20\nsay total\n';
  const extractVarRes = await api('/api/refactor/extract-variable', {
    code: codeBeforeExtractVar,
    selection: '10 plus 20',
    varName: 'subtotal'
  });
  assert.equal(extractVarRes.status, 200);
  assert.equal(extractVarRes.data.ok, true);
  assert.match(extractVarRes.data.newCode, /make subtotal is 10 plus 20/);
  assert.match(extractVarRes.data.newCode, /make total is subtotal/);
  console.log('  ✓ Extracted expression into local variable assignment');

  // --- 5. Inline Variable ---
  console.log('\n--- 5. Inline Variable ---');
  const codeBeforeInline = 'make bonus is 50\nmake payout is base plus bonus\nsay bonus\n';
  const inlineRes = await api('/api/refactor/inline-variable', {
    code: codeBeforeInline,
    varName: 'bonus'
  });
  assert.equal(inlineRes.status, 200);
  assert.equal(inlineRes.data.ok, true);
  assert.equal(inlineRes.data.inlinedCount, 2);
  assert.ok(!inlineRes.data.newCode.includes('make bonus is 50'));
  assert.match(inlineRes.data.newCode, /make payout is base plus 50/);
  assert.match(inlineRes.data.newCode, /say 50/);
  console.log('  ✓ Inlined variable across 2 call sites and removed declaration');

  // --- 6. Extract Function ---
  console.log('\n--- 6. Extract Function ---');
  const codeBeforeFn = 'make x is 5\nsay "Processing item"\nmake y is 10\n';
  const extractFnRes = await api('/api/refactor/extract-function', {
    code: codeBeforeFn,
    selection: 'say "Processing item"',
    fnName: 'logItem'
  });
  assert.equal(extractFnRes.status, 200);
  assert.equal(extractFnRes.data.ok, true);
  assert.match(extractFnRes.data.newCode, /to logItem\n    say "Processing item"\n\./);
  assert.match(extractFnRes.data.newCode, /logItem\nmake y is 10/);
  console.log('  ✓ Extracted statements into function definition placed sequentially before caller');

  // --- 7. Move Symbol / Module ---
  console.log('\n--- 7. Move Symbol / Module ---');
  const moveRes = await api('/api/refactor/move-symbol', {
    sourceFile: path.relative(REPO_ROOT, fileA1),
    targetFile: path.relative(REPO_ROOT, fileA2),
    symbolName: 'calculateGrandTotal',
    apply: true
  });
  assert.equal(moveRes.status, 200);
  assert.equal(moveRes.data.ok, true);

  const movedSource = fs.readFileSync(fileA1, 'utf8');
  const movedTarget = fs.readFileSync(fileA2, 'utf8');
  assert.ok(!movedSource.includes('to calculateGrandTotal'));
  assert.match(movedTarget, /to calculateGrandTotal/);
  console.log('  ✓ Moved function calculateGrandTotal from calc.ot to main.ot');

  // --- 8. Safe Delete ---
  console.log('\n--- 8. Safe Delete (Dependency Checking) ---');
  // Should report unsafe because calculateGrandTotal is still used in main.ot and client.ot
  const unsafeDeleteRes = await api('/api/refactor/safe-delete', {
    files: [fileA2, fileB1],
    symbolName: 'calculateGrandTotal'
  });
  assert.equal(unsafeDeleteRes.status, 200);
  assert.equal(unsafeDeleteRes.data.safe, false);
  assert.ok(unsafeDeleteRes.data.referenceCount > 0);
  assert.match(unsafeDeleteRes.data.warning, /is still referenced/);
  console.log('  ✓ Safe delete flagged active usages as unsafe');

  // Should report safe for an unused symbol
  const safeDeleteRes = await api('/api/refactor/safe-delete', {
    files: [fileA1, fileA2, fileB1],
    symbolName: 'nonExistentHelperSymbol'
  });
  assert.equal(safeDeleteRes.status, 200);
  assert.equal(safeDeleteRes.data.safe, true);
  assert.equal(safeDeleteRes.data.referenceCount, 0);
  console.log('  ✓ Safe delete confirmed symbol has 0 usages');

  // --- 9. Organize Modules / Imports ---
  console.log('\n--- 9. Organize Modules / Imports ---');
  const unorganizedCode = `
# Header comments
use "./local/helper.ot"
use "strings"
use "./local/helper.ot"
use "math"
use "@company/pkg-tools"
use "collections"

say "App started"
`;
  const organizeRes = await api('/api/refactor/organize-modules', {
    code: unorganizedCode
  });
  assert.equal(organizeRes.status, 200);
  assert.equal(organizeRes.data.ok, true);
  assert.equal(organizeRes.data.organizedCount, 5); // 5 unique imports

  // Verify alphabetical stdlib imports come first, followed by package, followed by relative
  const orgCode = organizeRes.data.newCode;
  const idxCollections = orgCode.indexOf('use "collections"');
  const idxMath = orgCode.indexOf('use "math"');
  const idxPkg = orgCode.indexOf('use "@company/pkg-tools"');
  const idxHelper = orgCode.indexOf('use "./local/helper.ot"');

  assert.ok(idxCollections < idxMath, 'collections should precede math');
  assert.ok(idxMath < idxPkg, 'stdlib should precede package');
  assert.ok(idxPkg < idxHelper, 'package should precede relative import');
  console.log('  ✓ Deduplicated and organized module imports alphabetically by group');

  // --- 10. Cross-Project Refactoring ---
  console.log('\n--- 10. Cross-Project Refactoring ---');
  // fileB1 currently contains 'make subtotal is computeTotal'
  // Let's refactor 'subtotal' to 'orderSubtotal' across both proj-a and proj-b
  const crossProjRes = await api('/api/refactor/cross-project', {
    solutionProjects: [
      path.relative(REPO_ROOT, PROJ_A_DIR),
      path.relative(REPO_ROOT, PROJ_B_DIR)
    ],
    oldName: 'subtotal',
    newName: 'orderSubtotal',
    kind: 'variable',
    apply: true
  });
  assert.equal(crossProjRes.status, 200);
  assert.equal(crossProjRes.data.ok, true);

  const updatedB1 = fs.readFileSync(fileB1, 'utf8');
  assert.match(updatedB1, /make orderSubtotal is computeTotal/);
  console.log('  ✓ Cross-project refactoring updated symbols across all solution projects');

  console.log('\n=== ALL SECTION 23 REFACTORING TESTS PASSED SUCCESSFULLY ===');
} finally {
  await cleanup();
}
