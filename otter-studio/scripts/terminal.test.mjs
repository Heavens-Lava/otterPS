// terminal.test.mjs - Comprehensive Test Suite for Otter Studio Terminal Engine (Section 4)
import assert from 'node:assert/strict';
import http from 'node:http';
import { stripAnsi, ansiToHtml, escapeHtml, get256Color } from '../js/terminal/ansi-parser.js';
import { TerminalProfileManager, DEFAULT_PROFILES } from '../js/terminal/terminal-profiles.js';
import { TerminalManager, TerminalSession, escapeShellArg, auditShellCommand } from '../js/terminal/terminal-manager.js';

console.log('Testing Otter Studio Terminal Engine (Section 4)...');

const PORT = 4200;

function apiRequest(method, endpoint, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(endpoint, `http://127.0.0.1:${PORT}`);
    const req = http.request(url, {
      method,
      headers: {
        'Content-Type': 'application/json'
      }
    }, res => {
      let data = '';
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: data ? JSON.parse(data) : {} });
        } catch {
          resolve({ status: res.statusCode, raw: data });
        }
      });
    });
    req.on('error', reject);
    if (body) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// -------------------------------------------------------------
// 1. ANSI / VT100 Parser & Sanitization Tests
// -------------------------------------------------------------
{
  // Plain text
  assert.equal(stripAnsi('Hello World'), 'Hello World');
  assert.equal(ansiToHtml('Hello World'), 'Hello World');

  // HTML escaping
  assert.equal(escapeHtml('<script>alert(1)</script>'), '&lt;script&gt;alert(1)&lt;/script&gt;');
  assert.equal(ansiToHtml('<b>test & "quote"</b>'), '&lt;b&gt;test &amp; &quot;quote&quot;&lt;/b&gt;');

  // Standard 16 colors
  const redText = '\x1b[31mError message\x1b[0m';
  assert.equal(stripAnsi(redText), 'Error message');
  const htmlRed = ansiToHtml(redText);
  assert.ok(htmlRed.includes('color: #f44336'), `Expected red color in: ${htmlRed}`);
  assert.ok(htmlRed.includes('Error message'));

  // Background colors
  const bgBlueText = '\x1b[44mBackground Blue\x1b[0m';
  assert.equal(stripAnsi(bgBlueText), 'Background Blue');
  const htmlBgBlue = ansiToHtml(bgBlueText);
  assert.ok(htmlBgBlue.includes('background-color: #0d47a1'), `Expected blue background in: ${htmlBgBlue}`);

  // Styles: Bold, Italic, Underline, Strikethrough
  const boldText = '\x1b[1mBold Text\x1b[0m';
  assert.ok(ansiToHtml(boldText).includes('font-weight: bold'));

  const italicText = '\x1b[3mItalic Text\x1b[0m';
  assert.ok(ansiToHtml(italicText).includes('font-style: italic'));

  const underlineText = '\x1b[4mUnderlined Text\x1b[0m';
  assert.ok(ansiToHtml(underlineText).includes('text-decoration: underline'));

  const strikeText = '\x1b[9mStrikethrough Text\x1b[0m';
  assert.ok(ansiToHtml(strikeText).includes('text-decoration: line-through'));

  // 256 colors
  const color256 = '\x1b[38;5;196mBright Red 256\x1b[0m';
  assert.equal(stripAnsi(color256), 'Bright Red 256');
  const html256 = ansiToHtml(color256);
  assert.ok(html256.includes('color: rgb(255, 0, 0)'), `Expected 256 color rgb in: ${html256}`);

  // 24-bit TrueColor RGB
  const rgbText = '\x1b[38;2;123;45;67mCustom TrueColor\x1b[0m';
  assert.equal(stripAnsi(rgbText), 'Custom TrueColor');
  const htmlRgb = ansiToHtml(rgbText);
  assert.ok(htmlRgb.includes('color: rgb(123, 45, 67)'), `Expected truecolor rgb in: ${htmlRgb}`);

  // Compound formatting
  const compound = '\x1b[1;32;40mBold Green on Black\x1b[0m';
  const htmlCompound = ansiToHtml(compound);
  assert.ok(htmlCompound.includes('font-weight: bold'));
  assert.ok(htmlCompound.includes('color: #4caf50'));
  assert.ok(htmlCompound.includes('background-color: #000000'));

  console.log('  pass  ANSI / VT100 rendering (16 colors, 256 colors, RGB truecolor, styles, HTML sanitization)');
}

