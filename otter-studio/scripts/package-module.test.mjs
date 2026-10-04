// otter-studio/scripts/package-module.test.mjs
// Certification Test Suite for Section 21: Packages and Modules
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ModuleResolutionEngine,
  ModuleDependencyGraph,
  LockfileManager,
  DependencyResolver,
  OfflineCacheManager,
  SecurityAndLicenseScanner,
  PublishManager
} from '../js/project/package-module-engine.js';

const baseUrl = 'http://127.0.0.1:4200';

test('Section 21.3, 21.5, 21.6: Module Resolution, Circular Import Detection & Exports Filtering', () => {
  const engine = new ModuleResolutionEngine();

  // 1. Relative import resolution
  const relRes = engine.resolve('./math.ot', 'src/main.ot');
  assert.equal(relRes.type, 'relative');
  assert.equal(relRes.resolvedPath, 'src/math.ot');

  const parentRel = engine.resolve('../core/calc.ot', 'src/modules/app.ot');
  assert.equal(parentRel.resolvedPath, 'src/core/calc.ot');

  // 2. Package import resolution
  const pkgRes = engine.resolve('math-utils', 'src/main.ot');
  assert.equal(pkgRes.type, 'package');
  assert.equal(pkgRes.resolvedPath, 'packages/math-utils/main.ot');

  const scopedPkg = engine.resolve('@otter/net/client', 'src/main.ot');
  assert.equal(scopedPkg.resolvedPath, 'packages/@otter/net/client.ot');

  // 3. Circular dependency detection
  const importMap = new Map([
    ['a.ot', new Set(['b.ot'])],
    ['b.ot', new Set(['c.ot'])],
    ['c.ot', new Set(['a.ot', 'd.ot'])],
    ['d.ot', new Set()]
  ]);
  const cycleResult = engine.detectCircular(importMap);
  assert.equal(cycleResult.hasCycle, true);
  assert.ok(cycleResult.cycles.length > 0);
  assert.deepEqual(cycleResult.cycles[0], ['a.ot', 'b.ot', 'c.ot', 'a.ot']);

  // 4. Exports filtering (public vs private)
  const symbols = ['score', 'calcSum', '_internalCache', '_hiddenVar'];
  const filtered = engine.filterExports(symbols);
  assert.deepEqual(filtered, ['score', 'calcSum']);

  const explicit = engine.filterExports(symbols, ['score', '_internalCache']);
  assert.deepEqual(explicit, ['score', '_internalCache']);
});

test('Section 21.7: Module Dependency Graph & Topological Ordering', () => {
  const graph = new ModuleDependencyGraph();
  graph.addDependency('main.ot', 'ui.ot');
  graph.addDependency('ui.ot', 'components.ot');
  graph.addDependency('components.ot', 'core.ot');
  graph.addDependency('main.ot', 'data.ot');
  graph.addDependency('data.ot', 'core.ot');

  assert.deepEqual(graph.getDependencies('main.ot'), ['ui.ot', 'data.ot']);
  assert.deepEqual(graph.getDependents('core.ot'), ['components.ot', 'data.ot']);

  const order = graph.getTopologicalOrder();
  assert.equal(order[0], 'main.ot');
  // core.ot should come after its dependents in build order
  assert.ok(order.indexOf('core.ot') > order.indexOf('ui.ot'));
});

test('Section 21.11, 21.16: Lockfile Generation & SRI SHA-256 Integrity Hashes', () => {
  const manifest = { name: 'sample-app', version: '2.0.0' };
  const resolved = {
    'core': { version: '1.4.0', dependencies: {} },
    'math-utils': { version: '2.1.0', dependencies: { 'core': '^1.0.0' } }
  };

  const lock = LockfileManager.generateLockfile(manifest, resolved);
  assert.equal(lock.lockfileVersion, 1);
  assert.equal(lock.name, 'sample-app');
  assert.ok(lock.packages['core'].integrity.startsWith('sha256-'));
  assert.ok(lock.packages['math-utils'].integrity.startsWith('sha256-'));

  const valid = LockfileManager.verifyIntegrity('core@1.4.0', lock.packages['core'].integrity);
  assert.equal(valid, true);

  const invalid = LockfileManager.verifyIntegrity('tampered-content', lock.packages['core'].integrity);
  assert.equal(invalid, false);
});

