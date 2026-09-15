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
-   [ ] Formal grammar
-   [ ] Formal semantic specification
-   [ ] Versioned AST contract
-   [ ] Standard diagnostic contract
-   [ ] Language version declaration/strategy
-   [ ] Compatibility policy
-   [ ] Deprecation policy
-   [ ] Feature-gating/version negotiation
-   [ ] Conformance suite
-   [ ] Reference implementation designation
-   [ ] Runtime/provider specification
-   [ ] Standard-library specification
-   [ ] Compiler backend interface
-   [ ] Host capability interface
-   [ ] Stable module/package ABI/API strategy

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
-   [x] Percent operation
-   [x] Power operation
-   [x] Mutation with `increase`
-   [x] Mutation with `decrease`
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
-   [ ] Freeze all remaining contextual-keyword behavior
-   [ ] Freeze operator precedence table
-   [ ] Document evaluation order
-   [ ] Short-circuit behavior certification
-   [ ] Tail-call behavior decision
-   [ ] Generator/yield decision only if real applications require it
-   [ ] Pattern matching decision only if dogfooding requires it

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
-   [ ] Numeric precision/range specification
-   [ ] Integer vs floating-point strategy
-   [ ] Large integer strategy
-   [ ] Decimal/money-safe numeric strategy
-   [ ] Unicode string semantics
-   [ ] Grapheme-safe string operations
-   [ ] Binary/byte data
-   [ ] Buffers
-   [ ] Streams
-   [ ] Immutable/read-only values if demonstrated necessary
-   [ ] Map/dictionary decision
-   [ ] Set collection decision
-   [ ] Tuple/record decision
-   [ ] Enum/symbol decision
-   [ ] Structured error value/type
-   [ ] User-defined types parity
-   [ ] Type metadata/reflection strategy
-   [ ] Serialization contract

# 4. Objects, Types & Properties

-   [x] `person has ...`
-   [x] Legacy thing construction
-   [x] Inline `with` configuration work
-   [x] Property access using `of`
-   [x] Nested property access
-   [x] Property assignment
-   [x] Dynamic object keys
-   [x] JS plain-object alias semantics
-   [ ] Portable custom `OtterType` construction parity
-   [ ] Resolve existing-thing `has` protective parity
-   [ ] Methods/member-behavior decision
-   [ ] Encapsulation/public-private decision
-   [ ] Composition model
-   [ ] Inheritance decision --- only if justified
-   [ ] Interface/protocol/trait strategy if needed
-   [ ] Generic/template type strategy if needed
-   [ ] Reflection/introspection
-   [ ] Runtime type querying
-   [ ] Object cloning/copying
-   [ ] Equality/hash semantics

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
-   [ ] Production-certify `use`
-   [ ] Freeze module resolution
-   [ ] Relative modules
-   [ ] Package modules
-   [ ] Circular dependency semantics
-   [ ] Module initialization order
-   [ ] Duplicate-load semantics
-   [ ] Public/private exports if needed
-   [ ] Namespace collision policy
-   [ ] Module caching/invalidation
-   [ ] Closures
-   [ ] First-class function values if required
-   [ ] Callbacks/delegates
-   [ ] Lambda/anonymous function decision only if necessary
-   [ ] Cross-module symbol metadata for IDE tooling

# 6. Errors & Diagnostics

-   [x] `try` / `otherwise`
-   [x] Runtime errors
-   [x] `log`
-   [x] `warn`
-   [x] `error`
-   [x] Source diagnostics exist
-   [ ] Stable diagnostic codes
-   [ ] Exact file/line/column ranges
-   [ ] Multiple diagnostics per parse where safe
-   [ ] Parser recovery
-   [ ] Stack traces expressed in Otter terms
-   [ ] Nested/cause errors
-   [ ] Structured errors
-   [ ] Error categories
-   [ ] Custom/user errors
-   [ ] Async error propagation
-   [ ] Host/provider error translation
-   [ ] Diagnostic suggestions/quick fixes
-   [ ] Panic/fatal-runtime policy
-   [ ] Crash-report format

# 7. Memory & Resource Management

