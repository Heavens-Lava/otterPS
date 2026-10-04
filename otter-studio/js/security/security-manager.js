/**
 * Otter Studio - Security Manager & Audit Engine
 * Path Containment, Command Injection Hardening, Secret Redaction,
 * Workspace Trust, Extension Permission Control & Preview Sandbox Validation
 */

import path from 'node:path';
import fs from 'node:fs';

export class OtterSecurityManager {
  constructor(options = {}) {
    this.repoRoot = options.repoRoot ? path.resolve(options.repoRoot) : process.cwd();
    this.trustedWorkspaces = new Set(options.trustedWorkspaces || [this.repoRoot]);
  }

  /**
   * Secret Redaction Engine
   * Detects and redacts credentials, API keys, tokens, and private keys from logs and terminal outputs.
   * @param {string} text
   * @returns {string}
   */
  redactSecrets(text) {
    if (!text || typeof text !== 'string') return text;

    return text
      // 1. AWS Access Key IDs
      .replace(/\b(AKIA[0-9A-Z]{16})\b/g, '[REDACTED_AWS_KEY]')
      // 2. GitHub Personal Access Tokens
      .replace(/\b(ghp_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9_]{82})\b/g, '[REDACTED_GITHUB_TOKEN]')
      // 3. Bearer authentication tokens
      .replace(/(Bearer\s+)[a-zA-Z0-9_\-\.]{16,}/gi, '$1[REDACTED_BEARER_TOKEN]')
      // 4. Private RSA/EC/OPENSSH keys
      .replace(/-----BEGIN [A-Z ]+ PRIVATE KEY-----[\s\S]+?-----END [A-Z ]+ PRIVATE KEY-----/g, '[REDACTED_PRIVATE_KEY]')
      // 5. Generic API Key & Secret assignments (e.g. api_key="...", secret='...')
      .replace(/(api[_-]?key|secret|token|auth[_-]?token)(\s*[:=]\s*["'])([^"']{6,})(["'])/gi, '$1$2[REDACTED_SECRET]$4')
      // 6. Password fields (e.g. password="...", pass='...')
      .replace(/(password|passwd|pwd)(\s*[:=]\s*["'])([^"']{4,})(["'])/gi, '$1$2[REDACTED_PASSWORD]$4')
      // 7. Generic high-entropy hex/base64 strings labeled as keys
      .replace(/(private_key|client_secret)(\s*[:=]\s*["'])([^"']+)(["'])/gi, '$1$2[REDACTED_KEY]$4');
  }

  /**
   * Verify that a candidate path is safely contained within an allowed base directory.
   * Prevents directory traversal attacks (e.g. ../../etc/passwd) and prefix spoofing.
   * @param {string} candidatePath
   * @param {string} [baseDir]
   * @returns {boolean}
   */
  isPathContained(candidatePath, baseDir = this.repoRoot) {
    if (!candidatePath || typeof candidatePath !== 'string') return false;

    // Check for null bytes or control characters
    if (candidatePath.includes('\0')) return false;

    const normalizedBase = path.resolve(baseDir);
    const resolvedCandidate = path.resolve(normalizedBase, candidatePath);

    // Prevent prefix spoofing: candidate must equal base or start with base + separator
    const isWithinBase =
      resolvedCandidate === normalizedBase ||
      resolvedCandidate.startsWith(normalizedBase + path.sep);

    if (!isWithinBase) return false;

    // Symlink escape defense: if candidate exists on disk, check its canonical realpath
    try {
      if (fs.existsSync(resolvedCandidate)) {
        const realCandidate = fs.realpathSync(resolvedCandidate);
        const realBase = fs.realpathSync(normalizedBase);
        const isRealContained =
          realCandidate === realBase ||
          realCandidate.startsWith(realBase + path.sep);
        if (!isRealContained) return false;
      }
    } catch {
      // If path doesn't exist yet, string containment is the authoritative check
    }

    return true;
  }

  /**
   * Validate command-line arguments to prevent shell injection (BatBadBut / CVE-2024-24576 class).
   * Refuses characters that trigger cmd.exe shell expansion when unquoted.
   * @param {string[]} args
   * @returns {{ valid: boolean, error?: string }}
   */
  validateCommandArguments(args) {
    if (!Array.isArray(args)) {
      return { valid: false, error: 'Arguments must be an array' };
    }

    // Characters that are dangerous when interpolated into Windows cmd.exe
    const dangerousChars = /[&|<>\^%!\r\n\0]/;

    for (const arg of args) {
      const str = String(arg);
      if (dangerousChars.test(str)) {
        return {
          valid: false,
          error: `Argument contains forbidden shell control characters: ${JSON.stringify(str)}`
        };
      }
    }

    return { valid: true };
  }

  /**
   * Workspace Trust Management
   * Determines whether an Otter workspace is trusted to execute build scripts or programs.
   */
  isWorkspaceTrusted(workspacePath) {
    const resolved = path.resolve(workspacePath);
    for (const trusted of this.trustedWorkspaces) {
      if (resolved === trusted || resolved.startsWith(trusted + path.sep)) {
        return true;
      }
    }
    return false;
  }

  trustWorkspace(workspacePath) {
    this.trustedWorkspaces.add(path.resolve(workspacePath));
  }

  revokeWorkspaceTrust(workspacePath) {
    this.trustedWorkspaces.delete(path.resolve(workspacePath));
  }

  /**
   * Check if an execution action requires a user security prompt.
   * @param {string} workspacePath
   * @param {'run' | 'build' | 'debug' | 'task'} action
   */
  checkExecutionSafety(workspacePath, action = 'run') {
    if (this.isWorkspaceTrusted(workspacePath)) {
      return { allowed: true };
    }
    return {
      allowed: false,
      requiresPrompt: true,
      warning: `Workspace at "${workspacePath}" is untrusted. Running ${action} could execute untrusted code.`
    };
  }

  /**
   * Extension Permission Enforcement
   * Verifies that an extension has declared and been granted the requested capability.
   * @param {string} extensionId
   * @param {string} requestedPermission
   * @param {string[]} declaredPermissions
   */
  validateExtensionPermission(extensionId, requestedPermission, declaredPermissions = []) {
    const knownPermissions = new Set([
      'filesystem:read',
      'filesystem:write',
      'process:exec',
      'network:connect',
      'ui:dialog'
    ]);

    if (!knownPermissions.has(requestedPermission)) {
      return { granted: false, error: `Unknown security permission: "${requestedPermission}"` };
    }

    if (!declaredPermissions.includes(requestedPermission)) {
      return {
        granted: false,
        error: `Extension "${extensionId}" was denied "${requestedPermission}". Permission not declared in manifest.`
      };
    }

    return { granted: true };
  }

  /**
   * Validate that a preview iframe is strictly sandboxed without same-origin privileges.
   * Proves preview cannot reach window.parent or execute native backend bridge calls.
   * @param {{ getAttribute: (attr: string) => string|null }} iframeLike
   */
  validatePreviewSandbox(iframeLike) {
    if (!iframeLike) return { secure: false, error: 'No iframe provided' };

    const sandbox = iframeLike.getAttribute('sandbox');
    if (!sandbox) {
      return { secure: false, error: 'Preview iframe lacks sandbox attribute' };
    }

    const tokens = sandbox.split(/\s+/).filter(Boolean);

    // Must NOT have allow-same-origin (which would give access to parent origin & storage)
    if (tokens.includes('allow-same-origin')) {
      return {
        secure: false,
        error: 'Security violation: sandbox includes "allow-same-origin" which allows parent origin access'
      };
    }

    // Must NOT have allow-top-navigation (which would allow redirecting the IDE window)
    if (tokens.includes('allow-top-navigation')) {
      return {
        secure: false,
        error: 'Security violation: sandbox includes "allow-top-navigation"'
      };
    }

    // Must have allow-scripts to run the compiled application
    if (!tokens.includes('allow-scripts')) {
      return {
        secure: false,
        error: 'Preview iframe requires "allow-scripts" to execute compiled app'
      };
    }

    return {
      secure: true,
      tokens
    };
  }
}

export const securityManager = new OtterSecurityManager();
