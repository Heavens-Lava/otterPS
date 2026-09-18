# tools/Test-OtterPerformanceGate.ps1
#
# Performance Regression Gate for Otter 1.0 Release Candidates.
# Establishes a repeatable methodology comparing against established baselines
# without brittle micro-benchmarking or arbitrary hard failure thresholds.
#
# Flags major regressions (> 3.0x baseline duration) for investigation.

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$otterCmd = Join-Path $repoRoot 'otter.cmd'
$scratchDir = Join-Path $repoRoot 'scratch\perf_gate'

if (Test-Path -LiteralPath $scratchDir) {
    Remove-Item -LiteralPath $scratchDir -Recurse -Force
}
New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null

$baselines = @(
    @{
        Name = "Parse 1,000 Statements"
        BaselineMs = 1885.89
        ThresholdMultiplier = 3.0
        Action = {
            $sb = [System.Text.StringBuilder]::new()
            for ($i = 1; $i -le 1000; $i++) { [void]$sb.AppendLine("x$i is $i") }
            $f = Join-Path $scratchDir "p1k.ot"
            Set-Content -LiteralPath $f -Value $sb.ToString() -Encoding utf8
            & $otterCmd check $f | Out-Null
        }
    },
    @{
        Name = "Parse 5,000 Statements"
        BaselineMs = 12571.81
        ThresholdMultiplier = 3.0
        Action = {
            $sb = [System.Text.StringBuilder]::new()
            for ($i = 1; $i -le 5000; $i++) { [void]$sb.AppendLine("x$i is $i") }
            $f = Join-Path $scratchDir "p5k.ot"
            Set-Content -LiteralPath $f -Value $sb.ToString() -Encoding utf8
            & $otterCmd check $f | Out-Null
        }
    },
    @{
        Name = "Arithmetic & Branching Loop (1,000 iters)"
        BaselineMs = 717.17
        ThresholdMultiplier = 3.0
        Action = {
            $src = @"
total is 0
count from 1 to 1000 as i
    if i is greater than 500
        total is total plus 2
    otherwise
        total is total plus 1
    .
.
"@
            $f = Join-Path $scratchDir "loop.ot"
            Set-Content -LiteralPath $f -Value $src -Encoding utf8
            & $otterCmd run $f | Out-Null
        }
    },
    @{
        Name = "List Creation & Mutation (500 items)"
        BaselineMs = 704.20
        ThresholdMultiplier = 3.0
        Action = {
            $src = @"
items are empty
count from 1 to 500 as i
    add i to items
.
"@
            $f = Join-Path $scratchDir "list.ot"
            Set-Content -LiteralPath $f -Value $src -Encoding utf8
            & $otterCmd run $f | Out-Null
        }
    },
    @{
        Name = "Web Target Compilation"
        BaselineMs = 973.29
        ThresholdMultiplier = 3.0
        Action = {
            $src = @"
app is a page
    title is "Gate App"
.
b is a button
    text is "Click"
.
show app
"@
            $f = Join-Path $scratchDir "web.ot"
            Set-Content -LiteralPath $f -Value $src -Encoding utf8
            & $otterCmd web $f | Out-Null
            $html = Join-Path $scratchDir "web.html"
            Remove-Item -LiteralPath $html -Force -ErrorAction SilentlyContinue
        }
    }
)

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Otter 1.0 RC - Performance Regression Gate" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$gateResults = [System.Collections.Generic.List[PSObject]]::new()
$regressions = 0

foreach ($b in $baselines) {
    Write-Host "Evaluating: $($b.Name)... " -NoNewline

    # Warmup
    try { & $b.Action } catch {}

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $b.Action
    $sw.Stop()
    $actualMs = [Math]::Round($sw.Elapsed.TotalMilliseconds, 2)

    $maxAllowed = [Math]::Round(($b.BaselineMs * $b.ThresholdMultiplier), 2)
    $ratio = [Math]::Round(($actualMs / $b.BaselineMs), 2)

    $isRegression = ($actualMs -gt $maxAllowed)
    $status = if ($isRegression) { "REGRESSION" } else { "STABLE" }

    if ($isRegression) {
        $regressions++
        Write-Host "$actualMs ms (Baseline: $($b.BaselineMs) ms, Ratio: ${ratio}x) - [INVESTIGATE]" -ForegroundColor Red
    } else {
        Write-Host "$actualMs ms (Baseline: $($b.BaselineMs) ms, Ratio: ${ratio}x) - [PASS]" -ForegroundColor Green
    }

    $gateResults.Add([PSCustomObject]@{
        Benchmark = $b.Name
        BaselineMs = $b.BaselineMs
        ActualMs = $actualMs
        Ratio = $ratio
        ThresholdMultiplier = $b.ThresholdMultiplier
        Status = $status
    })
}

Remove-Item -LiteralPath $scratchDir -Recurse -Force -ErrorAction SilentlyContinue

# Write Gate Report
$reportPath = Join-Path $repoRoot 'docs\PERFORMANCE_REGRESSION_GATE.md'
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Otter 1.0 - Performance Regression Gate Report')
$lines.Add('')
$lines.Add('## Methodology & Philosophy')
$lines.Add('Rather than asserting brittle micro-benchmarks that fluctuate with host CPU throttling, this regression gate:')
$lines.Add('1. Compares observed execution durations against verified v1.0.0-rc.1 baselines.')
$lines.Add('2. Enforces a 3.0x threshold multiplier to detect true algorithmic regressions ($O(N^2)$ traps, unbounded allocations) while absorbing ordinary system noise.')
$lines.Add('3. Provides repeatable criteria across release candidates.')
$lines.Add('')
$lines.Add('## Benchmark Results')
$lines.Add('')
$lines.Add('| Benchmark | Baseline (ms) | Actual (ms) | Variance Ratio | Gate Status |')
$lines.Add('|---|---|---|---|---|')
foreach ($r in $gateResults) {
    $lines.Add("| $($r.Benchmark) | $($r.BaselineMs) ms | **$($r.ActualMs) ms** | $($r.Ratio)x | **$($r.Status)** |")
}
$lines.Add('')
if ($regressions -eq 0) {
    $lines.Add('### Certification: All Benchmarks Within Accepted Release Tolerances.')
} else {
    $lines.Add("### Warning: $regressions benchmark(s) exceeded the 3.0x tolerance threshold and require investigation.")
}

Set-Content -LiteralPath $reportPath -Value ($lines -join "`r`n") -Encoding utf8
Write-Host "`nRegression gate report generated at: docs/PERFORMANCE_REGRESSION_GATE.md" -ForegroundColor Green

if ($regressions -gt 0) { exit 1 }
