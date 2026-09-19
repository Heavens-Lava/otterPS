# D60 — Windows / .NET Interoperability Architecture & Exhaustive Capability Inventory

## Executive Summary

This document establishes the architectural foundation for the **Otter 1.0 Expansion**, transitioning Otter from a promising proof-of-concept into a serious, unconstrained language for Windows console, shell, and native desktop development.

Per Jeff's architectural guidance:
1. **`VERSION` remains `0.2.0-dev`**: 1.0.0-rc.1 is deferred until the expanded Windows, Shell, and Desktop capabilities are built, unified, and certified.
2. **D59 is ratified as "Baseline Documentation Certification"**: Existing documentation surfaces pass 100% and provide the baseline for expansion.
3. **The Two-Layer Property Philosophy**:
   - **Layer 1 (Friendly Layer)**: High-level, beautiful, provider-neutral Otter vocabulary (`opacity`, `size`, `bold`, `border`, `round`, `visible`, `tooltip`, etc.) that compiles cleanly to both WPF and Web.
   - **Layer 2 (Native Escape Hatch)**: Explicit, controlled access to underlying WPF DependencyProperties, attached properties, enums, and .NET objects, guaranteeing that developers never hit an artificial capability ceiling.
4. **Strict Encapsulation Invariant (D43)**: All WPF types and reflection (`System.Windows.*`) remain strictly isolated inside `src/Otter.UI.psm1`. No other module or contract file may reference WPF types.

---

## 1. What Can Otter Do Today? (Exhaustive Inventory)

An audit of all modules in `src/` (`Otter.Runtime.psm1`, `Otter.Library.psm1`, `Otter.UI.psm1`, `Otter.Interpreter.psm1`, `Otter.Web.psm1`, `Otter.Server.psm1`, and `Otter.Contract.psm1`) reveals the following current capability baseline:

### 1.1 Core Language & Type System
- **Types**: Text (`string`), Number (`double`), Boolean (`bool`), `gone` (sentinel null/absence), Lists (`List[object]`), Objects (`OtterObject` for schema-less dictionaries or typed definitions), Dates (`OtterDate` with/without time).
- **Expressions & Operators**:
  - Arithmetic: `and` (addition in `make`), `plus`, `minus`, `times`, `divided by`.
  - Comparisons: `is`, `is not`, `is greater than`, `is less than`, `is at least`, `is at most`.
  - Text testing: `starts with`, `ends with`, `contains`.
  - Logic: `not`, `and`, `or` (precedence: `not` > `and` > `or`).
- **Control Flow**:
  - `if / otherwise / otherwise if` with block terminator `.`.
  - Continued conditions (D38B trailing connective): `if a is 1 and \n b is 2`.
  - `while <condition>`, `repeat N times`, `count from X to Y as N`, `for each item in list`.
  - `try ... otherwise ...` error recovery.
- **Functions**: `to <name> <params> ... return <val> .`, invoked via `<fn> <args> make <result>`.
- **String & List Library**:
  - Strings: `length of`, `uppercase of`, `lowercase of`, `replace <find> with <rep> in <var>`, `split <str> by <sep> into <var>`, `join <list> with <sep> into <var>`.
  - Lists: `first of`, `last of`, `length of`, `add <item> to <list>`, `remove <item> from <list>`, `sort <list>`, `reverse <list>`, `find <item> in <list> where <condition> into <var>`.
- **Dates & Math**:
  - `today`, `now`.
  - `add N days/months/years to <date>`, `days between <d1> and <d2> make <n>`, `format date as <fmt> into <str>`.
  - `random number from X to Y into N`, `random item from <list> into <var>`.

### 1.2 System, File System & External Process Execution
- **File System Operations**:
  - `read <file> into <var>`, `write <content> to <file>`.
  - `copy <file> to <dest>`, `move <file> to <dest>`, `delete file <file>`.
  - `if file <file> exists`.
  - `get files in <folder> [and subfolders] into <files>` (returns list of `file` objects with `name`, `path`, `extension`, `size`, `created`, `modified`).
  - `create folder <path>`, `delete folder <path>`, `copy folder <src> to <dst>`, `move folder <src> to <dst>`, `get folders in <folder> [and subfolders] into <folders>`.
- **JSON Serialization**:
  - `read json from <file> into <var>`.
  - `convert <obj> to json into <str>`.
  - `convert <str> from json into <var>`.
