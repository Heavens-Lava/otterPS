// editor.js - Multi-tab Synchronized Code & CSS Editor with lossless AST support

import { generateOtterSource } from '../compiler/otter-generator.js';
import { parseOtterSource } from '../compiler/otter-parser.js';

export function renderEditor(containerEl, uiModel, cssAstManager) {
  let activeTab = 'otter'; // 'otter' | 'css'

  containerEl.innerHTML = `
    <div class="editor-header">
      <div class="editor-tabs">
        <span class="editor-tab is-active" id="tabOtter">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
          main.ot
        </span>
        <span class="editor-tab" id="tabCss">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="16" y1="2" x2="16" y2="6"/></svg>
          app.css
        </span>
      </div>
      <div class="editor-actions">
        <button class="editor-btn" id="copyCodeBtn" title="Copy to clipboard">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
          Copy
        </button>
        <button class="editor-btn" id="downloadBtn" title="Download File">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
          Download
        </button>
        <span class="editor-live-status" title="Valid Otter UI source updates the designer automatically">● Live sync</span>
      </div>
    </div>
    <div class="editor-wrapper">
      <textarea class="code-textarea" id="activeCodeTextarea" spellcheck="false"></textarea>
      <div class="code-highlight-layer" id="codeHighlightLayer"></div>
    </div>
    <div class="editor-statusbar">
      <span class="status-item" id="editorStatusText">Synchronized with Designer</span>
      <span class="status-item" id="fileTypeStatus">Otter 1.0</span>
    </div>
  `;

  const tabOtter = containerEl.querySelector('#tabOtter');
  const tabCss = containerEl.querySelector('#tabCss');
  const textarea = containerEl.querySelector('#activeCodeTextarea');
  const highlightLayer = containerEl.querySelector('#codeHighlightLayer');
  const copyBtn = containerEl.querySelector('#copyCodeBtn');
  const downloadBtn = containerEl.querySelector('#downloadBtn');
  const statusText = containerEl.querySelector('#editorStatusText');
  const fileTypeStatus = containerEl.querySelector('#fileTypeStatus');

  let isTyping = false;
  let sourceSyncTimer = null;

  function refreshEditor() {
    if (isTyping) return;

    if (activeTab === 'otter') {
      tabOtter.classList.add('is-active');
      tabCss.classList.remove('is-active');
      fileTypeStatus.innerText = 'Otter 1.0 (Logic & Structure)';
      const src = generateOtterSource(uiModel);
      textarea.value = src;
      highlightOtter(src);
    } else {
      tabCss.classList.add('is-active');
      tabOtter.classList.remove('is-active');
      fileTypeStatus.innerText = 'CSS3 (Lossless Styling Source)';
      const css = cssAstManager ? cssAstManager.generateCss() : '';
      textarea.value = css;
      highlightCss(css);
    }

    statusText.innerText = 'Synchronized with Designer';
    statusText.style.color = '#94a3b8';
  }

  function highlightOtter(source) {
    const keywords = /\b(create|into|the|has|put|in|show|when|is|clicked|changed|closed|say|title|text|placeholder|checked|true|false)\b/g;
    const lines = source.split('\n');
    const highlightedLines = lines.map(line => {
      let l = escapeHtml(line);
      if (l.trim().startsWith('#')) return `<span class="tok-comment">${l}</span>`;
      l = l.replace(/"([^"]*)"/g, '<span class="tok-string">"$1"</span>');
      l = l.replace(/\b(\d+)\b/g, '<span class="tok-number">$1</span>');
      l = l.replace(keywords, '<span class="tok-keyword">$1</span>');
      return l;
    });
    highlightLayer.innerHTML = highlightedLines.join('\n') + '\n';
  }

  function highlightCss(source) {
    const lines = source.split('\n');
    const highlightedLines = lines.map(line => {
      let l = escapeHtml(line);
      if (l.includes('/*')) {
        l = l.replace(/\/\*.*?\*\//g, '<span class="tok-comment">$&</span>');
      }
      // Selectors
      if (l.includes('{')) {
        const parts = l.split('{');
        return `<span class="tok-var">${parts[0]}</span>{${parts.slice(1).join('{')}`;
      }
      // Declarations
      if (l.includes(':')) {
        const parts = l.split(':');
        return `<span class="tok-kw">${parts[0]}</span>:<span class="tok-str">${parts.slice(1).join(':')}</span>`;
      }
      return l;
    });
    highlightLayer.innerHTML = highlightedLines.join('\n') + '\n';
  }

  tabOtter.addEventListener('click', () => {
    activeTab = 'otter';
    isTyping = false;
    refreshEditor();
  });

  tabCss.addEventListener('click', () => {
    activeTab = 'css';
    isTyping = false;
    refreshEditor();
  });

  textarea.addEventListener('input', () => {
    isTyping = true;
    if (activeTab === 'otter') {
      highlightOtter(textarea.value);
    } else {
      highlightCss(textarea.value);
    }
    if (activeTab === 'otter') {
      scheduleOtterSourceSync();
    } else {
      statusText.innerText = 'Unsaved CSS changes';
      statusText.style.color = '#f59e0b';
    }
    highlightLayer.scrollTop = textarea.scrollTop;
    highlightLayer.scrollLeft = textarea.scrollLeft;
  });

  textarea.addEventListener('scroll', () => {
    highlightLayer.scrollTop = textarea.scrollTop;
    highlightLayer.scrollLeft = textarea.scrollLeft;
  });

  function scheduleOtterSourceSync() {
    if (sourceSyncTimer) clearTimeout(sourceSyncTimer);
    statusText.innerText = 'Updating designer…';
    statusText.style.color = '#60a5fa';
    sourceSyncTimer = setTimeout(() => {
      const success = parseOtterSource(textarea.value, uiModel);
      if (success) {
        statusText.innerText = 'Designer updated from source';
        statusText.style.color = '#22c55e';
        window.dispatchEvent(new CustomEvent('otter:source-changed', {
          detail: { source: textarea.value, origin: 'component-editor' }
        }));
      } else {
        // Do not destroy the last valid design while the author is midway
        // through a change. The shared diagnostics path explains the error.
        statusText.innerText = 'Waiting for valid UI source';
        statusText.style.color = '#f59e0b';
      }
    }, 180);
  }

  copyBtn.addEventListener('click', () => {
    navigator.clipboard?.writeText(textarea.value).then(() => {
      const orig = copyBtn.innerText;
      copyBtn.innerText = 'Copied!';
      setTimeout(() => copyBtn.innerText = orig, 1200);
    });
  });

  downloadBtn.addEventListener('click', () => {
    const filename = activeTab === 'otter' ? 'main.ot' : 'app.css';
    const blob = new Blob([textarea.value], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  });

  refreshEditor();

  uiModel.subscribe((type) => {
    if (type !== 'parse' && !isTyping) {
      refreshEditor();
    }
  });

  window.addEventListener('css-updated', (e) => {
    if (e.detail?.source !== 'editor' && !isTyping) {
      refreshEditor();
    }
  });

  // The primary editor is authoritative when a file is opened or edited.
  // Keep this split-editor surface showing that exact source rather than an
  // older model-generated representation.
  window.addEventListener('otter:source-synced', event => {
    const source = event.detail?.source;
    if (activeTab !== 'otter' || typeof source !== 'string' || textarea.value === source) return;
    isTyping = true;
    textarea.value = source;
    highlightOtter(source);
    statusText.innerText = 'Live source synchronized';
    statusText.style.color = '#22c55e';
  });
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
