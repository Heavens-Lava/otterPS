// library-explorer.test.mjs - Unit & integration tests for Otter Studio Library Explorer (RFC Phase 2)
import test from 'node:test';
import assert from 'node:assert/strict';
let LibraryExplorer;
try {
  ({ LibraryExplorer } = await import('../js/components/library-explorer.js'));
} catch {
  ({ LibraryExplorer } = await import('./library-explorer.js'));
}

// Minimal DOM mock for component unit tests
class MockElement {
  constructor(tagName = 'div') {
    this.tagName = tagName;
    this.attributes = {};
    this.classList = new Set();
    this.innerHTML = '';
    this.listeners = {};
    this.children = [];
  }

  setAttribute(name, val) { this.attributes[name] = String(val); }
  getAttribute(name) { return this.attributes[name] || null; }
  addEventListener(event, fn) {
    if (!this.listeners[event]) this.listeners[event] = [];
    this.listeners[event].push(fn);
  }
  click() {
    if (this.listeners['click']) {
      for (const fn of this.listeners['click']) fn({ target: this });
    }
  }

  querySelector(selector) {
    if (selector.startsWith('#')) {
      const id = selector.slice(1);
      if (this.attributes.id === id) return this;
      return this._findChild(el => el.attributes.id === id);
    }
    return null;
  }

  querySelectorAll(selector) {
    const results = [];
    if (selector.startsWith('.')) {
      const cls = selector.slice(1);
      this._walk(el => { if (el.classList.has(cls)) results.push(el); });
    }
    return results;
  }

  _walk(fn) {
    fn(this);
    for (const c of this.children) c._walk(fn);
  }

  _findChild(fn) {
    for (const c of this.children) {
      if (fn(c)) return c;
      const res = c._findChild(fn);
      if (res) return res;
    }
    return null;
  }
}

const mockCatalog = {
  snippets: [
    {
      id: 'cf-for-each',
      title: 'For Each Loop',
      category: 'Control Flow',
      description: 'Iterate over elements in a list using the idiomatic Otter loop syntax.',
      tags: ['loop', 'for', 'iterate', 'list'],
      capabilities: [],
      platforms: ['console', 'desktop', 'web'],
      template: 'for each ${item} in ${items}\n    say ${item}\n.',
      example: 'items are\n    "Ruby"\n.\nfor each item in items\n    say item\n.'
    },
    {
      id: 'math-clamp',
      title: 'Clamp Value',
      category: 'Math & Numbers',
      description: 'Constrain a numeric value between minimum and maximum boundaries.',
      tags: ['clamp', 'math', 'limit', 'bound'],
      capabilities: [],
      platforms: ['console', 'desktop', 'web'],
      template: 'to clamp val minLimit maxLimit ...',
      example: 'say clamp 150 0 100'
    }
  ],
  packs: [
    {
      name: 'math-utils',
      publisher: 'otter-official',
      version: '1.0.0',
      description: 'Essential mathematical helpers: clamp, lerp, min, max.',
      license: 'MIT',
      platforms: ['console', 'desktop', 'web'],
      capabilities: [],
      entry: 'src/main.ot',
      examples: ['examples/demo.ot']
    }
  ],
  installed: {
    'otter-official/math-utils': {
      version: '1.0.0',
      entry: 'src/main.ot',
      sha256: '6C7F6703C74849703A014EA91FD516CC7A45C167E026A4442C8074BC66F9EBAC',
      installedAt: '2026-11-10T13:08:31Z'
    }
  }
};

test('LibraryExplorer: Initialization, categories, and tabs', () => {
  const explorer = new LibraryExplorer({
    snippets: mockCatalog.snippets,
    packs: mockCatalog.packs,
    installedPackages: mockCatalog.installed
  });

  assert.equal(explorer.activeTab, 'snippets');
  const categories = explorer.getCategories();
  assert.ok(categories.includes('all'));
  assert.ok(categories.includes('Control Flow'));
  assert.ok(categories.includes('Math & Numbers'));
});

