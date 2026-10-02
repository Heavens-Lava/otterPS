# Otter 1.1 Master Checklist & Planning Ledger

**Status:** Draft / Active Planning  
**Branch:** `planning/1.1`  
**Semantic Oracle:** Windows PowerShell 5.1 Interpreter (`otter.ps1`) remains the normative reference implementation.  
**Rule:** No silent semantic drift. All new compiler or language behaviors are verified against the differential test harness.

---

## 1. Release Rules for Otter 1.1

1. **Semantic Parity**: The PowerShell reference implementation is the authoritative semantic oracle. Any behavior differences between the interpreter, JavaScript compiler, and C# native compiler must be caught by differential testing.
2. **Zero-Install Principle**: The compiler pipeline must provide a zero-extra-install option on Windows using PowerShell's built-in C# compilation (`Add-Type` / in-memory Roslyn) without forcing users to install the heavy .NET SDK for ordinary speedups.
3. **Experimental Isolation**: The C# native compiler is maintained as an experimental backend pipeline so that ongoing compiler optimization cannot hold up 1.1 release deliverables.
4. **Flagship Alignment**: OtterBoard serves as the primary desktop & web showcase application proving UI lifecycle, styling, state management, and the D56 declarative actions (`hide`, `show`, `focus`, `clear`).

---

## 2. Decision Ledger & Reconciled 1.1 Scope

### 2.1 Flagship Showcase & UI Operations (D56)
- [ ] **OtterBoard Showcase Application**:
  - [x] Base project structure and domain models (`projects/OtterBoard/`)
  - [x] Initial dashboard, sidebar navigation, stat cards, task management, activity feed, and persistence
  - [ ] Implement declarative UI actions: `focus <control>`, `clear <control>`, `hide <control>`, `show <control>` on Console, Desktop, and Web
  - [ ] Support OtterBoard Proposals P1, P2, P8, P9 (UI state persistence, theme switching, responsive panel collapse, search filtering)
  - [ ] Reconcile Proposals P3–P6 with Codex (advanced list virtualization, drag-and-drop kanban cards, dialog modal stacks)

### 2.2 Native C# Compiler (Experimental Speedup)
- [ ] **Section 17.1 Compiler Architecture & Design**:
  - [x] Compiler design specification (`docs/OTTER_1_1_COMPILER_DESIGN.md`)
  - [ ] C# Code Generator Module (`src/Otter.Compiler.CSharp.psm1`)
  - [ ] In-Memory Execution via `Add-Type` (Zero-install Windows path)
  - [ ] Executable Export via `.NET SDK` (`dotnet build` / standalone `.exe` when SDK is present)
  - [ ] Integration into differential test harness (`tools/Test-OtterReleaseConformance.ps1`)

### 2.3 Benchmark Baselines & Hardening (Completed / In Progress)
- [x] 1.0 Benchmark Baseline recorded (~1,300 stmts/sec on PS 5.1 reference interpreter)
- [x] Long-running resource soak tests
- [x] 4-Host testing matrix (Windows PS5.1, Windows PS7, Linux PS7, macOS PS7)
- [ ] Differential fuzz testing across Interpreter, JS Web target, and C# native compiler (1,000+ programs)

---

## 3. Otter 1.1 Feature & Subsystem Gates

| Subsystem | Scope / Capability | Target Deliverable | Status |
|---|---|---|---|
| **Compiler** | Otter AST -> C# Source Generator | `src/Otter.Compiler.CSharp.psm1` | Planned |
| **Compiler** | In-Memory Compilation (`Add-Type`) | `otter run -Compile script.ot` | Planned |
| **Compiler** | Standalone Executable Packaging | `otter compile script.ot -Out app.exe` | Experimental |
| **UI Lifecycle** | Declarative Actions (`focus`, `clear`, `hide`, `show`) | WPF Desktop + Web DOM | In Progress |
| **Query Engine** | Embedded LINQ-style queries | `src/Otter.Runtime.psm1` | Planned |
| **Permissions** | Runtime permission boundaries & sandbox | Studio card + CLI guard | In Progress |
| **OtterBoard** | Flagship Desktop Showcase | `projects/OtterBoard` | Active |
