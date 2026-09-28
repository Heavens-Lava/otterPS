# Otter Studio --- Professional IDE Master Requirements & Certification Checklist

**Status date:** September 27, 2026\
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
-   [ ] New Project wizard with Console/Desktop/Web/2D Game archetypes
    \[DONE, needs production certification per archetype\]
-   [x] Professional source editor (Complete Section 8 certification)
-   [ ] Language intelligence
-   [ ] Debugger
-   [ ] Production visual UI designer
-   [ ] Build system
-   [ ] Package/dependency manager
-   [ ] Test explorer
-   [ ] Source-control integration
-   [ ] Extension/plugin system
-   [ ] Profiler
-   [ ] Publishing/deployment
-   [ ] Cross-platform distribution
-   [ ] Accessibility certification
-   [ ] Security audit
-   [ ] Crash recovery/autosave
-   [ ] Stable language specification
-   [ ] Conformance suite
-   [ ] Updater
-   [ ] Complete docs

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
-   [ ] Resolve existing-thing `has` replacement parity
-   [ ] Portable custom `OtterType` parity
-   [ ] Freeze remaining 1.0 grammar
-   [ ] Publish formal grammar
-   [ ] Publish semantic specification
-   [ ] Publish AST contract
-   [ ] Publish diagnostic contract
-   [ ] Versioned compatibility/deprecation policy
-   [ ] Freeze Unicode/string behavior
-   [ ] Freeze numeric precision/range behavior
-   [ ] Freeze equality/order behavior
-   [ ] Document copy/reference semantics
-   [ ] Binary/byte data
-   [ ] Streams for large data

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
-   [ ] Recycle-bin/trash delete instead of permanent delete where the OS supports it

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
-   [x] New Project opens the created project like File > Open (Welcome closes, chip and Recent Projects update, template projects trusted) and never overwrites an existing project: 409 with "Open it instead", free name suggested (`3dc9f8a`; verified through the real dialog)
-   [ ] New Project location picker (create outside the repo's `projects/` folder)
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
-   [x] Validate names and overwrite safety (sanitizing names and directory bounds; creating over an existing project is refused with 409 since `ede1a52`, certified by source-preservation.test.mjs)
-   [x] Recent/pinned projects (session & localStorage tracking)
-   [x] Freeze project manifest (project.json metadata)
-   [x] Project version/entry point/target/dependencies/assets/build
    config/permissions metadata (Rich schema, dual-mode Settings visual inspector / raw JSON editor, live sync, validation diagnostics, certified via project-manifest.test.mjs)
-   [x] Workspace/multi-project solution format (Standard solution.json schema, folder mapping, and /api/workspace API certified via workspace-solution.test.mjs)
-   [x] Workspace settings/trust (Restricted Mode security banner, Run & Terminal execution safety guards, workspace settings overrides)
-   [x] Multi-root workspaces (Multi-root tree explorer with Solution header and multiple project roots, unified cross-project search and symbol index)
-   [x] Restore session (localStorage session recovery)
-   [x] Large-repo performance (Bounded scanDir with exclusion of .git, node_modules, dist, max depth and node limits guaranteeing sub-second response)
-   [x] Explorer file management: new file, new folder, rename, delete to recycle bin (`bc955d1`; right-click, F2, Del; open tabs follow)
-   [x] Explorer move by drag and drop between folders (`bc955d1`)
-   [ ] Explorer copy (Ctrl+drag / copy-paste of files)
-   [x] Reveal in OS file manager / copy path / copy relative path (`bc955d1`)
-   [x] Per-file local history (timeline) independent of Git, with restore (d409eda; File > Local History, Explorer menu, compare + restore)
-   [x] `.editorconfig` support and auto-detect indentation per file (3f46d74; status-bar indentation menu)
-   [ ] Workspace-recommended settings and extensions

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
-   [ ] Code folding for blocks, functions, and comment regions
-   [ ] Minimap
-   [x] Indent guides (Settings > Editor; `editing-assist.test.mjs`)
-   [x] Render-whitespace toggle (`91b8ee2`; Settings > Editor and the palette)
-   [ ] Sticky scroll (current block header pinned while scrolling)
-   [x] Auto-closing quotes/parentheses and auto-insert of the block-terminating period (wrap selection, step over closers, delete pairs; Enter after a block opener writes the body line and `.`; `editing-assist.test.mjs`, verified by typing in the real editor)
-   [ ] User-defined snippets with a snippet editor and tab stops
-   [x] Standalone diff editor: compare two files, compare with saved, compare with Git HEAD (`645e3d3`; side by side, next/previous change)
-   [x] Format on save, trim trailing whitespace, insert final newline (Settings > Files; applied before the file is written; verified through the real Save path)
-   [ ] Formatter style settings
-   [x] Bookmarks with next/previous navigation (`91b8ee2`; Ctrl+Alt+K / L / J, gutter marks, per file)
-   [x] TODO/FIXME comment scanner panel (`91b8ee2`; Tasks tab: TODO, FIXME, BUG, HACK, NOTE, most urgent first)
-   [x] Link detection: Ctrl+Click URLs and file paths in source (`91b8ee2`; URLs open in the browser, quoted workspace paths open in the editor)
-   [ ] Inlay hints (parameter names, inferred values)
-   [ ] Code lens (reference counts, run/debug test above functions)
-   [ ] Editor groups: drag tab to split, grid layouts, pinned tabs, preview tabs, Open Editors list
-   [x] Search in selection, preserve case on replace, multi-line search (`645e3d3`; plus match case, whole word, regex groups; find widget wired up for the first time)
-   [ ] Search include/exclude globs that honor `.gitignore`
-   [ ] Drag-and-drop text editing
-   [x] Editor font size (Settings > Editor, 12-15 px; code layer, input and gutter stay aligned)

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
-   [ ] Cross-file/module resolution
-   [ ] LSP support if beneficial
-   [ ] Stable language-service plugin API
-   [ ] Otter doc-comment syntax so user functions show documentation on hover
-   [ ] Call hierarchy (incoming/outgoing)
-   [ ] Diagnostic suppression comments and per-rule severity configuration
-   [ ] Workspace symbol search including standard-library and package symbols

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
-   [x] Designer writes are minimal splices derived from the UI model (js/compiler/source-splice.js): selection never writes, a property edit rewrites one phrase, and code the model does not represent is preserved (`ede1a52`, source-preservation.test.mjs)
-   [x] Source ↔ model ↔ designer round trip
-   [x] Save/close/reopen fidelity (main.ot + styles.css; the stylesheet is read from disk, written only when the designer changed it, and saved with its revision - `ede1a52`)
-   [x] Live source→designer and designer→source synchronization
-   [x] Reliable real-DOM hit testing (elementsFromPoint + computed flex direction)
-   [x] Selection/hover overlays
-   [x] Multi-selection (Ctrl/Shift+click, marquee drag, Ctrl+A siblings; style edits apply to all selected; `34b7c3b`)
-   [x] Resize handles (handle-e, handle-s, handle-se with 8px snapping & tooltip)
-   [x] Alignment/spacing guides (resize snaps to sibling sizes and parent width with guide lines; free-move snaps to parent/sibling edges and centres; draggable padding/margin/gap grips)
-   [x] Margin/padding visualization
-   [x] Insertion markers (GrapesJS-style line with dot endpoints)
-   [x] Nested drop targets
-   [x] Zoom/pan (Ctrl+wheel around the pointer, zoom menu, Fit; Space/middle-drag pan)
-   [x] Viewport presets (desktop/tablet/mobile/full)
-   [x] Responsive breakpoints (Desktop/Tablet/Mobile contexts write `@media` rules widest-first; canvas previews at 768/375 px; verified in the compiled app at 1280/768/375)
-   [x] Copy/paste/duplicate/delete controls (Ctrl+D duplicate, Del delete, badge buttons)
-   [x] Designer undo/redo (Ctrl+Z / Ctrl+Y with snapshot stack)
-   [x] Flex row/column insertion
-   [x] Grid placement (grid track overlay; drops into an empty cell write `grid-column`/`grid-row`; column stepper and span controls)
-   [x] Reparenting
-   [x] Empty-container drop
-   [x] Direct inline text editing on canvas (double-click to edit headings, text, buttons, labels)
-   [x] Live user interaction mode on canvas ([🎨 Design] vs [⚡ Live Interact])
-   [x] Auto-scroll while dragging
-   [ ] Pointer capture/touch/high-DPI
-   [x] No stale bounds
-   [x] No direct DOM-only mutation
-   [x] No hidden left/top in flow mode
-   [x] Explicit free-position mode only (free dragging only for `position: absolute/fixed`; flow elements reorder structurally)
-   [x] Production round-trip regression test
-   [x] Study/adapt GrapesJS interaction techniques without replacing Otter model/compiler
-   [x] Review third-party licenses
-   [x] Layers tree for the canvas: select, Ctrl multi-select, drag reorder/re-nest, double-click rename (`hierarchy.js`, sidebar pane shown in Design/Split mode)
-   [x] Layers panel named "Layers" in Design mode (the tab reads Layers wherever the designer shows, Outline in Code mode)
-   [x] Structure keys: Ctrl+Up/Down among siblings, Ctrl+Left out of parent, Ctrl+Right into previous container (`6c7e949`, designer/actions.js; verified in the real UI, `put` lines follow)
-   [x] Layers: Shift range select in the tree (in tree order, from the last clicked row)
-   [x] Lock and hide elements on canvas (`837be26`; Layers eye/lock buttons, Ctrl+Shift+H/L; designer-only state per design file, never written to the program; locked elements pass clicks to their parent and are skipped by marquee)
-   [ ] Keyboard nudging (arrow keys, Shift for 10px) and snap to grid (nudging done for absolute elements; 8px snapping on resize; a user-visible grid and snap-to-grid toggle remain)
-   [x] Style editor for `styles.css` with live preview (full CSS inspector per component, states and breakpoints, raw declarations, lossless CSS AST; `designer-css`/`designer-styles` suites) - shared class rules remain open
-   [x] State variants: hover/pressed/focused preview on canvas (`data-force-state`); verified hover in the compiled app; Disabled previewed the same way (`1f436a2`)
-   [ ] Sample data binding so lists/tables render realistic content on canvas

## 11a. Designer polish from the Webstudio / GrapesJS / Penpot review

Source: `docs/studio/DESIGNER_GAP_ANALYSIS.md`. Webstudio (AGPL) and Penpot
(MPL) are UX references only; copy no code. GrapesJS (BSD-3) is an
architecture reference. Listed in the recommended implementation order.

-   [x] Gap analysis written before implementation (`docs/studio/DESIGNER_GAP_ANALYSIS.md`)
-   [x] Provenance model: `StyleController.explain(comp, prop)` gives source kind (Otter source, styles.css, breakpoint, state, parent, compiler-forced, compiler default, browser default), exact location, and what overrides it; unit-tested (`24dc2ce`; `designer-styles` checks 13-17; verified against the real compiler render)
-   [x] Provenance UI: colored property labels, red for "set here but overridden", hover card with the cascade chain, Go to source (main.ot line or styles.css rule), compiler-forced values explained in words (`c330f6e`; verified through the real inspector: primary button background shown overridden by `.otter-button-primary !important`, fixed by setting it again, Go to source lands on the styles.css line)
-   [ ] Compiler: a primary/secondary/danger button's source `background`/`foreground` is ignored because the compiler's `.otter-button-*` rules are `!important` (Studio now routes designer edits around it; hand-written source still hits it)
-   [x] Breakpoints as data (`{id, label, media, previewWidth}`, default Desktop/Tablet/Mobile) with no index-order cascade assumption (`3e7262b`; project.json `designer.breakpoints`; min-width and condition breakpoints cascade by media evaluation + stylesheet order; `designer-styles` checks 18-19)
-   [x] Canvas simulates non-width media conditions (color scheme, reduced motion, orientation) instead of following Studio's window (`3e7262b`; verified in the real UI with Studio itself in dark mode: Desktop stays light, a Dark breakpoint previews the dark rule)
-   [x] Keyboard and context menu out of `canvas.js` into designer/actions.js, commands.js, context-menu.js (`6c7e949`)
-   [ ] Render / overlay / gestures still share `canvas.js`; split them when next reworked
-   [x] Designer shortcuts registered in the command registry (visible in F1 and the Shortcuts dialog) (`6c7e949`; `designer-commands` suite; F1 lists "Zoom to Selection · Shift+2" in the real UI)
-   [x] Spacing modifiers, Webstudio's convention (Shift = all sides, Alt = this side and its opposite) on the canvas grips and the inspector's box-model numbers, which drag-scrub and take Shift+Enter / Alt+Enter (`8fd2e5f`; verified in the real UI)
-   [x] Flex child and Grid child inspector sections shown by parent layout (grow, shrink, basis, align-self, order, select-parent link) (`1f436a2`; verified in the real UI)
-   [x] Outline (focus ring) controls (`1f436a2`; verified in the real UI)
-   [x] Per-side border controls (`1f436a2`; verified in the real UI)
-   [x] Layered box-shadow editor (x, y, blur, spread, color, inset) (`1f436a2`; verified in the real UI)
-   [x] Transition editor (property, duration, easing, delay) (`1f436a2`; verified in the real UI)
-   [x] `text-shadow` control (`1f436a2`; verified in the real UI)
-   [x] `disabled` state and `::placeholder` styling (`1f436a2`; verified in the real UI)
-   [x] Zoom to selection (Shift+2) (`6c7e949`)
-   [ ] Resize modifiers (Shift proportional, Alt from center)
-   [ ] Later: custom breakpoints UI (min/max width and media conditions), design tokens / shared classes, asset manager, grid generator presets, Hide UI mode
-   [ ] Dialogs (New Project, Build, Settings, Shortcuts) restyled to the dark workbench theme

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
-   [ ] Accessibility semantics
-   [x] Property inspector (layout, spacing, size, position, typography, background, border, effects, all CSS)
-   [x] Property search/categories (collapsible sections, search box, status dots for set/inherited values)
-   [ ] Binding/state editor
-   [ ] Events panel
-   [ ] Create/navigate handler
-   [ ] Safe component rename
-   [x] Responsive properties (every style field edits the active breakpoint/state; inherited values shown as placeholders)
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
-   [x] In-process IPC strategy for consumer apps where appropriate (Electron target: preload `contextBridge` exposes `window.otterNative.{files,folders,commands,clipboard,system,dialogs}`, Node main process implements them; no PowerShell at run time; `34b7c3b`, `ElectronExport.Tests.ps1` live launch)
-   [x] Windows packaging (`otter package --target windows`: NSIS installer + portable .exe from the Electron export; portable exe verified running outside the repo with PATH reduced to System32; `b88e173`)
-   [ ] macOS packaging (refused explicitly until run and tested on macOS)
-   [ ] Linux packaging (refused explicitly until run and tested on Linux)
-   [ ] Multiple windows
-   [ ] Native menus/dialogs (open-file / open-folder / save dialogs done through Electron `dialog`; native app menus open)
-   [ ] Tray/menu bar
-   [ ] Notifications (Electron `Notification` wired through `otterNative.system.notification`; not yet certified by a live test)
-   [ ] File associations
-   [ ] Protocol handlers
-   [ ] Single-instance apps
-   [ ] Auto-update
-   [x] Installer/uninstaller (NSIS per-user installer with choosable folder, desktop shortcut and uninstaller; `b88e173`)
-   [ ] Code signing (unsigned today; SmartScreen warns on other PCs; needs a certificate or Azure Trusted Signing)
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
-   [ ] In-Studio REST client for testing endpoints (request builder, history, saved collections)

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
-   [x] Clean/rebuild (Run ▾ > Rebuild / Clean Build Output; clean only deletes output `otter build` created, marked by otter.build.json) (certified via otter-studio/scripts/launch.test.mjs)
-   [ ] Build project/workspace (project build done via Ctrl+Shift+B / Run ▾ > Build Project; multi-project solution build pending)
-   [ ] Target selection
-   [ ] Parallel builds
-   [ ] Build cache
-   [ ] Reproducible builds
-   [x] Build logs/diagnostics (Output tab log with exit code/duration; failures shown in Problems) (certified via otter-studio/scripts/launch.test.mjs)
-   [x] Artifact directory (manifest build.outputDir; build summary lists artifacts) (certified via otter-studio/scripts/launch.test.mjs)
-   [ ] Resource processing
-   [ ] Version stamping
-   [ ] CI build command
-   [x] Run current file (`otter run <file>` via argument array, no shell) (certified via otter-studio/scripts/launch.test.mjs)
-   [x] Run project (`otter run <project folder>` through the manifest) (certified via otter-studio/scripts/launch.test.mjs)
-   [ ] Startup project
-   [x] Launch profiles (<project>/.otter-studio/launch.json, editor under Run ▾ > Edit Launch Profiles…, per-project startup profile) (certified via otter-studio/scripts/launch.test.mjs)
-   [x] Arguments/working dir/env vars (one argument per line; PATH-style variables protected; paths contained to the workspace) (certified via otter-studio/scripts/launch.test.mjs)
-   [ ] Web/Desktop/Console/Game/Server profiles
-   [x] Stop/restart (Shift+F5 / Ctrl+Shift+F5; kills the process tree; per-profile timeout) (certified via otter-studio/scripts/launch.test.mjs)
-   [x] Run without debug (certified via otter-studio/scripts/launch.test.mjs)
-   [ ] Run with debug
-   [x] Persist launch settings (launch.json saved atomically with revision checks; selection remembered per project) (certified via otter-studio/scripts/launch.test.mjs)
-   [ ] Task runner for arbitrary pre-build/post-build/custom tasks
-   [ ] Problem matchers that map external tool output into the Problems panel
-   [ ] Pre-launch tasks attached to launch profiles

# 19. Debugger

-   [ ] Debugger protocol
-   [ ] Runtime instrumentation
-   [ ] Breakpoints
-   [ ] Conditional/hit-count breakpoints
-   [ ] Logpoints
-   [ ] Step over/into/out
-   [ ] Continue/pause/stop/restart
-   [ ] Call stack
-   [ ] Current line
-   [ ] Locals/globals
-   [ ] Watches
-   [ ] Evaluate expression
-   [ ] Object/list inspection
-   [ ] Error breakpoints
-   [ ] Async debugging
-   [ ] Web/Desktop source mapping
-   [ ] Debug console
-   [ ] Attach
-   [ ] Remote debug if justified
-   [ ] DAP support if beneficial
-   [ ] Run to cursor / set next statement
-   [ ] Inline variable values and hover-to-evaluate while paused
-   [ ] Exception settings panel (break on thrown/uncaught by category)
-   [ ] Debug toolbar and multi-session debugging

# 20. Testing platform

-   [ ] Otter unit-test framework
-   [ ] Assertions
-   [ ] Setup/teardown
-   [ ] Parameterized/async/expected-error tests
-   [ ] Mocks/fakes strategy
-   [x] Discovery (Studio lists exactly the files `otter test` runs, same order; parity asserted) (otter-studio/scripts/test-explorer.test.mjs, through `otter test`)
-   [x] Test Explorer (bottom drawer Tests tab: state icons + words, message and line, output, open at failure) (otter-studio/scripts/test-explorer.test.mjs, through `otter test`)
-   [x] Run selected/all (Run All, Run Failed, per test; Stop skips the rest) (otter-studio/scripts/test-explorer.test.mjs, through `otter test`)
-   [ ] Debug test
-   [x] Filtering/output/duration (otter-studio/scripts/test-explorer.test.mjs, through `otter test`)
-   [ ] Coverage and visualization
-   [ ] UI/browser/desktop tests
-   [ ] Cross-platform tests
-   [ ] CI command
-   [ ] Flaky-test policy

# 21. Packages and modules

-   [x] Shared module resolver reported
-   [ ] Production-certify `use`
-   [ ] Freeze module resolution
-   [ ] Relative/package imports
-   [ ] Circular/duplicate/module-init semantics
-   [ ] Public/private exports if needed
-   [ ] Module dependency graph/cache
-   [ ] Package manifest
-   [ ] Semantic versions
-   [ ] Registry
-   [ ] Install/remove/update
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
-   [ ] Studio package manager UI

# 22. Git/source control

-   [x] Repository detection (git rev-parse from the open project; Initialize Repository when none) (otter-studio/scripts/git.test.mjs, real git CLI)
-   [x] Explorer status (M/A/U/D/R/! decorations on Explorer entries, refreshed on save/focus) (otter-studio/scripts/git.test.mjs, real git CLI)
-   [x] Diff viewer (side-by-side, Myers line diff, staged and working-tree sides) (otter-studio/scripts/git.test.mjs, real git CLI)
-   [x] Stage/unstage (per file and all) (otter-studio/scripts/git.test.mjs, real git CLI)
-   [x] Commit/amend (message via stdin, Ctrl+Enter; warns about unsaved tabs and amending pushed commits) (otter-studio/scripts/git.test.mjs, real git CLI)
-   [x] Branches (switch, create, delete, remote tracking) (otter-studio/scripts/git.test.mjs, real git CLI)
-   [x] Fetch/pull/push (first push publishes and sets upstream; never prompts for passwords) (otter-studio/scripts/git.test.mjs, real git CLI)
-   [x] Merge (merge into current, abort) (otter-studio/scripts/git.test.mjs, real git CLI)
-   [x] Conflict editor (accept ours/theirs/both per block; saves with revision check, then marks resolved) (otter-studio/scripts/git.test.mjs, real git CLI)
-   [x] History/file history (commit details with files and patch) (otter-studio/scripts/git.test.mjs, real git CLI)
-   [x] Blame (otter-studio/scripts/git.test.mjs, real git CLI)
-   [x] Stash (push incl. untracked, pop, apply, drop) (otter-studio/scripts/git.test.mjs, real git CLI)
-   [x] Tags (lightweight/annotated create, delete) (otter-studio/scripts/git.test.mjs, real git CLI)
-   [ ] Remote/auth management (add/remove remotes and redacted URLs done; sign-in is delegated to the user's credential helper/SSH agent, no in-Studio account management)
-   [ ] Source-control extension API
-   [x] Gutter change indicators (added/modified/deleted) in the editor (3ff8d4b; Alt+F3 next change, Revert Change at Cursor)
-   [x] Inline blame annotations (69c8dae; cursor line, Settings > Editor > Inline blame)
-   [ ] Pull request and issue integration (GitHub/GitLab providers)
-   [x] `.gitignore` template generator on project creation (3ff8d4b; New Project checkbox, honors build.outputDir)

# 23. Refactoring

-   [x] Rename local/function (scope-aware within a file: the analyzer places the symbol, parameters and globals stay separate; preview before applying) (`61a6e0d`)
-   [ ] Rename file/module and across files
-   [x] Update references (every reference in the symbol's scope, in the rename preview) (`61a6e0d`)
-   [x] Extract function (whole lines, nested blocks kept, parameters passed, refused when it would change the program) (`61a6e0d`; same interpreter output before/after)
-   [ ] Extract variable
-   [ ] Inline variable
-   [ ] Move symbol/module
-   [ ] Safe delete
-   [ ] Organize modules
-   [x] Preview changes (rename lists every changed line, old and new, before applying) (`61a6e0d`)
-   [x] Atomic undo (rename, extract and other whole-document edits are one Ctrl+Z) (`61a6e0d`)
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
-   [ ] Terminal accessibility
-   [ ] Production Otter REPL
-   [ ] Persistent REPL variables/functions
-   [ ] Multiline/history/completion/highlighting
-   [ ] Pretty values/object inspection
-   [ ] Load module/reset/error recovery

# 25. Extensions/plugins

-   [ ] Extension API
-   [ ] Manifest/lifecycle
-   [ ] Commands/menus/keybindings
-   [ ]
    Editor/workspace/filesystem/language/debugger/designer/build/terminal
    APIs
-   [ ] Theme API
-   [ ] Custom panels/webviews
-   [ ] Provider API
-   [ ] Sandbox/permissions
-   [ ] Signing
-   [ ] Marketplace
-   [ ] Updates
-   [ ] Disable/uninstall
-   [ ] Crash isolation
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

-   [ ] CPU profiler
-   [ ] Function timing
-   [ ] Memory/allocation/leak tools
-   [ ] UI render performance
-   [ ] Network inspector
-   [ ] Build/startup/extension performance
-   [ ] Game frame timing
-   [ ] Timeline/export
-   [ ] DOM inspector
-   [ ] CSS inspector
-   [ ] Browser console/network/storage
-   [ ] Responsive preview
-   [ ] Accessibility inspector
-   [ ] Generated JS source maps back to Otter

# 28. Packaging/publishing

-   [ ] `otter build`
-   [ ] `otter publish`
-   [ ] Version/app ID/icons
-   [ ] Release/debug artifacts
-   [ ] Checksums
-   [ ] Signing hooks
-   [ ] Publish wizard
-   [ ] Web production output/deployment presets
-   [ ] Windows standalone package/installer/uninstaller/signing/update
-   [ ] macOS app bundle/sign/notarize/DMG-or-PKG/update
-   [ ] Linux bundle/AppImage/deb-rpm/desktop entry/update

# 29. Security

-   [x] Loopback-only/ephemeral port/session token/origin validation
    reported (for desktop apps). Studio's own server: loopback-only bind, Host and Origin validation, no wildcard CORS since this batch (otter-studio/scripts/security.test.mjs)
-   [ ] Independent threat model/review
-   [ ] Prove preview cannot access native bridge
-   [ ] Prove external page cannot access native bridge
-   [ ] XSS/CSP hardening
-   [x] Path containment/traversal tests (file API and static server) (otter-studio/scripts/security.test.mjs)
-   [x] Command injection tests (Run/Build pass argument arrays, never a shell string; launch.test.mjs). The integrated terminal runs shell commands by design.
-   [x] Symlink escape tests (containment checks the real path, not just the text) (otter-studio/scripts/security.test.mjs)
-   [x] CSRF/origin tests (cross-site Origin and DNS-rebinding Host refused) (otter-studio/scripts/security.test.mjs)
-   [ ] DoS/request-size limits (32 MB request-body limit done (otter-studio/scripts/security.test.mjs); rate limiting not done)
-   [ ] Workspace trust
-   [x] Warn before running untrusted code/build hooks (one Restricted Mode gate for Run, Debug, Build, tests and Git actions that run repository hooks)
-   [ ] Secrets storage/redaction
-   [ ] Extension permissions
-   [ ] Preview sandbox
-   [ ] Dependency inventory/lock/vulnerability scan
-   [ ] SBOM
-   [ ] License scan
-   [ ] Signed releases/updates
-   [ ] Security response policy

# 30. Accessibility/i18n

-   [ ] Full keyboard navigation
-   [ ] Focus order
-   [ ] Screen-reader labels
-   [ ] ARIA
-   [ ] High contrast
-   [ ] Color-independent status
-   [ ] Font/zoom
-   [ ] Reduced motion
-   [ ] Accessible designer/terminal/errors/dialogs
-   [ ] WCAG audit
-   [ ] Automated/manual accessibility tests
-   [ ] Unicode/non-Latin source and paths
-   [ ] Locale UI
-   [ ] Translatable strings
-   [ ] Date/number localization
-   [ ] RTL
-   [ ] IME
-   [ ] CJK editing
-   [ ] Grapheme-safe cursor

# 31. Settings/workbench/commands

-   [ ] Global/workspace/project settings
-   [x] Settings UI (File > Settings, Ctrl+,; generated from one field list; persisted; `settings.test.mjs`)
-   [x] Keybinding editor (`e1a0430`; Help > Keyboard Shortcuts: record, reset, remove, conflicts; Studio and designer commands)
-   [ ] Themes/fonts
-   [ ] Editor/terminal/designer/autosave/update/privacy settings
-   [ ]
    Explorer/Search/SCM/Run-Debug/Extensions/Problems/Output/Terminal/Tests/Properties/Toolbox/Designer/Live
    App views
-   [x] Command Palette (F1, Ctrl+Shift+P, or `>` in Quick Open / Ctrl+K; runs registry commands; verified in the real UI)
-   [x] Quick Open (Ctrl+P and Ctrl+K with fuzzy file matching)
-   [x] Status bar (run/debug, problems, Studio service status, cursor, EOL, encoding, trust)
-   [ ] Dockable/resizable/persistent panels
-   [ ] Multi-window
-   [ ] Restore/reset layout
-   [x] Central command registry (`js/shell/commands.js`: 38 commands, unique ids and shortcuts enforced by `commands.test.mjs`)
-   [x] Context-sensitive shortcuts (`e1a0430`; designer keys only while the designer has focus, bare keys never while typing, editor keys in the editor)
-   [x] Discoverable shortcut UI (Help > Keyboard Shortcuts, generated from the registry, filterable; shortcuts also shown in the palette)
-   [ ] Platform shortcut mapping
-   [ ] Settings sync across machines and named settings profiles
-   [ ] Notifications center with history
-   [x] Zen/distraction-free mode and full screen (`91b8ee2`; Ctrl+Alt+Z / Esc, F11)
-   [x] Help menu: report issue, release notes, keyboard reference, in-IDE documentation viewer (`645e3d3`; guide, standard library, grammar, semantics, changelog with outline and find-in-page)
-   [ ] Standard-library / API browser panel (object-browser style)
-   [ ] Interactive first-run walkthroughs and guided tutorials

# 32. Reliability/performance

-   [ ] Atomic settings/source saves
-   [ ] Crash/autosave recovery
-   [ ] Corrupt workspace/settings recovery
-   [ ] Extension/renderer crash isolation
-   [ ] Terminal/bridge/orphan cleanup
-   [ ] Safe shutdown
-   [ ] Logs/rotation/Open Logs
-   [ ] Recovery mode
-   [ ] Reset Studio state
-   [ ] Startup/project scan/large workspace/large
    file/parser/compiler/build/memory/search/designer/terminal/game
    benchmarks
-   [ ] No UI blocking
-   [ ] Cancellation/progress
-   [ ] Performance-regression CI

# 33. Cross-platform certification

-   [ ] Windows 11 baseline
-   [ ] PowerShell 5.1/7/cmd/WSL behavior
-   [ ] Windows filesystem/Desktop/installer/signing/DPI/accessibility
-   [ ] macOS baseline/filesystem/shell/Desktop/app
    bundle/sign/notarize/Retina/accessibility
-   [ ] Linux distro
    baseline/filesystem/shell/Desktop/packaging/Wayland-X11/scaling/accessibility

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
-   [ ] Upgrade/repair/uninstall
-   [ ] Preserve projects/settings
-   [ ] Welcome screen
-   [ ] Create/open/sample projects
-   [ ] Toolchain detection
-   [ ] Offline install
-   [ ] Installer signing
-   [ ] Stable/preview update channels
-   [ ] Signed update metadata/packages
-   [ ] Progress/signature verification
-   [ ] Restart/rollback/release notes/skip version

# 36. Documentation/examples

-   [ ] Getting Started/install
-   [ ] Complete language reference
-   [ ] Standard-library API
-   [ ] Language specification
-   [ ] Compatibility guide
-   [ ] Studio
    tour/editor/designer/terminal/run/debug/test/Git/packages/extensions/build/settings/troubleshooting
    docs
-   [ ] Tutorials: Hello World, CLI, automation, desktop, web, API,
    database, 2D game, full stack, package, extension
-   [x] Task List/File Browser/Contact Manager examples reported
-   [ ] Studio dogfood \[IN PROGRESS\]
-   [ ] Every standard-library feature exercised by a real `.ot` example

# 37. Conformance/release gates

-   [ ] D61 language specification complete
-   [ ] D62 conformance suite complete
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
-   [ ] Security threat model
-   [ ] Preview isolation
-   [ ] Accessibility baseline
-   [ ] Crash recovery
-   [ ] Installer/update docs
-   [ ] Fresh-machine test
-   [ ] No known data-loss bugs
-   [ ] No critical security bugs
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
-   [x] Run Current File/project. (certified via otter-studio/scripts/launch.test.mjs)
-   [x] Launch profiles. (certified via otter-studio/scripts/launch.test.mjs)
-   [ ] Persistent PTY terminal.
-   [ ] Debugger with breakpoints, stepping, stack, variables, watches.

## P6 --- Tests/packages/Git/extensions

-   [ ] Otter test framework and Test Explorer. (Test Explorer done over the existing file-per-test `otter test` model; a richer framework - named cases, assertions, setup - is language work)
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
