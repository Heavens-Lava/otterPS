# Otter 1.0 RC — Red Team Gauntlet Report

**Mission:** Systematically discover, reproduce, classify, and resolve bugs, ambiguities, differential disagreements, escaping flaws, and edge-case failures across Otter 1.0 Release Candidate (`1.0.0-rc.1`).

**Active Period:** September 17 – October 10, 2026  
**Authoritative Reference:** `rules.md`, `SPEC-DECISIONS.md`  
**Governing Rule:** No new syntax. Semantic changes only for demonstrated bugs, contradictions, ambiguities, compiler/interpreter disagreements, data loss, or security flaws.

---

## Executive Summary

| Metric | Count |
|---|---|
| Adversarial Cases Evaluated | 20,040 |
| Genuine Defects Discovered | 9 |
| Defects Resolved & Verified | 9 |
| Open Known Issues | 0 |
| P0 (Security / Data Loss) | 0 |
| P1 (Wrong Result / Misparse / Crash) | 2 |
| P2 (Runtime Disagreement / Raw Host Exception / Injection) | 6 |
| P3 (Diagnostic / Usability Defect) | 1 |
| P4 (Performance / Hardening) | 0 |

---

## Log of Discovered Defects

### RT-001 (P2): Runtime Disagreement / Division by Zero in JS Compiler
- **Vector**: Expression Precedence & Math Parity
- **Minimal Reproducer**:
  ```otter
  x is 10 divided by 0
  say x
  ```
- **Observed Behavior**:
  - Console Interpreter: Throws `I cannot divide by zero.`
  - JS Compiler: Silently evaluated to `Infinity` without error.
- **Root Cause**: `src/Otter.Compiler.JavaScript.psm1` compiled `[MathOp]::Divide` to `(Number($left) / Number($right))` without checking for a zero denominator.
- **Resolution**: Emitted an inline IIFE verifying that the denominator is non-zero before division; throws `new Error('I cannot divide by zero.')` matching interpreter behavior.
- **Regression Test**: `tests/RedTeam.Tests.ps1` case `V2_divide_by_zero_rejection`.

### RT-002 (P2): Runtime Disagreement / Silent NaN & Boolean Coercion in JS Math
- **Vector**: Expression Precedence & Type Checking
- **Minimal Reproducer**:
  ```otter
  x is true minus 1
  y is "hello" times 5
  say x
  say y
  ```
- **Observed Behavior**:
  - Console Interpreter: Throws `I expected a number for the left side of this calculation but got true.` / `got "hello".`
  - JS Compiler: Silently converted `true` to `1` (`1 - 1 = 0`) and `"hello"` to `NaN`, propagating corrupted data silently.
- **Root Cause**: `src/Otter.Compiler.JavaScript.psm1` lacked runtime numeric assertion guards on `Subtract`, `Multiply`, `Divide`, `Percent`, and `Power`.
- **Resolution**: Added IIFE assertions matching `Assert-OtterNumber` on both operands for all math operators.
- **Regression Test**: `tests/RedTeam.Tests.ps1` cases `V2_subtract_boolean_rejection` and `V2_multiply_string_rejection`.

### RT-003 (P3): Misleading Parser Diagnostic on Unexpected Indentation
- **Vector**: Indentation & Lexer
- **Minimal Reproducer**:
  ```otter
  	x is 42
  say x
  ```
- **Observed Behavior**:
  - Parser threw: `I don't understand ''.`
- **Root Cause**: `Read-OtterStatement` in `src/Otter.Parser.psm1` fell through to `default`, formatting `$start.Text` which is empty for `Indent` tokens.
- **Resolution**: Added explicit `([TokenKind]::Indent)` and `([TokenKind]::Dedent)` branches in `src/Otter.Parser.psm1` throwing `Unexpected indentation.` with suggestion `Remove the extra space or tab at the beginning of the line.`.
- **Regression Test**: `tests/RedTeam.Tests.ps1` case `V5_unexpected_leading_indent`.

### RT-004 (P1): JS Compiler Crash on Nested Property Access & Assignment
- **Vector**: Collections & Objects / Code Generation
- **Minimal Reproducer**:
  ```otter
  address has
      city is "Tucson"
  .
  user has
      address is address
  .
  say city of address of user
  city of address of user is "Phoenix"
  say city of address of user
  ```
