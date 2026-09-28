// tests.mjs - Test discovery and running for the Test Explorer.
//
// Otter's test model (src/Otter.Project.psm1, `otter test`):
//   * a test is one file in the project's tests/ folder (searched
//     recursively) named *_test.ot or test_*.ot;
//   * it passes when the program exits with code 0; `fail with "..."` or any
//     runtime error fails it; exit code 2 means it did not parse.
//
// Discovery mirrors Get-OtterProjectTestFiles so the explorer lists exactly
// what `otter test` would run. Each test is run with `otter test <file>`,
// the real command, one file at a time, so the explorer can show progress,
// a duration and the output for every test, and results match the CLI.

import { execFile } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const TEST_TIMEOUT_MS = 5 * 60 * 1000;

export function isTestFileName(name) {
  const lower = name.toLowerCase();
  return lower.endsWith('.ot') && (lower.endsWith('_test.ot') || lower.startsWith('test_'));
}

/**
 * Test files for a project folder, sorted by full path (like otter test).
 * Returns absolute paths; [] when there is no tests/ folder.
 */
export function discoverTests(projectDir) {
  let testsDir = path.join(projectDir, 'tests');
  if (!fs.existsSync(testsDir) || !fs.statSync(testsDir).isDirectory()) {
    if (path.basename(projectDir).toLowerCase() === 'tests') testsDir = projectDir;
    else return [];
  }
  const found = [];
  const walk = dir => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile() && isTestFileName(entry.name)) found.push(full);
    }
  };
  walk(testsDir);
  // Sort-Object FullName in PowerShell is case-insensitive.
  return found.sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
}

/**
 * Read `otter test` output for one file into { message, line }.
 * Failure details look like:
 *   FAIL tests/app_test.ot:6
 *     Expected score to be 100.
 * and syntax errors like:
 *   FAIL tests/app_test.ot (syntax error)
 *   ... Line 3: ...
 */
export function parseTestFailure(output) {
  const lines = String(output || '').replace(/\r/g, '').split('\n');
  let line = null;
  let message = null;
  for (let i = 0; i < lines.length; i++) {
    const located = /^FAIL\s+\S+?:(\d+)\s*$/.exec(lines[i].trim());
    if (located) {
      line = Number(located[1]);
      message = (lines[i + 1] || '').trim() || null;
    }
    const syntaxLine = /^Line\s+(\d+):/.exec(lines[i].trim());
    if (syntaxLine && line === null) line = Number(syntaxLine[1]);
  }
  if (!message) {
    // Syntax errors: the explanation is the first plain sentence after the caret.
    const detail = lines.map(l => l.trim()).filter(l => l && !/^(FAIL|PASS|Running|Line \d+:|\^|Otter Syntax Error|\d+ (passed|failed))/.test(l));
    message = detail.find(l => /[.!?]$/.test(l)) || detail[0] || null;
  }
  return { line, message };
}

function runOne(repoRoot, projectDir, file) {
  return new Promise(resolve => {
    const start = Date.now();
    const otterPs1 = path.join(repoRoot, 'otter.ps1');
    execFile('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', otterPs1, 'test', file], {
      cwd: projectDir, timeout: TEST_TIMEOUT_MS, maxBuffer: 8 * 1024 * 1024, windowsHide: true
    }, (error, stdout, stderr) => {
      const exitCode = error ? (typeof error.code === 'number' ? error.code : 1) : 0;
      const output = `${stdout || ''}${stderr || ''}`;
      const status = exitCode === 0 ? 'passed' : (exitCode === 2 ? 'error' : 'failed');
      resolve({
        status,
        exitCode,
        durationMs: Date.now() - start,
        output,
        ...(status === 'passed' ? { line: null, message: null } : parseTestFailure(output))
      });
    });
  });
}

/**
 * /api/tests/list?folder=  and  POST /api/tests/run { folder, path }.
 * ctx = { repoRoot, isInsideRepo, readBody, sendJson }
 */
export async function handleTestRoutes(req, res, pathname, urlObj, ctx) {
  if (!pathname.startsWith('/api/tests/')) return false;
  const { repoRoot, isInsideRepo, readBody, sendJson } = ctx;
  const toRel = abs => path.relative(repoRoot, abs).split(path.sep).join('/');
  const body = req.method === 'POST' ? await readBody(req) : {};
  const folder = req.method === 'POST' ? body.folder : urlObj.searchParams.get('folder');
  const projectDir = typeof folder === 'string' && folder ? path.resolve(repoRoot, folder) : null;
  if (!projectDir || !isInsideRepo(projectDir) || !fs.existsSync(projectDir) || !fs.statSync(projectDir).isDirectory()) {
    return sendJson(res, { error: 'Open a project folder to find its tests.' }, 404), true;
  }

  if (pathname === '/api/tests/list' && req.method === 'GET') {
    const tests = discoverTests(projectDir).map(abs => ({
      path: toRel(abs),
      name: path.relative(projectDir, abs).split(path.sep).join('/')
    }));
    return sendJson(res, { folder: toRel(projectDir) || '.', tests }), true;
  }

  if (pathname === '/api/tests/run' && req.method === 'POST') {
    const file = typeof body.path === 'string' ? path.resolve(repoRoot, body.path) : null;
    // Only files discovery would list may be run as tests.
    if (!file || !isInsideRepo(file) || !discoverTests(projectDir).includes(file)) {
      return sendJson(res, { error: 'That file is not one of this project\'s tests.' }, 400), true;
    }
    const result = await runOne(repoRoot, projectDir, file);
    return sendJson(res, { path: toRel(file), ...result }), true;
  }

  return sendJson(res, { error: 'Unknown test request.' }, 404), true;
}
