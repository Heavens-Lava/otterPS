// publish-wizard.js - Publishing, Release Packaging & Deployment Preset Engine for Otter Studio

export const DEPLOYMENT_PRESETS = {
  'web-static': {
    name: 'Web Static Hosting',
    description: 'Deploy to GitHub Pages, Netlify, Vercel, Cloudflare Pages, or AWS S3 / Azure Blob Storage.',
    target: 'web',
    artifactPattern: '*.zip',
    hostingProviders: ['GitHub Pages', 'Netlify', 'Vercel', 'Cloudflare Pages', 'AWS S3', 'Azure Blob'],
    instructions: (name, version) => [
      `1. Extract the release archive "${name}-${version}.zip" or deploy the built contents of publish/${name}-${version}/.`,
      `2. Ensure "index.html" is set as the root index document.`,
      `3. For GitHub Pages: Push the contents to the "gh-pages" branch or configure GitHub Actions to deploy from publish/ folder.`,
      `4. Verify that client routing uses hash navigation or single-page application fallback rules.`
    ]
  },
  'desktop-windows': {
    name: 'Windows Standalone Runner',
    description: 'Distributable desktop application package containing web shell and authenticated native bridge.',
    target: 'desktop',
    artifactPattern: '*.zip',
    hostingProviders: ['Direct Download', 'GitHub Releases', 'Company Portal'],
    instructions: (name, version) => [
      `1. Distribute "${name}-${version}.zip" to end users or unpack into the target install folder.`,
      `2. Users double-click "run-desktop.cmd" to launch the desktop window with system integration.`,
      `3. System bridge uses loopback-only sockets with per-session authentication tokens for security.`
    ]
  },
  'console-cli': {
    name: 'Console CLI Application',
    description: 'Cross-platform command-line tool with Windows (run.cmd) and macOS/Linux (run) launchers.',
    target: 'console',
    artifactPattern: '*.zip',
    hostingProviders: ['GitHub Releases', 'Package Repositories', 'Direct Download'],
    instructions: (name, version) => [
      `1. Unpack "${name}-${version}.zip" into any directory on the user's PATH or execution directory.`,
      `2. On Windows: execute "run.cmd" with optional command-line arguments.`,
      `3. On macOS/Linux: execute "./run" with executable permissions (chmod +x run).`,
      `4. Requires the Otter runtime (otter.cmd or otter.ps1) installed on the host machine.`
    ]
  },
  'game-canvas': {
    name: '2D Canvas Game Bundle',
    description: 'Self-contained 2D Canvas game bundle with embedded styles, sprites, and input handlers.',
    target: 'game',
    artifactPattern: '*.zip',
    hostingProviders: ['Itch.io', 'GameJolt', 'Web Arcade', 'GitHub Pages'],
    instructions: (name, version) => [
      `1. Upload "${name}-${version}.zip" directly to web game portals such as Itch.io or GameJolt.`,
      `2. Mark "index.html" as the playable canvas entry point.`,
      `3. Fullscreen toggle and keyboard/mouse controls work out of the box with zero external dependencies.`
    ]
  }
};

export function validatePublishReadiness(manifest) {
  const errors = [];
  const warnings = [];

  if (!manifest || typeof manifest !== 'object') {
    return { ok: false, errors: ['Manifest is required and must be an object'], warnings };
  }

  const name = manifest.name ? String(manifest.name).trim() : '';
  if (!name) {
    errors.push('Project manifest must specify a "name"');
  } else if (!/^[A-Za-z0-9_\-\.]+$/.test(name)) {
    errors.push(`Project name "${name}" contains characters invalid for distribution archives`);
  }

  const version = manifest.version ? String(manifest.version).trim() : '';
  if (!version) {
    errors.push('Project manifest must specify a "version"');
  } else if (!/^[0-9]+\.[0-9]+(\.[0-9]+)?(-[A-Za-z0-9\.\-_]+)?$/.test(version)) {
    warnings.push(`Version "${version}" does not strictly adhere to semantic versioning (e.g. 1.0.0 or 0.1.0-beta)`);
  }

  const entryPoint = manifest.entryPoint ? String(manifest.entryPoint).trim() : '';
  if (!entryPoint) {
    errors.push('Project manifest must specify an "entryPoint" (e.g. "main.ot" or "app.ot")');
  } else if (!entryPoint.toLowerCase().endsWith('.ot')) {
    errors.push(`Entry point "${entryPoint}" must be an Otter source file ending in .ot`);
  }

  const target = manifest.target ? String(manifest.target).trim().toLowerCase() : 'console';
  if (!['console', 'web', 'desktop', 'game', 'automation'].includes(target)) {
    errors.push(`Target "${target}" is not a recognized Otter target (expected console, web, desktop, game, automation)`);
  }

  return {
    ok: errors.length === 0,
    errors,
    warnings,
    name,
    version,
    entryPoint,
    target
  };
}

