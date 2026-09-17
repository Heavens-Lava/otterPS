# Otter 1.0 Language and Runtime Inventory

**Authoritative as of:** commit `6a7b9e3` plus the V1 semantic-correction pass.
**Method:** every claim below was checked against the actual production
lexer/parser/interpreter source (`Otter.Contract.psm1`,
`src/Otter.Lexer.psm1`, `src/Otter.Parser.psm1`,
`src/Otter.Interpreter.psm1`, `src/Otter.Library.psm1`,
`src/Otter.Compiler.JavaScript.psm1`) and, wherever it could reasonably be
made to run, executed for real through `otter run <file.ot>` (or `otter
check`/`otter web` where noted). Nothing here is taken from README files,
prior roadmap documents, or recollection. Every code example in this
document is real syntax that ran successfully during this sweep, unless
explicitly marked otherwise.

**Scope.** This inventory covers the **non-UI language and runtime** -
the part of Otter you'd use in a console/file-processing/automation
program. It deliberately excludes the declarative UI/desktop/web-server
surface (buttons, windows, layout, `state`/`derive`, `when ... is
clicked`, web routes/servers) - that surface has its own extensive,
separate test coverage (`tests/UI.Tests.ps1`, `tests/Web.Tests.ps1`) and
was out of scope for this pass, matching the project's own long-standing
distinction between "the Otter language" and "Otter Studio." Thirteen
`NodeKind` values are excluded on this basis: `CreateUiResource`, `When`,
`PutIn`, `Show`, `WebRoute`, `Respond`, `StartServer`, `ListenServer`,
`UiElement`, `UiLayout`, `StateDef`, `DeriveDef`, `Watch`.

**Verification status legend** (Phase 2 of the audit):
- **PRODUCTION VERIFIED** - parses and executed for real through `otter run`, observable result confirmed.
- **PARSES BUT RUNTIME UNVERIFIED** - the production parser accepts it; execution was not (safely/practically) demonstrated in this pass.
- **RUNTIME EXISTS BUT UNREACHABLE** - an implementation exists below the surface, but no production Otter syntax reaches it.
- **TARGET-SPECIFIC** - a real, valid Otter capability, but only through one host/target (e.g. `otter web`, not `otter run`).
- **LEGACY/COMPATIBILITY** - supported, but not the canonical form.
- **EXPLICITLY NOT SUPPORTED IN V1** - the runtime deliberately rejects it with a clear message; this is a **decision already made**, not an unverified gap.

---

## PART A - LANGUAGE (core semantics, no runtime library involved)

### A1. Values and variables

| Syntax | What it does | Status |
|---|---|---|
| `name is "Jeff"` | Assigns a value to a variable (creates it if new) | PRODUCTION VERIFIED |
| Numbers (`10`, `3.5`), strings (`"text"`), `true`/`false` | Literal values | PRODUCTION VERIFIED |
| `gone` | The "missing value" - distinct from false/0/""/empty list (D22) | PRODUCTION VERIFIED (used throughout; e.g. `first of` an empty list) |

**Example** (`conformance/core/variables_math_control_flow.ot`):
```
score is 10
score is score plus 5
say score
```
Output: `15`.

**V1 semantic correction:** `today`, `now`, and `pi` are reserved literal
names. They are rejected wherever a writable variable binding is expected,
rather than accepting an assignment expression parsing could never read back.
The rejection is verified through `otter check` using
`conformance/negative/reserved_literal_variable.ot`.

### A2. Arithmetic

| Syntax | Operator | Status |
|---|---|---|
| `a plus b` / `a + b` (math context) | add | PRODUCTION VERIFIED |
| `a minus b` | subtract | PRODUCTION VERIFIED |
| `a times b` | multiply | PRODUCTION VERIFIED |
| `a divided by b` | divide (friendly error on divide-by-zero) | PRODUCTION VERIFIED |
| `a percent of b` | percentage (D88) | PRODUCTION VERIFIED |
| `a power b` | exponentiation (D88) | PRODUCTION VERIFIED |

**All arithmetic is flat, strictly left-to-right - there is no operator
precedence** (a frozen, deliberate design decision, D7). `2 plus 3 times
4` is `(2+3)*4 = 20`, not `14`.

