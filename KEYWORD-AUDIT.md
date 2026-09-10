# Otter Keyword Audit — a proposed decision, NOT yet approved

**Status: DRAFT. Nothing in this file is implemented. No lexer, parser, or
runtime file has been changed to produce it, and nothing here should be
treated as decided until Jeff approves a rule.**

This is not part of `SPEC-DECISIONS.md` for exactly that reason — that file
is authoritative and both agents build against it. This file is a report.
If a rule is approved, it becomes a new `SPEC-DECISIONS.md` entry (**D33**)
and only then does it become buildable.

---

## The question

Otter reserves 78 words at the lexer level today (plus 12 words recognized
contextually — `first`, `length`, day-units, etc. — and 2 more, `number` and
`item`, recognized only by text inside one parser branch). Every reserved
word is unusable as a variable name, function name, parameter name, property
name, or `for each` loop variable — in **every** position, not just the one
position where the grammar actually needs it.

That is correct for words like `is`, `to`, `of` — words the grammar leans on
constantly. It is very likely wrong for words like `copy`, `format`,
`random`, `error` — words that appear in exactly one place in the grammar
and nowhere else.

The goal stated for this audit was not "free every word." It was: stop
Otter from accumulating hundreds of unnecessarily forbidden ordinary words
as the language grows, the way D24 (`length`/`first`/`last`) and D32 (time
units) already proved is possible for two feature areas.

## Method

Every reserved word was tested empirically — not reasoned about — in six
positions, by feeding real source through the actual lexer and parser:

```
variable    x is 5
read back   x is 5 / say x
function    to x / say "hi"
parameter   to greet x / say x
property    book is a thing / x is 5 / .
for each    for each x in games / say x
```

Then, for every reserved token, I counted how many distinct places in
`src/Otter.Parser.psm1` reference that token kind — a direct measure of how
entangled a word is in the grammar, independent of guesswork.

```
95 words tested empirically
23 already usable in all six positions
72 blocked in at least one position
```

```
55 of ~100 token kinds are referenced at exactly ONE site in the parser
```

That second number is the headline finding. More than half the language's
vocabulary exists to gate exactly one statement shape and nothing else.

---

## 1. Must always be reserved — real ambiguity, not just current convenience

These cannot be made contextual with the adjacency trick D24 and D32 use,
because they appear in the same grammatical **slot** an identifier would
occupy, with no adjacent token to tell the two apart.

| Word | Why it cannot be freed |
|---|---|
| `gone` | Appears as a **value**, in exactly the slot a variable reference would occupy: `user is gone`. There is no token adjacent to `gone` that would distinguish "the absence literal" from "a variable named `gone`" — both parse identically. Freeing this breaks D22 outright. |
| `true`, `false` | Same shape as `gone`: literals sitting in ordinary value position. `ready is true` cannot be told from a reference to a variable called `true`. |
| `a` | **Two separate structural roles**, not one: statement-leading (`a Person has ...`) and mid-statement after `is` (`jeff is a Person`, `person is a thing`). A rule of "only a keyword when preceded by `Is`" looks clean until `letter is a` — meant as *copy the variable named `a`* — collides with `letter is a <Type>`, an object literal with no type given yet. Telling those apart needs either a second token of lookahead (peek past `a` for a capitalized name or the word `thing`) or an outright decision that this case stays unsupported. Both are judgment calls, not free wins. |
| `and` | Three unrelated jobs already coexist here (D11: addition vs. boolean-and) plus the `and subfolders` / `and call it` idioms (D32, ask). The highest-entanglement word measured (8 parser sites). Any further overload risks colliding with one of the existing three. |
| `is`, `to`, `of`, `in`, `into`, `from`, `with`, `where`, `as`, `make`/`makes`, `not`, `or` | The D17 structural set, already documented as never-filler. Every one of these sits at 2+ parser sites and several (`to`, `into`, `from`) at a dozen or more. They are the connective tissue the rest of the grammar hangs off. |

**Ambiguity discovered, not assumed:** the `a` case and the `gone`/`true`/
`false` case are genuinely different problems. `a` might be solvable with
more lookahead; `gone`/`true`/`false` cannot be, because the collision is
positional, not adjacency-based — there is nothing to look *at*.

## 2. Can safely be contextual, by direct extension of the existing mechanism

These sit at exactly **one** parser site: the head of the one statement they
introduce. The existing dispatch in `Read-OtterStatement` already only
checks a token's kind when it is the very first token of a statement — the
gap is that the **lexer** currently converts the word into that keyword
token unconditionally, everywhere it appears, not only at the head of a
statement.

