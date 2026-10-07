import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import crypto from 'node:crypto';
import { OtterUpdateManager } from '../js/updater/update-manager.js';

test('Hosted Updater Feeds & Live HTTP Channel Certification', async (t) => {
  // Generate cryptographic keys
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', {
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

  // Real Stable and Preview payloads
  const stablePayload = Buffer.from('Otter Studio v1.0.0-rc.12 Stable Binary Release');
  const stableSha = crypto.createHash('sha256').update(stablePayload).digest('hex');
  const stableSig = signPayload(stablePayload, privateKey);

  const previewPayload = Buffer.from('Otter Studio v1.1.0-preview.1 Preview Binary Release');
  const previewSha = crypto.createHash('sha256').update(previewPayload).digest('hex');
  const previewSig = signPayload(previewPayload, privateKey);

  const stableManifest = {
    channel: 'stable',
    version: '1.0.0-rc.12',
    releaseDate: '2026-10-07',
    artifactUrl: '', // filled below with real port
    sha256: stableSha,
    signature: stableSig,
    minCompatibleVersion: '1.0.0-rc.1'
  };

  const previewManifest = {
    channel: 'preview',
    version: '1.1.0-preview.1',
    releaseDate: '2026-10-07',
    artifactUrl: '', // filled below
    sha256: previewSha,
    signature: previewSig,
    minCompatibleVersion: '1.0.0-rc.1'
  };

  let server;
  let serverPort;

  await new Promise((resolve) => {
    server = http.createServer((req, res) => {
      const url = new URL(req.url, `http://127.0.0.1:${serverPort}`);
      
      if (url.pathname === '/updates/stable/manifest.json') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ...stableManifest, artifactUrl: `http://127.0.0.1:${serverPort}/updates/stable/artifact.zip` }));
      } else if (url.pathname === '/updates/preview/manifest.json') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ...previewManifest, artifactUrl: `http://127.0.0.1:${serverPort}/updates/preview/artifact.zip` }));
      } else if (url.pathname === '/updates/stable/artifact.zip') {
        res.writeHead(200, { 'Content-Type': 'application/zip' });
        res.end(stablePayload);
      } else if (url.pathname === '/updates/preview/artifact.zip') {
        res.writeHead(200, { 'Content-Type': 'application/zip' });
        res.end(previewPayload);
      } else {
        res.writeHead(404);
        res.end('Not found');
      }
    });

    server.listen(0, '127.0.0.1', () => {
      serverPort = server.address().port;
      resolve();
    });
  });

  t.after(() => {
    if (server) server.close();
  });

  await t.test('1. Stable Studio queries real hosted Stable feed over HTTP and stages update', async () => {
    const memoryStorage = new Map();
    const manager = new OtterUpdateManager({
      currentVersion: '1.0.0-rc.11',
      channel: 'stable',
      feedUrl: `http://127.0.0.1:${serverPort}/updates/stable/manifest.json`,
      trustedPublicKey: publicKey,
      storage: memoryStorage
    });

    const checkResult = await manager.checkForUpdates();
    assert.equal(checkResult.available, true, 'Discovered newer stable update');
    assert.equal(checkResult.isSimulated, false, 'Fetched from real hosted HTTP feed');
    assert.equal(checkResult.update.version, '1.0.0-rc.12', 'Discovered version 1.0.0-rc.12');

    // Download actual artifact
    const res = await fetch(checkResult.update.artifactUrl);
    assert.equal(res.status, 200, 'Downloaded artifact over HTTP');
    const artifactBuffer = Buffer.from(await res.arrayBuffer());

    // Verify cryptographic signature and checksum
    const verifyOk = manager.verifyArtifact(artifactBuffer, checkResult.update.sha256, checkResult.update.signature);
    assert.equal(verifyOk, true, 'Cryptographically verified downloaded binary');

    // Stage
    const stageRes = manager.stageUpdate(checkResult.update);
    assert.equal(stageRes.staged, true, 'Staged update successfully');
  });

  await t.test('2. Channel Isolation over Hosted Feed: Stable client querying Preview feed rejects mismatch', async () => {
    const memoryStorage = new Map();
    const manager = new OtterUpdateManager({
      currentVersion: '1.0.0-rc.11',
      channel: 'stable',
      feedUrl: `http://127.0.0.1:${serverPort}/updates/preview/manifest.json`,
      trustedPublicKey: publicKey,
      storage: memoryStorage
    });

    // Fetch manifest from preview feed
    const res = await fetch(manager.feedUrl);
    const previewFeedManifest = await res.json();

    // Passing a preview manifest to a stable manager must fail
    await assert.rejects(
      async () => await manager.processManifest(previewFeedManifest),
      /Manifest channel 'preview' does not match configured channel 'stable'/,
      'Channel cross-contamination prevented'
    );
  });
});
