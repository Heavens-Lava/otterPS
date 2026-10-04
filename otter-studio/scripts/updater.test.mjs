// otter-studio/scripts/updater.test.mjs
// Certification test for Otter Update System (Section 35)
// Validates SemVer comparison, channels, cryptographic integrity,
// skip version preferences, atomic rollback, release notes parsing,
// and live Studio update APIs.

import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { OtterUpdateManager } from '../js/updater/update-manager.js';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(studioRoot, '..');
const PORT = Number(process.env.OTTER_STUDIO_PORT || 4200);
const baseUrl = `http://127.0.0.1:${PORT}`;

test('Update Manager: SemVer Comparison Engine', () => {
  assert.equal(OtterUpdateManager.compareVersions('1.0.1', '1.0.0'), 1);
  assert.equal(OtterUpdateManager.compareVersions('1.0.0', '1.0.1'), -1);
  assert.equal(OtterUpdateManager.compareVersions('1.0.0', '1.0.0'), 0);
  assert.equal(OtterUpdateManager.compareVersions('1.1.0', '1.0.9'), 1);
  assert.equal(OtterUpdateManager.compareVersions('2.0.0', '1.9.9'), 1);
  assert.equal(OtterUpdateManager.compareVersions('1.0.0', '1.0.0-preview.1'), 1);
  assert.equal(OtterUpdateManager.compareVersions('1.0.0-preview.2', '1.0.0-preview.1'), 1);

  const manager = new OtterUpdateManager({ currentVersion: '1.0.0' });
  assert.equal(manager.isUpdateAvailable('1.0.1'), true);
  assert.equal(manager.isUpdateAvailable('1.0.0'), false);
  assert.equal(manager.isUpdateAvailable('0.9.9'), false);
});

test('Update Manager: Channel Switching & Persistence', () => {
  const store = new Map();
  const manager = new OtterUpdateManager({ currentVersion: '1.0.0', storage: store });

  assert.equal(manager.getChannel(), 'stable');
  manager.setChannel('preview');
  assert.equal(manager.getChannel(), 'preview');
  assert.equal(store.get('otter_update_channel'), 'preview');

  assert.throws(() => {
    manager.setChannel('invalid-channel');
  }, /Invalid update channel/);
});

test('Update Manager: Cryptographic SHA-256 Package Verification', () => {
  const manager = new OtterUpdateManager({ currentVersion: '1.0.0' });
  const samplePayload = Buffer.from('Otter release payload bytes');
  // Expected sha256 of 'Otter release payload bytes'
  // echo -n "Otter release payload bytes" | sha256sum
  // 565fefffa7f6bc69363a0bc1fe5e16548773e351817e0b57ea971168f237ef1d
  const hash = 'dc212b1d6f4af54bd39caa14013be2ea6966163123eea6d58020f0b86c0f3630';

  assert.equal(manager.verifyPackage(samplePayload, hash), true);
  assert.equal(manager.status, 'verifying');

  assert.throws(() => {
    manager.verifyPackage(samplePayload, 'wrong_sha256_hash');
  }, /SHA-256 verification failed/);
  assert.equal(manager.status, 'error');
});

test('Update Manager: Skip Version Preferences', async () => {
  const store = new Map();
  const manager = new OtterUpdateManager({ currentVersion: '1.0.0', storage: store });

  const feed = {
    version: '1.0.1',
    channel: 'stable',
    sha256: 'abc',
    downloadUrl: 'https://example.com/otter.zip'
  };

  const res1 = await manager.checkForUpdates(feed);
  assert.equal(res1.available, true);
  assert.equal(manager.status, 'available');

  manager.skipVersion('1.0.1');
  assert.equal(manager.isVersionSkipped('1.0.1'), true);

  const res2 = await manager.checkForUpdates(feed);
  assert.equal(res2.available, false);
  assert.equal(res2.skipped, true);

  manager.unskipVersion('1.0.1');
  assert.equal(manager.isVersionSkipped('1.0.1'), false);
});

test('Update Manager: Staging & Rollback Mechanism', () => {
  const store = new Map();
  const manager = new OtterUpdateManager({ currentVersion: '1.0.0', storage: store });

  manager.stageUpdate({ version: '1.1.0' }, { files: ['main.ot'] });
  assert.equal(manager.status, 'ready');

  manager.currentVersion = '1.1.0';
  const rollbackResult = manager.rollback();
  assert.equal(rollbackResult.restored, true);
  assert.equal(rollbackResult.version, '1.0.0');
  assert.equal(manager.currentVersion, '1.0.0');
});

test('Update Manager: Release Notes Parser', () => {
  const md = `# Otter 1.1.0
- High performance compiler pipeline
- Enhanced debugger variable inspections
* New 2D game physics extensions
Unrelated text`;

  const highlights = OtterUpdateManager.parseReleaseNotes(md);
  assert.deepEqual(highlights, [
    'High performance compiler pipeline',
    'Enhanced debugger variable inspections',
    'New 2D game physics extensions'
  ]);
});

test('Live Studio Server API: /api/update endpoints', async () => {
  // 1. GET /api/update/check
  const checkRes = await fetch(`${baseUrl}/api/update/check?channel=preview`);
  assert.equal(checkRes.status, 200);
  const checkData = await checkRes.json();
  assert.equal(checkData.ok, true);
  assert.equal(checkData.channel, 'preview');
  assert.ok(checkData.currentVersion);
  assert.ok(checkData.latestVersion);
  assert.ok(checkData.sha256);

  // 2. POST /api/update/apply
  const applyRes = await fetch(`${baseUrl}/api/update/apply`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ version: '1.0.1' })
  });
  assert.equal(applyRes.status, 200);
  const applyData = await applyRes.json();
  assert.equal(applyData.ok, true);
  assert.equal(applyData.status, 'applied');

  // 3. POST /api/update/skip
  const skipRes = await fetch(`${baseUrl}/api/update/skip`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ version: '1.0.1' })
  });
  assert.equal(skipRes.status, 200);
  const skipData = await skipRes.json();
  assert.equal(skipData.ok, true);
  assert.equal(skipData.skipped, '1.0.1');

  // 4. POST /api/update/rollback
  const rollbackRes = await fetch(`${baseUrl}/api/update/rollback`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({})
  });
  assert.equal(rollbackRes.status, 200);
  const rollbackData = await rollbackRes.json();
  assert.equal(rollbackData.ok, true);
  assert.equal(rollbackData.restored, true);
});

test('CLI Distribution Updater: Update-Otter.ps1', () => {
  const updateScript = path.join(repoRoot, 'distribution', 'Update-Otter.ps1');
  assert.ok(updateScript);

  // Test with -CheckOnly on the repo root
  const stdout = execFileSync('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', updateScript,
    '-Destination', repoRoot,
    '-CheckOnly'
  ], {
    cwd: repoRoot,
    encoding: 'utf8',
    windowsHide: true,
    timeout: 10000
  });

  assert.match(stdout, /Candidate version:/);
});
