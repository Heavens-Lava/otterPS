# Otter 1.0.0-rc.9 — release evidence

Candidate: `b8d91905c982ec9512f1b2a024a32cc927feccb7` (`VERSION` 1.0.0-rc.9),
**not tagged yet**. rc.8 (`6404211`, certified but superseded; see
`docs/OTTER_1_0_RC8_EVIDENCE.md`) plus:

- `f63b3dc` — built and published console apps get a `run` launcher for macOS
  and Linux beside `run.cmd` (D129);
- `7d1dc7b` — `otter help` lists `otter serve`;
- `f02b20a` — D130's scope per loop pass only for loops that set up a handler;
- `0ae3636`, `7d1dc7b`, `110b78f`, `5e1e024`, `c404ef8`, `6673565`, `9012008`,
  `080fcf2` — verification tools, the reviewed soak, documentation
  reconciliation, the benchmark suite and 1.0 baseline, the macOS install test;
- `b8d9190` — version 1.0.0-rc.9, changelog `[1.0.0-rc.9]`.

Release archive: `otter-1.0.0-rc.9.zip`, 412,848 bytes, SHA-256
`D5E550450271AC03F5C4FB2E09620A26F99B9DEEDB84E93C7EB1CA6CB5C0D4B1`
(built from this commit with Windows PowerShell 5.1 by
`tools/New-OtterDistribution.ps1`).

| Check | Result | Where |
|---|---|---|
| Release certification, clean checkout, Windows PowerShell 5.1 | **Pass.** All eight gates: contract structure; platform regression 63/63 test files; conformance 15/15; differential fuzz 1,000/1,000; malformed-input fuzz 1,000/1,000; release-surface audit; distribution smoke; repository clean afterwards. | `tools/Invoke-OtterReleaseCertification.ps1`, 2026-10-01, record `20261001T030700Z-b8d9190` |
| Earlier certification run of the same commit | **Failed one test**, then passed on re-run: `tests/Part3.Tests.ps1` D67 clipboard round-trip. The test uses the real Windows clipboard; other jobs were running on the machine at the time; the same file passed alone (93/93) and in the clean re-run above. rc.9 changes no clipboard code. | record `20261001T023056Z-b8d9190` |
| Windows PowerShell 5.1 recursion probe | **Pass**, 24 of 24 cases. | `tools/Test-OtterRecursionProbe.ps1`, PowerShell 5.1.26100.8115 |
| Desktop (WPF) smoke test | **Pass**, 9 of 9 checks. | `tools/Test-OtterDesktopSmoke.ps1`, PowerShell 5.1.26100.8115 |
| Linux, this commit | **Pass.** Clean container (PowerShell 7.4.2, Ubuntu 22.04, Node.js 20): the Windows-built archive above unzipped, run directly, installed twice, the project workflow (`new`, `check`, `test`, `run`, `build`, `publish`) and the built app's `dist/run` run through the installed `otter`, uninstalled; the 24 D120 portable suites pass. | Docker Desktop on the release machine, 2026-10-01 |
| D120 four-host workflow, this commit | **Not run** (GitHub Actions account spending limit). | — |
| macOS, hands-on | **In progress** on Jeff's Mac (`docs/MACOS_AGENT_TEST.md`). | — |
| Fresh-machine test (Windows) | **Not run.** | — |

All certification records are kept in `otter-certification-records` beside
the repository.
