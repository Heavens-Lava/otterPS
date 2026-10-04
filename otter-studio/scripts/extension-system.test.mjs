// otter-studio/scripts/extension-system.test.mjs
// Certification test for Otter Studio Extensible Plugin & Architecture System
// Validates manifest registration, declarative contributions (commands, themes, keybindings),
// lifecycle activation/deactivation, dynamic context APIs, on-demand activation,
// provider registries, cleanup disposables, and crash isolation.

import assert from 'node:assert/strict';
import { OtterExtensionManager } from '../js/extensions/extension-manager.js';

console.log('=== Running Otter Studio Extension & Plugin System Certification Suite ===\n');

// --- 1. Manifest Validation & Registration ---
console.log('--- 1. Manifest Validation & Registration ---');
{
  const manager = new OtterExtensionManager();

  assert.throws(
    () => manager.registerExtension(null),
    /Extension manifest must be an object with a unique "id"/,
    'registerExtension must require a valid manifest'
  );
  assert.throws(
    () => manager.registerExtension({ name: 'No ID' }),
    /Extension manifest must be an object with a unique "id"/,
    'registerExtension must require an id'
  );

  const reg = manager.registerExtension({
    id: 'otter.sample-pack',
    name: 'Sample Pack Extension',
    version: '1.2.0',
    author: 'Otter Team',
    description: 'A sample extension for Otter Studio'
  });

  assert.equal(reg.id, 'otter.sample-pack');
  const ext = manager.getExtension('otter.sample-pack');
  assert.ok(ext, 'Extension must be retrieved by id');
  assert.equal(ext.name, 'Sample Pack Extension');
  assert.equal(ext.version, '1.2.0');
  assert.equal(ext.state, 'inactive', 'Initial state must be inactive');
  assert.equal(ext.error, null);
  console.log('✓ Manifest registration verified');
}

// --- 2. Declarative Contributions (Commands, Themes, Keybindings) ---
console.log('--- 2. Declarative Contributions ---');
{
  const manager = new OtterExtensionManager();

  manager.registerExtension({
    id: 'otter.theme-and-tools',
    name: 'Theme and Tools',
    contributes: {
      commands: [
        { id: 'tools.formatSource', title: 'Format Active Source', category: 'Otter Tools' },
        { id: 'tools.inspectAst', title: 'Inspect AST', category: 'Otter Tools' }
      ],
      themes: [
        {
          id: 'nordic-frost',
          name: 'Nordic Frost',
          colors: { background: '#2e3440', foreground: '#d8dee9', accent: '#88c0d0' }
        }
      ],
      keybindings: [
        { key: 'Ctrl+Shift+F', command: 'tools.formatSource' }
      ]
    }
  });

  const cmd = manager.commands.get('tools.formatSource');
  assert.ok(cmd, 'Contributed command must be registered');
  assert.equal(cmd.title, 'Format Active Source');
  assert.equal(cmd.category, 'Otter Tools');
  assert.equal(cmd.extensionId, 'otter.theme-and-tools');

  const theme = manager.getTheme('nordic-frost');
  assert.ok(theme, 'Contributed theme must be retrievable');
  assert.equal(theme.colors.accent, '#88c0d0');

  const kb = manager.keybindings.get('Ctrl+Shift+F');
  assert.ok(kb, 'Contributed keybinding must be registered');
  assert.equal(kb.command, 'tools.formatSource');
  console.log('✓ Declarative contributions verified');
}