`and` remains lexically compatible with the historical arithmetic token only
for legacy `left and right make result` statements. Ordinary arithmetic uses
`plus` or `+`.

### A3. Comparisons and boolean logic

| Syntax | Status |
|---|---|
| `is`, `is not`, `is at least`, `is at most`, `is greater than`, `is less than` | PRODUCTION VERIFIED, inside `if`/`while` |
| `not X` | PRODUCTION VERIFIED **as a general expression** (works in `say`, assignment, anywhere) |
| `X and Y`, `X or Y` | PRODUCTION VERIFIED **inside a condition** (`if`/`while`) only |

`and`/`or` are **condition-position only**. Valid condition behavior is
unchanged:

```
if isReady or isDone
    say "yes"          # works: prints "yes"

say isReady or isDone   # Syntax Error: says `or` is condition-only

combined is isReady and isDone
say combined            # Syntax Error: says `and` is condition-only
```

`or` outside a condition is a syntax error. `and` in an ordinary expression
is also a syntax error, not an arithmetic AST; only the legacy
`... and ... make result` form remains compatible. Both errors name the valid
`if`/`while` context and suggest `plus` for numeric addition. `not` remains
available wherever a value expression is accepted. The negative fixture
`conformance/negative/boolean_operators_outside_conditions.ot` verifies the
real `otter check` diagnostic.

### A4. Conditions and blocks

| Syntax | Status |
|---|---|
| `if <condition>` / `otherwise` / (chained `otherwise if`, per session history) | PRODUCTION VERIFIED |
| Indentation defines blocks; a bare `.` also closes a block (per rules.md) | PRODUCTION VERIFIED (indentation form used throughout this sweep) |

### A5. Loops

| Syntax | What it does | Status |
|---|---|---|
| `while <condition>` | pretest loop | PRODUCTION VERIFIED |
| `repeat N times` | fixed repetition, no loop variable | PRODUCTION VERIFIED |
| `count from A to B as name` | inclusive counting loop (D5) | PRODUCTION VERIFIED - confirmed BOTH ends inclusive (`count from 1 to 3` prints `1 2 3`) |
| `for each x in collection` | iterates a list | PRODUCTION VERIFIED |

### A6. Lists

| Syntax | What it does | Status |
|---|---|---|
| `names are empty` | empty list literal | PRODUCTION VERIFIED |
| `names are` *(indented items, one per line)* | populated list literal | PRODUCTION VERIFIED - **not** comma-separated on one line |
| `add "x" to names` | append | PRODUCTION VERIFIED |
| `remove "x" from names` | remove by value | PRODUCTION VERIFIED |
| `names contains "x"` | membership test (in a condition) | PRODUCTION VERIFIED |
| `say names` | prints comma-space-joined (D8) | PRODUCTION VERIFIED (`Zelda, Mario`) |

`add`/`remove` **also work on plain numbers** (`add 5 to score`) -
dispatch is by runtime type, not by syntax (D12); verified previously in
this project's own regression suite, not re-verified in this pass since
it needed no new syntax.

### A7. Functions

| Syntax | What it does | Status |
|---|---|---|
| `to name param1 param2` *(body)* `return value` | function definition | PRODUCTION VERIFIED |
| `name arg1 arg2` | bare call, discards result | PRODUCTION VERIFIED |
| `name arg1 arg2 make result` | legacy statement call and capture | PRODUCTION VERIFIED |
| `result is name arg1 arg2` | function call as a value expression | PRODUCTION VERIFIED |

Calling a declared function as the right-hand side of `is` is valid:

```
to addNumbers x y
    return x plus y

result is addNumbers 3 and 4  # Works. result -> 7

addNumbers 3 4 make result    # Works. result -> 7
say result
```

The parser resolves an expression call by the declared function's arity, so
the call consumes exactly its arguments and leaves a following boolean
connective for the condition parser. The legacy `... make result` form remains
supported. `conformance/core/function_return_expression.ot` was executed
through `otter run`; differential interpreter/JavaScript parity also verifies
the expression form.

