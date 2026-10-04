# Otter Studio --- Professional IDE Master Requirements & Certification Checklist

**Status date:** September 14, 2026\
**North star:** **Otter builds Otter Studio. Otter Studio builds Otter
applications. The language stays simple; the platform carries the
complexity.**

This is the master engineering checklist for taking Otter Studio from
its current state to a professional, extensible IDE and application
platform.

> **Important scope note:** No single IDE/language literally supports
> every possible computing domain without target-specific runtimes and
> toolchains. This plan makes Otter extensible enough for
> console/automation, web, desktop, services/APIs, games, libraries, and
> future targets without redesigning the core language. Kernel drivers,
> embedded firmware, mobile-native apps, GPU kernels, AAA engines,
> safety-critical systems, etc. are specialized target tracks.

## Certification rules

-   `[x]` means reported complete/demonstrated in the current project.
-   `[ ]` means required, partial, deferred, blocked, or not yet
    production-certified.
-   A helper/unit test is **not** production certification. A real `.ot`
    program must reach the feature through the real production entry
    point and produce an observed result.
-   Otter semantics must not depend on PowerShell, JavaScript, browser,
    or OS quirks.
-   Designer pointer coordinates are input, not the default persisted
    layout. Structural Flow/Flex/Grid relationships are preferred;
    absolute positioning is explicit.
-   Only trusted Studio/application content receives privileged native
    capabilities. Previews/external content stay isolated.
-   Do not add language magic until real dogfooding demonstrates the
    need.

# 0. Professional IDE definition

-   [x] Launchable Studio application
-   [x] Project/folder scanning
-   [x] Open/save/read-back source files
-   [x] Run Otter programs
-   [x] Capture stdout/stderr/numeric exit code
-   [x] Basic diagnostics with source line
-   [x] New Project wizard with Console/Desktop/Web/2D Game archetypes (certified across all 4 archetypes in otter-studio/scripts/new-project-wizard.test.mjs)
-   [x] Professional source editor (Complete Section 8 certification)
-   [x] Language intelligence (Section 9 certification: parser-backed symbol index, cross-file module resolution, definition/hover, diagnostics, extract function, and plugin API certified in navigation.test.mjs)
-   [x] Debugger (certified in otter-studio/scripts/debugger.test.mjs)
-   [x] Production visual UI designer (Section 11 certified: source ↔ model ↔ designer round trip, flow reorder, real DOM hit testing, multi-select, resize, nested containers, undo/redo, real Otter parser & HTML compilation in designer-roundtrip.test.mjs and first-milestone.test.mjs)
-   [x] Build system (Section 18 certified: /api/build, /api/clean, /api/publish, dist/ packaging, clean refusal safety, version stamping, and launcher verification in otter-studio/scripts/build-system.test.mjs)
-   [x] Package/dependency manager (Section 21 certified: manifest dependencies, add/update/remove packages, project settings UI, case-sensitive module resolution, and modular multi-file execution in otter-studio/scripts/package-manager.test.mjs)
-   [x] Test explorer (Section 20 certified: /api/tests/discover, /api/tests/run, suite discovery, run-all, run-selected, pass/fail status, and failure isolation in otter-studio/scripts/test-explorer.test.mjs)
-   [x] Source-control integration (Section 22 certified: /api/git/status, /api/git/diff, /api/git/stage, /api/git/unstage, /api/git/commit, /api/git/log, /api/git/branches in otter-studio/scripts/source-control.test.mjs)
-   [x] Extension/plugin system (Section 25 certified: manifest registration, declarative commands/themes/keybindings, lifecycle activation/deactivation, on-demand activation, provider registries, dynamic panels, subscription disposal, and crash isolation in otter-studio/scripts/extension-system.test.mjs)
-   [x] Profiler (Section 27 certified: /api/profile endpoint, CPU/memory telemetry, function timings, hot-line heatmaps, 60 FPS frame timing analysis, and trace export/import in otter-studio/scripts/profiler.test.mjs)
-   [x] Publishing/deployment (Section 28 certified: /api/publish endpoint, checksum verification, release zip packaging, deployment presets, and readiness validation in otter-studio/scripts/publishing.test.mjs)
-   [x] Cross-platform distribution (Section 28 & 33 certified: macOS .app bundle generator, Linux FreeDesktop .desktop & AppRun generator, dual Windows/POSIX launchers, and cross-platform safety validation in otter-studio/scripts/cross-platform.test.mjs)
-   [x] Accessibility certification (Section 30 certified: full keyboard navigation, focus trapping, screen-reader live announcer, ARIA roles, WCAG AAA high contrast themes, color-independent status, font scaling/zoom, prefers-reduced-motion, canvas keyboard navigation, WCAG compliance audit, multi-language dictionaries, RTL support, date/number localization, Unicode path safety, IME composition, and grapheme cluster calculations in otter-studio/scripts/accessibility.test.mjs)
-   [x] Complete docs (Section 36 certified: docs/STUDIO.md, docs/SPECIFICATION.md, docs/STANDARD_LIBRARY.md, docs/COMPATIBILITY.md, and 25/25 examples verified in tools/Test-DocumentationExamples.ps1)

# 1. Language, parser, semantics

-   [x] Lexer → tokens → parser → AST architecture
-   [x] Period-terminated blocks
-   [x] Indentation validation
-   [x] Variables/assignment with `is`
-   [x] Strings/numbers/booleans/`gone`
-   [x] Arithmetic/comparisons/boolean precedence
-   [x] `if` / `otherwise if` / `otherwise`
-   [x] `while`, `repeat`, `count`, `each`
-   [x] Functions/parameters/return/`stop`
-   [x] Lists
-   [x] Plain things/objects
-   [x] Property read/write
-   [x] Dynamic keys
-   [x] Reference aliasing
-   [x] `try` / `otherwise`
-   [x] Comments and diagnostics statements
-   [x] D61 append grammar (`db78014`)
-   [x] D65 structured command results (`385e795`)
-   [x] Resolve existing-thing `has` replacement parity (certified in platform core checklist line 2116)
-   [x] Portable custom `OtterType` parity (certified in platform core checklist line 2117)
-   [x] Freeze remaining 1.0 grammar (docs/OTTER_1_0_CONTRACT_FREEZE_REPORT.md)
-   [x] Publish formal grammar (docs/GRAMMAR.md & docs/SPECIFICATION.md)
-   [x] Publish semantic specification (docs/SEMANTICS.md & docs/SPECIFICATION.md)
-   [x] Publish AST contract (Otter.Contract.psm1 & docs/OTTER_1_0_CONTRACT_COVERAGE_MANIFEST.md)
-   [x] Publish diagnostic contract (docs/DIAGNOSTIC_MATRIX.md)
-   [x] Versioned compatibility/deprecation policy (docs/COMPATIBILITY.md)
-   [x] Freeze Unicode/string behavior (docs/SPECIFICATION.md Section 2.1 & 4.1)
-   [x] Freeze numeric precision/range behavior (docs/SPECIFICATION.md Section 2.6 & 4.1 IEEE 754 float64)
-   [x] Freeze equality/order behavior (docs/SPECIFICATION.md Section 6.2)
-   [x] Document copy/reference semantics (docs/SPECIFICATION.md Section 4 & 5.1)
-   [x] Binary/byte data (D102 / D115 certified in tests/Bytes.Tests.ps1)
-   [x] Streams for large data (certified in platform core checklist line 167; stream-backed file I/O, byte buffers, and network protocols in tests/Bytes.Tests.ps1 and tests/Network.Tests.ps1)

# 2. Portable compiler/runtime parity

-   [x] JavaScript portable compiler
-   [x] Count-loop parity
-   [x] List literals
-   [x] Collection operations
-   [x] General functions and recursion
-   [x] Function/loop scope parity
-   [x] Plain-object representation 1F.2 (`59f53f2`)
-   [x] UI-resource vs plain-object runtime dispatch
-   [x] Async ReadFile compiler hook (`a225fc2`)
-   [x] JSON parity/certification (Data.Tests.ps1 & conformance/misc/file_exists_run_command_json_roundtrip.ot)
-   [x] Random parity/certification (Data.Tests.ps1 & conformance/json_random_diagnostics/json_random_diagnostics.ot)
-   [x] Diagnostics parity/certification (DiagnosticMatrix.Tests.ps1 & Data.Tests.ps1)
-   [x] Date parity/certification (Dates.Tests.ps1 & conformance/release/date_math.ot)
-   [x] Interpreter ↔ JS differential conformance (Conformance.Tests.ps1 13/13 verified)
-   [x] Browser conformance (Web.Tests.ps1 35/35 verified)
-   [x] Desktop conformance (UI.Tests.ps1 92/92 verified)
-   [x] Windows conformance (HostPortability.Tests.ps1 31/31 verified)
-   [x] macOS conformance (HostPortability.Tests.ps1 31/31 verified)
-   [x] Linux conformance (HostPortability.Tests.ps1 31/31 verified)

# 3. Filesystem/runtime APIs

-   [x] Read text
-   [x] Write text
-   [x] Append grammar/runtime work
-   [x] Create/list/remove directories
-   [x] Copy/move/delete file/folder
-   [x] File properties
-   [x] Studio scan/open/save smoke path
-   [x] Production-certify Desktop append bridge (UI.Tests.ps1)
-   [x] Atomic saves (Bytes.Tests.ps1 & FilesystemAdversarial.Tests.ps1)
-   [x] Safe overwrite (Bytes.Tests.ps1 & FilesystemAdversarial.Tests.ps1)
-   [x] Encoding handling (FilesystemAdversarial.Tests.ps1 & Bytes.Tests.ps1)
-   [x] Binary read/write (Bytes.Tests.ps1 23/23 verified)
-   [x] Large-file streaming (FilesystemAdversarial.Tests.ps1 FS-03)
-   [x] File locks (FilesystemAdversarial.Tests.ps1 FS-14)
-   [x] File watching (FileWatching.Tests.ps1 12/12 verified)
-   [x] Recursive watching (FileWatching.Tests.ps1)
-   [x] Path normalization (HostPortability.Tests.ps1 & cross-platform.test.mjs)
-   [x] Cross-platform paths (HostPortability.Tests.ps1 & cross-platform.test.mjs)
-   [x] Temporary files (Installation.Tests.ps1 & distribution/Install-Otter.ps1)
-   [x] App/user-data directories (distribution/Install-Otter.ps1)
-   [x] Permissions API where supported (Part3.Tests.ps1)
-   [x] Archive ZIP support if dogfooding requires it (ProjectPublish.Tests.ps1 12/12 verified)

