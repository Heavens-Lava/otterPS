// snapping.js - Where a control being moved in a Free layout container
// snaps, and what the canvas shows while it moves (the geometry only; the
// canvas draws it).
//
//   snapMove(box, siblings, parent, { threshold, zoom })
//
// box      the moved control's proposed box       { left, top, width, height }
// siblings the other controls in the container    [{ left, top, width, height }]
// parent   the container's padding box            { left, top, width, height }
// All in the same units (the canvas passes screen px); threshold is in those
// units too, zoom converts them to CSS px for the labels.
//
// It snaps, per axis, to whichever is nearest within the threshold:
//   - alignment: an edge or centre lines up with a sibling's or the
//     container's edge or centre (a guide line is drawn);
//   - equal spacing: the gap to a neighbour equals a gap already between two
//     siblings in the same row (or column), or the control sits exactly
//     midway between two neighbours (the equal gaps are marked).
// Then it measures the gaps around the result: to the nearest sibling on
// each side, and to the container's nearer edge on each axis where no
// sibling is in the way.
//
// Returns { dx, dy, lines, gaps, measures } - dx / dy in the input units.

const edges = (b) => ({ left: b.left, top: b.top, right: b.left + b.width, bottom: b.top + b.height, cx: b.left + b.width / 2, cy: b.top + b.height / 2 });
const overlapsY = (a, b) => a.top < b.bottom - 0.5 && b.top < a.bottom - 0.5;
const overlapsX = (a, b) => a.left < b.right - 0.5 && b.left < a.right - 0.5;

// Axis descriptors: the same code handles x (left/right, rows) and y.
const AXES = {
  x: { start: 'left', end: 'right', mid: 'cx', size: 'width', cross: overlapsY, crossStart: 'top', crossEnd: 'bottom' },
  y: { start: 'top', end: 'bottom', mid: 'cy', size: 'height', cross: overlapsX, crossStart: 'left', crossEnd: 'right' }
};

function alignmentCandidates(axis, box, targets) {
  const A = AXES[axis];
  const out = [];
  for (const t of targets) {
    for (const mine of [A.start, A.mid, A.end]) {
      for (const theirs of [A.start, A.mid, A.end]) {
        out.push({ kind: 'align', d: t[theirs] - box[mine], at: t[theirs], target: t });
      }
    }
  }
  return out;
}

// Gaps between neighbours in the moved control's row (x) or column (y).
function laneOf(axis, box, siblings) {
  const A = AXES[axis];
  return siblings.filter(s => A.cross(s, box)).sort((a, b) => a[A.start] - b[A.start]);
}

function existingGaps(axis, lane) {
  const A = AXES[axis];
  const gaps = [];
  for (let i = 0; i + 1 < lane.length; i++) {
    const g = lane[i + 1][A.start] - lane[i][A.end];
    if (g > 0.5) gaps.push({ size: g, a: lane[i], b: lane[i + 1] });
  }
  return gaps;
}

function spacingCandidates(axis, box, siblings) {
  const A = AXES[axis];
  const lane = laneOf(axis, box, siblings);
  const gaps = existingGaps(axis, lane);
  const size = box[A.end] - box[A.start];
  const out = [];
  for (const s of lane) {
    for (const g of gaps) {
      // After s: start = s.end + gap. Before s: end = s.start - gap.
      out.push({ kind: 'space', d: s[A.end] + g.size - box[A.start], markers: [[s[A.end], s[A.end] + g.size, s], [g.a[A.end], g.b[A.start], g.a, g.b]] });
      out.push({ kind: 'space', d: s[A.start] - g.size - box[A.end], markers: [[s[A.start] - g.size, s[A.start], s], [g.a[A.end], g.b[A.start], g.a, g.b]] });
    }
  }
  // Midway between two neighbours that have room for it.
  for (let i = 0; i + 1 < lane.length; i++) {
    const room = lane[i + 1][A.start] - lane[i][A.end];
    if (room <= size) continue;
    const g = (room - size) / 2;
    const start = lane[i][A.end] + g;
    out.push({ kind: 'space', d: start - box[A.start], markers: [[lane[i][A.end], start, lane[i]], [start + size, lane[i + 1][A.start], lane[i + 1]]] });
  }
  return out;
}

