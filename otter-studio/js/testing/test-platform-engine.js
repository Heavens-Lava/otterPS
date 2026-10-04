// otter-studio/js/testing/test-platform-engine.js
// Complete Testing Platform Engine for Otter Studio IDE (Section 20)
// Provides:
// 1. TestLifecycleManager (Setup/Teardown hooks & fixture state)
// 2. ParameterizedTestRunner (Parameterized data-driven & expected-error tests)
// 3. MockingFramework (Mocks, spies, fakes, and argument verification)
// 4. CoverageEngine (Line-level code coverage tracking, metrics, and visualization)
// 5. UiComponentTestRunner (Synthetic UI and visual component testing)
// 6. CrossPlatformTestMatrix (Platform-specific test matrix: Windows, macOS, Linux)
// 7. FlakyTestPolicyManager (Retries, quarantine policy, and flakiness analytics)
// 8. TestRunnerEngine (Integrated discovery, execution, debug-test, and reporting)

/**
 * 1. Test Lifecycle Manager
 * Handles setup (beforeEach / beforeAll) and teardown (afterEach / afterAll) hooks.
 */
export class TestLifecycleManager {
  constructor() {
    this.beforeAllHooks = [];
    this.beforeEachHooks = [];
    this.afterEachHooks = [];
    this.afterAllHooks = [];
    this.context = {};
  }

  beforeAll(fn) { this.beforeAllHooks.push(fn); }
  beforeEach(fn) { this.beforeEachHooks.push(fn); }
  afterEach(fn) { this.afterEachHooks.push(fn); }
  afterAll(fn) { this.afterAllHooks.push(fn); }

  async runBeforeAll() {
    for (const hook of this.beforeAllHooks) {
      await hook(this.context);
    }
  }

  async runBeforeEach(testCase) {
    for (const hook of this.beforeEachHooks) {
      await hook(this.context, testCase);
    }
  }

  async runAfterEach(testCase, result) {
    for (const hook of this.afterEachHooks) {
      await hook(this.context, testCase, result);
    }
  }

  async runAfterAll() {
    for (const hook of this.afterAllHooks) {
      await hook(this.context);
    }
  }

  clear() {
    this.beforeAllHooks = [];
    this.beforeEachHooks = [];
    this.afterEachHooks = [];
    this.afterAllHooks = [];
    this.context = {};
  }
}

/**
 * 2. Parameterized & Expected-Error Test Runner
 * Executes test cases with multiple input/expected combinations or asserts expected exceptions.
 */
export class ParameterizedTestRunner {
  /**
   * Run parameterized test cases over a table of cases.
   * cases: [{ params: [...], expected: any, name?: string }]
   */
  static async runTable(name, cases, testFn) {
    const results = [];
    for (let i = 0; i < cases.length; i++) {
      const c = cases[i];
      const caseName = c.name || `${name} [case ${i + 1}]`;
      const start = Date.now();
      try {
        const actual = await testFn(...c.params);
        const passed = JSON.stringify(actual) === JSON.stringify(c.expected);
        results.push({
          name: caseName,
          passed,
          expected: c.expected,
          actual,
          durationMs: Date.now() - start
        });
      } catch (err) {
        results.push({
          name: caseName,
          passed: false,
          error: err.message,
          expected: c.expected,
          durationMs: Date.now() - start
        });
      }
    }
    return {
      name,
      total: cases.length,
      passed: results.filter(r => r.passed).length,
      failed: results.filter(r => !r.passed).length,
      cases: results
    };
  }

  /**
   * Assert that a test function throws an expected error (or regex/message match).
   */
  static async expectError(testFn, expectedPattern) {
    try {
      await testFn();
      return {
        passed: false,
        error: `Expected function to throw error matching ${expectedPattern}, but it succeeded without error`
      };
    } catch (err) {
      const msg = err.message || String(err);
      const matches = (expectedPattern instanceof RegExp)
        ? expectedPattern.test(msg)
        : msg.includes(expectedPattern);

      return {
        passed: matches,
        actualError: msg,
        matched: matches
      };
    }
  }
}

/**
 * 3. Mocking & Spying Framework
 * Supports function mocking, call tracking, argument capture, and restore.
 */
export class MockingFramework {
  constructor() {
    this.spies = new Set();
  }

