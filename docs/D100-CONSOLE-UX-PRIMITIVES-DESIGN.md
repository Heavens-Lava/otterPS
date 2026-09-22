# D100: Console UX Primitives — Colors, Cursor, Menus, Progress, Secret Input, TTY Detection

**Status:** Implemented and certified — see "Implementation note" below.
**Authoritative spec:** Jeff's sign-off in-session, covering the 6 items left
unchecked in checklist section 12 (Console Application Development) after
independent verification found no existing grammar for any of them.
**Author:** Claude (interpreter/runtime). Grammar/lexer/parser/Contract
implementation is normally Codex's (`src/Otter.Lexer.psm1`,
`src/Otter.Parser.psm1`) — this document was originally written as the
handoff to them, but Jeff authorized Claude to implement the full stack
directly since Codex was unavailable (see the implementation note).

**Implementation note (added after the fact):** all six features below were
implemented exactly as specified — Contract, lexer, parser, interpreter, and
JS-compiler rejection cases — and certified end-to-end through the real
`otter run`/`otter check`/`otter web` CLI in
`tests/ConsoleUxPrimitives.Tests.ps1` (18 tests). Two things this sandbox
could not verify are called out explicitly in that test file rather than
silently skipped: real cursor movement (no attached console handle here even
when not explicitly redirected) and real character masking for `ask
secretly` (`[Console]::ReadKey` throws under redirected stdin, so those
tests exercise the documented `Read-Host` fallback instead). One real bug
was found and fixed during implementation testing: `show progress` redrawing
in place left a following `say` glued onto the same line until a
progress-bar-pending-newline flush was added.

---

## Why these six, together

All six were independently confirmed missing (zero related `TokenKind` or
`NodeKind` anywhere in the frozen contract) while triaging checklist section
12. None of them can be built without new grammar, so none of them were
things I could invent and ship unilaterally — this document is that design,
written so Codex can implement the lexer/parser/contract side without
re-deriving the decisions, and so I can implement the interpreter/JS-compiler
side against a settled shape once the AST nodes exist.

Every syntax choice below reuses an EXISTING token where one already fits,
following this project's own established convention (D67/D69's "small
enumerations are plain string values, not new keywords" pattern; D72's
"optional trailing modifier" pattern for `atomically`) rather than inventing
new punctuation or new reserved words where a contextual identifier already
does the job safely.

**Scope decision, explicit and deliberate:** every statement below is
specified for the **console/interpreter target only** in this first pass.
Desktop (WPF) and web (JS) targets should get the existing, established
"unsupported host capability" clean diagnostic (matching HTTP's own
console-unsupported precedent) rather than a silently different or degraded
behavior. Extending any of these to desktop/web is real, separate follow-up
work once a real dogfood need demonstrates it — not attempted here, per this
project's own "do not add language magic until dogfooding demonstrates a
need" principle.

---

## 1. Terminal colors/styles

```otter
say "Error!" in color "red"
say "Success" in color "green"
```

**Grammar:** parses exactly like today's `say <parts>`, then optionally
checks for a trailing `In` token (already a reserved `TokenKind` — no new
token needed) followed by the ordinary identifier `color` (contextual,
matching `current`/`environment`/`system` elsewhere), then `Read-OtterValue`
for the color name.

**Collision safety:** `In` is already unconditionally tokenized as
`TokenKind::In` today, so `say "The cat is in the hat"` is unaffected (that
`in` is inside a string literal, never re-tokenized). A bare, unquoted `in`
appearing mid-parts-list was already a parse error before this change
(`Read-OtterValue` has no production starting from `TokenKind::In`), so
there is no regression risk, only new capability.

**Contract change:** new `SayStmt` constructor overload
`SayStmt([Node[]]$parts, [Node]$colorExpr, [int]$line)`, adding
`[Node]$ColorExpr` (nullable). Existing 2-arg constructor unaffected,
`ColorExpr` defaults `$null` — matches `WriteFileStmt`'s `Atomic`-flag
precedent exactly (additive, non-breaking).

