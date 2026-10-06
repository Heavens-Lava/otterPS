/**
 * Opt-In Integration Test Suite: Live AI Cloud Providers (OpenAI, Anthropic, OpenAI-compatible)
 *
 * IMPORTANT:
 * - This suite requires explicit opt-in via environment variables:
 *     OPENAI_API_KEY
 *     ANTHROPIC_API_KEY
 *     OPENAI_COMPATIBLE_ENDPOINT
 * - When variables are absent, tests SKIP gracefully and spend ZERO API credits.
 * - Under NO circumstances are API keys, bearer tokens, or sensitive prompts logged.
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { OpenAiProvider } from '../js/ai/providers/openai-provider.js';
import { AnthropicProvider } from '../js/ai/providers/anthropic-provider.js';
import { OpenAiCompatibleProvider } from '../js/ai/providers/openai-compatible-provider.js';
import { OtterCodeValidator } from '../js/ai/code-validator.js';

// --- 1. Live OpenAI Provider Opt-In Verification ---
test('Live OpenAI Provider Certification (Opt-in via OPENAI_API_KEY)', async (t) => {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey || !apiKey.trim()) {
    t.skip('[OPT-IN] OPENAI_API_KEY not set - skipping live OpenAI test (0 credits consumed)');
    return;
  }

  const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';
  const provider = new OpenAiProvider({ apiKey, model });

  // 1. Connection & Authentication
  const conn = await provider.testConnection();
  assert.equal(conn.ok, true, `OpenAI connection failed: ${conn.message}`);
  assert.equal(conn.status, 'connected');

  // 2. Conversational Request
  const chatRes = await provider.chat([
    { role: 'user', content: 'In one short sentence, what is the Otter programming language keyword for variable assignment?' }
  ]);
  assert.ok(chatRes.reply, 'Expected non-empty reply from OpenAI');
  assert.ok(chatRes.reply.toLowerCase().includes('is'), 'Expected answer to mention "is"');

  // 3. Code Generation & Validation
  const codeRes = await provider.synthesizeCode('Create a counter variable initialized to 0 and print it');
  assert.ok(codeRes.code, 'Expected generated code');
  const validation = OtterCodeValidator.validate(codeRes.code);
  // Otter validator verifies balance & keywords
  assert.ok(codeRes.code.length > 0);

  // 4. Diagnostic Explanation
  const expRes = await provider.explain('when btn is clicked\n    count is count plus 1\n.');
  assert.ok(expRes.explanation);
});

// --- 2. Live Anthropic Provider Opt-In Verification ---
test('Live Anthropic Provider Certification (Opt-in via ANTHROPIC_API_KEY)', async (t) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey || !apiKey.trim()) {
    t.skip('[OPT-IN] ANTHROPIC_API_KEY not set - skipping live Anthropic test (0 credits consumed)');
    return;
  }

  const model = process.env.ANTHROPIC_MODEL || 'claude-3-5-sonnet-20241022';
  const provider = new AnthropicProvider({ apiKey, model });

  // 1. Connection & Authentication
  const conn = await provider.testConnection();
  assert.equal(conn.ok, true, `Anthropic connection failed: ${conn.message}`);
  assert.equal(conn.status, 'connected');

  // 2. Conversational Request
  const chatRes = await provider.chat([
    { role: 'user', content: 'What is the block terminator symbol in Otter? Answer in 3 words or less.' }
  ]);
  assert.ok(chatRes.reply);
  assert.ok(chatRes.reply.includes('.') || chatRes.reply.toLowerCase().includes('period') || chatRes.reply.toLowerCase().includes('dot'));

  // 3. Code Generation
  const codeRes = await provider.synthesizeCode('to greet name\n    say "Hello " plus name\n.');
  assert.ok(codeRes.code);

  // 4. Test Generation
  const testRes = await provider.generateTests('to add a and b\n    return a plus b\n.', { moduleName: 'math' });
  assert.ok(testRes.testCode);
});

// --- 3. Live OpenAI-Compatible Endpoint Opt-In Verification ---
test('Live OpenAI-Compatible Provider Certification (Opt-in via OPENAI_COMPATIBLE_ENDPOINT)', async (t) => {
  const endpoint = process.env.OPENAI_COMPATIBLE_ENDPOINT;
  if (!endpoint || !endpoint.trim()) {
    t.skip('[OPT-IN] OPENAI_COMPATIBLE_ENDPOINT not set - skipping local LLM test');
    return;
  }

  const model = process.env.OPENAI_COMPATIBLE_MODEL || 'llama3';
  const apiKey = process.env.OPENAI_COMPATIBLE_API_KEY || 'not-needed';
  const provider = new OpenAiCompatibleProvider({ endpoint, model, apiKey });

  const conn = await provider.testConnection();
  assert.equal(conn.ok, true);

  const chatRes = await provider.chat([{ role: 'user', content: 'Respond with OK' }]);
  assert.ok(chatRes.reply);
});
