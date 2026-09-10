# Otter Spec Decisions

`rules.md` plus Jeff's build brief are the language design. This file resolves
the questions they leave open, so that two agents implementing different halves
of Otter make the *same* choice.

**If you disagree with anything here, change it here first, then tell both
agents.** Never resolve an ambiguity inside implementation code.

Authority order, highest first:

1. Jeff's build brief
2. `rules.md`
3. this file
4. the code

---

## Scope: what 0.2 covers

| In 0.2 (milestones 1-6) | Deferred |
|---|---|
| variables, `say`, math, `ask` | objects (`is a thing`) -> 0.3 |
| `if` / `otherwise` / nesting | custom types (`a Person has`) -> 0.3 |
| `and` / `or` / `not` | files, `run`, HTTP, JSON -> 0.4 |
| `while`, `repeat`, `count from`, `for each` | |
| lists incl. `empty` / `contains` | |
| functions, parameters, `return`, local scope | |

Deferred keywords are **reserved and lexed now**, so adding them later cannot
break existing programs.

---

## Project structure

The brief suggests `src/Contract/Token.ps1` and `Ast.ps1`. We use a single
`Otter.Contract.psm1` **at the repo root** instead. This is the PS 5.1
adjustment the brief allows, for two measured reasons:

- PowerShell 5.1 shares classes across files **only** via `using module`.
  Dot-sourcing a `.ps1` does not export classes. So contract files must be
  `.psm1`, not `.ps1`.
- `using module` needs a stable literal relative path. Every module in the
  project imports the contract, so its path is frozen along with its contents.

Verified on PS 5.1: `using module` resolves relative to the **script file**,
not the working directory, and classes keep their type identity across module
boundaries — an object built in the parser satisfies `-is [Node]` in the
interpreter.

---

## D1. `add` is both a builtin and a legal function name

```otter
add 5 to score              # builtin: mutate
to add number1 and number2  # a user function also named "add"
```

**Decision (brief section 9): built-in grammar always wins.** The parser tries
built-in statement forms before user-defined calls. `add <expr> to <name>` is
always the builtin. No namespaces, no disambiguation mechanism — do not invent
one now.

> Consequence: a user function named `add` taking a `to` argument is
> unreachable. Accept the definition, and consider renaming the example in
> `rules.md` to `to sum number1 and number2`.

---

## D2. `is` means assignment OR comparison depending on position

```otter
age is 29                # assignment
if age is at least 18    # comparison
```

- Statement level, `<identifier> is <expr>` -> **assignment**
- Inside a condition (after `if`, `while`, `otherwise if`) -> **comparison**

| Otter | Meaning |
|---|---|
| `is` | equal to |
| `is not` | not equal to |
| `is at least` | >= |
| `is at most` | <= |
| `is greater than` | > |
| `is less than` | < |

---

## D3. `make` and `makes` are the same word

Both are accepted and produce the same AST. **`make` is canonical** — prefer it
in docs and examples. `makes` exists for compatibility with `rules.md`.

---

## D4. Period semantics

**REVISED — this replaces the earlier three-jobs version entirely.**

`.` has exactly **one** syntactic meaning outside quoted strings: it
terminates the current explicit block.

`.` is **not** member/property access.

Property access uses:

```text
property of object
```

Examples:

```otter
name of person
text of nameBox
extension of file
```

Nested property access is right-recursive:

```otter
city of address of user
```

The lexer emits `BlockEnd` for `.`. **There is no Dot / member-access token.**

Two places a period is still just a character, not a token:

- inside a quoted string — `say "Hello."`
- inside a number — `3.14` never leaves the number lexer

A `.` anywhere else is a syntax error, and that error is what lets Otter say
`Otter does not use periods to access properties.`

---

## D5. `count from 1 to 5 as number` is real

In 0.2. Both bounds **inclusive**. Bounds are full expressions, so
`count from start to finish as n` must work, not just literals.

---

## D6. `ask` coerces at input time

