// preview.js - Interactive live runtime preview running the compiled Otter application + CSS

import { generateOtterSource } from '../compiler/otter-generator.js';
import { withAssetBase } from '../designer/asset-url.js';

export function renderPreview(containerEl, uiModel, cssAstManager) {
  containerEl.innerHTML = `
    <div class="preview-header">
      <div class="preview-controls">
        <span class="preview-status-indicator">●</span>
        <span class="panel-title">Live Preview (real Otter compiler)</span>
        <div class="viewport-toggles">
          <button class="viewport-btn is-active" data-view="desktop" title="Desktop Window">Desktop</button>
          <button class="viewport-btn" data-view="tablet" title="Tablet (768px)">Tablet</button>
          <button class="viewport-btn" data-view="mobile" title="Mobile (375px)">Mobile</button>
          <button class="viewport-btn" data-view="responsive" title="Full Width">Full</button>
        </div>
      </div>
      <div class="preview-actions">
        <button class="editor-btn" id="reloadPreviewBtn" title="Rerun Application">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.57-8.38l5.67-5.67"/></svg>
          Reload
        </button>
        <button class="editor-btn editor-btn-primary" id="exportHtmlBtn" title="Export standalone HTML + CSS bundle">
          Export HTML
        </button>
      </div>
    </div>
    <div class="preview-viewport-container" id="previewViewportContainer">
      <div class="preview-device-frame view-desktop" id="previewDeviceFrame">
        <iframe class="preview-iframe" id="previewIframe" sandbox="allow-scripts allow-modals"></iframe>
      </div>
    </div>
    <div class="preview-log-drawer" id="previewLogDrawer">
      <div class="log-header">
        <span class="log-title">Otter Output</span>
        <button class="log-clear-btn" id="clearLogBtn">Clear</button>
      </div>
      <div class="log-entries" id="previewLogEntries">
        <div class="log-entry log-system">Application loaded with lossless CSS. Waiting for events...</div>
      </div>
    </div>
  `;

  const iframe = containerEl.querySelector('#previewIframe');
  const frameEl = containerEl.querySelector('#previewDeviceFrame');
  const reloadBtn = containerEl.querySelector('#reloadPreviewBtn');
  const exportBtn = containerEl.querySelector('#exportHtmlBtn');
  const logEntriesEl = containerEl.querySelector('#previewLogEntries');
  const clearLogBtn = containerEl.querySelector('#clearLogBtn');

  // The preview is the output of the production compiler (`otter web`), served
  // by Studio's /api/render - not a Studio-side approximation. Renders are
  // debounced, and a slower response for older source never overwrites a newer one.
  let renderTimer = null;
  let renderSerial = 0;
  let lastHtml = null;

  async function renderReal() {
    const serial = ++renderSerial;
    const code = generateOtterSource(uiModel);
    const css = cssAstManager ? cssAstManager.generateCss() : '';
    setStatus('rendering');
    try {
      const res = await fetch('/api/render', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code, css })
      });
      const result = await res.json();
      if (serial !== renderSerial) return;
      if (result.ok) {
        lastHtml = result.html;
        // Relative image sources load from the design's folder.
        iframe.srcdoc = withAssetBase(result.html);
        setStatus('ok');
      } else {
        setStatus('error', result.message);
      }
    } catch (err) {
      if (serial === renderSerial) setStatus('error', err.message);
    }
  }

  function setStatus(state, message) {
    const dot = containerEl.querySelector('.preview-status-indicator');
    if (dot) {
      dot.dataset.state = state;
      dot.style.color = state === 'ok' ? '#22c55e' : state === 'error' ? '#ef4444' : '#f59e0b';
      dot.title = state === 'error' ? message : state;
    }
    if (state === 'error') addLog(`Render failed: ${message}`);
  }

  function updatePreview() {
    clearTimeout(renderTimer);
    renderTimer = setTimeout(renderReal, 350);
  }

  updatePreview();

  // Model updates trigger preview update
  uiModel.subscribe((type) => {
    updatePreview();
  });

  window.addEventListener('css-updated', () => {
    updatePreview();
  });

  reloadBtn.addEventListener('click', () => {
    updatePreview();
    addLog('Application reloaded.');
  });

  clearLogBtn.addEventListener('click', () => {
    logEntriesEl.innerHTML = '';
  });

  exportBtn.addEventListener('click', () => {
    if (!lastHtml) return;
    const docHtml = lastHtml;
    const blob = new Blob([docHtml], { type: 'text/html;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${uiModel.getRoot()?.name || 'app'}.html`;
    a.click();
    URL.revokeObjectURL(url);
  });

  // Viewport toggles
  const viewportBtns = containerEl.querySelectorAll('.viewport-btn');
  viewportBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      viewportBtns.forEach(b => b.classList.remove('is-active'));
      btn.classList.add('is-active');

      const view = btn.getAttribute('data-view');
      frameEl.className = `preview-device-frame view-${view}`;
    });
  });

  // Listen for iframe log messages
  window.addEventListener('message', (e) => {
    if (e.data && e.data.type === 'otter-log') {
      addLog(e.data.message);
    }
  });

  function addLog(msg) {
    const entry = document.createElement('div');
    entry.className = 'log-entry';
    const time = new Date().toLocaleTimeString();
    entry.innerHTML = `<span class="log-time">[${time}]</span> ${escapeHtml(msg)}`;
    logEntriesEl.appendChild(entry);
    logEntriesEl.scrollTop = logEntriesEl.scrollHeight;
  }
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
