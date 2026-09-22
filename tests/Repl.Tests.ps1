# tests/Repl.Tests.ps1
#
# Production-entry-point certification for the interactive REPL
# (Start-OtterRepl in otter.ps1, reached by running `otter` with no file
# argument). Spawns the real otter.ps1 process with piped stdin, matching
# how any real automation/testing of the REPL has to work.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'REPL' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'

function Invoke-OtterRepl {
    param([string[]]$InputLines)

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:OtterPs1`""
    $psi.WorkingDirectory = $script:RepoRoot
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    foreach ($line in $InputLines) {
        $process.StandardInput.WriteLine($line)
    }
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit(15000) | Out-Null
    return $stdout
}


Test-Otter 'a variable persists across separate REPL lines' {
    $out = Invoke-OtterRepl -InputLines @('x is 5', 'say x', 'exit')
    Assert-True ($out -match '(?m)^5\s*$') 'expected the persisted variable to print 5'
}

Test-Otter 'a function definition typed across multiple REPL lines (multiline block collection) works' {
    $out = Invoke-OtterRepl -InputLines @('to greet name', '    say "Hello" name', '', 'greet "Jeff"', 'exit')
    Assert-True ($out -match 'Hello Jeff') 'expected the REPL-defined function to run correctly'
}

Test-Otter 'reset clears all variables and functions without restarting the process' {
    $out = Invoke-OtterRepl -InputLines @('x is 5', 'reset', 'say x', 'exit')
    Assert-True ($out -match 'session reset') 'expected a confirmation message from reset'
    Assert-True ($out -match 'could not find the variable') 'expected x to be genuinely gone after reset'
}

Test-Otter 'an error on one line does not end the session - later lines still run' {
    $out = Invoke-OtterRepl -InputLines @('say undefinedThing', 'y is 10', 'say y', 'exit')
    Assert-True ($out -match 'could not find the variable "undefinedThing"') 'expected the error to be reported'
    Assert-True ($out -match '(?m)^10\s*$') 'expected the REPL to keep running after the error'
}

Complete-OtterTests
