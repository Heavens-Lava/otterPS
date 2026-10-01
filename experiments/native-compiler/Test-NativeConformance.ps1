# experiments/native-compiler/Test-NativeConformance.ps1
#
# The release conformance fixtures (conformance/manifest.json) through the
# EXPERIMENTAL compiled backend, judged by the manifest's own expectations
# (exit code; exact stdout, or a diagnostic phrase) - the same expectations
# tools/Test-OtterReleaseConformance.ps1 holds the interpreter to. Only
# console "run" fixtures apply (check-only and web fixtures do not run code);
# a fixture outside the compiled subset is reported as "not yet", never as a
# pass. Each fixture runs in a fresh temporary folder.
#
#   powershell -NoProfile -File experiments/native-compiler/Test-NativeConformance.ps1

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$runner = Join-Path $PSScriptRoot 'Invoke-OtterCompiled.ps1'
$manifest = Get-Content -LiteralPath (Join-Path $root 'conformance\manifest.json') -Raw | ConvertFrom-Json
$hostExe = (Get-Process -Id $PID).Path

$counts = [ordered]@{ pass = 0; fail = 0; 'not yet' = 0; 'not applicable' = 0 }
foreach ($case in $manifest.fixtures) {
    if ($case.mode -notin @('run', 'run-in-temp-directory')) {
        $counts['not applicable']++
        Write-Output ('  n/a      {0} ({1})' -f $case.name, $case.mode)
        continue
    }
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ('otter-native-conf-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $file = Join-Path $work (Split-Path -Leaf $case.source)
        Copy-Item -LiteralPath (Join-Path $root $case.source) -Destination $file
        Push-Location $work
        try { $output = & $hostExe -NoProfile -File $runner $file 2>&1 | ForEach-Object { "$_" }; $code = $LASTEXITCODE }
        finally { Pop-Location }
        $text = (@($output) -join "`n").Trim()
        if ($code -eq 4) {
            $counts['not yet']++
            Write-Output ('  not yet  {0}: {1}' -f $case.name, ($text -replace '^Not compiled: The compiled backend does not support ', '' -replace ' Run this program with otter run\.$', ''))
            continue
        }
        $problems = @()
        if ($code -ne [int]$case.expectedExitCode) { $problems += "exit $code, expected $($case.expectedExitCode)" }
        if ($null -ne $case.expectedStdout) {
            $expected = (@($case.expectedStdout) -join "`n").Trim()
            if ($text -cne $expected) { $problems += "stdout differs:`n--- expected`n$expected`n--- got`n$text" }
        }
        if ($case.expectedDiagnosticContains -and $text -notmatch [regex]::Escape([string]$case.expectedDiagnosticContains)) {
            $problems += "diagnostic lacks '$($case.expectedDiagnosticContains)'"
        }
        if ($problems.Count -eq 0) { $counts.pass++; Write-Output ('  pass     {0}' -f $case.name) }
        else { $counts.fail++; Write-Output ('  FAIL     {0}: {1}' -f $case.name, ($problems -join '; ')) }
    }
    finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Output ''
Write-Output ('Compiled backend on the conformance fixtures: {0} pass, {1} fail, {2} not yet compiled, {3} not applicable.' -f $counts.pass, $counts.fail, $counts['not yet'], $counts['not applicable'])
if ($counts.fail -gt 0) { exit 1 }