// --- 3. Lifecycle Activation, Context Injection & Command Execution ---
console.log('--- 3. Lifecycle Activation, Context Injection & Command Execution ---');
{
  const manager = new OtterExtensionManager();
  let activated = false;
  let customActionRan = false;

  manager.registerExtension(
    {
      id: 'otter.linter',
      name: 'Otter Linter Extension',
      contributes: {
        commands: [{ id: 'linter.run', title: 'Run Otter Linter' }]
      }
    },
    context => {
      activated = true;
      assert.equal(context.extensionId, 'otter.linter');
      assert.ok(Array.isArray(context.subscriptions));

      // Attach handler to the manifest command
      context.registerCommand('linter.run', (source) => {
        return { diagnostics: [`Checked ${source.length} characters cleanly`] };
      });

      // Register dynamic command
      context.registerCommand('linter.quickFix', () => {
        customActionRan = true;
        return 'fixed';
      });

      // Register dynamic panel
      context.registerPanel('linter.results', {
        title: 'Linter Results',
        icon: 'checklist'
      });

      // Register provider
      context.registerProvider('diagnostics', {
        name: 'Otter Linter Provider',
        lint: (src) => []
      });
    },
    () => {
      activated = false;
    }
  );

  assert.equal(activated, false);
  const success = manager.activateExtension('otter.linter');
  assert.equal(success, true);
  assert.equal(activated, true);
  assert.equal(manager.getExtension('otter.linter').state, 'active');

  // Execute manifest-registered command
  const res = manager.executeCommand('linter.run', 'say "hello"');
  assert.deepEqual(res, { diagnostics: ['Checked 11 characters cleanly'] });

  // Execute dynamic command
  const fixRes = manager.executeCommand('linter.quickFix');
  assert.equal(fixRes, 'fixed');
  assert.equal(customActionRan, true);

  // Check panel registry
  const panel = manager.getPanel('linter.results');
  assert.ok(panel);
  assert.equal(panel.title, 'Linter Results');

  // Check provider registry
  const providers = manager.getProviders('diagnostics');
  assert.equal(providers.length, 1);
  assert.equal(providers[0].name, 'Otter Linter Provider');
  console.log('✓ Lifecycle activation, context injection & command execution verified');
}

// --- 4. On-Demand Activation ---
console.log('--- 4. On-Demand Activation ---');
{
  const manager = new OtterExtensionManager();
  let activatedOnDemand = false;

  manager.registerExtension(
    {
      id: 'otter.lazy-calc',
      name: 'Lazy Calculator',
      contributes: {
        commands: [{ id: 'calc.add', title: 'Add Numbers' }]
      }
    },
    context => {
      activatedOnDemand = true;
      context.registerCommand('calc.add', (a, b) => a + b);
    }
  );

  assert.equal(manager.getExtension('otter.lazy-calc').state, 'inactive');
  assert.equal(activatedOnDemand, false);

  // Invoking command should trigger auto-activation of the inactive extension
  const sum = manager.executeCommand('calc.add', 18, 24);
  assert.equal(sum, 42);
  assert.equal(activatedOnDemand, true);
  assert.equal(manager.getExtension('otter.lazy-calc').state, 'active');
  console.log('✓ On-demand activation verified');
}

// --- 5. Keybinding Dispatch ---
console.log('--- 5. Keybinding Dispatch ---');
{
  const manager = new OtterExtensionManager();

  manager.registerExtension(
    {
      id: 'otter.shortcuts',
      contributes: {
        commands: [{ id: 'shortcuts.saveAll', title: 'Save All Files' }],
        keybindings: [{ key: 'Ctrl+K S', command: 'shortcuts.saveAll' }]
      }
    },
    context => {
      context.registerCommand('shortcuts.saveAll', () => 'all-saved');
    }
  );

  manager.activateExtension('otter.shortcuts');
  const handled = manager.executeKeybinding('Ctrl+K S');
  assert.equal(handled, 'all-saved');

  const unhandled = manager.executeKeybinding('Ctrl+Alt+Z');
  assert.equal(unhandled, false);
  console.log('✓ Keybinding dispatch verified');
}