- **Observed Behavior**:
  - Console Interpreter: Output `Tucson` followed by `Phoenix`.
  - JS Compiler: Threw `ReferenceError: target is not defined` on both read and write. Chained property access was completely broken in JS/web targets.
- **Root Cause**: `src/Otter.Compiler.JavaScript.psm1` assumed `$Expr.Target` was always a `VariableExpr` (`$targetName = if ($target -is [VariableExpr]) { $target.Name } else { 'target' }`) and emitted `const _owner = target;`, dropping the nested expression and referencing an undefined `target` variable.
- **Resolution**: In `ConvertTo-OtterJsExpression` (read) and `ConvertTo-OtterJsStatement` (assignment), recursively evaluated `ConvertTo-OtterJsExpression -Expr $target` when `$target` is not a `VariableExpr`.
- **Regression Test**: `tests/RedTeam.Tests.ps1` case `V4_nested_property_read_and_write`.

### RT-005 (P2): Runtime Disagreement: ForEach Non-List Type Rejection & Mutation Snapshotting
- **Vector**: Collections & Loops
- **Minimal Reproducers**:
  - Case A (Non-list):
    ```otter
    text is "hello"
    each c in text
        say c
    .
    ```
    - Interpreter: Rejected with `I can only go through a list, but this is some text.`
    - JS Compiler: Silently accepted and iterated character-by-character over the string.
  - Case B (Mutation during iteration):
    ```otter
    numbers are
        1
        2
        3
    .
    total is 0
    each n in numbers
        total is total plus 1
        if total is less than 10
            add 99 to numbers
        .
    .
    say total
    ```
    - Interpreter: Output `3` (snapshotting the collection before iteration).
    - JS Compiler: Output `12` (iterating over mutated live array).
- **Root Cause**: `src/Otter.Compiler.JavaScript.psm1` emitted `for (const _item of ($collJs || []))` without validating array type or snapshotting the collection.
- **Resolution**: Emitted explicit `Array.isArray(_coll)` check throwing `I can only go through a list...` and created an explicit snapshot via `_coll.slice()`.
- **Regression Test**: `tests/RedTeam.Tests.ps1` cases `V4_foreach_non_list_rejection` and `V4_foreach_iteration_snapshotting`.

### RT-006 (P2): Runtime Disagreement: OfOperation List/String Validation
- **Vector**: Collections & Built-in Operations
- **Minimal Reproducer**:
  ```otter
  a is first of 123
  b is last of 123
  c is length of 123
  ```
- **Observed Behavior**:
  - Console Interpreter: Rejected with `Only a list has a first item, but this is a number.` / `a last item` / `I can only measure the length of a list or text, but this is a number.`.
  - JS Compiler: Silently evaluated `first of 123` and `last of 123` to `null` (`gone`), and `length of 123` to `undefined`.
- **Root Cause**: `src/Otter.Compiler.JavaScript.psm1` emitted loose ternary expressions without type assertions.
- **Resolution**: Emitted inline IIFEs validating `Array.isArray` for `First`/`Last` and `Array.isArray || typeof === 'string'` for `Length`, matching the Interpreter's type checks and error messages.
- **Regression Test**: `tests/RedTeam.Tests.ps1` cases `V4_first_of_number_rejection`, `V4_last_of_number_rejection`, and `V4_length_of_number_rejection`.

### RT-007 (P2): HTML / Script Tag Escaping & Script Context Breakout
- **Vector**: Web Compilation, UI Rendering & Escaping
- **Minimal Reproducers**:
  - Case A (JS string literals):
    ```otter
    payload is "</script><script>alert('xss')</script>"
    say payload
    ```
  - Case B (Web declarative/imperative controls):
    ```otter
    btn is a button
        text is "<script>alert(1)</script>"
    .
    ```
- **Observed Behavior**:
  - In web applications, string literals containing `</script>` broke out of the `<script>` execution tag, terminating script execution prematurely and executing injected markup in HTML context.
  - In `Render-OtterDeclarativeElementWeb` and `Render-OtterElement`, button text, input values, badges, and heading contents were interpolated raw into HTML without attribute/entity encoding.
- **Root Cause**:
  - `src/Otter.Compiler.JavaScript.psm1` lacked HTML script tag breakout escaping for string literals (`<\/script>`).
  - `src/Otter.Web.psm1` lacked HTML attribute and text encoding across web controls.
