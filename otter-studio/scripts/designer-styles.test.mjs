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
const { StyleController, DEFAULT_BREAKPOINTS } = await import('../js/designer/style-context.js');
const { evaluateMedia, envSatisfying } = await import('../js/designer/css-values.js');
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

// 13. Provenance: a value in the Otter source, and one in styles.css.
{
  const { model, sheet, styles, root } = setup();
  const card = model.addChild(root.id, 'card', { padding: 12 });
  sheet.setProperty(`#${card.name}`, 'opacity', '0.8');
  const pad = styles.explain(card, 'padding');
  assert.equal(pad.status, 'set');
  assert.equal(pad.source, 'otter');
  assert.equal(pad.value, '12px');
  assert.deepEqual(pad.location, { file: 'source', component: card.name, key: 'padding' });
  const op = styles.explain(card, 'opacity');
  assert.equal(op.status, 'set');
  assert.equal(op.source, 'styles.css');
  assert.deepEqual(op.location, { file: 'styles.css', selector: `#${card.name}`, media: '' });
  const none = styles.explain(card, 'z-index');
  assert.equal(none.status, 'default');
  assert.equal(none.value, null);
}

// 14. Provenance: cascading from a wider breakpoint and from the normal state.
{
  const { model, sheet, styles, root } = setup();
  const btn = model.addChild(root.id, 'button', { text: 'Go', padding: 8 });
  const n = btn.name;
  sheet.setProperty(`#${n}`, 'opacity', '0.5', '(max-width: 900px)');
  sheet.setProperty(`#${n}:hover`, 'color', 'blue');
  styles.setContext({ breakpoint: 'mobile', state: ':hover' });
  const op = styles.explain(btn, 'opacity');
  assert.equal(op.status, 'inherited');
  assert.equal(op.from, 'Tablet');
  assert.equal(op.location.media, '(max-width: 900px)');
  const color = styles.explain(btn, 'color');
  assert.equal(color.status, 'inherited');
  assert.equal(color.from, 'Desktop · Hover');
  const pad = styles.explain(btn, 'padding');
  assert.equal(pad.status, 'inherited', 'the source value applies at every breakpoint');
  assert.equal(pad.source, 'otter');
  styles.setContext({ breakpoint: 'base', state: '' });
}

// 15. Provenance: a value set here that loses. An inline source value beats a
// plain Tablet rule someone wrote by hand; the rule is reported as overridden
// and the chain says by what.
{
  const { model, sheet, styles, root } = setup();
  const title = model.addChild(root.id, 'heading', { text: 'Hi', size: 24 });
  sheet.setProperty(`#${title.name}`, 'font-size', '18px', '(max-width: 900px)');
  styles.setContext({ breakpoint: 'tablet' });
  const fs = styles.explain(title, 'font-size');
  assert.equal(fs.status, 'overridden');
  assert.equal(fs.value, '24px', 'what the app really shows');
  assert.equal(fs.overriddenBy.source, 'otter');
  assert.equal(fs.mine.value, '18px');
  assert.equal(fs.chain.length, 2);
  // The same rule written through the controller would have worked:
  styles.write(title, { 'font-size': '18px' });
  const fixed = styles.explain(title, 'font-size');
  assert.equal(fixed.status, 'set');
  assert.equal(fixed.value, '18px');
  styles.setContext({ breakpoint: 'base' });
}

// 16. Provenance: compiler-forced layout. A row always gets inline
// align-items; with no user value that is what shows, and a plain rule
// loses to it while the !important one the controller writes wins.
{
  const { model, sheet, styles, root } = setup();
  const row = model.addChild(root.id, 'row', {});
  styles.compilerProbe = (comp, prop) => (comp.kind === 'row' && prop === 'align-items')
    ? { inline: 'center', rules: [] }
    : (comp.kind === 'primary button' && prop === 'background'
      ? { inline: null, rules: [{ selector: '.otter-button.primary', value: '#2563eb', important: true }] }
      : null);
  const ai = styles.explain(row, 'align-items');
  assert.equal(ai.status, 'compiler');
  assert.equal(ai.forced, true);
  assert.equal(ai.value, 'center');
  sheet.setProperty(`#${row.name}`, 'align-items', 'flex-start');
  assert.equal(styles.explain(row, 'align-items').status, 'overridden', 'a hand-written plain rule loses');
  styles.write(row, { 'align-items': 'flex-end' });
  const won = styles.explain(row, 'align-items');
  assert.equal(won.status, 'set');
  assert.equal(won.value, 'flex-end');

  // A primary button's source `background` (the schema default) never shows:
  // the compiler's .otter-button-primary rule is !important. Say so.
  const btn = model.addChild(root.id, 'primary button', { text: 'Go' });
  const hidden = styles.explain(btn, 'background');
  assert.equal(hidden.status, 'overridden');
  assert.equal(hidden.mine.source, 'otter');
  assert.equal(hidden.overriddenBy.source, 'compiler');
  // Editing it moves it to styles.css with !important, where it does show.
  styles.importantProbe = (comp, prop) => comp.kind === 'primary button' && prop === 'background';
  styles.write(btn, { background: '#16a34a' });
  assert.equal(btn.properties.background, undefined, 'left the source');
  assert.equal(sheet.getProperty(`#${btn.name}`, 'background'), '#16a34a !important');
  const fixedBg = styles.explain(btn, 'background');
  assert.equal(fixedBg.status, 'set');
  assert.equal(fixedBg.value, '#16a34a');
  sheet.removeProperty(`#${btn.name}`, 'background');
  styles.importantProbe = null;
  const bg = styles.explain(btn, 'background');
  assert.equal(bg.status, 'compiler');
  assert.equal(bg.location.selector, '.otter-button.primary');
  sheet.setProperty(`#${btn.name}`, 'background', 'red');
  assert.equal(styles.explain(btn, 'background').status, 'overridden', 'compiler !important beats a plain #id rule');
  sheet.setProperty(`#${btn.name}`, 'background', 'red !important');
  assert.equal(styles.explain(btn, 'background').status, 'set');
  styles.compilerProbe = null;
}