| Word | Statement it gates | Site count |
|---|---|---|
| `copy`, `move`, `delete`, `create` | file/folder operations | 1 |
| `read`, `write`, `sort`, `reverse`, `replace`, `split`, `join`, `find` | files, strings, collections | 1 |
| `get`, `try`, `run` | discovery, error handling, processes | 1 |
| `log`, `warn`, `error` (`Problem`) | diagnostics (D31) | 1 |
| `random`, `json`, `convert`, `format`, `today`, `now`, `between` | D29/D30/D32 | 1 |
| `otherwise` | if/otherwise-if/otherwise, try/otherwise | 3, but every site is a clause head |
| `exists`, `contains` | infix condition words (`if file X exists`, `if Y contains Z`) | 1 each, but mid-expression rather than statement-head — needs the D24-style "preceded by a value" rule instead of "first token of statement" |
| `empty` | only ever follows `are` | 1, D24-style: keyword only when preceded by `Are` |
| `has` | only ever follows the `a`-driven type-def parse | 1, already grammatically unreachable elsewhere |
| `call`, `it` | fixed three-word idiom `and call it <name>` | 1 each, safe because the whole phrase is rigid |

These are worked examples that match the audit's own test cases directly:

```otter
copy is "backup"                    # would become a normal assignment
say copy

format is "PDF"
say format

error is "Connection failed"
say error

random is 5
say random
```

while the real statements stay unambiguous, because each still opens with
the word at the head of a line:

```otter
copy file to "Backup"
format date as "MM/dd/yyyy" into text
error "Could not connect."
random number from 1 to 10 into number
```

**This needs one new lexer capability, not present in D24/D32**: those two
decisions disambiguate by an *adjacent token* (`of`, a number, `between`).
This group needs disambiguation by *position in the statement* — "is this
token the first one on its logical line" — which the lexer does not
currently reason about explicitly, even though it already tracks line and
indent boundaries and could.

## 3. Already contextual — nothing to do

Confirmed working today, by direct test:

| Mechanism | Words |
|---|---|
| Keyword only immediately before `of` (D24) | `length`, `uppercase`, `lowercase`, `first`, `last` |
| Keyword only immediately before `with` | `starts`, `ends` |
| Keyword only immediately before `by` | `divided` |
| Combined into one token only when adjacent | `for` + `each` → `ForEach` (neither word is in the static keyword table at all) |
| Keyword only after a number, or before `between` (D32) | `day`/`days`, `month`/`months`, `year`/`years`, `hour`/`hours`, `minute`/`minutes`, `second`/`seconds` |
| Matched by **text**, inside one parser branch — never reserved at the lexer level at all (D30) | `number`, `item` |
| Explicitly whitelisted alongside `Identifier` everywhere an identifier is accepted | `file`, `files`, `folder`, `folders` |

The `file`/`files`/`folder`/`folders` mechanism is worth naming separately
from D24's: rather than "keyword only near a trigger token," these four are
simply **always** legal as identifiers in addition to their keyword role,
because the grammar never actually collides on them. That is a third,
even-simpler pattern, and it is the cheapest of the three to extend.

## 4. Structural words that must remain protected

This is the D17 list, restated here because the audit's site-count data
confirms it rather than merely repeating it. Every one of these sits at 2+
parser sites; several sit at a dozen or more (`to`: 12, `into`: 12, `and`: 8,
`from`: 7):

```
of   to   from   into   with   where   as   in   and   or   not   is   make
```

**One gap found in the existing D17 list:** `by` (`split X by Y`) is the
same part of speech as `with`/`from`/`into` and functions identically, but
it was never added to D17's structural table — it happens to sit at only
one parser site today simply because only one statement uses it so far.
Recommend adding `by` to the protected list now, before a second use of it
creates the same kind of accidental-looking exception this audit is trying
to prevent.

## 5. Reserved by implementation convenience, not language necessity

| Word | Evidence |
|---|---|
| `thing` | Confirmed, not inferred: `Read-OtterObjectTypeName` reads every token by `.Text` and joins them until `Newline` — it never once inspects `.Kind`. It already works this way so that future two-word UI type names (`text box`, `password box`) can be read the same way. The `'thing' = [TokenKind]::Thing` line in the lexer's keyword table is dead weight today; removing it needs zero parser change. |
| `open` | Zero parser sites. Reserved purely as a placeholder for an unwritten `open "notes.txt"` feature (`rules.md` section 31). |
| `when` | Zero parser sites. Reserved purely as a placeholder for `rules2.md`'s unwritten UI-event syntax (`when button is clicked`). |
| `makes` | Zero independent sites — the lexer collapses it into `Make` before the parser ever sees it (D3), so it is not really a separate reservation at all. |

