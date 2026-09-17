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
}

export const otterLanguageService = new OtterLanguageService();
