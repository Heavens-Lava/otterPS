import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import fs from 'node:fs';
import http from 'node:http';
import { OtterCodeValidator } from '../js/ai/code-validator.js';
import { OtterCompilerAdapter } from '../js/compiler/compiler-adapter.js';
import { spawn } from 'node:child_process';

test('Authoritative Compiler Integration & Diagnostic Normalization (Real Toolchain)', async (t) => {
  const repoRoot = path.resolve(process.cwd(), '..');
  const adapter = new OtterCompilerAdapter({ repoRoot });

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

  await t.test('3. Exact line numbers, column pointers, and compiler explanation messages extracted', async () => {
    // Malformed Otter code on Line 3
    const codeWithLine3Error = 'say "Line 1"\n\nmake score is 100\n';
    const result = await OtterCodeValidator.validate(codeWithLine3Error, adapter);
    
    assert.equal(result.isValid, false, 'Authoritative compiler rejected invalid code');
    assert.ok(result.diagnostics.length > 0, 'Diagnostics extracted');
    
    const diag = result.diagnostics[0];
    assert.equal(diag.line, 3, 'Exact line 3 matched via (\\d+) pattern');
    assert.equal(diag.column, 1, 'Exact column 1 matched from caret pointer');
    assert.ok(diag.message.includes("I don't understand 'make'") || diag.message.includes("make"), 'Captured compiler explanation message');
    assert.ok(diag.suggestion.length > 0, 'Captured compiler suggestion');
  });

  await t.test('4. Relative module imports (use "module.ot") resolve in project directory', async () => {
    const tempProjDir = path.join(repoRoot, 'scratch', `test_module_proj_${Date.now()}`);
    fs.mkdirSync(tempProjDir, { recursive: true });
    
    try {
      // Create helper module in project directory
      fs.writeFileSync(path.join(tempProjDir, 'helper.ot'), 'to greet name\n    say "Hello "\n.\n', 'utf8');
      
      const moduleCode = 'use "helper.ot"\n\ngreet "Jeff"\n';
      const result = await OtterCodeValidator.validate(moduleCode, adapter, { projectRoot: tempProjDir });
      
      assert.equal(result.isValid, true, 'Relative module import resolved and validated');
      assert.equal(result.errors.length, 0, 'No errors on valid multi-file program');
    } finally {
      try { fs.rmSync(tempProjDir, { recursive: true, force: true }); } catch {}
    }
  });

  await t.test('5. Live Studio Server route POST /api/ai/validate-code returns compiler verdict and structured diagnostics', async () => {
    // Start serve.mjs child process on a test port
    const testPort = 39871;
    const serverProcess = spawn('node', ['serve.mjs'], {
      cwd: path.resolve(process.cwd()),
      env: { ...process.env, OTTER_STUDIO_PORT: String(testPort) },
      stdio: ['pipe', 'pipe', 'pipe']
    });

    // Wait for server to listen
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Server start timed out')), 8000);
      serverProcess.stdout.on('data', (data) => {
        if (data.toString().includes('running with Full Interaction Engine') || data.toString().includes(String(testPort))) {
          clearTimeout(timeout);
          resolve();
        }
      });
      serverProcess.on('error', (err) => {
        clearTimeout(timeout);
        reject(err);
      });
      // Fallback timer
      setTimeout(resolve, 2000);
    });

    try {
      // Test 1: POST invalid code to /api/ai/validate-code
      const invalidPayload = JSON.stringify({ source: 'say "Line 1"\n\nmake score is 100\n' });
      const invalidRes = await makePostRequest(`http://127.0.0.1:${testPort}/api/ai/validate-code`, invalidPayload);
      
      assert.equal(invalidRes.ok, true, 'Server responded with 200 OK');
      assert.equal(invalidRes.isValid, false, 'Live endpoint returns isValid: false for malformed code');
      assert.ok(Array.isArray(invalidRes.diagnostics), 'Diagnostics array returned in response');
      assert.ok(invalidRes.diagnostics.length > 0, 'Non-empty diagnostics returned');
      assert.equal(invalidRes.diagnostics[0].line, 3, 'Live route diagnostic correctly reports Line 3');
      assert.ok(invalidRes.diagnostics[0].message.includes("I don't understand 'make'") || invalidRes.diagnostics[0].message.includes("make"), 'Live route returns compiler explanation');

      // Test 2: POST valid code to /api/ai/validate-code
      const validPayload = JSON.stringify({ source: 'score is 100\nsay score\n' });
      const validRes = await makePostRequest(`http://127.0.0.1:${testPort}/api/ai/validate-code`, validPayload);
      
      assert.equal(validRes.ok, true, 'Server responded with 200 OK');
      assert.equal(validRes.isValid, true, 'Live endpoint returns isValid: true for valid Otter code');
      assert.equal(validRes.errors.length, 0, 'Zero errors for valid code');
    } finally {
      serverProcess.kill();
    }
  });
});

function makePostRequest(urlStr, data) {
  return new Promise((resolve, reject) => {
    const url = new URL(urlStr);
    const req = http.request({
      hostname: url.hostname,
      port: url.port,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data)
      }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(body));
        } catch (e) {
          resolve({ raw: body, statusCode: res.statusCode });
        }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}
