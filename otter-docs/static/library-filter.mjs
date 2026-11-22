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

export function buildSandboxSrcDoc({ html = '', css = '', js = '' }) {
  // Runs ONLY inside <iframe sandbox="allow-scripts" referrerpolicy="no-referrer"> (no allow-same-origin).
  const safeJs = String(js || '').replace(/<\/script>/gi, '<\\/script>');
  const varBridge = `
window.addEventListener('message', function(ev) {
  var data = ev && ev.data;
  if (!data || data.type !== 'otter-lib-vars' || !data.vars) return;
  var root = document.documentElement;
  Object.keys(data.vars).forEach(function(k) {
    if (/^--[a-zA-Z0-9-]+$/.test(k)) root.style.setProperty(k, String(data.vars[k]));
  });
});`;
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
${css}
</style>
</head>
<body>
${html}
<script>
${varBridge}
${safeJs}
</script>
</body>
</html>`;
}
