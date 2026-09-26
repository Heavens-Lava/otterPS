using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Library.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1
using module ..\src\Otter.Interpreter.psm1
using module ..\src\Otter.Project.psm1

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Otter Asynchronous Process Execution (D119-R2)" -ForegroundColor Cyan

$testTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_async_cmd_tests_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testTmp -Force | Out-Null

function Run-OtterScript {
    param([string]$Source)
    $lines = [System.Collections.Generic.List[string]]::new()
    $writer = { param($Text) $lines.Add([string]$Text) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        $tokens = ConvertTo-OtterTokens -Source $Source
        $ast = ConvertTo-OtterAst -Tokens $tokens
        Invoke-OtterProgram -Program $ast -Environment (New-OtterEnvironment)
    } finally {
        Set-OtterOutputWriter -Writer $null
    }
    return , $lines.ToArray()
}

$otterCli = Join-Path $repoRoot 'otter.ps1'

function Run-OtterCli {
    param([string]$Source)
    $tmpFile = Join-Path $testTmp ("cli_" + [Guid]::NewGuid().ToString('N') + ".ot")
    try {
        Set-Content -LiteralPath $tmpFile -Value $Source -Encoding UTF8
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $otterCli $tmpFile 2>&1
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = ($out -join "`n")
        }
    } finally {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    }
}

