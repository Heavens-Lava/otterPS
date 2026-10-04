// package-manager.test.mjs - End-to-end certification for Otter Studio Package & Dependency Manager
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

const TEST_PROJECT_NAME = 'test-pkg-mgr-app';

try {
  console.log('=== Running Otter Studio Package & Dependency Manager Certification Suite ===\n');

  // --- 1. Project Creation with Default Dependencies ---
  console.log('--- 1. Create Test Project with Dependencies ---');
  const createRes = await api('/api/create-project', {
    name: TEST_PROJECT_NAME,
    archetype: 'console',
    target: 'console',
    code: 'say "Package Manager Test"\n'
  });
  assert.equal(createRes.status, 200);
  assert.equal(createRes.data.ok, true);
  const projectFolder = createRes.data.folder;
  const projectDir = path.join(REPO_ROOT, projectFolder);
  console.log(`  ✓ Project created on disk at ${projectFolder}`);

  // --- 2. Query Initial Dependencies ---
  console.log('\n--- 2. Inspect Initial Dependencies ---');
  const getRes = await api(`/api/project-manifest?folder=${encodeURIComponent(projectFolder)}`, null, 'GET');
  assert.equal(getRes.status, 200);
  assert.ok(getRes.data.manifest.dependencies, 'Dependencies object must exist');
  assert.equal(getRes.data.manifest.dependencies.core, '^1.0.0');
  console.log('  ✓ Initial manifest contains default dependencies: { core: "^1.0.0" }');

  // --- 3. Add Package Dependencies ---
  console.log('\n--- 3. Add Package Dependencies ---');
  const updatedManifest = {
    ...getRes.data.manifest,
    dependencies: {
      ...getRes.data.manifest.dependencies,
      'math-utils': '^2.4.0',
      'network-client': '~1.1.0'
    }
  };

  const addRes = await api('/api/project-manifest', {
    folder: projectFolder,
    manifest: updatedManifest
  });
  assert.equal(addRes.status, 200);
  assert.equal(addRes.data.ok, true);
  assert.equal(addRes.data.manifest.dependencies['math-utils'], '^2.4.0');
  assert.equal(addRes.data.manifest.dependencies['network-client'], '~1.1.0');

  // Read back directly from disk
  const diskManifest = JSON.parse(fs.readFileSync(path.join(projectDir, 'project.json'), 'utf8'));
  assert.equal(diskManifest.dependencies['math-utils'], '^2.4.0');
  console.log('  ✓ Added packages persisted to disk and verified via read-back');

  // --- 4. Update Dependency Version ---
  console.log('\n--- 4. Update Dependency Version ---');
  diskManifest.dependencies.core = '^1.5.0';
  const updateRes = await api('/api/project-manifest', {
    folder: projectFolder,
    manifest: diskManifest
  });
  assert.equal(updateRes.status, 200);
  assert.equal(updateRes.data.manifest.dependencies.core, '^1.5.0');
  console.log('  ✓ Updated dependency version verified: core -> ^1.5.0');

  // --- 5. Remove Dependency ---
  console.log('\n--- 5. Remove Package Dependency ---');
  delete diskManifest.dependencies['math-utils'];
  const removeRes = await api('/api/project-manifest', {
    folder: projectFolder,
    manifest: diskManifest
  });
  assert.equal(removeRes.status, 200);
  assert.equal(removeRes.data.manifest.dependencies['math-utils'], undefined);
  assert.equal(Object.keys(removeRes.data.manifest.dependencies).length, 2);
  console.log('  ✓ Package math-utils removed successfully');

  // --- 6. Modular Cross-File Dependency Execution ---
  console.log('\n--- 6. Modular Multi-File Import and Execution ---');
  const libDir = path.join(projectDir, 'lib');
  fs.mkdirSync(libDir, { recursive: true });
  fs.writeFileSync(path.join(libDir, 'calc.ot'), `to printTotal amount
    say "Total is " amount
.
`, 'utf8');

  const mainWithUse = `use "lib/calc.ot"

printTotal 35
`;
  fs.writeFileSync(path.join(projectDir, 'main.ot'), mainWithUse, 'utf8');

  const runRes = await api('/api/run', {
    path: `${projectFolder}/main.ot`,
    cwd: projectFolder
  });
  if (!runRes.data.ok) {
    console.error('Run failed:', runRes.data);
  }
  assert.equal(runRes.status, 200);
  assert.equal(runRes.data.ok, true);
  assert.equal(runRes.data.exitCode, 0);
  assert.match(runRes.data.stdout, /Total is\s+35/);
  console.log('  ✓ Modular dependency imported with use and executed cleanly with code 0');

  console.log('\n========================================');
  console.log('Package Manager Certification: All tests passed cleanly!');
} finally {
  const pDir = path.join(REPO_ROOT, 'projects', TEST_PROJECT_NAME);
  if (fs.existsSync(pDir)) {
    fs.rmSync(pDir, { recursive: true, force: true });
  }
}
