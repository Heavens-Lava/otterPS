// web-compiler.js - Compiles Otter UI Model and lossless CSS AST into production HTML/CSS/JS

export function compileToHtmlDocument(uiModel, cssAstManager) {
  const root = uiModel.getRoot();
  if (!root) {
    return '<html><body style="background:#0f172a;color:#cbd5e1;font-family:sans-serif;padding:20px;">No UI structure defined.</body></html>';
  }

  const { html, js } = compileUiTree(root, uiModel);
  const userCss = cssAstManager ? cssAstManager.generateCss() : '';

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(root.properties.title || 'Otter Application')}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
  <style>
    /* Reset & Base System Styles */
    *, *::before, *::after {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    body {
      background-color: #0b0f19;
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      min-height: 100vh;
      display: flex;
      justify-content: center;
      align-items: center;
      padding: 24px;
      overflow-x: hidden;
    }
    .otter-window {
      position: relative;
      box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.6), 0 0 0 1px rgba(255, 255, 255, 0.08);
    }
    .otter-row {
      display: flex;
      flex-direction: row;
    }
    .otter-column {
      display: flex;
      flex-direction: column;
    }
    .otter-scroll {
      overflow-y: auto;
      scrollbar-width: thin;
      scrollbar-color: #475569 transparent;
    }
    .otter-scroll::-webkit-scrollbar {
      width: 6px;
    }
    .otter-scroll::-webkit-scrollbar-thumb {
      background-color: #475569;
      border-radius: 3px;
    }
    button.otter-btn {
      font-family: inherit;
      outline: none;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      transition: all 0.15s ease;
    }
    button.otter-btn:hover {
      filter: brightness(1.1);
      transform: translateY(-1px);
    }
    button.otter-btn:active {
      transform: translateY(0);
      filter: brightness(0.95);
    }
    input.otter-input, select.otter-select {
      font-family: inherit;
      outline: none;
      transition: border-color 0.15s ease, box-shadow 0.15s ease;
    }
    input.otter-input:focus, select.otter-select:focus {
      border-color: #3b82f6;
      box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.2);
    }

    /* User Authoritative CSS Stylesheet (app.css) */
    ${userCss}
  </style>
</head>
<body>
  <div class="otter-window" id="${root.name}">
    ${html}
  </div>

  <script>
    // Otter Client Runtime
    (function() {
      window.otter = {
        say: function(...args) {
          console.log('[Otter Output]:', ...args);
          window.parent?.postMessage({ type: 'otter-log', message: args.join(' ') }, '*');
        },
        text: function(elId, val) {
          const el = document.getElementById(elId);
          if (!el) return '';
          if (val !== undefined) {
            if (el.tagName === 'INPUT' || el.tagName === 'SELECT') el.value = val;
            else el.innerText = val;
          }
          return el.tagName === 'INPUT' || el.tagName === 'SELECT' ? el.value : el.innerText;
        }
      };

      ${js}
    })();
  </script>
