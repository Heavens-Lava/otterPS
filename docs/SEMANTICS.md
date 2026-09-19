# Otter Programming Language — Formal Semantic Specification (v1.0)

This document specifies the operational semantics and evaluation rules of the **Otter Programming Language**.

---

## 1. Value Domain and Types

The Otter runtime operates over the following primitive and structured value types:

| Otter Type | PowerShell / .NET Implementation | JavaScript / Node Implementation | Description |
|---|---|---|---|
| **Text** | `System.String` | `string` | UTF-8/Unicode sequence |
| **Number** | `System.Double` | `number` (IEEE 754 float64) | Universal 64-bit float |
| **Boolean** | `System.Boolean` | `boolean` | `true` or `false` |
| **Gone** | `$null` / singleton | `null` | Absence of value |
| **List** | `System.Collections.Generic.List[object]` | `Array` | Ordered, mutable sequence |
| **Thing** | `OtterObject` | Object with `{ __otterThing: true }` | Key-value dictionary with ordered properties |
| **Date** | `OtterDate` (`System.DateTime`) | `{ __otterDate: true, value: Date }` | Instant with calendar and time representation |
| **UI Resource** | WPF UI element | DOM HTMLElement / Object | Host-backed UI element |

---

## 2. Truthiness Evaluation (D9)

In conditions (`if`, `while`, and logical expressions), a value evaluates to `false` if and only if it is:
1. Boolean `false`
2. Numeric `0` or `0.0`
3. Empty text `""`
4. `gone` (null)
5. An empty collection (e.g. `items are empty` with count 0)

All other values evaluate to `true`, including non-empty strings, numbers other than zero, objects, and non-empty collections.

---

## 3. Short-Circuit Evaluation

Logical expressions strictly short-circuit left-to-right:
- `A and B`: If `A` is falsy, `B` is not evaluated; the expression returns `false`.
- `A or B`: If `A` is truthy, `B` is not evaluated; the expression returns `true`.

---

## 4. Environment & Scoping

1. **Environment Hierarchy**: Variable lookup traverses outward from local function scope to global scope.
2. **Assignment (`is`)**:
   - At statement level, `x is value` binds or updates `x` in the enclosing scope.
   - If `x` does not exist in any enclosing scope, it is declared in the current local scope.
3. **Loop Variables**: Loop iteration variables (`for each item in list`, `count from 1 to 5 as i`) are bound locally to the loop block.
4. **Function Isolation**: Modifying a parameter or local variable inside a function does not mutate an outer variable of the same name unless explicitly qualified or globally defined.

---

## 5. Objects & Property Access (`of`)

1. **Property Access**: `property of target` evaluates right-recursively. For example, `city of address of user` parses as `city of (address of user)`.
2. **Missing Properties**: Reading an undefined property on a thing raises a runtime `OtterError` explaining that the property does not exist.
3. **Property Assignment**: `name of person is "Alice"` updates the property on the referenced object in place. If the property did not exist, it is created.
4. **Custom Types**: Types are declared via `a Person has name and age`. Instantiating `p is a Person` pre-allocates declared properties.

---

## 6. Functions and Execution

1. **Declaration (`to`)**: Declares a named function visible within the module from declaration onward (supporting recursion).
2. **Return / Stop**:
   - `return <expression>` terminates function execution and yields a value.
   - `stop` terminates execution with value `gone`.
3. **Call Syntax**: Calls are invoked by name followed by space-delimited arguments. Results are captured using `make <target>` (e.g., `addNumbers 5 and 10 make sum`).

---

## 7. Error Handling (`try` / `otherwise`)

1. If an unhandled exception occurs inside a `try` block, execution immediately jumps to the `otherwise` block.
2. If execution completes without error in `try`, the `otherwise` block is bypassed.
3. Errors are normalized into `OtterError` objects with phase, line, column, source line, and helpful suggestions.

---

## 8. Control Flow & Language Decisions

1. **Contextual Keywords**: All contextual keywords (`is`, `as`, `into`, `are`, `has`, `of`, `and`, `to`, `make`) are disambiguated deterministically by statement-head and syntactic position per `rules.md` and `SPEC-DECISIONS.md`.
2. **Recursion & Call Stack**: Functions support full recursion. Otter relies on the standard call stack of the host runtime; unbounded recursion terminates via runtime stack limits.
3. **Generators & Yield**: Deferred. Otter sequences are eagerly represented as `List` collections or iterative `count from ... to ...` loops.
4. **Pattern Matching**: Branching uses deterministic `if` / `otherwise if` cascades with boolean and text-matching operators. Pattern matching is deferred until post-1.0 dogfooding.

---

## 9. Numeric Precision & String Semantics

1. **Unified Numeric Type**: Numbers in Otter use 64-bit IEEE 754 floating-point representation (`double` in PowerShell/.NET, `number` in JS), covering values from `±5e-324` to `±1.7e+308`. Whole numbers format without a decimal suffix (`10`), while fractional values format with standard decimal points (`10.5`).
2. **No Integer Overflow Surprises**: Unifying integers and floats into IEEE 754 eliminates arithmetic overflow errors on standard operations.
3. **Unicode Text Semantics**: Otter strings represent Unicode text. File I/O explicitly enforces UTF-8 encoding (no BOM). Text operations (`length of`, `first of`, `last of`) preserve Unicode codepoints.

