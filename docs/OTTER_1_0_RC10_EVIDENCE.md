# Otter 1.0.0-rc.10 — release evidence

Candidate: `3ba7890391356d9b40cb5cf6052afe1de2ac69de` (`VERSION` 1.0.0-rc.10),
**not tagged yet**. rc.9 (`b8d9190`, certified but superseded; see
`docs/OTTER_1_0_RC9_EVIDENCE.md`) plus:

- `d70201f` — the macOS hands-on results for `080fcf2`
  (`docs/OTTER_MACOS_RESULTS_080fcf2.md`);
- `9eedd68` — `otter web` opens the page with `open` / `xdg-open` on macOS
  and Linux (on macOS it could never open a browser), a HostPortability test
  for it, and the macOS agent test guide corrections;
- `3ba7890` — version 1.0.0-rc.10, changelog `[1.0.0-rc.10]`.

Release archive: `otter-1.0.0-rc.10.zip`, 413,322 bytes, SHA-256
`06EEBC41C1AB3C29ECE6242F04670C8650905F2FE6A2CAED491CB3157ACA0E49`
(built from this commit with Windows PowerShell 5.1 by
`tools/New-OtterDistribution.ps1`).

| Check | Result | Where |
|---|---|---|
| Release certification, clean checkout, Windows PowerShell 5.1 | **Pass.** All eight gates: contract structure; platform regression 63/63 test files; conformance 15/15; differential fuzz 1,000/1,000; malformed-input fuzz 1,000/1,000; release-surface audit; distribution smoke; repository clean afterwards. | `tools/Invoke-OtterReleaseCertification.ps1`, 2026-10-01, record `20261001T183151Z-3ba7890` |
| Windows PowerShell 5.1 recursion probe | **Pass**, 24 of 24 cases. | `tools/Test-OtterRecursionProbe.ps1`, PowerShell 5.1.26100.8115 |
| Desktop (WPF) smoke test | **Pass**, 9 of 9 checks. | `tools/Test-OtterDesktopSmoke.ps1`, PowerShell 5.1.26100.8115 |
| Linux, this commit | **Pass.** Clean container (PowerShell 7.4.2, Ubuntu 22.04, Node.js 20): the Windows-built archive above unzipped, run directly, installed twice, the project workflow and the built app's `dist/run` run through the installed `otter`, uninstalled; the 24 D120 portable suites pass, including the new system-opener test. | Docker Desktop on the release machine, 2026-10-01 |
| macOS, hands-on | **Earlier code passed except `otter web`** (`080fcf2`: distribution, documented CLI 28/28, 24 portable suites on macOS 26.1 arm64, PowerShell 7.6.6). Re-run of this commit, including the real-download test, **pending** on Jeff's Mac. | `docs/OTTER_MACOS_RESULTS_080fcf2.md`, `docs/MACOS_AGENT_TEST.md` |
| D120 four-host workflow, this commit | **Not run** (GitHub Actions account spending limit). | — |
| Fresh-machine test (Windows) | **Not run.** | — |

All certification records are kept in `otter-certification-records` beside
the repository.
