# Otter Optimization Policy That Preserves Semantics

## 1. Core Mandate: Correctness Over Speed

In the Otter programming language platform, **observable language semantics are immutable**. No optimization—whether in the PowerShell interpreter, the JavaScript web compiler, or the experimental 1.1 native C# compiler—is permitted to alter language semantics, relax precision, suppress error checks, or degrade diagnostic quality for the sake of execution speed.

If an optimization cannot be proven to preserve 100% semantic equivalence across all valid inputs and error conditions, it is rejected or reverted immediately.

---

## 2. Invariants That Must Be Preserved

Every optimization must strictly maintain the following invariants:

### 2.1 Observable Value Equivalence
- **Numeric Precision:** Otter numbers are 64-bit IEEE 754 floating point (`double`). Integer operations must not overflow to alternative types or truncate decimals unless explicitly converted by language operators (`round`, `round up`, `round down`).
- **Equality Semantics (D2, rules.md):** Equality (`is`, `is not`, `contains`, `find`, `remove`) must maintain exact rules across the entire value matrix:
  - Numbers and numeric text: `"5"` equals `5`, and `"5.0"` equals `"5"`.
  - Collections: Deep value equality for lists and nested lists.
  - Nothing (`gone`): Only equal to `gone` / `$null`.
  - Objects (`thing`): Reference and property value semantics.
  - Dates & Bytes: Value equality based on underlying date/time and byte sequence.
- **Collection Preservation:** Array unwrapping or pipeline flattening in PowerShell must never accidentally collapse single-element lists, empty lists, or nested collections.

### 2.2 Diagnostic and Error Parity (D14)
- **Error Fidelity:** Every error raised must be an `OtterError` containing:
  - Exact error message text (e.g., `"I can't divide by zero."`).
  - Real source line number (`.Line`).
  - Source text snippet (`.SourceLine`).
  - Friendly suggestion (`.Suggestion`).
- **No Raw Host Crashes:** Unoptimized paths and optimized fast paths must trap internal exceptions and translate them to human-readable Otter diagnostics. Host-level exceptions (.NET or JavaScript) must never escape to the end user.

### 2.3 Cross-Target Parity
- Otter code compiled for the web (`otter web`), interpreted in PowerShell (`otter run`), or compiled natively (`Invoke-OtterCompiled.ps1`) must produce identical outputs for all supported standard library operations.

---

## 3. Classification of Optimizations

### 3.1 Permitted Optimizations
- **Type-Specialized Fast Paths:** Checking the runtime type up front (e.g., checking if both operands are already `[double]` in `Test-OtterEqual` or `Assert-OtterNumber`) to bypass general-purpose dynamic coercion routines when types are homogeneous.
- **Pipeline Unwrapping Bypass:** Skipping `Write-Output -NoEnumerate` for scalar values (numbers, strings, booleans) while preserving it for collections.
- **AST Lowering & Native Inlining:** Compiling AST nodes directly to typed IL or C# statements without dynamic AST visitor overhead.
- **Event Loop Batching:** Non-blocking draining of queued I/O events while respecting cooperative yielding and task scheduling.
- **Lookup Caching:** Memoizing immutable module paths, regex instances, and syntax maps.

### 3.2 Forbidden Optimizations
- **Fast Math with Precision Loss:** Reordering floating-point operations in ways that alter precision or rounding behavior.
- **Skipping Runtime Bounds Checks:** Omitting collection bounds or division-by-zero checks.
- **Error Message Alterations:** Simplifying or genericizing error messages to avoid string formatting overhead.
- **Silent Coercion Bypasses:** Skipping string-to-number checks when comparing string variables with numbers.
- **Benchmark-Specific Special Cases:** Adding shortcuts or heuristics that detect benchmark source code or specific variable names.

---

## 4. The 5-Gate Verification Lifecycle

Before any optimization is committed or merged, it must pass through all five validation gates:

```
[ Optimization Proposal ]
           │
           ▼
[ Gate 1: Baseline Profile ] ──> Profile with tools/Invoke-OtterBenchmarks.ps1
           │
           ▼
[ Gate 2: Golden Grid Tests ] ─> tests/Optimizations.Tests.ps1 (46-value matrix)
           │
           ▼
[ Gate 3: Full Platform Suite ] -> tests/Run-Tests.ps1 (all 63 suites pass)
           │
           ▼
[ Gate 4: Differential Parity ] -> tools/Invoke-DifferentialFuzzer.ps1 (0 discrepancies)
           │
           ▼
[ Gate 5: Performance Gate ] ───> tools/Test-OtterPerformanceGate.ps1 (certified)
           │
           ▼
    [ Commit & Merge ]
```

### Gate 1: Baseline Profile
Measure execution duration, statement throughput, and memory consumption using `tools/Invoke-OtterBenchmarks.ps1` before and after the change. Verify that the improvement is statistically significant and not noise.

### Gate 2: Golden Value Grid Tests (`tests/Optimizations.Tests.ps1`)
The optimization must pass the 46-value golden grid test, covering:
- Integers, doubles, negative zero, infinity, NaN, 64-bit integers.
- String representations of integers, decimals, empty strings.
- Booleans, `gone`, empty lists, nested lists, custom types, dates, and bytes.
- Exact error messages, error kinds, and error line numbers for invalid operations.

### Gate 3: Full Platform Regression Suite (`tests/Run-Tests.ps1`)
Every one of the 63 test suites in the Otter platform must pass with 0 failures.

### Gate 4: Differential Parity & Fuzzing
Run differential testing between the interpreter and compiler targets. 1,000+ generated programs must produce identical outputs on both targets with 0 discrepancies.

### Gate 5: Performance Regression Gate (`tools/Test-OtterPerformanceGate.ps1`)
Verify that the change does not introduce regressions in unrelated workloads, conforming to the thresholds defined in `docs/PERFORMANCE_REGRESSION_GATE.md`.

---

## 5. Applied Optimizations Reference

The platform has successfully applied the following optimizations under this policy:

| Optimization | Target | Mechanism | Performance Gain | Verification |
|---|---|---|---|---|
| **OPT-1** | `Test-OtterEqual` | Fast path for two `[double]`/`[int]`/`[long]` operands | 80% reduction in `contains` time on 300-item lists | `tests/Optimizations.Tests.ps1` |
| **OPT-2** | `Assert-OtterNumber` | Fast path for `[double]` in arithmetic and ordering | 25-30% faster arithmetic expressions | `tests/Optimizations.Tests.ps1` |
| **OPT-3** | `Get-OtterValue` | Direct return of scalar values, skipping pipeline unwrapping | 40 us saved per scalar variable read | `tests/Optimizations.Tests.ps1` |
| **Direct Return** | `Invoke-OtterCall` | Return statement fast path bypassing exception throw | 0.5 ms saved per function return | `tests/Profiler.Tests.ps1` |
| **Native Lowering** | `Otter.Compiler.Native` | Direct C# compilation of AST nodes with typed runtime | 300x–2,400x speedup across benchmark suite | `tools/Invoke-OtterBenchmarks.ps1 -Native` |
