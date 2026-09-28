// docs-viewer.js - Otter documentation inside Studio (Help > Otter Guide,
// Help > Release Notes). Reads the repository's own Markdown documents, so
// what you read is what ships: the language guide, grammar, semantics,
// standard library, compatibility notes and the changelog.

import { renderMarkdown, escapeHtml } from './markdown.js';

export const DOCS = [
  { path: 'rules.md', title: 'Otter language guide' },
  { path: 'docs/STANDARD_LIBRARY.md', title: 'Standard library' },
  { path: 'docs/GRAMMAR.md', title: 'Grammar' },
  { path: 'docs/SEMANTICS.md', title: 'Semantics' },
  { path: 'docs/COMPATIBILITY.md', title: 'Compatibility' },
  { path: 'CHANGELOG.md', title: 'Release notes' },
  { path: 'README.md', title: 'About Otter' }
];

export function mountDocsViewer({ ide }) {
  let backdrop = null;
  let current = null;
  const cache = new Map();

  async function load(path) {
    if (cache.has(path)) return cache.get(path);
    const res = await fetch(`/api/file?path=${encodeURIComponent(path)}`);
    const data = await res.json().catch(() => ({}));
    if (typeof data.content !== 'string') throw new Error(data.error || `Could not open ${path}.`);
    cache.set(path, data.content);
    return data.content;
  }

  function ensure() {
    if (backdrop) return;
    backdrop = document.createElement('div');
    backdrop.className = 'modal-backdrop docs-backdrop';
    backdrop.style.display = 'none';
    backdrop.innerHTML = `
      <div class="modal-dialog docs-viewer" role="dialog" aria-modal="true" aria-label="Otter documentation">
        <div class="docs-header">
          <strong class="docs-title">Otter documentation</strong>
          <input class="config-input docs-filter" placeholder="Find in this page..." spellcheck="false" />
          <button class="find-action-btn" data-docs-open title="Open this document in the editor">Open in editor</button>
          <button class="modal-close-btn" data-docs-close title="Close (Esc)">✕</button>
        </div>
        <div class="docs-layout">
          <nav class="docs-nav">
            <div class="docs-nav-list">${DOCS.map(d => `<button class="docs-nav-item" data-doc="${d.path}">${escapeHtml(d.title)}</button>`).join('')}</div>
            <div class="docs-outline"></div>
          </nav>
          <article class="docs-content markdown-body"></article>
        </div>
      </div>`;
    document.body.appendChild(backdrop);
    backdrop.querySelector('[data-docs-close]').addEventListener('click', close);
    backdrop.addEventListener('mousedown', (e) => { if (e.target === backdrop) close(); });
    backdrop.querySelector('.docs-nav-list').addEventListener('click', (e) => {
      const item = e.target.closest('[data-doc]');
      if (item) show(item.getAttribute('data-doc'));
    });
    backdrop.querySelector('.docs-outline').addEventListener('click', (e) => {
      const item = e.target.closest('[data-anchor]');
      if (item) backdrop.querySelector(`#${CSS.escape(item.getAttribute('data-anchor'))}`)?.scrollIntoView({ block: 'start' });
    });
    backdrop.querySelector('.docs-content').addEventListener('click', (e) => {
      const link = e.target.closest('a[data-doc-link]');
      if (!link) return;
      e.preventDefault();
      const [target, anchor] = link.getAttribute('href').split('#');
      const resolved = target ? resolveDoc(current, target) : current;
      show(resolved, anchor);
    });
    backdrop.querySelector('[data-docs-open]').addEventListener('click', () => {
      if (!current) return;
      close();
      ide.navigateToLocation({ path: current, line: 1, column: 0 });
    });
    backdrop.querySelector('.docs-filter').addEventListener('input', (e) => highlight(e.target.value));
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && backdrop.style.display !== 'none') { e.stopPropagation(); close(); }
    }, true);
  }

  async function show(path, anchor = null) {
    ensure();
    const content = backdrop.querySelector('.docs-content');
    current = path;
    backdrop.querySelectorAll('.docs-nav-item').forEach(b => b.classList.toggle('is-active', b.getAttribute('data-doc') === path));
    try {
      const { html, headings } = renderMarkdown(await load(path));
      content.innerHTML = html;
      backdrop.querySelector('.docs-outline').innerHTML = headings.filter(h => h.level <= 3)
        .map(h => `<button class="docs-outline-item lvl-${h.level}" data-anchor="${h.id}">${escapeHtml(h.text)}</button>`).join('');
      backdrop.querySelector('.docs-title').textContent = DOCS.find(d => d.path === path)?.title || path;
    } catch (err) {
      content.innerHTML = `<p class="docs-error">${escapeHtml(err.message)}</p>`;
      backdrop.querySelector('.docs-outline').innerHTML = '';
    }
    content.scrollTop = 0;
    const filter = backdrop.querySelector('.docs-filter');
    if (filter.value) highlight(filter.value);
    if (anchor) content.querySelector(`#${CSS.escape(anchor)}`)?.scrollIntoView({ block: 'start' });
  }

  // Mark every occurrence of the filter text in the page; jump to the first.
  function highlight(text) {
    const content = backdrop.querySelector('.docs-content');
    content.querySelectorAll('mark.docs-hit').forEach(m => m.replaceWith(document.createTextNode(m.textContent)));
    content.normalize();
    const term = text.trim().toLowerCase();
    if (term.length < 2) return;
    const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    let first = null;
    for (const node of nodes) {
      const lower = node.textContent.toLowerCase();
      let at = lower.indexOf(term);
      if (at < 0) continue;
      const frag = document.createDocumentFragment();
      let last = 0;
      while (at >= 0) {
        frag.append(node.textContent.slice(last, at));
        const mark = document.createElement('mark');
        mark.className = 'docs-hit';
        mark.textContent = node.textContent.slice(at, at + term.length);
        frag.append(mark);
        first = first || mark;
        last = at + term.length;
        at = lower.indexOf(term, last);
      }
      frag.append(node.textContent.slice(last));
      node.replaceWith(frag);
    }
    first?.scrollIntoView({ block: 'center' });
  }

  function open(path = 'rules.md') {
    ensure();
    backdrop.style.display = 'flex';
    show(path);
  }

  function close() {
    if (backdrop) backdrop.style.display = 'none';
  }

  return { open, close, show };
}

// "docs/GRAMMAR.md" + "SEMANTICS.md" -> "docs/SEMANTICS.md"; "../rules.md" climbs.
function resolveDoc(from, target) {
  const parts = String(from || '').split('/').slice(0, -1);
  for (const p of target.split('/')) {
    if (p === '..') parts.pop();
    else if (p && p !== '.') parts.push(p);
  }
  return parts.join('/');
}

// A new GitHub issue with Studio's details filled in.
export function issueUrl({ version = '', platform = '', userAgent = '' } = {}) {
  const body = [
    '**What happened**', '', '', '**What I expected**', '', '', '**Steps to reproduce**', '1. ', '',
    '---', `Otter Studio ${version}`, `Platform: ${platform}`, `Browser: ${userAgent}`
  ].join('\n');
  return `https://github.com/Heavens-Lava/otterPS/issues/new?body=${encodeURIComponent(body)}`;
}
