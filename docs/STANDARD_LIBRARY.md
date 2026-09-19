# Otter Programming Language — Standard Library Specification

This document defines the standard library constructs provided across all Otter hosts.

---

## 1. Math & Numbers
- **Operations**: `plus`, `minus`, `times`, `divided by`, `percent` (modulo/remainder).
- **Mutations**: `increase <var> [by <expr>]`, `decrease <var> [by <expr>]`.
- **Precedence**: Multiplicative precedes additive; parenthesized expressions take highest priority.

---

## 2. Text & Strings
- **Interpolation**: Direct value juxtaposition (`say "Count is " count`).
- **Of Operations**:
  - `length of <text>`
  - `uppercase of <text>`
  - `lowercase of <text>`
  - `first of <text>`
  - `last of <text>`
- **Matching Operations**:
  - `<text> contains <subtext>`
  - `<text> starts with <prefix>`
  - `<text> ends with <suffix>`

---

## 3. Collections & Lists
- **Declaration**: `items are "a", "b", "c"` or multiline block or `items are empty`.
- **Iteration**: `for each <item> in <list>` (or `each <item> in <list>`).
- **Mutations**:
  - `add <value> to <list>`
  - `remove <value> from <list>`
- **Inspection**: `length of <list>`.

---

## 4. Dates & Time
- **Clock**: `today` (date without time), `now` (date and time).
- **Parts**: `year of <d>`, `month of <d>`, `day of <d>`, `hour of <d>`, `minute of <d>`, `second of <d>`.
- **Arithmetic**: `add <N> days to <d>`, `remove <N> hours from <d>`.
- **Intervals**: `<unit> between <d1> and <d2> make <var>`.
- **Formatting**: `format <date> as "<pattern>" into <var>`.

---

## 5. Random
- **Numbers**: `random number from <min> to <max> into <var>`.
- **Items**: `random item from <list> into <var>`.

---

## 6. Serialization & JSON
- `read json from <path> into <var>`
- `convert <subject> to json into <var>`
- `convert <text> from json into <var>`

---

## 7. Diagnostics & Logging
- `log <expr>`: Standard info diagnostic.
- `warn <expr>`: Warning diagnostic.
- `error <expr>`: Error diagnostic.
