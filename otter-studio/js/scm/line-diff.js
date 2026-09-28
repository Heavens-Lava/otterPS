// line-diff.js - Line-by-line diff for the source-control diff viewer.
//
// Uses the Myers algorithm (the one git uses by default): it finds the
// shortest edit script - the fewest inserted plus deleted lines that turn
// the original text into the modified one - by exploring "diagonals" of an
// edit graph. Runs in O((N+M)·D) time where D is the number of differences,
// so typical small edits to large files are fast.
//
// diffLines(a, b) returns operations in order:
//   { type: 'equal' | 'delete' | 'insert', oldLine, newLine, text }
// (line numbers are 1-based; oldLine is null for inserts, newLine for deletes)
//
// sideBySide(ops) pairs deletes with inserts into rows for a two-column view.

const MAX_EDIT_DISTANCE = 20000;

export function splitLines(text) {
  if (text === '' || text === null || text === undefined) return [];
  const lines = String(text).replace(/\r\n/g, '\n').split('\n');
  if (lines[lines.length - 1] === '') lines.pop(); // trailing newline is not a line
  return lines;
}

export function diffLines(originalText, modifiedText) {
  const a = splitLines(originalText);
  const b = splitLines(modifiedText);

  // Trim the common start and end first: most real diffs are a small change
  // in the middle of a big file, so this keeps the core search tiny.
  let start = 0;
  while (start < a.length && start < b.length && a[start] === b[start]) start++;
  let endA = a.length;
  let endB = b.length;
  while (endA > start && endB > start && a[endA - 1] === b[endB - 1]) { endA--; endB--; }

  const ops = [];
  for (let i = 0; i < start; i++) ops.push({ type: 'equal', oldLine: i + 1, newLine: i + 1, text: a[i] });
  const middle = myers(a.slice(start, endA), b.slice(start, endB));
  for (const op of middle) {
    ops.push({
      type: op.type,
      oldLine: op.oldIndex === null ? null : op.oldIndex + start + 1,
      newLine: op.newIndex === null ? null : op.newIndex + start + 1,
      text: op.text
    });
  }
  for (let i = 0; i < a.length - endA; i++) {
    ops.push({ type: 'equal', oldLine: endA + i + 1, newLine: endB + i + 1, text: a[endA + i] });
  }
  return ops;
}

// Classic Myers: V[k] holds the furthest x reached on diagonal k (k = x - y).
// We keep a copy of V per edit distance d, then walk back to recover the path.
function myers(a, b) {
  const n = a.length;
  const m = b.length;
  if (n === 0) return b.map((text, j) => ({ type: 'insert', oldIndex: null, newIndex: j, text }));
  if (m === 0) return a.map((text, i) => ({ type: 'delete', oldIndex: i, newIndex: null, text }));

  const max = Math.min(n + m, MAX_EDIT_DISTANCE);
  const offset = max + 1;
  let v = new Int32Array(2 * max + 3);
  const trace = [];

  let found = false;
  for (let d = 0; d <= max && !found; d++) {
    trace.push(v.slice());
    for (let k = -d; k <= d; k += 2) {
      // Move down (insert) or right (delete), whichever reaches further.
      let x = (k === -d || (k !== d && v[offset + k - 1] < v[offset + k + 1]))
        ? v[offset + k + 1]
        : v[offset + k - 1] + 1;
      let y = x - k;
      // Follow the "snake": matching lines cost nothing.
      while (x < n && y < m && a[x] === b[y]) { x++; y++; }
      v[offset + k] = x;
      if (x >= n && y >= m) { found = true; break; }
    }
  }

  if (!found) {
    // Pathologically different inputs: report a full replacement.
    return [
      ...a.map((text, i) => ({ type: 'delete', oldIndex: i, newIndex: null, text })),
      ...b.map((text, j) => ({ type: 'insert', oldIndex: null, newIndex: j, text }))
    ];
  }

  // Backtrack from (n, m) through the saved V arrays.
  const ops = [];
  let x = n;
  let y = m;
  for (let d = trace.length - 1; d >= 0; d--) {
    const vd = trace[d];
    const k = x - y;
    const prevK = (k === -d || (k !== d && vd[offset + k - 1] < vd[offset + k + 1])) ? k + 1 : k - 1;
    const prevX = vd[offset + prevK];
    const prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      ops.push({ type: 'equal', oldIndex: x - 1, newIndex: y - 1, text: a[x - 1] });
      x--; y--;
    }
    if (d > 0) {
      if (x === prevX) ops.push({ type: 'insert', oldIndex: null, newIndex: prevY, text: b[prevY] });
      else ops.push({ type: 'delete', oldIndex: prevX, newIndex: null, text: a[prevX] });
    }
    x = prevX;
    y = prevY;
  }
  return ops.reverse();
}

/**
 * Rows for a two-column view: [{ left, right, type }] where left/right are
 * { line, text } or null. A run of deletes followed by inserts is shown as
 * "changed" rows side by side.
 */
export function sideBySide(ops) {
  const rows = [];
  let i = 0;
  while (i < ops.length) {
    const op = ops[i];
    if (op.type === 'equal') {
      rows.push({ type: 'equal', left: { line: op.oldLine, text: op.text }, right: { line: op.newLine, text: op.text } });
      i++;
      continue;
    }
    const deletes = [];
    const inserts = [];
    while (i < ops.length && ops[i].type === 'delete') deletes.push(ops[i++]);
    while (i < ops.length && ops[i].type === 'insert') inserts.push(ops[i++]);
    const count = Math.max(deletes.length, inserts.length);
    for (let j = 0; j < count; j++) {
      const del = deletes[j];
      const ins = inserts[j];
      rows.push({
        type: del && ins ? 'change' : (del ? 'delete' : 'insert'),
        left: del ? { line: del.oldLine, text: del.text } : null,
        right: ins ? { line: ins.newLine, text: ins.text } : null
      });
    }
  }
  return rows;
}

/** Count of added and removed lines, for summaries. */
export function diffStats(ops) {
  return {
    added: ops.filter(o => o.type === 'insert').length,
    removed: ops.filter(o => o.type === 'delete').length
  };
}
