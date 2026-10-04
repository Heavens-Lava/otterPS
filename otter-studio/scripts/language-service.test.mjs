// language-service.test.mjs - Automated tests for Section 9 (Incremental Lexer/Parser, Incremental AST, LSP Server)
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { IncrementalLexer, IncrementalAst } from '../js/language/incremental-parser.js';
import { OtterLspServer } from '../js/language/lsp-server.js';

test('IncrementalLexer tokenizes source and reuses unchanged lines', () => {
  const source1 = [
    'let count is 10',
    'let name is "Otter"',
    'add 5 to count',
    'say count'
  ].join('\n');

  const lexer = new IncrementalLexer();
  const tokens1 = lexer.tokenize(source1);
  assert.ok(tokens1.length > 0, 'Tokens should be emitted');
  const stats1 = lexer.getStats();
  assert.equal(stats1.reusedLines, 0, 'First run has no reused lines');
  assert.equal(stats1.totalLines, 4, '4 lines processed');

  // Edit line 2 only
  const source2 = [
    'let count is 10',
    'let name is "Otter Language"',
    'add 5 to count',
    'say count'
  ].join('\n');

  const tokens2 = lexer.tokenize(source2);
  assert.ok(tokens2.length > 0, 'Tokens should be emitted for modified source');
  const stats2 = lexer.getStats();
  assert.ok(stats2.reusedLines >= 3, `Expected at least 3 reused lines, got ${stats2.reusedLines}`);
  assert.equal(stats2.relexedLines, 1, 'Only modified line re-lexed');
});

test('IncrementalAst tracks statements and symbol declarations', () => {
  const source1 = [
    'let total is 100',
    'to calculate n',
    '    say n',
    '.',
    'let result is 200'
  ].join('\n');

  const ast = new IncrementalAst();
  const stmts1 = ast.parse(source1);

  assert.ok(stmts1.length >= 3, 'Multiple top-level statements parsed');
  const stats1 = ast.getStats();
  assert.equal(stats1.reusedNodes, 0, 'First run has no reused nodes');

  // Edit statement 3 only
  const source2 = [
    'let total is 100',
    'to calculate n',
    '    say n',
    '.',
    'let result is 500'
  ].join('\n');

  const stmts2 = ast.parse(source2);
  assert.ok(stmts2.length >= 3, 'Parsed modified statements');
  const stats2 = ast.getStats();
  assert.ok(stats2.reusedNodes >= 2, `Expected reused nodes >= 2, got ${stats2.reusedNodes}`);
});

test('OtterLspServer handles initialize, didOpen, hover, definition, and references', () => {
  const server = new OtterLspServer();

  // 1. Initialize
  const initRes = server.handleMessage({
    jsonrpc: '2.0',
    id: 1,
    method: 'initialize',
    params: { capabilities: {} }
  });
  assert.equal(initRes.id, 1);
  assert.ok(initRes.result.capabilities.hoverProvider);
  assert.ok(initRes.result.capabilities.definitionProvider);
  assert.ok(initRes.result.capabilities.referencesProvider);
  assert.ok(initRes.result.capabilities.completionProvider);
  assert.ok(initRes.result.capabilities.renameProvider);

  // 2. Open document
  const uri = 'file:///workspace/main.ot';
  const code = [
    'let score is 42',
    'add 10 to score',
    'say score'
  ].join('\n');

  server.handleMessage({
    jsonrpc: '2.0',
    method: 'textDocument/didOpen',
    params: {
      textDocument: { uri, languageId: 'otter', version: 1, text: code }
    }
  });

  assert.ok(server.documents.has(uri), 'Document should be stored');

  // 3. Hover over variable
  const hoverRes = server.handleMessage({
    jsonrpc: '2.0',
    id: 2,
    method: 'textDocument/hover',
    params: {
      textDocument: { uri },
      position: { line: 0, character: 5 } // 'score'
    }
  });
  assert.equal(hoverRes.id, 2);
  assert.ok(hoverRes.result);
  assert.match(hoverRes.result.contents.value, /score/);

  // 4. Hover over keyword
  const keywordHover = server.handleMessage({
    jsonrpc: '2.0',
    id: 3,
    method: 'textDocument/hover',
    params: {
      textDocument: { uri },
      position: { line: 1, character: 1 } // 'add'
    }
  });
  assert.equal(keywordHover.id, 3);
  assert.ok(keywordHover.result);
  assert.match(keywordHover.result.contents.value, /add/);

  // 5. Definition
  const defRes = server.handleMessage({
    jsonrpc: '2.0',
    id: 4,
    method: 'textDocument/definition',
    params: {
      textDocument: { uri },
      position: { line: 2, character: 5 } // 'score' in `say score`
    }
  });
  assert.equal(defRes.id, 4);
  assert.ok(defRes.result);
  assert.equal(defRes.result.uri, uri);
  assert.equal(defRes.result.range.start.line, 0); // defined on line 0

  // 6. References
  const refRes = server.handleMessage({
    jsonrpc: '2.0',
    id: 5,
    method: 'textDocument/references',
    params: {
      textDocument: { uri },
      position: { line: 0, character: 5 } // 'score'
    }
  });
  assert.equal(refRes.id, 5);
  assert.ok(Array.isArray(refRes.result));
  assert.equal(refRes.result.length, 3, 'score referenced 3 times');
});

