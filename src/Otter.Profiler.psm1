using module ..\Otter.Contract.psm1
using module .\Otter.Runtime.psm1
using module .\Otter.Interpreter.psm1

# Otter.Profiler.psm1
#
# `otter profile <file.ot>` - runs a program normally and then reports where
# its time went, in Otter terms: which Otter functions ran, how many times,
# and which Otter source lines were hottest. No PowerShell frames or .NET
# types appear in the report.
#
# This is not a second interpreter and it does not change how programs run.
# It plugs into the same single instrumentation point the debugger uses
# (Set-OtterStatementHook in src/Otter.Interpreter.psm1). The hook is called
# as each statement starts, so the time since the previous hook call is the
# time the PREVIOUS statement (and, for a function call, the callee's own
# statements) took. Each interval is charged to the line and function that
# were current when it began:
#
#   - line "self" time   = time spent on that line's own work, not in
#                          statements that ran after it started
#   - function "self"    = time charged while that function was the top frame
#   - function "total"   = self time of the function plus everything it called
#
# A normal `otter run` never loads this module, so it costs nothing there.
# Under `otter profile` the hook itself adds overhead to every statement, so
# absolute times are inflated; the relative shape (which lines and functions
# dominate) is what the report is for.

$script:Profile = $null

function Get-OtterAllocatedBytes {
    try {
        return [System.GC]::GetAllocatedBytesForCurrentThread()
    }
    catch {
        return [System.GC]::GetTotalMemory($false)
    }
}

function Format-OtterProfileBytes {
    param([long]$Bytes)
    $sign = if ($Bytes -lt 0) { '-' } else { '' }
    $abs = [Math]::Abs($Bytes)
    if ($abs -ge 1073741824) {
        return "$sign$([Math]::Round($abs / 1073741824.0, 1)) GB"
    }
    if ($abs -ge 1048576) {
        return "$sign$([Math]::Round($abs / 1048576.0, 1)) MB"
    }
    if ($abs -ge 1024) {
        return "$sign$([Math]::Round($abs / 1024.0, 1)) KB"
    }
    return "$sign$abs B"
}

function Start-OtterProfile {
    [CmdletBinding()]
    param()

    $proc = [System.Diagnostics.Process]::GetCurrentProcess()
    $proc.Refresh()
    $startCpuTicks = $proc.TotalProcessorTime.Ticks
    $startUserTicks = $proc.UserProcessorTime.Ticks
    $startKernelTicks = $proc.PrivilegedProcessorTime.Ticks

    $startManagedBytes = [System.GC]::GetTotalMemory($false)
    $startAllocBytes = Get-OtterAllocatedBytes
    $startWsBytes = $proc.WorkingSet64
    $startGen0 = [System.GC]::CollectionCount(0)
    $startGen1 = [System.GC]::CollectionCount(1)
    $startGen2 = [System.GC]::CollectionCount(2)

    $profile = [ordered]@{
        Clock               = [System.Diagnostics.Stopwatch]::StartNew()
        Process             = $proc
        StartCpuTicks       = $startCpuTicks
        StartUserTicks      = $startUserTicks
        StartKernelTicks    = $startKernelTicks
        StartManagedBytes   = $startManagedBytes
        PeakManagedBytes    = $startManagedBytes
        StartAllocatedBytes = $startAllocBytes
        LastAllocatedBytes  = $startAllocBytes
        StartWsBytes        = $startWsBytes
        StartGen0           = $startGen0
        StartGen1           = $startGen1
        StartGen2           = $startGen2
        LastTicks           = 0L
        LastCpuTicks        = $startCpuTicks
        LastLine            = 0
        LastStack           = @()               # function names on the stack when the last statement began
        LastFrames          = @{}               # depth -> frame object, to notice a new call
        Lines               = @{}               # line -> @{ Hits; Ticks; CpuTicks; AllocatedBytes }
        Functions           = @{}               # name -> @{ Calls; SelfTicks; TotalTicks; SelfCpuTicks; TotalCpuTicks; SelfAllocatedBytes; TotalAllocatedBytes }
        MainTicks           = 0L
        MainCpuTicks        = 0L
        MainAllocatedBytes  = 0L
        Statements          = 0L
    }
    $script:Profile = $profile

    $hook = {
        param($Statement, $Environment, $CallStack)
        $p = $script:Profile
        if ($null -eq $p) { return }

        $now = $p.Clock.ElapsedTicks
        $delta = $now - $p.LastTicks
        $p.LastTicks = $now

        $nowCpu = $p.Process.TotalProcessorTime.Ticks
        $deltaCpu = $nowCpu - $p.LastCpuTicks
        $p.LastCpuTicks = $nowCpu

        $nowAlloc = Get-OtterAllocatedBytes
        $deltaAlloc = [Math]::Max(0L, ($nowAlloc - $p.LastAllocatedBytes))
        $p.LastAllocatedBytes = $nowAlloc

        $nowManaged = [System.GC]::GetTotalMemory($false)
        if ($nowManaged -gt $p.PeakManagedBytes) { $p.PeakManagedBytes = $nowManaged }

        Add-OtterProfileInterval -Profile $p -Ticks $delta -CpuTicks $deltaCpu -AllocatedBytes $deltaAlloc

        $p.Statements++
        $line = [int]$Statement.Line
        $p.LastLine = $line
        if (-not $p.Lines.ContainsKey($line)) { $p.Lines[$line] = @{ Hits = 0L; Ticks = 0L; CpuTicks = 0L; AllocatedBytes = 0L } }
        $p.Lines[$line].Hits++

        # Record the stack this statement starts under, and count a call the
        # first time a frame is seen at its depth.
        $names = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $CallStack.Count; $i++) {
            $frame = $CallStack[$i]
            $names.Add([string]$frame.FunctionName)
            if (-not [object]::ReferenceEquals($p.LastFrames[$i], $frame)) {
                $p.LastFrames[$i] = $frame
                $entry = Get-OtterProfileFunction -Profile $p -Name $frame.FunctionName
                $entry.Calls++
            }
        }
        # Frames deeper than the current stack have returned.
        foreach ($depth in @($p.LastFrames.Keys)) {
            if ($depth -ge $CallStack.Count) { $p.LastFrames.Remove($depth) }
        }
        $p.LastStack = $names.ToArray()
    }

    Set-OtterStatementHook -Hook $hook
}

