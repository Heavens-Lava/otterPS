// refactoring-engine.js - Comprehensive Refactoring Engine for Otter Studio
import fs from 'node:fs';
import path from 'node:path';

/**
 * Atomic Multi-File Transaction Manager for Refactorings
 */
export class TransactionManager {
  constructor() {
    this.undoStack = [];
    this.redoStack = [];
  }

  createTransaction(id, description, fileSnapshots = []) {
    return {
      id: id || `tx-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      description: description || 'Refactoring Transaction',
      timestamp: new Date().toISOString(),
      fileSnapshots: fileSnapshots.map(s => ({
        filePath: s.filePath,
        originalContent: s.originalContent,
        newContent: s.newContent
      }))
    };
  }

  applyTransaction(tx) {
    for (const snap of tx.fileSnapshots) {
      const dir = path.dirname(snap.filePath);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(snap.filePath, snap.newContent, 'utf8');
    }
    this.undoStack.push(tx);
    this.redoStack = [];
    return { ok: true, transactionId: tx.id };
  }

  undo() {
    if (this.undoStack.length === 0) {
      return { ok: false, error: 'Nothing to undo' };
    }
    const tx = this.undoStack.pop();
    for (const snap of tx.fileSnapshots) {
      if (snap.originalContent === null) {
        if (fs.existsSync(snap.filePath)) fs.unlinkSync(snap.filePath);
      } else {
        const dir = path.dirname(snap.filePath);
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(snap.filePath, snap.originalContent, 'utf8');
      }
    }
    this.redoStack.push(tx);
    return { ok: true, undoneTransactionId: tx.id, description: tx.description };
  }

  redo() {
    if (this.redoStack.length === 0) {
      return { ok: false, error: 'Nothing to redo' };
    }
    const tx = this.redoStack.pop();
    for (const snap of tx.fileSnapshots) {
      const dir = path.dirname(snap.filePath);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(snap.filePath, snap.newContent, 'utf8');
    }
    this.undoStack.push(tx);
    return { ok: true, redoneTransactionId: tx.id, description: tx.description };
  }

  getHistory() {
    return {
      canUndo: this.undoStack.length > 0,
      canRedo: this.redoStack.length > 0,
      undoCount: this.undoStack.length,
      redoCount: this.redoStack.length,
      lastUndo: this.undoStack.length > 0 ? this.undoStack[this.undoStack.length - 1].description : null,
      lastRedo: this.redoStack.length > 0 ? this.redoStack[this.redoStack.length - 1].description : null
    };
  }
}

/**
 * Core Refactoring Engine
 */
export class RefactoringEngine {
  constructor(options = {}) {
    this.transactionManager = options.transactionManager || new TransactionManager();
  }

  // --- 1. Rename Symbol (local, function, component, file, module) ---
  renameSymbol({ projectRoot, files = [], oldName, newName, kind = 'symbol' }) {
    if (!oldName || !newName) {
      return { ok: false, error: 'Both oldName and newName are required.' };
    }
    if (oldName === newName) {
      return { ok: false, error: 'New name must be different from old name.' };
    }
    if (!/^[A-Za-z_][A-Za-z0-9_-]*$/.test(newName)) {
      return { ok: false, error: `'${newName}' is not a valid identifier.` };
    }

    const edits = [];
    const snapshots = [];
    const wordRegex = new RegExp(`\\b${escapeRegExp(oldName)}\\b`, 'g');

    for (const file of files) {
      const fullPath = path.isAbsolute(file) ? file : path.resolve(projectRoot || '.', file);
      if (!fs.existsSync(fullPath)) continue;

      const originalContent = fs.readFileSync(fullPath, 'utf8');
      const lines = originalContent.split(/\r?\n/);
      let fileModified = false;
      const fileEdits = [];

      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (wordRegex.test(line)) {
          const newLine = line.replace(wordRegex, newName);
          fileEdits.push({
            file: fullPath,
            line: i + 1,
            oldLine: line,
            newLine
          });
          lines[i] = newLine;
          fileModified = true;
        }
      }

      if (fileModified) {
        const newContent = lines.join('\n');
        edits.push(...fileEdits);
        snapshots.push({ filePath: fullPath, originalContent, newContent });
      }
    }

    const preview = this.generatePreview(edits);

    return {
      ok: true,
      kind,
      oldName,
      newName,
      affectedFiles: snapshots.map(s => s.filePath),
      editsCount: edits.length,
      edits,
      preview,
      snapshots
    };
  }

  // --- 2. Extract Variable ---
  extractVariable({ code, selection, varName }) {
    const trimmedVar = (varName || '').trim();
    if (!trimmedVar) return { ok: false, error: 'Variable name cannot be empty.' };
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(trimmedVar)) {
      return { ok: false, error: `'${trimmedVar}' is not a valid identifier.` };
    }
    if (!selection || !selection.trim()) {
      return { ok: false, error: 'Selection cannot be empty.' };
    }

    const cleanCode = code || '';
    const selIdx = cleanCode.indexOf(selection);
    if (selIdx === -1) {
      return { ok: false, error: 'Selection not found in document.' };
    }

    // Find start of statement line
    const beforeSel = cleanCode.slice(0, selIdx);
    const lineStartIdx = beforeSel.lastIndexOf('\n') + 1;
    const currentLine = beforeSel.slice(lineStartIdx);
    const indentMatch = currentLine.match(/^\s*/);
    const indent = indentMatch ? indentMatch[0] : '';

    const varDecl = `${indent}make ${trimmedVar} is ${selection.trim()}\n`;
    const replacedCode = cleanCode.slice(0, selIdx) + trimmedVar + cleanCode.slice(selIdx + selection.length);

    // Insert declaration right before the line
    const finalCode = replacedCode.slice(0, lineStartIdx) + varDecl + replacedCode.slice(lineStartIdx);

    return {
      ok: true,
      varName: trimmedVar,
      newCode: finalCode,
      insertedDeclaration: varDecl.trim()
    };
  }

  // --- 3. Extract Function ---
  extractFunction({ code, selection, fnName }) {
    const trimmedFn = (fnName || '').trim();
    if (!trimmedFn) return { ok: false, error: 'Function name cannot be empty.' };
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(trimmedFn)) {
      return { ok: false, error: `'${trimmedFn}' is not a valid identifier.` };
    }
    if (!selection || !selection.trim()) {
      return { ok: false, error: 'Selection cannot be empty.' };
    }

    const cleanCode = code || '';
    const selIdx = cleanCode.indexOf(selection);
    if (selIdx === -1) {
      return { ok: false, error: 'Selection not found in document.' };
    }

    const selectedLines = selection.split(/\r?\n/).filter(l => l.trim().length > 0);
    const indentedBody = selectedLines.map(l => '    ' + l.trim()).join('\n');
    const fnDef = `to ${trimmedFn}\n${indentedBody}\n.\n\n`;

    // Replace selection in place with function call
    const beforeSel = cleanCode.slice(0, selIdx);
    const afterSel = cleanCode.slice(selIdx + selection.length);
    const replacedCode = beforeSel + trimmedFn + afterSel;

    // Find insertion point before caller (Otter has no function hoisting)
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

  // --- 4. Inline Variable ---
  inlineVariable({ code, varName }) {
    const trimmedVar = (varName || '').trim();
    if (!trimmedVar) return { ok: false, error: 'Variable name required.' };

    const lines = (code || '').split(/\r?\n/);
    let declLineIndex = -1;
    let expr = null;

    // Find assignment: make <var> is <expr> or <var> is <expr>
    const declPattern = new RegExp(`^\\s*(?:make\\s+)?${escapeRegExp(trimmedVar)}\\s+is\\s+(.+)$`);

    for (let i = 0; i < lines.length; i++) {
      const match = lines[i].match(declPattern);
      if (match) {
        declLineIndex = i;
        expr = match[1].trim();
        break;
      }
    }

    if (declLineIndex === -1 || expr === null) {
      return { ok: false, error: `Declaration for variable '${trimmedVar}' was not found.` };
    }

    // Replace occurrences after declLineIndex
    let inlinedCount = 0;
    const usagePattern = new RegExp(`\\b${escapeRegExp(trimmedVar)}\\b`, 'g');
    const newLines = [];

    for (let i = 0; i < lines.length; i++) {
      if (i === declLineIndex) {
        continue; // remove declaration line
      }
      const line = lines[i];
      if (i > declLineIndex && usagePattern.test(line)) {
        newLines.push(line.replace(usagePattern, expr));
        inlinedCount++;
      } else {
        newLines.push(line);
      }
    }

    return {
      ok: true,
      varName: trimmedVar,
      inlinedCount,
      expr,
      newCode: newLines.join('\n')
    };
  }

  // --- 5. Move Symbol / Module ---
  moveSymbol({ sourceFile, targetFile, symbolName }) {
    if (!fs.existsSync(sourceFile)) {
      return { ok: false, error: `Source file '${sourceFile}' not found.` };
    }

    const sourceContent = fs.readFileSync(sourceFile, 'utf8');
    const fnPattern = new RegExp(`(^|\\n)(to\\s+${escapeRegExp(symbolName)}[\\s\\S]*?\\n\\.\\s*(\\n|$))`);
    const match = sourceContent.match(fnPattern);

    if (!match) {
      return { ok: false, error: `Symbol '${symbolName}' definition not found in source file.` };
    }

    const symbolBlock = match[2].trim();
    const newSourceContent = sourceContent.replace(match[2], '').trim() + '\n';

    let targetContent = '';
    if (fs.existsSync(targetFile)) {
      targetContent = fs.readFileSync(targetFile, 'utf8');
    }
    const newTargetContent = (targetContent.trim() ? targetContent.trim() + '\n\n' : '') + symbolBlock + '\n';

    return {
      ok: true,
      symbolName,
      sourceFile,
      targetFile,
      snapshots: [
        { filePath: sourceFile, originalContent: sourceContent, newContent: newSourceContent },
        { filePath: targetFile, originalContent: targetContent, newContent: newTargetContent }
      ]
    };
  }

  // --- 6. Safe Delete ---
  safeDelete({ projectRoot, files = [], symbolName, targetFile = null }) {
    if (!symbolName && !targetFile) {
      return { ok: false, error: 'Must provide symbolName or targetFile to safely delete.' };
    }

    const references = [];
    const searchToken = symbolName || path.basename(targetFile, path.extname(targetFile));
    const tokenRegex = new RegExp(`\\b${escapeRegExp(searchToken)}\\b`);

    for (const f of files) {
      const fullPath = path.isAbsolute(f) ? f : path.resolve(projectRoot || '.', f);
      if (!fs.existsSync(fullPath)) continue;
      if (targetFile && path.resolve(fullPath) === path.resolve(targetFile)) continue;

      const lines = fs.readFileSync(fullPath, 'utf8').split(/\r?\n/);
      for (let i = 0; i < lines.length; i++) {
        if (tokenRegex.test(lines[i])) {
          references.push({
            file: fullPath,
            line: i + 1,
            text: lines[i].trim()
          });
        }
      }
    }

    const isSafe = references.length === 0;
    return {
      ok: true,
      safe: isSafe,
      searchToken,
      referenceCount: references.length,
      references,
      warning: isSafe ? null : `Symbol '${searchToken}' is still referenced in ${references.length} locations.`
    };
  }

  // --- 7. Organize Modules / Imports ---
  organizeModules({ code }) {
    const lines = (code || '').split(/\r?\n/);
    const useLines = [];
    const otherLines = [];
    let sawNonUse = false;

    for (const line of lines) {
      const trimmed = line.trim();
      if (!sawNonUse && (trimmed.startsWith('use ') || trimmed === 'use')) {
        useLines.push(trimmed);
      } else if (!sawNonUse && (trimmed.startsWith('#') || trimmed.length === 0)) {
        otherLines.push(line);
      } else {
        sawNonUse = true;
        otherLines.push(line);
      }
    }

    // Deduplicate and categorize
    const uniqueUses = Array.from(new Set(useLines));
    const stdUses = [];
    const relUses = [];
    const pkgUses = [];

    for (const u of uniqueUses) {
      if (u.includes('./') || u.includes('../')) {
        relUses.push(u);
      } else if (/^use\s+["']?[A-Za-z0-9_-]+["']?$/.test(u)) {
        stdUses.push(u);
      } else {
        pkgUses.push(u);
      }
    }

    stdUses.sort();
    relUses.sort();
    pkgUses.sort();

    const organizedUses = [...stdUses, ...pkgUses, ...relUses];
    const header = organizedUses.length > 0 ? organizedUses.join('\n') + '\n\n' : '';
    const body = otherLines.join('\n').trimStart();

    return {
      ok: true,
      organizedCount: organizedUses.length,
      newCode: header + body
    };
  }

  // --- 8. Preview Changes ---
  generatePreview(edits = []) {
    const fileGroups = new Map();
    for (const edit of edits) {
      if (!fileGroups.has(edit.file)) fileGroups.set(edit.file, []);
      fileGroups.get(edit.file).push(edit);
    }

    const previews = [];
    for (const [file, fEdits] of fileGroups.entries()) {
      previews.push({
        file,
        changeCount: fEdits.length,
        diff: fEdits.map(e => `@@ Line ${e.line} @@\n- ${e.oldLine}\n+ ${e.newLine}`).join('\n\n')
      });
    }
    return previews;
  }

  // --- 9. Cross-Project Refactoring ---
  crossProjectRefactor({ solutionProjects = [], oldName, newName, kind = 'symbol' }) {
    const allFiles = [];
    for (const proj of solutionProjects) {
      const projDir = proj.dir || proj;
      if (fs.existsSync(projDir)) {
        const findOtFiles = (dir) => {
          for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
            const p = path.join(dir, item.name);
            if (item.isDirectory() && !item.name.startsWith('.') && item.name !== 'node_modules') {
              findOtFiles(p);
            } else if (item.isFile() && item.name.endsWith('.ot')) {
              allFiles.push(p);
            }
          }
        };
        findOtFiles(projDir);
      }
    }

    return this.renameSymbol({
      projectRoot: '.',
      files: allFiles,
      oldName,
      newName,
      kind
    });
  }
}

function escapeRegExp(string) {
  return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export const refactoringEngine = new RefactoringEngine();
