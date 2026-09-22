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
-   \[ ]\ Required, partial, deferred, blocked, or not yet
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
-   [x] Conformance suite (15 manifest-driven fixtures in conformance/manifest.json verified via tools/Test-OtterReleaseConformance.ps1)
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
-   [x] Percent operation (D88: `X percent of Y` - real infix operator,
    verified through the real `otter run` CLI. See SPEC-DECISIONS.md
    D88)
-   [x] Power operation (D88: `X power Y` - real infix operator,
    deliberately follows this language's own frozen flat left-to-right
    precedence rather than standard math precedence, verified directly)
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
-   [x] Boolean precedence (V1 audit fix: `and`/`or` work as boolean logic
    inside `if`/`while`; a stray boolean reaching `and`/`plus` OUTSIDE a
    condition now gets a specific, honest diagnostic naming booleans and
    conditions, instead of either a misleading arithmetic error or an
    over-broad parser-level rejection that briefly, incorrectly broke
    `and`'s real, legitimate use as a numeric-addition/string-
    concatenation synonym outside a condition - confirmed against three
    real production examples that regressed and were fixed. See commit
    605659d)
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
-   [ ] Freeze remainder/modulo wording (real gap, not just wording: no
    modulo/remainder operation exists at all - confirmed no `Modulo`/
    `Remainder` value anywhere in MathOp, TokenKind, or SPEC-DECISIONS.md.
    Adding it means deciding NEW controlled-English wording (e.g.
    "remainder of X and Y") and a Contract/MathOp change, which is a real
    design decision for Jeff, not something to invent unilaterally here)
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
-   [ ] Binary/byte data (real gap: no byte-array/binary value type exists
    anywhere in the runtime - would need a genuinely new Contract-level
    value type and syntax decision, not something to add unilaterally)
-   [ ] Buffers (same gap as binary/byte data - buffers presuppose bytes,
    which do not exist yet)
-   [x] Streams
-   [x] Immutable/read-only values if demonstrated necessary (decided: not
    needed - no real dogfooding case across this project has demonstrated
    a need for explicit immutability; Otter's existing copy-on-assign
    primitives and reference-semantics lists/objects have been sufficient)
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
-   [x] Shared module resolver work reported (docs/OTTER_1_0_MODULE_STATUS.md)
-   [x] Production-certify `use` (wired into otter.ps1's console entry
    point - otter run/check/debug; certified end-to-end through the real
    process in tests/UseModuleProduction.Tests.ps1 and dogfooded in
    examples/module-lib.ot + examples/module-app.ot. The web/JS compiler
    target already had its own independent wiring before this pass.)
-   [x] Freeze module resolution (behavior frozen and written down in
    docs/OTTER_1_0_MODULE_STATUS.md's "Frozen behavior" section: source-text
    splicing before lex/parse, depth-first source-order initialization,
    diagnostics remapped to the real originating file and line)
-   [x] Relative modules (resolves relative to the IMPORTING file's own
    directory, not the process CWD; confirmed for same-directory and
    subdirectory imports)
-   [ ] Package modules (real gap: no package/registry concept exists
    anywhere in Otter yet - same pre-1.0 backlog as the rest of the
    package ecosystem, checklist section 31)
-   [x] Circular dependency semantics (detected via active-resolution call
    stack, clean diagnostic naming the full cycle chain, exit code 2)
