# Otter 1.0 Event Model

How Otter runs event handlers: `on data from`, `on message from`, `on change of`,
`on output from`, `on complete of` and the rest. The language rules are decision
**D121** in `SPEC-DECISIONS.md`; this page explains them and, separately, describes
how the 1.0 runtime behaves in practice.

## The language guarantees (every target)

1. **One handler at a time.** A handler runs to completion before another
   handler starts, and a handler never interrupts running Otter code. Programs
   can share variables between the main program and handlers without locks.
2. **Progress, not equal shares.** Every source with events ready for dispatch
   is eventually serviced; a busy source cannot keep another ready source waiting
   indefinitely. Otter does not promise round-robin order, equal shares or a
   maximum delay.
3. **Order within a source.** Events from one source are handled in the order
   they became ready: a job's output lines in order, a socket's data in order, a
   watcher's changes in order. The order between different sources is not
   specified.
4. **`wait` lets events happen.** During `wait` (where the target supports it),
   every active event source is serviced, so handlers may run while the program
   waits. This is what makes a loop such as

   ```otter
   while not done
       wait 100 milliseconds
   .
   ```

   work when `done` is set by a handler.
5. **No real-time guarantee.** Otter promises how events are dispatched, not how
   quickly.
6. **Dispatch, not delivery.** These rules cover events once they are ready to
   dispatch. The outside world has its own rules: TCP may merge several writes
   into one `on data`, a network connection can fail, and a file system may merge
   or drop change notifications.

## When handlers run (differs by target)

| Target | Handlers run |
|---|---|
| Console and desktop (`otter run`) | After the main program's last statement, and during any `wait`. |
| Web (`otter web`) | Whenever the browser delivers the event, which includes while the main program is suspended at an asynchronous operation such as an HTTP request. `wait` is not available on the web target in Otter 1.0. |

The guarantees above hold on both. Exact timing is a property of the host and
is not the same across targets.

## Runtime characteristics of Otter 1.0 (not language rules)

Measured on Windows PowerShell 5.1 (`docs/OTTER_1_0_EVENT_LOOP_REVIEW.md`,
`benchmarks/results/event-loop-0.9.0.json`). A later runtime may be faster
without any change to the language.

* The console event loop polls. UDP datagrams and TCP reads are handled at about
  30 per second when they arrive back to back (two loop passes per event, and a
  10 ms sleep that lasts about 16 ms on Windows). File-watcher and command-job
  events are faster (hundreds per second).
* When file watchers and sockets are active at the same time, each loop pass
  waits about 200 ms for a watcher event (the whole-second timeout of PowerShell's
  `Wait-Event`), so socket events are slower still in that combination.
* A command job's queued output is handled in batches (currently up to 256 events
  per turn) so that other sources get a turn; the batch size is not part of the
  language.
* An idle program with an open socket and no traffic keeps polling (about 60
  passes per second; measured at roughly 7 to 16 percent of one CPU core).
