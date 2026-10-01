# Otter native compiler — design (draft)

Status: **draft**, 2026-09-30, on `planning/1.1`. Decided by Jeff on
2026-09-30: the hybrid prerequisite model (section 2.3, option 3) and the C# 5
ceiling (section 7, decision 2). The rest is open. Nothing
here changes Otter 1.0 or its semantics. Checklist: `OTTER_1_1_CHECKLIST.md`
section 18.

## 1. What this answers, and what it does not

The question: **can the certified Otter implementation compile its own programs
efficiently?** The compiler is a second *backend* inside `otterPS`: it reuses
Otter's lexer, parser and AST, and the PowerShell interpreter stays the
semantic reference ("oracle"). Every compiled program must behave exactly as
the interpreter does.

It is not a new implementation of the language, and it is separate from Jeff's
own C# implementation in `..\otter\`, which this work does not read, change or
depend on. Whether that project becomes Otter's architecture later is a
separate decision, taken after this one proves itself.

The compiled backend is **experimental in 1.1** and cannot block the 1.1
release.

Why it is worth doing, measured on this machine
(`benchmarks/results/baseline-1.0-c404ef8.json`): the interpreter runs about
1,000-1,700 Otter statements per second, so `benchmarks/arithmetic.ot` (a
400-pass loop) takes about 1,600 ms. The same loop translated by hand into the
C# a compiler would generate runs in 0.002-0.004 ms once compiled, and prints
the same total (84400). Real generated code will be much slower than that
hand translation: it has to carry Otter's values, formatting, errors and line
numbers through a runtime library. But the headroom is several orders of
magnitude.

## 2. First decision: what users must have installed

Otter 1.0 needs nothing but PowerShell (Windows PowerShell 5.1 built into
Windows; PowerShell 7 on macOS and Linux). The compiler must not quietly break
that promise, so its prerequisites are decided before anything else.

### 2.1 What each PowerShell can do with nothing installed

Measured with `experiments/native-compiler/Measure-Toolchains.ps1`:

| | Windows PowerShell 5.1 (.NET Framework 4.8) | PowerShell 7.4 (.NET 8, Linux) | PowerShell 7.5 (.NET 9, Linux) |
|---|---|---|---|
| C# through `Add-Type` | **C# 5 only** (async/await yes; string interpolation, expression bodies, tuples and later: no) | C# 11 and earlier (all probes) | C# 11 and earlier (all probes) |
| Compile in memory | yes | yes | yes |
| Write a library (`-OutputAssembly`) | yes, a `.dll` | yes, a `.dll` | yes, a `.dll` |
| Write an executable (`-OutputType ConsoleApplication`) | **yes: a .NET Framework `.exe` that runs on its own on any Windows 10/11** | **no** ("not currently supported") | **no** |
| Emit IL in memory (`Reflection.Emit`) | yes | yes | yes |
| Save emitted IL to disk | yes (`AssemblyBuilderAccess.RunAndSave`) | **no** | yes (`PersistedAssemblyBuilder`) |
| Cold compile of the arithmetic benchmark | 110 ms | 45 ms | 50 ms |
| Compiled benchmark, per run | 0.0016 ms | 0.0023 ms | 0.0044 ms |

The macOS CI hosts run PowerShell 7.5 and 7.6 (.NET 9 and 10), so they match
the 7.5 column; that is inferred from the .NET version, not measured on a Mac.

Two facts shape everything below:

- **Windows PowerShell 5.1 compiles only C# 5.** Any C# the compiler emits,
  and any C# runtime library it ships as source, must stay within C# 5 if the
  backend is to work on Windows' built-in PowerShell. PowerShell 7 accepts
  that subset too.
- **Only Windows PowerShell 5.1 can produce an executable without an SDK.**
  PowerShell 7 can compile in memory or to a `.dll`, not to an `.exe`.

### 2.2 The .NET SDK

Measured with `experiments/native-compiler/Measure-DotnetSdk.ps1` (the same
benchmark as a console project):

