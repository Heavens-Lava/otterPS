(() => {
  'use strict';
  let index = [];
  const route = location.pathname.endsWith('/') ? location.pathname : `${location.pathname}/`;
  const searchButton = document.getElementById('docsSearchButton');

  const escapeHtml = (value) => String(value).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
  const normalize = (value) => String(value || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  const tokenScore = (page, query) => {
    const title = normalize(page.title), text = normalize(page.text), words = normalize(query).split(' ').filter(Boolean);
    if (!words.length) return 0;
    return words.reduce((score, word) => score + (title.includes(word) ? 12 : 0) + (text.includes(word) ? 2 : 0), 0);
  };

  function installSearch() {
    const dialog = document.createElement('dialog');
    dialog.className = 'docs-search-dialog';
    dialog.innerHTML = '<div class="docs-search-panel" role="search"><input class="docs-search-input" type="search" placeholder="Search documentation" aria-label="Search documentation"><div class="docs-search-hint">Type to search · Esc to close</div><div class="docs-search-results" aria-live="polite"></div></div>';
    document.body.appendChild(dialog);
    const input = dialog.querySelector('input'); const results = dialog.querySelector('.docs-search-results');
    const render = () => {
      const query = input.value.trim();
      const matches = query ? index.map(page => ({ page, score: tokenScore(page, query) })).filter(x => x.score).sort((a,b) => b.score-a.score).slice(0, 10).map(x => x.page) : index.slice(0, 8);
      results.innerHTML = matches.length ? matches.map(page => `<a class="docs-search-result" href="${escapeHtml(page.url)}"><strong>${escapeHtml(page.title)}</strong><span>${escapeHtml(page.text).slice(0, 140)}</span></a>`).join('') : '<div class="docs-search-hint">No matching documentation found.</div>';
    };
    const open = () => { dialog.showModal(); input.value = ''; render(); input.focus(); };
    searchButton?.addEventListener('click', open);
    document.addEventListener('keydown', event => { if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') { event.preventDefault(); open(); } });
    input.addEventListener('input', render);
    dialog.addEventListener('click', event => { if (event.target === dialog) dialog.close(); });
  }

  function enhanceArticle() {
    const main = document.getElementById('docsMain');
    if (!main) return;
    const title = main.querySelector('h1, .otter-text');
    if (title) {
      const crumbs = document.createElement('nav'); crumbs.className = 'docs-crumbs'; crumbs.setAttribute('aria-label', 'Breadcrumb');
      crumbs.innerHTML = `<a href="/docs/">Documentation</a> <span aria-hidden="true">/</span> ${escapeHtml(title.textContent.trim())}`;
      main.insertBefore(crumbs, title);
    }
    // Otter's web compiler emits heading resources as .otter-text divs rather
    // than h2/h3 elements. Their authored 26px/800 styling is the stable
    // semantic signal on these documentation pages.
    const headings = [...main.querySelectorAll('h2, h3, .otter-text')].filter(heading => {
      const style = getComputedStyle(heading);
      return /^H[23]$/.test(heading.tagName) || (parseFloat(style.fontSize) >= 24 && Number(style.fontWeight) >= 700);
    });
    const seen = new Map();
    headings.forEach(heading => { const base = normalize(heading.textContent).replace(/ /g, '-') || 'section'; const n = (seen.get(base) || 0) + 1; seen.set(base, n); heading.id = n === 1 ? base : `${base}-${n}`; const link = document.createElement('a'); link.className = 'docs-heading-link'; link.href = `#${heading.id}`; link.textContent = heading.textContent; heading.textContent = ''; heading.appendChild(link); });
    const tocHeadings = headings.filter(heading => heading !== title);
    if (tocHeadings.length) { const toc = document.createElement('nav'); toc.className = 'docs-toc'; toc.setAttribute('aria-label', 'On this page'); toc.innerHTML = `<strong>On this page</strong>${tocHeadings.map(h => `<a href="#${h.id}">${escapeHtml(h.textContent)}</a>`).join('')}`; document.body.appendChild(toc); }
    const pos = index.findIndex(page => page.url === route);
    if (pos >= 0) { const nav = document.createElement('nav'); nav.className = 'docs-article-nav'; nav.setAttribute('aria-label', 'Article navigation'); const previous = index[pos - 1], next = index[pos + 1]; nav.innerHTML = `${previous ? `<a href="${previous.url}">← ${escapeHtml(previous.title)}</a>` : '<span></span>'}${next ? `<a href="${next.url}">${escapeHtml(next.title)} →</a>` : '<span></span>'}`; main.appendChild(nav); }
    const sidebar = document.getElementById('docsSidebar');
    if (sidebar) { const toggle = document.createElement('button'); toggle.className = 'docs-mobile-toggle'; toggle.type = 'button'; toggle.textContent = 'Browse documentation'; toggle.setAttribute('aria-expanded', 'false'); toggle.addEventListener('click', () => { const open = sidebar.classList.toggle('docs-sidebar-open'); toggle.setAttribute('aria-expanded', String(open)); }); main.parentElement.insertBefore(toggle, sidebar); }
  }

  // Phones: the header's links fold behind a menu button (CSS shows it only on
  // narrow screens) that opens them as a panel under the bar.
  function installSiteMenu() {
    const bar = document.getElementById('topBar');
    const links = document.getElementById('navLinks');
    if (!bar || !links) return;
    const toggle = document.createElement('button');
    toggle.className = 'site-menu-toggle'; toggle.type = 'button';
    toggle.setAttribute('aria-expanded', 'false'); toggle.setAttribute('aria-controls', 'navLinks');
    toggle.innerHTML = '<svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true"><path d="M2 4.5h14M2 9h14M2 13.5h14" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg><span>Menu</span>';
    const setOpen = (open) => { bar.classList.toggle('site-menu-open', open); toggle.setAttribute('aria-expanded', String(open)); toggle.querySelector('span').textContent = open ? 'Close' : 'Menu'; };
    toggle.addEventListener('click', () => setOpen(!bar.classList.contains('site-menu-open')));
    links.addEventListener('click', () => setOpen(false));
    document.addEventListener('keydown', event => { if (event.key === 'Escape') setOpen(false); });
    bar.appendChild(toggle);
  }
  installSiteMenu();

  // Interactive platform tabs on /download/ (Windows / macOS / Linux).
  function installDownloadTabs() {
    const winTab = document.getElementById('tabWindows');
    const macTab = document.getElementById('tabMac');
    const linuxTab = document.getElementById('tabLinux');
    const runBody = document.getElementById('runBody');
    const runCommand = document.getElementById('runCommand');
    const runLabel = document.getElementById('runCommandlabel');
    const reqOs = document.getElementById('reqOs');
    const reqShell = document.getElementById('reqShell');
    if (!winTab || !macTab || !linuxTab || !runCommand) return;

    const PLATFORMS = {
      windows: {
        tab: winTab,
        body: 'Extract otter-1.0.1.zip, open Windows PowerShell in the folder that contains otter.cmd, and run:',
        label: 'PowerShell (Windows)',
        cmd: '.\\otter.cmd examples\\hello.ot\n# Or install to user PATH:\n.\\Install-Otter.ps1 -AddToUserPath',
        os: 'Windows 10 or 11 (64-bit). Also available via winget install 9N5K67PPWJPN.',
        shell: 'Windows PowerShell 5.1 (built into Windows — nothing extra to install).'
      },
      macos: {
        tab: macTab,
        body: 'Install PowerShell 7 (brew install powershell), extract otter-1.0.1.zip, and run in Terminal:',
        label: 'Terminal (macOS)',
        cmd: './otter examples/hello.ot\n# Or install to ~/.local/bin:\npwsh -NoProfile -File ./Install-Otter.ps1 -AddToUserPath',
        os: 'macOS 12+ (Apple silicon or Intel) with PowerShell 7 (pwsh).',
        shell: 'PowerShell 7 (pwsh) for otterPS 1.0.1; native otter-net builds require .NET 10 SDK.'
      },
      linux: {
        tab: linuxTab,
        body: 'Install PowerShell 7 (pwsh), extract otter-1.0.1.zip, and run in your shell:',
        label: 'Shell (Linux / Chromebook)',
        cmd: './otter examples/hello.ot\n# Or install to ~/.local/bin:\npwsh -NoProfile -File ./Install-Otter.ps1 -AddToUserPath',
        os: 'Linux (x64 or arm64) and Chromebooks (Debian 12 Linux environment) with PowerShell 7.',
        shell: 'PowerShell 7 (pwsh) for otterPS 1.0.1; native otter-net builds require .NET 10 SDK.'
      }
    };

    const tabList = [
      ['windows', winTab],
      ['macos', macTab],
      ['linux', linuxTab]
    ];

    const activate = (key) => {
      const cfg = PLATFORMS[key] || PLATFORMS.windows;
      for (const [k, el] of tabList) {
        const active = k === key;
        el.setAttribute('aria-selected', String(active));
        el.dataset.activePlatform = active ? 'true' : 'false';
        el.style.background = active ? '#f8fbff' : 'transparent';
        el.style.color = active ? '#1d70ea' : '#0f1f36';
        el.style.border = active ? '2px solid #b9d7ff' : '2px solid transparent';
        el.style.borderRadius = '10px';
        el.style.fontWeight = active ? '700' : '600';
      }
      if (runBody) runBody.textContent = cfg.body;
      if (runLabel) runLabel.textContent = cfg.label;
      runCommand.textContent = cfg.cmd;
      if (reqOs) reqOs.textContent = cfg.os;
      if (reqShell) reqShell.textContent = cfg.shell;
    };

    const parent = winTab.parentElement;
    if (parent) parent.setAttribute('role', 'tablist');

    for (const [key, el] of tabList) {
      el.setAttribute('role', 'tab');
      el.setAttribute('tabindex', '0');
      el.style.cursor = 'pointer';
      el.addEventListener('click', () => activate(key));
      el.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          activate(key);
        }
      });
    }
    activate('windows');
  }
  installDownloadTabs();

  // The quick reference page has a Print button.
  document.getElementById('refPrint')?.addEventListener('click', () => window.print());

  fetch('/static/docs-index.json').then(response => response.ok ? response.json() : []).then(pages => { index = Array.isArray(pages) ? pages : []; installSearch(); enhanceArticle(); }).catch(() => { installSearch(); enhanceArticle(); });
})();
