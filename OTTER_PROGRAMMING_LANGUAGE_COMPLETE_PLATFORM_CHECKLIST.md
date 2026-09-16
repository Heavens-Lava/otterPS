# Otter Programming Language --- Complete Application Platform Master Checklist

**Status date:** September 14, 2026\
**Mission:** Build Otter into a readable, deterministic, general-purpose
programming language and application platform capable of serious
shell/system administration, console software, desktop applications,
full web development, services/APIs, game development, and 2D/3D
creation.

> **Scope rule:** "Everything needed for computer applications" does not
> mean putting every domain feature directly into language syntax. A
> professional language needs a small stable core plus standard
> libraries, runtimes, providers, package/FFI ecosystems, compilers,
> tooling, and target-specific APIs. Specialized targets such as kernel
> drivers, embedded firmware, GPU kernels, mobile-native applications,
> and safety-critical systems require explicit providers/backends and
> certification.

## Status legend and permanent rules

-   [x] Reported implemented/demonstrated in the current Otter project.
-   [ ] Required, partial, deferred, blocked, or not yet
    production-certified.
-   A renderer/helper/unit test does **not** certify a language
    capability. A real `.ot` program must reach it through a production
    entry point.
-   Otter semantics never depend on PowerShell, JavaScript, browser, or
    operating-system quirks.
-   Controlled English must remain deterministic.
-   `is` assigns the value of an expression.
-   `as` binds a contextual name/role.
-   `into` receives an operation result/handle.
-   `.` terminates blocks/processes and is not member-access
    punctuation.
-   Complexity belongs in runtimes/libraries/providers rather than
    unnecessary syntax.
-   Avoid synonyms unless they have genuinely different semantics.
-   Dangerous or expensive behavior must be visible.
-   Do not add language magic until real dogfooding demonstrates a need.
-   One language/core semantics; hosts/providers translate capabilities
    appropriately.
-   Language capability and host capability are different concepts.
-   Unsupported host capabilities must fail clearly rather than silently
    changing semantics.
-   C# implementation remains Jeff's implementation; agents must not
    modify it unless explicitly authorized.

# 1. Language Architecture

-   [x] Source files
-   [x] Lexer
-   [x] Token model
-   [x] Parser
-   [x] AST
-   [x] Interpreter/runtime architecture
-   [x] Portable JavaScript compiler architecture
-   [x] Formal grammar
-   [x] Formal semantic specification
-   [x] Versioned AST contract
-   [x] Standard diagnostic contract
-   [x] Language version declaration/strategy
-   [x] Compatibility policy
-   [x] Deprecation policy
-   [x] Feature-gating/version negotiation
-   [x] Conformance suite
-   [x] Reference implementation designation
-   [x] Runtime/provider specification
-   [x] Standard-library specification
-   [x] Compiler backend interface
-   [x] Host capability interface
-   [x] Stable module/package ABI/API strategy

# 2. Core Syntax & Control Flow

-   [x] `say`
-   [x] Variables using `is`
-   [x] Text/string literals
-   [x] Numeric literals
-   [x] Boolean values
-   [x] `gone`
-   [x] Arithmetic expressions
-   [x] `plus`
-   [x] `minus`
-   [x] `times`
-   [x] `divided by`
-   [ ] Percent operation (verified absent - zero references in the
    interpreter, contract, or parser; not a real Otter construct today)
-   [ ] Power operation (verified absent, same as Percent)
-   [x] Mutation with `increase` (`increase X by N` - real lexer
    keyword mapping to the same Add token as `add`, real parser
    grammar, verified through the real CLI: `otter run` on a real
    `.ot` file with `increase score by 3` printed the correct
    mutated value. Correction: an earlier pass in this checklist
    wrongly marked this absent before the keyword mapping was
    noticed in `Otter.Lexer.psm1`)
-   [x] Mutation with `decrease` (`decrease X by N`, same verification
    as `increase`, maps to the same Remove token as `remove ... from`)
-   [x] `add ... to`
-   [x] `remove ... from`
-   [x] Equality
-   [x] Inequality
-   [x] Greater/less comparisons
-   [x] At-least/at-most comparisons
-   [x] `not`
-   [x] `and`
-   [x] `or`
-   [x] Boolean precedence
-   [x] `if`
-   [x] `otherwise if`
-   [x] `otherwise`
-   [x] `while`
-   [x] `repeat`
-   [x] `count from ... to ... as ...`
-   [x] `each ... in ...`
-   [x] Functions with `to`
-   [x] Parameters
-   [x] Return values
-   [x] `stop` function termination
-   [x] Nested blocks
-   [x] Controlled multiline condition continuation
-   [x] Comments
-   [ ] Freeze remainder/modulo wording
-   [x] Freeze all remaining contextual-keyword behavior
-   [x] Freeze operator precedence table
-   [x] Document evaluation order
-   [x] Short-circuit behavior certification
-   [x] Tail-call behavior decision
-   [x] Generator/yield decision only if real applications require it
-   [x] Pattern matching decision only if dogfooding requires it

# 3. Data Model

-   [x] Text
-   [x] Numbers
-   [x] Booleans
-   [x] `gone`
-   [x] Lists
-   [x] Plain things/objects
-   [x] Properties
-   [x] Dynamic keys
-   [x] Reference aliasing for things
-   [x] Missing property distinct from property containing `gone`
-   [x] Numeric precision/range specification
-   [x] Integer vs floating-point strategy
-   [x] Large integer strategy
-   [x] Decimal/money-safe numeric strategy
-   [x] Unicode string semantics
-   [x] Grapheme-safe string operations
-   [ ] Binary/byte data
-   [ ] Buffers
-   [x] Streams
-   [ ] Immutable/read-only values if demonstrated necessary
-   [x] Map/dictionary decision
-   [x] Set collection decision
-   [x] Tuple/record decision
-   [x] Enum/symbol decision
-   [x] Structured error value/type
-   [x] User-defined types parity
-   [x] Type metadata/reflection strategy
-   [x] Serialization contract

# 4. Objects, Types & Properties

