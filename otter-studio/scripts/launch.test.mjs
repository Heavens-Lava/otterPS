// launch.test.mjs - Run, launch profiles, build and clean (checklist §18).
//
// Certification rule from the checklist: a real .ot program must reach the
// feature through the real entry point. So besides unit tests of the
// profile validation, this starts Studio's server and runs a real project
// (created by `otter new`) with arguments, environment variables and a
// working folder, builds it with `otter build`, and cleans it.
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createScratchFolder } from './test-scratch.mjs';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(studioRoot, '..');
const { validateLaunchConfig, defaultLaunchConfig, resolveLaunch, cleanBuildOutput } =
  await import(pathToFileURL(path.join(studioRoot, 'server', 'launch.mjs')).href);
const { parseArgLines, parseEnvLines, formatEnvLines } =
  await import(pathToFileURL(path.join(studioRoot, 'js', 'components', 'launch-profiles.js')).href);

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`  ✓ ${name}`);
}

console.log('Launch profiles (validation):');

await test('the default configuration is valid', () => {
  const { errors, config } = validateLaunchConfig(defaultLaunchConfig());
  assert.deepEqual(errors, []);
  assert.equal(config.startup, 'Run Project');
});

await test('every problem is reported, in plain words', () => {
  const { errors } = validateLaunchConfig({
    startup: 'Nope',
    profiles: [
      { name: 'A', kind: 'file' },
      { name: 'a', args: 'not a list', env: { 'BAD NAME': 'x', PATH: '/evil' }, timeoutSeconds: 0 }
    ]
  });
  const text = errors.join('\n');
  assert.match(text, /needs a program/);
  assert.match(text, /Two profiles are named "a"/);
  assert.match(text, /args must be a list/);
  assert.match(text, /not a valid environment variable name/);
  assert.match(text, /PATH cannot be set/);
  assert.match(text, /timeoutSeconds/);
  assert.match(text, /startup profile "Nope" does not exist/);
});

await test('a program outside the workspace or the working folder is refused', () => {
  const ctx = { repoRoot, projectDir: path.join(repoRoot, 'examples'), currentFile: null, isInside: p => !path.relative(repoRoot, p).startsWith('..') };
  assert.throws(() => resolveLaunch({ kind: 'file', program: '../../outside.ot', cwd: '.' }, ctx), /outside the workspace/);
  assert.throws(() => resolveLaunch({ kind: 'file', program: 'hello.ot', cwd: '../..' }, ctx), /working folder is outside/);
});

await test('arguments are passed as an array, never through a shell', () => {
  const ctx = { repoRoot, projectDir: path.join(repoRoot, 'examples'), currentFile: null, isInside: () => true };
  const launch = resolveLaunch({ kind: 'file', program: 'hello.ot', args: ['a b', '"; rm -rf /', '$(x)'], cwd: '.' }, ctx);
  assert.deepEqual(launch.args.slice(-3), ['a b', '"; rm -rf /', '$(x)']);
  assert.equal(launch.file, 'powershell.exe');
});

await test('editor helpers: one argument per line, NAME=value environment', () => {
  assert.deepEqual(parseArgLines('--input\n\nmy file.csv\n'), ['--input', 'my file.csv']);
  const { env, errors } = parseEnvLines('A=1\n# comment\nB = x=y\nbad line\n9X=1');
  assert.deepEqual(env, { A: '1', B: 'x=y' });
  assert.equal(errors.length, 2);
  assert.equal(formatEnvLines({ A: '1', B: 'x=y' }), 'A=1\nB=x=y');
});

await test('clean never deletes a folder that otter build did not create', () => {
  const scratch = createScratchFolder(repoRoot, 'launch-clean');
  fs.writeFileSync(path.join(scratch.abs, 'otter.json'), JSON.stringify({ entryPoint: 'main.ot', build: { outputDir: 'src' } }));
  fs.mkdirSync(path.join(scratch.abs, 'src'));
  fs.writeFileSync(path.join(scratch.abs, 'src', 'precious.ot'), 'say 1\n');
  const result = cleanBuildOutput(scratch.abs);
  assert.equal(result.removed, false);
  assert.match(result.reason, /not created by otter build/);
  assert.ok(fs.existsSync(path.join(scratch.abs, 'src', 'precious.ot')));
});

console.log('\nRun and build through the real otter command:');

const scratch = createScratchFolder(repoRoot, 'launch');
execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(repoRoot, 'otter.ps1'), 'new', 'console', 'demo'], { cwd: scratch.abs, stdio: 'ignore' });
const projectRel = `${scratch.rel}/demo`;
const projectAbs = path.join(scratch.abs, 'demo');
fs.writeFileSync(path.join(projectAbs, 'main.ot'), [
  'say "args: " length of arguments',
  'for each arg in arguments',
  '    say "arg: " arg',
  '.',
  'get environment variable "OTTER_STUDIO_TEST" into flag',
  'say "env: " flag',
  'get current directory into folder',
  'say "cwd: " folder',
  ''
].join('\n'));
fs.writeFileSync(path.join(projectAbs, 'src', 'loop.ot'), 'while true\n    wait 1 second\n.\n');

