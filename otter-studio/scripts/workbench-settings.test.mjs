// workbench-settings.test.mjs - Comprehensive Certification for Section 31 Settings & Workbench

import assert from 'node:assert/strict';
import {
  DEFAULT_SETTINGS,
  SETTINGS_SCHEMA,
  SettingsManager,
  CommandRegistry,
  KeybindingManager,
  CommandPaletteEngine,
  StatusBarManager,
  WORKBENCH_VIEWS,
  DEFAULT_LAYOUT,
  WorkbenchLayoutManager
} from '../js/workbench/workbench-engine.js';

console.log('--- RUNNING SECTION 31 SETTINGS & WORKBENCH TESTS ---');

// ============================================================================
// Test 1: Settings Cascade (Default -> User -> Workspace -> Project)
// ============================================================================
console.log('Test 1: Settings cascade & schema validation');
const settings = new SettingsManager();

// Default values
assert.equal(settings.get('editor.fontSize'), 14);
assert.equal(settings.get('workbench.theme'), 'dark-modern');

// User override
settings.set('user', 'editor.fontSize', 16);
assert.equal(settings.get('editor.fontSize'), 16);

// Workspace override
settings.set('workspace', 'editor.fontSize', 18);
assert.equal(settings.get('editor.fontSize'), 18);

// Project override
settings.set('project', 'editor.fontSize', 20);
assert.equal(settings.get('editor.fontSize'), 20);

// Reset project tier, falls back to workspace tier (18)
settings.resetTier('project');
assert.equal(settings.get('editor.fontSize'), 18);

// Reset workspace tier, falls back to user tier (16)
settings.resetTier('workspace');
assert.equal(settings.get('editor.fontSize'), 16);

// Reset user tier, falls back to default (14)
settings.resetTier('user');
assert.equal(settings.get('editor.fontSize'), 14);

// Schema enum validation error
assert.throws(() => {
  settings.set('user', 'workbench.theme', 'neon-cyberpunk');
}, /Invalid value/);

console.log('✓ Settings cascade & schema validation verified');

// ============================================================================
// Test 2: Central Command Registry & Context-Sensitive Execution
// ============================================================================
console.log('Test 2: Central command registry and context keys');
const reg = new CommandRegistry();
let runCount = 0;

reg.registerCommand({
  id: 'editor.save',
  title: 'Save Active File',
  category: 'File',
  keybinding: 'ctrl+s',
  when: 'editorFocus && !isReadonly',
  handler: () => { runCount++; return 'saved'; }
});

// Without context, command is blocked
reg.setContext('editorFocus', true);
reg.setContext('isReadonly', true);
assert.throws(() => {
  reg.executeCommand('editor.save');
}, /cannot be executed in current context/);

// With valid context, execution succeeds
reg.setContext('isReadonly', false);
const res = reg.executeCommand('editor.save');
assert.equal(res, 'saved');
assert.equal(runCount, 1);

// Query commands
const fileCommands = reg.getAllCommands({ category: 'File' });
assert.equal(fileCommands.length, 1);
assert.equal(fileCommands[0].id, 'editor.save');

console.log('✓ Command registry & context-sensitive execution verified');

// ============================================================================
// Test 3: Keybinding Manager & Platform Shortcut Mapping
// ============================================================================
console.log('Test 3: Platform shortcut mapping and custom keybindings');
const keybindingsWin = new KeybindingManager(reg, 'windows');
const keybindingsMac = new KeybindingManager(reg, 'macos');

// Format for Windows vs macOS
assert.equal(keybindingsWin.formatForPlatform('ctrl+shift+p'), 'Ctrl+Shift+P');
assert.equal(keybindingsMac.formatForPlatform('ctrl+shift+p'), '⌘ ⇧ P');

// Resolve command from shortcut
const resolvedCmd = keybindingsWin.resolveCommandForShortcut('ctrl+s');
assert.ok(resolvedCmd);
assert.equal(resolvedCmd.id, 'editor.save');

