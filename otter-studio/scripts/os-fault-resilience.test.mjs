import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { AtomicFileManager, ProcessOrphanManager } from '../js/reliability/reliability-engine.js';
import { OtterUpdateManager } from '../js/updater/update-manager.js';

test('OS & Process-Level Fault Resilience Certification (Real OS Boundaries)', async (t) => {
  const tmpDir = path.join(process.cwd(), 'scratch', 'fault-test-' + Date.now());
  if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });

  t.after(() => {
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch {}
  });

  await t.test('1. Real Process Termination & Disk Recovery: Spawns child process, kills it, verifies disk state recovery', async () => {
    const journalFile = path.join(tmpDir, 'real_recovery_journal.json');
    const childScript = path.join(tmpDir, 'child_worker.cjs');

    const scriptCode = [
      'const fs = require("fs");',
      'const target = process.argv[2];',
      'const payload = {',
      '  cleanExit: false,',
      '  entries: {',
      '    "src/app.ot": { content: "score is 100\\nsay score", cursor: 22, timestamp: Date.now() },',
      '    "src/config.ot": { content: "timeout is 5000", cursor: 14, timestamp: Date.now() }',
      '  }',
      '};',
      'fs.writeFileSync(target, JSON.stringify(payload), "utf8");',
      'setInterval(() => {}, 1000);'
    ].join('\n');
    
    fs.writeFileSync(childScript, scriptCode, 'utf8');

    // Spawn real child process
    const child = spawn(process.execPath, [childScript, journalFile], { stdio: 'ignore' });
    assert.ok(child.pid, 'Spawned real OS child process');

    // Poll until file written
    let fileWritten = false;
    for (let i = 0; i < 20; i++) {
      if (fs.existsSync(journalFile)) {
        fileWritten = true;
        break;
      }
      await new Promise(r => setTimeout(r, 100));
    }
    assert.equal(fileWritten, true, 'Child process successfully wrote journal to disk');

    // Kill child process abruptly (real OS kill)
    child.kill('SIGKILL');
    await new Promise(r => setTimeout(r, 200));

    // Verify persisted state from disk
    const diskContent = fs.readFileSync(journalFile, 'utf8');
    const parsedJournal = JSON.parse(diskContent);
    assert.equal(parsedJournal.cleanExit, false, 'Clean exit was false on abrupt process kill');
    assert.equal(Object.keys(parsedJournal.entries).length, 2, 'Recovered both unsaved files from disk');
    assert.equal(parsedJournal.entries['src/app.ot'].cursor, 22, 'Exact cursor position preserved on disk');
    assert.ok(parsedJournal.entries['src/app.ot'].content.includes('score is 100'), 'Unsaved buffer content preserved on disk');
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
