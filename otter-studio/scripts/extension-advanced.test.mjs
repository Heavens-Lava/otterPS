// extension-advanced.test.mjs - End-to-end certification for Section 25: Extensions & Plugins
import assert from 'node:assert/strict';
import { OtterExtensionManager, STUDIO_API_VERSION } from '../js/extensions/extension-manager.js';

console.log('=== Running Section 25: Extensions & Plugins Certification Suite ===\n');

// --- 1. API Versioning & Compatibility ---
console.log('--- 1. API Versioning & Compatibility ---');
{
  const manager = new OtterExtensionManager({ apiVersion: '1.2.0' });

  // Compatible extension (^1.0.0)
  const compatRes1 = manager.validateApiCompatibility({
    engines: { otterStudio: '^1.0.0' }
  });
  assert.equal(compatRes1.compatible, true);

  // Incompatible extension (^2.0.0)
  const compatRes2 = manager.validateApiCompatibility({
    engines: { otterStudio: '^2.0.0' }
  });
  assert.equal(compatRes2.compatible, false);
  assert.match(compatRes2.error, /requires Otter Studio API \^2\.0\.0/);

  // Registration of incompatible extension should throw
  assert.throws(
    () => manager.registerExtension({ id: 'future.ext', engines: { otterStudio: '^3.0.0' } }),
    /requires Otter Studio API \^3\.0\.0/
  );
  console.log('  ✓ API versioning verified with range and SemVer compatibility checks');
}

// --- 2. Sandbox & Permissions System ---
console.log('\n--- 2. Sandbox & Permissions System ---');
{
  const manager = new OtterExtensionManager();
  let executedPrivileged = false;

  manager.registerExtension(
    {
      id: 'otter.net-tool',
      name: 'Network Tool',
      permissions: ['network', 'filesystem:read']
    },
    context => {
      assert.equal(context.hasPermission('network'), true);
      assert.equal(context.hasPermission('filesystem:write'), false);

      context.registerCommand('net.fetch', () => {
        context.requirePermission('network');
        executedPrivileged = true;
        return 'network data';
      });

      context.registerCommand('net.write', () => {
        context.requirePermission('filesystem:write');
      });
    }
  );

  manager.activateExtension('otter.net-tool');
  const res = manager.executeCommand('net.fetch');
  assert.equal(res, 'network data');
  assert.equal(executedPrivileged, true);

  // Calling unpermitted command should throw permission error
  assert.throws(
    () => manager.executeCommand('net.write'),
    /lacks required permission: filesystem:write/
  );

  // Dynamic permission grant
  manager.grantPermission('otter.net-tool', 'filesystem:write');
  assert.equal(manager.hasPermission('otter.net-tool', 'filesystem:write'), true);
  console.log('  ✓ Sandbox permissions enforced; unauthorized actions rejected');
}

// --- 3. Cryptographic Signature Verification ---
console.log('\n--- 3. Cryptographic Signing & Verification ---');
{
  const manager = new OtterExtensionManager();

  // Unsigned extension
  const unsignedCheck = manager.verifySignature({
    id: 'untrusted.plugin',
    version: '1.0.0',
    author: 'Anonymous'
  });
  assert.equal(unsignedCheck.verified, false);
  assert.equal(unsignedCheck.trusted, false);

  // Signed extension from trusted publisher
  const signedManifest = {
    id: 'otter.core-tools',
    version: '1.0.0',
    publisher: 'otter-team',
    signature: 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90'
  };
  const signedCheck = manager.verifySignature(signedManifest);
  assert.equal(signedCheck.verified, true);
  assert.equal(signedCheck.trusted, true);
  assert.ok(signedCheck.integrityHash.length === 64);
  console.log('  ✓ Cryptographic signatures verified against trusted publisher list');
}

