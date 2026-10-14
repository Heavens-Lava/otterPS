# Otter 1.0.0-rc.13 — release evidence

Candidate: `084f9c7d6af1bebafc300fc357db597c6c5c0c9e` (`VERSION` 1.0.0-rc.13),
**not tagged yet**. rc.12 (`7de6c5a`, certified but superseded; see
`docs/OTTER_1_0_RC12_EVIDENCE.md`) plus:

- `2821fae` — Windows PowerShell 5.1 ignores PowerShell 7's module folders,
  so `otter publish` works from a PowerShell 7 terminal on Windows (found by
  the D120 host matrix; ProjectPublish test 25);
- `981ec22` — website corrections: the Download page no longer says open
  source, lists macOS and Linux as supported, describes the zip and checksum,
  and notes the 1-4 second start-up; About no longer says Windows only;
- `084f9c7` — version 1.0.0-rc.13, changelog `[1.0.0-rc.13]`, release
  checklist candidate line corrected (it still said rc.10).

Release archive: `otter-1.0.0-rc.13.zip`, 437,268 bytes, SHA-256
`5FFA4CE079CD39238C2CE0886D3793504E0F74752BD55C5AE8EEAEE3D17ECA34`
(built from this commit with Windows PowerShell 5.1 by
`tools/New-OtterDistribution.ps1`).

| Check | Result | Where |
|---|---|---|
| Release certification, clean checkout, Windows PowerShell 5.1 | **Pass.** All eight gates: contract structure; platform regression 64/64 test files; conformance 15/15; differential fuzz 1,000/1,000; malformed-input fuzz 1,000/1,000; release-surface audit; distribution smoke; repository clean afterwards. | `tools/Invoke-OtterReleaseCertification.ps1`, 2026-10-14, record `20261014T174435Z-084f9c7` |
| D120 four-host workflow, this commit | **Pass, 7 of 7 jobs**: the release archive built on Windows PowerShell 5.1, then installed and tested on GitHub's Linux and macOS runners; the portable suites on Windows PowerShell 5.1, PowerShell 7 on Windows, PowerShell 7 on macOS and PowerShell 7 on Linux. The first run of this workflow (rc.12, run 38603948010) failed only PowerShell 7 on Windows - the bug fixed here; run 38609074425 on the fix passed 7 of 7. | GitHub Actions run 38624116578 |
| Windows PowerShell 5.1 recursion probe | **Pass**, 24 of 24 cases. | `tools/Test-OtterRecursionProbe.ps1`, PowerShell 5.1.26100.8115 |
| Desktop (WPF) smoke test | **Pass**, 9 of 9 checks. | `tools/Test-OtterDesktopSmoke.ps1`, PowerShell 5.1.26100.8115 |
| Earlier run of the two checks above | **Failed** (6 recursion cases, 2 desktop checks) with "There is not enough space on the disk": the release machine's drive had 1.7 GB free. Both passed after old test checkouts were removed. Not an Otter defect. | 2026-10-14 |
| macOS, hands-on | **Carried from rc.12** (`docs/OTTER_MACOS_RESULTS_bb43658.md`): rc.13's code change runs only on Windows PowerShell 5.1, and the macOS runner above passes. | — |
| Hands-on project (a person writing Otter by hand) | **Pending**: Jeff. | — |
| Fresh-machine test (Windows) | **Not run.** | — |

All certification records are kept in `otter-certification-records` beside
the repository.