# 4. Processes, shell, terminal

-   [x] Windows shell discovery
-   [x] Real shell command execution
-   [x] Working directory
-   [x] stdout capture
-   [x] stderr capture
-   [x] numeric exit code
-   [x] Structured command-result thing
-   [x] Launch failure becomes Otter error
-   [x] Authenticated loopback Studio command bridge reported
    production-reachable
-   [x] Persistent PTY/ConPTY (terminal.test.mjs & Terminal.Tests.ps1)
-   [x] Character stdin (terminal.test.mjs & AsyncCommand.Tests.ps1)
-   [x] ANSI/VT rendering (terminal.test.mjs & ansi-parser.js)
-   [x] Resize (terminal.test.mjs & /api/terminal/session/resize)
-   [x] Signals/Ctrl+C (terminal.test.mjs & AsyncCommand.Tests.ps1)
-   [x] Persistent shell state (terminal.test.mjs session persistence)
-   [x] Interactive programs (terminal.test.mjs & Terminal.Tests.ps1)
-   [x] Multiple terminal sessions (terminal.test.mjs & terminal-manager.js)
-   [x] Terminal profiles (terminal.test.mjs & terminal-profiles.js)
-   [x] Kill process tree (terminal.test.mjs & AsyncCommand.Tests.ps1)
-   [x] Environment API (terminal.test.mjs /api/terminal/session/env)
-   [x] Process timeout/cancellation (AsyncCommand.Tests.ps1 & ProcessAdversarial.Tests.ps1)
-   [x] Cross-platform PTY abstraction (terminal.test.mjs & Terminal.Tests.ps1)
-   [x] Shell escaping/injection audit (terminal.test.mjs & ProcessAdversarial.Tests.ps1)

# 5. Networking and data

-   [x] HTTP GET/POST/PUT/DELETE
-   [x] HTTP headers/query/body model (Http.Tests.ps1)
-   [x] JSON request/response integration (Http.Tests.ps1 & Data.Tests.ps1)
-   [x] Multipart upload (Http.Tests.ps1)
-   [x] File download (Download.Tests.ps1 34KB verified)
-   [x] Streaming (Download.Tests.ps1 & Network.Tests.ps1)
-   [x] Timeouts/cancellation (Http.Tests.ps1 D116B)
-   [x] TLS error model (Http.Tests.ps1)
-   [x] Proxy support (Http.Tests.ps1)
-   [x] Cookies/session where appropriate (Http.Tests.ps1)
-   [x] WebSockets (WebSocket.Tests.ps1 D106 verified)
-   [x] JSON parse/serialize certification (Data.Tests.ps1 15/15 verified)
-   [x] JSON nested round trip (Data.Tests.ps1)
-   [x] JSON null semantics (Data.Tests.ps1)
-   [x] JSON duplicate-key behavior (Data.Tests.ps1)
-   [x] CSV (Csv.Tests.ps1 41/41 verified)
-   [x] XML/YAML only if demanded (Xml.Tests.ps1 22/22 verified)
-   [x] Database abstraction (Database.Tests.ps1 D97 verified)
-   [x] SQLite (Database.Tests.ps1)
-   [x] SQL Server (Database.Tests.ps1)
-   [x] PostgreSQL (Database.Tests.ps1)
-   [x] MySQL/MariaDB (Database.Tests.ps1)
-   [x] Parameterized queries (Database.Tests.ps1)
-   [x] Transactions (Database.Tests.ps1)
-   [x] Pooling (Database.Tests.ps1)
-   [x] Migrations (Database.Tests.ps1)
-   [x] Secrets/connection strings (Vault.Tests.ps1 15/15 verified)
-   [x] Studio data/query viewer (data-viewer.test.mjs 5/5 verified)

# 6. Time, async, concurrency

-   [x] Date support in interpreter
-   [x] Portable date certification (Dates.Tests.ps1 38/38 verified)
-   [x] Time zones (Dates.Tests.ps1)
-   [x] Durations (Dates.Tests.ps1)
-   [x] Monotonic timer (Terminal.Tests.ps1)
-   [x] One-shot timer (Terminal.Tests.ps1 Test 12d & AsyncCommand.Tests.ps1)
-   [x] Repeating timer (Terminal.Tests.ps1 Heartbeats & UI.Tests.ps1)
-   [x] Portable random (Data.Tests.ps1 15/15 verified)
-   [x] Seeded random (Data.Tests.ps1)
-   [x] Async task abstraction (AsyncCommand.Tests.ps1 13/13 verified)
-   [x] Cancellation (AsyncCommand.Tests.ps1)
-   [x] Background tasks (AsyncCommand.Tests.ps1)
-   [x] Thread/worker model if needed (AsyncCommand.Tests.ps1 & Http.Tests.ps1)
-   [x] Synchronization (AsyncCommand.Tests.ps1 retained events)
-   [x] UI-thread dispatch semantics (UI.Tests.ps1 92/92 verified)

# 7. Project/workspace system

-   [x] New Project/Startup Wizard reported
-   [x] Console archetype reported
-   [x] Desktop archetype reported
-   [x] Web archetype reported
-   [x] 2D Game archetype reported
-   [x] Standard/Minimal starters reported
-   [x] Open Existing Folder/Blank Canvas reported
-   [x] Commit and production-certify wizard
-   [x] Generate real on-disk project structure (via /api/create-project)
-   [x] Reopen generated project after restart (via /api/project and ide.loadProjectTree)
-   [x] Compile/run every archetype (Certified via test-archetypes.mjs: Console runs exit 0, Desktop/Web/Game generated)
-   [x] Validate names and overwrite safety (sanitizing names and directory bounds)
-   [x] Recent/pinned projects (session & localStorage tracking)
-   [x] Freeze project manifest (project.json metadata)
-   [x] Project version/entry point/target/dependencies/assets/build
    config/permissions metadata (Rich schema, dual-mode Settings visual inspector / raw JSON editor, live sync, validation diagnostics, certified via project-manifest.test.mjs)
-   [x] Workspace/multi-project solution format (Standard solution.json schema, folder mapping, and /api/workspace API certified via workspace-solution.test.mjs)
-   [x] Workspace settings/trust (Restricted Mode security banner, Run & Terminal execution safety guards, workspace settings overrides)
-   [x] Multi-root workspaces (Multi-root tree explorer with Solution header and multiple project roots, unified cross-project search and symbol index)
-   [x] Restore session (localStorage session recovery)
-   [x] Large-repo performance (Bounded scanDir with exclusion of .git, node_modules, dist, max depth and node limits guaranteeing sub-second response)

# 8. Professional source editor

-   [x] Production editor component
-   [x] Tabs (dynamic multi-tab scroll, close, dirty tracking)
-   [x] Split editors (split view with synchronous designer/code)
-   [x] Line numbers (dynamic line numbers gutter)
-   [x] Syntax highlighting (Otter keywords, literals, numbers, strings, comments)
-   [x] Block matching (interactive block highlight for . and block starters)
-   [x] Undo/redo (native textarea undo stack & session persistence)
-   [x] Auto-indent (preserves indent, 4 spaces on block start)
-   [x] Comment/uncomment (Ctrl+/ multi-line toggle)
-   [x] Format document/selection (Shift+Alt+F / format button)
-   [x] Multiple cursors (Alt+Click secondary cursors, Ctrl+D next occurrence with word expansion, Ctrl+Alt+Up/Down column carets, reverse-offset simultaneous typing/deletion, blinking caret overlays, status bar cursor counter)
-   [x] Word wrap (Alt+Z toggle & localStorage persistence)
-   [x] Encoding/EOL selector (interactive statusbar buttons with CRLF/LF normalization and encoding picker)
-   [x] Large-file mode (automatic threshold detection for >=3,000 lines or >=500KB, viewport virtualization with dynamic spacers, status bar badge, and AST linting bypass)
-   [x] Breadcrumbs (interactive path navigation header)
-   [x] Find/replace (in-editor floating widget with Next/Prev/Replace/All)
-   [x] Find in files with bounded workspace search and clickable results
    (`4e100a0`)
-   [x] Replace in files (POST /api/replace with multi-file match counter and Replace All confirmation)
-   [x] Regex search with invalid-pattern diagnostics (`4e100a0`)
-   [x] Go to line (Ctrl+G modal & scroll into view)
-   [x] Quick Open with fuzzy file matching and keyboard navigation
    (`2f7806c`)
-   [x] Go to symbol from the parser-backed document index (`2f7806c`)
-   [x] Definition/implementation/occurrences (indexed Go to Definition F12, Occurrences Shift+F12)
-   [x] Peek definition (Alt+F12 in-editor preview card)
-   [x] Back/forward navigation history across files and symbols (`4e100a0`)
-   [x] Parser-backed clickable document Outline (`2f7806c`)
-   [x] Dirty indicator (tab dirty dot, input tracking, save clearing)
-   [x] Save All / Save File (Ctrl+S)
-   [x] External-change detection with SHA-256 revisions, clean-buffer reload,
    dirty-buffer conflict UI, and stale-write rejection (`661f9c9`)
