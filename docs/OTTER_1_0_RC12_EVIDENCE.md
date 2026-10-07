# Otter 1.0.0-rc.12 — release evidence

Candidate: `1b1c49282fd5179b29ca0eccca1d5a31b728bc91` (`VERSION` 1.0.0-rc.12),
**not tagged yet**. rc.11 (`9e7cdac`, certified but superseded; see
`docs/OTTER_1_0_RC11_EVIDENCE.md`) plus:

- `89b8ab0` — a built app's `run.cmd` (and the desktop launcher) quotes its
  path, so apps in folders with spaces run;
- `0f588c1`, `49b1446` — `otter run` uses the compiled engine
  (`src/Otter.Compiler.Native.psm1`) for programs it can compile, with the
  interpreter as fallback before anything runs; compiled-runtime fixes
  (seeded random, bytes display and equality, HTTP options); processes, HTTP
  and sockets stay on the interpreter; `tests/CompiledRun.Tests.ps1`;
- `1b1c492` — version 1.0.0-rc.12, changelog `[1.0.0-rc.12]`.

Release archive: `otter-1.0.0-rc.12.zip`, 436,870 bytes, SHA-256
`8531E38872F0155BEA8C21A0F18120E709B7F0717510E5BF43FB37D3290ADDF2`
(built from this commit with Windows PowerShell 5.1 by
`tools/New-OtterDistribution.ps1`).

| Check | Result | Where |
|---|---|---|
| Release certification, clean checkout, Windows PowerShell 5.1 | **Pass.** All eight gates: contract structure; platform regression 64/64 test files (the compiled engine is the default for every `otter run` in them); conformance 15/15; differential fuzz 1,000/1,000; malformed-input fuzz 1,000/1,000; release-surface audit; distribution smoke; repository clean afterwards. | `tools/Invoke-OtterReleaseCertification.ps1`, 2026-10-06, record `20261006T235517Z-1b1c492` |
| Compiled engine against the interpreter | **Pass.** Differential fuzzer with `-IncludeNative`: 1,000/1,000 programs identical; `experiments/native-compiler/cases` 34/34; benchmarks 14/15 compiled and identical (`event_dispatch` uses UDP and stays on the interpreter). | 2026-10-06, commit `49b1446` |
| Windows PowerShell 5.1 recursion probe | **Pass**, 24 of 24 cases. | `tools/Test-OtterRecursionProbe.ps1`, PowerShell 5.1.26100.8115 |
| Desktop (WPF) smoke test | **Pass**, 9 of 9 checks. | `tools/Test-OtterDesktopSmoke.ps1`, PowerShell 5.1.26100.8115 |
| Linux, this commit | **Pass.** Clean container (PowerShell 7.4.2, Ubuntu 22.04, Node.js 20): the Windows-built archive above unzipped, run directly, installed twice, the project workflow and the built app's `dist/run` run through the installed `otter`, uninstalled; the 24 D120 portable suites and `CompiledRun.Tests.ps1` pass. | Docker Desktop on the release machine, 2026-10-07 |
| macOS, hands-on | **Pass.** macOS 26.1 arm64, PowerShell 7.6.6, at `bb43658` (this commit plus the evidence file): distribution test; documented CLI 28/28; the 25 portable suites including `CompiledRun.Tests.ps1`; the Windows-built archive above extracted with `ditto`, installed, project workflow, built app, uninstalled (25/25); `otter web` opened the default browser; the compiled engine ran the loop program. | `docs/OTTER_MACOS_RESULTS_bb43658.md` |
| Hands-on project (a person writing Otter by hand) | **Pending**: Jeff. | — |
| D120 four-host workflow, this commit | **Not run** (GitHub Actions account spending limit). | — |
| Fresh-machine test (Windows) | **Not run.** | — |

Speed (this machine, best of three, Windows PowerShell 5.1): `say "hi"` 1.4 s
on both engines; adding 1 to 20,000 in a loop 6.5 s interpreted, 1.45 s
compiled; 200,000 steps 1.5 s compiled. Python 3.11 runs both in 0.03 s: most
of Otter's remaining time is Windows PowerShell starting.

On the Mac (PowerShell 7.6.6, arm64) the same 20,000-step program took 3.9 s
compiled and 8.7 s interpreted: PowerShell 7 starts more slowly there than
Windows PowerShell 5.1 does on Windows. Startup is the main Otter 1.1 speed
work.

All certification records are kept in `otter-certification-records` beside
the repository.
