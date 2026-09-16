// events.js - Event handler inspector for wiring Otter actions

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
        <span class="badge badge-accent">${selected.name}</span>
      </div>
      <div class="events-body">
        ${availableEvents.length === 0 ? `
          <div class="empty-state" style="padding:16px;">
            A <code>${selected.kind}</code> has no interactive events in Otter.
          </div>
        ` : `
          <div class="events-list">
            ${availableEvents.map(eventKind => `
              <div class="event-card" data-event="${eventKind}">
                <div class="event-card-header">
                  <div class="event-name-badge">
                    <span class="event-dot"></span>
                    <span class="event-name">when ${selected.name} is ${eventKind}</span>
                  </div>
                  <button class="event-toggle-btn ${currentEvents[eventKind] !== undefined ? 'is-active' : ''}" data-event="${eventKind}">
                    ${currentEvents[eventKind] !== undefined ? 'Configured' : '+ Add'}
                  </button>
                </div>
                ${currentEvents[eventKind] !== undefined ? `
                  <div class="event-editor-wrap">
                    <textarea class="event-code-textarea" data-event="${eventKind}" placeholder="say \"Action triggered\"&#10;text of resultBox is \"Success\"">${escapeHtml(currentEvents[eventKind])}</textarea>
                    <div class="event-editor-footer">
                      <span class="event-hint">Otter statements run when this fires</span>
                      <button class="event-remove-btn" data-event="${eventKind}">Remove</button>
                    </div>
                  </div>
                ` : ''}
              </div>
            `).join('')}
          </div>
        `}
      </div>
    `;

    bindEvents(containerEl, selected);
  }

  function bindEvents(containerEl, selected) {
    const toggleBtns = containerEl.querySelectorAll('.event-toggle-btn');
    toggleBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        const eventKind = btn.getAttribute('data-event');
        const currentEvents = uiModel.getEvents(selected.id);
        if (currentEvents[eventKind] !== undefined) {
          uiModel.removeEvent(selected.id, eventKind);
        } else {
          uiModel.setEvent(selected.id, eventKind, `say "Clicked ${selected.name}"`);
        }
        update();
      });
    });

    const textareas = containerEl.querySelectorAll('.event-code-textarea');
    textareas.forEach(textarea => {
      textarea.addEventListener('input', (e) => {
        const eventKind = e.target.getAttribute('data-event');
        uiModel.setEvent(selected.id, eventKind, e.target.value);
      });
    });

    const removeBtns = containerEl.querySelectorAll('.event-remove-btn');
    removeBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        const eventKind = btn.getAttribute('data-event');
        uiModel.removeEvent(selected.id, eventKind);
        update();
      });
    });
  }

  update();
  uiModel.subscribe((type) => {
    if (type === 'select' || type === 'event' || type === 'rename' || type === 'parse' || type === 'template') {
      update();
    }
  });
}

function escapeHtml(str) {
  return String(str || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