- **Resolution**:
  - In `src/Otter.Compiler.JavaScript.psm1`, escaped `(?i)</script` to `<\/script` in all string literals (valid JS that never closes an HTML `<script>` block).
  - In `src/Otter.Web.psm1`, piped all element text, label, value, and title attributes through `Escape-OtterHtmlAttr`.
- **Regression Test**: `tests/RedTeam.Tests.ps1` case `V10_script_breakout_escaped`, `tests/Web.Tests.ps1`.

### RT-008 (P1): Collection Auto-Enumeration & List Flattening in Calls and Definitions
- **Vector**: Collection Integrity & Function Parameter Passing
- **Minimal Reproducer**:
  ```otter
  to inspectItems items
      say length of items
  .
  items are empty
  inspectItems items
  ```
- **Observed Behavior**:
  - Console Interpreter: Threw `I can only measure the length of text or a list, but this is gone.` because passing an empty list resulted in `$arguments` being empty and `$arguments[0]` defaulting to `gone`.
  - Nested list definitions (`matrix are / row1 / row2 / .`) had their items automatically spliced/flattened from length 2 to length 4.
- **Root Cause**:
  - In `src/Otter.Interpreter.psm1`, `Invoke-OtterCall` and `ListDef` used `$array = @(); $array += $value`. In PowerShell 5.1, `+=` auto-enumerates any RHS collection, unrolling list arguments and nested lists.
  - In `src/Otter.Compiler.JavaScript.psm1`, `ListDef` explicitly included an `if (Array.isArray(item)) { _items.push(...item) }` branch designed to emulate the historical PowerShell `+=` unrolling bug.
- **Resolution**:
  - In `src/Otter.Interpreter.psm1`, replaced array unrolling with `[System.Collections.Generic.List[object]]::new()` and `.Add($value)` in both `Invoke-OtterCall` and `ListDef`.
  - In `src/Otter.Compiler.JavaScript.psm1`, replaced the spread operator with `_items.push($itemJs)` so that nested lists preserve their structure across both runtimes.
- **Regression Test**: `tests/RedTeam.Tests.ps1` cases `V11_empty_list_function_parameter`, `V11_populated_list_function_parameter`, and `V11_nested_list_definition_preserves_length`.

### RT-009 (P2): Raw Host CallDepthOverflowException Escape on Deep Recursion
- **Vector**: Recursion Boundaries & Stack Limit
- **Minimal Reproducer**:
  ```otter
  to infiniteLoop n
      next is n plus 1
      infiniteLoop next
  .
  infiniteLoop 1
  ```
- **Observed Behavior**:
  - The script crashed with an unhandled PowerShell/.NET runtime exception: `System.Management.Automation.RuntimeException: The script failed due to call depth overflow.`
- **Root Cause**: `src/Otter.Interpreter.psm1` had no recursion frame guard before invoking child environments.
- **Resolution**: Added a guard in `Invoke-OtterCall`: if `$script:CallStack.Count -ge 250`, throw a friendly, controlled `[OtterError]` (`Call depth limit exceeded (possible infinite recursion).`) with line number and actionable suggestion.
- **Regression Test**: `tests/RedTeam.Tests.ps1` case `V12_infinite_recursion_handled_gracefully`.

---

## Attack Batches

