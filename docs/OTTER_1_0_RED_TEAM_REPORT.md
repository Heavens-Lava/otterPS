# Otter 1.0 RC — Red Team Gauntlet Report

**Mission:** Systematically discover, reproduce, classify, and resolve bugs, ambiguities, differential disagreements, escaping flaws, and edge-case failures across Otter 1.0 Release Candidate (`1.0.0-rc.1`).

**Active Period:** September 17 – October 10, 2026  
**Authoritative Reference:** `rules.md`, `SPEC-DECISIONS.md`  
**Governing Rule:** No new syntax. Semantic changes only for demonstrated bugs, contradictions, ambiguities, compiler/interpreter disagreements, data loss, or security flaws.

---

## Executive Summary

| Metric | Count |
|---|---|
| Adversarial Cases Evaluated | 133 |
| Genuine Defects Discovered | 6 |
| Defects Resolved & Verified | 6 |
| Open Known Issues | 0 |
| P0 (Security / Data Loss) | 0 |
| P1 (Wrong Result / Misparse / Crash) | 1 |
| P2 (Runtime Disagreement / Raw Host Exception) | 4 |
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
- **Adversarial Cases:** 15 static cases + 50 differential runs + 50 mutation fuzzing runs = 115 cases
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
  - **Differential Parity Runner** (`tools/Invoke-OtterDifferentialFuzzer.ps1`): 50/50 randomly generated programs passed with 100% identical outputs.
  - **Grammar-Aware Mutation Fuzzer** (`tools/Invoke-OtterDifferentialFuzzer.ps1`): 50/50 mutated programs handled safely with 0 raw host exceptions / 0 crashes.

---

## Certification Summary

- `tests/RedTeam.Tests.ps1`: 33/33 adversarial cases passed.
- `tools/Invoke-OtterDifferentialFuzzer.ps1`: 100 iterations (50 differential + 50 mutation fuzz) passed with 0 disagreements and 0 crashes.
- `tests/Run-Tests.ps1`: 20/20 test suites passed.
- `tools/Test-OtterReleaseConformance.ps1`: 15/15 release fixtures passed.
