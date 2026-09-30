// events.js - A component's events, and the way into their handlers.
//
// Handlers are written in the code editor, like Visual Studio's code-behind:
// Add handler writes `when <name> is <event>` into the source with a first
// line to replace, shows the code beside the design (Split) and selects that
// line. The panel shows what each handler does and opens it; it never edits
// code itself (a small textarea here had no highlighting, completion or
// indentation, and lost the caret on every keystroke).

import { ComponentSchema } from '../model/schema.js';

export function renderEvents(containerEl, uiModel) {
  function update() {
    const selected = uiModel.getComponent(uiModel.selectedId);
    if (!selected) {
      containerEl.innerHTML = `
        <div class="events-header"><span class="panel-title">Events</span></div>
        <div class="empty-state">No component selected</div>
      `;
      return;
    }

    const schema = ComponentSchema[selected.kind] || {};
    const availableEvents = schema.events || [];
    const currentEvents = uiModel.getEvents(selected.id);

    containerEl.innerHTML = `
      <div class="events-header">
        <span class="panel-title">Events</span>
        <span class="badge badge-accent">${escapeHtml(selected.name)}</span>
      </div>
      <div class="events-body">
        ${availableEvents.length === 0 ? `
          <div class="empty-state" style="padding:16px;">
            A ${escapeHtml(schema.label?.toLowerCase() || selected.kind)} has no events in Otter.
          </div>
        ` : `
          <div class="events-list">
            ${availableEvents.map(eventKind => {
              const body = currentEvents[eventKind];
              const has = body !== undefined;
              return `
              <div class="event-card ${has ? 'has-handler' : ''}" data-event="${eventKind}">
                <div class="event-card-header">
                  <span class="event-name"><span class="event-when">when</span> ${escapeHtml(selected.name)} <span class="event-when">is</span> ${escapeHtml(eventKind)}</span>
                  ${has
                    ? `<button type="button" class="event-edit-btn" data-event="${eventKind}" title="Open this handler in the code editor">Edit in code</button>`
                    : `<button type="button" class="event-add-btn" data-event="${eventKind}" title="Write what happens, in the code editor">Add handler</button>`}
                </div>
                ${has ? `
                  <button type="button" class="event-preview" data-event="${eventKind}" title="Open in the code editor">${escapeHtml(preview(body))}</button>
                  <div class="event-card-footer">
                    <button type="button" class="event-remove-btn" data-event="${eventKind}">Remove handler</button>
                  </div>` : ''}
              </div>`;
            }).join('')}
          </div>
          <p class="events-hint">Handlers are Otter code: they open in the editor beside the design.</p>
        `}
      </div>
    `;

    bindEvents(containerEl, selected);
  }

  function bindEvents(containerEl, selected) {
    containerEl.querySelectorAll('.event-add-btn').forEach(btn => btn.addEventListener('click', async () => {
      const eventKind = btn.getAttribute('data-event');
      // A first line to replace: selected in the editor, so typing replaces it.
      uiModel.setEvent(selected.id, eventKind, `say "${selected.name} was ${eventKind}"`);
      await openHandler(selected, eventKind, { selectBody: true });
    }));
    containerEl.querySelectorAll('.event-edit-btn, .event-preview').forEach(btn => btn.addEventListener('click', () => {
      openHandler(selected, btn.getAttribute('data-event'));
    }));
    containerEl.querySelectorAll('.event-remove-btn').forEach(btn => btn.addEventListener('click', () => {
      const eventKind = btn.getAttribute('data-event');
      if (!window.confirm(`Remove the handler "when ${selected.name} is ${eventKind}" and its code?`)) return;
      uiModel.removeEvent(selected.id, eventKind);
      update();
    }));
  }

  update();
  uiModel.subscribe((type) => {
    if (type === 'select' || type === 'event' || type === 'rename' || type === 'parse' || type === 'template') {
      update();
    }
  });
}

// The code beside the design (Split, unless code is already on screen), the
// cursor at the handler's first line; selectBody selects that line.
export async function openHandler(comp, eventKind, { selectBody = false } = {}) {
  const ide = window.otterIde;
  if (!ide) return false;
  const mode = document.body.dataset.studioMode;
  if (!['split', 'workbench', 'code'].includes(mode)) document.getElementById('pillSplitMode')?.click();
  await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  const lines = String(ide.currentCode || '').split('\n');
  const head = lines.findIndex(l => new RegExp(`^\\s*when\\s+${escapeRegExp(comp.name)}\\s+(?:is\\s+)?${escapeRegExp(eventKind)}\\b`).test(l));
  if (head < 0) return false;
  const bodyIndex = Math.min(head + 1, lines.length - 1);
  const indent = (lines[bodyIndex].match(/^\s*/) || [''])[0].length;
  ide.goToLine(bodyIndex + 1, indent);
  const textarea = document.getElementById('hiddenEditorInput');
  if (textarea) {
    const lineStart = lines.slice(0, bodyIndex).reduce((sum, l) => sum + l.length + 1, 0);
    textarea.focus();
    if (selectBody) textarea.setSelectionRange(lineStart + indent, lineStart + lines[bodyIndex].length);
    else textarea.setSelectionRange(lineStart + indent, lineStart + indent);
  }
  return true;
}

// The first lines of a handler, for the panel.
function preview(body) {
  const lines = String(body).split('\n').map(l => l.replace(/\s+$/, '')).filter(l => l.trim());
  const shown = lines.slice(0, 4).join('\n');
  return lines.length > 4 ? `${shown}\n…` : shown || '(empty)';
}

function escapeRegExp(text) {
  return String(text).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function escapeHtml(str) {
  return String(str || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
