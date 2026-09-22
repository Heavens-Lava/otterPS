# tests/UseModuleProduction.Tests.ps1
#
# Production-entry-point certification for `use "file.ot"` (D60/D94-follow-on).
#
# tests/Module.Tests.ps1 already certifies src/Otter.Module.psm1's resolver
# in isolation (Resolve-OtterModuleSource called directly). That proves the
# resolver works, not that a real Otter program reaches it - per this
# project's own rule, a renderer/helper/unit test does not certify a
# language capability until a real .ot file reaches it through a production
# entry point (otter.ps1 -> Invoke-OtterFile). This file is that
# certification: every test here spawns the real otter.ps1 process.
#
# Until this was wired in, `use "file.ot"` always failed at runtime with
# "'use' is not supported in Otter 1.0." - the resolver existed but no
# production entry point ever called it (see docs/OTTER_1_0_MODULE_STATUS.md,
# written when that was still true). The web/JS compiler target
# (src/Otter.Web.psm1) already called Resolve-OtterModuleSource separately;
# this closes the same gap for the console interpreter (`otter run`/`check`).

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'use "..." modules - production entry point (console)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'

function New-OtterTempDir {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_use_test_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir | Out-Null
    return $dir
}

function Invoke-OtterCli {
    param([string]$Command, [string]$TargetPath, [string]$WorkingDirectory)

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:OtterPs1`" $Command `"$TargetPath`""
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit(15000) | Out-Null
    return [pscustomobject]@{ Stdout = $stdout; Stderr = $stderr; ExitCode = $process.ExitCode }
}


Test-Otter 'a real otter run reaches an imported function through `use "file.ot"`' {
    $dir = New-OtterTempDir
    try {
        Set-Content -LiteralPath (Join-Path $dir 'greetings.ot') -Value @('to greet name', '    say "Hello" name') -Encoding utf8
        Set-Content -LiteralPath (Join-Path $dir 'main.ot') -Value @('use "greetings.ot"', '', 'greet "Jeff"', 'say "Done"') -Encoding utf8
        $result = Invoke-OtterCli -Command 'run' -TargetPath 'main.ot' -WorkingDirectory $dir
        Assert-AreEqual -Expected 0 -Actual $result.ExitCode
        Assert-Lines -Expected @('Hello Jeff', 'Done') -Actual (($result.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Otter 'diamond imports (two files importing the same shared file) do not double-declare' {
    $dir = New-OtterTempDir
    try {
        Set-Content -LiteralPath (Join-Path $dir 'shared.ot') -Value 'sharedValue is 42' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $dir 'left.ot') -Value 'use "shared.ot"' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $dir 'right.ot') -Value 'use "shared.ot"' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $dir 'main.ot') -Value @('use "left.ot"', 'use "right.ot"', 'say sharedValue') -Encoding utf8
        $result = Invoke-OtterCli -Command 'run' -TargetPath 'main.ot' -WorkingDirectory $dir
        Assert-AreEqual -Expected 0 -Actual $result.ExitCode
        Assert-AreEqual -Expected '42' -Actual ($result.Stdout.Trim())
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Otter 'a circular import is a clean, readable diagnostic (exit code 2, not a PowerShell crash)' {
    $dir = New-OtterTempDir
    try {
        Set-Content -LiteralPath (Join-Path $dir 'a.ot') -Value @('use "b.ot"', 'say "a"') -Encoding utf8
        Set-Content -LiteralPath (Join-Path $dir 'b.ot') -Value @('use "a.ot"', 'say "b"') -Encoding utf8
        $result = Invoke-OtterCli -Command 'run' -TargetPath 'a.ot' -WorkingDirectory $dir
        Assert-AreEqual -Expected 2 -Actual $result.ExitCode
        Assert-True ($result.Stdout -match 'Circular import detected: a\.ot -> b\.ot -> a\.ot') 'expected the cycle chain in the diagnostic'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Otter 'a missing import names the file and where it looked (exit code 2)' {
    $dir = New-OtterTempDir
    try {
        Set-Content -LiteralPath (Join-Path $dir 'main.ot') -Value 'use "does_not_exist.ot"' -Encoding utf8
        $result = Invoke-OtterCli -Command 'run' -TargetPath 'main.ot' -WorkingDirectory $dir
        Assert-AreEqual -Expected 2 -Actual $result.ExitCode
        Assert-True ($result.Stdout -match 'Cannot find imported Otter file "does_not_exist\.ot"') 'expected a clear missing-import diagnostic'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Otter 'a runtime error inside an imported file reports the file it actually came from and the correct local line' {
    $dir = New-OtterTempDir
    try {
        Set-Content -LiteralPath (Join-Path $dir 'broken.ot') -Value @('to sayIt', '    say notDefinedAnywhere') -Encoding utf8
        Set-Content -LiteralPath (Join-Path $dir 'main.ot') -Value @('use "broken.ot"', '', 'sayIt') -Encoding utf8
        $result = Invoke-OtterCli -Command 'run' -TargetPath 'main.ot' -WorkingDirectory $dir
        Assert-AreEqual -Expected 3 -Actual $result.ExitCode
        Assert-True ($result.Stdout -match 'In "broken\.ot":') 'expected the error to name the imported file it came from'
        Assert-True ($result.Stdout -match '(?m)^Line 2:') 'expected the LOCAL line number inside broken.ot (2), not the combined-source line'
        Assert-True ($result.Stdout -match 'say notDefinedAnywhere') 'expected the correct offending source line to be quoted'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Otter 'a file with no use statements at all is completely unaffected (module resolution is a no-op)' {
    $dir = New-OtterTempDir
    try {
        Set-Content -LiteralPath (Join-Path $dir 'plain.ot') -Value 'say "just a plain program"' -Encoding utf8
        $result = Invoke-OtterCli -Command 'run' -TargetPath 'plain.ot' -WorkingDirectory $dir
        Assert-AreEqual -Expected 0 -Actual $result.ExitCode
        Assert-AreEqual -Expected 'just a plain program' -Actual ($result.Stdout.Trim())
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Otter 'otter check also resolves modules (validates without running)' {
    $dir = New-OtterTempDir
    try {
        Set-Content -LiteralPath (Join-Path $dir 'greetings.ot') -Value @('to greet name', '    say "Hello" name') -Encoding utf8
        Set-Content -LiteralPath (Join-Path $dir 'main.ot') -Value @('use "greetings.ot"', 'greet "Jeff"') -Encoding utf8
        $result = Invoke-OtterCli -Command 'check' -TargetPath 'main.ot' -WorkingDirectory $dir
        Assert-AreEqual -Expected 0 -Actual $result.ExitCode
        Assert-True ($result.Stdout -match 'is valid') 'expected otter check to report the imported program as valid'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Complete-OtterTests
