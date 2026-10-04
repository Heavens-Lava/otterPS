// installer-first-run.test.mjs - Certification Test Suite for Section 35: Installer, Updater, First-Run
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  SAMPLE_PROJECTS,
  WelcomeManager,
  ToolchainDetector,
  FileAssociationManager,
  OfflineInstallVerifier
} from '../js/welcome/first-run-manager.js';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(studioRoot, '..');

test('1. SAMPLE_PROJECTS: Catalog contains valid archetypes with existing entry points or valid paths', () => {
  assert.ok(SAMPLE_PROJECTS.length >= 4, 'Should have at least 4 sample projects');

  for (const sample of SAMPLE_PROJECTS) {
    assert.ok(sample.id, 'Sample must have an id');
    assert.ok(sample.name, 'Sample must have a name');
    assert.ok(sample.category, 'Sample must have a category');
    assert.ok(sample.entryPoint, 'Sample must specify entryPoint');
    assert.ok(Array.isArray(sample.tags) && sample.tags.length > 0, 'Sample must have tags');
  }
});

test('2. WelcomeManager: Generates structured welcome data and renders accessible HTML', () => {
  const storage = new Map();
  const manager = new WelcomeManager({ storage });

  // Default state: show on startup = true
  assert.equal(manager.shouldShowOnStartup(), true);

  // Toggle show on startup
  manager.setShowOnStartup(false);
  assert.equal(manager.shouldShowOnStartup(), false);
  assert.equal(storage.get('otter_studio_show_welcome'), 'false');

  // Welcome data structure
  const recents = [
    { name: 'My App', path: 'projects/my-app' }
  ];
  const data = manager.getWelcomeData({ recentProjects: recents });
  assert.equal(data.version, '1.0.0');
  assert.equal(data.recentProjects.length, 1);
  assert.equal(data.quickActions.length, 4);
  assert.equal(data.documentationLinks.length, 4);

  // Render HTML
  const html = manager.renderWelcomeHtml({ recentProjects: recents });
  assert.ok(html.includes('Otter Studio'), 'HTML must include Otter Studio header');
  assert.ok(html.includes('welcome-recent-item'), 'HTML must include recent workspaces');
  assert.ok(html.includes('welcome-sample-card'), 'HTML must include sample project cards');
  assert.ok(html.includes('role="region"'), 'HTML must include accessibility region');
});

test('3. ToolchainDetector: Detects host developer tools and identifies PowerShell and Node runtime', () => {
  const toolchain = ToolchainDetector.detect();

  assert.equal(typeof toolchain.timestamp, 'number');
  assert.ok(toolchain.platform, 'Platform must be recorded');
  assert.equal(toolchain.tools.node.installed, true);
  assert.ok(toolchain.tools.node.version.startsWith('v'), 'Node version must start with v');

  // Verify PowerShell tool check executed
  assert.ok(toolchain.tools.powershell5 !== undefined);
  assert.ok(toolchain.tools.powershell7 !== undefined);

  // On Windows, PS 5.1 is installed
  if (process.platform === 'win32') {
    assert.equal(toolchain.tools.powershell5.installed, true, 'PowerShell 5.1 must be detected on Windows');
  }
});

test('4. FileAssociationManager: Generates valid Windows .reg, Linux MIME/.desktop, and macOS Info.plist configs', () => {
  // 1. Windows Registry script (.reg)
  const regScript = FileAssociationManager.generateWindowsRegistry({
    launcherPath: 'C:\\Users\\User\\AppData\\Local\\Otter\\1.0.0\\otter.cmd',
    studioUrl: 'http://127.0.0.1:4200'
  });
  assert.ok(regScript.includes('Windows Registry Editor Version 5.00'));
  assert.ok(regScript.includes('[HKEY_CURRENT_USER\\Software\\Classes\\.ot]'));
  assert.ok(regScript.includes('Edit with Otter Studio'));
  assert.ok(regScript.includes('Run with Otter'));

  // 2. Linux FreeDesktop MIME XML & .desktop
  const { mimeXml, desktopEntry } = FileAssociationManager.generateLinuxMimeAndDesktop({
    execPath: '/usr/local/bin/otter'
  });
  assert.ok(mimeXml.includes('type="text/x-otter"'));
  assert.ok(desktopEntry.includes('[Desktop Entry]'));
  assert.ok(desktopEntry.includes('MimeType=text/x-otter;'));

  // 3. macOS Document Types
  const macDoc = FileAssociationManager.generateMacOsDocumentType();
  assert.equal(macDoc.CFBundleTypeName, 'Otter Source Code');
  assert.ok(macDoc.CFBundleTypeExtensions.includes('ot'));
});

test('5. OfflineInstallVerifier: Verifies offline bundle contains all required files and contracts', () => {
  // Test repository root as a standalone package
  const res = OfflineInstallVerifier.verifyPackage(repoRoot);
  assert.equal(res.complete, true, `Missing files: ${res.missingFiles.join(', ')}`);
  assert.ok(res.verifiedFiles.includes('VERSION'));
  assert.ok(res.verifiedFiles.includes('Otter.Contract.psm1'));
  assert.ok(res.verifiedFiles.includes('README.md'));
  assert.ok(res.verifiedFiles.includes('INSTALL.md'));
  assert.ok(res.verifiedFiles.includes('LICENSE'));
});
