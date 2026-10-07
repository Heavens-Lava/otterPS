# Otter 1.0 Event Loop Review

Status: **investigation only. No scheduling behavior was changed.** Every
measurement below came from an instrumented *copy* of the interpreter under
`tools/event-loop-review/copy/` (git-ignored); the repository's modules are untouched.
Raw results: `benchmarks/results/event-loop-0.9.0.json`. Reproduce with
`tools/event-loop-review/` (see its README).

## Update 2026-09-27: decisions taken and a correction

* **Decided.** EV1-EV7 were decided and recorded as **D121** in
  `SPEC-DECISIONS.md`; user-facing description in `docs/OTTER_1_0_EVENT_MODEL.md`.
  Two runtime changes followed (commit `5e920fe`): `wait` now services every
  event source (EV3; previously HTTP and jobs only), and a command job handles
  at most 256 queued events per turn (EV2). Scheduling timing (the sleep) was not
  changed. The measurements below describe the runtime **before** those two
  changes.
* **Correction.** Section 2 says the loop "waits" with `Wait-Event 0.5 s` (watchers
  only) and `Wait-Event 0.02 s` (watchers plus sockets). `Wait-Event -Timeout`
  takes whole seconds, so both values round to 0, and a 0 timeout was measured to
  block for about **200 ms**. With watchers only the loop therefore waits about
  200 ms per pass (not 0.5 s); with watchers and sockets it waits about 200 ms per
  pass (not 20 ms), which makes socket events slower still in that combination.
  The watcher-only CPU note in section 8 ("not measured separately") stands.

## Short answer

The ~30 events per second in the `event_dispatch` benchmark is **not a property of
"the event system" in general.** It comes from two things that combine, and only for
**UDP and TCP data events**:

1. **A UDP or TCP socket needs two loop passes per event.** One pass *arms* the
   receive; the next pass *consumes* the result. (`Step-OtterUdp` and the read half of
   `Step-OtterTcp` are written as `if ($null -eq $ReceiveTask) { arm } elseif
   ($ReceiveTask.IsCompleted) { consume }`, so a task is never checked in the pass
   that created it. WebSocket receives and TCP server accepts do not have this
   pattern: they arm and check in the same pass.)
2. **Every pass sleeps about 16 ms, not 10 ms.** The loop calls
   `Start-Sleep -Milliseconds 10`, but on Windows the sleep rounds up to the 15.6 ms
   system timer tick: measured 16.0 ms for a 10 ms sleep, and 16.7 ms even for a 1 ms
   sleep. Sleeping is **92% of the loop's time** in the UDP benchmark.

Two passes at about 16 ms each is about 32 ms per event, which is the measured
30 to 31 events per second. Watcher events, process-job events and HTTP completions
do **not** have this limit (measured below).

## 1. How one loop iteration works

`Invoke-OtterEventLoop` runs **after** the main program has finished executing all its
top-level statements (`Invoke-OtterProgram` calls it last). Handlers therefore never
interrupt the main flow; they run only in the loop, one at a time, on the single
interpreter thread.

Each pass:

1. **Decide whether to continue.** Work out `hasWatchers` (any active file watcher) and
   `hasSockets`, which is true if any WebSocket, TCP/UDP socket or TCP server, HTTP
   request or command job is still active *and has at least one handler*. If both are
   false, the loop ends. (So a socket with no handler keeps nothing alive.)
2. **Wait.**
   * watchers only: `Wait-Event -Timeout 0.5` (returns immediately when an event arrives).
   * watchers **and** other sources: `Wait-Event -Timeout 0.02`.
   * no watchers: `Start-Sleep -Milliseconds 10`.
3. **If any non-watcher source exists, step each family once, in fixed order:**
   WebSockets, then TCP/UDP, then HTTP, then command jobs.

## 2. Every place the loop waits, sleeps or yields

