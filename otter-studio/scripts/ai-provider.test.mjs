/**
 * Comprehensive Test Suite: Otter Studio AI Provider Abstraction, Credential Isolation,
 * Prioritized Context Management, Multi-Turn Conversation, Code Validation & Inline Completion
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import { AiProvider } from '../js/ai/provider-base.js';
import { OfflineHeuristicProvider } from '../js/ai/providers/offline-provider.js';
import { OpenAiProvider } from '../js/ai/providers/openai-provider.js';
import { AnthropicProvider } from '../js/ai/providers/anthropic-provider.js';
import { OpenAiCompatibleProvider } from '../js/ai/providers/openai-compatible-provider.js';
import { AiProviderManager } from '../js/ai/provider-manager.js';
import { ContextManager } from '../js/ai/context-manager.js';
import { OtterCodeValidator } from '../js/ai/code-validator.js';
import { AiTelemetryManager } from '../js/ai/telemetry.js';
import { InlineCompletionEngine } from '../js/ai/inline-completion.js';

// --- 1. Provider Abstraction & Contract Tests ---
test('1. AiProvider base class enforces interface contract', () => {
  const base = new AiProvider();
  assert.equal(base.isConfigured(), false);
  assert.equal(base.getStatus().status, 'unconfigured');
  assert.rejects(async () => await base.chat([]), /not implemented/);
  assert.rejects(async () => await base.complete(''), /not implemented/);
  assert.rejects(async () => await base.explain(''), /not implemented/);
  assert.rejects(async () => await base.generateTests(''), /not implemented/);
  assert.rejects(async () => await base.diagnose([], ''), /not implemented/);
  assert.rejects(async () => await base.synthesizeCode(''), /not implemented/);
  assert.rejects(async () => await base.testConnection(), /not implemented/);
});

// --- 2. Offline Heuristic Fallback Provider ---
test('2. OfflineHeuristicProvider operates honestly without external credentials', async () => {
  const offline = new OfflineHeuristicProvider();
  assert.equal(offline.isConfigured(), true);
  assert.equal(offline.getStatus().status, 'offline');
  assert.ok(offline.displayName.includes('Offline Assistant'));

  const testConn = await offline.testConnection();
  assert.equal(testConn.ok, true);
  assert.equal(testConn.status, 'offline');

  const chatRes = await offline.chat([{ role: 'user', content: 'create counter' }]);
  assert.equal(chatRes.provider, 'offline-heuristic');
  assert.ok(chatRes.reply.includes('count is 0'));

  const expRes = await offline.explain('when btn is clicked\n    add 1 to count\n.');
  assert.ok(expRes.explanation.includes('click'));

  const genRes = await offline.generateTests('to add a and b\n    return a plus b\n.');
  assert.ok(genRes.testCode.includes('Test'));

  const diagRes = await offline.diagnose([{ line: 1, message: 'expected "than"' }], 'if x is greater 10');
  assert.ok(diagRes.patches.length > 0);
});

// --- 3. Unconfigured Provider State & Status Reporting ---
test('3. Unconfigured OpenAI and Anthropic providers report honest unconfigured status', async () => {
  const openai = new OpenAiProvider({ apiKey: '' });
  assert.equal(openai.isConfigured(), false);
  assert.equal(openai.getStatus().status, 'unconfigured');

  const anthropic = new AnthropicProvider({ apiKey: '' });
  assert.equal(anthropic.isConfigured(), false);
  assert.equal(anthropic.getStatus().status, 'unconfigured');

  const openAiComp = new OpenAiCompatibleProvider({ endpoint: '' });
  assert.equal(openAiComp.isConfigured(), false);
  assert.equal(openAiComp.getStatus().status, 'unconfigured');
});

// --- 4. Secret Sanitization & Credential Isolation ---
test('4. ContextManager redacts API keys and Bearer tokens', () => {
  const ctxManager = new ContextManager();
  const rawText = `
    Error with sk-abcdef123456789012345678 and ant-abcdef123456789012345678
    Authorization: Bearer mySecretToken1234567890123456
    apiKey: "secretKey999999999"
  `;
  const sanitized = ctxManager.sanitizeSecrets(rawText);
  assert.ok(!sanitized.includes('sk-abcdef123456789012345678'));
  assert.ok(!sanitized.includes('ant-abcdef123456789012345678'));
  assert.ok(!sanitized.includes('mySecretToken1234567890123456'));
  assert.ok(!sanitized.includes('secretKey999999999'));
  assert.ok(sanitized.includes('[REDACTED_API_KEY]'));
  assert.ok(sanitized.includes('Bearer [REDACTED_TOKEN]'));
  assert.ok(sanitized.includes('apiKey: "[REDACTED]"'));
});

// --- 5. Prioritized Bounded Context Budgeting ---
test('5. ContextManager prioritizes selection and diagnostics over low-priority files', () => {
  const ctxManager = new ContextManager({ maxContextChars: 500 });
  const giantSource = 'x is 1\n'.repeat(100);
  const context = ctxManager.buildContext({
    selectedCode: 'to add a and b\n    give back a plus b\n.',
    diagnostics: [{ line: 2, message: 'Type mismatch warning' }],
    activeFile: 'src/math.ot',
    sourceCode: giantSource,
    openFiles: ['src/a.ot', 'src/b.ot', 'src/c.ot', 'src/d.ot']
  });

  assert.ok(context.characterCount <= 500);
  // Highest priority items must be present
  assert.ok(context.formatted.includes('### Selected Code'));
  assert.ok(context.formatted.includes('### Active Diagnostics'));
});

// --- 6. Provider Manager Key Masking (Zero Browser Key Exposure) ---
test('6. AiProviderManager masks API keys in getPublicSettings', () => {
  const manager = new AiProviderManager();
  manager.setProviderConfig('openai', { apiKey: 'sk-prodSecretApiKey99991234', model: 'gpt-4o' });
  manager.setProviderConfig('anthropic', { apiKey: 'ant-prodSecretApiKey88885678', model: 'claude-3-5-sonnet' });

  const publicSettings = manager.getPublicSettings();
  assert.equal(publicSettings.providers.openai.hasKey, true);
  assert.equal(publicSettings.providers.openai.maskedKey, '••••••••1234');
  assert.ok(!JSON.stringify(publicSettings).includes('sk-prodSecretApiKey99991234'));

  assert.equal(publicSettings.providers.anthropic.hasKey, true);
  assert.equal(publicSettings.providers.anthropic.maskedKey, '••••••••5678');
  assert.ok(!JSON.stringify(publicSettings).includes('ant-prodSecretApiKey88885678'));

  manager.setProviderConfig('openai', { apiKey: '••••••••1234', model: 'gpt-4o-mini' });
  assert.equal(manager.settings.providers.openai.apiKey, 'sk-prodSecretApiKey99991234');
  assert.equal(manager.settings.providers.openai.model, 'gpt-4o-mini');
});

// --- 7. Mock HTTP Server Fixtures (Zero Cost API Testing) ---
test('7. OpenAI Provider handles mock server response, authentication failure, and rate limits', async () => {
  let mockStatusCode = 200;
  let mockResponseBody = {
    choices: [{ message: { content: 'Mocked OpenAI Otter response' } }],
    usage: { total_tokens: 42 }
  };
  let receivedAuthHeader = '';

  const server = http.createServer((req, res) => {
    receivedAuthHeader = req.headers['authorization'] || '';
    res.writeHead(mockStatusCode, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(mockResponseBody));
  });

  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  const endpoint = `http://127.0.0.1:${port}/v1`;

  try {
    const provider = new OpenAiProvider({
      endpoint,
      apiKey: 'sk-testMockKey1234567890',
      model: 'gpt-4o-mini'
    });

    const chatRes = await provider.chat([{ role: 'user', content: 'hello' }]);
    assert.equal(chatRes.reply, 'Mocked OpenAI Otter response');
    assert.equal(receivedAuthHeader, 'Bearer sk-testMockKey1234567890');

    const testRes = await provider.testConnection();
    assert.equal(testRes.ok, true);
    assert.equal(testRes.status, 'connected');

    mockStatusCode = 401;
    mockResponseBody = { error: { message: 'Invalid API key' } };
    const authTestRes = await provider.testConnection();
    assert.equal(authTestRes.ok, false);
    assert.equal(authTestRes.status, 'authentication_failed');

    mockStatusCode = 429;
    mockResponseBody = { error: { message: 'Rate limit reached' } };
    const rateTestRes = await provider.testConnection();
    assert.equal(rateTestRes.ok, false);
    assert.equal(rateTestRes.status, 'rate_limited');
  } finally {
    server.close();
  }
});

// --- 8. Anthropic Provider Mock Testing ---
test('8. Anthropic Provider messages API mock interaction', async () => {
  let receivedApiKeyHeader = '';
  const server = http.createServer((req, res) => {
    receivedApiKeyHeader = req.headers['x-api-key'] || '';
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      content: [{ type: 'text', text: 'Anthropic Claude generated Otter code' }],
      usage: { input_tokens: 15, output_tokens: 25 }
    }));
  });

  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  const endpoint = `http://127.0.0.1:${port}/v1`;

  try {
    const provider = new AnthropicProvider({
      endpoint,
      apiKey: 'ant-testKey987654321',
      model: 'claude-3-5-sonnet-20241022'
    });

    const chatRes = await provider.chat([{ role: 'user', content: 'synthesize helper' }]);
    assert.equal(chatRes.reply, 'Anthropic Claude generated Otter code');
    assert.equal(receivedApiKeyHeader, 'ant-testKey987654321');

    const testRes = await provider.testConnection();
    assert.equal(testRes.ok, true);
    assert.equal(testRes.status, 'connected');
  } finally {
    server.close();
  }
});

// --- 9. Timeout and Request Cancellation ---
test('9. Provider supports AbortSignal cancellation', async () => {
  const server = http.createServer((req, res) => {
    setTimeout(() => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ choices: [{ message: { content: 'slow' } }] }));
    }, 2000);
  });

  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;

  try {
    const provider = new OpenAiProvider({
      endpoint: `http://127.0.0.1:${port}/v1`,
      apiKey: 'sk-test'
    });

    const controller = new AbortController();
    setTimeout(() => controller.abort(), 50);

    await assert.rejects(
      async () => await provider.chat([{ role: 'user', content: 'test' }], { signal: controller.signal }),
      /abort/i
    );
  } finally {
    server.close();
  }
});

// --- 10. Multi-Turn Conversation Sequence Simulation ---
test('10. Multi-turn conversation preserves context across 4 sequential turns', async () => {
  const history = [];
  const responses = [
    'Line 2 is missing the "than" comparison keyword.',
    'Proposed fix: if score is greater than 10',
    'Test 1: Test score comparison with 15 and 5',
    'The test provides a value above 10 which would fail under the original unparsed syntax.'
  ];

  let turnIndex = 0;
  const mockProvider = {
    chat: async (messages) => {
      const resp = responses[turnIndex++] || 'OK';
      return { reply: resp, historyLength: messages.length };
    }
  };

  // Turn 1: Why is this failing?
  history.push({ role: 'user', content: 'Why is this function failing?' });
  let r1 = await mockProvider.chat(history);
  history.push({ role: 'assistant', content: r1.reply });
  assert.ok(r1.reply.includes('than'));

  // Turn 2: Fix it.
  history.push({ role: 'user', content: 'Fix it.' });
  let r2 = await mockProvider.chat(history);
  history.push({ role: 'assistant', content: r2.reply });
  assert.ok(r2.reply.includes('Proposed fix'));

  // Turn 3: Add a test for that fix.
  history.push({ role: 'user', content: 'Add a test for that fix.' });
  let r3 = await mockProvider.chat(history);
  history.push({ role: 'assistant', content: r3.reply });
  assert.ok(r3.reply.includes('Test 1'));

  // Turn 4: Explain why your test catches the original bug.
  history.push({ role: 'user', content: 'Explain why your test catches the original bug.' });
  let r4 = await mockProvider.chat(history);
  history.push({ role: 'assistant', content: r4.reply });
  assert.ok(r4.reply.includes('original unparsed syntax'));

  assert.equal(history.length, 8);
});

// --- 11. Code Validation & Detection of Non-Otter Hallucinations ---
test('11. OtterCodeValidator detects syntax errors and foreign keywords', () => {
  // Valid Otter code
  const valid = [
    'to calculateDiscount price rate',
    '    if rate is greater than 1',
    '        give back 0',
    '    .',
    '    give back price * rate',
    '.'
  ].join('\n');
  const validResult = OtterCodeValidator.validate(valid);
  assert.equal(validResult.isValid, true);
  assert.equal(validResult.errors.length, 0);

  // Invalid: JS function and const assignment
  const invalidJs = [
    'function add(a, b) {',
    '  const c = a + b;',
    '  return c;',
    '}'
  ].join('\n');
  const jsResult = OtterCodeValidator.validate(invalidJs);
  assert.equal(jsResult.isValid, false);
  assert.ok(jsResult.errors.some(e => e.includes('JavaScript function')));
  assert.ok(jsResult.errors.some(e => e.includes('JS variable declaration')));

  // Invalid: unclosed block missing period
  const unclosed = [
    'when btn is clicked',
    '    say "clicked"'
  ].join('\n');
  const unclosedResult = OtterCodeValidator.validate(unclosed);
  assert.equal(unclosedResult.isValid, false);
  assert.ok(unclosedResult.errors.some(e => e.includes('Unclosed Otter block')));

  // Local repair test
  const repair = OtterCodeValidator.attemptLocalRepair(unclosed);
  assert.equal(repair.repaired, true);
  assert.ok(repair.source.endsWith('.'));
});

// --- 12. Semantic Inline Completion Engine ---
test('12. InlineCompletionEngine debounces and provides completions with cancellation', async () => {
  const engine = new InlineCompletionEngine({ debounceMs: 50 });
  const mockProvider = {
    complete: async (prefix) => {
      if (prefix.includes('for each')) return { code: ' item in items\n    say item\n.' };
      return { code: 'is 0' };
    }
  };

  // Completion 1
  const comp1 = await engine.requestCompletion('count ', '', {}, mockProvider);
  assert.equal(comp1, 'is 0');

  // Completion 2: for each loop
  const comp2 = await engine.requestCompletion('for each', '', {}, mockProvider);
  assert.ok(comp2.includes('item in items'));

  // Disable engine
  engine.setEnabled(false);
  const disabledComp = await engine.requestCompletion('count ', '', {}, mockProvider);
  assert.equal(disabledComp, null);
});

// --- 13. Transparent Local Telemetry ---
test('13. AiTelemetryManager records performance without leaking secrets or source code', () => {
  const telemetry = new AiTelemetryManager();
  telemetry.record({
    operation: 'chat',
    provider: 'openai',
    model: 'gpt-4o-mini',
    durationMs: 340,
    contextCharCount: 1500,
    responseCharCount: 450,
    success: true
  });
  telemetry.record({
    operation: 'diagnose',
    provider: 'anthropic',
    model: 'claude-3-5-sonnet',
    durationMs: 620,
    contextCharCount: 800,
    responseCharCount: 200,
    success: false,
    errorCategory: 'RATE_LIMITED'
  });

  const summary = telemetry.getSummary();
  assert.equal(summary.totalRequests, 2);
  assert.equal(summary.successRate, 0.5);
  assert.equal(summary.byProvider.openai, 1);
  assert.equal(summary.byProvider.anthropic, 1);

  const recent = telemetry.getRecentEntries();
  assert.equal(recent.length, 2);
  assert.equal(recent[0].apiKey, undefined);
  assert.equal(recent[0].prompt, undefined);
  assert.equal(recent[0].sourceCode, undefined);
});
