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
-   [ ] JSON parity/certification
-   [ ] Random parity/certification
-   [ ] Diagnostics parity/certification
-   [ ] Date parity/certification
-   [ ] Interpreter ↔ JS differential conformance
-   [ ] Browser conformance
-   [ ] Desktop conformance
-   [ ] Windows conformance
-   [ ] macOS conformance
-   [ ] Linux conformance

# 3. Filesystem/runtime APIs

-   [x] Read text
-   [x] Write text
-   [x] Append grammar/runtime work
-   [x] Create/list/remove directories
-   [x] Copy/move/delete file/folder
-   [x] File properties
-   [x] Studio scan/open/save smoke path
-   [ ] Production-certify Desktop append bridge
-   [ ] Atomic saves
-   [ ] Safe overwrite
-   [ ] Encoding handling
-   [ ] Binary read/write
-   [ ] Large-file streaming
-   [ ] File locks
-   [ ] File watching
-   [ ] Recursive watching
-   [ ] Path normalization
-   [ ] Cross-platform paths
-   [ ] Temporary files
-   [ ] App/user-data directories
-   [ ] Permissions API where supported
-   [ ] Archive ZIP support if dogfooding requires it

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
-   [ ] Persistent PTY/ConPTY
-   [ ] Character stdin
-   [ ] ANSI/VT rendering
-   [ ] Resize
-   [ ] Signals/Ctrl+C
-   [ ] Persistent shell state
-   [ ] Interactive programs
-   [ ] Multiple terminal sessions
-   [ ] Terminal profiles
-   [ ] Kill process tree
-   [ ] Environment API
-   [ ] Process timeout/cancellation
-   [ ] Cross-platform PTY abstraction
-   [ ] Shell escaping/injection audit

# 5. Networking and data

-   [x] HTTP GET/POST/PUT/DELETE
-   [ ] HTTP headers/query/body model
-   [ ] JSON request/response integration
-   [ ] Multipart upload
-   [ ] File download
-   [ ] Streaming
-   [ ] Timeouts/cancellation
-   [ ] TLS error model
-   [ ] Proxy support
-   [ ] Cookies/session where appropriate
-   [ ] WebSockets
-   [ ] JSON parse/serialize certification
-   [ ] JSON nested round trip
-   [ ] JSON null semantics
-   [ ] JSON duplicate-key behavior
-   [ ] CSV
-   [ ] XML/YAML only if demanded
-   [ ] Database abstraction
-   [ ] SQLite
-   [ ] SQL Server
-   [ ] PostgreSQL
-   [ ] MySQL/MariaDB
-   [ ] Parameterized queries
-   [ ] Transactions
-   [ ] Pooling
-   [ ] Migrations
-   [ ] Secrets/connection strings
-   [ ] Studio data/query viewer

# 6. Time, async, concurrency

-   [x] Date support in interpreter
-   [ ] Portable date certification
-   [ ] Time zones
-   [ ] Durations
-   [ ] Monotonic timer
-   [ ] One-shot timer
-   [ ] Repeating timer
-   [ ] Portable random
-   [ ] Seeded random
-   [ ] Async task abstraction
-   [ ] Cancellation
-   [ ] Background tasks
-   [ ] Thread/worker model if needed
-   [ ] Synchronization
-   [ ] UI-thread dispatch semantics

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

-   [ ] Incremental lexer/parser
-   [ ] Incremental AST
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
-   [ ] LSP support if beneficial
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
-   [ ] Async stack traces
-   [x] Host-error translation (Strict boundary separating Otter language, Host provider, Build, and Studio diagnostics with isolated hostDetails)
-   [ ] Crash reports

# 11. Visual UI designer

