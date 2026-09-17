import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const studioRoot = path.resolve(scriptDir, '..');

const [appSrc, ideSrc, studioDarkCss, studioCss] = await Promise.all([
  fs.readFile(path.join(studioRoot, 'js', 'app.js'), 'utf8'),
  fs.readFile(path.join(studioRoot, 'js', 'ide.js'), 'utf8'),
  fs.readFile(path.join(studioRoot, 'css', 'studio-dark.css'), 'utf8'),
  fs.readFile(path.join(studioRoot, 'css', 'studio.css'), 'utf8')
]);

// 1. Split mode must show the real code editor view (codeEditorView), not the legacy editorContainer
assert.match(appSrc, /mode === 'split'[\s\S]*?codeEditorView\.style\.display = 'flex'/,
  'Split mode must display codeEditorView');
assert.match(appSrc, /mode === 'split'[\s\S]*?canvasEl\.style\.display = 'flex'/,
  'Split mode must display canvasEl');
assert.match(appSrc, /mode === 'split'[\s\S]*?editorEl\.style\.display = 'none'/,
  'Split mode must hide legacy editorEl');

// 2. CSS split layout classes
assert.match(studioDarkCss, /\.center-work-area\.is-split\s*\{[\s\S]*?\.code-editor-view/,
  'Dark theme must define is-split layout rules');
assert.match(studioCss, /\.center-work-area\.is-split\s*\{[\s\S]*?\.code-editor-view/,
  'Light theme must define is-split layout rules');

// 3. Ensure editor visible event listener in app.js
assert.match(appSrc, /otter:ensure-editor-visible/,
  'app.js must listen for otter:ensure-editor-visible to auto-switch out of pure designer/preview mode');

// 4. ide.js activateTab dispatches ensure-editor-visible
assert.match(ideSrc, /window\.dispatchEvent\(new CustomEvent\('otter:ensure-editor-visible'/,
  'ide.activateTab must dispatch otter:ensure-editor-visible on file activation');

// 5. ide.js activateTab syncs CSS AST manager & canvasUserCss
assert.match(ideSrc, /filePath\.endsWith\('\.css'\) && window\.otterCssAstManager/,
  'ide.activateTab must synchronize otterCssAstManager when activating CSS files');

// 6. Live CSS preview in app.js must update canvasUserCss directly on source change
assert.match(appSrc, /styleTag\.textContent = cssAstManager\.generateCss\(\)/,
  'app.js must update canvasUserCss in real time as styles.css is edited');

// 7. ide.js loadFile replaces unedited default tab
assert.match(ideSrc, /openTabs\.length === 1 && this\.openTabs\[0\]\.path === 'untitled\.ot' && !this\.openTabs\[0\]\.isDirty/,
  'ide.loadFile must replace clean untitled tab with opened project file');

// 8. ide.js renderProjectTree recursive and interactive
assert.match(ideSrc, /renderProjectTree\(items, rootName, rootFolder\)/,
  'ide.js must define renderProjectTree');
assert.match(ideSrc, /querySelectorAll\('\.project-file-item'\)/,
  'ide.renderProjectTree must attach click handlers to all project file items');
assert.match(ideSrc, /loadFile\(p\)/,
  'Clicking project file item must call loadFile');

// 9. Modular language routing and syntax highlighting
const { getLanguageForFile, getFileIcon, highlightSourceLine } = await import(
  pathToFileURL(path.join(studioRoot, 'js', 'editor', 'file-language-router.js')).href
);

assert.equal(getLanguageForFile('main.ot'), 'otter');
assert.equal(getLanguageForFile('styles.css'), 'css');
assert.equal(getLanguageForFile('project.json'), 'json');
assert.equal(getFileIcon('styles.css'), '🎨');
assert.equal(getFileIcon('project.json'), '⚙');
assert.equal(getFileIcon('main.ot'), '📄');

// Verify CSS syntax highlighting does not mistake #id selectors for Otter comments
const cssLine = highlightSourceLine('#app { background: #0f172a; }', 'styles.css');
assert.match(cssLine, /tok-ui">#app</, 'CSS #id selector must receive tok-ui class, never tok-comment');
assert.match(cssLine, /tok-var">background</, 'CSS property must receive tok-var class');
assert.doesNotMatch(cssLine, /tok-comment/, 'Valid CSS rule must not be treated as a comment');

// Verify JSON syntax highlighting
const jsonLine = highlightSourceLine('  "name": "my-app",', 'project.json');
assert.match(jsonLine, /tok-var">"name"</, 'JSON key must be highlighted as a property');
assert.match(jsonLine, /tok-str">"my-app"</, 'JSON string value must be highlighted as a string');

// 10. Document state preservation (unsaved text, selection, scroll per tab)
const { snapshotTabState } = await import(
  pathToFileURL(path.join(studioRoot, 'js', 'editor', 'document-state.js')).href
);

const tab1 = { path: 'main.ot', content: 'say "hi"' };
const mockTextarea1 = { value: 'say "unsaved text"', selectionStart: 4, selectionEnd: 11, scrollTop: 42, scrollLeft: 0 };
snapshotTabState(tab1, mockTextarea1);
assert.equal(tab1.content, 'say "unsaved text"', 'Tab snapshot must record live unsaved text');
assert.equal(tab1.selectionStart, 4, 'Tab snapshot must record selection start');
assert.equal(tab1.selectionEnd, 11, 'Tab snapshot must record selection end');
assert.equal(tab1.scrollTop, 42, 'Tab snapshot must record scroll top');

// 11. Tab switching state preservation in ide.js
assert.match(ideSrc, /snapshotTabState\(prevTab, textarea\)/,
  'ide.activateTab must snapshot the previous tab state before switching');
assert.match(ideSrc, /restoreTabState\(tab, textarea, this\.codeAreaEl, this\.gutterEl\)/,
  'ide.activateTab must restore caret selection and scroll positions when activating a tab');

// 12. Workspace session restoration
assert.match(ideSrc, /restoreSessionState\(\)/,
  'ide.js must implement restoreSessionState');
assert.match(ideSrc, /const restored = await this\.restoreSessionState\(\);/,
  'ide.init must attempt to restore previous workspace session on startup');
assert.match(appSrc, /const hasRestoredSession = ide\.currentProjectFolder/,
  'app.js must check hasRestoredSession before popping new project wizard');

// 13. File-type guarded linting
assert.match(ideSrc, /if \(this\.currentFile && !this\.currentFile\.endsWith\('\.ot'\)\)/,
  'ide.lintCurrentCode must guard non-Otter files from Otter parser analysis');
assert.match(ideSrc, /CSS Stylesheet/,
  'ide.lintCurrentCode must report CSS Stylesheet status for .css files');

console.log('Otter Studio file switching, tab preservation & modular editor tests passed successfully!');