test('Section 21.13, 21.14, 21.15: Transitive Dependencies & Version Conflict Resolution', () => {
  const registryCatalog = {
    'web-framework': {
      versions: {
        '2.0.0': { dependencies: { 'router': '^1.0.0', 'template-engine': '^3.0.0' } }
      }
    },
    'router': {
      versions: {
        '1.2.0': { dependencies: { 'path-match': '^1.0.0' } }
      }
    },
    'path-match': {
      versions: {
        '1.0.1': { dependencies: {} }
      }
    },
    'template-engine': {
      versions: {
        '3.1.0': { dependencies: {} }
      }
    }
  };

  // Transitive resolution
  const rootDeps = { 'web-framework': '^2.0.0' };
  const transRes = DependencyResolver.resolve(rootDeps, registryCatalog);
  assert.equal(transRes.success, true);
  assert.ok(transRes.resolved['web-framework']);
  assert.ok(transRes.resolved['router']);
  assert.ok(transRes.resolved['path-match']);
  assert.ok(transRes.resolved['template-engine']);

  // Conflict detection
  const conflictingCatalog = {
    'lib-a': { versions: { '1.0.0': { dependencies: { 'shared-dep': '^1.0.0' } } } },
    'lib-b': { versions: { '1.0.0': { dependencies: { 'shared-dep': '^2.0.0' } } } },
    'shared-dep': {
      versions: {
        '1.5.0': { dependencies: {} },
        '2.1.0': { dependencies: {} }
      }
    }
  };
  const conflictRes = DependencyResolver.resolve({ 'lib-a': '1.0.0', 'lib-b': '1.0.0' }, conflictingCatalog);
  assert.equal(conflictRes.success, false);
  assert.ok(conflictRes.conflicts.length > 0);
  assert.equal(conflictRes.conflicts[0].package, 'shared-dep');

  // Local and Git dependencies
  const localGitDeps = {
    'custom-logger': { version: 'local', path: '../custom-logger' },
    'auth-plugin': { version: 'git', url: 'git:https://github.com/otter-community/auth.git' }
  };
  const localRes = DependencyResolver.resolve({ 'custom-logger': '*', 'auth-plugin': '*' }, {}, localGitDeps);
  assert.equal(localRes.success, true);
  assert.equal(localRes.resolved['custom-logger'].version, 'local');
  assert.equal(localRes.resolved['auth-plugin'].version, 'git');
});

test('Section 21.19, 21.20: Offline Cache & Zero-Network Reproducible Restore', () => {
  const cache = new OfflineCacheManager();
  const pkgData = Buffer.from('package code archive content');

  cache.put('graphics-2d', '1.0.0', pkgData, { author: 'Otter' });
  assert.equal(cache.has('graphics-2d', '1.0.0'), true);
  assert.equal(cache.has('graphics-2d', '2.0.0'), false);

  const retrieved = cache.get('graphics-2d', '1.0.0');
  assert.ok(retrieved);
  assert.equal(retrieved.metadata.author, 'Otter');
  assert.equal(cache.list().length, 1);
});

test('Section 21.17, 21.18: License Compliance, Vulnerability Scanner & Package Signing', () => {
  // License audit
  const licenses = {
    'core': 'MIT',
    'math': 'Apache-2.0',
    'gpl-tool': 'GPL-3.0',
    'proprietary': 'Commercial-Custom'
  };
  const audit = SecurityAndLicenseScanner.auditLicenses(licenses);
  assert.equal(audit.compliant, false); // has warnings
  assert.ok(audit.results.some(r => r.package === 'gpl-tool' && r.status === 'warning'));
  assert.ok(audit.results.some(r => r.package === 'proprietary' && r.status === 'warning'));

  // Vulnerability scan
  const packages = { 'net-client': '1.0.4', 'safe-lib': '2.0.0' };
  const advisories = [
    {
      package: 'net-client',
      vulnerableRange: '<= 1.0.4',
      cve: 'CVE-2026-9999',
      severity: 'high',
      title: 'Buffer overflow in packet parsing',
      patchedIn: '1.0.5'
    }
  ];
  const vulnReport = SecurityAndLicenseScanner.scanVulnerabilities(packages, advisories);
  assert.equal(vulnReport.vulnerable, true);
  assert.equal(vulnReport.findings[0].cve, 'CVE-2026-9999');

  // Package signing
  const pkgManifest = { name: 'secure-pkg', version: '1.0.0' };
  const signed = SecurityAndLicenseScanner.signPackage(pkgManifest, 'secret-signing-key');
  assert.ok(signed.signature.startsWith('sig-sha256:'));
  assert.equal(SecurityAndLicenseScanner.verifySignature(pkgManifest, signed.signature, 'secret-signing-key'), true);
  assert.equal(SecurityAndLicenseScanner.verifySignature(pkgManifest, signed.signature, 'wrong-key'), false);
});