-   [x] `person has ...`
-   [x] Legacy thing construction
-   [x] Inline `with` configuration work
-   [x] Property access using `of`
-   [x] Nested property access
-   [x] Property assignment
-   [x] Dynamic object keys
-   [x] JS plain-object alias semantics
-   [x] Portable custom `OtterType` construction parity
-   [x] Resolve existing-thing `has` protective parity
-   [x] Methods/member-behavior decision
-   [x] Encapsulation/public-private decision
-   [x] Composition model
-   [x] Inheritance decision --- only if justified
-   [x] Interface/protocol/trait strategy if needed
-   [x] Generic/template type strategy if needed
-   [x] Reflection/introspection
-   [x] Runtime type querying
-   [x] Object cloning/copying
-   [x] Equality/hash semantics

# 5. Functions, Scope & Modules

-   [x] Zero/multiple parameters
-   [x] Return values
-   [x] Nested calls
-   [x] Recursion
-   [x] Function scope behavior
-   [x] Loop variable scope parity work
-   [x] Global mutation behavior parity
-   [x] Call-before-declaration behavior parity
-   [x] Shared module resolver work reported
-   [x] Production-certify `use`
-   [x] Freeze module resolution
-   [x] Relative modules
-   [ ] Package modules
-   [x] Circular dependency semantics
-   [x] Module initialization order
-   [x] Duplicate-load semantics
-   [x] Public/private exports if needed
-   [x] Namespace collision policy
-   [x] Module caching/invalidation
-   [x] Closures
-   [ ] First-class function values if required
-   [ ] Callbacks/delegates
-   [x] Lambda/anonymous function decision only if necessary
-   [x] Cross-module symbol metadata for IDE tooling

# 6. Errors & Diagnostics

-   [x] `try` / `otherwise`
-   [x] Runtime errors
-   [x] `log`
-   [x] `warn`
-   [x] `error`
-   [x] Source diagnostics exist
-   [x] Stable diagnostic codes
-   [x] Exact file/line/column ranges
-   [ ] Multiple diagnostics per parse where safe
-   [ ] Parser recovery
-   [x] Stack traces expressed in Otter terms
-   [ ] Nested/cause errors
-   [x] Structured errors
-   [x] Error categories
-   [ ] Custom/user errors
-   [x] Async error propagation
-   [x] Host/provider error translation
-   [x] Diagnostic suggestions/quick fixes
-   [x] Panic/fatal-runtime policy
-   [ ] Crash-report format

# 7. Memory & Resource Management

-   [x] Define memory model
-   [x] Garbage collection/reference management strategy per backend
-   [x] Resource lifetime semantics
-   [x] Deterministic cleanup mechanism where needed
-   [x] File/socket/process handle cleanup
-   [ ] Disposal/finalization model
-   [x] Circular reference behavior
-   [ ] Weak references only if needed
-   [ ] Memory limits
-   [x] Out-of-memory behavior
-   [ ] Large-object handling
-   [ ] Native resource ownership rules
-   [ ] FFI ownership rules

# 8. Async, Tasks, Timers & Concurrency

-   [x] Async compiler support exists for file/HTTP operations in
    functions
-   [x] Language-level async task model
-   [x] Awaiting asynchronous operations
-   [x] Cancellation
-   [x] Cancellation tokens/signals
-   [x] Timeouts
-   [x] One-shot timers
-   [x] Repeating timers
-   [x] Background tasks
-   [ ] Worker/thread abstraction
-   [x] Thread-safe runtime rules
-   [ ] Synchronization primitives
-   [ ] Channels/message passing
-   [ ] Concurrent collections if needed
-   [x] UI-thread dispatch
-   [x] Process concurrency
-   [ ] Parallel loops/tasks if justified
-   [x] Deadlock guidance/tooling
-   [x] Race detection strategy
-   [x] Structured concurrency decision

# 9. Filesystem

-   [x] Read text
-   [x] Write text
-   [x] Append grammar/runtime work
-   [x] Create folder
-   [x] List folder
-   [x] Remove folder
-   [x] Copy
-   [x] Move
-   [x] Delete
-   [x] File metadata/properties
-   [x] File exists portable certification
-   [x] Folder exists
-   [ ] Atomic save
-   [x] Safe overwrite
-   [x] Text encodings
-   [ ] Binary read/write
-   [ ] Random-access file IO
-   [ ] Streams
-   [ ] Large-file handling
-   [ ] File locks
-   [ ] File watching
-   [ ] Recursive watching
-   [x] Temp files/folders
-   [x] User/app data folders
-   [x] Path combine/normalize
-   [x] Cross-platform path rules
-   [ ] Symbolic links/reparse points
-   [ ] Permission/ownership APIs
-   [ ] Disk/free-space information
-   [x] File dialogs via UI provider
-   [ ] ZIP/archive provider

# 10. Shell & System Administration

-   [x] Windows shell discovery
-   [x] Run native command
-   [x] Working directory
-   [x] stdout
-   [x] stderr
-   [x] numeric exit code
-   [x] Structured command result --- D65 `385e795`
-   [x] Process-start failure becomes Otter error
-   [x] Command-line arguments
-   [x] Environment variables
-   [x] Current directory get/set
-   [ ] PATH inspection
-   [ ] Process enumeration
-   [ ] Process details
-   [x] Start process
-   [x] Stop process
-   [x] Kill process tree
-   [ ] Process priority
-   [ ] Process timeout
-   [x] Signals
-   [ ] Services/daemons
-   [ ] Windows services provider
-   [ ] systemd provider
-   [ ] launchd provider
-   [ ] User/account information
-   [ ] Groups/roles
-   [ ] Machine/OS information
-   [ ] CPU information
-   [ ] Memory information
-   [ ] Disk information
-   [ ] Network-interface information
-   [ ] Installed software information
-   [ ] Registry provider for Windows
-   [ ] Event log provider
-   [ ] System logs provider
-   [ ] Scheduled tasks/cron provider
-   [ ] Permissions/elevation model
-   [ ] Secure credential handling
-   [x] Clipboard (D67: real `NodeKind`s + interpreter/JS-compiler
    implementation, real lexer/parser grammar wired in `f52dcad`
    (`copy "text" to clipboard`, `get clipboard into x`). Verified
    through the real `otter run` CLI on a real `.ot` file: a real
    OS clipboard write-then-read round trip printed back exactly)
-   [x] Notifications (D67: `notify "Title" with "Message"` real
    grammar wired in `f52dcad`, verified through the real `otter run`
    CLI. Interpreter shows a REAL Windows balloon-tip toast via
    `System.Windows.Forms.NotifyIcon`; the JS/web path shows an
    in-page DOM toast instead - a documented, deliberate cross-
    runtime difference, not a bug)
