const commands = [
  { id: 'install', label: 'Install Official Pack', shortcut: 'I', command: 'otter pack install otter-official/math-utils' },
  { id: 'verify', label: 'Verify Pack Contracts', shortcut: 'V', command: 'otter pack verify --contracts' },
  { id: 'plan', label: 'Plan Multi-Pack Workflow', shortcut: 'P', command: 'otter compose plan --workflow app.workflow.json --explain' },
  { id: 'check', label: 'Static Check Project', shortcut: 'C', command: 'otter check src/main.ot' }
];

const input = document.getElementById('palInput');
const list = document.getElementById('palList');
const status = document.getElementById('palStatus');
let activeIndex = 0;

function filtered() {
  const q = (input.value || '').trim().toLowerCase();
  return q ? commands.filter((c) => c.label.toLowerCase().includes(q) || c.command.toLowerCase().includes(q)) : commands;
}

function render() {
  const items = filtered();
  activeIndex = Math.max(0, Math.min(activeIndex, items.length - 1));
  list.innerHTML = items.map((item, idx) =>
    `<li class="pal-item" role="option" data-idx="${idx}" aria-selected="${idx === activeIndex}"><span>${item.label}</span><kbd>${item.shortcut}</kbd></li>`
  ).join('') || '<li class="pal-item">No matching commands</li>';
}

function selectCurrent() {
  const items = filtered();
  const chosen = items[activeIndex];
  if (chosen) status.textContent = `Selected: ${chosen.command}`;
}

input.addEventListener('input', () => { activeIndex = 0; render(); });
input.addEventListener('keydown', (e) => {
  const count = filtered().length;
  if (!count) return;
  if (e.key === 'ArrowDown') { e.preventDefault(); activeIndex = (activeIndex + 1) % count; render(); }
  else if (e.key === 'ArrowUp') { e.preventDefault(); activeIndex = (activeIndex - 1 + count) % count; render(); }
  else if (e.key === 'Enter') { e.preventDefault(); selectCurrent(); }
});
list.addEventListener('click', (e) => {
  const li = e.target.closest('.pal-item[data-idx]');
  if (!li) return;
  activeIndex = Number(li.dataset.idx);
  render();
  selectCurrent();
});

render();
