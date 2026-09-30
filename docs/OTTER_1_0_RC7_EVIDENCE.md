# Otter 1.0.0-rc.7 — release evidence

Candidate: `85227abee6913d8f9d1d3a63ec9b7735af750ea3` (`VERSION` 1.0.0-rc.7).
**Superseded by rc.8 before publication, not tagged:** verifying the OtterBoard
proposals against rc.7 found three silent wrong answers (D130, D131 and the
web `has` fix; see `CHANGELOG.md` `[1.0.0-rc.8]`). rc.6 (`95b9d40`, certified but superseded; see
`docs/OTTER_1_0_RC6_EVIDENCE.md`) plus:

- `c9d7569` — the release archive uses forward-slash paths and Unix modes
  (`otter` 755), so it extracts correctly on macOS and Linux; the installer's
  `-AddToUserPath` works when run a second time;
- `3079104` — the D120 host matrix builds the archive on Windows PowerShell 5.1
  and unzips, installs, runs and uninstalls that same file on Linux and macOS;
- `85227ab` — version 1.0.0-rc.7, changelog `[1.0.0-rc.7]`.

Release archive: `otter-1.0.0-rc.7.zip`, 408,077 bytes, SHA-256
`55EB8F0FC875584C57738145EFADB05EA9FD30F74355FE55A662D00394B6DE8B`
(built from this commit with Windows PowerShell 5.1 by
`tools/New-OtterDistribution.ps1`).

| Check | Result | Where |
|---|---|---|
| Release certification, clean checkout, Windows PowerShell 5.1 | **Pass.** All eight gates: contract structure; platform regression 63/63 test files; conformance 15/15; differential fuzz 1,000/1,000; malformed-input fuzz 1,000/1,000; release-surface audit; distribution smoke (installing from the archive); repository clean afterwards. | `tools/Invoke-OtterReleaseCertification.ps1`, 2026-09-30 (record `20260930T022634Z-85227ab`) |
| Windows PowerShell 5.1 recursion probe | **Pass**, 24 of 24 cases. | `tools/Test-OtterRecursionProbe.ps1`, PowerShell 5.1.26100.8115 |
| Desktop (WPF) smoke test | **Pass**, 9 of 9 checks. | `tools/Test-OtterDesktopSmoke.ps1`, PowerShell 5.1.26100.8115 |
| Linux, this commit | **Pass.** In a clean container (`mcr.microsoft.com/powershell`, PowerShell 7.4.2 on Ubuntu 22.04): the Windows-built archive above unzipped with `unzip`, the extracted `./otter` run directly, installed twice with `-AddToUserPath`, programs and `otter web` run through the installed command, uninstalled (command and folder removed); the 24 D120 portable suites pass, including the platform-boundary suite (every Windows-only feature stops with "... is only available on Windows"; the clipboard round-trips). Csv, Conformance and Web run with Node.js 20, as on the GitHub runners. | Docker Desktop on the release machine, 2026-09-30 |
| D120 four-host workflow, this commit | **Not run.** GitHub Actions refused to start jobs (account spending limit). The code change it would test (`c9d7569`, `3079104`) passed all seven jobs, including the Windows-built archive on Linux and macOS, in [run 36657373162](https://github.com/Heavens-Lava/otterPS/actions/runs/36657373162); `85227ab` changes only the version and documentation. | — |
| macOS, hands-on | **Pending.** Jeff's Mac: Finder extraction, `./otter`, install, `otter web`, `otter desktop` refusal, uninstall. | — |
| Fresh-machine test (Windows) | **Not run.** Needs a machine or VM that has never had Otter. | — |
