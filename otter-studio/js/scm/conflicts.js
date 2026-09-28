// conflicts.js - Read and resolve Git merge-conflict markers.
//
// When a merge cannot combine two changes to the same lines, git writes both
// versions into the file between markers:
//
//   <<<<<<< HEAD            (ours: the branch you are on)
//   say "blue"
//   ||||||| base            (optional, with merge.conflictStyle=diff3)
//   say "green"
//   =======
//   say "red"               (theirs: the branch being merged in)
//   >>>>>>> feature
//
// parseConflicts splits a file into plain text and conflict blocks.
// resolveConflict replaces one block with the chosen side(s), leaving the
// rest of the file untouched. The conflict editor shows each block with
// "Accept ours / theirs / both" and saves through the normal file save.

const START = /^<{7}(?: (.*))?$/;
const BASE = /^\|{7}(?: (.*))?$/;
const SEP = /^={7}$/;
const END = /^>{7}(?: (.*))?$/;

/**
 * Returns { blocks: [{ index, startLine, endLine, ours, base, theirs,
 * oursLabel, theirsLabel }], hasConflicts }. Line numbers are 0-based
 * indexes of the marker lines; ours/base/theirs are arrays of lines.
 */
export function parseConflicts(text) {
  const lines = String(text).split('\n');
  const blocks = [];
  let i = 0;
  while (i < lines.length) {
    const start = START.exec(lines[i].replace(/\r$/, ''));
    if (!start) { i++; continue; }
    const block = { index: blocks.length, startLine: i, endLine: -1, ours: [], base: null, theirs: [], oursLabel: start[1] || 'ours', theirsLabel: 'theirs' };
    let section = 'ours';
    let j = i + 1;
    for (; j < lines.length; j++) {
      const line = lines[j].replace(/\r$/, '');
      if (section === 'ours' && BASE.test(line)) { section = 'base'; block.base = []; continue; }
      if ((section === 'ours' || section === 'base') && SEP.test(line)) { section = 'theirs'; continue; }
      const end = section === 'theirs' ? END.exec(line) : null;
      if (end) { block.theirsLabel = end[1] || 'theirs'; break; }
      block[section].push(lines[j]);
    }
    if (j >= lines.length) break; // unterminated: not a conflict block
    block.endLine = j;
    blocks.push(block);
    i = j + 1;
  }
  return { blocks, hasConflicts: blocks.length > 0 };
}

/**
 * Replace conflict block `index` with the chosen text.
 * choice: 'ours' | 'theirs' | 'both' (ours then theirs) | 'base'.
 */
export function resolveConflict(text, index, choice) {
  const lines = String(text).split('\n');
  const { blocks } = parseConflicts(text);
  const block = blocks[index];
  if (!block) return text;
  let replacement;
  if (choice === 'ours') replacement = block.ours;
  else if (choice === 'theirs') replacement = block.theirs;
  else if (choice === 'both') replacement = [...block.ours, ...block.theirs];
  else if (choice === 'base') replacement = block.base || [];
  else throw new Error(`Unknown choice: ${choice}`);
  lines.splice(block.startLine, block.endLine - block.startLine + 1, ...replacement);
  return lines.join('\n');
}
