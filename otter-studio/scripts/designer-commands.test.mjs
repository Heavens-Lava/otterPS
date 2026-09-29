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

// Free layout needs element geometry: stand-in elements with fixed boxes,
// and a getComputedStyle that reports the --otter-layout mark from the CSS
// model (the canvas's browser would apply it).
function setupFree(zoom = 1) {
  const model = new OtterUiModel();
  const css = new CssAstManager('');
  model.attachStylesheet(css);
  const styles = new StyleController(model, css);
  const root = model.getRoot();
  const a = model.addChild(root.id, 'button', { text: 'A' });
  const b = model.addChild(root.id, 'button', { text: 'B' });
  const boxes = {
    [root.id]: { left: 100, top: 50, width: 500 * zoom, height: 400 * zoom },
    [a.id]: { left: 100 + 16 * zoom, top: 50 + 16 * zoom, width: 200 * zoom, height: 30 * zoom },
    [b.id]: { left: 100 + 16 * zoom, top: 50 + 60 * zoom, width: 468 * zoom, height: 36 * zoom }
  };
  const fake = (id) => ({ id, getBoundingClientRect: () => ({ ...boxes[id], right: boxes[id].left + boxes[id].width, bottom: boxes[id].top + boxes[id].height }) });
  globalThis.getComputedStyle = (el) => ({
    borderLeftWidth: '0px', borderTopWidth: '0px', marginLeft: '0px', marginTop: '0px',
    getPropertyValue: (p) => (p === '--otter-layout' && css.generateCss().includes('--otter-layout: free') && el.id === root.id ? 'free' : '')
  });
  const actions = createDesignerActions({
    uiModel: model, styles, cssAstManager: css,
    canvas: { elementFor: (id) => (boxes[id] ? fake(id) : null), getZoom: () => zoom, zoomBy() {}, setZoom() {}, zoomToFit() {}, zoomToSelection() {} }
  });
  return { model, css, actions, root, a, b };
}

console.log('Designer commands:');

test('Free layout: turning it on keeps every child where it is, at its size', () => {
  const { css, actions, root } = setupFree();
  assert.equal(actions.isFreeLayout(root), false);
  assert.equal(actions.setFreeLayout(root, true), true);
  const out = css.generateCss();
  assert.match(out, /--otter-layout: free;\s*position: relative;/);
  assert.match(out, /#button1 \{\s*position: absolute;\s*left: 16px;\s*top: 16px;\s*width: 200px;/);
  assert.match(out, /#button2 \{\s*position: absolute;\s*left: 16px;\s*top: 60px;\s*width: 468px;/);
  assert.equal(actions.isFreeLayout(root), true);
});

test('Free layout: a drop lands where it was let go (zoom and grab point taken out)', () => {
  const { css, actions, root, b } = setupFree(2);
  actions.setFreeLayout(root, true);
  // Pointer at (400, 300) on screen, holding the element 10 x 5 px from its corner.
  actions.placeAt(b, root, 400, 300, { x: 10, y: 5 });
  assert.match(css.generateCss(), /#button2 \{[^}]*left: 140px;[^}]*top: 120px;/, '(400-100)/2-10, (300-50)/2-5');
  actions.placeAt(b, root, 50, 20);
  assert.match(css.generateCss(), /#button2 \{[^}]*left: 0px;[^}]*top: 0px;/, 'never outside the top-left corner');
});

test('Free layout: the window hides its own title header (the title bar is the title)', () => {
  const { css, actions, root } = setupFree();
  actions.setFreeLayout(root, true);
  assert.match(css.generateCss(), /#app > \.otter-window-header \{\s*display: none;/);
  assert.match(css.generateCss(), /#app \{[^}]*min-height: 400px;/, 'the window keeps its height');
  actions.setFreeLayout(root, false);
  assert.doesNotMatch(css.generateCss(), /otter-window-header|min-height/);
});

test('Free layout: a new control arrives at a sensible size, not stretched', () => {
  const { model, css, actions, root } = setupFree();
  actions.setFreeLayout(root, true);
  const box = model.addChild(root.id, 'text box', {});
  const button = model.addChild(root.id, 'button', { text: 'OK' });
  actions.placeAt(box, root, 300, 200, { x: 0, y: 0 }, { isNew: true });
  actions.placeAt(button, root, 300, 260, { x: 0, y: 0 }, { isNew: true });
  assert.equal(box.properties.width, 220, 'a text box is 220 wide (in the Otter source)');
  assert.match(css.generateCss(), new RegExp(`#${button.name} \\{[^}]*min-width: 100px;`), 'a button is at least 100 wide');
  assert.equal(button.properties.width, undefined, 'and otherwise sizes to its text');
});

test('Free layout: turning it off returns the children to flow; one undo step each way', () => {
  const { model, css, actions, root } = setupFree();
  actions.setFreeLayout(root, true);
  actions.setFreeLayout(root, false);
  const out = css.generateCss();
  assert.doesNotMatch(out, /position|left:|top:|--otter-layout/);
  assert.match(out, /width: 200px/, 'widths stay, so the form looks the same');
  model.undo();
  assert.match(css.generateCss(), /--otter-layout: free/, 'one undo brings Free back');
  assert.match(css.generateCss(), /#button1 \{[^}]*left: 16px;/);
});

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