- **Process & Shell Execution**:
  - `run <target>` (e.g. `run "notepad.exe"`) launches external process asynchronously via `Start-Process`.
  - `run command <cmd> into <var>` (e.g. `run command "git status" into result`) executes via PowerShell call operator `& $program $arguments` and captures standard output text.

### 1.3 Desktop UI (Native WPF Provider)
- **14 Controls Supported**: `window`, `button`, `primary button`, `secondary button`, `danger button`, `text`, `heading`, `text box`, `row`, `column`, `scroll`, `panel`, `grid`, `card`.
- **Properties Supported**: `title`, `text`, `width`, `height`, `width full`, `height full`, `background`, `foreground`, `spacing`, `padding`, `align` (`left`, `center`, `right`, `top`, `middle`, `bottom`), `spread`, `placeholder`, `round`.
- **Lifecycle & Events**: `create <kind> into <name>`, `<name> has <props>`, `put <child> in <parent>`, `show <window>`, `when <control> is clicked`, `when <control> is changed`, `when app is closed`.
- **State & Reactivity**: `state <name> is <val>`, `derive <name> is <expr>`, `when <name> changes ... .`.
- **Disconnected / Post-V1 (D56)**: Declarative WPF trees (`ConvertTo-OtterWpfWindow`), inline event/animation blocks, `card` declarative templates, `memo`, `shared`, `await`, `use`.

### 1.4 Web & Server (D50, D51)
- **Web App Compiler**: Compiles Otter UI and logic into standalone reactive HTML/CSS/JS (`otter web app.ot`).
- **Web Routes & Server**: Built-in HTTP server (`otter serve app.ot -Port 8080`) supporting routes and JSON responses.
- **HTTP Client (Web Only)**: `get <url> into <var>` and `get json from <url> into <var>` (implemented in `Otter.Web.psm1` via `fetch()`, currently cleanly unhandled in desktop interpreter).

---

## 2. What Must Otter 1.0 Be Able to Do? (Target Capability Matrix)

To serve as a serious, complete language for Windows shell, console, data processing, and native desktop applications, Otter 1.0 must address the following key domains:

```
                                  OTTER 1.0 TARGET MATRIX
                                             │
      ┌───────────────────┬──────────────────┴─────────────────┬───────────────────┐
      ▼                   ▼                                    ▼                   ▼
1. Shell & System    2. Console I/O                      3. Data & Storage    4. Desktop (WPF)
   • Env variables      • Stdin streaming                   • CSV parser         • Extended friendly props
   • Working folder     • Stderr output                     • Line-by-line read  • Richer native controls
   • Exit codes         • Color/styling                     • Registry access    • File dialogs (ask file)
   • Piping / redirects • Terminal size/clear               • Temp files         • Native escape hatch
```

### 2.1 Slice 1: Shell & System Expansion (Lead Focus)
- **Environment Variables**: Read and write environment variables naturally:
  ```otter
  read env "APPDATA" into appData
  # or
  env "MY_FLAG" is "true"
  ```
- **Working Directory**: Get and change current working directory:
  ```otter
  say working folder
  working folder is "C:\projects"
  ```
- **Process Exit & Return Codes**:
  - Capture child process exit codes:
    ```otter
    run command "git status" into result with exit code into code
    ```
  - Terminate Otter program with a specific exit code:
    ```otter
    stop program with code 1
    ```
- **Path Utilities**:
  - `parent of folder`, `temporary folder`, `home folder`, `desktop folder`, `combine path "a" and "b" into path`.
- **System Information**: `computer name`, `user name`, `windows version`.

### 2.2 Slice 2: Console Applications
- **Standard Input (Interactive CLI & Piping)**:
  - Reading piped input or single-line interactive input:
    ```otter
    read input into line
    for each line in input
        say "echo:" line
    .
    ```
- **Standard Error & Colors**:
  - Direct stderr output: `say error "Fatal failure"`
  - Console text styling: `say green "Success"`, `say bold "Attention:"`.
- **Terminal Control**: `clear screen`, `console title is "Otter Tool"`, `read key into pressedKey`.

### 2.3 Slice 3: Data Formats & Persistence
- **CSV & Tabular Data**:
  - Native parsing and serializing of CSV:
    ```otter
    read csv from "data.csv" into records
    write records to csv "output.csv"
    ```
- **Line-by-Line Large File Streaming**:
  - Reading massive files line by line without buffering entire files into a single string.
- **Windows Registry**:
  - Read/write registry values for Windows app configuration.

