// diagnostic-manager.js - Exact Ranges, Normalization, Collection, and Quick Fix Association
// Part of Section 10: Diagnostics Experience

import { DiagnosticCodes, DiagnosticMetadata, resolveDiagnosticCode } from './diagnostic-codes.js';
import { translateHostError, extractOtterStackFrames } from './host-translator.js';

let diagnosticCounter = 0;

/**
 * Computes exact startLine, startColumn, endLine, endColumn (all 1-based)
 * from source text, given a line and column.
 */
export function computeExactRange(sourceText = '', line = 1, column = 1, code = '', message = '') {
  const lines = String(sourceText || '').split('\n');
  const safeLine = Math.max(1, Math.min(line || 1, Math.max(lines.length, 1)));
  const lineContent = lines[safeLine - 1] || '';
  const lineLen = lineContent.length;

  let startCol = Math.max(1, column || 1);
  let endCol = startCol + 1;

  // If startCol is beyond line length, clamp it to end of line
  if (startCol > lineLen) {
    startCol = Math.max(1, lineLen + 1);
    endCol = startCol + 1;
    return {
      startLine: safeLine,
      startColumn: startCol,
      endLine: safeLine,
      endColumn: endCol
    };
  }

  const charIdx = startCol - 1;
  const ch = lineContent[charIdx] || '';

  // Special case: Missing block terminator
  if (code === DiagnosticCodes.MISSING_BLOCK_TERMINATOR) {
    // Underline the offending keyword or token at column, or end of line
    if (charIdx < lineLen && /\S/.test(ch)) {
      const match = lineContent.slice(charIdx).match(/^[A-Za-z0-9_]+/);
      if (match) {
        endCol = startCol + match[0].length;
      } else {
        endCol = startCol + 1;
      }
    } else {
      endCol = startCol + 1;
    }
    return {
      startLine: safeLine,
      startColumn: startCol,
      endLine: safeLine,
      endColumn: endCol
    };
  }

  // Special case: Equals assignment '='
  if (code === DiagnosticCodes.EQUALS_ASSIGNMENT || ch === '=') {
    if (lineContent.slice(charIdx, charIdx + 2) === '==') {
      endCol = startCol + 2;
    } else {
      endCol = startCol + 1;
    }
    return {
      startLine: safeLine,
      startColumn: startCol,
      endLine: safeLine,
      endColumn: endCol
    };
  }

  // Special case: Period property access '.'
  if (code === DiagnosticCodes.PERIOD_PROPERTY_ACCESS || ch === '.') {
    endCol = startCol + 1;
    return {
      startLine: safeLine,
      startColumn: startCol,
      endLine: safeLine,
      endColumn: endCol
    };
  }

  // Word token (identifier, keyword, number)
  if (/[A-Za-z0-9_]/.test(ch)) {
    // Find word start
    let wordStart = charIdx;
    while (wordStart > 0 && /[A-Za-z0-9_]/.test(lineContent[wordStart - 1])) {
      wordStart--;
    }
    // Find word end
    let wordEnd = charIdx;
    while (wordEnd < lineLen && /[A-Za-z0-9_]/.test(lineContent[wordEnd])) {
      wordEnd++;
    }
    startCol = wordStart + 1;
    endCol = wordEnd + 1;
    return {
      startLine: safeLine,
      startColumn: startCol,
      endLine: safeLine,
      endColumn: endCol
    };
  }

  // String literal quotes
  if (ch === '"' || ch === "'") {
    let quoteEnd = charIdx + 1;
    while (quoteEnd < lineLen && lineContent[quoteEnd] !== ch) {
      quoteEnd++;
    }
    if (quoteEnd < lineLen) quoteEnd++;
    endCol = quoteEnd + 1;
    return {
      startLine: safeLine,
      startColumn: startCol,
      endLine: safeLine,
      endColumn: endCol
    };
  }

  // Default fallback: 1 character width
  endCol = Math.min(lineLen + 1, startCol + 1);
  return {
    startLine: safeLine,
    startColumn: startCol,
    endLine: safeLine,
    endColumn: Math.max(startCol + 1, endCol)
  };
}

/**
 * Normalizes a raw diagnostic object into the standard Otter Diagnostic schema.
 */
export function normalizeDiagnostic(raw = {}, sourceText = '', currentFile = 'main.ot') {
  const line = Number(raw.Line ?? raw.line ?? raw.startLine ?? 1);
  const col = Number(raw.Column ?? raw.column ?? raw.startColumn ?? 1);

  const rawMessage = String(raw.Message ?? raw.message ?? 'Unknown error').trim();
  const stage = raw.stage || (raw.isWarning ? 'analyzer' : 'parser');
  const code = resolveDiagnosticCode(rawMessage, stage, raw);
  const meta = DiagnosticMetadata[code] || {
    code,
    category: raw.category || 'syntax',
    severity: raw.severity || (raw.isWarning ? 'warning' : 'error'),
    title: 'Otter Diagnostic'
  };

  const severity = raw.severity || (raw.isWarning ? 'warning' : (meta.severity || 'error'));

  // Determine exact ranges
  let startLine = Number(raw.startLine || line);
  let startColumn = Number(raw.startColumn || col);
  let endLine = Number(raw.endLine || startLine);
  let endColumn = Number(raw.endColumn || 0);

  if (!raw.endColumn || (startLine === endLine && startColumn === endColumn)) {
    const computed = computeExactRange(sourceText, startLine, startColumn, code, rawMessage);
    startLine = computed.startLine;
    startColumn = computed.startColumn;
    endLine = computed.endLine;
    endColumn = computed.endColumn;
  }

  const file = (raw.file || raw.File || currentFile).replace(/\\/g, '/');

  const diagnostic = {
    id: `diag-${++diagnosticCounter}`,
    file,
    startLine,
    startColumn,
    endLine,
    endColumn,
    severity,
    code,
    title: meta.title,
    message: rawMessage,
    suggestion: raw.Suggestion ?? raw.suggestion ?? null,
    source: raw.source || 'otter', // 'otter' | 'host' | 'build' | 'studio'
    category: meta.category || raw.category || 'syntax',
    sourceLine: raw.SourceLine ?? raw.sourceLine ?? null,
    hostDetails: raw.hostDetails || null,
    target: raw.target || null,
    stack: raw.stack || (raw.hostDetails ? extractOtterStackFrames(raw.hostDetails, file, startLine) : []),
    fixes: []
  };

  // Associate safe Quick Fixes
  diagnostic.fixes = getDiagnosticQuickFixes(diagnostic, sourceText);

  // If raw provided custom fixes, preserve and merge them
  if (Array.isArray(raw.fixes) && raw.fixes.length > 0) {
    diagnostic.fixes = [...raw.fixes, ...diagnostic.fixes];
  }

  return diagnostic;
}

/**
 * Returns safe, verified Quick Fix actions for an Otter diagnostic.
 * Never generates a fix when the intended correction cannot be determined safely.
 */
export function getDiagnosticQuickFixes(diagnostic, sourceText = '') {
  const fixes = [];
  const { code, startLine, startColumn, endLine, endColumn, file, message } = diagnostic;
  const lines = sourceText ? sourceText.split('\n') : [];
  const lineIdx = startLine - 1;
  const targetLine = lines[lineIdx] || '';

  switch (code) {
    case DiagnosticCodes.MISSING_BLOCK_TERMINATOR: { // OT2001
      // Safe fix: Insert '.' block terminator
      // Determine proper indentation for the closing '.'
      const matchIndent = targetLine.match(/^(\s*)/);
      const indent = matchIndent ? matchIndent[1] : '';
      fixes.push({
        title: 'Add closing "."',
        description: 'Appends a closing period to complete the open block.',
        edits: [{
          file,
          startLine: startLine + 1,
          startColumn: 1,
          endLine: startLine + 1,
          endColumn: 1,
          newText: `${indent}.\n`
        }]
      });
      break;
    }

    case DiagnosticCodes.EQUALS_ASSIGNMENT: { // OT1004
      // Safe fix: Replace '=' with 'is'
      if (targetLine.includes('=')) {
        fixes.push({
          title: "Replace '=' with 'is'",
          description: "Otter uses 'is' for assignment and comparison.",
          edits: [{
            file,
            startLine,
            startColumn,
            endLine,
            endColumn,
            newText: 'is'
          }]
        });
      }
      break;
    }

    case DiagnosticCodes.PERIOD_PROPERTY_ACCESS: { // OT1003
      // Safe fix: Rewrite "obj.prop" into "prop of obj" if matches simple pattern
      const periodIdx = startColumn - 1;
      const before = targetLine.slice(0, periodIdx).match(/([a-zA-Z_][a-zA-Z0-9_]*)$/);
      const after = targetLine.slice(periodIdx + 1).match(/^([a-zA-Z_][a-zA-Z0-9_]*)/);
      if (before && after) {
        const objName = before[1];
        const propName = after[1];
        const matchStart = periodIdx - objName.length + 1;
        const matchEnd = periodIdx + 1 + propName.length + 1;
        fixes.push({
          title: `Use '${propName} of ${objName}' syntax`,
          description: "Otter reads properties with the 'of' preposition.",
          edits: [{
            file,
            startLine,
            startColumn: matchStart,
            endLine,
            endColumn: matchEnd,
            newText: `${propName} of ${objName}`
          }]
        });
      }
      break;
    }

    case DiagnosticCodes.INDENTATION_JUMP: { // OT1001
      // Safe fix: adjust indentation to 4 spaces per block level
      fixes.push({
        title: 'Fix indentation (4 spaces per level)',
        description: 'Align block indentation with 4 spaces.',
        edits: [{
          file,
          startLine,
          startColumn: 1,
          endLine,
          endColumn: targetLine.match(/^\s*/)?.[0]?.length + 1 || 1,
          newText: '    '
        }]
      });
      break;
    }

    case DiagnosticCodes.UNDECLARED_VARIABLE: { // OT3001
      // Safe fix: If variable name is identifiable from message
      const varMatch = message.match(/'([^']+)'/) || message.match(/"([^"]+)"/);
      if (varMatch) {
        const varName = varMatch[1];
        fixes.push({
          title: `Declare variable '${varName}'`,
          description: `Add 'make ${varName} is gone' before use.`,
          edits: [{
            file,
            startLine,
            startColumn: 1,
            endLine: startLine,
            endColumn: 1,
            newText: `make ${varName} is gone\n`
          }]
        });
      }
      break;
    }

    case DiagnosticCodes.UNUSED_DECLARATION: { // OT3003
      // Safe fix: Remove unused declaration or comment it
      fixes.push({
        title: 'Remove unused declaration',
        description: 'Delete the statement declaring the unused symbol.',
        edits: [{
          file,
          startLine,
          startColumn: 1,
          endLine: startLine + 1,
          endColumn: 1,
          newText: ''
        }]
      });
      break;
    }

    default:
      break;
  }

  return fixes;
}

/**
 * DiagnosticCollection manages diagnostics for the workspace,
 * grouped by file and sorted by line and column.
 */
export class DiagnosticCollection {
  constructor() {
    this.diagnosticsByFile = new Map(); // file -> Diagnostic[]
  }

  set(file, diagnostics = []) {
    const normalizedFile = String(file || '').replace(/\\/g, '/');
    if (!diagnostics || diagnostics.length === 0) {
      this.diagnosticsByFile.delete(normalizedFile);
      return;
    }
    const sorted = [...diagnostics].sort((a, b) => {
      if (a.startLine !== b.startLine) return a.startLine - b.startLine;
      return a.startColumn - b.startColumn;
    });
    this.diagnosticsByFile.set(normalizedFile, sorted);
  }

  get(file) {
    const normalizedFile = String(file || '').replace(/\\/g, '/');
    return this.diagnosticsByFile.get(normalizedFile) || [];
  }

  getAll() {
    const all = [];
    for (const [file, diags] of this.diagnosticsByFile.entries()) {
      for (const diag of diags) {
        all.push({ ...diag, file });
      }
    }
    return all.sort((a, b) => {
      const cmp = a.file.localeCompare(b.file);
      if (cmp !== 0) return cmp;
      if (a.startLine !== b.startLine) return a.startLine - b.startLine;
      return a.startColumn - b.startColumn;
    });
  }

  clear(file) {
    if (file) {
      this.diagnosticsByFile.delete(String(file).replace(/\\/g, '/'));
    } else {
      this.clearAll();
    }
  }

  clearAll() {
    this.diagnosticsByFile.clear();
  }

  hasErrors(file = null) {
    if (file) {
      return this.get(file).some(d => d.severity === 'error');
    }
    for (const diags of this.diagnosticsByFile.values()) {
      if (diags.some(d => d.severity === 'error')) return true;
    }
    return false;
  }

  hasWarnings(file = null) {
    if (file) {
      return this.get(file).some(d => d.severity === 'warning');
    }
    for (const diags of this.diagnosticsByFile.values()) {
      if (diags.some(d => d.severity === 'warning')) return true;
    }
    return false;
  }

  getCounts(file = null) {
    const diags = file ? this.get(file) : this.getAll();
    let errors = 0;
    let warnings = 0;
    let info = 0;
    for (const d of diags) {
      if (d.severity === 'error') errors++;
      else if (d.severity === 'warning') warnings++;
      else info++;
    }
    return { total: diags.length, errors, warnings, info };
  }

  findByLocation(file, line, column = 1) {
    const list = this.get(file);
    return list.find(d => {
      if (line < d.startLine || line > d.endLine) return false;
      if (line === d.startLine && column < d.startColumn) return false;
      if (line === d.endLine && column > d.endColumn) return false;
      return true;
    }) || null;
  }
}
