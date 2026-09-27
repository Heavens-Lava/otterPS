# Otter 1.0 Contract Freeze — Follow-ups

**Gate 1 status: freeze candidate certified, follow-ups pending.**

`docs/OTTER_1_0_CONTRACT_FREEZE_REPORT.md` certifies candidate
`a5146971fa6c0a4c2d33dee283897e640e38fae5`. That report is not edited here.
This ledger records evidence corrections and contract questions found after
it, each needing an explicit disposition before Gate 1 is treated as closed.
None of them is resolved by this document.

## E1. Evidence citation: cross-platform CI run

`docs/OTTER_1_0_CLEAN_CHECKOUT_EVIDENCE_2026-09-27.md` cites
[run 36286141126](https://github.com/Heavens-Lava/otterPS/actions/runs/36286141126)
and states that "the tested runtime source is unchanged between that run and
this candidate". For that run the statement is not correct:

| Run | Tested commit | Runtime source vs candidate `a514697` | Result |
|---|---|---|---|
| 36286141126 | `aea1d9c` | **differs**: the OPT-1/2/3 optimization pass (`c0a5c43`) changed `src/Otter.Interpreter.psm1` and `src/Otter.Runtime.psm1` afterwards (34 insertions, 5 deletions) | pass, 4 hosts |
| [36293298178](https://github.com/Heavens-Lava/otterPS/actions/runs/36293298178) | `b97f944` | **identical** (`git diff b97f944 a5146971 -- src otter.ps1 Otter.Contract.psm1` is empty) | pass, 4 hosts |

Run 36293298178 is the matching evidence for the stated claim. Scope of both
runs: the production CLI smoke (`--version`, `run`, `check`) and the project
workflow (`new`, `check`, `test`, `run`, `build`, `publish`). Neither run
included the portable language suite, which was added to the workflow later
(`315abe0`) and, at the candidate's runtime source, fails on all three
PowerShell 7 hosts (P1 below).

Disposition needed: the evidence record should cite run 36293298178 and state
its scope.

## P1. PowerShell 7 portability — RESOLVED

**RESOLVED — the portable suite passes on all four certified host configurations**
at master `639112f25d2007fcb25c2c0cd9b3ddc2b101caf0`:
[D120 run 36327608764](https://github.com/Heavens-Lava/otterPS/actions/runs/36327608764)
(Windows PowerShell 5.1, PowerShell 7 on Windows, Linux and macOS; 20 portable
suites plus the project workflow). The same commit passed every local release
gate from a clean checkout:
[OTTER_1_0_CERTIFICATION_RUN_639112f.md](OTTER_1_0_CERTIFICATION_RUN_639112f.md).

History:

The D120 portable language suite failed on PowerShell 7 on Windows, Linux and
macOS at the candidate. The failures are present at every commit tested back
to `7458fb7` (CI run 36298005056); they are not caused by the OPT-1/2/3
optimization pass, which reduced them.

| Finding | Kind | Fix |
|---|---|---|
| On PowerShell 7 (7.6.6) a function that emits one value with `Write-Output -NoEnumerate` hands its caller a `List[object]` holding it; 5.1 hands over the value. Every Otter value boundary used that form. Minimal reproducer: `person has name "Jeff"` / `say name of person` fails with "this is a list" on 7. | Otter semantics differed by host | `return , value` at all 40 sites (`2f98adc`) |
| `write ... atomically` onto a read-only file failed on Windows, succeeded on Linux/macOS. | Otter semantics differed by host | explicit read-only check (`7b8065a`) |
| Published artifact names used the host's invalid-filename list, so the same project got a different file name off Windows. | Otter semantics differed by host | fixed character set (`7b8065a`) |
| 11 suites hard-coded `powershell.exe`, `cmd` or `$env:TEMP`; one test waited only 3 s for `otter serve`. | Test harness assumed Windows | `98e8232`, `962828e` |

Interim result (CI run 36299552381, temporary diagnostic branch, since
deleted): three hosts passed; PowerShell 7 on Linux failed only
`Module.Tests.ps1` at M1. After M1 (`78b9793`, `639112f`) all four pass.

## Contract questions needing disposition

| Id | Question | Current behavior | Evidence |
|---|---|---|---|
| DC1 | Is the HTTP client part of the **console** public surface? | The console interpreter implements `get`/`post`/`put`/`delete` and they are tested; `STANDARD_LIBRARY.md`, the capability matrix and the scope matrix all say console HTTP is unsupported. | `tests/Http.Tests.ps1`; `release/otter-1.0-surface.json` `documentConflicts` |
| EV1 | Is cross-source event fairness guaranteed or best-effort? | Fixed per-pass order; command jobs win under load. | `docs/OTTER_1_0_EVENT_LOOP_REVIEW.md` |
| EV2 | May one event source drain an unbounded queue before others run? | Yes for command jobs (measured 1.5 s starvation of a UDP handler). | same |
| EV3 | Which event sources are dispatched during `wait`? | Only HTTP and command jobs. | same |
| EV4 | Is event ordering guaranteed only within a source? | FIFO within a source; unspecified across sources. | same |
| EV5 | May TCP/UDP callbacks be delayed by polling cadence? | Yes (about 31 events/s). | same |
| EV6 | Is the event loop cooperative rather than real-time? | Cooperative; handlers are never preempted. | same |
| EV7 | Are the scheduling limits documented as part of 1.0? | Only in the event-loop review. | same |
| M1 | **RESOLVED — module paths require exact case on all supported hosts.** A `use` path must spell every file and folder name exactly as on disk; a case-only mismatch is rejected with the same diagnostic on every host (no case-insensitive fallback). Module identity is the exact on-disk path. | Decided 2026-09-27. Implemented in `src/Otter.Module.psm1` (`78b9793`, `639112f`). | `tests/Module.Tests.ps1` test 8; `tests/HostPortability.Tests.ps1` (file and folder cases, production entry point); D120 run 36327608764 |

## Other cross-document conflicts

DC2 to DC5 (capability matrix still lists `use` modules as deferred; the
reachability matrix's 31-versus-34 row count; "Processes" versus "Process";
53-versus-55 suite counts) are recorded with evidence in
`release/otter-1.0-surface.json` (`documentConflicts`) and
`docs/OTTER_1_0_SURFACE_RECONCILIATION.md` section 8.
