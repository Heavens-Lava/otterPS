const menu = document.querySelector('.menu');
if (menu) menu.addEventListener('click', () => document.querySelector('.sidebar').classList.toggle('open'));
const search = document.querySelector('[data-search]'); const dialog = document.querySelector('[data-results]');
if (search) { let entries; search.addEventListener('input', async () => { entries ||= await fetch('/search-index.json').then(r => r.json()); const term = search.value.trim().toLowerCase(); if (!term) return dialog.close(); const hits = entries.filter(x => `${x.title} ${x.section} ${x.description}`.toLowerCase().includes(term)).slice(0,10); dialog.querySelector('div').innerHTML = hits.length ? hits.map(x => `<p><a href="${x.url}">${x.title}</a><br><small>${x.section}</small></p>`).join('') : '<p>No pages found.</p>'; dialog.showModal(); }); }
document.querySelector('[data-close]')?.addEventListener('click', () => dialog.close());
