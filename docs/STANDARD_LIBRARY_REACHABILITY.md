# Otter 1.0 — Standard Library and Runtime Reachability Certification

## Overview
This document records the standard-library and runtime reachability audit for Otter 1.0.
Every capability claimed for the 1.0 runtime must be reachable through canonical `.ot` syntax and the production CLI entry point (`otter.cmd run`), executed by the real parser and interpreter runtime, and certified with automated tests.

Certification test suite: [tests/StandardLibrary.Tests.ps1](file:///c:/Users/jmacy/projects/otterPS/tests/StandardLibrary.Tests.ps1)
Result: **31 / 31 capabilities certified (100% PASS)**

---

## Reachability Matrix

| Area | Capability | Canonical Otter Syntax Example | AST Node / Runtime Handler | Status |
|---|---|---|---|---|
| **Text** | Uppercase | `say uppercase of t` | `OfOperationExpr (Uppercase)` | CERTIFIED |
| **Text** | Lowercase | `say lowercase of t` | `OfOperationExpr (Lowercase)` | CERTIFIED |
| **Text** | Starts/Ends With | `if t starts with "a" and t ends with "z"` | `TextMatchExpr (StartsWith/EndsWith)` | CERTIFIED |
| **Text** | In-place Replace | `replace "a" with "b" in t` | `ReplaceStmt` | CERTIFIED |
| **Text** | Split | `split t by "," into parts` | `SplitStmt` | CERTIFIED |
| **Text** | Contains | `if t contains "otter"` | `ContainsExpr` | CERTIFIED |
| **Text** | Length | `say length of t` | `OfOperationExpr (Length)` | CERTIFIED |
| **Math** | Arithmetic | `x is 10 plus 5 times 2 minus 6 divided by 2` | `MathExpr` / precedence tree | CERTIFIED |
| **Math** | Percent Of | `say 20 percent of 150` | `PercentOp` | CERTIFIED |
| **Math** | Power | `say 2 power 8` | `PowerOp` | CERTIFIED |
| **Math** | Rounding | `say round of 3.7` / `round up of 3.2` | `OfOperationExpr (Round/RoundUp/RoundDown)` | CERTIFIED |
| **Math** | Absolute Value | `say absolute value of n` | `OfOperationExpr (AbsoluteValue)` | CERTIFIED |
| **Math** | Square Root | `say square root of 144` | `OfOperationExpr (SquareRoot)` | CERTIFIED |
| **Math** | Min / Max | `say larger of 15 and 25` / `smaller of ...` | `MinMaxExpr` | CERTIFIED |
| **Math** | Trigonometry | `say sine of 90` / `cosine of 0` / `tangent of 45` | `OfOperationExpr (Sine/Cosine/Tangent)` | CERTIFIED |
| **Math** | Logarithms | `say log of 100` | `OfOperationExpr (LogTen)` | CERTIFIED |
| **Collections** | Lists | `nums are \n 10 \n 20 \n .` | `ListDefStmt` | CERTIFIED |
| **Collections** | Mutation | `add 30 to nums` / `remove 10 from nums` | `AddToStmt` / `RemoveFromStmt` | CERTIFIED |
| **Collections** | Empty List | `emptyList are empty` | `ListDefStmt (Items: empty)` | CERTIFIED |
| **Collections** | Iteration | `for each item in items \n ... \n .` | `ForEachStmt` | CERTIFIED |
| **Objects** | Object Definition | `person has \n name is "Alice" \n .` | `ObjectDefStmt` | CERTIFIED |
| **Objects** | Property Read/Write | `say name of person` / `name of person is "Bob"` | `PropertyAccessExpr` / `AssignStmt` | CERTIFIED |
| **Objects** | Dynamic Keys | `get "host" from config into h` / `set "p" to 80 in config` | `GetKeyStmt` / `SetKeyStmt` | CERTIFIED |
| **Objects** | Nested Objects | `say city of address of user` | Nested `PropertyAccessExpr` | CERTIFIED |
| **JSON** | Convert To/From | `convert user to json into s` / `convert s from json into o` | `ConvertToJsonStmt` / `ConvertFromJsonStmt` | CERTIFIED |
| **Dates** | Clock & Math | `d is today` / `add 1 year to d` / `year of d` | `ClockExpr` / `DateAdjustStmt` / `PropertyAccessExpr` | CERTIFIED |
| **Random** | Number & Item | `random number from 1 to 10 into n` / `random item from l into i` | `RandomNumberStmt` / `RandomItemStmt` | CERTIFIED |
| **Filesystem** | File I/O | `write "a" to p` / `read p into c` / `append "b" to p` / `delete file p` | `WriteFileStmt` / `ReadFileStmt` / `AppendFileStmt` / `DeleteFileStmt` | CERTIFIED |
| **Filesystem** | File Exists | `if file path exists` | `FileExistsExpr` | CERTIFIED |
| **Processes** | Run & Capture | `run command "cmd.exe /c echo hi" into res` | `RunStmt` (`output of res`, `exit code of res`) | CERTIFIED |
| **Processes** | Process List | `get processes into procList` | `GetProcessesStmt` | CERTIFIED |
| **System** | System Information | `get system information "os" into osInfo` | `GetSystemInfoStmt` | CERTIFIED |
| **System** | Clipboard | `copy "text" to clipboard` / `get clipboard into clip` | `CopyToClipboardStmt` / `GetClipboardStmt` | CERTIFIED |
| **System** | Environment | `get environment variable "TEMP" into t` | `GetEnvironmentVariableStmt` | CERTIFIED |


## Capabilities certified by focused production-entry suites

These are outside the 31-case smoke matrix above. Each is exercised through the
production CLI (`otter.ps1 run`) by its own suite, which is part of the D120
four-host portable suite (Windows PowerShell 5.1; PowerShell 7 on Windows, Linux
and macOS).

| Area | Capability | Canonical Otter Syntax Example | Suite | Status |
|---|---|---|---|---|
| **HTTP** | Synchronous requests (D116A) | `get "https://example.test/items" as json into data` / `post payload as json to url into response` | `tests/Http.Tests.ps1` | CERTIFIED (console and web) |
| **HTTP** | Request handles and cancellation (D116B) | `start get from url and call it req` / `on complete of req` / `cancel req` | `tests/Http.Tests.ps1` | CERTIFIED (console and web) |
| **Events** | Event sources serviced during `wait` (D121) | `wait 100 milliseconds` while a TCP, UDP, job, watcher or request event is pending | `tests/EventContract.Tests.ps1` | CERTIFIED (console) |

---

## Notes on Surface Grammar Discrepancies
During reachability auditing, several informal assumptions from other languages were tested and corrected to match Otter's authoritative grammar:
1. **Text & Math Operations**: `uppercase`, `lowercase`, `length`, `first`, `last`, `round`, `square root`, `absolute value`, etc., are right-hand expressions using the `of` operator (`uppercase of text`, `round of 3.7`), not prefix unary functions (`uppercase text` is invalid because Otter does not use prefix function call syntax for built-in operations).
2. **In-place String Replacement**: `replace <find> with <rep> in <target>` mutates `<target>` in place.
3. **Dynamic Key Access**: Key dictionary access uses `get <key> from <thing> into <var>` and `set <key> to <val> in <thing>`.
4. **JSON Conversion**: `convert <var> to json into <target>` and `convert <var> from json into <target>`.
5. **Filesystem Statements**: `write <content> to <path>`, `read <path> into <var>`, `append <content> to <path>`, `delete file <path>`, and condition `if file <path> exists`.