const port = 5300 + (process.pid % 500);
const baseUrl = `http://127.0.0.1:${port}`;
const server = spawn(process.execPath, ['serve.mjs'], { cwd: studioRoot, env: { ...process.env, OTTER_STUDIO_PORT: String(port) }, stdio: 'ignore' });
process.on('exit', () => server.kill());
for (let attempt = 0; ; attempt++) {
  try { if ((await fetch(`${baseUrl}/`)).ok) break; } catch {}
  // 15 s: a cold Node start on Windows after the launch tests can take several seconds.
  if (attempt > 150) throw new Error('Studio server did not start');
  await new Promise(r => setTimeout(r, 100));
}
const post = async (route, body) => {
  const res = await fetch(`${baseUrl}${route}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  return { status: res.status, body: await res.json() };
};

try {
  await test('Run Project passes arguments, environment and working folder to the program', async () => {
    const { status, body } = await post('/api/run', {
      folder: projectRel,
      profile: { name: 'Sample', kind: 'project', args: ['first arg', '--flag'], cwd: 'src', env: { OTTER_STUDIO_TEST: 'on' } }
    });
    assert.equal(status, 200);
    assert.equal(body.exitCode, 0, body.stderr);
    assert.match(body.stdout, /args:\s+2/);
    assert.match(body.stdout, /arg:\s+first arg\n/);
    assert.match(body.stdout, /arg:\s+--flag/);
    assert.match(body.stdout, /env:\s+on/);
    assert.match(body.stdout, /cwd:\s+.*demo[\\/]src/);
  });

  await test('Run Current File runs one file (old request shape still works)', async () => {
    const { body } = await post('/api/run', { path: `${projectRel}/main.ot` });
    assert.equal(body.exitCode, 0, body.stderr);
    assert.match(body.stdout, /args:\s+0/);
  });

  await test('a profile timeout stops a program that never ends', async () => {
    const { body } = await post('/api/run', {
      folder: projectRel,
      profile: { name: 'Loop', kind: 'file', program: 'src/loop.ot', timeoutSeconds: 4 }
    });
    assert.notEqual(body.exitCode, 0);
    assert.equal(body.timedOut, true);
  });

  await test('Stop ends the running program', async () => {
    const running = post('/api/run', { folder: projectRel, profile: { name: 'Loop', kind: 'file', program: 'src/loop.ot', timeoutSeconds: 60 } });
    await new Promise(r => setTimeout(r, 1500));
    const stop = await post('/api/stop', {});
    assert.equal(stop.body.stopped, true);
    const { body } = await running;
    assert.equal(body.stopped, true);
  });

  await test('launch.json is saved, read back, and protected by its revision', async () => {
    const config = { startup: 'Sample', profiles: [{ name: 'Sample', kind: 'project', args: ['x'] }] };
    const first = await post('/api/launch-config', { folder: projectRel, config });
    assert.equal(first.status, 200, JSON.stringify(first.body));
    const read = await (await fetch(`${baseUrl}/api/launch-config?folder=${encodeURIComponent(projectRel)}`)).json();
    assert.equal(read.exists, true);
    assert.equal(read.config.startup, 'Sample');
    const stale = await post('/api/launch-config', { folder: projectRel, config });
    assert.equal(stale.status, 409, 'saving over an existing launch.json without its revision is a conflict');
    const ok = await post('/api/launch-config', { folder: projectRel, config, expectedRevision: read.revision });
    assert.equal(ok.status, 200);
    const bad = await post('/api/launch-config', { folder: projectRel, config: { profiles: [{ name: '' }] }, expectedRevision: ok.body.revision });
    assert.equal(bad.status, 400);
  });

  await test('Build runs otter build and lists the artifacts; Rebuild cleans first', async () => {
    const build = await post('/api/build', { folder: projectRel });
    assert.equal(build.body.ok, true, build.body.output);
    assert.match(build.body.output, /Build succeeded/);
    assert.ok(build.body.artifacts.some(a => a.path === 'otter.build.json'));
    fs.writeFileSync(path.join(projectAbs, 'dist', 'stale.txt'), 'old');
    const rebuild = await post('/api/build', { folder: projectRel, clean: true });
    assert.equal(rebuild.body.ok, true);
    assert.equal(rebuild.body.cleaned.removed, true);
    assert.equal(fs.existsSync(path.join(projectAbs, 'dist', 'stale.txt')), false);
  });

  await test('a build error is reported with a non-zero exit code', async () => {
    const mainPath = path.join(projectAbs, 'main.ot');
    const good = fs.readFileSync(mainPath, 'utf8');
    fs.writeFileSync(mainPath, 'say "unterminated\n');
    const build = await post('/api/build', { folder: projectRel });
    fs.writeFileSync(mainPath, good);
    assert.equal(build.body.ok, false);
    assert.notEqual(build.body.exitCode, 0);
    assert.match(build.body.output, /Build failed/);
  });

  await test('Publish runs otter publish and names the package to upload and its zip', async () => {
    const pub = await post('/api/publish', { folder: projectRel });
    assert.equal(pub.body.ok, true, pub.body.output);
    assert.match(pub.body.output, /Publish succeeded/);
    assert.equal(pub.body.publishDir, 'publish');
    assert.ok(pub.body.packageFolder && fs.existsSync(path.join(projectAbs, 'publish', pub.body.packageFolder)), JSON.stringify(pub.body));
    assert.equal(pub.body.zip, `${pub.body.packageFolder}.zip`);
    assert.ok(pub.body.files.some(f => f.path === 'otter.publish.json'));
    const none = await post('/api/publish', { folder: 'otter-studio' });
    assert.equal(none.status, 400, 'a folder without a manifest cannot be published');
    fs.rmSync(path.join(projectAbs, 'publish'), { recursive: true, force: true });
  });

  await test('Clean removes only Otter-created output', async () => {
    const clean = await post('/api/clean', { folder: projectRel });
    assert.equal(clean.body.removed, true);
    assert.equal(fs.existsSync(path.join(projectAbs, 'dist')), false);
  });
} finally {
  server.kill();
}

console.log(`\nLaunch tests passed: ${passed}.`);
