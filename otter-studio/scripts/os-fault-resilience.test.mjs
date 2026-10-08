import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { AtomicFileManager, ProcessOrphanManager } from '../js/reliability/reliability-engine.js';
import { OtterUpdateManager } from '../js/updater/update-manager.js';

test('OS & Process-Level Fault Resilience Certification (Real OS Boundaries)', async (t) => {
  const tmpDir = path.join(process.cwd(), 'scratch', 'fault-test-' + Date.now());
  if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });

  t.after(() => {
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch {}
  });

  await t.test('1. Real Studio Process Termination & Fresh Process Recovery: Kills real Studio server with SIGKILL and recovers dirty edits on restart', async () => {
    const testPort = 39881;

    // Step 1: Start real Studio server process
    const firstServer = spawn('node', ['serve.mjs'], {
      cwd: path.resolve(process.cwd()),
      env: { ...process.env, OTTER_STUDIO_PORT: String(testPort) },
      stdio: ['pipe', 'pipe', 'pipe']
    });

    await waitForServer(testPort);

    try {
      // Step 2: In running Studio server, record dirty unsaved buffer edits into recovery journal
      const dirtyPayload = JSON.stringify({
        path: 'src/main.ot',
        content: 'score is 500\nbonus is 50\ntotal is score and bonus\nsay total\n',
        cursor: 34
      });

      const recordRes = await makePostRequest(`http://127.0.0.1:${testPort}/api/recovery/journal`, dirtyPayload);
      assert.equal(recordRes.ok, true, 'Dirty buffer change recorded in running Studio journal');
      assert.equal(recordRes.journal.cleanExit, false, 'Clean exit marked false while running');
    } finally {
      // Step 3: Forcibly kill Studio process with real OS SIGKILL (bypassing graceful exit handlers)
      firstServer.kill('SIGKILL');
      await new Promise(r => setTimeout(r, 500));
    }

    // Step 4: Launch a fresh second Studio server process on that same workspace
    const secondServer = spawn('node', ['serve.mjs'], {
      cwd: path.resolve(process.cwd()),
      env: { ...process.env, OTTER_STUDIO_PORT: String(testPort) },
      stdio: ['pipe', 'pipe', 'pipe']
    });

    await waitForServer(testPort);

    try {
      // Step 5: Fresh Studio process detects abnormal exit and surfaces recovered edits
      const statusRes = await makeGetRequest(`http://127.0.0.1:${testPort}/api/recovery/status`);
      assert.equal(statusRes.ok, true, 'Fresh Studio server answered recovery query');
      assert.equal(statusRes.crashed, true, 'Fresh Studio detected crashed previous session');
      assert.equal(statusRes.recoveredCount, 1, 'Detected 1 recovered unsaved file');
      
      const recoveredMain = statusRes.entries['src/main.ot'];
      assert.ok(recoveredMain, 'Recovered src/main.ot dirty buffer');
      assert.equal(recoveredMain.cursor, 34, 'Exact cursor position preserved across kill');
      assert.ok(recoveredMain.content.includes('score is 500'), 'Unsaved buffer content restored');

      // Step 6: Discard journal cleanly
      const discardRes = await makePostRequest(`http://127.0.0.1:${testPort}/api/recovery/discard`, '{}');
      assert.equal(discardRes.ok, true, 'Discarded journal cleanly');
    } finally {
      secondServer.kill('SIGTERM');
    }
  });

  await t.test('2. Atomic Save Failure: Original file preserved completely if write fails midway', async () => {
    const atomicManager = new AtomicFileManager();
    const targetFile = path.join(tmpDir, 'important-project-file.ot');
    fs.writeFileSync(targetFile, 'ORIGINAL VALID PRODUCTION SOURCE CODE', 'utf8');

    const invalidPath = path.join(tmpDir, 'invalid:*:?name.ot');
    await assert.rejects(
      async () => await atomicManager.atomicWrite(invalidPath, 'CORRUPT DATA'),
      /Atomic write failed/,
      'Atomic write rejected invalid write'
    );

    const originalContent = fs.readFileSync(targetFile, 'utf8');
    assert.equal(originalContent, 'ORIGINAL VALID PRODUCTION SOURCE CODE', 'Original file remained uncorrupted');
  });

  await t.test('3. Real Child Process Tracking & Cleanup: Spawns and kills real child processes', async () => {
    const orphanManager = new ProcessOrphanManager();
    
    // Spawn real dummy process
    const dummyChild = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' });
    orphanManager.registerProcess(dummyChild.pid, 'real-dummy-child');
    assert.equal(orphanManager.getTrackedProcesses().length, 1, 'Tracked real child PID');

    // Kill dummy child
    dummyChild.kill();
    orphanManager.unregisterProcess(dummyChild.pid);
    assert.equal(orphanManager.getTrackedProcesses().length, 0, 'Cleanly unregistered dead process');
  });

  await t.test('4. Updater Staging Interrupted: Rollback checkpoint restores original version', () => {
    const memoryStorage = new Map();
    const manager = new OtterUpdateManager({
      currentVersion: '1.0.0-rc.11',
      channel: 'stable',
      storage: memoryStorage
    });

    const preUpdateState = { version: '1.0.0-rc.11', binarySha: 'abc123456789' };
    manager.stageUpdate({ version: '1.0.0-rc.12' }, preUpdateState);
    manager.currentVersion = '1.0.0-rc.12-PARTIAL';

    const rollback = manager.rollback();
    assert.equal(rollback.restored, true, 'Rollback restored successfully');
    assert.equal(manager.currentVersion, '1.0.0-rc.11', 'Version restored to 1.0.0-rc.11');
  });
});

function waitForServer(port) {
  return new Promise((resolve, reject) => {
    const deadline = Date.now() + 8000;
    const check = () => {
      const req = http.get(`http://127.0.0.1:${port}/api/recovery/status`, (res) => {
        resolve();
      });
      req.on('error', () => {
        if (Date.now() > deadline) reject(new Error('Server start timed out on port ' + port));
        else setTimeout(check, 100);
      });
    };
    check();
  });
}

function makeGetRequest(urlStr) {
  return new Promise((resolve, reject) => {
    http.get(urlStr, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(body)); } catch (e) { resolve({ raw: body, status: res.statusCode }); }
      });
    }).on('error', reject);
  });
}

function makePostRequest(urlStr, data) {
  return new Promise((resolve, reject) => {
    const url = new URL(urlStr);
    const req = http.request({
      hostname: url.hostname,
      port: url.port,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data)
      }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(body)); } catch (e) { resolve({ raw: body, status: res.statusCode }); }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}