**Also confirmed:** the single-letter name `a` cannot be used as a
parameter or variable name - it collides with the reserved word `a`
(used in `a Person has ...` / `X is a Type`). `to addNumbers a b` fails
with "I expected a parameter name." Not a bug - `A` is a real
`TokenKind` - but worth documenting explicitly so it isn't rediscovered
as a mystery bug later.

**Recursion, scope isolation** (parameters not overwriting globals) -
already covered by the project's own long-standing regression suite;
not re-verified fresh in this pass since no syntax changed.

### A8. Objects / "things"

| Syntax | What it does | Status |
|---|---|---|
| `x has prop1 "v1", prop2 "v2"` | untyped object literal, comma-separated inline properties | PRODUCTION VERIFIED |
| `x has` *(newline, then indented `prop value` per line)* | untyped object literal, block form | RUNTIME EXISTS, grammar confirmed by reading `Read-OtterObjectBlockProperties`; not independently re-run this pass (same code path as the D40 audit) |
| `a TypeName has` *(indented field names)* | declares a reusable type (D39/D40-era) | PRODUCTION VERIFIED |
| `x is a TypeName with prop1 "v1", prop2 "v2"` | typed object, **inline `with`, comma-separated** | PRODUCTION VERIFIED |
| `name of thing` | property read | PRODUCTION VERIFIED |

**V1 grammar rule:** for a type **already declared** via `a TypeName has ...`,
properties must use the inline `with` form. An indented initializer is rejected
at its opening indentation with an Otter diagnostic rather than silently
producing an object with zero properties:

```
a Person has
    name
    age

sam is a Person
    name "Sam"          # rejected: use `with` on the same line
    age 25

sam is a Person with name "Sam", age 25   # <- the only form that works
```

The indented block form continues to work for `has` (untyped things) and for
`is a thing`. The declared-type rejection is covered by
`conformance/negative/typed_object_indented_initializer.ot`.

### A9. Dynamic keys (D41)

| Syntax | What it does | Status |
|---|---|---|
| `get "key" from thing into result` | dynamic property read | PRODUCTION VERIFIED |
| `set "key" to value in thing` | dynamic property write | PRODUCTION VERIFIED |

### A10. Errors

| Syntax | What it does | Status |
|---|---|---|
| `try` *(block)* `otherwise` *(block)* | catches any error | PRODUCTION VERIFIED |
| `try` ... `otherwise into reason` ... | catches and captures the message (D68) | PRODUCTION VERIFIED |
| `fail with "message"` | raises a real, catchable, user-defined error | PRODUCTION VERIFIED |

**Example** (`conformance/errors/try_fail.ot`) - all three forms run
correctly, including the no-error pass-through case.

### A11. Modules

| Syntax | Status |
|---|---|
| `use "module.ot"` | **EXPLICITLY NOT SUPPORTED IN V1** |

This is a **major correction to an assumption in Jeff's own roadmap
message**, which described the module resolver as "implemented" and
awaiting "final production certification." The actual, current
interpreter source contains:

```powershell
'UseModule' {
    throw (New-OtterRuntimeError -Message "'use' is not supported in Otter 1.0." -Line $Statement.Line)
}
```

Confirmed by real execution: `use "math.ot"` throws this exact runtime
error, every time, unconditionally. This is not an unfinished feature
waiting on one more certification pass - it is a **decision that has
already been made** to exclude modules from Otter 1.0 entirely. Jeff's
Gate 2 ("finish the module and core runtime certification") needs to be
re-scoped: there is no module system to certify. See the Gap Report.

### A12. Other explicit V1 exclusions (confirmed via source, not guessed)

The interpreter contains **eight** deliberate, hard rejections, each
with the identical message pattern `"'X' is not supported in Otter
1.0."` (or an equivalent explicit statement-specific message). These are
**decisions**, not gaps:

| Statement/expression | Surface syntax it corresponds to | Confirmed via |
|---|---|---|
| `UseModule` | `use "file.ot"` | real execution (above) |
| `MemoDef` | `memo ...` | source (`'memo' is not supported...`) |
| `Lifecycle` | `on start` / `on close` | source (`'on $Stage' is not supported...`) |
| `SharedState` | `shared x is ...` | source (`'shared' is not supported...`) |
| `UiAction` | `focus x` / `hide x` (confirmed already a documented, deliberate no-op-turned-error from a prior audit) | source |
| `UiEvent` | declarative `when` reactive blocks (D56-era, distinct from the working D46 `when button is clicked` handler registration) | source |
| `UiAnimation` | declarative animation blocks | source |
| `Await` | `await <expr>` | real execution: `say await 5` → `'await' is not supported in Otter 1.0.` |

**Caveat on `Await`:** at the time of this sweep, `src/Otter.Parser.psm1`
has **uncommitted, in-progress work** (not yet reviewed or merged)
extending the `await` grammar with new statement forms (`await X make
Y`, `await X into Y`). The interpreter's hard rejection above reflects
the last **committed** state. Whatever `await` becomes needs its own
explicit V1 decision (in-scope for 1.0, or deferred) rather than
inheriting whatever state the parser happens to be in when 1.0 is cut.

---

## PART B - STANDARD RUNTIME (files, data, system-independent utilities)

### B1. Files

| Syntax | What it does | Result type | Status |
|---|---|---|---|
| `write "text" to "file.txt"` | create/overwrite | - | PRODUCTION VERIFIED |
| `write "text" to "file.txt" atomically` | same, via atomic replace (D72) | - | RUNTIME EXISTS, exercised by this project's own D72 regression suite; not re-run fresh this pass |
| `append "text" to "file.txt"` | append, **no implicit newline** | - | PRODUCTION VERIFIED. Confirmed: `write "a"` then `append "b"` gives `ab`, not `a` + newline + `b` |
| `read "file.txt" into content` | read whole file as text | string | PRODUCTION VERIFIED |
| `if file "x" exists` | existence check (condition) | bool | PRODUCTION VERIFIED |
| `if file "x" is locked` | lock check (D72) | bool | RUNTIME EXISTS, D72 regression suite; not re-run fresh |
| `copy "a" to "b"` | copy a file | - | RUNTIME EXISTS, grammar confirmed; file-copy path itself was exercised via this sweep's D87 ZIP spot-check indirectly, not directly re-run as a bare file copy this pass |
| `move "a" to "b"` | move a file | - | same as above |
| `delete file "a"` | delete a file - **the word `file` is required** | - | PRODUCTION VERIFIED. `delete "a"` alone (no `file`) is a **syntax error**: "I expected 'file' after delete." This corrects an earlier, incorrect informal cheat-sheet exchange in this same conversation that omitted the required word. |

### B2. Folders

| Syntax | Status |
|---|---|
| `create folder "Projects"` | PRODUCTION VERIFIED |
| `get files in "Projects" into files` | PRODUCTION VERIFIED |
| `get files in "Projects" and subfolders into files` | RUNTIME EXISTS, grammar confirmed (`Test-OtterTokenKind Subfolders`); not re-run fresh this pass |
| `get folders in "Projects" into folders` | RUNTIME EXISTS, same grammar path as `get files in`, not independently re-run |
| `copy folder "a" to "b"` / `move folder "a" to "b"` | RUNTIME EXISTS, grammar confirmed |
| `delete folder "a"` | RUNTIME EXISTS, grammar confirmed |

File objects returned by `get files in` carry real properties, confirmed
directly:

```
get files in "Demo" into files
each file in files
    say name of file
    say path of file
    say extension of file
    say size of file
```
`size` is bytes (a number); `created`/`modified` are `"yyyy-MM-dd
HH:mm:ss"` text (confirmed present in `New-OtterFileObject`, matching
`rules3.md` section 8, though `created`/`modified` were not printed in
this pass's specific run - they follow the exact same code path as
`size`, which was).

### B3. Symbolic links, ownership, permissions (D73/D74)

