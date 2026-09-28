import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const studioRoot = path.resolve(scriptDir, '..');

const [html, app, ide, darkCss] = await Promise.all([
  fs.readFile(path.join(studioRoot, 'index.html'), 'utf8'),
  fs.readFile(path.join(studioRoot, 'js', 'app.js'), 'utf8'),
  fs.readFile(path.join(studioRoot, 'js', 'ide.js'), 'utf8'),
  fs.readFile(path.join(studioRoot, 'css', 'studio-dark.css'), 'utf8')
]);

assert.match(html, /id="btnThemeToggle"/, 'Studio must expose an accessible theme switch');
assert.match(html, /id="templatesCard"/, 'Templates must expose workspace-aware shell state');
assert.match(html, /id="btnToggleTemplates"[^>]+aria-expanded="true"/, 'Templates need an explicit collapse control');
assert.match(app, /otter-studio-theme/, 'Theme selection must persist between sessions');
assert.match(app, /classList\.toggle\('theme-dark'/, 'Theme switch must activate dark mode explicitly');
assert.match(app, /classList\.toggle\('theme-light'/, 'Theme switch must preserve light mode');
assert.match(ide, /renderCleanProjectTree\(\)[\s\S]*setTemplatesCollapsed\(false\)/, 'Empty workspaces must show templates');
assert.match(ide, /currentProjectName = data\.name[\s\S]*setTemplatesCollapsed\(true\)/, 'Open projects must collapse templates');
assert.match(ide, /caret, selection, and scroll/, 'Editor redraws must explicitly preserve typing context');
assert.match(ide, /setSelectionRange\(start, end\)/, 'Editor redraws must restore the original selection');
assert.match(ide, /textarea\.scrollTop = editorState\.scrollTop/, 'Editor redraws must restore the original scroll position');
assert.match(html, /id="btnToggleWordWrap"/, 'Editor must expose an explicit word-wrap control');
assert.match(html, /id="editorBreadcrumbs"/, 'Editor must expose the current-file breadcrumbs');
assert.match(html, /id="btnGoToDefinition"/, 'Editor must expose Go to Definition');
assert.match(html, /id="btnPeekDefinition"/, 'Editor must expose Peek Definition');
assert.match(html, /id="btnFindOccurrences"/, 'Editor must expose current-file occurrence search');
assert.match(html, /id="definitionPeek"/, 'Editor must have a definition preview surface');
assert.match(ide, /otter-studio-word-wrap/, 'Word-wrap preference must persist between Studio sessions');
assert.match(ide, /Alt\+Z/, 'Word-wrap must be discoverable through its keyboard shortcut');
assert.match(ide, /renderBreadcrumbs\(\)/, 'Editor chrome must render breadcrumbs as files change');
assert.match(ide, /definitionForWord/, 'Go to Definition must use the indexed symbol resolver');
assert.match(ide, /e\.key === 'F12'/, 'Go to Definition must have the standard F12 shortcut');
assert.match(ide, /peekDefinition\(\)/, 'Studio must support a non-navigating definition preview');
assert.match(ide, /occurrencesForWord/, 'Occurrence search must use the safe lexical scanner');
assert.match(html, /id="editorHoverTooltip"/, 'Editor must expose a hover tooltip surface');
assert.match(html, /id="editorSignatureHelp"/, 'Editor must expose a signature help surface');
assert.match(html, /id="btnEolSelector"/, 'Status bar must expose an EOL selector button');
assert.match(html, /id="btnEncodingSelector"/, 'Status bar must expose an encoding selector button');
assert.match(html, /id="problemStatusBanner"/, 'Problems drawer must expose a clickable status banner');
assert.match(ide, /handleEditorHover/, 'Editor must support hover information lookup');
assert.match(ide, /checkSignatureHelp/, 'Editor must support real-time parameter signature help');
assert.match(ide, /splitLineEnding\(fileContent\)/, 'Editor must detect a file\'s CRLF/LF line ending when it opens');
assert.match(ide, /withLineEnding\(this\.currentCode/, 'Save must write the file\'s own line ending');
assert.equal((ide.match(/e\.ctrlKey && e\.key === 's'/g) || []).length, 1, 'Ctrl+S must be handled once (twice saved twice and raised a false conflict)');
assert.match(ide, /if \(tab\.saveInFlight\) continue;/, 'The external-change check must skip a tab whose save is in flight');
// Assigning textarea.value clears the undo history; in-editor edits go
// through setEditorValue (execCommand insertText). Only tab switches,
// reloads, designer sync and the redraw fallback may assign it.
assert.match(ide, /applyAssistedEdit\(textarea, edit\) \{\s*this\.setEditorValue\(textarea, edit\.text\)/, 'Enter / auto-close must be undoable');
assert.ok((ide.match(/textarea\.value = /g) || []).length <= 6, 'a new direct textarea.value assignment would break Ctrl+Z; use setEditorValue');
assert.match(ide, /problemStatusBanner\?\.addEventListener\('click'/, 'Clicking problem banner must navigate to source');
assert.match(html, /id="workspaceReplaceInput"/, 'Workspace search pane must expose a replace input');
assert.match(html, /id="btnWorkspaceReplaceAll"/, 'Workspace search pane must expose a Replace All button');
assert.match(ide, /replaceWorkspace\(\)/, 'IDE must support workspace-wide replacement');
assert.match(darkCss, /\.theme-dark \.editor-hover-tooltip/, 'Dark theme must scope hover tooltip styles');
assert.match(html, /id="btnFindReferences"/, 'Editor must expose Find References button');
assert.match(html, /id="btnRenameSymbol"/, 'Editor must expose Rename Symbol button');
assert.match(html, /id="modalRenameSymbol"/, 'Studio must have a rename preview dialog');
assert.match(ide, /findReferences\(\)/, 'IDE must implement Find References');
assert.match(ide, /promptRename\(\)/, 'IDE must implement safe Rename Symbol');
assert.match(ide, /e\.ctrlKey.*goToDefinition/s, 'Editor must support Ctrl+Click to Go to Definition');
assert.match(darkCss, /\.theme-dark \.rename-dialog/, 'Dark theme must style the rename dialog');

assert.match(html, /id="outlineFilterInput"/, 'Document outline must expose a filter input');
assert.match(html, /id="btnWorkspaceSymbols"/, 'Editor quick actions must expose Workspace Symbols button');
assert.match(html, /id="btnExtractFunction"/, 'Editor quick actions must expose Extract Function button');
assert.match(html, /id="btnProblemQuickFix"/, 'Problems banner must expose Quick Fix button');
assert.match(ide, /openNavigationPalette\('workspace-symbols'\)/, 'IDE must support workspace symbol palette');
assert.match(ide, /e\.key\.toLowerCase\(\) === 't'/, 'IDE must bind Ctrl+T for workspace symbols');
assert.match(ide, /extractFunction\(\)/, 'IDE must support Extract Function refactoring');
assert.match(ide, /applyCurrentQuickFix\(\)/, 'IDE must support applying problem quick fixes');
assert.match(darkCss, /\.theme-dark \.tok-fn/, 'Dark theme must style semantic function tokens');
assert.match(darkCss, /\.theme-dark \.outline-symbol-icon/, 'Dark theme must style outline symbol kind icons');
assert.match(darkCss, /\.theme-dark \.code-line\.has-warning/, 'Dark theme must style warning squiggles');

console.log('Otter Studio workspace shell tests passed: themes, visible caret, project-aware templates, hover help, signature help, EOL/encoding selectors, workspace replace, references, rename, outline filtering, workspace symbols, extract function, and quick fixes.');



