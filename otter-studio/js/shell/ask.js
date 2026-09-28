// ask.js - A small text-input dialog: askText({ title, message, value }).
//
// Studio used window.prompt(), which the Otter Studio desktop app (Electron)
// does not implement - it returns nothing, so New File, Go to Line, Extract
// Function and the Git stash/tag/remote actions silently did nothing there.
// This dialog works in the browser and the desktop app alike, matches the
// workbench theme, and can check the value before accepting it.
//
// Resolves to the entered text, or null when cancelled (like prompt()).

let open = null;

export function askText({ title = 'Otter Studio', message = '', value = '', placeholder = '', okLabel = 'OK', validate = null } = {}) {
  if (open) open.cancel();
  return new Promise((resolve) => {
    const backdrop = document.createElement('div');
    backdrop.className = 'modal-backdrop ask-backdrop';
    backdrop.style.display = 'flex';
    backdrop.innerHTML = `
      <form class="modal-dialog ask-dialog" role="dialog" aria-modal="true" aria-labelledby="askTitle" novalidate>
        <div class="modal-header">
          <div class="modal-title-wrap">
            <h2 class="modal-title" id="askTitle"></h2>
            ${message ? '<p class="modal-subtitle ask-message"></p>' : ''}
          </div>
          <button type="button" class="modal-close-btn" data-ask-cancel title="Cancel (Esc)">✕</button>
        </div>
        <div class="modal-body ask-body">
          <input class="config-input ask-input" type="text" spellcheck="false" autocomplete="off" />
          <div class="ask-error" role="alert" hidden></div>
        </div>
        <div class="modal-footer">
          <div class="modal-footer-left"></div>
          <div class="modal-footer-right">
            <button type="button" class="btn-modal-cancel" data-ask-cancel>Cancel</button>
            <button type="submit" class="btn-modal-primary"></button>
          </div>
        </div>
      </form>`;
    backdrop.querySelector('#askTitle').textContent = title;
    if (message) backdrop.querySelector('.ask-message').textContent = message;
    backdrop.querySelector('.btn-modal-primary').textContent = okLabel;
    const input = backdrop.querySelector('.ask-input');
    const error = backdrop.querySelector('.ask-error');
    input.value = value;
    input.placeholder = placeholder;
    document.body.appendChild(backdrop);
    const previousFocus = document.activeElement;

    const finish = (result) => {
      backdrop.remove();
      document.removeEventListener('keydown', onKey, true);
      open = null;
      previousFocus?.focus?.({ preventScroll: true });
      resolve(result);
    };
    const onKey = (e) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        finish(null);
      }
    };
    backdrop.querySelector('form').addEventListener('submit', (e) => {
      e.preventDefault();
      const problem = validate ? validate(input.value) : null;
      if (problem) {
        error.textContent = problem;
        error.hidden = false;
        input.focus();
        return;
      }
      finish(input.value);
    });
    input.addEventListener('input', () => { error.hidden = true; });
    backdrop.querySelectorAll('[data-ask-cancel]').forEach(b => b.addEventListener('click', () => finish(null)));
    backdrop.addEventListener('mousedown', (e) => { if (e.target === backdrop) finish(null); });
    document.addEventListener('keydown', onKey, true);
    open = { cancel: () => finish(null) };
    setTimeout(() => { input.focus(); input.select(); }, 20);
  });
}
