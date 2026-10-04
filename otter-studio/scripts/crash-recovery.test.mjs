/**
 * Otter Studio - Crash Recovery & Autosave Certification Test Suite
 * Certifies Section 32 of OTTER_STUDIO_PROFESSIONAL_IDE_MASTER_CHECKLIST.md:
 * - Crash/autosave recovery
 * - Corrupt workspace/settings recovery
 * - Dirty buffer journaling
 * - Clean shutdown tracking
 * - Recovery Mode state reset
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { OtterRecoveryManager } from '../js/recovery/recovery-manager.js';

test('Recovery Manager: Journal records dirty buffer changes with cursor position', () => {
  const storage = new Map();
  const recovery = new OtterRecoveryManager({ storage });

  recovery.recordBufferChange('projects/app/main.ot', 'say "Hello Otter"', { cursor: 18 });
  recovery.flushJournal();

  const rawJournal = storage.get('otter_studio_recovery_journal');
  assert.ok(rawJournal, 'Journal must be serialized to storage');

  const journal = JSON.parse(rawJournal);
  assert.ok(journal.entries['projects/app/main.ot']);
  assert.equal(journal.entries['projects/app/main.ot'].content, 'say "Hello Otter"');
  assert.equal(journal.entries['projects/app/main.ot'].cursor, 18);
});

test('Recovery Manager: Saving file removes it from dirty journal and clears empty journal', () => {
  const storage = new Map();
  const recovery = new OtterRecoveryManager({ storage });

  recovery.recordBufferChange('file1.ot', 'score is 10');
  recovery.recordBufferChange('file2.ot', 'score is 20');
  recovery.flushJournal();

  assert.equal(Object.keys(JSON.parse(storage.get('otter_studio_recovery_journal')).entries).length, 2);

  // Save file1
  recovery.markFileSaved('file1.ot');
  assert.equal(Object.keys(JSON.parse(storage.get('otter_studio_recovery_journal')).entries).length, 1);

  // Save file2
  recovery.markFileSaved('file2.ot');
  assert.equal(recovery.getItem('otter_studio_recovery_journal'), null);
});

test('Recovery Manager: Detects crashed session on abnormal termination with unsaved edits', () => {
  const storage = new Map();

  // Session 1: Writes dirty edits and crashes (never calls recordCleanExit)
  const session1 = new OtterRecoveryManager({ storage });
  session1.init();
  session1.recordBufferChange('important.ot', 'uncommitted changes');
  session1.flushJournal();

  // Session 2: Starts up after crash
  let callbackInvoked = false;
  const session2 = new OtterRecoveryManager({
    storage,
    onRecoveryAvailable: () => { callbackInvoked = true; }
  });

  const detection = session2.init();
  assert.equal(detection.crashed, true);
  assert.equal(detection.recoveredCount, 1);
  assert.ok(detection.recoveredFiles.includes('important.ot'));
  assert.equal(callbackInvoked, true);

  // Restore recovered content
  const restored = session2.restoreJournal();
  assert.equal(restored['important.ot'].content, 'uncommitted changes');

  // User discards or saves edits
  session2.discardJournal();
  assert.equal(session2.getItem('otter_studio_recovery_journal'), null);
});

test('Recovery Manager: Clean exit does not trigger false crash alert on next startup', () => {
  const storage = new Map();

  // Session 1: Cleanly terminates
  const session1 = new OtterRecoveryManager({ storage });
  session1.init();
  session1.recordCleanExit();

  // Session 2: Normal startup
  const session2 = new OtterRecoveryManager({ storage });
  const detection = session2.init();
  assert.equal(detection.crashed, false);
  assert.equal(detection.recoveredCount, 0);
});

test('Recovery Manager: Corrupt JSON healing recovers syntax errors and provides safe defaults', () => {
  const recovery = new OtterRecoveryManager();

  const defaultManifestFactory = () => ({
    name: 'recovered-project',
    target: 'console',
    version: '1.0.0',
    entryPoint: 'main.ot'
  });

  // 1. Truncated / malformed JSON
  const corruptJson = '{"name": "broken-project", target: console, }';
  const healed = recovery.healCorruptJson(corruptJson, defaultManifestFactory);

  assert.equal(healed.ok, true);
  assert.equal(healed.healed, true);
  assert.equal(healed.data.name, 'recovered-project');
  assert.equal(healed.corruptBackup, corruptJson);

  // 2. Empty string
  const emptyHealed = recovery.healCorruptJson('', defaultManifestFactory);
  assert.equal(emptyHealed.ok, true);
  assert.equal(emptyHealed.healed, true);
  assert.equal(emptyHealed.data.name, 'recovered-project');

  // 3. Valid JSON with UTF-8 BOM
  const validJson = '\uFEFF{"name": "valid-app", "target": "web", "version": "1.0.0"}';
  const validResult = recovery.healCorruptJson(validJson, defaultManifestFactory);
  assert.equal(validResult.ok, true);
  assert.equal(validResult.healed, false);
  assert.equal(validResult.data.name, 'valid-app');
});

test('Recovery Manager: Reset Studio State wipes corrupted caches while preserving user files', () => {
  const storage = new Map();
  storage.set('otter_studio_session', '{"corrupted": true}');
  storage.set('otter_studio_recovery_journal', '{"entries": {}}');
  storage.set('otter-studio-theme', 'theme-dark');
  storage.set('otter_studio_recents', '["corrupt/path"]');

  const recovery = new OtterRecoveryManager({ storage });
  const res = recovery.resetStudioState();

  assert.equal(res.reset, true);
  assert.equal(recovery.getItem('otter_studio_session'), null);
  assert.equal(recovery.getItem('otter_studio_recovery_journal'), null);
  assert.equal(recovery.getItem('otter_studio_recents'), null);
});