| Where | Wait | Notes |
|---|---|---|
| Loop pass, no watchers | `Start-Sleep 10 ms` (really about 16 ms) | the fixed cost every socket/HTTP/job pass pays |
| Loop pass, watchers only | `Wait-Event 0.5 s` | wakes immediately on an event; 0 CPU while idle |
| Loop pass, watchers plus sockets | `Wait-Event 0.02 s` | acts as the sleep; does **not** wake for socket data |
| `wait N seconds` statement | `Start-Sleep` in chunks of up to 20 ms | pumps **only** HTTP and job steps; socket, WebSocket and watcher events are **not** dispatched during a `wait` |
| WebSocket send | `SendAsync(...).Wait()` | blocks the loop until the send completes |

There is no other yield. Handlers run to completion; nothing preempts them.

## 3 and 4. Events per source per pass, and whether queues are drained

| Source | Handled per pass | Drained or one at a time | Passes per event |
|---|---|---|---|
| UDP socket | at most 1 datagram | one at a time | **2** (arm, then consume) |
| TCP connection (read) | at most 1 read (whatever bytes are buffered) | one at a time | **2** |
| TCP server accept | at most 1 connection | one at a time | 1 (arms and checks in the same pass, like WebSockets) |
| WebSocket | at most 1 message per socket | one at a time | 1 (arms and checks in the same pass) |
| File watcher | 1 event from PowerShell's event queue | one at a time | 1, but Changed/Created/etc. events with no handler each still use a pass |
| HTTP request | every request that has completed | drained | 1 |
| Command job (output, exit) | **every** queued item | **drained completely** (`while TryDequeue`) | 1 |

A TCP read returns however many bytes are buffered, so a busy TCP stream loses
*event granularity* (several writes become one `on data`) but not bytes.

## 5. FIFO and ordering

* **Within one source: FIFO.** UDP datagrams, TCP reads, watcher events and job output
  each keep their arrival order.
* **Across sources: no global order.** A pass always visits sources in the fixed order
  above, so if a WebSocket message, a UDP datagram and a job line all arrived "at the
  same time", the handlers run WebSocket, then UDP, then job, regardless of arrival order.

## 6. Interaction between sources

| Source | Where it runs | In this loop? |
|---|---|---|
| File watchers | .NET FileSystemWatcher raises PowerShell events, queued and read with `Wait-Event` | yes |
| Command jobs (output/exit) | a background thread enqueues to a concurrent queue; the loop dequeues | yes |
| TCP / UDP | .NET async tasks polled with `IsCompleted` | yes |
| WebSockets | .NET async tasks polled with `IsCompleted` | yes |
| HTTP requests | .NET async tasks polled with `IsCompleted` | yes |
| **Timers** | Otter has **no timer event**; `start timer` is only a stopwatch, `wait` blocks | no such source |
| **UI events** (buttons, text boxes) | WPF dispatcher (desktop) or the browser's JavaScript (web) | **not in this loop at all** |

So UI responsiveness does not depend on this loop, and the 30/s figure does not apply
to UI events.

## 7. Can one busy source starve another?

**Yes: command jobs can starve everything else.** `Invoke-OtterJobEventLoopStep`
drains its queue with `while ($queue.TryDequeue(...))`. When the process's output (read on a background thread) arrives at least as fast as
the interpreter can run the handler, the queue does not empty until the output ends.
Everything else waits for that one `Invoke-OtterJobEventLoopStep` call to return.

Measured (`job_starve`): a job printing 4,000 lines, with a UDP datagram arriving from
outside about 1 second into the flood. Output:

```
job exited after lines: 4000
UDP handler ran after job lines: 4000
```

The datagram was delivered and armed, but its handler did not run until all 4,000 job
lines and the job's exit handler had finished (one job step took about 1.5 s). The
other sources cannot do this to each other: sockets, WebSockets and watchers are limited
to one event per source per pass, so no single one can monopolize the loop. HTTP handles
each completed request once.

## 8. CPU behavior

