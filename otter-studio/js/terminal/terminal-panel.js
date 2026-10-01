// terminal-panel.js - the Terminal tab: persistent PowerShell sessions
// (server/terminal-sessions.mjs), several at once, one tab each. In each,
// `cd`, variables and modules last; output streams while a command runs;
// what you type while a program runs is its input (Otter's `ask`). Up/Down
// recall earlier commands, Ctrl+C stops what is running, `clear` clears it.

const HISTORY_KEY = 'otter-studio-terminal-history';
const MAX_LINES = 5000;
const MAX_TERMINALS = 8;

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const post = async (route, body) => {
  const res = await fetch(route, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw Object.assign(new Error(data.error || `HTTP ${res.status}`), { status: res.status });
  return data;
};
const shortCwd = (cwd) => {
  const parts = String(cwd || '').split(/[\\/]/).filter(Boolean);
  return parts.length > 3 ? `…\\${parts.slice(-2).join('\\')}` : cwd;
};
const folderName = (cwd) => String(cwd || '').split(/[\\/]/).filter(Boolean).pop() || 'shell';

export function createTerminalPanel(ide, panel) {
  const container = panel.querySelector('.terminal-container') || panel;
  container.innerHTML = `
    <div class="term-bar">
      <div class="term-tabs" role="tablist" aria-label="Terminals"></div>
      <button type="button" class="term-btn term-new" data-term="new" title="New terminal" aria-label="New terminal">+</button>
      <span class="term-cwd" title=""></span>
      <span class="term-busy" hidden>running…</span>
      <span class="term-bar-actions">
        <button type="button" class="term-btn" data-term="interrupt" title="Stop what is running (Ctrl+C)" disabled>Stop</button>
        <button type="button" class="term-btn" data-term="clear" title="Clear this terminal (clear)">Clear</button>
        <button type="button" class="term-btn" data-term="restart" title="Close this terminal's shell and start a new one">New shell</button>
      </span>
    </div>
    <div class="term-screens" id="terminalHistory"></div>
    <form class="term-input-row" id="terminalForm" autocomplete="off">
      <span class="term-prompt">PS&gt;</span>
      <input type="text" class="term-input" id="terminalInput" spellcheck="false" placeholder="Type a command and press Enter" aria-label="Terminal command" />
    </form>`;
  const tabsEl = container.querySelector('.term-tabs');
  const screens = container.querySelector('.term-screens');
  const form = container.querySelector('.term-input-row');
  const input = container.querySelector('.term-input');
  const promptEl = container.querySelector('.term-prompt');
  const cwdEl = container.querySelector('.term-cwd');
  const busyEl = container.querySelector('.term-busy');
  const stopBtn = container.querySelector('[data-term="interrupt"]');
  const newBtn = container.querySelector('[data-term="new"]');

  const terminals = [];      // { key, id, screen, busy, alive, cwd, timer, opening, number }
  let active = null;
  let seq = 0;
  let history = [];
  let historyAt = -1;
  try { history = JSON.parse(localStorage.getItem(HISTORY_KEY) || '[]').filter(x => typeof x === 'string').slice(-200); } catch { /* none */ }

  // --- Output ------------------------------------------------------------
  function write(t, text, cls = '') {
    if (!text) return;
    const last = t.screen.lastElementChild;
    // Output that continues a line (a prompt such as "Your name? ") joins it.
    if (last && last.classList.contains('term-out') && last.dataset.cls === cls && !last.textContent.endsWith('\n')) {
      last.textContent += text;
    } else {
      const span = document.createElement('span');
      span.className = `term-out${cls ? ` ${cls}` : ''}`;
      span.dataset.cls = cls;
      span.textContent = text;
      t.screen.appendChild(span);
    }
    while (t.screen.childElementCount > MAX_LINES) t.screen.firstElementChild.remove();
    t.screen.scrollTop = t.screen.scrollHeight;
  }
  function line(t, html) {
    const div = document.createElement('div');
    div.className = 'term-line';
    div.innerHTML = html;
    t.screen.appendChild(div);
    t.screen.scrollTop = t.screen.scrollHeight;
  }

  // --- Rendering -----------------------------------------------------------
  function render() {
    tabsEl.innerHTML = terminals.map(t => `
      <span class="term-tab${t === active ? ' is-active' : ''}${t.busy ? ' is-busy' : ''}${t.id && !t.alive ? ' is-ended' : ''}" role="tab" aria-selected="${t === active}" data-key="${t.key}" title="${esc(t.cwd || 'PowerShell')}">
        <span class="term-tab-name">${t.number}: ${esc(folderName(t.cwd))}</span>
        ${terminals.length > 1 ? `<button type="button" class="term-tab-close" data-close="${t.key}" title="Close this terminal" aria-label="Close terminal ${t.number}">×</button>` : ''}
      </span>`).join('');
    newBtn.disabled = terminals.length >= MAX_TERMINALS;
    for (const t of terminals) t.screen.hidden = t !== active;
    const t = active;
    if (!t) return;
    promptEl.textContent = t.busy ? '›' : `PS ${shortCwd(t.cwd)}>`;
    promptEl.title = t.cwd;
    cwdEl.textContent = t.cwd;
    cwdEl.title = t.cwd;
    busyEl.hidden = !t.busy;
    stopBtn.disabled = !t.busy;
    input.placeholder = !t.alive && t.id ? 'The shell ended. Press Enter for a new one.'
      : t.busy ? 'Input for the running program (Enter sends it)' : 'Type a command and press Enter';
  }

  // --- Terminals -------------------------------------------------------------
  function addTerminal() {
    const screen = document.createElement('div');
    screen.className = 'term-screen';
    screen.setAttribute('role', 'log');
    screen.setAttribute('aria-live', 'polite');
    screen.tabIndex = 0;
    screen.addEventListener('click', () => { if (!window.getSelection()?.toString()) input.focus(); });
    screens.appendChild(screen);
    const t = { key: `t${++seq}`, number: seq, id: null, screen, busy: false, alive: false, cwd: '', timer: null, opening: null };
    terminals.push(t);
    active = t;
    render();
    return t;
  }

  async function ensureSession(t) {
    if (t.id && t.alive) return t.id;
    if (t.opening) return t.opening;
    t.opening = (async () => {
      const folder = ide.currentProjectFolder && !/\.(json|otter-workspace)$/i.test(ide.currentProjectFolder) ? ide.currentProjectFolder : '.';
      const opened = await post('/api/terminal/open', { folder });
      t.id = opened.id;
      t.alive = true;
      t.busy = true;
      t.cwd = opened.cwd;
      line(t, `<span class="term-note">PowerShell - ${esc(opened.cwd)}</span>`);
      render();
      // Ready when its setup line has finished; a command typed before that
      // would otherwise be taken as input for the setup.
      for (let i = 0; i < 300; i++) {
        const data = await (await fetch(`/api/terminal/poll?id=${encodeURIComponent(t.id)}`)).json();
        for (const c of data.chunks || []) write(t, c.text, c.stream === 'err' ? 'term-err' : '');
        t.cwd = data.cwd || t.cwd;
        if (!data.busy || !data.alive) { t.busy = false; t.alive = data.alive !== false; break; }
        await new Promise(r => setTimeout(r, 100));
      }
      render();
      startPolling(t);
      return t.id;
    })();
    try { return await t.opening; } finally { t.opening = null; }
  }

  function startPolling(t) {
    clearTimeout(t.timer);
    const tick = async () => {
      if (!t.id || !terminals.includes(t)) return;
      try {
        const res = await fetch(`/api/terminal/poll?id=${encodeURIComponent(t.id)}`);
        const data = await res.json();
        if (!res.ok) { t.alive = false; t.busy = false; render(); return; }
        for (const c of data.chunks || []) write(t, c.text, c.stream === 'err' ? 'term-err' : '');
        const wasBusy = t.busy;
        t.busy = data.busy;
        t.cwd = data.cwd || t.cwd;
        if (!data.alive) {
          t.alive = false;
          t.busy = false;
          line(t, '<span class="term-note">The shell ended. Press Enter to start a new one.</span>');
          render();
          return;
        }
        // A program's exit code (Invoke-Expression's own success says little
        // about a program it ran), or a PowerShell command that failed.
        if (wasBusy && !data.busy && data.commands > 1 && (data.exitCode || !data.exitOk)) {
          line(t, `<span class="term-note term-failed">${data.exitCode ? `exit code ${esc(data.exitCode)}` : 'the command failed'}</span>`);
        }
        if (wasBusy !== t.busy || t === active) render();
      } catch { /* the next tick tries again */ }
      // Quick while something runs; slower when idle.
      t.timer = setTimeout(tick, t.busy ? 120 : 800);
    };
    tick();
  }

  async function closeTerminal(t) {
    clearTimeout(t.timer);
    if (t.id) { try { await post('/api/terminal/close', { id: t.id }); } catch { /* gone */ } }
    t.screen.remove();
    const at = terminals.indexOf(t);
    terminals.splice(at, 1);
    if (!terminals.length) addTerminal();
    if (active === t) active = terminals[Math.min(at, terminals.length - 1)];
    render();
    input.focus();
  }

  function select(t) {
    active = t;
    render();
    if (!t.id) ensureSession(t).catch(err => line(t, `<span class="term-err">${esc(err.message)}</span>`));
    setTimeout(() => input.focus(), 30);
  }

  // --- Commands --------------------------------------------------------------
  async function run(text, t = active) {
    const cmd = String(text ?? '');
    if (!ide.isTrusted) {
      const proceed = confirm('Restricted Mode: This workspace is untrusted. Running terminal commands here may be unsafe.\n\nTrust this workspace and continue?');
      if (!proceed) return;
      ide.grantWorkspaceTrust();
    }
    if (!t.busy && /^\s*(clear|cls)\s*$/i.test(cmd)) { t.screen.innerHTML = ''; return; }
    try {
      if (!t.alive && t.id) t.id = null;
      await ensureSession(t);
      if (t.busy) {
        write(t, `${cmd}\n`, 'term-typed');
      } else {
        line(t, `<span class="term-prompt-echo">PS ${esc(shortCwd(t.cwd))}&gt;</span> <span class="term-cmd">${esc(cmd)}</span>`);
        if (cmd.trim()) {
          history = [...history.filter(h => h !== cmd), cmd].slice(-200);
          try { localStorage.setItem(HISTORY_KEY, JSON.stringify(history)); } catch { /* not kept */ }
        }
      }
      historyAt = -1;
      t.busy = true;
      render();
      await post('/api/terminal/write', { id: t.id, text: cmd });
      startPolling(t);
    } catch (err) {
      line(t, `<span class="term-err">${esc(err.message)}</span>`);
    }
  }

  async function interrupt(t = active) {
    if (!t?.id || !t.busy) return;
    try { await post('/api/terminal/interrupt', { id: t.id }); } catch (err) { line(t, `<span class="term-err">${esc(err.message)}</span>`); }
  }

  async function restart(t = active) {
    if (t.id) { try { await post('/api/terminal/close', { id: t.id }); } catch { /* gone */ } }
    clearTimeout(t.timer);
    t.id = null;
    t.alive = false;
    t.busy = false;
    t.screen.innerHTML = '';
    await ensureSession(t).catch(err => line(t, `<span class="term-err">${esc(err.message)}</span>`));
  }

  // --- Events ------------------------------------------------------------------
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const text = input.value;
    input.value = '';
    run(text);
  });
  input.addEventListener('keydown', (e) => {
    // Ctrl+C stops the running program - unless text is selected to copy.
    if (e.key === 'c' && e.ctrlKey && active?.busy && input.selectionStart === input.selectionEnd) { e.preventDefault(); interrupt(); return; }
    if (active?.busy) return;
    if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
      if (!history.length) return;
      e.preventDefault();
      if (historyAt === -1) historyAt = history.length;
      historyAt = Math.max(0, Math.min(history.length, historyAt + (e.key === 'ArrowUp' ? -1 : 1)));
      input.value = history[historyAt] ?? '';
    }
  });
  container.querySelector('.term-bar').addEventListener('click', (e) => {
    const close = e.target.closest('[data-close]');
    if (close) { const t = terminals.find(x => x.key === close.dataset.close); if (t) closeTerminal(t); return; }
    const tab = e.target.closest('.term-tab');
    if (tab) { const t = terminals.find(x => x.key === tab.dataset.key); if (t) select(t); return; }
    const b = e.target.closest('[data-term]');
    if (!b || b.disabled) return;
    if (b.dataset.term === 'new') select(addTerminal());
    else if (b.dataset.term === 'interrupt') interrupt();
    else if (b.dataset.term === 'clear') active.screen.innerHTML = '';
    else if (b.dataset.term === 'restart') restart();
  });

  addTerminal();
  return {
    run: (text) => run(text),
    interrupt: () => interrupt(),
    restart: () => restart(),
    newTerminal: () => select(addTerminal()),
    // The tab was opened: start the active terminal's shell, so its prompt and folder show.
    shown() { ensureSession(active).catch(err => line(active, `<span class="term-err">${esc(err.message)}</span>`)); setTimeout(() => input.focus(), 50); },
    get state() { return active; },
    get terminals() { return terminals; },
    input,
    form
  };
}