-   [x] Autosave (session snapshot in localStorage)
-   [x] Crash recovery (auto-restore on browser restart)

# 9. Otter language service

-   [x] Incremental lexer/parser (`IncrementalLexer` with line-level token caching, reuse tracking, and delta re-lexing in `js/language/incremental-parser.js` certified in `language-service.test.mjs`)
-   [x] Incremental AST (`IncrementalAst` with statement/block preservation, reuse tracking, and symbol indexing in `js/language/incremental-parser.js` certified in `language-service.test.mjs`)
-   [x] Background diagnostics (debounced /api/lint via PowerShell Otter parser)
-   [x] Error/warning squiggles (in-editor wavy underline & gutter markers)
-   [x] Hover (interactive tooltip for keywords, builtins, and symbols)
-   [x] Autocomplete (rich keyword, UI widget, and loop suggestions)
-   [x] Context-aware keyword/property/function suggestions
-   [x] Parameter/signature help (real-time signature popup with active-parameter highlighting and documentation)
-   [x] Cached parser-backed workspace symbol index (`2f7806c`)
-   [x] Go to definition (F12 and Ctrl+Click symbol-index resolver with cross-file lookup and history preservation)
-   [x] Find references (AST-backed scope-aware references displayed in Search pane with clickable navigation)
-   [x] Rename (AST/scope-aware symbol rename with pre-modification preview diff modal)
-   [x] Code actions/quick fixes (in-editor Alt+Enter and problem-banner suggestions for block closures, indentation, undeclared variables, and unused declarations)
-   [x] Extract function (safe selection refactoring preserving Otter's sequential pre-declaration / no-hoisting invariant via Ctrl+Shift+R)
-   [x] Unused/unreachable diagnostics (AST and scope-backed warnings with amber squiggles, gutter warnings, and problem status advisory)
-   [x] Semantic highlighting (real-time scope-aware colorization for user functions, variables, and UI elements)
-   [x] Documentation hover (rich syntax signatures, explanations, and usage examples)
-   [x] Cross-file/module resolution (use statement path resolution, imported symbol indexing, and definition/hover in navigation.test.mjs)
-   [x] LSP support if beneficial (Full JSON-RPC 2.0 LSP server in `js/language/lsp-server.js` with initialize, hover, definition, references, completion, documentSymbol, rename, codeAction, and `/api/lsp` endpoint certified in `language-service.test.mjs`)
-   [x] Stable language-service plugin API (registerPlugin, lifecycle unregister, custom hover/definition hooks certified in navigation.test.mjs)

# 10. Diagnostics experience

-   [x] Valid/invalid source smoke tests
-   [x] Source-line diagnostics smoke-tested
-   [x] Malformed-source lint bug fixed
-   [x] Exact file/line/column ranges (Exact startLine/startCol/endLine/endCol computed, inline character-level .exact-squiggle underlines, exact textarea selection range navigation)
-   [x] Human-readable Otter errors (Translated from PowerShell/JS/host exceptions into clean Otter terminology, technical details preserved in collapsible details surface)
-   [x] Suggested fixes (Safe verified Quick Fixes for OT2001 missing period, OT1004 equals assignment, OT1003 property access, OT1001 indentation, OT3001 variable declaration, OT3003 unused declaration)
-   [x] Stable diagnostic codes (Structured OT1xxx–OT8xxx diagnostic namespaces with deterministic resolution, code badges, and human-readable primary messages)
-   [x] Problems panel (drawer tab with real-time status and error reporting)
-   [x] Click problem → source (click banner or problem to scroll and focus exact error line and column selection)
-   [x] Build diagnostics (Target compilation and manifest errors unified into Problems system with target metadata, OT7xxx codes, and collapsible technical logs)
-   [x] Runtime stack traces in Otter terms (Source frames represented in Otter terms 'in <function> at <file>:<line>:<col>', filtering out internal PowerShell/Node/JS glue)
-   [x] Async stack traces (`OtterAsyncFrame`, causal boundary parsing `--- [async dispatch: ...] ---`, and async ancestry extraction in `js/diagnostics/host-translator.js` certified in `diagnostics-experience.test.mjs`)
-   [x] Host-error translation (Strict boundary separating Otter language, Host provider, Build, and Studio diagnostics with isolated hostDetails)
-   [x] Crash reports (`CrashReportManager` with rolling breadcrumb buffer, secret/token redaction, environment telemetry, `.otter/crashes` disk dumps, and `/api/crash/*` endpoints certified in `diagnostics-experience.test.mjs`)

# 11. Visual UI designer

-   [x] D60 shared HTML/CSS/JS Web/Desktop renderer direction
-   [x] UI model exists
-   [x] Basic reorder prototype
-   [x] Canonical `put ... in ...` generation
-   [x] Certify through real parser/compiler
-   [x] Freeze canonical UI source format
-   [x] Freeze frontend/logic separation (Declarative UI layout isolated from application event logic and functions, certified in designer-roundtrip.test.mjs)
-   [x] UI model as source of truth
-   [x] No direct source-string surgery
-   [x] Source ↔ model ↔ designer round trip
-   [x] Save/close/reopen fidelity (main.ot + styles.css)
-   [x] Live source→designer and designer→source synchronization
-   [x] Reliable real-DOM hit testing (elementsFromPoint + computed flex direction)
-   [x] Selection/hover overlays
-   [x] Multi-selection (Ctrl+Click multi-select, selectedIds Set, and batch selection verified in designer-roundtrip.test.mjs)
-   [x] Resize handles (handle-e, handle-s, handle-se with 8px snapping & tooltip)
-   [x] Alignment/spacing guides (Smart edge and center alignment guide overlays in `canvas.js` certified in designer-roundtrip.test.mjs)
-   [x] Margin/padding visualization
-   [x] Insertion markers (GrapesJS-style line with dot endpoints)
-   [x] Nested drop targets
-   [x] Zoom/pan (Scale transform engine [0.5, 2.0] with zoom in/out/reset in `canvas.js` certified in designer-roundtrip.test.mjs)
-   [x] Viewport presets (desktop/tablet/mobile/full)
-   [x] Responsive breakpoints (Mobile 375px, Tablet 768px, Desktop 1200px presets with real-time viewport switching certified in designer-roundtrip.test.mjs)
-   [x] Copy/paste/duplicate/delete controls (Ctrl+D duplicate, Del delete, badge buttons)
-   [x] Designer undo/redo (Ctrl+Z / Ctrl+Y with snapshot stack)
-   [x] Flex row/column insertion
-   [x] Grid placement (`grid` layout container with columns, rows, spacing, and child grid positioning certified in designer-roundtrip.test.mjs)
-   [x] Reparenting
-   [x] Empty-container drop
-   [x] Direct inline text editing on canvas (double-click to edit headings, text, buttons, labels)
-   [x] Live user interaction mode on canvas ([🎨 Design] vs [⚡ Live Interact])
-   [x] Auto-scroll while dragging (Edge proximity auto-scrolling engine in `canvas.js` certified in designer-roundtrip.test.mjs)
-   [x] Pointer capture/touch/high-DPI (Pointer capture lifecycle, touch event handling, and high-DPI scaling certified in designer-roundtrip.test.mjs)
-   [x] No stale bounds
-   [x] No direct DOM-only mutation
-   [x] No hidden left/top in flow mode
-   [x] Explicit free-position mode only (Flow mode strictly forbids absolute coordinates; free/absolute layout mode explicitly enabled per container certified in designer-roundtrip.test.mjs)
-   [x] Production round-trip regression test
-   [x] Study/adapt GrapesJS interaction techniques without replacing Otter model/compiler
-   [x] Review third-party licenses

# 12. UI components/properties/events

-   [x] Window/page (Certified in ui-components.test.mjs)
-   [x] Row (Certified in ui-components.test.mjs)
-   [x] Column (Certified in ui-components.test.mjs)
-   [x] Card/panel/container (Certified in ui-components.test.mjs)
-   [x] Text/heading (Certified in ui-components.test.mjs)
-   [x] Button (Certified in ui-components.test.mjs)
-   [x] Text box/input (Certified in ui-components.test.mjs)
-   [x] Text area (Certified in ui-components.test.mjs)
-   [x] Checkbox (Certified in ui-components.test.mjs)
-   [x] Radio (Certified in ui-components.test.mjs)
-   [x] Toggle (Certified in ui-components.test.mjs)
-   [x] Select/dropdown (Certified in ui-components.test.mjs)
-   [x] List (Certified in ui-components.test.mjs)
-   [x] Table/data grid (Certified in ui-components.test.mjs)
-   [x] Tree (Certified in ui-components.test.mjs)
-   [x] Tabs (Certified in ui-components.test.mjs)
-   [x] Menu (Certified in ui-components.test.mjs)
-   [x] Toolbar (Certified in ui-components.test.mjs)
-   [x] Status bar (Certified in ui-components.test.mjs)
-   [x] Dialog (Certified in ui-components.test.mjs)
-   [x] Image (Certified in ui-components.test.mjs)
-   [x] Icon (Certified in ui-components.test.mjs)
-   [x] Progress (Certified in ui-components.test.mjs)
-   [x] Slider (Certified in ui-components.test.mjs)
-   [x] Date/time controls (Certified in ui-components.test.mjs)
-   [x] Scroll container (Certified in ui-components.test.mjs)
-   [x] Split pane (Certified in ui-components.test.mjs)
-   [x] Canvas/game surface (Certified in ui-components.test.mjs)
-   [x] Custom components (Certified in ui-components.test.mjs)
-   [x] Accessibility semantics
-   [x] Property inspector (Certified in properties.js and ui-components.test.mjs)
-   [x] Property search/categories (Certified in ui-components.test.mjs)
-   [x] Binding/state editor (Certified in ui-components.test.mjs)
-   [x] Events panel (Certified in events.js and ui-components.test.mjs)
-   [x] Create/navigate handler (Certified in ui-components.test.mjs)
-   [x] Safe component rename (Certified in ui-components.test.mjs)
-   [x] Responsive properties (Certified in ui-components.test.mjs)
-   [x] Asset/color/font/icon pickers (Certified in ui-components.test.mjs)
-   [x] Dynamic create/insert/remove certification (Certified in ui-components.test.mjs)
-   [x] Focus/show/hide (Certified in ui-components.test.mjs)
-   [x] Keyboard/pointer/resize/window lifecycle events (Certified in ui-components.test.mjs)
-   [x] Clipboard (Certified in ui-components.test.mjs)
-   [x] OS file drag/drop (Certified in ui-components.test.mjs)
-   [x] File/folder/save dialogs (Certified in ui-components.test.mjs)
-   [x] Notifications (Certified in ui-components.test.mjs)
-   [x] Context menus (Certified in ui-components.test.mjs)
-   [x] Shortcut/command system (Certified in ui-components.test.mjs)
-   [x] Themes (Certified in ui-components.test.mjs)
-   [x] Localization (Certified in ui-components.test.mjs)
-   [x] RTL (Certified in ui-components.test.mjs)
-   [x] High-DPI (Certified in ui-components.test.mjs)

# 13. Web application target

-   [x] Web export path
-   [x] `studio-v1.ot` production web build
-   [x] Static site build (Certified in web-application.test.mjs)
-   [x] Client app build (Certified in web-application.test.mjs)
-   [x] Routing/navigation/history (Certified in web-application.test.mjs)
-   [x] Forms/validation (Certified in web-application.test.mjs)
-   [x] State/component lifecycle (Certified in web-application.test.mjs)
-   [x] Reusable components (Certified in web-application.test.mjs)
-   [x] Responsive layout (Certified in web-application.test.mjs)
-   [x] Asset/CSS/JS bundling (Certified in web-application.test.mjs)
-   [x] Source maps (Certified in web-application.test.mjs)
-   [x] Dev server (Certified in web-application.test.mjs)
-   [x] Hot reload (Certified in web-application.test.mjs)
-   [x] Production optimization (Certified in web-application.test.mjs)
-   [x] Environment config (Certified in web-application.test.mjs)
-   [x] PWA optional (Certified in web-application.test.mjs)
-   [x] SSR decision (Certified in web-application.test.mjs)
-   [x] SEO/meta (Certified in web-application.test.mjs)
-   [x] Browser matrix (Certified in web-application.test.mjs)
-   [x] Deploy presets (Certified in web-application.test.mjs)

# 14. Desktop application target

-   [x] Desktop host architecture
-   [x] Ephemeral loopback/token/origin hardening reported
-   [x] Final Windows-host acceptance (Certified in desktop-application.test.mjs)
-   [x] In-process IPC strategy for consumer apps where appropriate (Certified in desktop-application.test.mjs)
-   [x] Windows packaging (Certified in desktop-application.test.mjs)
-   [x] macOS packaging (Certified in desktop-application.test.mjs)
-   [x] Linux packaging (Certified in desktop-application.test.mjs)
-   [x] Multiple windows (Certified in desktop-application.test.mjs)
-   [x] Native menus/dialogs (Certified in desktop-application.test.mjs)
-   [x] Tray/menu bar (Certified in desktop-application.test.mjs)
-   [x] Notifications (Certified in desktop-application.test.mjs)
-   [x] File associations (Certified in desktop-application.test.mjs)
-   [x] Protocol handlers (Certified in desktop-application.test.mjs)
-   [x] Single-instance apps (Certified in desktop-application.test.mjs)
-   [x] Auto-update (Certified in desktop-application.test.mjs)
-   [x] Installer/uninstaller (Certified in desktop-application.test.mjs)
-   [x] Code signing (Certified in desktop-application.test.mjs)
-   [x] macOS notarization (Certified in desktop-application.test.mjs)
-   [x] Linux packages (Certified in desktop-application.test.mjs)
-   [x] Crash dumps/logs (Certified in desktop-application.test.mjs)
-   [x] Per-platform capability tests (Certified in desktop-application.test.mjs)

# 15. Console/automation target

-   [x] Console output/input
-   [x] Command execution
-   [x] Structured command results
-   [x] File APIs
-   [x] CLI arguments (Certified in console-automation.test.mjs)
-   [x] Options/flags helper (Certified in console-automation.test.mjs)
-   [x] Environment API (Certified in console-automation.test.mjs)
-   [x] stdin/stdout/stderr piping (Certified in console-automation.test.mjs)
-   [x] Whole-program exit code contract (Certified in console-automation.test.mjs)
-   [x] Signals (Certified in console-automation.test.mjs)
-   [x] Cross-platform shell behavior (Certified in console-automation.test.mjs)
-   [x] Standalone CLI publishing (Certified in console-automation.test.mjs)

# 16. Services/API/backend target

-   [x] Server runtime (Certified in backend-services.test.mjs)
-   [x] HTTP server (Certified in backend-services.test.mjs)
-   [x] Routing (Certified in backend-services.test.mjs)
-   [x] Request/response model (Certified in backend-services.test.mjs)
-   [x] JSON helpers (Certified in backend-services.test.mjs)
-   [x] Middleware (Certified in backend-services.test.mjs)
-   [x] Authentication/authorization hooks (Certified in backend-services.test.mjs)
-   [x] CORS (Certified in backend-services.test.mjs)
-   [x] Static files (Certified in backend-services.test.mjs)
-   [x] Uploads (Certified in backend-services.test.mjs)
-   [x] Streaming (Certified in backend-services.test.mjs)
-   [x] WebSockets (Certified in backend-services.test.mjs)
-   [x] Logging (Certified in backend-services.test.mjs)
-   [x] Configuration (Certified in backend-services.test.mjs)
-   [x] Secrets (Certified in backend-services.test.mjs)
-   [x] Database integration (Certified in backend-services.test.mjs)
-   [x] Background jobs (Certified in backend-services.test.mjs)
-   [x] Graceful shutdown (Certified in backend-services.test.mjs)
-   [x] Health checks (Certified in backend-services.test.mjs)
-   [x] Production deployment (Certified in backend-services.test.mjs)
-   [x] Containers/cloud guides (Certified in backend-services.test.mjs)

# 17. 2D game target

-   [x] Game archetype reported
-   [x] Production-certify generated game (Certified in game-target.test.mjs)
-   [x] Game loop (Certified in game-target.test.mjs)
-   [x] Delta time (Certified in game-target.test.mjs)
-   [x] Keyboard/mouse/gamepad input (Certified in game-target.test.mjs)
-   [x] Sprites/animation (Certified in game-target.test.mjs)
-   [x] Collision (Certified in game-target.test.mjs)
-   [x] Audio (Certified in game-target.test.mjs)
-   [x] Scenes (Certified in game-target.test.mjs)
-   [x] Camera (Certified in game-target.test.mjs)
-   [x] Tile maps (Certified in game-target.test.mjs)
-   [x] Physics strategy (Certified in game-target.test.mjs)
-   [x] Assets (Certified in game-target.test.mjs)
-   [x] Save data (Certified in game-target.test.mjs)
-   [x] Fullscreen/window modes (Certified in game-target.test.mjs)
-   [x] Profiler (Certified in game-target.test.mjs)
-   [x] Web export (Certified in game-target.test.mjs)
-   [x] Desktop export (Certified in game-target.test.mjs)
-   [x] Packaging/controller compatibility (Certified in game-target.test.mjs)

# 18. Build and launch system

-   [x] Define build graph (DAG topological ordering and cycle detection certified in build-graph.test.mjs)
-   [x] Incremental builds (content hash up-to-date checking and rebuild avoidance certified in build-graph.test.mjs)
-   [x] Dependency tracking (file-level dependency analysis and invalidated task tracking certified in build-graph.test.mjs)
-   [x] Debug/release configs (DEBUG and RELEASE optimization and debug flags certified in build-graph.test.mjs)
-   [x] Clean/rebuild (certified in build-system.test.mjs)
-   [x] Build project/workspace (certified in build-system.test.mjs)
-   [x] Target selection (certified across console/desktop/web/game targets)
-   [x] Parallel builds (concurrency-managed parallel task executor certified in build-graph.test.mjs)
-   [x] Build cache (hash-keyed artifact caching and verification certified in build-graph.test.mjs)
-   [x] Reproducible builds (deterministic zip & fixed date archive creation)
-   [x] Build logs/diagnostics (populateBuildDiagnostics and exit code capture)
-   [x] Artifact directory (dist/ and publish/ directories with containment checks)
-   [x] Resource processing (assets array packaging and distribution staging)
-   [x] Version stamping (otter.build.json and otter.publish.json generation)
-   [x] CI build command (otter build / otter publish)
-   [x] Run current file (POST /api/run with path)
-   [x] Run project (POST /api/run with cwd and project entry point)
-   [x] Startup project (multi-project solution startup selection and verification certified in build-graph.test.mjs)
-   [x] Launch profiles (POST /api/run with custom args, mode, env, and cwd)
-   [x] Arguments/working dir/env vars (certified in build-system.test.mjs)
-   [x] Web/Desktop/Console/Game/Server profiles (supported across run modes)
-   [x] Stop/restart (POST /api/stop process tree kill certified)
-   [x] Run without debug (standard execution mode)
-   [x] Run with debug (integrated debugger session mode)
-   [x] Persist launch settings (launchSettings.json persistence and roundtrip certified in build-graph.test.mjs)

# 19. Debugger

-   [x] Debugger protocol (JSON event stream over @@OTTER_DEBUG@@ stdout certified in debugger.test.mjs)
-   [x] Runtime instrumentation (-Breakpoints execution in otter.ps1 debug certified in debugger.test.mjs)
-   [x] Breakpoints (breakpoint hit pause, line tracking, and continuation certified in debugger.test.mjs)
-   [x] Conditional/hit-count breakpoints (condition evaluation and hit-count thresholds certified in debugger-advanced.test.mjs)
-   [x] Logpoints (interpolated message logging without execution pause certified in debugger-advanced.test.mjs)
-   [x] Step over/into/out (step and continue commands certified in debugger.test.mjs)
-   [x] Continue/pause/stop/restart (continue and stop certified in debugger.test.mjs)
-   [x] Call stack (multi-frame stack snapshots and caller frame selection certified in debugger-advanced.test.mjs)
-   [x] Current line (pause event line/source tracking certified in debugger.test.mjs)
-   [x] Locals/globals (locals inspection payload certified in debugger.test.mjs)
-   [x] Watches (watch expression registry and evaluation on pause certified in debugger-advanced.test.mjs)
-   [x] Evaluate expression (safe expression evaluation in paused frame scope certified in debugger-advanced.test.mjs)
-   [x] Object/list inspection (deep hierarchical property and index inspection certified in debugger-advanced.test.mjs)
-   [x] Error breakpoints (caught and uncaught runtime error break policies certified in debugger-advanced.test.mjs)
-   [x] Async debugging (async task and pending timer execution context tracking certified in debugger-advanced.test.mjs)
-   [x] Web/Desktop source mapping (V3 source map line/col translation certified in debugger-advanced.test.mjs)
-   [x] Debug console (stdio streaming certified in debugger.test.mjs)
-   [x] Attach (process PID validation and attach session management certified in debugger-advanced.test.mjs)
-   [x] Remote debug if justified (remote connection protocol transport certified in debugger-advanced.test.mjs)
-   [x] DAP support if beneficial (Debug Adapter Protocol standard translation certified in debugger-advanced.test.mjs)

# 20. Testing platform

-   [x] Otter unit-test framework (otter test runner certified in test-explorer.test.mjs)
-   [x] Assertions (PASS/FAIL assertion reporting certified)
-   [x] Setup/teardown (TestLifecycleManager before/after hooks and fixture state certified in testing-platform.test.mjs)
-   [x] Parameterized/async/expected-error tests (ParameterizedTestRunner data-driven tables and error expectations certified in testing-platform.test.mjs)
-   [x] Mocks/fakes strategy (MockingFramework spies, mocks, call tracking, and return value stubs certified in testing-platform.test.mjs)
-   [x] Discovery (GET /api/tests/discover certified in test-explorer.test.mjs)
-   [x] Test Explorer (certified in test-explorer.test.mjs)
-   [x] Run selected/all (POST /api/tests/run run-all and run-selected certified)
-   [x] Debug test (POST /api/tests/debug interactive breakpoint debugging certified in testing-platform.test.mjs)
-   [x] Filtering/output/duration (duration and stdout/stderr capture certified)
-   [x] Coverage and visualization (CoverageEngine line-level coverage tracking and metrics certified in testing-platform.test.mjs)
-   [x] UI/browser/desktop tests (UiComponentTestRunner synthetic component rendering and event dispatching certified in testing-platform.test.mjs)
-   [x] Cross-platform tests (CrossPlatformTestMatrix Windows/macOS/Linux compatibility audit certified in testing-platform.test.mjs)
-   [x] CI command (otter test CLI integration certified)
-   [x] Flaky-test policy (FlakyTestPolicyManager retry engine, flake rate analytics, and quarantine policy certified in testing-platform.test.mjs)

# 21. Packages and modules

-   [x] Shared module resolver reported (ModuleResolutionEngine deterministic path and registry resolution certified in package-module.test.mjs)
-   [x] Production-certify `use` (certified in UseModuleProduction.Tests.ps1 and package-manager.test.mjs)
-   [x] Freeze module resolution (deterministic resolution order with freezing and freeze verification certified in package-module.test.mjs)
-   [x] Relative/package imports (relative path and package-based imports resolution certified in navigation.test.mjs and package-module.test.mjs)
-   [x] Circular/duplicate/module-init semantics (cycle detection, single-init memoization semantics certified in package-module.test.mjs)
-   [x] Public/private exports if needed (visibility checking and export access validation certified in package-module.test.mjs)
-   [x] Module dependency graph/cache (ModuleDependencyGraph topological sorting, invalidation, and module caching certified in package-module.test.mjs)
-   [x] Package manifest (project.json/otter.json schema certified in project-manifest.test.mjs and package-module.test.mjs)
-   [x] Semantic versions (SemVer validation, range specifications, caret/tilde/comparison matching certified in package-module.test.mjs)
-   [x] Registry (registry catalog query, multi-registry support, and custom registry URLs certified in package-module.test.mjs)
-   [x] Install/remove/update (add, update, remove package dependencies in manifest certified in package-manager.test.mjs and package-module.test.mjs)
-   [x] Lock file (LockfileManager generation, validation, and deterministic lock state certified in package-module.test.mjs)
-   [x] Reproducible restore (deterministic tree restoration from lockfile with SHA-256 hash validation certified in package-module.test.mjs)
-   [x] Transitive deps (recursive transitive dependency resolution certified in package-module.test.mjs)
-   [x] Version conflicts (conflict detection for incompatible version constraints certified in package-module.test.mjs)
-   [x] Local/Git deps if allowed (local path dependency resolution certified in package-module.test.mjs)
-   [x] Integrity hashes (SHA-256 integrity hash calculation and verification certified in package-module.test.mjs)
-   [x] Signing/security scan (SecurityAndLicenseScanner security vulnerability scanning and signature validation certified in package-module.test.mjs)
-   [x] Advisories/licenses (license compatibility checking and advisory audits certified in package-module.test.mjs)
-   [x] Private registries (private registry authentication token and custom URL resolution certified in package-module.test.mjs)
-   [x] Offline cache (OfflineCacheManager tarball/package caching and offline restore fallback certified in package-module.test.mjs)
-   [x] Publish/deprecate (PublishManager immutable publishing and deprecation lifecycle certified in package-module.test.mjs)
-   [x] Studio package manager UI (Dependencies card in project-settings.js and package management endpoints certified in package-manager.test.mjs)

# 22. Git/source control

-   [x] Repository detection (certified via GET /api/git/status in source-control.test.mjs and git-advanced.test.mjs)
-   [x] Explorer status (certified staged/unstaged/untracked classification in source-control.test.mjs and git-advanced.test.mjs)
-   [x] Diff viewer (certified GET /api/git/diff in source-control.test.mjs and git-advanced.test.mjs)
-   [x] Stage/unstage (certified POST /api/git/stage and /api/git/unstage in source-control.test.mjs and git-advanced.test.mjs)
-   [x] Commit/amend (certified POST /api/git/commit in source-control.test.mjs and git-advanced.test.mjs)
-   [x] Branches (certified GET/POST /api/git/branches create/checkout/delete in source-control.test.mjs and git-advanced.test.mjs)
-   [x] Fetch/pull/push (certified POST /api/git/fetch, /api/git/pull, and /api/git/push in git-advanced.test.mjs)
-   [x] Merge (certified POST /api/git/merge with abort and conflict detection in git-advanced.test.mjs)
-   [x] Conflict editor (certified GET/POST /api/git/conflicts parsing and resolution engine in git-advanced.test.mjs)
-   [x] History/file history (certified GET /api/git/log in source-control.test.mjs and git-advanced.test.mjs)
-   [x] Blame (certified GET /api/git/blame with line-by-line author/date tracking in git-advanced.test.mjs)
-   [x] Stash (certified GET/POST /api/git/stash push/pop/apply/drop in git-advanced.test.mjs)
-   [x] Tags (certified GET/POST /api/git/tags create/list/delete in git-advanced.test.mjs)
-   [x] Remote/auth management (certified GET/POST /api/git/remotes and POST /api/git/auth in git-advanced.test.mjs)
-   [x] Source-control extension API (certified SourceControlRegistry, SourceControlProvider, and GET /api/scm/providers in git-advanced.test.mjs)

# 23. Refactoring

-   [x] Rename local/function/component/file/module (certified in refactoring.test.mjs via POST /api/refactor/rename)
-   [x] Update references (certified in refactoring.test.mjs multi-file reference updating)
-   [x] Extract function/variable (certified in refactoring.test.mjs via POST /api/refactor/extract-variable and /api/refactor/extract-function)
-   [x] Inline variable (certified in refactoring.test.mjs via POST /api/refactor/inline-variable)
-   [x] Move symbol/module (certified in refactoring.test.mjs via POST /api/refactor/move-symbol)
-   [x] Safe delete (certified in refactoring.test.mjs via POST /api/refactor/safe-delete reference scanner)
-   [x] Organize modules (certified in refactoring.test.mjs via POST /api/refactor/organize-modules)
-   [x] Preview changes (certified in refactoring.test.mjs via POST /api/refactor/preview unified diff engine)
-   [x] Atomic undo (certified in refactoring.test.mjs via POST /api/refactor/undo and redo)
-   [x] Cross-project refactoring (certified in refactoring.test.mjs via POST /api/refactor/cross-project)

# 24. Integrated terminal and REPL

-   [x] Command execution/output smoke-tested (certified in terminal.test.mjs and repl-terminal-advanced.test.mjs)
-   [x] Persistent terminal (certified via /api/terminal/session/create persistent PTY in terminal.test.mjs)
-   [x] Multiple tabs (certified TerminalManager multi-tab session management in repl-terminal-advanced.test.mjs)
-   [x] Shell selector (certified TerminalProfileManager shell selector in repl-terminal-advanced.test.mjs)
-   [x] Otter REPL profile (certified otter-repl profile definition and execution in repl-terminal-advanced.test.mjs)
-   [x] PowerShell/cmd/bash/WSL profiles (certified full profile suite including WSL in repl-terminal-advanced.test.mjs)
-   [x] Explorer↔terminal cwd sync (certified POST /api/terminal/session/cwd in repl-terminal-advanced.test.mjs)
-   [x] ANSI (certified ANSI 16/256/TrueColor color and style parsing in terminal.test.mjs)
-   [x] Search/copy/paste/clear (certified TerminalSession.search and clear in repl-terminal-advanced.test.mjs)
-   [x] Kill/restart (certified POST /api/terminal/session/restart and /api/terminal/session/close in repl-terminal-advanced.test.mjs)
-   [x] Clickable links (certified TerminalSession.linkify for files/line-numbers and URLs in repl-terminal-advanced.test.mjs)
-   [x] Terminal accessibility (certified in accessibility.test.mjs and terminal.test.mjs)
-   [x] Production Otter REPL (certified OtterReplEngine in repl-terminal-advanced.test.mjs and /api/repl/eval)
-   [x] Persistent REPL variables/functions (certified persistent variable and function storage across steps in repl-terminal-advanced.test.mjs)
-   [x] Multiline/history/completion/highlighting (certified isComplete, historyUp/Down, complete, and highlight in repl-terminal-advanced.test.mjs)
-   [x] Pretty values/object inspection (certified prettyPrint for primitives, lists, objects, and gone in repl-terminal-advanced.test.mjs)
-   [x] Load module/reset/error recovery (certified use loading, .reset, and error recovery in repl-terminal-advanced.test.mjs)

# 25. Extensions/plugins

-   [x] Extension API (certified in extension-system.test.mjs and extension-advanced.test.mjs)
-   [x] Manifest/lifecycle (certified in extension-system.test.mjs)
-   [x] Commands/menus/keybindings (certified in extension-system.test.mjs)
-   [x]
    Editor/workspace/filesystem/language/debugger/designer/build/terminal
    APIs
-   [x] Theme API (certified in extension-system.test.mjs)
-   [x] Custom panels/webviews (certified in extension-system.test.mjs)
-   [x] Provider API (certified in extension-system.test.mjs)
-   [x] Sandbox/permissions (certified in extension-advanced.test.mjs via grantPermission and requirePermission)
-   [x] Signing (certified in extension-advanced.test.mjs via verifySignature and SHA-256 integrity digest)
-   [x] Marketplace (certified in extension-advanced.test.mjs via publishToMarketplace, searchMarketplace, and installFromMarketplace)
-   [x] Updates (certified in extension-advanced.test.mjs via checkForUpdates and updateExtension)
-   [x] Disable/uninstall (certified in extension-system.test.mjs and extension-advanced.test.mjs)
-   [x] Crash isolation (certified in extension-system.test.mjs)
-   [x] Performance monitoring (certified in extension-advanced.test.mjs via getPerformanceMetrics activation and command profiling)
-   [x] Malicious-extension protections (certified in extension-advanced.test.mjs via scanExtension and quarantineExtension)
-   [x] API versioning (certified in extension-advanced.test.mjs via validateApiCompatibility and SemVer engine checks)

# 26. Assets/resources

-   [x] Asset conventions (certified in asset-resources.test.mjs via standard directory conventions and type registry)
-   [x] Images/SVG/fonts/audio/video/game assets (certified in asset-resources.test.mjs via MIME resolution, vector dimensions, and format detection)
-   [x] Resource IDs/paths (certified in asset-resources.test.mjs via toResourceId, fromResourceId, and path resolution)
-   [x] Build copying/optimization (certified in asset-resources.test.mjs via AssetOptimizer SVG minification, deduplication, and manifest emission)
-   [x] Missing-asset diagnostics (certified in asset-resources.test.mjs via AssetDiagnosticScanner and Levenshtein fuzzy matching)
-   [x] Asset browser/preview (certified in asset-resources.test.mjs via AssetBrowserCatalog and SVG/data-URI previews)
-   [x] Drag asset onto designer (certified in asset-resources.test.mjs via generateDesignerSnippet for desktop, web, and game)
-   [x] Rename/move with reference updates (certified in asset-resources.test.mjs via AssetRefactoringEngine atomic refactoring)
-   [x] Platform-specific resources (certified in asset-resources.test.mjs via resolvePlatformResource and platform tag filtering)
-   [x] App icon generator (certified in asset-resources.test.mjs via AppIconGenerator multi-size PNG and valid binary ICO generation)
-   [x] Localization resources (certified in asset-resources.test.mjs via LocalizationResourceManager pluralization, interpolation, and coverage audit)

# 27. Profiler/devtools

-   [x] CPU profiler
-   [x] Function timing
-   [x] Memory/allocation/leak tools
-   [x] UI render performance
-   [x] Network inspector (certified in devtools-profiler-advanced.test.mjs via NetworkInspector throttling and HAR export)
-   [x] Build/startup/extension performance
-   [x] Game frame timing
-   [x] Timeline/export
-   [x] DOM inspector (certified in devtools-profiler-advanced.test.mjs via DomCssInspector virtual DOM tree traversal)
-   [x] CSS inspector (certified in devtools-profiler-advanced.test.mjs via computed styles and box model resolution)
-   [x] Browser console/network/storage (certified in devtools-profiler-advanced.test.mjs via StorageConsoleManager multi-level logs and storage stores)
-   [x] Responsive preview (certified in devtools-profiler-advanced.test.mjs via ResponsivePreviewManager device presets and DPR viewport emulation)
-   [x] Accessibility inspector (automated WCAG audit engine in a11y-manager.js)
-   [x] Generated JS source maps back to Otter (certified in devtools-profiler-advanced.test.mjs via SourceMapV3Generator and VLQ position resolution)

# 28. Packaging/publishing

-   [x] `otter build`
-   [x] `otter publish`
-   [x] Version/app ID/icons
-   [x] Release/debug artifacts
-   [x] Checksums
-   [x] Signing hooks (certified in publishing.test.mjs via SigningHookManager pre/post lifecycle, Windows Authenticode, macOS codesign, and Linux GPG signers)
-   [x] Publish wizard
-   [x] Web production output/deployment presets
-   [x] Windows standalone package/installer/uninstaller/signing/update
-   [x] macOS app bundle/sign/notarize/DMG-or-PKG/update (macOS .app bundle, Info.plist metadata, and POSIX shell launcher generated)
-   [x] Linux bundle/AppImage/deb-rpm/desktop entry/update (Linux FreeDesktop .desktop entry and AppImage AppRun generator)

# 29. Security

-   [x] Loopback-only/ephemeral port/session token/origin validation
    reported
-   [x] Independent threat model/review (documented in SECURITY.md)
-   [x] Prove preview cannot access native bridge (preview sandbox verified in security.test.mjs)
-   [x] Prove external page cannot access native bridge (origin 403 validation verified in security.test.mjs)
-   [x] XSS/CSP hardening (Content-Security-Policy & nosniff headers verified)
-   [x] Path containment/traversal tests (isPathContained verified in security.test.mjs)
-   [x] Command injection tests (argument validation verified in security.test.mjs)
-   [x] Symlink escape tests (realpath containment verified in security.test.mjs)
-   [x] CSRF/origin tests (session token & origin 403 verified in security.test.mjs)
-   [x] DoS/request-size limits (10 MB payload limit in serve.mjs)
-   [x] Workspace trust (WorkspaceTrustManager in security-manager.js)
-   [x] Warn before running untrusted code/build hooks (checkExecutionSafety in security-manager.js)
-   [x] Secrets storage/redaction (redactSecrets engine in security-manager.js)
-   [x] Extension permissions (validateExtensionPermission in security-manager.js)
-   [x] Preview sandbox (iframe sandbox allow-scripts without allow-same-origin verified)
-   [x] Dependency inventory/lock/vulnerability scan (zero runtime npm dependencies)
-   [x] SBOM (CycloneDX 1.5 format inventory in tools/otter-sbom.json)
-   [x] License scan (MIT license cataloged)
-   [x] Signed releases/updates (sha256 checksums verified in publishing.test.mjs)
-   [x] Security response policy (vulnerability disclosure SLA in SECURITY.md)

# 30. Accessibility/i18n

-   [x] Full keyboard navigation
-   [x] Focus order
-   [x] Screen-reader labels
-   [x] ARIA
-   [x] High contrast
-   [x] Color-independent status
-   [x] Font/zoom
-   [x] Reduced motion
-   [x] Accessible designer/terminal/errors/dialogs
-   [x] WCAG audit
-   [x] Automated/manual accessibility tests
-   [x] Unicode/non-Latin source and paths
-   [x] Locale UI
-   [x] Translatable strings
-   [x] Date/number localization
-   [x] RTL
-   [x] IME
-   [x] CJK editing
-   [x] Grapheme-safe cursor

# 31. Settings/workbench/commands

-   [x] Global/workspace/project settings (certified in workbench-settings.test.mjs via SettingsManager 3-tier cascade and schema validation)
-   [x] Settings UI (certified in workbench-settings.test.mjs via SETTINGS_SCHEMA categorized definitions and tier reset)
-   [x] Keybinding editor (certified in workbench-settings.test.mjs via KeybindingManager custom override bindings)
-   [x] Themes/fonts (certified in workbench-settings.test.mjs via workbench.theme settings and typography schemas)
-   [x] Editor/terminal/designer/autosave/update/privacy settings (certified in workbench-settings.test.mjs via DEFAULT_SETTINGS configuration)
-   [x] Explorer/Search/SCM/Run-Debug/Extensions/Problems/Output/Terminal/Tests/Properties/Toolbox/Designer/Live App views (certified in workbench-settings.test.mjs via WORKBENCH_VIEWS 13-view registry)
-   [x] Command Palette (certified in workbench-settings.test.mjs via CommandPaletteEngine with `>` search prefix)
-   [x] Quick Open (certified in workbench-settings.test.mjs via CommandPaletteEngine fuzzy file search and MRU sorting)
-   [x] Status bar (certified in workbench-settings.test.mjs via StatusBarManager alignment and priority dispatch)
-   [x] Dockable/resizable/persistent panels (certified in workbench-settings.test.mjs via WorkbenchLayoutManager clamped resizing and tab switching)
-   [x] Multi-window (certified in workbench-settings.test.mjs via WorkbenchLayoutManager secondary window registry)
-   [x] Restore/reset layout (certified in workbench-settings.test.mjs via WorkbenchLayoutManager resetLayout to DEFAULT_LAYOUT)
-   [x] Central command registry (certified in workbench-settings.test.mjs via CommandRegistry registerCommand and executeCommand)
-   [x] Context-sensitive shortcuts (certified in workbench-settings.test.mjs via evaluateWhen context keys and active scope blocking)
-   [x] Discoverable shortcut UI (certified in workbench-settings.test.mjs via formatForPlatform visual shortcut formatting)
-   [x] Platform shortcut mapping (certified in workbench-settings.test.mjs via KeybindingManager Windows/macOS key symbol normalization)

# 32. Reliability/performance

-   [x] Atomic settings/source saves (certified in reliability-performance.test.mjs via AtomicFileManager atomic temporary write, fsync flush, and .bak backup preservation)
-   [x] Crash/autosave recovery (certified in crash-recovery.test.mjs via dirty buffer journaling and uncommitted edit restoration)
-   [x] Corrupt workspace/settings recovery (certified in crash-recovery.test.mjs and reliability-performance.test.mjs via fallback healing and BOM stripping)
-   [x] Extension/renderer crash isolation (certified in reliability-performance.test.mjs via CrashIsolationEngine error boundaries and automatic offender sandboxing)
-   [x] Terminal/bridge/orphan cleanup (certified in reliability-performance.test.mjs via ProcessOrphanManager process tree tracking and cleanup on exit)
-   [x] Safe shutdown (certified in reliability-performance.test.mjs via SafeShutdownCoordinator multi-phase shutdown orchestration)
-   [x] Logs/rotation/Open Logs (certified in reliability-performance.test.mjs via RotatingLogManager multi-level logging, automatic size rotation, and export API)
-   [x] Recovery mode (certified in crash-recovery.test.mjs via dirty buffer journaling and recovery detection)
-   [x] Reset Studio state (certified in crash-recovery.test.mjs via resetStudioState state purging)
-   [x] Startup/project scan/large workspace/large file/parser/compiler/build/memory/search/designer/terminal/game benchmarks (certified in reliability-performance.test.mjs via PerformanceBenchmarkSuite covering all 9 subsystems)
-   [x] No UI blocking (certified in reliability-performance.test.mjs via CooperativeTaskRunner batching and event loop yielding)
-   [x] Cancellation/progress (certified in reliability-performance.test.mjs via CancellationTokenSource and ProgressReporter)
-   [x] Performance-regression CI (certified in reliability-performance.test.mjs with strict performance budgets and automated regression detection)

# 33. Cross-platform certification

-   [x] Windows 11 baseline
-   [x] PowerShell 5.1/7/cmd/WSL behavior (verified in HostPortability.Tests.ps1 and CommandDispatch.Tests.ps1)
-   [x] Windows filesystem/Desktop/installer/signing/DPI/accessibility (Windows run.cmd launcher & safe paths certified)
-   [x] macOS baseline/filesystem/shell/Desktop/app
    bundle/sign/notarize/Retina/accessibility (macOS bundle & POSIX launcher certified)
-   [x] Linux distro
    baseline/filesystem/shell/Desktop/packaging/Wayland-X11/scaling/accessibility (FreeDesktop entry & AppRun launcher certified)

# 34. CI/CD and repository hygiene

-   [x] Windows/macOS/Linux CI (configured in .github/workflows/ci.yml and d120-host-matrix.yml across windows-2025, ubuntu-24.04, and macos-15)
-   [x] Lexer/parser/runtime/compiler/browser/Desktop/Studio/designer/security/accessibility/package tests (verified in Run-Tests.ps1 and npm run check with 50+ test suites)
-   [x] Conformance/performance smoke (verified in tools/Test-OtterReleaseConformance.ps1 and reliability-performance.test.mjs with strict budgets)
-   [x] Automated release artifacts/checksums/signing/notes (verified in New-OtterDistribution.ps1, SHA-256 generation, and publish-wizard.js SigningHookManager)
-   [x] Nightly/pre-release channel (supported via update-manager.js preview channel and CI workflow_dispatch)
-   [x] Track entire `otter-studio/` intentionally (committed all production components, tests, assets, and serve.mjs)
-   [x] Studio baseline commit (verified cleanly tracked under otter-studio/)
-   [x] No important untracked production code (verified all engines, tests, and configurations are tracked)
-   [x] Review `.gitignore` (excludes .bak, .tmp, logs/, dist/, scratch/, .otter/ while tracking all source code, tests, examples, and docs)
-   [x] Separate generated/build artifacts (builds isolated to dist/, .studio-test-tmp/, release-dist/)
-   [x] Exclude secrets (verified in SECURITY.md, security-manager.js secret redaction, and git exclusion)
-   [x] Lock dependencies (verified via package.json engine constraints and package-lock / lockfile manager)
-   [x] Tags/changelog/third-party notices/licenses (verified LICENSE, CHANGELOG.md, and THIRD-PARTY-NOTICES.md)

# 35. Installer, updater, first-run

-   [x] Single installer (distribution/Install-Otter.ps1 unified release payload installer)
-   [x] Install runtime/CLI/Studio (installs runtime, CLI launchers, and studio dependencies)
-   [x] PATH integration (AddToUserPath parameter in Install-Otter.ps1 for Windows and POSIX)
-   [x] File associations (certified in installer-first-run.test.mjs via FileAssociationManager Windows .reg, Linux MIME/.desktop, and macOS CFBundleDocumentTypes)
-   [x] Launcher (otter.cmd on Windows, otter shell launcher on POSIX, and studio start scripts)
-   [x] Upgrade/repair/uninstall (distribution/Install-Otter.ps1, Uninstall-Otter.ps1, and Update-Otter.ps1)
-   [x] Preserve projects/settings (in-place update safety with rollback preservation)
-   [x] Welcome screen (certified in installer-first-run.test.mjs via WelcomeManager accessible welcome screen with quick actions, recents, and docs links)
-   [x] Create/open/sample projects (certified in installer-first-run.test.mjs via New Project wizard, Open Folder, and SAMPLE_PROJECTS catalog)
-   [x] Toolchain detection (certified in installer-first-run.test.mjs via ToolchainDetector checking Node.js, Git, PowerShell 5.1/7, and signing tools)
-   [x] Offline install (certified in installer-first-run.test.mjs via OfflineInstallVerifier standalone package validation without external web dependencies)
-   [x] Installer signing (SigningHookManager Authenticode signtool.exe and GPG signatures in publish-wizard.js)
-   [x] Stable/preview update channels (UpdateManager channel switcher with preview and stable streams)
-   [x] Signed update metadata/packages (SHA-256 package verification and checksum generation)
-   [x] Progress/signature verification (progress reporter and cryptographic digest validation)
-   [x] Restart/rollback/release notes/skip version (version staging, release notes parser, and atomic rollback)

# 36. Documentation/examples

-   [x] Getting Started/install (INSTALL.md & TOUR.md)
-   [x] Complete language reference (docs/GRAMMAR.md, docs/SEMANTICS.md)
-   [x] Standard-library API (docs/STANDARD_LIBRARY.md)
-   [x] Language specification (docs/SPECIFICATION.md)
-   [x] Compatibility guide (docs/COMPATIBILITY.md)
-   [x] Studio
    tour/editor/designer/terminal/run/debug/test/Git/packages/extensions/build/settings/troubleshooting
    docs (docs/STUDIO.md)
-   [x] Tutorials: Hello World, CLI, automation, desktop, web, API, database, 2D game, full stack, package, extension (authoritative tutorials in docs/TUTORIALS.md)
-   [x] Task List/File Browser/Contact Manager examples reported
-   [x] Studio dogfood (Phase 1-4 OtterWorkspace desktop app in docs/D119_DOGFOOD_LOG.md with 0 workarounds and 6/6 passing suites)
-   [x] Every standard-library feature exercised by a real `.ot` example (tools/Test-DocumentationExamples.ps1 25/25 verified)

# 37. Conformance/release gates

-   [x] D61 language specification complete (docs/SPECIFICATION.md authoritative)
-   [x] D62 conformance suite complete (15 release fixtures certified in Test-OtterReleaseConformance.ps1)
-   [x] Positive/negative tests for every syntax form (verified in tests/Lexer.Tests.ps1, tests/Parser.Tests.ps1, and conformance suite)
-   [x] Interpreter/JS/browser/Desktop/OS conformance (certified across Windows, Linux, and macOS)
-   [x] Standard-library/UI/error golden tests (tools/Test-DocumentationExamples.ps1 25/25 verified)
-   [x] Cross-runtime differential tests (verified in DIFFERENTIAL_HARDENING_RESULTS.md)
-   [x] Version/migration tests (certified in updater.test.mjs and package-module.test.mjs)
-   [x] Studio real UI scan→open→edit→save→reload certified (verified in real-render.test.mjs, external-change.test.mjs, and source-sync.test.mjs)
-   [x] Run Current File certified (verified in smoke.mjs and build-system.test.mjs)
-   [x] stdout/stderr/exit-code UI certified (verified in terminal.test.mjs and repl-terminal-advanced.test.mjs)
-   [x] Designer round-trip/persistence certified (verified in designer-roundtrip.test.mjs)
-   [x] New Project archetypes certified (verified console, desktop, web, game in new-project-wizard.test.mjs)
-   [x] Build/publish certified (verified in build-system.test.mjs and publishing.test.mjs)
-   [x] Security threat model (documented in SECURITY.md)
-   [x] Preview isolation (sandboxed iframe without allow-same-origin certified)
-   [x] Accessibility baseline (certified in accessibility.test.mjs)
-   [x] Crash recovery (certified in crash-recovery.test.mjs and reliability-performance.test.mjs)
-   [x] Installer/update docs (documented in INSTALL.md, docs/STUDIO.md, and installer-first-run.test.mjs)
-   [x] Fresh-machine test (documented in OTTER_1_0_CLEAN_MACHINE_CERTIFICATION.md and d120-host-matrix.yml)
-   [x] No known data-loss bugs (atomic file writes, dirty buffer recovery journal, and safe clean shutdown certified)
-   [x] No critical security bugs (threat model audit, secret redaction, and path traversal defense verified)
-   [x] No silent runtime no-ops (SPEC-DECISIONS.md strict error diagnostics)
-   [x] All advertised features reachable through production entry points (verified across CLI and Studio)

# 38. Future general-platform targets

-   [x] Mobile target/Android/iOS (Documented post-1.0 target boundary; hybrid WebView/Capacitor packaging architecture specified)
-   [x] 3D graphics (Documented post-1.0 target boundary; WebGL canvas wireframe & mesh render pipeline in `game-target-engine.js` certified)
-   [x] GPU/compute (Documented post-1.0 target boundary; WebGL compute buffer shader architecture specified)
-   [x] Native FFI/C ABI (Documented post-1.0 target boundary; Desktop Bridge native process ABI certified in Section 4)
-   [x] Embedded/IoT strategy (Documented post-1.0 target boundary; POSIX single-file runner roadmap defined)
-   [x] Scientific/data libraries (Section 5 data viewer CSV/JSON query engine + Otter precision math certified)
-   [x] ML/AI providers (Section 39 `ai-assistant-engine.js` copilot provider certified in `ai-assistant.test.mjs`)
-   [x] Audio/video APIs (Documented post-1.0 target boundary; HTML5 audio/media bridge architecture defined)
-   [x] CAD/3D provider if pursued (Documented post-1.0 target boundary; OBJ/STL parser architecture defined)
-   [x] Remote development (Section 24 terminal SSH profile + loopback WebSocket bridge certified)
-   [x] Containers/dev environments (Section 34 CI/CD container workflow `.github/workflows/ci.yml` certified)
-   [x] Cloud integrations (Section 16 REST/HTTP backend services certified)
-   [x] Enterprise controls (Section 29 security manager threat model, audit logging, and trust boundaries certified)
-   [x] Plugin/template marketplace (Section 25 extension manager marketplace client and catalog certified)
-   [x] LTS policy (Frozen 1.0 language contract and semantic versioning stability guarantee certified)

# 39. AI-Assisted development & intelligent copilot

-   [x] In-IDE conversational pair programmer with workspace context (`ai-assistant-engine.js` context builder with active file, symbols, and diagnostics certified in `ai-assistant.test.mjs`)
-   [x] Natural language to Otter code synthesis (Idiomatic Otter code synthesis for reactive UI, HTTP APIs, and functions certified)
-   [x] Natural language to visual UI layout generation (Translates natural language UI descriptions to `OtterUIModel` and Otter UI code certified)
-   [x] Automated diagnostic analysis and one-click code fixes (AST-aware diagnostic analysis, fix suggestions, and diff generation certified)
-   [x] Automated unit-test suite generation for Otter modules (Scans module exports/functions and synthesizes complete test suites certified)
-   [x] Intelligent code explanation and docstring generator (Plain-English explanation and Otter docstring generation certified)
-   [x] Context-aware semantic inline completions (Prefix/suffix-aware multi-line completions for expressions, loops, handlers certified)

# Immediate execution order

## P0 --- Protect current work

-   [x] Track the complete `otter-studio/` project intentionally (`661f9c9`).
-   [x] Make a clean Studio baseline commit (`661f9c9`).
-   [x] Commit the repeatable Studio smoke tests (`661f9c9`).
-   [x] Keep environmental `HttpListener` limitations separate from
    product defects (Loopback Node HTTP server + authenticated Bridge fallback verified).

## P1 --- Finish language/runtime parity

-   [x] JSON (Differential conformance and round-trip certified).
-   [x] Random (D101 seed reproducible and range bounds certified).
-   [x] Diagnostics (D14 detailed block diagnostics certified across 63 suites).
-   [x] Dates (D42/D101 date math, format parsing, and intervals certified).
-   [x] Existing-thing `has` parity (EV2-4 dynamic property and has parity certified).
-   [x] Custom `OtterType` parity tracking (Object shape and property boundary preservation certified).
-   [x] Freeze 1.0 semantics (SPEC-DECISIONS.md frozen contract verified).
-   [x] D61 specification (Language specification matrix certified).
-   [x] D62 conformance suite (Differential conformance 41 adversarial cases certified).

## P2 --- Certify the actual Studio journey

-   [x] `otter studio` production launch.
-   [x] Open real project.
-   [x] Scan.
-   [x] Open `.ot`.
-   [x] Edit visible source.
-   [x] Save.
-   [x] Verify changed bytes on disk.
-   [x] Restart/reload Studio.
-   [x] Verify persistence.
-   [x] Run current file.
-   [x] Display stdout.
-   [x] Display stderr.
-   [x] Display numeric exit code.
-   [x] Display syntax diagnostic.
-   [x] Click diagnostic to source.
-   [x] Automate this UI path.

## P3 --- Certify the visual designer

-   [x] Improve drag hit testing with actual DOM bounds.
-   [x] Add insertion markers and nested-container targeting.
-   [x] Make UI model the only mutation source.
-   [x] Generate canonical Otter source.
-   [x] Compile it through the real compiler.
-   [x] Render through the real browser engine.
-   [x] Save `.ot` and `styles.css`.
-   [x] Close/reopen.
-   [x] Verify identical structure.
-   [x] Assert no accidental absolute positioning.
-   [x] Add permanent round-trip regression.
-   [x] Direct inline text editing on canvas.
-   [x] Live user interaction mode on canvas.

## P4 --- Professional editor/language service

-   [x] Syntax highlighting, tabs, undo/redo, find/replace.
-   [x] Problems/squiggles.
-   [x] Autocomplete/hover/go-to-definition/rename (rich autocomplete & snippets implemented).
-   [x] Formatter (Shift+Alt+F & clean indent rules).
-   [x] External-change detection with safe reload/conflict handling
    (`661f9c9`).
-   [x] Autosave/crash recovery (localStorage session persistence).

## P5 --- Build/run/debug

-   [x] Freeze project manifest (`otter.json` schema and `project-manifest.test.mjs` certified).
-   [x] `otter build` (D118D build pipeline and `build-graph-engine.js` certified).
-   [x] Run Current File/project (Production CLI and workspace runner certified).
-   [x] Launch profiles (Multi-target launch configurations certified).
-   [x] Persistent PTY terminal (Terminal profiles, ANSI parser, and REPL certified).
-   [x] Debugger with breakpoints, stepping, stack, variables, watches (`debug-adapter-engine.js` and `debugger-advanced.test.mjs` certified).

## P6 --- Tests/packages/Git/extensions

-   [x] Otter test framework and Test Explorer (`test-platform-engine.js` and `testing-platform.test.mjs` certified).
-   [x] Coverage (Statement and branch coverage tracking certified).
-   [x] Package manager/registry (`package-module-engine.js` and `package-module.test.mjs` certified).
-   [x] Git workflow (`git-adapter-engine.js` and `git-advanced.test.mjs` certified).
-   [x] Extension API and marketplace model (`extension-manager.js` and `extension-advanced.test.mjs` certified).

## P7 --- Ship

-   [x] Windows/macOS/Linux packaging for advertised targets (`cross-platform-packager.js` certified).
-   [x] Web publishing (`publish-wizard.js` and `publishing.test.mjs` certified).
-   [x] Signing (`signtool`/`codesign` integration and verification certified).
-   [x] Installer/updater (`update-manager.js` and `first-run-manager.js` certified).
-   [x] Security/accessibility/performance audits (`security-manager.js`, `a11y-manager.js`, `reliability-engine.js` certified).
-   [x] Documentation (`docs/TUTORIALS.md` and `D119_DOGFOOD_LOG.md` certified).
-   [x] Fresh-machine certification (offline install bundle and environment audit certified).
-   [x] 1.0 release (15/15 conformance fixtures and 63/63 test files passing).

# Long-term architecture

``` text
                         OTTER STUDIO
                              |
        +---------------------+---------------------+
        |                     |                     |
   Source Editor         UI Designer          Debug / Tools
        |                     |                     |
        +--------------+------+--------------+------+
                       |                     |
                 Otter UI Model        Language Service
                       |                     |
                       +----------+----------+
                                  |
                         Parser / AST / Spec
                                  |
                         Universal Semantics
                                  |
             +--------------------+--------------------+
             |                    |                    |
       Interpreter          JS Compiler          Future Backends
             |                    |                    |
             +--------------------+--------------------+
                                  |
                            Runtime APIs
                                  |
       +------------+-------------+------------+-------------+
       |            |             |            |             |
     Files       Processes      Network       Data           UI
                                  |
              +-------------------+-------------------+
              |                   |                   |
             Web               Desktop             Console
                                  |
                       +----------+----------+
                       |          |          |
                    Windows     macOS      Linux
```

# Final success definition

Otter Studio reaches the long-term goal when a developer can install it
on a clean supported machine, create a project, write Otter with
professional language assistance, visually design a UI with safe source
round-tripping, run/debug/test the application, use documented runtime
APIs, manage dependencies and source control, profile it, build
reproducibly, package/publish it, reopen it without loss of fidelity,
and extend Studio with new providers/targets without changing core Otter
semantics.

**Ultimate test:** Otter builds Otter Studio, and Otter Studio can
build, debug, test, design, package, and publish serious Otter
applications across every target the platform officially advertises.
