# Event-loop review tooling

Evidence for `docs/OTTER_1_0_EVENT_LOOP_REVIEW.md`. **Read-only investigation:** nothing here
changes how Otter schedules events.

* `make-instrumented-copy.py` copies the repo's modules into `copy/` (git-ignored) and adds
  counters and stopwatches around each phase of `Invoke-OtterEventLoop`. The scheduling
  decisions in the copy are identical to the original (the script asserts each one is still
  present); only timing lines are added. The real modules are not touched.
* `Invoke-EventLoopScenario.ps1 -Scenario <name>` runs one event source against the copy and
  prints a JSON line. Scenarios: `idle`, `udp_burst`, `udp_paced`, `tcp_stream`, `job_output`,
  `job_starve`, `watcher_burst`.

```powershell
python tools\event-loop-review\make-instrumented-copy.py
powershell -NoProfile -File tools\event-loop-review\Invoke-EventLoopScenario.ps1 -Scenario udp_burst
```

Results from the recorded run: `benchmarks/results/event-loop-0.9.0.json`.
Numbers depend on the machine; the structural findings (two passes per UDP/TCP event, the
timer-tick sleep, drain-all job events) do not.
