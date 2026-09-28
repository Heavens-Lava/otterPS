// test-explorer.js - The Tests tab in the bottom drawer.
//
// Lists the project's tests (tests/**/*_test.ot and test_*.ot, the same files
// `otter test` runs) and runs them through the real `otter test <file>`
// command, one at a time, via /api/tests/* (server/tests.mjs). Each row shows
// its state, duration and, when it failed, the message and line; the output
// panel shows everything the test printed.
//
//   Run All / Run Failed / Run one (▶ on a row)   Stop finishes the current
//   test and skips the rest. Filter by name or by state. Double-click a test
//   (or "Go to failure") to open it at the failing line.

const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));

// Icon plus a word, so the state never depends on colour alone.
const STATE = {
  idle: { icon: '○', label: 'Not run' },
  queued: { icon: '…', label: 'Queued' },
  running: { icon: '⟳', label: 'Running' },
  passed: { icon: '✓', label: 'Passed' },
  failed: { icon: '✗', label: 'Failed' },
  error: { icon: '⚠', label: 'Did not parse' }
};

export function formatDuration(ms) {
  if (ms === null || ms === undefined) return '';
  return ms < 1000 ? `${ms} ms` : `${(ms / 1000).toFixed(1)} s`;
}

export class TestExplorer {
  constructor(ide, container) {
    this.ide = ide;
    this.container = container;
    this.tests = [];            // [{ path, name, state, durationMs, message, line, output }]
    this.selected = null;
    this.filterText = '';
    this.filterState = 'all';
    this.running = false;
    this.cancelRequested = false;
  }

  get folder() {
    const f = this.ide.currentProjectFolder;
    return f && !/\.(json|otter-workspace)$/i.test(f) ? f : null;
  }

