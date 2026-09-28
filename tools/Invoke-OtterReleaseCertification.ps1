<#
.SYNOPSIS
    Runs every authoritative Otter 1.0 release gate once and records the exact
    outcome of each: commit, host, command, start/end time and exit code.

.DESCRIPTION
    This script contains NO test logic. Each gate is one of the repository's
    existing tools, run as a child process of the same PowerShell that is running
    this script, with its full output captured to a log file.

      contract-structural    tools/Test-OtterContractCoverage.ps1
      platform-regression    tests/Run-Tests.ps1 (every tests/*.Tests.ps1, including the
                             production-entry suites: CLI contract, command dispatch,
                             modules, debugger, profiler, installation and soak)
      conformance            tools/Test-OtterReleaseConformance.ps1
      differential-fuzz      tools/Invoke-OtterDifferentialFuzzer.ps1 -Mode Differential
      malformed-input-fuzz   tools/Invoke-OtterDifferentialFuzzer.ps1 -Mode MutationFuzz
      release-surface-audit  tools/Test-OtterReleaseSurface.ps1
      distribution-smoke     tools/Test-OtterDistribution.ps1

    After the gates, one more check runs, always:

      repository-clean       git status --porcelain --untracked-files=all
                             must be the same after the gates as before them.
                             A gate that rewrites a tracked file or leaves an
                             untracked one behind fails the run. Release
                             invariant: clean checkout -> full certification
                             -> git status still clean. Ignored paths (the
                             default record directory release/certification/,
                             scratch/, test scratch projects) are not counted.

    A run only counts as release certification when it is made from a CLEAN
    checkout (no modified or untracked files) whose HEAD is the nominated
    candidate SHA. Pass that SHA with -CandidateSha; the record states whether
    both conditions held. Any other run is recorded as a development run.

    Typical certification use, from a fresh detached worktree:

        git worktree add --detach ..\otter-cert <candidate-sha>
        cd ..\otter-cert
        powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-OtterReleaseCertification.ps1 -CandidateSha <candidate-sha>

    Output (in -OutputDirectory, default release/certification/<timestamp>-<sha7>/):
      certification.json   machine-readable record
      certification.md     the same record for people
      <gate>.log           full output of each gate

.PARAMETER CandidateSha
    The nominated release-candidate commit. Required for a run to be recorded as certification.
.PARAMETER FuzzIterations
    Programs per fuzz gate (default 1000).
.PARAMETER FuzzSeed
    Seed for both fuzz gates (default 20261001). Recorded in the output.
.PARAMETER Only
    Run only the named gates (comma-separated accepted).
.PARAMETER OutputDirectory
    Where to write the record and logs.
#>
[CmdletBinding()]
param(
    [string]$CandidateSha = '',
    [int]$FuzzIterations = 1000,
    [int]$FuzzSeed = 20261001,
    [string[]]$Only = @(),
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hostExe = (Get-Process -Id $PID).Path
$onWindows = ($PSVersionTable.PSEdition -ne 'Core') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)

function Invoke-Git { param([string[]]$GitArgs) $out = & git -C $repoRoot @GitArgs 2>$null; if ($LASTEXITCODE -ne 0) { return $null }; return $out }

$sha = [string](Invoke-Git @('rev-parse', 'HEAD'))
$sha = $sha.Trim()
$subject = [string](Invoke-Git @('log', '-1', '--format=%s'))
$porcelain = @(Invoke-Git @('status', '--porcelain', '--untracked-files=all'))
$porcelain = @($porcelain | Where-Object { $_ })
$clean = ($porcelain.Count -eq 0)
$matchesCandidate = if ($CandidateSha) { $sha -and $sha.StartsWith($CandidateSha.Trim(), [System.StringComparison]::OrdinalIgnoreCase) -or $CandidateSha.Trim().StartsWith($sha, [System.StringComparison]::OrdinalIgnoreCase) } else { $false }
$isCertification = $clean -and $matchesCandidate -and $sha

if (-not $OutputDirectory) {
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $short = if ($sha) { $sha.Substring(0, [Math]::Min(7, $sha.Length)) } else { 'nogit' }
    $OutputDirectory = Join-Path $repoRoot "release/certification/$stamp-$short"
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path $repoRoot $OutputDirectory }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$hostArgs = @('-NoProfile')
if ($onWindows) { $hostArgs += @('-ExecutionPolicy', 'Bypass') }

$gates = @(
    [ordered]@{ name = 'contract-structural'; script = 'tools/Test-OtterContractCoverage.ps1'; args = @() }
    [ordered]@{ name = 'platform-regression'; script = 'tests/Run-Tests.ps1'; args = @() }
    [ordered]@{ name = 'conformance'; script = 'tools/Test-OtterReleaseConformance.ps1'; args = @() }
    [ordered]@{ name = 'differential-fuzz'; script = 'tools/Invoke-OtterDifferentialFuzzer.ps1'; args = @('-Mode', 'Differential', '-Iterations', [string]$FuzzIterations, '-Seed', [string]$FuzzSeed) }
    [ordered]@{ name = 'malformed-input-fuzz'; script = 'tools/Invoke-OtterDifferentialFuzzer.ps1'; args = @('-Mode', 'MutationFuzz', '-Iterations', [string]$FuzzIterations, '-Seed', [string]$FuzzSeed) }
    [ordered]@{ name = 'release-surface-audit'; script = 'tools/Test-OtterReleaseSurface.ps1'; args = @() }
    [ordered]@{ name = 'distribution-smoke'; script = 'tools/Test-OtterDistribution.ps1'; args = @() }
)
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if ($Only.Count -gt 0) {
    $unknown = @($Only | Where-Object { $_ -notin @($gates | ForEach-Object { $_.name }) })
    if ($unknown.Count -gt 0) { throw "Unknown gate(s): $($unknown -join ', ')" }
    $gates = @($gates | Where-Object { $Only -contains $_.name })
}

Write-Host ''
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host 'Otter release certification' -ForegroundColor Cyan
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host "Commit:      $sha  $subject"
Write-Host "Clean tree:  $clean$(if (-not $clean) { " ($($porcelain.Count) modified/untracked path(s))" })"
Write-Host "Candidate:   $(if ($CandidateSha) { "$CandidateSha (matches HEAD: $matchesCandidate)" } else { '(none given)' })"
Write-Host "Host:        PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)) on $([System.Environment]::OSVersion.VersionString)"
if (-not $isCertification) {
    Write-Host 'This run is a DEVELOPMENT run, not release certification (needs a clean checkout whose HEAD is -CandidateSha).' -ForegroundColor Yellow
}
Write-Host ''

$records = New-Object System.Collections.Generic.List[object]
foreach ($gate in $gates) {
    $scriptPath = Join-Path $repoRoot $gate.script
    $logPath = Join-Path $OutputDirectory "$($gate.name).log"
    $commandLine = (@($hostExe) + $hostArgs + @('-File', $gate.script) + $gate.args) -join ' '
    $start = (Get-Date).ToUniversalTime()
    Write-Host ("[{0}] {1} ..." -f $start.ToString('HH:mm:ss'), $gate.name) -NoNewline
    $exitCode = $null
    $failure = $null
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        $failure = "gate script not found: $($gate.script)"
        [System.IO.File]::WriteAllText($logPath, $failure)
    }
    else {
        Push-Location -LiteralPath $repoRoot
        try {
            $output = & $hostExe @hostArgs -File $scriptPath @($gate.args) 2>&1
            $exitCode = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($logPath, [string[]]@($output | ForEach-Object { $_.ToString() }), [System.Text.UTF8Encoding]::new($false))
        }
        catch { $failure = $_.Exception.Message }
        finally { Pop-Location }
    }
    $end = (Get-Date).ToUniversalTime()
    $passed = ($null -eq $failure) -and ($exitCode -eq 0)
    $lastLines = @()
    if (Test-Path -LiteralPath $logPath) { $lastLines = @(Get-Content -LiteralPath $logPath -Tail 3 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() }) }
    Write-Host (" exit {0} in {1:N0}s {2}" -f $exitCode, ($end - $start).TotalSeconds, $(if ($passed) { 'PASS' } else { 'FAIL' })) -ForegroundColor $(if ($passed) { 'Green' } else { 'Red' })
    $records.Add([ordered]@{
        gate = $gate.name
        command = $commandLine
        startUtc = $start.ToString('o')
        endUtc = $end.ToString('o')
        seconds = [Math]::Round(($end - $start).TotalSeconds, 1)
        exitCode = $exitCode
        passed = $passed
        failure = $failure
        log = [System.IO.Path]::GetFileName($logPath)
        lastLines = $lastLines
    })
}

# --- repository-clean: the gates must not change the working tree -----------
# Compare `git status` after the gates with the snapshot taken before them. On
# a clean certification checkout this means "still clean"; on a development
# run with local edits it means "the gates added nothing to those edits".
# Paths are compared as whole porcelain lines, so a file that was already
# modified before the run and is modified again by a gate goes unnoticed on a
# development run; a certification run starts clean, so it catches that case.
$cleanStart = (Get-Date).ToUniversalTime()
$porcelainAfter = @(Invoke-Git @('status', '--porcelain', '--untracked-files=all'))
$porcelainAfter = @($porcelainAfter | Where-Object { $_ })
$dirtiedPaths = @($porcelainAfter | Where-Object { $porcelain -notcontains $_ })
$cleanedPaths = @($porcelain | Where-Object { $porcelainAfter -notcontains $_ })
$cleanPassed = ($dirtiedPaths.Count -eq 0) -and ($cleanedPaths.Count -eq 0)
$cleanLog = Join-Path $OutputDirectory 'repository-clean.log'
$cleanLines = @("git status --porcelain --untracked-files=all: $($porcelain.Count) path(s) before the gates, $($porcelainAfter.Count) after.")
if ($dirtiedPaths.Count -gt 0) { $cleanLines += 'Changed by the gates:'; $cleanLines += @($dirtiedPaths | ForEach-Object { "  $_" }) }
if ($cleanedPaths.Count -gt 0) { $cleanLines += 'Changed back or removed by the gates:'; $cleanLines += @($cleanedPaths | ForEach-Object { "  $_" }) }
if ($cleanPassed) { $cleanLines += 'The gates left the working tree exactly as they found it.' }
[System.IO.File]::WriteAllLines($cleanLog, [string[]]$cleanLines, [System.Text.UTF8Encoding]::new($false))
$cleanEnd = (Get-Date).ToUniversalTime()
Write-Host ("[{0}] repository-clean ... {1} path(s) changed by the gates {2}" -f $cleanStart.ToString('HH:mm:ss'), ($dirtiedPaths.Count + $cleanedPaths.Count), $(if ($cleanPassed) { 'PASS' } else { 'FAIL' })) -ForegroundColor $(if ($cleanPassed) { 'Green' } else { 'Red' })
if (-not $cleanPassed) { foreach ($p in @($dirtiedPaths + $cleanedPaths) | Select-Object -First 20) { Write-Host "    $p" -ForegroundColor Red } }
$records.Add([ordered]@{
    gate = 'repository-clean'
    command = 'git status --porcelain --untracked-files=all (after the gates, compared with before)'
    startUtc = $cleanStart.ToString('o')
    endUtc = $cleanEnd.ToString('o')
    seconds = [Math]::Round(($cleanEnd - $cleanStart).TotalSeconds, 1)
    exitCode = if ($cleanPassed) { 0 } else { 1 }
    passed = $cleanPassed
    failure = if ($cleanPassed) { $null } else { "the gates changed $($dirtiedPaths.Count + $cleanedPaths.Count) path(s); see repository-clean.log" }
    log = 'repository-clean.log'
    lastLines = @($cleanLines | Select-Object -Last 3)
})

$allPassed = (@($records | Where-Object { -not $_.passed }).Count -eq 0) -and $records.Count -gt 1
$record = [ordered]@{
    kind = if ($isCertification) { 'release-certification' } else { 'development-run' }
    commit = $sha
    subject = $subject
    candidateSha = if ($CandidateSha) { $CandidateSha } else { $null }
    headMatchesCandidate = $matchesCandidate
    cleanCheckout = $clean
    uncleanPaths = @($porcelain | Select-Object -First 50)
    cleanAfterGates = $cleanPassed
    pathsChangedByGates = @(@($dirtiedPaths + $cleanedPaths) | Select-Object -First 50)
    host = [ordered]@{
        os = [System.Environment]::OSVersion.VersionString
        powershellVersion = $PSVersionTable.PSVersion.ToString()
        powershellEdition = [string]$PSVersionTable.PSEdition
        executable = $hostExe
        machine = [System.Environment]::MachineName
    }
    fuzz = [ordered]@{ iterations = $FuzzIterations; seed = $FuzzSeed }
    gates = $records.ToArray()
    allGatesPassed = $allPassed
    note = 'Each gate is an existing repository tool; this record adds no test logic. Only kind=release-certification with allGatesPassed=true is release evidence.'
}
[System.IO.File]::WriteAllText((Join-Path $OutputDirectory 'certification.json'), ($record | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Otter release certification record")
[void]$md.AppendLine('')
[void]$md.AppendLine("| | |")
[void]$md.AppendLine("|---|---|")
[void]$md.AppendLine("| Kind | **$($record.kind)** |")
[void]$md.AppendLine("| Commit | ``$sha`` $subject |")
[void]$md.AppendLine("| Candidate SHA | $(if ($CandidateSha) { "``$CandidateSha`` (HEAD matches: $matchesCandidate)" } else { 'not given' }) |")
[void]$md.AppendLine("| Clean checkout | $clean |")
[void]$md.AppendLine("| Tree unchanged by the gates | $cleanPassed |")
[void]$md.AppendLine("| Host | PowerShell $($record.host.powershellVersion) ($($record.host.powershellEdition)), $($record.host.os) |")
[void]$md.AppendLine("| Fuzz | $FuzzIterations programs per fuzz gate, seed $FuzzSeed |")
[void]$md.AppendLine("| Result | **$(if ($allPassed) { 'all gates passed' } else { 'FAILED' })** |")
[void]$md.AppendLine('')
[void]$md.AppendLine('| Gate | Command | Start (UTC) | End (UTC) | Exit | Result |')
[void]$md.AppendLine('|---|---|---|---|---:|---|')
foreach ($r in $records) {
    [void]$md.AppendLine("| $($r.gate) | ``$($r.command.Replace($repoRoot, '.'))`` | $($r.startUtc) | $($r.endUtc) | $($r.exitCode) | $(if ($r.passed) { 'pass' } else { "**fail** $($r.failure)" }) |")
}
[System.IO.File]::WriteAllText((Join-Path $OutputDirectory 'certification.md'), $md.ToString(), [System.Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host "Record: $OutputDirectory" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "All $($records.Count) gate(s) passed ($($record.kind))." -ForegroundColor Green
    exit 0
}
Write-Host "Failing gate(s): $((@($records | Where-Object { -not $_.passed }) | ForEach-Object { $_.gate }) -join ', ')" -ForegroundColor Red
exit 1
