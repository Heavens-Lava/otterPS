# Otter 1.0.0-rc.8 — release evidence

Candidate: `640421159186fe56ce80d314713635bf558ef6a4` (`VERSION` 1.0.0-rc.8),
**not tagged yet**. rc.7 (`85227ab`, certified but superseded; see
`docs/OTTER_1_0_RC7_EVIDENCE.md`) plus fixes for three silent wrong answers,
found while verifying the OtterBoard 1.1 proposals against rc.7:

- `5e210aa` — web: file operations in a plain browser tab are errors (D131);
  a top-level `has` with a variable uses the variable's value;
- `9a67829` — a handler set up during a loop pass remembers that pass, on the
  console and the web (D130; `src/Otter.LoopPasses.psm1`);
- `6404211` — version 1.0.0-rc.8, changelog `[1.0.0-rc.8]`, D130 and D131 in
  `SPEC-DECISIONS.md`.

Release archive: `otter-1.0.0-rc.8.zip`, 412,019 bytes, SHA-256
`3CA5EC25F7731CE983FACD8576AD893B35E5E4ABA75338A23CC5B476EE65C3A5`
(built from this commit with Windows PowerShell 5.1 by
`tools/New-OtterDistribution.ps1`).

| Check | Result | Where |
|---|---|---|
| Release certification, clean checkout, Windows PowerShell 5.1 | **Pass.** All eight gates: contract structure; platform regression 63/63 test files (including the D130 console and browser tests and the D131 browser test); conformance 15/15; differential fuzz 1,000/1,000; malformed-input fuzz 1,000/1,000; release-surface audit; distribution smoke (installing from the archive); repository clean afterwards. | `tools/Invoke-OtterReleaseCertification.ps1`, 2026-09-30, record `20260930T051217Z-6404211` (copy kept in `otter-certification-records` beside the repository) |
| Windows PowerShell 5.1 recursion probe | **Pass**, 24 of 24 cases. | `tools/Test-OtterRecursionProbe.ps1`, PowerShell 5.1.26100.8115 |
| Desktop (WPF) smoke test | **Pass**, 9 of 9 checks. | `tools/Test-OtterDesktopSmoke.ps1`, PowerShell 5.1.26100.8115 |
| Linux, this commit | **Pass.** Clean container (`mcr.microsoft.com/powershell`, PowerShell 7.4.2 on Ubuntu 22.04, Node.js 20): the Windows-built archive above unzipped with `unzip`, `./otter` run directly, installed twice with `-AddToUserPath`, programs and `otter web` run, uninstalled; the 24 D120 portable suites pass, including the platform-boundary suite. The browser half of `WebRuntimeUi.Tests.ps1` needs playwright-core and ran on Windows only. | Docker Desktop on the release machine, 2026-09-30 |
| D120 four-host workflow, this commit | **Not run** (GitHub Actions account spending limit). The archive fix passed all seven jobs, including the Windows-built archive on Linux and macOS, in [run 36657373162](https://github.com/Heavens-Lava/otterPS/actions/runs/36657373162). | — |
| macOS, hands-on | **Pending.** Jeff's Mac: Finder extraction, `./otter`, install, `otter web`, `otter desktop` refusal, uninstall. | — |
| Fresh-machine test (Windows) | **Not run.** Needs a machine or VM that has never had Otter. | — |