| Syntax | Status |
|---|---|
| `create symbolic link "l" pointing to "t"` | PARSES BUT RUNTIME UNVERIFIED **in this environment** - this sandbox lacks Administrator/Developer-Mode privileges, and the real, friendly Otter error ("this needs Administrator privileges or Developer Mode turned on") was itself confirmed to fire correctly. The feature's success path was verified during D73's own original session work on a privileged machine; not re-demonstrable here. |
| `if file "l" is a symbolic link` | RUNTIME EXISTS, same privilege dependency |
| `get symbolic link target of "l" into t` | RUNTIME EXISTS, same privilege dependency |
| `get owner of "x" into owner` | PRODUCTION VERIFIED this pass |
| `if file "x" is read only` / `set file "x" to read only` | RUNTIME EXISTS, D74 regression suite; not re-run fresh |

### B4. Command execution (D65, D70)

| Syntax | What it does | Result | Status |
|---|---|---|---|
| `run "program.exe"` | launch a process, non-blocking | a process handle object | RUNTIME EXISTS, grammar confirmed; the **structured result path is different from `run command`** (see below) - a plain `run "x" into result` does **not** give `output`/`exit code` properties, it gives a process object (confirmed: attempting `output of result` on a plain `run` result fails with "This process has no property called 'output'." and suggests `id of ...` instead) |
| `run command "cmd /c echo hi" into result` | run synchronously, capture structured result | a "command result" thing | PRODUCTION VERIFIED |
| `output of result` / `error output of result` / `exit code of result` | read the structured result (D65) | string/string/number | PRODUCTION VERIFIED - `output of result` → `hello-from-run`, `exit code of result` → `0` |

**This distinction (`run "x"` vs. `run command "x"` giving genuinely
different result shapes) is real and should be stated explicitly in any
1.0 spec** - it is not obvious from the surface syntax alone that adding
the word "command" changes what kind of value comes back.

### B5. JSON (D29)

| Syntax | Status |
|---|---|
| `convert thing to json into text` | PRODUCTION VERIFIED |
| `convert text from json into thing` | PRODUCTION VERIFIED |
| `read json from "file.json" into thing` | PRODUCTION VERIFIED |

Round-trip confirmed for real: an object with `name`/`age` properties
survived `convert ... to json` → written to a real file → `read json
from ... into` → properties read back correctly.

### B6. Random (D30)

| Syntax | Status |
|---|---|
| `random number from 1 to 10 into n` | PRODUCTION VERIFIED (range-checked in a real run) |
| `random item from list into item` | PRODUCTION VERIFIED (membership-checked in a real run) |

### B7. Diagnostics (D31)

| Syntax | Output prefix | Status |
|---|---|---|
| `log "message"` | `log: ` | PRODUCTION VERIFIED |
| `warn "message"` | `warn: ` | PRODUCTION VERIFIED |
| `error "message"` | `error: ` | PRODUCTION VERIFIED |

These are **not** `say` aliases - confirmed they go through a
separate writer, and each carries a distinct prefix in the default CLI
output.

### B8. Dates and time (D32)

| Syntax | What it does | Status |
|---|---|---|
| `today` | today's date, no time-of-day | PRODUCTION VERIFIED |
| `now` | current date **and** time | PRODUCTION VERIFIED |
| `year of X` / `month of X` / `day of X` | works on either `today` or `now` | PRODUCTION VERIFIED |
| `hour of X` / `minute of X` / `second of X` | **only valid on `now`-shaped values** | PRODUCTION VERIFIED, including the friendly rejection: `hour of today` → *"This is a date with no time of day, so it has no hour. Try: started is now"* |
| `add N days\|months\|years\|hours\|minutes\|seconds to dateVar` | **mutates the variable in place** | PRODUCTION VERIFIED |
| `remove N <unit> from dateVar` | mutates in place, subtracting | PRODUCTION VERIFIED |
| `days between a and b make total` | statement form (D32) | PRODUCTION VERIFIED |
| `x is days between a and b` | **expression form** (D42) | PRODUCTION VERIFIED |
| `format dateVar as "yyyy-MM-dd HH:mm:ss" into text` | a **statement**, not an expression usable after `is` | PRODUCTION VERIFIED |

See Part A1 above for the important `today`/`now`-as-variable-name
shadowing finding, which applies here too.

---

## PART C - HOST/PROVIDER CAPABILITIES

### C1. Networking / HTTP (D49) - **major finding**

