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

## Decision ledger

**Before assigning a decision number, read this ledger. Do not claim a
number already listed below. Update the ledger in the same commit when
a new decision number is reserved.** Multiple agents work on this repo
at once (front end, back end, web) — this ledger is the single source
of truth for "what's the next number," so nobody has to guess or
collide with work in flight.

NEXT DECISION NUMBER: D54

CLAIMED:
- D49 — HTTP requests and web data — Gemini
- D50 — Otter Web App Compiler — Gemini
- D51 — Web Servers and API Routes — Gemini
- D52 — recent grammar/UI batch documentation (`has` for existing
  resources, comma `put`, compact/optional-`is` inline `has`,
  contextual `the`, row/column layout) — Claude
- D53 — scroll container — Claude (landed: `a550cbc`, `f29213f`)

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

## D20. File and folder discovery

```otter
get files in "Pictures" into files
get folders in "Documents" into folders
```

The result is a **list of file objects** (or folder objects), so it drops
straight into `for each file in files`.

`get` and `into` are reused from the CRUD vocabulary already established in
`rules2.md` section 14 (`get user from database where id is 5 into user`) —
no new verb.

**File object properties:**

| Property | Value |
|---|---|
| `name of file` | `photo.jpg` |
| `extension of file` | `.jpg` |
| `size of file` | bytes, a number |
| `path of file` | the full path |

**Folder object properties:** `name`, `path`, `created`, `modified`.

**A folder deliberately has no `size`.** Measuring one means walking
everything inside it, which is far too expensive to do just because someone
asked for the folder. If folder size is wanted later it should be requested
explicitly, not carried by every folder object.

Every file and folder operation accepts **either** a path the programmer
typed **or** an object:

```otter
move "photo.jpg" to "Pictures"     # text
move file to "Pictures"            # an object
```

Otter writes UTF-8 **without** a byte-order mark, so `size of file` matches
the text that was written.

---

## D21. Folder traversal is never recursive by default

```otter
get files in "Pictures" into files                    # only Pictures
get files in "Pictures" and subfolders into files     # and everything under it
```

**Decision: discovery does not recurse unless `and subfolders` says so.**

Silently reading an entire drive because someone named a folder is exactly
the surprise the language should not have — and it is slow in a way the
programmer never asked for.

### Folder operations

```otter
create folder "Backup"
delete folder "Backup"
copy folder "Work" to "Backup"
move folder "Work" to "Archive"
```

**`delete folder` refuses a folder that still has things in it.** Jeff's
Part 3 note says Otter must not silently do dangerous things, and a
`delete folder` that quietly erased a tree is the clearest example. The error
says how many things are in the way.

> **Open:** there is no syntax yet for "delete this folder and everything in
> it". That needs to be deliberate wording, not a flag. Until it exists,
> emptying a folder is done file by file.

---

## D22. `gone` is the absence of a value

```otter
user is gone

if user is gone
    say "User was not found."
.

if user is not gone
    say name of user
.
```

**`gone` is canonical.** Not `nothing`, `null`, `nil`, or `None` — and there
is exactly **one** word for it. `gone` reads better aloud than `nothing`
(`if user is gone`) and is shorter.

**`gone` means "no value exists here" and nothing else.** These are five
different states and Otter must never confuse any two of them:

```otter
user is gone          # no value
name is ""            # text, empty
score is 0            # a number
games are empty       # a list, empty
loggedIn is false     # a boolean
```

- `gone` is **not true enough** for an `if`.
- Setting a variable to `gone` deliberately clears it.
- **An undefined variable is still an error, not `gone`** (D9). Never
  mentioned and deliberately emptied are different things.

`gone` needs no AST node — it is a `LiteralExpr` carrying `$null`, which is
what makes `if user is gone` an ordinary comparison rather than special
syntax.

---

## D23. `try` / `otherwise` is the beginner error model

```otter
try
    read "settings.json" into settings
otherwise
    say "Could not load settings."
.
```

If anything in the body fails, the `otherwise` body runs instead and the
program carries on.

- No error variable and no error types in this version. `catch ... as error`
  and `throw` are noted in Part 3 as future work; `try` / `otherwise` is
  enough to stop a missing file from killing a program.
- **`return` passes straight through a `try`.** Control flow is not failure —
  if `try` caught the return signal, returning from inside one would silently
  run the `otherwise` body and lose the value. There is a test for this.
- A `try` with no `otherwise` swallows the failure and continues.

---

## D24. `X of Y` is two different things

Both read the same aloud, and they must not share an AST node:

| Written | Meaning | Node |
|---|---|---|
| `name of file` | a genuine **property** of an object | `PropertyAccessExpr` |
| `extension of file` | a genuine **property** | `PropertyAccessExpr` |
| `length of games` | an **operation** applied to a value | `OfOperationExpr` |
| `uppercase of name` | an **operation** | `OfOperationExpr` |
| `first of games` | an **operation** | `OfOperationExpr` |

Pretending a list literally carries a `length` property would make the runtime
object model strange purely to keep the grammar tidy. They share surface
syntax and nothing else.

**The parser decides from the word before `of`.** The operation words are a
fixed, known set — `length`, `uppercase`, `lowercase`, `first`, `last`. Any
other word before `of` is a property.

Consequence worth knowing: a thing with no `length` property still fails as a
property lookup. `length` is not magic on objects; it is only an operation on
text and lists.

---

## D25. The first string and collection operations

```otter
length of name        length of games
uppercase of name     lowercase of name
first of games        last of games

sort games            reverse games

if name contains "Jeff"
if name starts with "J"
if name ends with "Macy"

replace "Jeff" with "Jeffrey" in name
split sentence by " " into words
join words with ", " into text
```

Rules that are easy to get wrong:

- **`sort` and `reverse` change the list in place**, like `add 5 to score`
  does. They are statements, not expressions.
- **`sort` orders numbers as numbers.** Sorted as text, `10` would come
  before `9`.
- **`replace` is plain text, never a pattern.** A `.` means a full stop. A
  language whose strings are quietly regular expressions is a language that
  surprises beginners.
- **`contains` works on text *and* lists** — `if name contains "Jeff"` and
  `if games contains "Zelda"` both read naturally, so both work.
- **`first` / `last` of an empty list is `gone`**, not an error. That is
  precisely what D22 is for.
- Text comparisons are **case-sensitive**, consistent with D10.

---

## D26. `find` gives one thing. `get` gives many.

Singular and plural carry the meaning:

```otter
find file in files where extension of file is ".pdf" into result
```

returns **the first match, or `gone`** — which ties collections straight back
to D22:

```otter
if result is gone
    say "No PDF found."
.
```

The plural form returns a collection:

```otter
get files from files where extension of file is ".pdf" into pdfs
```

> **Not yet implemented** — the plural filter is designed but not built.
> `get files in "X" into y` (D20) is a different statement and does exist.

The item name in a `find` is bound **for the condition only**, exactly like a
`for each` variable. After the statement it is gone — there is a test pinning
this, because a leaking loop variable is a classic source of confusion.

---

## D23a. `otherwise` handles failure, not control flow

An addition to D23, stated explicitly because it is the kind of rule that
gets broken by accident:

> `otherwise` handles **runtime failure** from the `try` body. Normal
> control-flow transfers are **not** failures.

```otter
to find user
    try
        return user
    otherwise
        say "Failed."
    .
.
```

must return normally and never enter `otherwise`. The same will apply to
`break`, `continue`, and any later stop-style transfer: each must pass
through a `try` untouched.

---

## Deferred, deliberately

These are designed but not built, and the reason each is waiting matters.

**`delete folder "Backup" and everything in it`** — the explicit destructive
form. Reads better than a `recursive` flag and makes the danger visible in the
source. `delete folder` itself stays non-recursive forever.

**`measure folder "Pictures" into size`** — folder size, where the verb
signals that work is happening. Better than a `size of folder` property that
looks free but walks a directory tree.

**Methods on custom types** — left undecided rather than forced. `greet jeff`
is indistinguishable from a one-argument function call, and `ask jeff to
greet` overloads `ask`, which already means user input. Candidates worth
weighing later: `have jeff greet`, `tell jeff to greet`, `use greet on jeff`.
`tell jeff to greet` reads best so far. This is its own design milestone.

**`do at the same time`** — its own milestone. The syntax is easy; the
semantics are not. It needs decisions about variable isolation, shared
objects, failure handling, return values, ordering, and cancellation before
any of it is worth parsing. PowerShell 5.1 adds a constraint: background jobs
cannot share the interpreter's live objects at all, so this is real
engineering rather than a parser addition.

---

# Part 3 reconciliation (rules3.md)

`rules3.md` matched the implementation on almost everything — `gone`,
discovery, `and subfolders`, folder safety, `try`/`otherwise`, control flow
not being failure, `length of`, `first`/`last` returning `gone`, singular
`find` vs plural `get`, and the operation-vs-property split were all already
built as written. Two things did not match, and both were corrected.

---

## D27. `replace` mutates only when asked

**Conflict.** `rules3.md` section 26 says the original must not be mutated
unless the syntax explicitly requests it. The implementation mutated
unconditionally.

**Resolved — both forms are real, and the destination is what decides:**

```otter
replace "Jeff" with "Jeffrey" in name                  # changes name
replace "Jeff" with "Jeffrey" in name into fullName    # name is untouched
```

Naming a destination with `into` is the request for the non-mutating
behaviour. Without one, `in name` names the thing being changed — otherwise
the bare form would do nothing at all, which cannot be what it means.

This matches `uppercase of name` in section 22, which returns a new value and
leaves the original alone: nothing changes a variable unless the statement
says which variable it is changing.

---

## D28. Scope (rules3 sections 37-39) — already correct, now frozen

Verified against the implementation rather than assumed:

- **Functions can read outer variables.** `to greet / say name` sees a global
  `name`.
- **Function locals disappear when the function ends** (section 38). A
  variable created inside a function is not reachable afterwards.
- **Function parameters shadow, never overwrite** — already pinned by a test
  since 0.2.
- **Control-flow blocks do NOT create a scope** (section 39):

  ```otter
  if ready
      message is "Starting"
  .

  say message        # works
  ```

  This holds identically for `if`, `while`, `for each`, `count` and `try`.

  The one exception is deliberate: the item name in `find ... where ...` is
  bound for the condition only, like a `for each` variable, and does not
  survive the statement.

**Frozen now**, per section 39's request, before closures or concurrency
arrive and make it expensive to change.

---

## D29. JSON becomes ordinary Otter values

```otter
read json from "settings.json" into settings
convert text from json into user
convert user to json into text
```

**There is no JSON-navigation syntax** (section 36). Once JSON is read it is
an ordinary Otter value:

| JSON | Otter |
|---|---|
| object | a thing, read with `name of user` |
| array | a list, walked with `for each` |
| number | a number |
| `true` / `false` | a boolean |
| `null` | **`gone`** |
| string | text |

So `city of address of user` works on JSON exactly as it works on anything
else, and `if user is gone` catches a JSON `null`.

Invalid JSON is a readable Otter error, never a raw PowerShell one.

---

## D30. Random values

```otter
random number from 1 to 10 into number
random item from games into game
```

- **Both ends of the range are included**, consistent with `count from 1 to 5`
  (D5). PowerShell's `Get-Random -Maximum` is exclusive, so the
  implementation adds one — a test draws 60 times from a range of 3 and
  asserts all three values appear.
- Reversed bounds are accepted and swapped rather than erroring.
- **`random item` from an empty list is `gone`**, matching `first of` and
  `last of` (D25).

---

## D31. `log` / `warn` / `error` are diagnostics, not output

```otter
say "Hello"                    # what the program tells its USER
log "Server started."          # what it tells whoever is RUNNING it
warn "Connection is slow."
error "Could not connect."
```

**Decision: diagnostics go through a separate writer from `say`.** They are
not just `say` with a prefix. Keeping the two apart is what lets a runtime
send diagnostics to a file, a service, or nowhere, without touching what the
program says to its user. There is a test asserting `say` output and
diagnostic output never mix.

Parts are joined with one space, exactly like `say` (D8).

> The keyword is `error`, but the token is named `Problem` in the contract —
> `Error` would read confusingly next to `OtterError`, which is a different
> thing entirely.

---

## Still open after rules3.md

**Dates (sections 42-46) — needs a decision before implementation.**
`rules3.md` gives the syntax but not the value:

```otter
date is today
add 7 days to date
days between startDate and endDate make days
format date as "MM/dd/yyyy" into text
```

What *is* a date value in Otter? If it is text, `add 7 days to date` has to
re-parse it every time and `format` is meaningless. If it is an object, what
are its properties — `year of date`, `month of date`? And `add 7 days to
date` collides with `add 5 to score` (D12): same verb, same shape, different
meaning, decided by the word `days`.

Dates are the one Part 3 area where the syntax is settled and the semantics
are not. Recommend a short decision on the value model before any of it is
built.

**Also unbuilt, and fine to leave:** modules (`use`), packages, command-line
arguments, environment values and secrets, testing syntax, `measure folder`,
`delete folder ... and everything in it`, `sort files by name`, plural
`get ... where`, methods on custom types, and concurrency.

---

## D32. Dates and time

Dates are **first-class values, never text.** Text cannot be added to, cannot
be compared, and has to be re-parsed on every use; a language that stores
dates as strings makes every date operation a parsing problem.

