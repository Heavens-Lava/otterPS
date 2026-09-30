// launch.mjs - Run, launch profiles, build and clean for Otter Studio.
//
// Everything here drives the real `otter` command line (otter.ps1), exactly as
// a user would from a terminal. Studio never interprets or builds Otter itself:
//
//   Run current file   ->  otter run <file.ot> [args...]
//   Run project        ->  otter run <project folder> [args...]
//   Build / Rebuild    ->  otter build <project folder>
//   Clean              ->  delete the build output folder, but only one that
//                          `otter build` created (it contains otter.build.json)
//
// Launch profiles live in <project>/.otter-studio/launch.json so they travel
// with the project (like .vscode/launch.json). A profile is plain data:
//
//   { "name": "Run with sample data", "kind": "project" | "file",
//     "program": "tools/import.ot",       // kind "file": path in the project
//     "args": ["--input", "data.csv"],     // passed to the program verbatim
//     "cwd": ".",                           // relative to the project folder
//     "env": { "OTTER_ENV": "dev" },
//     "timeoutSeconds": 30 }
//
// Arguments are always passed as an argument array to execFile, never
// through a shell, so no argument or file name can inject a command.

import { execFile } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { addManifestAssets, referencedImages } from './manifest-assets.mjs';

export const LAUNCH_CONFIG_RELATIVE = '.otter-studio/launch.json';
const MAX_ARGS = 100;
const MAX_ARG_LENGTH = 4000;
const MAX_TIMEOUT_SECONDS = 3600;
const DEFAULT_TIMEOUT_SECONDS = 30;
const ENV_NAME = /^[A-Za-z_][A-Za-z0-9_]*$/;
// Variables a profile may not replace: they decide which programs and
// libraries the child process loads.
const PROTECTED_ENV = new Set(['PATH', 'PATHEXT', 'COMSPEC', 'SYSTEMROOT', 'WINDIR', 'PSMODULEPATH', 'LD_PRELOAD', 'LD_LIBRARY_PATH', 'DYLD_INSERT_LIBRARIES', 'NODE_OPTIONS']);

/** The profiles a project starts with when it has no launch.json yet. */
export function defaultLaunchConfig() {
  return {
    version: 1,
    startup: 'Run Project',
    profiles: [
      { name: 'Run Project', kind: 'project', args: [], cwd: '.', env: {}, timeoutSeconds: DEFAULT_TIMEOUT_SECONDS },
      { name: 'Run Current File', kind: 'file', program: '${currentFile}', args: [], cwd: '${fileDir}', env: {}, timeoutSeconds: DEFAULT_TIMEOUT_SECONDS }
    ]
  };
}

/**
 * Check a launch configuration and return { config, errors }.
 * `config` is a normalised copy (missing fields filled in); `errors` lists
 * every problem in plain words, so the editor can show them all at once.
 */
