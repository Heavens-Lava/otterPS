# Otter 1.0 Contract Freeze Report

**Status: CERTIFIED — Gate 1 language-contract freeze.**

This report is certified as the language-contract evidence ledger for
release-checklist Gate 1. It does not certify every runtime target or mark
Otter 1.0 itself released. It separates
the frozen contract from implementation and documentation observations. A
finding is not silently resolved by changing one side of the language.

## Candidate examined

| Field | Value |
|---|---|
| Candidate commit | `a6e1a814e6134eef8fb9ea4e61e97ecbc6c398bb` |
| Candidate subject | `release: add contract coverage evidence and D120 resolution` |
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

## Certification evidence

The detached clean-checkout run at the nominated SHA completed the structural
audit, complete suite, and release conformance harness with exit code 0. Its
exact commands and outcomes—including **55 of 55** test files and **15**
release fixtures—are recorded in
[the clean-checkout evidence record](OTTER_1_0_CLEAN_CHECKOUT_EVIDENCE_2026-09-27.md).

No frozen contract file, grammar rule, specification decision, or AST shape
was changed to obtain this certification.

## Remaining release work outside Gate 1

Continue with D120 target-specific certification, Gate 3 hardening/soak
evidence, Gate 4 release packaging across advertised platforms, and the
documentation/release-note gate. The event-loop starvation finding remains a
documented release decision, not a silently changed runtime behavior.