```otter
date is today
started is now

year of date        month of date       day of date
hour of started     minute of started   second of started

add 7 days to date
remove 1 month from date
add 30 minutes to started

format date as "MM/dd/yyyy" into text
days between startDate and endDate make days
```

---

### D32.1 `today` and `now` are different kinds of value

| | Produces | Supports |
|---|---|---|
| `today` | a **date** — no time of day | year, month, day arithmetic and parts |
| `now` | a **date and time** | all six units |

`hour of date` where `date` came from `today` is an **error**, not a silent
zero. Midnight and "no time at all" are different, and answering `0` would
hide a mistake.

Both use **local runtime time**. No timezone syntax in this milestone.

---

### D32.2 Reading a date part is ordinary property access — deliberately

`year of date` builds a **`PropertyAccessExpr`**. It is *not* an
`OfOperationExpr`, and it gets no node of its own.

This is the load-bearing decision in D32, and it is forced. D24 says operation
words are a fixed closed set the parser recognises statically. If `year`,
`month`, `day`, `hour`, `minute` and `second` joined that set, this would
break:

```otter
book is a thing
    year is 1984
.

say year of book        # a perfectly ordinary user property
```

`year of book` and `year of date` are indistinguishable at parse time and must
stay that way. So the **interpreter** resolves them: on a date value it
answers the date part, on an object it looks up the stored property, and on
anything else it reports the usual "no property called ..." error.

Consequence worth stating: a `thing` may carry its own `year` property and it
shadows nothing, because dates and things are different kinds of value.

Parts return **numbers**. `month of date` is `1`–`12`, never a month name —
no month-name syntax in this milestone.

---

### D32.3 Temporal mutation is structurally distinct from D12

```otter
add 5 to score              -> AddToStmt        (no unit)
add 5 days to startDate     -> DateAdjustStmt   (unit: Day)
```

The **unit word is present in the token stream**, so the parser decides the
shape from what it reads and never needs to know what the target holds. That
is the whole reason `TimeUnit` is carried in the AST rather than resolved at
runtime.

- Both spellings are legal: `1 day` and `7 days` produce the same `Day` unit,
  the same way `make` / `makes` collapse in D3.
- `add` and `remove` share one node with an `IsRemoval` flag.
- Adjusting **replaces** the value rather than mutating it in place, so two
  variables holding the same date never change together.
- Applying a time unit to a date-only value — `add 1 hour to date` — is an
  error, matching D32.1.

Month and year arithmetic clamps to the end of the month, so 31 January plus
one month is 28 or 29 February rather than overflowing into March. That is
what .NET does, and it is the reading a person expects.

---

### D32.4 Formatting produces text and changes nothing

```otter
format date as "MM/dd/yyyy" into text
```

The date is untouched, exactly like `uppercase of name` (rules3 section 22).
Format strings follow the ordinary .NET conventions the runtime already uses.

---

### D32.5 Printing a date — decided here, not specified anywhere

Neither `rules3.md` nor the milestone brief says what `say date` should
print, and it has to print *something*:

| Value | `say` prints |
|---|---|
| `today` | `2026-09-09` |
| `now` | `2026-09-09 14:30:05` |

ISO-style, because it is unambiguous, sorts correctly as text, and does not
silently pick a regional convention. Anyone who wants a different shape has
`format date as ...`.

---

### D32.6 Dates compare with the operators that already exist

No new syntax. `is`, `is not`, `is at least`, `is greater than` and the rest
already exist, so they work between two dates:

```otter
if endDate is greater than startDate
    say "The end is after the start."
.
```

A date compared against a number or text is an error rather than a
coincidence. This was not in the brief; it is the natural reading of syntax
Otter already has, and leaving it unimplemented would make `days between`
usable while `is greater than` silently failed.

---

### D32.7 UNRESOLVED — the sign of `days between`

```otter
days between startDate and endDate make days
```

If `endDate` is **before** `startDate`, is the answer negative or absolute?

- **Signed** (`end - start`) composes better and preserves direction.
- **Absolute** reads closer to what the English word "between" suggests.

**Implemented as signed**, matching the argument order, because throwing away
direction cannot be undone by the caller while taking the absolute value of a
signed answer is trivial. Flagged rather than settled — this is Jeff's call.

Whole units only, truncated toward zero: `days between` two date-times 36
hours apart is `1`, not `1.5`.

---

## D33. Keyword reservation — contextual by proof, not by default

**Approved.** Full reasoning and the empirical evidence behind this decision
live in `KEYWORD-AUDIT.md` (95 reserved words tested in 6 grammatical
positions, plus a per-word parser-site count). This entry records what was
decided, for implementation to build against.

### The finding

Of ~100 reserved token kinds, 55 are referenced at exactly **one** site in
the parser — meaning they gate one statement and nothing else, yet they are
unusable as a variable, function, parameter, property, or `for each` name
**everywhere**, because the lexer's keyword table has no notion of
position. Otter was on track to accumulate hundreds of unnecessarily
forbidden ordinary words as the vocabulary grows (D29–D32 alone added 16
new reservations, most of them single-site).

### The rule, going forward (applies to D33 and every future keyword)

> A new keyword is reserved everywhere by default. It may be narrowed to a
> single grammatical position only after the position is proven — by direct
> testing, the same way this audit tested it — to be the word's only real
> use, and only by one of three named mechanisms:
>
> 1. **Adjacency to a trigger token** (D24, D32) — keyword only when a
>    specific token immediately precedes or follows.
> 2. **Statement-head position** (new in D33) — keyword only when the token
>    is the first one on its logical line.
> 3. **Always legal alongside `Identifier`** (already used for `file`/
>    `files`/`folder`/`folders`) — no contextual check; the grammar simply
>    never collides on this word.
>
> A word is **never** made contextual by relying on spelling or
> capitalization convention. If a word appears in more than one grammatical
> position, or in the same position a value or identifier would occupy, it
> stays reserved everywhere — no ad hoc exceptions.

### Words freed by this decision — mechanism 2 (statement-head)

```
copy  move  delete  create  read  write  sort  reverse  replace  split
join  find  get  try  run  log  warn  error  random  json  convert
format  today  now  between  otherwise
```

Each becomes an ordinary identifier everywhere **except** as the first
token of a statement, where it keeps its existing meaning. Verified safe
per-word in `KEYWORD-AUDIT.md` category 2.

### Words freed by this decision — mechanism 1, D24-style adjacency

```
exists    keyword only when preceded by a value (condition position)
contains  keyword only when preceded by a value (condition position)
empty     keyword only when preceded by Are
has       keyword only reachable after the a-driven type-def parse (already
          grammatically unreachable elsewhere — no new check needed)
call, it  keyword only inside the fixed "and call it <name>" phrase
```

### Words freed by this decision — mechanism 3, dead keyword-table entry

```
thing
```

Confirmed, not inferred: `Read-OtterObjectTypeName` reads every token by
`.Text` and never inspects `.Kind` — it already has to, so that future
two-word type names (`text box`) read correctly. The
`'thing' = [TokenKind]::Thing` line can be deleted from the lexer's keyword
table with **zero parser change**.

### Words that stay reserved everywhere — no change

The full category-1 and category-4 lists from `KEYWORD-AUDIT.md`:

```
gone  true  false  a  and  is  to  of  in  into  from  with  where  as
make  makes  not  or
```

`gone`/`true`/`false` sit in ordinary value position with no adjacent token
to disambiguate. `a` carries two separate grammatical roles and a real
collision case (`letter is a` — copy a variable vs. begin a type literal)
that only a capitalization guess could resolve, which D33's rule explicitly
forbids relying on. The rest are the D17 structural set.

**D17 amendment:** `by` (`split X by Y`) is the same part of speech as
`with`/`from`/`into` and was missing from D17's table only because just one
statement used it so far. Added to the structural, always-reserved list
now, before a second use makes the gap look like an accident.

### Reserved by design, not by grammar

`if`, `while`, `repeat`, `count`, `return`, `ask`, `say` are grammatically
eligible for mechanism 2 — each sits at one or two statement-head sites,
same shape as `copy` or `format`. **They stay reserved anyway.** Otter's
own pitch is readability for a beginner, and these are the words used in
every one of the language's own examples. A program that runs with `if is
5` sitting in it is technically unambiguous and quietly hostile to exactly
the reader the language is for. This is a pedagogical boundary, decided
here explicitly rather than falling out of the grammar audit by accident.

### `open` and `when`

Left untouched — these are not accidental reservations. The lexer already
states the reason: they are pre-reserved for a future `open "notes.txt"`
statement (`rules.md` section 31) and future `when` events (`rules2.md`),
neither of which exists yet. Reserving a word before its grammar exists is
sound; D33 does not disturb it.

---

# Part 4 reconciliation (rules4.md)

`rules4.md` confirms more than it changes — sections 12, 13, 15, 16, 17, 18
(canonical half), 27, and 28 all independently restate decisions already
made (D14, D17, D19, D21, D25, D27, D33) without contradicting them. Section
17 is worth naming specifically: it arrives at D33's exact rule, unprompted,
down to reusing `day is 7 / say day` as the example. That is strong outside
confirmation that D33 is pointed the right way.

Three items are new and safe to build now (D34-D36). Two are real open
questions rules4 itself flags as unresolved, and are recorded as open here
rather than decided (D37, D38). One is a tension inside rules4 itself,
flagged rather than resolved (D39).

---

## D34. `plus` - a second spelling for addition, not new grammar

**Verified before deciding, not assumed:** `number is number1 and 5` already
parses and runs correctly today (`15`). Arithmetic inside a plain `is`
assignment is not new - `Read-OtterMathExpression` is already the value
parser for the right-hand side of every assignment, and it already accepts
`and` as addition there. Section 4's "new direction" is a **vocabulary**
request, not a grammar request.

**Decision: `plus` lexes directly to the existing `TokenKind::And`.** No new
`TokenKind`, no new `MathOp`, no parser change - the same one-line pattern
as `make`/`makes` collapsing to one token (D3). `total is price plus tax`
and `total is price and tax` become the same AST.

This inherits D11's one known, accepted edge case: `plus` inside a
*condition* would read as boolean-and, exactly as `and` already does there.
Nobody writes `if a plus b`; D11 already decided not to add syntax to guard
against a case no one writes, and `plus` doesn't change that math.

`price and tax make total` is unaffected and stays valid - rules4 flags it
for *review before 1.0*, not removal now. No action taken on it here.

---

## D35. `increase` / `decrease` - action words for numeric mutation

```otter
increase score by 5
increase score          # implicit +1
decrease lives          # implicit -1
decrease health by damage
```

**Decision: these are new surface syntax over the existing `AddToStmt` /
`RemoveFromStmt` nodes (D12) - no contract change.** `increase X` with no
`by` synthesizes `Amount = LiteralExpr(1.0)`; `decrease X` synthesizes the
same on the removal side. Every existing rule these nodes already carry
applies unchanged: an undefined target is still an error naming the
variable, and runtime dispatch is still by the target's actual type.

**Numeric only - this does not touch list mutation.** `add "Pokemon" to
games` stays the only way to append to a list; rules4's own examples never
show `increase` or `decrease` on a list, and D12's dispatch-by-runtime-type
behavior for lists is untouched.

**Left open, not decided:** rules4 does not say whether `add`/`remove`
should be deprecated for *numbers* now that `increase`/`decrease` exist.
Section 4 explicitly flags `make`-arithmetic for review; it says nothing
equivalent about `add`/`remove`. Treating silence as "no deprecation" and
leaving `add 5 to score` fully valid, per the project's additive-only
precedent everywhere else. If `add`/`remove` should be soft-deprecated for
numbers the way `make`-arithmetic was flagged, that needs its own line in
`rules4.md`, not an inference from omission.

Per section 6, `increase`/`decrease` are statements only, never usable as a
value: `number is increase number` stays invalid, matching the existing
statement/expression split.

---

## D36. Bare `each` - a second spelling for the loop, not a new loop

```otter
each product in products
    say name of product
.
```

**Verified before deciding:** bare `each` does not parse today - checked,
and it currently fails with *"I expected a value here"*, confirming it
falls through to ordinary identifier handling. `each` was already flagged
free-everywhere in `KEYWORD-AUDIT.md`.

**Decision: `each` becomes a D33-mechanism-2 word** (statement-head only,
same category as `copy`/`format`/`get`) that produces the **same
`ForEachStmt`** the existing `for each` combiner already builds. `for each`
stays valid - rules4 calls it "the older" form, not an invalid one, and
nothing here removes it. This is the same coexistence pattern as D34 and
D35: a new preferred spelling, the old one still works.

No conflict with D33's own rule: `each` remains a free identifier
everywhere except as the first token of a statement, exactly like every
other mechanism-2 word.

---

## D37. `stop` - decided

```otter
to greet name
    if name is empty
        stop
    .

    say "Hello" name
.
```

**`stop` terminates the nearest return-capable execution context and
produces no value.** Deliberately framed as "nearest return-capable
context," not "the current function" - so the same semantics extend later
to event handlers, routes, callbacks, and jobs without a redesign, the
moment `when` (or any of those) exists.

`stop` is not `break`. Inside a loop, it does **not** exit the loop - it
exits the function the loop is running in:

```otter
each file in files
    if name of file is "stop.txt"
        stop
    .