export function validateLaunchConfig(raw) {
  const errors = [];
  const config = { version: 1, startup: null, profiles: [] };
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return { config, errors: ['The launch configuration must be a JSON object.'] };
  }
  if (!Array.isArray(raw.profiles)) {
    errors.push('"profiles" must be a list.');
    return { config, errors };
  }

  const names = new Set();
  raw.profiles.forEach((p, i) => {
    const where = `Profile ${i + 1}`;
    if (!p || typeof p !== 'object') { errors.push(`${where} must be an object.`); return; }
    const name = typeof p.name === 'string' ? p.name.trim() : '';
    if (!name) errors.push(`${where} needs a name.`);
    else if (names.has(name.toLowerCase())) errors.push(`Two profiles are named "${name}".`);
    names.add(name.toLowerCase());

    const kind = p.kind === 'file' ? 'file' : (p.kind === 'project' || p.kind === undefined ? 'project' : null);
    if (!kind) errors.push(`${name || where}: kind must be "project" or "file".`);
    const program = typeof p.program === 'string' ? p.program.trim() : '';
    if (kind === 'file' && !program) errors.push(`${name || where}: a "file" profile needs a program (.ot file).`);
    if (kind === 'file' && program && program !== '${currentFile}' && !program.toLowerCase().endsWith('.ot')) {
      errors.push(`${name || where}: program must be an .ot file.`);
    }

    const args = p.args === undefined ? [] : p.args;
    if (!Array.isArray(args) || args.some(a => typeof a !== 'string')) errors.push(`${name || where}: args must be a list of strings.`);
    else if (args.length > MAX_ARGS) errors.push(`${name || where}: at most ${MAX_ARGS} arguments.`);
    else if (args.some(a => a.length > MAX_ARG_LENGTH || a.includes('\0'))) errors.push(`${name || where}: an argument is too long or contains a NUL character.`);

    const env = p.env === undefined ? {} : p.env;
    if (!env || typeof env !== 'object' || Array.isArray(env)) errors.push(`${name || where}: env must be an object of NAME: "value".`);
    else {
      for (const [k, v] of Object.entries(env)) {
        if (!ENV_NAME.test(k)) errors.push(`${name || where}: "${k}" is not a valid environment variable name.`);
        else if (PROTECTED_ENV.has(k.toUpperCase())) errors.push(`${name || where}: ${k} cannot be set by a launch profile.`);
        if (typeof v !== 'string') errors.push(`${name || where}: the value of ${k} must be a string.`);
      }
    }

    const cwd = typeof p.cwd === 'string' && p.cwd.trim() ? p.cwd.trim() : '.';
    const timeout = p.timeoutSeconds === undefined ? DEFAULT_TIMEOUT_SECONDS : Number(p.timeoutSeconds);
    if (!Number.isInteger(timeout) || timeout < 1 || timeout > MAX_TIMEOUT_SECONDS) {
      errors.push(`${name || where}: timeoutSeconds must be a whole number from 1 to ${MAX_TIMEOUT_SECONDS}.`);
    }

    config.profiles.push({
      name, kind: kind || 'project',
      ...(kind === 'file' ? { program } : {}),
      args: Array.isArray(args) ? [...args] : [],
      cwd,
      env: env && typeof env === 'object' && !Array.isArray(env) ? { ...env } : {},
      timeoutSeconds: Number.isInteger(timeout) ? timeout : DEFAULT_TIMEOUT_SECONDS
    });
  });

  if (raw.startup !== undefined && raw.startup !== null) {
    if (typeof raw.startup !== 'string' || !names.has(raw.startup.trim().toLowerCase())) {
      errors.push(`The startup profile "${raw.startup}" does not exist.`);
    } else {
      config.startup = raw.startup.trim();
    }
  }
  return { config, errors };
}

/**
 * Turn a profile into the exact process to start.
 * `ctx` = { repoRoot, projectDir (absolute or null), currentFile (absolute or
 * null), isInside(absPath) }. Throws an Error with a user-facing message.
 * Returns { file, args, cwd, env, timeoutMs, display }.
 */
