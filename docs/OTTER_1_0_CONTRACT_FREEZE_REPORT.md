# Otter 1.0 Contract Freeze Report

**Status: IN PROGRESS — not a language freeze approval.**

This report is the evidence ledger for release-checklist Gate 1. It separates
the frozen contract from implementation and documentation observations. A
finding is not silently resolved by changing one side of the language.

## Candidate examined

| Field | Value |
|---|---|
| Candidate commit | `b97f944` |
| Candidate subject | `docs: Otter 1.0 event loop review (investigation only, no behavior change)` |
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
| Lexer keyword mapping | Canonical keywords are mapped in `src/Otter.Lexer.psm1`; aliases such as `increase`/`decrease` and singular/plural time units are intentional surface choices. The structural audit enumerates all 178 current token kinds directly from the contract. | RESOLVED — see the contract coverage manifest. |
| Parser token reference | A stale `[TokenKind]::Cancel` reference was removed from `src/Otter.Parser.psm1`. `Cancel` is not declared by the frozen token enum and `cancel` remains intentionally parsed contextually by text for HTTP and command-job cancellation. | RESOLVED — no contract addition was made. |
| File modules | `UseModule` exists in the AST contract. The later `docs/OTTER_1_0_MODULE_STATUS.md` and production-entry tests certify file imports for the console target. The formal grammar and scope matrix now distinguish file imports from deferred package imports. `tests/UseModuleProduction.Tests.ps1` passed 10/10 on 2026-09-26, including the imported serve route. | DOCUMENTATION CONFLICT RESOLVED; full cross-target certification remains. |
| Standard library scope | The standard-library reference now names portable core, console, and target-specific boundaries. The 31-case reachability suite is defined as a canonical smoke matrix rather than an exhaustive capability list. | RESOLVED — `docs/STANDARD_LIBRARY.md` and the scope matrix agree. |
| Structural contract coverage | `tools/Test-OtterContractCoverage.ps1` derives the 178 `TokenKind` and 226 `NodeKind` members from the frozen contract, verifies lexer/parser consumption, AST construction, and runtime/compiler dispatch references. `UiLayout` and contextual `Thing` are explicit documented exceptions. It passed on 2026-09-27. | RESOLVED — behavioural evidence remains the named focused suites in the manifest. |
| D119 async jobs | `StartCommand` and `JobContext` are present in the current AST contract, listed in the console boundary, and have a dedicated 13-case regression suite. | RESOLVED — console runtime public surface. |

## Reproduction notes

On Windows PowerShell 5.1, tokenizing `cancel job` produces `Identifier` tokens
for `cancel` and `job`; the parser recognizes the statement contextually and
returns an AST successfully. This confirms that adding a `Cancel` token merely
to satisfy the stale reference would alter the frozen lexical contract without
need. The stale parser reference was removed while retaining the contextual
grammar. `tests/AsyncCommand.Tests.ps1` passed 13/13 and
`tests/Parser.Tests.ps1` passed after the change.

## Required decisions before certification

1. Run all checks on a clean checkout of the nominated candidate and record
   their exact exit codes. The previously started full Windows suite exited
   without recoverable console output, so it is not counted as passing evidence.

## Next implementation-safe action

Run the structural audit, full suite, release conformance, and distribution
verification from a clean checkout of the nominated candidate. Then append the
exact commands, candidate SHA, and exit codes before changing this report to a
freeze approval.
