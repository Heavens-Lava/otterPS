# Otter 1.0 Release Checklist

**Purpose:** This is the durable release ledger for the Otter 1.0 transition.
It records reproducible evidence, release decisions, environmental limits, and
the next command for each gate. It is not a substitute for a clean commit or
for an owner approving a release.

## Release rule

No item may be marked **CERTIFIED** unless it was run against a clean,
immutable revision and its evidence is recorded below. A passing run against a
dirty working tree is useful diagnostic evidence, but is **PROVISIONAL**.

## Release order (decided by Jeff, 2026-09-28)

The release candidate in preparation is **1.0.0-rc.10** (`VERSION`): rc.5 plus
macOS and Linux installation (D129), a release archive that extracts
correctly on macOS and Linux, the D130/D131 fixes for silent wrong answers,
a `run` launcher for built apps on macOS and Linux, `otter web` opening
the browser on macOS, the parser follow-ups (D27 `replace ... into`,
D32.3 variable date amounts), and the compiled engine for `otter run`. It is
**not certified yet**
and not tagged; the certification record will name its exact SHA. rc.6
(`145b15e`), rc.7 (`3cc888f`), rc.8 (`16a2e88`), rc.9 (`b9117a8`), rc.10
(`7dfcdfe`) and rc.11 (`8c6ae68`) each passed certification and were
superseded before publication; none is tagged. `v1.0.0-rc.5`
(`docs/OTTER_1_0_RC5_EVIDENCE.md`), `v1.0.0-rc.4`
(`docs/OTTER_1_0_RC4_EVIDENCE.md`) and `v1.0.0-rc.3` remain tagged on their
own certified commits.
RC2 (`19bc37b`) was superseded before its certification by the blockers the
production-readiness audit found; it is not tagged.
The name `v1.0.0-rc.1` is taken: it is the 2026-09-11 baseline checkpoint,
tagged before the 1.0 scope was widened, and it stays as history.

1. **Before the RC tag:** the candidate SHA passes (a) release certification
   (`tools/Invoke-OtterReleaseCertification.ps1`) from a clean checkout on
   Windows PowerShell 5.1 with all 8 checks passing, including
   `repository-clean`, and (b) the D120 four-host workflow on the same SHA.
2. **During RC stabilization, before 1.0.0:** clean-machine install, installer
   and uninstaller, the full public CLI workflow from the installed payload,
   console/web/desktop smoke apps built from the RC distribution, a literal
   walkthrough of the installation and Getting Started docs, and the final
   security/data-loss review. Rows marked **BEFORE 1.0.0** below are these
   gates; they are deliberately not preconditions for the RC tag.
3. **1.0.0:** final certification of the production SHA, release artifacts
   and checksums from that SHA, then the `v1.0.0` tag.

A commit cannot record its own SHA. Rows marked **RC CERTIFICATION** are
proven by the certification record and CI run of the candidate SHA; their
evidence is added here after those runs, without changing the tagged commit.

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
| Immutable release candidate revision | RC CERTIFICATION | All work is committed; the candidate is the rc.12 commit (`VERSION` 1.0.0-rc.12). The certification record names its exact SHA and requires a clean checkout. |
| Frozen language contract | RESOLVED | Every 1.0 contract decision is recorded in `SPEC-DECISIONS.md` (DC1, D121, D122 approved 2026-09-27; D99 deferred to 1.1 on 2026-09-28). No contract question remains open: `docs/OTTER_1_0_FREEZE_FOLLOWUPS.md`. |
| Existing scope reconciliation | RESOLVED | DC1 (console HTTP) was decided 2026-09-27; DC2-DC5 were resolved in the RC3 documentation pass (2026-09-28). Each is recorded with its decision in `docs/OTTER_1_0_SURFACE_RECONCILIATION.md` section 8. |

## Gate 1 — Final language and standard-library contract freeze

| Requirement | Status | Evidence / next action |
|---|---|---|
| Freeze language surface | RC CERTIFICATION | Gates `contract-structural` and `release-surface-audit`. Prior clean-checkout evidence: `docs/OTTER_1_0_CERTIFICATION_RUN_639112f.md`. |
| No unmapped diagnostics | RC CERTIFICATION | Gate `platform-regression` (`tests/Run-Tests.ps1`). |
| Documented public keywords and target boundaries | BEFORE 1.0.0 | Reserved words: `docs/OTTER_1_0_RESERVED_WORDS.md` and the site's Reference page (D124). Target boundaries labelled at point of use on branch `docs/target-boundaries` (desktop windows, controls, credential vault and running programs need Windows; five pages no longer say Otter is Windows-only). Done when merged. |

## Gate 2 — D120 cross-platform and runtime certification

### Required host matrix