export function resolveLaunch(profile, ctx) {
  const otterPs1 = path.join(ctx.repoRoot, 'otter.ps1');
  const base = ctx.projectDir || (ctx.currentFile ? path.dirname(ctx.currentFile) : ctx.repoRoot);
  const expand = value => value
    .replace(/\$\{currentFile\}/g, ctx.currentFile || '')
    .replace(/\$\{fileDir\}/g, ctx.currentFile ? path.dirname(ctx.currentFile) : base)
    .replace(/\$\{projectDir\}/g, ctx.projectDir || base);

  let target;
  if (profile.kind === 'file') {
    const program = expand(profile.program || '');
    if (!program) throw new Error('There is no current file to run.');
    target = path.resolve(base, program);
    if (!target.toLowerCase().endsWith('.ot')) throw new Error(`${path.basename(target)} is not an Otter (.ot) file.`);
  } else {
    if (!ctx.projectDir) throw new Error('Open a project folder to run the project.');
    target = ctx.projectDir;
  }
  if (!ctx.isInside(target)) throw new Error('The program is outside the workspace.');
  if (!fs.existsSync(target)) throw new Error(`${path.relative(ctx.repoRoot, target) || target} does not exist.`);

  const cwd = path.resolve(base, expand(profile.cwd || '.'));
  if (!ctx.isInside(cwd)) throw new Error('The working folder is outside the workspace.');
  if (!fs.existsSync(cwd) || !fs.statSync(cwd).isDirectory()) throw new Error(`The working folder ${path.relative(ctx.repoRoot, cwd)} does not exist.`);

  const programArgs = (profile.args || []).map(expand);
  return {
    file: 'powershell.exe',
    // Same as otter.cmd: powershell -NoProfile -ExecutionPolicy Bypass -File otter.ps1 ...
    args: ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', otterPs1, 'run', target, ...programArgs],
    cwd,
    env: { ...process.env, ...(profile.env || {}) },
    timeoutMs: (profile.timeoutSeconds || DEFAULT_TIMEOUT_SECONDS) * 1000,
    display: ['otter', 'run', path.relative(cwd, target) || '.', ...programArgs].map(quoteForDisplay).join(' ')
  };
}

function quoteForDisplay(arg) {
  return /^[\w./\\:=@+-]+$/.test(arg) ? arg : `"${arg.replace(/"/g, '\\"')}"`;
}

// Build output folders Otter created carry this marker file (see
// Assert-OtterReplaceableOutputDir in src/Otter.Project.psm1).
const BUILD_MARKER = 'otter.build.json';

/** Read the manifest's build.outputDir (default "dist"), relative to the project. */
export function readBuildOutputDir(projectDir) {
  for (const name of ['otter.json', 'project.json']) {
    const file = path.join(projectDir, name);
    if (!fs.existsSync(file)) continue;
    try {
      const manifest = JSON.parse(fs.readFileSync(file, 'utf8'));
      const out = manifest?.build?.outputDir;
      return typeof out === 'string' && out.trim() ? out.trim() : 'dist';
    } catch {
      return 'dist';
    }
  }
  return null;
}

/**
 * Delete the project's build output, only if `otter build` created it.
 * Returns { removed: bool, outputDir, reason }.
 */
export function cleanBuildOutput(projectDir) {
  const out = readBuildOutputDir(projectDir);
  if (!out) return { removed: false, outputDir: null, reason: 'This folder has no otter.json or project.json manifest.' };
  const abs = path.resolve(projectDir, out);
  const rel = path.relative(projectDir, abs);
  if (!rel || rel.startsWith('..') || path.isAbsolute(rel)) {
    return { removed: false, outputDir: out, reason: 'build.outputDir must be a folder inside the project.' };
  }
  if (!fs.existsSync(abs)) return { removed: false, outputDir: out, reason: 'There is no build output to clean.' };
  if (!fs.existsSync(path.join(abs, BUILD_MARKER))) {
    return { removed: false, outputDir: out, reason: `${out} was not created by otter build (no ${BUILD_MARKER}), so it was left alone.` };
  }
  fs.rmSync(abs, { recursive: true, force: true });
  return { removed: true, outputDir: out, reason: null };
}

/** List the files in a folder (relative paths), for the build summary. */
export function listArtifacts(dir, limit = 200) {
  const out = [];
  const walk = (d, prefix) => {
    for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
      if (out.length >= limit) return;
      const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.isDirectory()) walk(path.join(d, entry.name), rel);
      else out.push({ path: rel, size: fs.statSync(path.join(d, entry.name)).size });
    }
  };
  if (fs.existsSync(dir)) walk(dir, '');
  return out;
}

// ---------------------------------------------------------------------------
// HTTP routes. Returns true when the request was handled.
// ---------------------------------------------------------------------------

/**
 * @param ctx { repoRoot, isInsideRepo, readBody, sendJson, readFileSnapshot,
 *              runState: { process: ChildProcess|null, lastLaunch: object|null } }
 */