// --- 4. Malicious Extension Protection & Quarantine ---
console.log('\n--- 4. Malicious Extension Protection & Quarantine ---');
{
  const manager = new OtterExtensionManager();

  // Scan malicious code patterns
  const scan1 = manager.scanExtension(
    { id: 'bad.ext', permissions: ['network'] },
    'function evil() { eval("alert(1)"); Object.prototype.polluted = 123; }'
  );
  assert.equal(scan1.safe, false);
  assert.ok(scan1.threats.some(t => t.includes('eval()')));
  assert.ok(scan1.threats.some(t => t.includes('Prototype pollution')));

  // Quarantine extension
  manager.registerExtension({ id: 'suspicious.plugin' });
  manager.activateExtension('suspicious.plugin');
  assert.equal(manager.getExtension('suspicious.plugin').state, 'active');

  const qRes = manager.quarantineExtension('suspicious.plugin', 'Suspected security vulnerability');
  assert.equal(qRes.quarantined, true);
  assert.equal(manager.isQuarantined('suspicious.plugin'), true);
  assert.equal(manager.getExtension('suspicious.plugin').state, 'quarantined');

  // Attempting to activate quarantined extension must throw
  assert.throws(
    () => manager.activateExtension('suspicious.plugin'),
    /quarantined/
  );

  // Unquarantine
  manager.unquarantine('suspicious.plugin');
  assert.equal(manager.isQuarantined('suspicious.plugin'), false);
  console.log('  ✓ Malicious code scanned and quarantined extension isolated');
}

// --- 5. Performance Monitoring ---
console.log('\n--- 5. Performance Monitoring & Diagnostics ---');
{
  const manager = new OtterExtensionManager();

  manager.registerExtension(
    { id: 'perf.sample' },
    context => {
      // Simulate startup work
      let sum = 0;
      for (let i = 0; i < 10000; i++) sum += i;

      context.registerCommand('perf.run', () => {
        let x = 0;
        for (let i = 0; i < 5000; i++) x += i;
        return x;
      });
    }
  );

  manager.activateExtension('perf.sample');
  manager.executeCommand('perf.run');
  manager.executeCommand('perf.run');

  const metrics = manager.getPerformanceMetrics('perf.sample');
  assert.ok(metrics, 'Performance metrics must be recorded');
  assert.ok(metrics.activationTimeMs >= 0);
  assert.equal(metrics.commandRuns, 2);
  assert.ok(metrics.totalExecutionTimeMs >= 0);
  console.log(`  ✓ Performance metrics captured: ${metrics.commandRuns} runs, ${metrics.totalExecutionTimeMs.toFixed(3)}ms execution`);
}

// --- 6. Marketplace Catalog & Updates ---
console.log('\n--- 6. Marketplace Catalog & Automated Updates ---');
{
  const manager = new OtterExtensionManager();

  // Publish v1.0.0 and v1.1.0 to marketplace
  manager.publishToMarketplace({
    id: 'otter.git-graph',
    name: 'Git Graph Visualizer',
    version: '1.0.0',
    description: 'Visual Git commits and branches'
  });

  const searchResults = manager.searchMarketplace('Git Graph');
  assert.equal(searchResults.length, 1);
  assert.equal(searchResults[0].id, 'otter.git-graph');

  // Install from marketplace
  manager.installFromMarketplace('otter.git-graph', context => {
    context.registerCommand('gitGraph.view', () => 'graph view rendered');
  });
  manager.activateExtension('otter.git-graph');
  assert.equal(manager.executeCommand('gitGraph.view'), 'graph view rendered');
  assert.equal(manager.getExtension('otter.git-graph').version, '1.0.0');

  // New version published to marketplace
  manager.publishToMarketplace({
    id: 'otter.git-graph',
    name: 'Git Graph Visualizer',
    version: '1.1.0',
    description: 'Visual Git commits and branches with diff'
  });

  // Check for updates
  const updates = manager.checkForUpdates();
  assert.equal(updates.length, 1);
  assert.equal(updates[0].id, 'otter.git-graph');
  assert.equal(updates[0].currentVersion, '1.0.0');
  assert.equal(updates[0].latestVersion, '1.1.0');

  // Apply update
  const updateRes = manager.updateExtension('otter.git-graph');
  assert.equal(updateRes.ok, true);
  assert.equal(manager.getExtension('otter.git-graph').version, '1.1.0');
  assert.equal(manager.executeCommand('gitGraph.view'), 'graph view rendered');
  console.log('  ✓ Marketplace installation and automated version updates certified');
}

console.log('\n=== ALL SECTION 25 EXTENSIONS & PLUGINS TESTS PASSED SUCCESSFULLY ===');
