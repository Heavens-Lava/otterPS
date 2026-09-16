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
assert.match(darkCss, /body\.theme-dark/, 'Dark workbench colors must remain theme-scoped');
assert.match(darkCss, /\.theme-dark \.code-text-area[\s\S]*caret-color:/, 'Dark editor must keep a visible caret');

console.log('Otter Studio workspace shell tests passed: themes, visible caret, and project-aware templates.');