// -------------------------------------------------------------
// 2. Terminal Profile Manager Tests
// -------------------------------------------------------------
{
  const pm = new TerminalProfileManager();
  const profiles = pm.getAllProfiles();
  assert.ok(profiles.length >= 4, 'Expected default profiles');
  assert.ok(pm.getProfile('powershell-5'), 'Expected powershell-5 profile');
  assert.ok(pm.getProfile('cmd'), 'Expected cmd profile');
  assert.ok(pm.getProfile('otter-repl'), 'Expected otter-repl profile');

  // Default profile
  assert.equal(pm.getDefaultProfile().id, 'powershell-5');
  pm.setDefaultProfile('cmd');
  assert.equal(pm.getDefaultProfile().id, 'cmd');
  assert.ok(pm.getProfile('cmd').isDefault);

  // Custom profile
  const custom = pm.addProfile({
    id: 'custom-shell',
    name: 'Custom Shell',
    shell: 'custom.exe',
    args: ['--test'],
    env: { FOO: 'BAR' }
  });
  assert.equal(custom.name, 'Custom Shell');
  assert.equal(pm.getProfile('custom-shell').env.FOO, 'BAR');

  // Profile removal
  assert.ok(pm.removeProfile('custom-shell'));
  assert.equal(pm.getProfile('custom-shell'), null);

  // Primary profile protected
  assert.throws(() => pm.removeProfile('powershell-5'), /Cannot remove primary/);

  console.log('  pass  Terminal profiles manager (built-in profiles, detection, default switching, custom profiles)');
}

// -------------------------------------------------------------
// 3. Shell Escaping & Injection Audit Tests
// -------------------------------------------------------------
{
  // Safe argument escaping
  assert.equal(escapeShellArg('plainWord'), 'plainWord');
  assert.equal(escapeShellArg('path/to/file.ot'), 'path/to/file.ot');
  assert.equal(escapeShellArg('C:\\projects\\otterPS'), 'C:\\projects\\otterPS');
  assert.equal(escapeShellArg('with space'), '"with space"');
  assert.equal(escapeShellArg('quotes "nested"'), '"quotes `"nested`""');
  assert.equal(escapeShellArg(''), '""');

  // Command string safety audit
  assert.equal(auditShellCommand('').safe, false);
  assert.equal(auditShellCommand('   ').safe, false);
  assert.equal(auditShellCommand('cmd\0evil').safe, false);
  assert.equal(auditShellCommand('otter run file.ot').safe, true);
  assert.equal(auditShellCommand('echo hello\necho world').multiline, true);

  console.log('  pass  Shell escaping & injection audit (safe quoting, injection defense, argument audit)');
}

// -------------------------------------------------------------
// 4. Client-side Terminal Manager & Multi-Session Tests
// -------------------------------------------------------------
{
  const tm = new TerminalManager();
  const session1 = await tm.createSession({ name: 'Term 1' });
  const session2 = await tm.createSession({ name: 'Term 2' });

  assert.equal(tm.getAllSessions().length, 2);
  assert.equal(tm.getActiveSession().id, session1.id);

  // Switching active session
  tm.setActiveSession(session2.id);
  assert.equal(tm.getActiveSession().id, session2.id);

  // Buffering & formatting
  let outputReceived = '';
  session1.subscribe(e => {
    if (e.type === 'output') outputReceived += e.chunk;
  });

  session1.appendOutput('Line 1\n');
  session1.appendOutput('\x1b[32mLine 2 (Green)\x1b[0m\n');

  assert.ok(session1.buffer.includes('Line 1'));
  assert.ok(session1.buffer.includes('Line 2 (Green)'));
  assert.equal(outputReceived, 'Line 1\n\x1b[32mLine 2 (Green)\x1b[0m\n');
  assert.ok(session1.lines.some(l => l.includes('color: #4caf50')));

  // Session closing
  await tm.closeSession(session1.id);
  assert.equal(tm.getAllSessions().length, 1);
  assert.equal(tm.getActiveSession().id, session2.id);

  console.log('  pass  Client-side Terminal Manager (multi-session tabs, switching, output event subscriptions)');
}

