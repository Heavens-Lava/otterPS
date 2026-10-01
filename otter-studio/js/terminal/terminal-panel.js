// terminal-panel.js - the Terminal tab: a persistent PowerShell session
// (server/terminal-sessions.mjs). `cd`, variables and modules last for the
// session; output streams while a command runs; what you type while a
// program runs is its input (Otter's `ask`). Up/Down recall earlier commands,
// Ctrl+C stops what is running, `clear` clears the panel.

const HISTORY_KEY = 'otter-studio-terminal-history';
const MAX_LINES = 5000;

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const post = async (route, body) => {
  const res = await fetch(route, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw Object.assign(new Error(data.error || `HTTP ${res.status}`), { status: res.status });
  return data;
};

export function createTerminalPanel(ide, panel) {
  const container = panel.querySelector('.terminal-container') || panel;
  container.innerHTML = `
    <div class="term-bar">
      <span class="term-title">Terminal</span>
      <span class="term-cwd" title=""></span>
      <span class="term-busy" hidden>running…</span>
      <span class="term-bar-actions">
        <button type="button" class="term-btn" data-term="interrupt" title="Stop what is running (Ctrl+C)" disabled>Stop</button>
        <button type="button" class="term-btn" data-term="clear" title="Clear the panel (clear)">Clear</button>
        <button type="button" class="term-btn" data-term="restart" title="Close this shell and start a new one">New shell</button>
      </span>
    </div>
    <div class="term-screen" id="terminalHistory" role="log" aria-live="polite" tabindex="0"></div>
    <form class="term-input-row" id="terminalForm" autocomplete="off">
      <span class="term-prompt">PS&gt;</span>
      <input type="text" class="term-input" id="terminalInput" spellcheck="false" placeholder="Type a command and press Enter" aria-label="Terminal command" />
    </form>`;
  const screen = container.querySelector('.term-screen');
  const form = container.querySelector('.term-input-row');
  const input = container.querySelector('.term-input');
  const promptEl = container.querySelector('.term-prompt');
  const cwdEl = container.querySelector('.term-cwd');
  const busyEl = container.querySelector('.term-busy');
  const stopBtn = container.querySelector('[data-term="interrupt"]');

  const state = { id: null, opening: null, busy: false, alive: false, cwd: '', timer: null, history: [], historyAt: -1 };
  try { state.history = JSON.parse(localStorage.getItem(HISTORY_KEY) || '[]').filter(x => typeof x === 'string').slice(-200); } catch { /* none */ }

  function write(text, cls = '') {
    if (!text) return;
    const last = screen.lastElementChild;
    // Output that continues a line (a prompt such as "Your name? ") joins it.
    if (last && last.classList.contains('term-out') && last.dataset.cls === cls && !last.textContent.endsWith('\n')) {
      last.textContent += text;
    } else {
      const span = document.createElement('span');
      span.className = `term-out${cls ? ` ${cls}` : ''}`;
      span.dataset.cls = cls;
      span.textContent = text;
      screen.appendChild(span);
    }
    while (screen.childElementCount > MAX_LINES) screen.firstElementChild.remove();
    screen.scrollTop = screen.scrollHeight;
  }
  function line(html, cls) {
    const div = document.createElement('div');
    div.className = cls;
    div.innerHTML = html;
    screen.appendChild(div);
    screen.scrollTop = screen.scrollHeight;
  }

  function shortCwd(cwd) {
    const parts = String(cwd || '').split(/[\\/]/).filter(Boolean);
    return parts.length > 3 ? `…\\${parts.slice(-2).join('\\')}` : cwd;
  }
  function render() {
    promptEl.textContent = state.busy ? '›' : `PS ${shortCwd(state.cwd)}>`;
    promptEl.title = state.cwd;
    cwdEl.textContent = state.cwd;
    cwdEl.title = state.cwd;
    busyEl.hidden = !state.busy;
    stopBtn.disabled = !state.busy;
    input.placeholder = !state.alive && state.id ? 'The shell ended. Press Enter for a new one.'
      : state.busy ? 'Input for the running program (Enter sends it)' : 'Type a command and press Enter';
  }

  async function ensureSession() {
    if (state.id && state.alive) return state.id;
    if (state.opening) return state.opening;
    state.opening = (async () => {
      const folder = ide.currentProjectFolder && !/\.(json|otter-workspace)$/i.test(ide.currentProjectFolder) ? ide.currentProjectFolder : '.';
      const opened = await post('/api/terminal/open', { folder });
      state.id = opened.id;
      state.alive = true;
      state.busy = true;
      state.cwd = opened.cwd;
      line(`<span class="term-note">PowerShell - ${esc(opened.cwd)}</span>`, 'term-line');
      render();
      // Ready when its setup line has finished; a command typed before that
      // would otherwise be taken as input for the setup.
      for (let i = 0; i < 300; i++) {
        const data = await (await fetch(`/api/terminal/poll?id=${encodeURIComponent(state.id)}`)).json();
        for (const c of data.chunks || []) write(c.text, c.stream === 'err' ? 'term-err' : '');
        state.cwd = data.cwd || state.cwd;
        if (!data.busy || !data.alive) { state.busy = false; state.alive = data.alive !== false; break; }
        await new Promise(r => setTimeout(r, 100));
      }
      render();
      startPolling();
      return state.id;
    })();
    try { return await state.opening; } finally { state.opening = null; }
  }

  function startPolling() {
    clearTimeout(state.timer);
    const tick = async () => {
      if (!state.id) return;
      try {
        const res = await fetch(`/api/terminal/poll?id=${encodeURIComponent(state.id)}`);
        const data = await res.json();
        if (!res.ok) { state.alive = false; state.busy = false; render(); return; }
        for (const c of data.chunks || []) write(c.text, c.stream === 'err' ? 'term-err' : '');
        const wasBusy = state.busy;
        state.busy = data.busy;
        state.cwd = data.cwd || state.cwd;
        if (!data.alive) {
          state.alive = false;
          state.busy = false;
          line('<span class="term-note">The shell ended. Press Enter to start a new one.</span>', 'term-line');
          render();
          return;
        }
        // A program's exit code (Invoke-Expression's own success says little
        // about a program it ran), or a PowerShell command that failed.
        if (wasBusy && !data.busy && data.commands > 1 && (data.exitCode || !data.exitOk)) {
          line(`<span class="term-note term-failed">${data.exitCode ? `exit code ${esc(data.exitCode)}` : 'the command failed'}</span>`, 'term-line');
        }
        render();
      } catch { /* the next tick tries again */ }
      // Quick while something runs; slower when idle.
      state.timer = setTimeout(tick, state.busy ? 120 : 600);
    };
    tick();
  }

  async function run(text) {
    const cmd = String(text ?? '');
    if (!ide.isTrusted) {
      const proceed = confirm('Restricted Mode: This workspace is untrusted. Running terminal commands here may be unsafe.\n\nTrust this workspace and continue?');
      if (!proceed) return;
      ide.grantWorkspaceTrust();
    }
    if (!state.busy && /^\s*(clear|cls)\s*$/i.test(cmd)) { screen.innerHTML = ''; return; }
    try {
      if (!state.alive && state.id) { state.id = null; }
      await ensureSession();
      const asInput = state.busy;
      if (asInput) {
        write(`${cmd}\n`, 'term-typed');
      } else {
        line(`<span class="term-prompt-echo">PS ${esc(shortCwd(state.cwd))}&gt;</span> <span class="term-cmd">${esc(cmd)}</span>`, 'term-line');
        if (cmd.trim()) {
          state.history = [...state.history.filter(h => h !== cmd), cmd].slice(-200);
          try { localStorage.setItem(HISTORY_KEY, JSON.stringify(state.history)); } catch { /* not kept */ }
        }
      }
      state.historyAt = -1;
      state.busy = true;
      render();
      await post('/api/terminal/write', { id: state.id, text: cmd });
      startPolling();
    } catch (err) {
      line(`<span class="term-err">${esc(err.message)}</span>`, 'term-line');
    }
  }

  async function interrupt() {
    if (!state.id || !state.busy) return;
    try { await post('/api/terminal/interrupt', { id: state.id }); } catch (err) { line(`<span class="term-err">${esc(err.message)}</span>`, 'term-line'); }
  }

  async function restart() {
    if (state.id) { try { await post('/api/terminal/close', { id: state.id }); } catch { /* gone */ } }
    clearTimeout(state.timer);
    state.id = null;
    state.alive = false;
    state.busy = false;
    screen.innerHTML = '';
    await ensureSession().catch(err => line(`<span class="term-err">${esc(err.message)}</span>`, 'term-line'));
  }

  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const text = input.value;
    input.value = '';
    run(text);
  });
  input.addEventListener('keydown', (e) => {
    // Ctrl+C stops the running program - unless text is selected to copy.
    if (e.key === 'c' && e.ctrlKey && state.busy && input.selectionStart === input.selectionEnd) { e.preventDefault(); interrupt(); return; }
    if (state.busy) return;
    if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
      if (!state.history.length) return;
      e.preventDefault();
      if (state.historyAt === -1) state.historyAt = state.history.length;
      state.historyAt = Math.max(0, Math.min(state.history.length, state.historyAt + (e.key === 'ArrowUp' ? -1 : 1)));
      input.value = state.history[state.historyAt] ?? '';
    }
  });
  container.querySelector('.term-bar-actions').addEventListener('click', (e) => {
    const b = e.target.closest('[data-term]');
    if (!b) return;
    if (b.dataset.term === 'interrupt') interrupt();
    else if (b.dataset.term === 'clear') screen.innerHTML = '';
    else if (b.dataset.term === 'restart') restart();
  });
  screen.addEventListener('click', () => { if (!window.getSelection()?.toString()) input.focus(); });

  render();
  return {
    run,
    interrupt,
    restart,
    // The tab was opened: start the shell, so its prompt and folder show.
    shown() { ensureSession().catch(err => line(`<span class="term-err">${esc(err.message)}</span>`, 'term-line')); setTimeout(() => input.focus(), 50); },
    get state() { return state; },
    input,
    form
  };
}