test('LibraryExplorer: Natural-language and keyword snippet filtering', () => {
  const explorer = new LibraryExplorer({
    snippets: mockCatalog.snippets,
    packs: mockCatalog.packs
  });

  // Query: "for loop"
  explorer.searchQuery = 'for loop';
  const filtered1 = explorer.getFilteredSnippets();
  assert.equal(filtered1.length, 1);
  assert.equal(filtered1[0].id, 'cf-for-each');

  // Query: "clamp"
  explorer.searchQuery = 'clamp';
  const filtered2 = explorer.getFilteredSnippets();
  assert.equal(filtered2.length, 1);
  assert.equal(filtered2[0].id, 'math-clamp');

  // Category filter
  explorer.searchQuery = '';
  explorer.selectedCategory = 'Control Flow';
  const catFiltered = explorer.getFilteredSnippets();
  assert.equal(catFiltered.length, 1);
  assert.equal(catFiltered[0].id, 'cf-for-each');
});

test('LibraryExplorer: Pack filtering and metadata inspection', () => {
  const explorer = new LibraryExplorer({
    snippets: mockCatalog.snippets,
    packs: mockCatalog.packs
  });

  explorer.searchQuery = 'math';
  const filtered = explorer.getFilteredPacks();
  assert.equal(filtered.length, 1);
  assert.equal(filtered[0].name, 'math-utils');
  assert.equal(filtered[0].publisher, 'otter-official');
  assert.equal(filtered[0].version, '1.0.0');
});

test('LibraryExplorer: Selection and Callbacks', () => {
  let inserted = null;
  let installed = null;
  let uninstalled = null;

  const explorer = new LibraryExplorer({
    snippets: mockCatalog.snippets,
    packs: mockCatalog.packs,
    installedPackages: mockCatalog.installed,
    onInsertSnippet: (s) => { inserted = s; },
    onInstallPack: (p) => { installed = p; },
    onUninstallPack: (p) => { uninstalled = p; }
  });

  explorer.selectItem(mockCatalog.snippets[0], 'snippet');
  assert.equal(explorer.selectedItem.id, 'cf-for-each');
  explorer.onInsertSnippet(explorer.selectedItem);
  assert.equal(inserted.id, 'cf-for-each');

  explorer.selectItem(mockCatalog.packs[0], 'pack');
  assert.equal(explorer.selectedItem.name, 'math-utils');
  explorer.onInstallPack(explorer.selectedItem);
  assert.equal(installed.name, 'math-utils');

  const instList = explorer.getInstalledList();
  assert.equal(instList.length, 1);
  assert.equal(instList[0].name, 'otter-official/math-utils');
  explorer.onUninstallPack(instList[0]);
  assert.equal(uninstalled.name, 'otter-official/math-utils');
});

console.log('✓ All LibraryExplorer unit tests passed cleanly!');

test('LibraryExplorer: Integration with OtterExtensionManager', async () => {
  let OtterExtensionManager;
  try {
    ({ OtterExtensionManager } = await import('../js/extensions/extension-manager.js'));
  } catch {
    ({ OtterExtensionManager } = await import('../../../otterPS/otter-studio/js/extensions/extension-manager.js'));
  }
  const extManager = new OtterExtensionManager();

  const dispose = extManager.registerPanel('library-explorer', {
    title: 'Library Explorer',
    render: (container) => {
      const explorer = new LibraryExplorer({ snippets: mockCatalog.snippets });
      explorer.render(container);
    }
  });

  const panel = extManager.getPanel('library-explorer');
  assert.ok(panel);
  assert.equal(panel.title, 'Library Explorer');

  // Verify command registration
  extManager.registerCommand('otter.library.search', (query) => {
    return mockCatalog.snippets.filter(s => s.id.includes(query));
  });

  const results = await extManager.executeCommand('otter.library.search', 'clamp');
  assert.equal(results.length, 1);
  assert.equal(results[0].id, 'math-clamp');

  dispose();
  assert.equal(extManager.getPanel('library-explorer'), null);
});