.
```

reaching `stop` here ends the whole function, not just the `each`. This is
the sharpest way the word could be misread, so it is stated in the
implementation-facing docs, not left to be inferred. Loop-scoped `break`
is explicitly deferred - only added later if real programs prove they need
it, per D23a's own precedent of not building control-flow transfers before
they are needed.

Semantically, `stop`:

- terminates the current return-capable execution context
- produces no value
- propagates through `try`/`otherwise` using the existing return-control
  mechanism (D23a) - `stop` inside a `try` body does not trigger
  `otherwise`, exactly as `return` does not

### The four cases, each verified rather than assumed

| Case | Outcome | Evidence |
|---|---|---|
| Inside a function | Exits the function | Existing test, unchanged: *"a function returns a value"* |
| Inside `try`, inside a function | Propagates out, exits the function; `otherwise` does not run | Existing test, unchanged: *"return escapes straight through a try"* (D23a) |
| **At the top level** | **A clean `OtterError`, naming the line - not a whole-program exit, not a crash** | New: *"return with no value at the top level is a clean error, not a crash"* |
| Inside a loop, inside a function | Exits the function, **not just the loop** | Existing test, unchanged: *"return escapes from inside a loop"* |

The top-level case needed real work; the other three were already correct
and already tested, because `stop` reuses the exact mechanism `return`
already uses (D23a) rather than introducing a new one.

**A real gap this surfaced, fixed in the interpreter, not the grammar:** a
null-valued `ReturnStmt` thrown outside of any function call was not caught
anywhere. It would have unwound past `Invoke-OtterProgram` uncaught and
been reported as *"Otter hit a problem inside itself"* — flatly wrong,
since nothing broke; the program just tried to stop something that was
never running. `Invoke-OtterProgram` now catches an escaping
`OtterReturnSignal` at that one boundary and raises:

```
Otter: stop only works inside something Otter can call, like a
function. There is nothing here to stop. (line N)
```

This is deliberately general, not `stop`-specific: **any** `OtterReturnSignal`
reaching the top of the program gets this treatment, including a
hypothetical value-carrying top-level `return` — both are tested.

**Implementation is smaller than first proposed, and doesn't touch
`return`'s existing grammar at all.** Checked before building: `return`
today has no bare form — the parser unconditionally requires a value after
it, so `ReturnStmt(Value: $null)` was not reachable from any Otter source
until now. Rather than change `return`'s grammar (which reads
`return <value>` on purpose per `rules.md`), `stop` gets its own
statement-head parser case that constructs `ReturnStmt(Value: $null)`
directly. Zero contract change, zero interaction with `return`'s existing
shape.

**Split across the two lanes**, per Jeff's stated preference to keep D37
out of the D34-D36 batch unless trivial and isolated: the parser piece
(one new keyword, one switch case) *is* trivial and isolated, so it ships
in the same Codex handoff as D34-D36. The top-level fix and its tests are
interpreter-side and are already done, in this repository's own lane —
`OtterReturnSignal` gained a `Line` field to carry the source line for that
error message.

---

## D38. Statement continuation across lines - OPEN, needs its own design pass

```otter
get files in "Pictures" and subfolders
    into pictures
```

This is the one item in rules4 I'm not comfortable turning into even a
tentative proposal, because it touches the language's most load-bearing
rule (D7): indentation **is** the block structure. Every `Indent` token
today means "a new nested block begins." Section 10 asks for a second
meaning - "this indented line is not a new block, it's the rest of the
previous statement" - and the two have to be told apart somehow.

Genuinely open questions, not implementation details:

1. **How does the lexer know a continuation is coming, before it sees the
   next line?** Does an incomplete statement at end-of-line signal it (the
   parser already knows a `get files ... into <name>` statement isn't
   finished when it hits `Newline` without ever reaching `Into`)? Or is
   there an explicit trailing marker?
2. **Which words may lead a continuation line?** Section 10 names
   `where, and, with, by, in, into` as candidates, but immediately qualifies
   it with *"only when the active grammar expects them"* - which is doing a
   lot of work in one clause. `where`-clause filtering on `get files` has no
   grammar at all yet (D20 documents this as unbuilt: *"the plural filter is
   designed but not built"*, D26 note). Section 10's own filtering example
   is speculative on top of a mechanism that is itself speculative.
3. **Does a continuation line's indentation collide with a real nested
   block at the same depth?** `get files in "Pictures" and subfolders` is
   not itself a block-opening statement - but the lexer decides `Indent`
   generically, without knowing what statement it's inside.

Recommend treating this as its own milestone: freeze the answer to (1) and
(2) as a dedicated decision before any lexer work starts, the same way D32
froze `ClockKind`/`TimeUnit` before Codex touched the grammar. Building it
speculatively risks exactly the kind of contract rework the whole
contract-freeze process (`AGENTS.md`, `CLAUDE.md`) exists to prevent.

---

## D39. `create` is for external resources, not object construction - resolved

Section 11 originally gave this example for `create`:

```otter
create user with
    name is "Jeff"
    age is 29
.
```

structurally identical to what `is a thing` already does (D19) — an
indented block of `name is <value>` properties — under a **third**
spelling, alongside `X is a thing` and section 19's own
explicitly-under-review `X has`. Section 19, two sections later, argues the
opposite instinct directly: *"Otter should ultimately prefer one canonical
property-access model... Do not add both permanently merely as
synonyms."* — a principle that applies to object-creation syntax exactly
as much as to the possessive-vs-`of` question it was written about.

**Resolved by Jeff: `create` means bringing an external or domain resource
into existence through a provider or runtime action — a file, a folder, a
database row — never an ordinary in-memory object.** `registration is a
thing` stays the only way to build one. A future `create user in database`
is fine, because that genuinely reaches outside the program the same way
`create folder` already does; a bare `create user with` would not have.

`rules4.md` section 11 has been edited directly to remove the
`create user with` example and state this rule, since this was Jeff's own
correction to his own document, not a scope call for me to make. The other
new form in that section, `create file "notes.txt"`, had no such tension
and is unaffected — a clean, small addition once wanted: a version of
`WriteFileStmt` with no content, or a dedicated "create an empty file"
runtime op.

---

## D40. `has` becomes canonical object construction. `is a thing` stays, legacy

```otter
person has
    name is "Jeff"
    age is 29
    city is "Phoenix"
.
```

reads better aloud than `person is a thing`, and gives Otter's core verbs
clean, separate jobs: `is` assigns a value, `has` builds an object,
`create` reaches outside the program (D39). **Approved. `is a thing` is not
removed** — the same coexistence pattern as every decision this session
(D3, D34, D35, D36): a new preferred spelling, the old one still valid,
documented as legacy rather than deleted.

Nesting and property access are unaffected — both already work exactly
this way, and `has` changes nothing about them:

```otter
person has
    name is "Jeff"

    address has
        city is "Phoenix"
        state is "Arizona"
    .
.

say name of person
say city of address of person
```

### The word `has` is already reserved for something else — checked, not assumed

`a Person has / name / age / .` already exists (`TypeDefStmt`) — declaring
a custom type's field **names**, with no values, one bare identifier per
line. This is a different grammar than `person has / name is "Jeff" / .`,
which needs value-bearing property lines.

**Verified before deciding, not assumed: the two do not collide.** They
are reached from genuinely different parser call sites. `a Person has`
is only reachable after the statement already began with the leading
token `A` (the parser has consumed `a <TypeName>` before it ever checks
for `Has`). A new `person has` production sits in the ordinary
statement-leading-`Identifier` branch instead — a different call site
entirely, checking for `Has` immediately after reading a plain name. They
also read their blocks with different helpers: `a Person has` calls
`Read-OtterTypeFields` (bare names only); `person has` should call the
same `Read-OtterBlock` + `AssignStmt`-validation path `is a thing` already
uses. Two call sites, two readers, one shared word — not a grammatical
ambiguity, a considered reuse: "a Person **has** a name and an age" (the
shape) and "person **has** the name Jeff" (an instance) is exactly how the
word already works in English.

**Decision: `person has` produces the same node `is a thing` already
does** — `ObjectDefStmt(Name: 'person', TypeName: 'thing', Properties)` —
with `TypeName` defaulted to `'thing'` exactly as `is a thing` defaults it
today. **Zero contract change, zero interpreter change.** This only
replaces the *untyped* object-literal spelling. Instantiating a declared
custom type still uses `is a <TypeName>` (`jeff is a Person`) — untouched,
not in scope here.

Grammar-only, Codex's lane, bundled into the same handoff as D34-D37.

---

## D41. Dynamic thing access - frozen

**Otter does not get a separate dictionary runtime type.** Dynamic key
access is a capability of `thing`, not a second collection kind. This
follows directly from the investigation above: `has` (D40), JSON (D29),
and dynamic access all already resolve to the same `OtterObject`, verified
against the real code, not assumed.

```otter
person has
    name is "Jeff"
    age is 29
.

read json from "person.json" into person

set "nickname" to "Jeffrey" in person

get "nickname" from person into nickname
say nickname
```

`scores are a dictionary` is not introduced. It is not needed.

### The nine frozen rules

1. **No separate dictionary runtime type.**
2. **`has` and JSON objects both stay `OtterObject(TypeName: 'thing')`** —
   already true today, unchanged by this decision (verified in the
   investigation above).
3. **Dynamic `get`/`set` operate only on `thing`.** Enforced at runtime:
   `Assert-OtterDynamicKeyTarget` checks `TypeName -eq 'thing'` before
   either statement touches the object.
4. **`get` on a missing key returns `gone`**, not an error — `ReadProperty`
   already returns `$null` for an unset key; the statement simply doesn't
   add the `HasProperty` guard `name of person` uses.
5. **Ordinary `property of thing` keeps its existing missing-property
   error.** Unchanged, and tested directly: the same missing key that
   `get` reports as `gone` still raises *"no property called ..."* through
   `of`.
6. **`set` creates or replaces a dynamic key.** Free — this is exactly what
   `WriteProperty` has always done; no new logic needed for it.
7. **Dynamic access gets separate AST nodes from `PropertyAccessExpr`** —
   `GetKeyStmt` and `SetKeyStmt` (D41's contract, frozen separately), kept
   apart from property access on purpose because rule 4 and rule 5 are
   different intents, not the same behavior wearing two syntaxes.
8. **Empty `has` objects become legal.** Parser-side, not yet built (see
   below) — without it, the central "start empty, build it with dynamic
   keys" pattern this feature exists for isn't reachable.
9. **Files, folders, and other domain/resource objects cannot be
   dynamically mutated.** Enforced by the same `TypeName -eq 'thing'`
   check as rule 3. This is the rule the investigation's probe exists to
   justify — it actually corrupted a file object's `size` property with an
   unguarded write before this guard was written.

### Left open inside D41, on purpose: key type

**String-only for 0.1.** `get`/`set` require the key's *runtime value* to
be text — `Assert-OtterStringKey` rejects a number, a date, a boolean, or
`gone` used as a key, rather than silently stringifying it. The **key
expression itself is unrestricted** — `get name of user from scores into
x` is legal syntax, because `Key` is a full expression in the contract, not
a string literal. Only what it evaluates to at runtime is constrained.
Explicitly deferred, not decided against: whether other primitives become
legal keys later, and what they'd coerce to, is left for whenever a real
program asks for it.

### Runtime: complete

`GetKeyStmt`/`SetKeyStmt` reuse `OtterObject.ReadProperty`/`WriteProperty`
exactly as they exist today — **zero changes to that class**, confirmed by
the investigation before any code was written. 13 new tests cover all nine
rules directly against hand-built AST (rule 8's empty-object grammar is
parser-side and is not testable here yet). 209 tests, 12 files, all green.

### Grammar: not yet built - the two precise pieces Codex needs

**New statement grammar**, reusing the frozen contract exactly:

```otter
get <key-expr> from <target-expr> into <name>
set <key-expr> to <value-expr> in <target-expr>
```

`Get` already exists and currently requires `Files`/`Folders` immediately
after it (`get files in ...` / `get folders in ...`); this needs a third
branch — anything else after `Get` falls through to reading a general
expression as the dynamic key. `Set` is a new, previously-unreserved
keyword.

**Rule 8's empty-object fix is narrow, and where it must NOT be narrow to
is exactly as important as where it must be.** Checked directly in the
parser before writing this: `has` and the untyped `is a thing` are the
*only two* call sites of `Read-OtterBlock` that should ever accept zero
properties. Every other call site — `if`, `while`, `repeat`, `count`,
`for each`, `try`, `to` (function bodies) — shares that same function and
must keep requiring real content; an empty `if` body is still a mistake
worth stopping on. **Do not touch `Read-OtterBlock` itself.** Add a new,
narrower helper used only by the two object-construction sites (currently
lines 747 and 775 of `src/Otter.Parser.psm1`) that behaves exactly like
`Read-OtterBlock` when an `Indent` follows, and returns an empty array
when the statement instead ends at `Newline` with no `Indent` — making
`person has` (with nothing under it) and `person is a thing` (same) both
legal, with zero effect on every other statement that still shares
`Read-OtterBlock`.

### The empty-object terminator bug — found, fixed, closed

Found during the dogfooding milestone: `Read-OtterObjectBlock` (above)
returned zero properties correctly when no `Indent` followed `has`, but
never consumed a `BlockEnd` that immediately followed, leaving an explicit
`.` a user would naturally write — matching D4/D18, every other block in
the language — orphaned with nothing to close.

**Status: CLOSED.**

| | |
|---|---|
| Found | `examples/json-settings/README.md`, during dogfooding |
| Fixed | `4d132e0` — `Read-OtterObjectBlock` now consumes an optional trailing `BlockEnd` on the empty-body path too |
| Verified | `5139e12` — `settings has` / `.` and `person is a thing` / `.` both run; the no-period form is unchanged; a dynamic `set`/`get` round trip on the resulting object works; empty `if`/`to`/`while` bodies followed by `.` are still correctly rejected, confirming the fix stayed inside `Read-OtterObjectBlock` and never touched the shared `Read-OtterBlock` |
| Suite | 218 tests, 12 files, green |

No new D-number — a bug fix inside already-approved D41 work, not a design
question.

---

## Confirmed, not new: lists are unchanged

`games are / "Zelda" / "Mario" / .` (D13) needed no revisiting and got
none — explicitly reaffirmed as already good rather than replaced with
something closer to a traditional array. No action, recorded for
completeness alongside D40/D41 since all three arrived in the same design
conversation.

---

## Deferred, matches existing scope decisions - no action

Sections 20-26 (Otter Web: buttons/text/`when` events, `otter new`/
`otter build` project tooling, `otter.json` manifests) restate the same
territory D16 already scoped out of the current milestone (*"0.3 is objects
and properties only... every UI, web and database feature in Part 2 is
built on top of them, so they come first"*). Nothing here changes that
scoping; recorded as aligned, not as new work.

---

## D42. `days between` becomes a first-class expression - frozen

```otter
waiting is days between date and deadline
elapsed is seconds between started and finished

