# tools/Test-ResourceSoak.ps1
#
# Memory & Resource Soak Test Suite for Otter 1.0 RC.
# Tests 8 distinct repeated workloads for resource leaks:
# 1. Parse same program 1,000 times
# 2. Execute representative programs repeatedly (1,000 times)
# 3. Compile web output repeatedly (200 times)
# 4. Repeated file reads/writes (500 times)
# 5. Repeated command execution (50 times)
# 6. Repeated JSON conversions (500 times)
# 7. Repeated function calls (5,000 times)
# 8. Repeated failures/diagnostics (500 times)
#
# Tracks WorkingSet64 and PrivateMemorySize64 before, during, and after,
# verifying that memory plateaus and resources (handles, temp files) do not leak.

using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1
using module ..\src\Otter.Interpreter.psm1
using module ..\src\Otter.Web.psm1

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tempDir = Join-Path $repoRoot 'scratch\soak_temp'

if (Test-Path -LiteralPath $tempDir) {
    Remove-Item -LiteralPath $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$startHandles = [System.Diagnostics.Process]::GetCurrentProcess().HandleCount

function Get-MemorySnapshot {
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
    $proc = [System.Diagnostics.Process]::GetCurrentProcess()
    $proc.Refresh()
    return [PSCustomObject]@{
        WorkingSetMB = [Math]::Round(($proc.WorkingSet64 / 1MB), 2)
        PrivateMB    = [Math]::Round(($proc.PrivateMemorySize64 / 1MB), 2)
    }
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Otter 1.0 RC - Memory and Resource Soak Suite" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$soakResults = [System.Collections.Generic.List[PSObject]]::new()

function Run-SoakWorkload {
    param(
        [string]$Name,
        [int]$Iterations,
        [scriptblock]$Action
    )

    Write-Host "`nRunning soak test: $Name ($Iterations iterations)..." -ForegroundColor Yellow
    $startMem = Get-MemorySnapshot
    $midMem = $null
    $halfway = [int]($Iterations / 2)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    for ($i = 1; $i -le $Iterations; $i++) {
        & $Action $i
        if ($i -eq $halfway) {
            $midMem = Get-MemorySnapshot
        }
    }

    $sw.Stop()
    $endMem = Get-MemorySnapshot
    $elapsedSec = [Math]::Round($sw.Elapsed.TotalSeconds, 2)

    # Calculate growth from midpoint to end (identifies true unbounded leakage vs initial JIT/pool warm-up)
    $workingSetDiff = [Math]::Round(($endMem.WorkingSetMB - $startMem.WorkingSetMB), 2)
    $privateDiff = [Math]::Round(($endMem.PrivateMB - $startMem.PrivateMB), 2)
    $midToEndDiff = if ($null -ne $midMem) { [Math]::Round(($endMem.PrivateMB - $midMem.PrivateMB), 2) } else { 0 }

    # An unbounded leak would show continued linear growth between midpoint and end
    $status = if ($midToEndDiff -gt 25.0) { "INVESTIGATE" } else { "STABLE" }

    Write-Host ("  Start: {0,6} MB priv | Mid: {1,6} MB priv | End: {2,6} MB priv | Delta: {3,6} MB | {4} ({5}s)" -f `
        $startMem.PrivateMB, $(if ($midMem) { $midMem.PrivateMB } else { "-" }), $endMem.PrivateMB, $privateDiff, $status, $elapsedSec)

    $soakResults.Add([PSCustomObject]@{
        Workload = $Name
        Iterations = $Iterations
        StartPrivateMB = $startMem.PrivateMB
        MidPrivateMB = if ($midMem) { $midMem.PrivateMB } else { $startMem.PrivateMB }
        EndPrivateMB = $endMem.PrivateMB
        DeltaPrivateMB = $privateDiff
        MidToEndDeltaMB = $midToEndDiff
        ElapsedSec = $elapsedSec
        Status = $status
    })
}

# 1. Parse same program 1,000 times
$parseSource = @"
name is "Otter"
count from 1 to 50 as i
    if i is greater than 25
        say "halfway"
    otherwise
        say i
    .
.
100 and 200 make result
"@

Run-SoakWorkload "1. Parse 1,000x" 1000 {
    $tokens = ConvertTo-OtterTokens -Source $parseSource
    $ast = ConvertTo-OtterAst -Tokens $tokens
}

# 2. Execute representative programs repeatedly 1,000 times
$execProgramSource = @"
s is 0
count from 1 to 20 as j
    s is s plus j
.
"@
$execTokens = ConvertTo-OtterTokens -Source $execProgramSource
$execAst = ConvertTo-OtterAst -Tokens $execTokens
$execLines = $execProgramSource -split "`r?`n"

Run-SoakWorkload "2. Execute Program 1,000x" 1000 {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Program $execAst -Environment $env -SourceLines $execLines
}

# 3. Compile web output repeatedly (200 times)
$webSource = @"
app is a page
    title is "Soak App"
.
lbl is a text
    text is "Ready"
.
btn is a button
    text is "Go"
.
when btn is clicked
    text of lbl is "Done"
.
put lbl, btn in app
show app
"@
$webTokens = ConvertTo-OtterTokens -Source $webSource
$webAst = ConvertTo-OtterAst -Tokens $webTokens

Run-SoakWorkload "3. Web Compile 200x" 200 {
    $null = ConvertTo-OtterWeb -Program $webAst
}

# 4. Repeated file reads/writes (500 times)
$ioSourceTemplate = @"
write "cycle {0}" to "scratch\soak_temp\cycle_{0}.txt"
read "scratch\soak_temp\cycle_{0}.txt" into content
delete file "scratch\soak_temp\cycle_{0}.txt"
"@

Run-SoakWorkload "4. File Read/Write 500x" 500 {
    param($idx)
    $src = $ioSourceTemplate -f $idx
    $tokens = ConvertTo-OtterTokens -Source $src
    $ast = ConvertTo-OtterAst -Tokens $tokens
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Program $ast -Environment $env -SourceLines ($src -split "`r?`n")
}

# 5. Repeated command execution (50 times)
$cmdSource = @"
run command "powershell -NoProfile -Command exit 0" into procRes
"@
$cmdTokens = ConvertTo-OtterTokens -Source $cmdSource
$cmdAst = ConvertTo-OtterAst -Tokens $cmdTokens
$cmdLines = $cmdSource -split "`r?`n"

Run-SoakWorkload "5. Run Command 50x" 50 {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Program $cmdAst -Environment $env -SourceLines $cmdLines
}

# 6. Repeated JSON conversions (500 times)
$jsonSource = @"
data is "{ \"user\": \"Otter\", \"id\": 101, \"roles\": [\"admin\", \"dev\"], \"nested\": { \"ok\": true } }"
convert data from json into obj
convert obj to json into serialized
"@
$jsonTokens = ConvertTo-OtterTokens -Source $jsonSource
$jsonAst = ConvertTo-OtterAst -Tokens $jsonTokens
$jsonLines = $jsonSource -split "`r?`n"

Run-SoakWorkload "6. JSON Convert 500x" 500 {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Program $jsonAst -Environment $env -SourceLines $jsonLines
}

# 7. Repeated function calls (5,000 times)
$fnSource = @"
to inc n
    return n plus 1
.
inc 1 make val
"@
$fnTokens = ConvertTo-OtterTokens -Source $fnSource
$fnAst = ConvertTo-OtterAst -Tokens $fnTokens
$fnLines = $fnSource -split "`r?`n"

Run-SoakWorkload "7. Function Calls 5,000x" 5000 {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Program $fnAst -Environment $env -SourceLines $fnLines
}

# 8. Repeated failures/diagnostics (500 times)
Run-SoakWorkload "8. Failures & Diagnostics 500x" 500 {
    # 250 syntax/lexer errors
    try {
        $null = ConvertTo-OtterTokens -Source "say `""
    } catch {}

    # 250 runtime errors
    try {
        $errSrc = "x is missingVar plus 1"
        $errTokens = ConvertTo-OtterTokens -Source $errSrc
        $errAst = ConvertTo-OtterAst -Tokens $errTokens
        $env = New-OtterEnvironment
        Invoke-OtterProgram -Program $errAst -Environment $env -SourceLines ($errSrc -split "`r?`n")
    } catch {}
}

# Measured leak checks, before cleaning up: files the workloads left behind,
# child processes still running, and this process's handle count.
$leftFiles = @(Get-ChildItem -LiteralPath $tempDir -Recurse -File -ErrorAction SilentlyContinue)
$children = @(Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId=$PID" -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'conhost.exe' })
[System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers(); [System.GC]::Collect()
$endProc = [System.Diagnostics.Process]::GetCurrentProcess(); $endProc.Refresh()
$endHandles = $endProc.HandleCount

# Cleanup temp files
Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# Generate Soak Report
$soakReportPath = Join-Path $repoRoot 'docs\RESOURCE_SOAK_RESULTS.md'
$reportLines = [System.Collections.Generic.List[string]]::new()
$reportLines.Add('# Otter 1.0 - Memory & Resource Soak Report')
$reportLines.Add('')
$reportLines.Add('## Test Environment')
$reportLines.Add('- **Host**: Windows PowerShell 5.1')
$reportLines.Add("- **Date**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$reportLines.Add('')
$reportLines.Add('## Soak Workload Results')
$reportLines.Add('')
$reportLines.Add('| Workload | Iterations | Start (MB) | Mid (MB) | End (MB) | Net Delta (MB) | Mid-End Delta (MB) | Status | Duration (s) |')
$reportLines.Add('|---|---|---|---|---|---|---|---|---|')
foreach ($res in $soakResults) {
    $reportLines.Add("| $($res.Workload) | $($res.Iterations) | $($res.StartPrivateMB) | $($res.MidPrivateMB) | $($res.EndPrivateMB) | $($res.DeltaPrivateMB) | $($res.MidToEndDeltaMB) | **$($res.Status)** | $($res.ElapsedSec)s |")
}
$reportLines.Add('')
$reportLines.Add('Status: STABLE means private memory grew by at most 25 MB between the middle and the end of the workload; INVESTIGATE otherwise.')
$reportLines.Add('')
$reportLines.Add('## Measured leak checks')
$reportLines.Add("- **Files left in the soak folder by the workloads**: $($leftFiles.Count)")
$reportLines.Add("- **Child processes still running after the workloads**: $($children.Count)$(if ($children.Count) { ' (' + (($children | ForEach-Object { $_.Name }) -join ', ') + ')' })")
$reportLines.Add("- **Handles held by this process**: $startHandles before, $endHandles after (change $($endHandles - $startHandles))")

Set-Content -LiteralPath $soakReportPath -Value ($reportLines -join "`r`n") -Encoding utf8
Write-Host "`nSoak report generated at: docs/RESOURCE_SOAK_RESULTS.md" -ForegroundColor Green
