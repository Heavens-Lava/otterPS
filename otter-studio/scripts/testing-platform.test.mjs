// otter-studio/scripts/testing-platform.test.mjs
// Certification Test Suite for Section 20: Testing Platform
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  TestLifecycleManager,
  ParameterizedTestRunner,
  MockingFramework,
  CoverageEngine,
  UiComponentTestRunner,
  CrossPlatformTestMatrix,
  FlakyTestPolicyManager,
  TestPlatformEngine
} from '../js/testing/test-platform-engine.js';

const baseUrl = 'http://127.0.0.1:4200';

test('Section 20.3: Test Lifecycle Hooks (Setup and Teardown)', async () => {
  const lifecycle = new TestLifecycleManager();
  const sequence = [];

  lifecycle.beforeAll((ctx) => {
    sequence.push('beforeAll');
    ctx.db = 'initialized';
  });

  lifecycle.beforeEach((ctx, testCase) => {
    sequence.push(`beforeEach:${testCase}`);
    ctx.transaction = true;
  });

  lifecycle.afterEach((ctx, testCase) => {
    sequence.push(`afterEach:${testCase}`);
    ctx.transaction = false;
  });

  lifecycle.afterAll((ctx) => {
    sequence.push('afterAll');
    ctx.db = 'closed';
  });

  await lifecycle.runBeforeAll();
  assert.equal(lifecycle.context.db, 'initialized');

  await lifecycle.runBeforeEach('TestA');
  assert.equal(lifecycle.context.transaction, true);

  await lifecycle.runAfterEach('TestA', { passed: true });
  assert.equal(lifecycle.context.transaction, false);

  await lifecycle.runAfterAll();
  assert.equal(lifecycle.context.db, 'closed');

  assert.deepEqual(sequence, [
    'beforeAll',
    'beforeEach:TestA',
    'afterEach:TestA',
    'afterAll'
  ]);
});

test('Section 20.4: Parameterized and Expected-Error Test Execution', async () => {
  // 1. Table-driven parameterized test
  const tableCases = [
    { params: [2, 3], expected: 5, name: 'add 2 + 3' },
    { params: [10, -5], expected: 5, name: 'add 10 + -5' },
    { params: [0, 0], expected: 0, name: 'add 0 + 0' }
  ];

  const tableResult = await ParameterizedTestRunner.runTable(
    'Addition Suite',
    tableCases,
    async (a, b) => a + b
  );

  assert.equal(tableResult.total, 3);
  assert.equal(tableResult.passed, 3);
  assert.equal(tableResult.failed, 0);

  // 2. Expected-error test
  const expectedErrorSuccess = await ParameterizedTestRunner.expectError(async () => {
    throw new Error('Variable "count" is not defined');
  }, 'is not defined');

  assert.equal(expectedErrorSuccess.passed, true);
  assert.equal(expectedErrorSuccess.matched, true);

  const unexpectedSuccess = await ParameterizedTestRunner.expectError(async () => {
    return 'success';
  }, 'any error');

  assert.equal(unexpectedSuccess.passed, false);
});

test('Section 20.5: Mocking and Spying Framework', () => {
  const mocking = new MockingFramework();

  const service = {
    fetchScore(userId) {
      return userId * 10;
    }
  };

  // Spy on service.fetchScore
  const spy = mocking.spy(service, 'fetchScore');
  spy.mockReturnValue(999);

  const res1 = service.fetchScore(5);
  assert.equal(res1, 999);
  assert.equal(spy.getCallCount(), 1);
  assert.equal(spy.calledWith(5), true);

  // Restore
  spy.restore();
  const res2 = service.fetchScore(5);
  assert.equal(res2, 50); // back to original implementation

  // Standalone mock function
  const mockFn = mocking.fn();
  mockFn.mockReturnValue('ok');
  mockFn('hello', 42);
  assert.equal(mockFn.getCallCount(), 1);
  assert.equal(mockFn.calledWith('hello', 42), true);
});