say days between start and finish

if days between start and finish is greater than 30
    say "More than 30 days."
.
```

**A refinement of D32, prompted by the dogfooding milestone finding real
programs want this value usable everywhere an expression is, not only as
the whole right-hand side of a `make` statement.** D32 was not wrong; the
language grew a more consistent expression model since it was written, and
this brings `days between` into it — the same spirit as D34/D36/D40, which
each added a better spelling for something that already worked.

**`DateDifferenceExpr(Unit, Start, End)` is a new, separate node — it does
not repurpose `DateDifferenceStmt`.** The legacy statement form keeps
working exactly as it always has, unchanged:

```otter
days between date and deadline make waiting
```

is compatibility syntax now, not the preferred form, but it is not going
anywhere. Same coexistence pattern as everywhere else in this project.

**The invariant, stated explicitly because it is the whole point:**
`waiting is days between date and deadline` means the *exact same
calculation* as `days between date and deadline make waiting` — signed,
`end - start`, whole units truncated toward zero (D32.7), same validation,
same errors. Both forms share `Assert-OtterDateOperands` (factored out of
the statement case, not duplicated) and the existing
`Measure-OtterDateDifference` (untouched). A test runs both forms against
identical fixture dates in the same program and asserts identical output.

`Unit` reuses D32's existing `TimeUnit` enum — no new enum. No destination
field on the expression node; a value has nothing to assign into.

**Contract:** `5305e02`. **Runtime:** `10ef2a1`, 9 new tests (218 total, 12
files, all green). Lexer and parser untouched — Codex's lane, unblocked by
this pair of commits.

---

## D38A. Statement continuation for required trailing clauses - frozen

D38 split into two subproblems, per Jeff's call, rather than one mechanism
trying to cover both:

- **D38A** (this entry): continuing a statement that has no body of its
  own, at the exact point the parser is still waiting for a required
  clause. Frozen and ready to build.
- **D38B** (below): continuing a *condition* inside an `if`/`while` header,
  which sits at the same natural depth as the block's own body. Still
  under investigation, not frozen, no implementation yet.

```otter
get files in "Pictures" and subfolders
    into pictures
```

**Verified, not assumed, before freezing this:** the real token stream for
that exact input is

```
... Subfolders Newline Indent Into Identifier Newline Dedent
```

The `Newline, Indent` already sits exactly where `Into` is currently
required — zero lexer change needed. And `subfolders` can never legally be
the last token of this statement today; it is a hard, specific error
(*"I expected 'into' and a result name"*) in every case, so this is purely
additive — no currently-valid program can change meaning.

### Mechanism

One small, reusable parser helper — not a special case hardcoded to `get`:

```powershell
# Peeks for a soft line continuation: Newline immediately followed by
# Indent, at a point where the grammar is not yet finished. If present,
# consumes both and returns $true so the caller knows to consume the
# matching Dedent once the continued clause is fully read. If absent,
# consumes nothing - ordinary single-line parsing proceeds unchanged.
function Test-OtterSoftContinuation {
    if (-not (Test-OtterTokenKind ([TokenKind]::Newline))) { return $false }
    if ($script:Tokens[$script:Position + 1].Kind -ne [TokenKind]::Indent) { return $false }
    [void](Read-OtterToken)  # Newline
    [void](Read-OtterToken)  # Indent
    return $true
}
```

Used at the exact point `Into` is required:

```powershell
$continued = Test-OtterSoftContinuation
[void](Assert-OtterTokenKind ([TokenKind]::Into) '...')
$target = Read-OtterVariableName '...'
[void](Assert-OtterTokenKind ([TokenKind]::Newline) '...')
if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) '...') }
```

matching the verified token order exactly: `Into`, identifier, `Newline`
(closes the continuation line itself), then `Dedent` only if a
continuation was actually used.

**No AST change.** `GetFilesStmt`/`GetFoldersStmt` are built exactly as
they are today — this only changes how tokens are consumed to reach them,
not what gets built. Zero contract change.

### Scope for this pass — deliberately narrow

**Wired up only to `get files`/`get folders`, both with and without `and
subfolders`**, matching Jeff's example exactly. `Test-OtterSoftContinuation`
is written as a reusable helper on purpose, but this pass does not extend
it to every other multi-clause statement (`replace ... in ... into ...`,
`set ... to ... in ...`, `read json from ... into ...`, and others all have
the identical shape and are natural candidates) — those wait for a later
pass, once this one is dogfooded, per the same prove-narrow-then-extend
discipline as D33.

**Does not touch D7.** No indentation rule changes.

**Does not touch conditions.** `if`/`while` are D38B, not this entry.

Grammar-only. Codex's lane. No contract change, no runtime change.

---

## D38B. Condition continuation inside a block header - under investigation, NOT frozen

```otter
if extension of file is ".jpg"
    or extension of file is ".png"
    say "yes"
.
```

**Not decided. Not implemented. This entry records an investigation, the
same way the D41 unified-representation question was investigated before
being frozen** — evidence gathered, options laid out, decision left to
Jeff.

### Why this is a different, harder problem than D38A

`if`'s condition and `if`'s body are both real, both expected, and — when
the condition is written across two lines at the same natural depth as the
body — currently indistinguishable at the token level:

```otter
if true or
    false
    say "yes"
.
```

tokenizes as **one** `Indent`/`Dedent` pair wrapping *both* lines. Nothing
in the indentation says where the condition ends and the body begins.

**One resolution was tried and rejected: indenting the continuation deeper
than the body.** Verified directly — this is currently a hard error
*independent of D38 entirely*: *"Indentation cannot jump more than one
level at a time"* (D7). Making it work would mean carving an exception into
D7's jump-limit rule, not just adding continuation grammar. Rejected for
exactly the reason Jeff gave: it reads backwards (the condition sits
visually deeper than the body it belongs to) and it means touching D7
itself, which D38A was explicit about never needing to do.

**Also rejected: reusing `.` as a continuation marker.** `.` already has
one clean job — closing a block. Giving it a second, contextual meaning is
exactly the kind of overload this project has avoided everywhere else
(D4's whole point was collapsing period-meanings to exactly one).

### The direction worth investigating: a leading connective

```otter
if extension of file is ".jpg"
    or extension of file is ".png"
    say "yes"
.
```

Here the *first* line is already a complete, valid condition on its own —
`Read-OtterCondition` finishes reading it and returns normally, because
nothing currently makes it keep looking for more. The idea: when what
would otherwise be the first *body* statement instead begins with `or` or
`and`, treat that as continuing the condition instead of starting the
body — and only once a line's leading token is neither does real body
parsing begin.

**Verified, not assumed:** `or` (or `and`) as the leading token of an
ordinary statement is a hard, specific error today — *"I don't understand
'or'."* — in every case. No currently-valid body statement can begin with
either word. That is exactly the same additive-safety property D38A relies
on: nothing that currently works could change meaning.

**What actually needs answering before this is buildable — genuinely open,
not implementation detail:**

1. **This cannot reuse the generic `Read-OtterBlock` unchanged.** `if` and
   `while` would need their own condition-aware body reader: consume
   `Newline`+`Indent` once, then loop — while the current line's leading
   token is `Or`/`And`, consume it, read another condition operand, consume
   that line's `Newline`, and check again; once a line's leading token is
   neither, switch to ordinary `Read-OtterStatements` for the body, still
   inside the *same* `Indent` that was already consumed for the
   continuation. That is a real, contained rewrite of how these two
   statements read their blocks, not a one-line addition.
2. **Precedence across continuation lines.** D11 already defines `not` >
   `and` > `or` on one line. Does `if a` / `    and b` / `    or c` compose
   the same way it would on one line, or does each continuation line
   implicitly parenthesize against the ones before it? Needs a stated rule,
   not an inferred one.
3. **Does this generalize to `while`, or only `if`?** The mechanism is
   identical either way (both read a condition then a body), but each
   needs its own explicit yes/no rather than assuming both are included
   because one is.
4. **Interaction with `otherwise if`.** `otherwise if <condition>` reads a
   condition the same way `if` does — does a continued condition there
   follow the identical rule automatically, or does chaining `otherwise`
   onto a continuation introduce its own ambiguity worth checking
   separately?

### Status

Investigation only. Report findings before any implementation, per Jeff's
explicit instruction — this entry exists to carry that report, not to
close the question.

---

# UI (new design track)

D16 explicitly deferred all of this — *"0.3 is objects and properties
only... every UI, web and database feature in Part 2 is built on top of
them, so they come first."* Objects (D40) and dynamic access (D41) are now
solid, so per D16's own logic this is the natural next track to open, not
a departure from it.

---

## D43. External UI resource creation - the boundary, frozen. Everything else, deferred.

```otter
create button into helloButton

text of helloButton is "Say Hello"
```

**UI controls are external/domain resources, created with `create`, never
constructed with `has`.** This is not a new rule invented for UI — it is
D39's existing rule (*"`create` means bringing an external or domain
resource into existence through a provider or runtime action... never an
ordinary in-memory object"*) applied to a case it already covers. A WinUI
button needs a real provider and real native resources behind it, exactly
the distinction D39 already draws; a `has`-built `thing` is purely
in-memory. `has` remains reserved for ordinary data objects and does not
become a second UI syntax.

**The binding is `into`, not a quoted string doubling as an identifier.**
The original UI sketch used `create button "helloButton" with / ... / .`,
then referred to the bare identifier `helloButton` afterward — the two
spellings were meant to be the same thing, but nothing in that grammar
actually bound one to the other; it relied on the programmer keeping a
string literal and a variable name in sync by convention. Rejected for
being unlike the rest of the language: **a string literal never implicitly
creates or names an Otter variable anywhere else**, and `into` already
means exactly *"put the result here"* everywhere it's used
(`get files ... into files`, `read json ... into settings`, `random number
... into n`). Using it here is the same rule, not a new one.

**Identity and display content are kept separate, on purpose.** The first
sketch also passed a quoted label at creation (`create button "Say Hello"
into helloButton`), but `"Say Hello"` is presentation, not identity —
conflating the two in one statement was rejected. Setting a control's
visible text is ordinary property assignment, already fully built (D19):

```otter
text of helloButton is "Say Hello"
```

No new grammar needed for that part at all.

### Explicitly out of scope for D43

Frozen here is **only** the boundary and the binding mechanism. Deferred,
each to its own future decision:

- control properties and what each control type supports
- an initialization block (`create button into helloButton with\n    text is "..."\n.`) — plausible later, once property sets exist to populate, but not frozen now
- layout
- events / `when` (`when` still has zero grammar — D33 already pre-reserved it for exactly this, but the event model itself is undecided)
- the provider architecture (WinUI, and later web/cross-platform) that actually backs a created resource
- which specific control types exist beyond illustrative examples (`window`, `text`, `button` are examples in this entry, not a frozen list)

Because provider architecture is explicitly out of scope, this entry does
not commit to what a created UI resource concretely *is* at runtime yet —
that is downstream of deciding how a provider backs it, not upstream of
this boundary decision. Implementation (contract, grammar, runtime) is
deliberately not started as part of this entry; it follows once enough of
the deferred list is settled to build something real, the same sequencing
D16 already used for objects before UI was allowed to start.

---

## D44. UI provider architecture and resource lifecycle - frozen and implemented

```otter
create button into helloButton
```

### The provider question was settled with evidence, not preference

The obvious first instinct was WinUI 3 — it's the current, supported
Windows UI framework. **Checked directly before deciding anything:** on
this machine, `Add-Type -AssemblyName PresentationFramework` (WPF) loads
and instantiates a `Window` and a `Button` immediately, no install, no
packaging. Searching for the Windows App SDK runtime that WinUI 3 needs —
`WindowsAppRuntime` packages — found **zero matches**. WinUI 3 is not a
"just works from a script" technology the way WPF is; it needs its runtime
deployed, which for an end user means *they'd* need to install something
too. That directly contradicts this project's own stated identity —
*"there is nothing to install and nothing to download"* — on the very
machine this project has been built and tested on the whole time.

**Decision: WPF is the first provider.** Not because it looks better —
it doesn't — but because it lets the resource model be proven today, with
zero new constraints on how Otter ships. The abstraction layer this
project cares about doesn't depend on which toolkit is first:

```
Otter code
   ↓
