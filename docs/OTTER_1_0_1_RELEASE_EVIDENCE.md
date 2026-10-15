# Otter 1.0.1 — release evidence

Release: `cfb657c` (`VERSION` 1.0.1), tagged `v1.0.1` on 2026-10-15. A
maintenance release of Otter 1.0.0; what changed is in `CHANGELOG.md`
([1.0.1]).

Release archive: `otter-1.0.1.zip`, 440,190 bytes, SHA-256
`B70FF7D6D6A47BD477499CAC48B681FAF0826CC03A1E77B1AFB0F39A66826A87`
(built from this commit in a clean worktree with Windows PowerShell 5.1 by
`tools/New-OtterDistribution.ps1`), published on GitHub Releases; the
downloaded file was checked against this checksum.

| Check | Result | Where |
|---|---|---|
| Release certification, clean checkout, Windows PowerShell 5.1 | **Pass.** All nine gates: contract structure; platform regression (65 of 65 test files); conformance 15/15; differential fuzz 1,000/1,000; malformed-input fuzz 1,000/1,000; release-surface audit; distribution smoke; documentation samples (new: 221 samples, every website Run button pressed in headless Chromium, every README and TOUR block run); repository unchanged afterwards. | `tools/Invoke-OtterReleaseCertification.ps1`, record `20261015T163245Z-cfb657c` |
| D120 four-host workflow, this commit | **Pass, 7 of 7 jobs** (Windows PowerShell 5.1; PowerShell 7 on Windows, macOS and Linux; the release archive built on Windows and installed and tested on macOS and Linux). | GitHub Actions run 38769892911 |
| D133 on Windows (the first branch's console test was pending a Windows run) | Found and fixed before merging: every console/desktop button click failed, and functions called by a handler could not see its names. Console UI tests 95/95, browser 14/14, network tests 10 consecutive runs 23/23. | `tests/UI.Tests.ps1`, `tests/WebRuntimeUi.Tests.ps1`, `tests/Network.Tests.ps1` |
| Outside review (ChatGPT, of the 1.0.0 source archive and the D133 wording) | Two documentation findings fixed (README status, which ZIP to download); D133 wording reviewed and amended, approved by Jeff. | — |

All certification records are kept in `otter-certification-records` beside
the repository.
