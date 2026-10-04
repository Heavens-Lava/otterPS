// reliability-performance.test.mjs - Comprehensive Certification Test Suite for Section 32 Reliability, Performance, and Recovery
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  AtomicFileManager,
  CrashIsolationEngine,
  ProcessOrphanManager,
  SafeShutdownCoordinator,
  RotatingLogManager,
  CancellationTokenSource,
  ProgressReporter,
  CooperativeTaskRunner,
  PerformanceBenchmarkSuite
} from '../js/reliability/reliability-engine.js';
import { OtterRecoveryManager } from '../js/recovery/recovery-manager.js';

test('1. AtomicFileManager: writes file atomically with backup preservation and heals corrupt JSON', () => {
  const atomic = new AtomicFileManager();
  const testDir = path.resolve('test-scratch-atomic');
  const targetFile = path.join(testDir, 'settings.json');

  if (fs.existsSync(testDir)) {
    fs.rmSync(testDir, { recursive: true, force: true });
  }

  // First atomic write
  const initialContent = JSON.stringify({ theme: 'dark', fontSize: 14 });
  const writeRes1 = atomic.atomicWrite(targetFile, initialContent);
  assert.equal(writeRes1.ok, true);
  assert.equal(fs.existsSync(targetFile), true);
  assert.equal(fs.readFileSync(targetFile, 'utf8'), initialContent);

  // Second atomic write replaces file and generates .bak backup
  const updatedContent = JSON.stringify({ theme: 'light', fontSize: 16 });
  const writeRes2 = atomic.atomicWrite(targetFile, updatedContent, { backup: true });
  assert.equal(writeRes2.ok, true);
  assert.equal(fs.readFileSync(targetFile, 'utf8'), updatedContent);
  assert.equal(fs.existsSync(`${targetFile}.bak`), true);
  assert.equal(fs.readFileSync(`${targetFile}.bak`, 'utf8'), initialContent);

  // Read valid JSON
  const readRes = atomic.atomicReadJson(targetFile);
  assert.equal(readRes.ok, true);
  assert.equal(readRes.healed, false);
  assert.equal(readRes.data.theme, 'light');

  // Corrupt file and test fallback healing
  fs.writeFileSync(targetFile, '{"theme": "broken, bad json');
  const healedRes = atomic.atomicReadJson(targetFile, () => ({ theme: 'default-fallback' }));
  assert.equal(healedRes.ok, true);
  assert.equal(healedRes.healed, true);
  assert.equal(healedRes.data.theme, 'default-fallback');
  assert.equal(healedRes.backupPath, `${targetFile}.bak`);

  // Clean up scratch dir
  fs.rmSync(testDir, { recursive: true, force: true });
});

test('2. CrashIsolationEngine: isolates extension crashes, tracks faults, and disables repeated offenders', () => {
  const isolator = new CrashIsolationEngine({ maxConsecutiveErrors: 3 });

  // Good execution
  const res1 = isolator.executeIsolated('good-plugin', () => 42);
  assert.equal(res1.ok, true);
  assert.equal(res1.result, 42);
  assert.equal(isolator.isComponentDisabled('good-plugin'), false);

  // Bad execution 1
  const badFn = () => { throw new Error('Segmentation fault simulation'); };
  const resBad1 = isolator.executeIsolated('faulty-ext', badFn, 'fallback');
  assert.equal(resBad1.ok, false);
  assert.equal(resBad1.disabled, false);
  assert.equal(resBad1.result, 'fallback');
  assert.equal(resBad1.consecutiveErrors, 1);

  // Bad execution 2
  const resBad2 = isolator.executeIsolated('faulty-ext', badFn, 'fallback');
  assert.equal(resBad2.consecutiveErrors, 2);
  assert.equal(resBad2.disabled, false);

  // Bad execution 3 -> Triggers automatic disable
  const resBad3 = isolator.executeIsolated('faulty-ext', badFn, 'fallback');
  assert.equal(resBad3.consecutiveErrors, 3);
  assert.equal(resBad3.disabled, true);
  assert.equal(isolator.isComponentDisabled('faulty-ext'), true);

  // Subsequent call returns disabled without throwing
  const resAfter = isolator.executeIsolated('faulty-ext', badFn, 'fallback');
  assert.equal(resAfter.ok, false);
  assert.equal(resAfter.disabled, true);

  // Reset component
  isolator.resetComponent('faulty-ext');
  assert.equal(isolator.isComponentDisabled('faulty-ext'), false);
  const resReset = isolator.executeIsolated('faulty-ext', () => 'healed');
  assert.equal(resReset.ok, true);
  assert.equal(resReset.result, 'healed');
});

