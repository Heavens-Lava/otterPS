// debug-controller.js - Studio's side of the Otter debugger.
//
// The debugger itself is src/Otter.Debugger.psm1, running inside the real
// `otter debug` process; Studio's server relays its events and commands
// (serve.mjs /api/debug/*). This module is the workbench around it:
//
//   - the debug toolbar: Continue / Pause, Step Over, Step Into, Step Out,
//     Restart, Stop (F5, F6, F10, F11, Shift+F11, Ctrl+Shift+F5, Shift+F5)
//   - Variables: Locals and Globals, lists and things expandable
//   - Call Stack: innermost first; a frame in this file shows its line
//   - Watch: expressions evaluated each time the program stops (kept)
//   - the debug console: evaluate an expression while paused
//   - breakpoint conditions and log messages (right-click a breakpoint)
//
// ide.js owns the session (start, poll, stop) and calls in here.

import { askText } from '../shell/ask.js';

const WATCH_KEY = 'otter-studio-watches';
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const ICONS = {
  continue: 'M4 3v10l8-5z',
  pause: 'M4.5 3h2.5v10H4.5zM9 3h2.5v10H9z',
  next: 'M2 9a6 6 0 0 1 11-3M13 2.5V6H9.5M7 13h2',
  step: 'M8 2v8M5 7l3 3 3-3M7 13.5h2',
  out: 'M8 10V2M5 5l3-3 3 3M7 13.5h2',
  restart: 'M3 8a5 5 0 1 0 1.6-3.7M3 2.5V5h2.5',
  stop: 'M4 4h8v8H4z'
};
const icon = (name) => `<svg viewBox="0 0 16 16" aria-hidden="true"><path d="${ICONS[name]}"/></svg>`;

function loadWatches() {
  try { const list = JSON.parse(localStorage.getItem(WATCH_KEY) || '[]'); return Array.isArray(list) ? list.filter(x => typeof x === 'string') : []; } catch { return []; }
}
function saveWatches(list) {
  try { localStorage.setItem(WATCH_KEY, JSON.stringify(list)); } catch { /* not kept */ }
}

