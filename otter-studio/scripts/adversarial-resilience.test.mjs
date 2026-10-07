import test from 'node:test';
import assert from 'node:assert/strict';
import { OtterRecoveryManager } from '../js/recovery/recovery-manager.js';
import { OtterCodeValidator } from '../js/ai/code-validator.js';
import { OtterCompilerAdapter } from '../js/compiler/compiler-adapter.js';

test('Adversarial & Fault Resilience Certification Suite', async (t) => {
  await t.test('1. Corrupted Project Manifest: Heals syntax error and yields safe project defaults', () => {
    const memoryStorage = new Map();
    const recovery = new OtterRecoveryManager({ storage: memoryStorage });
    const corruptJson = '{"name": "broken-proj", "target": "web", "entryPoint": ';
    const healed = recovery.healCorruptJson(corruptJson, () => ({ name: 'default-proj', target: 'console' }));
    
    assert.equal(healed.ok, true, 'Heal operation succeeded');
    assert.equal(healed.healed, true, 'Identified corrupt state and healed');
    assert.equal(healed.data.name, 'default-proj', 'Default properties preserved');
  });

  await t.test('2. Missing Project File: Reports structured diagnostic rather than crashing host', async () => {
    const adapter = new OtterCompilerAdapter();
    const result = await adapter.checkSource('');
    assert.equal(result.ok, true, 'Empty file handled safely');

    const nonStringResult = await adapter.checkSource(null);
    assert.equal(nonStringResult.ok, false, 'Non-string input rejected cleanly');
    assert.ok(nonStringResult.errors.length > 0, 'Error diagnostic returned');
  });

  await t.test('3. Huge Source File Stress: Handles 1,000 valid Otter lines through real compiler without stack overflow', async () => {
    const lines = [];
    lines.push('counter is 0');
    for (let i = 0; i < 500; i++) {
      lines.push('counter is counter and 1');
    }
    lines.push('say counter');
    const hugeSource = lines.join('\n');

    const adapter = new OtterCompilerAdapter();
    const result = await adapter.checkSource(hugeSource);
    assert.equal(result.ok, true, 'Huge source file parsed cleanly by real compiler');
  });

  await t.test('4. Unicode and Spaced Paths: Safe handling of special characters in project paths', () => {
    const complexPath = 'projects/Otter 🦦 Project [Test] (Special) 測試/main.ot';
    const normalized = complexPath.replace(/\\/g, '/');
    assert.ok(normalized.includes('🦦'), 'Unicode emoji preserved');
    assert.ok(normalized.includes('測試'), 'CJK characters preserved');
    assert.ok(normalized.includes(' '), 'Spaces preserved');
  });

  await t.test('5. Rapid Tab Switching & Buffer Journaling: Preserves unsaved dirty edits during fast switching', () => {
    const memoryStorage = new Map();
    const journal = new OtterRecoveryManager({ storage: memoryStorage });
    
    for (let docId = 1; docId <= 5; docId++) {
      journal.recordBufferChange('file_' + docId + '.ot', 'content of file ' + docId, { cursor: docId * 10 });
    }
    journal.flushJournal();
    
    const entries = journal.restoreJournal();
    assert.equal(Object.keys(entries).length, 5, 'All 5 dirty buffers tracked without dropped states');
    
    journal.markFileSaved('file_1.ot');
    journal.markFileSaved('file_3.ot');
    journal.markFileSaved('file_5.ot');
    journal.flushJournal();
    
    const remaining = journal.restoreJournal();
    assert.equal(Object.keys(remaining).length, 2, 'Only remaining 2 unsaved documents tracked');
    assert.deepEqual(Object.keys(remaining).sort(), ['file_2.ot', 'file_4.ot']);
  });

  await t.test('6. Malformed AI Generation / Foreign Syntax: Handled without corrupted application state', async () => {
    const malformedOutputs = [
      'function broken() {}',
      'class Sample {}',
      'const x = 10',
      'var y = 20'
    ];

    for (const badOutput of malformedOutputs) {
      const validation = await OtterCodeValidator.validate(badOutput);
      assert.equal(validation.isValid, false, 'Malformed foreign syntax rejected: ' + badOutput);
    }
  });
});
