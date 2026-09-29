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
| DC1 | **RESOLVED — console HTTP is part of Otter 1.0** (approved 2026-09-27; D116A/D116B affirmed in `SPEC-DECISIONS.md`). Stale documents corrected; `http-web-target-only` fixture renamed `http-web-fetch`. | `tests/Http.Tests.ps1` made host-portable and passing on all four D120 hosts (run 36373295822). | `docs/OTTER_1_0_CONTRACT_DECISIONS_DC1_EV.md` |
| EV1 | **RESOLVED — see D121** (approved 2026-09-27). Documentation only. | | `SPEC-DECISIONS.md` D121; `docs/OTTER_1_0_EVENT_MODEL.md`; `tests/EventContract.Tests.ps1` |
| EV2 | **RESOLVED — see D121** (approved 2026-09-27). Implemented: bounded job events per turn (`6451f68`). | | `SPEC-DECISIONS.md` D121; `docs/OTTER_1_0_EVENT_MODEL.md`; `tests/EventContract.Tests.ps1` |
| EV3 | **RESOLVED — see D121** (approved 2026-09-27). Implemented: `wait` services every event source (`6451f68`). | | `SPEC-DECISIONS.md` D121; `docs/OTTER_1_0_EVENT_MODEL.md`; `tests/EventContract.Tests.ps1` |
| EV4 | **RESOLVED — see D121** (approved 2026-09-27). Documentation only. | | `SPEC-DECISIONS.md` D121; `docs/OTTER_1_0_EVENT_MODEL.md`; `tests/EventContract.Tests.ps1` |
| EV5 | **RESOLVED — see D121** (approved 2026-09-27). Documentation only. | | `SPEC-DECISIONS.md` D121; `docs/OTTER_1_0_EVENT_MODEL.md`; `tests/EventContract.Tests.ps1` |
| EV6 | **RESOLVED — see D121** (approved 2026-09-27). Documentation only. | | `SPEC-DECISIONS.md` D121; `docs/OTTER_1_0_EVENT_MODEL.md`; `tests/EventContract.Tests.ps1` |
| EV7 | **RESOLVED — see D121** (approved 2026-09-27). Documentation only. | | `SPEC-DECISIONS.md` D121; `docs/OTTER_1_0_EVENT_MODEL.md`; `tests/EventContract.Tests.ps1` |
| M1 | **RESOLVED — module paths require exact case on all supported hosts.** A `use` path must spell every file and folder name exactly as on disk; a case-only mismatch is rejected with the same diagnostic on every host (no case-insensitive fallback). Module identity is the exact on-disk path. | Decided 2026-09-27. Implemented in `src/Otter.Module.psm1` (`78b9793`, `639112f`). | `tests/Module.Tests.ps1` test 8; `tests/HostPortability.Tests.ps1` (file and folder cases, production entry point); D120 run 36327608764 |
| D99 | **RESOLVED — DEFERRED from Otter 1.0; target Otter 1.1+** (approved 2026-09-28). The query language stays in the source tree unchanged as experimental, non-1.0 surface; it is not advertised as a 1.0 feature. | Implemented (`c32767d`) and in the frozen contract, but its only design record said "Target: Otter 1.1+ ... Not approved yet". | `SPEC-DECISIONS.md` D99; `release/otter-1.0-surface.json` (`status: deferred`); `otter-docs/pages/queries.ot` |

## Ledger reconstruction (2026-09-27)

`SPEC-DECISIONS.md` now records D100-D114 and D119, reconstructed from the
approved specifications (including `docs/design/D107-D111-SPECIFICATION.md`),
the implementing commits and the tests. D99 (Otter Query Language) was recorded
as UNRESOLVED on 2026-09-27 and decided on 2026-09-28: **deferred from Otter 1.0,
target 1.1+** (see the D99 row above). With that, no Otter 1.0 contract decision
remains unresolved in the ledger. (Older entries once marked open were settled
later: D32.7 by D42, D38 by D38A/D38B.) DC2 to DC5 below are documentation
conflicts, not contract questions.

## Other cross-document conflicts

DC2 to DC5 (capability matrix still lists `use` modules as deferred; the
reachability matrix's 31-versus-34 row count; "Processes" versus "Process";
53-versus-55 suite counts) are recorded with evidence in
`release/otter-1.0-surface.json` (`documentConflicts`) and
`docs/OTTER_1_0_SURFACE_RECONCILIATION.md` section 8. The RC3 documentation
pass corrected the stale documents; section 8 records how each was resolved.

## RC2 stabilization reviews (2026-09-28)

Three read-only reviews ran against the frozen candidate before the RC tag:
security and data loss (files and paths), security (networking and secrets),
and a literal walkthrough of the installation and Getting Started docs. The
release-blocking findings were fixed before the RC tag, each with a regression
test (see `CHANGELOG.md`, 1.0.0-rc.2, "Security"). Everything below was
triaged as **not** blocking the RC and is tracked here.

### Before 1.0.0