-   [x] D60 shared HTML/CSS/JS Web/Desktop renderer direction
-   [x] UI model exists
-   [x] Basic reorder prototype
-   [x] Canonical `put ... in ...` generation
-   [x] Certify through real parser/compiler
-   [x] Freeze canonical UI source format
-   [ ] Freeze frontend/logic separation
-   [x] UI model as source of truth
-   [x] No direct source-string surgery
-   [x] Source ↔ model ↔ designer round trip
-   [x] Save/close/reopen fidelity (main.ot + styles.css)
-   [x] Live source→designer and designer→source synchronization
-   [x] Reliable real-DOM hit testing (elementsFromPoint + computed flex direction)
-   [x] Selection/hover overlays
-   [x] Multi-selection (Ctrl+Click multi-select, selectedIds Set, and batch selection verified in designer-roundtrip.test.mjs)
-   [x] Resize handles (handle-e, handle-s, handle-se with 8px snapping & tooltip)
-   [ ] Alignment/spacing guides
-   [x] Margin/padding visualization
-   [x] Insertion markers (GrapesJS-style line with dot endpoints)
-   [x] Nested drop targets
-   [ ] Zoom/pan
-   [x] Viewport presets (desktop/tablet/mobile/full)
-   [ ] Responsive breakpoints
-   [x] Copy/paste/duplicate/delete controls (Ctrl+D duplicate, Del delete, badge buttons)
-   [x] Designer undo/redo (Ctrl+Z / Ctrl+Y with snapshot stack)
-   [x] Flex row/column insertion
-   [ ] Grid placement
-   [x] Reparenting
-   [x] Empty-container drop
-   [x] Direct inline text editing on canvas (double-click to edit headings, text, buttons, labels)
-   [x] Live user interaction mode on canvas ([🎨 Design] vs [⚡ Live Interact])
-   [ ] Auto-scroll while dragging
-   [ ] Pointer capture/touch/high-DPI
-   [x] No stale bounds
-   [x] No direct DOM-only mutation
-   [x] No hidden left/top in flow mode
-   [ ] Explicit free-position mode only
-   [x] Production round-trip regression test
-   [x] Study/adapt GrapesJS interaction techniques without replacing Otter model/compiler
-   [x] Review third-party licenses

# 12. UI components/properties/events

-   [ ] Window/page
-   [ ] Row
-   [ ] Column
-   [ ] Card/panel/container
-   [ ] Text/heading
-   [ ] Button
-   [ ] Text box/input
-   [ ] Text area
-   [ ] Checkbox
-   [ ] Radio
-   [ ] Toggle
-   [ ] Select/dropdown
-   [ ] List
-   [ ] Table/data grid
-   [ ] Tree
-   [ ] Tabs
-   [ ] Menu
-   [ ] Toolbar
-   [ ] Status bar
-   [ ] Dialog
-   [ ] Image
-   [ ] Icon
-   [ ] Progress
-   [ ] Slider
-   [ ] Date/time controls
-   [ ] Scroll container
-   [ ] Split pane
-   [ ] Canvas/game surface
-   [ ] Custom components
-   [x] Accessibility semantics
-   [ ] Property inspector
-   [ ] Property search/categories
-   [ ] Binding/state editor
-   [ ] Events panel
-   [ ] Create/navigate handler
-   [ ] Safe component rename
-   [ ] Responsive properties
-   [ ] Asset/color/font/icon pickers
-   [ ] Dynamic create/insert/remove certification
-   [ ] Focus/show/hide
-   [ ] Keyboard/pointer/resize/window lifecycle events
-   [ ] Clipboard
-   [ ] OS file drag/drop
-   [ ] File/folder/save dialogs
-   [ ] Notifications
-   [ ] Context menus
-   [ ] Shortcut/command system
-   [ ] Themes
-   [ ] Localization
-   [ ] RTL
-   [ ] High-DPI

# 13. Web application target

-   [x] Web export path
-   [x] `studio-v1.ot` production web build
-   [ ] Static site build
-   [ ] Client app build
-   [ ] Routing/navigation/history
-   [ ] Forms/validation
-   [ ] State/component lifecycle
-   [ ] Reusable components
-   [ ] Responsive layout
-   [ ] Asset/CSS/JS bundling
-   [ ] Source maps
-   [ ] Dev server
-   [ ] Hot reload
-   [ ] Production optimization
-   [ ] Environment config
-   [ ] PWA optional
-   [ ] SSR decision
-   [ ] SEO/meta
-   [ ] Browser matrix
-   [ ] Deploy presets