### 2.4 Slice 4: Desktop UI (WPF Native) & Native Escape Hatch
- **Extended Friendly Properties**:
  - Visual: `opacity`, `size` / `font size`, `bold`, `italic`, `font` (`"Segoe UI"`), `round` (on buttons/panels, not just cards), `border`, `border color`.
  - Layout & Bounds: `margin`, `minimum width`, `maximum width`, `minimum height`, `maximum height`, `wrap`.
  - State: `visible` / `hidden`, `enabled` / `disabled`, `tooltip`, `cursor`.
- **Extended Native Controls**:
  - `checkbox` (with `checked` boolean property).
  - `slider` (with `value`, `minimum`, `maximum`).
  - `dropdown` / `select` (with `items`, `selected`).
  - `image` (with `source` path).
  - `progress bar` (with `value`, `maximum`).
  - Native dialogs: `ask file into selectedPath`, `ask save file into savePath`, `ask folder into folderPath`.
- **Crisp Rendering Defaults**:
  - Automatic `SnapsToDevicePixels = true`, `UseLayoutRounding = true`, and `TextOptions.TextFormattingMode = Display` on all created Windows.

---

## 3. How Do We Guarantee Otter Never Hits an Artificial Ceiling? (Native Escape Hatch)

To resolve the tension between beginner readability and unrestricted power, Otter desktop implements a **Two-Layer Property Architecture**:

```
                       OTTER UI ARCHITECTURE
                                 │
                 ┌───────────────┴───────────────┐
                 ▼                               ▼
       LAYER 1: FRIENDLY VOCABULARY     LAYER 2: NATIVE ESCAPE HATCH
       (Canonical, Portable, Human)     (Explicit, Complete, Windows-WPF)
                 │                               │
       • button has background "#2563eb" • native "SnapsToDevicePixels" of app is true
       • card has opacity 0.85          • native "FontFamily" of title is "Segoe UI"
       • row has spread, spacing 12     • native "ScrollViewer.VerticalScrollBarVisibility"
                 │                               │
                 └───────────────┬───────────────┘
                                 ▼
                     WPF PROVIDER RESOLVER
                      (in Otter.UI.psm1)
                                 │
     ┌───────────────────────────┴───────────────────────────┐
     ▼                                                       ▼
1. Friendly Lookup                              2. Native Escape Hatch
   Map to known property/type                    Inspect CLR, DependencyProperty,
   Validate ranges (0.0 - 1.0)                   or Attached Property via Reflection
   Apply layout rules & wrappers                 Convert types safely (Double, Brush, Enum)
     │                                                       │
     └───────────────────────────┬───────────────────────────┘
                                 ▼
                    NATIVE WPF / WINDOWS RUNTIME
```

### 3.1 D43 Invariant & Encapsulation
Per D43, **all WPF types and reflection (`System.Windows.*`) live exclusively inside `src/Otter.UI.psm1`**.
No parser, lexer, or other runtime module may ever reference WPF assemblies or types directly.

### 3.2 Syntax for the Native Escape Hatch

The escape hatch is **visibly provider-specific**:

```otter
# Reading a native property
say native "ActualWidth" of saveButton

# Setting a native CLR or DependencyProperty
native "SnapsToDevicePixels" of app is true
native "Opacity" of app is 0.75
native "FontFamily" of heading is "Consolas"

# Setting an Attached Property
native "Grid.Row" of saveButton is 1
native "ScrollViewer.VerticalScrollBarVisibility" of scroll is "Auto"

# Setting via 'has'
app has
    title "Hardware Monitor"
    native "WindowStyle" "None"
    native "AllowsTransparency" true
    native "Background" "Transparent"
.
```

### 3.3 Native Type Conversion Engine (inside `Otter.UI.psm1`)

The bridge converts Otter primitives into the required .NET/WPF target type:
1. **Numbers**: Auto-convert to `System.Double`, `System.Single`, `System.Int32`, `System.Int64`.
2. **Strings**: Auto-convert to `System.String`, `System.Windows.Media.FontFamily`, or `System.Uri`.
3. **Booleans**: Auto-convert to `System.Boolean`.
4. **Enums**: Case-insensitive string-to-enum resolution (e.g. `"Auto"` $\to$ `System.Windows.Controls.ScrollBarVisibility.Auto`).
5. **Colors & Brushes**: Strings (named or hex `#RRGGBB`) $\to$ `System.Windows.Media.Brush` via `System.Windows.Media.BrushConverter`.
6. **Thickness & CornerRadius**: Single number `8` $\to$ `Thickness(8)` or `CornerRadius(8)`.