UI resource abstraction   (OtterUiResource)
   ↓
provider                  ("wpf" - the only one implemented)
   ↓
WPF
```

WinUI, web, and cross-platform providers can be added later — for anyone
willing to accept their install requirements — without touching Otter's
language surface, because nothing at the language level knows WPF exists.

### The lifecycle question, answered with the same evidence

**`create <kind> into <name>` creates the real, live, provider-backed
object immediately — never a description materialized later.** Verified,
not assumed: created a `Button` standalone with no parent, then set it as
a `Window`'s `Content`, then confirmed via `[object]::ReferenceEquals`
that the exact same instance was still there. WPF's own object model
already works exactly the way this project wanted the lifecycle to work —
create now, attach later (D47), never recreate.

### The wrapper, and why the boundary is structural, not a rule to remember

```
helloButton
    ↓
OtterUiResource
    Kind:     "button"
    Provider: "wpf"
    Native:   the real System.Windows.Controls.Button
```

Never a raw WPF object sitting in an Otter variable. That is what makes
*"provider: web, native: HTMLElement"* a future possibility without
changing what `helloButton` means at the language level — a promise this
entry can make with confidence because of *where* the WPF-specific code
lives: **`src/Otter.UI.psm1` is the only file in this entire project
permitted to mention `System.Windows.*`.** No other module needs to, and
none do — checked, this isn't an unenforced convention. `Get-OtterTypeName`
and error messages say `"a button"`, never `Button` or the assembly it
came from; a test asserts the output never contains the string
`"System.Windows"`.

**One deliberate exception to how the project usually checks types, and
why:** `Format-OtterValue` and `Test-OtterTruthy` live in
`Otter.Runtime.psm1` — the foundation every other module, including
`Otter.UI.psm1`, builds on top of. Having Runtime `using module` UI back
would invert that layering. Both functions check
`$Value.GetType().Name -eq 'OtterUiResource'` instead of the usual
`-is [OtterUiResource]` — a plain runtime name comparison needs no import
at all, so the dependency direction stays honest. `Get-OtterTypeName`
lives in the interpreter, which already imports both `Otter.Runtime.psm1`
and `Otter.UI.psm1`, so it uses the normal `-is` check.

### Scope: the small proving set, matching D44's own job

Four control kinds, one line each in a lookup table, each mapping
directly to a real WPF type: `window`, `button`, `text` (a display label —
WPF `TextBlock`), `text box` (WPF `TextBox`). An unsupported kind is a
clear Otter error naming what's actually known, not a raw exception.

**Control-kind words are read as raw text, not reserved keywords** — the
same pattern `Read-OtterObjectTypeName` already uses for `is a <type>`.
D44 does not take a single word away from ordinary Otter programs; `text`,
`button`, `window` all stay legal as ordinary identifiers everywhere else.

**Property access is explicitly, honestly unbuilt — not silently
unbuilt.** `text of helloButton` (read or write) raises *"...is not built
yet"*, a distinct message from the ordinary *"I can only read properties
of a thing"* a non-object gets — the first says *this is coming*, the
second would have incorrectly implied *this can never work*.

**Dynamic `get`/`set` (D41) exclude UI resources automatically, with zero
new code.** `Assert-OtterDynamicKeyTarget` checks `Test-OtterObject`
specifically, and `OtterUiResource` was never made to inherit from
`OtterObject` — so D41 rule 9 (*"files, folders, and other domain/resource
objects cannot be dynamically mutated"*) already covers UI resources for
free, the same way it already covered files and folders. Confirmed with a
test, not assumed from the class hierarchy alone.

### Out of scope, staying exactly where Jeff put it

- **D45** — property translation. Which Otter property name maps to which
  native property, per control kind (a button's `text` is WPF `.Content`;
  a window's is `.Title`; a text box's is `.Text` — genuinely different
  per kind, which is exactly why this is its own decision, not folded into
  D44's resource model).
- **D46** — events / `when`. Still zero grammar (D33 pre-reserved the word
  for exactly this).
- **D47** — layout / attachment (`add helloButton to mainWindow` or
  whatever gets frozen). The WPF evidence above already shows the object
  model supports this without recreating anything; the syntax itself is
  undecided.

### What's built, what's still Codex's

**Contract:** `15dda45`. **Runtime:** committed alongside this entry — new
`src/Otter.UI.psm1`, `OtterUiResource`, the WPF provider, wiring into
`Get-OtterValue`/`Set-OtterTarget`/`Format-OtterValue`/`Test-OtterTruthy`/
`Get-OtterTypeName`. 12 new tests, 13 files, 230 total, all green.

**Grammar not yet built.** `create` today only recognizes
`create folder "path"` — a single hardcoded check for the literal word
`Folder` right after `Create`. `create <kind> into <name>` needs a new
branch: if the token after `Create` is `Folder`, existing behavior,
unchanged; otherwise, read raw words (same pattern as
`Read-OtterObjectTypeName`) until `Into`, then a target identifier. No
lexer change — `into` and `create` are both already tokens. Codex's lane,
once handed off.

---

## D45. UI property access and assignment - frozen and implemented

```otter
create window into app
title of app is "My App"
width of app is 500

create button into helloButton
text of helloButton is "Say Hello"
say text of helloButton
```

### No grammar change - D19 already covers this exactly

`text of helloButton` and `text of helloButton is "Say Hello"` are
ordinary `property of target` / `property of target is value` expressions
— the same `PropertyAccessExpr` / `AssignStmt` shapes D19 already parses
for `has`-built things. Verified by reading the parser: nothing there
special-cases the target's *kind*, only its syntactic position. So D45
needed **zero** contract and **zero** parser changes. The only new work is
in `Get-OtterValue`'s and `Set-OtterTarget`'s `PropertyAccess` cases in
`Otter.Interpreter.psm1`, which previously threw an explicit "not built
yet" error for `OtterUiResource` targets (from D44) and now route to
`Otter.UI.psm1` instead:

```powershell
if (Test-OtterUiResource $target) {
    Write-Output -NoEnumerate (
        Get-OtterUiProperty -Resource $target -Property $Expression.Property -Line $Expression.Line)
    return
}
```

Nothing about `has`-built `thing` property access changed; the
`OtterObject` branch is untouched, and D41's dynamic `get`/`set` continue
to exclude UI resources automatically (checked against `Test-OtterObject`,
which `OtterUiResource` was never made to satisfy).

### Property metadata belongs in the provider abstraction, not the interpreter

"What does `text` mean for a button" is provider-specific knowledge — a
button's `text` is WPF `.Content`; a text box's or `text`'s is `.Text`; a
window has no `text` at all, only `title`/`width`/`height`. The same
reasoning that put D44's create-kind lookup table in `Otter.UI.psm1` puts
this one there too, as a second table next to it:

```powershell
$script:OtterUiProperties = @{
    'button'   = @{ 'text' = @{ Native = 'Content'; Type = 'text' } }
    'text box' = @{ 'text' = @{ Native = 'Text';    Type = 'text' } }
    'text'     = @{ 'text' = @{ Native = 'Text';    Type = 'text' } }
    'window'   = @{
        'title'  = @{ Native = 'Title';  Type = 'text' }
        'width'  = @{ Native = 'Width';  Type = 'number' }
        'height' = @{ Native = 'Height'; Type = 'number' }
    }
}
```

Verified directly against the real WPF types, not assumed from naming
convention: `TextBox` has no `Content` property at all; `Button` has no
settable `Text` property the way a `TextBox`/`TextBlock` does. Getting
the mapping backwards would have been a silent wrong write, not an error
— exactly the kind of mistake a table checked against the real object
forecloses. Every property in this table is both readable and writable on
its real WPF type, verified rather than assumed, so this pass has no
read/write asymmetry to design around; the table shape (one entry, not
two) already leaves room for a future read-only property without
changing how `Get-`/`Set-OtterUiProperty` are called.

### Type validation happens before the native object is ever touched

Each property carries a `Type`, which is a **validation/coercion
strategy**, not a WPF concept:

- **`'text'`** — any Otter value is accepted and passed through
  `Format-OtterValue`, the exact conversion `say` already applies. `text
  of helloButton is 5` sets it to `"5"`; it does not error, consistent
  with how `say 5` already prints `5` rather than complaining about type.
- **`'number'`** — the Otter value must already be numeric. Checked with
  `Test-OtterNumeric`/`ConvertTo-OtterNumber` and converted **before**
  the native WPF object is touched at all.

That ordering matters because of a real, verified leak: assigning
`"not a number"` directly to `Window.Width` throws WPF's own
`SetValueInvocationException`, whose message names `"System.Double"`
directly — exactly what D44 principle 5 ("Otter semantics must not
expose WPF-specific class names or APIs") forbids. Validating first means
that exception can never actually fire through the Otter-facing path; a
type mismatch always surfaces as `"I expected a number for the width of
this window but got \"not a number\"."` instead. Tested directly,
including asserting the raw exception text (`System.`, `SetValueInvocation`)
never appears in what reaches the user.

`Assert-OtterUiNumber` is deliberately self-contained rather than reusing
the interpreter's own `Assert-OtterNumber`: `Otter.Interpreter.psm1`
already imports `Otter.UI.psm1`, so importing the other direction would
invert D44's module layering. `Test-OtterNumeric`/`ConvertTo-OtterNumber`
(from `Otter.Runtime.psm1`, the foundation layer both modules already
depend on) are reused instead — the correct-direction dependency.

### Unsupported properties, two distinct messages

- A kind Otter has never heard of (should not currently be reachable,
  since every D44 kind has an entry): *"A `<kind>` has no properties
  Otter knows about yet."*
- A known kind with an unrecognized property name: *"A `<kind>` has no
  property called `"<property>"`."*, with a suggestion listing the
  kind's actual properties — always naming the Otter-facing kind
  (`"a window"`, `"a text box"`) exactly as D44 already required for
  creation errors, never `TextBox` or `System.Windows.Controls`. Setting
  an unsupported property fails via this same lookup *before* touching
  the native object, verified by asserting the native value is unchanged
  after the failed write.

### Reading an unset text property is `gone`, not `""`

A freshly created button has never had `.Content` set — WPF itself
reports that as `$null`. D22 already distinguishes *no value exists*
from *an empty value exists*, so `Get-OtterUiProperty` maps a `$null`
text-typed read straight to `gone` rather than inventing a UI-specific
"empty" concept. Numeric properties (`width`, `height`) don't need this:
WPF gives every `Window` a real default `Width`/`Height` the moment it's
constructed, so there's no unset-number case to handle here.

### What's still out of scope

Unchanged from D44's own list: **D46** (events/`when`), **D47**
(layout/attachment), more control kinds beyond the D44 proving set, and
any property *initialization block* syntax on `create` itself (`create
button into x with text "Say Hello"` or similar — not proposed, not
needed yet; D45 only covers property access on an already-created
resource).

### What's built

**Contract:** none needed — see above. **Runtime:** `src/Otter.UI.psm1`
gained the property table and `Get-OtterUiPropertyMapping` /
`Assert-OtterUiNumber` / `Get-OtterUiProperty` / `Set-OtterUiProperty`;
`src/Otter.Interpreter.psm1`'s `PropertyAccess` cases in `Get-OtterValue`
and `Set-OtterTarget` now route `OtterUiResource` targets there instead
of throwing "not built yet". 11 new tests added to `tests/UI.Tests.ps1`
(3 replacing now-obsolete D44-era stub-error tests, 8 new), full suite:
13 files, all green.

**No Codex handoff needed.** D45 required no grammar work — D19's
existing `property of target` parsing already produces the right AST for
a UI-resource target exactly as it does for a `thing` target; nothing
about parsing changes based on what the target turns out to be at
runtime.

### Maintenance fix (found during D48 investigation): negative sizes leaked a raw .NET exception

`Assert-OtterUiNumber` originally only checked *is this numeric* — never
*is this negative*. Verified directly: `Window.Width = -10` throws WPF's
own `System.ArgumentException: '-10' is not a valid value for property
'Width'.`, which reached the user completely untranslated, since nothing
here ever tried a negative value before. Fixed by rejecting negative
numbers before the native object is ever touched, same discipline as the
not-a-number case right next to it: *"The `<property>` of a `<kind>`
can't be negative, but I got `<number>`."* Zero remains valid (WPF itself
raises nothing for `Width = 0`, confirmed). This single fix, in one
shared function, automatically covers every numeric UI property that
exists now or is added later (width, height, and D48's `spacing`) — none
of them call WPF directly.

---

## D46. UI event registration - frozen and implemented (registration only)

```otter
when helloButton is clicked
    say "Hello"