**REVISED — the earlier version of this decision was wrong.**
Per brief section 11, `ask` does **not** always return text. It performs safe
automatic primitive conversion as it reads:

| The user types | Otter stores |
|---|---|
| `29` | the number `29` |
| `3.5` | the number `3.5` |
| `true` / `false` | the boolean |
| anything else | the text, unchanged |

So `ask "How old are you?" and call it age` followed by
`if age is at least 18` works with no further coercion.

Comparison still coerces where sensible: a numeric string and a number compare
equal. Where a number is required and the value cannot be one, it is a runtime
error naming the value.

---

## D7. Indentation

**REVISED — the earlier version of this decision was wrong.**
Per brief section 15, tabs are **allowed**, not an error.

- **4 spaces = one level. 1 tab = one level.**
- A file may use either style.
- Indentation that does not resolve to a whole level is an error naming the
  line, in the brief's format:

  ```text
  Indentation error on line 7:
  expected indentation level 2 but found inconsistent whitespace.
  ```

- Jumping more than one level deeper at once is an error.
- **Blank lines and comment-only lines never affect blocks** — skip them
  entirely *before* measuring indentation.
- The lexer emits explicit `Indent` / `Dedent` tokens. The parser never
  re-measures whitespace.
- A `.` on its own line closes the innermost open block early.

---

## D8. How `say` joins its parts

```otter
say name "is" age "years old."   ->   Jeff is 29 years old.
```

- Join every part with exactly **one space**
- Numbers print without trailing zeros: `10`, not `10.00`; `3.5` stays `3.5`
- Booleans print as `true` / `false`
- Lists print as their items joined with `, `
- `say` with no parts prints a blank line
- There is **no interpolation syntax** — not `{name}`, `${name}`, or `$name`

---

## D9. Truthiness

| Value | Truthy? |
|---|---|
| `true` | yes |
| `false` | no |
| a number | yes unless `0` |
| text | yes unless empty |
| a list | yes unless empty |
| null | no |
| undefined variable | **runtime error**, not `false` |

---

## D10. Identifiers, keywords, comments

- **Keywords are lowercase only.** `If` is an identifier, not a keyword.
- **Identifiers are case-sensitive.** `loggedIn` and `loggedin` differ.
- Identifiers: letter or `_` first, then letters/digits/`_`.
- **Comments** start with `#` outside a string, and run to end of line.
  `name is "Jeff" # username` works; `say "#1"` keeps the `#`.
- Using an undefined variable is a runtime error naming the variable and line.

---

## D11. `and` is BOTH addition and boolean-and

New in the build brief (section 13), and the sharpest ambiguity in the
language:

```otter
number1 and number2 make total     # addition
if loggedIn and admin              # boolean and
```

**Decision: position decides, exactly like `is` in D2.**

- Inside a **condition** (after `if`, `while`, `otherwise if`, or `not`),
  `and` is **always boolean**.
- In a **statement** ending in `make`/`makes`, `and` is **addition**.

Precedence inside conditions, tightest first:

```text
not        (tightest)
and
or         (loosest)
```

So `if not a and b or c` parses as `if ((not a) and b) or c`.

> Known edge: `if total is 5 and 5` is ambiguous in principle. The rule above
> makes it boolean, which will read oddly. Nobody writes this. Do not add
> syntax to fix it.

---

## D12. `add` / `remove` dispatch on the target's runtime type

```otter
add 5 to score              # number  -> arithmetic
add "Pokemon" to games      # list    -> append
remove 2 from score         # number  -> arithmetic
remove "Mario" from games   # list    -> remove item
```

**Decision: one AST node per verb.** `AddToStmt` and `RemoveFromStmt` cover
both cases; the **interpreter** dispatches on what the target actually holds.
The parser never needs to know. If the target is neither a number nor a list,
it is a runtime error naming the variable and its actual type.

---

## D13. Lists

```otter
games are              games are empty
    "Zelda"
    "Mario"
.
```

- A list literal is closed by `.` or by dedent. The brief prefers the explicit
  `.` because the relationship to following indentation is otherwise
  ambiguous — **write it in examples**, but accept both.
