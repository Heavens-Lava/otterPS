# Otter 1.0 Contract Freeze Report

**Status: IN PROGRESS — not a language freeze approval.**

This report is the evidence ledger for release-checklist Gate 1. It separates
the frozen contract from implementation and documentation observations. A
finding is not silently resolved by changing one side of the language.

## Candidate examined

| Field | Value |
|---|---|
| Candidate commit | `344db09b` |
| Candidate subject | `docs: record D120 Windows PowerShell host evidence` |
| Contract file | `Otter.Contract.psm1` |
| Front-end implementation | `src/Otter.Lexer.psm1`, `src/Otter.Parser.psm1` |
| Runtime implementation | `src/Otter.Interpreter.psm1`, `src/Otter.Runtime.psm1`, `src/Otter.Library.psm1` |

## Initial surface audit

The first static pass enumerated 178 declared token kinds and 226 declared AST
node kinds from `Otter.Contract.psm1`. Parser/interpreter source references
were compared against those names. This is a name-integrity check only; it
does not establish that every grammar path has behavioural coverage.

| Area | Observation | Freeze disposition |
|---|---|---|
| Lexer keyword mapping | Canonical keywords are mapped in `src/Otter.Lexer.psm1`; aliases such as `increase`/`decrease` and singular/plural time units are intentional surface choices requiring documentation confirmation. | IN REVIEW |
| Parser token reference | A stale `[TokenKind]::Cancel` reference was removed from `src/Otter.Parser.psm1`. `Cancel` is not declared by the frozen token enum and `cancel` remains intentionally parsed contextually by text for HTTP and command-job cancellation. | RESOLVED — no contract addition was made. |
| File modules | `UseModule` exists in the AST contract. The later `docs/OTTER_1_0_MODULE_STATUS.md` and production-entry tests certify file imports for the console target. The formal grammar and scope matrix now distinguish file imports from deferred package imports. `tests/UseModuleProduction.Tests.ps1` passed 10/10 on 2026-09-26, including the imported serve route. | DOCUMENTATION CONFLICT RESOLVED; full cross-target certification remains. |
| Standard library scope | `docs/STANDARD_LIBRARY.md` is a concise subset while `docs/STANDARD_LIBRARY_REACHABILITY.md` records 31 certified capabilities. The public-reference scope and target-specific availability must be reconciled. | DOCUMENTATION CONFLICT — resolve before freeze. |
| D119 async jobs | `StartCommand` and `JobContext` are present in the current AST contract and have a dedicated 13-case regression suite. | IMPLEMENTED; PUBLIC-SURFACE REVIEW REQUIRED |

## Reproduction notes

On Windows PowerShell 5.1, tokenizing `cancel job` produces `Identifier` tokens
for `cancel` and `job`; the parser recognizes the statement contextually and
returns an AST successfully. This confirms that adding a `Cancel` token merely
to satisfy the stale reference would alter the frozen lexical contract without
need. The stale parser reference was removed while retaining the contextual
grammar. `tests/AsyncCommand.Tests.ps1` passed 13/13 and
`tests/Parser.Tests.ps1` passed after the change.

## Required decisions before certification

1. Define the public standard-library boundary from the tested reachability
   matrix, including host-specific operations such as Windows UI and clipboard
   APIs.
2. Complete source-level coverage of each declared token, node kind, and
   diagnostic path with an auditable manifest rather than relying on name
   matching.
3. Run all checks on a clean checkout of the nominated candidate and record
   their exact exit codes. The previously started full Windows suite exited
   without recoverable console output, so it is not counted as passing
   evidence.

## Next implementation-safe action

Certify file-import behavior through the remaining advertised targets and
reconcile the public standard-library reference with the reachability matrix.
