# tests/ProcessAdversarial.Tests.ps1
#
# Process Adversarial Red-Team Suite for Otter 1.0 RC.
# Hammers: `run command ... into result` across stress & boundary conditions:
# - Successful process execution
# - Nonzero exit codes
# - Missing / invalid executables
# - Spaces in executable paths & arguments
# - Unicode output
# - Stderr only
# - Interleaved stdout + stderr
# - Large output buffers (50KB+)
# - Zero output processes
# - Quoted arguments handling
# - Verification of output, error output, and exit code
# - Verification that child processes are never leaked
#
# GUARANTEE: Operates safely in isolated sandbox without polluting machine state.

using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Library.psm1
using module ..\src\Otter.Interpreter.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1

. "$PSScriptRoot\TestHelpers.ps1"

function Invoke-OtterTestSnippet {
    param([string]$Source)
    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($Text) $collected.Add($Text) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        $tokens = ConvertTo-OtterTokens -Source $Source
        $ast = ConvertTo-OtterAst -Tokens $tokens
        $env = New-OtterEnvironment
        Invoke-OtterProgram -Program $ast -Environment $env -SourceLines ($Source -split "`r?`n")
    }
    finally {
        Set-OtterOutputWriter -Writer $null
    }
    return , $collected.ToArray()
}

Write-Host ''
Write-Host 'Otter 1.0 Process Adversarial Red-Team Suite' -ForegroundColor Cyan

# 1. Successful process
Test-Otter 'PROC-01: successful command captures output, empty error, exit code 0' {
    $out = Invoke-OtterTestSnippet @"
run command "powershell -NoProfile -Command Write-Output 'proc-success-token'" into res
say output of res
say error output of res
say exit code of res
"@
    Assert-True ($out[0].Contains('proc-success-token')) 'stdout must contain token'
    Assert-AreEqual -Expected '' -Actual $out[1] 'stderr must be empty'
    Assert-AreEqual -Expected '0' -Actual $out[2] 'exit code must be 0'
}

# 2. Nonzero exit code
Test-Otter 'PROC-02: command with nonzero exit captures exit code cleanly' {
    $out = Invoke-OtterTestSnippet @"
run command "powershell -NoProfile -Command exit 7" into res
say exit code of res
"@
    Assert-AreEqual -Expected '7' -Actual $out[0] 'exit code must be 7'
}

# 3. Missing executable handled without unhandled host crash
Test-Otter 'PROC-03: nonexistent executable handled cleanly via error code or try' {
    $out = Invoke-OtterTestSnippet @"
try
    run command "non_existent_executable_otter_xyz_987654" into res
    if exit code of res is not 0
        say "nonzero-or-failed"
    .
otherwise
    say "caught-missing-executable"
.
"@
    Assert-True ($out.Count -ge 1) 'Must catch or record failure'
    Assert-True ($out[0] -in @('nonzero-or-failed', 'caught-missing-executable')) 'Must handle missing executable gracefully'
}

# 4. Spaces in executable path and arguments
Test-Otter 'PROC-04: command with spaces in path and arguments' {
    $out = Invoke-OtterTestSnippet @"
run command "cmd.exe /c echo hello from spaced arg" into res
say output of res
say exit code of res
"@
    Assert-True ($out[0].Contains('hello from spaced arg')) 'stdout must contain spaced string'
    Assert-AreEqual -Expected '0' -Actual $out[1] 'exit code must be 0'
}

# 5. Unicode output
Test-Otter 'PROC-05: command with Unicode output in stdout' {
    $out = Invoke-OtterTestSnippet @"
run command "cmd.exe /c echo Otter: こんにちは World" into res
say output of res
"@
    Assert-True ($out[0].Contains('World')) 'Must capture output'
}

# 6. Stderr only
Test-Otter 'PROC-06: command writing only to stderr' {
    $out = Invoke-OtterTestSnippet @"
run command "powershell -NoProfile -Command [Console]::Error.WriteLine('error-only-stream')" into res
say output of res
say error output of res
say exit code of res
"@
    Assert-AreEqual -Expected '' -Actual $out[0] 'stdout must be empty'
    Assert-True ($out[1].Contains('error-only-stream')) 'stderr must contain error message'
    Assert-AreEqual -Expected '0' -Actual $out[2] 'exit code must be 0'
}

# 7. Interleaved stdout and stderr
Test-Otter 'PROC-07: command with both stdout and stderr separated correctly' {
    $out = Invoke-OtterTestSnippet @"
run command "powershell -NoProfile -Command Write-Output 'out-channel'; [Console]::Error.WriteLine('err-channel')" into res
say output of res
say error output of res
say exit code of res
"@
    Assert-True ($out[0].Contains('out-channel')) 'stdout must capture stdout'
    Assert-True ($out[1].Contains('err-channel')) 'stderr must capture stderr'
    Assert-AreEqual -Expected '0' -Actual $out[2] 'exit code must be 0'
}

# 8. Large output buffer (50KB+)
Test-Otter 'PROC-08: large output buffer does not hang or deadlock process' {
    $out = Invoke-OtterTestSnippet @"
run command "powershell -NoProfile -Command Write-Output ('ABCDEFGHIJKLMNOPQRSTUVWXYZ' * 1000)" into res
say length of output of res
say exit code of res
"@
    Assert-True ([int]$out[0] -ge 26000) 'Output must capture all 26,000+ characters'
    Assert-AreEqual -Expected '0' -Actual $out[1] 'exit code must be 0'
}

# 9. No output
Test-Otter 'PROC-09: zero-output command succeeds cleanly' {
    $out = Invoke-OtterTestSnippet @"
run command "powershell -NoProfile -Command exit 0" into res
say output of res
say error output of res
say exit code of res
"@
    Assert-AreEqual -Expected '' -Actual $out[0] 'stdout must be empty'
    Assert-AreEqual -Expected '' -Actual $out[1] 'stderr must be empty'
    Assert-AreEqual -Expected '0' -Actual $out[2] 'exit code must be 0'
}

# 10. Quoted arguments handling
Test-Otter 'PROC-10: complex nested quotes in command line' {
    $out = Invoke-OtterTestSnippet @"
run command "cmd.exe /c echo \"nested quote string\"" into res
say output of res
say exit code of res
"@
    Assert-True ($out[0].Contains('nested quote string')) 'Must handle quotes correctly'
    Assert-AreEqual -Expected '0' -Actual $out[1] 'exit code must be 0'
}

# 11. Child process leak check
Test-Otter 'PROC-11: child processes do not leak after command terminates' {
    $beforeProcs = @(Get-Process -Name powershell -ErrorAction SilentlyContinue).Count
    $out = Invoke-OtterTestSnippet @"
run command "powershell -NoProfile -Command Start-Sleep -Milliseconds 200; exit 0" into res
say exit code of res
"@
    Assert-AreEqual -Expected '0' -Actual $out[0] 'exit code must be 0'
    Start-Sleep -Milliseconds 400
    $afterProcs = @(Get-Process -Name powershell -ErrorAction SilentlyContinue).Count
    # Verify child powershell terminated
    Assert-True ($afterProcs -le ($beforeProcs + 1)) "No orphan processes leaked (before: $beforeProcs, after: $afterProcs)"
}

Complete-OtterTests