**Interpreter semantics:** evaluate `ColorExpr`, require a string; map to
`[System.ConsoleColor]` by name (case-insensitive: red, green, yellow, blue,
cyan, magenta, white, gray, darkgray, darkred, darkgreen, darkyellow,
darkblue, darkcyan, darkmagenta, black). An unrecognized name is a clean
Otter error naming the valid list, not a silent fallback to default color.
`Write-Host -ForegroundColor $mapped` instead of the plain `Write-Host` path
when `ColorExpr` is set.

**JS/desktop:** `ColorExpr` present but target isn't console → clean
"color is not supported on the web/desktop target yet" diagnostic at
compile/run time, not a silently colorless print.

---

## 2. Cursor positioning

```otter
set cursor to row 5 column 10
```

**Grammar:** new statement form under the existing `Set` dispatch (same
family as `set current directory to`/`set environment variable ... to`):
after `Set`, ordinary identifier `cursor` (contextual), then `To`, then
ordinary identifier `row` + `Read-OtterValue` (row number), then ordinary
identifier `column` + `Read-OtterValue` (column number).

**Contract change:** new `SetCursorPositionStmt : Node` with `[Node]$Row`,
`[Node]$Column`, `[int]$Line`. New `NodeKind::SetCursorPosition`.

**Interpreter semantics:** both values must evaluate to non-negative whole
numbers (clean "I need a row/column number of 0 or greater" error
otherwise); Otter's row/column are 1-based (matching D5's inclusive
1-based counting convention throughout the language), so subtract 1 before
calling `[Console]::SetCursorPosition($column - 1, $row - 1)`. Out-of-range
values (beyond the current buffer size) should surface .NET's own
`ArgumentOutOfRangeException` translated into a clean Otter error via the
existing host-error-translation path, not a raw exception.

---

## 3. Interactive menus

```otter
choose from options into choice
```

**Grammar:** extends the existing `Choose`-token dispatch (D67:
`choose file into path`, `choose folder into path`, `choose file to save
into path` — all currently distinguished by the identifier immediately
after `Choose`). Add a fourth branch: after `Choose`, check for the
already-existing `From` token (distinct `TokenKind`, trivially
distinguishable from the identifiers `file`/`folder` the other three
branches check for — no ambiguity). Then `Read-OtterValue` for the list
expression, then `Into` + target variable name, exactly like every other
`... into <target>` statement in the language.

**Contract change:** new `ChooseFromListStmt : Node` with `[Node]$Options`,
`[string]$Target`, `[int]$Line`. New `NodeKind::ChooseFromList`.

**Interpreter semantics:** `Options` must evaluate to a non-empty list
(clean "I cannot choose from an empty list" error otherwise). Print each
item numbered (`1. <formatted item>`, using the same `Format-OtterValue`
`say` already uses), prompt for a number, re-prompt on anything that isn't
a valid in-range integer (never a raw exception), then set `Target` to the
**selected item itself** (not its index) — matching how `random item from
games into game` already hands back an element, not a position.

---

## 4. Progress indicators

```otter
show progress 50 percent
```