</body>
</html>`;
}

function compileUiTree(root, uiModel) {
  let jsStatements = [];

  function compileComponent(comp) {
    if (!comp) return '';

    const id = comp.name;
    const props = comp.properties || {};

    let innerHtml = '';
    if (comp.children && comp.children.length > 0) {
      innerHtml = comp.children
        .map(cId => compileComponent(uiModel.getComponent(cId)))
        .join('\n');
    }

    // Attach user events
    const events = uiModel.getEvents(comp.id);
    for (const [eventKind, code] of Object.entries(events)) {
      if (!code || !code.trim()) continue;
      const domEvent = eventKind === 'clicked' ? 'click' : 'input';
      jsStatements.push(`
        document.getElementById('${id}')?.addEventListener('${domEvent}', function(e) {
          try {
            ${transpileOtterToJs(code, comp)}
          } catch(err) {
            console.error('Otter handler error on ${id}:', err);
          }
        });
      `);
    }

    switch (comp.kind) {
      case 'row':
        return `<div class="otter-row" id="${id}">${innerHtml}</div>`;
      case 'column':
        return `<div class="otter-column" id="${id}">${innerHtml}</div>`;
      case 'card':
        return `<div class="otter-card task-item" id="${id}">${innerHtml}</div>`;
      case 'scroll':
        return `<div class="otter-scroll" id="${id}">${innerHtml}</div>`;
      case 'heading':
        return `<h2 id="${id}">${escapeHtml(props.text || '')}</h2>`;
      case 'text':
        return `<p id="${id}">${escapeHtml(props.text || '')}</p>`;
      case 'button':
      case 'primary button':
      case 'danger button':
        return `<button class="otter-btn" id="${id}">${escapeHtml(props.text || 'Button')}</button>`;
      case 'text box':
        return `<input type="text" class="otter-input" id="${id}" placeholder="${escapeHtml(props.placeholder || '')}" value="${escapeHtml(props.text || '')}" />`;
      case 'checkbox':
        const checkedAttr = props.checked ? 'checked' : '';
        return `<label style="display:inline-flex;align-items:center;gap:8px;cursor:pointer;" id="label_${id}">
          <input type="checkbox" id="${id}" ${checkedAttr} style="accent-color:#3b82f6;width:16px;height:16px;" />
          <span style="font-size:14px;color:#cbd5e1">${escapeHtml(props.text || '')}</span>
        </label>`;
      case 'slider':
        return `<input type="range" id="${id}" min="${props.minimum || 0}" max="${props.maximum || 100}" value="${props.value || 50}" style="accent-color:#3b82f6;cursor:pointer;" />`;
      case 'dropdown':
        return `<select class="otter-select" id="${id}">
          <option value="" disabled selected>${escapeHtml(props.placeholder || 'Select...')}</option>
          <option value="1">Option 1</option>
          <option value="2">Option 2</option>
        </select>`;
      case 'progress bar':
        const pct = Math.min(100, Math.max(0, ((props.value || 0) / (props.maximum || 100)) * 100));
        return `<div id="${id}" style="height:8px;border-radius:99px;overflow:hidden;width:100%;background:#1e293b;">
          <div style="background:#3b82f6;width:${pct}%;height:100%;transition:width 0.3s ease;"></div>
        </div>`;
      case 'image':
        return `<img id="${id}" src="${escapeHtml(props.source || '')}" alt="Otter Resource" style="object-fit:cover;" />`;
      default:
        return `<div id="${id}">${innerHtml}</div>`;
    }
  }

  const html = root.children
    .map(cId => compileComponent(uiModel.getComponent(cId)))
    .join('\n');

  return {
    html,
    js: jsStatements.join('\n')
  };
}

function transpileOtterToJs(otterCode, comp) {
  const lines = otterCode.split('\n');
  const jsLines = [];

  for (let raw of lines) {
    let line = raw.trim();
    if (!line || line.startsWith('#')) continue;

    // say "text"
    if (line.startsWith('say ')) {
      const expr = line.slice(4).trim();
      jsLines.push(`otter.say(${expr});`);
      continue;
    }

    // add <num> to <target>
    const addMatch = line.match(/^add\s+(\d+)\s+to\s+([a-zA-Z0-9_]+)$/i);
    if (addMatch) {
      const amt = parseInt(addMatch[1], 10);
      const target = addMatch[2];
      jsLines.push(`
        (function() {
          const el = document.getElementById('${target}');
          if (el) {
            const curVal = parseInt(el.value || el.innerText || '0', 10);
            if (!isNaN(curVal)) {
              const nextVal = curVal + ${amt};
              if (el.tagName === 'INPUT') el.value = nextVal;
              else el.innerText = nextVal;
              otter.say('Added ${amt} to ${target}: ' + nextVal);
            }
          }
        })();
      `);
      continue;
    }

    // remove <num> from <target> / subtract <num> from <target>
    const subMatch = line.match(/^(?:remove|subtract)\s+(\d+)\s+from\s+([a-zA-Z0-9_]+)$/i);
    if (subMatch) {
      const amt = parseInt(subMatch[1], 10);
      const target = subMatch[2];
      jsLines.push(`
        (function() {
          const el = document.getElementById('${target}');
          if (el) {
            const curVal = parseInt(el.value || el.innerText || '0', 10);
            if (!isNaN(curVal)) {
              const nextVal = Math.max(0, curVal - ${amt});
              if (el.tagName === 'INPUT') el.value = nextVal;
              else el.innerText = nextVal;
              otter.say('Subtracted ${amt} from ${target}: ' + nextVal);
            }
          }
        })();
      `);
      continue;
    }

    // target has text ""
    const hasMatch = line.match(/^([a-zA-Z0-9_]+)\s+has\s+text\s+(.*)$/i);
    if (hasMatch) {
      const target = hasMatch[1];
      const val = hasMatch[2];
      jsLines.push(`otter.text('${target}', ${val});`);
      continue;
    }

    // target has value ""
    const valMatch = line.match(/^([a-zA-Z0-9_]+)\s+has\s+value\s+(.*)$/i);
    if (valMatch) {
      const target = valMatch[1];
      const val = valMatch[2];
      jsLines.push(`(function() { const el = document.getElementById('${target}'); if (el) el.value = ${val}; })();`);
      continue;
    }

    // default raw statement execution fallback
    jsLines.push(`// Otter: ${line}`);
  }

  return jsLines.join('\n');
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
