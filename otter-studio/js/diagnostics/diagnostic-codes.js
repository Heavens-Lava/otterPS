// diagnostic-codes.js - Stable Otter Diagnostic Codes, Categories, and Registry
// Part of Section 10: Diagnostics Experience

export const DiagnosticCodes = {
  // OT1xxx - Lexical
  INDENTATION_JUMP: 'OT1001',
  INVALID_CHARACTER: 'OT1002',
  PERIOD_PROPERTY_ACCESS: 'OT1003',
  EQUALS_ASSIGNMENT: 'OT1004',
  UNTERMINATED_STRING: 'OT1005',

  // OT2xxx - Syntax / Parser
  MISSING_BLOCK_TERMINATOR: 'OT2001',
  UNEXPECTED_TOKEN: 'OT2002',
  UNEXPECTED_EOF: 'OT2003',
  INVALID_ASSIGNMENT: 'OT2004',
  MISSING_CONDITION: 'OT2005',
  INVALID_FUNCTION_DEF: 'OT2006',
  EXTRANEOUS_BLOCK_TERMINATOR: 'OT2007',

  // OT3xxx - Name / Scope
  UNDECLARED_VARIABLE: 'OT3001',
  UNKNOWN_FUNCTION: 'OT3002',
  UNUSED_DECLARATION: 'OT3003',
  UNREACHABLE_CODE: 'OT3004',
  FUNCTION_HOISTING_VIOLATION: 'OT3005',

  // OT4xxx - Type / Value / Operation
  TYPE_MISMATCH: 'OT4001',
  PROPERTY_NOT_FOUND: 'OT4002',
  DIVISION_BY_ZERO: 'OT4003',
  COLLECTION_OUT_OF_RANGE: 'OT4004',

  // OT5xxx - Runtime
  PROGRAM_FAILURE: 'OT5001',
  GONE_ACCESS: 'OT5002',
  CALL_STACK_OVERFLOW: 'OT5003',
  ARGUMENT_COUNT_MISMATCH: 'OT5004',

  // OT6xxx - Filesystem / System / Provider
  FILE_NOT_FOUND: 'OT6001',
  FOLDER_NOT_FOUND: 'OT6002',
  FILE_ACCESS_DENIED: 'OT6003',
  INVALID_PATH_TYPE: 'OT6004',
  COMMAND_EXECUTION_FAILURE: 'OT6005',
  NETWORK_REQUEST_FAILURE: 'OT6006',

  // OT7xxx - Build / Target
  TARGET_COMPILATION_ERROR: 'OT7001',
  MANIFEST_VALIDATION_ERROR: 'OT7002',
  MISSING_BUILD_ASSET: 'OT7003',
  BUNDLE_GENERATION_ERROR: 'OT7004',

  // OT8xxx - Studio / Tooling
  UNTRUSTED_WORKSPACE_BLOCKED: 'OT8001',
  LARGE_FILE_ANALYSIS_BYPASS: 'OT8002',
  FILE_CHANGED_ON_DISK: 'OT8003',
  STUDIO_ANALYZER_ERROR: 'OT8004'
};

