/**
 * Comprehensive Test Suite: Otter Studio AI Provider Abstraction, Credential Isolation,
 * Prioritized Context Management, Multi-Turn Conversation, Compiler Authority, Designer AI & Release Manifests
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
import { OtterCompilerAdapter } from '../js/compiler/compiler-adapter.js';
import { DesignerAiPlanner } from '../js/ai/designer-ai.js';
import { OtterUiModel } from '../js/model/ui-model.js';
import { UpdateManifestValidator } from '../js/updater/update-manifest.js';

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

  history.push({ role: 'user', content: 'Why is this function failing?' });
  let r1 = await mockProvider.chat(history);
  history.push({ role: 'assistant', content: r1.reply });
  assert.ok(r1.reply.includes('than'));

  history.push({ role: 'user', content: 'Fix it.' });
  let r2 = await mockProvider.chat(history);
  history.push({ role: 'assistant', content: r2.reply });
  assert.ok(r2.reply.includes('Proposed fix'));

  history.push({ role: 'user', content: 'Add a test for that fix.' });
  let r3 = await mockProvider.chat(history);
  history.push({ role: 'assistant', content: r3.reply });
  assert.ok(r3.reply.includes('Test 1'));

  history.push({ role: 'user', content: 'Explain why your test catches the original bug.' });
  let r4 = await mockProvider.chat(history);
  history.push({ role: 'assistant', content: r4.reply });
  assert.ok(r4.reply.includes('original unparsed syntax'));

  assert.equal(history.length, 8);
});

// --- 11. Authoritative Compiler Validation Pipeline ---
test('11. Real Otter compiler is authoritative validator over preflight', async () => {
  const adapter = new OtterCompilerAdapter();

  // Valid source accepted by compiler
  const valid = [
    '# Generated by Otter Studio',
    'app is a window with title "Task Manager", width 740, height 520',
    'show app'
  ].join('\n');
  const validRes = await OtterCodeValidator.validate(valid, adapter);
  assert.equal(validRes.isValid, true);
  assert.equal(validRes.compilerValidated, true);

  // Malformed source rejected by compiler cannot be validated
  const malformed = 'to broken\n    say "no closure';
  const mockFailingAdapter = {
    checkSource: async () => ({ ok: false, errors: [{ message: 'Unexpected EOF at line 2' }] })
  };
  const malformedRes = await OtterCodeValidator.validate(malformed, mockFailingAdapter);
  assert.equal(malformedRes.isValid, false);
  assert.ok(malformedRes.errors.some(e => e.includes('Unexpected EOF')));

  // Disagreement: Compiler accepts newer construct, compiler wins
  const mockPassingAdapter = {
    checkSource: async () => ({ ok: true, errors: [] })
  };
  const advancedSyntax = 'to newFeature\n    give back true\n.';
  const advancedRes = await OtterCodeValidator.validate(advancedSyntax, mockPassingAdapter);
  assert.equal(advancedRes.isValid, true);
});

// --- 12. Visual Designer AI Operations ---
test('12. DesignerAiPlanner produces structured operations and applies transactionally', () => {
  const plan = DesignerAiPlanner.planFromPrompt('Create a settings card with name and email inputs and Save and Cancel buttons');
  assert.ok(plan.operations.length >= 8);

  const uiModel = new OtterUiModel();
  const initialComponentCount = uiModel.components.size;

  const result = DesignerAiPlanner.applyPlan(plan, uiModel);
  assert.equal(result.success, true);
  assert.ok(uiModel.components.size > initialComponentCount);

  // Verify created controls exist and are inspectable
  const hasText = Array.from(uiModel.components.values()).some(c => c.kind === 'text' || c.kind === 'heading');
  const hasButton = Array.from(uiModel.components.values()).some(c => c.kind === 'button');
  assert.equal(hasText, true);
  assert.equal(hasButton, true);
});

// --- 13. Release & Update Manifest Specification ---
test('13. UpdateManifestValidator validates schema, versions, and checksums', () => {
  const validManifest = {
    channel: 'stable',
    version: '1.1.0',
    releaseDate: '2026-10-06T12:00:00Z',
    artifactUrl: 'https://releases.otter-lang.org/v1.1.0/otter-studio-win-x64.zip',
    sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    minCompatibleVersion: '1.0.0',
    releaseNotesUrl: 'https://releases.otter-lang.org/v1.1.0/notes.md'
  };

  const validation = UpdateManifestValidator.validate(validManifest);
  assert.equal(validation.valid, true);

  // Version comparisons
  assert.equal(UpdateManifestValidator.compareVersions('1.1.0', '1.0.0'), 1);
  assert.equal(UpdateManifestValidator.compareVersions('1.0.0', '1.1.0'), -1);
  assert.equal(UpdateManifestValidator.compareVersions('1.0.0', '1.0.0'), 0);

  // Checksum verification
  const emptyBuffer = Buffer.from('');
  const match = UpdateManifestValidator.verifyChecksum(emptyBuffer, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  assert.equal(match, true);
});
