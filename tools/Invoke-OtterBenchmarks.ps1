using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1
using module ..\src\Otter.Interpreter.psm1
using module ..\src\Otter.Web.psm1

<#
.SYNOPSIS
    Otter performance baseline runner (see benchmarks\README.md).

.DESCRIPTION
    Runs each benchmarks\*.ot program in-process: the source is tokenised and
    parsed once, then the AST is executed repeatedly. Startup, module loading
    and parsing are therefore NOT part of the measured time.

    For each benchmark:
      1. a counting pass (untimed) counts statements executed and function
         calls made, using the interpreter's statement hook;
      2. warmup runs execute the program and are discarded;
      3. measured runs execute it with NO hook installed and are timed with a
         Stopwatch. The profiler is never active while timing.

    Reports median, minimum and maximum over the measured runs, plus
    statements/second and function calls/second derived from the MEDIAN.

    -Startup measures process startup separately (spawns otter.ps1).
    -Compile times the web compiler (otter web) on each program and on
    examples\v1\tasks.ot; parsing is not included.
    -Http times benchmarks\http\http_get.ot, 50 requests to a local Otter
    web server (benchmarks\http\server.ot) that the runner starts with
    otter serve and stops afterwards.
    -Ui times benchmarks\ui\*.ot, which build desktop controls in-process
    (Windows only; skipped elsewhere).
    -All turns on every section.

.EXAMPLE
    powershell -NoProfile -File tools\Invoke-OtterBenchmarks.ps1
    powershell -NoProfile -File tools\Invoke-OtterBenchmarks.ps1 -Only function_calls -Runs 9
    powershell -NoProfile -File tools\Invoke-OtterBenchmarks.ps1 -Startup -Json benchmarks\results\baseline.json
#>
[CmdletBinding()]
param(
    [int]$Runs = 5,
    [int]$Warmup = 1,
    [string[]]$Only = @(),
    [switch]$Startup,
    [int]$StartupRuns = 5,
    [switch]$Compile,
    [switch]$Http,
    [switch]$Ui,
    [switch]$All,
    [string]$Json = ''
)
if ($All) { $Startup = $true; $Compile = $true; $Http = $true; $Ui = $true }

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$benchDir = Join-Path $repoRoot 'benchmarks'

function Get-Median {
    param([double[]]$Values)
    $sorted = $Values | Sort-Object
    $n = $sorted.Count
    if ($n -eq 0) { return 0.0 }
    if ($n % 2 -eq 1) { return [double]$sorted[($n - 1) / 2] }
    return ([double]$sorted[$n / 2 - 1] + [double]$sorted[$n / 2]) / 2.0
}

function Get-OtterHostInfo {
    $versionFile = Join-Path $repoRoot 'VERSION'
    $otterVersion = if (Test-Path -LiteralPath $versionFile) { ([System.IO.File]::ReadAllText($versionFile)).Trim() } else { 'unknown' }
    $cpu = try { (Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name } catch { 'unknown' }
    return [ordered]@{
        OtterVersion      = $otterVersion
        GitCommit         = $(try { (& git -C $repoRoot rev-parse --short HEAD 2>$null) } catch { 'unknown' })
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        PowerShellEdition = [string]$PSVersionTable.PSEdition
        OperatingSystem   = [System.Environment]::OSVersion.VersionString
        Processor         = ([string]$cpu).Trim()
        LogicalCores      = [System.Environment]::ProcessorCount
        MeasuredRuns      = $Runs
        WarmupRuns        = $Warmup
        Date              = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    }
}

# Counts statements and function calls for one full run. Untimed; the hook is
# removed again before anything is measured.
function Measure-OtterWorkload {
    param($Ast, [string[]]$SourceLines)

    $state = @{ Statements = 0L; Calls = 0L; Frames = @{} }
    $hook = {
        param($Statement, $Environment, $CallStack)
        $state.Statements++
        for ($i = 0; $i -lt $CallStack.Count; $i++) {
            if (-not [object]::ReferenceEquals($state.Frames[$i], $CallStack[$i])) {
                $state.Frames[$i] = $CallStack[$i]
                $state.Calls++
            }
        }
        foreach ($depth in @($state.Frames.Keys)) {
            if ($depth -ge $CallStack.Count) { $state.Frames.Remove($depth) }
        }
    }.GetNewClosure()

    Set-OtterStatementHook -Hook $hook
    try {
        Invoke-OtterProgram -Program $Ast -Environment (New-OtterEnvironment) -SourceLines $SourceLines
    }
    finally {
        Set-OtterStatementHook -Hook $null
    }
    return [pscustomobject]@{ Statements = $state.Statements; Calls = $state.Calls }
}

# Times $Action over warmup + measured runs; returns median/min/max in ms.
function Measure-OtterRuns {
    param([scriptblock]$Action)
    for ($w = 0; $w -lt $Warmup; $w++) { & $Action }
    $times = New-Object System.Collections.Generic.List[double]
    for ($r = 0; $r -lt $Runs; $r++) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        & $Action
        $stopwatch.Stop()
        $times.Add($stopwatch.Elapsed.TotalMilliseconds)
    }
    $median = Get-Median -Values $times.ToArray()
    return [ordered]@{
        MedianMs = [Math]::Round($median, 2)
        MinMs    = [Math]::Round(($times | Measure-Object -Minimum).Minimum, 2)
        MaxMs    = [Math]::Round(($times | Measure-Object -Maximum).Maximum, 2)
        RunsMs   = @($times | ForEach-Object { [Math]::Round($_, 2) })
    }
}