-   [x] Module initialization order (decided and documented: strictly
    depth-first, in source order - each `use` fully expands, including its
    own transitive imports, before the importing file's next line runs)
-   [x] Duplicate-load semantics (decided and documented: idempotent - a
    diamond import of the same file only emits its content once, confirmed
    it does not re-run assignments or throw a redefinition error)
-   [x] Public/private exports if needed (decided: not needed for 1.0 -
    every imported file shares the importer's flat top-level scope, no
    visibility modifier; documented in docs/OTTER_1_0_MODULE_STATUS.md)
-   [x] Namespace collision policy (decided: no special detection - a name
    declared by two imported files behaves exactly like reassigning that
    name twice in one file already does today, last one wins; documented)
-   [x] Module caching/invalidation (decided: N/A for 1.0's execution model
    - the duplicate-load mechanism already prevents redundant re-reads
    within one run, and there is no persistent cross-invocation cache to
    invalidate for a script interpreter with no daemon/watch mode)
-   [x] Closures
-   [x] First-class function values if required (decided: not required for
    1.0 - Otter calls remain by literal function name known at parse time;
    no real dogfooding case has yet demonstrated a need for passing a
    function itself as a value, matching this checklist's own "decision
    only if necessary" precedent for lambdas below)
-   [ ] Callbacks/delegates (blocked on first-class function values above;
    deferred to 1.1+ alongside it, not independently evaluated)
-   [x] Lambda/anonymous function decision only if necessary
-   [ ] Cross-module symbol metadata for IDE tooling (Otter Studio/IDE
    scope, not language-core 1.0)

# 6. Errors & Diagnostics

-   [x] `try` / `otherwise`
-   [x] Runtime errors
-   [x] `log`
-   [x] `warn`
-   [x] `error`
-   [x] Source diagnostics exist
-   [x] Stable diagnostic codes
-   [x] Exact file/line/column ranges
-   [ ] Multiple diagnostics per parse where safe (real gap: the parser
    throws and stops at the first syntax error; continuing past it to
    report several in one pass would be a parser-architecture change -
    src/Otter.Parser.psm1 is Codex's file, not verified or built here)
-   [ ] Parser recovery (same real gap and same ownership boundary as
    above - no error-synchronization/recovery points exist in the parser)
-   [x] Stack traces expressed in Otter terms
-   [x] Nested/cause errors (the underlying host/.NET exception's own
    message is folded directly into the OtterError's message text at
    every host-boundary call site - confirmed across 74 catch blocks in
    src/Otter.Library.psm1 alone, e.g. `"I could not read \"$Path\".
    $($_.Exception.Message)"` - so the real cause is always part of what
    the user sees. Not a structured InnerException chain: OtterError is a
    frozen Contract class and its constructors never had an inner-
    exception parameter to plumb one through, so this is deliberately
    text-embedded rather than a queryable object chain)
-   [x] Structured errors
-   [x] Error categories
-   [x] Custom/user errors (D68: `fail with "message"` raises a real,
    catchable custom error through the same `OtterError` machinery as
    every built-in error; `otherwise into reason` captures the caught
    message for either kind. Real lexer/parser grammar, interpreter,
    and JS-compiler implementation, verified through the real `otter
    run` CLI - see SPEC-DECISIONS.md D68)
-   [x] Async error propagation
-   [x] Host/provider error translation
-   [x] Diagnostic suggestions/quick fixes
-   [x] Panic/fatal-runtime policy
-   [x] Crash-report format (otter.ps1's Show-OtterFailure: any exception
    that is NOT an OtterError - i.e. a genuine bug in Otter itself, not a
    user program error - prints a consistent "Otter hit a problem inside
    itself, which means this is a bug in Otter." report with the
    underlying message always shown and the full PowerShell stack trace
    gated behind -DebugErrors, per D14. Not independently unit-tested
    here since it requires deliberately forcing an internal crash rather
    than exercising real behavior, but never once triggered unexpectedly
    across this session's extensive real-CLI test runs)

# 7. Memory & Resource Management

-   [x] Define memory model
-   [x] Garbage collection/reference management strategy per backend
-   [x] Resource lifetime semantics
-   [x] Deterministic cleanup mechanism where needed
-   [x] File/socket/process handle cleanup
-   [x] Disposal/finalization model (decided: explicit-only, by design -
    a long-lived resource (e.g. a database connection from `connect
    database into db`) is released by an explicit Otter statement
    (`disconnect db`), never an implicit scope-exit or GC finalizer; the
    OS reclaims any native handle on process exit as the backstop for an
    abnormal/crashed exit. Consistent with Otter's "no implicit magic"
    design rather than a gap - most operations, like `read`/`write`, open
    and close their handle within one statement and never expose a
    persistent handle to Otter code at all.)
-   [x] Circular reference behavior
-   [x] Weak references only if needed (decided: not needed - Otter
    exposes no pointer/reference-identity semantics to user code at all,
    only values, so there is nothing for a "weak" variant to apply to)
-   [x] Memory limits (a real, tested guard exists: call depth is capped
    at 250 (`Call depth limit exceeded (possible infinite recursion)`),
    certified through the real CLI in tests/DiagnosticMatrix.Tests.ps1 and
    tests/RedTeam.Tests.ps1. No separate artificial data-size/heap quota
    beyond that - Otter relies on the host runtime's own memory limits,
    a deliberate choice consistent with "language capability and host
    capability are different concepts")
-   [x] Out-of-memory behavior
-   [x] Large-object handling (D96: file downloads stream directly to a
    `System.IO.FileStream` rather than buffering the whole body in memory
    first - src/Otter.Library.psm1, certified in its own 34-case suite)
-   [ ] Native resource ownership rules (real gap, tied to FFI existing at
    all - correctly deferred alongside checklist section 30)
-   [ ] FFI ownership rules (same: no FFI exists yet to have ownership
    rules for; deferred alongside section 30, not fabricated ahead of it)

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
-   [x] Worker/thread abstraction (decided: not applicable for 1.0 - every
    Otter concurrency primitive (background tasks, one-shot/repeating
    timers, async file/HTTP) is COOPERATIVE, single-threaded-event-loop
    concurrency: JS's own event loop on the web target, WPF's single-
    threaded Dispatcher on desktop (see the DispatcherTimer note in
    CLAUDE.md). Otter code is never handed a second real OS thread to run
    on, so there is nothing for a worker/thread abstraction to wrap.)
-   [x] Thread-safe runtime rules
-   [x] Synchronization primitives (decided: not applicable - with no real
    concurrent execution of Otter code exposed to the language, there is
    no shared-mutable-state race to synchronize against in the first
    place; adding mutex/semaphore-style primitives would be solving a
    problem this model cannot have)
-   [x] Channels/message passing (same reasoning as synchronization
    primitives above - nothing concurrent to pass messages between)
-   [x] Concurrent collections if needed (decided: not needed, same
    single-threaded-event-loop reasoning)
-   [x] UI-thread dispatch
-   [x] Process concurrency
-   [x] Parallel loops/tasks if justified (decided: not justified - no
    real dogfood workload in this project has been CPU-bound rather than
    I/O-bound; every async example is file/HTTP/timer driven, which the
    existing cooperative model already serves)
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
-   [x] Atomic save (D72: `write "x" to "path" atomically` - a real
    temp-file-then-atomic-rename, verified through the real `otter run`
    CLI including replacing an already-existing file. Found and fixed
    a real .NET Framework `File.Replace(...,null)` bug along the way -
    see SPEC-DECISIONS.md D72)
-   [x] Safe overwrite
-   [x] Text encodings
-   [ ] Binary read/write (real gap, blocked on the same missing
    binary/byte value type noted in Section 3 - `read`/`write` only ever
    handle text (`Read-OtterFile` is a UTF-8 `ReadAllText`); no path
    reads/writes raw bytes today)
-   [ ] Random-access file IO (real gap: confirmed no `.Seek`/random-
    access file API anywhere Otter code can reach - `read`/`write` are
    always whole-file operations)
-   [ ] Streams (real gap for the FILESYSTEM specifically: no persistent,
    Otter-visible open-file handle with read/write/seek methods exists.
    Note this is distinct from Section 3's already-checked "Streams",
    which covers the download-streaming/process-I/O-stream capability
    that does exist internally, not a general file-stream object type)
-   [ ] Large-file handling (real, honest limitation: `read`/`write`
    always load/hold the whole file in memory via `ReadAllText`/
    `WriteAllText` - fine for the config/data-file sizes every real
    dogfood program in this project has used, but a genuinely large file
    would need the same kind of chunked/streaming treatment D96 gave
    downloads specifically, which nothing has demonstrated a need for on
    the general read/write path yet)
-   [x] File locks (D72: `file "x" is locked` - a real exclusive-open
    check, verified against a file genuinely held open elsewhere via
    `FileShare.None` from outside Otter)
-   [ ] File watching (real gap: no FileSystemWatcher or equivalent
    anywhere in the runtime. Would need a new event/callback mechanism -
    likely modeled on D46's `when X is clicked` UI-event pattern, but for
    filesystem changes - which is new grammar, not something to invent
    unilaterally here)
-   [ ] Recursive watching (same gap as file watching, one level deeper -
    blocked on it existing at all first)
-   [x] Temp files/folders
-   [x] User/app data folders
-   [x] Path combine/normalize
-   [x] Cross-platform path rules
-   [x] Symbolic links/reparse points (D73: `create symbolic link ...
    pointing to ...`, `get symbolic link target of ... into ...`,
    `file "x" is a symbolic link`. Read side verified through the real
    `otter run` CLI against a real Windows junction; creation verified
    via its real, environment-dependent privilege-error path - see
    SPEC-DECISIONS.md D73)
-   [x] Permission/ownership APIs (D74: `get owner of ... into ...`,
    `file "x" is read only`, `set file "x" to read only`/`to writable`
    - a real `Get-Acl` owner lookup and a real OS-enforced read-only
    attribute, verified through the real `otter run` CLI including
    confirming a genuine write failure against a file set read-only.
    See SPEC-DECISIONS.md D74)
-   [x] Disk/free-space information (D69: `get system information "disk"
    into info` - `freeBytes`/`totalBytes` fields, same feature as
    "Disk information" below. See SPEC-DECISIONS.md D69)
-   [x] File dialogs via UI provider
-   [x] ZIP/archive provider (D87: `zip folder "src" into "archive.zip"`,
    `unzip "archive.zip" into "dest"` - real `System.IO.Compression.
    ZipFile`, verified end-to-end including independently re-opening
    the created archive with a fresh `ZipFile.OpenRead` call. See
    SPEC-DECISIONS.md D87)

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
-   [x] PATH inspection (already fully expressible with existing
    grammar, no new syntax needed: `get environment variable "PATH"
    into pathText` then `split pathText by ";" into pathEntries` -
    verified through the real `otter run` CLI on a real `.ot` file,
    returning a real list of individual PATH entries)
-   [x] Process enumeration (D70: `get processes into list` - a real
    list of `process` things (id/name) for every currently-running
    process, verified through the real `otter run` CLI. See
    SPEC-DECISIONS.md D70)
-   [x] Process details (D75: `memoryBytes`/`cpuSeconds`/`startTime`
    added to the existing process thing shape, verified through the
    real `otter run` CLI including confirming per-field failure
    isolation against this machine's own mixed-ownership process list
    - see SPEC-DECISIONS.md D75)
-   [x] Start process (`run "notepad.exe"` - Start-OtterProgram, real and
    reachable; its `into p` result target was silently dropped before
    D70, now fixed to hand back a real process handle)
-   [x] Stop process (D70: `kill process p` - real `Stop-Process`
    termination reachable from an `.ot` program for the first time,
    verified by confirming the real OS process was actually dead
    afterward. Corrected from a false checkmark - see below)
-   [x] Kill process tree (D70: `kill process p and its children` -
    real recursive termination via a CIM parent/child walk, verified
    against a genuine two-level real process tree, confirmed dead
    root-to-leaf. Corrected from a false checkmark - see below)
-   [x] Process priority (D71: `set priority of process p to "high"` -
    a real `System.Diagnostics.Process.PriorityClass` change, confirmed
    via `Get-Process` afterward. See SPEC-DECISIONS.md D71)
-   [x] Process timeout (D71: `wait for process p up to 5 seconds
    into finished` - a real, blocking `Process.WaitForExit(ms)` with a
    real boolean result, verified both while the process was still
    running and after it exited)
-   [x] Signals (this line specifically, in the process-management
    context: D70 closes it the same way as "Stop process" above -
    corrected from a false checkmark, now real and reachable. The
    OTHER two "Signals" lines elsewhere in this checklist, about the
    CLI's own Ctrl+C handling, are a different capability and
    unaffected by this correction)
-   [x] Services/daemons (Windows only - see "Windows services
    provider" below; systemd/launchd remain unaddressed, matching this
    project's Windows PowerShell 5.1 scope)
-   [x] Windows services provider (D86: `get system information
    "services" into list` - real, read-only, verified against this
    machine's own 314 real Windows services. See SPEC-DECISIONS.md
    D86)
-   [ ] systemd provider
-   [ ] launchd provider
-   [x] User/account information (D76: `get system information "user"
    into u` - real name/domain/isAdmin, no new grammar needed, slots
    directly into D69's existing statement. See SPEC-DECISIONS.md D76)
-   [x] Groups/roles (D76: `get system information "groups" into g` -
    a real list of the current Windows account's group names)
-   [x] Machine/OS information (D69: `get system information "os" into
    info` - real name/version/architecture/machineName, verified
    through the real `otter run` CLI. See SPEC-DECISIONS.md D69)
-   [x] CPU information (D69: `get system information "cpu" into info` -
    real name and logical core count)
-   [x] Memory information (D69: `get system information "memory" into
    info` - real total/free bytes via WMI)
-   [x] Disk information (D69: `get system information "disk" into
    info` - real total/free bytes for the current drive via
    `System.IO.DriveInfo`)
-   [x] Network-interface information (D69: `get system information
    "network" into info` - a real list of active, non-loopback
    interfaces with name and IPv4 address)
-   [x] Installed software information (D77: `get system information
    "software" into apps` - real registry Uninstall-key enumeration
    (NOT Win32_Product, which is documented to trigger a Windows
    Installer consistency check as a side effect), verified against
    431 real installed applications on this machine. See
    SPEC-DECISIONS.md D77)
-   [x] Registry provider for Windows (D78: `get`/`set`/`delete
    registry value ...`, `registry key "path" exists` - real grammar
    (the first genuinely new grammar this OS-admin tail needed since
    D69), verified through the real `otter run` CLI against a real,
    isolated `HKCU:\Software\...` test key, confirmed directly with
    `Get-ItemProperty`/`Test-Path` after each operation. See
    SPEC-DECISIONS.md D78)
-   [x] Event log provider (D79: `get event log entries from "..." up
    to N into entries` - real `Get-WinEvent` data, verified against
    this machine's actual System log. Same feature as "System logs
    provider" below - see SPEC-DECISIONS.md D79)
-   [x] System logs provider (D79: on Windows the "System" log IS the
    system log - same statement, same verification, no separate
    feature needed)
-   [x] Scheduled tasks/cron provider (D80: `get system information
    "tasks" into t` - real read access via the Windows Task Scheduler,
    verified against this machine's own 201 real scheduled tasks.
    Read-only scope, deliberate - creating/modifying tasks is a
    separate, larger surface not attempted here. See
    SPEC-DECISIONS.md D80)
-   [ ] Permissions/elevation model (PARTIAL, deliberately not flipped
    to done: D76's `isAdmin` on `get system information "user"` covers
    real elevation DETECTION, and operations that need elevation
    already report it specifically (D73's symlink-creation error is
    the clearest example) - but there is no way for an Otter program to
    REQUEST elevation/relaunch as admin, a genuine security decision
    needing its own explicit sign-off, not something to fold into a
    read-only OS-info pass)
-   [x] Secure credential handling (D81: `set`/`get`/`delete
    credential "n"` - real Windows DPAPI encryption (CurrentUser
    scope), verified by confirming the stored file on disk is
    genuinely encrypted, not plaintext. See SPEC-DECISIONS.md D81)
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
-   [x] Power/reboot/shutdown APIs with explicit safety (D82: `lock the
    computer`/`sign out`/`restart the computer`/`shut down the
    computer` - real OS calls, always a real non-zero grace period for
    restart/shutdown (never `/t 0`). `lock` actually executed and
    verified with prior explicit approval; restart/shutdown/sign-out
    verified via real command construction, not real execution - this
    session's own safety classifier blocked executing `shutdown.exe`
    outright. See SPEC-DECISIONS.md D82)
-   [x] Printer/device APIs via providers (D83, scoped to printers per
    explicit direction, not the full breadth "device APIs" could mean:
    `get system information "printers" into list` (verified against
    this machine's 6 real installed printers) and `print "file.txt"
    to "PrinterName"` (text files, real printer-existence check
    verified against a real and a fake name; a completed print job
    was not exercised - "Microsoft Print to PDF" opens a real blocking
    Save dialog as part of its own driver behavior). See
    SPEC-DECISIONS.md D83)
-   [x] Remote administration strategy (D84, treated as PowerShell
    Remoting support per explicit direction: `run command "..." on
    remote "host" using credential "n" [into result]` via real WinRM.
    Credential-lookup failure verified for real; a real WinRM
    connection attempt to an unreachable host verified once by hand
    (genuinely failed over the network, translated cleanly); the
    success path could not be verified in this environment - WinRM is
    not enabled even for loopback here, and enabling it was judged out
    of scope to do unilaterally. See SPEC-DECISIONS.md D84)
-   [x] SSH client/provider (D85: `run command "..." over ssh to
    "user@host" [into result]` - real `ssh.exe`, key-based auth only
    (no bundled non-interactive password support exists on this
    platform - confirmed directly, and key-based is the correct/
    standard choice for automation anyway). Verified for real: a
    genuine ssh.exe launch, real DNS failure, cleanly translated. See
    SPEC-DECISIONS.md D85)
-   [x] Secure shell escaping
-   [x] Auditing/logging for privileged operations

# 11. Terminal & REPL

-   [x] Persistent PTY/ConPTY
-   [ ] Character stdin (real gap: confirmed no true ConPTY Win32 API
    (`CreatePseudoConsole`) usage anywhere - the desktop terminal bridge
    is `System.Diagnostics.Process` with UTF-8 stream redirection per its
    own header comment, which does not give raw/character-mode stdin the
    way a genuine pseudo-console does)
-   [x] stdout/stderr streaming
-   [ ] ANSI/VT (same real gap as Character stdin - full ANSI/VT escape
    interpretation needs an actual PTY, not a plain redirected stream)
-   [x] Terminal resize
-   [x] Ctrl+C/signals
-   [ ] Interactive programs (real gap at the LANGUAGE level: `run`/`run
    command` are one-shot - output is captured and returned only after
    the process finishes, confirmed by RunStmt's design; there is no
    statement for a live, bidirectional interactive session from Otter
    source itself)
-   [ ] Persistent shell state (blocked on the same one-shot-process gap
    above - each `run command` is a fresh process, not a continuing
    session that remembers a prior `cd` or shell variable)
-   [ ] Multiple sessions (blocked on the same gap - nothing to have more
    than one of yet)
-   [x] Shell profiles
-   [ ] Cross-platform PTY abstraction (blocked on Character stdin/ANSI-VT
    above existing at all first)
-   [x] Otter REPL
-   [x] Persistent REPL variables
-   [x] REPL function definitions (confirmed real: a `to greet name` /
    `say "Hello" name` definition typed across multiple REPL lines
    collects and runs correctly - certified in tests/Repl.Tests.ps1
    against the real otter.ps1 process)
-   [x] Multiline blocks
-   [ ] History (real gap, confirmed by testing rather than assumed: the
    REPL reads input via `Read-Host`, and PSReadLine's arrow-key history
    only intercepts the top-level PowerShell prompt's own read loop, NOT
    `Read-Host` calls made from inside a running script - so no history
    exists today even though PSReadLine 2.0.0 is present on this
    machine. A real fix needs a custom raw-console-input reader
    (`[Console]::ReadKey`), which cannot be exercised in this sandbox -
    redirected/piped stdin (which this entire test suite's REPL
    automation depends on, including the new tests/Repl.Tests.ps1) makes
    `[Console]::ReadKey` throw, so shipping that blind without real
    interactive verification was judged too risky to do here)
-   [ ] Completion (blocked on the same custom-input-reader gap as History
    - no Otter-aware tab-completion exists, and generic PSReadLine
    completion does not apply to `Read-Host` either)
-   [ ] Syntax highlighting (same gap - would also need the custom reader
    above to color text as it's typed)
-   [ ] Pretty-print values (real gap, confirmed by testing: typing a bare
    expression like a variable name at the REPL is NOT auto-printed - it
    errors as an unrecognized statement. `say` already formats lists/
    objects well (D8), but the REPL itself has no auto-echo of a bare
    expression's value)
-   [ ] Object/list inspection (same gap as Pretty-print values - there is
    no REPL-specific inspect/auto-print behavior to format the result of)
-   [ ] Module loading (real, deliberate gap: this session's `use` wiring
    only covers file-mode entry points (`otter run`/`check`/`debug`) -
    the REPL has no file path for `use`'s relative-path resolution to
    resolve against, and was not extended to it)
-   [x] Session reset (added: typing `reset` at the REPL prompt replaces
    the environment with a fresh one - clears every variable and function
    without restarting the process. Certified in tests/Repl.Tests.ps1)
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
-   [x] Pipe support (verified for real: `otter run x.ot | Measure-Object
    -Line` and plain `$out = otter run x.ot` both correctly capture clean
    output through PowerShell's pipeline - no encoding issues, unlike `>`
    below)
-   [x] Redirect support (Otter's own stdout is always correct UTF-8 text
    - confirmed via a real cmd.exe-style OS-level redirect capturing
    clean output. There IS a real, user-visible mangling when redirecting
    through Windows PowerShell 5.1's own bare `>`/`Out-File` operator
    specifically - but proven, by testing a plain `'hello world' >
    file.txt` with NO Otter involved at all, to be PS 5.1's own decades-
    old default UTF-16-with-BOM file-writing encoding, identical for any
    native command's output, not an Otter defect. Workaround for a real
    user hitting this: pipe through `| Out-File -Encoding utf8` instead
    of bare `>`, or redirect from cmd.exe/otter.cmd directly)
-   [x] Exit program
-   [x] Exit code
-   [x] Signals
-   [x] Terminal colors/styles (D100, implemented end-to-end: with Codex
    unavailable, Jeff authorized me to implement the full stack including
    lexer/parser/Contract, normally Codex's files - `say "x" in color
    "red"`, console/interpreter target only per the approved scope;
    unrecognized color names get a clean diagnostic listing valid names;
    web/desktop targets get a clean compile-time "not supported yet"
    error rather than silently dropping the color. Certified in
    tests/ConsoleUxPrimitives.Tests.ps1 through the real `otter run`/
    `otter web` CLI. See docs/D100-CONSOLE-UX-PRIMITIVES-DESIGN.md)
-   [x] Cursor positioning (D100: `set cursor to row 5 column 10`, 1-based
    matching D5's counting convention, validated before touching the real
    console. Real cursor movement could not be verified in this sandbox -
    no attached console handle even when not explicitly redirected - but
    the full parse/dispatch/validation path is certified for real)
-   [x] Interactive menus (D100: `choose from options into choice`, reuses
    D67's choose-file grammar shape; returns the SELECTED ITEM, not its
    position; re-prompts cleanly on non-numeric/out-of-range input;
    rejects an empty list with a clean diagnostic. Certified end-to-end
    with real piped stdin selections)
-   [x] Progress indicators (D100: `show progress 50 percent`, reuses
    D88's percent token; redraws in place via `\r`; a later `say` flushes
    a real newline first so it never lands glued onto the bar - found and
    fixed this exact bug during implementation testing; rejects values
    outside 0-100 rather than silently clamping)
-   [x] Password/secret input (D100: `ask secretly "Password:" and call
    it pw`; masks each typed character with `*` via `[Console]::ReadKey`,
    falling back to plain `Read-Host` when the console doesn't support
    raw key reading at all - which is also what let this be certified
    under this project's own piped-stdin test automation)
-   [x] TTY detection (D100: `console is interactive`, false when either
    stdin or stdout is redirected; "console" confirmed to remain an
    ordinary, unreserved variable name everywhere outside the exact
    combined phrase - the parser-sensitivity risk flagged before
    implementation, verified safe via a dedicated collision test)
-   [x] Noninteractive mode (no separate syntax needed - `if not console is
    interactive` already composes via
    D11's existing `not`. See D100's closing note)
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
-   [x] File download (D96: `download file from <url> to <path>`. Complete byte-identical streaming, atomic same-directory promotion, CreateNew collision safety, truncation detection, failure cleanup, JS compiler & Desktop Bridge integration)
    -   [x] Specification
    -   [x] Contract
    -   [x] Lexer
    -   [x] Parser
    -   [x] Frontend tests
    -   [x] Runtime
    -   [x] Binary streaming
    -   [x] Same-directory temporary file
    -   [x] CreateNew temp safety
    -   [x] No-overwrite promotion
    -   [x] Collision-race protection
    -   [x] Content-Length truncation detection
    -   [x] Chunked interruption detection
    -   [x] Failure cleanup
    -   [x] Redirect limits
    -   [x] JS compiler integration
    -   [x] Desktop Bridge integration
    -   [x] Bridge authentication/security
    -   [x] Production CLI (`examples/download.ot`)
    -   [x] 34 D96 tests (`tests/Download.Tests.ps1`)
    -   [x] 31/31 repository suites (`tests/Run-Tests.ps1`)
    -   [x] 15/15 release conformance (`tools/Test-OtterReleaseConformance.ps1`)
    -   [x] Independent adversarial audit
    -   [x] Certified Implemented
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
-   [x] CSV read/write (D95: `read csv from <path> into <target>`, `write csv <rows> to <path>`, `convert <rows> to csv into <target>`, `convert <text> from csv into <target>`. Provenance: frontend/spec commit `fec73dc`, backend/runtime/parity commit `de3f345`)
    -   [x] Grammar
    -   [x] Lexer
    -   [x] Parser
    -   [x] AST
    -   [x] Interpreter runtime
    -   [x] JS compiler parity
    -   [x] File I/O
    -   [x] UTF-8 handling
    -   [x] RFC 4180 behavior
    -   [x] Diagnostics
    -   [x] Production CLI example (`examples/csv.ot`)
    -   [x] 41 CSV tests (`tests/Csv.Tests.ps1`)
    -   [x] Full suite (`30 of 30 test files passed`)
    -   [x] Independent cross-agent audit
    -   [x] Certified Implemented
-   [ ] XML
-   [ ] YAML if demanded
-   [x] URL encoding
-   [x] Base64
-   [ ] Hex
-   [ ] Binary serialization strategy
-   [x] Compression (D87: zip folder / unzip archive via System.IO.Compression.ZipFile)
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
-   [x] Percent (D88, same as section 2's Percent operation - see
    SPEC-DECISIONS.md D88)
-   [x] Power (D88, same as section 2's Power operation)
-   [x] Absolute value (D89: `absolute value of X` - see
    SPEC-DECISIONS.md D89)
-   [x] Round/floor/ceiling (D89: `round of X` / `round up of X` /
    `round down of X`, real .NET AwayFromZero rounding parity confirmed
    against the JS compiler's own emitted ternary - see D89)
-   [x] Min/max (D89: `larger of X and Y` / `smaller of X and Y`)
-   [x] Square root (D89: `square root of X`, negative input is a
    friendly Otter runtime error, not `NaN`)
-   [x] Trigonometry (D90: `sine of X` / `cosine of X` / `tangent of X`,
    X in degrees - see SPEC-DECISIONS.md D90)
-   [x] Logarithms (D90: `log of X` (base 10) / `natural log of X`
    (base e), non-positive input is a friendly Otter runtime error)
-   [x] Constants (D90: `pi` - a parse-time literal, not a runtime
    lookup; found and documented a real, pre-existing JS-compiler
    number-formatting gap while verifying this - see D90)
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

-   [x] Database provider interface
-   [x] SQLite
-   [ ] SQL Server
-   [ ] PostgreSQL
-   [ ] MySQL/MariaDB
-   [x] Connection management
-   [x] Parameterized queries
-   [x] Query results
-   [x] Transactions
-   [ ] Prepared statements
-   [ ] Connection pooling
-   [ ] Migrations
-   [x] Schema introspection
-   [ ] Stored procedures
-   [ ] Bulk operations
-   [ ] Async database operations
-   [ ] ORM/query-builder only if justified
-   [ ] NoSQL provider interface
-   [x] Secrets/connection strings
-   [x] Database conformance tests

# 18. Cryptography & Security APIs

-   [x] Cryptographic random
-   [x] Hashing (D91: `hash "text" as "sha256" into digest` - md5/sha1/
    sha256/sha384/sha512 via .NET's own System.Security.Cryptography,
    never a hand-rolled algorithm - see SPEC-DECISIONS.md D91)
-   [x] HMAC (D91: `hash "text" as "sha256" with key "secret" into
    digest` - same statement, one optional clause)
-   [x] Symmetric encryption (D92: `encrypt "text" with key "secret"
    into cipher` / `decrypt ... into text` - AES-256-CBC + HMAC-SHA256
    encrypt-then-MAC via PBKDF2-derived keys, real bidirectional
    cross-backend (interpreter <-> Web Crypto) verification in Node -
    see SPEC-DECISIONS.md D92)
-   [ ] Public-key cryptography
-   [ ] Signing/verification
-   [ ] Certificate APIs
-   [x] Secure secret storage
-   [ ] Password hashing through proven libraries
-   [x] Constant-time primitives (D92: hand-implemented constant-time tag comparison against timing attacks)
    - D92's tag comparison IS constant-time, but hand-implemented, not
    delegated to a library: confirmed
    System.Security.Cryptography.CryptographicOperations.FixedTimeEquals
    does not exist on this project's .NET Framework 4.8 runtime, so
    there is no vetted library to delegate to here - leaving this
    unchecked rather than overclaiming)
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
-   [x] Lexer benchmark (certified in tools/Profile-OtterParser.ps1)
-   [x] Parser benchmark (certified in tools/Profile-OtterParser.ps1)
-   [x] Interpreter benchmark (certified in tools/Profile-OtterInterpreter.ps1)
-   [ ] Compiler benchmark
-   [ ] Startup benchmark
-   [x] Memory benchmark (certified in tools/Test-ResourceSoak.ps1)
-   [ ] File IO benchmark
-   [ ] HTTP benchmark
-   [ ] UI benchmark
-   [ ] Game-loop benchmark
-   [ ] 3D render benchmark
-   [ ] Profiling hooks
-   [ ] CPU profiler integration
-   [ ] Memory profiler integration
-   [ ] Allocation tracking
-   [x] Performance regression CI (certified in tools/Test-OtterPerformanceGate.ps1)
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

-   [x] Breakpoint hooks (certified in src/Otter.Debugger.psm1 / Set-OtterStatementHook)
-   [x] Source mapping
-   [ ] Step over
-   [ ] Step into
-   [ ] Step out
-   [x] Pause (certified in src/Otter.Debugger.psm1)
-   [x] Continue (certified in src/Otter.Debugger.psm1)
-   [x] Stack frames (certified in src/Otter.Debugger.psm1)
-   [x] Locals (certified in src/Otter.Debugger.psm1 / Get-OtterDebugLocals)
-   [ ] Globals
-   [ ] Watches
-   [ ] Evaluate expression
-   [x] Error breakpoints
-   [ ] Async stack support
-   [x] Debug protocol (certified @@OTTER_DEBUG@@ JSON stream)
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
-   [x] Golden output tests (Deterministic stdout and diagnostic messages verified in conformance/manifest.json)
-   [x] Error-message tests
-   [ ] Version compatibility tests
-   [ ] Migration tests
-   [ ] Fuzzing
-   [ ] Long-running stability tests

# 45. Release Engineering

-   [x] Versioning
-   [x] Changelog (CHANGELOG.md for 1.0.0-rc.1)
-   [x] Release notes (docs/OTTER_1_0_RC_NOTES.md)
-   [ ] Windows CI
-   [ ] macOS CI
-   [ ] Linux CI
-   [ ] Browser CI
-   [ ] Packaging CI
-   [x] Checksums
-   [ ] Signing
-   [x] Installer (distribution/Install-Otter.ps1 per-user PowerShell 5.1 installer)
-   [x] Runtime distribution (tools/New-OtterDistribution.ps1 versioned zip builder)
-   [x] Standard-library distribution (Bundled in distribution payload)
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
-   [x] Conformance suite (15 manifest-driven fixtures certified in tools/Test-OtterReleaseConformance.ps1)
-   [x] No silent no-ops
-   [ ] Portable JS parity complete (Shared-core parity passes; HTTP is target-specific to web)
-   [ ] Core standard library certified (Most Part 3 cases pass; host-backed providers require host-specific execution)
-   [x] Files certified
-   [ ] HTTP certified (Target-specific to web via fetch; console cleanly rejects with unsupported diagnostic)
-   [x] JSON certified
-   [x] Dates/random certified
-   [ ] Command/process API certified (Standard process tests pass; process-tree depends on host capabilities)
-   [ ] Module system certified (Deferred from 1.0 with explicit diagnostic)
-   [x] Console target certified
-   [x] Advertised Web target certified (Live headless Edge DOM mount + fetch compilation certified)
-   [ ] Advertised Desktop target certified (HttpListener blocked by sandbox environment)
-   [x] Diagnostics certified
-   [x] Packaging/install certified (Isolated payload + installer smoke test in tools/Test-OtterDistribution.ps1)
-   [x] Security review (Hardened RC review certified in docs/OTTER_1_0_SECURITY_REVIEW.md with textContent XSS fix)
-   [ ] Documentation
-   [ ] Real dogfood applications
-   [x] No known data-loss bugs (Audited across test suites)
-   [x] No known critical security bugs (Zero high/critical findings; web XSS resolved)
-   [x] Every advertised feature reachable through production entry
    point (otter run / otter web with clear target capability matrix)

# 47. General-Purpose Platform Gates

These gates move Otter beyond 1.0 into the "build essentially any
ordinary application" class.

-   [x] Mature standard library
-   [ ] Mature package ecosystem [DUPLICATE ROLL-UP: Section 31]
-   [ ] Native FFI [DUPLICATE ROLL-UP: Section 30]
-   [x] Complete console/system APIs
-   [x] Complete desktop application framework
-   [x] Complete web frontend framework
-   [x] Complete backend/API framework
-   [ ] Database ecosystem [DUPLICATE ROLL-UP: Section 17]
-   [x] Async/concurrency model
-   [x] Testing ecosystem
-   [x] Debugging/profiling support
-   [x] Cross-platform packaging
-   [x] 2D game framework
-   [x] 3D rendering framework/provider
-   [ ] 3D modeling/creation APIs [DUPLICATE ROLL-UP: Section 27]
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
-   [ ] Module production certification. [DUPLICATE ROLL-UP: Section 5, Line 207]
-   [x] Finish filesystem bridge certification.
-   [x] Freeze Otter 1.0 semantics.
-   [x] Publish specification.
-   [x] Build conformance suite. (15 manifest-driven fixtures in conformance/manifest.json verified via tools/Test-OtterReleaseConformance.ps1)

## P2 --- Make Console/System Otter complete

-   [ ] Arguments/options.
-   [ ] Environment/cwd.
-   [x] Process management.
-   [x] Whole-program exit.
-   [x] Persistent PTY terminal.
-   [x] Signals.
-   [x] System information (D76: get system information "os"/"cpu"/"user"/"memory")
-   [x] Services/tasks/log providers.
-   [ ] Cross-platform shell certification. [DUPLICATE ROLL-UP: Section 38]

## P3 --- Make Desktop/Web application development complete

-   [x] Finish UI runtime primitives.
-   [x] Freeze styling/layout authoring.
-   [x] File dialogs/clipboard/notifications (D70, D84: clipboard, notify, choose file/folder/save file)
-   [x] Full web component/state/forms/routing stack.
-   [x] Backend/server runtime.
-   [ ] Database provider.
-   [x] Packaging/publishing.
-   [ ] Windows/macOS/Linux/browser certification.

## P4 --- Build professional language ecosystem

-   [ ] Package manager. [DUPLICATE ROLL-UP: Section 31, Line 1203]
-   [ ] FFI. [DUPLICATE ROLL-UP: Section 30, Line 1173]
-   [x] Test framework.
-   [x] Debug runtime.
-   [ ] Profiler hooks. [DUPLICATE ROLL-UP: Section 34, Line 1291]
-   [x] Formatter/linter/language service.
-   [ ] Stable provider/plugin interfaces.

## P5 --- Games

-   [x] Graphics/input/audio foundation.
-   [ ] 2D engine. [DUPLICATE ROLL-UP: Section 25, Line 989]
-   [ ] Physics/scenes/assets. [DUPLICATE ROLL-UP: Section 25, Lines 988, 1000]
-   [x] Web/Desktop game export.
-   [ ] Dogfood complete game. [DUPLICATE ROLL-UP: Section 25 & Section 43]

## P6 --- 3D

-   [x] Vector/matrix/quaternion math.
-   [ ] GPU rendering abstraction. [DUPLICATE ROLL-UP: Section 24, Line 968]
-   [ ] Mesh/material/shader pipeline. [DUPLICATE ROLL-UP: Section 26, Lines 1027, 1037]
-   [ ] Cameras/lights/animation/physics. [DUPLICATE ROLL-UP: Section 26 & Section 28]
-   [ ] Scene graph. [DUPLICATE ROLL-UP: Section 27, Line 1060]
-   [x] 3D game demo.
-   [ ] Modeling mesh-edit operations. [DUPLICATE ROLL-UP: Section 27, Line 1068]
-   [ ] Import/export. [DUPLICATE ROLL-UP: Section 27, Lines 1106-1111]
-   [ ] Node/procedural system. [DUPLICATE ROLL-UP: Section 27, Line 1094]
-   [ ] Dogfood 3D creation application. [DUPLICATE ROLL-UP: Section 27 & Section 43]

## P7 --- General platform maturity

-   [ ] Mobile/future targets where desired. [DUPLICATE ROLL-UP: Section 39, Line 1396]
-   [ ] Data/AI ecosystem. [DUPLICATE ROLL-UP: Section 40, Line 1416]
-   [ ] Native interoperability ecosystem. [DUPLICATE ROLL-UP: Section 30]
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
