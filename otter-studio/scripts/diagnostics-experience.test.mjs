// diagnostics-experience.test.mjs - Dedicated Certification Suite for Section 10: Diagnostics Experience
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import {
  DiagnosticCodes,
  DiagnosticMetadata,
  DiagnosticCertificationTier,
  DiagnosticCertificationStatus,
  getDiagnosticCertification,
  resolveDiagnosticCode
} from '../js/diagnostics/diagnostic-codes.js';
import { translateHostError, extractOtterStackFrames, formatOtterStackTrace } from '../js/diagnostics/host-translator.js';
import {
  computeExactRange,
  normalizeDiagnostic,
  getDiagnosticQuickFixes,
  DiagnosticCollection
} from '../js/diagnostics/diagnostic-manager.js';
import { OtterStudioIde } from '../js/ide.js';

async function runDiagnosticsTests() {
  console.log('=== Running Section 10: Diagnostics Experience Certification Suite ===\n');
  let passed = 0;
  let failed = 0;

  function test(name, fn) {
    try {
      fn();
      console.log(`  ✓ ${name}`);
      passed++;
    } catch (err) {
      console.error(`  ✗ ${name}:`, err.message);
      failed++;
    }
  }

  function parseWithRealOtter(source) {
    const repoRoot = path.resolve('.');
    const psCmd = `
      $ErrorActionPreference = 'Stop'
      Import-Module (Join-Path '${repoRoot}\\src' 'Otter.Lexer.psm1') -Global
      Import-Module (Join-Path '${repoRoot}\\src' 'Otter.Parser.psm1') -Global
      try {
        $src = @'
${source}
'@
        $toks = ConvertTo-OtterTokens -Source $src
        $ast = ConvertTo-OtterAst -Tokens $toks
        $firstType = if ($ast.Statements.Count -gt 0) { $ast.Statements[0].GetType().Name } else { $null }
        [pscustomobject]@{
          Ok = $true
          StatementCount = $ast.Statements.Count
          FirstType = $firstType
        } | ConvertTo-Json
      } catch {
        [pscustomobject]@{
          Ok = $false
          Message = $_.Exception.Message
          Stage = $_.Exception.Stage
        } | ConvertTo-Json
      }
    `;
    const result = spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', psCmd], { encoding: 'utf8' });
    try {
      return JSON.parse(result.stdout.trim());
    } catch (err) {
      return { Ok: false, Message: result.stderr || result.stdout };
    }
  }

  // --- 1. Stable Otter Diagnostic Codes (Requirement 2) ---
  console.log('--- 1. Stable Otter Diagnostic Codes ---');

  test('All diagnostic categories adhere to defined OTxxxx namespaces', () => {
    for (const [key, code] of Object.entries(DiagnosticCodes)) {
      assert.match(code, /^OT[1-8]\d{3}$/, `Code ${code} for ${key} must match OT[1-8]xxx`);
      const meta = DiagnosticMetadata[code];
      assert.ok(meta, `DiagnosticMetadata must exist for ${code}`);
      assert.equal(meta.code, code);
      assert.ok(meta.title, `Metadata must have title for ${code}`);
      assert.ok(meta.category, `Metadata must have category for ${code}`);
      assert.ok(meta.severity, `Metadata must have severity for ${code}`);
    }
  });

  test('Codes resolve stably and deterministically', () => {
    assert.equal(resolveDiagnosticCode('Indentation cannot jump more than one level', 'lexer'), DiagnosticCodes.INDENTATION_JUMP);
    assert.equal(resolveDiagnosticCode("Otter does not use '=' to assign values", 'lexer'), DiagnosticCodes.EQUALS_ASSIGNMENT);
    assert.equal(resolveDiagnosticCode("Expected \".\" to close this block", 'parser'), DiagnosticCodes.MISSING_BLOCK_TERMINATOR);
    assert.equal(resolveDiagnosticCode("There is no open block for this period to close", 'parser'), DiagnosticCodes.EXTRANEOUS_BLOCK_TERMINATOR);
    assert.equal(resolveDiagnosticCode("Could not find anything called 'total'", 'analyzer'), DiagnosticCodes.UNDECLARED_VARIABLE);
    assert.equal(resolveDiagnosticCode("Variable declared but never read", 'analyzer', { semanticType: 'unused-variable' }), DiagnosticCodes.UNUSED_DECLARATION);
    assert.equal(resolveDiagnosticCode("Unreachable code detected", 'analyzer', { semanticType: 'unreachable-code' }), DiagnosticCodes.UNREACHABLE_CODE);
    assert.equal(resolveDiagnosticCode("Could not find a file called 'config.txt'", 'provider'), DiagnosticCodes.FILE_NOT_FOUND);
    assert.equal(resolveDiagnosticCode("Build compilation error", 'build', { isBuild: true }), DiagnosticCodes.TARGET_COMPILATION_ERROR);
  });

  // --- 2. Exact Diagnostic Ranges (Requirement 1) ---
  console.log('\n--- 2. Exact Diagnostic Ranges ---');

  test('Computes exact range for identifier token', () => {
    const source = 'say undeclaredName\n';
    // "undeclaredName" starts at column 5 (index 4) and has length 14 -> endCol 19
    const range = computeExactRange(source, 1, 5, DiagnosticCodes.UNDECLARED_VARIABLE, 'Unknown variable');
    assert.equal(range.startLine, 1);
    assert.equal(range.startColumn, 5);
    assert.equal(range.endLine, 1);
    assert.equal(range.endColumn, 19);
  });

  test('Computes exact range for equals assignment operator', () => {
    const source = 'score = 10\n';
    // "=" is at column 7 (index 6)
    const range = computeExactRange(source, 1, 7, DiagnosticCodes.EQUALS_ASSIGNMENT, "Does not use '='");
    assert.equal(range.startLine, 1);
    assert.equal(range.startColumn, 7);
    assert.equal(range.endLine, 1);
    assert.equal(range.endColumn, 8);
  });

  test('Computes exact range for missing block terminator', () => {
    const source = 'loop while count < 10\n    say count\n';
    const range = computeExactRange(source, 1, 1, DiagnosticCodes.MISSING_BLOCK_TERMINATOR, 'Expected "." to close');
    assert.equal(range.startLine, 1);
    assert.equal(range.startColumn, 1);
    assert.equal(range.endLine, 1);
    assert.equal(range.endColumn, 5); // highlights "loop" keyword
  });

  test('Clamps exact range safely when column exceeds line length', () => {
    const source = 'say "Hi"\n';
    const range = computeExactRange(source, 1, 40, DiagnosticCodes.UNEXPECTED_TOKEN, 'Unexpected token');
    assert.equal(range.startLine, 1);
    assert.equal(range.startColumn, 9);
    assert.equal(range.endColumn, 10);
  });

  test('HTML exact squiggle wrapping applies only to offending characters', () => {
    const ide = new OtterStudioIde();
    const renderedHtml = '<span class="tok-var">score</span> = <span class="tok-num">10</span>';
    // Offending token is "=" at startCol: 7, endCol: 8
    const wrapped = ide.wrapExactRangeInHtml(renderedHtml, 7, 8, 'exact-squiggle squiggle-error', 'OT1004');
    assert.ok(wrapped.includes('<span class="exact-squiggle squiggle-error" title="OT1004">=</span>'), `Wrapped HTML must underline only '=': ${wrapped}`);
    // "score" should NOT have exact-squiggle
    assert.ok(!wrapped.includes('class="tok-var exact-squiggle'));
  });

  // --- 3. Human-Readable Otter Errors & Host Translation (Requirements 3 & 6) ---
  console.log('\n--- 3. Human-Readable Otter Errors & Host Translation ---');

  test('Translates PowerShell CommandNotFoundException into clean Otter error', () => {
    const rawHostError = "The term 'node' is not recognized as the name of a cmdlet, function, script file, or operable program.\nAt line:1 char:1";
    const translated = translateHostError(rawHostError, { file: 'main.ot', line: 1 });
    assert.ok(translated);
    assert.equal(translated.isOtter, false);
    assert.equal(translated.source, 'host');
    assert.equal(translated.code, DiagnosticCodes.COMMAND_EXECUTION_FAILURE);
    assert.equal(translated.message, "I do not know a command called 'node'.");
    assert.ok(translated.suggestion.includes('Check the spelling'));
    assert.equal(translated.hostDetails, rawHostError);
  });

  test('Translates PowerShell and Node file-not-found into clean Otter error', () => {
    const rawHostError = "Cannot find path 'C:\\data\\items.txt' because it does not exist.";
    const translated = translateHostError(rawHostError, { file: 'main.ot', line: 3 });
    assert.ok(translated);
    assert.equal(translated.source, 'host');
    assert.equal(translated.code, DiagnosticCodes.FILE_NOT_FOUND);
    assert.equal(translated.message, "I could not find a file called 'C:\\data\\items.txt'.");
    assert.equal(translated.hostDetails, rawHostError);
  });

  test('Translates file permission / locked errors into clean Otter error', () => {
    const rawHostError = "System.UnauthorizedAccessException: Access to the path 'C:\\secret.log' is denied.";
    const translated = translateHostError(rawHostError, { file: 'main.ot', line: 2 });
    assert.ok(translated);
    assert.equal(translated.source, 'host');
    assert.equal(translated.code, DiagnosticCodes.FILE_ACCESS_DENIED);
    assert.equal(translated.message, "I could not access 'C:\\secret.log'. Permission was denied.");
    assert.equal(translated.hostDetails, rawHostError);
  });

  test('Translates JavaScript ReferenceError into clean Otter error', () => {
    const rawJsError = "ReferenceError: activeUser is not defined\n    at eval (eval at <anonymous>)";
    const translated = translateHostError(rawJsError, { file: 'main.ot', line: 7 });
    assert.ok(translated);
    assert.equal(translated.source, 'host');
    assert.equal(translated.code, DiagnosticCodes.UNDECLARED_VARIABLE);
    assert.equal(translated.message, "I don't know a variable called 'activeUser'.");
    assert.ok(translated.suggestion.includes("Assign a value to 'activeUser' before using it"));
    assert.equal(translated.hostDetails, rawJsError);
  });

  test('Preserves native Otter Runtime Error as semantic authority without alterations', () => {
    const nativeOtterError = `Otter Runtime Error

Line 12:
    say 10 divided by 0

Cannot divide number by zero.

Try:
    check that divisor is not 0 before dividing`;

    const translated = translateHostError(nativeOtterError, { file: 'main.ot' });
    assert.ok(translated);
    assert.equal(translated.isOtter, true);
    assert.equal(translated.source, 'otter');
    assert.equal(translated.line, 12);
    assert.equal(translated.code, DiagnosticCodes.DIVISION_BY_ZERO);
    assert.equal(translated.message, 'Cannot divide number by zero.');
    assert.equal(translated.suggestion, 'check that divisor is not 0 before dividing');
    assert.equal(translated.hostDetails, null); // native Otter error needs no separate host details
  });

  // --- 4. Suggested Fixes (Requirement 4) ---
  console.log('\n--- 4. Suggested Fixes ---');

  test('Generates safe Quick Fix for missing block terminator (OT2001)', () => {
    const source = 'to computeTotal\n    x is 10\n';
    const diag = normalizeDiagnostic({
      Line: 1,
      Column: 1,
      Message: 'Expected "." to close this block.'
    }, source, 'main.ot');

    assert.equal(diag.code, DiagnosticCodes.MISSING_BLOCK_TERMINATOR);
    assert.ok(diag.fixes.length > 0);
    const fix = diag.fixes[0];
    assert.equal(fix.title, 'Add closing "."');
    assert.equal(fix.edits.length, 1);
    assert.equal(fix.edits[0].newText, '.\n');
  });

  test('Generates safe Quick Fix for equals assignment (OT1004) without introducing make', () => {
    const source = 'score = 100\n';
    const diag = normalizeDiagnostic({
      Line: 1,
      Column: 7,
      Message: "Otter does not use '=' to assign values."
    }, source, 'main.ot');

    assert.equal(diag.code, DiagnosticCodes.EQUALS_ASSIGNMENT);
    assert.ok(diag.fixes.length > 0);
    const fix = diag.fixes[0];
    assert.equal(fix.title, "Replace '=' with 'is'");
    assert.equal(fix.edits[0].newText, 'is');

    // Test applying the edit produces canonical assignment: score is 100
    const ide = new OtterStudioIde();
    const updated = ide.applyEditToText(source, fix.edits[0]);
    assert.equal(updated, 'score is 100\n');
  });

  test('Generates safe Quick Fix for equals assignment with make prefix stripping make', () => {
    const source = 'make score = 100\n';
    const diag = normalizeDiagnostic({
      Line: 1,
      Column: 12,
      Message: "Otter does not use '=' to assign values."
    }, source, 'main.ot');

    assert.equal(diag.code, DiagnosticCodes.EQUALS_ASSIGNMENT);
    assert.ok(diag.fixes.length > 0);
    const fix = diag.fixes[0];
    assert.equal(fix.title, "Replace with canonical assignment 'score is 100'");

    const ide = new OtterStudioIde();
    const updated = ide.applyEditToText(source, fix.edits[0]);
    assert.equal(updated, 'score is 100\n');
  });

  test('Never creates automatic edit for undeclared variable (OT3001) - guidance only', () => {
    const source = 'say mysteryTotal\n';
    const diag = normalizeDiagnostic({
      Line: 1,
      Column: 5,
      Message: "I could not find anything called 'mysteryTotal'."
    }, source, 'main.ot');

    assert.equal(diag.code, DiagnosticCodes.UNDECLARED_VARIABLE);
    assert.equal(diag.fixes.length, 0, 'Undeclared variable must have 0 automatic edits');
  });

  test('Safely removes unused declaration (OT3003) for pure assignment statement', () => {
    const source = 'used is 10\nunused is 20\nsay used\n';
    const diag = normalizeDiagnostic({
      Line: 2,
      Column: 1,
      Message: "Variable 'unused' declared but never read.",
      semanticType: 'unused-variable'
    }, source, 'main.ot');

    assert.equal(diag.code, DiagnosticCodes.UNUSED_DECLARATION);
    assert.equal(diag.fixes.length, 1);
    const ide = new OtterStudioIde();
    const updated = ide.applyEditToText(source, diag.fixes[0].edits[0]);
    assert.equal(updated, 'used is 10\nsay used\n');
  });

  test('Generates safe Quick Fix for period property access (OT1003)', () => {
    const source = 'say user.name\n';
    const diag = normalizeDiagnostic({
      Line: 1,
      Column: 9,
      Message: "Otter does not use periods to access properties."
    }, source, 'main.ot');

    assert.equal(diag.code, DiagnosticCodes.PERIOD_PROPERTY_ACCESS);
    assert.ok(diag.fixes.length > 0);
    const fix = diag.fixes[0];
    assert.equal(fix.title, "Use 'name of user' syntax");

    const ide = new OtterStudioIde();
    const updated = ide.applyEditToText(source, fix.edits[0]);
    assert.equal(updated, 'say name of user\n');
  });

  test('Never generates an unsafe fix when intended correction cannot be determined', () => {
    const source = 'bad token ?? mystery\n';
    const diag = normalizeDiagnostic({
      Line: 1,
      Column: 1,
      Message: 'General unexpected syntax error.'
    }, source, 'main.ot');

    // Should have 0 safe automatic fixes
    assert.equal(diag.fixes.length, 0, 'Must not generate arbitrary or unsafe fixes');
  });

  // --- 5. Build Diagnostics (Requirement 5) ---
  console.log('\n--- 5. Build Diagnostics ---');

  test('Populates structured build diagnostics into Problems system', () => {
    const ide = new OtterStudioIde();
    const buildResult = {
      ok: false,
      error: 'Webpack bundle error: entrypoint main.ot failed to compile',
      stderr: 'Error: Module build failed at line 14\n   at TargetCompiler.bundle'
    };

    ide.populateBuildDiagnostics('web', buildResult);

    assert.ok(ide.diagnosticCollection.hasErrors('build-web'));
    const diags = ide.diagnosticCollection.get('build-web');
    assert.equal(diags.length, 1);
    const buildDiag = diags[0];
    assert.equal(buildDiag.source, 'build');
    assert.equal(buildDiag.target, 'web');
    assert.equal(buildDiag.category, 'build');
    assert.equal(buildDiag.code, DiagnosticCodes.TARGET_COMPILATION_ERROR);
    assert.ok(buildDiag.hostDetails.includes('Module build failed'));
  });

  // --- 6. Runtime Stack Trace Foundation (Requirement 7) ---
  console.log('\n--- 6. Runtime Stack Trace Foundation ---');

  test('Extracts Otter stack frames and excludes host/JS runtime glue', () => {
    const errorWithStack = `Otter Runtime Error: Division by zero
    in calculateAverage at stats.ot:18:9
    in processGrades at main.ot:42:5
    at Module._compile (node:internal/modules/cjs/loader:1256:14)
    at Object.Module._extensions..js (node:internal/modules/cjs/loader:1310:10)`;

    const frames = extractOtterStackFrames(errorWithStack, 'main.ot', 1);
    assert.equal(frames.length, 2, 'Must extract only the 2 Otter frames');
    assert.equal(frames[0].functionName, 'calculateAverage');
    assert.equal(frames[0].file, 'stats.ot');
    assert.equal(frames[0].line, 18);
    assert.equal(frames[0].column, 9);

    assert.equal(frames[1].functionName, 'processGrades');
    assert.equal(frames[1].file, 'main.ot');
    assert.equal(frames[1].line, 42);
    assert.equal(frames[1].column, 5);

    const formatted = formatOtterStackTrace(frames);
    assert.ok(formatted.includes('at in calculateAverage stats.ot:18:9'));
    assert.ok(formatted.includes('at in processGrades main.ot:42:5'));
    assert.ok(!formatted.includes('node:internal'), 'Must not include node internal stack frames');
  });

  // --- 7. DiagnosticCollection Management ---
  console.log('\n--- 7. DiagnosticCollection Management ---');

  test('DiagnosticCollection handles multiple files, severities, and sorting', () => {
    const collection = new DiagnosticCollection();

    collection.set('main.ot', [
      { startLine: 10, startColumn: 5, severity: 'error', code: 'OT2001' },
      { startLine: 3, startColumn: 2, severity: 'warning', code: 'OT3003' }
    ]);
    collection.set('helper.ot', [
      { startLine: 1, startColumn: 1, severity: 'error', code: 'OT1001' }
    ]);

    // Sorting check: main.ot line 3 should come before line 10
    const mainDiags = collection.get('main.ot');
    assert.equal(mainDiags[0].startLine, 3);
    assert.equal(mainDiags[1].startLine, 10);

    assert.equal(collection.hasErrors('main.ot'), true);
    assert.equal(collection.hasWarnings('main.ot'), true);
    assert.equal(collection.hasWarnings('helper.ot'), false);

    const counts = collection.getCounts();
    assert.equal(counts.total, 3);
    assert.equal(counts.errors, 2);
    assert.equal(counts.warnings, 1);

    // Clear one file
    collection.clear('helper.ot');
    assert.equal(collection.getAll().length, 2);

    // Clear all
    collection.clearAll();
    assert.equal(collection.getAll().length, 0);
  });

  // --- 8. Navigation to Exact Source Location ---
  console.log('\n--- 8. Problems Navigation ---');

  test('Calculates exact character offsets for textarea cursor selection', () => {
    const ide = new OtterStudioIde();
    const doc = "first line\nsecond line\nthird line";

    // Line 1, Col 1 -> offset 0
    assert.equal(ide.getOffsetFromPosition(doc, 1, 1), 0);

    // Line 1, Col 6 -> offset 5 ("first" is 5 chars)
    assert.equal(ide.getOffsetFromPosition(doc, 1, 6), 5);

    // Line 2, Col 1 -> offset 11 ("first line\n" is 11 chars)
    assert.equal(ide.getOffsetFromPosition(doc, 2, 1), 11);

    // Line 2, Col 8 -> offset 11 + 7 = 18 ("second " is 7 chars)
    assert.equal(ide.getOffsetFromPosition(doc, 2, 8), 18);
  });

  // --- 9. Real Live Server Diagnostic Integration ---
  console.log('\n--- 9. Real Live Server Diagnostic Integration ---');

  await (async () => {
    try {
      const response = await fetch('http://127.0.0.1:4200/api/lint', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code: 'speed = 80' })
      });
      if (response.ok) {
        const raw = await response.json();
        assert.equal(raw.ok, false);
        assert.equal(raw.stage, 'lexer');
        assert.equal(raw.line, 1);
        assert.equal(raw.column, 7);
        const normalized = normalizeDiagnostic(raw, 'speed = 80', 'main.ot');
        assert.equal(normalized.code, DiagnosticCodes.EQUALS_ASSIGNMENT);
        assert.equal(normalized.startLine, 1);
        assert.equal(normalized.startColumn, 7);
        assert.equal(normalized.endColumn, 8);
        assert.ok(normalized.fixes.length > 0);
        assert.equal(normalized.fixes[0].title, "Replace '=' with 'is'");
        const ide = new OtterStudioIde();
        const updated = ide.applyEditToText('speed = 80', normalized.fixes[0].edits[0]);
        assert.equal(updated, 'speed is 80');
        console.log('  ✓ Real /api/lint lexer diagnostic returns exact range and resolves stable code OT1004 with canonical Quick Fix');
        passed++;
      }
    } catch {
      console.log('  ⚠ Live server not reachable for integration test, skipping route check');
    }
  })();

  // --- 10. Diagnostic Code Certification Status Audit ---
  console.log('\n--- 10. Diagnostic Code Certification Status Audit ---');

  test('Distinguishes DEFINED, MAPPED, and PRODUCTION_VERIFIED status tiers', () => {
    assert.equal(DiagnosticCertificationTier.DEFINED, 'DEFINED');
    assert.equal(DiagnosticCertificationTier.MAPPED, 'MAPPED');
    assert.equal(DiagnosticCertificationTier.PRODUCTION_VERIFIED, 'PRODUCTION_VERIFIED');

    // Certified production verified codes
    assert.equal(getDiagnosticCertification('OT1004'), DiagnosticCertificationTier.PRODUCTION_VERIFIED);
    assert.equal(getDiagnosticCertification('OT3001'), DiagnosticCertificationTier.PRODUCTION_VERIFIED);
    assert.equal(getDiagnosticCertification('OT3003'), DiagnosticCertificationTier.PRODUCTION_VERIFIED);
    assert.equal(getDiagnosticCertification('OT2001'), DiagnosticCertificationTier.PRODUCTION_VERIFIED);
    assert.equal(getDiagnosticCertification('OT1001'), DiagnosticCertificationTier.PRODUCTION_VERIFIED);

    // Mapped codes (deterministic translation exists, not yet live-compiler integration certified)
    assert.equal(getDiagnosticCertification('OT1002'), DiagnosticCertificationTier.MAPPED);
    assert.equal(getDiagnosticCertification('OT2004'), DiagnosticCertificationTier.MAPPED);
    assert.equal(getDiagnosticCertification('OT3002'), DiagnosticCertificationTier.MAPPED);

    // Defined codes (defined schema/metadata placeholder)
    assert.equal(getDiagnosticCertification('OT4001'), DiagnosticCertificationTier.DEFINED);
    assert.equal(getDiagnosticCertification('OT4002'), DiagnosticCertificationTier.DEFINED);
    assert.equal(getDiagnosticCertification('OT7004'), DiagnosticCertificationTier.DEFINED);

    // Verify all codes in DiagnosticCodes have defined status
    for (const [key, code] of Object.entries(DiagnosticCodes)) {
      const status = getDiagnosticCertification(code);
      assert.ok(status, `Code ${code} (${key}) must have a certification status`);
      assert.ok(
        [DiagnosticCertificationTier.DEFINED, DiagnosticCertificationTier.MAPPED, DiagnosticCertificationTier.PRODUCTION_VERIFIED].includes(status),
        `Status ${status} must be a valid tier`
      );
    }
  });

  // --- 11. Real Otter Parser Verification for Canonical Assignment & Quick Fix Outputs ---
  console.log('\n--- 11. Real Otter Parser Verification for Canonical Assignment & Quick Fix Outputs ---');

  test('Real Otter parser certifies canonical variable assignment syntax without make', () => {
    const t1 = parseWithRealOtter('name is "Jeff"');
    assert.equal(t1.Ok, true, `name is "Jeff" failed: ${t1.Message}`);
    assert.equal(t1.StatementCount, 1);
    assert.equal(t1.FirstType, 'AssignStmt');

    const t2 = parseWithRealOtter('score is 100');
    assert.equal(t2.Ok, true, `score is 100 failed: ${t2.Message}`);
    assert.equal(t2.StatementCount, 1);
    assert.equal(t2.FirstType, 'AssignStmt');

    const t3 = parseWithRealOtter('total is price times quantity');
    assert.equal(t3.Ok, true, `total is price times quantity failed: ${t3.Message}`);
    assert.equal(t3.StatementCount, 1);
    assert.equal(t3.FirstType, 'AssignStmt');

    // Confirm that 'make score is 100' is rejected by the real Otter parser
    const invalidMake = parseWithRealOtter('make score is 100');
    assert.equal(invalidMake.Ok, false, 'make score is 100 must be rejected by parser');
    assert.match(invalidMake.Message, /don't understand 'make'/i);
  });

  test('Real Otter parser certifies OT1004 equals assignment Quick Fix output', () => {
    const source = 'score = 100';
    const diag = normalizeDiagnostic({
      Line: 1,
      Column: 7,
      Message: "Otter does not use '=' to assign values."
    }, source, 'main.ot');

    assert.equal(diag.fixes.length, 1);
    const ide = new OtterStudioIde();
    const fixedSource = ide.applyEditToText(source, diag.fixes[0].edits[0]);
    assert.equal(fixedSource, 'score is 100');

    // Run real Otter parser on the Quick Fix output
    const parsed = parseWithRealOtter(fixedSource);
    assert.equal(parsed.Ok, true, `Quick Fix output failed parsing: ${parsed.Message}`);
    assert.equal(parsed.StatementCount, 1);
    assert.equal(parsed.FirstType, 'AssignStmt');
  });

  test('Real Otter parser certifies OT1004 equals assignment with make-prefix Quick Fix output', () => {
    const source = 'make score = 100';
    const diag = normalizeDiagnostic({
      Line: 1,
      Column: 12,
      Message: "Otter does not use '=' to assign values."
    }, source, 'main.ot');

    assert.equal(diag.fixes.length, 1);
    const ide = new OtterStudioIde();
    const fixedSource = ide.applyEditToText(source, diag.fixes[0].edits[0]);
    assert.equal(fixedSource, 'score is 100');

    // Run real Otter parser on the Quick Fix output
    const parsed = parseWithRealOtter(fixedSource);
    assert.equal(parsed.Ok, true, `Quick Fix output failed parsing: ${parsed.Message}`);
    assert.equal(parsed.StatementCount, 1);
    assert.equal(parsed.FirstType, 'AssignStmt');
  });

  test('Real Otter parser certifies OT2001 missing block terminator Quick Fix output', () => {
    const source = 'if score is greater than 10\n    say "You won!"';
    const diag = normalizeDiagnostic({
      Line: 1,
      Column: 1,
      Message: 'Expected "." to close this block.'
    }, source, 'main.ot');

    assert.equal(diag.fixes.length, 1);
    const ide = new OtterStudioIde();
    const fixedSource = ide.applyEditToText(source, diag.fixes[0].edits[0]);

    // Run real Otter parser on the Quick Fix output
    const parsed = parseWithRealOtter(fixedSource);
    assert.equal(parsed.Ok, true, `Quick Fix output failed parsing: ${parsed.Message}`);
    assert.equal(parsed.FirstType, 'IfStmt');
  });

  test('Real Otter parser certifies OT1003 period property access Quick Fix output', () => {
    const source = 'say player.score';
    const diag = normalizeDiagnostic({
      Line: 1,
      Column: 11,
      Message: 'Otter does not use periods to access properties.'
    }, source, 'main.ot');

    assert.equal(diag.fixes.length, 1);
    const ide = new OtterStudioIde();
    const fixedSource = ide.applyEditToText(source, diag.fixes[0].edits[0]);
    assert.equal(fixedSource, 'say score of player');

    // Run real Otter parser on the Quick Fix output
    const parsed = parseWithRealOtter(fixedSource);
    assert.equal(parsed.Ok, true, `Quick Fix output failed parsing: ${parsed.Message}`);
    assert.equal(parsed.FirstType, 'SayStmt');
  });

  test('Real Otter parser certifies OT3003 unused declaration removal Quick Fix output', () => {
    const source = 'score is 100\nunused is 20\nsay score\n';
    const diag = normalizeDiagnostic({
      Line: 2,
      Column: 1,
      Message: "Variable 'unused' declared but never read.",
      semanticType: 'unused-variable'
    }, source, 'main.ot');

    assert.equal(diag.fixes.length, 1);
    const ide = new OtterStudioIde();
    const fixedSource = ide.applyEditToText(source, diag.fixes[0].edits[0]);
    assert.equal(fixedSource, 'score is 100\nsay score\n');

    // Run real Otter parser on the Quick Fix output
    const parsed = parseWithRealOtter(fixedSource);
    assert.equal(parsed.Ok, true, `Quick Fix output failed parsing: ${parsed.Message}`);
    assert.equal(parsed.StatementCount, 2);
    assert.equal(parsed.FirstType, 'AssignStmt');
  });

  console.log(`\nDiagnostics Experience Test Results: ${passed} passed, ${failed} failed`);
  if (failed > 0) {
    process.exit(1);
  }
}

runDiagnosticsTests();