test('Section 20.8, 20.10: Line Coverage and Metrics Calculation', () => {
  const engine = new CoverageEngine();

  // Record line hits for math.ot
  engine.recordLineHit('src/math.ot', 1);
  engine.recordLineHit('src/math.ot', 2);
  engine.recordLineHit('src/math.ot', 4);

  const fileReport = engine.computeFileCoverage('src/math.ot', 5, [1, 2, 3, 4, 5]);
  assert.equal(fileReport.executableLines, 5);
  assert.equal(fileReport.coveredLines, 3);
  assert.equal(fileReport.missedLines, 2);
  assert.equal(fileReport.percent, 60.0);
  assert.deepEqual(fileReport.covered, [1, 2, 4]);
  assert.deepEqual(fileReport.missed, [3, 5]);

  // Overall summary
  const summary = engine.computeSummary([
    { file: 'src/math.ot', totalLines: 5, executableLines: [1, 2, 3, 4, 5] },
    { file: 'src/util.ot', totalLines: 3, executableLines: [1, 2, 3] }
  ]);
  assert.equal(summary.totalExecutable, 8);
  assert.equal(summary.totalCovered, 3);
  assert.equal(summary.overallPercent, 37.5);
});

test('Section 20.11: Synthetic UI Component Testing', () => {
  let clicked = false;
  const result = UiComponentTestRunner.renderAndAssert(
    { tag: 'button', props: { className: 'btn btn-primary', label: 'Submit' } },
    (el) => {
      assert.equal(el.tag, 'button');
      assert.ok(el.classList.has('btn-primary'));

      el.addEventListener('click', () => {
        clicked = true;
      });
      el.click();
      assert.equal(clicked, true);
      return { ok: true, verified: true };
    }
  );
  assert.equal(result.ok, true);
});

test('Section 20.12: Cross-Platform Test Matrix Audit', () => {
  const posixCode = `
    const p = path.join('data', 'items.json');
    const content = fs.readFileSync(p, 'utf8');
  `;
  const matrixSafe = CrossPlatformTestMatrix.runMatrix(posixCode);
  assert.equal(matrixSafe.every(p => p.safe), true);

  const windowsHardcoded = `
    const p = "C:\\\\Users\\\\jmacy\\\\file.ot";
  `;
  const matrixUnsafe = CrossPlatformTestMatrix.runMatrix(windowsHardcoded);
  const linuxResult = matrixUnsafe.find(p => p.platform === 'linux');
  assert.equal(linuxResult.safe, false);
  assert.ok(linuxResult.issues.length > 0);
});

test('Section 20.13: Flaky Test Retry Policy and Quarantine Management', async () => {
  const policy = new FlakyTestPolicyManager({ maxRetries: 2, quarantineThreshold: 0.25 });

  // 1. Transient test: fails once, passes on retry
  let attempt = 0;
  const flakyRes = await policy.runWithRetry('NetworkSyncTest', async () => {
    attempt++;
    if (attempt === 1) throw new Error('Network timeout');
    return 'ok';
  });

  assert.equal(flakyRes.passed, true);
  assert.equal(flakyRes.attempts, 2);
  assert.equal(flakyRes.wasFlaky, true);

  // 2. Quarantine management
  policy.quarantineTest('FlakyWorkerTest');
  const stats = policy.getFlakyStats();
  const quarantined = stats.find(s => s.testName === 'FlakyWorkerTest');
  assert.ok(quarantined);
  assert.equal(quarantined.quarantined, true);
});

test('Section 20 Live Studio Server API Test Endpoints', async () => {
  // Test /api/tests/coverage
  const covRes = await fetch(`${baseUrl}/api/tests/coverage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      hits: [
        { file: 'main.ot', line: 1 },
        { file: 'main.ot', line: 2 },
        { file: 'main.ot', line: 3 }
      ],
      files: [
        { file: 'main.ot', totalLines: 4, executableLines: [1, 2, 3, 4] }
      ]
    })
  });
  assert.equal(covRes.status, 200);
  const covData = await covRes.json();
  assert.equal(covData.ok, true);
  assert.equal(covData.coverage.totalCovered, 3);
  assert.equal(covData.coverage.overallPercent, 75);

  // Test /api/tests/matrix
  const matRes = await fetch(`${baseUrl}/api/tests/matrix`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: 'const x = 1;\n' })
  });
  assert.equal(matRes.status, 200);
  const matData = await matRes.json();
  assert.equal(matData.ok, true);
  assert.equal(matData.allSafe, true);

  // Test /api/tests/flaky
  const flakeRes = await fetch(`${baseUrl}/api/tests/flaky`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ testName: 'SuiteAlpha', quarantine: true })
  });
  assert.equal(flakeRes.status, 200);
  const flakeData = await flakeRes.json();
  assert.equal(flakeData.ok, true);
  assert.ok(flakeData.stats.some(s => s.testName === 'SuiteAlpha' && s.quarantined === true));
});
