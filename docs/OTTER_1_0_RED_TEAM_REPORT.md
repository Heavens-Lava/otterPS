# Otter 1.0 RC — Red Team Gauntlet Report

**Mission:** Systematically discover, reproduce, classify, and resolve bugs, ambiguities, differential disagreements, escaping flaws, and edge-case failures across Otter 1.0 Release Candidate (`1.0.0-rc.1`).

**Active Period:** September 17 – October 10, 2026  
**Authoritative Reference:** `rules.md`, `SPEC-DECISIONS.md`  
**Governing Rule:** No new syntax. Semantic changes only for demonstrated bugs, contradictions, ambiguities, compiler/interpreter disagreements, data loss, or security flaws.

---

## Executive Summary

| Metric | Count |
|---|---|
| Adversarial Cases Evaluated | 18 |
| Genuine Defects Discovered | 3 |
| Defects Resolved & Verified | 3 |
| Open Known Issues | 0 |
| P0 (Security / Data Loss) | 0 |
| P1 (Wrong Result / Misparse / Crash) | 0 |
| P2 (Runtime Disagreement / Raw Host Exception) | 2 |
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
