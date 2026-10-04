// otter-studio/scripts/debugger-advanced.test.mjs
// Certification Test Suite for Section 19: Complete Debugger
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  DebugAdapterEngine,
  BreakpointManager,
  CallStackManager,
  WatchExpressionManager,
  ExpressionEvaluator,
  ObjectInspectionEngine,
  ErrorBreakpointManager,
  AsyncDebugTracker,
  SourceMapResolver,
  AttachManager,
  RemoteDebugManager,
  DapAdapter
} from '../js/debugger/debug-adapter-engine.js';

const baseUrl = 'http://127.0.0.1:4200';

test('Section 19.4, 19.5: Conditional Breakpoints, Hit-Count Breakpoints, and Logpoints', () => {
  const bpm = new BreakpointManager();

  // 1. Standard breakpoint
  bpm.setBreakpoint({ file: 'main.ot', line: 10 });
  const hit1 = bpm.evaluateHit('main.ot', 10, { score: 5 });
  assert.equal(hit1.pause, true);
  assert.equal(hit1.hitCount, 1);

  // 2. Conditional breakpoint: score > 10
  bpm.setBreakpoint({ file: 'main.ot', line: 15, condition: 'score > 10' });
  // score = 5 -> false -> should not pause
  const hitCondUnmet = bpm.evaluateHit('main.ot', 15, { score: 5 });
  assert.equal(hitCondUnmet.pause, false);
  assert.equal(hitCondUnmet.reason, 'condition_unmet');

  // score = 15 -> true -> should pause
  const hitCondMet = bpm.evaluateHit('main.ot', 15, { score: 15 });
  assert.equal(hitCondMet.pause, true);
  assert.equal(hitCondMet.hitCount, 2);

  // 3. Otter syntax condition: score is greater than 10 and active is true
  bpm.setBreakpoint({ file: 'main.ot', line: 20, condition: 'score is greater than 10 and active is true' });
  const hitOtterCond = bpm.evaluateHit('main.ot', 20, { score: 25, active: true });
  assert.equal(hitOtterCond.pause, true);

  // 4. Hit-count breakpoint: hitCondition "3"
  bpm.setBreakpoint({ file: 'main.ot', line: 30, hitCondition: '3' });
  assert.equal(bpm.evaluateHit('main.ot', 30, {}).pause, false); // hit 1
  assert.equal(bpm.evaluateHit('main.ot', 30, {}).pause, false); // hit 2
  const hit3 = bpm.evaluateHit('main.ot', 30, {});
  assert.equal(hit3.pause, true); // hit 3 -> pauses!
  assert.equal(hit3.hitCount, 3);

  // 5. Logpoint: message interpolation without pausing
  bpm.setBreakpoint({ file: 'main.ot', line: 40, logMessage: 'At line {line}: user={user} score={score}' });
  const logHit = bpm.evaluateHit('main.ot', 40, { user: 'Alice', score: 99 });
  assert.equal(logHit.pause, false);
  assert.equal(logHit.reason, 'logpoint');
  assert.equal(logHit.log, 'At line 40: user=Alice score=99');
});

test('Section 19.7, 19.9: Call Stack Hierarchy and Scope Frames', () => {
  const stack = new CallStackManager();
  const pauseEvent = {
    file: 'calc.ot',
    line: 42,
    locals: { result: 100, factor: 2 },
    callStack: [
      { function: 'main', file: 'app.ot', line: 12, locals: { args: [] } },
      { function: 'computeTotal', file: 'calc.ot', line: 42, locals: { result: 100, factor: 2 } }
    ]
  };

  const frames = stack.updateFromPauseEvent(pauseEvent);
  assert.equal(frames.length, 2);
  assert.equal(frames[0].functionName, 'computeTotal');
  assert.equal(frames[0].line, 42);
  assert.equal(frames[0].locals.result, 100);

  // Inspect caller frame
  const callerFrame = stack.selectFrame(1);
  assert.ok(callerFrame);
  assert.equal(callerFrame.functionName, 'main');
  assert.equal(callerFrame.line, 12);
});

test('Section 19.11, 19.12: Expression Evaluator & Watch Expressions', () => {
  const scope = {
    x: 10,
    y: 20,
    title: 'Otter',
    items: [1, 2, 3],
    user: { name: 'Bob', age: 30 }
  };

  // Arithmetic & binary ops
  const res1 = ExpressionEvaluator.evaluate('x + y * 2', scope);
  assert.equal(res1.ok, true);
  assert.equal(res1.value, 50);

  // Otter comparisons
  const res2 = ExpressionEvaluator.evaluate('x is less than y', scope);
  assert.equal(res2.ok, true);
  assert.equal(res2.value, true);

  // Nested property & indexing
  const res3 = ExpressionEvaluator.evaluate('user.name', scope);
  assert.equal(res3.ok, true);
  assert.equal(res3.value, 'Bob');

  const res4 = ExpressionEvaluator.evaluate('items[1]', scope);
  assert.equal(res4.ok, true);
  assert.equal(res4.value, 2);

  // Watch expressions manager
  const wm = new WatchExpressionManager();
  wm.addWatch('x * 2');
  wm.addWatch('user.age is at least 18');
  const evaluatedWatches = wm.evaluateAll(scope);
  assert.equal(evaluatedWatches.length, 2);
  assert.equal(evaluatedWatches[0].value, 20);
  assert.equal(evaluatedWatches[1].value, true);
});

