// multi-cursor.js - Multi-Cursor State, Next Occurrence Selection, and Synchronized Editing for Otter Studio

export class MultiCursorManager {
  constructor() {
    // Array of { start: number, end: number }
    // The first entry (index 0) represents the primary cursor matching the native textarea.
    this.cursors = [{ start: 0, end: 0 }];
  }

  get primary() {
    return this.cursors[0] || { start: 0, end: 0 };
  }

  get secondaries() {
    return this.cursors.slice(1);
  }

  hasMultipleCursors() {
    return this.cursors.length > 1;
  }

  setPrimaryCursor(start, end = start) {
    this.cursors[0] = { start: Math.min(start, end), end: Math.max(start, end) };
  }

  clearSecondaryCursors() {
    this.cursors = [this.primary];
  }

  addCursor(start, end = start) {
    const range = { start: Math.min(start, end), end: Math.max(start, end) };
    // Check if cursor already exists at exact location
    const exists = this.cursors.some(c => c.start === range.start && c.end === range.end);
    if (!exists) {
      this.cursors.push(range);
      this.normalizeCursors();
    }
  }

  normalizeCursors() {
    // Sort cursors by start offset ascending, merging overlapping ranges
    if (this.cursors.length <= 1) return;

    this.cursors.sort((a, b) => a.start - b.start || a.end - b.end);

    const merged = [this.cursors[0]];
    for (let i = 1; i < this.cursors.length; i++) {
      const prev = merged[merged.length - 1];
      const cur = this.cursors[i];

      if (cur.start <= prev.end) {
        // Overlap or touch: merge
        prev.end = Math.max(prev.end, cur.end);
      } else {
        merged.push({ start: cur.start, end: cur.end });
      }
    }
    this.cursors = merged;
  }

  // Ctrl+D: Find next occurrence of current selection (or word under primary cursor)
  selectNextOccurrence(code) {
    if (!code) return false;

    let targetText = '';
    const prim = this.primary;

    if (prim.start !== prim.end) {
      targetText = code.slice(prim.start, prim.end);
    } else {
      // Find word bounds under cursor
      const word = this.getWordAtOffset(code, prim.start);
      if (!word.text) return false;
      targetText = word.text;
      this.cursors[0] = { start: word.start, end: word.end };
    }

    if (!targetText) return false;

    // Search for next occurrence after the last cursor's end
    const lastCursor = this.cursors[this.cursors.length - 1];
    let nextIndex = code.indexOf(targetText, lastCursor.end);

    if (nextIndex === -1) {
      // Wrap around to start of document
      nextIndex = code.indexOf(targetText, 0);
    }

    // Check if this occurrence is already selected
    const alreadySelected = this.cursors.some(c => c.start === nextIndex && c.end === nextIndex + targetText.length);
    if (nextIndex !== -1 && !alreadySelected) {
      this.addCursor(nextIndex, nextIndex + targetText.length);
      return true;
    }

    return false;
  }

  // Ctrl+Alt+Up / Ctrl+Alt+Down: Add cursor on line above (-1) or line below (+1) at same column
  addColumnCursor(code, direction = 1) {
    if (!code) return false;

    const prim = this.primary;
    const { line, column } = this.getLineAndCol(code, prim.start);
    const targetLine = line + direction;

    const lines = code.split('\n');
    if (targetLine < 1 || targetLine > lines.length) return false;

    const targetLineText = lines[targetLine - 1];
    const targetCol = Math.min(column, targetLineText.length);
    const targetOffset = this.getOffsetFromLineAndCol(code, targetLine, targetCol);

    this.addCursor(targetOffset, targetOffset);
    return true;
  }

  // Synchronized multi-cursor text editing:
  // Sorts cursors, computes cumulative shift deltas, and applies replacements in descending order
  applyEdit(code, textToInsert = '', isBackspace = false, isDelete = false) {
    if (!this.hasMultipleCursors()) {
      return null;
    }

    this.normalizeCursors();

    // Prepare range to replace for each cursor
    const editOps = this.cursors.map(c => {
      let start = c.start;
      let end = c.end;

      if (isBackspace) {
        if (start === end && start > 0) {
          start -= 1;
        }
      } else if (isDelete) {
        if (start === end && end < code.length) {
          end += 1;
        }
      }

      return { start, end };
    });

    // Compute updated cursor positions with cumulative shift deltas
    let cumulativeDelta = 0;
    const newCursors = [];

    for (const op of editOps) {
      const newPos = op.start + textToInsert.length + cumulativeDelta;
      newCursors.push({ start: newPos, end: newPos });
      const opDelta = textToInsert.length - (op.end - op.start);
      cumulativeDelta += opDelta;
    }

    // Apply text replacements from right to left so left indices remain valid
    let updatedCode = code;
    const sortedDescending = [...editOps].sort((a, b) => b.start - a.start);

    for (const op of sortedDescending) {
      updatedCode = updatedCode.slice(0, op.start) + textToInsert + updatedCode.slice(op.end);
    }

    this.cursors = newCursors;
    this.normalizeCursors();

    return {
      code: updatedCode,
      cursors: this.cursors
    };
  }

  getWordAtOffset(code, offset) {
    if (!code) return { text: '', start: offset, end: offset };
    const safeOffset = Math.max(0, Math.min(offset, code.length));

    // Expand left
    let start = safeOffset;
    while (start > 0 && /[a-zA-Z0-9_\$]/.test(code[start - 1])) {
      start--;
    }

    // Expand right
    let end = safeOffset;
    while (end < code.length && /[a-zA-Z0-9_\$]/.test(code[end])) {
      end++;
    }

    return {
      text: code.slice(start, end),
      start,
      end
    };
  }

  getLineAndCol(code, offset) {
    const textUpToOffset = code.slice(0, Math.max(0, offset));
    const lines = textUpToOffset.split('\n');
    return {
      line: lines.length,
      column: lines[lines.length - 1].length
    };
  }

  getOffsetFromLineAndCol(code, targetLine, targetCol) {
    const lines = code.split('\n');
    let offset = 0;
    for (let i = 0; i < lines.length && i < targetLine - 1; i++) {
      offset += lines[i].length + 1; // +1 for \n
    }
    if (targetLine <= lines.length) {
      offset += Math.min(targetCol, lines[targetLine - 1].length);
    }
    return offset;
  }
}