test('OtterLspServer handles completion, rename, documentSymbol, and codeAction', () => {
  const server = new OtterLspServer();
  const uri = 'file:///workspace/app.ot';
  const code = [
    'let counter is 0',
    'function increment with amount',
    '    add amount to counter',
    'say counter'
  ].join('\n');

  server.handleMessage({
    jsonrpc: '2.0',
    method: 'textDocument/didOpen',
    params: {
      textDocument: { uri, languageId: 'otter', version: 1, text: code }
    }
  });

  // 1. Completion
  const compRes = server.handleMessage({
    jsonrpc: '2.0',
    id: 10,
    method: 'textDocument/completion',
    params: {
      textDocument: { uri },
      position: { line: 0, character: 3 }
    }
  });
  assert.equal(compRes.id, 10);
  assert.ok(Array.isArray(compRes.result.items));
  const labels = compRes.result.items.map(i => i.label);
  assert.ok(labels.includes('counter'));
  assert.ok(labels.includes('increment'));
  assert.ok(labels.includes('function'));

  // 2. Document Symbol
  const symRes = server.handleMessage({
    jsonrpc: '2.0',
    id: 11,
    method: 'textDocument/documentSymbol',
    params: { textDocument: { uri } }
  });
  assert.equal(symRes.id, 11);
  assert.ok(Array.isArray(symRes.result));
  assert.ok(symRes.result.some(s => s.name === 'counter'));
  assert.ok(symRes.result.some(s => s.name === 'increment'));

  // 3. Rename
  const renameRes = server.handleMessage({
    jsonrpc: '2.0',
    id: 12,
    method: 'textDocument/rename',
    params: {
      textDocument: { uri },
      position: { line: 0, character: 6 }, // 'counter'
      newName: 'totalCount'
    }
  });
  assert.equal(renameRes.id, 12);
  assert.ok(renameRes.result.changes[uri]);
  assert.equal(renameRes.result.changes[uri].length, 3, 'All 3 occurrences of counter renamed');
  assert.equal(renameRes.result.changes[uri][0].newText, 'totalCount');

  // 4. CodeAction
  const actionRes = server.handleMessage({
    jsonrpc: '2.0',
    id: 13,
    method: 'textDocument/codeAction',
    params: {
      textDocument: { uri },
      range: { start: { line: 2, character: 4 }, end: { line: 2, character: 10 } },
      context: { diagnostics: [] }
    }
  });
  assert.equal(actionRes.id, 13);
  assert.ok(Array.isArray(actionRes.result));
});

test('HTTP POST /api/lsp dispatches JSON-RPC requests correctly', async () => {
  const reqPayload = JSON.stringify({
    jsonrpc: '2.0',
    id: 99,
    method: 'initialize',
    params: { capabilities: {} }
  });

  const res = await new Promise((resolve, reject) => {
    const req = http.request(
      'http://127.0.0.1:4200/api/lsp',
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(reqPayload)
        }
      },
      (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          resolve({ statusCode: res.statusCode, body: JSON.parse(data) });
        });
      }
    );
    req.on('error', reject);
    req.write(reqPayload);
    req.end();
  });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.jsonrpc, '2.0');
  assert.equal(res.body.id, 99);
  assert.ok(res.body.result.capabilities.hoverProvider);
  assert.equal(res.body.result.serverInfo.name, 'otter-language-server');
});