// Custom keybinding override
keybindingsWin.setCustomKeybinding('editor.save', 'alt+s');
assert.equal(keybindingsWin.getKeybinding('editor.save'), 'alt+s');
assert.equal(keybindingsWin.resolveCommandForShortcut('alt+s').id, 'editor.save');

console.log('✓ Platform shortcut mapping & keybinding overrides verified');

// ============================================================================
// Test 4: Command Palette & Quick Open Engine
// ============================================================================
console.log('Test 4: Command palette and quick open');
const palette = new CommandPaletteEngine(reg, ['src/main.ot', 'src/math.ot', 'project.json', 'README.md']);
palette.recordFileAccess('src/math.ot');

// 1. Command search mode
const cmdRes = palette.query('>save');
assert.equal(cmdRes.mode, 'commands');
assert.equal(cmdRes.results.length, 1);
assert.equal(cmdRes.results[0].title, 'Save Active File');

// 2. Line number mode
const lineRes = palette.query(':120');
assert.equal(lineRes.mode, 'line');
assert.equal(lineRes.targetLine, 120);

// 3. Quick open file search (recent file prioritized)
const fileRes = palette.query('ot');
assert.equal(fileRes.mode, 'files');
assert.equal(fileRes.results[0].path, 'src/math.ot'); // Recently accessed first
console.log('✓ Command palette & quick open verified');

// ============================================================================
// Test 5: Status Bar Manager
// ============================================================================
console.log('Test 5: Status bar manager');
const statusBar = new StatusBarManager();

statusBar.setItem('git', { text: 'main*', alignment: 'left', priority: 100 });
statusBar.setItem('problems', { text: '0 Errors, 2 Warnings', alignment: 'left', priority: 50 });
statusBar.setItem('encoding', { text: 'UTF-8', alignment: 'right', priority: 10 });
statusBar.setItem('lang', { text: 'Otter', alignment: 'right', priority: 20 });

const leftItems = statusBar.getItems('left');
assert.equal(leftItems.length, 2);
assert.equal(leftItems[0].id, 'git'); // higher priority

const rightItems = statusBar.getItems('right');
assert.equal(rightItems.length, 2);
assert.equal(rightItems[0].id, 'lang'); // higher priority (20 > 10)
console.log('✓ Status bar manager verified');

// ============================================================================
// Test 6: Workbench Layout & Panel Management
// ============================================================================
console.log('Test 6: Workbench views and layout management');
const layout = new WorkbenchLayoutManager();

assert.equal(WORKBENCH_VIEWS.length, 13);
assert.ok(WORKBENCH_VIEWS.includes('scm'));
assert.ok(WORKBENCH_VIEWS.includes('live-app'));

layout.setActiveView('scm');
assert.equal(layout.getLayout().activeView, 'scm');
assert.equal(layout.getLayout().sidebarOpen, true);

// Resize sidebar with clamping
layout.setSidebarWidth(100); // below min 180
assert.equal(layout.getLayout().sidebarWidth, 180);

layout.setSidebarWidth(400);
assert.equal(layout.getLayout().sidebarWidth, 400);

// Bottom panel toggle
layout.toggleBottomPanel();
assert.equal(layout.getLayout().bottomPanelOpen, false);

layout.setActiveBottomTab('output');
assert.equal(layout.getLayout().activeBottomTab, 'output');
assert.equal(layout.getLayout().bottomPanelOpen, true);

// Multi-window registration
layout.registerWindow('win-designer-2', { role: 'designer', url: '/designer.html' });
assert.equal(layout.getLayout().secondaryWindows.length, 1);
assert.equal(layout.getLayout().secondaryWindows[0].role, 'designer');

layout.unregisterWindow('win-designer-2');
assert.equal(layout.getLayout().secondaryWindows.length, 0);

// Reset layout
layout.resetLayout();
assert.equal(layout.getLayout().activeView, 'explorer');
assert.equal(layout.getLayout().sidebarWidth, 280);

console.log('✓ Workbench views & layout management verified');

console.log('\n--- ALL SECTION 31 SETTINGS & WORKBENCH TESTS PASSED (6/6) ---');