---

## 10. Object Model & Encapsulation Decisions

1. **Composition over Inheritance**: Otter deliberately avoids class inheritance hierarchies. Data structures are modeled through plain `thing` objects or custom types declared via `a Type has ...`.
2. **Properties vs Methods**: Behaviors are expressed through standalone functions (`to funcName ...`) and operations (`operation of target`) rather than class methods, keeping syntax readable and approachable.
3. **Public Properties**: Object properties are public. Encapsulation is achieved at module boundaries through file-level scoping.
4. **Reference Semantics**: Things are reference types. Assigning a thing to multiple variables or passing it into functions shares the underlying reference.

---

## 11. Closures & Module Scope

1. **Closures**: UI and event handlers close over their lexical environment at registration time.
2. **Exports**: Top-level function and type definitions in an Otter module are automatically visible when imported via `use "module.ot"`.
3. **DAG Resolution**: The module resolver caches imported files in a directed acyclic graph (DAG), ensuring diamond dependencies are loaded exactly once and circular imports are rejected with clear diagnostics.

---

## 12. Memory Model & Resource Management

1. **Garbage Collection**: Otter delegates memory allocation and reclamation to the host runtime's garbage collector:
   - .NET / Windows PowerShell 5.1 CLR generational garbage collector.
   - V8 / JavaScript engine generational and mark-sweep garbage collector.
2. **Reference Cycles**: Tracing garbage collectors in both supported runtimes naturally collect circular references among objects and lists without leaks.
3. **Deterministic Handle Cleanup**:
   - File streams are opened, processed, and closed immediately within runtime file operations (`Read-OtterFile`, `Write-OtterFile`, `Add-OtterFileContent`).
   - Server sockets and terminal bridges implement deterministic session teardown (`Stop()`, `Dispose()`, and graceful heartbeat timeouts).
   - Child processes spawned by `run command` are awaited and their standard stream buffers drained and closed upon process termination.
4. **Out-of-Memory Handling**: Host OOM errors are converted into runtime diagnostic errors where feasible or trigger clean host termination without data corruption.

---

## 13. Concurrency & Async Architecture

1. **Host Event Loop & UI Dispatch**: Otter UI execution runs on the host's primary UI thread (WPF dispatcher on Windows, browser event loop in Web applications). Event handlers execute sequentially, preventing data races on user variables.
2. **Asynchronous Operations**: Host bridge operations (file I/O, process execution, HTTP requests) use asynchronous non-blocking patterns behind the scenes, exposing synchronous or promise-backed semantics to the Otter script.
3. **Process Concurrency & Signals**: Subprocesses execute concurrently with the host when started via `Start-OtterProgram` or desktop bridge, with cancellation signals routed via standard OS signals or process termination.
4. **Cancellation & Timeouts**: Asynchronous operations and long-running bridge sessions enforce deterministic timeout boundaries (`HandleNextRequest($TimeoutMs)`) and heartbeat intervals (`HeartbeatGraceMs = 8000`). Cancellation is triggered via explicit session termination (`Stop()`) and process tree termination (`Process.Kill()`).
5. **Thread-Safe Runtime & Deadlock Prevention**: Otter script execution is strictly single-threaded per environment. Because user code cannot acquire raw mutex locks or block background threads directly, deadlock conditions are structurally impossible within pure Otter scripts.
6. **Structured Concurrency Model**: Rather than exposing raw threads, locks, or channels that complicate syntax and introduce race conditions for beginners, Otter delegates concurrency to isolated OS processes and host-managed event queues.

---


## 14. Extended Data Model Decisions

1. **Large Integers**: Safe integer precision is exact within `[-9,007,199,254,740,991, 9,007,199,254,740,991]` (IEEE 754 safe integer limit). Calculations beyond this range gracefully approximate without throwing numeric overflow exceptions.
2. **Decimal & Currency Strategy**: Floating-point decimals are formatted deterministically via standard library formatters (`Format-OtterValue`), suppressing scientific notation for everyday quantities and preventing rounding artifacts.
3. **Set Semantics**: Sets are represented as unique-element `List` collections, queried using readable `contains` expressions (`if items contains "apple"`).
4. **Tuples and Records**: Otter rejects positional tuple syntax (`(a, b)`) in favor of readable named things (`thing with x is 10 and y is 20`) or declared types (`a Coordinate has x and y`). This ensures every field has an explicit semantic name.
5. **Enums & Constants**: Distinct states are expressed using self-describing text literals (`"active"`, `"paused"`, `"completed"`) rather than artificial numeric enum mappings, aligning with Otter's natural-language design philosophy.
6. **Type Reflection & Introspection**: Every object exposes runtime type metadata through its `TypeName`, `PropertyNames()`, and property lookup mechanisms, enabling dynamic serialization, debugging, and inspector interfaces.
7. **Polymorphism & Generics**: Otter uses dynamic structural typing (duck typing) for collections and functions. Functions operate generically on any value providing the required properties without requiring complex generic type parameters.


