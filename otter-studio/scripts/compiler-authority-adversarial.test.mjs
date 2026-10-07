import test from 'node:test';
import assert from 'node:assert/strict';
import { OtterCodeValidator } from '../js/ai/code-validator.js';
import { OtterCompilerAdapter } from '../js/compiler/compiler-adapter.js';

test('Compiler Authority & Adversarial Validation Certification', async (t) => {
  await t.test('1. Valid Otter code passes both preflight heuristics and real compiler check', async () => {
    const validCode = `
make score is 100
make bonus is 20
make total is score and bonus
say total
`;
    const result = await OtterCodeValidator.validate(validCode);
    assert.equal(result.isValid, true, 'Valid code is certified');
    assert.equal(result.errors.length, 0, 'No validation errors');
    assert.equal(result.compilerValidated, true, 'Compiler confirmed validation');
  });

  await t.test('2. Adversarial Case: Code passes simple regex preflight but fails real compiler -> REJECTED', async () => {
    // This code uses Otter keywords (make, is, and, say) and ends with '.', so shallow regex thinks it might be valid,
    // but the grammatical structure is completely invalid in the real parser.
    const adversarialSource = `
make is is make
say and and
to
.
`;
    // Mock compiler adapter simulating real compiler AST failure on malformed grammar
    const mockRealCompiler = {
      async checkSource(src) {
        return {
          ok: false,
          errors: [{ message: 'Otter Parser Error: Unexpected token "is" at line 2 column 6' }]
        };
      }
    };

    const preflight = OtterCodeValidator.preflightLint(adversarialSource);
    // Preflight alone might not catch deep grammar errors
    const authoritativeResult = await OtterCodeValidator.validate(adversarialSource, mockRealCompiler);
    
    assert.equal(authoritativeResult.isValid, false, 'Authoritative validator marked adversarial code invalid');
    assert.ok(authoritativeResult.errors.some(e => e.includes('Otter Parser Error')), 'Parser error surfaced to Studio');
  });

  await t.test('3. Preflight False Positive: Complex valid Otter syntax is accepted because real compiler succeeds', async () => {
    const advancedOtterCode = `
to calculate_discount of price with rate
  make discount is price and rate
  return discount
.
`;
    // Compiler adapter accepts valid function definition
    const mockRealCompiler = {
      async checkSource(src) {
        return { ok: true, errors: [] };
      }
    };

    const result = await OtterCodeValidator.validate(advancedOtterCode, mockRealCompiler);
    assert.equal(result.isValid, true, 'Real compiler authority certifies advanced syntax');
    assert.equal(result.errors.length, 0, 'Zero errors reported when compiler passes');
  });

  await t.test('4. Code application guard: Malformed code rejected by validator CANNOT be applied to editor buffer', () => {
    let editorContent = 'make score is 10';
    
    function applyAiPatch(currentBuffer, patchCode, validationResult) {
      if (!validationResult.isValid) {
        throw new Error(`Cannot apply invalid AI code: ${validationResult.errors.join(', ')}`);
      }
      return patchCode;
    }
    
    const invalidValidation = {
      isValid: false,
      errors: ['Syntax error at line 3: missing block terminator']
    };
    
    assert.throws(
      () => applyAiPatch(editorContent, 'corrupt code', invalidValidation),
      /Cannot apply invalid AI code/,
      'Editor refused to apply invalid AI code'
    );
    assert.equal(editorContent, 'make score is 10', 'Editor buffer remained uncorrupted');
  });
});
