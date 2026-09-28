// Designer actions and commands (js/designer/actions.js, commands.js): the
// structural edits behind the keyboard, the context menu and the palette.
import assert from 'node:assert/strict';

globalThis.window = globalThis.window || new EventTarget();

const { OtterUiModel } = await import('../js/model/ui-model.js');
const { CssAstManager } = await import('../js/compiler/css-ast.js');
const { StyleController } = await import('../js/designer/style-context.js');
const { createDesignerActions } = await import('../js/designer/actions.js');
const { designerCommands, chordOf, displayChord, installDesignerKeyboard, toRegistryCommands } = await import('../js/designer/commands.js');
const { createCommandRegistry } = await import('../js/shell/commands.js');
const { createViewState } = await import('../js/designer/view-state.js');

let passed = 0;
function test(name, fn) {
  fn();
  passed++;
  console.log(`  ✓ ${name}`);
}

function setup() {
  const model = new OtterUiModel();
  const css = new CssAstManager('');
  model.attachStylesheet(css);
  const styles = new StyleController(model, css);
  const zoomCalls = [];
  const actions = createDesignerActions({
    uiModel: model, styles, cssAstManager: css,
    canvas: {
      elementFor: () => null,
      zoomBy: (d) => zoomCalls.push(d), setZoom: (z) => zoomCalls.push(`=${z}`),
      zoomToFit: () => zoomCalls.push('fit'), zoomToSelection: () => { zoomCalls.push('sel'); return true; }
    }
  });
  const root = model.getRoot();
  const a = model.addChild(root.id, 'button', { text: 'A' });
  const b = model.addChild(root.id, 'button', { text: 'B' });
  const row = model.addChild(root.id, 'row', {});
  const c = model.addChild(row.id, 'text', { text: 'C' });
  return { model, css, styles, actions, root, a, b, row, c, zoomCalls };
}

console.log('Designer commands:');

test('every command has a unique id and no key is bound twice', () => {
  const { actions } = setup();
  const commands = designerCommands(actions);
  assert.equal(new Set(commands.map(c => c.id)).size, commands.length);
  const keys = commands.flatMap(c => c.keys);
  assert.equal(new Set(keys).size, keys.length, keys.join(' '));
});

test('chords: modifiers in a fixed order, digits from the physical key', () => {
  assert.equal(chordOf({ ctrlKey: true, shiftKey: true, key: 'G' }), 'ctrl+shift+g');
  assert.equal(chordOf({ shiftKey: true, key: '!', code: 'Digit1' }), 'shift+1');
  assert.equal(chordOf({ metaKey: true, key: 'z' }, true), 'ctrl+z', 'Cmd is ctrl on a Mac');
  assert.equal(chordOf({ ctrlKey: true, key: 'ArrowUp' }), 'ctrl+arrowup');
  assert.equal(displayChord('ctrl+arrowup'), 'Ctrl+Up');
  assert.equal(displayChord('shift+2'), 'Shift+2');
  assert.equal(displayChord('escape'), 'Esc');
});

test('select parent, first child, siblings (wrapping) and all siblings', () => {
  const { model, actions, root, a, b, row, c } = setup();
  model.select(c.id);
  assert.equal(actions.selectParent(), true);
  assert.equal(model.selectedId, row.id);
  assert.equal(actions.selectFirstChild(), true);
  assert.equal(model.selectedId, c.id);
  assert.equal(actions.selectSibling(1), false, 'an only child has no sibling');
  model.select(a.id);
  actions.selectSibling(-1);
  assert.equal(model.selectedId, row.id, 'wraps to the last sibling');
  actions.selectAllSiblings();
  assert.deepEqual([...model.selectedIds].sort(), [a.id, b.id, row.id].sort());
  model.select(root.id);
  assert.equal(actions.selectParent(), false, 'the window has no parent');
});

test('move among siblings, out of the parent and into the previous container', () => {
  const { model, actions, root, a, b, row, c } = setup();
  model.select(b.id);
  assert.equal(actions.moveAmongSiblings(-1), true);
  assert.deepEqual(model.getRoot().children, [b.id, a.id, row.id]);
  assert.equal(actions.moveAmongSiblings(-1), false, 'already first');
  model.select(c.id);
  assert.equal(actions.moveOutOfParent(), true);
  assert.deepEqual(model.getRoot().children, [b.id, a.id, row.id, c.id], 'right after its old parent');
  assert.equal(model.selectedId, c.id, 'still selected');
  assert.equal(actions.moveIntoPrevious(), true, 'the row before it is a container');
  assert.deepEqual(model.getComponent(row.id).children, [c.id]);
  model.select(a.id);
  assert.equal(actions.moveIntoPrevious(), false, 'a button is not a container');
  model.select(root.id);
  assert.equal(actions.moveAmongSiblings(1), false);
});

