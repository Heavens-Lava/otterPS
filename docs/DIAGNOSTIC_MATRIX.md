# Otter 1.0 — Diagnostic Certification Matrix

## Overview
Normal user mistakes in Otter programs must produce clean, readable, instructional Otter diagnostics with real line numbers, column/context where applicable, helpful suggestions, and deterministic exit codes.
Under no circumstances may raw PowerShell host exceptions, `.NET` stack traces, internal module paths (`.psm1:`), `NullReferenceException`, or unhandled JavaScript exceptions reach normal user console output.

Certification test suite: [tests/DiagnosticMatrix.Tests.ps1](file:///c:/Users/jmacy/projects/otterPS/tests/DiagnosticMatrix.Tests.ps1)
Result: **15 / 15 categories certified (100% PASS)**

---

## Exit Code Contract
- **Exit 0**: Successful program execution
- **Exit 1**: Command-line usage error, missing file argument, or unknown CLI command
- **Exit 2**: Otter Syntax Error (Lexer, Parser, or Indentation error)
- **Exit 3**: Otter Runtime Error (Execution failure, Type mismatch, I/O error)

---

## Diagnostic Matrix

| # | Category | Trigger Scenario | Exit Code | Diagnostic Banner | Line Reference | Verified Properties | Status |
|---|---|---|---|---|---|---|---|
| 1 | **Lexer failure** | Unclosed string literal `say "unterminated` | 2 | `Otter Syntax Error` | Yes (`Line 1:`) | Identifies string never closes, suggests closing quote | CERTIFIED |
| 2 | **Parser failure** | Missing expected keyword `if age is greater 18` | 2 | `Otter Syntax Error` | Yes (`Line 1:`) | Identifies unexpected token, suggests expected structure | CERTIFIED |
| 3 | **Indentation failure** | Inconsistent whitespace (2 spaces when 4 expected) | 2 | `Otter Syntax Error` | Yes (`Line 2:`) | Identifies inconsistent indentation level | CERTIFIED |
| 4 | **Type mismatch** | Arithmetic on non-numeric type `total is "banana" plus 5` | 3 | `Otter Runtime Error` | Yes (`Line 1:`) | Names operand and required numeric type | CERTIFIED |
| 5 | **Bad arithmetic** | Multiplying non-numeric values `"apple" times 5` | 3 | `Otter Runtime Error` | Yes (`Line 1:`) | Readable explanation of required numeric operand | CERTIFIED |
| 6 | **Division by zero** | `10 divided by 0` | 3 | `Otter Runtime Error` | Yes (`Line 1:`) | Explicitly names division by zero | CERTIFIED |
| 7 | **Missing file** | `read "nonexistent.txt" into c` | 3 | `Otter Runtime Error` | Yes (`Line 1:`) | Names missing file and suggests checking `if file ... exists` | CERTIFIED |
| 8 | **Directory as file** | `write "hello" to "."` | 3 | `Otter Runtime Error` | Yes (`Line 1:`) | Distinguishes folder from file (`"." is a folder, not a file.`) | CERTIFIED |
| 9 | **Malformed JSON** | `convert "{bad" from json into obj` | 3 | `Otter Runtime Error` | Yes (`Line 1:`) | Friendly JSON parsing diagnostic, no host JsonReader exception | CERTIFIED |
| 10 | **Invalid collection op** | `remove "item" from 42` | 3 | `Otter Runtime Error` | Yes (`Line 2:`) | Clarifies target is not a list or valid target | CERTIFIED |
| 11 | **Missing object property** | `say age of person` (unassigned property) | 3 | `Otter Runtime Error` | Yes (`Line 3:`) | Names missing property, suggests assignment | CERTIFIED |
| 12 | **Bad function arguments**| Calling 2-parameter function with 1 argument | 3 | `Otter Runtime Error` | Yes (`Line 4:`) | Identifies missing argument for parameter | CERTIFIED |
| 13 | **Recursion overflow** | Unbounded recursive calls | 3 | `Otter Runtime Error` | Yes (`Line 2:`) | Identifies call depth limit exceeded, suggests checking recursion | CERTIFIED |
| 14 | **Failed process invocation** | Running nonexistent executable | 3 | `Otter Runtime Error` | Yes (`Line 1:`) | Clean Otter error naming executable, no raw Win32Exception leak | CERTIFIED |
| 15 | **Undefined variable** | `say missingVariable` | 3 | `Otter Runtime Error` | Yes (`Line 1:`) | Names variable, suggests initializing with `is` | CERTIFIED |

---

## Leakage Prevention Certified
All 15 diagnostic tests specifically assert the absence of:
- `System.Management.Automation.*`
- `NullReferenceException`
- `Otter.Interpreter.psm1`, `Otter.Parser.psm1`, `Otter.Lexer.psm1`
- `at <ScriptBlock>`
- Raw .NET `StackTrace`