**Grammar:** extends the existing `Show` dispatch (D47: `show app`).
After `Show`, check for the ordinary identifier `progress` (contextual) as
a new branch ahead of the existing generic "show a UI resource" fallback.
Then `Read-OtterValue` for the percentage, then require the existing
`Percent` token (D88's `X percent of Y` already established this token) —
no label/message argument in this first pass, deliberately (see the "not
added" note at the end of this document).

**Contract change:** new `ShowProgressStmt : Node` with `[Node]$Percent`,
`[int]$Line`. New `NodeKind::ShowProgress`.

**Interpreter semantics:** value must evaluate to a number in `[0, 100]`
(clean error naming the actual value if outside that range — never silently
clamped, per "dangerous/invalid behavior must be visible"). Render a
fixed-width ASCII bar redrawn on the current line via a leading `\r` (no
newline), e.g. `[###########-------] 55%`, so repeated calls update in
place rather than spamming new lines — the natural, expected behavior for
a CLI progress indicator. A subsequent unrelated `say` call should emit a
real newline first so it doesn't collide with the bar's line.

---

## 5. Password/secret input

```otter
ask secretly "Password:" and call it pw
```

**Grammar:** after the existing `Ask` token, optionally check for the
ordinary identifier `secretly` (contextual) before the prompt expression;
if present, consume it and set a new `Secret` flag, then parse the rest of
the statement exactly as today (`<prompt> and call it <name>`).

**Contract change:** new `AskStmt` constructor overload
`AskStmt([Node]$prompt, [string]$name, [bool]$secret, [int]$line)`, adding
`[bool]$Secret`. Existing 3-arg constructor unaffected, `Secret` defaults
`$false` — same additive pattern as `WriteFileStmt`'s `Atomic` flag.

**Interpreter semantics:** print the prompt exactly as `ask` already does,
then read input character-by-character via `[Console]::ReadKey($true)`,
printing `*` for each character typed (Backspace removes the last `*` and
buffered character) instead of echoing the real character, terminating on
Enter. The value stored in the target variable is the real plain text
typed (Otter has no `SecureString`/masked-value runtime type — this only
changes what appears on screen while typing, matching the checklist item's
literal ask: "password/secret **input**," not encrypted-at-rest storage,
which `set credential "n" to "secret"` (D81) already covers separately for
anything that needs to persist).

**Testing note:** unlike the REPL's `Read-Host`-based main loop (left
alone this session specifically because changing its core input path
risks breaking the piped-stdin automation this whole test suite depends
on), `ask secretly` is a **new, opt-in** statement only reached when a
program explicitly uses it — it doesn't change how any *existing* `ask`
or the REPL behaves, so the same testing-safety objection doesn't apply
here. It will still need real interactive verification (or an accepted
"verified by construction, not full keystroke simulation" note, matching
this project's own precedent for D82/D84's unexecutable-in-this-sandbox
success paths) since `[Console]::ReadKey` cannot run under redirected
stdin either.

---

## 6. TTY detection (covers "noninteractive mode" too — no separate syntax needed)

```otter
if console is interactive
    say "Running in a real terminal."
otherwise
    say "Running noninteractively - skipping the progress bar."
.
```

**Grammar:** a new, special-cased two-word condition recognized directly
inside `if`/`while` condition parsing, alongside the existing special cases
there (`X contains Y`, `X starts with Y`). Requires a new `TokenKind::Console`
(the bare word `console`, contextual — only significant when immediately
followed by `Is` + the identifier `interactive`; `console` remains a valid
ordinary variable name everywhere else, per D33's keyword-narrowing
convention). On recognizing `console is interactive`, produce a new,
field-less expression node — there is no "noninteractive mode" statement
to separately design; `if not console is interactive` (D11's existing
`not` already composes with any boolean condition) is the entire answer to
that checklist line.

**Contract change:** new `ConsoleInteractiveExpr : Node` (no fields beyond
the inherited `Line`). New `NodeKind::ConsoleInteractive`.

**Interpreter semantics:** `-not ([Console]::IsInputRedirected -or
[Console]::IsOutputRedirected)` — false if EITHER stream is redirected,
since most of the console-UX features above (colors, cursor positioning,
progress bars, interactive menus) only make sense when both are real,
attached streams; a program gating on this before using them is exactly
the intended use case.

---

## Deliberately not included in this pass

- **A labeled/titled progress bar** (`show progress "Downloading" at 50
  percent`) — no real dogfood case has asked for a label yet; the plain
  form above is the minimal, unambiguous cut. Add the labeled form later
  if a real program needs it, following the same "demonstrated need"
  principle everything else in this project already follows.
- **Desktop/web equivalents** for any of the six (a WPF `ProgressBar`/
  `PasswordBox`, a DOM `<progress>`/`<input type="password">`) — real,
  plausible follow-up work, deliberately scoped out of this pass so the
  console-target semantics above can be reviewed and implemented on their
  own first, rather than growing this into a six-feature, three-target
  design all at once.
