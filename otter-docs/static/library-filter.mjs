// Shared pure library filtering, syntax highlighting, and sandbox srcdoc builder.
// Imported by both the browser UI (library-app.js) and automated Node tests (tests/library.test.mjs).

export const CATEGORY_META = {
  web: { id: 'web', label: 'Web', description: 'HTML, CSS, JavaScript, and TypeScript UI components' },
  desktop: { id: 'desktop', label: 'Desktop', description: 'C#, WPF/XAML, and native desktop UI patterns' },
  games: { id: 'games', label: 'Games', description: 'Godot GDScript, Unity C#, Roblox Luau, and Otter game systems' },
  effects: { id: 'effects', label: 'Styles & Effects', description: 'Glassmorphism, animations, hover effects, and CSS themes' },
  otter: { id: 'otter', label: 'Otter', description: 'Canonical Packs, Snippets, Blueprints, Recipes, and Workflows from otter-net' }
};

export function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (ch) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]
  ));
}

export function normalizeText(value) {
  return String(value || '').toLowerCase().replace(/[^a-z0-9#+.\/_-]+/g, ' ').trim();
}

export function componentSearchText(item) {
  const opNames = Array.isArray(item.contract?.operations)
    ? item.contract.operations.map((o) => o.name).join(' ')
    : '';
  return normalizeText([
    item.id,
    item.slug,
    item.name,
    item.description,
    item.category,
    item.subcategory,
    item.language,
    item.framework,
    item.otterKind || '',
    ...(item.tags || []),
    ...(item.platforms || []),
    opNames
  ].join(' '));
}

export function scoreMatch(item, query) {
  const words = normalizeText(query).split(/\s+/).filter(Boolean);
  if (!words.length) return 1;
  const name = normalizeText(item.name);
  const id = normalizeText(item.id);
  const tags = normalizeText((item.tags || []).join(' '));
  const full = componentSearchText(item);
  let score = 0;
  for (const w of words) {
    if (!full.includes(w)) return 0;
    if (name.includes(w)) score += 14;
    if (id.includes(w)) score += 10;
    if (tags.includes(w)) score += 6;
    score += 2;
  }
  return score;
}

export function filterComponents(items, filters = {}) {
  const {
    query = '',
    category = 'all',
    subcategory = 'all',
    language = 'all',
    verification = 'all'
  } = filters;

  const q = String(query || '').trim();
  const matched = [];
  for (const item of items) {
    if (category && category !== 'all' && item.category !== category) continue;
    if (subcategory && subcategory !== 'all' && item.subcategory !== subcategory) continue;
    if (language && language !== 'all') {
      const langs = (item.languages || [item.language]).map((l) => String(l).toLowerCase());
      if (!langs.includes(language.toLowerCase())) continue;
    }
    if (verification && verification !== 'all' && item.verification?.status !== verification) continue;

    const score = q ? scoreMatch(item, q) : 1;
    if (score > 0) matched.push({ item, score });
  }

  if (q) {
    matched.sort((a, b) => b.score - a.score || a.item.name.localeCompare(b.item.name));
  }
  return matched.map((m) => m.item);
}

export function extractFacets(items) {
  const categoryCounts = { all: items.length, web: 0, desktop: 0, games: 0, effects: 0, otter: 0 };
  const subcategories = new Map();
  const languages = new Map();
  const verifications = new Map();

  for (const item of items) {
    if (Object.prototype.hasOwnProperty.call(categoryCounts, item.category)) {
      categoryCounts[item.category]++;
    }
    subcategories.set(item.subcategory, (subcategories.get(item.subcategory) || 0) + 1);
    for (const lang of (item.languages || [item.language])) {
      languages.set(lang, (languages.get(lang) || 0) + 1);
    }
    const v = item.verification?.status || 'source-reviewed';
    verifications.set(v, (verifications.get(v) || 0) + 1);
  }

  return {
    categoryCounts,
    subcategories: [...subcategories.entries()].sort((a, b) => a[0].localeCompare(b[0])),
    languages: [...languages.entries()].sort((a, b) => a[0].localeCompare(b[0])),
    verifications: [...verifications.entries()].sort((a, b) => a[0].localeCompare(b[0]))
  };
}

// Lightweight, zero-dependency, XSS-safe tokenizer highlighter.
const KEYWORDS = {
  otter: /\b(use|to|return|if|otherwise|while|repeat|for|each|in|count|from|to|as|is|are|has|a|an|of|and|or|not|say|ask|add|remove|into|make|try|fail|with|true|false|gone|empty|sort|reverse|convert|plus|minus|times|divided|at|least|most|greater|less|than|contains)\b/g,
  javascript: /\b(const|let|var|function|return|if|else|for|of|in|while|switch|case|break|continue|new|class|extends|export|import|from|async|await|try|catch|finally|true|false|null|undefined|typeof|interface|type)\b/g,
  typescript: /\b(const|let|var|function|return|if|else|for|of|in|while|switch|case|break|continue|new|class|extends|export|import|from|async|await|try|catch|finally|true|false|null|undefined|typeof|interface|type|readonly|public|private)\b/g,
  csharp: /\b(using|namespace|public|private|protected|internal|sealed|partial|static|readonly|class|record|struct|interface|void|bool|int|string|var|new|return|if|else|foreach|for|while|in|is|not|null|true|false|event|get|set|override)\b/g,
  gdscript: /\b(class_name|extends|signal|func|var|const|if|elif|else|for|in|while|return|and|or|not|true|false|null|void|int|float|bool|String|@export)\b/g,
  luau: /\b(local|function|end|if|then|elseif|else|for|in|do|while|repeat|until|return|and|or|not|true|false|nil|continue|break|export|type|require)\b/g,
  css: /(@media|@keyframes|:root|:hover|:focus-visible|:active|::after|::before)/g,
  bash: /\b(export|cd|mkdir|cat|echo|otter|npm|pwsh|python3|git)\b/g
};

export function highlightCode(source, language = 'text') {
  const lang = String(language || 'text').toLowerCase();
  const escaped = escapeHtml(source);
  if (lang === 'json') {
    return escaped
      .replace(/(&quot;(?:\\.|[^&]|&(?!quot;))*?&quot;)(\s*:)/g, '<span class="tok-key">$1</span>$2')
      .replace(/(:\s*)(&quot;(?:\\.|[^&]|&(?!quot;))*?&quot;)/g, '$1<span class="tok-str">$2</span>')
      .replace(/\b(true|false|null)\b/g, '<span class="tok-kw">$1</span>')
      .replace(/\b(-?\d+(?:\.\d+)?)\b/g, '<span class="tok-num">$1</span>');
  }
  if (lang === 'html' || lang === 'xaml' || lang === 'xml') {
    return escaped
      .replace(/(&lt;!--[\s\S]*?--&gt;)/g, '<span class="tok-com">$1</span>')
      .replace(/(&lt;\/?[a-zA-Z0-9:._-]+)/g, '<span class="tok-tag">$1</span>')
      .replace(/(\s[a-zA-Z0-9:._-]+)(=)(&quot;.*?&quot;)/g, '<span class="tok-attr">$1</span>$2<span class="tok-str">$3</span>');
  }

  // Line-by-line safe pass for comments, strings, numbers, keywords
  const kwPattern = KEYWORDS[lang];
  const commentChar = (lang === 'otter' || lang === 'gdscript' || lang === 'bash')
    ? '#'
    : (lang === 'luau' ? '--' : (lang === 'css' ? '/*' : '//'));

  return escaped.split('\n').map((line) => {
    let codePart = line;
    let commentPart = '';
    if (commentChar === '#' || commentChar === '--' || commentChar === '//') {
      const idx = line.indexOf(commentChar);
      if (idx >= 0 && !line.slice(0, idx).includes('&quot;')) {
        codePart = line.slice(0, idx);
        commentPart = `<span class="tok-com">${line.slice(idx)}</span>`;
      }
    }
    const placeholders = [];
    codePart = codePart.replace(/(&quot;(?:\\.|[^&]|&(?!quot;))*?&quot;|&#39;(?:\\.|[^&]|&(?!#39;))*?&#39;)/g, (m) => {
      const token = `\u0000STR${placeholders.length}\u0000`;
      placeholders.push(`<span class="tok-str">${m}</span>`);
      return token;
    });
    if (kwPattern) {
      codePart = codePart.replace(kwPattern, '<span class="tok-kw">$1</span>');
    }
    codePart = codePart.replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="tok-num">$1</span>');
    codePart = codePart.replace(/\u0000STR(\d+)\u0000/g, (_, i) => placeholders[Number(i)]);
    return codePart + commentPart;
  }).join('\n');
}

export const SANDBOX_CSP =
  "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; font-src 'none'; connect-src 'none'; media-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none';";

const FORBIDDEN_PREVIEW_HTML_PATTERNS = [
  /<\s*script\b/i,
  /<\s*iframe\b/i,
  /<\s*object\b/i,
  /<\s*embed\b/i,
  /<\s*meta\b/i,
  /<\s*base\b/i,
  /<\s*form\b/i,
  /\bjavascript\s*:/i,
  /\btarget\s*=\s*["']?\s*_(top|parent|blank)/i
];

export function assertSafePreviewMarkup(html = '', css = '', js = '') {
  const htmlStr = String(html || '');
  const cssStr = String(css || '');
  const jsStr = String(js || '');
  for (const re of FORBIDDEN_PREVIEW_HTML_PATTERNS) {
    if (re.test(htmlStr)) {
      throw new Error(`Unsafe preview HTML rejected by sanitizer (matched ${re}).`);
    }
  }
  if (/@import\b/i.test(cssStr) || /url\(\s*["']?\s*https?:/i.test(cssStr)) {
    throw new Error('Unsafe preview CSS rejected: external @import or http(s) url() is forbidden.');
  }
  if (/\b(?:top|parent)\.location\b/i.test(jsStr) || /\bwindow\.open\s*\(/i.test(jsStr)) {
    throw new Error('Unsafe preview JS rejected: top/parent navigation and window.open are forbidden.');
  }
}

export function sanitizePreviewHtml(html = '') {
  return String(html || '')
    .replace(/<\s*(script|iframe|object|embed|meta|base|form)\b[\s\S]*?(?:<\s*\/\s*\1\s*>|$)/gi, '')
    .replace(/\bjavascript\s*:/gi, 'blocked:')
    .replace(/\btarget\s*=\s*(["'])\s*_(?:top|parent|blank)\s*\1/gi, 'target="_self"');
}

export function buildSandboxSrcDoc({ html = '', css = '', js = '', channel = 'otter-preview' }) {
  // Runs ONLY inside <iframe sandbox="allow-scripts" referrerpolicy="no-referrer"> (no allow-same-origin).
  const safeHtml = sanitizePreviewHtml(html);
  // Neutralize closing tag breakouts and HTML comment openers inside <style> and <script>
  const safeCss = String(css || '').replace(/<\s*\/\s*style/gi, '<\\/style');
  const safeJs = String(js || '')
    .replace(/<\s*\/\s*script/gi, '<\\/script')
    .replace(/<!--/g, '<\\!--');
  const safeChannel = JSON.stringify(String(channel || 'otter-preview'));

  const varBridge = `
(function() {
  var EXPECTED_CHANNEL = ${safeChannel};
  var SAFE_VAR_NAME = /^--[a-zA-Z0-9-]{1,40}$/;
  var SAFE_VAR_VAL = /^(#[0-9a-fA-F]{3,8}|-?[0-9]{1,4}(?:\\.[0-9]{1,2})?(?:px|rem|em|%|s|ms|deg)?|rgba?\\([0-9.,\\s%]+\\))$/;

  window.addEventListener('message', function(ev) {
    if (ev.source !== window.parent) return;
    var data = ev && ev.data;
    if (!data || typeof data !== 'object') return;
    if (data.type !== 'otter-lib-vars' || data.channel !== EXPECTED_CHANNEL) return;
    if (!data.vars || typeof data.vars !== 'object' || Array.isArray(data.vars)) return;
    var root = document.documentElement;
    Object.keys(data.vars).forEach(function(k) {
      var val = String(data.vars[k]).trim();
      if (SAFE_VAR_NAME.test(k) && SAFE_VAR_VAL.test(val)) {
        root.style.setProperty(k, val);
      }
    });
  });

  // Prevent unintended external or top-level navigation from anchor clicks inside preview
  document.addEventListener('click', function(ev) {
    var link = ev.target && ev.target.closest ? ev.target.closest('a[href]') : null;
    if (!link) return;
    var href = (link.getAttribute('href') || '').trim();
    if (!href.startsWith('#')) {
      ev.preventDefault();
    }
  });
})();`;

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="${SANDBOX_CSP}">
<style>
${safeCss}
</style>
</head>
<body>
${safeHtml}
<script>
${varBridge}
${safeJs}
</script>
</body>
</html>`;
}
