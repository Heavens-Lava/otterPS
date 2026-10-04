/**
 * Test Suite: Otter Studio Section 39 AI-Assisted Development & Copilot Certification
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { OtterAIAssistant } from '../js/ai/ai-assistant-engine.js';

test('1. Conversational pair programmer with workspace context', () => {
  const assistant = new OtterAIAssistant();
  const context = assistant.buildWorkspaceContext({
    workspaceRoot: '/projects/my-app',
    activeFile: 'src/main.ot',
    cursorPosition: { line: 12, column: 5 },
    diagnostics: [{ line: 12, message: 'expected "than" after "greater"' }],
    terminalHistory: ['$ otter run src/main.ot', 'Syntax error at line 12']
  });

  assert.equal(context.activeFile, 'src/main.ot');
  assert.equal(context.diagnosticsCount, 1);
  assert.equal(context.recentTerminalLines.length, 2);

  const res = assistant.chat('Can you fix the diagnostic?', {
    activeFile: 'src/main.ot',
    diagnostics: [{ line: 12, message: 'expected "than" after "greater"' }],
    source: 'if x is greater 10\n    say "high"\n.'
  });

  assert.ok(res.reply.includes('than'));
  assert.equal(res.historyLength, 2);
});

test('2. Natural language to Otter code synthesis', () => {
  const assistant = new OtterAIAssistant();
  const counterCode = assistant.generateOtterCode('create a counter with a button');
  assert.ok(counterCode.includes('count is 0'));
  assert.ok(counterCode.includes('when btn is clicked'));

  const httpCode = assistant.generateOtterCode('fetch data from API with http');
  assert.ok(httpCode.includes('get json from'));
  assert.ok(httpCode.includes('for each item in response'));

  const fileCode = assistant.generateOtterCode('read and write files on disk');
  assert.ok(fileCode.includes('write content to'));
  assert.ok(fileCode.includes('read text from'));
});

test('3. Natural language to visual UI layout generation', () => {
  const assistant = new OtterAIAssistant();
  const loginLayout = assistant.generateUILayout('create a login form with username and password');
  assert.equal(loginLayout.components.length, 4);
  assert.ok(loginLayout.otterCode.includes('text label'));
  assert.ok(loginLayout.otterCode.includes('primary button'));

  const settingsLayout = assistant.generateUILayout('create a settings panel with dark theme');
  assert.ok(settingsLayout.otterCode.includes('checkbox'));
});

test('4. Automated diagnostic analysis and one-click code fixes', () => {
  const assistant = new OtterAIAssistant();
  const source = [
    'if score is greater 5',
    '    say "unclosed',
    '.'
  ].join('\n');

  const diags = [
    { line: 1, message: 'expected "than" after "greater"' },
    { line: 2, message: 'unclosed string literal' }
  ];

  const fixes = assistant.analyzeDiagnosticsAndSuggestFixes(diags, source);
  assert.equal(fixes.length, 2);
  assert.equal(fixes[0].fixedLine, 'if score is greater than 5');
  assert.ok(fixes[0].canApplyAutomatically);

  assert.equal(fixes[1].fixedLine, '    say "unclosed"');
  assert.ok(fixes[1].canApplyAutomatically);
});

test('5. Automated unit-test suite generation for Otter modules', () => {
  const assistant = new OtterAIAssistant();
  const moduleSource = [
    'to calculateTax amount rate',
    '    give back amount * rate',
    '.',
    'to getStatus',
    '    give back "ready"',
    '.'
  ].join('\n');

  const suite = assistant.generateTestSuites(moduleSource, 'accounting');
  assert.ok(suite.includes('use "accounting.ot"'));
  assert.ok(suite.includes('Test 1: calculateTax execution'));
  assert.ok(suite.includes('Test 2: getStatus execution'));
  assert.ok(suite.includes('All tests for accounting passed!'));
});

test('6. Intelligent code explanation and docstring generator', () => {
  const assistant = new OtterAIAssistant();
  const code = [
    'when submitBtn is clicked',
    '    try',
    '        for each user in users',
    '            say user',
    '        .',
    '    otherwise err',
    '        say err',
    '    .',
    '.'
  ].join('\n');

  const explanation = assistant.explainCode(code);
  assert.ok(explanation.includes('click event handler'));
  assert.ok(explanation.includes('for-each loop'));
  assert.ok(explanation.includes('try/otherwise'));

  const doc = assistant.generateDocstring('addNumbers', ['a', 'b'], 'Sum of numbers');
  assert.ok(doc.includes('# Function: addNumbers'));
  assert.ok(doc.includes('#   a: Parameter description'));
  assert.ok(doc.includes('# Gives back: Sum of numbers'));
});

test('7. Context-aware semantic inline completions', () => {
  const assistant = new OtterAIAssistant();
  const completions = assistant.semanticInlineCompletions('btn is', '');
  assert.ok(completions.some(c => c.text.includes('primary button')));

  const loopCompletions = assistant.semanticInlineCompletions('for each', '');
  assert.ok(loopCompletions.some(c => c.text.includes('item in list')));
});
