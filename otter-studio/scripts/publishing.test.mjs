// publishing.test.mjs - Publishing, Release Packaging & Deployment Verification Suite
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import {
  DEPLOYMENT_PRESETS,
  validatePublishReadiness,
  generateDeploymentPackage
} from '../js/project/publish-wizard.js';

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

test('Publish Wizard: validatePublishReadiness checks manifest properties', () => {
  const valid = validatePublishReadiness({
    name: 'MyCoolApp',
    version: '1.2.0',
    entryPoint: 'main.ot',
    target: 'web'
  });
  assert.equal(valid.ok, true);
  assert.equal(valid.name, 'MyCoolApp');
  assert.equal(valid.version, '1.2.0');

  // Missing name
  const missingName = validatePublishReadiness({ version: '1.0.0', entryPoint: 'main.ot' });
  assert.equal(missingName.ok, false);
  assert.ok(missingName.errors.some(e => e.includes('must specify a "name"')));

  // Bad name with slash
  const badName = validatePublishReadiness({ name: 'foo/bar', version: '1.0.0', entryPoint: 'main.ot' });
  assert.equal(badName.ok, false);
  assert.ok(badName.errors.some(e => e.includes('invalid for distribution')));

  // Bad entryPoint
  const badEntry = validatePublishReadiness({ name: 'App', version: '1.0.0', entryPoint: 'main.txt' });
  assert.equal(badEntry.ok, false);
  assert.ok(badEntry.errors.some(e => e.includes('ending in .ot')));

  // Invalid target
  const badTarget = validatePublishReadiness({ name: 'App', version: '1.0.0', entryPoint: 'main.ot', target: 'quantum' });
  assert.equal(badTarget.ok, false);
  assert.ok(badTarget.errors.some(e => e.includes('recognized Otter target')));
});

test('Publish Wizard: generateDeploymentPackage generates presets and guides', () => {
  const webPkg = generateDeploymentPackage({
    name: 'WebShowcase',
    version: '2.0.0',
    entryPoint: 'index.ot',
    target: 'web'
  });

  assert.equal(webPkg.preset, 'web-static');
  assert.equal(webPkg.archiveName, 'WebShowcase-2.0.0.zip');
  assert.equal(webPkg.checksumName, 'WebShowcase-2.0.0.zip.sha256');
  assert.match(webPkg.deployDoc, /GitHub Pages/);
  assert.match(webPkg.deployDoc, /WebShowcase-2.0.0\.zip/);

  const desktopPkg = generateDeploymentPackage({
    name: 'DesktopTool',
    version: '1.0.0-rc.1',
    entryPoint: 'app.ot',
    target: 'desktop'
  });

  assert.equal(desktopPkg.preset, 'desktop-windows');
  assert.match(desktopPkg.deployDoc, /run-desktop\.cmd/);
});

test('Live Studio Server API: POST /api/publish packages console project with checksum and metadata', async () => {
  const projName = 'test-pub-console-app';
  const projFolder = `projects/${projName}`;
  const absProjDir = path.join(REPO_ROOT, projFolder);

  try {
    // 1. Create console project
    const createRes = await api('/api/create-project', {
      name: projName,
      archetype: 'console',
      target: 'console',
      code: 'say "Publish Test Console App"\n'
    });
    assert.equal(createRes.status, 200);

    // 2. Publish project via /api/publish
    const pubRes = await api('/api/publish', { folder: projFolder });
    assert.equal(pubRes.status, 200);
    assert.equal(pubRes.data.ok, true);
    assert.equal(pubRes.data.exitCode, 0);

    // Verify metadata and archive paths
    assert.ok(pubRes.data.archiveName);
    assert.match(pubRes.data.archiveName, new RegExp(`${projName}-1\\.0\\.0\\.zip`));
    assert.ok(pubRes.data.archivePath);
    assert.ok(pubRes.data.checksum);
    assert.ok(pubRes.data.checksumPath);

    // Verify on disk
    const zipOnDisk = path.join(REPO_ROOT, pubRes.data.archivePath);
    assert.ok(fs.existsSync(zipOnDisk), 'Release zip archive must exist on disk');

    const shaOnDisk = path.join(REPO_ROOT, pubRes.data.checksumPath);
    assert.ok(fs.existsSync(shaOnDisk), 'Checksum file must exist on disk');

    // Compute actual SHA256 of zip file and compare with published checksum
    const zipBytes = fs.readFileSync(zipOnDisk);
    const computedHash = crypto.createHash('sha256').update(zipBytes).digest('hex').toUpperCase();
    const storedContent = fs.readFileSync(shaOnDisk, 'utf8').trim();
    const storedHash = storedContent.split(/\s+/)[0].toUpperCase();
    assert.equal(computedHash, storedHash, 'Stored checksum must match byte-for-byte SHA256 of archive');

    // Verify otter.publish.json
    assert.ok(pubRes.data.publishMeta);
    assert.equal(pubRes.data.publishMeta.name, projName);
    assert.equal(pubRes.data.publishMeta.target, 'console');
  } finally {
    if (fs.existsSync(absProjDir)) {
      fs.rmSync(absProjDir, { recursive: true, force: true });
    }
  }
});

test('Live Studio Server API: POST /api/publish packages web project with inlined assets', async () => {
  const projName = 'test-pub-web-app';
  const projFolder = `projects/${projName}`;
  const absProjDir = path.join(REPO_ROOT, projFolder);

  try {
    const createRes = await api('/api/create-project', {
      name: projName,
      archetype: 'web',
      target: 'web',
      code: 'title is "Published Web App"\nsay "Welcome to Otter Web"\n'
    });
    assert.equal(createRes.status, 200);

    const pubRes = await api('/api/publish', { folder: projFolder });
    assert.equal(pubRes.status, 200);
    assert.equal(pubRes.data.ok, true);

    const pubDir = path.join(absProjDir, 'publish');
    assert.ok(fs.existsSync(pubDir));

    // Verify unzipped package folder exists
    const pkgFolder = path.join(pubDir, `${projName}-1.0.0`);
    assert.ok(fs.existsSync(pkgFolder));
    assert.ok(fs.existsSync(path.join(pkgFolder, 'index.html')));

    const htmlContent = fs.readFileSync(path.join(pkgFolder, 'index.html'), 'utf8');
    assert.match(htmlContent, /Published Web App/);
  } finally {
    if (fs.existsSync(absProjDir)) {
      fs.rmSync(absProjDir, { recursive: true, force: true });
    }
  }
});
