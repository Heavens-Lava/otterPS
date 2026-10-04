// profiler.test.mjs - Comprehensive Verification Suite for Otter Studio Profiler & DevTools
import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import {
  formatBytes,
  formatMs,
  normalizeProfile,
  analyzeFrameTiming,
  exportProfileTrace,
  importProfileTrace,
  compareProfiles
} from '../js/profiler/profiler-engine.js';

const execFileAsync = promisify(execFile);
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const RUN_PROFILE_PS1 = path.join(__dirname, 'run-profile.ps1');

test('Profiler Engine: formatters handle byte and millisecond scales', () => {
  assert.equal(formatBytes(0), '0 B');
  assert.equal(formatBytes(512), '512 B');
  assert.equal(formatBytes(2048), '2.0 KB');
  assert.equal(formatBytes(5242880), '5.0 MB');
  assert.equal(formatBytes(2147483648), '2.0 GB');
  assert.equal(formatBytes(-1048576), '-1.0 MB');

  assert.equal(formatMs(0), '0.00 ms');
  assert.equal(formatMs(12.3456), '12.35 ms');
  assert.equal(formatMs(1250), '1250.00 ms');
});

test('Profiler Engine: normalizeProfile derives percentages, hot paths, and averages', () => {
  const rawPayload = {
    ok: true,
    exitCode: 0,
    output: ['hello from otter'],
    profile: {
      Statements: 150,
      TotalMs: 200,
      TotalCpuMs: 180,
      UserCpuMs: 150,
      KernelCpuMs: 30,
      CpuUtilization: 90,
      TotalAllocatedBytes: 1048576,
      PeakManagedBytes: 20971520,
      WorkingSetBytes: 67108864,
      Gen0Collections: 1,
      Functions: [
        {
          Function: 'computeHeavy',
          Calls: 10,
          TotalMs: 150,
          SelfMs: 120,
          TotalCpuMs: 130,
          SelfCpuMs: 110,
          TotalAllocatedBytes: 524288,
          SelfAllocatedBytes: 524288
        },
        {
          Function: 'helper',
          Calls: 50,
          TotalMs: 30,
          SelfMs: 30,
          TotalCpuMs: 25,
          SelfCpuMs: 25,
          TotalAllocatedBytes: 131072,
          SelfAllocatedBytes: 131072
        }
      ],
      Lines: [
        { Line: 12, Hits: 10, SelfMs: 80, CpuMs: 70, AllocatedBytes: 262144, Source: 'result is result plus val' },
        { Line: 15, Hits: 50, SelfMs: 20, CpuMs: 15, AllocatedBytes: 65536, Source: 'say result' }
      ]
    }
  };

  const norm = normalizeProfile(rawPayload);
  assert.equal(norm.ok, true);
  assert.equal(norm.summary.statements, 150);
  assert.equal(norm.summary.totalMs, 200);
  assert.equal(norm.functions.length, 2);

  const f0 = norm.functions[0];
  assert.equal(f0.name, 'computeHeavy');
  assert.equal(f0.calls, 10);
  assert.equal(f0.selfMsPct, 60.0); // 120 / 200 = 60%
  assert.equal(f0.totalMsPct, 75.0); // 150 / 200 = 75%
  assert.equal(f0.avgSelfMsPerCall, 12.0); // 120 / 10 = 12ms
  assert.equal(f0.allocPct, 50.0); // 524288 / 1048576 = 50%

  assert.equal(norm.lines.length, 2);
  const l0 = norm.lines[0];
  assert.equal(l0.line, 12);
  assert.equal(l0.selfMsPct, 40.0); // 80 / 200 = 40%

  // Hot paths
  assert.equal(norm.hotFunctions[0].name, 'computeHeavy');
  assert.equal(norm.hotLines[0].line, 12);
});