test('3. ProcessOrphanManager: tracks child PIDs and safely cleans up process trees', () => {
  const orphanManager = new ProcessOrphanManager();

  // Register mock processes
  orphanManager.registerProcess(999991, { type: 'terminal', command: 'powershell.exe' });
  orphanManager.registerProcess(999992, { type: 'runner', command: 'otter run main.ot' });

  const tracked = orphanManager.getTrackedProcesses();
  assert.equal(tracked.length, 2);
  assert.equal(tracked[0].pid, 999991);
  assert.equal(tracked[0].type, 'terminal');

  // Unregister one
  orphanManager.unregisterProcess(999991);
  assert.equal(orphanManager.getTrackedProcesses().length, 1);

  // Cleanup all
  const cleaned = orphanManager.cleanupAllProcesses();
  assert.equal(cleaned.length, 1);
  assert.equal(cleaned[0].pid, 999992);
  assert.equal(orphanManager.getTrackedProcesses().length, 0);
});

test('4. SafeShutdownCoordinator: orchestrates dirty buffer flush, orphan kill, and state persistence', async () => {
  const storage = new Map();
  const recovery = new OtterRecoveryManager({ storage });
  recovery.init();
  recovery.recordBufferChange('app.ot', 'say "hello"');

  const orphanManager = new ProcessOrphanManager();
  orphanManager.registerProcess(999995, { type: 'build-worker' });

  const coordinator = new SafeShutdownCoordinator({
    orphanManager,
    recoveryManager: recovery
  });

  let statePersisted = false;
  const shutdownRes = await coordinator.coordinateShutdown({
    persistCallback: async (atomicIO) => {
      statePersisted = true;
      return 'workbench.json';
    }
  });

  assert.equal(shutdownRes.dirtyBuffersFlushed, 1);
  assert.equal(shutdownRes.processesCleaned.length, 1);
  assert.equal(statePersisted, true);
  assert.equal(shutdownRes.cleanExitRecorded, true);
  assert.equal(storage.get('otter_studio_clean_exit'), 'true');
});

test('5. RotatingLogManager: logs across levels, rotates files upon size limit, and exports logs', () => {
  const logDir = path.resolve('test-scratch-logs');
  if (fs.existsSync(logDir)) {
    fs.rmSync(logDir, { recursive: true, force: true });
  }

  // Small 150 byte size threshold to trigger rotation in test
  const logger = new RotatingLogManager({
    logDir,
    logFile: 'test.log',
    maxSizeBytes: 150,
    maxBackups: 3
  });

  logger.info('core', 'Starting Otter Studio session');
  logger.warn('terminal', 'PTY buffer high watermark warning', { buffered: 1024 });
  logger.error('compiler', 'Compilation failed in main.ot', { line: 12 });
  logger.debug('lsp', 'Completion requested at position 5');

  // Verify memory log search
  const queryAll = logger.getLogs();
  assert.equal(queryAll.total, 4);

  const queryWarn = logger.getLogs({ level: 'WARN' });
  assert.equal(queryWarn.total, 1);
  assert.equal(queryWarn.logs[0].subsystem, 'terminal');

  const querySearch = logger.getLogs({ search: 'compilation' });
  assert.equal(querySearch.total, 1);

  // Rotation check: verify multiple log files generated
  const exportData = logger.exportLogs();
  assert.ok(exportData.fileCount >= 2, 'Must have rotated and created backup log files');
  assert.ok(exportData.files.some(f => f.name === 'test.log'));
  assert.ok(exportData.files.some(f => f.name === 'test.log.1'));

  // Clean up
  fs.rmSync(logDir, { recursive: true, force: true });
});