function Get-OtterProfileFunction {
    param($Profile, [string]$Name)
    if (-not $Profile.Functions.ContainsKey($Name)) {
        $Profile.Functions[$Name] = @{ Calls = 0L; SelfTicks = 0L; TotalTicks = 0L; SelfCpuTicks = 0L; TotalCpuTicks = 0L; SelfAllocatedBytes = 0L; TotalAllocatedBytes = 0L }
    }
    return $Profile.Functions[$Name]
}

function Add-OtterProfileInterval {
    param($Profile, [long]$Ticks, [long]$CpuTicks = 0L, [long]$AllocatedBytes = 0L)

    if ($Profile.LastLine -le 0) { return }   # before the first statement
    $lineEntry = $Profile.Lines[$Profile.LastLine]
    $lineEntry.Ticks += $Ticks
    $lineEntry.CpuTicks += $CpuTicks
    $lineEntry.AllocatedBytes += $AllocatedBytes

    $stack = $Profile.LastStack
    if ($stack.Count -eq 0) {
        $Profile.MainTicks += $Ticks
        $Profile.MainCpuTicks += $CpuTicks
        $Profile.MainAllocatedBytes += $AllocatedBytes
        return
    }
    $top = Get-OtterProfileFunction -Profile $Profile -Name $stack[$stack.Count - 1]
    $top.SelfTicks += $Ticks
    $top.SelfCpuTicks += $CpuTicks
    $top.SelfAllocatedBytes += $AllocatedBytes
    # Total counts each distinct function once, so recursion is not double-counted.
    foreach ($name in ($stack | Select-Object -Unique)) {
        $f = Get-OtterProfileFunction -Profile $Profile -Name $name
        $f.TotalTicks += $Ticks
        $f.TotalCpuTicks += $CpuTicks
        $f.TotalAllocatedBytes += $AllocatedBytes
    }
}

function ConvertTo-OtterProfileMs {
    param([long]$Ticks)
    return [Math]::Round(($Ticks * 1000.0) / [System.Diagnostics.Stopwatch]::Frequency, 2)
}

function ConvertTo-OtterCpuMs {
    param([long]$Ticks)
    return [Math]::Round($Ticks / 10000.0, 2)
}

