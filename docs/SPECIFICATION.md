# Otter Programming Language — Formal Language Specification (v1.0)

**Document Version:** 1.0.0  
**Status:** Frozen & Authoritative  
**Target:** Otter 1.0 Reference Implementation (PowerShell 5.1 / Node.js Engine)

---

## Table of Contents

1. [Introduction & Core Philosophy](#1-introduction--core-philosophy)
2. [Lexical Grammar](#2-lexical-grammar)
   - 2.1 Character Set & Encodings
   - 2.2 Whitespace & Indentation Tokens
   - 2.3 Comments
   - 2.4 Keywords & Reserved Words
   - 2.5 Identifiers
   - 2.6 Literals (Numbers, Text, Booleans, Gone)
3. [Syntactic Grammar & Layout](#3-syntactic-grammar--layout)
   - 3.1 Source Units & Statements
   - 3.2 Indentation & Period-Terminated Blocks
   - 3.3 Expressions & Operator Precedence
4. [Types & Value Domain](#4-types--value-domain)
   - 4.1 Primitive Types (Text, Number, Boolean, Gone)
   - 4.2 Composite Types (List, Thing, Blueprints)
   - 4.3 Native & Extended Types (Date, UI Resources)
5. [Variables, Environment & Scoping](#5-variables-environment--scoping)
   - 5.1 Variable Declarations & Assignment (`is`)
   - 5.2 Lexical Scoping & Closure Behavior
   - 5.3 Variable Shadowing & Immutability Guarantees
6. [Expressions & Operators](#6-expressions--operators)
   - 6.1 Arithmetic Operators (`plus`, `minus`, `times`, `divided by`, `modulo`)
   - 6.2 Comparison Operators (`is`, `is not`, `is greater than`, etc.)
   - 6.3 Logical Operators (`and`, `or`, `not`) & Context-Sensitive Rules
   - 6.4 Property Access & Projection (`of`)
7. [Statements & Control Flow](#7-statements--control-flow)
   - 7.1 Conditional Execution (`if`, `otherwise`)
   - 7.2 Count Loops (`count from X to Y as I`)
   - 7.3 Iteration Loops (`for each ITEM in LIST`)
   - 7.4 While Loops (`while CONDITION`)
   - 7.5 Repeat Loops (`repeat N times`)
8. [Functions & Procedures](#8-functions--procedures)
   - 8.1 Function Definitions (`to NAME with PARAMETERS`)
   - 8.2 Parameter Binding & Passing Semantics
   - 8.3 Return Values (Direct Expressions vs `make RESULT`)
   - 8.4 Recursion & Call Stack Limits
9. [Object Blueprints & Structural Modeling](#9-object-blueprints--structural-modeling)
   - 9.1 Type Blueprint Declarations (`a TYPE has FIELDS`)
   - 9.2 Instantiation (`X is a TYPE with ...`)
   - 9.3 Dynamic Key Access (`get ... from`, `set ... in`)
10. [Evaluation Semantics](#10-evaluation-semantics)
    - 10.1 Truthiness & Falsiness Rules
    - 10.2 Short-Circuit Evaluation
    - 10.3 Order of Evaluation & Side Effects
11. [Error Handling & Diagnostic System](#11-error-handling--diagnostic-system)
    - 11.1 Structural Handling (`try`, `otherwise`, `into`)
    - 11.2 Explicit Failure (`fail with`)
    - 11.3 Diagnostic Model (`OtterError`, line mapping, suggestions)
12. [Modular System & Package Resolution](#12-modular-system--package-resolution)
    - 12.1 Module Imports (`use`)
    - 12.2 Single-Evaluation DAG Resolution
    - 12.3 Export Visibility & Namespace Encapsulation
13. [Standard Library & System Interfaces](#13-standard-library--system-interfaces)
    - 13.1 Console I/O (`say`, `ask`)
    - 13.2 Filesystem Operations (`read file`, `write ... to file`)
    - 13.3 JSON Serialization & Deserialization
    - 13.4 System, Process & Date Math
14. [Target Hosts & Execution Environments](#14-target-hosts--execution-environments)
    - 14.1 Console Target (`otter run`)
    - 14.2 Web & Browser Target (`otter web`)
    - 14.3 Desktop Target (`otter desktop`)
    - 14.4 Capability Gating & Boundary Refusal
15. [Versioning & Compatibility Guarantees](#15-versioning--compatibility-guarantees)
    - 15.1 Semantic Versioning Model
    - 15.2 CLI Exit Code Contract
    - 15.3 Backward Compatibility & Deprecation Policy

---

## 1. Introduction & Core Philosophy

Otter is an approachable, human-readable programming language designed for clarity, structural safety, and cross-target portability. Otter code reads naturally, avoiding arbitrary cryptic punctuation in favor of descriptive English phrases, while maintaining a mathematically rigorous formal grammar and deterministic operational semantics.

Key tenets:
1. **Unambiguous Natural Syntax:** Statements such as `add 5 to score` or `for each item in list` are first-class language forms parsed deterministically.
2. **Explicit Block Structure:** Blocks are defined by indentation and explicitly terminated by a solitary period (`.`), eliminating ambiguity between dangling blocks and outer statements.
3. **No Silent Failures:** Operations that cannot be carried out safely raise explicit, structured `OtterError` diagnostics with accurate line numbers and remediation suggestions.
4. **Universal Value Model:** Values are runtime-portable across Windows PowerShell, modern POSIX runtimes, and client/server web targets.

---

## 2. Lexical Grammar

### 2.1 Character Set & Encodings
- Otter source text is encoded as **UTF-8** (with or without BOM) or ASCII.
- Line terminators are carriage return + line feed (`\r\n`), line feed (`\n`), or carriage return (`\r`). All line terminators are normalized to `\n` by the lexer.

### 2.2 Whitespace & Indentation Tokens
- Whitespace consists of spaces (` `) and horizontal tabs (`\t`).
- Indentation depth is tracked at the start of each line:
  - 4 spaces = 1 indentation level.
  - 1 tab = 1 indentation level (D7).
  - Mixing spaces and tabs within a single file is valid as long as each line consistently increments or decrements by full levels.
- The lexer synthesizes explicit layout tokens:
  - `Indent`: Emitted when indentation increases.
  - `Dedent`: Emitted when indentation decreases to match an outer block.
  - The parser never re-measures whitespace directly.

### 2.3 Comments
- Single-line comments begin with `#` and extend to the end of the line:
  ```otter
  # This is a comment
  score is 100 # Inline comment
  ```
- Blank lines and comment-only lines do not alter indentation tracking or emit layout tokens.

### 2.4 Keywords & Reserved Words
The following words have syntactic significance and cannot be used as variable or function identifiers:

`a`, `add`, `all`, `and`, `are`, `as`, `ask`, `at`, `between`, `by`, `check`, `contains`, `convert`, `count`, `day`, `days`, `derive`, `divided`, `each`, `else`, `empty`, `ends`, `error`, `exists`, `fail`, `false`, `first`, `for`, `format`, `from`, `get`, `gone`, `greater`, `has`, `hour`, `hours`, `if`, `in`, `into`, `is`, `item`, `join`, `last`, `least`, `length`, `less`, `list`, `log`, `lowercase`, `make`, `memo`, `minus`, `minute`, `minutes`, `modulo`, `month`, `months`, `most`, `not`, `now`, `number`, `of`, `or`, `otherwise`, `pi`, `plus`, `post`, `put`, `random`, `read`, `remove`, `repeat`, `replace`, `return`, `reverse`, `round`, `run`, `say`, `seconds`, `set`, `show`, `shuffle`, `sort`, `split`, `starts`, `state`, `text`, `thing`, `times`, `to`, `today`, `true`, `try`, `uppercase`, `use`, `warn`, `when`, `while`, `with`, `write`, `year`, `years`.

Multi-word tokens are lexed as single lexical units:
- `for each`
- `divided by`
- `is at least`
- `is at most`
- `is greater than`
- `is less than`
- `is not`

### 2.5 Identifiers
- Identifiers begin with a Unicode letter or underscore (`_`), followed by any combination of letters, digits, and underscores.
- Variable and function names are case-preserving but case-insensitive in resolution.
- Reserved literal words (`today`, `now`, `pi`) cannot be used as binding targets.

### 2.6 Literals
1. **Numbers:** Decimal float64 representations without sign or digit grouping (`42`, `3.14159`). Negative numbers are expressed syntactically as `0 minus N` (D5).
2. **Text:** Double-quoted strings (`"Hello world"`). Supported escapes: `\n`, `\t`, `\\`, `\"`. Multi-line strings are expressed using consecutive string expressions or explicit `\n`.
3. **Booleans:** `true` and `false`.
4. **Gone:** `gone` represents the absence of a value (equivalent to canonical null/none).

---

## 3. Syntactic Grammar & Layout

### 3.1 Extended Backus-Naur Form (EBNF) Grammar

```ebnf
Program         = { Statement | Newline } , EndOfFile ;

Statement       = VariableAssignment
                | FunctionDeclaration
                | ConditionalStatement
                | LoopStatement
                | TryCatchStatement
                | ReturnStatement
                | CommandStatement
                | ExpressionStatement ;

VariableAssignment = Identifier , "is" , Expression ;

PeriodBlock     = Newline , Indent , { Statement | Newline } , Dedent , "." ;

ConditionalStatement = "if" , Condition , PeriodBlock , [ "otherwise" , PeriodBlock ] ;

LoopStatement   = CountLoop | ForEachLoop | WhileLoop | RepeatLoop ;
CountLoop       = "count" , "from" , Expression , "to" , Expression , "as" , Identifier , PeriodBlock ;
ForEachLoop     = "for each" , Identifier , "in" , Expression , PeriodBlock ;
WhileLoop       = "while" , Condition , PeriodBlock ;
RepeatLoop      = "repeat" , Expression , "times" , PeriodBlock ;

FunctionDeclaration = "to" , Identifier , [ "with" , ParameterList ] , PeriodBlock ;
ParameterList   = Identifier , { ( "," | "and" ) , Identifier } ;

ReturnStatement = "make" , Expression ;
```

### 3.2 Period-Terminated Blocks
Every multi-line block construct (`if`, `otherwise`, `for each`, `while`, `repeat`, `count`, `to`, `try`) MUST conclude with a solitary period (`.`) on its own line matching the indentation of the initiating keyword.

```otter
if score is greater than 100
    say "You win!"
.
```

---

## 4. Types & Value Domain

Otter defines seven fundamental value types:

| Type | Nature | Mutability | Representation (.NET / JS) |
|---|---|---|---|
| **Text** | Unicode character sequence | Immutable | `System.String` / `string` |
| **Number** | IEEE 754 64-bit float | Immutable | `System.Double` / `number` |
| **Boolean** | Truth value | Immutable | `System.Boolean` / `boolean` |
| **Gone** | Missing value / null | Immutable | `$null` / `null` |
| **List** | Ordered sequence of elements | Mutable | `List<object>` / `Array` |
| **Thing** | Key-value associative dictionary | Mutable | `OtterObject` / `Object` |
| **Date** | ISO-8601 calendar date & time | Immutable | `DateTime` / `Date` |

---

## 5. Variables, Environment & Scoping

1. **Declaration & Assignment:**
   - Assignment uses the statement-level `is` keyword:
     ```otter
     name is "Alice"
     score is 50
     ```
   - If `name` does not exist in any enclosing scope, it is declared in the local environment.
   - If `name` exists in an outer scope, it is mutated in place unless shadowed.
2. **Function Scoping:**
   - Function bodies establish a distinct lexical scope.
   - Parameters and locally assigned variables do not escape to the caller.
3. **Loop Variables:**
   - Loop index and element variables (`as i`, `for each item`) are scoped strictly to the loop body.

---

## 6. Expressions & Operators

### 6.1 Operator Precedence (Tightest to Loosest)
1. **Primary & Grouping:** `( ... )`, literals, variable references.
2. **Property Access:** `property of target`.
3. **Unary Logical:** `not`.
4. **Multiplicative:** `times`, `divided by`, `modulo`.
5. **Additive & Math:** `plus`, `minus`.
6. **Relational / Comparison:** `is`, `is not`, `is greater than`, `is less than`, `is at least`, `is at most`.
7. **Logical Conjunction:** `and` (in conditional expressions).
8. **Logical Disjunction:** `or`.

### 6.2 Context-Sensitive `and` Rule (D11)
- Inside a **condition** (`if`, `while`, `where`), `and` is strictly a boolean conjunction:
  ```otter
  if score is greater than 50 and score is less than 100
  ```
- Inside a **math/assignment expression**, `and` acts as an additive alias for `plus`:
  ```otter
  total is 10 and 20 # yields 30
  ```

---

## 7. Control Flow Statements

### 7.1 If / Otherwise
```otter
if score is at least 90
    say "Grade: A"
otherwise
    say "Keep trying!"
.
```

### 7.2 Count Loops
```otter
count from 1 to 5 as step
    say "Step number: " plus step
.
```

### 7.3 For Each Loops
```otter
for each player in team
    say "Hello, " plus player
.
```

### 7.4 While Loops
```otter
while health is greater than 0
    health is health minus 10
.
```

---

## 8. Functions & Procedures

### 8.1 Declaration & Return
```otter
to calculateArea with width, height
    make width times height
.

area is calculateArea with 10, 20
```

### 8.2 Procedure without Return
Functions without an explicit `make` return statement implicitly return `gone`.

---

## 9. Object Blueprints & Structural Modeling

### 9.1 Blueprints
```otter
a User has name, email, score

player is a User with name "Jeff", email "jeff@example.com", score 100
say player's name
```

### 9.2 Dynamic Key Manipulation
```otter
set "status" to "active" in player
get "status" from player into currentStatus
```

---

## 10. Evaluation Semantics

### 10.1 Truthiness
A value evaluates to `false` in a condition if and only if it is:
1. `false`
2. `0` or `0.0`
3. `""` (empty string)
4. `gone`
5. An empty collection (List or Thing with 0 items)

All other values evaluate to `true`.

### 10.2 Short-Circuit Evaluation
Logical `and` and `or` expressions strictly short-circuit left-to-right.

---

## 11. Error Handling & Diagnostics

### 11.1 Try / Otherwise
```otter
try
    dangerousOperation
otherwise into err
    say "Operation failed: " plus err
.
```

### 11.2 Explicit Failure
```otter
if divisor is 0
    fail with "Cannot divide by zero."
.
```

### 11.3 Diagnostic Structure
Errors produced by the compiler or runtime are structured as `OtterError`:
- `Message`: Human-readable explanation.
- `LineNumber`: 1-indexed source line.
- `SourceLine`: Exact offending source line.
- `Suggestion`: Concrete guidance on how to resolve the syntax or runtime error.

---

## 12. Modular System

Modules are imported using the `use` statement:
```otter
use "math_helpers.ot"
```
Module evaluation forms a Directed Acyclic Graph (DAG) resolved by canonical path. Diamond dependencies evaluate the shared leaf module exactly once.

---

## 13. Standard Library

- **Console:** `say <expr>`, `ask <prompt> into <var>`.
- **Filesystem:** `read file <path> into <var>`, `write <expr> to file <path>`, `if file <path> exists`.
- **JSON:** `convert <expr> to json`, `convert <expr> from json`.
- **Date Math:** `today`, `now`, `add <N> days to <date>`, `days between <d1> and <d2>`.
- **Collections:** `add <item> to <list>`, `remove <item> from <list>`, `sort <list>`, `reverse <list>`.

---

## 14. Target Hosts & Platform Boundaries

1. **Console Target (`otter run`):** Full access to local OS, files, processes, and environment.
2. **Web Target (`otter web`):** Compiles Otter to HTML/CSS/JS for modern browsers; DOM elements and HTTP `fetch` are first class; direct local disk access is restricted.
3. **Desktop Target (`otter desktop`):** Native window host with UI layout, reactive events, and secure native bridge.

When an operation unsupported on the current target is invoked, Otter raises an immediate diagnostic naming the capability boundary rather than silently ignoring the request.

---

## 15. Versioning & Compatibility Guarantees

1. **Semantic Versioning:** Otter follows `MAJOR.MINOR.PATCH` SemVer rules.
2. **CLI Exit Code Contract:**
   - `0`: Success.
   - `1`: CLI invocation or usage error.
   - `2`: Lexical, syntactic, or static check error.
   - `3`: Unhandled runtime exception.
3. **Backward Compatibility:** All valid Otter 1.0 code is guaranteed to parse and execute with identical semantics across all 1.x releases.
