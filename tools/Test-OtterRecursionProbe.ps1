# Test-OtterRecursionProbe.ps1
#
# Windows PowerShell 5.1 recursion probe (release check). Deep but legitimate
# recursion through the real CLI must either give the right answer or Otter's
# clean "Call depth limit exceeded" error (exit 3) - never a host crash, a raw
# PowerShell error, or a hang. The limit is 250 nested calls
# (src/Otter.Interpreter.psm1), so depths straddle it.
#
#     powershell -NoProfile -File tools\Test-OtterRecursionProbe.ps1
#
# Exit code 0 when every case behaves; 1 otherwise.

param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [int[]]$Depths = @(50, 100, 200, 240, 249, 250, 251, 400),
    [int]$Limit = 250
)

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_recprobe_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

# Three ways a recursive call can be written: as a call statement, as a value
# after `is`, and inside a loop body.
$shapes = [ordered]@{
    'plain call'    = "to total n`n    if n is 0`n        return 0`n    .`n    m is n minus 1`n    total m make rest`n    return rest plus n`n.`ntotal {N} make answer`nsay answer`n"
    'in expression' = "to total n`n    if n is 0`n        return 0`n    .`n    m is n minus 1`n    rest is total m`n    return rest plus n`n.`nanswer is total {N}`nsay answer`n"
    'in loop body'  = "ones are`n    1`n.`nto total n`n    if n is 0`n        return 0`n    .`n    result is 0`n    for each k in ones`n        m is n minus 1`n        total m make result`n    .`n    return result plus n`n.`ntotal {N} make answer`nsay answer`n"
}

$failures = 0
try {
    $rows = foreach ($shape in $shapes.Keys) {
        foreach ($depth in $Depths) {
            $file = Join-Path $tmp 'probe.ot'
            [System.IO.File]::WriteAllText($file, $shapes[$shape].Replace('{N}', [string]$depth), [System.Text.UTF8Encoding]::new($false))
            $psi = [System.Diagnostics.ProcessStartInfo]::new('powershell.exe', "-NoProfile -ExecutionPolicy Bypass -File `"$Root\otter.ps1`" run `"$file`"")
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            $proc = [System.Diagnostics.Process]::Start($psi)
            $errTask = $proc.StandardError.ReadToEndAsync()
            $out = $proc.StandardOutput.ReadToEnd()
            $finished = $proc.WaitForExit(120000)
            if (-not $finished) { $proc.Kill() }
            $text = ($out + $errTask.Result).Trim()
            $expected = [string](($depth * ($depth + 1)) / 2)
            $want = if ($depth -lt $Limit) { 'correct' } else { 'clean limit error' }
            $got = if (-not $finished) { 'HANG' }
                elseif ($proc.ExitCode -eq 0 -and $text -eq $expected) { 'correct' }
                elseif ($proc.ExitCode -eq 3 -and $text -match 'Call depth limit exceeded') { 'clean limit error' }
                else { "UNEXPECTED (exit $($proc.ExitCode)): $($text -replace '\s+', ' ')" }
            if ($got -ne $want) { $failures++ }
            [pscustomobject]@{ Shape = $shape; Depth = $depth; Seconds = [math]::Round($watch.Elapsed.TotalSeconds, 1); Expected = $want; Result = $got }
        }
    }
    $rows | Format-Table -AutoSize | Out-String -Width 220 | Write-Output
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures -gt 0) {
    Write-Output "RECURSION PROBE FAILED: $failures case(s) did not behave."
    exit 1
}
Write-Output "Recursion probe passed ($(@($shapes.Keys).Count * $Depths.Count) cases, PowerShell $($PSVersionTable.PSVersion))."
exit 0