-   [ ] Define memory model
-   [ ] Garbage collection/reference management strategy per backend
-   [ ] Resource lifetime semantics
-   [ ] Deterministic cleanup mechanism where needed
-   [ ] File/socket/process handle cleanup
-   [ ] Disposal/finalization model
-   [ ] Circular reference behavior
-   [ ] Weak references only if needed
-   [ ] Memory limits
-   [ ] Out-of-memory behavior
-   [ ] Large-object handling
-   [ ] Native resource ownership rules
-   [ ] FFI ownership rules

# 8. Async, Tasks, Timers & Concurrency

-   [x] Async compiler support exists for file/HTTP operations in
    functions
-   [ ] Language-level async task model
-   [ ] Awaiting asynchronous operations
-   [ ] Cancellation
-   [ ] Cancellation tokens/signals
-   [ ] Timeouts
-   [ ] One-shot timers
-   [ ] Repeating timers
-   [ ] Background tasks
-   [ ] Worker/thread abstraction
-   [ ] Thread-safe runtime rules
-   [ ] Synchronization primitives
-   [ ] Channels/message passing
-   [ ] Concurrent collections if needed
-   [ ] UI-thread dispatch
-   [ ] Process concurrency
-   [ ] Parallel loops/tasks if justified
-   [ ] Deadlock guidance/tooling
-   [ ] Race detection strategy
-   [ ] Structured concurrency decision

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
-   [ ] File exists portable certification
-   [ ] Folder exists
-   [ ] Atomic save
-   [ ] Safe overwrite
-   [ ] Text encodings
-   [ ] Binary read/write
-   [ ] Random-access file IO
-   [ ] Streams
-   [ ] Large-file handling
-   [ ] File locks
-   [ ] File watching
-   [ ] Recursive watching
-   [ ] Temp files/folders
-   [ ] User/app data folders
-   [ ] Path combine/normalize
-   [ ] Cross-platform path rules
-   [ ] Symbolic links/reparse points
-   [ ] Permission/ownership APIs
-   [ ] Disk/free-space information
-   [ ] File dialogs via UI provider
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
-   [ ] Command-line arguments
-   [ ] Environment variables
-   [ ] Current directory get/set
-   [ ] PATH inspection
-   [ ] Process enumeration
-   [ ] Process details
-   [ ] Start process
-   [ ] Stop process
-   [ ] Kill process tree
-   [ ] Process priority
-   [ ] Process timeout
-   [ ] Signals
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
-   [ ] Clipboard
-   [ ] Notifications
-   [ ] Power/reboot/shutdown APIs with explicit safety
-   [ ] Printer/device APIs via providers
-   [ ] Remote administration strategy
-   [ ] SSH client/provider
-   [ ] Secure shell escaping
-   [ ] Auditing/logging for privileged operations

# 11. Terminal & REPL

-   [ ] Persistent PTY/ConPTY
-   [ ] Character stdin
-   [ ] stdout/stderr streaming
-   [ ] ANSI/VT
-   [ ] Terminal resize
-   [ ] Ctrl+C/signals
-   [ ] Interactive programs
-   [ ] Persistent shell state
-   [ ] Multiple sessions
-   [ ] Shell profiles
-   [ ] Cross-platform PTY abstraction
-   [ ] Otter REPL
-   [ ] Persistent REPL variables
-   [ ] REPL function definitions
-   [ ] Multiline blocks
-   [ ] History
-   [ ] Completion
-   [ ] Syntax highlighting
-   [ ] Pretty-print values
-   [ ] Object/list inspection
-   [ ] Module loading
-   [ ] Session reset
-   [ ] Error recovery

# 12. Console Application Development

-   [x] Console output
-   [x] Console input
-   [x] Files
-   [x] Command execution
-   [ ] CLI argument API
-   [ ] Named flags/options helper
-   [ ] stdin
-   [ ] stdout
-   [ ] stderr
-   [ ] Pipe support
-   [ ] Redirect support
-   [ ] Exit program
-   [ ] Exit code
-   [ ] Signals
-   [ ] Terminal colors/styles
-   [ ] Cursor positioning
-   [ ] Interactive menus
-   [ ] Progress indicators
-   [ ] Password/secret input
-   [ ] TTY detection
-   [ ] Noninteractive mode
-   [ ] Standalone executable packaging
-   [ ] Cross-platform console certification

