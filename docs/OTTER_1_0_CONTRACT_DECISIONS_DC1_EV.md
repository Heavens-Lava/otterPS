# Otter 1.0 — Contract Analysis: DC1 and EV1–EV7

**Status: analysis only. Every decision below is UNRESOLVED.** No runtime,
compiler, test or manifest behavior was changed to produce this document.
Baseline: `origin/master` `80867ee` (certified executable baseline `f170a5f`).
Companion evidence: `docs/OTTER_1_0_EVENT_LOOP_REVIEW.md`,
`docs/OTTER_1_0_FREEZE_FOLLOWUPS.md`, `release/otter-1.0-surface.json`.

---

## DC1 — Is the HTTP client part of the console (interpreter) surface?

### Evidence

| Item | Finding |
|---|---|
| Frozen decision ledger | `SPEC-DECISIONS.md` **D116A** (2026-09-24): "Otter 1.0 provides full cross-target parity for synchronous HTTP requests across console/.NET and web (browser) targets." **D116B**: asynchronous request handles (`start get ... and call it`, `cancel`, `on complete/error/cancel`, state predicates) for Otter 1.0. |
| Implementation | Interpreter handles `HttpGet/Post/Put/Delete`, `HttpStart`, `HttpCancel`, `HttpRequestIsState` and `DownloadFile` through `Invoke-OtterHttpRequest` (`src/Otter.Library.psm1`, pooled `HttpClientHandler`, cookies, redirects, timeout, JSON/bytes bodies). The JavaScript compiler emits `fetch` for the same nodes, including `HttpStart`/`HttpCancel`. |
| Production reachability | Yes. `tests/Http.Tests.ps1` runs programs both in-process and through `otter.ps1 run` (`Run-OtterCli`); conformance fixture `http-invalid-url-negative` runs `get "not-a-valid-url"` through `otter run` and targets `console` and `portable-core`. |
| Tests | `tests/Http.Tests.ps1`: 33 cases (D116A 14, D116B 19) against a deterministic local HTTP server: all verbs, JSON/bytes, headers, cookies, redirects, timeouts, status codes, malformed JSON, invalid URL, cancellation, retained terminal events, 20-request concurrency, a 500-request soak. Passes on Windows PowerShell 5.1. |
| Host support | Exercised only on Windows PowerShell 5.1. `Http.Tests.ps1` is **not** in the D120 portable suite and its CLI helper hard-codes `powershell.exe`, so console HTTP is **unverified** on PowerShell 7 (Windows/Linux/macOS). The code uses `System.Net.Http.HttpClient`, which exists on all of them. |
| Documentation claiming the opposite | `docs/STANDARD_LIBRARY.md` ("Web target via browser fetch; not the headless console interpreter"), `docs/OTTER_1_0_CAPABILITY_MATRIX.md` (Console: No), `docs/OTTER_1_0_RELEASE_SCOPE_MATRIX.md` ("Not supported on headless Console runtime"), `docs/OTTER_1_0_HTTP_TARGET_PARITY.md` ("The interpreter has no statement cases for any HTTP node"). The conformance fixture name `http-web-target-only` repeats the old classification. |
| Chronology | The four "console: no" documents were written on **2026-09-17**. Console HTTP (D116A/B) and its tests landed on **2026-09-24**. `STANDARD_LIBRARY.md` was last edited on 2026-09-26 during the freeze and carried the older claim forward. |

### Contradictions

The implementation, the tests and the **frozen decision ledger (D116A/B)** agree
that console HTTP is part of Otter 1.0. Four documents written a week earlier,
plus one fixture name, say it is not. The freeze report's statement that
"`docs/STANDARD_LIBRARY.md` and the scope matrix agree" is true of those two
documents but both disagree with D116A.

### Options