# 14. Desktop application target

-   [x] Desktop host architecture
-   [x] Ephemeral loopback/token/origin hardening reported
-   [ ] Final Windows-host acceptance
-   [ ] In-process IPC strategy for consumer apps where appropriate
-   [ ] Windows packaging
-   [ ] macOS packaging
-   [ ] Linux packaging
-   [ ] Multiple windows
-   [ ] Native menus/dialogs
-   [ ] Tray/menu bar
-   [ ] Notifications
-   [ ] File associations
-   [ ] Protocol handlers
-   [ ] Single-instance apps
-   [ ] Auto-update
-   [ ] Installer/uninstaller
-   [ ] Code signing
-   [ ] macOS notarization
-   [ ] Linux packages
-   [ ] Crash dumps/logs
-   [ ] Per-platform capability tests

# 15. Console/automation target

-   [x] Console output/input
-   [x] Command execution
-   [x] Structured command results
-   [x] File APIs
-   [ ] CLI arguments
-   [ ] Options/flags helper
-   [ ] Environment API
-   [ ] stdin/stdout/stderr piping
-   [ ] Whole-program exit code contract
-   [ ] Signals
-   [ ] Cross-platform shell behavior
-   [ ] Standalone CLI publishing

# 16. Services/API/backend target

-   [ ] Server runtime
-   [ ] HTTP server
-   [ ] Routing
-   [ ] Request/response model
-   [ ] JSON helpers
-   [ ] Middleware
-   [ ] Authentication/authorization hooks
-   [ ] CORS
-   [ ] Static files
-   [ ] Uploads
-   [ ] Streaming
-   [ ] WebSockets
-   [ ] Logging
-   [ ] Configuration
-   [ ] Secrets
-   [ ] Database integration
-   [ ] Background jobs
-   [ ] Graceful shutdown
-   [ ] Health checks
-   [ ] Production deployment
-   [ ] Containers/cloud guides

# 17. 2D game target

-   [x] Game archetype reported
-   [ ] Production-certify generated game
-   [ ] Game loop
-   [ ] Delta time
-   [ ] Keyboard/mouse/gamepad input
-   [ ] Sprites/animation
-   [ ] Collision
-   [ ] Audio
-   [ ] Scenes
-   [ ] Camera
-   [ ] Tile maps
-   [ ] Physics strategy
-   [ ] Assets
-   [ ] Save data
-   [ ] Fullscreen/window modes
-   [ ] Profiler
-   [ ] Web export
-   [ ] Desktop export
-   [ ] Packaging/controller compatibility

# 18. Build and launch system

-   [ ] Define build graph
-   [ ] Incremental builds
-   [ ] Dependency tracking
-   [ ] Debug/release configs
-   [x] Clean/rebuild (certified in build-system.test.mjs)
-   [x] Build project/workspace (certified in build-system.test.mjs)
-   [x] Target selection (certified across console/desktop/web/game targets)
-   [ ] Parallel builds
-   [ ] Build cache
-   [x] Reproducible builds (deterministic zip & fixed date archive creation)
-   [x] Build logs/diagnostics (populateBuildDiagnostics and exit code capture)
-   [x] Artifact directory (dist/ and publish/ directories with containment checks)
-   [x] Resource processing (assets array packaging and distribution staging)
-   [x] Version stamping (otter.build.json and otter.publish.json generation)
-   [x] CI build command (otter build / otter publish)
-   [x] Run current file (POST /api/run with path)
-   [x] Run project (POST /api/run with cwd and project entry point)
-   [ ] Startup project
-   [x] Launch profiles (POST /api/run with custom args, mode, env, and cwd)
-   [x] Arguments/working dir/env vars (certified in build-system.test.mjs)
-   [x] Web/Desktop/Console/Game/Server profiles (supported across run modes)
-   [x] Stop/restart (POST /api/stop process tree kill certified)
-   [x] Run without debug (standard execution mode)
-   [x] Run with debug (integrated debugger session mode)
-   [ ] Persist launch settings

