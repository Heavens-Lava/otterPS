import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { OtterCodeValidator } from '../js/ai/code-validator.js';
import { OtterCompilerAdapter } from '../js/compiler/compiler-adapter.js';

test('Authoritative Compiler Integration & Diagnostic Normalization (Real Toolchain)', async (t) => {
  const repoRoot = path.resolve(process.cwd(), '..');
  const adapter = new OtterCompilerAdapter();

  await t.test('1. Real repository Otter programs pass authoritative compiler check', async () => {
    const realFiles = [
      path.join(repoRoot, 'examples', 'hello.ot'),
      path.join(repoRoot, 'examples', 'calculator.ot'),
      path.join(repoRoot, 'examples', 'variables.ot'),
      path.join(repoRoot, 'examples', 'conditions.ot')
    ];

    for (const filePath of realFiles) {
      const result = await adapter.checkSource(filePath);
      assert.equal(result.ok, true, `Real repo file ${path.basename(filePath)} passed authoritative check`);
      assert.equal(result.errors.length, 0, 'Zero errors reported for canonical example');
    }
  });

  await t.test('2. Real valid Otter code string passes authoritative validator', async () => {
    const validOtterCode = 'score is 100\nbonus is 20\ntotal is score and bonus\nsay total\n';
    const result = await OtterCodeValidator.validate(validOtterCode, adapter);
    
    assert.equal(result.isValid, true, 'Valid canonical Otter code string certified');
    assert.equal(result.errors.length, 0, 'No errors reported');
    assert.equal(result.compilerValidated, true, 'Compiler confirmed validation');
  });

  await t.test('3. Real invalid syntax is authoritatively rejected by compiler with structured diagnostics', async () => {
    // Malformed Otter code
    const malformedCode = 'make is is make\nsay and and\n';
    const result = await OtterCodeValidator.validate(malformedCode, adapter);
    
    assert.equal(result.isValid, false, 'Authoritative compiler rejected invalid code');
    assert.ok(result.errors.length > 0, 'Structured diagnostics returned from compiler');
    assert.ok(result.errors.some(e => e.includes('make') || e.includes('value') || e.includes('Syntax')), 'Diagnostic surfaces compiler error details');
  });

  await t.test('4. Foreign JavaScript / Python syntax rejected authoritatively', async () => {
    const foreignCode = 'function calculateTotal(price) {\n  return price * 1.1;\n}\n';
    const result = await OtterCodeValidator.validate(foreignCode, adapter);
    
    assert.equal(result.isValid, false, 'Foreign JavaScript code rejected');
    assert.ok(result.errors.length > 0, 'Errors reported');
  });
});