- `games are empty` produces a `ListDefStmt` with zero items.
- `if games contains "Zelda"` -> `ContainsExpr`. Comparison uses the same
  equality rules as `is`.
- Lists are 0.2. Nesting lists inside lists is not.

---

## D14. Error message format

Per brief section 32, errors are written for beginners. Two forms:

- `Format()` — one line, used by the REPL:
  `Otter: I expected a number but got "banana" (line 4)`
- `FormatDetailed()` — the block form, used when running a script file:

  ```text
  Otter Syntax Error

  Line 4:
      if age is greater 18

  Otter expected "than" after "greater".

  Try:
      if age is greater than 18
  ```

Rules:

- Every error carries a **real line number**.
- Populate `SourceLine` whenever the source is available — the offending line
  is most of the value.
- Populate `Suggestion` whenever a plausible fix exists.
- **A raw PowerShell exception must never reach a normal user.** The entry
  point catches everything; only `-DebugAst`-style developer mode shows stack
  traces.

---

# Part 2 decisions (rules2.md)

`rules2.md` is a design target for a much larger Otter: UI, web servers,
HTTP, databases. Most of it is future work. These decisions cover only what
is needed to start, plus the one place Part 2 **contradicts** Part 1.

---

## D15. Properties use `of`. The period is NOT member access.

**This is a breaking change to the core language.** The two documents
disagree outright:

| | |
|---|---|
| `rules.md` section 27 | `say person.name` |
| `rules2.md` section 2 | "Do not write `person.name`. Write: `name of person`" |

**Decision: `rules2.md` wins.** It is newer and states the rule as a
prohibition, and the reasoning in section 3 is sound — a period cannot be both
"close this block" and "reach into this object" without the grammar becoming
ambiguous on exactly the lines where blocks end.

Consequences:

- `name of person`, `text of nameBox`, `city of address of user` — nesting
  reads right to left, innermost last.
- Assignment: `text of message is "Hello"` -> `MemberAssignStmt`.
- **D4 rule 2 is void.** A `.` between identifiers is no longer member
  access. The lexer should keep recognising it *only* to raise a helpful
  error:

  ```text
  Otter Syntax Error

  Line 4:
      say person.name

  Otter reads properties with "of", not with a period.

  Try:
      say name of person
  ```

- `MemberAccessExpr` keeps its existing shape (`Target` + `MemberName`), so
  only the syntax that builds it changed, not the contract.
- **`rules.md` section 27 needs updating** to match. That is Jeff's file.

---

## D16. What 0.3 covers, and what it does not

`rules2.md` describes UI controls, layout, events, web servers, HTTP, CRUD
and databases. All of it depends on objects and properties existing first —
`text of nameBox` is just property access, and a button is just an object.

**Decision: 0.3 is objects and properties only.**

| In 0.3 | Deferred |
|---|---|
| `person is a thing` with an indented body | UI controls and layout (section 5-9) |
| `name of person` reading | `when` events (section 8) |
| `text of message is "Hello"` assigning | web servers, ports, HTTP (10-13) |
| `a Person has` custom types | CRUD and databases (14-19) |
| nested `city of address of user` | filler words (D17) |

Build the foundation before the building. A `when` event or a database row is
not reachable until an object is.

---

## D17. Filler words vs structural words

`rules.md` (revised) now states this directly, and `rules2.md` section 4 is
the stale copy - it still lists `of` among possible filler words. **That is
wrong**, and the distinction matters enough to keep stated here.

Words such as `the`, `a`, `an`, and `value` **may** be optional filler in
explicitly permitted grammar positions. Structural words such as `of`, `to`,
`from`, `in`, `where`, `into`, and `as` are **not** globally ignorable,
because they carry grammatical meaning.