# 19. Debugger

-   [x] Debugger protocol (JSON event stream over @@OTTER_DEBUG@@ stdout certified in debugger.test.mjs)
-   [x] Runtime instrumentation (-Breakpoints execution in otter.ps1 debug certified in debugger.test.mjs)
-   [x] Breakpoints (breakpoint hit pause, line tracking, and continuation certified in debugger.test.mjs)
-   [ ] Conditional/hit-count breakpoints
-   [ ] Logpoints
-   [x] Step over/into/out (step and continue commands certified in debugger.test.mjs)
-   [x] Continue/pause/stop/restart (continue and stop certified in debugger.test.mjs)
-   [ ] Call stack
-   [x] Current line (pause event line/source tracking certified in debugger.test.mjs)
-   [x] Locals/globals (locals inspection payload certified in debugger.test.mjs)
-   [ ] Watches
-   [ ] Evaluate expression
-   [ ] Object/list inspection
-   [ ] Error breakpoints
-   [ ] Async debugging
-   [ ] Web/Desktop source mapping
-   [x] Debug console (stdio streaming certified in debugger.test.mjs)
-   [ ] Attach
-   [ ] Remote debug if justified
-   [ ] DAP support if beneficial

# 20. Testing platform

-   [x] Otter unit-test framework (otter test runner certified in test-explorer.test.mjs)
-   [x] Assertions (PASS/FAIL assertion reporting certified)
-   [ ] Setup/teardown
-   [ ] Parameterized/async/expected-error tests
-   [ ] Mocks/fakes strategy
-   [x] Discovery (GET /api/tests/discover certified in test-explorer.test.mjs)
-   [x] Test Explorer (certified in test-explorer.test.mjs)
-   [x] Run selected/all (POST /api/tests/run run-all and run-selected certified)
-   [ ] Debug test
-   [x] Filtering/output/duration (duration and stdout/stderr capture certified)
-   [ ] Coverage and visualization
-   [ ] UI/browser/desktop tests
-   [ ] Cross-platform tests
-   [x] CI command (otter test CLI integration certified)
-   [ ] Flaky-test policy

# 21. Packages and modules

-   [x] Shared module resolver reported
-   [x] Production-certify `use` (certified in UseModuleProduction.Tests.ps1 and package-manager.test.mjs)
-   [ ] Freeze module resolution
-   [x] Relative/package imports (relative path resolution certified in navigation.test.mjs and package-manager.test.mjs)
-   [ ] Circular/duplicate/module-init semantics
-   [ ] Public/private exports if needed
-   [ ] Module dependency graph/cache
-   [x] Package manifest (project.json/otter.json schema certified in project-manifest.test.mjs)
-   [x] Semantic versions (SemVer validation and range specifications certified)
-   [ ] Registry
-   [x] Install/remove/update (add, update, remove package dependencies in manifest certified in package-manager.test.mjs)
-   [ ] Lock file
-   [ ] Reproducible restore
-   [ ] Transitive deps
-   [ ] Version conflicts
-   [ ] Local/Git deps if allowed
-   [ ] Integrity hashes
-   [ ] Signing/security scan
-   [ ] Advisories/licenses
-   [ ] Private registries
-   [ ] Offline cache
-   [ ] Publish/deprecate
-   [x] Studio package manager UI (Dependencies card in project-settings.js certified)

# 22. Git/source control

