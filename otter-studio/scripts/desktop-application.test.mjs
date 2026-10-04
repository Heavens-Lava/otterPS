// desktop-application.test.mjs - Comprehensive Test Suite for Section 14: Desktop Application Target
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  PLATFORM_CAPABILITY_MATRIX,
  IPC_STRATEGY,
  WindowManager,
  generateNativeMenuTemplate,
  generateTrayMenuTemplate,
  buildNotificationPayload,
  generateFileAssociationRegistry,
  generateSingleInstanceScript,
  prepareDesktopUpdate,
  generateInnoSetupScript,
  generateCodeSigningConfig,
  generateDebianPackageMeta,
  DesktopCrashReporter,
  buildDesktopPackage
} from '../js/project/desktop-target-engine.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');

// ----------------------------------------------------------------------------
// 1. Per-Platform Capability Matrix & Specifications (Section 14.19)
// ----------------------------------------------------------------------------
test('Section 14.19: Per-Platform Capability Matrix for Windows, macOS & Linux', () => {
  assert.ok(PLATFORM_CAPABILITY_MATRIX.windows);
  assert.ok(PLATFORM_CAPABILITY_MATRIX.macos);
  assert.ok(PLATFORM_CAPABILITY_MATRIX.linux);

  // Windows capabilities
  const win = PLATFORM_CAPABILITY_MATRIX.windows;
  assert.equal(win.features.multipleWindows, true);
  assert.equal(win.features.singleInstanceMutex, true);
  assert.match(win.features.codeSigning, /Authenticode/);

  // macOS capabilities
  const mac = PLATFORM_CAPABILITY_MATRIX.macos;
  assert.equal(mac.features.multipleWindows, true);
  assert.match(mac.features.codeSigning, /codesign/);
  assert.match(mac.features.notarization, /notarytool/);

  // Linux capabilities
  const linux = PLATFORM_CAPABILITY_MATRIX.linux;
  assert.equal(linux.features.multipleWindows, true);
  assert.match(linux.packaging[1], /Debian/);
});

// ----------------------------------------------------------------------------
// 2. In-Process & Loopback IPC Strategy (Section 14.2)
// ----------------------------------------------------------------------------
test('Section 14.2: In-Process IPC Strategy Protocol & Security', () => {
  assert.equal(IPC_STRATEGY.architecture, 'Authenticated Host-Client Bridge');
  assert.match(IPC_STRATEGY.securityModel, /Session-scoped random token/);

  const env = IPC_STRATEGY.messageEnvelope('window:minimize', { windowId: 'win_1' }, 'req_123');
  assert.equal(env.jsonrpc, '2.0');
  assert.equal(env.id, 'req_123');
  assert.equal(env.action, 'window:minimize');
  assert.equal(env.payload.windowId, 'win_1');

  const parsed = IPC_STRATEGY.parseMessage(JSON.stringify(env));
  assert.equal(parsed.ok, true);
  assert.equal(parsed.message.action, 'window:minimize');

  const badParsed = IPC_STRATEGY.parseMessage('invalid json string');
  assert.equal(badParsed.ok, false);
});

// ----------------------------------------------------------------------------
// 3. Multiple Windows Management (Section 14.6)
// ----------------------------------------------------------------------------
test('Section 14.6: Multi-Window Lifecycle & State Management', () => {
  const wm = new WindowManager();
  assert.equal(wm.listWindows().length, 0);

  const mainWin = wm.createWindow({ title: 'Main Editor', width: 1200, height: 800 });
  assert.ok(mainWin.id);
  assert.equal(mainWin.title, 'Main Editor');
  assert.equal(wm.activeWindowId, mainWin.id);

  const prefWin = wm.createWindow({ title: 'Preferences', modal: true, parentId: mainWin.id });
  assert.equal(prefWin.modal, true);
  assert.equal(prefWin.parentId, mainWin.id);
  assert.equal(wm.listWindows().length, 2);

  wm.focusWindow(mainWin.id);
  assert.equal(wm.activeWindowId, mainWin.id);

  const closed = wm.closeWindow(mainWin.id);
  assert.equal(closed, true);
  assert.equal(wm.listWindows().length, 1);
  assert.equal(wm.activeWindowId, prefWin.id);
});