# Returns the profile as plain data (also what the printed report is built from).
function Get-OtterProfileResult {
    [CmdletBinding()]
    param([string[]]$SourceLines = @(), [int]$Top = 10)

    $p = $script:Profile
    if ($null -eq $p) { throw 'No profile is running.' }

    # Charge the final interval to the last statement.
    $now = $p.Clock.ElapsedTicks
    $nowCpu = $p.Process.TotalProcessorTime.Ticks
    $nowAlloc = Get-OtterAllocatedBytes
    $deltaAlloc = [Math]::Max(0L, ($nowAlloc - $p.LastAllocatedBytes))
    $p.LastAllocatedBytes = $nowAlloc
    Add-OtterProfileInterval -Profile $p -Ticks ($now - $p.LastTicks) -CpuTicks ($nowCpu - $p.LastCpuTicks) -AllocatedBytes $deltaAlloc
    $p.LastTicks = $now
    $p.LastCpuTicks = $nowCpu
    $p.Clock.Stop()

    $totalMs = ConvertTo-OtterProfileMs -Ticks $p.Clock.ElapsedTicks
    $totalCpuTicks = $p.Process.TotalProcessorTime.Ticks - $p.StartCpuTicks
    $userCpuTicks = $p.Process.UserProcessorTime.Ticks - $p.StartUserTicks
    $kernelCpuTicks = $p.Process.PrivilegedProcessorTime.Ticks - $p.StartKernelTicks

    $totalCpuMs = ConvertTo-OtterCpuMs -Ticks $totalCpuTicks
    $userCpuMs = ConvertTo-OtterCpuMs -Ticks $userCpuTicks
    $kernelCpuMs = ConvertTo-OtterCpuMs -Ticks $kernelCpuTicks
    $cpuUtilization = if ($totalMs -gt 0) { [Math]::Round(($totalCpuMs / $totalMs) * 100.0, 1) } else { 0.0 }

    # Memory and allocation metrics
    $p.Process.Refresh()
    $endManaged = [System.GC]::GetTotalMemory($false)
    if ($endManaged -gt $p.PeakManagedBytes) { $p.PeakManagedBytes = $endManaged }
    $peakManagedBytes = $p.PeakManagedBytes
    $managedDeltaBytes = $endManaged - $p.StartManagedBytes
    $totalAllocatedBytes = [Math]::Max(0L, ($nowAlloc - $p.StartAllocatedBytes))
    $workingSetBytes = $p.Process.WorkingSet64
    $peakWorkingSetBytes = $p.Process.PeakWorkingSet64
    $workingSetDeltaBytes = $workingSetBytes - $p.StartWsBytes
    $gen0Collections = [System.GC]::CollectionCount(0) - $p.StartGen0
    $gen1Collections = [System.GC]::CollectionCount(1) - $p.StartGen1
    $gen2Collections = [System.GC]::CollectionCount(2) - $p.StartGen2

    $functions = foreach ($name in $p.Functions.Keys) {
        $f = $p.Functions[$name]
        [pscustomobject]@{
            Function            = $name
            Calls               = $f.Calls
            TotalMs             = ConvertTo-OtterProfileMs -Ticks $f.TotalTicks
            SelfMs              = ConvertTo-OtterProfileMs -Ticks $f.SelfTicks
            TotalCpuMs          = ConvertTo-OtterCpuMs -Ticks $f.TotalCpuTicks
            SelfCpuMs           = ConvertTo-OtterCpuMs -Ticks $f.SelfCpuTicks
            TotalAllocatedBytes = $f.TotalAllocatedBytes
            SelfAllocatedBytes  = $f.SelfAllocatedBytes
            Allocated           = Format-OtterProfileBytes $f.TotalAllocatedBytes
        }
    }
    $lines = foreach ($number in $p.Lines.Keys) {
        $l = $p.Lines[$number]
        $text = if ($number -ge 1 -and $number -le $SourceLines.Count) { $SourceLines[$number - 1].Trim() } else { '' }
        [pscustomobject]@{
            Line           = $number
            Hits           = $l.Hits
            SelfMs         = ConvertTo-OtterProfileMs -Ticks $l.Ticks
            CpuMs          = ConvertTo-OtterCpuMs -Ticks $l.CpuTicks
            AllocatedBytes = $l.AllocatedBytes
            Allocated      = Format-OtterProfileBytes $l.AllocatedBytes
            Source         = $text
        }
    }

    return [pscustomobject]@{
        TotalMs                 = $totalMs
        TotalCpuMs              = $totalCpuMs
        UserCpuMs               = $userCpuMs
        KernelCpuMs             = $kernelCpuMs
        CpuUtilization          = $cpuUtilization
        PeakManagedBytes        = $peakManagedBytes
        PeakManagedFormatted    = Format-OtterProfileBytes $peakManagedBytes
        ManagedDeltaBytes       = $managedDeltaBytes
        ManagedDeltaFormatted   = Format-OtterProfileBytes $managedDeltaBytes
        TotalAllocatedBytes     = $totalAllocatedBytes
        TotalAllocatedFormatted = Format-OtterProfileBytes $totalAllocatedBytes
        WorkingSetBytes         = $workingSetBytes
        WorkingSetFormatted     = Format-OtterProfileBytes $workingSetBytes
        PeakWorkingSetBytes     = $peakWorkingSetBytes
        PeakWorkingSetFormatted = Format-OtterProfileBytes $peakWorkingSetBytes
        WorkingSetDeltaBytes    = $workingSetDeltaBytes
        WorkingSetDeltaFormatted= Format-OtterProfileBytes $workingSetDeltaBytes
        Gen0Collections         = $gen0Collections
        Gen1Collections         = $gen1Collections
        Gen2Collections         = $gen2Collections
        MainMs                  = ConvertTo-OtterProfileMs -Ticks $p.MainTicks
        MainCpuMs               = ConvertTo-OtterCpuMs -Ticks $p.MainCpuTicks
        MainAllocatedBytes      = $p.MainAllocatedBytes
        Statements              = $p.Statements
        Functions               = @($functions | Sort-Object -Property TotalMs -Descending | Select-Object -First $Top)
        Lines                   = @($lines | Sort-Object -Property SelfMs -Descending | Select-Object -First $Top)
    }
}