export async function handleLaunchRoutes(req, res, pathname, urlObj, ctx) {
  const { repoRoot, isInsideRepo, readBody, sendJson, readFileSnapshot, runState } = ctx;
  const resolveFolder = rel => {
    if (typeof rel !== 'string' || !rel.trim()) return null;
    const abs = path.resolve(repoRoot, rel);
    return isInsideRepo(abs) && fs.existsSync(abs) && fs.statSync(abs).isDirectory() ? abs : null;
  };
  const toRel = abs => path.relative(repoRoot, abs).replace(/\\/g, '/');

  if (pathname === '/api/launch-config' && req.method === 'GET') {
    const projectDir = resolveFolder(urlObj.searchParams.get('folder'));
    if (!projectDir) return sendJson(res, { error: 'Project folder not found.' }, 404), true;
    const file = path.join(projectDir, ...LAUNCH_CONFIG_RELATIVE.split('/'));
    if (!fs.existsSync(file)) {
      return sendJson(res, { path: toRel(file), exists: false, revision: null, config: defaultLaunchConfig(), errors: [] }), true;
    }
    const snapshot = readFileSnapshot(file);
    let parsed;
    try { parsed = JSON.parse(snapshot.content); } catch (err) {
      return sendJson(res, { path: toRel(file), exists: true, revision: snapshot.revision, config: defaultLaunchConfig(), errors: [`launch.json is not valid JSON: ${err.message}`] }), true;
    }
    const { config, errors } = validateLaunchConfig(parsed);
    return sendJson(res, { path: toRel(file), exists: true, revision: snapshot.revision, config, errors }), true;
  }

  if (pathname === '/api/launch-config' && req.method === 'POST') {
    const body = await readBody(req);
    const projectDir = resolveFolder(body.folder);
    if (!projectDir) return sendJson(res, { error: 'Project folder not found.' }, 404), true;
    const { config, errors } = validateLaunchConfig(body.config);
    if (errors.length) return sendJson(res, { error: errors[0], errors }, 400), true;
    const file = path.join(projectDir, ...LAUNCH_CONFIG_RELATIVE.split('/'));
    // Same rule as file saves: replacing an existing file needs its revision.
    if (fs.existsSync(file)) {
      const current = readFileSnapshot(file);
      if (current.revision !== body.expectedRevision) {
        return sendJson(res, { error: 'launch.json changed on disk. Reload the profiles and try again.', conflict: true, revision: current.revision }, 409), true;
      }
    }
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const text = JSON.stringify(config, null, 2) + '\n';
    writeFileAtomic(file, text);
    return sendJson(res, { ok: true, path: toRel(file), revision: readFileSnapshot(file).revision, config }), true;
  }

  if (pathname === '/api/run' && req.method === 'POST') {
    const body = await readBody(req);
    const projectDir = body.folder ? resolveFolder(body.folder) : null;
    let currentFile = null;
    if (typeof body.path === 'string' && body.path.trim()) {
      currentFile = path.resolve(repoRoot, body.path);
      if (!isInsideRepo(currentFile)) return sendJson(res, { error: 'Forbidden' }, 403), true;
    }
    // A request without a profile is "run this file", as before.
    const rawProfile = body.profile || { name: 'Run File', kind: 'file', program: '${currentFile}', cwd: '${fileDir}' };
    const { config, errors } = validateLaunchConfig({ profiles: [rawProfile] });
    if (errors.length) return sendJson(res, { error: errors[0], errors }, 400), true;

    let launch;
    try {
      launch = resolveLaunch(config.profiles[0], { repoRoot, projectDir, currentFile, isInside: isInsideRepo });
    } catch (err) {
      return sendJson(res, { error: err.message }, 400), true;
    }

    stopRun(runState);
    const startTime = Date.now();
    // Our own timer rather than execFile's `timeout`: that one only kills
    // powershell itself (not programs it started), and PowerShell answers
    // SIGTERM with exit code 143 instead of a signal, so a timeout could not
    // be told apart from a failure afterwards.
    const child = execFile(launch.file, launch.args, {
      cwd: launch.cwd, env: launch.env, maxBuffer: 16 * 1024 * 1024, windowsHide: true
    }, (error, stdout, stderr) => {
      clearTimeout(timer);
      if (runState.process === child) runState.process = null;
      const timedOut = Boolean(child.timedOut);
      sendJson(res, {
        exitCode: error ? (typeof error.code === 'number' ? error.code : 1) : 0,
        stdout: stdout ? stdout.toString() : '',
        stderr: stderr ? stderr.toString() : '',
        durationMs: Date.now() - startTime,
        timedOut,
        stopped: Boolean(child.stoppedByUser),
        command: launch.display,
        cwd: toRel(launch.cwd) || '.',
        error: error && !(typeof error.code === 'number') ? error.message : null
      });
    });
    const timer = setTimeout(() => {
      child.timedOut = true;
      killTree(child);
    }, launch.timeoutMs);
    runState.process = child;
    runState.lastLaunch = { body, startedAt: startTime };
    return true;
  }

  if (pathname === '/api/stop' && req.method === 'POST') {
    const stopped = stopRun(runState);
    return sendJson(res, stopped ? { stopped: true } : { stopped: false, message: 'No process currently running' }), true;
  }

  if ((pathname === '/api/build' || pathname === '/api/clean') && req.method === 'POST') {
    const body = await readBody(req);
    const projectDir = resolveFolder(body.folder);
    if (!projectDir) return sendJson(res, { error: 'Project folder not found.' }, 404), true;
    if (!readBuildOutputDir(projectDir)) {
      return sendJson(res, { error: 'This folder has no otter.json or project.json manifest, so it cannot be built.' }, 400), true;
    }

    const startTime = Date.now();
    let cleaned = null;
    if (pathname === '/api/clean' || body.clean === true) {
      cleaned = cleanBuildOutput(projectDir);
      if (pathname === '/api/clean') {
        return sendJson(res, { ok: true, ...cleaned, durationMs: Date.now() - startTime }), true;
      }
    }

    // Every picture the pages show is in the build: the project's own
    // images a page uses are listed in its assets first (the build copies
    // listed assets), and the output says which were added.
    const addedAssets = addManifestAssets(projectDir, referencedImages(projectDir));
    const assetNote = addedAssets.length ? `Listed in the project's assets (copied into the build): ${addedAssets.join(', ')}\n` : '';
    const otterPs1 = path.join(repoRoot, 'otter.ps1');
    execFile('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', otterPs1, 'build', projectDir], {
      cwd: projectDir, timeout: 10 * 60 * 1000, maxBuffer: 16 * 1024 * 1024, windowsHide: true
    }, (error, stdout, stderr) => {
      const outputDir = readBuildOutputDir(projectDir);
      const exitCode = error ? (typeof error.code === 'number' ? error.code : 1) : 0;
      sendJson(res, {
        ok: exitCode === 0,
        exitCode,
        output: `${assetNote}${stdout || ''}${stderr || ''}`,
        durationMs: Date.now() - startTime,
        cleaned,
        outputDir,
        artifacts: exitCode === 0 ? listArtifacts(path.resolve(projectDir, outputDir)) : []
      });
    });
    return true;
  }

  return false;
}

/** Stop the running program (and its child processes). Returns true if one ran. */
export function stopRun(runState) {
  const child = runState.process;
  if (!child) return false;
  child.stoppedByUser = true;
  killTree(child);
  runState.process = null;
  return true;
}

/** Kill a process and everything it started (taskkill /t on Windows). */
export function killTree(child) {
  try {
    if (process.platform === 'win32') execFile('taskkill', ['/pid', String(child.pid), '/f', '/t'], () => {});
    else child.kill('SIGTERM');
  } catch {}
}

/** Write through a temporary file and rename, so a crash never leaves half a file. */
export function writeFileAtomic(file, text) {
  const temp = `${file}.${crypto.randomBytes(6).toString('hex')}.tmp`;
  fs.writeFileSync(temp, text, 'utf8');
  fs.renameSync(temp, file);
}