// ----------------------------------------------------------------------------
// 4. Native Menus, Dialogs & Tray Menu (Section 14.7, 14.8)
// ----------------------------------------------------------------------------
test('Section 14.7, 14.8: Native Menus, Accelerators & System Tray', () => {
  const menus = generateNativeMenuTemplate('OtterStudio');
  assert.ok(menus.some(m => m.label === 'File'));
  assert.ok(menus.some(m => m.label === 'Edit'));
  assert.ok(menus.some(m => m.label === 'View'));
  assert.ok(menus.some(m => m.label === 'Help'));

  const fileMenu = menus.find(m => m.label === 'File');
  assert.ok(fileMenu.submenu.some(item => item.label === 'Save' && item.accelerator === 'Ctrl+S'));

  const tray = generateTrayMenuTemplate('OtterStudio');
  assert.ok(tray.some(t => t.action === 'tray:show'));
  assert.ok(tray.some(t => t.action === 'app:exit'));
});

// ----------------------------------------------------------------------------
// 5. Desktop Native Notifications (Section 14.9)
// ----------------------------------------------------------------------------
test('Section 14.9: Desktop Native Notifications Engine', () => {
  const notif = buildNotificationPayload({
    title: 'Build Succeeded',
    body: 'Otter application compiled in 142ms.',
    urgency: 'normal'
  });

  assert.equal(notif.title, 'Build Succeeded');
  assert.match(notif.body, /142ms/);
  assert.equal(notif.urgency, 'normal');
  assert.ok(notif.id.startsWith('notif_'));
});

// ----------------------------------------------------------------------------
// 6. File Associations & Protocol Handlers (Section 14.10, 14.11)
// ----------------------------------------------------------------------------
test('Section 14.10, 14.11: File Associations & Deep-Link Protocols', () => {
  const assoc = generateFileAssociationRegistry({ name: 'OtterEditor' }, { extension: '.ot', protocol: 'otter' });

  assert.equal(assoc.extension, '.ot');
  assert.equal(assoc.protocol, 'otter');
  assert.match(assoc.windowsReg, /\[HKEY_CURRENT_USER\\Software\\Classes\\\.ot\]/);
  assert.match(assoc.windowsReg, /\[HKEY_CURRENT_USER\\Software\\Classes\\otter\]/);
  assert.match(assoc.windowsReg, /URL:otter Protocol/);
  assert.match(assoc.linuxMime, /<glob pattern="\*\.ot"\/>/);
});