export const DiagnosticMetadata = {
  [DiagnosticCodes.INDENTATION_JUMP]: {
    code: 'OT1001',
    category: 'lexical',
    severity: 'error',
    title: 'Indentation Jump',
    defaultMessage: 'Indentation cannot jump more than one level at a time.'
  },
  [DiagnosticCodes.INVALID_CHARACTER]: {
    code: 'OT1002',
    category: 'lexical',
    severity: 'error',
    title: 'Unrecognized Character',
    defaultMessage: 'Unrecognized character in Otter source.'
  },
  [DiagnosticCodes.PERIOD_PROPERTY_ACCESS]: {
    code: 'OT1003',
    category: 'lexical',
    severity: 'error',
    title: 'Period Property Access',
    defaultMessage: 'Otter does not use periods to access properties.'
  },
  [DiagnosticCodes.EQUALS_ASSIGNMENT]: {
    code: 'OT1004',
    category: 'lexical',
    severity: 'error',
    title: 'Equals Assignment',
    defaultMessage: "Otter does not use '=' to assign values."
  },
  [DiagnosticCodes.UNTERMINATED_STRING]: {
    code: 'OT1005',
    category: 'lexical',
    severity: 'error',
    title: 'Unterminated String',
    defaultMessage: 'This string never closes.'
  },

  [DiagnosticCodes.MISSING_BLOCK_TERMINATOR]: {
    code: 'OT2001',
    category: 'syntax',
    severity: 'error',
    title: 'Missing Block Terminator',
    defaultMessage: 'Expected "." to close this block.'
  },
  [DiagnosticCodes.UNEXPECTED_TOKEN]: {
    code: 'OT2002',
    category: 'syntax',
    severity: 'error',
    title: 'Unexpected Token',
    defaultMessage: 'Unexpected grammar token in statement.'
  },
  [DiagnosticCodes.UNEXPECTED_EOF]: {
    code: 'OT2003',
    category: 'syntax',
    severity: 'error',
    title: 'Unexpected End of File',
    defaultMessage: 'Unexpected end of file while reading statement.'
  },
  [DiagnosticCodes.INVALID_ASSIGNMENT]: {
    code: 'OT2004',
    category: 'syntax',
    severity: 'error',
    title: 'Invalid Assignment',
    defaultMessage: 'Invalid assignment statement.'
  },
  [DiagnosticCodes.MISSING_CONDITION]: {
    code: 'OT2005',
    category: 'syntax',
    severity: 'error',
    title: 'Missing Condition',
    defaultMessage: 'Expected condition expression.'
  },
  [DiagnosticCodes.INVALID_FUNCTION_DEF]: {
    code: 'OT2006',
    category: 'syntax',
    severity: 'error',
    title: 'Invalid Function Definition',
    defaultMessage: 'Invalid function header or parameter specification.'
  },
  [DiagnosticCodes.EXTRANEOUS_BLOCK_TERMINATOR]: {
    code: 'OT2007',
    category: 'syntax',
    severity: 'error',
    title: 'Extraneous Block Terminator',
    defaultMessage: 'There is no open block for this period to close.'
  },

  [DiagnosticCodes.UNDECLARED_VARIABLE]: {
    code: 'OT3001',
    category: 'scope',
    severity: 'error',
    title: 'Undeclared Variable',
    defaultMessage: 'Unknown variable accessed before declaration.'
  },
  [DiagnosticCodes.UNKNOWN_FUNCTION]: {
    code: 'OT3002',
    category: 'scope',
    severity: 'error',
    title: 'Unknown Function',
    defaultMessage: 'Call to undefined function.'
  },
  [DiagnosticCodes.UNUSED_DECLARATION]: {
    code: 'OT3003',
    category: 'scope',
    severity: 'warning',
    title: 'Unused Declaration',
    defaultMessage: 'Variable declared but never read.'
  },
  [DiagnosticCodes.UNREACHABLE_CODE]: {
    code: 'OT3004',
    category: 'scope',
    severity: 'warning',
    title: 'Unreachable Code',
    defaultMessage: 'Unreachable code detected after return or stop.'
  },
  [DiagnosticCodes.FUNCTION_HOISTING_VIOLATION]: {
    code: 'OT3005',
    category: 'scope',
    severity: 'error',
    title: 'Function Called Before Declaration',
    defaultMessage: 'Otter requires functions to be declared before they are called.'
  },

  [DiagnosticCodes.TYPE_MISMATCH]: {
    code: 'OT4001',
    category: 'type',
    severity: 'error',
    title: 'Type Mismatch',
    defaultMessage: 'Invalid value type for this operation.'
  },
  [DiagnosticCodes.PROPERTY_NOT_FOUND]: {
    code: 'OT4002',
    category: 'type',
    severity: 'error',
    title: 'Property Not Found',
    defaultMessage: 'Thing does not have requested property.'
  },
  [DiagnosticCodes.DIVISION_BY_ZERO]: {
    code: 'OT4003',
    category: 'type',
    severity: 'error',
    title: 'Division by Zero',
    defaultMessage: 'Cannot divide number by zero.'
  },
  [DiagnosticCodes.COLLECTION_OUT_OF_RANGE]: {
    code: 'OT4004',
    category: 'type',
    severity: 'error',
    title: 'Collection Out of Range',
    defaultMessage: 'List index or collection bound out of range.'
  },

  [DiagnosticCodes.PROGRAM_FAILURE]: {
    code: 'OT5001',
    category: 'runtime',
    severity: 'error',
    title: 'Runtime Error',
    defaultMessage: 'Program execution halted.'
  },
  [DiagnosticCodes.GONE_ACCESS]: {
    code: 'OT5002',
    category: 'runtime',
    severity: 'error',
    title: 'Gone Value Access',
    defaultMessage: 'Variable has gone value and cannot be operated upon.'
  },
  [DiagnosticCodes.CALL_STACK_OVERFLOW]: {
    code: 'OT5003',
    category: 'runtime',
    severity: 'error',
    title: 'Call Stack Overflow',
    defaultMessage: 'Maximum recursion depth exceeded.'
  },
  [DiagnosticCodes.ARGUMENT_COUNT_MISMATCH]: {
    code: 'OT5004',
    category: 'runtime',
    severity: 'error',
    title: 'Argument Count Mismatch',
    defaultMessage: 'Incorrect number of arguments passed to function.'
  },

  [DiagnosticCodes.FILE_NOT_FOUND]: {
    code: 'OT6001',
    category: 'provider',
    severity: 'error',
    title: 'File Not Found',
    defaultMessage: 'Target file could not be found.'
  },
  [DiagnosticCodes.FOLDER_NOT_FOUND]: {
    code: 'OT6002',
    category: 'provider',
    severity: 'error',
    title: 'Folder Not Found',
    defaultMessage: 'Target folder could not be found.'
  },
  [DiagnosticCodes.FILE_ACCESS_DENIED]: {
    code: 'OT6003',
    category: 'provider',
    severity: 'error',
    title: 'File Access Denied',
    defaultMessage: 'Permission denied or file is locked.'
  },
  [DiagnosticCodes.INVALID_PATH_TYPE]: {
    code: 'OT6004',
    category: 'provider',
    severity: 'error',
    title: 'Invalid Path Type',
    defaultMessage: 'Path refers to a folder where a file is required, or vice versa.'
  },
  [DiagnosticCodes.COMMAND_EXECUTION_FAILURE]: {
    code: 'OT6005',
    category: 'provider',
    severity: 'error',
    title: 'Command Execution Failure',
    defaultMessage: 'External command exited with non-zero code.'
  },
  [DiagnosticCodes.NETWORK_REQUEST_FAILURE]: {
    code: 'OT6006',
    category: 'provider',
    severity: 'error',
    title: 'Network Request Failure',
    defaultMessage: 'HTTP network request failed.'
  },

  [DiagnosticCodes.TARGET_COMPILATION_ERROR]: {
    code: 'OT7001',
    category: 'build',
    severity: 'error',
    title: 'Build Compilation Error',
    defaultMessage: 'Target compiler reported errors.'
  },
  [DiagnosticCodes.MANIFEST_VALIDATION_ERROR]: {
    code: 'OT7002',
    category: 'build',
    severity: 'error',
    title: 'Project Manifest Error',
    defaultMessage: 'project.json manifest configuration is invalid.'
  },
  [DiagnosticCodes.MISSING_BUILD_ASSET]: {
    code: 'OT7003',
    category: 'build',
    severity: 'error',
    title: 'Missing Build Asset',
    defaultMessage: 'Required build asset is missing.'
  },
  [DiagnosticCodes.BUNDLE_GENERATION_ERROR]: {
    code: 'OT7004',
    category: 'build',
    severity: 'error',
    title: 'Bundle Generation Error',
    defaultMessage: 'Failed to generate target distribution package.'
  },

  [DiagnosticCodes.UNTRUSTED_WORKSPACE_BLOCKED]: {
    code: 'OT8001',
    category: 'studio',
    severity: 'warning',
    title: 'Execution Blocked',
    defaultMessage: 'Code execution and terminal commands restricted in untrusted workspace.'
  },
  [DiagnosticCodes.LARGE_FILE_ANALYSIS_BYPASS]: {
    code: 'OT8002',
    category: 'studio',
    severity: 'info',
    title: 'Large File Mode Active',
    defaultMessage: 'AST analysis bypassed for high performance.'
  },
  [DiagnosticCodes.FILE_CHANGED_ON_DISK]: {
    code: 'OT8003',
    category: 'studio',
    severity: 'warning',
    title: 'External File Change',
    defaultMessage: 'File changed externally on disk.'
  },
  [DiagnosticCodes.STUDIO_ANALYZER_ERROR]: {
    code: 'OT8004',
    category: 'studio',
    severity: 'error',
    title: 'Studio Analyzer Unavailable',
    defaultMessage: 'Otter background analysis service encountered an error.'
  }
};

