# Otter 1.0.0 — release evidence

Release: `6cbbc97546ec774359b938b9b1548ebc150c9927` (`VERSION` 1.0.0), tagged
`v1.0.0`. It is rc.14 (`8667e6c`, see `docs/OTTER_1_0_RC13_EVIDENCE.md` and
the rc.14 entries below) with its version set to 1.0.0, the release notes,
and the website's Download page linking to the release; nothing else in Otter
changed.

Release archive: `otter-1.0.0.zip`, 438,359 bytes, SHA-256
`62DC15966CC8C3454134C4A04071FEB06ADDC223A656367DF9F77700FE0839E1`
(built from this commit with Windows PowerShell 5.1 by
`tools/New-OtterDistribution.ps1`), published on GitHub Releases.

| Check | Result | Where |
|---|---|---|
| Release certification, clean checkout, Windows PowerShell 5.1 | **Pass.** All eight gates: contract structure; platform regression (every test file); conformance 15/15; differential fuzz 1,000/1,000; malformed-input fuzz 1,000/1,000; release-surface audit; distribution smoke; repository clean afterwards. | `tools/Invoke-OtterReleaseCertification.ps1`, 2026-10-14, record `20261014T213534Z-6cbbc97` |
| D120 four-host workflow, this commit | **Pass, 7 of 7 jobs**: the release archive built on Windows PowerShell 5.1, then installed and tested on GitHub's Linux and macOS runners; the portable suites on Windows PowerShell 5.1, PowerShell 7 on Windows, PowerShell 7 on macOS and PowerShell 7 on Linux. | GitHub Actions run 38641449614 |
| Windows PowerShell 5.1 recursion probe | **Pass**, 24 of 24 cases. | `tools/Test-OtterRecursionProbe.ps1` |
| Desktop (WPF) smoke test | **Pass**, 9 of 9 checks. | `tools/Test-OtterDesktopSmoke.ps1` |
| rc.14 (`8667e6c`, the same Otter) | **Pass**: certification `20261014T205324Z-8667e6c` (8 gates) and four-host CI run 38635845278 (7 of 7). | — |
| macOS, hands-on | **Pass** on rc.12 (`docs/OTTER_MACOS_RESULTS_bb43658.md`); the macOS CI runner passes on this commit. | — |
| A full application written against Otter | The "Build a Task Tracker in Otter" tutorial series (10 parts, 49 programs; written with an AI assistant, not by hand) found the two bugs fixed in rc.14; all 49 programs pass `otter check` on this release. | `Heavens-Lava/tutorials` |
| A person writing Otter by hand | **Not done before release** (Jeff's decision, 2026-10-14). | — |
| Fresh-machine test (Windows) | **Not run.** | — |

All certification records are kept in `otter-certification-records` beside
the repository.