test('Section 19.13: Object & List Deep Inspection Engine', () => {
  const data = {
    id: 101,
    tags: ['fast', 'stable'],
    meta: {
      owner: 'Admin',
      active: true
    }
  };

  const root = ObjectInspectionEngine.inspect(data);
  assert.equal(root.type, 'object');
  assert.equal(root.hasChildren, true);
  assert.equal(root.properties.length, 3);

  // Navigate to child list path
  const tagsNode = ObjectInspectionEngine.inspect(data, 'tags');
  assert.equal(tagsNode.type, 'list');
  assert.equal(tagsNode.length, 2);
  assert.equal(tagsNode.children[0].value, '"fast"');

  // Navigate to nested object
  const metaNode = ObjectInspectionEngine.inspect(data, 'meta.owner');
  assert.equal(metaNode.type, 'string');
  assert.equal(metaNode.value, '"Admin"');
});

test('Section 19.14, 19.15: Error Breakpoints & Async Debug Tracking', () => {
  const ebm = new ErrorBreakpointManager();
  ebm.setOptions({ all: false, uncaught: true });
  assert.equal(ebm.shouldBreakOnError(true), false); // caught -> false
  assert.equal(ebm.shouldBreakOnError(false), true); // uncaught -> true

  ebm.setOptions({ all: true });
  assert.equal(ebm.shouldBreakOnError(true), true); // all -> true

  // Async Tracker
  const tracker = new AsyncDebugTracker();
  const task = tracker.registerTask({ name: 'FetchData', metadata: { url: '/api/data' } });
  assert.equal(tracker.getActiveTasks().length, 1);
  assert.equal(task.status, 'pending');

  tracker.completeTask(task.id, { rows: 10 });
  assert.equal(tracker.getActiveTasks().length, 0);
});

test('Section 19.16, 19.18, 19.19, 19.20: Source Maps, Attach, Remote & DAP Protocol', () => {
  // 1. Source Map Resolver
  const resolver = new SourceMapResolver();
  resolver.registerSourceMap('bundle.js', {
    file: 'main.ot',
    lineMap: {
      100: { sourceFile: 'main.ot', line: 15, column: 4 }
    }
  });
  const mapped = resolver.resolveSourceLocation('bundle.js', 100);
  assert.equal(mapped.sourceFile, 'main.ot');
  assert.equal(mapped.line, 15);
  assert.equal(mapped.column, 4);

  // 2. Attach Manager
  const attachRes = AttachManager.attachToPid(12345);
  assert.equal(attachRes.ok, true);
  assert.equal(attachRes.pid, 12345);
  assert.equal(attachRes.mode, 'attached');

  // 3. Remote Debug Manager
  const rdm = new RemoteDebugManager();
  const remoteSession = rdm.createRemoteSession('127.0.0.1', 9229);
  assert.equal(remoteSession.connected, true);
  assert.equal(remoteSession.port, 9229);
  rdm.closeSession(remoteSession.sessionId);
  assert.equal(rdm.getSession(remoteSession.sessionId), null);

  // 4. DAP Adapter
  const engine = new DebugAdapterEngine();
  const dap = new DapAdapter(engine);

  // initialize
  const initRes = dap.handleMessage({ command: 'initialize', seq: 1 });
  assert.equal(initRes.success, true);
  assert.equal(initRes.body.supportsConditionalBreakpoints, true);
  assert.equal(initRes.body.supportsLogPoints, true);

  // setBreakpoints
  const setBpRes = dap.handleMessage({
    command: 'setBreakpoints',
    seq: 2,
    arguments: {
      source: { path: 'main.ot' },
      breakpoints: [{ line: 12, condition: 'x > 5' }]
    }
  });
  assert.equal(setBpRes.success, true);
  assert.equal(setBpRes.body.breakpoints.length, 1);
  assert.equal(setBpRes.body.breakpoints[0].line, 12);

  // threads
  const threadsRes = dap.handleMessage({ command: 'threads', seq: 3 });
  assert.equal(threadsRes.body.threads.length, 1);
});

test('Section 19 Live Studio Server API Debug Endpoints', async () => {
  // Test /api/debug/sourcemap
  const smRes = await fetch(`${baseUrl}/api/debug/sourcemap`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      compiledFile: 'out.js',
      line: 50,
      column: 1,
      mapData: {
        file: 'src/main.ot',
        lineMap: { 50: { line: 10, column: 2 } }
      }
    })
  });
  assert.equal(smRes.status, 200);
  const smData = await smRes.json();
  assert.equal(smData.ok, true);
  assert.equal(smData.mapped.line, 10);

  // Test /api/debug/attach
  const attachRes = await fetch(`${baseUrl}/api/debug/attach`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ pid: 9876 })
  });
  assert.equal(attachRes.status, 200);
  const attachData = await attachRes.json();
  assert.equal(attachData.ok, true);
  assert.equal(attachData.pid, 9876);

  // Test /api/debug/dap
  const dapRes = await fetch(`${baseUrl}/api/debug/dap`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      sessionId: attachData.sessionId,
      message: { command: 'initialize', seq: 1 }
    })
  });
  assert.equal(dapRes.status, 200);
  const dapData = await dapRes.json();
  assert.equal(dapData.success, true);
  assert.equal(dapData.body.supportsLogPoints, true);
});
