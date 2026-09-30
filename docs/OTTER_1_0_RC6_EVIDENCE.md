# Otter 1.0.0-rc.6 — release evidence (superseded, not tagged)

Candidate: `95b9d400d18548d17fd193eaf0b73b90b0f88842` (`VERSION` 1.0.0-rc.6).
rc.5 (`v1.0.0-rc.5` = `687219c`) plus macOS and Linux installation (D129):
the `otter` shell launcher, `Install-Otter.ps1`/`Uninstall-Otter.ps1` on every
platform, Windows-only features refused clearly on macOS and Linux, and the
`run command` fix for extensionless files on Windows.

**Outcome: passed certification, then superseded by rc.7 before publication.**
Inspecting the release archive itself (not the payload folder the checks had
installed from) showed that Windows PowerShell 5.1's `Compress-Archive` stored
backslash paths and no Unix permissions. On macOS and Linux the extracted
`otter` launcher was not executable (`unzip` shows `-rw----  fat`), and tools
that do not repair backslash paths can extract flat files named
`otter-1.0.0-rc.6\otter`. `Install-Otter.ps1 -AddToUserPath` also refused to
replace its own `~/.local/bin/otter` on a second run. rc.6 is therefore not
tagged and was never published; rc.7 carries the fixes.

| Check | Result | Where |
|---|---|---|
| Release certification, clean checkout, Windows PowerShell 5.1 | **Pass.** All eight gates: contract structure; platform regression 63/63 test files; conformance 15/15; differential fuzz 1,000/1,000; malformed-input fuzz 1,000/1,000; release-surface audit; distribution smoke; repository clean afterwards. | `tools/Invoke-OtterReleaseCertification.ps1`, 2026-09-30 (record `20260930T004556Z-95b9d40`) |
| D120 four-host workflow | **Pass** on Windows PowerShell 5.1 and PowerShell 7 on Windows, Linux and macOS, including the platform-boundary suite and distribution install/uninstall from the payload folder. | [run 36651892072](https://github.com/Heavens-Lava/otterPS/actions/runs/36651892072) |
| Windows PowerShell 5.1 recursion probe | **Pass**, 24 of 24 cases. | `tools/Test-OtterRecursionProbe.ps1`, PowerShell 5.1.26100.8115 |
| Desktop (WPF) smoke test | **Pass**, 9 of 9 checks. | `tools/Test-OtterDesktopSmoke.ps1`, PowerShell 5.1.26100.8115 |
| Release archive on macOS and Linux | **Fail** (found by inspection; not covered by any check at the time). | Fixed in rc.7; the host matrix now installs the Windows-built archive on Linux and macOS. |