// 17. Provenance: inheritable properties come from the nearest ancestor.
{
  const { model, sheet, styles, root } = setup();
  const card = model.addChild(root.id, 'card', { foreground: '#ffffff' });
  const row = model.addChild(card.id, 'row', {});
  const text = model.addChild(row.id, 'text', { text: 'Hi' });
  delete text.properties.foreground; // schema default; this check is about the parent
  const color = styles.explain(text, 'color');
  assert.equal(color.status, 'inherited');
  assert.equal(color.source, 'parent');
  assert.equal(color.from, `parent ${card.name}`);
  assert.equal(color.value, '#ffffff');
  assert.equal(color.location.component, card.name);
  sheet.setProperty(`#${root.name}`, 'padding', '4px');
  assert.equal(styles.explain(text, 'padding').status, 'default', 'padding is not inherited');
  // The compiler's `.otter-heading { color: inherit }` defers to the parent too.
  const heading = model.addChild(row.id, 'heading', { text: 'Title' });
  delete heading.properties.foreground;
  styles.compilerProbe = (comp, prop) => (comp.kind === 'heading' && prop === 'color')
    ? { inline: null, rules: [{ selector: '.otter-heading', value: 'inherit', important: false }] } : null;
  assert.equal(styles.explain(heading, 'color').value, '#ffffff');
  assert.equal(styles.explain(heading, 'color').source, 'parent');
  styles.compilerProbe = null;
}

// 18. Breakpoints are data. A mobile-first project (min-width) cascades
// upward: designing Wide sees Tablet's value; designing Tablet does not
// see Wide's. New @media blocks go narrowest first so the wider one wins.
{
  const { model, sheet, styles, root } = setup();
  styles.setBreakpoints([
    { id: 'base', label: 'Phone', media: '', width: 375 },
    { id: 'tablet', label: 'Tablet', media: '(min-width: 768px)', width: 900 },
    { id: 'wide', label: 'Wide', media: '(min-width: 1200px)', width: 1400 }
  ]);
  assert.deepEqual(styles.breakpoints.map(b => b.id), ['base', 'tablet', 'wide']);
  const card = model.addChild(root.id, 'card', {});
  styles.setContext({ breakpoint: 'wide' });
  styles.write(card, { opacity: '0.9' });
  styles.setContext({ breakpoint: 'tablet' });
  styles.write(card, { 'letter-spacing': '2px' });
  assert.deepEqual(sheet.getMediaQueries(), ['(min-width: 768px)', '(min-width: 1200px)'], 'narrowest min-width first');
  assert.equal(styles.explain(card, 'opacity').status, 'default', 'Wide does not apply on a tablet');
  styles.setContext({ breakpoint: 'wide' });
  const ls = styles.explain(card, 'letter-spacing');
  assert.equal(ls.status, 'inherited');
  assert.equal(ls.from, 'Tablet');
  assert.equal(styles.resolve(card).inheritedFrom['letter-spacing'], 'Tablet');
  styles.setBreakpoints(null);
  assert.deepEqual(styles.breakpoints.map(b => b.id), ['base', 'tablet', 'mobile'], 'null restores the defaults');
  assert.equal(styles.context.breakpoint, 'base', 'an unknown breakpoint falls back to the base');
}

// 19. A condition breakpoint (dark mode) is previewed in its own
// environment: dark, desktop width. A Mobile rule does not apply there, and
// the dark rule does not apply on Mobile.
{
  const { model, sheet, styles, root } = setup();
  styles.setBreakpoints([
    ...DEFAULT_BREAKPOINTS,
    { id: 'dark', label: 'Dark', media: '(prefers-color-scheme: dark)' }
  ]);
  const env = styles.envFor(styles.breakpoints.find(b => b.id === 'dark'));
  assert.equal(env.colorScheme, 'dark');
  assert.equal(env.width, 1280);
  const text = model.addChild(root.id, 'text', { text: 'Hi' });
  sheet.setProperty(`#${text.name}`, 'opacity', '0.5', '(max-width: 600px)');
  sheet.setProperty(`#${text.name}`, 'letter-spacing', '1px', '(prefers-color-scheme: dark)');
  styles.setContext({ breakpoint: 'dark' });
  assert.equal(styles.explain(text, 'opacity').status, 'default');
  assert.equal(styles.explain(text, 'letter-spacing').status, 'set');
  styles.setContext({ breakpoint: 'mobile' });
  assert.equal(styles.explain(text, 'letter-spacing').status, 'default', 'Mobile previews light mode');
  assert.equal(styles.explain(text, 'opacity').status, 'set');
  assert.equal(evaluateMedia('(prefers-color-scheme: dark) and (max-width: 600px)', { width: 375, colorScheme: 'dark' }), true);
  assert.equal(evaluateMedia('(orientation: portrait)', envSatisfying('(orientation: portrait)', { width: 800 })), true);
  assert.equal(evaluateMedia('(hover: hover)', {}), true, 'desktop default has a mouse');
  assert.equal(evaluateMedia('(scripting: none)', {}), null, 'an unmodelled feature is left to the browser');
  styles.setBreakpoints(null);
}

console.log('Designer style routing certification passed (19 checks).');