| Id | Finding | Where |
|---|---|---|
| S6 | Docs call file operations "sandboxed"; they are not a sandbox (absolute paths, `..`, links all work). Reword. | `README.md`, `otter-docs/pages/files.ot`, `otter-docs/pages/welcome.ot` |
| S7 | `use` accepts absolute and `../` paths and non-`.ot` files; an absolute path skips the D122 case check, so a wrong-case absolute path loads on Windows/macOS. | `src/Otter.Module.psm1` |
| N4 | One aborted request (short body) ends `otter serve`; request bodies are read unbounded. | `src/Otter.Server.psm1`, `otter.ps1` serve loop |
| N5 | `download file` has no deadline on the response body (a slow server hangs the program). | `src/Otter.Library.psm1` |
| N6 | Console HTTP has no default timeout or response-size cap; error messages repeat the full URL (credentials in `user:pass@` or query strings). | `src/Otter.Library.psm1` |
| D1 | No documented install path for PowerShell 7 on Linux/macOS (the engine is certified there; the installer is Windows-only). Decide what 1.0 promises and document it. | `INSTALL.md`, docs site installation page |
| D3 | REPL: `quit` is documented but only `exit` works. | `INSTALL.md` section 6 |
| D4 | REPL treats only some block starters as blocks (`each ... in` and `has` fail); block end rule undocumented. | REPL, docs `repl` page |
| D5 | `otter check .` reports a project valid while an unimported project file has a syntax error; docs say it validates the whole project. | `otter check`, docs `cli`/`projects` pages |
| DC2-DC5 | Documentation conflicts listed below. | |

### Post-1.0 (minor)

S8 symlink cycles in `use` give a confusing error; `copy folder` into its own
subfolder recurses; `otter web` overwrites an existing `.html` silently; the
distribution builder deletes an existing zip without `-Force`. S5 (remainder)
the uninstaller's PATH cleanup can throw on unusual PATH entries and rewrites
REG_EXPAND_SZ as REG_SZ. N7 UDP listens on all interfaces (TCP defaults to
loopback). N8 desktop bridge token: case-insensitive, non-constant-time check,
accepted in the query string, written into the app folder. N9 runtime
`url`/`src` accept `javascript:` URLs. N10 no cap on stored password-hash
iterations. D6-D12 docs wording: `-ParseOnly` output, versioned install folder
wording, "no registry changes", argument pass-through exceptions, undocumented
`serve`/`profile`/`debug`/`browse`, the `hello` page stub, mislabelled code
blocks.

### Otter Studio (out of scope for the language release)

Studio is a development preview, not in the 1.0 distribution. Its dev server
(`otter-studio/serve.mjs`) listens on all interfaces with no authentication,
allows any origin, runs shell commands (`/api/terminal`), writes files outside
the workspace (`/api/run`, `/api/create-project`), and its `startsWith` path
checks accept sibling folders. Jeff's decision (2026-09-28): Studio is done
after the Otter language; fix these before Studio is released. Until then, do
not run `otter studio` on an untrusted network.

## RC3 (2026-09-28)

The production-readiness audit of RC2 (`708ef2e`) found release blockers, so
RC2 was superseded without certification or a tag. RC3 resolves the approved
blocker set B1-B14 and decisions D124-D127, each with a regression test that
fails on RC2 (see `CHANGELOG.md` 1.0.0-rc.3). The DC2-DC5 documentation
conflicts are reconciled.

**RESOLVED:** D123 (D-1, arithmetic in conditions) is implemented in the final
RC3 candidate. `src/Otter.Parser.psm1` now permits arithmetic only as an
ordinary comparison operand; bare conditions, state predicates and string-match
predicates retain their existing grammar. `tests/ConditionArithmetic.Tests.ps1`
contains 41 regression cases, including the scope guards. Final release
certification remains required before tagging.

**Found while fixing, not in RC3:**

| Finding | Class |
|---|---|
| `when b is hovered` compiles to a `hovered` DOM event that never fires; `hovered` is not a known event on desktop either | post-1.0 (mapping it is a new feature) |
| `use "../x.ot"` bundles an `.ot` file from outside the project into build output; it is the author's explicit import (S7) | before 1.0.0: decide whether `use` may leave the project |
| `otter test` does not read the manifest entry point, so it is not covered by the build-input containment check | before 1.0.0 |
| `tools/Build-OtterRelease.ps1` has a stale module list (8 modules missing) and is referenced by nothing; `tools/New-OtterDistribution.ps1` is the release path | post-1.0: remove or fix |
| `otter-docs/scripts/rules-pages.json` and `rules3.md` still hold old page text; `build-docs-content.ps1 -RegeneratePages` would overwrite the corrected pages | before 1.0.0: do not regenerate until updated |
| `otter web .` on Linux cannot open a browser and says so (use `-NoOpen`) | documented |
| Text set on UI elements (`text of x is value`) does not use the D126 formatter | post-1.0 |
| `log`/`warn`/`error` and fuzzer stand-ins join values with JavaScript's default joining | post-1.0 |
| Negative zero prints `-0` on the PowerShell 7 console and `0` on web (the console itself differs by host) | documented |