// ----------------------------------------------------------------------------
// 7. Single-Instance App Mutex (Section 14.12)
// ----------------------------------------------------------------------------
test('Section 14.12: Single-Instance Application Mutex Script', () => {
  const script = generateSingleInstanceScript('OtterStudio');
  assert.match(script, /function Test-OtterSingleInstance/);
  assert.match(script, /System\.Threading\.Mutex/);
  assert.match(script, /OtterAppMutex_\$AppId/);
  assert.match(script, /param\(\[string\]\$AppId = "OtterStudio"/);
});

// ----------------------------------------------------------------------------
// 8. Auto-Update & Staging (Section 14.13)
// ----------------------------------------------------------------------------
test('Section 14.13: Desktop Auto-Update Staging & Script Generation', () => {
  const update = prepareDesktopUpdate('1.0.0', {
    version: '1.0.1',
    sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    downloadUrl: 'https://releases.otter-lang.org/desktop/v1.0.1.zip'
  });

  assert.equal(update.canUpdate, true);
  assert.equal(update.nextVersion, '1.0.1');
  assert.match(update.scriptContent, /xcopy \/E \/Y/);
  assert.match(update.scriptContent, /run-desktop\.cmd/);
});

// ----------------------------------------------------------------------------
// 9. Installer & Uninstaller Generation (Section 14.14)
// ----------------------------------------------------------------------------
test('Section 14.14: InnoSetup Windows Installer Script', () => {
  const inno = generateInnoSetupScript({
    name: 'OtterStudio',
    version: '1.0.0',
    publisher: 'Otter Software',
    url: 'https://otter-lang.org'
  });

  assert.match(inno, /AppName=OtterStudio/);
  assert.match(inno, /AppVersion=1\.0\.0/);
  assert.match(inno, /DefaultDirName=\{autopf\}\\OtterStudio/);
  assert.match(inno, /\{cm:UninstallProgram,OtterStudio\}/);
});

// ----------------------------------------------------------------------------
// 10. Code Signing & macOS Notarization (Section 14.15, 14.16)
// ----------------------------------------------------------------------------
test('Section 14.15, 14.16: Code Signing & macOS Notarization Config', () => {
  const cfg = generateCodeSigningConfig();
  assert.equal(cfg.windows.tool, 'signtool.exe');
  assert.match(cfg.windows.command('app.exe', 'cert.pfx', 'pass'), /signtool\.exe sign/);

  assert.equal(cfg.macos.tool, 'codesign');
  assert.match(cfg.macos.notarization.tool, /notarytool/);
  assert.match(cfg.macos.entitlements, /com\.apple\.security\.cs\.allow-jit/);
});

// ----------------------------------------------------------------------------
// 11. Linux Packaging & Control Scripts (Section 14.17)
// ----------------------------------------------------------------------------
test('Section 14.17: Linux Debian Package Control & Postinst', () => {
  const deb = generateDebianPackageMeta({
    name: 'OtterStudio',
    version: '1.0.0',
    description: 'Otter Studio Desktop IDE'
  });

  assert.equal(deb.pkgName, 'otterstudio');
  assert.match(deb.control, /Package: otterstudio/);
  assert.match(deb.control, /Depends: powershell \| pwsh/);
  assert.match(deb.postinst, /update-desktop-database/);
});

// ----------------------------------------------------------------------------
// 12. Desktop Crash Reporting & Minidumps (Section 14.18)
// ----------------------------------------------------------------------------
test('Section 14.18: Desktop Crash Dumps & Diagnostic Journaling', () => {
  const testCrashDir = path.join(REPO_ROOT, 'publish', 'test-crash-app');
  const reporter = new DesktopCrashReporter(testCrashDir);

  try {
    const res = reporter.recordCrash(new Error('Test UI thread failure'), { window: 'main' });
    assert.equal(res.ok, true);
    assert.ok(fs.existsSync(res.dumpPath));

    const crashes = reporter.listCrashes();
    assert.equal(crashes.length, 1);
    assert.equal(crashes[0].error.message, 'Test UI thread failure');
    assert.equal(crashes[0].context.window, 'main');
  } finally {
    if (fs.existsSync(testCrashDir)) {
      fs.rmSync(testCrashDir, { recursive: true, force: true });
    }
  }
});

// ----------------------------------------------------------------------------
// 13. End-to-End Desktop Packaging (Windows, macOS, Linux) (Section 14.1, 14.3, 14.4, 14.5)
// ----------------------------------------------------------------------------
test('Section 14.1, 14.3, 14.4, 14.5: End-to-End Desktop Packaging Pipeline', () => {
  const testOutDir = path.join(REPO_ROOT, 'publish', 'test-desktop-pkg');

  try {
    const res = buildDesktopPackage({
      outputDir: testOutDir,
      platform: 'all',
      manifest: {
        name: 'OtterDesktopApp',
        version: '1.0.0',
        entryPoint: 'main.ot'
      }
    });

    assert.equal(res.ok, true);
    assert.ok(fs.existsSync(path.join(testOutDir, 'windows', 'run-desktop.cmd')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'windows', 'installer.iss')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'windows', 'associations.reg')));

    assert.ok(fs.existsSync(path.join(testOutDir, 'macos', 'OtterDesktopApp.app', 'Contents', 'Info.plist')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'macos', 'OtterDesktopApp.app', 'Contents', 'MacOS', 'OtterDesktopApp')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'macos', 'entitlements.plist')));

    assert.ok(fs.existsSync(path.join(testOutDir, 'linux', 'otterdesktopapp.desktop')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'linux', 'DEBIAN', 'control')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'linux', 'DEBIAN', 'postinst')));

    // Verify Windows runner script executes correctly or contains hardened environment
    const winCmd = fs.readFileSync(path.join(testOutDir, 'windows', 'run-desktop.cmd'), 'utf8');
    assert.match(winCmd, /OTTER_SESSION_TOKEN/);
    assert.match(winCmd, /Otter Desktop Host/);
  } finally {
    if (fs.existsSync(testOutDir)) {
      fs.rmSync(testOutDir, { recursive: true, force: true });
    }
  }
});
