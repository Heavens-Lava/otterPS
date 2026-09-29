# Otter 1.0.0-rc.4 — release evidence

Candidate: `v1.0.0-rc.4` = `e850e900f60395ff5657d4ebc0dcdb35d650c251`
(rc.3 plus D128, web UI created while the page runs). All results below are
for that exact commit, unless a row says otherwise.

| Check | Result | Where |
|---|---|---|
| Release certification, clean checkout, Windows PowerShell 5.1 | **Pass.** All seven gates: contract structure; platform regression 62/62 test files (including 3 headless-Chromium tests for D128); conformance 15/15; differential fuzz 1,000/1,000; malformed-input fuzz 1,000/1,000; release-surface audit; distribution smoke. Tree clean afterwards. | `tools/Invoke-OtterReleaseCertification.ps1`, 2026-09-29 |
| D120 four-host workflow | **Pass.** 23 portable suites and the project workflow on Windows PowerShell 5.1 and PowerShell 7 on Windows, Linux and macOS. The D128 browser tests skip on these runners (no playwright-core); their compile checks run. | [run 36580645737](https://github.com/Heavens-Lava/otterPS/actions/runs/36580645737) |
| Windows PowerShell 5.1 recursion probe | **Pass**, 24 of 24 cases. A recursive sum written three ways (call statement, value after `is`, inside a loop body) at depths 50, 100, 200, 240 and 249 gives the right answer; at 250, 251 and 400 it gives Otter's "Call depth limit exceeded" error with exit code 3. No host crash, raw PowerShell error or hang. Slowest case 9.2 s (limit error inside a loop body at depth 400). | `tools/Test-OtterRecursionProbe.ps1`, PowerShell 5.1.26100.8115 |
| Desktop (WPF) smoke test | **Pass**, 9 of 9 checks. `examples/v1/tasks.ot` through `otter run`, driven with Windows UI Automation: the window opens as "Otter Tasks"; typing a task and clicking Add adds a line with that text (twice); Add with an empty box adds nothing; the box is cleared; closing the window ends the program with exit code 0 and no output. | `tools/Test-OtterDesktopSmoke.ps1`, PowerShell 5.1.26100.8115 |
| Fresh-machine test | **Not run.** Needs a machine or VM that has never had Otter, following only the published instructions. | — |

The same `tasks.ot` behaves identically on the desktop (this smoke test) and
on the web (`tests/WebRuntimeUi.Tests.ps1`), which was the gap D128 closed.

## Decisions recorded with this candidate

- **D128** — web UI created while the page runs (`SPEC-DECISIONS.md`).
- **D56 affirmed for 1.0** (`SPEC-DECISIONS.md`, "D56 affirmation"):
  `hide`, `focus`, `clear` and the other D56 exclusions stay out of 1.0 on
  every target; they are planned for 1.1, with OtterBoard as the 1.1 flagship
  application.
