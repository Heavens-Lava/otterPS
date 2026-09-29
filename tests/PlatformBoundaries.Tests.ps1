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

# A clean Otter error: finished, non-zero exit, an Otter-worded message that
# matches $Expect, none of the raw markers, and not Otter's own internal-error
# message (which means a bug, not a clean refusal).
function Assert-CleanError {
    param($Result, [string]$Label, [string]$Expect)
    Assert-True $Result.Finished "$Label did not finish within 60 seconds"
    Write-Output "        -> exit $($Result.ExitCode): $(($Result.Text -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 4) -join ' | ')"
    foreach ($marker in $script:RawMarkers) {
        Assert-False ($Result.Text.Contains($marker)) "$Label printed raw error text '$marker': $($Result.Text)"
    }
    Assert-False ($Result.Text.Contains('Otter hit a problem inside itself')) "$Label crashed inside Otter: $($Result.Text)"
    Assert-True ($Result.ExitCode -ne 0) "$Label should stop with an error on this platform, but exited 0: $($Result.Text)"
    Assert-True ($Result.Text -match $Expect) "$Label should say '$Expect', got: $($Result.Text)"
}

$windowsOnly = 'only available on Windows'
$cases = [ordered]@{
    'a desktop window (otter run)'           = @{ Source = "create window into app`ncreate button into b`nput b in app`nshow app`n"; Expect = 'Otter Runtime Error' }
    'a desktop window (otter desktop)'       = @{ Source = "create window into app`nshow app`n"; Command = @('desktop'); Expect = $windowsOnly }
    'reading the registry'                   = @{ Source = "get registry value `"n`" from `"HKCU:\Software\OtterPlatformTest`" into t`nsay t`n"; Expect = $windowsOnly }
    'checking a registry key'                = @{ Source = "if registry key `"HKCU:\Software\OtterPlatformTest`" exists`n    say `"yes`"`n.`n"; Expect = $windowsOnly }
    'writing the registry'                   = @{ Source = "set registry value `"n`" to `"d`" in `"HKCU:\Software\OtterPlatformTest`"`n"; Expect = $windowsOnly }
    'a stored credential'                    = @{ Source = "set credential `"otter-platform-test`" to `"secret`"`n"; Expect = $windowsOnly }
    'the credential vault'                   = @{ Source = "store secret `"otter-platform-test`" with value `"v`"`n"; Expect = 'Otter Runtime Error' }
    'the event log'                          = @{ Source = "get event log entries from `"System`" up to 1 into entries`nsay length of entries`n"; Expect = $windowsOnly }
    'the owner of a file'                    = @{ Source = "get owner of `"file.txt`" into owner`nsay owner`n"; Expect = $windowsOnly }
    'printing a file'                        = @{ Source = "print `"file.txt`" to `"Otter Test Printer`"`n"; Expect = $windowsOnly }
    'a notification'                         = @{ Source = "notify `"Otter`" with `"hello`"`n"; Expect = $windowsOnly }
    'a file dialog'                          = @{ Source = "choose file into picked`nsay picked`n"; Expect = $windowsOnly }
    'locking the computer'                   = @{ Source = "lock the computer`n"; Expect = $windowsOnly }
    'running a Windows command (cmd)'        = @{ Source = "run command `"cmd /c echo hi`" into result`nsay output of result`n"; Expect = 'Otter Runtime Error' }
}

try {
    foreach ($name in $cases.Keys) {
        $case = $cases[$name]
        $command = if ($case.Command) { $case.Command } else { @('run') }
        Test-Otter "on $($PSVersionTable.OS): $name stops with a clean Otter error" ({
            $r = Invoke-OtterPlatformProgram -Source $case.Source -Command $command
            Assert-CleanError -Result $r -Label $name -Expect $case.Expect
        }.GetNewClosure())
    }

    # The clipboard needs a clipboard program and a desktop session on macOS and
    # Linux: copying either round-trips the text or says it cannot.
    Test-Otter "on $($PSVersionTable.OS): the clipboard round-trips its text or says it cannot" {
        $r = Invoke-OtterPlatformProgram -Source "copy `"otter-clip-test`" to clipboard`nget clipboard into pasted`nsay pasted`n"
        if ($r.ExitCode -eq 0) {
            Write-Output "        -> exit 0: $($r.Text)"
            Assert-AreEqual -Expected 'otter-clip-test' -Actual $r.Text
        } else {
            Assert-CleanError -Result $r -Label 'the clipboard' -Expect 'clipboard'
        }
    }
}
finally {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests
