# Otter Conformance Fixtures

These `.ot` files support Otter 1.0 release certification (see
`docs/OTTER_1_0_LANGUAGE_AND_RUNTIME_INVENTORY.md` and
`docs/OTTER_1_0_GAP_REPORT.md`). The deterministic RC subset (15 fixtures) is
described in `manifest.json` and run through the real production entry point with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-OtterReleaseConformance.ps1
```

That runner records expected exit code, stdout or diagnostic text, target,
generated-web semantic assertions, and live headless browser runtime execution
via Microsoft Edge / Chromium. It deliberately creates temporary copies for
filesystem and web fixtures so release certification does not depend on the
developer's repository or profile state.

The suite certifies:
- Deterministic core syntax, arithmetic, and control flow.
- Function return expressions and parameters.
- Filesystem mutation, JSON parsing/generation, and command execution.
- Deterministic date math.
- Error handling, `try` / `otherwise [into reason]` / `fail with`.
- Declared types, things, and dynamic key access.
- Text operations and collection manipulation (sorting, reversing, filtering, case).
- Negative compiler and semantic diagnostic checks (reserved literals, operator scope, typed initializer syntax).
- Web compiler target parity: HTTP fetch generation and headless browser execution.
- Target-specific HTTP enforcement: clear diagnostic when HTTP statements are used on console.
- The manifest intentionally certifies only deterministic, portable-core
  fixtures plus one web compiler semantic fixture. Nondeterministic clock and
  random outputs require normalization before they can become golden-output
  cases.
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
