// terminal-sessions.mjs - Studio's integrated terminal: real, persistent
// PowerShell sessions.
//
// Each terminal is ONE long-lived powershell.exe reading commands on its
// stdin (`-Command -`), so the folder you `cd` to, variables, functions and
// modules last for the whole session, output streams while a command runs,
// and a program that asks for input (Otter's `ask`, Read-Host...) reads what
// you type next. It is not a pseudo-terminal: full-screen programs that
// redraw the screen (vim, a progress bar) are not supported.
//
// - UTF-8 both ways: the shell starts under code page 65001.
// - Each command is sent base64-encoded and run with Invoke-Expression in
//   the session's own scope (one line, its exact text - quotes and a trailing
//   # comment included), followed by a marker with a per-session token that
//   says the command finished, whether it succeeded and the current folder.
//   The marker never reaches the terminal.
// - While a command runs, what you type is sent as that program's input.
// - Interrupt stops what the shell is running (its child processes), not the
//   shell; Close ends the session and everything it started.
//
//   POST /api/terminal/open      { folder? }        -> { id, cwd }
//   POST /api/terminal/write     { id, text }       -> { ok, busy }
//   GET  /api/terminal/poll?id=  -> { chunks:[{stream,text}], busy, cwd, alive, exitOk }
//   POST /api/terminal/interrupt { id }
//   POST /api/terminal/close     { id }

import { spawn, execFile } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const MAX_SESSIONS = 8;
const MAX_BUFFERED = 2 * 1024 * 1024; // chars kept for a terminal nobody polls

