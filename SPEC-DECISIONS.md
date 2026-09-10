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