# 13. Networking

-   [x] HTTP GET reported
-   [x] HTTP POST reported
-   [x] HTTP PUT reported
-   [x] HTTP DELETE reported
-   [ ] Headers
-   [ ] Query parameters
-   [ ] Request body types
-   [ ] JSON integration
-   [ ] Form encoding
-   [ ] Multipart/form-data
-   [ ] File upload
-   [ ] File download
-   [ ] Streaming
-   [ ] Timeouts
-   [ ] Cancellation
-   [ ] Redirect policy
-   [ ] Cookies
-   [ ] Sessions
-   [ ] Authentication helpers
-   [ ] TLS/certificate handling
-   [ ] Proxy
-   [ ] DNS
-   [ ] WebSocket client
-   [ ] WebSocket server
-   [ ] TCP
-   [ ] UDP
-   [ ] Unix/domain sockets where supported
-   [ ] Network diagnostics
-   [ ] Rate limiting helpers
-   [ ] Retry/backoff
-   [ ] Connection pooling

# 14. Data Formats & Serialization

-   [x] JSON support exists in interpreter
-   [ ] JSON portable certification
-   [ ] JSON serialize
-   [ ] JSON nested round trip
-   [ ] JSON `gone`/null mapping
-   [ ] CSV read/write
-   [ ] XML
-   [ ] YAML if demanded
-   [ ] URL encoding
-   [ ] Base64
-   [ ] Hex
-   [ ] Binary serialization strategy
-   [ ] Compression
-   [ ] MIME/content-type helpers
-   [ ] Schema validation
-   [ ] Data conversion/coercion rules

# 15. Dates, Time & Random

-   [x] Date support exists in interpreter
-   [ ] Portable date certification
-   [ ] Current local time
-   [ ] UTC
-   [ ] Time zones
-   [ ] Date parsing
-   [ ] Date formatting
-   [ ] Date arithmetic
-   [ ] Durations
-   [ ] Monotonic time
-   [ ] High-resolution timer
-   [ ] Random portable certification
-   [ ] Seeded deterministic random
-   [ ] Cryptographically secure random provider

# 16. Math & Scientific Foundation

-   [x] Basic arithmetic
-   [x] Percent
-   [x] Power
-   [ ] Absolute value
-   [ ] Round/floor/ceiling
-   [ ] Min/max
-   [ ] Square root
-   [ ] Trigonometry
-   [ ] Logarithms
-   [ ] Constants
-   [ ] Vector math
-   [ ] Matrix math
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

-   [ ] Cryptographic random
-   [ ] Hashing
-   [ ] HMAC
-   [ ] Symmetric encryption
-   [ ] Public-key cryptography
-   [ ] Signing/verification
-   [ ] Certificate APIs
-   [ ] Secure secret storage
-   [ ] Password hashing through proven libraries
-   [ ] Constant-time primitives delegated to vetted libraries
-   [ ] TLS provider
-   [ ] Keychain/Credential Manager/libsecret providers
-   [ ] Never invent custom cryptography
-   [ ] Security-sensitive APIs clearly marked

# 19. Full Web Frontend Development

-   [x] JavaScript portable compiler
-   [x] Web application export path
-   [x] Shared HTML/CSS/JS representation direction
-   [ ] HTML/document abstraction
-   [ ] Components
-   [ ] Reusable components
-   [ ] Properties/attributes
-   [ ] Events
-   [ ] State
-   [ ] Derived state
-   [ ] Reactive updates
-   [ ] Conditional rendering
-   [ ] List rendering
-   [ ] Forms
-   [ ] Validation
-   [ ] Routing
-   [ ] Route parameters
-   [ ] Navigation/history
-   [ ] Browser storage
-   [ ] Cookies
-   [ ] Fetch/HTTP
-   [ ] WebSockets
-   [ ] File upload/download
-   [ ] Drag/drop
-   [ ] Clipboard
-   [ ] Browser notifications
-   [ ] Canvas
-   [ ] SVG
-   [ ] Audio/video
-   [ ] Accessibility
-   [ ] Responsive design
-   [ ] CSS exact escape hatch
-   [ ] Otter-native styling authoring layer
-   [ ] CSS variables/themes
-   [ ] Animation/transitions
-   [ ] Asset bundling
-   [ ] CSS bundling
-   [ ] JS bundling
-   [ ] Minification
-   [ ] Source maps
-   [ ] Dev server
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

