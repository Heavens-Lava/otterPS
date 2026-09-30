// Snapping in Free layout (js/designer/snapping.js): alignment, equal
// spacing, and the distances shown while moving.
import assert from 'node:assert/strict';
const { snapMove, snapResize } = await import('../js/designer/snapping.js');

let passed = 0;
function test(name, fn) {
  fn();
  passed++;
  console.log(`  ✓ ${name}`);
}

const parent = { left: 0, top: 0, width: 1000, height: 600 };
const card = (left, top, width = 200, height = 100) => ({ left, top, width, height });

console.log('Free layout snapping:');

test('edges line up: a left edge 4 px off snaps to the sibling above', () => {
  const r = snapMove(card(104, 310), [card(100, 100)], parent);
  assert.equal(r.dx, -4);
  assert.deepEqual(r.lines.map(l => [l.axis, l.at]), [['x', 100]]);
});

test('nothing near: no snap, no guide', () => {
  const r = snapMove(card(137, 333), [card(500, 50)], parent);
  assert.equal(r.dx, 0);
  assert.equal(r.dy, 0);
  assert.equal(r.lines.length, 0);
});

test('equal spacing: the third card snaps to the gap between the first two', () => {
  // Cards at 100 and 340 (gap 40, they end at 300); the third is dragged to 583.
  const r = snapMove(card(583, 100), [card(100, 100), card(340, 100)], parent);
  assert.equal(r.dx, 580 - 583, 'lands at 540 + 40');
  assert.ok(r.gaps.length >= 2, 'both equal gaps are marked');
  assert.ok(r.gaps.every(g => g.px === 40));
});

test('midway between two neighbours: equal gaps on both sides', () => {
  // Room between 300 and 700 for a 200-wide card: 100 each side.
  const r = snapMove(card(403, 100), [card(100, 100), card(700, 100)], parent);
  assert.equal(r.dx, -3);
  assert.deepEqual(r.gaps.map(g => g.px).sort(), [100, 100]);
});

test('vertical spacing works the same way (a column of cards)', () => {
  const r = snapMove(card(100, 262), [card(100, 20), card(100, 140)], parent);
  assert.equal(r.dy, 260 - 262, 'gap 20 below the second card');
});

test('distances: to the nearest neighbour on each side, in CSS px at the zoom', () => {
  const r = snapMove(card(400, 300, 100, 50), [card(100, 300, 100, 50), card(700, 300, 100, 50)], parent, { threshold: 0, zoom: 2 });
  const xs = r.measures.filter(m => m.axis === 'x' && !m.toParent).map(m => m.px).sort((a, b) => a - b);
  assert.deepEqual(xs, [100, 100], '200 screen px each side at 200% = 100 px');
  const toParent = r.measures.filter(m => m.axis === 'y' && m.toParent);
  assert.equal(toParent.length, 1, 'no sibling above or below: the nearer container edge only');
  assert.equal(toParent[0].px, Math.round(250 / 2), '600 - 350 = 250 below vs 300 above');
});

console.log('Resizing:');

test('resize: the dragged right edge snaps to a sibling\'s right edge', () => {
  // Card at 100..300; the other (at 100, 250) is dragged from its right handle to 296.
  const r = snapResize(card(100, 250, 196, 80), 'e', [card(100, 100)], parent);
  assert.equal(r.box.width, 200);
  assert.equal(r.box.left, 100);
  assert.deepEqual(r.lines.map(l => [l.axis, l.at]), [['x', 300]]);
});

test('resize: the left handle moves the left edge; the right edge stays put', () => {
  const r = snapResize(card(503, 250, 197, 80), 'w', [card(500, 100)], parent);
  assert.equal(r.box.left, 500);
  assert.equal(r.box.left + r.box.width, 700);
});

test('resize: equal width with a sibling elsewhere, both marked with the size', () => {
  // Not aligned (different left), but 4 px short of the sibling's 200.
  const r = snapResize(card(600, 300, 196, 80), 'e', [card(100, 100)], parent);
  assert.equal(r.box.width, 200);
  assert.equal(r.lines.length, 0);
  assert.deepEqual(r.sizes.map(z => z.px), [200, 200]);
  assert.equal(r.sizes[1].index, 0, 'the second bar is under the sibling');
});

test('resize: a bottom-right corner snaps each edge on its own; nothing near leaves it alone', () => {
  const r = snapResize(card(100, 250, 203, 57), 'se', [card(100, 100), card(400, 250, 100, 60)], parent);
  assert.equal(r.box.width, 200, 'right edge to 300');
  assert.equal(r.box.height, 60, 'bottom to the neighbour\'s bottom (310)');
  const none = snapResize(card(100, 250, 137, 57), 'e', [card(700, 500, 40, 40)], parent);
  assert.equal(none.box.width, 137);
});

test('resize: never to a size of nothing', () => {
  // The only nearby edge is the control's own left edge (a sibling starts there).
  const r = snapResize(card(100, 300, 3, 40), 'e', [card(100, 100)], parent);
  assert.ok(r.box.width >= 1);
});

// Tablet and Mobile (js/components/canvas.js): what is inside what is the
// same on every screen, so a move there only places a control - never into
// another container - and the canvas draws what hangs past the screen edge
// (the app scrolls sideways to it) so it can be grabbed.
{
  const fs = await import('node:fs');
  const canvasJs = fs.readFileSync(new URL('../js/components/canvas.js', import.meta.url), 'utf8');
  const designerCss = fs.readFileSync(new URL('../css/designer.css', import.meta.url), 'utf8');
  const canvasCss = fs.readFileSync(new URL('../css/canvas.css', import.meta.url), 'utf8');
  test('breakpoints: a move on Tablet or Mobile never changes the container', () => {
    assert.match(canvasJs, /into = styles\.isBaseBreakpoint\(\) \? other : null;/);
  });
  test('breakpoints: controls past the screen edge stay drawn and are counted', () => {
    assert.match(designerCss, /\.canvas-window-wrapper\.is-device \.window-content-area \{[^}]*overflow: visible;/);
    assert.match(canvasJs, /past the edge/);
  });
  test('the window\'s children never shrink to its height (as in the compiled window)', () => {
    assert.match(canvasCss, /\.window-content-area > \.canvas-element \{\s*flex-shrink: 0;/);
  });
}

console.log(`\nSnapping tests passed: ${passed}.`);
