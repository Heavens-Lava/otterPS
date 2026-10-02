# Otter 1.1 Compiler Architecture & Design (Section 17.1)

**Status:** Design Proposal & Architecture  
**Target:** Otter 1.1 Experimental Native Pipeline  
**Module Target:** `src/Otter.Compiler.CSharp.psm1`  
**Semantic Reference:** PowerShell 5.1 Interpreter (`src/Otter.Interpreter.psm1`)

---

## 1. The Core Dilemma: Installation Prerequisites vs. True Native Binaries

Otter 1.0 promises **zero extra installation** on stock Windows machines. Introducing a C# compilation backend must respect this promise while allowing high-performance execution.

### 1.1 The Two-Tier Compilation Strategy

```
                          Otter Source (.ot)
                                  │
                                  ▼  ConvertTo-OtterTokens (Lexer)
                              Token[]
                                  │
                                  ▼  ConvertTo-OtterAst (Parser)
                             ProgramNode (AST)
                                  │
                                  ▼  Export-OtterCSharp (src/Otter.Compiler.CSharp.psm1)
                              C# Source Text
                                  │
        ┌─────────────────────────┴─────────────────────────┐
        ▼                                                   ▼
Tier 1: In-Memory Roslyn (Default)                 Tier 2: .NET SDK (Optional)
• Uses PowerShell `Add-Type`                       • Uses `dotnet build` / Native AOT
• Zero extra installs needed on Windows            • Produces standalone `.exe`
• Fast compilation (~100-200ms)                    • Maximum optimization & distribution
• Runs in-process via compiled assembly            • Requires .NET 8/9 SDK installed
```

1. **Tier 1 — Zero-Install In-Memory Compilation (`Add-Type`) [Default]**:
   - Compiles generated C# directly into memory using PowerShell's built-in `Add-Type -TypeDefinition $csharpSource -Language CSharp`.
   - Requires **nothing extra installed** on Windows 10/11 (uses the framework compiler in Windows PowerShell 5.1 and Roslyn in PS 7).
   - Yields 50x–200x speedups over the AST tree-walking interpreter.
   - Command: `otter run -Compile file.ot` (or `otter compile -Run file.ot`).

2. **Tier 2 — Standalone Executable Packaging (`dotnet` / Native AOT) [Optional]**:
   - Generates a standalone `.csproj` and uses the local `.NET SDK` if present on the developer's machine.
   - Compiles into a single self-contained executable (`.exe` or ELF/Mach-O) with optional Native AOT.
   - If `dotnet` is not found on PATH, Otter reports a friendly diagnostic:
     `"Otter: Standalone .exe compilation requires the .NET SDK. For zero-install execution, use 'otter run -Compile'."`
   - Command: `otter compile file.ot -Out app.exe`.

---

## 2. Code Generation Strategy: C# Source vs. Direct IL

Generating **C# source text** from the Otter AST is chosen over direct IL emission (`Reflection.Emit`) for three key reasons:
1. **Debuggability & Auditing**: Generated C# can be written to disk, inspected by developers, and debugged using standard C# tools.
2. **Maintenance & Safety**: Direct IL emission is fragile and complex to maintain across PowerShell 5.1 / .NET Framework and .NET Core / .NET 8.
3. **Compiler Optimization**: Roslyn / RyuJIT perform sophisticated dead-code elimination, loop vectorization, and inlining on C# code that manual IL generation would miss.

---

## 3. AST Mapping & C# Runtime Bridge

The generated C# source imports a minimal runtime header (`OtterRuntime.cs`) implementing Otter value semantics:
- `OtterValue` / dynamic object representation.
- Otter arithmetic (`and` as addition, `minus`, `times`, `divided by`).
- Otter collections (lists, sets, dictionaries) and slicing.
- Control flow (`if`, `otherwise`, `while`, `repeat`, `count from ... to ... as ...`, `for each`).
- I/O and standard library primitives (`say`, `ask`, filesystem, JSON).

### Example AST Transformation

**Otter Source:**
```otter
count from 1 to 1000000 as i
    if i percent of 2 is 0
        total is total and i
    .
.
say total
```

**Generated C#:**
```csharp
using System;
using System.Collections.Generic;

namespace OtterCompiled {
    public static class Program {
        public static void Main(string[] args) {
            double total = 0;
            for (double i = 1; i <= 1000000; i++) {
                if ((i % 2) == 0) {
                    total = total + i;
                }
            }
            Console.WriteLine(total);
        }
    }
}
```

---

## 4. Differential Test Harness Integration

The C# compiler backend directly hooks into the existing **1,000-program differential fuzz test suite** (`tools/Test-OtterReleaseConformance.ps1`):

```
                   Fuzz / Golden Test Program (.ot)
                                  │
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
[ Reference Interpreter ]   [ JS Web Target ]    [ C# Native Compiler ]
   (Windows PS 5.1)         (Node/Headless)      (Add-Type / In-Memory)
         │                        │                        │
         ▼                        ▼                        ▼
     stdout A                 stdout B                 stdout C
         └────────────────────────┼────────────────────────┘
                                  ▼
                     Assert-Equal(A, B, C)
```

If stdout or exit code diverges between the PowerShell reference interpreter and the compiled C# executable on any program, the differential fuzzer flags a regression immediately.

---

## 5. Performance Targets & Milestones

| Milestone | Execution Engine | Target Performance | Status |
|---|---|---|---|
| **Otter 1.0 Baseline** | PowerShell 5.1 Interpreter | ~1,300 stmts/sec | **Baseline Established** |
| **Otter 1.1 Target** | In-Memory Compiled C# (`Add-Type`) | **100,000+ stmts/sec (75x–150x)** | Target |
| **Otter 1.1 Peak** | Standalone Compiled Native AOT | **500,000+ stmts/sec (300x+)** | Experimental |
