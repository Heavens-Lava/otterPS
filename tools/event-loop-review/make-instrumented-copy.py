"""Builds tools/event-loop-review/copy/ : a copy of the repo modules whose event loop is
instrumented with counters and stopwatches. Scheduling logic is copied verbatim;
only timing/counting lines are added. The repo itself is not modified."""
import os, re, shutil

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(os.path.dirname(here))
dest = os.path.join(here, 'copy')
if os.path.exists(dest):
    shutil.rmtree(dest)
os.makedirs(os.path.join(dest, 'src'))
shutil.copy(os.path.join(repo, 'Otter.Contract.psm1'), dest)
for name in os.listdir(os.path.join(repo, 'src')):
    if name.endswith('.psm1'):
        shutil.copy(os.path.join(repo, 'src', name), os.path.join(dest, 'src', name))

path = os.path.join(dest, 'src', 'Otter.Interpreter.psm1')
s = open(path, encoding='utf-8', newline='').read().replace('\r\n', '\n')

start = s.index('function Invoke-OtterEventLoop {')
end = s.index('function Invoke-OtterWatchEventLoop {')
original = s[start:end]

instrumented = r'''$script:LoopStats = $null
function Get-OtterLoopStats { return $script:LoopStats }

function Invoke-OtterEventLoop {
    $st = @{ Passes = 0; SleepMs = 0.0; SleepCalls = 0; WatchMs = 0.0; WsMs = 0.0; NetMs = 0.0; HttpMs = 0.0; JobMs = 0.0; CheckMs = 0.0; WallMs = 0.0; CpuStartMs = 0.0; CpuEndMs = 0.0 }
    $script:LoopStats = $st
    $clock = [System.Diagnostics.Stopwatch]::new()
    $loopClock = [System.Diagnostics.Stopwatch]::StartNew()
    $st.CpuStartMs = [System.Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.TotalMilliseconds
    while ($true) {
        $clock.Restart()
        $hasWatchers = ($script:OtterActiveWatchers.Count -gt 0)
        $hasSockets = $false
        foreach ($ws in $script:OtterActiveWebSockets) {
            if ($ws.State -in @('connecting', 'open', 'closing')) {
                if ($script:OtterWebSocketHandlers.ContainsKey($ws) -and $script:OtterWebSocketHandlers[$ws].Count -gt 0) {
                    $hasSockets = $true
                    break
                }
            }
        }

        $hasNet = Test-OtterNetActive
        if ($hasNet) { $hasSockets = $true }

        $hasHttp = Test-OtterHttpActive
        if ($hasHttp) { $hasSockets = $true }

        $hasJobs = Test-OtterJobsActive
        if ($hasJobs) { $hasSockets = $true }
        $st.CheckMs += $clock.Elapsed.TotalMilliseconds

        if (-not $hasWatchers -and -not $hasSockets) {
            break
        }
        $st.Passes++

        $clock.Restart()
        if ($hasWatchers) {
            $watchTimeout = if ($hasSockets) { 0.02 } else { 0.5 }
            Invoke-OtterWatchEventLoopStep -Timeout $watchTimeout
            $st.WatchMs += $clock.Elapsed.TotalMilliseconds
        } elseif ($hasSockets) {
            Start-Sleep -Milliseconds 10
            $st.SleepMs += $clock.Elapsed.TotalMilliseconds
            $st.SleepCalls++
        }

        if ($hasSockets) {
            $clock.Restart(); Invoke-OtterWebSocketEventLoopStep; $st.WsMs += $clock.Elapsed.TotalMilliseconds
            $clock.Restart(); Invoke-OtterNetEventLoopStep; $st.NetMs += $clock.Elapsed.TotalMilliseconds
            $clock.Restart(); Invoke-OtterHttpEventLoopStep; $st.HttpMs += $clock.Elapsed.TotalMilliseconds
            $clock.Restart(); Invoke-OtterJobEventLoopStep; $st.JobMs += $clock.Elapsed.TotalMilliseconds
        }
    }
    $st.WallMs = $loopClock.Elapsed.TotalMilliseconds
    $st.CpuEndMs = [System.Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.TotalMilliseconds
}

'''

# Sanity: the instrumented copy must keep every scheduling decision of the original.
for needle in ("0.02 } else { 0.5 }", "Start-Sleep -Milliseconds 10", "Invoke-OtterWebSocketEventLoopStep",
               "Invoke-OtterNetEventLoopStep", "Invoke-OtterHttpEventLoopStep", "Invoke-OtterJobEventLoopStep",
               "Test-OtterNetActive", "Test-OtterHttpActive", "Test-OtterJobsActive"):
    assert needle in original, needle
    assert needle in instrumented, needle

s = s[:start] + instrumented + s[end:]
s = re.sub(r'(Set-OtterStatementHook, Get-OtterCallStackSnapshot, Set-OtterApplicationId)', r'\1, Get-OtterLoopStats', s, count=1)
assert 'Get-OtterLoopStats' in s.split('Export-ModuleMember')[-1]
open(path, 'w', encoding='utf-8', newline='').write(s)
print('instrumented copy written to', dest)
