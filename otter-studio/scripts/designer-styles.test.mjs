// Designer style routing certification: every style edit lands where it will
// actually take effect in the compiled app (see js/designer/style-context.js),
// and undo/redo, rename, duplicate, delete, wrap and unwrap keep the
// stylesheet in step with the component tree.
import assert from 'node:assert/strict';

// The controller announces changes on `window`; Node has no window.
globalThis.window = globalThis.window || new EventTarget();
const events = [];
window.addEventListener('css-updated', (e) => events.push(e.detail));

const { OtterUiModel } = await import('../js/model/ui-model.js');
const { CssAstManager } = await import('../js/compiler/css-ast.js');
const { StyleController } = await import('../js/designer/style-context.js');
const { generateOtterSource } = await import('../js/compiler/otter-generator.js');

function setup(css = '') {
  const model = new OtterUiModel();
  const sheet = new CssAstManager(css);
  model.attachStylesheet(sheet);
  const styles = new StyleController(model, sheet);
  const root = model.getRoot();
  return { model, sheet, styles, root };
}

// 1. A property the Otter source already holds is edited in the source.
{
  const { model, sheet, styles, root } = setup();
  const title = model.addChild(root.id, 'heading', { text: 'Hi', size: 24 });
  styles.write(title, { 'font-size': '32px' });
  assert.equal(title.properties.size, 32, 'source `size` updated');
  assert.equal(sheet.getProperty(`#${title.name}`, 'font-size'), null, 'nothing written to styles.css');
  assert.match(generateOtterSource(model), /size 32/);
}

// 2. A value too rich for the source moves to styles.css.
{
  const { model, sheet, styles, root } = setup();
  const card = model.addChild(root.id, 'card', { padding: 12 });
  styles.write(card, { padding: '8px 24px' });
  assert.equal(card.properties.padding, undefined, 'removed from source');
  assert.equal(sheet.getProperty(`#${card.name}`, 'padding'), '8px 24px');
}

// 3. A new property goes to styles.css.
{
  const { model, sheet, styles, root } = setup();
  const card = model.addChild(root.id, 'card', {});
  styles.write(card, { 'box-shadow': '0 4px 12px rgba(0,0,0,.1)' });
  assert.equal(sheet.getProperty(`#${card.name}`, 'box-shadow'), '0 4px 12px rgba(0,0,0,.1)');
}

// 4. A breakpoint override moves the inline source value into styles.css
// first (inline would beat the @media rule), replacing a stale CSS value.
{
  const { model, sheet, styles, root } = setup();
  const title = model.addChild(root.id, 'heading', { text: 'Hi', size: 24 });
  sheet.setProperty(`#${title.name}`, 'font-size', '26px'); // never visible: source wins
  styles.setContext({ breakpoint: 'mobile' });
  styles.write(title, { 'font-size': '14px' });
  assert.equal(title.properties.size, undefined, 'source size moved out');
  assert.equal(sheet.getProperty(`#${title.name}`, 'font-size'), '24px', 'base keeps the value that was showing');
  assert.equal(sheet.getProperty(`#${title.name}`, 'font-size', '(max-width: 600px)'), '14px');
  const resolved = styles.resolve(title);
  assert.equal(resolved.own['font-size'], '14px');
  styles.setContext({ breakpoint: 'base' });
}

// 5. Layout the compiler always inlines for a kind is written !important.
{
  const { model, sheet, styles, root } = setup();
  const row = model.addChild(root.id, 'row', {});
  styles.setContext({ breakpoint: 'tablet' });
  styles.write(row, { 'flex-direction': 'column' });
  assert.equal(sheet.getProperty(`#${row.name}`, 'flex-direction', '(max-width: 900px)'), 'column !important');
  assert.equal(styles.resolve(row).own['flex-direction'], 'column', 'shown without !important');
  styles.setContext({ breakpoint: 'base' });
  // A text component is not forced.
  const text = model.addChild(root.id, 'text', { text: 'x' });
  styles.write(text, { 'letter-spacing': '2px' });
  assert.equal(sheet.getProperty(`#${text.name}`, 'letter-spacing'), '2px');
}

// 6. Container gap is Otter `spacing`.
{
  const { model, sheet, styles, root } = setup();
  const row = model.addChild(root.id, 'row', {});
  styles.write(row, { gap: '30px' });
  assert.equal(row.properties.spacing, 30);
  assert.equal(sheet.getProperty(`#${row.name}`, 'gap'), null);
  assert.match(generateOtterSource(model), /spacing 30/);
}

// 7. The canvas can report compiler !important rules (e.g. primary buttons).
{
  const { model, sheet, styles, root } = setup();
  const btn = model.addChild(root.id, 'primary button', { text: 'Go' });
  styles.importantProbe = (comp, prop) => comp.kind === 'primary button' && prop === 'background';
  styles.setContext({ state: ':hover' });
  styles.write(btn, { background: '#16a34a' });
  assert.equal(sheet.getProperty(`#${btn.name}:hover`, 'background'), '#16a34a !important');
  styles.setContext({ state: '' });
}