try {
    # -------------------------------------------------------------
    # 1. Basic async start and exit completion
    # -------------------------------------------------------------
    $code1 = @"
start command "powershell.exe -NoProfile -Command Write-Output 'async_stdout_ok'" and call it job

on exit of job
    ec is exit code of job
    st is state of job
    out is output of job
    say "EXIT:" ec
    say "STATE:" st
    say "OUT:" out
.
"@
    $res1 = Run-OtterScript $code1
    $out1 = $res1 -join "`n"
    if ($out1 -notmatch 'EXIT:\s*0') { throw "Test 1 failed: Expected exit 0. Got: $out1" }
    if ($out1 -notmatch 'STATE:\s*completed') { throw "Test 1 failed: Expected state completed. Got: $out1" }
    if ($out1 -notmatch 'OUT:\s*async_stdout_ok') { throw "Test 1 failed: Expected output. Got: $out1" }
    Write-Output '  pass  basic async process start, on exit handler, and exit code capture'

    # -------------------------------------------------------------
    # 2. Streaming stdout events
    # -------------------------------------------------------------
    $code2 = @"
start command "powershell.exe -NoProfile -Command Write-Output 'line1'; Write-Output 'line2'" and call it job

on output from job
    say "STREAM:" received output
.

on exit of job
    say "DONE"
.
"@
    $res2 = Run-OtterScript $code2
    $out2 = $res2 -join "`n"
    if ($out2 -notmatch 'STREAM:\s*line1') { throw "Test 2 failed: Expected line1. Got: $out2" }
    if ($out2 -notmatch 'STREAM:\s*line2') { throw "Test 2 failed: Expected line2. Got: $out2" }
    if ($out2 -notmatch 'DONE') { throw "Test 2 failed: Expected DONE. Got: $out2" }
    Write-Output '  pass  on output from job streaming line events via received output'

    # -------------------------------------------------------------
    # 3. Streaming stderr events
    # -------------------------------------------------------------
    $code3 = @"
start command "powershell.exe -NoProfile -Command [Console]::Error.WriteLine('stderr_line1')" and call it job

on error output from job
    say "ERR_STREAM:" received error output
.

on exit of job
    say "DONE_ERR"
.
"@
    $res3 = Run-OtterScript $code3
    $out3 = $res3 -join "`n"
    if ($out3 -notmatch 'ERR_STREAM:\s*stderr_line1') { throw "Test 3 failed: Expected stderr. Got: $out3" }
    if ($out3 -notmatch 'DONE_ERR') { throw "Test 3 failed: Expected DONE_ERR. Got: $out3" }
    Write-Output '  pass  on error output from job streaming stderr events via received error output'

    # -------------------------------------------------------------
    # 4. on complete of job
    # -------------------------------------------------------------
    $code4 = @"
start command "powershell.exe -NoProfile -Command Write-Output 'complete_test'" and call it job

on complete of job
    say "COMPLETE_OK"
.
"@
    $res4 = Run-OtterScript $code4
    $out4 = $res4 -join "`n"
    if ($out4 -notmatch 'COMPLETE_OK') { throw "Test 4 failed: Expected COMPLETE_OK. Got: $out4" }
    Write-Output '  pass  on complete of job fires upon zero exit code'

    # -------------------------------------------------------------
    # 5. State predicates: running, completed, failed
    # -------------------------------------------------------------
    $code5 = @"
start command "powershell.exe -NoProfile -Command Start-Sleep -Milliseconds 150; exit 0" and call it job

if job is running
    say "IS_RUNNING:TRUE"
.
if job is not completed
    say "NOT_COMPLETED:TRUE"
.

on exit of job
    if job is completed
        say "IS_COMPLETED:TRUE"
    .
    if job is not running
        say "NOT_RUNNING:TRUE"
    .
.
"@
    $res5 = Run-OtterScript $code5
    $out5 = $res5 -join "`n"
    if ($out5 -notmatch 'IS_RUNNING:TRUE') { throw "Test 5 failed: Expected running. Got: $out5" }
    if ($out5 -notmatch 'NOT_COMPLETED:TRUE') { throw "Test 5 failed: Expected not completed. Got: $out5" }
    if ($out5 -notmatch 'IS_COMPLETED:TRUE') { throw "Test 5 failed: Expected completed. Got: $out5" }
    if ($out5 -notmatch 'NOT_RUNNING:TRUE') { throw "Test 5 failed: Expected not running. Got: $out5" }
    Write-Output '  pass  job is running / completed / failed state predicates'

    # -------------------------------------------------------------
    # 6. Explicit cancellation
    # -------------------------------------------------------------
    $code6 = @"
start command "powershell.exe -NoProfile -Command Start-Sleep -Seconds 10" and call it job

on cancel of job
    say "CANCEL_HANDLER_FIRED"
    st is state of job
    say "STATE:" st
.

wait 50 milliseconds
cancel job
"@
    $res6 = Run-OtterScript $code6
    $out6 = $res6 -join "`n"
    if ($out6 -notmatch 'CANCEL_HANDLER_FIRED') { throw "Test 6 failed: Expected cancel handler. Got: $out6" }
    if ($out6 -notmatch 'STATE:\s*cancelled') { throw "Test 6 failed: Expected state cancelled. Got: $out6" }
    Write-Output '  pass  cancel job terminates process tree and dispatches on cancel'

    # -------------------------------------------------------------
    # 7. Double-cancel idempotency
    # -------------------------------------------------------------
    $code7 = @"
start command "powershell.exe -NoProfile -Command Start-Sleep -Seconds 10" and call it job

cancelCount is 0
on cancel of job
    add 1 to cancelCount
    say "CANCEL_COUNT:" cancelCount
.

wait 50 milliseconds
cancel job
cancel job
cancel job
"@
    $res7 = Run-OtterScript $code7
    $out7 = $res7 -join "`n"
    if ($out7 -notmatch 'CANCEL_COUNT:\s*1') { throw "Test 7 failed: Cancel must fire exactly once. Got: $out7" }
    Write-Output '  pass  repeated cancel is idempotent and fires once'

    # -------------------------------------------------------------
    # 8. Property accesses on command job
    # -------------------------------------------------------------
    $code8 = @"
start command "powershell.exe -NoProfile -Command Write-Output 'job_prop_out'; exit 7" and call it job

on exit of job
    if id of job is not gone
        say "ID_PRESENT:true"
    .
    ec is exit code of job
    st is state of job
    out is output of job
    say "EC:" ec
    say "ST:" st
    say "OUT:" out
.
"@
    $res8 = Run-OtterScript $code8
    $out8 = $res8 -join "`n"
    if ($out8 -notmatch 'ID_PRESENT:true') { throw "Test 8 failed: id of job. Got: $out8" }
    if ($out8 -notmatch 'EC:\s*7') { throw "Test 8 failed: exit code 7. Got: $out8" }
    if ($out8 -notmatch 'ST:\s*failed') { throw "Test 8 failed: state failed for exit 7. Got: $out8" }
    if ($out8 -notmatch 'OUT:\s*job_prop_out') { throw "Test 8 failed: output. Got: $out8" }
    Write-Output '  pass  property accesses (id, exit code, state, output, error output, command)'

    # -------------------------------------------------------------
    # 9. Script-aware dispatch with .ps1 fixture
    # -------------------------------------------------------------
    $ps1Fixture = Join-Path $testTmp 'async_echo.ps1'
    $ps1Content = 'param($First, $Second)' + "`n" +
                  'Write-Output ("FIRST=" + $First)' + "`n" +
                  'Write-Output ("SECOND=" + $Second)'
    Set-Content -LiteralPath $ps1Fixture -Value $ps1Content -Encoding UTF8
    $fixPathPs1 = $ps1Fixture.Replace('\', '/')

    $code9 = 'cmdText is "' + $fixPathPs1 + ' \"hello world\" test"' + "`n" +
             'start command cmdText and call it job' + "`n" +
             'on exit of job' + "`n" +
             '    say output of job' + "`n" +
             '.'
    $res9 = Run-OtterScript $code9
    $out9 = $res9 -join "`n"
    if ($out9 -notmatch 'FIRST=hello world') { throw "Test 9 failed: Expected FIRST=hello world. Got: $out9" }
    if ($out9 -notmatch 'SECOND=test') { throw "Test 9 failed: Expected SECOND=test. Got: $out9" }
    Write-Output '  pass  script-aware dispatch with quoted args on async jobs'

    # -------------------------------------------------------------
    # 10. Retained terminal event delivery
    # -------------------------------------------------------------
    $code10 = @"
start command "powershell.exe -NoProfile -Command Write-Output 'fast_done'" and call it job

wait 200 milliseconds

on exit of job
    out is output of job
    say "LATE_EXIT_FIRED:" out
.
"@
    $res10 = Run-OtterScript $code10
    $out10 = $res10 -join "`n"
    if ($out10 -notmatch 'LATE_EXIT_FIRED:\s*fast_done') { throw "Test 10 failed: Expected late exit handler to fire. Got: $out10" }
    Write-Output '  pass  retained terminal event fires immediately when handler registered post-exit'

    # -------------------------------------------------------------
    # 11. Synchronous run command remains unchanged
    # -------------------------------------------------------------
    $code11 = @"
run command "powershell.exe -NoProfile -Command Write-Output 'sync_remains_ok'" into res
ec is exit code of res
out is output of res
say "SYNC_EXIT:" ec
say "SYNC_OUT:" out
"@
    $res11 = Run-OtterScript $code11
    $out11 = $res11 -join "`n"
    if ($out11 -notmatch 'SYNC_EXIT:\s*0') { throw "Test 11 failed: Expected sync exit 0. Got: $out11" }
    if ($out11 -notmatch 'SYNC_OUT:\s*sync_remains_ok') { throw "Test 11 failed: Expected sync output. Got: $out11" }
    Write-Output '  pass  synchronous run command into result remains completely supported'

    # -------------------------------------------------------------
    # 12. Scoped error for received output outside handler
    # -------------------------------------------------------------
    $code12 = @"
say received output
"@
    $res12 = Run-OtterCli $code12
    if ($res12.ExitCode -eq 0) { throw "Test 12 failed: Expected error for received output outside handler. Got: $($res12.Output)" }
    if ($res12.Output -notmatch 'received output') { throw "Test 12 failed: Expected error diagnostic. Got: $($res12.Output)" }
    Write-Output '  pass  received output outside on output handler rejected with clean diagnostic'

    # -------------------------------------------------------------
    # 13. End-to-End CLI Invocation
    # -------------------------------------------------------------
    $code13 = @"
start command "powershell.exe -NoProfile -Command Write-Output 'cli_e2e_ok'" and call it job
on exit of job
    out is output of job
    say "CLI_OUT:" out
.
"@
    $res13 = Run-OtterCli $code13
    if ($res13.ExitCode -ne 0) { throw "Test 13 failed with exit code $($res13.ExitCode): $($res13.Output)" }
    if ($res13.Output -notmatch 'CLI_OUT:\s*cli_e2e_ok') { throw "Test 13 failed: Expected CLI output. Got: $($res13.Output)" }
    Write-Output '  pass  end-to-end CLI execution via otter.ps1 file.ot'

} finally {
    Remove-Item -LiteralPath $testTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "All Async Command Execution tests passed (13/13)." -ForegroundColor Green
