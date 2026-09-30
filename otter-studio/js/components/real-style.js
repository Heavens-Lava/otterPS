// real-style.js - Makes the design canvas look like the real program.
//
// The canvas used to approximate Otter's rendering with its own CSS, so a card
// or button could look different on the canvas than in the running app. This
// module asks Studio's /api/render for the output of the production web
// compiler (`otter web`), then adopts from it:
//   1. the compiler's own stylesheet, scoped so it cannot leak into Studio, and
//   2. each element's class list and inline style, matched by element id.
// The canvas keeps its own DOM (data-id, drag handles, overlays) - only the
// look comes from the real output.

import { evaluateMedia } from '../designer/css-values.js';

const SCOPE_STYLE_ID = 'otterRealCanvasCss';

// The canvas is not the browser window, so a real @media query would test the
// width of Studio, not of the design. Rules are flattened instead: a media
// block that matches the canvas device width is applied, one that does not is
// dropped, and one that depends on something else is kept as written.
// `device` is the preview environment (see DEFAULT_MEDIA_ENV) or a bare width.
function walkMedia(rule, device, walkInner, into) {
  const verdict = device ? evaluateMedia(rule.conditionText || rule.media.mediaText, device) : null;
  if (verdict === false) return;
  const inner = [];
  walkInner(rule.cssRules, inner);
  if (!inner.length) return;
  if (verdict === true) into.push(...inner);
  else into.push(`@media ${rule.conditionText || rule.media.mediaText} {\n${inner.join('\n')}\n}`);
}

// While a state is being designed, its rules also apply to elements marked
// with data-force-state, so the canvas can show :hover without a mouse.
const FORCEABLE_STATES = ['hover', 'active', 'focus', 'disabled'];
function withForcedStates(selector) {
  let forced = selector;
  for (const state of FORCEABLE_STATES) {
    forced = forced.replace(new RegExp(`:${state}(?![\\w-])`, 'g'), `[data-force-state="${state}"]`);
  }
  return forced === selector ? null : forced;
}

// The live user stylesheet (styles.css), scoped to the canvas window and
// evaluated for the device width being designed.
export function prepareUserCss(cssText, scope, device) {
  const sheet = new CSSStyleSheet();
  try {
    sheet.replaceSync(cssText || '');
  } catch {
    return '';
  }
  const scopeSelector = (selector) => {
    const sel = selector.trim();
    if (!sel) return null;
    if (/^(html|body|:root)$/.test(sel)) return scope;
    if (/^(html|body)\b/.test(sel)) return `${scope} ${sel.replace(/^(html|body)\s*/, '')}`;
    return `${scope} ${sel}`;
  };
  const walk = (rules, into) => {
    for (const rule of rules) {
      if (rule.type === CSSRule.STYLE_RULE) {
        const selectors = [];
        for (const part of rule.selectorText.split(',')) {
          const scoped = scopeSelector(part);
          if (!scoped) continue;
          selectors.push(scoped);
          const forced = withForcedStates(scoped);
          if (forced) selectors.push(forced);
        }
        if (selectors.length && rule.style.cssText.trim()) into.push(`${selectors.join(', ')} { ${rule.style.cssText} }`);
      } else if (rule.type === CSSRule.MEDIA_RULE) {
        walkMedia(rule, device, walk, into);
      } else {
        into.push(rule.cssText);
      }
    }
  };
  const out = [];
  walk(sheet.cssRules, out);
  return out.join('\n');
}

// The document being designed, so the server can resolve its `use` imports,
// icon sprite and images from the folder the file really lives in.
export function currentDocumentPath() {
  const ide = window.otterIde;
  const file = ide && ide.currentFile;
  return typeof file === 'string' && file.endsWith('.ot') && file !== 'untitled.ot' ? file : '';
}