test('Profiler Engine: analyzeFrameTiming assesses 60 FPS frame budget and latency', () => {
  // Fast loop taking 4ms -> well within 16.6ms budget
  const fastTiming = analyzeFrameTiming({ summary: { totalMs: 4.0 } }, { targetFps: 60 });
  assert.equal(fastTiming.targetFps, 60);
  assert.equal(fastTiming.targetFrameBudgetMs, 16.67);
  assert.equal(fastTiming.is60FpsCapable, true);
  assert.equal(fastTiming.status, 'well-within-budget');
  assert.equal(fastTiming.estimatedMaxFps, 60);

  // Heavy loop taking 25ms -> exceeds 16.6ms budget
  const slowTiming = analyzeFrameTiming({ summary: { totalMs: 25.0 } }, { targetFps: 60 });
  assert.equal(slowTiming.is60FpsCapable, false);
  assert.equal(slowTiming.status, 'over-budget');
  assert.equal(slowTiming.budgetUtilizationPct, 150.0);
  assert.equal(slowTiming.estimatedMaxFps, 40.0); // 1000 / 25 = 40 FPS
});

test('Profiler Engine: trace export, import, and schema validation round-trip', () => {
  const sample = normalizeProfile({
    ok: true,
    profile: {
      Statements: 25,
      TotalMs: 45.5,
      TotalCpuMs: 40.0,
      Functions: [{ Function: 'testFn', Calls: 5, TotalMs: 20, SelfMs: 20 }],
      Lines: [{ Line: 4, Hits: 5, SelfMs: 15, Source: 'testFn 1' }]
    }
  });

  const traceJson = exportProfileTrace(sample, {
    sourceFile: 'game_loop.ot',
    project: 'Game 2D Engine'
  });

  assert.match(traceJson, /"schema": "otter-profile-v1"/);
  assert.match(traceJson, /"sourceFile": "game_loop.ot"/);

  const imported = importProfileTrace(traceJson);
  assert.equal(imported.metadata.sourceFile, 'game_loop.ot');
  assert.equal(imported.profile.summary.statements, 25);
  assert.equal(imported.profile.functions[0].name, 'testFn');

  // Rejects invalid schema
  assert.throws(() => importProfileTrace(JSON.stringify({ schema: 'invalid' })), /missing schema/);
});

test('Profiler Engine: compareProfiles computes optimization and regression deltas', () => {
  const baseline = normalizeProfile({
    ok: true,
    profile: {
      Statements: 100,
      TotalMs: 100,
      TotalCpuMs: 90,
      TotalAllocatedBytes: 1000000,
      Functions: [
        { Function: 'fib', Calls: 100, SelfMs: 80, TotalMs: 80, TotalAllocatedBytes: 500000 }
      ]
    }
  });

  const optimized = normalizeProfile({
    ok: true,
    profile: {
      Statements: 100,
      TotalMs: 60, // 40% speedup
      TotalCpuMs: 50,
      TotalAllocatedBytes: 300000,
      Functions: [
        { Function: 'fib', Calls: 100, SelfMs: 45, TotalMs: 45, TotalAllocatedBytes: 200000 }
      ]
    }
  });

  const comparison = compareProfiles(baseline, optimized);
  assert.equal(comparison.status, 'improved');
  assert.equal(comparison.totalMsDelta, -40.0);
  assert.equal(comparison.totalMsPctChange, -40.0);
  assert.equal(comparison.cpuDelta, -40.0);
  assert.equal(comparison.allocDelta, -700000);

  const fibDelta = comparison.functionDeltas.find(d => d.name === 'fib');
  assert.ok(fibDelta);
  assert.equal(fibDelta.selfMsDelta, -35.0);
  assert.equal(fibDelta.allocBytesDelta, -300000);
});