export function createDebugController(ide) {
  const state = {
    active: false,
    paused: null,          // the last "paused" event while stopped, else null
    watches: loadWatches(),
    watchValues: new Map(),
    details: new Map(),    // breakpoint line -> { condition, log }
    evalSeq: 0,
    pendingConsole: new Map()
  };

  // --- DOM -------------------------------------------------------------
  const runArea = ide.btnDebugProgram?.parentElement;
  const toolbar = document.createElement('div');
  toolbar.className = 'debug-toolbar';
  toolbar.id = 'debugToolbar';
  toolbar.hidden = true;
  toolbar.setAttribute('role', 'toolbar');
  toolbar.setAttribute('aria-label', 'Debug');
  const buttons = [
    ['continue', 'Continue (F5)'], ['pause', 'Pause (F6)'], ['next', 'Step Over (F10)'],
    ['step', 'Step Into (F11)'], ['out', 'Step Out (Shift+F11)'], ['restart', 'Restart (Ctrl+Shift+F5)'], ['stop', 'Stop (Shift+F5)']
  ];
  toolbar.innerHTML = buttons.map(([name, title]) => `<button type="button" class="debug-tb-btn" data-debug="${name}" title="${title}" aria-label="${title}">${icon(name)}</button>`).join('');
  if (runArea && ide.btnDebugContinue) runArea.insertBefore(toolbar, ide.btnDebugContinue);
  toolbar.addEventListener('click', (e) => {
    const b = e.target.closest('[data-debug]');
    if (b && !b.disabled) act(b.dataset.debug);
  });

  const sidebar = document.getElementById('codeRightSidebar');
  const variablesCard = sidebar?.querySelector('.variables-card');
  const stackCard = document.createElement('div');
  stackCard.className = 'panel-card call-stack-card';
  stackCard.innerHTML = `
    <div class="panel-card-header"><div class="header-with-icon"><span class="panel-card-title">Call Stack</span></div></div>
    <div class="call-stack-body"><div class="var-empty-state">Shows where the program is while it is paused.</div></div>`;
  if (variablesCard) variablesCard.insertAdjacentElement('afterend', stackCard);
  const stackBody = stackCard.querySelector('.call-stack-body');

  const watchCard = sidebar?.querySelector('.watch-card');
  const watchBody = watchCard?.querySelector('.watch-body');
  const watchAdd = watchCard?.querySelector('[title="Add Watch"]');
  watchAdd?.addEventListener('click', async () => {
    const expression = await askText({ title: 'Add Watch', message: 'An Otter expression to show each time the program stops, for example: total, price times 2, name is "Ada".', placeholder: 'total' });
    if (!expression || !expression.trim()) return;
    state.watches.push(expression.trim());
    saveWatches(state.watches);
    renderWatches();
    if (state.paused) evaluateWatches();
  });
  watchBody?.addEventListener('click', (e) => {
    const remove = e.target.closest('[data-watch-remove]');
    if (!remove) return;
    state.watches.splice(Number(remove.dataset.watchRemove), 1);
    saveWatches(state.watches);
    renderWatches();
  });

  const outputCard = sidebar?.querySelector('.program-output-card');
  const consoleRow = document.createElement('form');
  consoleRow.className = 'debug-console';
  consoleRow.hidden = true;
  consoleRow.innerHTML = '<span class="debug-console-prompt" aria-hidden="true">›</span><input type="text" class="debug-console-input" placeholder="Evaluate an expression while paused (Enter)" aria-label="Evaluate an expression" spellcheck="false" autocomplete="off" />';
  outputCard?.appendChild(consoleRow);
  const consoleInput = consoleRow.querySelector('input');
  consoleRow.addEventListener('submit', (e) => {
    e.preventDefault();
    const expression = consoleInput.value.trim();
    if (!expression || !state.paused) return;
    const id = `c${++state.evalSeq}`;
    state.pendingConsole.set(id, expression);
    ide.appendProgramOutputLine(`› ${expression}`);
    command('eval', { id, expression });
    consoleInput.value = '';
  });

  // --- Commands ----------------------------------------------------------
  async function command(verb, extra = {}) {
    if (!ide.debugSessionId) return false;
    try {
      const res = await fetch('/api/debug/command', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sessionId: ide.debugSessionId, command: verb, ...extra })
      });
      return res.ok;
    } catch { return false; }
  }

  function act(name) {
    if (name === 'stop') { ide.stopCurrentProgram(); return; }
    if (name === 'restart') { restart(); return; }
    if (!state.active) return;
    if (name === 'pause') { if (!state.paused) command('pause'); return; }
    if (!state.paused) return;
    const verb = name === 'continue' ? 'continue' : name;
    resumed();
    command(verb);
  }

  async function restart() {
    if (!state.active) { ide.startDebugSession(); return; }
    await ide.stopCurrentProgram();
    setTimeout(() => ide.startDebugSession(), 300);
  }

  // --- Rendering ------------------------------------------------------------
  function variableHtml(v) {
    const children = Array.isArray(v.children) ? v.children : null;
    const row = `<span class="dbg-var-name">${esc(v.name)}</span><span class="dbg-var-value" title="${esc(v.type || '')}">${esc(v.value)}</span>`;
    if (!children) return `<div class="dbg-var">${row}</div>`;
    return `<details class="dbg-var dbg-var-group"><summary>${row}</summary><div class="dbg-var-children">${children.length ? children.map(variableHtml).join('') : '<div class="dbg-var dbg-var-empty">empty</div>'}</div></details>`;
  }

  function renderVariables(event) {
    if (!ide.variablesBody) return;
    const scopes = Array.isArray(event.scopes) ? event.scopes : [];
    ide.variablesBody.innerHTML = scopes.map(scope => `
      <details class="dbg-scope" open>
        <summary class="dbg-scope-title">${esc(scope.name)}</summary>
        ${(scope.variables || []).length ? scope.variables.map(variableHtml).join('') : '<div class="dbg-var dbg-var-empty">No variables yet.</div>'}
      </details>`).join('');
  }

  function renderStack(event) {
    const frames = Array.isArray(event.frames) ? event.frames : [];
    stackBody.innerHTML = frames.map((f, i) => `
      <button type="button" class="dbg-frame${i === 0 ? ' is-current' : ''}" data-line="${Number(f.line) || 0}">
        <span class="dbg-frame-name">${esc(f.function)}</span><span class="dbg-frame-line">line ${esc(f.line)}</span>
      </button>`).join('');
  }
  stackBody.addEventListener('click', (e) => {
    const frame = e.target.closest('.dbg-frame');
    if (!frame) return;
    const line = Number(frame.dataset.line);
    const lineEl = ide.codeAreaEl?.querySelector(`.code-line[data-line="${line}"]`);
    lineEl?.scrollIntoView({ block: 'center', behavior: 'smooth' });
  });

  function renderWatches() {
    if (!watchBody) return;
    if (!state.watches.length) {
      watchBody.innerHTML = '<span class="watch-placeholder">Click + to watch an expression while the program is paused.</span>';
      return;
    }
    watchBody.innerHTML = state.watches.map((expr, i) => {
      const result = state.watchValues.get(expr);
      const shown = !state.paused ? '<span class="dbg-watch-idle">not paused</span>'
        : !result ? '<span class="dbg-watch-idle">…</span>'
        : result.error ? `<span class="dbg-watch-error" title="${esc(result.error)}">${esc(result.error)}</span>`
        : `<span class="dbg-var-value" title="${esc(result.type || '')}">${esc(result.value)}</span>`;
      return `<div class="dbg-watch"><span class="dbg-var-name">${esc(expr)}</span>${shown}<button type="button" class="dbg-watch-remove" data-watch-remove="${i}" title="Remove this watch" aria-label="Remove watch ${esc(expr)}">✕</button></div>`;
    }).join('');
  }

  function evaluateWatches() {
    state.watchValues.clear();
    renderWatches();
    state.watches.forEach((expression, i) => command('eval', { id: `w${i}`, expression }));
  }

  function setToolbar() {
    toolbar.hidden = !state.active;
    const paused = Boolean(state.paused);
    toolbar.querySelector('[data-debug="continue"]').hidden = !paused;
    toolbar.querySelector('[data-debug="pause"]').hidden = paused;
    for (const name of ['next', 'step', 'out']) toolbar.querySelector(`[data-debug="${name}"]`).disabled = !paused;
    consoleRow.hidden = !paused;
    document.body.classList.toggle('is-debugging', state.active);
    document.body.classList.toggle('is-debug-paused', paused);
  }

  function resumed() {
    state.paused = null;
    state.watchValues.clear();
    ide.clearDebugPauseState(true);
    stackBody.innerHTML = '<div class="var-empty-state">Running…</div>';
    renderWatches();
    setToolbar();
  }

  // --- From ide.js ----------------------------------------------------------
  function onStart() {
    state.active = true;
    state.paused = null;
    stackBody.innerHTML = '<div class="var-empty-state">Running…</div>';
    renderWatches();
    setToolbar();
  }

  function onPaused(event) {
    state.paused = event;
    renderVariables(event);
    renderStack(event);
    if (event.reason === 'error') {
      ide.appendProgramOutputLine(`Stopped on an error at line ${event.line}: ${event.message || ''}`);
      ide.codeAreaEl?.querySelector(`.code-line[data-line="${event.line}"]`)?.classList.add('has-debug-error');
    }
    setToolbar();
    evaluateWatches();
    consoleInput?.focus({ preventScroll: true });
  }

  function onEvaluated(event) {
    if (event.id && event.id.startsWith('w')) {
      const expr = state.watches[Number(event.id.slice(1))];
      if (expr !== undefined) { state.watchValues.set(expr, event); renderWatches(); }
      return;
    }
    if (state.pendingConsole.has(event.id)) {
      state.pendingConsole.delete(event.id);
      ide.appendProgramOutputLine(event.error ? `  ${event.error}` : `  ${event.value}`, false, event.error ? 'log-error' : 'log-eval');
    }
  }

  function onLog(event) {
    ide.appendProgramOutputLine(`line ${event.line}: ${event.text}`, false, 'log-logpoint');
  }

  function onEnd() {
    state.active = false;
    state.paused = null;
    state.watchValues.clear();
    stackBody.innerHTML = '<div class="var-empty-state">Shows where the program is while it is paused.</div>';
    ide.codeAreaEl?.querySelectorAll('.has-debug-error').forEach(el => el.classList.remove('has-debug-error'));
    renderWatches();
    setToolbar();
  }

  // Breakpoints as the debugger wants them: line, plus condition / log text.
  function breakpointList() {
    return Array.from(ide.debugBreakpoints || []).sort((a, b) => a - b).map(line => ({ line, ...(state.details.get(line) || {}) }));
  }
  function breakpointsChanged() {
    for (const line of [...state.details.keys()]) if (!ide.debugBreakpoints?.has(line)) state.details.delete(line);
    if (state.active) command('breakpoints', { breakpoints: breakpointList() });
  }
  function detailFor(line) { return state.details.get(line) || null; }

  // One dialog for a breakpoint's settings: a condition, a hit count and a
  // log message (a logpoint). Resolves to the settings, or null if cancelled.
  function breakpointDialog(line, current) {
    return new Promise((resolve) => {
      const backdrop = document.createElement('div');
      backdrop.className = 'modal-backdrop ask-backdrop';
      backdrop.style.display = 'flex';
      backdrop.innerHTML = `
        <form class="modal-dialog ask-dialog bp-dialog" role="dialog" aria-modal="true" aria-labelledby="bpTitle" novalidate>
          <div class="modal-header">
            <div class="modal-title-wrap">
              <h2 class="modal-title" id="bpTitle">Breakpoint on line ${line}</h2>
              <p class="modal-subtitle">Leave a field empty to not use it. With all three empty, it always stops.</p>
            </div>
            <button type="button" class="modal-close-btn" data-bp-cancel title="Cancel (Esc)">✕</button>
          </div>
          <div class="modal-body bp-fields">
            <label class="bp-field"><span class="bp-label">Condition</span>
              <input class="config-input" name="condition" placeholder="price is 20" spellcheck="false" autocomplete="off" />
              <span class="bp-hint">Stop only when this Otter condition is true.</span></label>
            <label class="bp-field"><span class="bp-label">Hit count</span>
              <input class="config-input" name="hits" placeholder="5   or   >= 5   or   % 3" spellcheck="false" autocomplete="off" />
              <span class="bp-hint">5 stops at the 5th hit, &gt;= 5 from then on, % 3 every third.</span></label>
            <label class="bp-field"><span class="bp-label">Log message</span>
              <input class="config-input" name="log" placeholder="total is {total}" spellcheck="false" autocomplete="off" />
              <span class="bp-hint">Write this instead of stopping; {expressions} are filled in.</span></label>
            <div class="ask-error" role="alert" hidden></div>
          </div>
          <div class="modal-footer">
            <div class="modal-footer-left"><button type="button" class="btn-modal-cancel" data-bp-remove>Remove breakpoint</button></div>
            <div class="modal-footer-right">
              <button type="button" class="btn-modal-cancel" data-bp-cancel>Cancel</button>
              <button type="submit" class="btn-modal-primary">Save</button>
            </div>
          </div>
        </form>`;
      const form = backdrop.querySelector('form');
      for (const key of ['condition', 'hits', 'log']) form.elements[key].value = current[key] || '';
      const error = backdrop.querySelector('.ask-error');
      const finish = (result) => { backdrop.remove(); document.removeEventListener('keydown', onKey, true); resolve(result); };
      const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); finish(null); } };
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        const hits = form.elements.hits.value.trim();
        if (hits && !/^(?:%|>=|>|==?)?\s*\d+$/.test(hits)) {
          error.textContent = 'A hit count is a number, >= a number, > a number, or % a number (for example 5, >= 5, % 3).';
          error.hidden = false;
          form.elements.hits.focus();
          return;
        }
        finish({ condition: form.elements.condition.value.trim(), hits, log: form.elements.log.value.trim() });
      });
      backdrop.querySelectorAll('[data-bp-cancel]').forEach(b => b.addEventListener('click', () => finish(null)));
      backdrop.querySelector('[data-bp-remove]').addEventListener('click', () => finish({ remove: true }));
      backdrop.addEventListener('mousedown', (e) => { if (e.target === backdrop) finish(null); });
      document.addEventListener('keydown', onKey, true);
      document.body.appendChild(backdrop);
      setTimeout(() => form.elements.condition.focus(), 20);
    });
  }

  async function editBreakpoint(line) {
    const result = await breakpointDialog(line, state.details.get(line) || {});
    if (result === null) return;
    if (result.remove) {
      state.details.delete(line);
      ide.debugBreakpoints.delete(line);
    } else {
      const detail = {};
      for (const key of ['condition', 'hits', 'log']) if (result[key]) detail[key] = result[key];
      if (Object.keys(detail).length) state.details.set(line, detail); else state.details.delete(line);
      ide.debugBreakpoints.add(line);
    }
    ide.renderGutter((ide.currentCode || '').split('\n').length);
    breakpointsChanged();
  }

  // F-keys while a session is on (before ide.js's own F5 = Run).
  window.addEventListener('keydown', (e) => {
    if (!state.active) return;
    let name = null;
    if (e.key === 'F5' && e.ctrlKey && e.shiftKey) name = 'restart';
    else if (e.key === 'F5' && e.shiftKey) name = 'stop';
    else if (e.key === 'F5' && !e.ctrlKey && !e.altKey) name = 'continue';
    else if (e.key === 'F6') name = 'pause';
    else if (e.key === 'F10') name = 'next';
    else if (e.key === 'F11' && e.shiftKey) name = 'out';
    else if (e.key === 'F11') name = 'step';
    if (!name) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    act(name);
  }, true);

  renderWatches();
  setToolbar();
  return { onStart, onPaused, onEvaluated, onLog, onEnd, breakpointList, breakpointsChanged, editBreakpoint, detailFor, command, act, state };
}