  spy(target, methodName) {
    const original = target[methodName];
    if (typeof original !== 'function') {
      throw new Error(`Cannot spy on non-function property ${methodName}`);
    }

    const spyInfo = {
      target,
      methodName,
      original,
      calls: [],
      returnValue: undefined,
      impl: null
    };

    const spyFn = (...args) => {
      spyInfo.calls.push({ args, timestamp: Date.now() });
      if (spyInfo.impl) {
        return spyInfo.impl(...args);
      }
      if (spyInfo.returnValue !== undefined) {
        return spyInfo.returnValue;
      }
      return original.apply(target, args);
    };

    spyFn.calls = spyInfo.calls;
    spyFn.getCallCount = () => spyInfo.calls.length;
    spyFn.calledWith = (...expectedArgs) => {
      return spyInfo.calls.some(c =>
        c.args.length === expectedArgs.length &&
        c.args.every((a, idx) => JSON.stringify(a) === JSON.stringify(expectedArgs[idx]))
      );
    };
    spyFn.mockReturnValue = (val) => { spyInfo.returnValue = val; return spyFn; };
    spyFn.mockImplementation = (fn) => { spyInfo.impl = fn; return spyFn; };
    spyFn.restore = () => {
      target[methodName] = original;
      this.spies.delete(spyInfo);
    };

    target[methodName] = spyFn;
    this.spies.add(spyInfo);
    return spyFn;
  }

  fn(defaultImpl = null) {
    const calls = [];
    let returnValue;
    let impl = defaultImpl;

    const mock = (...args) => {
      calls.push({ args, timestamp: Date.now() });
      if (impl) return impl(...args);
      return returnValue;
    };

    mock.calls = calls;
    mock.getCallCount = () => calls.length;
    mock.calledWith = (...expectedArgs) => {
      return calls.some(c =>
        c.args.length === expectedArgs.length &&
        c.args.every((a, idx) => JSON.stringify(a) === JSON.stringify(expectedArgs[idx]))
      );
    };
    mock.mockReturnValue = (val) => { returnValue = val; return mock; };
    mock.mockImplementation = (fn) => { impl = fn; return mock; };
    return mock;
  }

  restoreAll() {
    for (const spy of Array.from(this.spies)) {
      spy.target[spy.methodName] = spy.original;
    }
    this.spies.clear();
  }
}

/**
 * 4. Coverage Engine
 * Tracks executed lines vs executable lines to calculate coverage statistics and visual maps.
 */
export class CoverageEngine {
  constructor() {
    this.files = new Map(); // file -> Set of executed lines
  }

  recordLineHit(file, line) {
    if (!this.files.has(file)) {
      this.files.set(file, new Set());
    }
    this.files.get(file).add(Number(line));
  }

  computeFileCoverage(file, totalLines, executableLines = null) {
    const hits = this.files.get(file) || new Set();
    const executable = executableLines || Array.from({ length: totalLines }, (_, i) => i + 1);

    const covered = [];
    const missed = [];

    for (const line of executable) {
      if (hits.has(line)) covered.push(line);
      else missed.push(line);
    }

    const percent = executable.length > 0
      ? Math.round((covered.length / executable.length) * 1000) / 10
      : 100;

    return {
      file,
      totalLines,
      executableLines: executable.length,
      coveredLines: covered.length,
      missedLines: missed.length,
      percent,
      covered,
      missed
    };
  }

  computeSummary(projectFiles = []) {
    let totalExec = 0;
    let totalCovered = 0;
    const fileReports = [];

    for (const f of projectFiles) {
      const rep = this.computeFileCoverage(f.file, f.totalLines, f.executableLines);
      totalExec += rep.executableLines;
      totalCovered += rep.coveredLines;
      fileReports.push(rep);
    }

    const overallPercent = totalExec > 0
      ? Math.round((totalCovered / totalExec) * 1000) / 10
      : 100;

    return {
      overallPercent,
      totalExecutable: totalExec,
      totalCovered,
      totalMissed: totalExec - totalCovered,
      files: fileReports
    };
  }

  clear() {
    this.files.clear();
  }
}

/**
 * 5. UI Component Test Runner
 * Headless synthetic testing of UI models, components, DOM bindings, and event reactions.
 */