### Batch 1: Parser Ambiguity, Expression Precedence & Lexer Indentation Boundaries
- **Adversarial Cases:** 18
- **Results:**
  - `V1_chained_is_rejected`: PASSED (rejection confirmed)
  - `V1_and_string_plus_chain`: PASSED (both runtimes evaluated `"Otter Language"`)
  - `V1_function_call_in_math_chain`: PASSED (both runtimes agreed)
  - `V2_flat_left_to_right_precedence`: PASSED (`2 plus 3 times 4` evaluated to `20` in both runtimes)
  - `V2_divide_by_zero_rejection`: DEFECT RT-001 (fixed and verified)
  - `V2_subtract_boolean_rejection`: DEFECT RT-002 (fixed and verified)
  - `V2_multiply_string_rejection`: DEFECT RT-002 (fixed and verified)
  - `V3_parameter_shadows_outer`: PASSED (scoped shadowing isolated correctly)
  - `V3_loop_variable_scoping`: PASSED (loop variable isolated correctly)
  - `V4_out_of_bounds_list_index`: PASSED (`first of games are empty` returned `gone`)
  - `V4_missing_dynamic_key_is_gone`: PASSED (`get "age" from o into val` returned `gone`)
  - `V4_missing_property_access_throws`: PASSED (`age of o` throws `has no property called "age"`)
  - `V5_tab_indentation`: PASSED (real tab indentation works cleanly)
  - `V5_blank_lines_inside_block`: PASSED (blank lines do not break blocks)
  - `V5_comment_between_block_lines`: PASSED (comments preserve block indent)
  - `V5_unexpected_leading_indent`: DEFECT RT-003 (fixed and verified)
  - `V6_unicode_strings_and_emoji`: PASSED (multi-byte UTF-8 and emoji preserved)
  - `V6_closing_script_tag_escaping`: PASSED (`</script>` in string literals does not break web target)

### Batch 2: Deep Collections, Filesystem, Process Subsystem, Error Quality & Differential Fuzzing
- **Adversarial Cases:** 15 static cases + 100 differential runs
- **Results:**
  - `V4_nested_property_read_and_write`: DEFECT RT-004 (fixed and verified)
  - `V4_foreach_non_list_rejection`: DEFECT RT-005 (fixed and verified)
  - `V4_foreach_iteration_snapshotting`: DEFECT RT-005 (fixed and verified)
  - `V4_first_of_number_rejection`: DEFECT RT-006 (fixed and verified)
  - `V4_last_of_number_rejection`: DEFECT RT-006 (fixed and verified)
  - `V4_length_of_number_rejection`: DEFECT RT-006 (fixed and verified)
  - `V6_extended_unicode_and_combining_characters`: PASSED (CJK, mathematical script, accents preserved identically)
  - `V7_write_read_roundtrip_with_spaces_in_path`: PASSED (spaces in directory and file names round-trip cleanly)
  - `V7_read_missing_file_fails_clearly`: PASSED (explicit Otter diagnostic without host leak)
  - `V7_atomic_write_preserves_content`: PASSED (atomic replace commits cleanly)
  - `V8_command_with_spaces_and_quotes`: PASSED (captured output and exit code 0)
  - `V8_command_nonzero_exit_code`: PASSED (captured non-zero exit code cleanly without crashing)
  - `V8_nonexistent_command_rejection`: PASSED (explicit diagnostic naming missing program)
  - `V9_undefined_variable_diagnostic`: PASSED (clean diagnostic, no raw null ref)
  - `V9_unclosed_string_diagnostic`: PASSED (clean diagnostic with line/column)

### Batch 3: Scaled Gauntlet (10,000 Differential Programs & 10,000 Grammar Mutations)
- **Adversarial Cases:** 7 static cases + 10,000 seeded differential runs + 10,000 seeded grammar-aware mutations = 20,007 cases
- **Harness:** `tools/Invoke-OtterParallelGauntlet.ps1` (16 worker processes across 32 cores, total run time 228.5s).
- **Static Vector Results:**
  - `V10_script_breakout_escaped`: DEFECT RT-007 (fixed and verified)
  - `V11_empty_list_function_parameter`: DEFECT RT-008 (fixed and verified)
  - `V11_populated_list_function_parameter`: DEFECT RT-008 (fixed and verified)
  - `V11_nested_list_definition_preserves_length`: DEFECT RT-008 (fixed and verified)
  - `V11_collection_mutation_during_each`: PASSED (snapshotting isolates iteration from mutation)
  - `V12_infinite_recursion_handled_gracefully`: DEFECT RT-009 (fixed and verified)
  - `V13_deep_nested_property_chains`: PASSED (deep property chains up to depth 25 evaluated right-recursively in both runtimes)
- **Scaled Differential Execution (10,000 Programs)**:
  - 10,000 / 10,000 programs evaluated identically between Console Interpreter and Node.js VM sandbox.
  - Features exercised simultaneously: functions, nested function calls, returns, conditions, count loops, each loops, lists, list mutations, objects, nested property access, dynamic keys, strings, gone, math, comparisons, and text operations.
  - **Disagreements: 0 (100% agreement on the generated programs)**. The generated programs do not print lists, `gone`, things or JSON text, so this is not a claim of full console/web parity; see the known differences in `docs/OTTER_1_0_RELEASE_SCOPE_MATRIX.md`.