-   [ ] HTTP server runtime
-   [ ] Routes
-   [ ] Route parameters
-   [ ] Query parameters
-   [ ] Request body
-   [ ] Response body
-   [ ] Headers
-   [ ] Cookies
-   [ ] Sessions
-   [ ] Middleware
-   [ ] JSON APIs
-   [ ] REST helpers
-   [ ] Static files
-   [ ] File upload
-   [ ] Streaming responses
-   [ ] WebSockets
-   [ ] Authentication hooks
-   [ ] Authorization hooks
-   [ ] CORS
-   [ ] CSRF protections
-   [ ] Rate limiting
-   [ ] Request limits
-   [ ] Logging
-   [ ] Configuration
-   [ ] Secrets
-   [ ] Database integration
-   [ ] Background jobs
-   [ ] Email provider
-   [ ] Caching provider
-   [ ] Queue/message broker provider
-   [ ] Graceful shutdown
-   [ ] Health checks
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
-   [ ] Production-certify current V1 desktop controls
-   [ ] Window
-   [ ] Multiple windows
-   [ ] Row
-   [ ] Column
-   [ ] Grid when justified
-   [ ] Panel/card
-   [ ] Text/heading
-   [ ] Button
-   [ ] Text box
-   [ ] Text area/editor
-   [ ] Checkbox
-   [ ] Radio
-   [ ] Toggle
-   [ ] Select/dropdown
-   [ ] List
-   [ ] Data grid
-   [ ] Tree
-   [ ] Tabs
-   [ ] Menu
-   [ ] Toolbar
-   [ ] Status bar
-   [ ] Dialog/modal
-   [ ] Image
-   [ ] Icon
-   [ ] Progress
-   [ ] Slider
-   [ ] Date/time controls
-   [ ] Scroll container
-   [ ] Split panes
-   [ ] Custom controls
-   [ ] Focus
-   [ ] Show/hide
-   [ ] Keyboard events
-   [ ] Pointer events
-   [ ] Resize events
-   [ ] Window lifecycle
-   [ ] Clipboard
-   [ ] OS drag/drop
-   [ ] File/folder/save pickers
-   [ ] Notifications
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
-   [ ] Final Windows-host certification
-   [ ] Generic host API independent of one browser implementation
-   [ ] In-process IPC where appropriate
-   [ ] Windows runtime
-   [ ] macOS runtime
-   [ ] Linux runtime
-   [ ] Windows executable/app packaging
-   [ ] macOS `.app`
-   [ ] Linux bundle
-   [ ] Installer
-   [ ] Uninstaller
-   [ ] Code signing
-   [ ] macOS notarization
-   [ ] Linux packages
-   [ ] Auto-update
-   [ ] Crash dumps
-   [ ] Platform capability discovery
-   [ ] Platform permission handling
-   [ ] Sandboxed distribution strategy where needed

# 23. UI Layout & Styling Language

-   [x] Row/column concepts
-   [x] Align/spread work
-   [x] Padding/placeholder work
-   [x] CSS is exact renderer standard in D60
-   [ ] Freeze developer-facing Otter styling syntax
-   [ ] Width/height
-   [ ] Min/max size
-   [ ] Margin
-   [ ] Padding
-   [ ] Gap/spacing
-   [ ] Alignment
-   [ ] Distribution
-   [ ] Flex behavior
-   [ ] Grid behavior if justified
-   [ ] Positioning
-   [ ] Explicit absolute/free positioning
-   [ ] Overflow/scroll
-   [ ] Borders
-   [ ] Radius
-   [ ] Background
-   [ ] Foreground
-   [ ] Typography
-   [ ] Shadows
-   [ ] Opacity
-   [ ] Transform
-   [ ] Responsive breakpoints
-   [ ] State styles
-   [ ] Themes/tokens
-   [ ] Animation
-   [ ] Transitions
-   [ ] Raw CSS escape hatch
-   [ ] Deterministic Web/Desktop styling parity