| | A. Certify console HTTP for 1.0 | B. Declare console HTTP unsupported/deferred |
|---|---|---|
| Consistent with the ledger | Yes (D116A/B) | **No: requires reversing a recorded decision** |
| Code change | None | Make the interpreter reject HTTP nodes with a target diagnostic |
| Programs broken | None | Every console program using `get`/`post`/`put`/`delete`/`start get`/`download` |
| Remaining work | Update 4 documents and the fixture name; add `Http.Tests.ps1` (made host-portable) to the four-host suite; record host evidence | Remove/disable 33 tests, rewrite D116, change the dogfood evidence |

### Recommendation

**A.** The documents are stale; the recorded decision, implementation and tests
agree. Minimal 1.0 contract: *the HTTP client (D116A synchronous statements and
D116B request handles) is supported on the console and web targets with the
semantics of D116A/B; host evidence is required on all four D120 hosts before
certification.* Only documentation and test-coverage work is needed, unless the
four-host run finds a portability defect.

**Decision: UNRESOLVED.**

---

## EV1–EV7 — Event semantics

### Context that applies to every question

* **No recorded contract exists for any of this.** The decisions that introduced
  every console event source are missing from `SPEC-DECISIONS.md`: D101 (`wait`,
  timers), D104 (file watching), D106 (WebSockets), D107 (TCP), D108 (UDP) and
  D119 (command jobs) have no ledger entry (see "Additional contradictions").
  The only ledger text about scheduling is D116B's "handler executes ...
  upon registration or next event loop tick". Current behavior is therefore
  implementation behavior, not a documented promise.
* **Console model today:** the main program runs to completion first; then the
  event loop dispatches handlers until nothing with a handler is active. During
  `wait`, only HTTP and command-job events are dispatched.
