# Otter benchmarks

A repeatable performance baseline. **This suite measures; it does not tune.**
No benchmark adds syntax, changes semantics, or relies on a runtime shortcut -
each program is ordinary Otter.

## Run

```powershell
powershell -NoProfile -File tools\Invoke-OtterBenchmarks.ps1                 # all, 5 runs
powershell -NoProfile -File tools\Invoke-OtterBenchmarks.ps1 -Only lists -Runs 9
powershell -NoProfile -File tools\Invoke-OtterBenchmarks.ps1 -Startup -Json benchmarks\results\my-run.json
```

## Method

For every `*.ot` file the runner, in one PowerShell process:

1. tokenises and parses **once**;
2. does an untimed **counting pass** (statement hook) to record how many
   statements ran and how many function calls were made;
3. runs the program **`-Warmup` times** (default 1) and discards those runs;
4. runs it **`-Runs` times** (default 5) with **no hook installed**, timing
   each with a `Stopwatch`.

It reports **median, minimum and maximum**. Statements/second and calls/second
come from the median. Process startup, module loading and parsing are not in the
measured time; **startup is a separate benchmark** (`-Startup`). The profiler
(`otter profile`) is never active while timing - it adds roughly 2.3x to 2.6x overhead.

Host details (Otter version, PowerShell version/edition, OS, CPU, run counts) are
printed and stored in the JSON output.

## Programs

| File | Measures |
|---|---|
| `arithmetic.ot` | expression evaluation and assignment |
| `loops.ot` | `count`, `while`, `repeat`, `for each` |
| `function_calls.ot` | call setup, scope creation, return (value, two-parameter, no-value) |
| `recursion.ot` | recursive calls (Fibonacci 12, depth-100 sum) |
| `lists.ot` | add, contains, remove, sort, reverse, iterate |
| `objects.ot` | custom-type and plain-thing property read/write |
| `strings.ot` | case, replace, split, join |
| `json.ot` | JSON encode/decode round trips |
| `file_io.ot` | write/append/read/exists/delete (runs in a temp folder) |
| `contains_300.ot` | `contains` scans: 20 worst-case lookups on a 300-item number list |
| `contains_5000.ot` | `contains` scans: 2 worst-case lookups on a 5,000-item number list |
| `event_dispatch.ot` | event loop: 100 loopback UDP datagrams to an `on data` handler (uses port 47391) |

Workloads are deliberately small (hundreds to a few thousand statements) because
the interpreter runs at roughly 1-2 thousand statements/second; results are
compared as ratios between builds, not against other languages.

## Other sections

| Switch | Measures |
|---|---|
| `-Startup` | a separate `otter` process per run: `--version`, and `run examples\hello.ot` |
| `-Compile` | the web compiler (`otter web`) on every program above and on `examples\v1\tasks.ot`; parsing is not included. Console-only programs (UDP) are reported as skipped |
| `-Http` | `http/http_get.ot`: 50 GET requests from an Otter client to `http/server.ot`, an Otter web server the runner starts with `otter serve` (port 47392) and stops afterwards |
| `-Ui` | `ui/*.ot`: `build_window.ot` creates, configures and places 100 buttons with click handlers in a window that is never shown. Windows only; skipped elsewhere |
| `-All` | every section: `tools\Invoke-OtterBenchmarks.ps1 -All -Json benchmarks\results\my-run.json` |

The JSON output records the host, the Otter version and the git commit measured.

Timings on a busy machine vary: the same build measured twice has differed by
up to 13% on this suite. Compare builds back to back on one machine, and treat
smaller differences as noise.

## Results

`benchmarks/results/baseline-0.9.0.json` is the recorded baseline (before the
low-risk optimization pass), `before-contains.json` holds the two `contains`
benchmarks measured at the same point, and `optimized-0.9.0.json` is the result
after the pass. The analysis is
in [`docs/OTTER_1_0_PERFORMANCE_BASELINE.md`](../docs/OTTER_1_0_PERFORMANCE_BASELINE.md).
Compare a new run against it on the same machine; do not compare across machines.