function Write-OtterSectionRow {
    param([string]$Name, $Result, [string]$Extra = '')
    Write-Host ('  {0,-24} median {1,9:N1} ms   min {2,9:N1}   max {3,9:N1}   {4}' -f $Name, $Result.MedianMs, $Result.MinMs, $Result.MaxMs, $Extra)
}

function Read-OtterAst {
    param([string]$Path)
    $source = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    return [pscustomobject]@{ Ast = (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $source)); Lines = ($source -split "`r?`n") }
}

$hostInfo = Get-OtterHostInfo
Write-Host ''
Write-Host ('=' * 78) -ForegroundColor Cyan
Write-Host "Otter benchmarks - Otter $($hostInfo.OtterVersion), PowerShell $($hostInfo.PowerShellVersion) ($($hostInfo.PowerShellEdition))" -ForegroundColor Cyan
Write-Host "$($hostInfo.OperatingSystem); $($hostInfo.LogicalCores) logical cores; $($hostInfo.Processor)"
Write-Host "$Runs measured runs after $Warmup warmup run(s); median / min / max of measured runs"
Write-Host ('=' * 78) -ForegroundColor Cyan

$files = Get-ChildItem -LiteralPath $benchDir -Filter '*.ot' | Sort-Object Name
# `-File` passes `a,b` as ONE string, so accept comma-separated names too.
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if ($Only.Count -gt 0) { $files = $files | Where-Object { $Only -contains $_.BaseName } }
if ($files.Count -eq 0) { throw "No benchmark programs matched in $benchDir." }

# Programs run with a temporary working folder so file benchmarks never touch the repo.
$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_bench_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
$originalLocation = Get-Location

$results = New-Object System.Collections.Generic.List[object]
$header = '{0,-16} {1,9} {2,9} {3,9} {4,8} {5,8} {6,9} {7,9}' -f 'benchmark', 'median ms', 'min ms', 'max ms', 'stmts', 'calls', 'stmts/s', 'calls/s'
Write-Host ''
Write-Host $header -ForegroundColor Yellow

