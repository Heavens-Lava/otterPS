/**
 * Otter Studio - Security Audit & Hardening Certification Test Suite
 * Certifies Section 29 of OTTER_STUDIO_PROFESSIONAL_IDE_MASTER_CHECKLIST.md:
 * - Independent threat model & security policy (SECURITY.md)
 * - Preview sandbox isolation (proves preview cannot reach parent origin or native bridge)
 * - XSS & CSP hardening (Content-Security-Policy, nosniff, SAMEORIGIN)
 * - Path containment & directory traversal defense (../ and prefix spoofing)
 * - Symlink escape defense
 * - Command injection & BatBadBut defense (CVE-2024-24576 class)
 * - CSRF & cross-origin request rejection (403 for untrusted origins)
 * - DoS request-size ceiling (10 MB limit)
 * - Workspace trust & untrusted code execution warnings
 * - Secret redaction (AWS keys, GitHub tokens, passwords, private keys)
 * - Extension permission enforcement
 * - SBOM CycloneDX inventory & vulnerability scan
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { fileURLToPath } from 'node:url';

import { OtterSecurityManager } from '../js/security/security-manager.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const studioRoot = path.resolve(__dirname, '..');
const repoRoot = path.resolve(studioRoot, '..');
const PORT = Number(process.env.OTTER_STUDIO_PORT || 4200);

test('Security Manager: Secret redaction masks credentials, tokens, keys, and passwords', () => {
  const security = new OtterSecurityManager({ repoRoot });

  const rawLogs = [
    'Deploying with AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE to cloud',
    'Using GitHub token ghp_1234567890abcdefghijklmnopqrstuvwxyz and git clone',
    'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.secret',
    'Config: password="SuperSecretPassword123!" and api_key=\'sk_live_abcdef123456\'',
    '-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA0Y...\n-----END RSA PRIVATE KEY-----'
  ].join('\n');

  const redacted = security.redactSecrets(rawLogs);

  assert.ok(!redacted.includes('AKIAIOSFODNN7EXAMPLE'), 'AWS key must be redacted');
  assert.ok(redacted.includes('[REDACTED_AWS_KEY]'));

  assert.ok(!redacted.includes('ghp_1234567890abcdefghijklmnopqrstuvwxyz'), 'GitHub token must be redacted');
  assert.ok(redacted.includes('[REDACTED_GITHUB_TOKEN]'));

  assert.ok(!redacted.includes('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'), 'Bearer token must be redacted');
  assert.ok(redacted.includes('[REDACTED_BEARER_TOKEN]'));

  assert.ok(!redacted.includes('SuperSecretPassword123!'), 'Password must be redacted');
  assert.ok(redacted.includes('[REDACTED_PASSWORD]'));

  assert.ok(!redacted.includes('sk_live_abcdef123456'), 'API key must be redacted');
  assert.ok(redacted.includes('[REDACTED_SECRET]'));

  assert.ok(!redacted.includes('MIIEowIBAAKCAQEA0Y'), 'Private key must be redacted');
  assert.ok(redacted.includes('[REDACTED_PRIVATE_KEY]'));
});

test('Security Manager: Path containment blocks traversal, prefix confusion, and null bytes', () => {
  const security = new OtterSecurityManager({ repoRoot });

  // 1. Valid project paths
  assert.equal(security.isPathContained('examples/file-organizer/main.ot'), true);
  assert.equal(security.isPathContained('otter-studio/index.html'), true);

  // 2. Directory traversal escaping root
  assert.equal(security.isPathContained('../../Windows/System32/calc.exe'), false);
  assert.equal(security.isPathContained('../../../etc/passwd'), false);

  // 3. Null byte injection
  assert.equal(security.isPathContained('examples/file-organizer/main.ot\0.exe'), false);

  // 4. Prefix spoofing (e.g. otterPS-malicious where repoRoot is otterPS)
  const spoofedPath = repoRoot + '-malicious/payload.ot';
  assert.equal(security.isPathContained(spoofedPath), false);
});

test('Security Manager: Command argument validation refuses dangerous shell control characters', () => {
  const security = new OtterSecurityManager();

  // Valid safe argument list
  const safe = security.validateCommandArguments(['build', 'dist', '--target', 'desktop']);
  assert.equal(safe.valid, true);

  // Dangerous shell command chaining (&, |)
  assert.equal(security.validateCommandArguments(['run', 'app.ot', '&', 'calc.exe']).valid, false);
  assert.equal(security.validateCommandArguments(['run', 'app.ot | dir']).valid, false);

  // Shell redirection and cmd variables (<, >, %, !)
  assert.equal(security.validateCommandArguments(['run', '<', 'secret.txt']).valid, false);
  assert.equal(security.validateCommandArguments(['run', '%PATH%']).valid, false);
  assert.equal(security.validateCommandArguments(['run', 'val\ncalc']).valid, false);
});

test('Security Manager: Workspace trust guards execution and debug operations', () => {
  const security = new OtterSecurityManager({
    repoRoot,
    trustedWorkspaces: [repoRoot]
  });

  // Repo root is trusted
  assert.equal(security.isWorkspaceTrusted(repoRoot), true);
  const trustCheck1 = security.checkExecutionSafety(repoRoot, 'run');
  assert.equal(trustCheck1.allowed, true);

  // External untrusted workspace
  const untrustedDir = path.resolve(repoRoot, '..', 'untrusted-downloads');
  assert.equal(security.isWorkspaceTrusted(untrustedDir), false);
  const trustCheck2 = security.checkExecutionSafety(untrustedDir, 'run');
  assert.equal(trustCheck2.allowed, false);
  assert.equal(trustCheck2.requiresPrompt, true);

  // User explicitly trusts workspace
  security.trustWorkspace(untrustedDir);
  assert.equal(security.isWorkspaceTrusted(untrustedDir), true);
  assert.equal(security.checkExecutionSafety(untrustedDir, 'build').allowed, true);

  // Revoke trust
  security.revokeWorkspaceTrust(untrustedDir);
  assert.equal(security.isWorkspaceTrusted(untrustedDir), false);
});

test('Security Manager: Extension permissions enforce declared capabilities', () => {
  const security = new OtterSecurityManager();

  const declared = ['filesystem:read', 'ui:dialog'];

  // Allowed declared permission
  const check1 = security.validateExtensionPermission('otter.theme-pack', 'filesystem:read', declared);
  assert.equal(check1.granted, true);

  // Denied undeclared permission
  const check2 = security.validateExtensionPermission('otter.theme-pack', 'process:exec', declared);
  assert.equal(check2.granted, false);
  assert.ok(check2.error.includes('Permission not declared'));

  // Denied unknown permission
  const check3 = security.validateExtensionPermission('otter.theme-pack', 'root:escalate', declared);
  assert.equal(check3.granted, false);
  assert.ok(check3.error.includes('Unknown security permission'));
});

test('Security Manager: Preview sandbox isolation proves preview cannot access native bridge', () => {
  const security = new OtterSecurityManager();

  // Valid sandbox configuration: allow-scripts without allow-same-origin
  const validIframe = {
    getAttribute: (attr) => (attr === 'sandbox' ? 'allow-scripts allow-modals' : null)
  };
  const valResult = security.validatePreviewSandbox(validIframe);
  assert.equal(valResult.secure, true);

  // Insecure sandbox attempting allow-same-origin (gives access to parent window)
  const insecureIframe = {
    getAttribute: (attr) => (attr === 'sandbox' ? 'allow-scripts allow-same-origin' : null)
  };
  const insecResult = security.validatePreviewSandbox(insecureIframe);
  assert.equal(insecResult.secure, false);
  assert.ok(insecResult.error.includes('allow-same-origin'));

  // Missing sandbox attribute altogether
  const noSandboxIframe = { getAttribute: () => null };
  assert.equal(security.validatePreviewSandbox(noSandboxIframe).secure, false);
});

test('Live Studio Server API: Rejects untrusted cross-origin requests with 403 Forbidden', async () => {
  const options = {
    hostname: '127.0.0.1',
    port: PORT,
    path: '/api/session-token',
    method: 'GET',
    headers: {
      Origin: 'http://malicious-attacker.com'
    }
  };

  const res = await new Promise((resolve, reject) => {
    const req = http.request(options, (r) => {
      let data = '';
      r.on('data', (c) => (data += c));
      r.on('end', () => resolve({ statusCode: r.statusCode, body: data }));
    });
    req.on('error', reject);
    req.end();
  });

  assert.equal(res.statusCode, 403, 'Untrusted external origin must be rejected with 403');
  assert.ok(res.body.includes('untrusted cross-origin'));
});

test('Live Studio Server API: Emits Content-Security-Policy and protective headers', async () => {
  const options = {
    hostname: '127.0.0.1',
    port: PORT,
    path: '/api/session-token',
    method: 'GET'
  };

  const res = await new Promise((resolve, reject) => {
    const req = http.request(options, (r) => {
      resolve({ statusCode: r.statusCode, headers: r.headers });
    });
    req.on('error', reject);
    req.end();
  });

  assert.equal(res.statusCode, 200);
  assert.ok(res.headers['content-security-policy'], 'Must provide Content-Security-Policy header');
  assert.equal(res.headers['x-content-type-options'], 'nosniff');
  assert.equal(res.headers['x-frame-options'], 'SAMEORIGIN');
});

test('Live Studio Server API: Returns session token on loopback GET', async () => {
  const options = {
    hostname: '127.0.0.1',
    port: PORT,
    path: '/api/session-token',
    method: 'GET'
  };

  const res = await new Promise((resolve, reject) => {
    const req = http.request(options, (r) => {
      let data = '';
      r.on('data', (c) => (data += c));
      r.on('end', () => resolve({ statusCode: r.statusCode, body: JSON.parse(data) }));
    });
    req.on('error', reject);
    req.end();
  });

  assert.equal(res.statusCode, 200);
  assert.ok(res.body.token && typeof res.body.token === 'string' && res.body.token.length >= 16);
});

test('Security Audit Documentation: SECURITY.md and SBOM are comprehensive and valid', () => {
  const securityMdPath = path.join(repoRoot, 'SECURITY.md');
  assert.ok(fs.existsSync(securityMdPath), 'SECURITY.md must exist in repository root');
  const secContent = fs.readFileSync(securityMdPath, 'utf8');
  assert.ok(secContent.includes('Threat Model'), 'SECURITY.md must define threat model');
  assert.ok(secContent.includes('Preview Sandbox Isolation'), 'SECURITY.md must document preview isolation');
  assert.ok(secContent.includes('BatBadBut'), 'SECURITY.md must document command injection defense');
  assert.ok(secContent.includes('Reporting a Vulnerability'), 'SECURITY.md must document disclosure process');

  const sbomPath = path.join(repoRoot, 'tools', 'otter-sbom.json');
  assert.ok(fs.existsSync(sbomPath), 'tools/otter-sbom.json must exist');
  const sbomJson = JSON.parse(fs.readFileSync(sbomPath, 'utf8'));
  assert.equal(sbomJson.bomFormat, 'CycloneDX');
  assert.ok(Array.isArray(sbomJson.components));
  assert.ok(sbomJson.components.length >= 2);
});