- **Scaled Grammar-Aware Mutation Fuzzing (10,000 Mutations)**:
  - 10,000 / 10,000 mutated programs handled cleanly without unhandled host exceptions.
  - Attack classes exercised: token deletion, token duplication, operator substitution, keyword substitution (`if` -> `while`, `to` -> `fn`), block terminator removal/addition, indentation corruption, malformed strings, malformed numbers, malformed property chains, malformed function calls, bare words in blocks, CRLF/LF variations, and comments at structural boundaries.
  - **Raw Host Crashes: 0 (100% safe)**.

### Batch 4: RC Hardening Pass 1 — Profiling, Soak, Adversarial Subsystems & Differential Parity
- **Adversarial Passes**:
  - **Filesystem Adversarial Suite (`tests/FilesystemAdversarial.Tests.ps1`)**: 15 / 15 passed (empty files, 0-byte files, 440KB files, Unicode/emoji paths, spaces, nested directories, read-only protection, missing parents, source==destination collisions, file locking).
  - **Process Adversarial Suite (`tests/ProcessAdversarial.Tests.ps1`)**: 11 / 11 passed (clean exit codes, missing binaries, quoted args, Unicode output, stderr/stdout separation, 50KB+ buffers, zero zombie processes).
- **Long-Run Differential Verification (`tools/Invoke-OtterDifferentialHardening.ps1`)**:
  - 1,000 / 1,000 seeded programs (Seed 20260918) evaluated with **0 disagreements** between PowerShell Interpreter and JavaScript Compiler.
  - Biased feature interactions verified: deep call chains, nested objects, property chains, `gone` checks, list mutations during iteration, math boundaries, and escaped strings.
- **Resource Soak Suite (`tools/Test-ResourceSoak.ps1`)**:
  - 8 / 8 soak workloads certified **STABLE** with zero unbounded memory growth or resource leaks across 1,000 parses, 1,000 executions, 200 web compilations, 500 file I/O cycles, 50 command runs, 500 JSON roundtrips, 5,000 function calls, and 500 error diagnostics.
- **Installation Soak Suite (`tests/InstallSoak.Tests.ps1`)**:
  - 13 / 13 checks passed across sequential install -> run -> web compile -> uninstall cycles, confirming clean disk cleanup and PATH deduplication.
- **Performance Regression Gate (`tools/Test-OtterPerformanceGate.ps1`)**:
  - 5 / 5 benchmarks certified **STABLE** within established 3.0x release variance tolerances.

---

## Certification Summary

- `tests/RedTeam.Tests.ps1`: **40 / 40** adversarial cases passed (100%).
- `tests/FilesystemAdversarial.Tests.ps1`: **15 / 15** cases passed (100%).
- `tests/ProcessAdversarial.Tests.ps1`: **11 / 11** cases passed (100%).
- `tests/InstallSoak.Tests.ps1`: **13 / 13** lifecycle checks passed (100%).
- `tools/Test-ResourceSoak.ps1`: **8 / 8** workloads certified STABLE (0 memory/handle leaks).
- `tools/Invoke-OtterDifferentialHardening.ps1`: **1,000 / 1,000** differential programs passed with **0 disagreements** (100%).
- `tools/Invoke-OtterParallelGauntlet.ps1`: **10,000 / 10,000** differential programs and **10,000 / 10,000** mutations passed with **0 disagreements** and **0 host crashes** (100%).
- `tests/Run-Tests.ps1`: **28 / 28** test suites passed (100%).
- `tools/Test-OtterReleaseConformance.ps1`: **15 / 15** release fixtures passed (100%).
- `tools/Test-DocumentationExamples.ps1`: **25 / 25** canonical examples passed (100%).
- `tests/CliContract.Tests.ps1`: **18 / 18** CLI contract tests passed (100%).
- `tests/StandardLibrary.Tests.ps1`: **31 / 31** standard library capabilities passed (100%).
- `tests/DiagnosticMatrix.Tests.ps1`: **15 / 15** diagnostic categories passed (100%).
- `tools/Test-OtterPerformanceGate.ps1`: **5 / 5** benchmarks certified within release tolerances (100%).