| Situation | Measured |
|---|---|
| **Idle, sockets waiting for data** (UDP socket, nothing arriving, 8.8 s) | 534 passes (about 61 per second, about 16.5 ms each). Loop CPU about 656 to 1,391 ms over the 8.8 s across two runs, roughly **7% to 16% of one core** while doing nothing (noisy: includes first-run JIT) |
| **Idle, watchers only** | not measured separately; by the code it blocks in `Wait-Event 0.5 s` rather than polling, so it should be near zero |
| **Occasional events** (`udp_paced`: 20 events, 250 ms apart) | about 60 passes per second continue between events; loop CPU about 15% of a core |
| **Continuously queued events** (`udp_burst`) | sleeping 92% of the time; loop CPU about 20% of a core; the loop is latency-bound, not CPU-bound |
| **Job flood** | CPU-bound on the interpreter (handlers running back to back): loop CPU 2,250 ms in a 1,694 ms loop, i.e. more than one core counting the reader thread |

Polling costs a steady 60 passes per second whether or not anything happens, because
each pass runs the "is anything still active" checks and one step per socket.

## 9. Cancellation responsiveness

* Handlers that end things (`close udp ...`, `stop watching ...`, closing a socket,
  cancelling a job or request) take effect **at the next loop check**, at most about
  one pass (16 ms) later. By construction the loop's continue-or-stop check
  runs at the top of every pass, so a close is seen within one pass.
* Nothing can cancel a handler that is already running, and a long `wait` inside a
  handler pumps only HTTP and jobs.
* A job flood (section 7) delays *every* other event and cancellation until the flood's
  step returns.
* External interruption (Ctrl+C, closing the console) was not analyzed here.

## 10. Is 30 events/s specific to the benchmark or general?

**Specific to UDP and TCP data events, and it would apply to any UDP or TCP program.**
It is not specific to the benchmark's sender; it is the loop's structure. Measured:

| Scenario | Events | Loop time | Passes | Sleep time | Result |
|---|---:|---:|---:|---:|---|
| `udp_burst` (200 datagrams already queued) | 200 | 6,385 ms | 400 | 5,826 ms (91%) | **31 events/s**, exactly 2 passes per event |
| `udp_paced` (20 datagrams, 250 ms apart) | 20 | 5,603 ms | 305 | 5,321 ms | each event delayed up to about 32 ms by the arm-then-consume pattern |
| `tcp_stream` (100 one-byte writes, 30 ms apart) | 97 events, 100 bytes | 3,814 ms | 235 | 3,412 ms | writes 30 ms apart start to **coalesce** (97 events for 100 writes); no bytes lost |
| `job_output` (300 lines) | 300 | **347 ms** | 8 | 127 ms | about **865 events/s**: not limited by the sleep |
| `watcher_burst` (40 files created) | 40 | **177 ms** | 79 | 0 | about **226 events/s**: event-driven, no sleeping |
| `job_starve` | 4,001 | 1,694 ms | 6 | 123 ms | one job step ran about 1.5 s, starving the UDP handler |

WebSockets are structurally better (one pass per message) but each pass still sleeps
about 16 ms, so a single busy WebSocket is capped near 60 messages per second per
socket. HTTP is not limited by the sleep for throughput (all completed requests are
handled per pass), only by its latency.

What this means for real programs:

* A UDP or TCP program that needs to react to more than about 30 packets or reads per
  second **is limited by the loop, not by Otter's speed on the handler.**
* Watchers and process streaming are fine.
* Web apps and desktop UI apps are unaffected.

## Why "just shorten the sleep" will not work

* The sleep is really a 15.6 ms timer tick. `Start-Sleep -Milliseconds 1` measured
  16.7 ms. Reducing the number does nothing on Windows unless the process raises the
  system timer resolution or the loop stops sleeping and *blocks on something*
  (a wait handle signalled when data arrives).
* The two-pass structure means even a zero-length sleep leaves two loop round trips
  per event.

## Options, ranked, not implemented

Each of these changes scheduling behavior and belongs to the design questions in the
next section, not to a benchmark tweak.

