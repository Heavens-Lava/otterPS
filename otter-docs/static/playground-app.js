(() => {
  'use strict';

  const EXAMPLES = [
    {
      id: 'hello',
      title: '1. Hello Otter',
      stdin: '',
      code: [
        '# Write Otter 1.0.1 right in your browser!',
        'name is "Otter"',
        'say "Hello," name',
        '',
        'to greet person',
        '    say "Welcome to Otter," person',
        '.',
        '',
        'greet "Ada"',
        'greet "Developer"'
      ].join('\n')
    },
    {
      id: 'conditions',
      title: '2. Conditions & Functions',
      stdin: '',
      code: [
        'to classify latencyMs',
        '    if latencyMs is at most 50',
        '        return "Healthy"',
        '    otherwise if latencyMs is at most 200',
        '        return "Degraded"',
        '    otherwise',
        '        return "Slow"',
        '    .',
        '.',
        '',
        'samples are',
        '    18',
        '    120',
        '    420',
        '.',
        '',
        'each ms in samples',
        '    status is classify ms',
        '    say ms "ms ->" status',
        '.'
      ].join('\n')
    },
    {
      id: 'lists',
      title: '3. Lists, Sorting & Loops',
      stdin: '',
      code: [
        'languages are',
        '    "Otter"',
        '    "C#"',
        '    "Rust"',
        '.',
        '',
        'add "WebAssembly" to languages',
        'sort languages',
        'say "Total:" length of languages',
        'say "First:" first of languages "Last:" last of languages',
        '',
        'rank is 1',
        'each lang in languages',
        '    say rank lang',
        '    rank is rank plus 1',
        '.'
      ].join('\n')
    },
    {
      id: 'objects',
      title: '4. Objects & Custom Types',
      stdin: '',
      code: [
        'a Service has',
        '    name',
        '    port',
        '    healthy',
        '.',
        '',
        'orders is a Service with name "Orders API", port 8082, healthy true',
        'say name of orders "on port" port of orders "healthy:" healthy of orders'
      ].join('\n')
    },
    {
      id: 'json-errors',
      title: '5. JSON & Error Handling (try/otherwise)',
      stdin: '',
      code: [
        'payload has',
        '    app is "Otter Pulse"',
        '    version is "1.0.1"',
        '    checks is 5',
        '.',
        '',
        'convert payload to json into encoded',
        'say "JSON:" encoded',
        '',
        'convert encoded from json into decoded',
        'say "App:" app of decoded "Checks:" checks of decoded',
        '',
        'try',
        '    fail with "Simulated probe timeout"',
        'otherwise into reason',
        '    say "Recovered cleanly:" reason',
        '.'
      ].join('\n')
    },
    {
      id: 'ask-input',
      title: '6. Interactive Input (ask)',
      stdin: 'Ada\n3',
      code: [
        '# Open "Program Input (ask)" below to edit the lines supplied to ask.',
        'ask "Your name: " and call it visitor',
        'ask "How many greetings? " and call it repeatCount',
        '',
        'count from 1 to repeatCount as n',
        '    say n "Hello," visitor',
        '.'
      ].join('\n')
    },
    {
      id: 'otter-pulse',
      title: '7. Otter Pulse Health Score Logic',
      stdin: '',
      code: [
        '# Real clamping & telemetry scoring pattern used in Flagship App #1 (Otter Pulse)',
        'to clamp val low high',
        '    if val is less than low',
        '        return low',
        '    .',
        '    if val is greater than high',
        '        return high',
        '    .',
        '    return val',
        '.',
        '',
        'to scoreProbe latencyMs ok',
        '    if ok is false',
        '        return 0',
        '    .',
        '    penalty is latencyMs divided by 5',
        '    rawScore is 100 minus penalty',
        '    return clamp rawScore 10 100',
        '.',
        '',
        's1 is scoreProbe 21 true',
        's2 is scoreProbe 180 true',
        's3 is scoreProbe 300 false',
        'say "Live Orders API (21ms):" s1 "/ 100"',
        'say "Billing Worker (180ms):" s2 "/ 100"',
        'say "Down Service (503):" s3 "/ 100"'
      ].join('\n')
    },
    {
      id: 'sandbox-limit',
      title: '8. Sandbox Safety Demo (Loop Guard)',
      stdin: '',
      code: [
        '# Infinite loops are automatically stopped by the WebAssembly safety budget',
        '# (or immediately if you click Stop).',
        'say "Starting guarded loop..."',
        'ticks is 0',
        'while true',
        '    ticks is ticks plus 1',
        '.'
      ].join('\n')
    }
  ];

  const WORKER_URL = '/static/playground/otter-worker.mjs';
  const MAX_STEPS = 250000;
  const TIMEOUT_MS = 3000;
  const MAX_OUTPUT_BYTES = 65536;

  const KEYWORDS_RE = /\b(otherwise if|for each|is at least|is at most|is greater than|is less than|is not|divided by|length of|random number|random item|set random seed|start timer|elapsed milliseconds|from json|to json|from csv|to csv|and call it|fail with|into|say|ask|if|otherwise|while|repeat|times|count|from|to|as|each|in|return|stop|try|is|are|has|of|plus|minus|times|add|remove|sort|reverse|replace|with|split|by|join|find|convert|query|where|set|get|key|at|true|false|gone|and|or|not|a|an)\b/g;

  function escapeHtml(s) {
    return String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
  }

  function highlightOtter(source) {
    const lines = String(source || '').split('\n');
    return lines.map((line) => {
      const trimmed = line.trim();
      if (trimmed === '.') {
        return line.replace('.', '<span class="ot-dot">.</span>');
      }
      // Split comment outside quotes
      let inStr = false;
      let commentIdx = -1;
      for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (ch === '"' && line[i - 1] !== '\\') inStr = !inStr;
        if (!inStr && ch === '#') {
          commentIdx = i;
          break;
        }
      }
      const codePart = commentIdx >= 0 ? line.slice(0, commentIdx) : line;
      const commentPart = commentIdx >= 0 ? line.slice(commentIdx) : '';

      // Tokenize strings first so keywords inside quotes aren't colored
      let out = '';
      const strRe = /"(?:[^"\\]|\\.)*"/g;
      let last = 0;
      let m;
      while ((m = strRe.exec(codePart)) !== null) {
        out += highlightSegment(codePart.slice(last, m.index));
        out += `<span class="ot-str">${escapeHtml(m[0])}</span>`;
        last = m.index + m[0].length;
      }
      out += highlightSegment(codePart.slice(last));
      if (commentPart) {
        out += `<span class="ot-com">${escapeHtml(commentPart)}</span>`;
      }
      return out;
    }).join('\n') + '\n';
  }

  function highlightSegment(seg) {
    let escaped = escapeHtml(seg);
    escaped = escaped.replace(KEYWORDS_RE, '<span class="ot-kw">$1</span>');
    escaped = escaped.replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="ot-num">$1</span>');
    return escaped;
  }

  function encodeShareHash(code, stdin) {
    const payload = JSON.stringify({ code, stdin });
    const bytes = new TextEncoder().encode(payload);
    let bin = '';
    bytes.forEach((b) => { bin += String.fromCharCode(b); });
    return '#code=' + encodeURIComponent(btoa(bin));
  }

  function decodeShareHash() {
    const hash = window.location.hash || '';
    if (hash.startsWith('#example=')) {
      const id = decodeURIComponent(hash.slice('#example='.length));
      const found = EXAMPLES.find((ex) => ex.id === id);
      if (found) return { exampleId: found.id, code: found.code, stdin: found.stdin };
    }
    if (hash.startsWith('#code=')) {
      try {
        const b64 = decodeURIComponent(hash.slice('#code='.length));
        if (b64.length > 24000) return null;
        const bin = atob(b64);
        const bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
        const parsed = JSON.parse(new TextDecoder().decode(bytes));
        if (typeof parsed.code === 'string') {
          return { exampleId: '', code: parsed.code, stdin: typeof parsed.stdin === 'string' ? parsed.stdin : '' };
        }
      } catch {
        return null;
      }
    }
    return null;
  }

  function mountPlayground() {
    const mount = document.getElementById('playgroundMount');
    if (!mount) return;

    if (typeof WebAssembly === 'undefined' || typeof Worker === 'undefined') {
      mount.innerHTML = '<div class="pg-diag-card"><strong>WebAssembly or Web Workers are unavailable in this browser.</strong> Please use a modern version of Chrome, Edge, Firefox, or Safari, or <a href="/download/">download the Otter CLI</a>.</div>';
      return;
    }

    const initial = decodeShareHash() || { exampleId: EXAMPLES[0].id, code: EXAMPLES[0].code, stdin: EXAMPLES[0].stdin };
    let currentExampleId = initial.exampleId || EXAMPLES[0].id;

    mount.innerHTML = `
      <div class="pg-app" data-pg-ready="false">
        <div class="pg-toolbar" role="toolbar" aria-label="Playground controls">
          <div class="pg-toolbar-group">
            <label class="pg-label" for="pgExampleSelect">Example</label>
            <select id="pgExampleSelect" class="pg-select" aria-label="Load Otter example">
              ${EXAMPLES.map((ex) => `<option value="${ex.id}"${ex.id === currentExampleId ? ' selected' : ''}>${escapeHtml(ex.title)}</option>`).join('')}
            </select>
          </div>
          <div class="pg-toolbar-group">
            <button id="pgRunBtn" type="button" class="pg-btn pg-btn-primary" disabled aria-keyshortcuts="Control+Enter Meta+Enter">&#9654; Run</button>
            <button id="pgStopBtn" type="button" class="pg-btn pg-btn-danger" disabled>&#9632; Stop</button>
            <button id="pgResetBtn" type="button" class="pg-btn">Reset</button>
            <button id="pgCopyBtn" type="button" class="pg-btn">Copy Code</button>
            <button id="pgShareBtn" type="button" class="pg-btn">Share Link</button>
          </div>
        </div>

        <div class="pg-status-bar" role="status" aria-live="polite">
          <span class="pg-status-pill">
            <span id="pgDot" class="pg-dot pg-dot-loading" aria-hidden="true"></span>
            <span id="pgStatusText">Loading Otter 1.0.1 WebAssembly runtime...</span>
          </span>
          <span id="pgMetricsText">Sandbox: 250k steps · 3s timeout · 64 KB output · client-side only</span>
        </div>

        <div class="pg-workspace">
          <section class="pg-pane" aria-label="Otter code editor">
            <div class="pg-pane-head">
              <span>program.ot</span>
              <span class="pg-pane-meta">Ctrl/Cmd + Enter to Run · Tab indents</span>
            </div>
            <div class="pg-editor-wrap">
              <pre id="pgGutter" class="pg-gutter" aria-hidden="true">1</pre>
              <div class="pg-code-stage">
                <pre id="pgHighlight" class="pg-highlight" aria-hidden="true"></pre>
                <textarea id="pgEditor" class="pg-textarea" spellcheck="false" autocomplete="off" autocapitalize="off" aria-label="Otter source code editor"></textarea>
              </div>
            </div>
            <details id="pgStdinDetails" class="pg-stdin-drawer">
              <summary>Program Input (<code>ask</code> lines — one answer per line)</summary>
              <textarea id="pgStdin" class="pg-stdin-input" placeholder="Optional input lines for programs using ask..." aria-label="Program standard input lines"></textarea>
            </details>
          </section>

          <section class="pg-pane" aria-label="Console output and diagnostics">
            <div class="pg-pane-head">
              <span>Console Output</span>
              <span id="pgRunMeta" class="pg-pane-meta">Idle</span>
            </div>
            <div class="pg-output-body">
              <pre id="pgConsole" class="pg-console pg-console-empty" aria-live="polite" tabindex="0">Click Run (or press Ctrl/Cmd + Enter) to execute your Otter program.</pre>
              <div id="pgDiagnostics" class="pg-diagnostics" aria-live="polite">
                <div class="pg-diag-heading">Diagnostics</div>
                <div class="pg-diag-ok">No syntax or runtime issues detected.</div>
              </div>
            </div>
          </section>
        </div>

        <div class="pg-footer-note">
          <span>
            <strong>Real Otter interpreter in your browser:</strong> Runs the canonical C# <code>Otter.Language</code> + <code>Otter.Runtime</code> WebAssembly engine inside an isolated Web Worker. Filesystem, shell, database, and network commands are disabled in the browser sandbox.
          </span>
          <span>
            Ready to build locally? <a href="/download/">Download Otter</a> · <a href="/otter-pulse/">Otter Pulse Tutorial</a> · <a href="/library/">Component Library</a>
          </span>
        </div>
      </div>
    `;

    const appEl = mount.querySelector('.pg-app');
    const selectEl = document.getElementById('pgExampleSelect');
    const runBtn = document.getElementById('pgRunBtn');
    const stopBtn = document.getElementById('pgStopBtn');
    const resetBtn = document.getElementById('pgResetBtn');
    const copyBtn = document.getElementById('pgCopyBtn');
    const shareBtn = document.getElementById('pgShareBtn');
    const dotEl = document.getElementById('pgDot');
    const statusText = document.getElementById('pgStatusText');
    const runMeta = document.getElementById('pgRunMeta');
    const gutterEl = document.getElementById('pgGutter');
    const highlightEl = document.getElementById('pgHighlight');
    const editorEl = document.getElementById('pgEditor');
    const stdinDetails = document.getElementById('pgStdinDetails');
    const stdinEl = document.getElementById('pgStdin');
    const consoleEl = document.getElementById('pgConsole');
    const diagEl = document.getElementById('pgDiagnostics');

    editorEl.value = initial.code;
    stdinEl.value = initial.stdin || '';
    if (initial.stdin) stdinDetails.open = true;

    function syncEditorVisuals() {
      const text = editorEl.value;
      const lineCount = Math.max(1, text.split('\n').length);
      let nums = '';
      for (let i = 1; i <= lineCount; i++) nums += i + (i < lineCount ? '\n' : '');
      gutterEl.textContent = nums;
      highlightEl.innerHTML = highlightOtter(text);
      syncScroll();
    }

    function syncScroll() {
      highlightEl.scrollTop = editorEl.scrollTop;
      highlightEl.scrollLeft = editorEl.scrollLeft;
      gutterEl.scrollTop = editorEl.scrollTop;
    }

    function setStatus(state, text) {
      dotEl.className = `pg-dot pg-dot-${state}`;
      statusText.textContent = text;
    }

    function renderDiagnostics(diagnostics) {
      if (!diagnostics || diagnostics.length === 0) {
        diagEl.innerHTML = '<div class="pg-diag-heading">Diagnostics</div><div class="pg-diag-ok">No syntax or runtime issues detected.</div>';
        return;
      }
      const cards = diagnostics.map((d) => {
        const loc = `Line ${d.line || 1}${d.code ? ` · ${escapeHtml(d.code)}` : ''}`;
        const sug = d.suggestion ? `<div class="pg-diag-suggestion">Try: ${escapeHtml(d.suggestion)}</div>` : '';
        return `<div class="pg-diag-card"><div class="pg-diag-loc">${loc}</div><div>${escapeHtml(d.message)}</div>${sug}</div>`;
      }).join('');
      diagEl.innerHTML = `<div class="pg-diag-heading">Diagnostics (${diagnostics.length})</div>${cards}`;
    }

    let worker = null;
    let workerReady = false;
    let runtimeVersion = 'Otter 1.0.1 (WebAssembly)';
    let nextMsgId = 1;
    let activeRunId = null;
    let watchdogTimer = null;
    const pending = new Map();

    function spawnWorker() {
      if (worker) {
        try { worker.terminate(); } catch {}
      }
      pending.clear();
      workerReady = false;
      activeRunId = null;
      appEl.dataset.pgReady = 'false';
      runBtn.disabled = true;
      stopBtn.disabled = true;
      setStatus('loading', 'Loading Otter 1.0.1 WebAssembly runtime...');

      worker = new Worker(WORKER_URL, { type: 'module' });
      worker.onmessage = (event) => {
        const msg = event.data || {};
        const handler = pending.get(msg.id);
        if (!handler) return;
        pending.delete(msg.id);
        if (msg.type === 'error') handler.reject(new Error(msg.error || 'Worker error'));
        else handler.resolve(msg);
      };
      worker.onerror = (event) => {
        const err = new Error(event.message || 'WebAssembly worker failed to load.');
        for (const [, h] of pending) h.reject(err);
        pending.clear();
        setStatus('error', err.message);
      };

      sendWorker({ type: 'init' })
        .then((res) => {
          workerReady = true;
          runtimeVersion = res.version || runtimeVersion;
          appEl.dataset.pgReady = 'true';
          runBtn.disabled = false;
          setStatus('ready', `Ready · ${runtimeVersion}`);
        })
        .catch((err) => {
          setStatus('error', `Failed to initialize WebAssembly runtime: ${err.message}`);
        });
    }

    function sendWorker(msg) {
      return new Promise((resolve, reject) => {
        const id = nextMsgId++;
        pending.set(id, { resolve, reject });
        worker.postMessage({ ...msg, id });
      });
    }

    async function executeProgram() {
      if (!workerReady || activeRunId !== null) return;
      const source = editorEl.value;
      const stdin = stdinEl.value;
      const runToken = nextMsgId;
      activeRunId = runToken;
      runBtn.disabled = true;
      stopBtn.disabled = false;
      setStatus('running', 'Running Otter program...');
      runMeta.textContent = 'Running...';

      clearTimeout(watchdogTimer);
      watchdogTimer = setTimeout(() => {
        if (activeRunId === runToken) {
          stopExecution('Execution hard-stopped after watchdog timeout.');
        }
      }, TIMEOUT_MS + 1500);

      try {
        const res = await sendWorker({
          type: 'run',
          source,
          stdin,
          maxSteps: MAX_STEPS,
          timeoutMs: TIMEOUT_MS,
          maxOutputBytes: MAX_OUTPUT_BYTES
        });
        if (activeRunId !== runToken) return;
        clearTimeout(watchdogTimer);
        activeRunId = null;
        runBtn.disabled = false;
        stopBtn.disabled = true;

        const payload = res.payload || {};
        const out = payload.stdout || '';
        if (out.length > 0) {
          consoleEl.classList.remove('pg-console-empty');
          consoleEl.textContent = out;
        } else {
          consoleEl.classList.add('pg-console-empty');
          consoleEl.textContent = payload.ok
            ? '(Program finished with no output)'
            : '(No output before error)';
        }

        renderDiagnostics(payload.diagnostics || []);
        const ms = typeof payload.elapsedMs === 'number' ? `${payload.elapsedMs.toFixed(1)} ms` : '';
        const steps = typeof payload.stepsExecuted === 'number' ? `${payload.stepsExecuted.toLocaleString()} steps` : '';
        runMeta.textContent = [ms, steps].filter(Boolean).join(' · ') || 'Done';

        if (payload.ok) {
          setStatus('ready', `Finished cleanly · ${runtimeVersion}`);
        } else {
          setStatus('error', `Stopped with ${(payload.diagnostics || []).length} diagnostic(s)`);
        }
      } catch (err) {
        if (activeRunId !== runToken) return;
        clearTimeout(watchdogTimer);
        activeRunId = null;
        runBtn.disabled = false;
        stopBtn.disabled = true;
        setStatus('error', `Execution error: ${err.message}`);
      }
    }

    function stopExecution(reason = 'Stopped by user.') {
      clearTimeout(watchdogTimer);
      activeRunId = null;
      renderDiagnostics([{ line: 1, code: 'OTTER_PLAYGROUND_STOPPED', message: reason, suggestion: 'Click Run to execute again.' }]);
      runMeta.textContent = 'Stopped';
      spawnWorker();
    }

    // Live debounced syntax check while typing
    let checkTimer = null;
    function scheduleLiveCheck() {
      clearTimeout(checkTimer);
      checkTimer = setTimeout(async () => {
        if (!workerReady || activeRunId !== null) return;
        try {
          const res = await sendWorker({ type: 'check', source: editorEl.value });
          if (activeRunId === null && res && res.payload) {
            renderDiagnostics(res.payload.diagnostics || []);
          }
        } catch {
          // ignore transient check failures
        }
      }, 380);
    }

    editorEl.addEventListener('input', () => {
      syncEditorVisuals();
      scheduleLiveCheck();
    });
    editorEl.addEventListener('scroll', syncScroll);
    editorEl.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
        e.preventDefault();
        executeProgram();
        return;
      }
      if (e.key === 'Tab') {
        e.preventDefault();
        const start = editorEl.selectionStart;
        const end = editorEl.selectionEnd;
        editorEl.value = editorEl.value.slice(0, start) + '    ' + editorEl.value.slice(end);
        editorEl.selectionStart = editorEl.selectionEnd = start + 4;
        syncEditorVisuals();
      }
    });

    selectEl.addEventListener('change', () => {
      const found = EXAMPLES.find((ex) => ex.id === selectEl.value);
      if (!found) return;
      currentExampleId = found.id;
      editorEl.value = found.code;
      stdinEl.value = found.stdin || '';
      stdinDetails.open = Boolean(found.stdin);
      syncEditorVisuals();
      renderDiagnostics([]);
      consoleEl.classList.add('pg-console-empty');
      consoleEl.textContent = 'Click Run (or press Ctrl/Cmd + Enter) to execute your Otter program.';
      runMeta.textContent = 'Idle';
      history.replaceState(null, '', `#example=${encodeURIComponent(found.id)}`);
    });

    runBtn.addEventListener('click', executeProgram);
    stopBtn.addEventListener('click', () => stopExecution('Execution stopped by user.'));

    resetBtn.addEventListener('click', () => {
      const found = EXAMPLES.find((ex) => ex.id === currentExampleId) || EXAMPLES[0];
      editorEl.value = found.code;
      stdinEl.value = found.stdin || '';
      stdinDetails.open = Boolean(found.stdin);
      syncEditorVisuals();
      renderDiagnostics([]);
      consoleEl.classList.add('pg-console-empty');
      consoleEl.textContent = 'Click Run (or press Ctrl/Cmd + Enter) to execute your Otter program.';
      runMeta.textContent = 'Idle';
    });

    copyBtn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(editorEl.value);
        copyBtn.textContent = 'Copied!';
        setTimeout(() => { copyBtn.textContent = 'Copy Code'; }, 1400);
      } catch {
        copyBtn.textContent = 'Copy failed';
        setTimeout(() => { copyBtn.textContent = 'Copy Code'; }, 1400);
      }
    });

    shareBtn.addEventListener('click', async () => {
      const hash = encodeShareHash(editorEl.value, stdinEl.value);
      history.replaceState(null, '', hash);
      try {
        await navigator.clipboard.writeText(window.location.href);
        shareBtn.textContent = 'Link Copied!';
        setTimeout(() => { shareBtn.textContent = 'Share Link'; }, 1600);
      } catch {
        shareBtn.textContent = 'URL Updated';
        setTimeout(() => { shareBtn.textContent = 'Share Link'; }, 1600);
      }
    });

    syncEditorVisuals();
    spawnWorker();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mountPlayground);
  } else {
    mountPlayground();
  }
})();