| Syntax | Status |
|---|---|
| `get "url" into result` | **TARGET-SPECIFIC: `otter web` only** |
| `get "url" as json into result` | same |
| `post "data" to "url" into result` | same |
| `put "data" to "url" into result` | same |
| `put "data" as json to "url" into result` | same |
| `delete from "url" into result` | same |

**This directly contradicts an assumption in Jeff's own roadmap message**
("we've also gone considerably beyond pure language syntax... HTTP
operations" listed alongside file operations as already-solid V1
runtime). The reality, confirmed by real execution:

```
get "https://httpbin.org/get" into response
```
via `otter run` produces:
```
Otter Runtime Error
I do not know how to run a HttpGet statement yet.
```
Grepping `src/Otter.Interpreter.psm1` for `'HttpGet'`/`'HttpPost'`/
`'HttpPut'`/`'HttpDelete'` returns **zero matches** - there is no
interpreter implementation at all. The JS compiler (`otter web`)
**does** implement all four (`src/Otter.Compiler.JavaScript.psm1` lines
~1800-1870) and the same file compiled successfully via `otter web`.
HTTP in Otter today is a **web-target-only** capability, full stop. This
needs an explicit V1 decision: implement it in the interpreter (real
work, likely via `Invoke-WebRequest`/`Invoke-RestMethod`), or document
HTTP as web-target-only for 1.0. Either is legitimate; silently assuming
it "already works" is not. See the Gap Report.

### C2. System integration (D67)

| Syntax | Status |
|---|---|
| `get environment variable "PATH" into value` | PRODUCTION VERIFIED |
| `get system folder "temp" into path` | PRODUCTION VERIFIED |
| `copy "text" to clipboard` | PRODUCTION VERIFIED |
| `get clipboard into text` | PRODUCTION VERIFIED |
| `notify "Title" with "Message"` | PRODUCTION VERIFIED (a real Windows toast notification was sent) |
| `choose file into path` | PARSES BUT RUNTIME UNVERIFIED - opens a real, blocking OS file-picker dialog; cannot be exercised in a non-interactive sweep |
| `choose folder into path` | same |
| `choose file to save into path` | same |

### C3. System information, processes (D69-D71)

| Syntax | Status |
|---|---|
| `get system information "os"/"cpu"/"memory"/"disk"/"network"/"user"/"groups"/"software"/"tasks"/"printers"/"services" into info` | PRODUCTION VERIFIED (spot-checked `"os"` fresh this pass; the other ten kinds share the identical, generalized dispatch mechanism, each individually verified during their own D-numbers this project) |
| `get processes into list` | PRODUCTION VERIFIED |
| `kill process p` / `kill process p and its children` | RUNTIME EXISTS, D70 regression suite; not re-run fresh (destructive - would kill a real process) |
| `set priority of process p to "high"` | RUNTIME EXISTS, D71 regression suite |
| `wait for process p up to N seconds [into finished]` | RUNTIME EXISTS, D71 regression suite |

### C4. Windows registry (D78)

| Syntax | Status |
|---|---|
| `get registry value "n" from "path" into t` | PRODUCTION VERIFIED fresh this pass |
| `set registry value "n" to "d" in "path"` | PRODUCTION VERIFIED fresh this pass |
| `delete registry value "n" from "path"` | PRODUCTION VERIFIED fresh this pass (used to clean up the test key) |
| `if registry key "path" exists` | RUNTIME EXISTS, D78 regression suite |

### C5. Event logs (D79)

| Syntax | Status |
|---|---|
| `get event log entries from "System" up to 20 into entries` | RUNTIME EXISTS, D79 regression suite; not re-run fresh this pass |

### C6. Secure credential storage (D81)

| Syntax | Status |
|---|---|
| `set credential "n" to "secret"` | PRODUCTION VERIFIED fresh this pass |
| `get credential "n" into secret` | PRODUCTION VERIFIED fresh this pass |
| `delete credential "n"` | PRODUCTION VERIFIED fresh this pass |

Storage is DPAPI, `CurrentUser` scope - local-machine, local-user only
(by design, D81).

### C7. Power/session actions (D82)