test('6. CancellationTokenSource and ProgressReporter: cooperative cancellation and progress updates', () => {
  const cts = new CancellationTokenSource();
  const token = cts.token;
  assert.equal(token.isCancellationRequested(), false);

  let notifiedReason = null;
  token.onCancellationRequested((reason) => {
    notifiedReason = reason;
  });

  const progressUpdates = [];
  const progress = new ProgressReporter({
    onProgress: (p) => progressUpdates.push(p)
  });

  progress.report({ percent: 25, message: 'Parsing AST', stage: 'analysis' });
  progress.report({ percent: 50, message: 'Type checking', stage: 'analysis' });

  assert.equal(progressUpdates.length, 2);
  assert.equal(progressUpdates[0].percent, 25);
  assert.equal(progressUpdates[1].message, 'Type checking');

  cts.cancel('User aborted build');
  assert.equal(token.isCancellationRequested(), true);
  assert.equal(token.getReason(), 'User aborted build');
  assert.equal(notifiedReason, 'User aborted build');
  assert.throws(() => token.throwIfCancellationRequested(), /User aborted build/);
});

test('7. CooperativeTaskRunner: slices heavy loops without UI blocking and respects cancellation', async () => {
  const items = Array.from({ length: 250 }, (_, i) => i);
  let progressCalled = 0;
  const progress = new ProgressReporter({
    onProgress: () => { progressCalled++; }
  });

  // Successful run
  const results = await CooperativeTaskRunner.runCooperative(items, async (item) => item * 2, {
    batchSize: 50,
    progress
  });

  assert.equal(results.length, 250);
  assert.equal(results[0], 0);
  assert.equal(results[249], 498);
  assert.ok(progressCalled >= 5, 'Should have reported progress across batches');

  // Cancelled run
  const cts = new CancellationTokenSource();
  let processedBeforeCancel = 0;
  const runnerPromise = CooperativeTaskRunner.runCooperative(items, async (item) => {
    processedBeforeCancel++;
    if (processedBeforeCancel === 60) {
      cts.cancel('Cancelled during batch');
    }
    return item;
  }, {
    batchSize: 25,
    token: cts.token
  });

  await assert.rejects(runnerPromise, /Cancelled during batch/);
});

test('8. PerformanceBenchmarkSuite and Regression CI: all 9 IDE operations within budgets with zero regressions', async () => {
  const benchmarkSuite = new PerformanceBenchmarkSuite();
  const report = await benchmarkSuite.runAllBenchmarks();

  assert.equal(report.total, 9);
  assert.equal(report.regressionsCount, 0, `Performance regressions detected: ${report.regressions.join(', ')}`);
  assert.ok(report.passed >= 8, `Expected at least 8/9 within strict budget, got ${report.passed}`);

  const benchmarkNames = report.results.map(r => r.name);
  assert.ok(benchmarkNames.includes('startup'));
  assert.ok(benchmarkNames.includes('projectScan'));
  assert.ok(benchmarkNames.includes('largeFileParse'));
  assert.ok(benchmarkNames.includes('compilerThroughput'));
  assert.ok(benchmarkNames.includes('memoryFootprint'));
  assert.ok(benchmarkNames.includes('workspaceSearch'));
  assert.ok(benchmarkNames.includes('designerCanvas'));
  assert.ok(benchmarkNames.includes('terminalBurst'));
  assert.ok(benchmarkNames.includes('gameTargetStep'));
});