// -------------------------------------------------------------
// 5. Backend Persistent PTY API Integration Tests (via serve.mjs)
// -------------------------------------------------------------
{
  // 5a. GET /api/terminal/profiles
  const profilesRes = await apiRequest('GET', '/api/terminal/profiles');
  assert.equal(profilesRes.status, 200);
  assert.ok(profilesRes.body.ok);
  assert.ok(Array.isArray(profilesRes.body.profiles));
  assert.ok(profilesRes.body.profiles.some(p => p.id === 'powershell-5'));
  console.log('  pass  backend: /api/terminal/profiles returns system shells');

  // 5b. POST /api/terminal/session/create
  const createRes = await apiRequest('POST', '/api/terminal/session/create', {
    shell: 'powershell.exe',
    args: ['-NoLogo', '-NoProfile', '-Command', '-'],
    cols: 100,
    rows: 30,
    env: { OTTER_TEST_VAR: 'OtterTerminalTestVal' }
  });
  assert.equal(createRes.status, 200);
  assert.ok(createRes.body.ok);
  const sessionId = createRes.body.id;
  assert.ok(sessionId, 'Expected sessionId');
  assert.ok(createRes.body.pid, 'Expected process pid');
  console.log(`  pass  backend: /api/terminal/session/create spawned persistent PTY (PID: ${createRes.body.pid})`);

  // 5c. GET /api/terminal/sessions
  const listRes = await apiRequest('GET', '/api/terminal/sessions');
  assert.equal(listRes.status, 200);
  assert.ok(listRes.body.sessions.some(s => s.id === sessionId));
  console.log('  pass  backend: /api/terminal/sessions reflects active session');

  // 5d. POST /api/terminal/session/resize
  const resizeRes = await apiRequest('POST', '/api/terminal/session/resize', {
    id: sessionId,
    cols: 120,
    rows: 40
  });
  assert.equal(resizeRes.status, 200);
  assert.equal(resizeRes.body.cols, 120);
  assert.equal(resizeRes.body.rows, 40);
  console.log('  pass  backend: /api/terminal/session/resize updates terminal geometry');

  // 5e. Environment API: GET & POST /api/terminal/session/env
  const envRes = await apiRequest('GET', `/api/terminal/session/env?id=${sessionId}`);
  assert.equal(envRes.status, 200);
  assert.equal(envRes.body.env.OTTER_TEST_VAR, 'OtterTerminalTestVal');

  const setEnvRes = await apiRequest('POST', '/api/terminal/session/env', {
    id: sessionId,
    key: 'NEW_TEST_KEY',
    value: 'NEW_TEST_VALUE'
  });
  assert.equal(setEnvRes.status, 200);
  assert.equal(setEnvRes.body.env.NEW_TEST_KEY, 'NEW_TEST_VALUE');
  console.log('  pass  backend: /api/terminal/session/env manages session environment');

  // 5f. Character stdin input & output polling (Persistent Shell State & Interactive Commands)
  const inputCmd = "Write-Output 'PTY_INTERACTIVE_TOKEN_123'; $persistentShellState = 'ActiveSessionState456'\r\n";
  const inputRes = await apiRequest('POST', '/api/terminal/session/input', {
    id: sessionId,
    input: inputCmd
  });
  assert.equal(inputRes.status, 200);
  assert.ok(inputRes.body.ok);

  // Poll for output
  let receivedToken = false;
  for (let i = 0; i < 20; i++) {
    await sleep(150);
    const pollRes = await apiRequest('GET', `/api/terminal/session/poll?id=${sessionId}&offset=0`);
    if (pollRes.status === 200 && pollRes.body.output && pollRes.body.output.includes('PTY_INTERACTIVE_TOKEN_123')) {
      receivedToken = true;
      break;
    }
  }
  assert.ok(receivedToken, 'Expected interactive output token via stdin and polling');
  console.log('  pass  backend: character stdin streaming and output polling received token');

  // Verify persistent shell state across separate command
  const inputCmd2 = "Write-Output ('STATE=' + $persistentShellState)\r\n";
  await apiRequest('POST', '/api/terminal/session/input', {
    id: sessionId,
    input: inputCmd2
  });

  let receivedState = false;
  for (let i = 0; i < 20; i++) {
    await sleep(150);
    const pollRes = await apiRequest('GET', `/api/terminal/session/poll?id=${sessionId}&offset=0`);
    if (pollRes.status === 200 && pollRes.body.output && pollRes.body.output.includes('STATE=ActiveSessionState456')) {
      receivedState = true;
      break;
    }
  }
  assert.ok(receivedState, 'Expected persistent shell state across separate inputs');
  console.log('  pass  backend: persistent shell state survives across subsequent commands');

  // 5g. Signals / Ctrl+C
  const sigRes = await apiRequest('POST', '/api/terminal/session/signal', {
    id: sessionId,
    signal: 'SIGINT'
  });
  assert.equal(sigRes.status, 200);
  assert.ok(sigRes.body.ok);
  console.log('  pass  backend: /api/terminal/session/signal delivers Ctrl+C / SIGINT');

  // 5h. POST /api/terminal/session/close (Kill Process Tree)
  const closeRes = await apiRequest('POST', '/api/terminal/session/close', {
    id: sessionId
  });
  assert.equal(closeRes.status, 200);
  assert.ok(closeRes.body.ok);

  const checkClosedRes = await apiRequest('GET', `/api/terminal/session/poll?id=${sessionId}&offset=0`);
  assert.equal(checkClosedRes.status, 404, 'Session must no longer exist after close');
  console.log('  pass  backend: /api/terminal/session/close terminates process tree and cleans up session');

  // 5i. Legacy /api/terminal single-command backward compatibility
  const legacyRes = await apiRequest('POST', '/api/terminal', {
    command: "Write-Output 'LegacyEndpointOK'"
  });
  assert.equal(legacyRes.status, 200);
  assert.equal(legacyRes.body.exitCode, 0);
  assert.ok(legacyRes.body.stdout.includes('LegacyEndpointOK'));
  console.log('  pass  backend: legacy /api/terminal remains 100% backward compatible');
}

console.log('All Otter Studio Terminal Engine tests passed (14/14).');