# 24. Graphics Foundation

-   [ ] Color type/helpers
-   [ ] Point
-   [ ] Size
-   [ ] Rectangle
-   [ ] Vector2
-   [ ] Vector3
-   [ ] Vector4
-   [ ] Matrix
-   [ ] Quaternion
-   [ ] Transform
-   [ ] 2D canvas
-   [ ] Lines
-   [ ] Rectangles
-   [ ] Circles/ellipses
-   [ ] Paths
-   [ ] Polygons
-   [ ] Text drawing
-   [ ] Images/textures
-   [ ] Gradients
-   [ ] Clipping
-   [ ] Layers
-   [ ] Blend modes
-   [ ] Offscreen rendering
-   [ ] Screenshot/export
-   [ ] SVG/vector graphics
-   [ ] GPU-accelerated graphics provider

# 25. 2D Game Development

-   [x] 2D Game Studio archetype reported
-   [ ] Production-certify generated game
-   [ ] Game loop
-   [ ] Delta time
-   [ ] Fixed timestep option
-   [ ] Keyboard input
-   [ ] Pointer/mouse input
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
-   [ ] UI/HUD
-   [ ] Save/load
-   [ ] Asset manager
-   [ ] Level loading
-   [ ] Fullscreen/window
-   [ ] Resolution/scaling
-   [ ] Frame timing
-   [ ] Game profiler
-   [ ] Web export
-   [ ] Desktop export
-   [ ] Controller compatibility
-   [ ] Packaging

# 26. 3D Math & Rendering

-   [ ] Vector3
-   [ ] Matrix4
-   [ ] Quaternion
-   [ ] Transform hierarchy
-   [ ] Coordinate-system specification
-   [ ] Camera
-   [ ] Perspective projection
-   [ ] Orthographic projection
-   [ ] Mesh
-   [ ] Vertices
-   [ ] Indices
-   [ ] Normals
-   [ ] UVs
-   [ ] Tangents
-   [ ] Materials
-   [ ] Textures
-   [ ] Samplers
-   [ ] Lights
-   [ ] Shadows
-   [ ] Depth testing
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
-   [ ] WebGPU/WebGL provider
-   [ ] Direct3D provider strategy
-   [ ] Vulkan provider strategy
-   [ ] Metal provider strategy

# 27. 3D Creation / Modeling

-   [ ] Scene graph
-   [ ] Object hierarchy
-   [ ] Primitive creation: cube
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
-   [ ] Browser JavaScript certification
-   [ ] Desktop JavaScript/container certification
-   [ ] Node/server target decision
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
-   [ ] Backend conformance tests
-   [ ] Backend capability matrix

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

-   [ ] Native Otter test syntax/API
-   [ ] Assertions
-   [ ] Setup/teardown
-   [ ] Parameterized tests
-   [ ] Async tests
-   [ ] Expected errors
-   [ ] Test discovery
-   [ ] Filtering
-   [ ] Coverage
-   [ ] Mock/fake strategy
-   [ ] Filesystem tests
-   [ ] HTTP tests
-   [ ] UI tests
-   [ ] Browser tests
-   [ ] Desktop tests
-   [ ] Game tests
-   [ ] Graphics tests
-   [ ] Cross-platform tests
-   [ ] Golden tests
-   [ ] Differential runtime tests
-   [ ] Fuzz parser/runtime tests
-   [ ] Property-based testing if useful

# 36. Debugging Runtime Support

-   [ ] Breakpoint hooks
-   [ ] Source mapping
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
-   [ ] Error breakpoints
-   [ ] Async stack support
-   [ ] Debug protocol
-   [ ] Debug Adapter Protocol evaluation
-   [ ] Browser debugging mapping
-   [ ] Desktop debugging mapping
-   [ ] Server debugging
-   [ ] Game debugging
-   [ ] 3D scene debug visualization

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