* **Web model today:** handlers are browser event listeners and run whenever the
  browser delivers an event, including while the (async) main program is still
  running. `wait` is rejected on the web target ("not supported on the web
  target yet"). File watching, TCP and UDP are console/desktop only.
* The differential fuzzer (interpreter vs JavaScript) does not generate event
  programs, so no cross-runtime event behavior is checked automatically.

### EV1. Is cross-source fairness guaranteed or best-effort?

| | |
|---|---|
| Current behavior | Each pass visits sources in a fixed order (watcher, WebSocket, TCP/UDP, HTTP, jobs). Sockets, WebSockets and watchers handle at most one event per pass; HTTP handles every completed request; jobs drain their whole queue. Under load, jobs win (EV2). |
| Documented | Nothing. |
| Tests | None assert cross-source fairness. |
| Hosts/runtimes | Same on all four PowerShell hosts (single-threaded interpreter). Web: the browser's own event-loop policy. |
| Accidental or relied upon | Accidental. No test or program depends on the pass order. |
| Option A | **Best-effort, with a progress guarantee:** no source may prevent another ready source from being serviced indefinitely; the order in which ready sources are serviced is unspecified. |
| Option B | **Guaranteed fairness:** a defined policy (for example round-robin, at most N events per source per turn). |
| Compatibility | A: no change for programs. B: none today, but fixes a policy future runtimes must reproduce exactly. |
| Implementation | A requires fixing EV2 (jobs currently can starve others). B requires a defined scheduler and tests for it. |
| Recommended minimal 1.0 contract | **A.** |
| Decision | **UNRESOLVED** |

### EV2. May one event source drain an unbounded queue before others run?

| | |
|---|---|
| Current behavior | Yes, for command jobs only: `Invoke-OtterJobEventLoopStep` loops `while TryDequeue`. Measured: a job printing 4,000 lines delayed a UDP handler until all 4,000 lines and the job's exit handler had run (about 1.5 s). |
| Documented | Nothing (D119 is not in the ledger). |
| Tests | `tests/AsyncCommand.Tests.ps1` asserts per-job output order and that exit fires after output; nothing asserts draining or cross-source timing. |
| Hosts/runtimes | All four PowerShell hosts. Web: not applicable (no command jobs in a browser). |
| Accidental or relied upon | Accidental. Within-source order (which draining preserves) is relied upon; the unboundedness is not. |
| Option A | **No:** a source may process a bounded number of events before other ready sources are serviced (implementation detail of the bound left to the runtime). |
| Option B | **Yes, as today:** a source may drain its queue; document that heavy job output delays other handlers. |
| Compatibility | A: output and exit still arrive in order and `on exit` still fires after all output, so no program observes a difference except shorter delays for other sources. B: none. |
| Implementation | A: bound the job loop (one small change in one function) plus a test. B: documentation only. |
| Relationship to EV1 | EV1 Option A is not true while EV2 is B. Choosing EV1-A implies EV2-A. |
| Recommended minimal 1.0 contract | **A** (it is what makes EV1-A true). |
| Decision | **UNRESOLVED** |

### EV3. Which event sources are dispatched during `wait`?

| | |
|---|---|
| Current behavior | HTTP and command jobs only. Socket, WebSocket, TCP-server and watcher events are held until the main program ends. **Demonstrated:** a program that connected to a local TCP listener (accepted immediately at the OS level) and polled `if conn is connected` / `wait 100 milliseconds` for 3 seconds never saw `connected`; its `on connect` handler ran only after the main program finished. |
| Documented | Nothing for dispatch. `rules3.md` section 59 says `wait` "should not be confused with concurrent execution semantics". |
| Tests | `tests/Http.Tests.ps1` #28 (request completes during `wait`, handler registered afterwards fires once via retained event); `tests/AsyncCommand.Tests.ps1` #6/#7 (`wait` then `cancel`); `tests/FileWatching.Tests.ps1` (`wait 3 seconds` with a handler-less watcher). None asserts that sockets or watchers are *not* dispatched. |
| Hosts/runtimes | All four PowerShell hosts. Web: `wait` is a compile error, so there is no web behavior to match. |
| Accidental or relied upon | **Partly relied upon.** `OtterWorkspace/tests/task_runner_test.ot` (the D119 dogfood) polls a job's status in a loop with `wait 50 milliseconds`; job state only changes when the loop services jobs, so that program depends on `wait` servicing jobs. The same polling pattern over a TCP or WebSocket state **never terminates** today (demonstrated above). The HTTP/jobs-only set is an artifact of which providers were wired into `wait`, not a design choice (no record exists). |
| Option A | **`wait` services every active event source** (handlers may run during a `wait`, in the same way they run in the event loop). |
| Option B | **`wait` services no event source:** it only pauses; handlers run after the main program. |
| Option C | **Keep today's set** (HTTP and jobs only) and document it. |
| Compatibility | A: programs that `wait` while sockets/watchers are active will see handlers run earlier (during the wait instead of after the program); any program that relied on socket handlers *not* running during a wait would change. No test or dogfood program was found that relies on that. B: **breaks** the D119 dogfood polling pattern and the HTTP-during-wait behavior D116B tests use. C: no change; leaves polling over sockets/watchers hanging forever, which is a trap for users. |
| Implementation | A: call the same socket/WebSocket/watcher steps from the `wait` loop that the event loop calls (small, local). B: remove steps (breaking). C: documentation only. |
| Semantic meaning of `wait` | Under A, `wait` means "pause the main program and let pending events be handled"; under B, "pause, nothing else happens"; under C, it has no consistent meaning. |
| Recommended minimal 1.0 contract | **A.** It is the only option that gives `wait` one consistent meaning, keeps every existing test and the dogfood program working, and removes the hang. |
| Decision | **UNRESOLVED** |

### EV4. Is event ordering guaranteed only within a source?

| | |
|---|---|
| Current behavior | FIFO within a source (UDP datagrams, TCP reads, WebSocket messages, watcher events, job output, then exit). Across sources, the fixed pass order decides, not arrival time. |
| Documented | D116B: exactly one terminal event per request. Nothing on ordering across sources. |
| Tests | Within-source order is asserted: `AsyncCommand.Tests.ps1` (output lines in order, exit after output), `WebSocket.Tests.ps1` and `Network.Tests.ps1` (message and data sequences), `FileWatching.Tests.ps1` (create, delete, rename sequence). Nothing asserts cross-source order. |
| Hosts/runtimes | All four PowerShell hosts. Web: per-source order follows the browser, which is also FIFO per event target. |
| Accidental or relied upon | Within-source order is relied upon (tested). Cross-source order is accidental. |
| Option A | **Guaranteed within a source (FIFO); unspecified across sources.** |
| Option B | Guaranteed global arrival order. |
| Compatibility | A: none. B: not achievable on the web target and would need timestamps and a merged queue on the console. |
| Implementation | A: documentation only. B: significant. |
| Recommended minimal 1.0 contract | **A.** |
| Decision | **UNRESOLVED** |

### EV5. May TCP/UDP receive callbacks be delayed by polling cadence?

| | |
|---|---|
| Current behavior | Yes. Two loop passes per UDP datagram or TCP read (arm, then consume) and a 10 ms sleep that lasts about 16 ms on Windows: about 31 events/s sustained, and up to about 32 ms latency per event. |
| Documented | Nothing. |
| Tests | None assert latency or throughput. |
| Hosts/runtimes | Measured on Windows PowerShell 5.1; the sleep granularity differs by OS (Linux/macOS timers are finer), so throughput is host-dependent today. |
| Accidental or relied upon | Accidental; nothing relies on the delay. |
| Option A | **Yes:** the contract promises delivery and within-source order, not latency or throughput; limits are documented as characteristics of this runtime. |
| Option B | A latency/throughput floor in the contract. |
| Compatibility | A: none. B: none for programs; constrains every runtime. |
| Implementation | A: documentation. B: a scheduler rework (the event-loop review's options B/C). |
| Recommended minimal 1.0 contract | **A**, with the current measured limits documented as runtime characteristics (EV7), not as language semantics. |
| Decision | **UNRESOLVED** |

### EV6. Is the event loop cooperative rather than real-time?

| | |
|---|---|
| Current behavior | Cooperative. One thread; a handler runs to completion and is never preempted; no timing guarantees. |
| Documented | Implicitly (D104 comment in the source: "handlers run one at a time, on this same thread ... never concurrently, never re-entering"). Not in the ledger. |
| Tests | Implicit in every event test (handlers observe consistent variable state). |
| Hosts/runtimes | All four PowerShell hosts and the web target (JavaScript is single-threaded and run-to-completion). |
| Accidental or relied upon | Relied upon: Otter programs share variables between the main program and handlers without locks. |
| Option A | **Cooperative, single-threaded, run-to-completion handlers; no real-time guarantees.** |
| Option B | Preemptive or real-time. |
| Compatibility | A: none. B: would break every program that shares state with handlers. |
| Implementation | A: documentation only. |
| Recommended minimal 1.0 contract | **A.** |
| Decision | **UNRESOLVED** |

Note for EV6: *when* handlers run relative to the main program differs by target
today. Console: after the main program, or during `wait` for HTTP/jobs. Web:
whenever the browser delivers the event, which includes while the main program is
paused at an awaited operation (for example an HTTP request, which compiles to an
awaited `fetch`). So "handlers never run in the middle of a main-program
statement" is **not** true on the web target today. A contract must either name
the points where handlers may run ("between statements, at `wait`, and at an
awaited operation") or state the difference between targets explicitly.

### EV7. Are the current scheduling limits documented as part of 1.0?

| | |
|---|---|
| Current behavior | The limits are recorded only in `docs/OTTER_1_0_EVENT_LOOP_REVIEW.md` (an engineering review), not in user documentation or the ledger. |
| Tests | Not applicable. |
| Option A | **Document them as characteristics of the 1.0 runtime** (not as language guarantees): about 30 UDP/TCP events per second, handlers run after the main program except during `wait` (per EV3), heavy job output delays other handlers (unless EV2-A). |
| Option B | Make them part of the language contract. |
| Option C | Do not document them. |
| Compatibility | A: none; lets a later runtime be faster without a contract change. B: freezes today's slowness into the language. C: leaves users to discover the 30 events/s ceiling and the `wait` hang themselves. |
| Implementation | A: user documentation only. |
| Recommended minimal 1.0 contract | **A.** |
| Decision | **UNRESOLVED** |

---

## Additional contradictions found

1. **Seventeen decisions are cited by the contract and code but absent from the
   frozen ledger.** `SPEC-DECISIONS.md` has no entry for D99, D100, D101, D102,
   D103, D104, D105, D106, D107, D108, D109, D110, D111, D112, D113, D114 or D119
   (OQL, console UX, wait/timers/seeded random, bytes, SPA routing, file watching,
   XML, WebSockets, TCP, UDP, cryptography, drag and drop, credential vault, TLS,
   and command jobs, among others). Gate 1 certified a contract whose decision
   record does not describe these features. Several (D107-D112) were implemented
   from specifications supplied in conversation that were never entered in the
   ledger, because the ledger is frozen and entries require Jeff's approval.
2. **Web `wait` is unsupported** ("not supported on the web target yet"), so `wait`
   is effectively console/desktop-only, while `STANDARD_LIBRARY.md` does not list it
   among target-specific operations.
3. **Handler timing differs by target** (EV6 note): console runs handlers after the
   main program; the web runs them as events arrive. Nothing documents or tests this.
4. **`Http.Tests.ps1` is not host-portable** (hard-coded `powershell.exe` in its CLI
   helper) and is not in the D120 suite, so DC1 has no four-host evidence.
5. The conformance fixture `http-web-target-only` is named for a classification the
   implementation no longer has.

## Classification of the decisions

| Decision | If the recommendation is taken |
|---|---|
| DC1-A | Documentation + test coverage (fixture rename, four-host HTTP run). No runtime change expected. |
| EV1-A, EV2-A | **Implementation change** (bound job draining) + one test. |
| EV3-A | **Implementation change** (service all sources during `wait`) + tests. |
| EV4-A, EV5-A, EV6-A, EV7-A | Documentation only. |
| Ledger gap (17 decisions) | Documentation (ledger entries), with Jeff's approval. |

**Could break existing programs:** DC1-B (every console HTTP program), EV3-B (the
D119 dogfood poll loop and HTTP-during-wait), EV6-B (all shared-state programs).
EV3-A changes *when* socket/watcher handlers run for programs that `wait` while
those sources are active (earlier, during the wait); no existing test or example
relies on the old timing. EV2-A changes only how long other sources wait behind a
busy job.

## Proposed smallest coherent Otter 1.0 event contract

1. **Cooperative:** handlers run one at a time on a single thread, to completion,
   and never preempt running code. They run only at defined points: after the
   main program, during `wait`, and (web target) while the main program awaits an
   asynchronous operation such as an HTTP request. No real-time guarantees.
2. **Ordering:** events from one source are delivered in the order they occurred;
   order across sources is unspecified.
3. **Progress:** every ready source is eventually serviced; no source may
   indefinitely prevent another from being serviced (bounded per-turn work).
4. **When handlers run:** after the main program's last statement, and during any
   `wait`, for **all** active event sources.
5. **Delivery, not speed:** the contract promises delivery and order, not latency
   or throughput. The 1.0 runtime's measured limits are documented as runtime
   characteristics, not language semantics.

Implementation differences from today: point 3 (bound job draining) and point 4
(extend `wait` to sockets, WebSockets, TCP servers and watchers). Everything else
is documentation.

**All decisions: UNRESOLVED.**
