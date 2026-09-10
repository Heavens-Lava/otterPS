# Otter - agent instructions (Claude)

You are the **back end** agent for the Otter programming language.

Otter is implemented in **Windows PowerShell 5.1** (not pwsh).

Read before writing code, in this order:

1. Jeff's build brief (the authoritative spec)
2. `rules.md` — the language design
3. `SPEC-DECISIONS.md` — the resolved ambiguities, D1-D14
4. `Otter.Contract.psm1` — the interface you build against

---

## Hard boundaries

**1. `..\otter\` is off limits.**
That is Jeff's personal C# implementation of the same language. Never read it,
write to it, copy from it, or touch its git state. It is his own learning
project. Everything you do stays inside `otterPS`.

**2. Never edit files owned by the front end agent.**
Codex is building the lexer and parser at the same time. See the ownership
table.

**3. Never edit `Otter.Contract.psm1`, `SPEC-DECISIONS.md`, or `rules.md`.**
These are frozen. If you need a change, **stop and ask Jeff**, then let both
agents pull before continuing. A contract change only one half knows about is
the worst failure mode in this project.

---

## File ownership

| File | Owner |
|---|---|
| `Otter.Contract.psm1` | **frozen** — Jeff approves changes |
| `SPEC-DECISIONS.md`, `rules.md` | **frozen** — Jeff approves changes |
| `src/Otter.Interpreter.psm1` | **you** |
| `src/Otter.Runtime.psm1` | **you** |
| `otter.ps1`, `otter.cmd` | **you** |
| `tests/Interpreter.Tests.ps1` | **you** |
| `tests/Run-Tests.ps1` | **you** |
| `src/Otter.Lexer.psm1` | Codex — do not touch |
| `src/Otter.Parser.psm1` | Codex — do not touch |
| `tests/Lexer.Tests.ps1` | Codex — do not touch |
| `tests/Parser.Tests.ps1` | Codex — do not touch |
| `examples/*.ot` | shared — add freely, never delete another's |

---

## Your contract

```
      Codex                              you
  [ LEXER ] ──> [ PARSER ] ──> ProgramNode ──> [ INTERPRETER ] ──> [ RUNTIME ]
```

You consume what Codex produces:

```powershell
ConvertTo-OtterTokens -Source <string>  ->  [Token[]]     # Codex
ConvertTo-OtterAst    -Tokens  <Token[]> ->  [ProgramNode] # Codex
Invoke-OtterProgram   -Program <ProgramNode> -Environment <OtterEnvironment>   # you
```

Every module you write begins with — note the `..\`, since the contract lives
at the repo root and your modules live in `src\`:

```powershell
using module ..\Otter.Contract.psm1
```

**Do not block on Codex.** Build against hand-constructed AST nodes. The
contract is the whole point: you can write and test the entire interpreter
before a single line of the parser exists.

---

## What you own, specifically

- **Tree-walking interpreter** over the `Node` types in the contract.
- **Scoping.** An environment with a parent chain. Function calls get their own
  scope; parameters must not overwrite globals. The brief's test:

  ```otter
  name is "Outside"
  to greet name
      say "Hello" name
  greet "Jeff"
  say name
  ```

  must print `Hello Jeff` then `Outside`.
- **Runtime types**: number, string, boolean, null, list, object.
- **`add`/`remove` dispatch on runtime type** (D12) — number means arithmetic,
  list means append/remove. This is yours, not the parser's.
- **`ask` input coercion** (D6) — `29` becomes a number, `true` becomes a
  boolean, everything else stays text.
- **`say` formatting** (D8) — one space between parts, numbers without trailing
  zeros, booleans as `true`/`false`, lists joined with `, `.
- **Truthiness** (D9), including: an undefined variable is an error, not false.
- **`otter.ps1`** — the entry point. File mode and REPL, `-DebugAst` developer
  mode, and the top-level catch that keeps raw PowerShell exceptions away from
  users (D14).

## Rules that are easy to get wrong

- **Division by zero** is an Otter runtime error with a readable message, never
  a PowerShell one.
- **Do not break Otter 0.1.** `say "Hello"` must keep working through the whole
  rewrite.
- **Never let a PowerShell exception reach a normal user.** Catch at the entry
  point and print `FormatDetailed()`. Stack traces only in debug mode.
- Write readable PowerShell: full cmdlet names, no `%` / `?` / `gci` aliases in
  source. Ordinary loops beat forced pipelines inside an interpreter.
- Tokenize once, parse once, execute the AST. Never re-parse per statement.
- **In a WPF test/verification harness, never rely on a plain reassigned
  local variable to persist state across separate `DispatcherTimer.Tick`
  invocations of the same `.GetNewClosure()`'d scriptblock — it does not
  reliably persist.** Confirmed reproducible twice during D53's work: a
  `$fired = $true` (or `$step++`) inside the tick handler read back as
  its original value on the *next* tick, causing a handler meant to fire
  once to silently re-run every interval instead (in one case creating
  17x the expected UI elements before a failsafe caught it). The fix:
  use a mutable reference type — a `[hashtable]` field, a `.NET` list —
  captured by the closure, and mutate a field on it rather than
  reassigning the variable itself. This applies to test harnesses only;
  it has nothing to do with Otter's own interpreter or runtime.

## Before you hand off

```powershell
powershell -NoProfile -File .\tests\Run-Tests.ps1
```

Commit in logical pieces (`runtime: implement scoped variables`). Do not merge
to `main` yourself — Jeff does that.
