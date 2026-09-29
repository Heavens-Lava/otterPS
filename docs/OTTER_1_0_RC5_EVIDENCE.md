# Otter 1.0.0-rc.5 — release evidence

Candidate: `687219c0544b73238f7a31ccc2dde5d4fe08f174` (`VERSION` 1.0.0-rc.5),
**not tagged yet**. rc.4 (`v1.0.0-rc.4` = `ab25d4f`) plus:

- `7389c63` — compiler fix: Run-button samples are compiled with their own
  names, not their page's runtime-UI names (a D128 bug found by clicking every
  Run button on the documentation site);
- `618e8ef` — documentation site sources for rc.4;
- `687219c` — version 1.0.0-rc.5, changelog `[1.0.0-rc.5]`.

All results below are for that exact commit.

| Check | Result | Where |
|---|---|---|
| Release certification, clean checkout, Windows PowerShell 5.1 | **Pass.** All seven gates: contract structure; platform regression 62/62 test files (including the headless-Chromium D128 tests and the new Run-button sample tests); conformance 15/15; differential fuzz 1,000/1,000; malformed-input fuzz 1,000/1,000; release-surface audit; distribution smoke. Tree clean afterwards. | `tools/Invoke-OtterReleaseCertification.ps1`, 2026-09-29 |
| D120 four-host workflow | **Pass.** 23 portable suites and the project workflow on Windows PowerShell 5.1 and PowerShell 7 on Windows, Linux and macOS. | [run 36617022157](https://github.com/Heavens-Lava/otterPS/actions/runs/36617022157) |
| Windows PowerShell 5.1 recursion probe | **Pass**, 24 of 24 cases (three call forms, depths 50 to 400 around the 250-call limit: correct answers below it, the clean "Call depth limit exceeded" error at and above it). | `tools/Test-OtterRecursionProbe.ps1`, PowerShell 5.1.26100.8115 |
| Desktop (WPF) smoke test | **Pass**, 9 of 9 checks (`examples/v1/tasks.ot` driven with UI Automation). | `tools/Test-OtterDesktopSmoke.ps1`, PowerShell 5.1.26100.8115 |
| Documentation site (built from these sources) | 237 code samples parse; 122 Run buttons run (one intentionally shows an error); 12,032 internal links resolve. The published site (<https://heavens-lava.github.io/>) describes 1.0.0-rc.4. | `otter-docs/scripts/*` |
| Fresh-machine test | **Not run.** Needs a machine or VM that has never had Otter. | — |
