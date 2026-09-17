// host-translator.js - Host Error Translation & Otter Runtime Stack Trace Foundation
// Part of Section 10: Diagnostics Experience

import { DiagnosticCodes, resolveDiagnosticCode } from './diagnostic-codes.js';

/**
 * Translates raw host errors (PowerShell, Node, JavaScript, OS) into clean, human-readable
 * Otter diagnostics while preserving technical details in hostDetails.
 */
export function translateHostError(rawErrorText = '', context = {}) {
  const text = String(rawErrorText || '').trim();
  if (!text) {
    return null;
  }

  // Check if text is ALREADY a native Otter error block:
  // e.g.:
  // Otter Runtime Error
  // Line 1:
  //     say 10 divided by 0
  //
  // Cannot divide number by zero.
  //
  // Try:
  //     if file "foo.txt" exists
  if (text.includes('Otter Runtime Error') || text.includes('Otter Syntax Error')) {
    const isSyntax = text.includes('Otter Syntax Error');
    const stage = isSyntax ? 'parser' : 'runtime';

    const lineMatch = text.match(/Line\s+(\d+):/i);
    const line = lineMatch ? parseInt(lineMatch[1], 10) : (context.line || 1);

    const tryMatch = text.match(/Try:\s*\r?\n\s*([^\r\n]+)/i);
    const suggestion = tryMatch ? tryMatch[1].trim() : null;

    let message = 'Otter execution error';
    const lines = text.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
    const contentLines = lines.filter(l =>
      !l.startsWith('Otter Runtime Error') &&
      !l.startsWith('Otter Syntax Error') &&
      !/^Line\s+\d+:?$/i.test(l) &&
      l !== 'Try:' &&
      l !== suggestion
    );

    if (contentLines.length >= 2) {
      message = contentLines[1];
    } else if (contentLines.length === 1) {
      message = contentLines[0];
    }

    const code = resolveDiagnosticCode(message, stage, context);

    return {
      isOtter: true,
      source: 'otter',
      category: stage === 'parser' ? 'syntax' : 'runtime',
      code,
      message,
      suggestion,
      line,
      column: context.column || 1,
      hostDetails: null,
      stack: extractOtterStackFrames(text, context.file || 'main.ot', line)
    };
  }

  // 1. PowerShell: Command / Program Not Found
  // e.g. "The term 'xyz' is not recognized as the name of a cmdlet, function, script file, or operable program."
  const psCmdMatch = text.match(/The term '([^']+)' is not recognized as the name of a cmdlet, function, script file/i);
  if (psCmdMatch) {
    const commandName = psCmdMatch[1];
    return {
      isOtter: false,
      source: 'host',
      category: 'provider',
      code: DiagnosticCodes.COMMAND_EXECUTION_FAILURE,
      message: `I do not know a command called '${commandName}'.`,
      suggestion: 'Check the spelling of the command or verify that the external tool is installed.',
      line: extractLineNumber(text) || context.line || 1,
      column: extractColumnNumber(text) || context.column || 1,
      hostDetails: text,
      stack: extractOtterStackFrames(text, context.file, context.line)
    };
  }

  // 2. PowerShell / OS: File or Path Not Found
  // e.g. "Cannot find path 'C:\...' because it does not exist."
  const psPathMatch = text.match(/Cannot find (?:path|file) '([^']+)' because it does not exist/i) ||
                      text.match(/ENOENT: no such file or directory, (?:open|stat) '([^']+)'/i);
  if (psPathMatch) {
    const filePath = psPathMatch[1];
    return {
      isOtter: false,
      source: 'host',
      category: 'provider',
      code: DiagnosticCodes.FILE_NOT_FOUND,
      message: `I could not find a file called '${filePath}'.`,
      suggestion: `Check that the file exists before reading it.`,
      line: extractLineNumber(text) || context.line || 1,
      column: extractColumnNumber(text) || context.column || 1,
      hostDetails: text,
      stack: extractOtterStackFrames(text, context.file, context.line)
    };
  }

  // 3. PowerShell / OS: Access / Permission Denied / File Locked
  if (text.includes('UnauthorizedAccessException') || text.includes('Access to the path') || text.includes('EACCES')) {
    const targetMatch = text.match(/path '([^']+)' is denied/i) || text.match(/'([^']+)'/);
    const target = targetMatch ? targetMatch[1] : 'the file or folder';
    return {
      isOtter: false,
      source: 'host',
      category: 'provider',
      code: DiagnosticCodes.FILE_ACCESS_DENIED,
      message: `I could not access '${target}'. Permission was denied.`,
      suggestion: 'Check file permissions or verify that the file is not opened and locked by another application.',
      line: extractLineNumber(text) || context.line || 1,
      column: extractColumnNumber(text) || context.column || 1,
      hostDetails: text,
      stack: extractOtterStackFrames(text, context.file, context.line)
    };
  }

  // 4. Arithmetic: Division by zero
  if (text.includes('DivideByZeroException') || text.includes('division by zero') || text.includes('Attempted to divide by zero')) {
    return {
      isOtter: false,
      source: 'runtime',
      category: 'type',
      code: DiagnosticCodes.DIVISION_BY_ZERO,
      message: 'Cannot divide number by zero.',
      suggestion: 'Check that the divisor is not zero before dividing.',
      line: extractLineNumber(text) || context.line || 1,
      column: extractColumnNumber(text) || context.column || 1,
      hostDetails: text,
      stack: extractOtterStackFrames(text, context.file, context.line)
    };
  }

  // 5. JavaScript / Browser: ReferenceError (undefined variable)
  const jsRefMatch = text.match(/ReferenceError: (\w+) is not defined/i);
  if (jsRefMatch) {
    const varName = jsRefMatch[1];
    return {
      isOtter: false,
      source: 'host',
      category: 'scope',
      code: DiagnosticCodes.UNDECLARED_VARIABLE,
      message: `I don't know a variable called '${varName}'.`,
      suggestion: `Assign a value to '${varName}' before using it (e.g. '${varName} is ...').`,
      line: extractLineNumber(text) || context.line || 1,
      column: extractColumnNumber(text) || context.column || 1,
      hostDetails: text,
      stack: extractOtterStackFrames(text, context.file, context.line)
    };
  }

  // 6. JavaScript / Browser: TypeError (property on null/undefined)
  const jsTypeMatch = text.match(/TypeError: Cannot read propert(?:y|ies) of (?:null|undefined) \(reading '([^']+)'\)/i);
  if (jsTypeMatch) {
    const propName = jsTypeMatch[1];
    return {
      isOtter: false,
      source: 'host',
      category: 'type',
      code: DiagnosticCodes.PROPERTY_NOT_FOUND,
      message: `I could not read property '${propName}' because the target value has gone.`,
      suggestion: 'Verify that the target object is not gone before accessing its properties.',
      line: extractLineNumber(text) || context.line || 1,
      column: extractColumnNumber(text) || context.column || 1,
      hostDetails: text,
      stack: extractOtterStackFrames(text, context.file, context.line)
    };
  }

  // 7. General Host Failure fallback
  const firstLine = text.split('\n')[0].trim();
  return {
    isOtter: false,
    source: 'host',
    category: 'provider',
    code: DiagnosticCodes.COMMAND_EXECUTION_FAILURE,
    message: firstLine.replace(/^(?:System\.[A-Za-z]+\.)?[A-Za-z]+Exception:\s*/i, ''),
    suggestion: 'Review the technical host details for troubleshooting.',
    line: extractLineNumber(text) || context.line || 1,
    column: extractColumnNumber(text) || context.column || 1,
    hostDetails: text,
    stack: extractOtterStackFrames(text, context.file, context.line)
  };
}

/**
 * Extracts line number from error text.
 */
function extractLineNumber(text) {
  const lineMatch = text.match(/Line\s*(\d+)/i) ||
                    text.match(/line:(\d+)/i) ||
                    text.match(/:(\d+):\d+/);
  return lineMatch ? parseInt(lineMatch[1], 10) : null;
}

/**
 * Extracts column number from error text.
 */
function extractColumnNumber(text) {
  const colMatch = text.match(/char(?:acter)?\s*(\d+)/i) ||
                   text.match(/column\s*(\d+)/i) ||
                   text.match(/:\d+:(\d+)/);
  return colMatch ? parseInt(colMatch[1], 10) : null;
}

/**
 * Extracts and translates runtime stack frames into clean Otter terms:
 * [{ functionName, file, line, column }]
 * Excludes internal PowerShell scripts, Node internals, and compiled JavaScript runtime glue.
 */
export function extractOtterStackFrames(errorText = '', defaultFile = 'main.ot', defaultLine = 1) {
  const frames = [];
  const lines = errorText.split('\n');

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;

    // 1. Matches Otter syntax: "in function greet at file.ot:12:4" or "at file.ot line 12"
    const otterFrameMatch = line.match(/(?:in (?:function\s+)?([A-Za-z0-9_]+)\s+)?at\s+([A-Za-z0-9_\-\.\/\\]+\.ot)(?::(\d+)(?::(\d+))?|\s+line\s+(\d+))/i);
    if (otterFrameMatch) {
      const functionName = otterFrameMatch[1] || '<script>';
      const file = otterFrameMatch[2];
      const lineNum = parseInt(otterFrameMatch[3] || otterFrameMatch[5], 10);
      const colNum = otterFrameMatch[4] ? parseInt(otterFrameMatch[4], 10) : 1;
      frames.push({ functionName, file, line: lineNum, column: colNum });
      continue;
    }

    // 2. Matches generic "Line X:" header
    const lineHeaderMatch = line.match(/^Line\s+(\d+):/i);
    if (lineHeaderMatch && frames.length === 0) {
      frames.push({
        functionName: '<script>',
        file: defaultFile,
        line: parseInt(lineHeaderMatch[1], 10),
        column: 1
      });
    }
  }

  if (frames.length === 0 && defaultLine) {
    frames.push({
      functionName: '<script>',
      file: defaultFile,
      line: defaultLine,
      column: 1
    });
  }

  return frames;
}

/**
 * Formats Otter stack frames for user-facing display.
 */
export function formatOtterStackTrace(stackFrames = []) {
  if (!Array.isArray(stackFrames) || stackFrames.length === 0) {
    return '';
  }

  return stackFrames.map(frame => {
    const fn = frame.functionName && frame.functionName !== '<script>' ? `in ${frame.functionName} ` : '';
    const col = frame.column && frame.column > 1 ? `:${frame.column}` : '';
    return `    at ${fn}${frame.file}:${frame.line}${col}`;
  }).join('\n');
}
