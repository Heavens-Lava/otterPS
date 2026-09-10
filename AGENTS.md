# Otter - agent instructions (Codex)

You are the **front end** agent for the Otter programming language.

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
write to it, copy from it, or touch its git state. Everything you do stays
inside `otterPS`.

**2. Never edit files owned by the back end agent.**
Claude is building the interpreter at the same time. See the ownership table.

**3. Never edit `Otter.Contract.psm1`, `SPEC-DECISIONS.md`, or `rules.md`.**
These are frozen. If you need a new token kind, a different AST shape, or hit
an ambiguity `SPEC-DECISIONS.md` does not answer: **stop and ask Jeff.** Do not
work around it locally.

That last rule is the important one. A contract change only one half knows
about is the worst failure mode here, because the code still merges cleanly
and the language is silently wrong.

---

## File ownership

| File | Owner |
|---|---|
| `Otter.Contract.psm1` | **frozen** — Jeff approves changes |
| `SPEC-DECISIONS.md`, `rules.md` | **frozen** — Jeff approves changes |
| `src/Otter.Lexer.psm1` | **you** |
| `src/Otter.Parser.psm1` | **you** |
| `tests/Lexer.Tests.ps1` | **you** |
| `tests/Parser.Tests.ps1` | **you** |
| `src/Otter.Interpreter.psm1` | Claude — do not touch |
| `src/Otter.Runtime.psm1` | Claude — do not touch |
| `otter.ps1`, `otter.cmd` | Claude — do not touch |
| `tests/Interpreter.Tests.ps1` | Claude — do not touch |
| `tests/Run-Tests.ps1` | Claude — do not touch |
| `examples/*.ot` | shared — add freely, never delete another's |

---

## Your contract

```
                 you                              Claude
  source ──> [ LEXER ] ──> Token[] ──> [ PARSER ] ──> ProgramNode ──> [ INTERPRETER ]
```

Export exactly these two functions, one per module:

```powershell
# src/Otter.Lexer.psm1
function ConvertTo-OtterTokens {
    param([Parameter(Mandatory)][string]$Source)
    # returns [Token[]], always ending with one TokenKind::EndOfFile
}

# src/Otter.Parser.psm1
function ConvertTo-OtterAst {
    param([Parameter(Mandatory)][Token[]]$Tokens)
    # returns [ProgramNode]
}
```

Both modules must begin with this exact line — note the `..\`, because the
contract lives at the repo root while your modules live in `src\`:

```powershell
using module ..\Otter.Contract.psm1
```

That line makes your `Token` and `Node` objects the *same .NET type* the
interpreter checks against. Verified on PS 5.1: `using module` resolves
relative to the **script file**, not the working directory, and type identity
survives the module boundary.

---

## Things that will save you time

- **Emit explicit `Indent` / `Dedent` tokens.** The parser must never
  re-measure whitespace.
- **Tabs are allowed** (D7). 4 spaces = one level, 1 tab = one level, a file
  may use either. This is a correction — an earlier draft of D7 said tabs were
  an error. They are not.
- **`and` is both addition and boolean-and** (D11). Inside a condition it is
  always boolean; in a `make` statement it is addition. Precedence, tightest
  first: `not`, `and`, `or`.
- **`is` is assignment at statement level, comparison inside a condition**
  (D2). Emit the same `Is` token for both; the parser decides by position.
- **Multi-word tokens**: `for each`, `is at least`, `is at most`,
  `is greater than`, `is less than`, `is not`, `divided by` are each ONE token.
- **`.` is overloaded three ways** (D4). Get it right in the lexer and the
  parser stays simple.
- **Built-in grammar is tried before user function calls** (D1). `add 5 to
  score` is always the builtin.
- **`add`/`remove` produce one node each** (D12) — do not try to tell numeric
  mutation from list mutation. The interpreter dispatches on runtime type.

## Error quality is a feature

Every error you raise is an `OtterError` with a real line number. Populate
`SourceLine` and `Suggestion` whenever you can — see D14. Beginners read these
messages, so `Otter expected "than" after "greater".` beats `unexpected token`.

Use approved PowerShell verbs on exported functions (`Get-`, `ConvertTo-`,
`Test-`, `Read-`). `Require-` is not approved and will warn on import.

## Before you hand off

Run your own tests, commit in logical pieces
(`lexer: tokenize literals and keywords`), and do not merge to `main`
yourself — Jeff does that.