.
```

### Scope: registration, not execution

Unlike D45, `when` had **zero** existing AST support before this entry —
`When` was only a reserved lexer token (`Otter.Contract.psm1`, "reserved,
UI milestone"), with no `NodeKind` entry and no parser handling at all
(confirmed by reading `src/Otter.Parser.psm1` directly). So D46 needed a
real contract addition and a real parser addition, the opposite of D45.

More importantly: no Otter program today runs a message loop. WPF's real
input events (an actual click) require an active `Dispatcher` pumping
messages; a script that creates a window and finishes just exits without
ever giving WPF a chance to deliver anything. So D46 is explicitly scoped
to **registration only** — wiring a handler to a native event correctly —
and leaves *whether/when that handler is ever actually invoked in a
running program* to D47 (a message loop / `show`). This was Jeff's
explicit call after the trade-off was raised, not an assumption.

### No grammar reuse this time - a real contract addition

```powershell
class WhenStmt : Node {
    [Node]$Target        # the UI resource identifier
    [string]$EventName   # "clicked", "changed", "closed" - a raw word
    [Node[]]$Body
    WhenStmt([Node]$target, [string]$eventName, [Node[]]$body, [int]$line)
        : base([NodeKind]::When, $line) { ... }
}
```

`EventName` is read as a raw word, exactly like D44's `TypeName` and
D45's property names — `clicked`/`changed`/`closed` are **not** reserved
keywords, preserving Otter's contextual-keyword philosophy. The block
body reuses the parser's existing `Read-OtterBlock` helper, the same one
`if`/`while`/`repeat` already share, so the parser addition is small.

### Event metadata belongs in the provider, same shape as D45's properties

```powershell
$script:OtterUiEvents = @{
    'button'   = @{ 'clicked' = 'Click' }
    'text box' = @{ 'changed' = 'TextChanged' }
    'window'   = @{ 'closed'  = 'Closed' }
}
```

"What does `clicked` mean for a button" is provider-specific knowledge,
same reasoning as D44's create-kind table and D45's property table —
Otter only ever sees the left-hand word; the CLR event name never
surfaces.

Subscription is **one generic function** for every kind/event, not one
code path per event, verified directly against real WPF: `Button.Click`
is `RoutedEventHandler`, `TextBox.TextChanged` is
`TextChangedEventHandler`, `Window.Closed` is a plain `EventHandler` —
three different delegate types — yet reflection subscribes correctly to
all three with the same code:

```powershell
$eventInfo = $Resource.Native.GetType().GetEvent($clrName)
$typedHandler = $Handler -as $eventInfo.EventHandlerType
$eventInfo.AddEventHandler($Resource.Native, $typedHandler)
```

Tested by actually firing each native event for real (not simulated):
`Button.RaiseEvent` with a `ClickEvent` routed-event args, setting
`TextBox.Text` directly (fires real `TextChanged`), and calling
`Window.Close()` (fires real `Closed`) — each confirmed to run the
registered Otter handler body and produce the expected `say` output.

### Frozen scoping rule: no implicit new scope

A `when` handler's body closes over the environment active where `when`
is registered and introduces **no** implicit child scope — the same
model `if`/`while`/`repeat` bodies already use (`Invoke-OtterStatements`
called with the *same* `$Environment`, verified by reading
`Otter.Interpreter.psm1:320-341`), not a function call's fresh scope.
Assigning a variable inside a handler body is visible in that same
environment afterward — tested directly by firing a click and reading
back the assigned variable through the environment the program used.

### No event payload

`Body` has no way to name "the event" or read anything about it in D46.
`when nameBox is changed as event` is explicitly not built. All three
proving-set handlers run with zero arguments.

### Unsupported events, same two-message pattern as D45

- A kind with no event table entry at all: *"A `<kind>` has no events
  Otter knows about yet."*
- A known kind with an unrecognized event name: *"A `<kind>` has no
  event called `"<event>"`."*, with a suggestion listing the kind's
  actual events — always the Otter-facing kind name, never a WPF type.

### Listening on a non-UI-resource target

`Get-OtterTypeName` already names every runtime value distinctly (`"some
text"`, `"a button"`, `"gone"`, ...) — reused directly for the target
check: *"I can only listen for an event on a UI resource, but this is
some text."* No new naming logic needed.

### What's still out of scope

- **D47** — a message loop / `show`, without which no handler registered
  under D46 can ever fire from real user interaction.