-   [ ] Windows semantic certification
-   [ ] macOS semantic certification
-   [ ] Linux semantic certification
-   [ ] Browser semantic certification
-   [ ] Case-sensitive filesystem behavior
-   [ ] Path separators
-   [ ] Line endings
-   [ ] Unicode filenames
-   [ ] Environment variables
-   [ ] Shell differences
-   [ ] Process signals
-   [ ] Permissions
-   [ ] Time zones/locales
-   [ ] Networking
-   [ ] UI scaling
-   [ ] Graphics backends
-   [ ] Feature/capability discovery
-   [ ] Clear unsupported-capability errors
-   [ ] No host-specific semantic drift

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
-   [ ] Language service
-   [ ] Autocomplete
-   [ ] Hover
-   [ ] Go to definition
-   [ ] References
-   [ ] Rename
-   [ ] Refactoring
-   [ ] Documentation generator
-   [ ] Package manager
-   [ ] Build tool
-   [ ] Test runner
-   [ ] Debugger
-   [ ] Profiler
-   [ ] REPL
-   [ ] Dependency inspector
-   [ ] Compiler diagnostics
-   [ ] API browser
-   [ ] Migration tool
-   [ ] Version manager/runtime manager if required

# 42. Documentation

-   [ ] Language tour
-   [ ] Installation
-   [ ] Grammar reference
-   [ ] Semantic specification
-   [ ] Standard library
-   [ ] Runtime/provider API
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
-   [ ] Migration/version guide
-   [ ] Complete searchable API reference
-   [ ] Cookbook/examples

# 43. Dogfood Applications

-   [x] Task List reported
-   [x] File Browser reported
-   [x] Contact Manager reported
-   [x] `studio-v1.ot` web build reported
-   [ ] Real shell administration utility
-   [ ] Complete CLI program
-   [ ] File synchronization/automation tool
-   [ ] Complete desktop CRUD application
-   [ ] Complete web frontend
-   [ ] Complete REST API
-   [ ] Full-stack web application
-   [ ] Database application
-   [ ] 2D game
-   [ ] 3D game/demo
-   [ ] 3D modeling utility
-   [ ] Package/library
-   [ ] Multi-module large application
-   [ ] Otter Studio substantially implemented in Otter
-   [ ] Every advertised standard-library feature used by real `.ot`
    code

# 44. Conformance

-   [ ] Positive grammar tests for every construct
-   [ ] Negative grammar tests
-   [ ] Semantic tests
-   [ ] Interpreter tests
-   [ ] JS compiler tests
-   [ ] Browser tests
-   [ ] Desktop tests
-   [ ] Windows tests
-   [ ] macOS tests
-   [ ] Linux tests
-   [ ] Standard-library tests
-   [ ] Provider tests
-   [ ] Cross-runtime differential tests
-   [ ] Golden output tests
-   [ ] Error-message tests
-   [ ] Version compatibility tests
-   [ ] Migration tests
-   [ ] Fuzzing
-   [ ] Long-running stability tests

# 45. Release Engineering

-   [ ] Versioning
-   [ ] Changelog
-   [ ] Release notes
-   [ ] Windows CI
-   [ ] macOS CI
-   [ ] Linux CI
-   [ ] Browser CI
-   [ ] Packaging CI
-   [ ] Checksums
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
-   [ ] Offline install
-   [ ] Reproducible-build goals
-   [ ] License/third-party notices

# 46. Otter 1.0 Core Release Gates

-   [ ] Core syntax frozen
-   [ ] Semantics frozen
-   [ ] Formal specification
-   [ ] Conformance suite
-   [ ] No silent no-ops
-   [ ] Portable JS parity complete
-   [ ] Core standard library certified
-   [ ] Files certified
-   [ ] HTTP certified
-   [ ] JSON certified
-   [ ] Dates/random certified
-   [ ] Command/process API certified
-   [ ] Module system certified
-   [ ] Console target certified
-   [ ] Advertised Web target certified
-   [ ] Advertised Desktop target certified
-   [ ] Diagnostics certified
-   [ ] Packaging/install certified
-   [ ] Security review
-   [ ] Documentation
-   [ ] Real dogfood applications
-   [ ] No known data-loss bugs
-   [ ] No known critical security bugs
-   [ ] Every advertised feature reachable through production entry
    point

