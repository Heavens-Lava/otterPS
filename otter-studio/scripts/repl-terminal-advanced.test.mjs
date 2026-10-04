// repl-terminal-advanced.test.mjs - End-to-end certification for Section 24: Integrated Terminal and REPL
import assert from 'node:assert/strict';
import { TerminalProfileManager, DEFAULT_PROFILES } from '../js/terminal/terminal-profiles.js';
import { TerminalManager, TerminalSession } from '../js/terminal/terminal-manager.js';
import { OtterReplEngine, otterRepl } from '../js/terminal/otter-repl-engine.js';

const PORT = Number(process.env.OTTER_STUDIO_PORT || 4200);
const BASE_URL = `http://127.0.0.1:${PORT}`;

async function api(pathname, body, method = 'POST') {
  const res = await fetch(`${BASE_URL}${pathname}`, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await res.json().catch(() => ({}));
  return { status: res.status, data };
}

try {
  console.log('=== Running Section 24: Integrated Terminal & REPL Certification Suite ===\n');

  // --- 1. Shell Selector & Profiles ---
  console.log('--- 1. Shell Profiles & Selector ---');
  const profileManager = new TerminalProfileManager();
  const profiles = profileManager.getAllProfiles();
  const profileIds = profiles.map(p => p.id);
  assert.ok(profileIds.includes('powershell-5'), 'PowerShell 5.1 profile required');
  assert.ok(profileIds.includes('powershell-7'), 'PowerShell 7 profile required');
  assert.ok(profileIds.includes('cmd'), 'CMD profile required');
  assert.ok(profileIds.includes('bash'), 'Bash profile required');
  assert.ok(profileIds.includes('wsl'), 'WSL profile required');
  assert.ok(profileIds.includes('otter-repl'), 'Otter REPL profile required');
  console.log('  ✓ Supported shell profiles: PowerShell 5.1, PowerShell 7, CMD, Bash, WSL, and Otter REPL');

  // --- 2. Multiple Terminal Tabs & Persistence ---
  console.log('\n--- 2. Multiple Terminal Tabs & Session Management ---');
  const termManager = new TerminalManager();
  const tab1 = await termManager.createSession({ name: 'Terminal Tab 1', cwd: 'C:\\projects\\otterPS' });
  const tab2 = await termManager.createSession({ name: 'Terminal Tab 2', cwd: 'C:\\projects\\otterPS\\src' });
  assert.equal(termManager.getAllSessions().length, 2);
  assert.equal(tab1.name, 'Terminal Tab 1');
  assert.equal(tab2.name, 'Terminal Tab 2');

  termManager.setActiveSession(tab2.id);
  assert.equal(termManager.getActiveSession().id, tab2.id);
  console.log('  ✓ Multiple terminal tabs instantiated with independent active selection');

  // --- 3. Terminal Buffer Search & Clickable Links ---
  console.log('\n--- 3. Terminal Search & Clickable Links Engine ---');
  tab1.appendOutput('Error in src/Otter.Lexer.psm1:45:10 - unexpected token\nVisit https://otter-lang.org for docs\n');
  const searchRes = tab1.search('unexpected token');
  assert.equal(searchRes.matchCount, 1);
  assert.equal(searchRes.matches[0].line, 1);
  console.log('  ✓ Terminal buffer search located query with line/col coordinates');

  const linkified = TerminalSession.linkify(tab1.buffer);
  assert.ok(linkified.includes('class="term-link term-file-link"'), 'File paths must be transformed into clickable links');
  assert.ok(linkified.includes('class="term-link term-url"'), 'URLs must be transformed into clickable links');
  assert.ok(linkified.includes('data-line="45"'), 'Line numbers must be embedded in link dataset');
  console.log('  ✓ Clickable file links and web URLs generated accurately');

  // --- 4. Explorer <-> Terminal CWD Sync & Session Restart ---
  console.log('\n--- 4. Explorer <-> Terminal CWD Sync & Session Restart ---');
  // API test for CWD sync
  const createPTYRes = await api('/api/terminal/session/create', {
    shell: 'cmd.exe',
    args: ['/Q'],
    cwd: 'c:\\Users\\jmacy\\projects\\otterPS'
  });
  assert.equal(createPTYRes.status, 200);
  const ptyId = createPTYRes.data.id;

  const syncRes = await api('/api/terminal/session/cwd', {
    id: ptyId,
    cwd: 'c:\\Users\\jmacy\\projects\\otterPS\\otter-studio'
  });
  assert.equal(syncRes.status, 200);
  assert.equal(syncRes.data.cwd, 'c:\\Users\\jmacy\\projects\\otterPS\\otter-studio');

  const getCwdRes = await api(`/api/terminal/session/cwd?id=${encodeURIComponent(ptyId)}`, null, 'GET');
  assert.equal(getCwdRes.data.cwd, 'c:\\Users\\jmacy\\projects\\otterPS\\otter-studio');
  console.log('  ✓ Explorer <-> Terminal CWD synchronized seamlessly');

  // Session restart test
  const restartRes = await api('/api/terminal/session/restart', { id: ptyId });
  assert.equal(restartRes.status, 200);
  assert.equal(restartRes.data.restarted, true);
  console.log('  ✓ Terminal session restarted cleanly');

  // Clean up PTY session
  await api('/api/terminal/session/close', { id: ptyId });

  // --- 5. Production Otter REPL: Persistent Variables and Expressions ---
  console.log('\n--- 5. Production Otter REPL: Variables & State Persistence ---');
  const repl = new OtterReplEngine();

  // Evaluate variable declaration
  const step1 = await repl.eval('make score is 100');
  assert.equal(step1.ok, true);
  assert.equal(step1.value, 100);

  // Evaluate mutation using persistent variable
  const step2 = await repl.eval('score plus 25');
  assert.equal(step2.ok, true);
  assert.equal(step2.value, 125);

  // Evaluate string operation
  await repl.eval('make title is "Otter"');
  const step3 = await repl.eval('title and " Studio"');
  assert.equal(step3.ok, true);
  assert.equal(step3.value, 'Otter Studio');
  console.log('  ✓ Persistent variables maintained across evaluation steps');

  // --- 6. Production Otter REPL: Function Definitions & Execution ---
  console.log('\n--- 6. Production Otter REPL: Functions & Modules ---');
  const fnDef = `to computeTax\n    make rate is 15\n    return rate\n.`;
  const fnRes = await repl.eval(fnDef);
  assert.equal(fnRes.ok, true);
  assert.equal(fnRes.type, 'function');

  // Load module
  const modRes = await repl.eval('use "math"');
  assert.equal(modRes.ok, true);
  assert.equal(modRes.type, 'module');
  assert.ok(repl.loadedModules.has('math'));
  console.log('  ✓ REPL function definitions and module loading certified');

  // --- 7. Production Otter REPL: Multiline Detection ---
  console.log('\n--- 7. Multiline Detection & Continuation Prompts ---');
  const incompleteFn = repl.isComplete('to formatSummary\n    say "Hello"');
  assert.equal(incompleteFn.complete, false);
  assert.equal(incompleteFn.prompt, '...   ');

  const completeFn = repl.isComplete('to formatSummary\n    say "Hello"\n.');
  assert.equal(completeFn.complete, true);
  assert.equal(completeFn.prompt, 'otter> ');
  console.log('  ✓ Incomplete blocks detected with continuation prompt (...   )');

  // --- 8. Command History & Tab Completion ---
  console.log('\n--- 8. History Navigation & Tab Completion ---');
  repl.addHistory('make a is 1');
  repl.addHistory('make b is 2');

  assert.equal(repl.historyUp(), 'make b is 2');
  assert.equal(repl.historyUp(), 'make a is 1');
  assert.equal(repl.historyDown(), 'make b is 2');

  const compRes = repl.complete('mak');
  assert.ok(compRes.completions.includes('make'));

  const varCompRes = repl.complete('sc');
  assert.ok(varCompRes.completions.includes('score'));
  console.log('  ✓ History navigation and tab completion for keywords and identifiers verified');

  // --- 9. Pretty Values & Object Inspection ---
  console.log('\n--- 9. Pretty Values & Object Inspection ---');
  assert.match(repl.prettyPrint(null), /gone/);
  assert.match(repl.prettyPrint(42), /42/);
  assert.match(repl.prettyPrint([1, 2, 3]), /\[\x1b\[33m1\x1b\[0m, \x1b\[33m2\x1b\[0m, \x1b\[33m3\x1b\[0m\]/);
  assert.match(repl.prettyPrint({ name: 'Otter', port: 4200 }), /name: \x1b\[32m"Otter"\x1b\[0m/);
  console.log('  ✓ Pretty values format primitives, lists, objects, and gone');

  // --- 10. Error Recovery & Reset ---
  console.log('\n--- 10. Error Recovery & Reset ---');
  const errorRes = await repl.eval('unknownVariable');
  assert.equal(errorRes.ok, false);
  assert.ok(errorRes.suggestion);
  assert.equal(repl.variables.get('score'), 100, 'REPL state must survive evaluation error');

  const resetRes = repl.reset();
  assert.equal(resetRes.ok, true);
  assert.equal(repl.variables.has('score'), false);
  console.log('  ✓ REPL recovered from error without state loss, and reset cleared environment');

  // --- 11. Full HTTP REPL Endpoints Integration ---
  console.log('\n--- 11. Backend /api/repl/* Endpoints Integration ---');
  const httpEval1 = await api('/api/repl/eval', { input: 'make testVal is 999' });
  assert.equal(httpEval1.status, 200);
  assert.equal(httpEval1.data.value, 999);

  const httpEval2 = await api('/api/repl/eval', { input: 'testVal plus 1' });
  assert.equal(httpEval2.status, 200);
  assert.equal(httpEval2.data.value, 1000);

  const httpComplete = await api('/api/repl/complete', { line: 'testV' });
  assert.equal(httpComplete.status, 200);
  assert.ok(httpComplete.data.completions.includes('testVal'));

  const httpHighlight = await api('/api/repl/highlight', { code: 'make x is 10 # comment', mode: 'ansi' });
  assert.equal(httpHighlight.status, 200);
  assert.ok(httpHighlight.data.highlighted.includes('\x1b[36mmake\x1b[0m'));

  console.log('  ✓ All /api/repl HTTP endpoints certified');

  console.log('\n=== ALL SECTION 24 TERMINAL & REPL TESTS PASSED SUCCESSFULLY ===');
} catch (err) {
  console.error('\nTest failed:', err);
  process.exit(1);
}
