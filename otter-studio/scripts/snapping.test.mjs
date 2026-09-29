// Snapping in Free layout (js/designer/snapping.js): alignment, equal
// spacing, and the distances shown while moving.
import assert from 'node:assert/strict';
const { snapMove } = await import('../js/designer/snapping.js');

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

console.log(`\nSnapping tests passed: ${passed}.`);
