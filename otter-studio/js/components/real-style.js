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

import { evaluateMediaForWidth } from '../designer/css-values.js';

const SCOPE_STYLE_ID = 'otterRealCanvasCss';

// The canvas is not the browser window, so a real @media query would test the
// width of Studio, not of the design. Rules are flattened instead: a media
// block that matches the canvas device width is applied, one that does not is
// dropped, and one that depends on something else is kept as written.
function walkMedia(rule, deviceWidth, walkInner, into) {
  const verdict = deviceWidth ? evaluateMediaForWidth(rule.conditionText || rule.media.mediaText, deviceWidth) : null;
  if (verdict === false) return;
  const inner = [];
  walkInner(rule.cssRules, inner);
  if (!inner.length) return;
  if (verdict === true) into.push(...inner);
  else into.push(`@media ${rule.conditionText || rule.media.mediaText} {\n${inner.join('\n')}\n}`);
}

// While a state is being designed, its rules also apply to elements marked
// with data-force-state, so the canvas can show :hover without a mouse.
const FORCEABLE_STATES = ['hover', 'active', 'focus'];
function withForcedStates(selector) {
  let forced = selector;
  for (const state of FORCEABLE_STATES) {
    forced = forced.replace(new RegExp(`:${state}(?![\\w-])`, 'g'), `[data-force-state="${state}"]`);
  }
  return forced === selector ? null : forced;
}

// The live user stylesheet (styles.css), scoped to the canvas window and
// evaluated for the device width being designed.
export function prepareUserCss(cssText, scope, deviceWidth) {
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
        walkMedia(rule, deviceWidth, walk, into);
      } else {
        into.push(rule.cssText);
      }
    }
  };
  const out = [];
  walk(sheet.cssRules, out);
  return out.join('\n');
}

export async function fetchRealRender(code, css) {
  const res = await fetch('/api/render', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, css })
  });
  const result = await res.json();
  if (!result.ok) throw new Error(result.message || 'Render failed.');
  return parseRealRender(result.html);
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
export function scopeCss(cssText, scope, deviceWidth = null) {
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
        walkMedia(rule, deviceWidth, walk, into);
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
export function applyRealRender(root, real, deviceWidth = null) {
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
  styleEl.textContent = scopeCss(real.css, scope, deviceWidth);

  const rootInfo = real.elements.get(root.id);
  if (rootInfo) {
    root.classList.add('otter-window');
    root.style.cssText = rootInfo.style;
  }
  root.classList.add('is-real-render');

  for (const el of root.querySelectorAll('.canvas-element')) {
    const info = real.elements.get(el.id);
    if (!info) continue;
    // Keep designer/interaction classes; replace the canvas's approximate look
    // with the classes the real compiler emitted.
    const keep = Array.from(el.classList).filter(c =>
      c === 'canvas-element' || c === 'is-container' || c === 'is-control' ||
      c === 'is-interactive-mode' || c === 'is-dragging' || c === 'btn-clicked');
    el.className = [...keep, ...info.className.split(/\s+/).filter(Boolean), 'is-real-render'].join(' ');
    // The canvas draws bare containers/controls with its own min sizes; the real
    // inline style decides the geometry.
    const preserved = el.style.cursor;
    el.style.cssText = info.style;
    if (preserved) el.style.cursor = preserved;
  }
}
