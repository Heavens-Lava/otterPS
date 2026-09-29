# PlatformBoundaries.Tests.ps1
#
# macOS and Linux (PowerShell 7): every Windows-only feature must either work
# or stop with a clean Otter error - never a raw .NET or PowerShell error, a
# crash, or a hang. Each program runs through the real CLI (otter.ps1 run /
# desktop / studio) with the PowerShell that runs this file.
#
# On Windows the features are real and are tested by their own suites, so this
# file reports itself as skipped there.

. "$PSScriptRoot\TestHelpers.ps1"
. "$PSScriptRoot\TestHost.ps1"

Write-Host ''
Write-Host 'Platform boundaries (macOS and Linux)' -ForegroundColor Cyan

if ($script:OtterHostIsWindows) {
    Write-Output '  skip  Windows-only features are tested by their own suites on Windows'
    Complete-OtterTests
    return
}

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'
$script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_platform_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $script:Tmp 'file.txt'), 'hello')

# Text that must never reach a user: raw .NET / PowerShell error output.
$script:RawMarkers = @('Exception', 'CategoryInfo', 'FullyQualifiedErrorId', 'At line:', ' at System.', 'is not recognized as', 'StackTrace', 'Cannot find type', 'Unable to find type')

function Invoke-OtterPlatformProgram {
    param([string]$Source, [string[]]$Command = @('run'))
    $path = Join-Path $script:Tmp ('p' + [Guid]::NewGuid().ToString('N') + '.ot')
    [System.IO.File]::WriteAllText($path, $Source, [System.Text.UTF8Encoding]::new($false))
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $script:OtterHostExe
    $argList = @('-NoProfile', '-File', $script:OtterPs1) + $Command + @($path)
    foreach ($a in $argList) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $script:Tmp
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $errTask = $proc.StandardError.ReadToEndAsync()
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $finished = $proc.WaitForExit(60000)
    if (-not $finished) { try { $proc.Kill($true) } catch {} }
    return [pscustomobject]@{ Finished = $finished; ExitCode = $(if ($finished) { $proc.ExitCode } else { $null }); Text = ($outTask.Result + $errTask.Result).Trim() }
}

# Works (exit 0), or a clean Otter error: an Otter banner or Otter-worded
# message, a non-zero exit, and none of the raw markers.
function Assert-WorksOrCleanError {
    param($Result, [string]$Label)
    Assert-True $Result.Finished "$Label did not finish within 60 seconds"
    foreach ($marker in $script:RawMarkers) {
        Assert-False ($Result.Text.Contains($marker)) "$Label printed raw error text '$marker': $($Result.Text)"
    }
    if ($Result.ExitCode -ne 0) {
        Assert-True ($Result.Text -match 'Otter (Runtime|Syntax) Error|^Otter[: ]|not supported|only (works|available|supported) on Windows|needs Windows') "$Label failed without a clean Otter message (exit $($Result.ExitCode)): $($Result.Text)"
    }
    Write-Output "        -> exit $($Result.ExitCode): $(($Result.Text -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 3) -join ' | ')"
}

$cases = [ordered]@{
    'a desktop window (otter run)'           = @{ Source = "create window into app`ncreate button into b`nput b in app`nshow app`n" }
    'a desktop window (otter desktop)'       = @{ Source = "create window into app`nshow app`n"; Command = @('desktop') }
    'reading the registry'                   = @{ Source = "get registry value `"n`" from `"HKCU:\Software\OtterPlatformTest`" into t`nsay t`n" }
    'checking a registry key'                = @{ Source = "if registry key `"HKCU:\Software\OtterPlatformTest`" exists`n    say `"yes`"`n.`n" }
    'writing the registry'                   = @{ Source = "set registry value `"n`" to `"d`" in `"HKCU:\Software\OtterPlatformTest`"`n" }
    'a DPAPI credential'                     = @{ Source = "set credential `"otter-platform-test`" to `"secret`"`n" }
    'the credential vault'                   = @{ Source = "store secret `"otter-platform-test`" with value `"v`"`n" }
    'the event log'                          = @{ Source = "get event log entries from `"System`" up to 1 into entries`nsay length of entries`n" }
    'the owner of a file'                    = @{ Source = "get owner of `"file.txt`" into owner`nsay owner`n" }
    'copying to the clipboard'               = @{ Source = "copy `"otter`" to clipboard`n" }
    'printing a file'                        = @{ Source = "print `"file.txt`" to `"Otter Test Printer`"`n" }
    'running a Windows command (cmd)'        = @{ Source = "run command `"cmd /c echo hi`" into result`nsay output of result`n" }
}

try {
    foreach ($name in $cases.Keys) {
        $case = $cases[$name]
        $command = if ($case.Command) { $case.Command } else { @('run') }
        Test-Otter "on $($PSVersionTable.OS): $name works or stops with a clean Otter error" ({
            $r = Invoke-OtterPlatformProgram -Source $case.Source -Command $command
            Assert-WorksOrCleanError -Result $r -Label $name
        }.GetNewClosure())
    }
}
finally {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests
