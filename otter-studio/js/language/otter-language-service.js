// otter-studio/js/language/otter-language-service.js
// Shared Otter Language Analysis & Intelligence Service
// Consolidates Metadata, Hover, Definition, References, Signature Help, and Safe Rename.

import { getBuiltinMetadata, getBuiltinSignatures } from './otter-metadata.js';

export class OtterLanguageService {
  constructor() {
    this.builtinSignatures = getBuiltinSignatures();
  }

  // --- 1. Token & Word Extraction ---
  getWordAtOffset(text, offset) {
    if (!text || offset < 0 || offset >= text.length) return null;
    const isWordChar = c => /[A-Za-z0-9_]/.test(c || '');
    
    let lineStart = text.lastIndexOf('\n', offset - 1) + 1;
    let lineEnd = text.indexOf('\n', offset);
    if (lineEnd === -1) lineEnd = text.length;
    const line = text.slice(lineStart, lineEnd);
    const col = offset - lineStart;

    const multiWordKeywords = [
      'is at least', 'is at most', 'is greater than', 'is less than', 'is not',
      'get files in', 'get folders in', 'and subfolders into', 'copy file to',
      'for each', 'name of', 'extension of', 'create folder', 'divided by',
      'length of', 'uppercase of', 'lowercase of', 'on tick', 'on key'
    ];

    for (const phrase of multiWordKeywords) {
      let searchIdx = 0;
      while ((searchIdx = line.toLowerCase().indexOf(phrase, searchIdx)) !== -1) {
        if (col >= searchIdx && col <= searchIdx + phrase.length) {
          return phrase;
        }
        searchIdx += phrase.length;
      }
    }

    let start = col;
    let end = col;
    if (!isWordChar(line[col])) {
      if (col > 0 && isWordChar(line[col - 1])) {
        start = col - 1;
        end = col - 1;
      } else {
        return null;
      }
    }
    while (start > 0 && isWordChar(line[start - 1])) start--;
    while (end < line.length && isWordChar(line[end])) end++;
    return line.slice(start, end) || null;
  }

  // --- 2. Scope & Symbol Resolution ---
  resolveSymbol(symbols, filePath, word, line = 1) {
    if (!symbols || !word) return null;
    const lower = word.toLowerCase();
    const fileSymbols = symbols.filter(s => (s.File === filePath || s.path === filePath || !filePath) && (s.Name || s.name)?.toLowerCase() === lower);
    if (fileSymbols.length === 0) return null;

    // Prefer declaration before or at the line
    const beforeLine = fileSymbols
      .filter(s => Number(s.Line || s.line || 1) <= Number(line))
      .sort((a, b) => Number(b.Line || b.line || 1) - Number(a.Line || a.line || 1));
    if (beforeLine.length > 0) return beforeLine[0];

    // Otherwise return earliest (e.g. forward-referenced function)
    return fileSymbols.sort((a, b) => Number(a.Line || a.line || 1) - Number(b.Line || b.line || 1))[0];
  }

  // --- 3. Hover Information ---
  getHoverInfo(word, filePath, symbols = [], line = 1) {
    if (!word) return null;
    const lower = word.toLowerCase();

    // 1. Check user-defined symbols first
    const symbol = this.resolveSymbol(symbols, filePath, word, line);
    if (symbol) {
      const kind = (symbol.Kind || symbol.kind || 'symbol').toLowerCase();
      const name = symbol.Name || symbol.name;
      const declLine = Number(symbol.Line || symbol.line) || 1;
      const declPath = symbol.File || symbol.path || filePath || 'current file';

      if (kind === 'function') {
        const rawParams = symbol.Parameters || symbol.parameters || [];
        const paramList = Array.isArray(rawParams) ? rawParams.filter(Boolean) : [];
        const paramStr = paramList.length > 0 ? ' ' + paramList.join(' and ') : '';
        return {
          kind: 'function',
          title: name,
          signature: `to ${name}${paramStr}`,
          description: `User-defined function with ${paramList.length} parameter${paramList.length === 1 ? '' : 's'}.\nDeclared at line ${declLine} in ${declPath}.`,
          parameters: paramList,
          line: declLine,
          path: declPath
        };
      }

      // Known variable / parameter / loop variable / object
      let kindLabel = 'variable';
      if (kind === 'parameter') kindLabel = 'parameter';
      else if (kind.includes('loop')) kindLabel = 'loop variable';
      else if (kind === 'object') kindLabel = 'object';

      return {
        kind: kindLabel,
        title: name,
        signature: `${kindLabel} ${name}`,
        description: `Declared at line ${declLine} in ${declPath}.`,
        line: declLine,
        path: declPath
      };
    }

    // 2. Check authoritative built-in metadata
    const builtin = getBuiltinMetadata(lower);
    if (builtin) {
      return {
        kind: 'builtin',
        title: builtin.name,
        signature: builtin.syntax,
        description: builtin.doc,
        example: builtin.example || null
      };
    }

    return null;
  }

  // --- 4. Go to Definition ---
  getDefinition(word, filePath, line, symbols = [], workspaceSymbols = []) {
    if (!word) return null;
    // Check current file symbols
    const local = this.resolveSymbol(symbols, filePath, word, line);
    if (local) {
      return {
        name: local.Name || local.name,
        kind: local.Kind || local.kind || 'symbol',
        path: local.File || local.path || filePath,
        line: Number(local.Line || local.line) || 1,
        column: Number(local.Column || local.column) || 0
      };
    }

    // Cross-file fallback: search workspace symbols
    if (Array.isArray(workspaceSymbols) && workspaceSymbols.length > 0) {
      const remote = workspaceSymbols.find(s => (s.Name || s.name)?.toLowerCase() === word.toLowerCase() && (s.Kind || s.kind) === 'function');
      if (remote) {
        return {
          name: remote.Name || remote.name,
          kind: remote.Kind || remote.kind || 'function',
          path: remote.File || remote.path,
          line: Number(remote.Line || remote.line) || 1,
          column: Number(remote.Column || remote.column) || 0
        };
      }
    }

    return null;
  }

  // --- 5. Scope-Aware Find References ---
  findReferences(word, filePath, source, symbols = [], astReferences = [], scopes = []) {
    if (!word) return [];
    const lower = word.toLowerCase();

    // If AST references are available from parser analysis, use scope-filtered references
    if (Array.isArray(astReferences) && astReferences.length > 0) {
      const matchingAst = astReferences.filter(r => r.Name?.toLowerCase() === lower);
      if (matchingAst.length > 0) {
        const sourceLines = (source || '').split(/\r?\n/);
        return matchingAst.map(ref => {
          const l = Number(ref.Line) || 1;
          const lineText = sourceLines[l - 1] || '';
          return {
            file: filePath,
            line: l,
            column: Number(ref.Column) || 0,
            text: lineText.trim(),
            isDeclaration: Boolean(ref.IsDeclaration)
          };
        });
      }
    }

    // Safe lexical occurrence fallback (ignores comments and string literals)
    return this.lexicalReferences(source, word, filePath);
  }

  lexicalReferences(source, name, filePath) {
    if (!name || !source) return [];
    const occurrences = [];
    const isWordChar = character => /[A-Za-z0-9_]/.test(character || '');
    const lines = String(source).split(/\r?\n/);

    for (let index = 0; index < lines.length; index++) {
      const line = lines[index];
      let inString = false;
      for (let column = 0; column < line.length;) {
        const char = line[column];
        if (char === '"') {
          inString = !inString;
          column++;
          continue;
        }
        if (!inString && char === '#') break;
        if (!inString && line.startsWith(name, column)) {
          const prev = column > 0 ? line[column - 1] : '';
          const next = column + name.length < line.length ? line[column + name.length] : '';
          if (!isWordChar(prev) && !isWordChar(next)) {
            occurrences.push({
              file: filePath,
              line: index + 1,
              column,
              text: line.trim(),
              isDeclaration: index === 0
            });
            column += name.length;
            continue;
          }
        }
        column++;
      }
    }
    return occurrences;
  }

  // --- 6. Safe Symbol Renaming with Preview Diff ---
  prepareRename(oldName, newName, filePath, source, symbols = [], astReferences = []) {
    if (!oldName) {
      return { ok: false, error: 'No symbol selected for rename.' };
    }
    const trimmedNew = (newName || '').trim();
    if (!trimmedNew) {
      return { ok: false, error: 'New name cannot be empty.' };
    }
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(trimmedNew)) {
      return { ok: false, error: `'${trimmedNew}' is not a valid Otter identifier.` };
    }
    if (oldName === trimmedNew) {
      return { ok: false, error: 'New name must be different from current name.' };
    }

    // Gather reference locations
    const references = this.findReferences(oldName, filePath, source, symbols, astReferences);
    if (references.length === 0) {
      return { ok: false, error: `No references found for '${oldName}'.` };
    }

    const lines = String(source).split(/\r?\n/);
    const edits = [];
    // Group references by line to generate line-level preview diffs
    const byLine = new Map();
    for (const ref of references) {
      if (!byLine.has(ref.line)) byLine.set(ref.line, []);
      byLine.get(ref.line).push(ref);
    }

    for (const [lineNum, refs] of byLine.entries()) {
      const originalLine = lines[lineNum - 1] || '';
      // Replace references from right to left on the line to preserve column offsets
      const sorted = [...refs].sort((a, b) => b.column - a.column);
      let modifiedLine = originalLine;
      for (const r of sorted) {
        const before = modifiedLine.slice(0, r.column);
        const after = modifiedLine.slice(r.column + oldName.length);
        modifiedLine = before + trimmedNew + after;
        edits.push({
          file: r.file,
          line: r.line,
          column: r.column,
          oldText: oldName,
          newText: trimmedNew,
          originalLine,
          modifiedLine
        });
      }
    }

    return {
      ok: true,
      oldName,
      newName: trimmedNew,
      referencesCount: references.length,
      affectedLinesCount: byLine.size,
      edits
    };
  }

  applyRenameToSource(source, oldName, newName, edits = []) {
    const lines = String(source).split(/\r?\n/);
    const byLine = new Map();
    for (const edit of edits) {
      if (!byLine.has(edit.line)) byLine.set(edit.line, []);
      byLine.get(edit.line).push(edit);
    }

    for (const [lineNum, lineEdits] of byLine.entries()) {
      let line = lines[lineNum - 1] || '';
      const sorted = [...lineEdits].sort((a, b) => b.column - a.column);
      for (const edit of sorted) {
        line = line.slice(0, edit.column) + newName + line.slice(edit.column + oldName.length);
      }
      lines[lineNum - 1] = line;
    }
    return lines.join('\n');
  }

  // --- 7. Signature Help ---
  getSignatureHelp(lineUntilCursor, symbols = []) {
    if (!lineUntilCursor) return null;
    const trimmed = lineUntilCursor.trimStart();

    // 1. Check built-in signatures derived from authoritative metadata
    for (const def of this.builtinSignatures) {
      if (def.prefix.test(trimmed)) {
        let activeIndex = 0;
        if (typeof def.customActive === 'function') {
          activeIndex = def.customActive(trimmed);
        } else if (def.splitParam) {
          activeIndex = def.splitParam.test(trimmed) ? 1 : 0;
        }
        return {
          label: def.syntax,
          parameters: def.parameters,
          activeParameter: Math.min(activeIndex, def.parameters.length - 1),
          doc: def.doc
        };
      }
    }

    // 2. Check user-defined function calls (e.g. `to greet name and age` or calling `greet ...`)
    const words = trimmed.split(/\s+/);
    if (words.length > 0) {
      const firstWord = words[0];
      const fnSymbol = symbols.find(s => (s.Name || s.name)?.toLowerCase() === firstWord.toLowerCase() && (s.Kind || s.kind) === 'function');
      if (fnSymbol) {
        const rawParams = fnSymbol.Parameters || fnSymbol.parameters || [];
        const params = Array.isArray(rawParams) && rawParams.length > 0
          ? rawParams.map(p => ({ label: p, doc: `Parameter ${p} for function ${fnSymbol.Name || fnSymbol.name}` }))
          : [{ label: 'args', doc: `Arguments for ${firstWord}` }];
        
        const activeIndex = Math.max(0, Math.min(words.length - 2, params.length - 1));
        const label = `to ${fnSymbol.Name || fnSymbol.name} ${params.map(p => p.label).join(' and ')}`;
        return {
          label,
          parameters: params,
          activeParameter: activeIndex,
          doc: `User function declared at line ${fnSymbol.Line || fnSymbol.line}.`
        };
      }
    }

    return null;
  }

  // --- 8. Semantic Diagnostics (Unused Variables & Unreachable Code) ---
  computeSemanticDiagnostics(source, symbols = [], astReferences = []) {
    const diagnostics = [];
    if (!source) return diagnostics;
    const lines = source.split(/\r?\n/);

    // 1. Unused Variables
    const variables = symbols.filter(s => (s.Kind || s.kind) === 'variable' && Number(s.ScopeId ?? s.scopeId) >= 0);
    for (const v of variables) {
      const name = v.Name || v.name;
      const declLine = Number(v.Line || v.line) || 1;
      // If we have AST references:
      if (Array.isArray(astReferences) && astReferences.length > 0) {
        const reads = astReferences.filter(r => r.Name?.toLowerCase() === name.toLowerCase() && !r.IsDeclaration && Number(r.ScopeId) === Number(v.ScopeId ?? v.scopeId));
        if (reads.length === 0) {
          diagnostics.push({
            severity: 'warning',
            code: 'unused-variable',
            message: `Variable '${name}' is declared but never read.`,
            line: declLine,
            column: Number(v.Column || v.column) || 0,
            symbolName: name
          });
        }
      } else {
        // Lexical check
        const refs = this.lexicalReferences(source, name, '');
        if (refs.length <= 1) {
          diagnostics.push({
            severity: 'warning',
            code: 'unused-variable',
            message: `Variable '${name}' is declared but never read.`,
            line: declLine,
            column: Number(v.Column || v.column) || 0,
            symbolName: name
          });
        }
      }
    }

    // 2. Unreachable Code after unconditional return or stop
    let blockHasReturn = false;
    let returnIndent = -1;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const indent = line.search(/\S/);

      if (trimmed === '.' || (returnIndent >= 0 && indent < returnIndent)) {
        blockHasReturn = false;
        returnIndent = -1;
      }

      if (blockHasReturn && returnIndent >= 0 && indent >= returnIndent && trimmed !== '.') {
        diagnostics.push({
          severity: 'warning',
          code: 'unreachable-code',
          message: 'Unreachable code detected after return or stop.',
          line: i + 1,
          column: indent >= 0 ? indent : 0
        });
      }

      if (trimmed === 'stop' || trimmed.startsWith('return ') || trimmed === 'return') {
        blockHasReturn = true;
        returnIndent = indent;
      }
    }

    return diagnostics;
  }

  // --- 9. Safe Extract-Function Refactoring ---
  prepareExtractFunction(selectedText, fnName, currentCode, cursorLine = 1) {
    const trimmedFn = (fnName || '').trim();
    if (!trimmedFn) {
      return { ok: false, error: 'Function name cannot be empty.' };
    }
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(trimmedFn)) {
      return { ok: false, error: `'${trimmedFn}' is not a valid Otter identifier.` };
    }
    if (!selectedText || !selectedText.trim()) {
      return { ok: false, error: 'Select one or more statements to extract.' };
    }

    const code = currentCode || '';
    const selIdx = code.indexOf(selectedText);
    if (selIdx === -1) {
      return { ok: false, error: 'Selected text could not be located in document.' };
    }

    const selectedLines = selectedText.split(/\r?\n/).filter(l => l.trim().length > 0);
    const indentedBody = selectedLines.map(l => '    ' + l.trim()).join('\n');
    const fnDef = `to ${trimmedFn}\n${indentedBody}\n.\n\n`;

    // 1. Replace selection in place with the function call
    const beforeSel = code.slice(0, selIdx);
    const afterSel = code.slice(selIdx + selectedText.length);
    const replacedCode = beforeSel + trimmedFn + afterSel;

    // 2. Find the top-level insertion point BEFORE the calling site
    // (Otter enforces sequential execution with no function hoisting)
    const codeLines = replacedCode.split(/\r?\n/);
    const callLineIdx = beforeSel.split(/\r?\n/).length - 1;

    let insertLine = 0;
    for (let i = callLineIdx; i >= 0; i--) {
      const l = codeLines[i];
      if (l && l.search(/\S/) === 0 && !l.trim().startsWith('#') && !l.trim().startsWith('.')) {
        insertLine = i;
        break;
      }
    }

    const newCodeLines = [...codeLines];
    const defLines = [`to ${trimmedFn}`, ...selectedLines.map(l => '    ' + l.trim()), '.', ''];
    newCodeLines.splice(insertLine, 0, ...defLines);

    return {
      ok: true,
      fnName: trimmedFn,
      fnDef,
      newCode: newCodeLines.join('\n')
    };
  }

  // Extract whole lines startLine..endLine (1-based) into `to fnName`. The
  // body keeps its relative indentation (nested blocks stay nested), the
  // call replaces the lines at their indentation, and the definition goes
  // before the top-level statement that contains the call (Otter functions
  // must be defined before they run).
  prepareExtractLines(code, startLine, endLine, fnName) {
    const name = (fnName || '').trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) {
      return { ok: false, error: `'${name}' is not a valid Otter identifier.` };
    }
    const eol = String(code).includes('\r\n') ? '\r\n' : '\n';
    const lines = String(code).split(/\r?\n/);
    const first = Math.max(1, Math.min(startLine, endLine));
    const last = Math.min(lines.length, Math.max(startLine, endLine));
    const selected = lines.slice(first - 1, last);
    if (!selected.some(l => l.trim())) {
      return { ok: false, error: 'Select one or more statements to extract.' };
    }
    const indentOf = (l) => l.match(/^\s*/)[0].length;
    const base = Math.min(...selected.filter(l => l.trim()).map(indentOf));
    // Otter blocks are indentation (a period may close one explicitly).
    // Only whole statements can move: the selection must start at its own
    // outermost level, must not start with the tail of an earlier block, and
    // must not leave the body of a selected block behind.
    const firstLine = selected.find(l => l.trim());
    if (indentOf(firstLine) !== base) {
      return { ok: false, error: 'The selection starts inside a block. Select whole statements.' };
    }
    if (/^(\.|otherwise\b)/.test(firstLine.trim())) {
      return { ok: false, error: 'The selection starts with the end of an earlier block. Select whole statements.' };
    }
    const nextLine = lines.slice(last).find(l => l.trim());
    if (nextLine !== undefined && indentOf(nextLine) > base) {
      return { ok: false, error: 'The selection leaves part of a block behind. Select the whole block.' };
    }

    // Inside a function, its parameters and earlier locals are not visible to
    // a new function (Otter functions have their own scope): pass the ones
    // the lines use as parameters. Assigning to one could not flow back, so
    // that is refused.
    const params = [];
    let minIndent = base;
    for (let i = first - 2; i >= 0 && minIndent > 0; i--) {
      const l = lines[i];
      if (!l.trim() || indentOf(l) >= minIndent) continue;
      minIndent = indentOf(l);
      const fn = l.trim().match(/^to\s+[A-Za-z_]\w*\s*(.*)$/);
      if (!fn) continue;
      const visible = new Set(fn[1].split(/\s+and\s+/).map(p => p.trim()).filter(p => /^[A-Za-z_]\w*$/.test(p)));
      for (let j = i + 1; j < first - 1; j++) {
        const assigned = lines[j].match(/^\s*([A-Za-z_]\w*)\s+is\b/) || lines[j].match(/\bmake\s+([A-Za-z_]\w*)\s*$/);
        if (assigned) visible.add(assigned[1]);
      }
      const code = selected.map(l => l.replace(/"[^"]*"/g, '""').replace(/#.*$/, '')).join('\n');
      for (const v of visible) {
        if (new RegExp(`\\b${v}\\b`).test(code)) params.push(v);
      }
      const reassigned = params.find(p => selected.some(l => new RegExp(`^\\s*${p}\\s+is\\b|\\bmake\\s+${p}\\s*$`).test(l)));
      if (reassigned) {
        return { ok: false, error: `The selection changes '${reassigned}', which belongs to the function around it; a new function could not change it there.` };
      }
      break;
    }

    // A variable the lines create is local to the new function: code after
    // the selection could no longer see it.
    const created = new Set();
    for (const l of selected) {
      const m = l.match(/^\s*([A-Za-z_]\w*)\s+is\b/) || l.match(/\bmake\s+([A-Za-z_]\w*)\s*$/);
      if (m) created.add(m[1]);
    }
    const after = lines.slice(last).map(l => l.replace(/"[^"]*"/g, '""').replace(/#.*$/, '')).join('\n');
    const leaked = [...created].find(v => new RegExp(`\\b${v}\\b`).test(after));
    if (leaked) {
      return { ok: false, error: `'${leaked}' is set in the selection and used after it; inside a new function it would no longer be visible there.` };
    }

    const body = selected.map(l => (l.trim() ? '    ' + l.slice(base) : ''));
    const args = params.length ? ' ' + params.join(' and ') : '';
    const call = ' '.repeat(base) + name + args;
    const out = [...lines.slice(0, first - 1), call, ...lines.slice(last)];

    // The top-level statement containing the call: scan up for column 0.
    let insertAt = first - 1;
    for (let i = first - 1; i >= 0; i--) {
      const l = out[i];
      if (l && indentOf(l) === 0 && l.trim() && !l.trim().startsWith('#') && l.trim() !== '.') { insertAt = i; break; }
    }
    out.splice(insertAt, 0, `to ${name}${args}`, ...body, '.', '');
    return { ok: true, fnName: name, parameters: params, newCode: out.join(eol) };
  }

  // --- 10. Code Actions & Quick Fixes ---
  getQuickFixes(diagnostic, sourceCode) {
    const fixes = [];
    if (!diagnostic || !diagnostic.message) return fixes;
    const msg = diagnostic.message.toLowerCase();
    const line = Number(diagnostic.line) || 1;
    const lines = (sourceCode || '').split(/\r?\n/);

    // 1. Missing block end '.'
    if (msg.includes('expected "."') || (msg.includes('missing') && msg.includes('.'))) {
      fixes.push({
        title: "Add missing block end '.'",
        kind: 'quickfix',
        apply: () => {
          const target = Math.max(0, Math.min(line - 1, lines.length));
          lines.splice(target + 1, 0, '.');
          return lines.join('\n');
        }
      });
    }

    // 2. Fix block indentation
    if (msg.includes('indent') || msg.includes('indentation')) {
      fixes.push({
        title: 'Fix line indentation (4 spaces)',
        kind: 'quickfix',
        apply: () => {
          const target = Math.max(0, Math.min(line - 1, lines.length - 1));
          lines[target] = '    ' + lines[target].trim();
          return lines.join('\n');
        }
      });
    }

    // 3. Undeclared variables: Do NOT automatically generate edits (e.g. 'name is gone')
    // Intent and value cannot be safely inferred; provide explanatory guidance only without source mutation.

    // 4. Remove unused variable declaration
    if (diagnostic.code === 'unused-variable' && diagnostic.symbolName) {
      fixes.push({
        title: `Remove unused variable '${diagnostic.symbolName}'`,
        kind: 'quickfix',
        apply: () => {
          const target = Math.max(0, Math.min(line - 1, lines.length - 1));
          lines.splice(target, 1);
          return lines.join('\n');
        }
      });
    }

    return fixes;
  }

  // --- 11. Symbol Outline Filtering ---
  filterOutlineSymbols(symbols, query) {
    if (!Array.isArray(symbols)) return [];
    const q = (query || '').trim().toLowerCase();
    if (!q) return symbols;
    return symbols.filter(s => {
      const name = (s.Name || s.name || '').toLowerCase();
      const kind = (s.Kind || s.kind || '').toLowerCase();
      return name.includes(q) || kind.includes(q);
    });
  }

  // --- 12. Workspace Symbol Search ---
  searchWorkspaceSymbols(workspaceSymbols, query) {
    if (!Array.isArray(workspaceSymbols)) return [];
    const q = (query || '').trim().toLowerCase();
    const symbols = workspaceSymbols.filter(s => {
      if (!q) return true;
      const name = (s.Name || s.name || '').toLowerCase();
      const file = (s.File || s.file || '').toLowerCase();
      const kind = (s.Kind || s.kind || '').toLowerCase();
      return name.includes(q) || file.includes(q) || kind.includes(q);
    });

    return symbols.map(s => {
      const kind = (s.Kind || s.kind || 'symbol').toLowerCase();
      const icon = kind === 'function' ? 'ƒ' : (kind === 'ui' ? '⊞' : (kind === 'object' ? '◇' : 'v'));
      const filePath = s.File || s.file || '';
      const fileName = filePath.split(/[\\/]/).pop() || 'file.ot';
      return {
        type: 'symbol',
        label: s.Name || s.name,
        detail: `${fileName} (${kind})`,
        path: filePath,
        line: Number(s.Line || s.line) || 1,
        column: Number(s.Column || s.column) || 0,
        icon
      };
    });
  }
}

export const otterLanguageService = new OtterLanguageService();

// Standalone exports for modular consumption and testing
export const filterOutlineSymbols = (symbols, query) => otterLanguageService.filterOutlineSymbols(symbols, query);
export const searchWorkspaceSymbols = (workspaceSymbols, query) => otterLanguageService.searchWorkspaceSymbols(workspaceSymbols, query);
export const computeSemanticDiagnostics = (source, symbols, astReferences) => otterLanguageService.computeSemanticDiagnostics(source, symbols, astReferences);
export const prepareExtractFunction = (selectedText, fnName, currentCode, cursorLine) => otterLanguageService.prepareExtractFunction(selectedText, fnName, currentCode, cursorLine);
export const getQuickFixes = (diagnostic, sourceCode) => otterLanguageService.getQuickFixes(diagnostic, sourceCode);

