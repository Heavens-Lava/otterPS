# Otter 1.0 Performance Baseline

Status: **baseline only. No optimization has been made** (apart from the
`return` fast path that predates this work, described below).

Measured with `tools\Invoke-OtterBenchmarks.ps1` on the programs in `benchmarks\`.
Raw data: `benchmarks\results\baseline-0.9.0.json`.

## Host

| | |
|---|---|
| Otter | 0.9.0 (includes the direct-`return` fast path, commit `aea1d9c`) |
| PowerShell | 5.1.26100.8115 (Desktop) |
| OS | Windows NT 10.0.26200 |
| CPU | Intel Core i9-14900 (32 logical cores; the interpreter is single-threaded) |
| Method | 1 warmup run discarded, 5 measured runs, in-process, profiler off |

## Results

Median / minimum / maximum of five measured runs. Spread is small (min and max
within about 5% of the median for everything except `event_dispatch`, about 7%),
so the medians are stable.

| Benchmark | Median ms | Min ms | Max ms | Statements | Calls | Stmts/s | Calls/s | ms per statement |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| arithmetic | 1,123.9 | 1,091.5 | 1,129.6 | 2,003 | - | 1,782 | - | 0.56 |
| event_dispatch | 3,503.1 | 3,232.3 | 3,722.1 | 310 | - | 88 | - | 11.3 |
| file_io | 482.2 | 472.8 | 495.1 | 364 | - | 755 | - | 1.32 |
| function_calls | 897.8 | 871.1 | 913.3 | 2,106 | 900 | 2,346 | 1,002 | 0.43 |
| json | 143.5 | 136.4 | 147.2 | 184 | - | 1,283 | - | 0.78 |
| lists | 1,484.8 | 1,475.7 | 1,493.3 | 810 | - | 546 | - | 1.83 |
| loops | 996.1 | 972.3 | 1,024.5 | 1,538 | - | 1,544 | - | 0.65 |
| objects | 828.4 | 818.5 | 848.3 | 1,205 | - | 1,455 | - | 0.69 |
| recursion | 1,451.8 | 1,442.0 | 1,453.4 | 2,265 | 566 | 1,560 | 390 | 0.64 |
| strings | 502.1 | 494.1 | 514.9 | 704 | - | 1,402 | - | 0.71 |

Startup, measured separately (separate process per run, 5 runs after 1 warmup):

| Command | Median | Min | Max |
|---|---:|---:|---:|
| `otter --version` | 789 ms | 776 ms | 792 ms |
| `otter run hello.ot` | 1,197 ms | 1,172 ms | 1,207 ms |

Typical statements cost about **0.4 to 0.8 ms** each, i.e. roughly **1,500 to
2,400 statements per second** and about **1,000 function calls per second**.

## Profiler validation

`otter profile` was run on `function_calls.ot` and `recursion.ot` and compared
with the runner's independent counts.

* **Counts agree exactly.** function_calls: `double` 300, `combine` 300, `touch`
  300 (= the runner's 900 calls); 2,106 statements (= the runner's 2,106).
  recursion: `fib` 465 (the known call count for fib(12)) + `sumTo` 101 = 566
  (= the runner's 566).
* **Accounting is internally consistent.** A function's total equals its self
  time when it only calls itself (recursion is not double-counted); a function's
  self time equals the sum of its body lines; per-line hit counts equal the
  number of times each line ran.
* **Overhead is large: about 2.3x to 2.6x.** function_calls took 2,364 ms profiled
  versus 898 ms unprofiled (2.6x); recursion 3,356 ms versus 1,452 ms (2.3x). Use the profile
  for *shape* (which lines/functions dominate), not for absolute time. Timing runs
  never use it.

## Where the time goes

Measured directly, by timing the interpreter's internal functions in isolation
(cost per call in microseconds, averaged over 3,000 calls):

| Operation | Cost |
|---|---:|
| calling an empty PowerShell function | 22 |
| `Get-OtterValue`: a literal | 36 |
| `Get-OtterValue`: a variable | 85 |
| `Get-OtterValue`: `x plus 7` | **364** |
| `Assert-OtterNumber` on a number (called twice per arithmetic/comparison) | **84** |
| `Test-OtterEqual` on two numbers | **164** |
| `Test-OtterEqual` on two strings | **210** |
| `Write-Output -NoEnumerate` (used on every variable read) vs plain `return` | 62 vs 22 |
| `Invoke-OtterStatement`: assign a literal | 121 |
| `Invoke-OtterStatement`: assign `x plus 7` | **474** |

The interpreter is not slow because PowerShell function calls are slow (22 us);
it is slow because each Otter operation is a *chain* of small helper calls, and
a few chains are long:

* **Arithmetic and ordering comparisons** call `Assert-OtterNumber` twice, each
  of which calls `Test-OtterNumeric` and `ConvertTo-OtterNumber`. That is about
  170 us of a 364 us expression, even when both operands are already numbers.
* **Equality** (`is`, `is not`, `contains`, `remove`, `find`) goes through
  `Test-OtterEqual`, which makes about eight helper calls (bool, date, numeric,
  bytes, list checks) before reaching the answer: 164 to 210 us per comparison.
* **Every variable read** pays for `Write-Output -NoEnumerate` (about 40 us
  extra) so that lists are not unrolled - needed for lists, wasted for numbers
  and text.
* **Function calls** cost about 1 ms end to end (900 calls in 898 ms in
  `function_calls`: the call statement, argument list, new scope, call frame,
  try/finally, the body statement and the return).

## Findings against the release policy

The 1.0 policy asks for: no pathological defect in advertised workloads, no
accidental algorithmic catastrophe, responsive ordinary applications, documented
characteristics.

1. **`contains` is linear with a very large constant.** A `contains` on a
   300-item list costs about 60 ms because each element comparison is a full
   `Test-OtterEqual` (about 200 us). Measured: 100 lookups on a 300-item list took
   1.0 s, 400 lookups 13 s. Same for `remove`, `find` and other equality scans.
   It is *not* worse than linear per lookup, so it is not an algorithmic
   catastrophe, but a 5,000-item list search would take about one second per
   lookup. **This is the most likely pathological experience for an ordinary
   program.**
2. **Event dispatch is slow: about 35 ms per event.** `event_dispatch` handles 100
   loopback datagrams in 3.5 s. The event loop sleeps 10 ms on every pass, does
   about four provider steps each pass, and a UDP socket keeps one outstanding
   receive at a time, so it handles at most one datagram per pass. That caps sustained dispatch near 30 events per second when events are
   already queued. This affects UDP/TCP/WebSocket/watcher/job handlers in console
   programs, not web-page events.
3. **Startup is 0.8 s (`--version`) to 1.2 s (`run hello.ot`).** Almost all of it
   is PowerShell start and module loading. Acceptable for a 1.0 interpreter,
   noticeable in scripts run in a tight shell loop.
4. **`return` (already fixed).** Before the profiler work, a `return` directly in
   a function body ended the call by throwing an exception, about 0.5 ms per call.
   Direct returns no longer throw; nested returns still do. Every measurement in
   this document is with that fix in place.
5. **No unbounded growth or scaling surprise was found** for `add`, loops, JSON,
   strings, file I/O, or call depth: list `add` and counter loops scaled linearly
   (100 to 800 iterations: 47 to 212 ms, and 64 to 434 ms).

Nothing measured here is a correctness problem, and nothing requires an
architectural redesign to fix (see below).

## Optimization candidates, ranked by measured impact

None of these has been implemented. Each must, before merging, preserve
interpreter behavior, keep JS differential parity, and pass the full regression
suite, the 15 conformance fixtures, and the differential fuzzer.

| # | Candidate | Evidence | Expected effect | Risk |
|---|---|---|---|---|
| 1 | **Fast path in `Test-OtterEqual` for two numbers** (and other cheap same-type cases) before the chain of type helpers | 164 us per comparison, dominating `contains`/`is` | `contains` on 300 items from about 60 ms to well under 10 ms; every `if x is y` about 150 us cheaper | **Low** for `[double]`/`[int]` pairs. **Not** safe for strings without a numeric check: `"5"` equals `5` today, and `"5.0"` equals `"5"` |
| 2 | **Inline `[double]` fast path for `Assert-OtterNumber`** in math and ordering comparisons | 84 us x2 inside a 364 us expression | about 40% off each arithmetic/comparison expression; arithmetic benchmark about 25-30% faster | **Low** - the fast path returns exactly what the helpers return for a `[double]` |
| 3 | **Skip `Write-Output -NoEnumerate` for non-collection values** on variable reads | 62 us vs 22 us on every variable read | about 40 us per variable read (one to three per statement) | **Low-medium** - lists must still not unroll; the check must be by type, and any missed collection type becomes a bug |
| 4 | **Event loop: do not sleep when a pass made progress; drain queued events** | 35 ms per event vs 10 ms sleep floor | queued-event throughput 5x to 20x | **Medium** - changes event ordering/timing between providers and could spin CPU; needs the async-job and watcher tests to prove no starvation |
| 5 | **Trim per-call overhead** (`Invoke-OtterCall`: typed call-frame instead of `[pscustomobject]`, fewer lookups) | about 1 ms per call end to end | about 10-15% on call-heavy code | **Medium** - the call frame is what the debugger and profiler read |
| 6 | **Reduce `Invoke-OtterStatement` dispatch overhead** (statement-hook check, `Kind.ToString()` switch) | 85 us statement overhead above the value evaluation | about 5-10% overall | **Medium** - a large `switch`; a table dispatch is a bigger change |
| 7 | **Lazy-load rarely used modules at startup** | 0.8 s `--version` | perhaps 0.2 to 0.4 s off startup | **Medium-high** - changes module load order and error behavior |

Candidates 1 to 3 are small, local, and behavior-preserving, and together should
remove roughly 30 to 40% of typical statement cost. They do not require
restructuring the interpreter. Candidates 4 to 7 are worth doing only after 1 to 3
are measured again.

## Recommendation for 1.0

* Document the measured characteristics (about 1,500 to 2,400 statements per
  second; about 1,000 calls per second; 0.8 to 1.2 s startup) in the user
  documentation so nobody is surprised.
* Treat **candidates 1 and 2** as worthwhile pre-1.0 work: they are low-risk and
  remove the only workload (`contains`/equality scans) that could feel broken in
  an ordinary program.
* Treat the **event-loop sleep (4)** as a judgment call for 1.0: sustained event
  rates above about 30 per second are unusual for the console programs it serves.
  If deferred, note the limit in the documentation.
* Defer 5 to 7 unless the freeze audit or dogfooding shows a need.

## Reproduce

```powershell
powershell -NoProfile -File tools\Invoke-OtterBenchmarks.ps1 -Runs 5 -Startup -Json benchmarks\results\latest.json
powershell -NoProfile -File otter.ps1 profile benchmarks\function_calls.ot
```

Results depend on the machine; compare runs from the same machine only.
