# Otter Studio — Professional IDE User Guide & Technical Manual

**Product:** Otter Studio  
**Version:** 1.0.0  
**Target:** Visual UI Designer, Interactive IDE, and Build System for Otter Applications

---

## Table of Contents

1. [Introduction & Overview](#1-introduction--overview)
2. [Studio Tour & Layout Architecture](#2-studio-tour--layout-architecture)
3. [Professional Source Editor](#3-professional-source-editor)
4. [Visual UI Designer & Two-Way Code Synchronization](#4-visual-ui-designer--two-way-code-synchronization)
5. [Interactive Execution & Integrated Terminal](#5-interactive-execution--integrated-terminal)
6. [Interactive Debugger](#6-interactive-debugger)
7. [Test Explorer](#7-test-explorer)
8. [Integrated Source Control (Git)](#8-integrated-source-control-git)
9. [Package & Dependency Management](#9-package--dependency-management)
10. [Extension & Plugin Ecosystem](#10-extension--plugin-ecosystem)
11. [Performance Profiler](#11-performance-profiler)
12. [Build System & Cross-Platform Distribution](#12-build-system--cross-platform-distribution)
13. [Accessibility, i18n & High-Contrast Support](#13-accessibility-i18n--high-contrast-support)
14. [Crash Recovery, Healing & Safe Reset](#14-crash-recovery-healing--safe-reset)
15. [Updater & Release Channels](#15-updater--release-channels)
16. [Troubleshooting & Diagnostics](#16-troubleshooting--diagnostics)

---

## 1. Introduction & Overview

Otter Studio is a modern, lightweight, high-performance integrated development environment tailored specifically for the Otter programming language. Designed for both rapid visual prototyping and professional software engineering, Otter Studio combines:

- A full-featured code editor with semantic analysis, autocomplete, and quick fixes.
- A live visual UI designer featuring direct manipulation and continuous two-way synchronization with Otter source code.
- Zero-drift execution and debugging powered directly by the reference Windows PowerShell 5.1 / Node.js runtime engines.
- Built-in multi-platform publishing delivering standalone Windows, macOS, and Linux executables.

---

## 2. Studio Tour & Layout Architecture

The Studio interface is organized into five primary ergonomic regions:

```
+-------------------------------------------------------------------------+
| Activity Bar: Explorer | Designer | Search | Debug | Tests | Git | Extensions |
+------------------+------------------------------------+-----------------+
| Tool Sidebar     | Main Workspace: Editor / Designer  | Properties /    |
| - Project Tree   | - Dual Mode: Split / Canvas / Code | Live Preview /  |
| - Component Kit  | - Multi-tab document support       | Mascot Advice   |
| - Symbol Outline | - Breadcrumb navigation            |                 |
+------------------+------------------------------------+-----------------+
| Bottom Panel: Terminal | Problems | Output | Profiler | Debug Console  |
+-------------------------------------------------------------------------+
| Status Bar: Branch | Error/Warn | Line/Col | EOL | Encoding | Channel   |
+-------------------------------------------------------------------------+
```

- **Activity Bar:** Quick access to the core functional modes of the IDE.
- **Tool Sidebar:** Context-sensitive panels showing files, visual widgets, outline symbols, or extensions.
- **Main Workspace:** Tabbed editor and visual designer with split-screen, canvas-only, or code-only layouts.
- **Properties & Preview Panel:** Inspector for widget attributes and isolated sandboxed preview frame.
- **Bottom Panel:** Integrated output, problems pane, profiler timeline, and interactive terminal.
- **Status Bar:** Real-time workspace indicators including Git branch, diagnostic counts, cursor position, and update channel.

---

## 3. Professional Source Editor

The Otter Studio editor is engineered for ergonomics, precision, and readability:

1. **Syntax Highlighting:** Themeable token-based colorization distinguishing keywords (`if`, `count`, `make`), operators (`plus`, `divided by`, `is greater than`), strings, numbers, and identifiers.
2. **Language Intelligence & Autocomplete:** Contextual word and symbol completion (`Ctrl+Space`) prioritizing local variables, functions, and standard library methods.
3. **Diagnostics & Quick Fixes:** Real-time red/yellow wavy squiggles mapped directly from the compiler diagnostic matrix. Clicking a diagnostic presents verified Quick Fix suggestions (e.g., auto-converting `=` to `is`, or closing unclosed blocks with `.`).
4. **Symbol Index & Navigation:** Document symbol outline (`Ctrl+Shift+O`), Go-to-Definition (`F12`), and Jump-to-Line (`Ctrl+G`).
5. **Editing Shortcuts:**
   - Multi-cursor editing (`Alt+Click`).
   - Duplicate Line (`Shift+Alt+Down`).
   - Move Line (`Alt+Up / Alt+Down`).
   - Comment / Uncomment (`Ctrl+/`).
   - Format Document (`Shift+Alt+F`).

---

## 4. Visual UI Designer & Two-Way Code Synchronization

The visual designer enables rapid, high-fidelity UI layout without losing control of the underlying source code:

1. **Direct Drag-and-Drop:** Drag widgets (`window`, `button`, `text box`, `label`, `checkbox`, `container`) directly from the Component Toolbox onto the canvas.
2. **Reordering & Hierarchy:** Reorder elements visually in the canvas flow or using the hierarchical treeview in the sidebar.
3. **Properties Inspector:** Live property editors for text, colors (with color picker), dimensions, padding, margins, borders, and event handlers.
4. **Authoritative Code Generation:** Canvas modifications immediately serialize to human-readable, canonical Otter code using the standard `OtterUiModel`.
5. **Two-Way Code Reflection:** Editing source code in the editor automatically re-parses and updates the visual canvas in real time.
6. **Undo & Redo:** Full transactional undo/redo stack (`Ctrl+Z` / `Ctrl+Y`) spanning both canvas layout and property edits.

---

## 5. Interactive Execution & Integrated Terminal

1. **Run Current File (`F5` / Run Button):** Spawns the current Otter program in the local execution engine. Output streams directly to the Integrated Output Console in real time.
2. **Exit Code & Diagnostics:** Upon completion, the exit status is displayed with clear color-coded indicators (Green = 0 Success, Red = Non-Zero Failure, Yellow = Usage Error).
3. **Integrated Terminal:** Provides a fully functional terminal shell for executing CLI commands, running scripts, and interacting with Git.

---

## 6. Interactive Debugger

Otter Studio incorporates a first-class interactive debugging interface:

1. **Breakpoints:** Click in the editor gutter to toggle line breakpoints (indicated by red dots).
2. **Debug Session Lifecycle:** Start debugging (`F5` in Debug Mode) to spawn a managed session communicating with `src/Otter.Debugger.psm1`.
3. **Execution Controls:**
   - **Continue (`F5`):** Resume execution until the next breakpoint.
   - **Step Over (`F10`):** Execute the next statement without entering sub-functions.
   - **Stop (`Shift+F5`):** Terminate the debugging session immediately and cleanup child processes.
4. **Variables & Locals Inspector:** Inspect variables in local and global scopes as execution pauses.
5. **Call Stack:** Visual display of active invocation frames, allowing navigation up and down the stack.

---

## 7. Test Explorer

1. **Automated Discovery:** Automatically scans `tests/` directories for Otter test suites matching `*_test.ot` or `*.Tests.ps1`.
2. **Hierarchy & Status:** Displays tests in a tree view categorized by suite, file, and test case.
3. **Run Controls:** Run all discovered tests or execute a single test case with a single click.
4. **Failure Diagnostics:** Test failures highlight the failing assertion and line number in the Problems pane.

---

## 8. Integrated Source Control (Git)

1. **Status & Change Tracking:** Real-time detection of modified, added, deleted, and untracked files.
2. **Diff Viewer:** Side-by-side and inline syntax-highlighted diffs comparing working tree changes against `HEAD`.
3. **Staging & Commit:** Stage individual files or all changes (`Ctrl+Enter` to commit with a descriptive message).
4. **Branch Management:** Switch branches, create new feature branches, and view recent commit history directly from the status bar.

---

## 9. Package & Dependency Management

Otter projects declare dependencies in `project.json`:

```json
{
  "name": "my-app",
  "version": "1.0.0",
  "dependencies": {
    "core": "^1.0.0",
    "math-utils": "^1.2.0"
  }
}
```

1. **Dependency Browser:** Search and install community packages from official registries.
2. **Version Pinning:** SemVer ranges (`^1.0.0`, `~1.2.0`, exact `1.2.3`) resolve automatically.
3. **Modular Imports:** Use installed packages seamlessly in Otter source code using the `use` statement.

---

## 10. Extension & Plugin Ecosystem

Otter Studio features a modular extension system:

1. **Contribution Points:** Extensions contribute commands, color themes, keybindings, activity bar views, and custom panels via an `extension.json` manifest.
2. **Lifecycle Management:** Extensions activate on-demand (e.g., when an Otter file is opened or a specific command is run).
3. **Fault Resilience & Crash Isolation:** Extensions run in isolated contexts; an uncaught exception or crash inside a plugin cannot crash Studio or corrupt open buffers.

---

## 11. Performance Profiler

1. **CPU & Function Timings:** Measure execution time per function call, identifying hot paths and bottlenecks.
2. **Hot-Line Heatmaps:** Colorized margin indicators showing high-frequency execution lines.
3. **60 FPS Frame Budget Analysis:** Assess frame rendering budgets for graphical and interactive desktop applications.
4. **Trace Export & Import:** Export performance traces to JSON for regression analysis and sharing.

---

## 12. Build System & Cross-Platform Distribution

1. **One-Click Build:** Compile applications into `dist/` with optimized launchers, icons, and bundled runtime scripts.
2. **Target Architectures:**
   - **Windows:** Standalone `.cmd` launcher and WPF desktop window host.
   - **macOS:** Self-contained `.app` bundle with `Info.plist` and POSIX launcher.
   - **Linux:** FreeDesktop `.desktop` entry, scalable icons, and `AppRun` binary launcher.
3. **Release Packaging:** Automatic creation of versioned release `.zip` archives with SHA-256 integrity checksums.

---

## 13. Accessibility, i18n & High-Contrast Support

1. **WCAG Compliance:** Certified for WCAG AAA contrast ratios across Dark, Light, and High Contrast themes.
2. **Screen Reader Live Announcer:** `aria-live` announcer provides speech feedback for status changes, errors, and test results.
3. **Full Keyboard Navigation:** Complete keyboard shortcuts for all actions, canvas widget nudging/resizing, and dialog focus trapping.
4. **Internationalization (i18n):** Multi-language dictionaries, RTL layout support, and Unicode/CJK IME composition handling.

---

## 14. Crash Recovery, Healing & Safe Reset

1. **Dirty Buffer Journaling:** Uncommitted edits are continuously journaled to local storage every 500ms.
2. **Abnormal Termination Recovery:** If Studio is terminated unexpectedly, restart displays a prompt to restore unsaved documents with cursor positions intact.
3. **Corrupt Settings Healing:** Corrupted JSON configuration files are automatically backed up to `<name>.corrupt.<timestamp>` and healed with safe default configurations.
4. **Recovery Mode & Safe Reset:** Hold `Shift` during launch or invoke "Reset Studio State" to clear corrupted cache and extension storage without deleting user project files.

---

## 15. Updater & Release Channels

1. **Release Channels:** Select between `stable` (production-grade) and `preview` (early access features) channels.
2. **Cryptographic Verification:** Every update payload is verified against official SHA-256 signatures before installation.
3. **Atomic Rollback:** If an update fails verification or execution, Studio automatically rolls back to the prior working version snapshot.
4. **Skip Version:** Users can choose to skip specific minor updates with a single click.

---

## 16. Troubleshooting & Diagnostics

- **Studio Fails to Start:** Run `node serve.mjs` directly in a terminal to inspect startup logs. Verify port 4200 is available.
- **Parser Mismatch:** Ensure source files use period-terminated blocks (`.`) and consistent 4-space or 1-tab indentation.
- **Port Conflict:** Set `OTTER_STUDIO_PORT=5000` to bind Studio to an alternate local port.
- **Open Logs:** Access Studio diagnostic logs via Help → Open Logs or at `~/.otter/logs/studio.log`.