### 3.4 DependencyProperty & Attached Property Resolution

When `native "Prop"` is accessed in `Otter.UI.psm1`:
1. **Attached Property Check**: If `"Owner.Property"` contains a dot (e.g. `"Grid.Row"`):
   - Resolve type `System.Windows.Controls.Grid`.
   - Locate `Grid.RowProperty` dependency property.
   - Call `$target.SetValue([System.Windows.Controls.Grid]::RowProperty, $convertedVal)`.
2. **Dependency Property Check**: Look for `[Type]::PropProperty` (e.g. `UIElement.SnapsToDevicePixelsProperty`).
   - Call `$target.SetValue($dp, $convertedVal)`.
3. **Standard CLR Property Check**:
   - Inspect `$target.GetType().GetProperty("Prop")`.
   - Call `$prop.SetValue($target, $convertedVal, $null)`.
4. **Diagnostic Integrity**: If the property is not found or conversion fails, throw a structured `OtterError` naming the property and control kind. Raw .NET `TargetInvocationException` or stack traces **never leak**.

---

## 4. Phased Implementation Roadmap

```
Phase 1: Architecture Alignment & D60 Decision Draft
         • Save capability inventory in repo for Claude & Jeff
         • Align sequencing: Slice 1 (Shell/Console) is lead focus

Phase 2: Slice 1 — Shell & System Capabilities
         • Environment variables: read/write env
         • Working directory: working folder
         • Process control: exit codes, program exit
         • Front end (Gemini): Grammar, Tokens, AST, Parser tests
         • Back end (Claude): Interpreter execution in Otter.Library.psm1 / Otter.Interpreter.psm1

Phase 3: Slice 2 — Console Applications
         • Standard error, piped input, terminal styling

Phase 4: Slice 3 — Data Formats & Persistence
         • CSV parsing/writing, streaming line reader

Phase 5: Slice 4 — Fuller Desktop UI & Native Escape Hatch
         • Extended friendly vocabulary (opacity, size, bold, border, visible)
         • WPF provider native escape hatch implementation (strictly in Otter.UI.psm1)

Phase 6: Dogfooding, Final Documentation & Packaging
         • Build real-world multi-feature administrative and desktop tools
         • Update docs site and release README for the expanded 1.0 surface
         • Cut 1.0.0-rc.1 -> 1.0.0 Final Release
```

---

## 5. Phase 1 Ownership Split & Architectural Boundary Record

| Layer / Component | Owner | Boundary & Scope |
|---|---|---|
| **`Otter.Compiler.JavaScript.psm1`** | **Claude** | Otter AST → portable JavaScript semantics (expressions, control flow, functions, objects, error semantics). |
| **`Otter.Web.psm1`** | **Gemini** | Browser target, HTML5 document generation, DOM element mapping, and browser bootstrap. Consumes compiled JS output from the compiler without duplicating compiler logic. |
| **`Otter.Desktop.psm1`** | **Gemini** | Desktop host & shell integration consuming the shared Web UI representation. |
| **Otter Studio & UI Tooling** | **Gemini** | Visual designer, CSS AST parser/tooling, and IDE interface. |
| **`Otter.Interpreter.psm1`, `Otter.Runtime.psm1`** | **Claude** | Core interpreter execution, environment, scopes, and runtime dispatch. |
| **`otter.ps1`, `otter.cmd`** | **Claude** | Command-line interface and subcommand router (`otter run`, `otter test`, `otter web`). |
| **`Otter.UI.psm1`** | **Claude** | Frozen reference implementation for native WPF desktop controls. |
| **`Otter.Lexer.psm1`, `Otter.Parser.psm1`** | **Gemini** | Language frontend (tokens, indentation/dedentation tracking, AST node construction). |

### Frontend & Runtime Boundary Invariants
1. **Host & UI vs. Language Semantics**: Host and UI capabilities belong to Gemini; universal Otter language semantics belong to Claude. A browser or desktop host must never invent or redefine language semantics in response to Web/Desktop needs. If the Web or Desktop target requires an unhandled language construct, coordinate with the compiler owner rather than creating a Web-only dialect.
2. **Frontend Contract Invariant**: Frontend ownership does not grant authority to change frozen language semantics without a new decision. Lexer/parser changes implement the language contract; they do not redefine it.