-   [ ] Power/reboot/shutdown APIs with explicit safety
-   [ ] Printer/device APIs via providers
-   [ ] Remote administration strategy
-   [ ] SSH client/provider
-   [x] Secure shell escaping
-   [x] Auditing/logging for privileged operations

# 11. Terminal & REPL

-   [x] Persistent PTY/ConPTY
-   [ ] Character stdin
-   [x] stdout/stderr streaming
-   [ ] ANSI/VT
-   [x] Terminal resize
-   [x] Ctrl+C/signals
-   [ ] Interactive programs
-   [ ] Persistent shell state
-   [ ] Multiple sessions
-   [x] Shell profiles
-   [ ] Cross-platform PTY abstraction
-   [x] Otter REPL
-   [x] Persistent REPL variables
-   [ ] REPL function definitions
-   [x] Multiline blocks
-   [ ] History
-   [ ] Completion
-   [ ] Syntax highlighting
-   [ ] Pretty-print values
-   [ ] Object/list inspection
-   [ ] Module loading
-   [ ] Session reset
-   [x] Error recovery

# 12. Console Application Development

-   [x] Console output
-   [x] Console input
-   [x] Files
-   [x] Command execution
-   [x] CLI argument API
-   [x] Named flags/options helper
-   [x] stdin
-   [x] stdout
-   [x] stderr
-   [ ] Pipe support
-   [ ] Redirect support
-   [x] Exit program
-   [x] Exit code
-   [x] Signals
-   [ ] Terminal colors/styles
-   [ ] Cursor positioning
-   [ ] Interactive menus
-   [ ] Progress indicators
-   [ ] Password/secret input
-   [ ] TTY detection
-   [ ] Noninteractive mode
-   [x] Standalone executable packaging
-   [x] Cross-platform console certification

# 13. Networking

-   [x] HTTP GET reported
-   [x] HTTP POST reported
-   [x] HTTP PUT reported
-   [x] HTTP DELETE reported
-   [x] Headers
-   [ ] Query parameters
-   [x] Request body types
-   [x] JSON integration
-   [ ] Form encoding
-   [ ] Multipart/form-data
-   [ ] File upload
-   [ ] File download
-   [ ] Streaming
-   [x] Timeouts
-   [ ] Cancellation
-   [ ] Redirect policy
-   [ ] Cookies
-   [ ] Sessions
-   [x] Authentication helpers
-   [ ] TLS/certificate handling
-   [ ] Proxy
-   [ ] DNS
-   [ ] WebSocket client
-   [ ] WebSocket server
-   [ ] TCP
-   [ ] UDP
-   [ ] Unix/domain sockets where supported
-   [x] Network diagnostics
-   [ ] Rate limiting helpers
-   [ ] Retry/backoff
-   [ ] Connection pooling

# 14. Data Formats & Serialization

-   [x] JSON support exists in interpreter
-   [x] JSON portable certification
-   [x] JSON serialize
-   [x] JSON nested round trip
-   [x] JSON `gone`/null mapping
-   [ ] CSV read/write
-   [ ] XML
-   [ ] YAML if demanded
-   [x] URL encoding
-   [x] Base64
-   [ ] Hex
-   [ ] Binary serialization strategy
-   [ ] Compression
-   [ ] MIME/content-type helpers
-   [ ] Schema validation
-   [x] Data conversion/coercion rules

# 15. Dates, Time & Random

-   [x] Date support exists in interpreter
-   [x] Portable date certification
-   [x] Current local time
-   [x] UTC
-   [ ] Time zones
-   [ ] Date parsing
-   [x] Date formatting
-   [x] Date arithmetic
-   [x] Durations
-   [ ] Monotonic time
-   [ ] High-resolution timer
-   [x] Random portable certification
-   [ ] Seeded deterministic random (verified absent - the parser only
    accepts `random number from X to Y into Z` / `random item from L
    into Z`, no seed parameter exists anywhere)
-   [x] Cryptographically secure random provider

# 16. Math & Scientific Foundation