/**
 * Resolves a stable OTxxxx diagnostic code from a message, stage, or existing code.
 */
export function resolveDiagnosticCode(message = '', stage = 'parser', context = {}) {
  const msg = String(message || '').trim();
  const lower = msg.toLowerCase();

  // Explicit code provided
  if (context.code && DiagnosticMetadata[context.code]) {
    return context.code;
  }

  // 1. Lexical checks
  if (lower.includes('indentation cannot jump')) return DiagnosticCodes.INDENTATION_JUMP;
  if (lower.includes("does not use periods to access properties") || lower.includes("periods to access properties")) return DiagnosticCodes.PERIOD_PROPERTY_ACCESS;
  if (lower.includes("does not use '=' to assign values") || lower.includes("does not use '='") || lower.includes("does not use =")) return DiagnosticCodes.EQUALS_ASSIGNMENT;
  if (lower.includes('this string never closes') || lower.includes('unterminated string')) return DiagnosticCodes.UNTERMINATED_STRING;
  if (lower.includes("i don't understand") || lower.includes('unrecognized character')) return DiagnosticCodes.INVALID_CHARACTER;

  // 2. Syntax / Parser checks
  if (lower.includes("there is no open block for this period to close")) {
    return DiagnosticCodes.EXTRANEOUS_BLOCK_TERMINATOR;
  }
  if (lower.includes('expected "." to close') || lower.includes('close this block') || lower.includes('missing "."') || lower.includes('expected blockend')) {
    return DiagnosticCodes.MISSING_BLOCK_TERMINATOR;
  }
  if (lower.includes("i expected the program to end here") || lower.includes("unexpected end of file") || lower.includes("i expected the statement to end here")) {
    return DiagnosticCodes.UNEXPECTED_EOF;
  }
  if (lower.includes("i expected") || lower.includes("i found") || lower.includes("unexpected token")) {
    return DiagnosticCodes.UNEXPECTED_TOKEN;
  }

  // 3. Name & Scope checks
  if (context.semanticType === 'unused-variable' || lower.includes('declared but never read')) {
    return DiagnosticCodes.UNUSED_DECLARATION;
  }
  if (context.semanticType === 'unreachable-code' || lower.includes('unreachable code')) {
    return DiagnosticCodes.UNREACHABLE_CODE;
  }
  if (lower.includes('called before its declaration') || lower.includes('called before declaration')) {
    return DiagnosticCodes.FUNCTION_HOISTING_VIOLATION;
  }
  if (lower.includes("could not find anything called") || lower.includes("undefined variable") || lower.includes("i don't know a variable called")) {
    return DiagnosticCodes.UNDECLARED_VARIABLE;
  }
  if (lower.includes("i do not know a function called") || lower.includes("unknown function")) {
    return DiagnosticCodes.UNKNOWN_FUNCTION;
  }

  // 4. Filesystem / Provider checks
  if (lower.includes("could not find a file called") || lower.includes("file not found")) {
    return DiagnosticCodes.FILE_NOT_FOUND;
  }
  if (lower.includes("could not find a folder called") || lower.includes("folder not found")) {
    return DiagnosticCodes.FOLDER_NOT_FOUND;
  }
  if (lower.includes("could not read") || lower.includes("could not write") || lower.includes("permission") || lower.includes("locked")) {
    return DiagnosticCodes.FILE_ACCESS_DENIED;
  }
  if (lower.includes("is a folder, not a file") || lower.includes("is not a symbolic link")) {
    return DiagnosticCodes.INVALID_PATH_TYPE;
  }

  // 5. Build & Target checks
  if (stage === 'build' || context.isBuild) {
    if (lower.includes('manifest') || lower.includes('entrypoint') || lower.includes('project.json')) {
      return DiagnosticCodes.MANIFEST_VALIDATION_ERROR;
    }
    if (lower.includes('asset')) {
      return DiagnosticCodes.MISSING_BUILD_ASSET;
    }
    return DiagnosticCodes.TARGET_COMPILATION_ERROR;
  }

  // 6. Runtime default
  if (stage === 'runtime') {
    if (lower.includes('gone')) return DiagnosticCodes.GONE_ACCESS;
    if (lower.includes('recursion') || lower.includes('stack overflow')) return DiagnosticCodes.CALL_STACK_OVERFLOW;
    if (lower.includes('division by zero') || lower.includes('divide by zero') || (lower.includes('divide') && lower.includes('zero'))) return DiagnosticCodes.DIVISION_BY_ZERO;
    return DiagnosticCodes.PROGRAM_FAILURE;
  }

  // Default fallback
  return DiagnosticCodes.UNEXPECTED_TOKEN;
}

