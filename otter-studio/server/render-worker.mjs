// render-worker.mjs - One long-running compiler process for Studio's
// renders (server/render-worker.ps1), instead of a new PowerShell per
// render: loading the compiler costs about 1.5 s, a compile once loaded
// about 0.1 s for a form.
//
//   compile({ source, output, sourceDir }) -> { ok, code?, message? }
//
// One request at a time (the server queues renders anyway). The worker is
// restarted when the compiler's own files change (src/*.psm1), when it
// exits, or when a compile runs past the time limit. A caller falls back to
// a fresh `otter web` process when the worker cannot be used at all.

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';

export function createRenderWorker({ repoRoot, timeoutMs = 180000 }) {
  const srcRoot = path.join(repoRoot, 'src');
  const script = path.join(path.dirname(fileURLToPath(import.meta.url)), 'render-worker.ps1');
  let child = null;
  let ready = null; // promise: the worker has loaded the compiler
  let pending = null; // { id, resolve, timer }
  let nextId = 1;
  let loadedStamp = '';

  // The compiler's files as they are now; a change means a restart.
  const stamp = () => {
    try {
      return fs.readdirSync(srcRoot).filter(f => f.endsWith('.psm1'))
        .map(f => `${f}:${fs.statSync(path.join(srcRoot, f)).mtimeMs}`).join('|');
    } catch { return ''; }
  };

  function stop() {
    if (child) { try { child.kill(); } catch { /* already gone */ } }
    child = null;
    ready = null;
  }

  function start() {
    loadedStamp = stamp();
    child = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, '-SrcRoot', srcRoot], {
      cwd: repoRoot, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe']
    });
    const proc = child;
    ready = new Promise((resolve, reject) => {
      const lines = readline.createInterface({ input: proc.stdout });
      lines.on('line', (line) => {
        let reply;
        try { reply = JSON.parse(line); } catch { return; } // stray output
        if (reply.ready) return resolve();
        if (pending && reply.id === pending.id) {
          const { resolve: done, timer } = pending;
          clearTimeout(timer);
          pending = null;
          done({ ok: reply.ok === true, code: reply.code, message: reply.message });
        }
      });
      proc.stderr.on('data', () => { /* PowerShell progress noise */ });
      proc.on('error', reject);
      proc.on('exit', () => {
        if (child === proc) { child = null; ready = null; }
        reject(new Error('The compiler process stopped.'));
        if (pending) {
          const { resolve: done, timer } = pending;
          clearTimeout(timer);
          pending = null;
          done(null); // the caller falls back
        }
      });
    });
    ready.catch(() => {});
  }

  async function compile({ source, output, sourceDir = '' }) {
    if (child && stamp() !== loadedStamp) stop();
    if (!child) start();
    try { await ready; } catch { stop(); return null; }
    return new Promise((resolve) => {
      const id = nextId++;
      const timer = setTimeout(() => {
        pending = null;
        stop(); // a runaway compile: start fresh next time
        resolve({ ok: false, code: 1, message: 'The compiler took too long and was stopped.' });
      }, timeoutMs);
      pending = { id, resolve, timer };
      child.stdin.write(JSON.stringify({ id, source, output, sourceDir }) + '\n');
    });
  }

  return { compile, stop };
}
