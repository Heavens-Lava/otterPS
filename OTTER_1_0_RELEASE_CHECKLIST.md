# Otter 1.0 Release Checklist

**Purpose:** This is the durable release ledger for the Otter 1.0 transition.
It records reproducible evidence, release decisions, environmental limits, and
the next command for each gate. It is not a substitute for a clean commit or
for an owner approving a release.

## Release rule

No item may be marked **CERTIFIED** unless it was run against a clean,
immutable revision and its evidence is recorded below. A passing run against a
dirty working tree is useful diagnostic evidence, but is **PROVISIONAL**.

## D119 — Dogfooding freeze

**Status: COMPLETE AS THE FROZEN D119 REFERENCE APPLICATION.**

`OtterWorkspace` has completed its four intended phases: Foundation, Async
Task Runner, Project Management, and Project Explorer. The D119 dogfooding
log records 0 host-language application-workaround LOC, 880+ Otter application
LOC, 650+ Otter test LOC, six Otter test suites, and the two production
refinements D119-R1 (script-aware command dispatch) and D119-R2 (async process
jobs with output streaming and cancellation).

This closes D119 as a *dogfood milestone*. It does not automatically certify
every feature exercised by the app for the 1.0 public contract. New work in
`OtterWorkspace` requires an explicit post-1.0 decision; it must not expand
the 1.0 language surface during the release freeze.

Primary evidence: `docs/D119_DOGFOOD_LOG.md`.

## Current baseline integrity

| Check | Status | Evidence / action |
|---|---|---|
| Immutable release candidate revision | BLOCKED | The checkout contains uncommitted edits to the frozen contract, parser, interpreter, runtime, UI/library modules, tests, project manifests, examples, and `OtterWorkspace`. The owner must commit or otherwise preserve this work and nominate its commit SHA before final certification. |
| Frozen language contract | BLOCKED | Do not edit `Otter.Contract.psm1`, `rules.md`, or `SPEC-DECISIONS.md` as part of a release gate. Record their committed SHA after the baseline is clean. |
| Existing scope reconciliation | REVIEW REQUIRED | `docs/OTTER_1_0_RELEASE_SCOPE_MATRIX.md` and `docs/OTTER_1_0_RELEASE_GATE_CERTIFICATION.md` currently classify modules as deferred and packaging as implemented but not production-certified. Those classifications conflict with broader claims in the D119 handoff and must be explicitly reconciled by Jeff before 1.0 scope is frozen. |

## Gate 1 — Final language and standard-library contract freeze

| Requirement | Status | Evidence / next action |
|---|---|---|
| Freeze language surface | BLOCKED | First create a clean release-candidate commit; then record the SHAs for `rules.md`, `SPEC-DECISIONS.md`, and `Otter.Contract.psm1`. |
| No unmapped diagnostics | PENDING | Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1` from the clean candidate and archive the result. |
| Documented public keywords and target boundaries | PENDING | Reconcile public docs against the frozen rules and scope matrix; target-specific features must be labelled at point of use. |

## Gate 2 — D120 cross-platform and runtime certification

### Required host matrix

| Host / target | Status | Evidence |
|---|---|---|
| Windows PowerShell 5.1 | PROVISIONAL PASS | This host is Windows PowerShell **5.1.26100.8115** on Windows NT 10.0.26200.0. The distribution smoke test passed on 2026-09-25; see Gate 4. The result is provisional because the baseline is dirty. |
| PowerShell 7 on Windows | BLOCKED | `pwsh` is not installed on this host. Install PowerShell 7, then run the release conformance manifest and full suite from the nominated clean SHA. |
| PowerShell 7 on Linux | BLOCKED | No Linux host is available in this environment. Run the same immutable release candidate on a supported Linux CI runner. |
| PowerShell 7 on macOS | BLOCKED | No macOS host is available in this environment. Run the same immutable release candidate on a supported macOS CI runner. |
| Headless Web target | PROVISIONAL PASS | The release conformance manifest exercises generated web fixtures and finds a local headless Edge/Chromium executable when available. Record the completed manifest result against the clean candidate. |

### Minimum D120 evidence per host

1. Run `otter --version`.
2. Run `otter check`, `otter run`, `otter new`, `otter test`, `otter build`, and
   `otter publish` against temporary fixtures.
3. Run `tools/Test-OtterReleaseConformance.ps1` or its host-neutral successor.
4. Record OS, host version, architecture, commit SHA, exact command, exit code,
   and failures/skips. A Windows-only provider must be recorded as
   target-specific, not as cross-platform parity.

## Gate 3 — Hardening, fuzzing, and conformance

| Requirement | Status | Next command / evidence |
|---|---|---|
| Production-entry conformance manifest | IN PROGRESS | `tools/Test-OtterReleaseConformance.ps1` was started on 2026-09-25 against the dirty workspace. Do not call it a pass until its process exits successfully and the clean-candidate run is archived. |
| Lexer/parser malformed-input coverage | PENDING | Preserve and run the parser fuzz assertions in `tests/Parser.Tests.ps1`; run the differential fuzzer on the clean candidate. |
| Differential fuzzing | PENDING | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Invoke-OtterDifferentialFuzzer.ps1` with a recorded seed and iteration count. |
| Resource/memory soak | PENDING | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Test-ResourceSoak.ps1`; archive the generated report and ensure it is reviewed. |
| Full platform regression suite | PENDING | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1` from the clean candidate. |

## Gate 4 — Fresh-install and packaging verification

| Requirement | Status | Evidence |
|---|---|---|
| Distribution build and temporary install | PROVISIONAL PASS | On 2026-09-25, `tools/Test-OtterDistribution.ps1` built `otter-0.9.0-windows-powershell`, installed it into a fresh temp directory, and passed `--version`, `run` fixtures, and `web -NoOpen`. The test cleans up its temporary install. |
| Clean-machine validation | PENDING | Repeat on a VM or CI host with no source checkout, no inherited PATH entries, and no developer dependencies. |
| Per-user installer / uninstaller | PENDING | Exercise `distribution/Install-Otter.ps1` and `distribution/Uninstall-Otter.ps1` on the clean machine, including upgrade and PATH behavior. |
| Full public CLI workflow | PENDING | Prove `--version`, `new`, `check`, `test`, `run`, `build`, and `publish` from the installed payload. |

## Gate 5 — Documentation and release freeze

| Requirement | Status | Next action |
|---|---|---|
| Language and standard-library reference | PENDING | Reconcile documentation with the approved frozen scope. |
| CLI and project-system guide | PENDING | Validate each documented command against the installed release payload. |
| Target-specific boundaries | PENDING | Mark web-only, Windows-only, experimental, and deferred capabilities clearly. |
| Changelog and release notes | PENDING | Finalize `CHANGELOG.md` only after the release-candidate SHA and scope are approved. |
| RC change freeze | PENDING | After all gates pass, tag `1.0.0-rc.1`; permit bug fixes only, each with a regression test and release-ledger update. |

## Resume protocol

1. **Owner of the active backend work:** commit the current logical changes or
   save them to a branch before the session expires. Do not rely on chat
   context to preserve uncommitted work.
2. Record the nominated candidate SHA in this file and ensure `git status` is
   clean.
3. Run Gates 1–5 in order; update only evidence actually reproduced on that
   SHA.
4. Run D120 on Windows PowerShell 5.1, PowerShell 7/Windows, Linux, and macOS.
5. Do not tag an RC or 1.0.0 until every required row is **CERTIFIED** or
   explicitly deferred by Jeff with a public scope note.