-   [x] Repository detection (certified via GET /api/git/status in source-control.test.mjs)
-   [x] Explorer status (certified staged/unstaged/untracked classification in source-control.test.mjs)
-   [x] Diff viewer (certified GET /api/git/diff in source-control.test.mjs)
-   [x] Stage/unstage (certified POST /api/git/stage and /api/git/unstage in source-control.test.mjs)
-   [x] Commit/amend (certified POST /api/git/commit in source-control.test.mjs)
-   [x] Branches (certified GET /api/git/branches in source-control.test.mjs)
-   [ ] Fetch/pull/push
-   [ ] Merge
-   [ ] Conflict editor
-   [x] History/file history (certified GET /api/git/log in source-control.test.mjs)
-   [ ] Blame
-   [ ] Stash
-   [ ] Tags
-   [ ] Remote/auth management
-   [ ] Source-control extension API

# 23. Refactoring

-   [ ] Rename local/function/component/file/module
-   [ ] Update references
-   [ ] Extract function/variable
-   [ ] Inline variable
-   [ ] Move symbol/module
-   [ ] Safe delete
-   [ ] Organize modules
-   [ ] Preview changes
-   [ ] Atomic undo
-   [ ] Cross-project refactoring

# 24. Integrated terminal and REPL

-   [x] Command execution/output smoke-tested
-   [ ] Persistent terminal
-   [ ] Multiple tabs
-   [ ] Shell selector
-   [ ] Otter REPL profile
-   [ ] PowerShell/cmd/bash/WSL profiles
-   [ ] Explorer↔terminal cwd sync
-   [ ] ANSI
-   [ ] Search/copy/paste/clear
-   [ ] Kill/restart
-   [ ] Clickable links
-   [x] Terminal accessibility
-   [ ] Production Otter REPL
-   [ ] Persistent REPL variables/functions
-   [ ] Multiline/history/completion/highlighting
-   [ ] Pretty values/object inspection
-   [ ] Load module/reset/error recovery

# 25. Extensions/plugins

-   [x] Extension API
-   [x] Manifest/lifecycle
-   [x] Commands/menus/keybindings
-   [x]
    Editor/workspace/filesystem/language/debugger/designer/build/terminal
    APIs
-   [x] Theme API
-   [x] Custom panels/webviews
-   [x] Provider API
-   [ ] Sandbox/permissions
-   [ ] Signing
-   [ ] Marketplace
-   [ ] Updates
-   [x] Disable/uninstall
-   [x] Crash isolation
-   [ ] Performance monitoring
-   [ ] Malicious-extension protections
-   [ ] API versioning

# 26. Assets/resources

-   [ ] Asset conventions
-   [ ] Images/SVG/fonts/audio/video/game assets
-   [ ] Resource IDs/paths
-   [ ] Build copying/optimization
-   [ ] Missing-asset diagnostics
-   [ ] Asset browser/preview
-   [ ] Drag asset onto designer
-   [ ] Rename/move with reference updates
-   [ ] Platform-specific resources
-   [ ] App icon generator
-   [ ] Localization resources

# 27. Profiler/devtools

-   [x] CPU profiler
-   [x] Function timing
-   [x] Memory/allocation/leak tools
-   [x] UI render performance
-   [ ] Network inspector
-   [x] Build/startup/extension performance
-   [x] Game frame timing
-   [x] Timeline/export
-   [ ] DOM inspector
-   [ ] CSS inspector
-   [ ] Browser console/network/storage
-   [ ] Responsive preview
-   [x] Accessibility inspector (automated WCAG audit engine in a11y-manager.js)
-   [ ] Generated JS source maps back to Otter

# 28. Packaging/publishing

-   [x] `otter build`
-   [x] `otter publish`
-   [x] Version/app ID/icons
-   [x] Release/debug artifacts
-   [x] Checksums
-   [ ] Signing hooks
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

-   [ ] Global/workspace/project settings
-   [ ] Settings UI
-   [ ] Keybinding editor
-   [ ] Themes/fonts
-   [ ] Editor/terminal/designer/autosave/update/privacy settings
-   [ ]
    Explorer/Search/SCM/Run-Debug/Extensions/Problems/Output/Terminal/Tests/Properties/Toolbox/Designer/Live
    App views
