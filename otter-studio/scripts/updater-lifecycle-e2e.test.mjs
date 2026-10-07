import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { OtterUpdateManager } from '../js/updater/update-manager.js';
import { UpdateManifestValidator } from '../js/updater/update-manifest.js';

test('Updater Lifecycle & Cryptographic Staging End-to-End Certification', async (t) => {
  // Generate an isolated RSA keypair for cryptographic release signing tests
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' }
  });

  // Generate a separate untrusted/rogue keypair
  const rogueKeys = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' }
  });

  function signPayload(data, key) {
    const signer = crypto.createSign('SHA256');
    signer.update(data);
    signer.end();
    return signer.sign(key, 'hex');
  }

  await t.test('1. Successful A -> B Signed Update Flow with SHA-256 & Signature Verification', async () => {
    const memoryStorage = new Map();
    const manager = new OtterUpdateManager({
      currentVersion: '1.0.0-rc.11',
      channel: 'stable',
      trustedPublicKey: publicKey,
      storage: memoryStorage
    });

    // Create real binary artifact for Version B (1.0.0-rc.12)
    const packageContent = Buffer.from('Otter Studio v1.0.0-rc.12 Production Binary Payload Content');
    const sha256 = crypto.createHash('sha256').update(packageContent).digest('hex');
    const signature = signPayload(packageContent, privateKey);

    const manifestB = {
      channel: 'stable',
      version: '1.0.0-rc.12',
      releaseDate: '2026-10-07',
      artifactUrl: 'https://updates.otter-lang.org/studio/stable/otter-studio-1.0.0-rc.12.zip',
      sha256: sha256,
      signature: signature,
      minCompatibleVersion: '1.0.0-rc.1'
    };

    // Step 1: Process Manifest
    const manifestResult = await manager.processManifest(manifestB);
    assert.equal(manifestResult.available, true, 'Update is detected as available');
    assert.equal(manifestResult.requiresFullInstaller, false, 'Standard in-place update applicable');

    // Step 2: Verify Artifact
    const verifyOk = manager.verifyArtifact(packageContent, sha256, signature);
    assert.equal(verifyOk, true, 'Artifact verified with SHA-256 and pinned RSA key');

    // Step 3: Stage Update with pre-update snapshot
    const stageResult = manager.stageUpdate(manifestB, { activeFiles: ['main.ot'], userSettings: { theme: 'dark' } });
    assert.equal(stageResult.staged, true, 'Update staged successfully');
    assert.equal(manager.status, 'ready', 'Manager status transitioned to ready');
  });

  await t.test('2. Tampered Manifest / Rogue Key: Rejected when signed by unauthorized key', async () => {
    const memoryStorage = new Map();
    const manager = new OtterUpdateManager({
      currentVersion: '1.0.0-rc.11',
      channel: 'stable',
      trustedPublicKey: publicKey, // Pinned official key
      storage: memoryStorage
    });

    const packageContent = Buffer.from('Otter Studio v1.0.0-rc.12 Payload');
    const sha256 = crypto.createHash('sha256').update(packageContent).digest('hex');
    // Sign with ROGUE private key
    const rogueSignature = signPayload(packageContent, rogueKeys.privateKey);

    assert.throws(
      () => manager.verifyArtifact(packageContent, sha256, rogueSignature),
      /Cryptographic signature verification failed/,
      'Update rejected due to unauthorized signing key'
    );
  });

  await t.test('3. Tampered Package / Byte Corruption: Rejected when SHA-256 does not match', async () => {
    const memoryStorage = new Map();
    const manager = new OtterUpdateManager({
      currentVersion: '1.0.0-rc.11',
      channel: 'stable',
      trustedPublicKey: publicKey,
      storage: memoryStorage
    });

    const validContent = Buffer.from('Original Otter Studio Binary');
    const expectedSha256 = crypto.createHash('sha256').update(validContent).digest('hex');

    // Tampered content (1 byte modified)
    const tamperedContent = Buffer.from('Modified Otter Studio Binary');

    assert.throws(
      () => manager.verifyArtifact(tamperedContent, expectedSha256),
      /SHA-256 checksum mismatch/,
      'Update rejected due to checksum mismatch'
    );
  });

  await t.test('4. Channel Isolation: Stable cannot consume Preview manifest without explicit user switch', async () => {
    const memoryStorage = new Map();
    const manager = new OtterUpdateManager({
      currentVersion: '1.0.0-rc.11',
      channel: 'stable',
      storage: memoryStorage
    });

    const previewManifest = {
      channel: 'preview',
      version: '1.1.0-preview.1',
      releaseDate: '2026-10-07',
      artifactUrl: 'https://updates.otter-lang.org/studio/preview/update.zip',
      sha256: 'a'.repeat(64)
    };

    await assert.rejects(
      async () => await manager.processManifest(previewManifest),
      /Manifest channel 'preview' does not match configured channel 'stable'/,
      'Channel cross-contamination was strictly blocked'
    );

    // Explicit channel switch allows consumption
    manager.setChannel('preview');
    assert.equal(manager.getChannel(), 'preview', 'Channel switched to preview');
    const result = await manager.processManifest(previewManifest);
    assert.equal(result.available, true, 'Preview manifest accepted after explicit channel switch');
  });

  await t.test('5. Anti-Downgrade Protection: Refuses to apply older versions', async () => {
    const memoryStorage = new Map();
    const manager = new OtterUpdateManager({
      currentVersion: '1.0.0-rc.11',
      channel: 'stable',
      storage: memoryStorage
    });

    const olderManifest = {
      channel: 'stable',
      version: '1.0.0-rc.10',
      releaseDate: '2026-10-01',
      artifactUrl: 'https://updates.otter-lang.org/studio/stable/old.zip',
      sha256: 'b'.repeat(64)
    };

    await assert.rejects(
      async () => await manager.processManifest(olderManifest),
      /Refusing version downgrade from 1.0.0-rc.11 to 1.0.0-rc.10/,
      'Downgrade rejected'
    );
  });

  await t.test('6. Rollback Recovery: Restores pre-update state if installation encounters failure', () => {
    const memoryStorage = new Map();
    const manager = new OtterUpdateManager({
      currentVersion: '1.0.0-rc.11',
      channel: 'stable',
      storage: memoryStorage
    });

    const preUpdateSnapshot = { version: '1.0.0-rc.11', filesHash: 'abc12345' };
    manager.stageUpdate({ version: '1.0.0-rc.12' }, preUpdateSnapshot);

    // Simulate update in progress
    manager.currentVersion = '1.0.0-rc.12-corrupted';

    // Trigger rollback
    const rollbackResult = manager.rollback();
    assert.equal(rollbackResult.restored, true, 'Rollback performed');
    assert.equal(manager.currentVersion, '1.0.0-rc.11', 'Restored to original version 1.0.0-rc.11');
  });
});
