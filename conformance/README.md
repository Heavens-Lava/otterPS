# Otter Conformance Fixtures (starting set)

These `.ot` files were written and verified during the Otter 1.0
language/runtime capability sweep (see
`docs/OTTER_1_0_LANGUAGE_AND_RUNTIME_INVENTORY.md` and
`docs/OTTER_1_0_GAP_REPORT.md`). Every file here was run for real through
`otter run <file>` (or `otter check` at minimum) and its output was
inspected before being committed.

This is a **starting point**, not the formal Otter 1.0 conformance suite
Jeff's roadmap calls for. Known gaps before it can become that:

- `misc/file_exists_run_command_json_roundtrip.ot` and the filesystem
  portions of `system_integration/clipboard_env_notify.ot` use absolute
  paths under a specific machine's temp directory. A real conformance
  harness needs these parameterized to a fresh temp directory per run,
  not hardcoded.
- `http/http_web_target_only.ot` depends on a live network call to
  `httpbin.org`. It documents that HTTP is **web-target-only** (see the
  gap report) — it is not runnable via `otter run` at all right now, only
  `otter web`. A real harness will need a decision on whether network-
  dependent fixtures are acceptable, mocked, or skipped.
- None of these files yet assert their own expected output programmatically
  - they were verified by a human (well, an agent) reading the real
    `otter run` output during the sweep. The formal suite Jeff describes
    needs each fixture paired with an expected-output file and an
    automated diff, run through both the interpreter and (where
    applicable) the JS compiler, per his Phase 5 vision.
- Coverage here is not exhaustive. D69-D92 (system info, processes,
  symlinks, permissions, registry, event logs, credentials, power
  actions, printers, remote/SSH, ZIP, hashing, encryption, extended
  math) already have their own dedicated, committed regression tests in
  `tests/Part3.Tests.ps1` and `tests/Interpreter.Tests.ps1` - this sweep
  spot-checked them again for real (see the inventory doc) but did not
  duplicate that coverage here as `.ot` fixtures.
- UI/declarative-reactivity/web-server capabilities (buttons, windows,
  `state`/`derive`/`memo`, `when ... is clicked`, web routes) are
  intentionally **not** covered by this fixture set - this sweep was
  scoped to the non-UI language and runtime, per the same Otter-vs-
  Otter-Studio distinction the project has used throughout. They have
  their own extensive test coverage in `tests/UI.Tests.ps1` and
  `tests/Web.Tests.ps1`.

## What's here

| Directory | Covers |
|---|---|
| `core/` | variables, arithmetic, `if`/`otherwise`, `while`, `repeat`, `count...as`, `for each`, lists, and function returns in both expression and legacy `... make result` forms |
| `objects/` | `a Type has`, `X has ...`, `X is a Type with ...`, dynamic `get X from Y into Z` / `set X to Y in Z` |
| `errors/` | `try` / `otherwise [into name]` / `fail with` |
| `strings/` | `sort`, `reverse`, `replace ... with ... in`, `split ... by ... into`, `join ... with ... into`, `find ... in ... where ... into`, `starts with`/`ends with`, `length`/`uppercase`/`lowercase`/`first`/`last` of, `larger`/`smaller of ... and ...` |
| `json_random_diagnostics/` | `convert ... to json` / `convert ... from json`, `random number from ... to ... into`, `random item from ... into`, `log`/`warn`/`error` |
| `dates/` | `today`/`now`, `year`/`month`/`day`/`hour`/`minute` of, `add ... days to` / `remove ... from`, `days between ... and ... make`, `format ... as ... into` |
| `http/` | documents that `get`/`post`/`put`/`delete from` a URL **only work through `otter web`**, not `otter run` - see the gap report |
| `system_integration/` | clipboard, environment variables, system folders, `notify` |
| `misc/` | `if file ... exists`, `run command "..." into result`, `read json from ... into` |
| `negative/` | programs that must fail with a clear diagnostic; most use `otter check`, while `boolean_operators_outside_conditions.ot` intentionally parses as addition syntax and fails under `otter run` when its operands are boolean |

Run any of them directly:

```
otter run conformance/core/variables_math_control_flow.ot
otter check conformance/http/http_web_target_only.ot
```