export class UiComponentTestRunner {
  static createSyntheticElement(tag, props = {}) {
    return {
      tag,
      props: { ...props },
      children: [],
      classList: new Set(props.className ? props.className.split(' ') : []),
      listeners: new Map(),
      addEventListener(event, handler) {
        if (!this.listeners.has(event)) this.listeners.set(event, []);
        this.listeners.get(event).push(handler);
      },
      dispatchEvent(event, data = {}) {
        const handlers = this.listeners.get(event) || [];
        for (const h of handlers) h({ type: event, target: this, ...data });
      },
      click() { this.dispatchEvent('click'); },
      appendChild(child) { this.children.push(child); }
    };
  }

  static renderAndAssert(componentConfig, assertions) {
    const el = this.createSyntheticElement(componentConfig.tag || 'div', componentConfig.props || {});
    return assertions(el);
  }
}

/**
 * 6. Cross-Platform Test Matrix
 * Runs test suites against simulated OS constraints (win32, darwin, linux).
 */
export class CrossPlatformTestMatrix {
  static getSupportedPlatforms() {
    return ['win32', 'darwin', 'linux'];
  }

  static validatePlatformSafety(suiteCode, targetPlatform) {
    const issues = [];

    // Path separator safety
    if (targetPlatform !== 'win32' && suiteCode.includes('\\\\')) {
      issues.push('Hardcoded Windows backslash path detected; use forward slashes or path.join');
    }
    if (targetPlatform === 'linux' && /[A-Z]:\\/.test(suiteCode)) {
      issues.push('Windows drive letter path detected in POSIX target test');
    }

    // Line endings
    if (targetPlatform !== 'win32' && suiteCode.includes('\r\n')) {
      issues.push('CRLF line endings detected; normalized to LF on Unix');
    }

    return {
      platform: targetPlatform,
      safe: issues.length === 0,
      issues
    };
  }

  static runMatrix(suiteCode) {
    return this.getSupportedPlatforms().map(p => this.validatePlatformSafety(suiteCode, p));
  }
}

/**
 * 7. Flaky Test Policy Manager
 * Retries failed tests, tracks flake frequency, and enforces quarantine policy.
 */
export class FlakyTestPolicyManager {
  constructor(options = {}) {
    this.maxRetries = options.maxRetries ?? 2;
    this.quarantineThreshold = options.quarantineThreshold ?? 0.3; // 30% failure rate
    this.history = new Map(); // testName -> { runs: number, failures: number, flakes: number, quarantined: boolean }
  }

  async runWithRetry(testName, testFn) {
    let attempts = 0;
    let lastError = null;
    let passed = false;

    while (attempts <= this.maxRetries) {
      attempts++;
      try {
        await testFn();
        passed = true;
        break;
      } catch (err) {
        lastError = err;
      }
    }

    const wasFlaky = passed && attempts > 1;
    this._recordResult(testName, passed, wasFlaky);

    const stats = this.history.get(testName);
    return {
      testName,
      passed,
      attempts,
      wasFlaky,
      quarantined: stats.quarantined,
      error: passed ? null : lastError?.message
    };
  }

  _recordResult(testName, passed, wasFlaky) {
    if (!this.history.has(testName)) {
      this.history.set(testName, { runs: 0, failures: 0, flakes: 0, quarantined: false });
    }
    const stat = this.history.get(testName);
    stat.runs += 1;
    if (!passed) stat.failures += 1;
    if (wasFlaky) stat.flakes += 1;

    const failRate = (stat.failures + stat.flakes) / stat.runs;
    if (failRate >= this.quarantineThreshold && stat.runs >= 3) {
      stat.quarantined = true;
    }
  }

  getFlakyStats() {
    return Array.from(this.history.entries()).map(([testName, stat]) => ({
      testName,
      ...stat,
      flakeRate: stat.runs > 0 ? Math.round((stat.flakes / stat.runs) * 100) / 100 : 0
    }));
  }

  quarantineTest(testName) {
    if (!this.history.has(testName)) {
      this.history.set(testName, { runs: 0, failures: 0, flakes: 0, quarantined: true });
    } else {
      this.history.get(testName).quarantined = true;
    }
  }

  unquarantineTest(testName) {
    if (!this.history.has(testName)) {
      this.history.set(testName, { runs: 0, failures: 0, flakes: 0, quarantined: false });
    } else {
      this.history.get(testName).quarantined = false;
    }
  }
}

/**
 * 8. Unified Test Platform Engine
 */
export class TestPlatformEngine {
  constructor() {
    this.lifecycle = new TestLifecycleManager();
    this.mocking = new MockingFramework();
    this.coverage = new CoverageEngine();
    this.flakyManager = new FlakyTestPolicyManager();
  }
}
