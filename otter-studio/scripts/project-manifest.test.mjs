// project-manifest.test.mjs - Automated Certification Suite for Project Manifest & Settings
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  createDefaultManifest,
  normalizeManifest,
  validateManifest,
  serializeManifest,
  VALID_ARCHETYPES
} from '../js/project/project-manifest.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const PORT = Number(process.env.OTTER_STUDIO_PORT || 4200);
const baseUrl = `http://127.0.0.1:${PORT}`;

async function request(endpoint, options = {}) {
  const url = `${baseUrl}${endpoint}`;
  const res = await fetch(url, options);
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {}
  return { status: res.status, ok: res.ok, text, json };
}

async function runTests() {
  console.log('=== Running Otter Project Manifest & Settings Certification Suite ===\n');
  let passed = 0;
  let failed = 0;

  function test(name, fn) {
    try {
      fn();
      console.log(`  ✓ ${name}`);
      passed++;
    } catch (err) {
      console.error(`  ✗ ${name}:`, err.message);
      failed++;
    }
  }

  async function testAsync(name, fn) {
    try {
      await fn();
      console.log(`  ✓ ${name}`);
      passed++;
    } catch (err) {
      console.error(`  ✗ ${name}:`, err.message);
      failed++;
    }
  }

  // 1. Schema Generation Across Archetypes
  console.log('--- 1. Schema Generation Across Archetypes ---');
  for (const arch of VALID_ARCHETYPES) {
    test(`Generates valid default manifest for archetype: ${arch}`, () => {
      const manifest = createDefaultManifest(`my-${arch}-app`, arch);
      assert.equal(manifest.name, `my-${arch}-app`);
      assert.equal(manifest.version, '1.0.0');
      assert.equal(manifest.target, arch);
      assert.equal(manifest.archetype, arch);
      assert.ok(manifest.entryPoint && manifest.entryPoint.endsWith('.ot'));
      assert.ok(manifest.build && typeof manifest.build === 'object');
      assert.equal(manifest.build.outputDir, 'dist');
      assert.equal(manifest.build.sourceMaps, true);
      assert.equal(manifest.build.clean, true);
      assert.ok(manifest.permissions && typeof manifest.permissions === 'object');
      assert.equal(manifest.permissions.filesystem, true);
      assert.ok(manifest.dependencies && manifest.dependencies.core);
      assert.ok(Array.isArray(manifest.assets));
      assert.ok(manifest.scripts && manifest.scripts.start);
    });
  }

  // 2. Normalization & Backwards Compatibility
  console.log('\n--- 2. Normalization & Backwards Compatibility ---');
  test('Normalizes legacy project.json with "main" and missing sections', () => {
    const legacy = {
      name: 'legacy-project',
      main: 'script.ot',
      archetype: 'console'
    };
    const normalized = normalizeManifest(legacy);
    assert.equal(normalized.name, 'legacy-project');
    assert.equal(normalized.entryPoint, 'script.ot');
    assert.equal(normalized.version, '1.0.0');
    assert.equal(normalized.target, 'console');
    assert.equal(normalized.build.outputDir, 'dist');
    assert.equal(normalized.permissions.filesystem, true);
    assert.deepEqual(normalized.dependencies, {});
    assert.deepEqual(normalized.assets, []);
  });

  test('Handles null or non-object raw input safely', () => {
    const fallback = normalizeManifest(null);
    assert.equal(fallback.name, 'my-app');
    assert.equal(fallback.target, 'desktop');
    assert.equal(fallback.version, '1.0.0');
  });

  // 3. Validation Logic
  console.log('\n--- 3. Validation Rules & Diagnostics ---');
  test('Validates complete manifest without errors or warnings', () => {
    const manifest = createDefaultManifest('demo', 'desktop', 'main.ot');
    const mockFiles = [{ name: 'main.ot', path: 'main.ot' }, { name: 'styles.css', path: 'styles.css' }];
    const res = validateManifest(manifest, mockFiles);
    assert.equal(res.ok, true);
    assert.equal(res.errors.length, 0);
    assert.equal(res.warnings.length, 0);
  });

  test('Detects missing entryPoint on disk with warning', () => {
    const manifest = createDefaultManifest('demo', 'desktop', 'missing.ot');
    const mockFiles = [{ name: 'main.ot', path: 'main.ot' }];
    const res = validateManifest(manifest, mockFiles);
    assert.equal(res.ok, true);
    assert.ok(res.warnings.some(w => w.includes('missing.ot')));
  });

  test('Rejects empty or blank project name', () => {
    const manifest = createDefaultManifest('', 'desktop');
    manifest.name = '';
    const res = validateManifest(manifest);
    assert.equal(res.ok, false);
    assert.ok(res.errors.some(e => e.includes('name is required')));
  });

  test('Flags non-SemVer version with warning', () => {
    const manifest = createDefaultManifest('demo', 'desktop');
    manifest.version = 'v1';
    const res = validateManifest(manifest);
    assert.ok(res.warnings.some(w => w.includes('Semantic Versioning')));
  });

  // 4. Serialization
  console.log('\n--- 4. Serialization ---');
  test('Serializes to clean indented JSON ending with newline', () => {
    const manifest = createDefaultManifest('clean-app', 'web', 'web-app.ot');
    const serialized = serializeManifest(manifest);
    assert.ok(serialized.endsWith('\n'));
    const parsed = JSON.parse(serialized);
    assert.equal(parsed.name, 'clean-app');
    assert.equal(parsed.target, 'web');
  });

  // 5. Backend Server API Integration
  console.log('\n--- 5. Backend Server API Integration ---');
  await testAsync('POST /api/create-project generates rich project.json', async () => {
    const createRes = await request('/api/create-project', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: 'test-rich-manifest',
        archetype: 'web',
        fileName: 'web-app.ot',
        code: 'say "Web app started"\n'
      })
    });
    assert.equal(createRes.status, 200);
    assert.equal(createRes.json.ok, true);

    const manifestDiskPath = path.join(REPO_ROOT, 'projects', 'test-rich-manifest', 'project.json');
    assert.ok(fs.existsSync(manifestDiskPath), 'project.json must exist on disk');

    const diskContent = JSON.parse(fs.readFileSync(manifestDiskPath, 'utf8'));
    assert.equal(diskContent.name, 'test-rich-manifest');
    assert.equal(diskContent.target, 'web');
    assert.equal(diskContent.version, '1.0.0');
    assert.ok(diskContent.build && diskContent.build.outputDir === 'dist');
    assert.ok(diskContent.permissions && diskContent.permissions.filesystem === true);
    assert.ok(diskContent.dependencies && diskContent.dependencies.core);
  });

  await testAsync('GET /api/project-manifest returns normalized manifest and validation', async () => {
    const getRes = await request('/api/project-manifest?folder=projects/test-rich-manifest');
    assert.equal(getRes.status, 200);
    assert.equal(getRes.json.ok, true);
    assert.equal(getRes.json.manifest.name, 'test-rich-manifest');
    assert.equal(getRes.json.manifest.target, 'web');
    assert.ok(getRes.json.validation && getRes.json.validation.ok);
  });

  await testAsync('POST /api/project-manifest updates manifest and saves to disk', async () => {
    const updated = createDefaultManifest('test-rich-manifest', 'web', 'web-app.ot', {
      version: '1.2.3',
      description: 'Updated description for certification test',
      author: 'Otter Team'
    });
    updated.permissions.network = true;

    const postRes = await request('/api/project-manifest', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        folder: 'projects/test-rich-manifest',
        manifest: updated
      })
    });
    assert.equal(postRes.status, 200);
    assert.equal(postRes.json.ok, true);
    assert.equal(postRes.json.manifest.version, '1.2.3');
    assert.equal(postRes.json.manifest.author, 'Otter Team');

    // Verify written to disk
    const manifestDiskPath = path.join(REPO_ROOT, 'projects', 'test-rich-manifest', 'project.json');
    const diskContent = JSON.parse(fs.readFileSync(manifestDiskPath, 'utf8'));
    assert.equal(diskContent.version, '1.2.3');
    assert.equal(diskContent.description, 'Updated description for certification test');
    assert.equal(diskContent.permissions.network, true);
  });

  console.log(`\n========================================`);
  console.log(`Manifest Test Summary: ${passed} passed, ${failed} failed.`);
  if (failed > 0) {
    process.exit(1);
  }
}

runTests().catch(err => {
  console.error('Fatal error in test suite:', err);
  process.exit(1);
});
