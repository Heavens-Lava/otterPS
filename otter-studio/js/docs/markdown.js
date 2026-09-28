// markdown.js - A small, safe Markdown renderer for Studio's docs viewer.
//
// Everything is HTML-escaped first; only the Markdown this repository's docs
// use becomes markup: headings, paragraphs, fenced code, lists (nested by
// indentation), block quotes, tables, rules, and inline code, bold, italic
// and links. Raw HTML in a document is shown as text, never run.
// Returns { html, headings: [{ level, text, id }] } for the outline.

export function renderMarkdown(source) {
  const lines = String(source || '').replace(/\r\n?/g, '\n').split('\n');
  const out = [];
  const headings = [];
  const usedIds = new Map();
  let i = 0;

  const slug = (text) => {
    const base = text.toLowerCase().replace(/<[^>]+>/g, '').replace(/[^a-z0-9 -]/g, '').trim().replace(/\s+/g, '-') || 'section';
    const n = usedIds.get(base) || 0;
    usedIds.set(base, n + 1);
    return n ? `${base}-${n}` : base;
  };

  while (i < lines.length) {
    const line = lines[i];

    // Fenced code block.
    const fence = line.match(/^\s*(```|~~~)\s*([\w-]*)\s*$/);
    if (fence) {
      const body = [];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith(fence[1])) body.push(lines[i++]);
      i++;
      out.push(`<pre class="md-code"${fence[2] ? ` data-lang="${escapeHtml(fence[2])}"` : ''}><code>${escapeHtml(body.join('\n'))}</code></pre>`);
      continue;
    }

    if (!line.trim()) { i++; continue; }

    const heading = line.match(/^(#{1,6})\s+(.*?)\s*#*\s*$/);
    if (heading) {
      const level = heading[1].length;
      const text = heading[2];
      const id = slug(text);
      headings.push({ level, text: stripInline(text), id });
      out.push(`<h${level} id="${id}">${inline(text)}</h${level}>`);
      i++;
      continue;
    }

    if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) {
      out.push('<hr>');
      i++;
      continue;
    }

    // Table: a header row, then a |---|---| separator.
    if (line.includes('|') && i + 1 < lines.length && /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/.test(lines[i + 1])) {
      const cells = (row) => row.trim().replace(/^\||\|$/g, '').split(/(?<!\\)\|/).map(c => inline(c.trim().replace(/\\\|/g, '|')));
      const head = cells(line);
      i += 2;
      const rows = [];
      while (i < lines.length && lines[i].includes('|') && lines[i].trim()) rows.push(cells(lines[i++]));
      out.push(`<div class="md-table-wrap"><table><thead><tr>${head.map(c => `<th>${c}</th>`).join('')}</tr></thead><tbody>${rows.map(r => `<tr>${r.map(c => `<td>${c}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`);
      continue;
    }

    if (/^\s*>/.test(line)) {
      const body = [];
      while (i < lines.length && /^\s*>/.test(lines[i])) body.push(lines[i++].replace(/^\s*>\s?/, ''));
      out.push(`<blockquote>${renderMarkdown(body.join('\n')).html}</blockquote>`);
      continue;
    }

    // Lists (- * + or 1.), nested by indentation.
    if (/^\s*([-*+]|\d+\.)\s+/.test(line)) {
      const items = [];
      while (i < lines.length && (/^\s*([-*+]|\d+\.)\s+/.test(lines[i]) || (lines[i].trim() && /^\s{2,}/.test(lines[i]) && items.length))) {
        const m = lines[i].match(/^(\s*)([-*+]|\d+\.)\s+(.*)$/);
        if (m) items.push({ indent: m[1].length, ordered: /\d/.test(m[2]), text: m[3] });
        else items[items.length - 1].text += ' ' + lines[i].trim();
        i++;
      }
      // Consecutive lists of different kinds (bullets, then numbers) stay separate.
      for (let at = 0; at < items.length;) {
        const list = renderList(items, at);
        out.push(list.html);
        at = list.next;
      }
      continue;
    }

    // Paragraph: until a blank line or another block.
    const para = [];
    while (i < lines.length && lines[i].trim() && !/^(#{1,6}\s|\s*(```|~~~)|\s*>|\s*([-*+]|\d+\.)\s+)/.test(lines[i])) para.push(lines[i++].trim());
    out.push(`<p>${inline(para.join(' '))}</p>`);
  }
  return { html: out.join('\n'), headings };
}

function renderList(items, start) {
  const indent = items[start].indent;
  const ordered = items[start].ordered;
  let html = ordered ? '<ol>' : '<ul>';
  let i = start;
  while (i < items.length && items[i].indent >= indent && !(items[i].indent === indent && items[i].ordered !== ordered)) {
    if (items[i].indent > indent) {
      const nested = renderList(items, i);
      html = html.replace(/<\/li>$/, `${nested.html}</li>`);
      i = nested.next;
      continue;
    }
    html += `<li>${inline(items[i].text)}</li>`;
    i++;
  }
  return { html: html + (ordered ? '</ol>' : '</ul>'), next: i };
}

// Inline Markdown on escaped text. Code spans are protected first.
function inline(text) {
  const codes = [];
  let s = escapeHtml(text).replace(/`([^`]+)`/g, (_, c) => { codes.push(c); return `\u0000${codes.length - 1}\u0000`; });
  s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, label, href) => {
    const safe = /^(https?:|mailto:|#|[\w./-]+(\.md)?(#[\w-]+)?$)/i.test(href) ? href : '#';
    const external = /^https?:/i.test(safe);
    return `<a href="${safe}"${external ? ' target="_blank" rel="noopener"' : ' data-doc-link'}>${label}</a>`;
  });
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>').replace(/__([^_]+)__/g, '<strong>$1</strong>');
  s = s.replace(/(^|[^*])\*([^*\s][^*]*)\*/g, '$1<em>$2</em>').replace(/(^|\W)_([^_\s][^_]*)_(?=\W|$)/g, '$1<em>$2</em>');
  return s.replace(/\u0000(\d+)\u0000/g, (_, n) => `<code>${codes[Number(n)]}</code>`);
}

function stripInline(text) {
  return text.replace(/[`*_]/g, '').replace(/\[([^\]]+)\]\([^)]*\)/g, '$1');
}

export function escapeHtml(str) {
  return String(str ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
