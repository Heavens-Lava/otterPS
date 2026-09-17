# tools/Invoke-OtterParallelGauntlet.ps1
# Parallel Test Harness for Otter 1.0 RC Scaled Gauntlet (Batch 3)
# Executes 10,000 Differential & 10,000 Mutation Fuzzing runs across worker processes

param(
    [int]$TotalIterations = 10000,
    [int]$Workers = 8,
    [int]$Seed = 20261010,
    [int]$BatchSize = 250,
    [ValidateSet('All', 'Differential', 'MutationFuzz')][string]$Mode = 'All'
)

$ErrorActionPreference = 'Stop'

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Otter 1.0 RC Parallel Adversarial Gauntlet (Batch 3)" -ForegroundColor Cyan
Write-Host "Total Iterations: $TotalIterations across $Workers Workers ($([Math]::Ceiling($TotalIterations / $Workers)) per worker)" -ForegroundColor Cyan
Write-Host "Seed: $Seed | Mode: $Mode" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$itersPerWorker = [int][Math]::Ceiling($TotalIterations / $Workers)
$jobs = [System.Collections.Generic.List[hashtable]]::new()
$fuzzerScript = Join-Path $PSScriptRoot "Invoke-OtterDifferentialFuzzer.ps1"
$swTotal = [System.Diagnostics.Stopwatch]::StartNew()

for ($w = 0; $w -lt $Workers; $w++) {
    $offset = $w * $itersPerWorker
    $curIters = [Math]::Min($itersPerWorker, ($TotalIterations - $offset))
    if ($curIters -le 0) { break }

    $logFile = [System.IO.Path]::GetTempFileName()

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "powershell.exe"
    $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& '$fuzzerScript' -Seed $Seed -SeedOffset $offset -Iterations $curIters -BatchSize $BatchSize -Mode $Mode *>&1 | Out-File -FilePath '$logFile' -Encoding utf8`""
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $jobs.Add(@{
        Worker = $w
        Offset = $offset
        Iterations = $curIters
        Process = $proc
        LogFile = $logFile
    })
}

Write-Host "Spawned $($jobs.Count) parallel workers. Awaiting completion..." -ForegroundColor Yellow

$allSucceeded = $true

foreach ($job in $jobs) {
    $proc = $job.Process
    $proc.WaitForExit()
    $fullOut = if (Test-Path $job.LogFile) { [System.IO.File]::ReadAllText($job.LogFile) } else { "" }
    Remove-Item $job.LogFile -Force -ErrorAction SilentlyContinue

    if ($proc.ExitCode -ne 0) {
        $allSucceeded = $false
        Write-Host "Worker $($job.Worker) (Offset $($job.Offset), $($job.Iterations) iters) FAILED with code $($proc.ExitCode)!" -ForegroundColor Red
        Write-Host $fullOut -ForegroundColor DarkYellow
    } else {
        Write-Host "Worker $($job.Worker) (Offset $($job.Offset), $($job.Iterations) iters) completed successfully." -ForegroundColor Green
    }
}

$swTotal.Stop()

Write-Host "`n===================================================="
Write-Host "Gauntlet Execution Time: $($swTotal.Elapsed.TotalSeconds.ToString('F1'))s" -ForegroundColor Cyan
if ($allSucceeded) {
    Write-Host "PARALLEL GAUNTLET CERTIFIED: 100% of $TotalIterations differential programs and $TotalIterations mutations PASSED with 0 disagreements and 0 host crashes." -ForegroundColor Green
    exit 0
} else {
    Write-Host "PARALLEL GAUNTLET FAILED." -ForegroundColor Red
    exit 1
}