| Output | Windows, .NET 10 SDK | Linux, .NET 9 SDK |
|---|---|---|
| Framework-dependent executable (needs the .NET runtime installed) | 0.2 MB; build 4.2 s cold, 0.8 s warm | 0.1 MB; build 2.6 s cold, 0.8 s warm |
| Self-contained single file (needs nothing) | 70 MB; build 4.0 s | 68 MB; build 5.9 s |
| Native AOT | **failed**: the native link step needs the Visual Studio C++ tools set up correctly (`vswhere`/`link.exe`), even with Visual Studio installed | **failed** without `clang`/`gcc`; with `clang` and `zlib`: 3.7 MB, starts in 3 ms |

The SDK is a large separate install (hundreds of MB), and true native
executables add a platform C++ toolchain on top.

### 2.3 The three options

1. **In-process compilation with nothing to install.** `otter run` compiles a
   program's C# with `Add-Type` inside the PowerShell already running Otter,
   caches the compiled `.dll` by source hash, and runs it. Works on Windows
   PowerShell 5.1 and PowerShell 7 everywhere. Costs 45-110 ms per compile (once
   per program change, with a cache). Does not help startup time (PowerShell and
   Otter's modules still load, 0.9-1.4 s), and produces no standalone
   executable, except that Windows PowerShell 5.1 can write a .NET Framework
   `.exe`.
2. **.NET SDK compilation to executables.** `otter build` emits a C# project
   and runs `dotnet publish`. Gives real executables, including 3 ms native
   start with Native AOT, but makes the SDK (and for AOT a C++ toolchain) a
   requirement, which Otter 1.0 never had.
3. **Hybrid.** Accelerated execution (option 1) needs nothing extra and is the
   default path for `otter run`. Executable publishing is optional: it uses the
   SDK (option 2) when present, and says clearly what to install when it is
   not. On Windows PowerShell 5.1, a framework `.exe` without an SDK is a
   possible extra.

**Recommendation: option 3 (hybrid).** It keeps 1.0's "nothing extra to
install" promise for everyone who only wants programs to run faster, and puts
the SDK where it earns its size: producing standalone programs. It also lets
the first prototype (section 6) use option 1 alone.

## 3. Generated C# versus direct IL

| | Generated C# (Roslyn / CodeDom via `Add-Type`) | Direct IL (`Reflection.Emit`) |
|---|---|---|
| Inspectable | yes: the generated file can be read, diffed and committed as a test expectation | no: IL has to be disassembled |
| Debuggable | yes: ordinary C# debugging; `#line` directives can map back to `.ot` lines | hard |
| Correctness risk | low: the C# compiler type-checks what we emit | high: invalid IL fails at run time or not at all |
| Works with nothing installed | yes on 5.1 (C# 5) and 7.x | yes in memory everywhere; saving needs 5.1 or 7.5+ |
| Compile cost | 45-110 ms per program (measured) | lower, not measured |
| Language ceiling | C# 5 on Windows PowerShell 5.1 | none, but everything is hand-written |
| Reviewable by agents and people | yes | poorly |

**Presumption: generated C# (C# 5 subset) for the first prototype.** It is
inspectable and far easier to validate, and its one measurable cost (compile
time) is paid once per program change. IL stays a later option if compile time
ever matters more than reviewability. This is not frozen until the prototype
records compile times and correctness on real programs.

## 4. Architecture

```text
.ot source
  -> lexer, parser (Codex's, unchanged)        -> AST (frozen contract)
  -> existing checks (D124 reserved words, D122 module paths, loop passes D130)
  -> lowering: AST -> C# 5 source                (new: src/Otter.Compiler.Native.psm1)
  -> compile: Add-Type (cached .dll)  | dotnet publish (optional, executables)
  -> run against the Otter runtime library        (new: C# 5 source, compiled once)
```

- **No grammar fork.** The compiler consumes the same AST; there is no
  compiler-only syntax and no contract change.
- **The runtime library holds Otter's semantics in C#:** values (numbers are
  doubles, text, booleans, `gone`, lists, things, types), `say` formatting
  (D8, D126), truthiness (D9), equality, `add`/`remove` dispatch (D12), the
  `and`/`is` rules as the parser already resolved them, loop passes (D130),
  and Otter errors with their line numbers and wording (D14). Generated code
  calls this library rather than raw .NET where the two differ (for example
  number formatting and culture).
- **Host capabilities** (files, HTTP, processes, UI) are reached through the
  same boundaries the interpreter uses. For the prototype, a program that uses
  anything the compiled backend does not support yet is refused at compile
  time with a clear message; it never silently falls back or half-runs.
- **Source mapping:** every generated statement carries its `.ot` line
  (`#line` directives plus the runtime's own line tracking), so errors report
  the Otter line, as the interpreter does.
- **Caching:** compiled `.dll`s are keyed by a hash of the source, the Otter
  version and the backend version; a cache miss recompiles.
- **Security:** Otter text becomes C# string literals, so escaping is a
  security boundary (generated-code injection); it gets its own test corpus
  (checklist section 20).

## 5. Testing against the reference

No parallel test system. The native backend becomes another implementation in
the infrastructure that already compares implementations:

- **Conformance fixtures** (`conformance/manifest.json`,
  `tools/Test-OtterReleaseConformance.ps1`): each fixture records expected
  output, exit code and diagnostics through the production entry point. Add a
  backend dimension: every fixture the compiled backend supports runs through
  it too, with the same expectations. Fixtures it does not support are listed
  as "not yet", never skipped silently.
- **Differential fuzzer** (`tools/Invoke-OtterDifferentialFuzzer.ps1`):
  already generates random programs and compares the interpreter with the
  JavaScript backend. Add the native backend as a third implementation of the
  same programs; any disagreement is a failure, and the program joins the
  permanent regression corpus.
- **Benchmarks** (`tools/Invoke-OtterBenchmarks.ps1`): add a backend switch so
  every benchmark reports interpreter and compiled times side by side from the
  same recorded run.
- The interpreter stays the oracle: when the two disagree, the compiled
  backend is wrong unless a D-number says otherwise.

## 6. Recommended first prototype

Option 1 (in-process), generated C# 5, the smallest useful subset:

- `say`, variables, numbers, text, booleans, `gone`;
- arithmetic and comparisons, `if` / `otherwise`;
- `count`, `repeat`, `while`, `for each` / `each`;
- functions with parameters and `return`, recursion;
- lists with `add`, `remove`, `contains`, `length of`;
- Otter errors with line numbers (division by zero, unknown variable).

Done when:

1. The benchmark programs in that subset (`arithmetic`, `loops`,
   `function_calls`, `recursion`, `lists`, `contains_*`) produce the
   interpreter's exact output compiled, on Windows PowerShell 5.1 and
   PowerShell 7.
2. The conformance fixtures in the subset pass through the compiled backend.
3. The differential fuzzer runs its generated programs through the compiled
   backend with zero disagreements.
4. The benchmark runner reports interpreter and compiled times side by side.

The prototype lives in `src/Otter.Compiler.Native.psm1` (back-end agent) and
`experiments/native-compiler/`; it is reached only through an explicitly
experimental entry point whose name is part of the 1.1 CLI decision. It does
not change `otter run`'s default, the interpreter, or any 1.0 behaviour.

## 6a. Prototype status (2026-10-01, branch `native/prototype`)

The first prototype meets all four done criteria in section 6:

1. **Benchmarks.** `arithmetic`, `contains_300`, `contains_5000`,
   `function_calls`, `loops` and `recursion` print the interpreter's exact
   output compiled, on Windows PowerShell 5.1 and on PowerShell 7.4 (Linux).
2. **Conformance.** Every console "run" fixture in the compiled subset passes
   against the manifest's own expectations: `hello`, `variables-control-flow`,
   `function-return-expression`, `boolean-and-negative` (4 pass, 0 fail; 6 not
   compiled yet: `try`, `sort`, types, JSON, the clock, HTTP;
   `experiments/native-compiler/Test-NativeConformance.ps1`).
3. **Differential fuzzer.** `tools/Invoke-OtterDifferentialFuzzer.ps1
   -IncludeNative`, 1,000 programs: 1,000 matched the interpreter, 0 disagreed,
   0 not compiled.
4. **Benchmarks side by side.** `tools/Invoke-OtterBenchmarks.ps1 -Native`
   checks the compiled output against the interpreter, then times both
   (`benchmarks/results/native-prototype-1.json`): the compiled programs run
   480x to 1,700x faster than the interpreter (0.5-0.9 ms against 0.26-1.5 s),
   after a 100-350 ms compile that is cached per program.

Edge cases and errors: 10 programs in `experiments/native-compiler/cases`
(division by zero, unknown names, argument counts, the 250-call limit, text in
arithmetic, `for each` over a non-list, a top-level `stop`, and more) match the
interpreter's message, line, suggestion and exit code.

Subset compiled today: `say`, variables, numbers, text, booleans, `gone`,
arithmetic, comparisons, `and`/`or`/`not`, `if`, `count`, `repeat`, `while`,
`for each`, functions, `return`, recursion, lists (`add`, `remove`,
`contains`, `length`/`first`/`last of`, `sort`, `reverse`), things and custom
types (`has`, `a Person has`, property read and write, `get ... from ...
into`), `try`/`fail with`, text and math operations, JSON, files and dates
(`docs/NATIVE_COMPILER_COVERAGE.md`: 47 of 225 node kinds, 3 partly).

Library bridge: JSON and file statements call the interpreter's own
PowerShell functions (`Otter.Library.psm1`) through one delegate, so their
behaviour and messages are the interpreter's by construction; values are
converted at the boundary. Dates are mirrored in the runtime library instead,
because a date value has to work in formatting, equality, comparison and
property access everywhere. Library-bound programs gain little (file I/O
1.3x, JSON 2.2x): the time is in the library, not the language.

11 of the 12 benchmarks compile and match on both PowerShells;
`event_dispatch` (UDP) is still refused. Conformance: 6 pass, 0 fail, 4 not
compiled yet.

Findings: importing `Otter.Interpreter.psm1` turns a script's `exit N` into
exit code 0 (`otter.ps1` uses `[Environment]::Exit`); `Add-Type` on Windows
PowerShell 5.1 treats warnings as errors; on PowerShell 7, `Add-Type
-ReferencedAssemblies` drops the default references, so the generated code
names no collection types.

## 7. Decisions that need Jeff

1. **Prerequisite model: decided 2026-09-30, option 3 (hybrid).** Accelerated
   runs need nothing beyond PowerShell; executable publishing is optional and
   uses the .NET SDK when present.
2. **C# 5 ceiling: decided 2026-09-30.** Generated code and the runtime library
   stay within C# 5, so the compiled backend works on Windows PowerShell 5.1 and
   PowerShell 7 alike.
3. **Experimental entry point:** how the prototype is reached (an `otter run`
   option or a separate command) - part of the 1.1 CLI surface.
4. **Executables:** whether 1.1 offers executable publishing at all, and if so
   framework-dependent (small, needs the .NET runtime), self-contained (about
   70 MB, needs nothing) or Native AOT (small and instant, needs a C++
   toolchain to build).
5. **Ownership:** the lowering module and runtime library are back-end work;
   nothing in the plan changes Codex's lexer or parser. Confirm that split.

## 8. Evidence

- `experiments/native-compiler/Measure-Toolchains.ps1` - run on Windows
  PowerShell 5.1.26100 (.NET Framework 4.8.9325), PowerShell 7.4.2 (.NET 8.0.4,
  Ubuntu 22.04, `mcr.microsoft.com/powershell`) and PowerShell 7.5.11 (.NET
  9.0.20, Debian 12, `mcr.microsoft.com/dotnet/sdk:9.0`), 2026-09-30.
- `experiments/native-compiler/Measure-DotnetSdk.ps1` - run with .NET SDK
  10.0.100 on Windows 11 and .NET SDK 9.0.318 on Debian 12 (with and without
  `clang`), 2026-09-30.
- Interpreter baseline: `benchmarks/results/baseline-1.0-c404ef8.json` (on
  `perf/benchmark-suite`).