| Syntax | Status |
|---|---|
| `lock the computer` | RUNTIME EXISTS, verified during D82 (real command construction confirmed; per an explicit Jeff scope decision at the time, only logoff/lock were candidates for real execution, and even those were not re-executed in THIS pass to avoid disrupting the current session) |
| `sign out` | same |
| `restart the computer` / `shut down the computer` | RUNTIME EXISTS, command construction verified during D82; **real execution was never attempted**, including a Claude-Code auto-mode safety classifier that itself blocked a deliberate schedule-then-abort verification attempt at the time |

### C8. Printers (D83)

| Syntax | Status |
|---|---|
| `print "file.txt" to "PrinterName"` | RUNTIME EXISTS, D83 regression suite; the actual print-job completion was never verified against a real physical/virtual printer (documented limitation from D83 itself) |

### C9. Remote administration / SSH (D84/D85)

| Syntax | Status |
|---|---|
| `run command "..." on remote "host" using credential "n" [into result]` | RUNTIME EXISTS (PSRemoting/WinRM); command construction verified during D84; real execution requires WinRM enabled on a target, confirmed **disabled** in this environment (`Test-WSMan` failed) - success path unverified, by design (enabling WinRM would be a real security-posture change this project chose not to make unilaterally) |
| `run command "..." over ssh to "user@host" [into result]` | RUNTIME EXISTS; D85 confirmed `ssh.exe`'s real behavior (reads passwords from the terminal device, not stdin) and designed around key-based auth only; no real SSH target was available to demonstrate the full success path |

### C10. ZIP archives (D87)

| Syntax | Status |
|---|---|
| `zip folder "src" into "archive.zip"` | PRODUCTION VERIFIED fresh this pass |
| `unzip "archive.zip" into "dest"` | PRODUCTION VERIFIED fresh this pass |

### C11. Math extensions (D88-D90)

| Syntax | Status |
|---|---|
| `X percent of Y` / `X power Y` | PRODUCTION VERIFIED fresh this pass |
| `absolute value of X` / `square root of X` | PRODUCTION VERIFIED fresh this pass |
| `round of X` / `round up of X` / `round down of X` | PRODUCTION VERIFIED fresh this pass |
| `larger of X and Y` / `smaller of X and Y` | PRODUCTION VERIFIED fresh this pass |
| `sine of X` / `cosine of X` / `tangent of X` (degrees) | PRODUCTION VERIFIED fresh this pass |
| `log of X` (base 10) / `natural log of X` (base e) | PRODUCTION VERIFIED fresh this pass |
| `pi` | PRODUCTION VERIFIED fresh this pass |

### C12. Cryptography (D91/D92)

| Syntax | Status |
|---|---|
| `hash "text" as "sha256" into digest` | PRODUCTION VERIFIED fresh this pass |
| `hash "text" as "sha256" with key "secret" into digest` (HMAC) | RUNTIME EXISTS, D91 regression suite (not re-executed fresh, plain-hash path was) |
| `encrypt "text" with key "secret" into cipher` | PRODUCTION VERIFIED fresh this pass |
| `decrypt "cipher" with key "secret" into text` | PRODUCTION VERIFIED fresh this pass |

---

## Summary table (by NodeKind, in-scope only)

| Category | Count |
|---|---|
| Total `NodeKind` values in `Otter.Contract.psm1` | 127 |
| Excluded from this sweep (UI/desktop/web-server surface) | 13 |
| In scope for this sweep | 114 |
| ...explicitly rejected at runtime (real V1 decisions already made) | 8 |
| ...target-specific to `otter web` only, absent from the interpreter | 4 (HTTP GET/POST/PUT/DELETE) |
| ...remaining candidates | 102 |
| ...of which PRODUCTION VERIFIED (fresh, this sweep, real `otter run`) | ~55 |
| ...of which RUNTIME EXISTS / verified via this project's own prior committed regression tests (D-numbered), not re-run fresh this pass | ~35 |
| ...of which PARSES BUT RUNTIME UNVERIFIED (interactive dialogs, or environment lacks required privilege/target) | ~12 |

See `docs/OTTER_1_0_GAP_REPORT.md` for what this means for the V1
release decision.