test('Section 21.21: Package Publishing and Deprecation Manager', () => {
  const pm = new PublishManager();
  const manifest = {
    name: 'otter-router',
    version: '1.0.0',
    license: 'MIT',
    entryPoint: 'main.ot'
  };

  const archive = Buffer.from('binary-tarball');
  const entry = pm.publish(manifest, archive);
  assert.equal(entry.name, 'otter-router');
  assert.equal(entry.version, '1.0.0');

  // Duplicate publish error
  assert.throws(() => pm.publish(manifest, archive), /already exists/);

  // Deprecate version
  const dep = pm.deprecate('otter-router', '1.0.0', 'Use @otter/router v2 instead');
  assert.equal(dep.deprecated, true);
  assert.equal(pm.isDeprecated('otter-router', '1.0.0'), 'Use @otter/router v2 instead');
});

test('Section 21 Live Studio Server API Package Endpoints', async () => {
  // Test /api/packages/resolve
  const resRes = await fetch(`${baseUrl}/api/packages/resolve`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ specifier: './engine.ot', fromFile: 'src/main.ot' })
  });
  assert.equal(resRes.status, 200);
  const resData = await resRes.json();
  assert.equal(resData.ok, true);
  assert.equal(resData.resolved.resolvedPath, 'src/engine.ot');

  // Test /api/packages/graph
  const graphRes = await fetch(`${baseUrl}/api/packages/graph`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      dependencies: [
        { from: 'main.ot', to: 'a.ot' },
        { from: 'a.ot', to: 'b.ot' }
      ]
    })
  });
  assert.equal(graphRes.status, 200);
  const graphData = await graphRes.json();
  assert.equal(graphData.ok, true);
  assert.deepEqual(graphData.order, ['main.ot', 'a.ot', 'b.ot']);

  // Test /api/packages/lock
  const lockRes = await fetch(`${baseUrl}/api/packages/lock`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      manifest: { name: 'demo-app', version: '1.0.0' },
      resolved: { 'core': { version: '1.0.0' } }
    })
  });
  assert.equal(lockRes.status, 200);
  const lockData = await lockRes.json();
  assert.equal(lockData.ok, true);
  assert.ok(lockData.lockfile.packages['core']);

  // Test /api/packages/audit
  const auditRes = await fetch(`${baseUrl}/api/packages/audit`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      licenses: { 'core': 'MIT', 'util': 'Apache-2.0' },
      packages: { 'core': '1.0.0' }
    })
  });
  assert.equal(auditRes.status, 200);
  const auditData = await auditRes.json();
  assert.equal(auditData.ok, true);
  assert.equal(auditData.licenses.compliant, true);

  // Test /api/packages/publish
  const testPkgName = `live-pkg-${Date.now()}`;
  const pubRes = await fetch(`${baseUrl}/api/packages/publish`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      manifest: { name: testPkgName, version: '1.0.0', license: 'MIT', entryPoint: 'main.ot' },
      archiveBase64: Buffer.from('hello').toString('base64')
    })
  });
  assert.equal(pubRes.status, 200);
  const pubData = await pubRes.json();
  assert.equal(pubData.ok, true);
  assert.equal(pubData.published.name, testPkgName);

  // Test /api/packages/deprecate
  const depRes = await fetch(`${baseUrl}/api/packages/deprecate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ package: testPkgName, version: '1.0.0', message: 'Legacy release' })
  });
  assert.equal(depRes.status, 200);
  const depData = await depRes.json();
  assert.equal(depData.ok, true);
  assert.equal(depData.deprecated, true);
});
