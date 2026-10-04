// cross-platform.test.mjs - Verification Suite for Cross-Platform Distribution and Tooling
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  generateMacOsAppBundle,
  generateLinuxDesktopEntry,
  validateCrossPlatformSafety
} from '../js/project/cross-platform-packager.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');

test('Cross-Platform Distribution: macOS app bundle generator produces valid Info.plist and POSIX launcher', () => {
  const manifest = {
    name: 'OtterShowcase',
    displayName: 'Otter Showcase App',
    version: '1.2.3',
    entryPoint: 'main.ot'
  };

  const bundle = generateMacOsAppBundle(manifest, { bundleId: 'org.otter.showcase' });
  assert.equal(bundle.bundleName, 'OtterShowcase.app');
  assert.ok(bundle.infoPlist.includes('<key>CFBundleName</key>'));
  assert.ok(bundle.infoPlist.includes('<string>OtterShowcase</string>'));
  assert.ok(bundle.infoPlist.includes('<string>org.otter.showcase</string>'));
  assert.ok(bundle.infoPlist.includes('<string>1.2.3</string>'));
  assert.ok(bundle.infoPlist.includes('<key>NSHighResolutionCapable</key>'));
  assert.ok(bundle.infoPlist.includes('<true/>'));

  // Launcher script must be valid POSIX sh
  assert.ok(bundle.launcherScript.startsWith('#!/bin/sh'));
  assert.ok(bundle.launcherScript.includes('otter run'));
  assert.ok(bundle.launcherScript.includes('pwsh -NoProfile'));
});

test('Cross-Platform Distribution: Linux FreeDesktop entry and AppRun generator', () => {
  const consoleManifest = {
    name: 'OtterCLI',
    displayName: 'Otter Command Line Tool',
    version: '1.0.0',
    target: 'console',
    entryPoint: 'cli.ot'
  };

  const desktop = generateLinuxDesktopEntry(consoleManifest);
  assert.equal(desktop.fileName, 'ottercli.desktop');
  assert.ok(desktop.desktopEntry.includes('[Desktop Entry]'));
  assert.ok(desktop.desktopEntry.includes('Type=Application'));
  assert.ok(desktop.desktopEntry.includes('Name=Otter Command Line Tool'));
  assert.ok(desktop.desktopEntry.includes('Terminal=true'));
  assert.ok(desktop.desktopEntry.includes('Categories=Development;Utility;'));

  // AppRun script
  assert.ok(desktop.appRunScript.startsWith('#!/bin/sh'));
  assert.ok(desktop.appRunScript.includes('readlink -f'));
});

test('Cross-Platform Distribution: validateCrossPlatformSafety detects path backslashes and case collisions', () => {
  // Valid cross-platform project
  const valid = validateCrossPlatformSafety(
    { name: 'SafeApp', entryPoint: 'src/main.ot', assets: ['assets/icon.png', 'assets/data.json'] },
    ['src/main.ot', 'assets/icon.png', 'assets/data.json']
  );
  assert.equal(valid.ok, true);
  assert.equal(valid.issues.length, 0);

  // Backslash in entryPoint
  const backslashEntry = validateCrossPlatformSafety(
    { name: 'App', entryPoint: 'src\\main.ot' },
    ['src/main.ot']
  );
  assert.equal(backslashEntry.ok, false);
  assert.ok(backslashEntry.issues.some(i => i.includes('Windows backslashes')));

  // Case collision (fails on Linux/macOS case-sensitive filesystems)
  const collision = validateCrossPlatformSafety(
    { name: 'App', entryPoint: 'main.ot' },
    ['src/utils.ot', 'src/Utils.ot']
  );
  assert.equal(collision.ok, false);
  assert.ok(collision.issues.some(i => i.includes('Case-sensitivity collision')));
});

test('Cross-Platform Distribution: published console project contains both Windows (run.cmd) and POSIX (run) launchers', () => {
  // Check the root launchers or distribution launchers
  const rootRunCmd = path.join(REPO_ROOT, 'otter.cmd');
  const rootRunSh = path.join(REPO_ROOT, 'otter');

  assert.ok(fs.existsSync(rootRunCmd), 'Windows otter.cmd must exist');
  assert.ok(fs.existsSync(rootRunSh), 'POSIX shell launcher otter must exist');

  const shContent = fs.readFileSync(rootRunSh, 'utf8');
  assert.ok(shContent.startsWith('#!/bin/sh'), 'otter POSIX launcher must start with #!/bin/sh');
  assert.ok(shContent.includes('pwsh') || shContent.includes('powershell'), 'POSIX launcher invokes PowerShell runtime');
});