`open` and `when` are not accidents in the pejorative sense — the lexer's
own comment states the intent plainly: *"Reserved for later language
versions. Lexing them now prevents a future keyword from silently changing
an existing program's meaning."* That is a deliberate, reasonable policy.
It is included here because it is a **different justification** than
categories 1–4, and worth naming as its own thing: **pre-reservation for
known future grammar**, distinct from *accidental* reservation.

The larger point: **most of category 2 is also category 5.** The verbs in
category 2 are reserved everywhere not because the grammar demands it, but
because the lexer's keyword table is a flat, unconditional map with no
notion of position. The two categories describe the same underlying words
from two different angles — "here's the fix" and "here's why it wasn't done
this way already."

---

## A qualifier that cuts across every category: design intent, not just grammar

Several words are **grammatically** eligible for category 2 — `if`, `while`,
`repeat`, `count`, `return`, `ask`, `say` — sitting at only 1–2 parser sites
each, gated purely by statement-head position, exactly like `copy` or
`format`.

I would not free these anyway, and not for a grammatical reason. Otter's own
pitch is *"readable like English, precise like code"* — `if`, `say`, and
`while` are the words a beginner reads first, and they are the words used
in every one of Otter's own design examples. A program that runs with `if
is 5` sitting above it is technically unambiguous and quietly hostile to the
same beginner the language is for. This is a **pedagogical** boundary, not a
grammatical one, and it should be decided as its own question rather than
falling out of the grammar audit by accident.

Recommend treating this as a short, separate, explicit list — core
control-flow and I/O vocabulary that stays reserved by design regardless of
what the grammar would technically allow.

---

## Lexer implications

Three different contextual mechanisms now exist or are proposed, and they
should be named as such rather than left implicit:

1. **Adjacency to a trigger token** (D24, D32): keyword only when a specific
   token immediately precedes or follows. Cheapest, already proven twice.
2. **Statement-head position** (proposed, category 2): keyword only when
   the token is the first one on its logical line. Requires the lexer to
   carry an "am I at the start of a statement" flag through the combining
   pass — new, but a small, mechanical addition; the lexer already knows
   line and indent boundaries.
3. **Always-legal-alongside-Identifier** (already used for `file`/`files`/
   `folder`/`folders`): no contextual logic at all — the word is simply
   accepted in both roles because the grammar never collides. Cheapest of
   the three, and worth checking first for any given word before reaching
   for mechanism 1 or 2.

None of these three requires runtime type information — consistent with
D24's and D32's existing rule that the parser must decide from the token
stream alone. That principle should extend to whatever gets approved here.

## Parser implications

Every place that currently does
`Assert-OtterTokenKind([TokenKind]::Identifier)` or checks
`$token.Kind -in @([TokenKind]::Identifier, ...)` would need the newly-freed
kinds added to that whitelist — the same pattern already used for `File`/
`Files`/`Folder`/`Folders`. This is mechanical and low-risk *once the lexer
decision is made*; it is not a second design problem.

## Compatibility risk

None to existing programs. Every existing `.ot` file and every test that
currently relies on `copy`, `format`, `random`, etc. being a *keyword* would
keep working unchanged, because the statement forms themselves are
untouched — only new uses (as a bare identifier) become newly legal. This
is purely additive, the same shape as every other decision since D6.

The one real risk is **scope creep in the other direction**: if "safely
contextual" is read too generously, someone frees a word from category 1
by accident later and it is much harder to notice, because the failure
mode is silent misparse, not a syntax error. The recommendation below is
written to guard against that specifically.

## Recommended rule for future Otter keywords

> **A new keyword is reserved everywhere by default. It may be narrowed to
> a single grammatical position only after the position is proven to be
> the word's only real use — checked by direct testing, the way `first`,
> the time units, and this audit's category-2 words were checked — and
> only using one of the three named mechanisms above. A word is never made
> contextual by relying on spelling or capitalization convention (the `a`
> case in this audit is the cautionary example of exactly that trap). If a
> word appears in more than one grammatical position, or in the same
> position a value or identifier would occupy, it stays reserved
> everywhere, full stop — no exceptions decided ad hoc.**

Practically, for D33 if approved: implement category 3's `file`-style
mechanism first (cheapest, zero new lexer logic) for `thing` and any other
category-5 word confirmed dead-code-free; implement the statement-head
mechanism once, generically, for the whole category-2 list at once rather
than word by word; leave categories 1 and 4 untouched permanently unless a
specific new grammar need forces a fresh look; treat the pedagogical
qualifier list as Jeff's call, not mine, the same way D32.7's sign question
was.
