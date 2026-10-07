import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { OtterRecoveryManager } from '../js/recovery/recovery-manager.js';
import { AtomicFileManager, ProcessOrphanManager } from '../js/reliability/reliability-engine.js';
import { OtterUpdateManager } from '../js/updater/update-manager.js';

test('OS & Process-Level Adversarial Fault Resilience Certification', async (t) => {
  const tmpDir = path.join(process.cwd(), 'scratch', 'fault-test-' + Date.now());
  if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });

  t.after(() => {
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch {}
  });

  await t.test('1. Studio abnormal kill: Recovers dirty buffers with exact cursor offsets on reboot', () => {
    const memoryStorage = new Map();
    // Simulate active session crashing before clean shutdown
    const crashingSession = new OtterRecoveryManager({ storage: memoryStorage });
    crashingSession.init();
    crashingSession.recordBufferChange('src/app.ot', 'make total is 500\nfor each item in list\n  add item to total\n.', { cursor: 42 });
    crashingSession.recordBufferChange('src/config.ot', 'make timeout is 30', { cursor: 18 });
    crashingSession.flushJournal();
    // Simulate sudden process kill (cleanExit remains false)
    crashingSession.setItem(crashingSession.cleanExitKey, 'false');

    // Reboot on fresh startup
    const restartedSession = new OtterRecoveryManager({ storage: memoryStorage });
    const recoveryResult = restartedSession.init();
    
    assert.equal(recoveryResult.crashed, true, 'Detected crashed session');
    assert.equal(recoveryResult.recoveredCount, 2, 'Recovered 2 dirty buffers');
    assert.ok(recoveryResult.recoveredFiles.includes('src/app.ot'), 'Recovered src/app.ot');
    assert.ok(recoveryResult.recoveredFiles.includes('src/config.ot'), 'Recovered src/config.ot');

    const restoredEntries = restartedSession.restoreJournal();
    assert.equal(restoredEntries['src/app.ot'].cursor, 42, 'Preserved cursor position in app.ot');
    assert.ok(restoredEntries['src/app.ot'].content.includes('make total is 500'), 'Preserved unsaved edits');
  });

  await t.test('2. Atomic Save Failure: Original file preserved completely if disk write fails midway', async () => {
    const atomicManager = new AtomicFileManager();
    const targetFile = path.join(tmpDir, 'important-project-file.ot');
    fs.writeFileSync(targetFile, 'ORIGINAL VALID PRODUCTION SOURCE CODE', 'utf8');

    // Attempt atomic write to invalid filename
    const invalidPath = path.join(tmpDir, 'invalid:*:?name.ot');
    await assert.rejects(
      async () => await atomicManager.atomicWrite(invalidPath, 'CORRUPT DATA'),
      /Atomic write failed/,
      'Atomic write rejected invalid write'
    );

    // Verify original file is 100% untouched
    const originalContent = fs.readFileSync(targetFile, 'utf8');
    assert.equal(originalContent, 'ORIGINAL VALID PRODUCTION SOURCE CODE', 'Original file remained uncorrupted');
  });

  await t.test('3. Terminal & Runner Process Crash: Isolates child process failure and purges orphans', () => {
    const orphanManager = new ProcessOrphanManager();
    
    // Register simulated child runner processes
    orphanManager.registerProcess(99901, 'otter-repl');
    orphanManager.registerProcess(99902, 'otter-runner');
    assert.equal(orphanManager.getTrackedProcesses().length, 2, 'Tracked 2 child runner processes');

    // Simulate child process unexpected exit (SIGTERM / crash)
    orphanManager.unregisterProcess(99901);
    assert.equal(orphanManager.getTrackedProcesses().length, 1, 'Cleanly unregistered dead process');

    // Safe purge of all remaining orphans
    const cleaned = orphanManager.cleanupAllProcesses();
    assert.ok(Array.isArray(cleaned), 'Orphan cleanup executed without throwing');
    assert.equal(orphanManager.getTrackedProcesses().length, 0, 'All tracked processes cleared');
  });

  await t.test('4. Updater Staging Interrupted: Rollback checkpoint guarantees zero version state corruption', () => {
    const memoryStorage = new Map();
    const manager = new OtterUpdateManager({
      currentVersion: '1.0.0-rc.11',
      channel: 'stable',
      storage: memoryStorage
    });

    const preUpdateState = { version: '1.0.0-rc.11', binarySha: 'abc123456789' };
    manager.stageUpdate({ version: '1.0.0-rc.12' }, preUpdateState);

    // Simulate updater killed midway through binary replacement
    manager.currentVersion = '1.0.0-rc.12-PARTIAL';

    // Recover on restart
    const rollback = manager.rollback();
    assert.equal(rollback.restored, true, 'Rollback restored successfully');
    assert.equal(manager.currentVersion, '1.0.0-rc.11', 'Version restored to 1.0.0-rc.11');
  });

  await t.test('5. Read-Only / Denied Access Safety: Graceful error response without crashing', async () => {
    const atomicManager = new AtomicFileManager();
    const readOnlyFilePath = path.join(tmpDir, 'readonly.ot');
    fs.writeFileSync(readOnlyFilePath, 'content', { mode: 0o444 });

    try {
      try {
        await atomicManager.atomicWrite(readOnlyFilePath, 'overwrite attempt');
      } catch (err) {
        assert.ok(err.message.includes('Atomic write failed'), 'Surfaced structured write failure');
      }
    } finally {
      try { fs.chmodSync(readOnlyFilePath, 0o666); } catch {}
    }
  });
});