  init() {
    this.container.addEventListener('click', e => this.onClick(e));
    this.container.addEventListener('dblclick', e => {
      const row = e.target.closest('[data-test]');
      if (row) this.openTest(row.dataset.test);
    });
    this.container.addEventListener('keydown', e => {
      const row = e.target.closest('[data-test]');
      if (!row) return;
      if (e.key === 'Enter') { e.preventDefault(); this.select(row.dataset.test); }
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        const rows = [...this.container.querySelectorAll('[data-test]')];
        const next = rows[rows.indexOf(row) + (e.key === 'ArrowDown' ? 1 : -1)];
        next?.focus();
      }
    });
    this.container.addEventListener('input', e => {
      if (e.target.id === 'testFilter') { this.filterText = e.target.value; this.renderList(); }
    });
    this.container.addEventListener('change', e => {
      if (e.target.id === 'testStateFilter') { this.filterState = e.target.value; this.renderList(); }
    });
    this.render();
  }

  async discover() {
    const folder = this.folder;
    if (!folder) {
      this.tests = [];
      this.message = 'Open a project folder to see its tests.';
      this.render();
      return;
    }
    try {
      const res = await fetch(`/api/tests/list?folder=${encodeURIComponent(folder)}`);
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      // Keep earlier results for tests that still exist.
      const previous = new Map(this.tests.map(t => [t.path, t]));
      this.tests = data.tests.map(t => previous.get(t.path) || { ...t, state: 'idle', durationMs: null, message: null, line: null, output: '' });
      this.message = this.tests.length ? null : 'No tests found. Add files named tests/<name>_test.ot; a test passes when it runs without `fail with`.';
    } catch (err) {
      this.tests = [];
      this.message = err.message;
    }
    this.render();
  }

  visibleTests() {
    const text = this.filterText.trim().toLowerCase();
    return this.tests.filter(t =>
      (!text || t.name.toLowerCase().includes(text)) &&
      (this.filterState === 'all' ||
        (this.filterState === 'failed' && (t.state === 'failed' || t.state === 'error')) ||
        (this.filterState === 'passed' && t.state === 'passed') ||
        (this.filterState === 'idle' && t.state === 'idle')));
  }

  summary() {
    const count = state => this.tests.filter(t => t.state === state).length;
    const failed = count('failed') + count('error');
    const total = this.tests.reduce((sum, t) => sum + (t.durationMs || 0), 0);
    return `${count('passed')} passed · ${failed} failed · ${count('idle')} not run${total ? ` · ${formatDuration(total)}` : ''}`;
  }

  render() {
    this.container.innerHTML = `
      <div class="test-toolbar" role="toolbar" aria-label="Tests">
        <button class="scm-btn scm-btn-primary" data-test-action="run-all" ${this.running ? 'disabled' : ''}>▶ Run All</button>
        <button class="scm-btn" data-test-action="run-failed" ${this.running ? 'disabled' : ''}>Run Failed</button>
        <button class="scm-btn" data-test-action="stop" ${this.running ? '' : 'disabled'}>■ Stop</button>
        <button class="scm-btn" data-test-action="refresh" title="Find tests again">↻</button>
        <label class="scm-visually-hidden" for="testFilter">Filter tests</label>
        <input id="testFilter" class="config-input test-filter" placeholder="Filter by name" value="${esc(this.filterText)}" />
        <label class="scm-visually-hidden" for="testStateFilter">Show</label>
        <select id="testStateFilter" class="config-select test-filter">
          ${[['all', 'All'], ['failed', 'Failed'], ['passed', 'Passed'], ['idle', 'Not run']].map(([v, l]) => `<option value="${v}"${this.filterState === v ? ' selected' : ''}>${l}</option>`).join('')}
        </select>
        <span class="test-summary" role="status" aria-live="polite">${esc(this.summary())}</span>
      </div>
      <div class="test-body">
        <ul class="test-list" role="listbox" aria-label="Tests"></ul>
        <div class="test-details" aria-live="polite"></div>
      </div>`;
    this.renderList();
    this.renderDetails();
  }

  renderList() {
    const list = this.container.querySelector('.test-list');
    if (!list) return;
    if (this.message && !this.tests.length) {
      list.innerHTML = `<li class="scm-none">${esc(this.message)}</li>`;
      return;
    }
    list.innerHTML = this.visibleTests().map(t => {
      const s = STATE[t.state];
      return `
        <li class="test-row test-${t.state}${this.selected === t.path ? ' is-selected' : ''}" data-test="${esc(t.path)}" role="option" aria-selected="${this.selected === t.path}" tabindex="0">
          <span class="test-icon" aria-hidden="true">${s.icon}</span>
          <span class="test-name">${esc(t.name)}</span>
          <span class="test-state">${s.label}</span>
          <span class="test-duration">${esc(formatDuration(t.durationMs))}</span>
          <button class="scm-icon-btn" data-test-action="run-one" title="Run this test" aria-label="Run ${esc(t.name)}" ${this.running ? 'disabled' : ''}>▶</button>
        </li>`;
    }).join('') || '<li class="scm-none">No tests match the filter.</li>';
    const summary = this.container.querySelector('.test-summary');
    if (summary) summary.textContent = this.summary();
  }

  renderDetails() {
    const details = this.container.querySelector('.test-details');
    if (!details) return;
    const t = this.tests.find(x => x.path === this.selected);
    if (!t) {
      details.innerHTML = '<div class="scm-none">Select a test to see its output.</div>';
      return;
    }
    details.innerHTML = `
      <div class="test-details-head">
        <strong>${esc(t.name)}</strong> — ${STATE[t.state].label}${t.durationMs !== null ? ` in ${esc(formatDuration(t.durationMs))}` : ''}
        <button class="scm-btn" data-test-action="open">Open${t.line ? ` at line ${t.line}` : ''}</button>
      </div>
      ${t.message ? `<div class="test-message">${esc(t.message)}</div>` : ''}
      <pre class="test-output">${esc(t.output || (t.state === 'idle' ? 'Not run yet.' : ''))}</pre>`;
  }

  select(testPath) {
    this.selected = testPath;
    this.renderList();
    this.renderDetails();
  }

  async openTest(testPath) {
    const t = this.tests.find(x => x.path === testPath);
    if (!t) return;
    await this.ide.loadFile(t.path);
    if (t.line) this.ide.goToLine(t.line);
  }

  async onClick(e) {
    const actionEl = e.target.closest('[data-test-action]');
    const row = e.target.closest('[data-test]');
    if (!actionEl) {
      if (row) this.select(row.dataset.test);
      return;
    }
    const action = actionEl.dataset.testAction;
    if (action === 'refresh') return this.discover();
    if (action === 'stop') { this.cancelRequested = true; return; }
    if (action === 'open') return this.openTest(this.selected);
    if (action === 'run-one' && row) return this.run([row.dataset.test]);
    if (action === 'run-all') return this.run(this.tests.map(t => t.path));
    if (action === 'run-failed') return this.run(this.tests.filter(t => t.state === 'failed' || t.state === 'error').map(t => t.path));
    return undefined;
  }

  // Run tests one after another so each gets its own result as it finishes.
  async run(paths) {
    if (this.running || !paths.length) return;
    // Tests are programs: Restricted Mode asks first.
    if (typeof this.ide.ensureTrusted === 'function' && !(await this.ide.ensureTrusted('Running tests'))) return;
    // Tests read files from disk: save edits first (each with its revision).
    if (typeof this.ide.saveAllFiles === 'function' && !(await this.ide.saveAllFiles())) {
      alert('Some files could not be saved, so the tests were not run.');
      return;
    }
    this.running = true;
    this.cancelRequested = false;
    for (const t of this.tests) if (paths.includes(t.path)) t.state = 'queued';
    this.render();

    for (const testPath of paths) {
      const t = this.tests.find(x => x.path === testPath);
      if (!t) continue;
      if (this.cancelRequested) { t.state = 'idle'; continue; }
      t.state = 'running';
      this.renderList();
      try {
        const res = await fetch('/api/tests/run', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ folder: this.folder, path: t.path })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || `status ${res.status}`);
        Object.assign(t, { state: data.status, durationMs: data.durationMs, message: data.message, line: data.line, output: data.output });
      } catch (err) {
        Object.assign(t, { state: 'error', message: err.message, output: '' });
      }
      if (this.selected === null && t.state !== 'passed') this.selected = t.path;
      this.renderList();
      if (this.selected === t.path) this.renderDetails();
    }
    for (const t of this.tests) if (t.state === 'queued') t.state = 'idle';
    this.running = false;
    this.render();
    this.reportToProblems();
  }

  reportToProblems() {
    const failed = this.tests.filter(t => t.state === 'failed' || t.state === 'error');
    if (typeof this.ide.setProblemsStatus !== 'function') return;
    if (failed.length) {
      const first = failed[0];
      this.ide.setProblemsStatus(false, `${failed.length} test${failed.length === 1 ? '' : 's'} failed: ${first.name}${first.line ? `:${first.line}` : ''}`, first.message || 'See the Tests tab for the output.', 'Tests', 'Check the failing test! 🔍');
    } else if (this.tests.some(t => t.state === 'passed')) {
      this.ide.setProblemsStatus(true, 'All tests passed.', this.summary(), 'Tests', 'Nice work! 🐾');
    }
  }
}