| Word | Role |
|---|---|
| `the` | potentially filler |
| `a` | potentially filler |
| `an` | potentially filler |
| `value` | potentially filler |
| `called` | potentially filler |
| `then` | potentially filler |
| `of` | **structural** |
| `to` | **structural** in many forms |
| `from` | **structural** |
| `with` | **structural** |
| `where` | **structural** |
| `into` | **structural** |
| `in` | **structural** |
| `as` | **structural** |
| `at` | **structural** |
| `on` | **structural** |

`name of person` cannot discard `of` — it is what establishes property
ownership. Removing it changes `name of person` into two unrelated words.

**Decision: no filler words in 0.3.** They are optional by definition, so
nothing is blocked by leaving them out, and each one adds a place the parser
can go wrong. `a` is already load-bearing (`is a thing`, `is a Person`), so
treating it as skippable while it is also a keyword is exactly the ambiguity
that bites later. Revisit once objects are solid, one word at a time, with a
test each.

---

## D18. One period closes one block

`rules2.md` section 3 is more specific than D4 was:

```otter
when loginButton is clicked
    if text of usernameBox is empty
        say "Enter your username."
    otherwise
        say "Welcome"
    .          <- closes the if
.              <- closes the when
```

**Decision: each `.` closes exactly one block**, the innermost open one. It
never closes two at once, and it stays optional — a dedent closes a block just
as well.

---

## D19. Property access

> Jeff's note numbered this D8; that number was already taken by the `say`
> formatting rule, so it lands here as D19 rather than renumbering the
> earlier decisions.

Properties are written **property-first**:

```text
property of target
```

`of` is a **structural keyword**, never filler (D17).

Property access is an **expression** and may appear anywhere an expression is
allowed — in `say`, in a condition, as a function argument.

Property access may be **nested**, right-recursively:

```otter
city of address of user
```

```text
PropertyAccessExpr("city",
    PropertyAccessExpr("address",
        VariableExpr("user")))
```

A property access may be used as an **assignment target**:

```otter
age of person is 30
```

The parser resolves this into an unambiguous property-access AST. **The
interpreter never parses property relationships out of strings** — the
structure is in the tree.

### Assignment has one node, with an assignable target

These all produce `AssignStmt`:

```otter
name is "Jeff"                 Target: VariableExpr
age of person is 30            Target: PropertyAccessExpr
text of message is "Hello"     Target: PropertyAccessExpr
```

Valid assignment targets are `VariableExpr` and `PropertyAccessExpr`. Adding
list indexing later means adding a target type, not a second statement node.

`AssignStmt` keeps a convenience constructor taking a plain `[string]` name,
which builds the `VariableExpr` for you, so ordinary assignment stays a
one-liner in the parser.

### `person.name` is a syntax error

Not deprecated, not accepted-with-a-warning — an error, with the fix in the
message:

```text
Otter Syntax Error

Line 4:
    say person.name

Otter does not use periods to access properties.

Try:
    say name of person
```

Carrying both forms would permanently complicate the lexer and undermine the
clean "a period closes a block" rule. Otter is young enough to make this
change now.

---

## D20. File objects — the back end is ready, the grammar is not

The revised `rules.md` gives a file properties:

```otter
say name of file
say extension of file
say size of file

for each file in files
    if extension of file is ".jpg"
        move file to "Pictures"
    .
.
```

**Decided, and implemented:**

- A file is an `OtterObject` with type name `file` and the properties
  `name`, `extension`, `size` (bytes, a number), and `path` (the full path).
- Every file operation accepts **either** a path the programmer typed **or**
  a file object — because `move "hello.txt" to ...` passes text while
  `move file to ...` passes an object.
- Otter writes UTF-8 **without** a byte-order mark, so `size of file` matches
  the text that was written and other tools do not show a stray `ï»¿`.

**Open — needs Jeff:** nothing in `rules.md` says how you obtain `files` in
the first place. The example loops over it, but no syntax produces it. Some
possibilities, none chosen:

```otter
get files in "Pictures" into files
files in "Pictures" become files
list files in "Pictures" into files
```

This also raises a second undecided question: is there a **folder** object,
and does `for each file in files` recurse into subfolders? Until both are
settled, the file-object support is reachable only from the runtime, not from
Otter source.