/**
 * Diagnostic Certification Status Tiers
 * 1. DEFINED: Code and metadata exist in Studio registry.
 * 2. MAPPED: Code is deterministically resolved from real lexer/parser/runtime/build/host diagnostic strings.
 * 3. PRODUCTION_VERIFIED: Code mapping and normalization has verified automated test coverage with real compiler/runtime/server.
 */
export const DiagnosticCertificationTier = {
  DEFINED: 'DEFINED',
  MAPPED: 'MAPPED',
  PRODUCTION_VERIFIED: 'PRODUCTION_VERIFIED'
};

export const DiagnosticCertificationStatus = {
  // OT1xxx - Lexical
  [DiagnosticCodes.INDENTATION_JUMP]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.INVALID_CHARACTER]: DiagnosticCertificationTier.MAPPED,
  [DiagnosticCodes.PERIOD_PROPERTY_ACCESS]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.EQUALS_ASSIGNMENT]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.UNTERMINATED_STRING]: DiagnosticCertificationTier.MAPPED,

  // OT2xxx - Syntax / Parser
  [DiagnosticCodes.MISSING_BLOCK_TERMINATOR]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.UNEXPECTED_TOKEN]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.UNEXPECTED_EOF]: DiagnosticCertificationTier.MAPPED,
  [DiagnosticCodes.INVALID_ASSIGNMENT]: DiagnosticCertificationTier.MAPPED,
  [DiagnosticCodes.MISSING_CONDITION]: DiagnosticCertificationTier.MAPPED,
  [DiagnosticCodes.INVALID_FUNCTION_DEF]: DiagnosticCertificationTier.MAPPED,
  [DiagnosticCodes.EXTRANEOUS_BLOCK_TERMINATOR]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,

  // OT3xxx - Name / Scope
  [DiagnosticCodes.UNDECLARED_VARIABLE]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.UNKNOWN_FUNCTION]: DiagnosticCertificationTier.MAPPED,
  [DiagnosticCodes.UNUSED_DECLARATION]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.UNREACHABLE_CODE]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.FUNCTION_HOISTING_VIOLATION]: DiagnosticCertificationTier.MAPPED,

  // OT4xxx - Type / Value / Operation
  [DiagnosticCodes.TYPE_MISMATCH]: DiagnosticCertificationTier.DEFINED,
  [DiagnosticCodes.PROPERTY_NOT_FOUND]: DiagnosticCertificationTier.DEFINED,
  [DiagnosticCodes.DIVISION_BY_ZERO]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.COLLECTION_OUT_OF_RANGE]: DiagnosticCertificationTier.DEFINED,

  // OT5xxx - Runtime
  [DiagnosticCodes.PROGRAM_FAILURE]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.GONE_ACCESS]: DiagnosticCertificationTier.MAPPED,
  [DiagnosticCodes.CALL_STACK_OVERFLOW]: DiagnosticCertificationTier.MAPPED,
  [DiagnosticCodes.ARGUMENT_COUNT_MISMATCH]: DiagnosticCertificationTier.DEFINED,

  // OT6xxx - Filesystem / System / Provider
  [DiagnosticCodes.FILE_NOT_FOUND]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.FOLDER_NOT_FOUND]: DiagnosticCertificationTier.MAPPED,
  [DiagnosticCodes.FILE_ACCESS_DENIED]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.INVALID_PATH_TYPE]: DiagnosticCertificationTier.MAPPED,
  [DiagnosticCodes.COMMAND_EXECUTION_FAILURE]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.NETWORK_REQUEST_FAILURE]: DiagnosticCertificationTier.DEFINED,

  // OT7xxx - Build / Target
  [DiagnosticCodes.TARGET_COMPILATION_ERROR]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.MANIFEST_VALIDATION_ERROR]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.MISSING_BUILD_ASSET]: DiagnosticCertificationTier.MAPPED,
  [DiagnosticCodes.BUNDLE_GENERATION_ERROR]: DiagnosticCertificationTier.DEFINED,

  // OT8xxx - Tooling / Studio
  [DiagnosticCodes.UNTRUSTED_WORKSPACE_BLOCKED]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.LARGE_FILE_ANALYSIS_BYPASS]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.FILE_CHANGED_ON_DISK]: DiagnosticCertificationTier.PRODUCTION_VERIFIED,
  [DiagnosticCodes.STUDIO_ANALYZER_ERROR]: DiagnosticCertificationTier.PRODUCTION_VERIFIED
};

export function getDiagnosticCertification(code) {
  return DiagnosticCertificationStatus[code] || DiagnosticCertificationTier.DEFINED;
}

// Decorate metadata registry with explicit certification tier
for (const [code, meta] of Object.entries(DiagnosticMetadata)) {
  meta.certification = getDiagnosticCertification(code);
}
