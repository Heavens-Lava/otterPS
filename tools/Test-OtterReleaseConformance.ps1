[CmdletBinding()]
param(
    [string]$Fixture,
    [switch]$KeepArtifacts
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $root 'conformance\manifest.json'
$otter = Join-Path $root 'otter.ps1'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

function Quote-OtterProcessArgument {
    param([Parameter(Mandatory)][string]$Value)
    return '"' + ($Value -replace '(\\*)"', '$1$1\\"') + '"'
}

function Invoke-OtterProductionEntryPoint {
    param(
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Get-Command powershell.exe -ErrorAction Stop).Source
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Quote-OtterProcessArgument $otter), $Mode, (Quote-OtterProcessArgument $SourcePath))
    if ($Mode -eq 'web') { $args += '-NoOpen' }
    $psi.Arguments = $args -join ' '
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdoutTask.Result.Replace("`r`n", "`n").TrimEnd("`r", "`n")
        Stderr = $stderrTask.Result.Replace("`r`n", "`n").TrimEnd("`r", "`n")
    }
}

$fixtures = @($manifest.fixtures)
if ($Fixture) {
    $fixtures = @($fixtures | Where-Object { $_.name -eq $Fixture })
    if ($fixtures.Count -eq 0) { throw "No release conformance fixture named '$Fixture'." }
}

$failures = @()
foreach ($case in $fixtures) {
    $source = Join-Path $root $case.source
    $temp = $null
    try {
        $workdir = $root
        $sourceForRun = $source
        if ($case.mode -eq 'run-in-temp-directory' -or $case.mode -eq 'web') {
            $temp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter-release-' + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $temp | Out-Null
            $sourceForRun = Join-Path $temp ([System.IO.Path]::GetFileName($source))
            Copy-Item -LiteralPath $source -Destination $sourceForRun
            $workdir = $temp
        }

        $mode = if ($case.mode -eq 'run-in-temp-directory') { 'run' } else { [string]$case.mode }
        $actual = Invoke-OtterProductionEntryPoint -Mode $mode -SourcePath $sourceForRun -WorkingDirectory $workdir
        if ($actual.ExitCode -ne [int]$case.expectedExitCode) { throw "exit code $($actual.ExitCode), expected $($case.expectedExitCode). stderr: $($actual.Stderr)" }
        if ($null -ne $case.expectedStdout) {
            $expected = (@($case.expectedStdout) -join "`n")
            if ($actual.Stdout -ne $expected) { throw "stdout mismatch. Expected [$expected], got [$($actual.Stdout)]" }
        }
        if ($case.expectedDiagnosticContains) {
            # otter.ps1 uses Write-Host for its beginner-facing diagnostic
            # formatter, so production diagnostics arrive on stdout in
            # Windows PowerShell. Preserve both streams separately above and
            # certify the user-visible combined output here.
            $diagnosticOutput = $actual.Stdout + "`n" + $actual.Stderr
            if ($diagnosticOutput -notmatch [regex]::Escape([string]$case.expectedDiagnosticContains)) {
                throw "diagnostic did not contain '$($case.expectedDiagnosticContains)'. Got: $diagnosticOutput"
            }
        }
        if ($case.expectedHtmlContains) {
            $html = [System.IO.Path]::ChangeExtension($sourceForRun, '.html')
            if (-not (Test-Path -LiteralPath $html)) { throw "web compiler did not create $html" }
            $htmlText = Get-Content -LiteralPath $html -Raw
            foreach ($needle in @($case.expectedHtmlContains)) {
                if ($htmlText -notlike "*$needle*") { throw "generated HTML did not contain '$needle'" }
            }
        }
        Write-Output "  pass  $($case.name)"
    }
    catch {
        $failures += "$($case.name): $($_.Exception.Message)"
        Write-Output "  FAIL  $($case.name): $($_.Exception.Message)"
    }
    finally {
        if ($temp -and -not $KeepArtifacts -and (Test-Path -LiteralPath $temp)) {
            Remove-Item -LiteralPath $temp -Recurse -Force
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Error ("Release conformance failed:`n" + ($failures -join "`n"))
    exit 1
}

Write-Output "Release conformance passed ($($fixtures.Count) fixtures)."