function best(candidates, threshold) {
  let pick = null;
  for (const c of candidates) {
    if (Math.abs(c.d) > threshold) continue;
    // Nearest wins; on a tie, alignment beats spacing (it reads better).
    if (!pick || Math.abs(c.d) < Math.abs(pick.d) - 0.01 || (Math.abs(Math.abs(c.d) - Math.abs(pick.d)) <= 0.01 && c.kind === 'align' && pick.kind !== 'align')) pick = c;
  }
  return pick;
}

export function snapMove(box, siblings = [], parent = null, { threshold = 6, zoom = 1 } = {}) {
  const b0 = edges(box);
  const sibs = siblings.map(edges);
  const par = parent ? edges(parent) : null;
  const alignTargets = par ? [par, ...sibs] : sibs;

  const spaceX = spacingCandidates('x', b0, sibs);
  const spaceY = spacingCandidates('y', b0, sibs);
  const pickX = best([...alignmentCandidates('x', b0, alignTargets), ...spaceX], threshold);
  const pickY = best([...alignmentCandidates('y', b0, alignTargets), ...spaceY], threshold);
  // When an alignment and an equal spacing land on the same spot (midway
  // between two cards is also the window's centre), show both.
  const alsoSpace = (pick, candidates) => (pick?.kind === 'align' ? candidates.find(c => Math.abs(c.d - pick.d) < 0.5) : null);
  const extraX = alsoSpace(pickX, spaceX);
  const extraY = alsoSpace(pickY, spaceY);
  const dx = pickX ? pickX.d : 0;
  const dy = pickY ? pickY.d : 0;
  const b = edges({ left: box.left + dx, top: box.top + dy, width: box.width, height: box.height });

  const lines = [];
  if (pickX?.kind === 'align') lines.push({ axis: 'x', at: pickX.at, from: Math.min(b.top, pickX.target.top), to: Math.max(b.bottom, pickX.target.bottom) });
  if (pickY?.kind === 'align') lines.push({ axis: 'y', at: pickY.at, from: Math.min(b.left, pickY.target.left), to: Math.max(b.right, pickY.target.right) });

  // Equal-gap markers: short bars across each equal gap, with its size.
  const gaps = [];
  for (const [axis, pick] of [['x', pickX], ['y', pickY], ['x', extraX], ['y', extraY]]) {
    if (pick?.kind !== 'space') continue;
    const A = AXES[axis];
    for (const [from, to, s1, s2] of pick.markers) {
      const other = s2 || b;
      const lo = Math.max(s1[A.crossStart], other[A.crossStart]);
      const hi = Math.min(s1[A.crossEnd], other[A.crossEnd]);
      const at = lo < hi ? (lo + hi) / 2 : (s1[A.crossStart] + s1[A.crossEnd]) / 2;
      gaps.push({ axis, from, to, at, px: Math.round((to - from) / zoom) });
    }
  }

  // Distances to the nearest sibling on each side; to the container's nearer
  // edge on each axis where that side has no sibling.
  const measures = [];
  for (const axis of ['x', 'y']) {
    const A = AXES[axis];
    const lane = sibs.filter(s => A.cross(s, b));
    const before = lane.filter(s => s[A.end] <= b[A.start] + 0.5).sort((p, q) => q[A.end] - p[A.end])[0];
    const after = lane.filter(s => s[A.start] >= b[A.end] - 0.5).sort((p, q) => p[A.start] - q[A.start])[0];
    const crossMid = (s) => {
      const lo = Math.max(s[A.crossStart], b[A.crossStart]);
      const hi = Math.min(s[A.crossEnd], b[A.crossEnd]);
      return (lo + hi) / 2;
    };
    if (before) measures.push({ axis, from: before[A.end], to: b[A.start], at: crossMid(before), px: Math.round((b[A.start] - before[A.end]) / zoom) });
    if (after) measures.push({ axis, from: b[A.end], to: after[A.start], at: crossMid(after), px: Math.round((after[A.start] - b[A.end]) / zoom) });
    if (par) {
      // The sides with no sibling measure to the container; of those, only
      // the nearer one is shown (four edge lines at once is clutter).
      const mid = (b[A.crossStart] + b[A.crossEnd]) / 2;
      const open = [];
      if (!before) open.push({ from: par[A.start], to: b[A.start] });
      if (!after) open.push({ from: b[A.end], to: par[A.end] });
      const nearest = open.sort((p, q) => (p.to - p.from) - (q.to - q.from))[0];
      if (nearest) measures.push({ axis, ...nearest, at: mid, px: Math.round((nearest.to - nearest.from) / zoom), toParent: true });
    }
  }

  return { dx, dy, lines, gaps, measures };
}

