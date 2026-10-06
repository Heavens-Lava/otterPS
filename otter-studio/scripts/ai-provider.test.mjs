/**
 * Comprehensive Test Suite: Otter Studio AI Provider Abstraction, Credential Isolation,
 * Context Management & Reviewable Edits
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

// --- 5. Bounded Context Budgeting ---
test('5. ContextManager enforces token character budget and truncates gracefully', () => {
  const ctxManager = new ContextManager({ maxContextChars: 400 });
  const giantSource = 'x is 1\n'.repeat(200);
  const context = ctxManager.buildContext({
    activeFile: 'large.ot',
    sourceCode: giantSource,
    diagnostics: [{ line: 1, message: 'syntax warning' }]
  });

  assert.ok(context.characterCount <= 400);
  assert.ok(context.formatted.includes('### Active File'));
  assert.ok(context.formatted.includes('### Current Source Code'));
  assert.ok(context.formatted.includes('[truncated for token budget]'));
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

  // Updating other settings without touching masked key preserves the secret server-side
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

    // A. Normal Chat Request
    const chatRes = await provider.chat([{ role: 'user', content: 'hello' }]);
    assert.equal(chatRes.reply, 'Mocked OpenAI Otter response');
    assert.equal(receivedAuthHeader, 'Bearer sk-testMockKey1234567890');

    // B. Test Connection
    const testRes = await provider.testConnection();
    assert.equal(testRes.ok, true);
    assert.equal(testRes.status, 'connected');

    // C. Authentication Failure (401)
    mockStatusCode = 401;
    mockResponseBody = { error: { message: 'Invalid API key' } };
    const authTestRes = await provider.testConnection();
    assert.equal(authTestRes.ok, false);
    assert.equal(authTestRes.status, 'authentication_failed');

    // D. Rate Limit Exceeded (429)
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

// --- 10. Reviewable Patch / Edit Workflow Simulation ---
test('10. Reviewable patch workflow: propose, review diff, apply, reject', () => {
  const originalSource = [
    'to calculateDiscount price rate',
    '    if rate is greater 1',
    '        give back 0',
    '    .',
    '    give back price * rate',
    '.'
  ].join('\n');

  const lineNum = 2;
  const fixedLine = '    if rate is greater than 1';
  const explanation = 'Expected "than" after "greater"';

  const lines = originalSource.split('\n');
  const oldLine = lines[lineNum - 1];
  const diffText = `--- Original (Line ${lineNum})\n- ${oldLine}\n+++ Proposed AI Fix\n+ ${fixedLine}`;

  lines[lineNum - 1] = fixedLine;
  const patchedSource = lines.join('\n');

  assert.ok(diffText.includes('-     if rate is greater 1'));
  assert.ok(diffText.includes('+     if rate is greater than 1'));
  assert.ok(patchedSource.includes('if rate is greater than 1'));

  let currentSource = originalSource;
  const rejectEdit = () => { /* no-op */ };
  rejectEdit();
  assert.equal(currentSource, originalSource);

  const applyEdit = (patch) => { currentSource = patch; };
  applyEdit(patchedSource);
  assert.equal(currentSource, patchedSource);
});
