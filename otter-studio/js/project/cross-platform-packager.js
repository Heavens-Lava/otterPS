// cross-platform-packager.js - Cross-Platform Packaging & Distribution Engine for Otter Studio

export function generateMacOsAppBundle(manifest, options = {}) {
  const name = manifest.name || 'OtterApp';
  const version = manifest.version || '1.0.0';
  const bundleId = options.bundleId || `com.otter.${name.toLowerCase().replace(/[^a-z0-9]/g, '')}`;
  const executable = options.executable || name;

  const infoPlist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${name}</string>
    <key>CFBundleDisplayName</key>
    <string>${manifest.displayName || name}</string>
    <key>CFBundleIdentifier</key>
    <string>${bundleId}</string>
    <key>CFBundleVersion</key>
    <string>${version}</string>
    <key>CFBundleShortVersionString</key>
    <string>${version}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${executable}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
`;

  const launcherScript = `#!/bin/sh
# macOS Otter App Launcher
DIR="$(cd "$(dirname "$0")/../../Resources" && pwd)"
export OTTER_APP_DIR="$DIR"
if command -v otter >/dev/null 2>&1; then
    exec otter run "$DIR/${manifest.entryPoint || 'main.ot'}" "$@"
elif command -v pwsh >/dev/null 2>&1; then
    exec pwsh -NoProfile -File "$DIR/otter.ps1" run "$DIR/${manifest.entryPoint || 'main.ot'}" "$@"
else
    osascript -e 'display alert "Otter Runtime Not Found" message "Please install Otter or PowerShell 7 (pwsh) to run this application."'
    exit 1
fi
`;

  return {
    bundleName: `${name}.app`,
    structure: {
      'Contents/Info.plist': infoPlist,
      [`Contents/MacOS/${executable}`]: launcherScript,
      'Contents/Resources/': null
    },
    infoPlist,
    launcherScript
  };
}

export function generateLinuxDesktopEntry(manifest, options = {}) {
  const name = manifest.name || 'OtterApp';
  const execPath = options.execPath || `run`;
  const icon = options.icon || name.toLowerCase();
  const comment = manifest.description || `${name} built with Otter`;
  const terminal = manifest.target === 'console' ? 'true' : 'false';
  const categories = options.categories || (manifest.target === 'game' ? 'Game;' : 'Development;Utility;');

  const desktopEntry = `[Desktop Entry]
Version=1.0
Type=Application
Name=${manifest.displayName || name}
Comment=${comment}
Exec=${execPath} %F
Icon=${icon}
Terminal=${terminal}
Categories=${categories}
StartupNotify=true
`;

  const appRunScript = `#!/bin/sh
# Linux AppImage AppRun Launcher
HERE="$(dirname "$(readlink -f "$0")")"
export PATH="$HERE/usr/bin:$PATH"
export OTTER_APP_DIR="$HERE"
if command -v otter >/dev/null 2>&1; then
    exec otter run "$HERE/${manifest.entryPoint || 'main.ot'}" "$@"
elif command -v pwsh >/dev/null 2>&1; then
    exec pwsh -NoProfile -File "$HERE/otter.ps1" run "$HERE/${manifest.entryPoint || 'main.ot'}" "$@"
else
    echo "Otter runtime (otter or pwsh) required to run $NAME" >&2
    exit 1
fi
`;

  return {
    fileName: `${name.toLowerCase()}.desktop`,
    desktopEntry,
    appRunScript
  };
}

export function validateCrossPlatformSafety(manifest, files = []) {
  const issues = [];
  const warnings = [];

  // Check manifest paths
  if (manifest) {
    if (manifest.entryPoint && manifest.entryPoint.includes('\\')) {
      issues.push(`Entry point path contains Windows backslashes: "${manifest.entryPoint}". Use forward slashes for cross-platform safety.`);
    }
    if (manifest.assets && Array.isArray(manifest.assets)) {
      for (const asset of manifest.assets) {
        if (typeof asset === 'string' && asset.includes('\\')) {
          issues.push(`Asset path contains Windows backslashes: "${asset}". Use forward slashes.`);
        }
      }
    }
  }

  // Check file casing collisions (FAT32/NTFS ignores case, Linux ext4 is case-sensitive)
  const lowerMap = new Map();
  for (const f of files) {
    const norm = f.replace(/\\/g, '/');
    const lower = norm.toLowerCase();
    if (lowerMap.has(lower)) {
      issues.push(`Case-sensitivity collision detected between "${lowerMap.get(lower)}" and "${norm}". This will break on Linux/macOS.`);
    } else {
      lowerMap.set(lower, norm);
    }

    if (f.includes('\\')) {
      issues.push(`File path "${f}" uses backslashes instead of cross-platform forward slashes.`);
    }
  }

  return {
    ok: issues.length === 0,
    issues,
    warnings
  };
}