// --- 6. Deactivation & Resource Disposal ---
console.log('--- 6. Deactivation & Resource Disposal ---');
{
  const manager = new OtterExtensionManager();
  let deactivated = false;

  manager.registerExtension(
    {
      id: 'otter.cleanup-test',
      contributes: {
        commands: [{ id: 'cleanup.action', title: 'Cleanup Action' }]
      }
    },
    context => {
      context.registerCommand('cleanup.action', () => 'active');
      context.registerPanel('cleanup.panel', { title: 'Cleanup Panel' });
      context.registerProvider('cleanup-provider', { ok: true });
    },
    () => {
      deactivated = true;
    }
  );

  manager.activateExtension('otter.cleanup-test');
  assert.ok(manager.getPanel('cleanup.panel'));
  assert.equal(manager.getProviders('cleanup-provider').length, 1);

  manager.deactivateExtension('otter.cleanup-test');
  assert.equal(deactivated, true);
  assert.equal(manager.getExtension('otter.cleanup-test').state, 'inactive');

  // Dynamic subscriptions must be cleared
  assert.equal(manager.getPanel('cleanup.panel'), null, 'Panel must be cleaned up on deactivation');
  assert.equal(manager.getProviders('cleanup-provider').length, 0, 'Provider must be cleaned up on deactivation');
  console.log('✓ Deactivation and subscription disposal verified');
}

// --- 7. Full Unregistration ---
console.log('--- 7. Full Unregistration ---');
{
  const manager = new OtterExtensionManager();

  manager.registerExtension({
    id: 'otter.to-remove',
    contributes: {
      commands: [{ id: 'remove.cmd', title: 'Remove Cmd' }],
      themes: [{ id: 'remove-theme', colors: {} }],
      keybindings: [{ key: 'Ctrl+R', command: 'remove.cmd' }]
    }
  });

  assert.ok(manager.getExtension('otter.to-remove'));
  assert.ok(manager.commands.has('remove.cmd'));
  assert.ok(manager.getTheme('remove-theme'));
  assert.ok(manager.keybindings.has('Ctrl+R'));

  manager.unregisterExtension('otter.to-remove');
  assert.equal(manager.getExtension('otter.to-remove'), null, 'Extension record must be deleted');
  assert.equal(manager.commands.has('remove.cmd'), false, 'Manifest commands must be purged');
  assert.equal(manager.getTheme('remove-theme'), null, 'Manifest themes must be purged');
  assert.equal(manager.keybindings.has('Ctrl+R'), false, 'Manifest keybindings must be purged');
  console.log('✓ Full unregistration and contribution purge verified');
}

// --- 8. Crash Isolation & Fault Resilience ---
console.log('--- 8. Crash Isolation & Fault Resilience ---');
{
  const manager = new OtterExtensionManager();

  // Extension that throws during activateFn
  manager.registerExtension(
    {
      id: 'otter.faulty-activate',
      name: 'Faulty Activate Extension'
    },
    () => {
      throw new Error('Explosion during startup');
    }
  );

  // Healthy extension
  manager.registerExtension(
    {
      id: 'otter.healthy',
      name: 'Healthy Extension'
    },
    context => {
      context.registerCommand('healthy.ping', () => 'pong');
    }
  );

  // Activating faulty extension must return false, capture error, and not crash process
  const faultySuccess = manager.activateExtension('otter.faulty-activate');
  assert.equal(faultySuccess, false);
  const faultyExt = manager.getExtension('otter.faulty-activate');
  assert.equal(faultyExt.state, 'error');
  assert.equal(faultyExt.error, 'Explosion during startup');

  // Healthy extension operates completely normally
  const healthySuccess = manager.activateExtension('otter.healthy');
  assert.equal(healthySuccess, true);
  assert.equal(manager.executeCommand('healthy.ping'), 'pong');

  // Faulty deactivateFn isolation
  manager.registerExtension(
    { id: 'otter.faulty-deactivate' },
    () => {},
    () => {
      throw new Error('Deactivate failed');
    }
  );
  manager.activateExtension('otter.faulty-deactivate');
  const deactRes = manager.deactivateExtension('otter.faulty-deactivate');
  assert.equal(deactRes, true, 'deactivateExtension must isolate errors and succeed gracefully');
  assert.equal(manager.getExtension('otter.faulty-deactivate').state, 'inactive');

  console.log('✓ Crash isolation and fault resilience verified');
}

console.log('\n=== All Otter Studio Extension & Plugin Tests Passed Successfully! ===');
