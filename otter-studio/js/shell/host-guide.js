// host-guide.js - "Where will you put it?" after Build > Publish...
//
// An Otter website is plain files (pages, their pictures), so any static host
// serves the published folder as it is: no host settings are needed. This
// dialog gives the steps for a few common hosts, naming the folder and .zip
// Publish just made. Nothing is uploaded from Studio; no account is touched.
// (Steps checked 2026-09-30.)

const HOSTS = [
  {
    id: 'netlify',
    name: 'Netlify Drop',
    url: 'https://app.netlify.com/drop',
    steps: (p) => [
      `Open <a href="https://app.netlify.com/drop" target="_blank" rel="noopener noreferrer">app.netlify.com/drop</a>.`,
      `Drag the folder <code>${p.folder}</code> onto the page.`,
      'A few seconds later Netlify gives you a live address.',
      'Without an account the site is temporary: claim it (a free account) to keep it, and to drop a new version later.'
    ]
  },
  {
    id: 'github',
    name: 'GitHub Pages',
    url: 'https://github.com/new',
    steps: (p) => [
      `Create a repository on <a href="https://github.com/new" target="_blank" rel="noopener noreferrer">github.com/new</a> (public, for a free Pages site).`,
      `In it: Add file &gt; Upload files, and drop in everything inside <code>${p.folder}</code> (index.html at the top, not inside a folder). Commit.`,
      'Settings &gt; Pages: Source "Deploy from a branch", branch main, folder / (root). Save.',
      'A minute later the site is at https://&lt;your-name&gt;.github.io/&lt;repository&gt;/.'
    ]
  },
  {
    id: 'cloudflare',
    name: 'Cloudflare Pages',
    url: 'https://dash.cloudflare.com/',
    steps: (p) => [
      `In the <a href="https://dash.cloudflare.com/" target="_blank" rel="noopener noreferrer">Cloudflare dashboard</a>: Workers &amp; Pages &gt; Create application &gt; Drag and drop your files.`,
      'Give the project a name.',
      `Drop the folder <code>${p.folder}</code>${p.zip ? ` (or <code>${p.zip}</code>)` : ''} and choose Deploy.`,
      'The site is at https://&lt;project-name&gt;.pages.dev.'
    ]
  },
  {
    id: 'own',
    name: 'Your own host',
    url: '',
    steps: (p) => [
      `Copy everything inside <code>${p.folder}</code> to your web server's site folder (FTP, your host's file manager, or <code>${p.zip || 'the .zip'}</code> unpacked there).`,
      'index.html is the home page; keep the folders (assets/...) next to it as they are.',
      'Nothing needs to run on the server: the pages are plain HTML, CSS and JavaScript.'
    ]
  }
];

const escapeHtml = (s) => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// folder: the published folder to upload; zip: its .zip; reveal(): shows the
// folder in the file manager.
export function showHostGuide({ folder, zip = '', reveal = null } = {}) {
  document.querySelector('.host-guide-backdrop')?.remove();
  const place = { folder: escapeHtml(folder), zip: escapeHtml(zip) };
  const backdrop = document.createElement('div');
  backdrop.className = 'modal-backdrop ask-backdrop host-guide-backdrop';
  backdrop.style.display = 'flex';
  backdrop.innerHTML = `
    <div class="modal-dialog ask-dialog host-guide" role="dialog" aria-modal="true" aria-labelledby="hostGuideTitle">
      <div class="modal-header">
        <div class="modal-title-wrap">
          <h2 class="modal-title" id="hostGuideTitle">Put your website online</h2>
          <p class="modal-subtitle">Your site is plain files, so any of these serves it as it is. Pick where it goes:</p>
        </div>
        <button type="button" class="modal-close-btn" data-guide-close title="Close (Esc)">✕</button>
      </div>
      <div class="modal-body">
        <div class="host-guide-tabs" role="tablist">
          ${HOSTS.map((h, i) => `<button type="button" role="tab" class="host-guide-tab${i === 0 ? ' is-active' : ''}" data-host="${h.id}" aria-selected="${i === 0}">${h.name}</button>`).join('')}
        </div>
        <ol class="host-guide-steps" role="tabpanel"></ol>
      </div>
      <div class="modal-footer">
        <div class="modal-footer-left"></div>
        <div class="modal-footer-right">
          ${reveal ? '<button type="button" class="btn-modal-cancel" data-guide-reveal>Show the folder</button>' : ''}
          <button type="button" class="btn-modal-primary" data-guide-close>Done</button>
        </div>
      </div>
    </div>`;
  const list = backdrop.querySelector('.host-guide-steps');
  const choose = (id) => {
    const host = HOSTS.find(h => h.id === id) || HOSTS[0];
    list.innerHTML = host.steps(place).map(step => `<li>${step}</li>`).join('');
    backdrop.querySelectorAll('.host-guide-tab').forEach(tab => {
      const on = tab.dataset.host === host.id;
      tab.classList.toggle('is-active', on);
      tab.setAttribute('aria-selected', String(on));
    });
  };
  choose(HOSTS[0].id);
  backdrop.querySelectorAll('.host-guide-tab').forEach(tab => tab.addEventListener('click', () => choose(tab.dataset.host)));
  const close = () => { backdrop.remove(); document.removeEventListener('keydown', onKey, true); };
  const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(); } };
  backdrop.querySelectorAll('[data-guide-close]').forEach(b => b.addEventListener('click', close));
  backdrop.querySelector('[data-guide-reveal]')?.addEventListener('click', () => reveal());
  backdrop.addEventListener('mousedown', (e) => { if (e.target === backdrop) close(); });
  document.addEventListener('keydown', onKey, true);
  document.body.appendChild(backdrop);
  setTimeout(() => backdrop.querySelector('.host-guide-tab.is-active')?.focus(), 20);
  return { choose, close };
}
