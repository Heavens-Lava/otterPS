import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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

// 5. ide.js activateTab syncs CSS AST manager
assert.match(ideSrc, /filePath\.endsWith\('\.css'\) && window\.otterCssAstManager/,
  'ide.activateTab must synchronize otterCssAstManager when activating CSS files');

// 6. ide.js loadFile replaces unedited default tab
assert.match(ideSrc, /openTabs\.length === 1 && this\.openTabs\[0\]\.path === 'untitled\.ot' && !this\.openTabs\[0\]\.isDirty/,
  'ide.loadFile must replace clean untitled tab with opened project file');

// 7. ide.js renderProjectTree recursive and interactive
assert.match(ideSrc, /renderProjectTree\(items, rootName, rootFolder\)/,
  'ide.js must define renderProjectTree');
assert.match(ideSrc, /querySelectorAll\('\.project-file-item'\)/,
  'ide.renderProjectTree must attach click handlers to all project file items');
assert.match(ideSrc, /loadFile\(p\)/,
  'Clicking project file item must call loadFile');

// 8. ide.js syntax highlighting for CSS and JSON
assert.match(ideSrc, /syntaxHighlightCssLine\(line\)/,
  'ide.js must implement syntaxHighlightCssLine');
assert.match(ideSrc, /syntaxHighlightJsonLine\(line\)/,
  'ide.js must implement syntaxHighlightJsonLine');
assert.match(ideSrc, /this\.currentFile\?\.endsWith\('\.css'\)/,
  'ide.syntaxHighlightLine must dispatch to CSS syntax highlighter');
assert.match(ideSrc, /this\.currentFile\?\.endsWith\('\.json'\)/,
  'ide.syntaxHighlightLine must dispatch to JSON syntax highlighter');

// 9. ide.js lintCurrentCode file-type guarding
assert.match(ideSrc, /if \(this\.currentFile && !this\.currentFile\.endsWith\('\.ot'\)\)/,
  'ide.lintCurrentCode must guard non-Otter files from Otter parser analysis');
assert.match(ideSrc, /CSS Stylesheet/,
  'ide.lintCurrentCode must report CSS Stylesheet status for .css files');

// 10. Non-Otter file edits in app.js must not overwrite ide.currentCode from uiModel
assert.match(appSrc, /if \(!ide\.currentFile \|\| ide\.currentFile\.endsWith\('\.ot'\)\) \{\s*syncCodeFromUiModel\(\);/,
  'uiModel changes must not overwrite ide.currentCode when viewing non-Otter files');

console.log('Otter Studio file switching & editor visibility tests passed successfully!');
