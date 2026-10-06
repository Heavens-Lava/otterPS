import test from 'node:test';
import assert from 'node:assert/strict';

const PORT = Number(process.env.OTTER_STUDIO_PORT || 4200);
const baseUrl = `http://127.0.0.1:${PORT}`;

test('Live Studio Server API: /api/ai/chat', async () => {
  const res = await fetch(`${baseUrl}/api/ai/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: 'create a counter with button',
      context: { activeFile: 'main.ot', source: 'count is 0' }
    })
  });
  assert.equal(res.ok, true);
  const data = await res.json();
  assert.ok(data.reply);
  assert.ok(data.reply.includes('count is 0'));
  assert.equal(data.isPrototype, true);
});

test('Live Studio Server API: /api/ai/explain', async () => {
  const res = await fetch(`${baseUrl}/api/ai/explain`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      source: 'when btn is clicked\n    add 1 to count\n.'
    })
  });
  assert.equal(res.ok, true);
  const data = await res.json();
  assert.ok(data.explanation);
  assert.ok(data.explanation.toLowerCase().includes('click'));
});

test('Live Studio Server API: /api/ai/generate-tests', async () => {
  const res = await fetch(`${baseUrl}/api/ai/generate-tests`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      source: 'to add a and b\n    return a plus b\n.',
      moduleName: 'math-utils'
    })
  });
  assert.equal(res.ok, true);
  const data = await res.json();
  assert.ok(data.testSuite);
  assert.ok(data.testSuite.includes('math-utils.ot'));
});

test('Live Studio Server API: /api/ai/fix-diagnostics', async () => {
  const res = await fetch(`${baseUrl}/api/ai/fix-diagnostics`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      source: 'if x is greater 10\n    say "high"\n.',
      diagnostics: [{ line: 1, message: 'expected "than" after "greater"' }]
    })
  });
  assert.equal(res.ok, true);
  const data = await res.json();
  assert.ok(data.fixes);
  assert.equal(data.fixes.length, 1);
  assert.ok(data.fixes[0].fixedLine.includes('is greater than'));
});