test('Real Profiler Execution: run-profile.ps1 profiles Otter function calls and hot lines', async () => {
  const testOtterCode = `
to cube number
    number times number make sq
    sq times number make cb
    return cb

total is 0
count from 1 to 10 as idx
    cube idx make c
    total is total plus c
.
say "Total cubes:" total
`;

  const args = [
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', RUN_PROFILE_PS1,
    '-Source', testOtterCode,
    '-Top', '10'
  ];

  const { stdout } = await execFileAsync('powershell.exe', args, {
    cwd: REPO_ROOT,
    timeout: 30000
  });

  const result = JSON.parse(stdout.trim());
  assert.equal(result.ok, true);
  assert.equal(result.exitCode, 0);
  assert.ok(result.output.some(line => line.includes('Total cubes: 3025')));

  const prof = normalizeProfile(result);
  assert.ok(prof.summary.statements >= 10, 'Tracked statements executed');
  assert.ok(prof.summary.totalMs > 0, 'Measured wall clock duration');
  assert.ok(prof.summary.totalAllocatedBytes > 0, 'Measured memory allocations');

  // Verify function profiling
  const cubeFunc = prof.functions.find(f => f.name === 'cube');
  assert.ok(cubeFunc, 'Function cube tracked in profiler');
  assert.equal(cubeFunc.calls, 10, 'Function cube was called 10 times');
  assert.ok(cubeFunc.selfMs >= 0);

  // Verify hot lines attribution
  assert.ok(prof.lines.length > 0, 'Line profiles collected');
  assert.ok(prof.lines.some(l => l.source.includes('cube') || l.source.includes('total plus c')));
});

test('Real Profiler Execution: run-profile.ps1 captures runtime error and preserves execution profile', async () => {
  const badCode = `
to stepOne
    say "step one ok"
    return 1

stepOne make res
say "res is" res
say undefinedVariable
`;

  const args = [
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', RUN_PROFILE_PS1,
    '-Source', badCode
  ];

  const { stdout } = await execFileAsync('powershell.exe', args, {
    cwd: REPO_ROOT,
    timeout: 30000
  });

  const result = JSON.parse(stdout.trim());
  assert.equal(result.ok, false);
  assert.equal(result.exitCode, 3);
  assert.ok(result.error);
  assert.match(result.error.message, /undefinedVariable/i);
  assert.ok(result.output.includes('step one ok'));

  // Profiler metrics still captured up to failure
  assert.ok(result.profile);
  assert.ok(result.profile.Statements >= 2);
  const norm = normalizeProfile(result);
  const stepOne = norm.functions.find(f => f.name === 'stepOne');
  assert.ok(stepOne);
  assert.equal(stepOne.calls, 1);
});

async function postApiProfile(payload) {
  const res = await fetch('http://localhost:4200/api/profile', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  });
  const data = await res.json();
  return { status: res.status, data };
}

test('Live Studio Server API: POST /api/profile with inline code returns execution profile', async () => {
  const { status, data } = await postApiProfile({
    code: `
to triple n
    return n times 3

triple 7 make ans
say "ans is" ans
`
  });

  assert.equal(status, 200);
  assert.equal(data.ok, true);
  assert.equal(data.exitCode, 0);
  assert.ok(data.output.includes('ans is 21'));
  assert.ok(data.profile);
  assert.ok(data.profile.Statements >= 3);

  const norm = normalizeProfile(data);
  const triple = norm.functions.find(f => f.name === 'triple');
  assert.ok(triple);
  assert.equal(triple.calls, 1);
});

test('Live Studio Server API: POST /api/profile with path executes real file', async () => {
  const { status, data } = await postApiProfile({
    path: 'examples/collections.ot',
    top: 10
  });

  assert.equal(status, 200);
  assert.equal(data.ok, true);
  assert.ok(data.output.some(l => l.includes('Mario')));
  assert.ok(data.profile.Lines.length > 0);
  assert.ok(data.profile.Statements >= 15);
});

test('Live Studio Server API: POST /api/profile handles 404 for missing path and 400 for bad input', async () => {
  const notFound = await postApiProfile({ path: 'examples/nonexistent_file.ot' });
  assert.equal(notFound.status, 404);
  assert.equal(notFound.data.ok, false);

  const badInput = await postApiProfile({});
  assert.equal(badInput.status, 400);
  assert.equal(badInput.data.ok, false);
});