// wantedIds: the design's components. A program that builds its page while
// it runs (Otter 1.1's runtime UI: OtterBoard) has almost none of them in
// the compiled HTML; then the page is run, sandboxed, to read them.
// signal: aborts a render a newer one has replaced, so waiting renders of a
// slow project never hold the browser's few connections to the server (a
// save queued behind them could not be sent).
export async function fetchRealRender(code, css, wantedIds = [], { signal } = {}) {
  const res = await fetch('/api/render', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, css, path: currentDocumentPath() }),
    signal
  });
  const result = await res.json();
  if (!result.ok) throw new Error(result.message || 'Render failed.');
  const real = parseRealRender(result.html);
  const found = wantedIds.filter(id => real.elements.has(id)).length;
  if (wantedIds.length > 1 && found < wantedIds.length * 0.6) {
    const live = await runLiveRender(result.html);
    if (live && live.elements.size > real.elements.size) return { ...real, css: live.css || real.css, elements: live.elements };
  }
  return real;
}

// Run a compiled page in a hidden iframe and read what its program built:
// every element's class and inline style, and the compiler's stylesheet.
// sandbox="allow-scripts" only - the page gets no access to Studio's
// origin, its API, dialogs or popups - and it reports back by postMessage.
// null when it does not answer in time (the static read stands then).
export function runLiveRender(html, timeoutMs = 5000) {
  return new Promise((resolve) => {
    const token = Math.random().toString(36).slice(2);
    const collector = `<script>(function(){function send(){var els={};document.querySelectorAll('[id]').forEach(function(e){els[e.id]={className:e.getAttribute('class')||'',style:e.getAttribute('style')||''};});var css=Array.prototype.filter.call(document.querySelectorAll('style'),function(s){return s.id!=='otter-sidecar-style';}).map(function(s){return s.textContent;}).join('\\n');parent.postMessage({otterLiveRender:'${token}',elements:els,css:css},'*');}if(document.readyState==='complete'){setTimeout(send,200);}else{window.addEventListener('load',function(){setTimeout(send,200);});}})();<\/script>`;
    const doc = /<\/body>/i.test(html) ? html.replace(/<\/body>/i, () => `${collector}</body>`) : html + collector;
    const frame = document.createElement('iframe');
    frame.setAttribute('sandbox', 'allow-scripts');
    frame.setAttribute('aria-hidden', 'true');
    frame.style.cssText = 'position:fixed;left:-20000px;top:0;width:1280px;height:800px;visibility:hidden;pointer-events:none;';
    let timer = null;
    const onMessage = (e) => {
      if (e.source !== frame.contentWindow || e.data?.otterLiveRender !== token) return;
      done({ css: String(e.data.css || ''), elements: new Map(Object.entries(e.data.elements || {})) });
    };
    const done = (result) => {
      clearTimeout(timer);
      window.removeEventListener('message', onMessage);
      frame.remove();
      resolve(result);
    };
    timer = setTimeout(() => done(null), timeoutMs);
    window.addEventListener('message', onMessage);
    frame.srcdoc = doc;
    document.body.appendChild(frame);
  });
}