- Multiple handlers on the same event, removing/replacing a handler,
  and any event carrying data (all deferred, per Jeff's explicit call —
  can come later if dogfooding proves they're needed).
- More event kinds beyond the three-event proving set (`clicked`,
  `changed`, `closed`) — same one-line-per-event extension pattern as
  D44/D45's tables.

### What's built

**Contract:** `NodeKind::When`, `WhenStmt`. **Runtime:**
`src/Otter.UI.psm1` gained `$script:OtterUiEvents`,
`Get-OtterUiEventMapping`, `Add-OtterUiEventHandler`;
`src/Otter.Interpreter.psm1` gained the `'When'` statement case. 7 new
tests in `tests/UI.Tests.ps1` (three real native-event-fire tests, one
scoping test, one unsupported-event test, one non-resource-target test),
full suite: 13 files, all green.

**Parser handoff to Codex, grammar only.** `When Target(Identifier) Is
EventWord` then the standard `Read-OtterBlock`-parsed body. No lexer
change — `when` and `is` are both already tokens, and event-name words
are read raw, the same way `Read-OtterObjectTypeName` already reads
control-kind words for D44.

---

## D47. UI layout and show - frozen and implemented

```otter
create window into app
title of app is "Hello Otter"

create button into helloButton
text of helloButton is "Say Hello"

when helloButton is clicked
    say "Hello!"
.

put helloButton in app
show app
```

This is the milestone: a real window appears, stays alive, accepts a real
click, runs the D46 handler, and closes cleanly. Verified end-to-end, not
assumed — `tests/UI.Tests.ps1` has a test that runs exactly this shape
through `Invoke-OtterStatement`, fires a synthetic click via
`RaiseEvent` partway through a blocking `ShowDialog`, and confirms the
handler's `say` output arrives before the call returns.

### `show` is `Window.ShowDialog()` - modal, verified to actually work from a script

Windows PowerShell 5.1 runs **STA by default**, both interactively and
via `-File`/`-Command` (checked directly with
`[Thread]::CurrentThread.GetApartmentState()`) — no `-sta` launch flag
needed anywhere in `otter.ps1` or the test runner. `ShowDialog()` blocks
the calling thread, pumps real WPF messages while blocked, and returns
once the window closes — confirmed by literally clicking a button
(`RaiseEvent`) from a `DispatcherTimer.Tick` while `ShowDialog` was
blocked, and watching the D46 handler run and `Close()` unblock it.
No `System.Windows.Application` object is needed for this.

Modal only, on purpose: a second `show` of a different window would
block behind the first. Independent, simultaneously-visible top-level
windows are explicitly out of scope for this milestone.

### `put` needs an Otter-invisible implicit container - a window can only hold one direct child

`Window.Content` accepts exactly one `UIElement` (verified). `put`
therefore lazily creates a `StackPanel` (default vertical stacking) the
first time anything is put into a window, and adds subsequent items to
that same panel — `Children.Add` always appends, so **order is
preserved** automatically (verified with two buttons, checking
`panel.Children[0]`/`[1]` by reference). Nothing outside
`Add-OtterUiChild` in `Otter.UI.psm1` ever creates, names, or reads this
panel; Otter code has no way to see or refer to it, matching D44
principle 5 exactly the way the property and event tables already do.

`put` **attaches the existing resource — it never recreates or copies
it.** Verified with `[object]::ReferenceEquals` between the button's
`.Native` and what actually lands in `panel.Children[0]`, the same
identity check D44 already used for resource lifecycle.

### A resource can have only one parent - verified as a real WPF constraint, translated cleanly

Adding the same `UIElement` to a second container throws WPF's own
`InvalidOperationException` ("Specified element is already the logical
child of another element..."), wrapped by PowerShell as a
`MethodInvocationException` — verified directly, including that the
*same* exception type covers both "into a different window" and "into
the same window twice," so no further type-based disambiguation is
needed. `Add-OtterUiChild` catches it and raises a clean Otter error
instead: *"A `<kind>` can only be in one place at a time, and this one
is already somewhere else."* — never `InvalidOperationException`, never
"logical child."

### Two more failure modes, verified and translated the same way

- **Showing an already-closed window** — real WPF throws
  `InvalidOperationException` ("Cannot set Visibility or call Show,
  ShowDialog... after a Window has closed"); translated to *"This window
  has already been closed, so it can't be shown again."* Verified by
  actually closing a window, then calling `ShowDialog` on it again.
- **Showing or putting-into something that isn't a window** — checked
  before touching WPF at all (a `Button` has no `ShowDialog` method;
  calling it would be a raw MissingMethod-style failure, not a language
  error), and worded with the resource's real kind: *"I can only show a
  window right now, not a `<kind>`."* / *"I can only put things in a
  window right now, not a `<kind>`."*

An **empty window (nothing ever put into it) shows and closes without
error** — verified directly; WPF raises nothing for this case, so no
special-casing was needed in `Show-OtterUiResource` at all.

### Both statements validate "is this even a UI resource" generically first

Same pattern as D46's `When` case: `Get-OtterValue` on the target/item/
container, then `Test-OtterUiResource`, then `Get-OtterTypeName` for the
error if not — reused directly rather than inventing new naming logic.
Kind-specific checks ("must be a window," "already parented") live one
layer deeper, in `Otter.UI.psm1`, exactly where D44/D45/D46 already put
provider-specific knowledge.

### What's still explicitly out of scope

Per Jeff's freeze: grids, horizontal layout, explicit coordinates,
multiple simultaneously-shown top-level windows, non-modal windows,
reparenting or removing an already-put item, and re-showing a closed
window. All are natural, larger follow-on decisions once dogfooding a
real app surfaces which of them actually matter first.

### What's built

**Contract:** `NodeKind::PutIn`, `NodeKind::Show`, `PutInStmt(Item,
Container)`, `ShowStmt(Target)`. **Runtime:** `src/Otter.UI.psm1` gained
`Add-OtterUiChild` and `Show-OtterUiResource`; `src/Otter.Interpreter.psm1`
gained the `'PutIn'` and `'Show'` statement cases. 12 new tests in
`tests/UI.Tests.ps1`, including the full click-through-a-real-window
end-to-end test, identity/order verification, both parent-conflict
shapes, both wrong-kind shapes, both not-a-resource shapes, the
empty-window case, and the closed-window-can't-reshow case. Full suite:
13 files, all green.

**Parser handoff to Codex needed**, same as D46: `Put Item(Expression)
In Container(Expression)` and `Show Target(Expression)` are new
statement shapes, not grammar D19 or any prior decision already covers.

---

## D48. UI styling - size, color, and window spacing - frozen and implemented

```otter
width of app is 500
height of app is 350
background of app is "#111827"
spacing of app is 12

width of addButton is 140
height of addButton is 42
background of addButton is "#2563EB"
foreground of addButton is "white"
```

Driven entirely by real dogfooding (D47's `hello-app.ot`, `greeter.ot`,
`calculator.ot`) rather than designed in advance — the same three gaps
kept showing up across all three programs: no way to size a control, no
way to color anything, no way to space controls apart. This entry closes
all three at once, and closes a related bug D45 had been carrying
unnoticed (see the maintenance-fix note at the end of the D45 entry
above).

### The headline result: zero grammar, zero AST, zero Codex work

Every part of D48 routes through D45's existing `property of target is
value` mechanism. Confirmed before writing anything: property names are
already read as raw words with no reserved-word collisions, so `width`,
`height`, `background`, `foreground`, and `spacing` needed nothing from
the parser. All of the work is inside `Otter.UI.psm1` — this is the
first UI decision since D44 that needed **no** contract addition and
**no** Codex handoff at all.

### Width/height apply uniformly to all four kinds - verified, not assumed

Checked via reflection before extending the property table: `Window`,
`Button`, `TextBox`, and even `TextBlock` (which isn't a `Control` at
all) each define their own real `Width`/`Height` (`System.Double`).
No kind needed special-casing; the same `{ Native = 'Width'; Type =
'number' }` entry was simply added for `button`, `text box`, and `text`
alongside window's pre-existing one. Validation is the same
`Assert-OtterUiNumber` D45 already had — now also rejecting negative
values, per the maintenance fix above.

### Colors: one conversion path for both named and hex, verified identical

`[System.Windows.Media.BrushConverter]::new().ConvertFromString(...)`
handles `"blue"` and `"#3366FF"` through the exact same call — confirmed
directly, so there is no named-vs-hex branching anywhere in
`Assert-OtterUiColor`. An invalid string throws a real
`System.FormatException`, caught and translated to *"I don't understand
the color `"<text>"`."* — never the raw exception type or message.

`Background`/`Foreground` are both typed `System.Windows.Media.Brush` on
all four kinds, including `TextBlock` — verified via reflection, so
"does this make sense per kind" checked out uniformly with no
special-casing needed there either.

**Colors always round-trip as a hex string, never the raw WPF `Brush`
object.** Every color this provider ever sets is a `SolidColorBrush`
(verified — `BrushConverter` never returns anything else here), so
`Get-OtterUiProperty` converts it back via `.Color.ToString()` — an
8-digit `#AARRGGBB` form. This means `background of x is "blue"` then
reading it back gives `"#FF0000FF"`, not `"blue"` — a real, worth-noting
asymmetry, but an honest and still-fully-Otter-safe one, the same kind
of round-trip-not-verbatim behavior D8 already accepts for number
formatting. A brush Otter never set (a theme-provided one, not a
`SolidColorBrush`) reads as `gone` rather than guessing at a text form
for it — verified every kind's *unset* `Background` is actually `null`
(so already `gone` via the ordinary unset path) and every kind's default
*unset* `Foreground` is already a real `SolidColorBrush` (so it reads
back as a real color immediately, with no explicit `foreground is ...`
ever needed) — both confirmed by reflection before relying on either.

### Spacing: no `StackPanel.Spacing` exists in WPF - `Margin` is the only real mechanism, and it's genuinely stateful

Verified there is no such property; a per-child `Margin` is what actually
produces visual spacing in a `StackPanel`. Every child gets the same
bottom `Margin`, including the last one — simpler and more robust than
tracking which child is currently last just to skip its margin.

**Confirmed directly that order matters operationally:** a child added
*after* `spacing` is set does **not** inherit it for free — its `Margin`
stays `0,0,0,0` until something explicitly applies the value. So this
needed two cooperating pieces, both entirely inside `Otter.UI.psm1`:
`Set-OtterUiSpacing` stores the value on the invisible panel's own `Tag`
property (verified `Tag` round-trips a boxed `double` cleanly) *and*
re-margins every child already there; `Add-OtterUiChild` reads that same
`Tag` value for every future child. Both directions were tested
explicitly — spacing set before any `put`, spacing set after some `put`s
(re-margining the existing ones), and a `put` happening after spacing
was changed *again* (inheriting the latest value, not a stale one) — all
produce the identical end state. **No `OtterUiResource` contract change
was needed** for this state to exist — `Tag` is a plain property every
`FrameworkElement` already has, entirely internal to this one file.

`spacing` only exists in the `window` entry of the property table (no
`Native` key — it never reads or writes a single native property
directly, unlike every other D45/D48 property), so it is a genuine
runtime error on any other kind, via the same lookup every unsupported
property already uses. Unset spacing reads as `gone`, matching every
other never-set property's precedent — even before any `put` has ever
happened, which would otherwise force the invisible panel to exist just
to answer a read; `Get-OtterUiSpacing` checks the window's `Content` for
`null` first specifically to avoid that side effect.

### Visually verified, not just round-tripped through the property system

Rendered a real window (`title`, `width`, `height`, `background` all
set) with a styled button (`width`, `height`, `background`, `foreground`)
and a text box, via `RenderTargetBitmap`, and inspected the resulting
image directly. The window's dark background, the text box's white
background, and — notably — the button's blue background *and* white
text all rendered exactly as set, with no default Windows theme
resistance to a custom `Background`/`Foreground` on `Button`/`TextBox`
(a real risk flagged before implementing, since WPF control templates
can sometimes override a plain `Background` write visually even though
the property itself always accepts the write) — that risk did not
materialize. Spacing between the two controls was clearly visible in the
render too.

### What's still explicitly out of scope

**`app has padding is 24 / spacing is 12`** — a grouped-property block
syntax — was raised during discussion but deliberately not folded into
D48. `has` already carries established object-construction semantics
(D16 and onward); whether it can also mean "configure this external
resource" is a separate language-design question from "does this
property work through `property of target is value`," which is all D48
commits to. Worth its own investigation later, not assumed here.

Also still deferred: horizontal layout, grids, explicit coordinates, any
property beyond this five-property proving set (`width`, `height`,
`background`, `foreground`, `spacing`) — more can be added the same
one-line-per-property way once real programs need them, per the same
dogfooding discipline that produced this entry in the first place.

### What's built

**Contract:** none — see above. **Runtime:** `src/Otter.UI.psm1`:
extended `$script:OtterUiProperties` with `width`/`height` for `button`/
`text box`/`text`, `background`/`foreground` for all four kinds, and
`spacing` for `window`; added `Assert-OtterUiColor`, `Get-OtterUiSpacing`,
`Set-OtterUiSpacing`, and `Get-OtterUiContainerPanel` (factored out of
`Add-OtterUiChild`, now shared with the spacing functions); extended
`Get-OtterUiProperty`/`Set-OtterUiProperty` with `'color'`/`'spacing'`
branches; tightened `Assert-OtterUiNumber` (the D45 fix above).
`src/Otter.Interpreter.psm1` — **unchanged**, since everything routes
through the existing `Get-`/`Set-OtterUiProperty` calls it already had
from D45. 15 new tests in `tests/UI.Tests.ps1` (2 for the D45 negative-
size fix, 13 for D48 proper: width/height on every kind, colors on every
kind via both named and hex, the invalid-color diagnostic, unset-color-
is-gone, all three spacing-ordering scenarios, unset-spacing-is-gone,
spacing round-trip, negative-spacing rejection, and spacing being
window-only). Full suite: 13 files, all green. Visual render check
saved and inspected directly (not committed — a one-off verification
artifact, not a repo asset).

**No Codex handoff.** Nothing here touches the lexer, parser, or
contract.

---

## D49. HTTP requests and web data

```otter
get "https://api.example.com/status" into statusText
get json from "https://api.example.com/users" into users
post user to "https://api.example.com/users" into createdUser
put user to "https://api.example.com/users/5" into updatedUser
delete from "https://api.example.com/users/5" into result
```

### Scope and Motivation

`rules2.md` Section 12, `rules3.md` Section 35, and `rules4.md` Section 23 describe
direct, readable HTTP requests without manual socket handling, Promise boilerplate,
or async/await syntax.

D49 defines the language contract and front-end grammar for client HTTP operations:
- `get <url> into <target>`
- `get json from <url> into <target>`
- `post <data> to <url> [into <target>]`
- `put <data> to <url> [into <target>]`
- `delete from <url> [into <target>]`

### Disambiguation and Grammar Design

1. **`get`**:
   - `get files` / `get folders` -> Filesystem discovery (D20/D21).
   - `get json from <url> into <target>` -> JSON HTTP GET.
   - `get <expr> from <thing> into <target>` -> Dynamic key access (D41).
   - `get <url> into <target>` -> Plain HTTP GET.
2. **`post`**:
   - `post` is a new statement-starting keyword (`TokenKind::Post`).
   - Followed by data expression, `to`, URL expression, and optional `into <target>`.
3. **`put`**:
   - `put <resource> in <container>` (preposition is `in`) -> UI layout (D47).
   - `put <data> to <url> [into <target>]` (preposition is `to`) -> HTTP PUT.
4. **`delete`**:
   - `delete folder <path>` -> Folder deletion (D21).
   - `delete <path>` / `delete file <path>` -> File deletion (milestone 7).
   - `delete from <url> [into <target>]` (preposition is `from`) -> HTTP DELETE.

### Contract additions

`TokenKind`:
- `Post`

`NodeKind`:
- `HttpGet`
- `HttpPost`
- `HttpPut`
- `HttpDelete`

AST Node classes:
- `HttpGetStmt([Node]$url, [string]$target, [bool]$asJson, [int]$line)`
- `HttpPostStmt([Node]$data, [Node]$url, [string]$target, [bool]$asJson, [int]$line)`
- `HttpPutStmt([Node]$data, [Node]$url, [string]$target, [bool]$asJson, [int]$line)`
- `HttpDeleteStmt([Node]$url, [string]$target, [int]$line)`

---

## D50. Otter Web App Compiler (`ConvertTo-OtterWeb` / `otter build web`)

```otter
app is a page
    title is "My Otter Web App"
    width is 500
    background is "#0f172a"
.

nameBox is a text box
    placeholder is "Enter your name"
.

helloButton is a button
    text is "Say Hello"
    background is "#2563eb"
    foreground is "white"
.

message is a text
    value is ""
    foreground is "#94a3b8"
.

when helloButton is clicked
    name is text of nameBox
    if name is empty
        text of message is "Please enter a name."
    otherwise
        text of message is "Hello " name "!"
    .
.

put nameBox, helloButton, message in app
show app
```

### Scope and Motivation

`rules2.md` Section 5 and `rules4.md` Sections 20-22 and 24 specify that the exact same Otter
UI intent can run across targets (`otter run` on desktop, `otter build web` on the browser).
Otter Web expresses what exists, how it looks, and what it does without forcing the programmer
to manage DOM selectors, event-listener plumbing, or JavaScript frameworks.

D50 defines the web compilation target:
- Compiles an Otter `ProgramNode` into a self-contained, dependency-free HTML5/CSS3/JavaScript web application.
- Supports both `page` and `window` as the root web viewport.
- Maps UI resources directly to semantic HTML elements:
  - `page` / `window` -> container card with styling (`title`, `width`, `height`, `background`, `spacing`).
  - `button` -> `<button>` with click handling and styles.
  - `text box` -> `<input type="text">` supporting `text` / `value` / `placeholder`.
  - `text` -> `<div class="otter-text">` / `<p>` supporting `text` / `value` / `foreground`.
  - `row` -> `<div class="otter-row">` with flex-direction row.
  - `column` -> `<div class="otter-column">` with flex-direction column.
- Compiles reactive event handlers (`when <target> is clicked`) to browser event listeners with full Otter state.
- Compiles Otter expressions, math, variables, strings, and conditions to clean, modern JavaScript.

---

## D51. Web Servers and API Routes

```otter
api is a web server
    port is 5000
    host is "localhost"
.

when api receives GET at "/users"
    respond with users as json
.

when api receives POST at "/users" into req
    respond with user as json and status 201
.

when server receives a request at "/hello"
    respond with "Hello from Otter!"
.

when api receives GET at "/health"
    respond with status 200
.

start api
```

### Scope and Motivation

`rules2.md` Sections 10 and 13 define the syntax for readable HTTP services in Otter.
A web server is declared as an object (`api is a web server`), routes are declared as
reactive handlers (`when <server> receives <method> at <path> [into <req>]`), and responses
are cleanly emitted with `respond with <expr> [as json] [and status <code>]`.
Lifecycle is controlled via `start <server>` or `listen on port <port>`.

### Disambiguation and Grammar Design

1. **`receives`**:
   - Follows the server target in a `when` statement: `when <server> receives ...`.
   - Distinguishes UI event blocks (`when <button> is clicked`) from server route blocks.
   - Accepts either an explicit HTTP verb (`GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `OPTIONS`, `HEAD`),
     an open request pattern (`a request`), or defaults to `GET` when directly followed by `at`.
2. **`at`**:
   - Contextual preposition marking the route path: `at "/path"`.
3. **`into`**:
   - Optional capture of the incoming request context into a named variable: `into req`.
   - The request object provides `method`, `path`, `query`, `body`, `headers`.
4. **`respond`**:
   - Statement starting with `respond with`.
   - Optional `as json` formats and sends Content-Type `application/json`.
   - Optional `and status <codeExpr>` or `with status <codeExpr>` sets HTTP response status.
   - `respond with status <codeExpr>` allows sending status-only responses (e.g. 204 No Content).
5. **`start` and `listen`**:
   - `start <server>` starts the server instance.
   - `listen on port <port>` provides the concise single-statement server form.

### Contract additions

`TokenKind`:
- `Respond`
- `Receives`
- `At`
- `Start`
- `Listen`

`NodeKind`:
- `WebRoute`
- `Respond`
- `StartServer`
- `ListenServer`

AST Node classes:
- `WebRouteStmt([Node]$server, [string]$method, [Node]$path, [string]$requestTarget, [Node[]]$body, [int]$line)`
- `RespondStmt([Node]$value, [Node]$status, [bool]$asJson, [int]$line)`
- `StartServerStmt([Node]$server, [int]$line)`
- `ListenServerStmt([Node]$port, [int]$line)`

---

## D52. Retroactive documentation: `has` for existing resources, comma `put`, contextual `the`, row/column layout

This entry documents work that was already implemented, tested, and
committed (14 commits, `e327a20` through `1eb4671`) without a
corresponding spec entry — the first batch since D16 to land that way.
Written after the fact specifically to close that gap before more work
builds on top of undocumented behavior. Nothing here was designed by
this entry; it verifies and records what the code already does.

### `has` now configures an existing UI resource, deterministically

```otter
create window into app

app has
    title is "Otter Calculator"
    width is 420
.
```

This was the exact open question from the pre-D48 investigation: could
`has` mean *both* "construct a new thing" and "configure this existing
resource" without ambiguity, and without a misspelled name silently
doing the wrong thing? Confirmed by reading `Otter.Interpreter.psm1`'s
`ObjectDef` case directly — the dispatch is on **runtime state**, not
parser-visible information (the parser cannot know whether a name is
already bound; `Environment.Has` is checked at execution time), which
matches D12's precedent (`add`/`remove` dispatch on runtime type, not
parse-time knowledge) rather than inventing a new mechanism:

- **Name doesn't exist yet** → constructs a new `thing`, exactly D40's
  original behavior, completely unchanged.
- **Name exists and holds a UI resource** → each property in the block
  is applied through the *existing* `Set-OtterUiProperty` (D45) — so an
  unknown property name is caught immediately by D45's own validation,
  the same as `property of x is value` already gives.
- **Name exists and holds anything else** (a number, a string, an
  existing plain `thing`, ...) → refuses outright: *"Otter will not
  replace existing `<type>` called `"<name>"` with a new thing."* This
  is deliberately more conservative than merging or replacing — it
  sidesteps the identity/aliasing question a plain thing would raise
  (does re-`has`-ing an existing `thing` update it in place, or replace
  it and orphan any other variable referencing the old one?) by simply
  not allowing it, leaving that as a genuinely separate, not-yet-needed
  question rather than deciding it implicitly here.

**The specific typo danger raised before implementation — `ap has ...`
when `app` was meant — turns out to be inherently safe**, confirmed by
how the dispatch above actually works: a name that was never bound
takes the *construct* branch, producing a harmless new `thing` called
`ap`; it can never reach or touch the real `app`. The genuinely
dangerous case (reusing the *correct* name) is exactly the one the
dispatch above makes safe.

Verified directly with two tests: `has configures an existing UI
resource without replacing it`, `has refuses to replace an existing
non-UI value` (`tests/UI.Tests.ps1`).

### Inline `has` — comma-separated, `is` optional per property

```otter
addButton has text "Add", width 120, background "#2563EB", foreground "white"
```

A second grammar was added alongside the original indented-block `has`
(unchanged): a single-line, comma-delimited form. `is` is checked and
consumed if present, otherwise skipped — independently for each
property in the list — so `text is "Add"` and `text "Add"` in the same
list both produce the identical `AssignStmt`. This went through several
short-lived intermediate states in the commit history (briefly
*requiring* the compact `is`-less form, before settling on making `is`
optional) — the state described here is the final, current one, verified
against the actual parser code (`Read-OtterInlineObjectProperties`,
`src/Otter.Parser.psm1`), not against any intermediate commit.

### `put` accepts a comma-separated list, desugared at parse time

```otter
put firstLabel, firstBox, secondLabel, secondBox, addButton, resultLabel in app
```

Confirmed by reading the parser directly: this is **not** a new AST
node. `Read-OtterStatement`'s `Put` case returns an *array* of
`PutInStmt` nodes (one per item, same container, order preserved), and
`Read-OtterStatements` splices an array result into the statement list
in place. `Otter.Interpreter.psm1` needed zero changes — every
desugared `PutInStmt` runs through the exact `'PutIn'` case D47 already
had.

### Contextual `the` — a readability word, restricted on purpose

```otter
create the window into the app
the text of the nameBox is "Jeff"
say the text of the nameBox
```

`the` is consumed and discarded with no AST or semantic effect,
verified in the parser (`src/Otter.Parser.psm1`) to apply **only**
where it introduces a genuine `<property> of ...` sequence or a
resource-creation target — explicitly *not* a blanket filler-word rule
("this is not a global filler-word rule," per the parser's own
comment). This matters: a general "skip the word `the` anywhere"
rule would risk swallowing `the` when it was meant as an ordinary
identifier or part of a string, which this restricted, position-specific
version cannot do.

### Row and column: real layout containers, not new UI concepts

```otter
create row into toolbar
toolbar has spacing 10
put folderBox, loadButton in toolbar
put heading, toolbar, resultText in app
```

Directly answers the layout-pressure question raised by the File
Browser dogfooding example (a text box and button that needed to sit
side by side, which vertical-only `StackPanel` stacking could not do).
`row` and `column` are new `OtterWpfKinds` entries — a horizontally-
oriented and a vertically-oriented `StackPanel`, respectively — nothing
more than that; they are `create`d, `put` into like any other resource,
and can themselves be `put` into another window/row/column (nesting
confirmed directly: a row inside a column inside a window, verified by
`[object]::ReferenceEquals` down the whole chain, in
`tests/UI.Tests.ps1`'s `rows and columns accept ordered and nested
children`).

`width`, `height`, `background`, and `spacing` all apply to `row`/
`column` the same way they apply to `window` — the existing D45/D48
property table, extended with two more kind entries, nothing new. One
implementation detail changed underneath this: `Set-`/`Get-OtterUiSpacing`
moved from storing the spacing value on the panel's own `Tag` property
to a module-level dictionary keyed by
`[System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode(Native)`
— needed because a `row`/`column`'s `Native` *is* the panel itself
(unlike a window, where the panel is `Window.Content`, a separate
object `Tag` could live on independent of the window), so `Tag` was no
longer available as the storage location as a `window`-only assumption.
Spacing's own behavior (works before or after `put`, future children
inherit the current value) is unchanged and still covered by the
original D48 tests plus new ones for the row/column case.

### Resolved: desktop deliberately does NOT accept `X is a <kind>` as UI construction

While tracing this batch, a cross-target inconsistency turned up:
Gemini's D50 web compiler recognizes `nameBox is a text box`
(`ObjectDefStmt` whose `TypeName` matches a UI-kind whitelist) as a UI
resource declaration, alongside `create text box into nameBox`.
Verified directly that the **desktop** interpreter does not — `nameBox
is a text box` on `otter run` produces an ordinary `OtterObject` with
`TypeName = "text box"` (`Test-OtterUiResource` is false), not a real
control; `put`/`show` on it fails with a genuine Otter error rather
than silently doing the wrong thing, which is at least safe, but the
same source file's meaning still diverges by target.

**Settled: this divergence is intentional and stays.** D43 already
froze the relevant boundary explicitly — *"`has` remains reserved for
ordinary data objects and does not become a second UI syntax."*
`X is a <kind>` with an indented property block is the same
construction-idiom family as `has` (the parser already treats them as
twins — both produce `ObjectDefStmt` via the identical inline-or-block
property-reading path); extending it to also mean "construct a real UI
resource" would directly contradict D43's already-frozen principle, not
merely add a convenience. `create <kind> into X` remains the one
desktop UI-construction syntax. This is also not purely a matter of
syntax preference: the web compiler's UI-kind whitelist (`page`,
`image`, `list`, ...) is broader than desktop's actual `OtterWpfKinds`
(`window`, `button`, `text`, `text box`, `row`, `column`) — `page` in
particular has no desktop equivalent at all — so full unification would
need its own separate design pass (does `page` map to `window`? do
`image`/`list` get built for desktop first?) rather than a one-line
interpreter change smuggled into this entry.

### What's built

Everything in this entry was already implemented and tested before this
entry was written; nothing here changes behavior. **Contract:** no
changes — every grammar addition here (`has` runtime dispatch, inline
`has`, comma `put`, contextual `the`, row/column) reused existing
`NodeKind`/`Node` shapes (`ObjectDefStmt`, `PutInStmt`) or needed only
`OtterWpfKinds`/`OtterUiProperties` table entries in `Otter.UI.psm1`.
Full suite: 13 test files at the time of this batch (a 14th, the web
compiler's own suite, landed separately under D50), all green.

---

## D53. Scroll container - frozen and implemented

```otter
create scroll into fileArea
height of fileArea is 350

create column into fileList
put fileList in fileArea
put fileArea in app
```

Driven directly by the File Browser dogfooding example: once the
dynamically-created file-label list exceeded the window's height, the
remaining files ran off-screen with no way to reach them. This entry
closes that gap with the smallest model that solves the actual problem,
not a general-purpose layout system.

### The load-bearing rule, verified before anything else

**A scroll region only becomes scrollable once it has an explicit
bound.** Verified directly, and this shaped the entire design: a
`ScrollViewer` with no explicit `Height`, placed inside Otter's existing
`StackPanel`-based window root (D47), does not scroll at all — it grows
to fit all of its content (`ScrollableHeight` stayed `0` with 798px of
real content inside a 300px window). Setting an explicit height fixes
it completely — re-verified with the same setup and `Height = 200`:
`ScrollableHeight` became `598`, and `ScrollToVerticalOffset` genuinely
moved the viewport (confirmed by reading `VerticalOffset` back after the
call). Otter does **not** invent an implicit default height to make
scrolling "just work" — that would be magic, and it would vary
unpredictably by provider (the web equivalent, a bounded `<div>` with
`overflow-y: auto`, has the exact same requirement for the exact same
underlying reason: unbounded content never triggers a scrollbar in CSS
either).

### `scroll` is a dedicated resource, not a container property

Verified `StackPanel` has no scroll capability of its own — no
scrollbar, no clipping, no `ScrollableHeight` concept; the properties it
does expose (`CanHorizontallyScroll`, `CanVerticallyScroll`,
`ScrollOwner`) exist only so a `ScrollViewer` can *coordinate* with a
scroll-aware panel, not to make the panel scroll unassisted. Scrolling
in WPF is always a distinct wrapping control. A `scrolling "vertical"`
property on `row`/`column` would have to secretly wrap the panel in a
`ScrollViewer` behind the scenes to mean anything — more hidden
machinery for the identical result a dedicated kind gives directly.

### Vertical-first, for free from the provider's own defaults

`ScrollViewer`'s real defaults are `VerticalScrollBarVisibility =
Visible`, `HorizontalScrollBarVisibility = Disabled` — vertical-only is
already the out-of-the-box behavior, not something built here.
Overridden to `Auto` (not raw `Visible`) so a scroll region with
non-overflowing content shows no scrollbar at all — verified directly
(`ScrollableHeight` is simply `0` in that case, no error, no special
state) — matching the same "nicer default than raw WPF" instinct
already behind D48's `HorizontalAlignment = Left` override on `button`/
`text`/`text box`. Horizontal scrolling is out of scope for D53
entirely; enabling it later is a one-line property addition with no
structural change, exactly like D48's own properties were added
incrementally to the same table.

### Exactly one child, and two silent-failure modes closed explicitly

`ScrollViewer` is a `ContentControl` (`ScrollViewer -> ContentControl ->
Control -> ...`, verified via the type's own inheritance chain) — the
same family as `Window`, not a panel. Two real gaps were found and
closed, both because `.Content` does **not** protect itself the way
`Panel.Children.Add` already does for `window`/`row`/`column`:

- **Setting `.Content` a second time on the same `scroll` does not
  throw** — verified directly, it silently replaces the first child
  with no error at all. Checked explicitly before touching the native
  object: *"A scroll can only hold one thing. Put a column or row in it
  first if you need more than one."*
- **Setting `.Content` to an element that is already parented somewhere
  else entirely does not throw either** — verified directly, it
  silently *steals* the element away from its real parent. `row`/
  `column`/`window` get this protection for free from
  `Panel.Children.Add`'s own exception; `scroll` needed an explicit
  check (`Item.Native.Parent -ne $null`, confirmed to reliably detect
  both a panel-attached and a ContentControl-attached element) before
  ever assigning `.Content`, raising the exact same *"can only be in
  one place at a time"* error `row`/`column`/`window` already give.

### Composability - no special-casing needed in either direction

`put scrollArea in someRow` (a scroll being placed *into* a row/column/
window) needed **zero** new code — the existing multi-child
`Add-OtterUiChild` path doesn't care what kind of resource it receives.
Nesting a `scroll` inside another `scroll` needed no special-casing
either (`ContentControl.Content` accepts anything, including another
`ScrollViewer`) — both verified directly with tests, not assumed from
the type shapes.

### Properties: `width`, `height`, `background` - no `spacing`

Same D45/D48 table mechanism, one more kind entry. `spacing` is
deliberately absent — verified `spacing` only ever means "distribute
multiple children apart" (`window`/`row`/`column`, all of which hold
their put-in children in an implicit multi-child panel); `scroll` holds
exactly one child directly, so the concept doesn't apply, and the
existing unsupported-property error (*"A scroll has no property called
`"spacing"`."*) covers it with no new logic.

### What's built

**Contract:** none — same pattern as D48 and D52, a provider table
addition, not a grammar change. **Runtime:** `src/Otter.UI.psm1` gained
the `'scroll'` entry in `$script:OtterWpfKinds` (`ScrollViewer`,
`HorizontalAlignment = Left`, `VerticalScrollBarVisibility = Auto`,
`HorizontalScrollBarVisibility = Disabled`) and in
`$script:OtterUiProperties` (`width`/`height`/`background`, no
`spacing`); `Add-OtterUiScrollChild` (the single-child path, with both
silent-failure checks above) and a small branch in `Add-OtterUiChild`
routing `Container.Kind -eq 'scroll'` to it before the existing
multi-child panel path. `src/Otter.Interpreter.psm1` — **unchanged**,
same as D48: everything routes through the `PutIn`/property machinery
already wired in from D45/D47.

14 new tests in `tests/UI.Tests.ps1`: creation, single-child attachment,
second-put rejection (and that the original child survives the rejected
attempt), the acceptance test the investigation itself demanded — real
overflowing content with a real bound produces a genuine positive
`ScrollableHeight` *and* `ScrollToVerticalOffset` actually moves
`VerticalOffset`, not just "a `ScrollViewer` object exists" — the
non-overflow case, `width`/`height`/`background`, unsupported
`spacing`, nesting into `window`/`row`/`column`, nesting a `scroll`
inside a `scroll`, and the one-parent rule enforced through `scroll`'s
own path. Full suite: 15 files, all green.

`examples/file-browser.ot` updated to wrap `resultsColumn` in a
`fileArea` scroll (`height` 350) before putting it in `app` — verified
end-to-end through the real lexer/parser/interpreter (28 real files,
28 labels, exact match) and visually confirmed with two renders: one at
the top of the list showing a real scrollbar with a thumb, and one
after `ScrollToBottom()` showing files (`variables.ot`, `ui-input.ot`,
...) that were completely unreachable before this entry.

**No Codex handoff.** Nothing here touches the lexer, parser, or
contract.

