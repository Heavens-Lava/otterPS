// build-system.test.mjs - End-to-end certification for Otter Studio Build & Launch System
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');
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

const TEST_PROJECT_NAME = 'test-build-sys-app';

try {
  console.log('=== Running Otter Studio Build & Launch System Certification Suite ===\n');

  // --- 1. Project Creation ---
  console.log('--- 1. Create Test Console Project ---');
  const createRes = await api('/api/create-project', {
    name: TEST_PROJECT_NAME,
    archetype: 'console',
    target: 'console',
    code: 'say "Hello, Otter!"\n'
  });
  assert.equal(createRes.status, 200, 'Project creation should return 200');
  assert.equal(createRes.data.ok, true);
  const projectFolder = createRes.data.folder;
  const projectDir = path.join(REPO_ROOT, projectFolder);
  console.log(`  ✓ Project created on disk at ${projectFolder}`);

  // --- 2. Build Project (/api/build) ---
  console.log('\n--- 2. Build Project via /api/build ---');
  const buildRes = await api('/api/build', {
    folder: projectFolder
  });
  assert.equal(buildRes.status, 200, 'Build should return 200 OK');
  assert.equal(buildRes.data.ok, true, 'Build response ok should be true');
  assert.equal(buildRes.data.exitCode, 0, 'Exit code should be 0');
  assert.ok(buildRes.data.buildMeta, 'Build response should include buildMeta');
  assert.equal(buildRes.data.buildMeta.name, TEST_PROJECT_NAME);
  assert.equal(buildRes.data.buildMeta.target, 'console');

  // Verify on-disk output
  const distDir = path.join(projectDir, 'dist');
  assert.ok(fs.existsSync(distDir), 'dist/ directory must exist');
  assert.ok(fs.existsSync(path.join(distDir, 'otter.build.json')), 'otter.build.json must exist');
  assert.ok(fs.existsSync(path.join(distDir, 'main.ot')), 'dist/main.ot must exist');
  assert.ok(fs.existsSync(path.join(distDir, 'run.cmd')), 'dist/run.cmd must exist');
  assert.ok(fs.existsSync(path.join(distDir, 'run')), 'dist/run launcher must exist');
  console.log('  ✓ Build produced dist/ with otter.build.json, main.ot, run.cmd, and run launcher');

  // --- 3. Enhanced Run with Launch Profiles (/api/run) ---
  console.log('\n--- 3. Enhanced Run with Launch Options ---');
  const runRes = await api('/api/run', {
    path: `${projectFolder}/dist/main.ot`,
    cwd: `${projectFolder}/dist`
  });
  assert.equal(runRes.status, 200);
  assert.equal(runRes.data.ok, true);
  assert.equal(runRes.data.exitCode, 0);
  assert.match(runRes.data.stdout, /Hello, Otter!/);
  console.log('  ✓ Executed built application successfully with exit code 0');

  // --- 4. Clean Refusal Safety (/api/clean) ---
  console.log('\n--- 4. Clean Refusal Safety ---');
  // Attempting to clean a directory without otter.build.json marker must be refused
  const fakeDir = path.join(projectDir, 'my_custom_folder');
  fs.mkdirSync(fakeDir, { recursive: true });
  fs.writeFileSync(path.join(fakeDir, 'secret.txt'), 'important data');
  
  // Point project.json outputDir to my_custom_folder to simulate dangerous config
  const manifestPath = fs.existsSync(path.join(projectDir, 'otter.json')) 
    ? path.join(projectDir, 'otter.json') 
    : path.join(projectDir, 'project.json');
  const manifestConfig = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  manifestConfig.build = { ...(manifestConfig.build || {}), outputDir: 'my_custom_folder' };
  fs.writeFileSync(manifestPath, JSON.stringify(manifestConfig, null, 2));

  const unsafeClean = await api('/api/clean', { folder: projectFolder });
  assert.equal(unsafeClean.status, 400, 'Unsafe clean must be refused with 400');
  assert.ok(fs.existsSync(path.join(fakeDir, 'secret.txt')), 'Protected folder was NOT deleted');
  console.log('  ✓ Clean refusal safety protected non-Otter folder from deletion');

  // Restore outputDir to dist
  manifestConfig.build.outputDir = 'dist';
  fs.writeFileSync(manifestPath, JSON.stringify(manifestConfig, null, 2));

  // --- 5. Clean Output Directory (/api/clean) ---
  console.log('\n--- 5. Clean Output Directory ---');
  const cleanRes = await api('/api/clean', { folder: projectFolder });
  assert.equal(cleanRes.status, 200);
  assert.equal(cleanRes.data.ok, true);
  assert.equal(cleanRes.data.cleaned, true);
  assert.equal(fs.existsSync(distDir), false, 'dist/ directory should be removed after clean');
  console.log('  ✓ dist/ directory cleaned successfully');

  // --- 6. Publish Project (/api/publish) ---
  console.log('\n--- 6. Publish Project via /api/publish ---');
  const pubRes = await api('/api/publish', { folder: projectFolder });
  assert.equal(pubRes.status, 200, 'Publish should return 200 OK');
  assert.equal(pubRes.data.ok, true);
  assert.equal(pubRes.data.exitCode, 0);

  const pubDir = path.join(projectDir, 'publish');
  assert.ok(fs.existsSync(pubDir), 'publish/ directory must exist');
  const pubFiles = fs.readdirSync(pubDir);
  const zipFile = pubFiles.find(f => f.endsWith('.zip'));
  assert.ok(zipFile, 'Publish must produce a zip archive');
  console.log(`  ✓ Published distributable archive: ${zipFile}`);

  console.log('\n========================================');
  console.log('Build System Certification: All tests passed cleanly!');
} finally {
  const pDir = path.join(REPO_ROOT, 'projects', TEST_PROJECT_NAME);
  if (fs.existsSync(pDir)) {
    fs.rmSync(pDir, { recursive: true, force: true });
  }
}
