# Otter 1.0 — Contract Coverage Manifest

This manifest is the auditable coverage record for the frozen
`Otter.Contract.psm1` surface. It separates two necessary forms of evidence:

1. **Structural coverage:** every declared enum member is connected to the
   lexer/parser/runtime pipeline, or is an explicitly documented reservation.
2. **Behavioural coverage:** representative and adversarial programs execute
   through the production CLI and assert observable output or Otter errors.

Neither form substitutes for the other. A source-name search alone cannot
prove semantics, and an individual program cannot prove that an enum member
remains connected to the pipeline.

## Reproducible structural audit

Run from the repository root with Windows PowerShell 5.1 or PowerShell 7:

```powershell
powershell.exe -NoProfile -File .\tools\Test-OtterContractCoverage.ps1
```

The script gets the `TokenKind` and `NodeKind` lists from the frozen contract
at execution time, then checks these production paths:

| Contract surface | Required pipeline references |
|---|---|
| Every `TokenKind` | `src/Otter.Lexer.psm1` or `src/Otter.Parser.psm1` |
| Every `NodeKind` | A contract AST class, parser construction of that class, and a class- or kind-based dispatch reference in interpreter, JavaScript compiler, web, desktop, or server runtime |
| `TokenKind::Thing` | Explicit contextual exception: `thing` is read by token text in object-type parsing, preserving contextual-keyword behavior; `Parser.Tests.ps1` and `Objects.Tests.ps1` cover `person is a thing` |
| `NodeKind::UiLayout` | Explicit reserved exception: layout is stored on `UiElement`; see [D114.5](D114_5_LANGUAGE_INTEGRITY_AUDIT.md) |

Any newly declared member that is not wired into a pipeline fails the audit.
The exception list lives in the script and is intentionally small and visible
in its output; adding an exception is a release-contract decision, not an
incidental test change.

## Behavioural-suite map

The complete suite is invoked by `tests/Run-Tests.ps1`. The following map
identifies the focused evidence for each public contract region. All listed
suites are production-path tests, not mocks of lexer/parser output.

| Contract region | Primary behavioural evidence |
|---|---|
| Tokenization, indentation, multiword/contextual keywords | `Lexer.Tests.ps1`, `Keywords.Tests.ps1`, `Grammar.Tests.ps1`, `RedTeam.Tests.ps1` |
| AST productions, expressions, blocks, diagnostics | `Parser.Tests.ps1`, `Grammar.Tests.ps1`, `DiagnosticMatrix.Tests.ps1`, `V1Audit.Tests.ps1` |
| Core evaluation, values, control flow, collections, functions, things | `Interpreter.Tests.ps1`, `Collections.Tests.ps1`, `Objects.Tests.ps1`, `Part3.Tests.ps1`, `DynamicThing.Tests.ps1` |
| Standard library | `StandardLibrary.Tests.ps1` (31 canonical capabilities), `Library.Tests.ps1`, `Dates.Tests.ps1`, `Data.Tests.ps1`, `Csv.Tests.ps1`, `Bytes.Tests.ps1`, `Xml.Tests.ps1` |
| Files, process, system, install, project CLI | `FilesystemAdversarial.Tests.ps1`, `ProcessAdversarial.Tests.ps1`, `TierOneRuntime.Tests.ps1`, `Installation.Tests.ps1`, `InstallSoak.Tests.ps1`, `Project*.Tests.ps1` |
| Network, servers, event sources | `Network.Tests.ps1`, `Http.Tests.ps1`, `Server.Tests.ps1`, `WebSocket.Tests.ps1`, `FileWatching.Tests.ps1`, `AsyncCommand.Tests.ps1` |
| Target-specific UI and web compiler | `UI.Tests.ps1`, `DragDrop.Tests.ps1`, `Web.Tests.ps1`, `Download.Tests.ps1` |
| Modules, query/database, security | `Module.Tests.ps1`, `UseModuleProduction.Tests.ps1`, `Query.Tests.ps1`, `Database.Tests.ps1`, `Crypto.Tests.ps1`, `Vault.Tests.ps1` |
| CLI and user-facing errors | `CliArguments.Tests.ps1`, `CliContract.Tests.ps1`, `CommandDispatch.Tests.ps1`, `Debugger.Tests.ps1`, `Terminal.Tests.ps1`, `Repl.Tests.ps1` |

## Release evidence recorded for this candidate

On 2026-09-27, `tests/Run-Tests.ps1` completed with exit code 0 and reported
**53 of 53 test files passed** on the Windows PowerShell 5.1 development host.
That count is the suite as it stood on that date; test files were added
afterwards (for example the profiler and optimization suites), so later records
report 55 of 55, and the rc.2 candidate `708ef2e` has 59 test files. A count is
only meaningful together with the candidate SHA it ran against.
This is behavioural evidence only; the clean-checkout reproduction remains a
separate Gate 1 record. The release conformance harness and differential
fuzzer evidence are recorded in
[Gate 3 evidence](OTTER_1_0_GATE3_EVIDENCE_2026-09-26.md).

## Review rule

Before freeze approval, run the structural audit and the complete suite from
the nominated clean checkout. Record their exact exit codes alongside the
candidate SHA. Changes to the frozen contract require Jeff's approval under
the repository ownership rules; this manifest does not grant an exception.