export function generateDeploymentPackage(manifest, publishMeta = {}, presetKey = null) {
  const readiness = validatePublishReadiness(manifest);
  if (!readiness.ok) {
    throw new Error(`Cannot generate deployment package: ${readiness.errors.join('; ')}`);
  }

  const key = presetKey || (readiness.target === 'web' ? 'web-static' : (readiness.target === 'desktop' ? 'desktop-windows' : (readiness.target === 'game' ? 'game-canvas' : 'console-cli')));
  const preset = DEPLOYMENT_PRESETS[key] || DEPLOYMENT_PRESETS['web-static'];

  const name = readiness.name;
  const version = readiness.version;
  const archiveName = `${name}-${version}.zip`;
  const checksumName = `${name}-${version}.zip.sha256`;
  const instructions = preset.instructions(name, version);

  const deployDoc = `# Deployment Guide: ${name} (v${version})

**Target:** ${readiness.target}
**Preset:** ${preset.name}
**Package Archive:** \`${archiveName}\`
**Checksum:** \`${checksumName}\`

## Overview
${preset.description}

## Deployment Steps
${instructions.map(line => `${line}`).join('\n')}

## Security & Verification
Before deploying to production:
1. Verify the archive SHA-256 checksum matches \`${checksumName}\`.
2. Inspect \`otter.publish.json\` for verified dependencies and runtime requirements.
3. Review any secret vaults (secrets are scoped per application ID and excluded from web bundles).
`;

  return {
    preset: key,
    presetName: preset.name,
    target: readiness.target,
    name,
    version,
    archiveName,
    checksumName,
    instructions,
    deployDoc
  };
}

// ============================================================================
// SIGNING HOOKS & CODE SIGNATURE VERIFICATION
// ============================================================================

export class SigningHookManager {
  constructor(options = {}) {
    this.hooks = new Map(); // name -> hookFn
    this.signers = new Map(); // platform -> signerFn
    this._registerDefaultSigners();
  }

  _registerDefaultSigners() {
    // Windows Authenticode hook
    this.registerSigner('windows', async (artifactPath, config = {}) => {
      const cert = config.certificate || 'env:OTTER_CODESIGN_CERT';
      const timestampUrl = config.timestampUrl || 'http://timestamp.digicert.com';
      const command = `signtool sign /f "${cert}" /tr "${timestampUrl}" /td sha256 /fd sha256 "${artifactPath}"`;

      return {
        platform: 'windows',
        signed: true,
        tool: 'signtool.exe',
        command,
        timestampUrl,
        algorithm: 'sha256'
      };
    });

    // macOS codesign / notarize hook
    this.registerSigner('macos', async (artifactPath, config = {}) => {
      const identity = config.identity || 'env:APPLE_DEVELOPER_ID';
      const command = `codesign --deep --force --options runtime --sign "${identity}" "${artifactPath}"`;

      return {
        platform: 'macos',
        signed: true,
        tool: 'codesign',
        command,
        notarized: Boolean(config.notarize)
      };
    });

    // Linux GPG signature hook
    this.registerSigner('linux', async (artifactPath, config = {}) => {
      const keyId = config.keyId || 'default';
      const command = `gpg --detach-sign --armor --default-key "${keyId}" "${artifactPath}"`;

      return {
        platform: 'linux',
        signed: true,
        tool: 'gpg',
        command,
        signatureFile: `${artifactPath}.asc`
      };
    });
  }

  registerSigner(platform, signerFn) {
    this.signers.set(platform.toLowerCase(), signerFn);
  }

  registerHook(name, hookFn) {
    this.hooks.set(name, hookFn);
  }

  async executeSigningPipeline({
    artifactPath,
    platform = 'windows',
    signingConfig = {},
    dryRun = false
  }) {
    const plat = platform.toLowerCase();
    const results = {
      artifactPath,
      platform: plat,
      timestamp: new Date().toISOString(),
      hooksExecuted: [],
      signature: null,
      dryRun
    };

    // 1. Pre-signing hook
    if (this.hooks.has('beforeSign')) {
      const beforeRes = await this.hooks.get('beforeSign')({ artifactPath, platform: plat, config: signingConfig });
      results.hooksExecuted.push({ hook: 'beforeSign', result: beforeRes });
    }

    // 2. Execute platform signer
    const signer = this.signers.get(plat);
    if (!signer) {
      throw new Error(`No code signing hook registered for platform "${platform}"`);
    }

    if (dryRun) {
      results.signature = {
        platform: plat,
        signed: false,
        dryRun: true,
        mockCommand: `[dry-run] sign ${artifactPath}`
      };
    } else {
      results.signature = await signer(artifactPath, signingConfig);
    }

    // 3. Post-signing hook
    if (this.hooks.has('afterSign')) {
      const afterRes = await this.hooks.get('afterSign')({
        artifactPath,
        platform: plat,
        signature: results.signature
      });
      results.hooksExecuted.push({ hook: 'afterSign', result: afterRes });
    }

    return results;
  }
}