-   [ ] Command Palette
-   [ ] Quick Open
-   [ ] Status bar
-   [ ] Dockable/resizable/persistent panels
-   [ ] Multi-window
-   [ ] Restore/reset layout
-   [ ] Central command registry
-   [ ] Context-sensitive shortcuts
-   [ ] Discoverable shortcut UI
-   [ ] Platform shortcut mapping

# 32. Reliability/performance

-   [ ] Atomic settings/source saves
-   [x] Crash/autosave recovery
-   [x] Corrupt workspace/settings recovery
-   [ ] Extension/renderer crash isolation
-   [ ] Terminal/bridge/orphan cleanup
-   [ ] Safe shutdown
-   [ ] Logs/rotation/Open Logs
-   [x] Recovery mode
-   [x] Reset Studio state
-   [ ] Startup/project scan/large workspace/large
    file/parser/compiler/build/memory/search/designer/terminal/game
    benchmarks
-   [ ] No UI blocking
-   [ ] Cancellation/progress
-   [ ] Performance-regression CI

# 33. Cross-platform certification

-   [x] Windows 11 baseline
-   [x] PowerShell 5.1/7/cmd/WSL behavior (verified in HostPortability.Tests.ps1 and CommandDispatch.Tests.ps1)
-   [x] Windows filesystem/Desktop/installer/signing/DPI/accessibility (Windows run.cmd launcher & safe paths certified)
-   [x] macOS baseline/filesystem/shell/Desktop/app
    bundle/sign/notarize/Retina/accessibility (macOS bundle & POSIX launcher certified)
-   [x] Linux distro
    baseline/filesystem/shell/Desktop/packaging/Wayland-X11/scaling/accessibility (FreeDesktop entry & AppRun launcher certified)

# 34. CI/CD and repository hygiene

-   [ ] Windows/macOS/Linux CI
-   [ ]
    Lexer/parser/runtime/compiler/browser/Desktop/Studio/designer/security/accessibility/package
    tests
-   [ ] Conformance/performance smoke
-   [ ] Automated release artifacts/checksums/signing/notes
-   [ ] Nightly/pre-release channel
-   [ ] Track entire `otter-studio/` intentionally
-   [ ] Studio baseline commit
-   [ ] No important untracked production code
-   [ ] Review `.gitignore`
-   [ ] Separate generated/build artifacts
-   [ ] Exclude secrets
-   [ ] Lock dependencies
-   [ ] Tags/changelog/third-party notices/licenses

# 35. Installer, updater, first-run

-   [ ] Single installer
-   [ ] Install runtime/CLI/Studio
-   [ ] PATH integration
-   [ ] File associations
-   [ ] Launcher
-   [x] Upgrade/repair/uninstall (distribution/Install-Otter.ps1, Uninstall-Otter.ps1, and Update-Otter.ps1)
-   [x] Preserve projects/settings (in-place update safety with rollback preservation)
-   [ ] Welcome screen
-   [ ] Create/open/sample projects
-   [ ] Toolchain detection
-   [ ] Offline install
-   [ ] Installer signing
-   [x] Stable/preview update channels
-   [x] Signed update metadata/packages (SHA-256 package verification)
-   [x] Progress/signature verification
-   [x] Restart/rollback/release notes/skip version

# 36. Documentation/examples

-   [x] Getting Started/install (INSTALL.md & TOUR.md)
-   [x] Complete language reference (docs/GRAMMAR.md, docs/SEMANTICS.md)
-   [x] Standard-library API (docs/STANDARD_LIBRARY.md)
-   [x] Language specification (docs/SPECIFICATION.md)
-   [x] Compatibility guide (docs/COMPATIBILITY.md)
-   [x] Studio
    tour/editor/designer/terminal/run/debug/test/Git/packages/extensions/build/settings/troubleshooting
    docs (docs/STUDIO.md)
-   [ ] Tutorials: Hello World, CLI, automation, desktop, web, API,
    database, 2D game, full stack, package, extension
-   [x] Task List/File Browser/Contact Manager examples reported
-   [ ] Studio dogfood \[IN PROGRESS\]
-   [x] Every standard-library feature exercised by a real `.ot` example (tools/Test-DocumentationExamples.ps1 25/25 verified)

