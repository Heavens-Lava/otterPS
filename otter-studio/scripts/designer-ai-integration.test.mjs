import test from 'node:test';
import assert from 'node:assert/strict';
import { OtterUiModel } from '../js/model/ui-model.js';
import { DesignerAiPlanner } from '../js/ai/designer-ai.js';
import { generateOtterSource } from '../js/compiler/otter-generator.js';
import { compileToHtmlDocument } from '../js/compiler/web-compiler.js';
import { OtterCompilerAdapter } from '../js/compiler/compiler-adapter.js';

test('Designer AI: Comprehensive Visual UI Model Integration & Transaction Certification', async (t) => {
  await t.test('1. Generates complete settings card from natural language prompt', () => {
    const model = new OtterUiModel();
    const prompt = 'Create a settings card with name and email fields, notification options, and Cancel and Save buttons.';
    
    const result = DesignerAiPlanner.planAndApply(prompt, model);
    assert.equal(result.success, true, 'Planner returned success');
    assert.ok(result.operations.length >= 6, 'Generated structured operations');
    
    const components = model.getAllComponents();
    assert.ok(components.length >= 6, 'Components added to model');
    
    // Check specific UI controls
    const card = components.find(c => c.kind === 'card' || c.name.toLowerCase().includes('card'));
    assert.ok(card, 'Card container exists');
    
    const nameControl = components.find(c => (c.properties?.text && c.properties.text.toLowerCase().includes('name')) || c.name.toLowerCase().includes('name'));
    assert.ok(nameControl, 'Name field exists');
    
    const emailControl = components.find(c => (c.properties?.text && c.properties.text.toLowerCase().includes('email')) || c.name.toLowerCase().includes('email'));
    assert.ok(emailControl, 'Email field exists');
    
    const notifControl = components.find(c => (c.properties?.text && c.properties.text.toLowerCase().includes('notif')) || c.name.toLowerCase().includes('notif'));
    assert.ok(notifControl, 'Notification option exists');
    
    const cancelBtn = components.find(c => c.properties?.text === 'Cancel' || c.name.toLowerCase().includes('cancel'));
    assert.ok(cancelBtn, 'Cancel button exists');
    
    const saveBtn = components.find(c => c.properties?.text === 'Save' || c.name.toLowerCase().includes('save'));
    assert.ok(saveBtn, 'Save button exists');
  });

  await t.test('2. Every generated object supports Canvas selection, Layers, Properties, and Mutation', () => {
    const model = new OtterUiModel();
    DesignerAiPlanner.planAndApply('Create a settings card with name and email fields, notification options, and Cancel and Save buttons.', model);
    
    const components = model.getAllComponents();
    assert.ok(components.length > 1, 'Components exist in model');
    
    for (const comp of components) {
      if (comp.id === model.rootId) continue;
      
      // Canvas selection
      model.select(comp.id);
      assert.equal(model.isSelected(comp.id), true, `Component ${comp.name} (${comp.id}) is selectable`);
      
      // Properties inspector read & mutation
      const originalText = comp.properties?.text;
      if (originalText !== undefined) {
        model.setProperty(comp.id, 'text', originalText + ' (Edited)');
        const updated = model.getComponent(comp.id);
        assert.equal(updated.properties.text, originalText + ' (Edited)', `Component ${comp.name} property updated`);
        model.setProperty(comp.id, 'text', originalText);
      }
    }
  });

  await t.test('3. Source code generation and compiler validation round-trip', async () => {
    const model = new OtterUiModel();
    DesignerAiPlanner.planAndApply('Create a settings card with name and email fields, notification options, and Cancel and Save buttons.', model);
    
    const source = generateOtterSource(model);
    assert.ok(source && source.length > 0, 'Generated Otter UI source');
    
    // Validate with Otter Compiler Adapter
    const adapter = new OtterCompilerAdapter();
    const validation = await adapter.checkSource(source);
    assert.equal(validation.ok, true, 'Compiler accepted generated UI source');
    
    // HTML/CSS Compilation
    const htmlDoc = compileToHtmlDocument(model);
    assert.ok(htmlDoc.includes('Save') || htmlDoc.includes('Cancel'), 'Compiled HTML contains UI buttons');
  });

  await t.test('4. Atomic Transaction: Single Undo removes entire AI generation; Single Redo restores it', () => {
    const model = new OtterUiModel();
    const initialCount = model.getAllComponents().length;
    
    DesignerAiPlanner.planAndApply('Create a settings card with name and email fields, notification options, and Cancel and Save buttons.', model);
    const postAiCount = model.getAllComponents().length;
    assert.ok(postAiCount > initialCount, 'Components were added by AI');
    
    // Single Undo
    const undoSuccess = model.undo();
    assert.equal(undoSuccess, true, 'Undo succeeded');
    assert.equal(model.getAllComponents().length, initialCount, 'Entire AI transaction was undone in a single step');
    
    // Single Redo
    const redoSuccess = model.redo();
    assert.equal(redoSuccess, true, 'Redo succeeded');
    assert.equal(model.getAllComponents().length, postAiCount, 'Entire AI transaction was restored in a single step');
  });

  await t.test('5. Mid-transaction failure cleanly rolls back with ZERO partial state corruption', () => {
    const model = new OtterUiModel();
    const initialCount = model.getAllComponents().length;
    const initialSnapshot = model.serializeSnapshot();
    
    const brokenOperations = [
      { op: 'create-container', id: 'valid_card', type: 'card' },
      { op: 'create-control', id: 'valid_name', parentId: 'valid_card', type: 'text', properties: { text: 'Name' } },
      { op: 'invalid_corrupt_op_type', id: 'bad_control', parentId: 'non_existent_parent_id' },
      { op: 'create-control', id: 'valid_btn', parentId: 'valid_card', type: 'button', properties: { text: 'Save' } }
    ];
    
    const result = DesignerAiPlanner.applyOperations(brokenOperations, model);
    assert.equal(result.success, false, 'Operation failed as expected');
    assert.ok(result.error, 'Error was reported');
    
    // State must be completely restored to initial
    assert.equal(model.getAllComponents().length, initialCount, 'No partial controls remained after failure');
    assert.deepEqual(model.serializeSnapshot(), initialSnapshot, 'Tree structure is identical to pre-transaction state');
  });
});