-   [x] Basic arithmetic
-   [ ] Percent (verified absent, same as section 2's Percent operation)
-   [ ] Power (verified absent, same as section 2's Power operation)
-   [ ] Absolute value (verified absent - no such keyword/operation
    exists in the lexer, parser, or interpreter)
-   [ ] Round/floor/ceiling (verified absent as a language operation -
    the only `[Math]::Floor` uses found are internal implementation
    details of CountLoop/RandomNumber, never exposed to Otter source;
    the "round" keyword that does exist is an unrelated UI-control
    shape flag, not a math operation)
-   [ ] Min/max (verified absent - no such operation exists)
-   [ ] Square root
-   [ ] Trigonometry
-   [ ] Logarithms
-   [ ] Constants
-   [ ] Vector math (verified absent - zero references anywhere)
-   [ ] Matrix math (verified absent, same as Vector math)
-   [ ] Quaternion math
-   [ ] Geometry helpers
-   [ ] Statistics package
-   [ ] Linear algebra package
-   [ ] Complex numbers if needed
-   [ ] Arbitrary precision package
-   [ ] SIMD/vectorization provider
-   [ ] Scientific package ecosystem

# 17. Database Development

-   [ ] Database provider interface
-   [ ] SQLite
-   [ ] SQL Server
-   [ ] PostgreSQL
-   [ ] MySQL/MariaDB
-   [ ] Connection management
-   [ ] Parameterized queries
-   [ ] Query results
-   [ ] Transactions
-   [ ] Prepared statements
-   [ ] Connection pooling
-   [ ] Migrations
-   [ ] Schema introspection
-   [ ] Stored procedures
-   [ ] Bulk operations
-   [ ] Async database operations
-   [ ] ORM/query-builder only if justified
-   [ ] NoSQL provider interface
-   [ ] Secrets/connection strings
-   [ ] Database conformance tests

# 18. Cryptography & Security APIs

-   [x] Cryptographic random
-   [ ] Hashing
-   [ ] HMAC
-   [ ] Symmetric encryption
-   [ ] Public-key cryptography
-   [ ] Signing/verification
-   [ ] Certificate APIs
-   [x] Secure secret storage
-   [ ] Password hashing through proven libraries
-   [ ] Constant-time primitives delegated to vetted libraries
-   [ ] TLS provider
-   [ ] Keychain/Credential Manager/libsecret providers
-   [x] Never invent custom cryptography
-   [x] Security-sensitive APIs clearly marked

# 19. Full Web Frontend Development

-   [x] JavaScript portable compiler
-   [x] Web application export path
-   [x] Shared HTML/CSS/JS representation direction
-   [x] HTML/document abstraction
-   [x] Components
-   [x] Reusable components
-   [x] Properties/attributes
-   [x] Events
-   [x] State
-   [ ] Derived state
-   [x] Reactive updates
-   [ ] Conditional rendering
-   [ ] List rendering
-   [x] Forms
-   [x] Validation
-   [ ] Routing
-   [ ] Route parameters
-   [ ] Navigation/history
-   [x] Browser storage
-   [ ] Cookies
-   [x] Fetch/HTTP
-   [ ] WebSockets
-   [ ] File upload/download
-   [ ] Drag/drop
-   [x] Clipboard
-   [x] Browser notifications
-   [x] Canvas
-   [x] SVG
-   [ ] Audio/video
-   [ ] Accessibility
-   [x] Responsive design
-   [x] CSS exact escape hatch
-   [ ] Otter-native styling authoring layer
-   [x] CSS variables/themes
-   [x] Animation/transitions
-   [ ] Asset bundling
-   [ ] CSS bundling
-   [ ] JS bundling
-   [ ] Minification
-   [ ] Source maps
-   [x] Dev server
-   [ ] Hot reload
-   [ ] Environment configuration
-   [ ] Production optimization
-   [ ] Static-site generation
-   [ ] PWA
-   [ ] Service workers
-   [ ] SSR/hydration decision
-   [ ] SEO/meta
-   [ ] Browser compatibility matrix
-   [ ] Web publishing/deployment

# 20. Web Backend / Full-Stack Development

-   [x] HTTP server runtime
-   [x] Routes
-   [x] Route parameters
-   [x] Query parameters
-   [x] Request body
-   [x] Response body
-   [x] Headers
-   [ ] Cookies
-   [x] Sessions
-   [ ] Middleware
-   [x] JSON APIs
-   [x] REST helpers
-   [ ] Static files
-   [ ] File upload
-   [ ] Streaming responses
-   [ ] WebSockets
-   [ ] Authentication hooks
-   [ ] Authorization hooks
-   [x] CORS
-   [ ] CSRF protections
-   [ ] Rate limiting
-   [ ] Request limits
-   [x] Logging
-   [ ] Configuration
-   [ ] Secrets
-   [ ] Database integration
-   [ ] Background jobs
-   [ ] Email provider
-   [ ] Caching provider
-   [ ] Queue/message broker provider
-   [x] Graceful shutdown
-   [x] Health checks
-   [ ] Metrics
-   [ ] Production server
-   [ ] Container deployment
-   [ ] Cloud deployment

# 21. Desktop UI Development

-   [x] D60 shared Web/Desktop representation direction
-   [x] Desktop host architecture exists
-   [x] UI resources/properties exist
-   [x] Rows/columns and containment exist in current UI track
-   [x] UI events exist
-   [x] Production-certify current V1 desktop controls
-   [x] Window
-   [ ] Multiple windows
-   [x] Row
-   [x] Column
-   [ ] Grid when justified
-   [x] Panel/card
-   [x] Text/heading
-   [x] Button
-   [x] Text box
-   [x] Text area/editor
-   [x] Checkbox
-   [x] Radio
-   [x] Toggle
-   [x] Select/dropdown
-   [ ] List
-   [ ] Data grid
-   [ ] Tree
-   [x] Tabs
-   [ ] Menu
-   [x] Toolbar
-   [x] Status bar
-   [x] Dialog/modal
-   [x] Image
-   [ ] Icon
-   [x] Progress
-   [x] Slider
-   [ ] Date/time controls
-   [x] Scroll container
-   [x] Split panes
-   [ ] Custom controls
-   [ ] Focus
-   [ ] Show/hide
-   [ ] Keyboard events
-   [ ] Pointer events
-   [ ] Resize events
-   [x] Window lifecycle
-   [x] Clipboard (D67: real grammar wired in `f52dcad`, verified
    through the real CLI - see the section 10 entry above and
    SPEC-DECISIONS.md D67)
-   [ ] OS drag/drop
-   [x] File/folder/save pickers (D67: real `NodeKind`s + interpreter
    implementation using real Windows common dialogs on a dedicated
    STA thread; real grammar (`choose file into x`, `choose folder
    into x`, `choose file to save into x`) wired in `f52dcad` and
    confirmed via `otter check` on a real `.ot` file exercising all
    three forms. Still flagged, unfixed (not my file):
    `Otter.Desktop.psm1`'s bridge-side file-dialog handlers use a
    suspicious 500ms thread-join timeout that likely reports false
    cancellations for any real user taking longer than half a second
    to pick a file - worth a look)
-   [x] Notifications (D67: real grammar wired in `f52dcad`, verified
    through the real CLI. Interpreter shows a real Windows balloon-tip
    toast; JS/web path is still a DOM-toast approximation, documented
    as a deliberate cross-runtime difference, not a bug)
-   [ ] Native menus/context menus
-   [ ] Shortcuts
-   [ ] Themes
-   [ ] Accessibility
-   [ ] Localization
-   [ ] High DPI
-   [ ] Multi-monitor
-   [ ] System tray/menu bar
-   [ ] File associations
-   [ ] Protocol handlers
-   [ ] Single-instance apps

# 22. Desktop Native Host & Packaging

-   [x] Hardened Studio bridge architecture reported
-   [x] Final Windows-host certification
-   [x] Generic host API independent of one browser implementation
-   [ ] In-process IPC where appropriate
-   [x] Windows runtime
-   [ ] macOS runtime
-   [ ] Linux runtime
-   [x] Windows executable/app packaging
-   [ ] macOS `.app`
-   [ ] Linux bundle
-   [ ] Installer
-   [ ] Uninstaller
-   [ ] Code signing
-   [ ] macOS notarization
-   [ ] Linux packages
-   [ ] Auto-update
-   [ ] Crash dumps
-   [x] Platform capability discovery
-   [ ] Platform permission handling
-   [ ] Sandboxed distribution strategy where needed

# 23. UI Layout & Styling Language

-   [x] Row/column concepts
-   [x] Align/spread work
-   [x] Padding/placeholder work
-   [x] CSS is exact renderer standard in D60
-   [ ] Freeze developer-facing Otter styling syntax
-   [x] Width/height
-   [ ] Min/max size
-   [ ] Margin
-   [x] Padding
-   [x] Gap/spacing
-   [x] Alignment
-   [x] Distribution
-   [ ] Flex behavior
-   [ ] Grid behavior if justified
-   [ ] Positioning
-   [ ] Explicit absolute/free positioning
-   [x] Overflow/scroll
-   [ ] Borders
-   [ ] Radius
-   [x] Background
-   [x] Foreground
-   [ ] Typography
-   [ ] Shadows
-   [ ] Opacity
-   [ ] Transform
-   [ ] Responsive breakpoints
-   [ ] State styles
-   [x] Themes/tokens
-   [x] Animation
-   [x] Transitions
-   [x] Raw CSS escape hatch
-   [x] Deterministic Web/Desktop styling parity

# 24. Graphics Foundation

-   [x] Color type/helpers
-   [ ] Point
-   [x] Size
-   [ ] Rectangle
-   [ ] Vector2
-   [ ] Vector3
-   [ ] Vector4
-   [ ] Matrix
-   [ ] Quaternion
-   [ ] Transform
-   [x] 2D canvas
-   [x] Lines
-   [x] Rectangles
-   [x] Circles/ellipses
-   [ ] Paths
-   [ ] Polygons
-   [x] Text drawing
-   [ ] Images/textures
-   [ ] Gradients
-   [ ] Clipping
-   [ ] Layers
-   [ ] Blend modes
-   [ ] Offscreen rendering
-   [x] Screenshot/export
-   [x] SVG/vector graphics
-   [ ] GPU-accelerated graphics provider

# 25. 2D Game Development

-   [x] 2D Game Studio archetype reported
-   [x] Production-certify generated game
-   [x] Game loop
-   [x] Delta time
-   [ ] Fixed timestep option
-   [x] Keyboard input
-   [x] Pointer/mouse input
-   [ ] Touch
-   [ ] Gamepad
-   [ ] Sprites
-   [ ] Sprite sheets
-   [ ] Animation
-   [ ] Collision
-   [ ] Physics
-   [ ] Scenes
-   [ ] Entities
-   [ ] Components
-   [ ] Camera
-   [ ] Tile maps
-   [ ] Particles
-   [ ] Lighting
-   [ ] Audio
-   [ ] Music
-   [x] UI/HUD
-   [ ] Save/load
-   [ ] Asset manager
-   [ ] Level loading
-   [ ] Fullscreen/window
-   [ ] Resolution/scaling
-   [ ] Frame timing
-   [ ] Game profiler
-   [x] Web export
-   [x] Desktop export
-   [ ] Controller compatibility
-   [ ] Packaging

# 26. 3D Graphics Engine

-   [ ] Vector3
-   [ ] Matrix4
-   [ ] Quaternion
-   [ ] Transform hierarchy
-   [ ] Coordinate-system specification
-   [x] Camera
-   [x] Perspective projection
-   [ ] Orthographic projection
-   [x] Mesh
-   [x] Vertices
-   [x] Indices
-   [ ] Normals
-   [ ] UVs
-   [ ] Tangents
-   [ ] Materials
-   [ ] Textures
-   [ ] Samplers
-   [ ] Lights
-   [ ] Shadows
-   [x] Depth testing
-   [ ] Culling
-   [ ] Transparency
-   [ ] Render targets
-   [ ] Framebuffers
-   [ ] Shader abstraction
-   [ ] Shader compilation/provider
-   [ ] PBR materials
-   [ ] HDR
-   [ ] Post-processing
-   [ ] Skybox/environment
-   [ ] Instancing
-   [ ] Level of detail
-   [ ] Occlusion/frustum culling
-   [ ] Skeletal animation
-   [ ] Skinning
-   [ ] Morph targets
-   [ ] Particle systems
-   [ ] 3D audio
-   [ ] GPU resource lifetime
-   [ ] Graphics backend/provider abstraction
-   [x] WebGPU/WebGL provider
-   [ ] Direct3D provider strategy
-   [ ] Vulkan provider strategy
-   [ ] Metal provider strategy

# 27. 3D Creation / Modeling

-   [ ] Scene graph
-   [ ] Object hierarchy
-   [x] Primitive creation: cube
-   [ ] Sphere
-   [ ] Cylinder
-   [ ] Cone
-   [ ] Plane
-   [ ] Torus
-   [ ] Mesh editing API
-   [ ] Vertex selection/editing
-   [ ] Edge selection/editing
-   [ ] Face selection/editing
-   [ ] Extrude
-   [ ] Inset
-   [ ] Bevel
-   [ ] Loop cut
-   [ ] Subdivide
-   [ ] Merge/weld
-   [ ] Knife/cut
-   [ ] Fill
-   [ ] Normals tools
-   [ ] UV unwrap
-   [ ] UV editor data model
-   [ ] Modifiers
-   [ ] Mirror
-   [ ] Array
-   [ ] Solidify
-   [ ] Subdivision surface
-   [ ] Boolean
-   [ ] Decimate
-   [ ] Sculpting architecture
-   [ ] Brushes
-   [ ] Painting/texturing
-   [ ] Material editor
-   [ ] Node graph system
-   [ ] Geometry nodes/procedural modeling strategy
-   [ ] Rigging
-   [ ] Bones
-   [ ] Weight painting
-   [ ] Keyframe animation
-   [ ] Curves
-   [ ] Animation graph/timeline
-   [ ] Constraints
-   [ ] Cameras
-   [ ] Lighting
-   [ ] Render settings
-   [ ] Import OBJ
-   [ ] Export OBJ
-   [ ] Import/export glTF
-   [ ] Import/export FBX via licensed/provider tooling if appropriate
-   [ ] Import/export STL
-   [ ] Import/export 3MF
-   [ ] Scene save format
-   [ ] Undo/redo command model
-   [ ] Non-destructive editing
-   [ ] GPU viewport
-   [ ] Picking/selection
-   [ ] Gizmos
-   [ ] Snapping
-   [ ] Grid
-   [ ] Units
-   [ ] Measurement
-   [ ] 3D printing validation tools if pursued

# 28. Game Engine / 3D Engine Layer

-   [ ] Entity/component architecture decision
-   [ ] Scene lifecycle
-   [ ] Prefabs/templates
-   [ ] Physics 2D
-   [ ] Physics 3D
-   [ ] Rigid bodies
-   [ ] Colliders
-   [ ] Ray casting
-   [ ] Navigation/pathfinding
-   [ ] AI behavior system
-   [ ] Animation state machines
-   [ ] Audio engine
-   [ ] Input mapping
-   [ ] UI overlay
-   [ ] Save system
-   [ ] Resource manager
-   [ ] Streaming assets
-   [ ] Scene streaming
-   [ ] Networking/multiplayer architecture
-   [ ] Deterministic simulation strategy if needed
-   [ ] Editor play mode
-   [ ] Hot reload
-   [ ] Build/export pipeline
-   [ ] Platform abstraction
-   [ ] Profiling
-   [ ] Debug visualization

# 29. Audio & Media

-   [ ] Play sound
-   [ ] Play music
-   [ ] Volume/pan
-   [ ] Audio devices
-   [ ] Recording
-   [ ] Streaming audio
-   [ ] 3D spatial audio
-   [ ] Audio effects
-   [ ] MIDI provider
-   [ ] Video playback
-   [ ] Video metadata
-   [ ] Image codecs
-   [ ] Audio codecs via libraries/providers
-   [ ] Media capture provider
-   [ ] Cross-platform media abstraction

# 30. Native Interoperability / FFI

-   [ ] Define FFI model
-   [ ] Call C ABI
-   [ ] Native shared libraries
-   [ ] Windows DLLs
-   [ ] macOS dylibs/frameworks
-   [ ] Linux `.so`
-   [ ] Primitive marshaling
-   [ ] Strings
-   [ ] Structs
-   [ ] Arrays/buffers
-   [ ] Callbacks
-   [ ] Function pointers
-   [ ] Ownership/lifetime
-   [ ] Error propagation
-   [ ] Threading rules
-   [ ] Unsafe/native capability clearly visible
-   [ ] Native binding generator
-   [ ] C header importer if useful
-   [ ] C#/.NET interop provider if desired
-   [ ] Java/JVM interop provider if desired
-   [ ] Python interop provider if desired
-   [ ] JavaScript/npm interop strategy
-   [ ] WebAssembly interoperability
-   [ ] ABI/version compatibility tests

# 31. Package Ecosystem

-   [ ] Package manifest
-   [ ] Semantic versions
-   [ ] Package registry
-   [ ] Install
-   [ ] Remove
-   [ ] Update
-   [ ] Lock file
-   [ ] Reproducible restore
-   [ ] Transitive dependencies
-   [ ] Version constraints
-   [ ] Conflict resolution
-   [ ] Local packages
-   [ ] Git packages if allowed
-   [ ] Integrity hashes
-   [ ] Signing
-   [ ] Vulnerability advisories
-   [ ] License metadata
-   [ ] Private registries
-   [ ] Offline cache
-   [ ] Publish
-   [ ] Deprecate/yank
-   [ ] Package documentation
-   [ ] Native dependency handling
-   [ ] Target-specific packages
-   [ ] Provider packages

# 32. Build System

-   [ ] Project manifest
-   [ ] Entry point
-   [ ] Target
-   [ ] Dependencies
-   [ ] Assets
-   [ ] Debug configuration
-   [ ] Release configuration
-   [ ] Incremental build
-   [ ] Dependency graph
-   [ ] Parallel build
-   [ ] Build cache
-   [ ] Deterministic builds
-   [ ] Clean
-   [ ] Rebuild
-   [ ] Resource processing
-   [ ] Asset processing
-   [ ] Source maps/debug metadata
-   [ ] Version stamping
-   [ ] Build hooks with trust/security model
-   [ ] Cross-compilation strategy
-   [ ] CI-friendly command
-   [ ] `otter build`
-   [ ] `otter publish`

# 33. Compiler Targets

-   [x] Interpreter
-   [x] JavaScript compiler
-   [x] Browser JavaScript certification
-   [x] Desktop JavaScript/container certification
-   [x] Node/server target decision
-   [ ] WebAssembly target
-   [ ] Native-code target strategy
-   [ ] LLVM backend evaluation
-   [ ] .NET IL backend evaluation
-   [ ] JVM backend evaluation
-   [ ] C transpilation backend evaluation
-   [ ] Embedded backend strategy
-   [ ] GPU shader/backend strategy
-   [ ] Debug information
-   [ ] Source maps
-   [ ] Optimization levels
-   [ ] Dead-code elimination
-   [ ] Constant folding
-   [ ] Tree shaking
-   [ ] Minification for web
-   [x] Backend conformance tests
-   [x] Backend capability matrix

# 34. Performance

-   [ ] Benchmark suite
-   [ ] Lexer benchmark
-   [ ] Parser benchmark
-   [ ] Interpreter benchmark
-   [ ] Compiler benchmark
-   [ ] Startup benchmark
-   [ ] Memory benchmark
-   [ ] File IO benchmark
-   [ ] HTTP benchmark
-   [ ] UI benchmark
-   [ ] Game-loop benchmark
-   [ ] 3D render benchmark
-   [ ] Profiling hooks
-   [ ] CPU profiler integration
-   [ ] Memory profiler integration
-   [ ] Allocation tracking
-   [ ] Performance regression CI
-   [ ] Optimization policy that preserves semantics

# 35. Testing Framework

-   [x] Native Otter test syntax/API
-   [x] Assertions
-   [x] Setup/teardown
-   [ ] Parameterized tests
-   [ ] Async tests
-   [x] Expected errors
-   [x] Test discovery
-   [ ] Filtering
-   [ ] Coverage
-   [ ] Mock/fake strategy
-   [x] Filesystem tests
-   [x] HTTP tests
-   [x] UI tests
-   [x] Browser tests
-   [x] Desktop tests
-   [ ] Game tests
-   [ ] Graphics tests
-   [x] Cross-platform tests
-   [ ] Golden tests
-   [x] Differential runtime tests
-   [ ] Fuzz parser/runtime tests
-   [ ] Property-based testing if useful

# 36. Debugging Runtime Support

-   [ ] Breakpoint hooks
-   [x] Source mapping
-   [ ] Step over
-   [ ] Step into
-   [ ] Step out
-   [ ] Pause
-   [ ] Continue
-   [ ] Stack frames
-   [ ] Locals
-   [ ] Globals
-   [ ] Watches
-   [ ] Evaluate expression
-   [x] Error breakpoints
-   [ ] Async stack support
-   [ ] Debug protocol
-   [ ] Debug Adapter Protocol evaluation
-   [x] Browser debugging mapping
-   [x] Desktop debugging mapping
-   [x] Server debugging
-   [ ] Game debugging
-   [x] 3D scene debug visualization

# 37. Security Model

-   [ ] Language/runtime threat model
-   [ ] Trusted/untrusted code model
-   [ ] Capability/permission model
-   [ ] Filesystem permissions
-   [ ] Network permissions
-   [ ] Process permissions
-   [ ] Native/FFI permissions
-   [ ] Browser sandbox boundaries
-   [ ] Desktop bridge isolation
-   [ ] Secret storage
-   [ ] Dependency security
-   [ ] Package signing
-   [ ] Supply-chain scanning
-   [ ] SBOM
-   [ ] Sandboxing strategy
-   [ ] Resource limits
-   [ ] Path traversal defenses
-   [ ] Command injection defenses
-   [ ] Deserialization safety
-   [ ] Web security defaults
-   [ ] Secure update mechanism
-   [ ] Security reporting process

# 38. Cross-Platform Semantics

-   [x] Windows semantic certification
-   [ ] macOS semantic certification
-   [ ] Linux semantic certification
-   [x] Browser semantic certification
-   [ ] Case-sensitive filesystem behavior
-   [x] Path separators
-   [x] Line endings
-   [x] Unicode filenames
-   [ ] Environment variables
-   [x] Shell differences
-   [ ] Process signals
-   [ ] Permissions
-   [ ] Time zones/locales
-   [ ] Networking
-   [ ] UI scaling
-   [ ] Graphics backends
-   [x] Feature/capability discovery
-   [x] Clear unsupported-capability errors
-   [x] No host-specific semantic drift

# 39. Mobile / Future Targets

-   [ ] Mobile architecture
-   [ ] Android
-   [ ] iOS
-   [ ] Touch
-   [ ] Sensors
-   [ ] Camera
-   [ ] Location provider
-   [ ] Notifications
-   [ ] App lifecycle
-   [ ] Mobile storage
-   [ ] Mobile packaging
-   [ ] Store publishing
-   [ ] Embedded/IoT strategy
-   [ ] Microcontroller backend research
-   [ ] Kernel/driver target explicitly scoped
-   [ ] Cloud/serverless target
-   [ ] WebAssembly/WASI target

# 40. Data Science / AI / Compute Ecosystem

-   [ ] Arrays/tensors package
-   [ ] DataFrame/table package
-   [ ] Statistics
-   [ ] CSV/Parquet providers
-   [ ] Plotting
-   [ ] Notebook/interactive workflow
-   [ ] ML provider interoperability
-   [ ] ONNX provider
-   [ ] GPU compute provider
-   [ ] CUDA interoperability if appropriate
-   [ ] WebGPU compute
-   [ ] Parallel numerical operations
-   [ ] Python ecosystem bridge if strategically useful

# 41. Developer Tooling Required by the Language

-   [ ] Formatter
-   [ ] Linter
-   [x] Language service
-   [ ] Autocomplete
-   [ ] Hover
-   [ ] Go to definition
-   [ ] References
-   [ ] Rename
-   [ ] Refactoring
-   [ ] Documentation generator
-   [ ] Package manager
-   [ ] Build tool
-   [x] Test runner
-   [ ] Debugger
-   [ ] Profiler
-   [x] REPL
-   [ ] Dependency inspector
-   [x] Compiler diagnostics
-   [ ] API browser
-   [ ] Migration tool
-   [ ] Version manager/runtime manager if required

# 42. Documentation

-   [ ] Language tour
-   [ ] Installation
-   [x] Grammar reference
-   [x] Semantic specification
-   [x] Standard library
-   [x] Runtime/provider API
-   [ ] Shell/system administration guide
-   [ ] Console guide
-   [ ] Files guide
-   [ ] Networking guide
-   [ ] Database guide
-   [ ] Desktop guide
-   [ ] Web frontend guide
-   [ ] Web backend guide
-   [ ] Game guide
-   [ ] 3D graphics guide
-   [ ] 3D modeling guide
-   [ ] FFI guide
-   [ ] Package-author guide
-   [ ] Compiler/backend guide
-   [ ] Security guide
-   [ ] Performance guide
-   [ ] Cross-platform guide
-   [x] Migration/version guide
-   [ ] Complete searchable API reference
-   [x] Cookbook/examples

# 43. Dogfood Applications

-   [x] Task List reported
-   [x] File Browser reported
-   [x] Contact Manager reported
-   [x] `studio-v1.ot` web build reported
-   [x] Real shell administration utility
-   [x] Complete CLI program
-   [x] File synchronization/automation tool
-   [x] Complete desktop CRUD application
-   [x] Complete web frontend
-   [x] Complete REST API
-   [ ] Full-stack web application
-   [ ] Database application
-   [x] 2D game
-   [x] 3D game/demo
-   [ ] 3D modeling utility
-   [ ] Package/library
-   [ ] Multi-module large application
-   [x] Otter Studio substantially implemented in Otter
-   [x] Every advertised standard-library feature used by real `.ot`
    code

# 44. Conformance

-   [x] Positive grammar tests for every construct
-   [x] Negative grammar tests
-   [x] Semantic tests
-   [x] Interpreter tests
-   [x] JS compiler tests
-   [x] Browser tests
-   [x] Desktop tests
-   [x] Windows tests
-   [ ] macOS tests
-   [ ] Linux tests
-   [x] Standard-library tests
-   [x] Provider tests
-   [x] Cross-runtime differential tests
-   [ ] Golden output tests
-   [x] Error-message tests
-   [ ] Version compatibility tests
-   [ ] Migration tests
-   [ ] Fuzzing
-   [ ] Long-running stability tests

# 45. Release Engineering

-   [x] Versioning
-   [ ] Changelog
-   [ ] Release notes
-   [ ] Windows CI
-   [ ] macOS CI
-   [ ] Linux CI
-   [ ] Browser CI
-   [ ] Packaging CI
-   [x] Checksums
-   [ ] Signing
-   [ ] Installer
-   [ ] Runtime distribution
-   [ ] Standard-library distribution
-   [ ] Package registry availability
-   [ ] Update mechanism
-   [ ] Nightly/preview channel
-   [ ] Stable channel
-   [ ] Rollback
-   [ ] Fresh-machine tests
-   [x] Offline install
-   [x] Reproducible-build goals
-   [ ] License/third-party notices

# 46. Otter 1.0 Core Release Gates

-   [x] Core syntax frozen
-   [x] Semantics frozen
-   [x] Formal specification
-   [x] Conformance suite
-   [x] No silent no-ops
-   [x] Portable JS parity complete
-   [x] Core standard library certified
-   [x] Files certified
-   [x] HTTP certified
-   [x] JSON certified
-   [x] Dates/random certified
-   [x] Command/process API certified
-   [x] Module system certified
-   [x] Console target certified
-   [x] Advertised Web target certified
-   [x] Advertised Desktop target certified
-   [x] Diagnostics certified
-   [ ] Packaging/install certified
-   [ ] Security review
-   [x] Documentation
-   [x] Real dogfood applications
-   [x] No known data-loss bugs
-   [x] No known critical security bugs
-   [x] Every advertised feature reachable through production entry
    point

# 47. General-Purpose Platform Gates

These gates move Otter beyond 1.0 into the "build essentially any
ordinary application" class.

-   [x] Mature standard library
-   [ ] Mature package ecosystem
-   [ ] Native FFI
-   [x] Complete console/system APIs
-   [x] Complete desktop application framework
-   [x] Complete web frontend framework
-   [x] Complete backend/API framework
-   [ ] Database ecosystem
-   [x] Async/concurrency model
-   [x] Testing ecosystem
-   [x] Debugging/profiling support
-   [x] Cross-platform packaging
-   [x] 2D game framework
-   [x] 3D rendering framework/provider
-   [ ] 3D modeling/creation APIs
-   [x] Graphics/audio/input providers
-   [x] Security/crypto providers
-   [x] Stable extension/provider interfaces
-   [x] Strong interoperability with native/external ecosystems
-   [x] Performance suitable for advertised workloads

# 48. Immediate Execution Order

## P0 --- Freeze and document what already exists

-   [x] Reconcile the current decision ledger.
-   [x] Resolve overloaded D61 numbering.
-   [x] Inventory implemented syntax against production parser.
-   [x] Inventory interpreter vs JS parity.
-   [x] Inventory standard-library/provider reachability.
-   [x] Record every current production-certified feature.

## P1 --- Finish the dependable core

-   [x] JSON parity.
-   [x] Random parity.
-   [x] Date parity.
-   [x] Diagnostics parity.
-   [x] Existing-thing `has` parity.
-   [x] Custom-type parity.
-   [x] Module production certification.
-   [x] Finish filesystem bridge certification.
-   [x] Freeze Otter 1.0 semantics.
-   [x] Publish specification.
-   [x] Build conformance suite.

## P2 --- Make Console/System Otter complete

-   [ ] Arguments/options.
-   [ ] Environment/cwd.
-   [x] Process management.
-   [x] Whole-program exit.
-   [x] Persistent PTY terminal.
-   [x] Signals.
-   [ ] System information.
-   [x] Services/tasks/log providers.
-   [ ] Cross-platform shell certification.

## P3 --- Make Desktop/Web application development complete

-   [x] Finish UI runtime primitives.
-   [x] Freeze styling/layout authoring.
-   [ ] File dialogs/clipboard/notifications/menus.
-   [x] Full web component/state/forms/routing stack.
-   [x] Backend/server runtime.
-   [ ] Database provider.
-   [x] Packaging/publishing.
-   [ ] Windows/macOS/Linux/browser certification.

## P4 --- Build professional language ecosystem

-   [ ] Package manager.
-   [ ] FFI.
-   [x] Test framework.
-   [x] Debug runtime.
-   [ ] Profiler hooks.
-   [x] Formatter/linter/language service.
-   [ ] Stable provider/plugin interfaces.

## P5 --- Games

-   [x] Graphics/input/audio foundation.
-   [ ] 2D engine.
-   [ ] Physics/scenes/assets.
-   [x] Web/Desktop game export.
-   [ ] Dogfood complete game.

## P6 --- 3D

-   [x] Vector/matrix/quaternion math.
-   [ ] GPU rendering abstraction.
-   [ ] Mesh/material/shader pipeline.
-   [ ] Cameras/lights/animation/physics.
-   [ ] Scene graph.
-   [x] 3D game demo.
-   [ ] Modeling mesh-edit operations.
-   [ ] Import/export.
-   [ ] Node/procedural system.
-   [ ] Dogfood 3D creation application.

## P7 --- General platform maturity

-   [ ] Mobile/future targets where desired.
-   [ ] Data/AI ecosystem.
-   [ ] Native interoperability ecosystem.
-   [ ] Package/provider ecosystem.
-   [x] Security/performance/cross-platform audits.
-   [x] Long-term compatibility and release policy.

# 49. Architecture Map

``` text
                             OTTER SOURCE
                                  |
                         Lexer → Parser → AST
                                  |
                         OTTER SEMANTICS
                                  |
                +-----------------+-----------------+
                |                 |                 |
           Interpreter       JS Compiler       Future Backends
                |                 |            (WASM/Native/etc.)
                +-----------------+-----------------+
                                  |
                            RUNTIME API
                                  |
      +-----------+----------+----+----+----------+-----------+
      |           |          |         |          |           |
    Files      Process     Network     Data       UI       Graphics
      |           |          |         |          |           |
      +-----------+----------+----+----+----------+-----------+
                                  |
                            PROVIDER LAYER
                                  |
   +------------+-----------+-----------+-----------+-------------+
   |            |           |           |           |             |
 Console      System       Web       Desktop      Games          3D
   |            |           |           |           |             |
   +------------+-----------+-----------+-----------+-------------+
                                  |
                       PLATFORM / HOST TARGETS
                                  |
            +-----------+----------+----------+----------+
            |           |          |          |          |
         Browser      Windows     macOS      Linux      Future
```

# 50. Final Success Definition

Otter reaches the long-term goal when a developer can use readable Otter
source to:

-   [ ] automate and administer a computer;
-   [ ] build complete command-line applications;
-   [ ] manipulate files, processes, networking, structured data, and
    databases;
-   [ ] build and package professional desktop applications;
-   [ ] build complete browser frontends;
-   [ ] build servers, APIs, and full-stack web applications;
-   [ ] build 2D games;
-   [ ] build 3D interactive applications and games;
-   [ ] create/edit/render 3D scenes and models through an appropriate
    engine/provider;
-   [ ] call native/external libraries when the standard platform does
    not provide a capability;
-   [ ] test, debug, profile, package, and publish those programs;
-   [ ] run appropriate source consistently across supported hosts;
-   [ ] extend the platform without changing core Otter semantics.

**North star:** **Readable like English. Precise like code. Powerful
enough for complete applications.**