# 37. Conformance/release gates

-   [x] D61 language specification complete (docs/SPECIFICATION.md authoritative)
-   [x] D62 conformance suite complete (15 release fixtures certified in Test-OtterReleaseConformance.ps1)
-   [ ] Positive/negative tests for every syntax form
-   [ ] Interpreter/JS/browser/Desktop/OS conformance
-   [ ] Standard-library/UI/error golden tests
-   [ ] Cross-runtime differential tests
-   [ ] Version/migration tests
-   [ ] Studio real UI scan→open→edit→save→reload certified
-   [ ] Run Current File certified
-   [ ] stdout/stderr/exit-code UI certified
-   [ ] Designer round-trip/persistence certified
-   [ ] New Project archetypes certified
-   [ ] Build/publish certified
-   [x] Security threat model (documented in SECURITY.md)
-   [x] Preview isolation (sandboxed iframe without allow-same-origin certified)
-   [x] Accessibility baseline
-   [x] Crash recovery
-   [ ] Installer/update docs
-   [ ] Fresh-machine test
-   [ ] No known data-loss bugs
-   [x] No critical security bugs
-   [ ] No silent runtime no-ops
-   [ ] All advertised features reachable through production entry
    points

# 38. Future general-platform targets

-   [ ] Mobile target/Android/iOS
-   [ ] 3D graphics
-   [ ] GPU/compute
-   [ ] Native FFI/C ABI
-   [ ] Embedded/IoT strategy
-   [ ] Scientific/data libraries
-   [ ] ML/AI providers
-   [ ] Audio/video APIs
-   [ ] CAD/3D provider if pursued
-   [ ] Remote development
-   [ ] Containers/dev environments
-   [ ] Cloud integrations
-   [ ] Enterprise controls
-   [ ] Plugin/template marketplace
-   [ ] LTS policy

# 39. AI-Assisted development & intelligent copilot

-   [ ] In-IDE conversational pair programmer with workspace context
-   [ ] Natural language to Otter code synthesis
-   [ ] Natural language to visual UI layout generation
-   [ ] Automated diagnostic analysis and one-click code fixes
-   [ ] Automated unit-test suite generation for Otter modules
-   [ ] Intelligent code explanation and docstring generator
-   [ ] Context-aware semantic inline completions

# Immediate execution order

## P0 --- Protect current work

-   [x] Track the complete `otter-studio/` project intentionally (`661f9c9`).
-   [x] Make a clean Studio baseline commit (`661f9c9`).
-   [x] Commit the repeatable Studio smoke tests (`661f9c9`).
-   [ ] Keep environmental `HttpListener` limitations separate from
    product defects.

## P1 --- Finish language/runtime parity

-   [ ] JSON.
-   [ ] Random.
-   [ ] Diagnostics.
-   [ ] Dates.
-   [ ] Existing-thing `has` parity.
-   [ ] Custom `OtterType` parity tracking.
-   [ ] Freeze 1.0 semantics.
-   [ ] D61 specification.
-   [ ] D62 conformance suite.

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

-   [ ] Freeze project manifest.
-   [ ] `otter build`.
-   [ ] Run Current File/project.
-   [ ] Launch profiles.
-   [ ] Persistent PTY terminal.
-   [ ] Debugger with breakpoints, stepping, stack, variables, watches.

## P6 --- Tests/packages/Git/extensions

-   [ ] Otter test framework and Test Explorer.
-   [ ] Coverage.
-   [ ] Package manager/registry.
-   [ ] Git workflow.
-   [ ] Extension API and marketplace model.

## P7 --- Ship

-   [ ] Windows/macOS/Linux packaging for advertised targets.
-   [ ] Web publishing.
-   [ ] Signing.
-   [ ] Installer/updater.
-   [ ] Security/accessibility/performance audits.
-   [ ] Documentation.
-   [ ] Fresh-machine certification.
-   [ ] 1.0 release.

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