try {
    Set-Location -LiteralPath $workDir
    Set-OtterOutputWriter -Writer { param($text) }

    foreach ($file in $files) {
        $source = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        $sourceLines = $source -split "`r?`n"
        $ast = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $source)

        try {
            $counts = Measure-OtterWorkload -Ast $ast -SourceLines $sourceLines

            for ($w = 0; $w -lt $Warmup; $w++) {
                Invoke-OtterProgram -Program $ast -Environment (New-OtterEnvironment) -SourceLines $sourceLines
            }

            $times = New-Object System.Collections.Generic.List[double]
            for ($r = 0; $r -lt $Runs; $r++) {
                $environment = New-OtterEnvironment
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                Invoke-OtterProgram -Program $ast -Environment $environment -SourceLines $sourceLines
                $stopwatch.Stop()
                $times.Add($stopwatch.Elapsed.TotalMilliseconds)
            }
        }
        catch {
            Write-Host ('{0,-16} FAILED: {1}' -f $file.BaseName, $_.Exception.Message) -ForegroundColor Red
            $results.Add([ordered]@{ Benchmark = $file.BaseName; Failed = $_.Exception.Message })
            continue
        }

        $median = Get-Median -Values $times.ToArray()
        $min = ($times | Measure-Object -Minimum).Minimum
        $max = ($times | Measure-Object -Maximum).Maximum
        $stmtsPerSecond = if ($median -gt 0) { [Math]::Round($counts.Statements / ($median / 1000.0)) } else { 0 }
        $callsPerSecond = if ($median -gt 0 -and $counts.Calls -gt 0) { [Math]::Round($counts.Calls / ($median / 1000.0)) } else { 0 }
        $callsText = if ($counts.Calls -gt 0) { [string]$callsPerSecond } else { '-' }

        Write-Host ('{0,-16} {1,9:N1} {2,9:N1} {3,9:N1} {4,8} {5,8} {6,9} {7,9}' -f `
            $file.BaseName, $median, $min, $max, $counts.Statements, $counts.Calls, $stmtsPerSecond, $callsText)

        $results.Add([ordered]@{
            Benchmark        = $file.BaseName
            MedianMs         = [Math]::Round($median, 2)
            MinMs            = [Math]::Round($min, 2)
            MaxMs            = [Math]::Round($max, 2)
            RunsMs           = @($times | ForEach-Object { [Math]::Round($_, 2) })
            Statements       = $counts.Statements
            FunctionCalls    = $counts.Calls
            StatementsPerSec = $stmtsPerSecond
            CallsPerSec      = $callsPerSecond
        })
    }
}
finally {
    Set-OtterOutputWriter -Writer $null
    Set-Location -LiteralPath $originalLocation
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- startup: a separate benchmark, never mixed into the ones above ------------

$startupResults = $null
if ($Startup) {
    Write-Host ''
    Write-Host 'Startup (separate process per run; includes PowerShell start, module load, parse, run)' -ForegroundColor Yellow
    $hello = Join-Path $repoRoot 'examples\hello.ot'
    $hostExe = (Get-Process -Id $PID).Path
    $startupResults = [ordered]@{}
    foreach ($case in @(
            @{ Name = 'otter --version'; Args = @('--version') },
            @{ Name = 'otter run hello.ot'; Args = @('run', $hello) })) {
        $times = New-Object System.Collections.Generic.List[double]
        for ($r = 0; $r -lt ($StartupRuns + 1); $r++) {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            & $hostExe -NoProfile -File (Join-Path $repoRoot 'otter.ps1') @($case.Args) *> $null
            $stopwatch.Stop()
            if ($r -gt 0) { $times.Add($stopwatch.Elapsed.TotalMilliseconds) }   # first run is warmup
        }
        $median = Get-Median -Values $times.ToArray()
        $min = ($times | Measure-Object -Minimum).Minimum
        $max = ($times | Measure-Object -Maximum).Maximum
        Write-Host ('  {0,-22} median {1,8:N0} ms   min {2,8:N0}   max {3,8:N0}   ({4} runs)' -f $case.Name, $median, $min, $max, $StartupRuns)
        $startupResults[$case.Name] = [ordered]@{ MedianMs = [Math]::Round($median); MinMs = [Math]::Round($min); MaxMs = [Math]::Round($max); Runs = $StartupRuns }
    }
}

# --- compile: the web compiler, parse excluded ------------------------------------

$compileResults = $null
if ($Compile) {
    Write-Host ''
    Write-Host 'Compile (otter web: AST to a standalone page; parsing not included)' -ForegroundColor Yellow
    $compileResults = [ordered]@{}
    $targets = @(Get-ChildItem -LiteralPath $benchDir -Filter '*.ot' | Sort-Object Name | ForEach-Object { $_.FullName })
    $targets += (Join-Path $repoRoot 'examples\v1\tasks.ot')
    foreach ($path in $targets) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($path)
        try {
            $parsed = Read-OtterAst -Path $path
            $result = Measure-OtterRuns -Action { $null = ConvertTo-OtterWeb -Program $parsed.Ast }.GetNewClosure()
            Write-OtterSectionRow -Name $name -Result $result
            $compileResults[$name] = $result
        } catch {
            if ($_.Exception.Message -match 'not supported on the web target') {
                # A console-only program (UDP, for example): the web compiler
                # refuses it by design, so there is nothing to time.
                Write-Host ('  {0,-24} skipped: {1}' -f $name, $_.Exception.Message)
                $compileResults[$name] = [ordered]@{ Skipped = $_.Exception.Message }
            } else {
                Write-Host ('  {0,-24} FAILED: {1}' -f $name, $_.Exception.Message) -ForegroundColor Red
                $compileResults[$name] = [ordered]@{ Failed = $_.Exception.Message }
            }
        }
    }
}

# --- http: an Otter client against an Otter server (otter serve) ---------------------

$httpResults = $null
if ($Http) {
    Write-Host ''
    Write-Host 'HTTP (benchmarks\http\http_get.ot: 50 GETs to otter serve benchmarks\http\server.ot)' -ForegroundColor Yellow
    $httpResults = [ordered]@{}
    $hostExe = (Get-Process -Id $PID).Path
    $serverArgs = @('-NoProfile', '-File', (Join-Path $repoRoot 'otter.ps1'), 'serve', (Join-Path $benchDir 'http\server.ot'))
    $server = Start-Process -FilePath $hostExe -ArgumentList $serverArgs -PassThru -WindowStyle Hidden
    try {
        $ready = $false
        for ($i = 0; $i -lt 60 -and -not $ready; $i++) {
            Start-Sleep -Milliseconds 500
            try { $ready = ((Invoke-WebRequest -Uri 'http://localhost:47392/ping' -UseBasicParsing -TimeoutSec 2).Content -eq 'pong') } catch { }
        }
        if (-not $ready) { throw 'the benchmark server did not answer on port 47392' }
        $parsed = Read-OtterAst -Path (Join-Path $benchDir 'http\http_get.ot')
        Set-OtterOutputWriter -Writer { param($text) }
        try {
            $result = Measure-OtterRuns -Action { Invoke-OtterProgram -Program $parsed.Ast -Environment (New-OtterEnvironment) -SourceLines $parsed.Lines }.GetNewClosure()
        } finally { Set-OtterOutputWriter -Writer $null }
        Write-OtterSectionRow -Name 'http_get (50 requests)' -Result $result -Extra ('{0:N1} ms per request' -f ($result.MedianMs / 50))
        $httpResults['http_get'] = $result
    } catch {
        Write-Host "  http_get FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $httpResults['http_get'] = [ordered]@{ Failed = $_.Exception.Message }
    } finally {
        if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
    }
}

# --- ui: desktop controls built in-process (Windows) -------------------------------

$uiResults = $null
if ($Ui) {
    Write-Host ''
    Write-Host 'UI (benchmarks\ui\*.ot: desktop controls created, configured and placed; never shown)' -ForegroundColor Yellow
    $uiResults = [ordered]@{}
    $onWindows = ($PSVersionTable.PSEdition -ne 'Core') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
    foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $benchDir 'ui') -Filter '*.ot' | Sort-Object Name)) {
        if (-not $onWindows) {
            Write-Host ('  {0,-24} skipped: desktop controls need Windows' -f $file.BaseName)
            $uiResults[$file.BaseName] = [ordered]@{ Skipped = 'desktop controls need Windows' }
            continue
        }
        try {
            $parsed = Read-OtterAst -Path $file.FullName
            Set-OtterOutputWriter -Writer { param($text) }
            try {
                $result = Measure-OtterRuns -Action { Invoke-OtterProgram -Program $parsed.Ast -Environment (New-OtterEnvironment) -SourceLines $parsed.Lines }.GetNewClosure()
            } finally { Set-OtterOutputWriter -Writer $null }
            Write-OtterSectionRow -Name $file.BaseName -Result $result
            $uiResults[$file.BaseName] = $result
        } catch {
            Write-Host ('  {0,-24} FAILED: {1}' -f $file.BaseName, $_.Exception.Message) -ForegroundColor Red
            $uiResults[$file.BaseName] = [ordered]@{ Failed = $_.Exception.Message }
        }
    }
}

Write-Host ''
if ($Json) {
    $jsonPath = if ([System.IO.Path]::IsPathRooted($Json)) { $Json } else { Join-Path $repoRoot $Json }
    $jsonDir = Split-Path -Parent $jsonPath
    if ($jsonDir -and -not (Test-Path -LiteralPath $jsonDir)) { New-Item -ItemType Directory -Path $jsonDir -Force | Out-Null }
    $document = [ordered]@{ Host = $hostInfo; Benchmarks = $results.ToArray(); Startup = $startupResults; Compile = $compileResults; Http = $httpResults; Ui = $uiResults }
    [System.IO.File]::WriteAllText($jsonPath, ($document | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
    Write-Host "Results written to $jsonPath"
}
$failureCount = @($results | Where-Object { $_.Contains('Failed') }).Count
foreach ($section in @($compileResults, $httpResults, $uiResults)) {
    if ($null -eq $section) { continue }
    foreach ($key in @($section.Keys)) { if ($section[$key].Contains('Failed')) { $failureCount++ } }
}
if ($failureCount -gt 0) { exit 1 }
exit 0