// Resizing by a handle: the edges that handle drags snap on their own.
//
//   snapResize(box, handle, siblings, parent, { threshold, zoom })
//
// handle is 'e', 'sw', 'n', ... (the sides that move). Per moving side, the
// edge snaps to whichever is nearest within the threshold:
//   - alignment: a sibling's or the container's edge or centre (a line);
//   - equal size: the width (or height) of a sibling (both are marked).
// Returns { box, lines, sizes } - box is the snapped box; sizes are bars
// under (x) or beside (y) each equal-sized control, with the size in CSS px.
export function snapResize(box, handle, siblings = [], parent = null, { threshold = 6, zoom = 1 } = {}) {
  const b0 = edges(box);
  const sibs = siblings.map((s, index) => ({ ...edges(s), index }));
  const par = parent ? edges(parent) : null;
  const targets = par ? [par, ...sibs] : sibs;
  const out = { left: box.left, top: box.top, width: box.width, height: box.height };
  const picks = [];

  for (const axis of ['x', 'y']) {
    const A = AXES[axis];
    const [endKey, startKey] = axis === 'x' ? ['e', 'w'] : ['s', 'n'];
    const side = handle.includes(endKey) ? 'end' : handle.includes(startKey) ? 'start' : null;
    if (!side) continue;
    const edge = b0[side === 'end' ? A.end : A.start];
    const size = b0[A.end] - b0[A.start];
    // Moving the end edge by d grows the size by d; the start edge shrinks it.
    const grow = side === 'end' ? 1 : -1;
    const candidates = [];
    for (const t of targets) {
      for (const k of [A.start, A.mid, A.end]) candidates.push({ kind: 'align', d: t[k] - edge, at: t[k], target: t });
    }
    for (const s of sibs) candidates.push({ kind: 'size', d: grow * ((s[A.end] - s[A.start]) - size), target: s });
    // Never snap to a size of nothing (an edge onto the opposite edge).
    const pick = best(candidates.filter(c => size + grow * c.d >= 1), threshold);
    if (!pick) continue;
    if (side === 'end') out[A.size] += pick.d;
    else { out[A.start] += pick.d; out[A.size] -= pick.d; }
    // An alignment that also makes the sizes equal shows both.
    const sameSize = pick.kind === 'align' ? candidates.find(c => c.kind === 'size' && Math.abs(c.d - pick.d) < 0.5) : null;
    picks.push({ axis, pick, sameSize });
  }

  const b = edges(out);
  const lines = [];
  const sizes = [];
  for (const { axis, pick, sameSize } of picks) {
    const A = AXES[axis];
    if (pick.kind === 'align') {
      lines.push({ axis, at: pick.at, from: Math.min(b[A.crossStart], pick.target[A.crossStart]), to: Math.max(b[A.crossEnd], pick.target[A.crossEnd]) });
    }
    const match = pick.kind === 'size' ? pick.target : sameSize?.target;
    if (match) {
      for (const r of [b, match]) {
        // A bar just outside the box: under it for a width, beside it for a height.
        sizes.push({ axis, from: r[A.start], to: r[A.end], at: r[A.crossEnd] + 6 * zoom, px: Math.round((r[A.end] - r[A.start]) / zoom), index: r.index });
      }
    }
  }
  return { box: out, lines, sizes };
}