// 8. Rapid edits with one key are one undo step; undo restores CSS and source.
{
  const { model, sheet, styles, root } = setup();
  const card = model.addChild(root.id, 'card', { padding: 10 });
  const depth = model.undoStack.length;
  for (let i = 11; i <= 20; i++) styles.write(card, { padding: `${i}px`, 'letter-spacing': `${i}px` }, { key: 'drag' });
  assert.equal(model.undoStack.length, depth + 1, 'one snapshot for the whole drag');
  assert.equal(card.properties.padding, 20);
  model.undo();
  const restored = model.getComponent(card.id);
  assert.equal(restored.properties.padding, 10, 'source restored');
  assert.equal(sheet.getProperty(`#${card.name}`, 'letter-spacing'), null, 'CSS restored');
  model.redo();
  assert.equal(sheet.getProperty(`#${card.name}`, 'letter-spacing'), '20px', 'CSS redone');
}

// 8b. A bare `round` compiles to a pill; editing the radius replaces it with
// an explicit `radius`, and undo brings `round` back.
{
  const { model, styles, root } = setup();
  const card = model.addChild(root.id, 'card', { round: 8 });
  assert.equal(styles.sourceValue(card, 'border-radius'), '9999px', 'bare round is a pill');
  styles.write(card, { 'border-radius': '12px' });
  assert.equal(card.properties.round, undefined);
  assert.equal(card.properties.radius, 12);
  assert.match(generateOtterSource(model), /radius 12/);
  model.undo();
  assert.equal(model.getComponent(card.id).properties.round, 8);
}

// 9. Inheritance: mobile hover sees base hover before base normal.
{
  const { model, sheet, styles, root } = setup();
  const btn = model.addChild(root.id, 'button', { text: 'Go' });
  const n = btn.name;
  sheet.setProperty(`#${n}`, 'color', 'black');
  sheet.setProperty(`#${n}:hover`, 'color', 'blue');
  sheet.setProperty(`#${n}`, 'opacity', '0.5', '(max-width: 900px)');
  styles.setContext({ breakpoint: 'mobile', state: ':hover' });
  const r = styles.resolve(btn);
  assert.equal(r.inherited.color, 'blue');
  assert.equal(r.inheritedFrom.color, 'Desktop Hover');
  assert.equal(r.inherited.opacity, '0.5');
  assert.equal(r.inheritedFrom.opacity, 'Tablet');
  styles.setContext({ breakpoint: 'base', state: '' });
}

// 10. Rename, duplicate and delete carry the whole selector family.
{
  const { model, sheet, root } = setup();
  const card = model.addChild(root.id, 'card', {});
  sheet.setProperty(`#${card.name}`, 'color', 'red');
  sheet.setProperty(`#${card.name}:hover`, 'color', 'blue');
  sheet.setProperty(`#${card.name}`, 'width', '100%', '(max-width: 600px)');
  model.setName(card.id, 'hero');
  assert.equal(sheet.getProperty('#hero:hover', 'color'), 'blue');
  assert.equal(sheet.getProperty('#hero', 'width', '(max-width: 600px)'), '100%');
  const copy = model.duplicateComponent(card.id);
  assert.equal(sheet.getProperty(`#${copy.name}:hover`, 'color'), 'blue', 'duplicate copies states');
  model.removeComponent(copy.id);
  assert.equal(sheet.getProperty(`#${copy.name}:hover`, 'color'), null, 'delete removes the rules');
  model.undo();
  assert.equal(sheet.getProperty(`#${copy.name}:hover`, 'color'), 'blue', 'undo of delete restores them');
}

// 11. Wrap and unwrap keep order and are single undo steps.
{
  const { model, root } = setup();
  const a = model.addChild(root.id, 'button', {});
  const b = model.addChild(root.id, 'button', {});
  const c = model.addChild(root.id, 'button', {});
  const depth = model.undoStack.length;
  const wrapper = model.wrapComponents([c.id, a.id], 'row');
  assert.equal(model.undoStack.length, depth + 1);
  assert.deepEqual(wrapper.children, [a.id, c.id], 'document order kept');
  assert.deepEqual(model.getRoot().children, [wrapper.id, b.id]);
  model.unwrapComponent(wrapper.id);
  assert.deepEqual(model.getRoot().children, [a.id, c.id, b.id]);
  model.undo();
  model.undo();
  assert.deepEqual(model.getRoot().children, [a.id, b.id, c.id], 'back to the start');
}

// 12. Every write announces itself for the canvas and the file-dirty tracker.
assert.ok(events.length > 0 && events.every(e => e.source === 'style'));

console.log('Designer style routing certification passed (12 checks).');