test('wrap and unwrap; delete and duplicate are one undo step each', () => {
  const { model, actions, root, a, b } = setup();
  model.selectMany([a.id, b.id]);
  assert.equal(actions.wrap('row'), true);
  const wrapper = model.getComponent(model.getComponent(a.id).parentId);
  assert.equal(wrapper.kind, 'row');
  model.select(wrapper.id);
  assert.equal(actions.unwrap(), true);
  assert.equal(model.getComponent(a.id).parentId, root.id);

  model.selectMany([a.id, b.id]);
  const depth = model.undoStack.length;
  assert.equal(actions.deleteSelection(), true);
  assert.equal(model.undoStack.length, depth + 1);
  assert.equal(model.getComponent(a.id), null);
  model.undo();
  assert.ok(model.getComponent(a.id) && model.getComponent(b.id), 'one undo brings both back');

  model.select(a.id);
  assert.equal(actions.duplicateSelection(), true);
  assert.notEqual(model.selectedId, a.id, 'the copy is selected');
  model.select(root.id);
  assert.equal(actions.deleteSelection(), false, 'the window is never deleted');
});

test('nudge leaves flow elements alone; zoom goes to the canvas', () => {
  const { model, actions, a, zoomCalls } = setup();
  model.select(a.id);
  assert.equal(actions.nudge(1, 0), false);
  actions.zoomIn(); actions.zoomOut(); actions.zoomReset(); actions.zoomToFit(); actions.zoomToSelection();
  assert.deepEqual(zoomCalls, [1, -1, '=1', 'fit', 'sel']);
});

test('keyboard: runs the command, prevents the default only when it did something', () => {
  const { model, actions, b } = setup();
  const target = new EventTarget();
  let active = true;
  installDesignerKeyboard(designerCommands(actions), { isActive: () => active, target });
  const press = (init) => {
    const e = new Event('keydown', { cancelable: true });
    Object.assign(e, { key: '', code: '', ctrlKey: false, shiftKey: false, altKey: false, metaKey: false }, init);
    target.dispatchEvent(e);
    return e.defaultPrevented;
  };
  model.select(b.id);
  assert.equal(press({ ctrlKey: true, key: 'ArrowUp' }), true);
  assert.equal(model.getRoot().children[0], b.id);
  assert.equal(press({ ctrlKey: true, key: 'ArrowUp' }), false, 'nothing to do: the key is not taken');
  assert.equal(press({ key: 'ArrowLeft' }), false, 'arrows on a flow element stay free');
  active = false;
  assert.equal(press({ key: 'Delete' }), false, 'inactive designer ignores keys');
  assert.ok(model.getComponent(b.id));
});

test('registry: designer commands appear with shortcuts, only while the designer is shown', () => {
  const { actions } = setup();
  const registry = createCommandRegistry();
  let visible = false;
  registry.registerAll(toRegistryCommands(designerCommands(actions), () => visible));
  assert.equal(registry.list().length, 0);
  assert.ok(registry.list({ includeUnavailable: true }).length > 20);
  visible = true;
  const wrapRow = registry.get('designer.wrapRow');
  assert.equal(wrapRow.shortcut, 'Ctrl+Shift+G');
  assert.equal(wrapRow.category, 'Designer');
  assert.equal(registry.get('designer.zoomSelection').shortcut, 'Shift+2');
});

test('hide and lock: designer-only state keyed by name, kept per design, follows renames', () => {
  const memory = new Map();
  globalThis.localStorage = { getItem: k => memory.get(k) ?? null, setItem: (k, v) => memory.set(k, String(v)), removeItem: k => memory.delete(k) };
  const view = createViewState();
  const { model, styles, css, a, b } = setup();
  const actions = createDesignerActions({ uiModel: model, styles, cssAstManager: css, viewState: view, canvas: { elementFor: () => null } });
  let events = 0;
  window.addEventListener('otter:view-state', () => events++);
  view.setScope('projects/x/main.ot');
  model.selectMany([a.id, b.id]);
  assert.equal(actions.toggleHidden(), true);
  assert.equal(view.isHidden(a.name) && view.isHidden(b.name), true);
  actions.toggleHidden();
  assert.equal(view.isHidden(a.name), false, 'second toggle shows both');
  model.select(a.id);
  actions.toggleLocked();
  assert.equal(view.isLocked(a.name), true);
  view.rename(a.name, 'hero');
  assert.equal(view.isLocked('hero'), true);
  view.setScope('projects/y/main.ot');
  assert.equal(view.isLocked('hero'), false, 'another design has its own state');
  view.setScope('projects/x/main.ot');
  assert.equal(view.isLocked('hero'), true, 'state comes back with the design');
  assert.equal(view.unlockAll(), true);
  assert.ok(events > 0);
  assert.equal(Object.keys(model.getComponent(a.id).properties).some(k => /hidden|lock/i.test(k)), false, 'nothing written to the model');
});

console.log(`\nDesigner command tests passed: ${passed}.`);
