// blueprint-workspace.test.mjs - Unit tests for Otter Studio BlueprintWorkspace
import test from 'node:test';
import assert from 'node:assert/strict';
let BlueprintWorkspace;
try {
  ({ BlueprintWorkspace } = await import('../js/components/blueprint-workspace.js'));
} catch {
  ({ BlueprintWorkspace } = await import('./blueprint-workspace.js'));
}

const mockCombatBlueprint = {
  schemaVersion: 1,
  id: "otter-official/game-combat",
  version: "1.0.0",
  title: "RPG Combat Starter",
  summary: "Connect damage, health and reward logic",
  targets: ["console", "game"],
  requiresOtter: ">=1.0.1",
  packs: [
    { id: "otter-official/math-utils", version: "1.0.0" },
    { id: "otter-official/game-entity", version: "1.0.0" }
  ],
  configuration: [
    { id: "startingHealth", label: "Enemy Starting Health", type: "number", default: 100, minimum: 1 },
    { id: "baseAttackDamage", label: "Player Base Attack Damage", type: "number", default: 35, minimum: 1 }
  ],
  nodes: [
    { id: "enemyInit", title: "Spawn Enemy", kind: "pack-call", capability: "game-entity.createActor", inputs: [], outputs: [{ name: "enemy", type: "object" }] },
    { id: "attack", title: "Player Attack", kind: "input", inputs: [], outputs: [{ name: "damage", type: "number" }] },
    { id: "applyDamage", title: "Apply Damage", kind: "pack-call", capability: "game-entity.applyDamage", inputs: [{ name: "actor", type: "object" }, { name: "amount", type: "number" }], outputs: [{ name: "remainingHealth", type: "number" }] },
    { id: "defeatCheck", title: "Defeat Condition", kind: "condition", inputs: [{ name: "health", type: "number" }], outputs: [{ name: "isDefeated", type: "boolean" }] },
    { id: "reward", title: "Reward", kind: "output", inputs: [{ name: "isDefeated", type: "boolean" }], outputs: [] }
  ],
  edges: [
    { from: "enemyInit.enemy", to: "applyDamage.actor", label: "target" },
    { from: "attack.damage", to: "applyDamage.amount", label: "damage" },
    { from: "applyDamage.remainingHealth", to: "defeatCheck.health", label: "remaining" },
    { from: "defeatCheck.isDefeated", to: "reward.isDefeated", label: "status" }
  ],
  generatedFiles: [
    { path: "src/combat.ot", template: "templates/combat.ot.tmpl" }
  ],
  explanations: {
    beginner: "A complete beginner guide to fighting a goblin.",
    intermediate: "Data flows from enemyInit and attack into game-entity.applyDamage.",
    advanced: "Verified pure state machine contract with Otter 1.0.1 runtime."
  },
  tests: ["tests/test.ot"]
};

test('BlueprintWorkspace: Initialization and state loading', () => {
  const ws = new BlueprintWorkspace({ blueprint: mockCombatBlueprint });
  assert.equal(ws.blueprint.id, 'otter-official/game-combat');
  assert.equal(ws.configValues['startingHealth'], 100);
  assert.equal(ws.configValues['baseAttackDamage'], 35);
  assert.equal(ws.selectedNodeId, 'enemyInit');
  assert.equal(ws.isCustomized, false);
});

test('BlueprintWorkspace: Deterministic Otter 1.0.1 source generation & source mapping', () => {
  const ws = new BlueprintWorkspace({ blueprint: mockCombatBlueprint });
  const src = ws.sourceCode;

  // Must use standard Otter 1.0.1 grammar: of for property access, no dot syntax
  assert.match(src, /use "\.otter\/packages\/otter-official\/game-entity\/1\.0\.0\/src\/main\.ot"/);
  assert.match(src, /name of enemy/);
  assert.match(src, /remHp is applyDamage enemy attackDmg/);
  assert.doesNotMatch(src, /enemy\.health/);
  assert.doesNotMatch(src, /enemy\.name/);

  // Check source ranges
  assert.ok(ws.sourceNodeRanges.has('enemyInit'));
  assert.ok(ws.sourceNodeRanges.has('attack'));
  assert.ok(ws.sourceNodeRanges.has('applyDamage'));
  assert.ok(ws.sourceNodeRanges.has('defeatCheck'));
  assert.ok(ws.sourceNodeRanges.has('reward'));

  const range = ws.sourceNodeRanges.get('applyDamage');
  assert.ok(range.startLine > 0);
  assert.ok(range.endLine >= range.startLine);
});

test('BlueprintWorkspace: 3-level explanation engine', () => {
  const ws = new BlueprintWorkspace({ blueprint: mockCombatBlueprint });

  ws.selectedNodeId = null; // blueprint-level explanation
  ws.setExplanationLevel('beginner');
  assert.equal(ws.getExplanation(), 'A complete beginner guide to fighting a goblin.');

  ws.setExplanationLevel('intermediate');
  assert.equal(ws.getExplanation(), 'Data flows from enemyInit and attack into game-entity.applyDamage.');

  ws.setExplanationLevel('advanced');
  assert.equal(ws.getExplanation(), 'Verified pure state machine contract with Otter 1.0.1 runtime.');

  // Node-level explanation
  ws.selectNode('applyDamage');
  ws.setExplanationLevel('beginner');
  assert.match(ws.getExplanation(), /Step 'Apply Damage'/);
});

test('BlueprintWorkspace: Configuration parameter update and customization guard', () => {
  const ws = new BlueprintWorkspace({ blueprint: mockCombatBlueprint });

  // Update starting health
  ws.updateConfig('startingHealth', 250);
  assert.equal(ws.configValues['startingHealth'], 250);
  assert.match(ws.sourceCode, /enemyHp is 250/);

  // Manual code modification marks workspace as customized
  ws.sourceCode = ws.sourceCode + '\n# Custom manual code edit';
  ws.isCustomized = true;

  // Further config changes do not overwrite customized source
  ws.updateConfig('startingHealth', 500);
  assert.doesNotMatch(ws.sourceCode, /enemyHp is 500/);
  assert.match(ws.sourceCode, /Custom manual code edit/);
});

test('BlueprintWorkspace: Dry-run ApplyPlan generation and Mermaid diagram export', () => {
  let appliedPlan = null;
  const ws = new BlueprintWorkspace({
    blueprint: mockCombatBlueprint,
    onApplyBlueprint: (plan) => { appliedPlan = plan; }
  });

  const plan = ws.generatePlan('/home/project');
  assert.equal(plan.blueprintId, 'otter-official/game-combat');
  assert.equal(plan.dependencies.length, 2);
  assert.equal(plan.plannedFiles.length, 1);
  assert.equal(plan.plannedFiles[0].path, 'src/combat.ot');
  assert.equal(plan.configuration['startingHealth'], 100);

  // Mermaid export
  const mermaid = ws.exportMermaid();
  assert.match(mermaid, /^graph LR/);
  assert.match(mermaid, /enemyInit\["Spawn Enemy"\]/);
  assert.match(mermaid, /enemyInit -->\|target\| applyDamage/);
});

console.log('✓ All BlueprintWorkspace unit tests passed cleanly!');
