// build-graph.test.mjs - Comprehensive Test Suite for Section 18: Build and Launch System
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  BuildGraph,
  DependencyTracker,
  IncrementalBuildManager,
  BUILD_CONFIGS,
  getBuildConfig,
  ParallelBuildExecutor,
  StartupProjectManager,
  LaunchSettingsManager
} from '../js/project/build-graph-engine.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');

// ----------------------------------------------------------------------------
// 1. Build Graph DAG & Topological Execution (Section 18.1)
// ----------------------------------------------------------------------------
test('Section 18.1: Build Graph DAG & Topological Ordering', () => {
  const graph = new BuildGraph();

  graph.addTask('clean', async () => 'cleaned');
  graph.addTask('compile_core', async () => 'core compiled', ['clean']);
  graph.addTask('compile_plugins', async () => 'plugins compiled', ['compile_core']);
  graph.addTask('bundle', async () => 'bundled', ['compile_plugins']);

  const order = graph.getExecutionOrder();
  assert.deepEqual(order, ['clean', 'compile_core', 'compile_plugins', 'bundle']);

  // Circular dependency detection
  const cyclic = new BuildGraph();
  cyclic.addTask('taskA', async () => {}, ['taskB']);
  cyclic.addTask('taskB', async () => {}, ['taskA']);
  assert.throws(() => cyclic.getExecutionOrder(), /Circular dependency/);
});

// ----------------------------------------------------------------------------
// 2. Dependency Tracking (Section 18.3)
// ----------------------------------------------------------------------------
test('Section 18.3: File-Level Dependency Tracking', () => {
  const tracker = new DependencyTracker();

  tracker.addDependency('src/main.ot', 'src/math.ot');
  tracker.addDependency('src/math.ot', 'src/vector.ot');
  tracker.addDependency('src/app.ot', 'src/vector.ot');

  // Changing vector.ot should affect vector.ot, math.ot, main.ot, and app.ot
  const affected = tracker.getAffectedFiles('src/vector.ot');
  assert.ok(affected.includes('src/vector.ot'));
  assert.ok(affected.includes('src/math.ot'));
  assert.ok(affected.includes('src/main.ot'));
  assert.ok(affected.includes('src/app.ot'));
});

// ----------------------------------------------------------------------------
// 3. Incremental Builds & Build Cache (Section 18.2, 18.6)
// ----------------------------------------------------------------------------
test('Section 18.2, 18.6: Incremental Build Cache & Up-To-Date Checks', () => {
  const testCacheDir = path.join(REPO_ROOT, 'publish', 'test-build-cache');
  const testSrcDir = path.join(REPO_ROOT, 'publish', 'test-build-src');
  fs.mkdirSync(testSrcDir, { recursive: true });

  const fileA = path.join(testSrcDir, 'a.ot');
  fs.writeFileSync(fileA, 'say "A"', 'utf8');

  try {
    const mgr = new IncrementalBuildManager(testCacheDir);

    // Initial check: not up-to-date
    assert.equal(mgr.isUpToDate('app_target', [fileA]), false);

    // Record build
    mgr.recordBuild('app_target', [fileA], ['dist/app.bin']);
    assert.equal(mgr.isUpToDate('app_target', [fileA]), true);

    // Modify fileA
    fs.writeFileSync(fileA, 'say "A Modified"', 'utf8');
    assert.equal(mgr.isUpToDate('app_target', [fileA]), false);

    // Invalidate
    mgr.recordBuild('app_target', [fileA]);
    mgr.invalidate('app_target');
    assert.equal(mgr.isUpToDate('app_target', [fileA]), false);
  } finally {
    if (fs.existsSync(testCacheDir)) fs.rmSync(testCacheDir, { recursive: true, force: true });
    if (fs.existsSync(testSrcDir)) fs.rmSync(testSrcDir, { recursive: true, force: true });
  }
});

// ----------------------------------------------------------------------------
// 4. Debug vs Release Configurations (Section 18.4)
// ----------------------------------------------------------------------------
test('Section 18.4: Debug and Release Build Configurations', () => {
  const dbg = getBuildConfig('debug');
  assert.equal(dbg.minify, false);
  assert.equal(dbg.sourceMaps, true);
  assert.equal(dbg.assertions, true);

  const rel = getBuildConfig('release');
  assert.equal(rel.minify, true);
  assert.equal(rel.sourceMaps, false);
  assert.equal(rel.stripComments, true);
});

// ----------------------------------------------------------------------------
// 5. Parallel Builds Execution (Section 18.5)
// ----------------------------------------------------------------------------
test('Section 18.5: Parallel Build Execution Engine', async () => {
  const graph = new BuildGraph();
  const log = [];

  graph.addTask('task1', async () => { log.push('task1'); return 1; });
  graph.addTask('task2', async () => { log.push('task2'); return 2; });
  graph.addTask('task3', async () => { log.push('task3'); return 3; }, ['task1', 'task2']);

  const executor = new ParallelBuildExecutor(2);
  const result = await executor.executeGraph(graph);

  assert.equal(result.completed.length, 3);
  assert.equal(result.results.get('task3'), 3);
  // task3 must run after both task1 and task2
  assert.ok(log.indexOf('task3') > log.indexOf('task1'));
  assert.ok(log.indexOf('task3') > log.indexOf('task2'));
});

// ----------------------------------------------------------------------------
// 6. Startup Project Selection (Section 18.7)
// ----------------------------------------------------------------------------
test('Section 18.7: Startup Project Management', () => {
  const testSolPath = path.join(REPO_ROOT, 'publish', 'test-startup.solution.json');

  try {
    const spm = new StartupProjectManager(testSolPath);
    assert.equal(spm.load(), null);

    spm.setStartupProject('OtterStudio');
    assert.equal(spm.load(), 'OtterStudio');

    const onDisk = JSON.parse(fs.readFileSync(testSolPath, 'utf8'));
    assert.equal(onDisk.startupProject, 'OtterStudio');
  } finally {
    if (fs.existsSync(testSolPath)) fs.rmSync(testSolPath, { force: true });
  }
});

// ----------------------------------------------------------------------------
// 7. Persist Launch Settings (.otter/launch.json) (Section 18.8)
// ----------------------------------------------------------------------------
test('Section 18.8: Persist Launch Settings Profiles', () => {
  const testLaunchPath = path.join(REPO_ROOT, 'publish', 'test-launch.json');

  try {
    const lsm = new LaunchSettingsManager(testLaunchPath);
    lsm.setProfile('WebDev', {
      mode: 'web',
      port: 3000,
      env: { DEBUG: '1' }
    });

    lsm.setProfile('ConsoleRun', {
      mode: 'console',
      args: ['--input', 'data.txt']
    });

    const profiles = lsm.listProfiles();
    assert.equal(profiles.length, 2);
    assert.equal(lsm.getProfile('WebDev').port, 3000);

    // Verify on disk persistence
    const reloaded = new LaunchSettingsManager(testLaunchPath);
    assert.equal(reloaded.getProfile('WebDev').port, 3000);

    reloaded.deleteProfile('ConsoleRun');
    assert.equal(reloaded.listProfiles().length, 1);
  } finally {
    if (fs.existsSync(testLaunchPath)) fs.rmSync(testLaunchPath, { force: true });
  }
});
