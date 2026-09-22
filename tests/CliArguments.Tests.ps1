# tests/CliArguments.Tests.ps1
#
# Real subprocess certification of D94's CLI argument passthrough, through
# the actual production entry point (otter.ps1 -> Invoke-OtterFile), not a
# helper called directly.
#
# Found while independently reviewing D94: declaring
# [Parameter(ValueFromRemainingArguments = $true)] on otter.ps1's param
# block (needed to capture arbitrary trailing arguments for the OTTER
# PROGRAM) makes it an "advanced" script, which makes PowerShell silently
# add its own common parameters (-Verbose, -Debug, -ErrorAction,
# -WarningAction, -InformationAction, -ErrorVariable, -WarningVariable,
# -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable).
# Confirmed directly: `otter run script.ot -Verbose` silently dropped that
# argument (bound to PowerShell's own -Verbose switch instead), and
# `otter run script.ot -OutVariable foo` swallowed BOTH tokens, leaving the
# Otter program with zero arguments and no error at all - exactly the kind
# of silent capability loss this project treats as a real bug. Fixed in
# otter.ps1 (Get-OtterRawTrailingArguments) by bypassing the parameter
# binder for the trailing-arguments slice and reconstructing it from the
# real, raw command line instead.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'CLI Arguments (D94)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'
$script:CliExample = 'examples/cli-arguments.ot'

function Invoke-OtterCli {
    param([string[]]$CliArgs)

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'powershell.exe'
    $quoted = ($CliArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:OtterPs1`" $quoted"
    $psi.WorkingDirectory = $script:RepoRoot
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit(15000) | Out-Null
    return $stdout
}

function Get-CliField {
    param([string]$Stdout, [string]$Label)
    $line = ($Stdout -split "`r?`n") | Where-Object { $_ -like "$Label*" } | Select-Object -First 1
    if ($null -eq $line) { return $null }
    return $line.Substring($Label.Length).Trim()
}


Test-Otter 'ordinary arguments pass through unchanged (run form)' {
    $out = Invoke-OtterCli -CliArgs @('run', $script:CliExample, 'Jeff', '42')
    Assert-AreEqual -Expected '2' -Actual (Get-CliField -Stdout $out -Label 'Total arguments:')
    Assert-AreEqual -Expected 'Jeff' -Actual (Get-CliField -Stdout $out -Label 'First argument:')
    Assert-AreEqual -Expected '42' -Actual (Get-CliField -Stdout $out -Label 'Last argument:')
}

Test-Otter 'ordinary arguments pass through unchanged (canonical short form)' {
    $out = Invoke-OtterCli -CliArgs @($script:CliExample, 'Alpha', 'Beta', 'Gamma')
    Assert-AreEqual -Expected '3' -Actual (Get-CliField -Stdout $out -Label 'Total arguments:')
    Assert-AreEqual -Expected 'Alpha' -Actual (Get-CliField -Stdout $out -Label 'First argument:')
    Assert-AreEqual -Expected 'Gamma' -Actual (Get-CliField -Stdout $out -Label 'Last argument:')
}

Test-Otter 'no arguments produces the documented empty-list message' {
    $out = Invoke-OtterCli -CliArgs @('run', $script:CliExample)
    Assert-True ($out -match 'No arguments provided') 'expected the length-zero branch to run'
}

Test-Otter 'a program argument that exactly matches a PowerShell common parameter name is not silently swallowed' {
    # -Verbose, -Debug, -OutVariable, etc. are PowerShell's own common
    # parameters on any advanced script/function - otter.ps1 never reads
    # any of them, so a user's program argument that happens to collide
    # must still reach the Otter program, not vanish into $VerbosePreference
    # or similar with zero indication anything went wrong.
    foreach ($commonParam in @('-Verbose', '-Debug')) {
        $out = Invoke-OtterCli -CliArgs @('run', $script:CliExample, $commonParam)
        Assert-AreEqual -Expected '1' -Actual (Get-CliField -Stdout $out -Label 'Total arguments:') "for $commonParam"
        Assert-AreEqual -Expected $commonParam -Actual (Get-CliField -Stdout $out -Label 'First argument:') "for $commonParam"
    }
}

Test-Otter 'a VALUE-taking common parameter (-OutVariable) does not also swallow the token after it' {
    $out = Invoke-OtterCli -CliArgs @('run', $script:CliExample, '-OutVariable', 'foo')
    Assert-AreEqual -Expected '2' -Actual (Get-CliField -Stdout $out -Label 'Total arguments:')
    Assert-AreEqual -Expected '-OutVariable' -Actual (Get-CliField -Stdout $out -Label 'First argument:')
    Assert-AreEqual -Expected 'foo' -Actual (Get-CliField -Stdout $out -Label 'Last argument:')
}

Test-Otter 'a single trailing argument (exactly one token after the target) is not corrupted to its first character' {
    # The regression that motivated the rewrite: with exactly one raw token
    # left after skipping the subcommand and target, otter.ps1's own
    # argument-reconstruction previously returned only that token's first
    # character ("-Debug" -> "-").
    $out = Invoke-OtterCli -CliArgs @('run', $script:CliExample, '-Debug')
    Assert-AreEqual -Expected '1' -Actual (Get-CliField -Stdout $out -Label 'Total arguments:')
    Assert-AreEqual -Expected '-Debug' -Actual (Get-CliField -Stdout $out -Label 'First argument:')
}

Test-Otter 'otter.ps1''s own -DebugAst flag is still recognized as its own flag, not a program argument' {
    $out = Invoke-OtterCli -CliArgs @('run', $script:CliExample, 'Jeff', '-DebugAst')
    Assert-True ($out -match '(?m)^--- ast ---') 'expected -DebugAst to still trigger the AST developer view'
    Assert-AreEqual -Expected '1' -Actual (Get-CliField -Stdout $out -Label 'Total arguments:')
    Assert-AreEqual -Expected 'Jeff' -Actual (Get-CliField -Stdout $out -Label 'First argument:')
}

Test-Otter 'otter debug''s own -Breakpoints value flag is still stripped from the program''s arguments' {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:OtterPs1`" debug `"examples/debugger-demo.ot`" -Breakpoints `"7`""
    $psi.WorkingDirectory = $script:RepoRoot
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $process.StandardInput.WriteLine('continue')
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit(15000) | Out-Null

    Assert-True ($stdout -match '"line":7') 'expected the breakpoint to still pause at line 7'
    Assert-True ($stdout -match 'Score is 5') 'expected the program to still finish normally after continue'
}

Complete-OtterTests