export function createTerminalManager({ repoRoot, isInsideRepo }) {
  const sessions = new Map();

  function push(session, stream, text) {
    if (!text) return;
    const last = session.chunks[session.chunks.length - 1];
    if (last && last.stream === stream) last.text += text; else session.chunks.push({ stream, text });
    session.buffered += text.length;
    while (session.buffered > MAX_BUFFERED && session.chunks.length > 1) session.buffered -= session.chunks.shift().text.length;
  }

  // stdout: everything except the marker line, which ends a command. A
  // partial line goes out at once (a prompt such as "Your name? "), unless it
  // could be the start of a marker.
  function onStdout(session, data) {
    session.pending += data;
    const lines = session.pending.split('\n');
    session.pending = lines.pop();
    for (const raw of lines) {
      const line = raw.endsWith('\r') ? raw.slice(0, -1) : raw;
      // The panel shows what you typed for a program; one that echoes it
      // back itself (PowerShell's Read-Host, so Otter's `ask`) would show it
      // twice - its echo of exactly that line is dropped, once.
      if (session.expectEcho !== null) {
        const echoed = line === session.expectEcho;
        session.expectEcho = null;
        if (echoed) continue;
      }
      const at = line.indexOf(session.token);
      if (at >= 0) {
        if (at > 0) push(session, 'out', line.slice(0, at) + '\n');
        const [, ok, code, ...cwdParts] = line.slice(at).split(' ');
        session.busy = false;
        session.exitOk = ok === '1';
        session.exitCode = Number(code) || 0;
        session.cwd = cwdParts.join(' ').trim() || session.cwd;
        session.commands++;
      } else {
        push(session, 'out', line + '\n');
      }
    }
    // A partial line: out now, except from an "@@" on (a marker may be
    // arriving), which waits for the rest of its line.
    const rest = session.pending;
    const hold = rest.indexOf('@@');
    if (rest && session.expectEcho !== null && session.expectEcho.startsWith(rest)) {
      // May be the start of the program's echo of the typed line: wait.
    } else if (hold === -1) {
      push(session, 'out', rest);
      session.pending = '';
    } else if (hold > 0) {
      push(session, 'out', rest.slice(0, hold));
      session.pending = rest.slice(hold);
    }
  }

  // Succeeded = no new PowerShell error (after Invoke-Expression, $? is about
  // Invoke-Expression, not the command) - the newest error is not the one
  // there before (a reference check, right even when $Error is full).
  function marker(session) {
    return `; Write-Output ('${session.token} ' + [int][object]::ReferenceEquals($Error[0], $global:otterErrorBefore) + ' ' + [int]$global:LASTEXITCODE + ' ' + (Get-Location).ProviderPath)`;
  }

  function open({ folder } = {}) {
    for (const [id, s] of sessions) if (!s.alive) sessions.delete(id);
    if (sessions.size >= MAX_SESSIONS) {
      const err = new Error(`Up to ${MAX_SESSIONS} terminals can be open. Close one first.`);
      err.status = 409;
      throw err;
    }
    let cwd = repoRoot;
    if (folder) {
      const abs = path.resolve(repoRoot, String(folder));
      if (isInsideRepo(abs) && fs.existsSync(abs) && fs.statSync(abs).isDirectory()) cwd = abs;
    }
    const id = crypto.randomUUID();
    const session = { id, child: null, token: '', cwd, chunks: [], buffered: 0, pending: '', busy: true, exitOk: true, exitCode: 0, alive: true, commands: 0, expectEcho: null };
    sessions.set(id, session);
    startShell(session, cwd);
    return { id, cwd };
  }

  // The session's shell process: a new one replaces it after an interrupt of
  // a command running inside PowerShell itself (see interrupt()).
  function startShell(session, cwd) {
    session.token = `@@OTTER_TERM_${crypto.randomBytes(6).toString('hex')}@@`;
    session.pending = '';
    session.expectEcho = null;
    session.busy = true;
    session.alive = true;
    const args = '-NoLogo -NoProfile -ExecutionPolicy Bypass -Command -';
    const child = process.platform === 'win32'
      ? spawn('cmd.exe', ['/d', '/s', '/c', `chcp 65001 >nul && powershell.exe ${args}`], { cwd, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] })
      : spawn('pwsh', args.split(' '), { cwd, stdio: ['pipe', 'pipe', 'pipe'] });
    session.child = child;
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', d => { if (session.child === child) onStdout(session, d); });
    child.stderr.on('data', d => { if (session.child === child) push(session, 'err', d); });
    child.on('close', () => { if (session.child === child) { session.alive = false; session.busy = false; } });
    child.on('error', (err) => { if (session.child === child) { push(session, 'err', `The terminal could not start: ${err.message}\n`); session.alive = false; } });
    // Setup counts as a command: the shell is ready at its marker.
    // `otter` is this Otter (its otter.ps1), wherever the shell is and
    // whatever is on PATH; $OtterRepo is its folder.
    const repo = repoRoot.replace(/'/g, "''");
    child.stdin.write(`$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); $ProgressPreference = 'SilentlyContinue'; $OtterRepo = '${repo}'; function global:otter { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $OtterRepo 'otter.ps1') @args }${marker(session)}\n`);
  }

  function get(id) {
    const session = sessions.get(id);
    if (!session) {
      const err = new Error('That terminal has closed. Open a new one.');
      err.status = 404;
      throw err;
    }
    return session;
  }

  // Idle: run it as a command. Busy: it is input for what is running.
  function write(id, text) {
    const session = get(id);
    if (!session.alive) {
      const err = new Error('That terminal has closed. Open a new one.');
      err.status = 410;
      throw err;
    }
    const line = String(text ?? '').replace(/[\r\n]+$/, '');
    if (session.busy) {
      session.expectEcho = line;
      session.child.stdin.write(line + '\n');
      return { ok: true, busy: true, input: true };
    }
    const encoded = Buffer.from(line, 'utf8').toString('base64');
    session.busy = true;
    // $LASTEXITCODE starts at 0, so the marker reports this command's own
    // exit code (a native program's), not an earlier one's.
    session.child.stdin.write(`$global:LASTEXITCODE = 0; $global:otterErrorBefore = $Error[0]; Invoke-Expression ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${encoded}')))${marker(session)}\n`);
    return { ok: true, busy: true, input: false };
  }

  function poll(id) {
    const session = get(id);
    const chunks = session.chunks.splice(0);
    session.buffered = 0;
    return { chunks, busy: session.busy, cwd: session.cwd, alive: session.alive, exitOk: session.exitOk, exitCode: session.exitCode, commands: session.commands };
  }

  // Stop what is running. A program the shell started (otter run, git, node)
  // is ended and the shell lives on. A command running inside PowerShell
  // itself (Start-Sleep, a long loop) cannot be stopped from outside without
  // a console - a console Ctrl+C left the shell hung - so the shell is
  // replaced by a new one in the same folder, and the panel says so.
  function interrupt(id) {
    const session = get(id);
    if (!session.busy) return Promise.resolve({ ok: true, stopped: 'nothing' });
    if (process.platform !== 'win32') { session.child.kill('SIGINT'); return Promise.resolve({ ok: true, stopped: 'program' }); }
    const script = `$shell = Get-CimInstance Win32_Process -Filter "ParentProcessId=${session.child.pid} AND Name='powershell.exe'" | Select-Object -First 1; $n = 0; if ($shell) { Get-CimInstance Win32_Process -Filter "ParentProcessId=$($shell.ProcessId)" | ForEach-Object { taskkill /pid $_.ProcessId /t /f | Out-Null; $n++ } }; $n`;
    return new Promise((resolve) => {
      execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { windowsHide: true, timeout: 15000 }, (err, stdout) => {
        const ended = Number(String(stdout).trim()) || 0;
        if (ended > 0) {
          push(session, 'err', '^C\n');
          resolve({ ok: true, stopped: 'program' });
          return;
        }
        const old = session.child;
        const cwd = session.cwd;
        push(session, 'err', `^C\nStopped by starting a new shell in ${cwd} - variables and functions from before are gone.\n`);
        startShell(session, cwd);
        try { execFile('taskkill', ['/pid', String(old.pid), '/t', '/f'], { windowsHide: true }, () => {}); } catch { /* gone */ }
        resolve({ ok: true, stopped: 'shell' });
      });
    });
  }

  function close(id) {
    const session = sessions.get(id);
    if (!session) return { ok: true };
    sessions.delete(id);
    try {
      if (process.platform === 'win32') execFile('taskkill', ['/pid', String(session.child.pid), '/t', '/f'], { windowsHide: true }, () => {});
      else session.child.kill('SIGTERM');
    } catch { /* already gone */ }
    return { ok: true };
  }

  function closeAll() { for (const id of [...sessions.keys()]) close(id); }

  return { open, write, poll, interrupt, close, closeAll };
}

export async function handleTerminalRoutes(req, res, pathname, urlObj, ctx, manager) {
  if (!pathname.startsWith('/api/terminal/')) return false;
  const { sendJson, readBody } = ctx;
  try {
    if (pathname === '/api/terminal/poll' && req.method === 'GET') return sendJson(res, manager.poll(urlObj.searchParams.get('id'))), true;
    if (req.method !== 'POST') return false;
    const body = await readBody(req);
    switch (pathname) {
      case '/api/terminal/open': return sendJson(res, manager.open({ folder: body.folder })), true;
      case '/api/terminal/write': return sendJson(res, manager.write(body.id, body.text)), true;
      case '/api/terminal/interrupt': return sendJson(res, await manager.interrupt(body.id)), true;
      case '/api/terminal/close': return sendJson(res, manager.close(body.id)), true;
      default: return false;
    }
  } catch (err) {
    sendJson(res, { error: err.message }, err.status || 500);
    return true;
  }
}