// Returns { css, elements: Map<id, { className, style }> }.
export function parseRealRender(html) {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  // The program's own styles.css is embedded as #otter-sidecar-style. The
  // canvas applies the live stylesheet itself (instantly, per breakpoint), so
  // it takes only the compiler's stylesheet from the render; a stale copy of
  // the user's CSS would otherwise fight every edit until the next render.
  const css = Array.from(doc.querySelectorAll('style'))
    .filter(s => s.id !== 'otter-sidecar-style')
    .map(s => s.textContent).join('\n');
  const elements = new Map();
  for (const el of doc.body.querySelectorAll('[id]')) {
    elements.set(el.id, {
      className: el.getAttribute('class') || '',
      style: el.getAttribute('style') || ''
    });
  }
  const fonts = Array.from(doc.querySelectorAll('link[rel="stylesheet"], link:not([rel])[href]'))
    .map(l => l.getAttribute('href'))
    .filter(href => href && /^https:\/\/fonts\.googleapis\.com\//.test(href));
  return { css, elements, fonts };
}

// Prefix every rule of the compiler stylesheet with `scope` (a selector for the
// canvas root). Rules that target the page itself (body/html) are dropped: the
// canvas is not the page. `:root` variables move onto the scope element.
export function scopeCss(cssText, scope, device = null) {
  const sheet = new CSSStyleSheet();
  sheet.replaceSync(cssText);
  // Studio's own chrome sets line-height, weight, etc. on ancestors of the
  // canvas. A real page starts from browser defaults, so start there too.
  const out = [
    `${scope} { font-size: 16px; font-weight: 400; font-style: normal; line-height: normal; ` +
      'letter-spacing: normal; text-align: left; text-transform: none; white-space: normal; }'
  ];

  const scopeSelector = (selector) => {
    const sel = selector.trim();
    if (!sel) return null;
    if (sel === 'body') return scope; // typography only - see below
    if (/^(html|body)\b/.test(sel)) return null;
    if (sel === ':root') return scope;
    if (/^\*/.test(sel)) return `${scope} ${sel}`;
    // The window element IS the scope element, so its rules bind to it directly.
    if (/^\.otter-window\b/.test(sel)) return `${scope}${sel}, ${scope} ${sel}`;
    return `${scope} ${sel}`;
  };

  const walk = (rules, into) => {
    for (const rule of rules) {
      if (rule.type === CSSRule.STYLE_RULE) {
        const isBody = rule.selectorText.trim() === 'body';
        const selectors = rule.selectorText.split(',').map(scopeSelector).filter(Boolean);
        // The page's body rule sets layout for the page, which the canvas is not;
        // only its typography carries over.
        const declarations = isBody
          ? ['font-family', 'color']
              .map(name => rule.style.getPropertyValue(name) ? `${name}: ${rule.style.getPropertyValue(name)};` : '')
              .join(' ')
          : rule.style.cssText;
        if (selectors.length && declarations.trim()) into.push(`${selectors.join(', ')} { ${declarations} }`);
      } else if (rule.type === CSSRule.MEDIA_RULE) {
        walkMedia(rule, device, walk, into);
      } else if (rule.type === CSSRule.KEYFRAMES_RULE) {
        into.push(rule.cssText);
      }
    }
  };
  walk(sheet.cssRules, out);
  // Form controls use the browser's own font unless the program says otherwise.
  out.push(`${scope} button, ${scope} input, ${scope} textarea, ${scope} select { font-family: revert; }`);
  return out.join('\n');
}

// Apply the real look to the canvas. `root` is the canvas content area (whose
// id is the window's name); canvas elements are found by id.
export function applyRealRender(root, real, device = null) {
  if (!root || !real) return;
  const scope = `#${CSS.escape(root.id)}`;

  // The compiler loads its web fonts from Google Fonts; load the same ones so
  // text measures the same as in the running app.
  for (const href of real.fonts || []) {
    if (!document.head.querySelector(`link[data-otter-real-font][href="${href}"]`)) {
      const link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = href;
      link.dataset.otterRealFont = 'true';
      document.head.appendChild(link);
    }
  }

  let styleEl = document.getElementById(SCOPE_STYLE_ID);
  if (!styleEl) {
    styleEl = document.createElement('style');
    styleEl.id = SCOPE_STYLE_ID;
    document.head.appendChild(styleEl);
  }
  styleEl.textContent = scopeCss(real.css, scope, device);

  const rootInfo = real.elements.get(root.id);
  if (rootInfo) {
    root.classList.add('otter-window');
    root.style.cssText = rootInfo.style;
    // The compiled page centres the window with a margin around it; on the
    // canvas the frame is the window, so its content starts right under the
    // title bar (a Free layout's positions are measured from there).
    root.style.margin = '0';
  }
  root.classList.add('is-real-render');

  for (const el of root.querySelectorAll('.canvas-element')) {
    const info = real.elements.get(el.id);
    if (!info) continue;
    // Keep designer/interaction classes; replace the canvas's approximate look
    // with the classes the real compiler emitted.
    const keep = Array.from(el.classList).filter(c =>
      c === 'canvas-element' || c === 'is-container' || c === 'is-control' ||
      c === 'is-interactive-mode' || c === 'is-dragging' || c === 'btn-clicked' ||
      c === 'has-field-label' || c === 'has-field-label-flow');
    el.className = [...keep, ...info.className.split(/\s+/).filter(Boolean), 'is-real-render'].join(' ');
    // The canvas draws bare containers/controls with its own min sizes; the real
    // inline style decides the geometry.
    const preserved = el.style.cursor;
    el.style.cssText = info.style;
    if (preserved) el.style.cursor = preserved;
  }
}