| # | Option | Effect | Risk |
|---|---|---|---|
| A | **Check the task in the pass that arms it** (UDP/TCP read/accept), as the WebSocket step already does | halves passes per event: about 62 events/s | **Low.** Same handlers, same order, same ownership; matches an existing pattern. Ordering across sources changes only in that an already-completed receive is seen one pass sooner |
| B | **Skip the sleep when a pass did work** (an event was dispatched) and only sleep when idle | throughput limited by handler speed instead of the timer tick, for backlogs | **Medium.** Needs the fairness rules in the next section; can otherwise spin |
| C | **Block on a wait handle** covering all sources (task completion, job queue, watcher events) instead of polling | zero idle CPU, near-zero latency | **Higher.** A real redesign of the loop; needs a wake-up mechanism for each source |
| D | **Per-pass limit for job events** (process at most N job items per pass) | removes job starvation | **Low to medium.** Changes when handlers run relative to job output, but only under load |
| E | **Pump every source during `wait`** | events not silently held during `wait` | **Medium.** Changes when handlers run relative to the main program |

## Questions the review leaves for design (not decided here)

1. **How many events should one pass process per source?** Today: one per source per
   pass, except jobs (all). A bound (for example up to N per source) with the current
   round-robin order would give both throughput and fairness.
2. **Should a pass drain a source's queue?** Draining is what causes job starvation.
3. **What is the fairness rule between sources?** Today: fixed order, and jobs win
   under load.
4. **Is cross-source arrival order a guarantee?** Today it is not, and the 1.0
   documentation should say so.
5. **When should the loop yield?** Today: a fixed sleep. A blocking wait would need
   every source to be able to signal.
6. **Should `wait` dispatch all events?** Today: only HTTP and jobs.
7. **What is the idle CPU target?** Today: polling, about 7% to 16% of a core with a
   socket open and nothing arriving.

## Release disposition (decided; no runtime change until the freeze audit completes)

The review is accepted as release evidence. **No event-loop behavior is changed at this
time**: no Option A, no cap on job events, no sleep-timing change, no wider `wait`
dispatch. Scheduling semantics change only after the contract-freeze audit says what
the contract is.

| # | Finding | Classification |
|---|---|---|
| 1 | UDP/TCP throughput (about 31 events/s: two passes per event plus a 16 ms sleep) | **Documented performance limitation**, not yet a 1.0 blocker |
| 2 | Command-job starvation (one source drains an unbounded queue while others get one event per pass) | **Potential 1.0 scheduling concern. Requires an explicit fairness decision** before release |
| 3 | `wait` dispatches only HTTP and job events | **Semantic inconsistency. Needs contract review before freeze** |
| 4 | UI events | **Outside this event loop.** Document separately; UI responsiveness is not equivalent to socket/event-loop throughput |

## Event contract questions for 1.0

To be answered by the contract freeze. If the frozen contract says something like
"ordering is guaranteed within a source, cross-source ordering is unspecified, event
handling is cooperative and best-effort, and `wait` dispatches all active
asynchronous sources", the implementation must then be made to match it (smallest
semantic-preserving change, all release gates re-run). If the contract instead says
`wait` services only certain operations, that must be stated explicitly.

- [ ] Is cross-source fairness guaranteed or best-effort?
- [ ] May one event source drain an unbounded queue before others run?
- [ ] Which event sources are dispatched during `wait`?
- [ ] Is event ordering guaranteed only within a source?
- [ ] Are TCP/UDP receive callbacks allowed to be delayed by polling cadence?
- [ ] Is the event loop cooperative rather than real-time?
- [ ] Are the current scheduling limits documented as part of 1.0?

Facts the answers rest on (sections 5, 7 and 10 above): ordering is FIFO within a
source and unspecified across sources; jobs drain fully while every other source
handles at most one event per pass; sockets are delayed by the polling cadence (about
16 ms per pass, two passes per UDP/TCP event); the loop is cooperative and never
preempts a handler; `wait` pumps HTTP and jobs only.

## Recommendation for 1.0

* **Document the current guarantees and limits** (section 5, the 30 events per second
  ceiling for UDP/TCP, that events are dispatched only after the main program ends and
  are not dispatched during `wait` except HTTP and jobs, and that a job that emits a
  large amount of output delays other events).
* **Option A is the smallest change with a clear benefit** (2x for UDP/TCP) and matches
  what the WebSocket step already does; if a change is wanted before 1.0, it is the one
  to consider first. Options B to E need the design questions answered.
* The job-flood starvation (section 7) is the finding most worth a decision before 1.0,
  because it can make other handlers appear to hang. Option D addresses it directly.