# 47. General-Purpose Platform Gates

These gates move Otter beyond 1.0 into the "build essentially any
ordinary application" class.

-   [ ] Mature standard library
-   [ ] Mature package ecosystem
-   [ ] Native FFI
-   [ ] Complete console/system APIs
-   [ ] Complete desktop application framework
-   [ ] Complete web frontend framework
-   [ ] Complete backend/API framework
-   [ ] Database ecosystem
-   [ ] Async/concurrency model
-   [ ] Testing ecosystem
-   [ ] Debugging/profiling support
-   [ ] Cross-platform packaging
-   [ ] 2D game framework
-   [ ] 3D rendering framework/provider
-   [ ] 3D modeling/creation APIs
-   [ ] Graphics/audio/input providers
-   [ ] Security/crypto providers
-   [ ] Stable extension/provider interfaces
-   [ ] Strong interoperability with native/external ecosystems
-   [ ] Performance suitable for advertised workloads

# 48. Immediate Execution Order

## P0 --- Freeze and document what already exists

-   [ ] Reconcile the current decision ledger.
-   [ ] Resolve overloaded D61 numbering.
-   [ ] Inventory implemented syntax against production parser.
-   [ ] Inventory interpreter vs JS parity.
-   [ ] Inventory standard-library/provider reachability.
-   [ ] Record every current production-certified feature.

## P1 --- Finish the dependable core

-   [ ] JSON parity.
-   [ ] Random parity.
-   [ ] Date parity.
-   [ ] Diagnostics parity.
-   [ ] Existing-thing `has` parity.
-   [ ] Custom-type parity.
-   [ ] Module production certification.
-   [ ] Finish filesystem bridge certification.
-   [ ] Freeze Otter 1.0 semantics.
-   [ ] Publish specification.
-   [ ] Build conformance suite.

## P2 --- Make Console/System Otter complete

-   [ ] Arguments/options.
-   [ ] Environment/cwd.
-   [ ] Process management.
-   [ ] Whole-program exit.
-   [ ] Persistent PTY terminal.
-   [ ] Signals.
-   [ ] System information.
-   [ ] Services/tasks/log providers.
-   [ ] Cross-platform shell certification.

## P3 --- Make Desktop/Web application development complete

-   [ ] Finish UI runtime primitives.
-   [ ] Freeze styling/layout authoring.
-   [ ] File dialogs/clipboard/notifications/menus.
-   [ ] Full web component/state/forms/routing stack.
-   [ ] Backend/server runtime.
-   [ ] Database provider.
-   [ ] Packaging/publishing.
-   [ ] Windows/macOS/Linux/browser certification.

## P4 --- Build professional language ecosystem

-   [ ] Package manager.
-   [ ] FFI.
-   [ ] Test framework.
-   [ ] Debug runtime.
-   [ ] Profiler hooks.
-   [ ] Formatter/linter/language service.
-   [ ] Stable provider/plugin interfaces.

## P5 --- Games

-   [ ] Graphics/input/audio foundation.
-   [ ] 2D engine.
-   [ ] Physics/scenes/assets.
-   [ ] Web/Desktop game export.
-   [ ] Dogfood complete game.

## P6 --- 3D

-   [ ] Vector/matrix/quaternion math.
-   [ ] GPU rendering abstraction.
-   [ ] Mesh/material/shader pipeline.
-   [ ] Cameras/lights/animation/physics.
-   [ ] Scene graph.
-   [ ] 3D game demo.
-   [ ] Modeling mesh-edit operations.
-   [ ] Import/export.
-   [ ] Node/procedural system.
-   [ ] Dogfood 3D creation application.

## P7 --- General platform maturity

-   [ ] Mobile/future targets where desired.
-   [ ] Data/AI ecosystem.
-   [ ] Native interoperability ecosystem.
-   [ ] Package/provider ecosystem.
-   [ ] Security/performance/cross-platform audits.
-   [ ] Long-term compatibility and release policy.

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