function Write-OtterProfileReport {
    [CmdletBinding()]
    param([string[]]$SourceLines = @(), [int]$Top = 10)

    $r = Get-OtterProfileResult -SourceLines $SourceLines -Top $Top
    Set-OtterStatementHook -Hook $null

    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor Cyan
    Write-Host 'Otter profile' -ForegroundColor Cyan
    Write-Host ('=' * 60) -ForegroundColor Cyan
    Write-Host ("{0} statements run in {1} ms (CPU: {2} ms, {3}% utilization; user: {4} ms, kernel: {5} ms)" -f $r.Statements, $r.TotalMs, $r.TotalCpuMs, $r.CpuUtilization, $r.UserCpuMs, $r.KernelCpuMs)
    Write-Host ("Memory: managed peak {0} (delta {1}), working set peak {2}; allocated: {3}; GC: {4} gen0, {5} gen1, {6} gen2" -f $r.PeakManagedFormatted, $r.ManagedDeltaFormatted, $r.PeakWorkingSetFormatted, $r.TotalAllocatedFormatted, $r.Gen0Collections, $r.Gen1Collections, $r.Gen2Collections)
    Write-Host '(profiling adds overhead to every statement - read the shape, not the absolute times)' -ForegroundColor DarkGray

    Write-Host ''
    Write-Host 'Functions (by total time)' -ForegroundColor Yellow
    if ($r.Functions.Count -eq 0) {
        Write-Host '  (no functions were called)' -ForegroundColor DarkGray
    } else {
        Write-Host ('  {0,-24} {1,8} {2,11} {3,10} {4,10} {5,10}' -f 'function', 'calls', 'total ms', 'self ms', 'cpu ms', 'alloc')
        foreach ($f in $r.Functions) {
            Write-Host ('  {0,-24} {1,8} {2,11} {3,10} {4,10} {5,10}' -f $f.Function, $f.Calls, $f.TotalMs, $f.SelfMs, $f.TotalCpuMs, $f.Allocated)
        }
    }

    Write-Host ''
    Write-Host 'Hottest lines (by self time)' -ForegroundColor Yellow
    Write-Host ('  {0,5} {1,8} {2,10} {3,10} {4,10}  {5}' -f 'line', 'hits', 'self ms', 'cpu ms', 'alloc', 'source')
    foreach ($l in $r.Lines) {
        $src = if ($l.Source.Length -gt 45) { $l.Source.Substring(0, 42) + '...' } else { $l.Source }
        Write-Host ('  {0,5} {1,8} {2,10} {3,10} {4,10}  {5}' -f $l.Line, $l.Hits, $l.SelfMs, $l.CpuMs, $l.Allocated, $src)
    }
    Write-Host ''
}


Export-ModuleMember -Function Start-OtterProfile, Get-OtterProfileResult, Write-OtterProfileReport, Format-OtterProfileBytes