| Host / target | Status | Evidence |
|---|---|---|
| Windows PowerShell 5.1 | RC CERTIFICATION | The full certification run, plus the D120 workflow's Windows PowerShell 5.1 job. |
| PowerShell 7 on Windows | RC CERTIFICATION | D120 workflow (`.github/workflows/d120-host-matrix.yml`) on the candidate SHA. Prior evidence: run 36374374754 passed on `940de6b`. |
| PowerShell 7 on Linux | RC CERTIFICATION | D120 workflow on the candidate SHA. |
| PowerShell 7 on macOS | RC CERTIFICATION | D120 workflow on the candidate SHA. |
| Headless Web target | RC CERTIFICATION | Gate `conformance` (`tools/Test-OtterReleaseConformance.ps1`). |

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
| Production-entry conformance manifest | RC CERTIFICATION | Gate `conformance`. |
| Lexer/parser malformed-input coverage | RC CERTIFICATION | Gate `malformed-input-fuzz` (1,000 programs, recorded seed). |
| Differential fuzzing | RC CERTIFICATION | Gate `differential-fuzz` (1,000 programs, recorded seed). |
| Resource/memory soak | BEFORE 1.0.0 | `tools/Test-ResourceSoak.ps1` is not a certification gate; run it on the RC and archive the reviewed report. |
| Full platform regression suite | RC CERTIFICATION | Gate `platform-regression`; gate `repository-clean` proves the suite leaves the checkout unchanged. |

## Gate 4 — Fresh-install and packaging verification

| Requirement | Status | Evidence |
|---|---|---|
| Distribution build and temporary install | RC CERTIFICATION | Gate `distribution-smoke` (`tools/Test-OtterDistribution.ps1`) builds `otter-<version>.zip`, extracts it (`unzip` on macOS and Linux), installs it into a fresh temp directory and runs `--version`, `run` fixtures and `web -NoOpen` through the installed launcher; on macOS and Linux it also checks `~/.local/bin/otter`, a second install and the uninstaller (D129). |
| Clean-machine validation | BEFORE 1.0.0 | Repeat on a VM or CI host with no source checkout, no inherited PATH entries, and no developer dependencies. |
| Per-user installer / uninstaller | BEFORE 1.0.0 | Exercise `distribution/Install-Otter.ps1` and `distribution/Uninstall-Otter.ps1` on the clean machine, including upgrade and PATH behavior. |
| Full public CLI workflow | BEFORE 1.0.0 | Proven from the installed payload on Windows PowerShell 5.1 and Linux (PowerShell 7) on branch `release/installed-cli-workflow`: `tools/Test-OtterDistribution.ps1` runs `new`, `check`, `test`, `run`, `build` and `publish` through the installed launcher. macOS pending. |

## Gate 5 — Documentation and release freeze

| Requirement | Status | Next action |
|---|---|---|
| Language and standard-library reference | BEFORE 1.0.0 | Reconciled with D122-D131 on branch `docs/reference-reconciliation`: arithmetic in comparisons (D123; the Conditions page and `docs/GRAMMAR.md` still said "put it in a variable first"), exact `use` paths (D122), offline web pages (D127), loop handlers (D130), browser file errors (D131), and browser cryptography (D114; two pages said the web does not support it). Done when merged. |
| CLI and project-system guide | BEFORE 1.0.0 | `tools/Test-OtterDocumentedCli.ps1` checks 28 claims from the CLI and Projects pages against the installed payload: Windows PowerShell 5.1 27/28, Linux 28/28 (branch `docs/cli-guide-validation`). Open: an ambiguous short flag (`-p`) prints PowerShell's own binding error, not an Otter message (D14); `otter debug` and `otter profile` work but are undocumented (scope decision). |
| Target-specific boundaries | BEFORE 1.0.0 | Mark web-only, Windows-only, experimental, and deferred capabilities clearly. The query language (D99) is already labelled "not part of Otter 1.0" on the docs site. |
| Changelog and release notes | IN PROGRESS | `CHANGELOG.md` has the `[1.0.0-rc.3]`, `[1.0.0-rc.4]`, `[1.0.0-rc.5]`, `[1.0.0-rc.6]`, `[1.0.0-rc.7]`, `[1.0.0-rc.8]`, `[1.0.0-rc.9]`, `[1.0.0-rc.10]`, `[1.0.0-rc.11]` and `[1.0.0-rc.12]` sections; final 1.0.0 release notes are written from the production SHA. |
| RC change freeze | PENDING | After the two pre-RC checks in "Release order" pass, tag `v1.0.0-rc.3` on the certified SHA; then permit release-blocking fixes only, each with a regression test and release-ledger update. |

## Resume protocol

1. **Owner of the active backend work:** commit the current logical changes or
   save them to a branch before the session expires. Do not rely on chat
   context to preserve uncommitted work.
2. Record the nominated candidate SHA in this file and ensure `git status` is
   clean.
3. Run Gates 1–5 in order; update only evidence actually reproduced on that
   SHA.
4. Run D120 on Windows PowerShell 5.1, PowerShell 7/Windows, Linux, and macOS.
5. Do not tag an RC until the two pre-RC checks in "Release order" pass on
   the exact candidate SHA. Do not tag 1.0.0 until every row is **CERTIFIED**
   or explicitly deferred by Jeff with a public scope note.
