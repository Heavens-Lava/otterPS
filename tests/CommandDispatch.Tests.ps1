using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Library.psm1
using module ..\src\Otter.Interpreter.psm1
using module ..\src\Otter.Project.psm1

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Otter Script-Aware Command Dispatch (D119-R1)" -ForegroundColor Cyan

$testTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_dispatch_tests_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testTmp -Force | Out-Null

function Run-OtterScript([string]$Code) {
    $scriptFile = Join-Path $testTmp ("test_" + [Guid]::NewGuid().ToString('N') + ".ot")
    Set-Content -LiteralPath $scriptFile -Value $Code -Encoding UTF8
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') run $scriptFile 2>&1
    $exitCode = $LASTEXITCODE
    Remove-Item -LiteralPath $scriptFile -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output -join "`n")
    }
}

try {
    # -------------------------------------------------------------
    # 1. Native executable dispatch
    # -------------------------------------------------------------
    $code1 = 'run command "cmd.exe /c echo native_exec_ok" into res' + "`n" +
             'say "EXIT:" exit code of res' + "`n" +
             'say "OUT:" output of res'
    $res1 = Run-OtterScript $code1
    if ($res1.ExitCode -ne 0) { throw "Test 1 failed with exit code $($res1.ExitCode): $($res1.Output)" }
    if ($res1.Output -notmatch 'EXIT:\s*0') { throw "Test 1 failed: Expected exit code 0. Got: $($res1.Output)" }
    if ($res1.Output -notmatch 'OUT:\s*native_exec_ok') { throw "Test 1 failed: Expected output 'native_exec_ok'. Got: $($res1.Output)" }
    Write-Output '  pass  native executable dispatch captures stdout, stderr, and exit code'

    # -------------------------------------------------------------
    # 2. PowerShell (.ps1) script dispatch
    # -------------------------------------------------------------
    $ps1Fixture = Join-Path $testTmp 'echo_args.ps1'
    $ps1Content = '[Console]::Error.WriteLine("PS_STDERR_MARKER")' + "`n" +
                  'Write-Output ("COUNT=" + $args.Count)' + "`n" +
                  'for ($i = 0; $i -lt $args.Count; $i++) {' + "`n" +
                  '    Write-Output ("ARG" + $i + "=" + $args[$i])' + "`n" +
                  '}' + "`n" +
                  'exit 42'
    Set-Content -LiteralPath $ps1Fixture -Value $ps1Content -Encoding UTF8

    $fixPathPs1 = $ps1Fixture.Replace('\', '/')
    $code2 = 'run command "' + $fixPathPs1 + ' alpha beta" into res' + "`n" +
             'say "EXIT:" exit code of res' + "`n" +
             'say "OUT:" output of res' + "`n" +
             'say "ERR:" error output of res'
    $res2 = Run-OtterScript $code2
    if ($res2.ExitCode -ne 0) { throw "Test 2 failed with exit code $($res2.ExitCode): $($res2.Output)" }
    if ($res2.Output -notmatch 'EXIT:\s*42') { throw "Test 2 failed: Expected exit code 42. Got: $($res2.Output)" }
    if ($res2.Output -notmatch 'COUNT=2') { throw "Test 2 failed: Expected 2 arguments. Got: $($res2.Output)" }
    if ($res2.Output -notmatch 'ARG0=alpha' -or $res2.Output -notmatch 'ARG1=beta') { throw "Test 2 failed: Argument mismatch. Got: $($res2.Output)" }
    if ($res2.Output -notmatch 'PS_STDERR_MARKER') { throw "Test 2 failed: Expected stderr marker. Got: $($res2.Output)" }
    Write-Output '  pass  powershell .ps1 dispatch executes via host and preserves streams and exit code'

    # -------------------------------------------------------------
    # 3. Windows CMD/BAT (.cmd) script dispatch
    # -------------------------------------------------------------
    $cmdFixture = Join-Path $testTmp 'echo_args.cmd'
    $cmdContent = "@echo off`necho CMD_STDERR_MARKER 1>&2`necho ARG0=%1`necho ARG1=%2`nexit /b 43`n"
    Set-Content -LiteralPath $cmdFixture -Value $cmdContent -Encoding ASCII

    $fixPathCmd = $cmdFixture.Replace('\', '/')
    $code3 = 'run command "' + $fixPathCmd + ' first second" into res' + "`n" +
             'say "EXIT:" exit code of res' + "`n" +
             'say "OUT:" output of res' + "`n" +
             'say "ERR:" error output of res'
    $res3 = Run-OtterScript $code3
    if ($res3.ExitCode -ne 0) { throw "Test 3 failed with exit code $($res3.ExitCode): $($res3.Output)" }
    if ($res3.Output -notmatch 'EXIT:\s*43') { throw "Test 3 failed: Expected exit code 43. Got: $($res3.Output)" }
    if ($res3.Output -notmatch 'ARG0=first' -or $res3.Output -notmatch 'ARG1=second') { throw "Test 3 failed: Argument mismatch. Got: $($res3.Output)" }
    if ($res3.Output -notmatch 'CMD_STDERR_MARKER') { throw "Test 3 failed: Expected stderr marker. Got: $($res3.Output)" }
    Write-Output '  pass  windows .cmd dispatch executes via cmd.exe and preserves streams and exit code'

    # -------------------------------------------------------------
    # 4. Argument safety: spaces, quotes, empty string, Unicode, metacharacters
    # -------------------------------------------------------------
    $argFixture = Join-Path $testTmp 'check_args.ps1'
    $argContent = 'Write-Output ("COUNT=" + $args.Count)' + "`n" +
                  'for ($i = 0; $i -lt $args.Count; $i++) {' + "`n" +
                  '    Write-Output ("ARG" + $i + "=[" + $args[$i] + "]")' + "`n" +
                  '}' + "`n" +
                  'exit 0'
    Set-Content -LiteralPath $argFixture -Value $argContent -Encoding UTF8

    $fixPathArg = $argFixture.Replace('\', '/')
    $innerCmd = $fixPathArg + ' \"hello world\" \"\" \"quote\"\"inside\" \"test_unicode_fox\" \"foo & bar | baz < qux > out ^ caret\" \"C:/path with spaces/file.txt\"'
    $code4 = 'run command "' + $innerCmd + '" into res' + "`n" +
             'say "EXIT:" exit code of res' + "`n" +
             'say output of res'
    $res4 = Run-OtterScript $code4
    if ($res4.ExitCode -ne 0) { throw "Test 4 failed with exit code $($res4.ExitCode): $($res4.Output)" }
    if ($res4.Output -notmatch 'COUNT=6') { throw "Test 4 failed: Expected COUNT=6. Got: $($res4.Output)" }
    if ($res4.Output -notmatch 'ARG0=\[hello world\]') { throw "Test 4 failed: ARG0 spaces mismatch. Got: $($res4.Output)" }
    if ($res4.Output -notmatch 'ARG1=\[\]') { throw "Test 4 failed: ARG1 empty arg mismatch. Got: $($res4.Output)" }
    if ($res4.Output -notmatch 'ARG2=\[quote"inside\]') { throw "Test 4 failed: ARG2 quote inside mismatch. Got: $($res4.Output)" }
    if ($res4.Output -notmatch 'ARG3=\[test_unicode_fox\]') { throw "Test 4 failed: ARG3 Unicode mismatch. Got: $($res4.Output)" }
    if ($res4.Output -notmatch 'ARG4=\[foo & bar \| baz < qux > out \^ caret\]') { throw "Test 4 failed: ARG4 metacharacters mismatch. Got: $($res4.Output)" }
    if ($res4.Output -notmatch 'ARG5=\[C:/path with spaces/file\.txt\]') { throw "Test 4 failed: ARG5 path with spaces mismatch. Got: $($res4.Output)" }
    Write-Output '  pass  argument safety preserves spaces, empty string, quotes, Unicode, paths, and metacharacters'

    # -------------------------------------------------------------
    # 5. Deadlock safety: high volume stdout and stderr concurrent writes
    # -------------------------------------------------------------
    $deadlockFixture = Join-Path $testTmp 'deadlock_test.ps1'
    $deadlockContent = '$chunkOut = "O" * 4096' + "`n" +
                       '$chunkErr = "E" * 4096' + "`n" +
                       'for ($i = 0; $i -lt 25; $i++) {' + "`n" +
                       '    [Console]::Out.WriteLine($chunkOut)' + "`n" +
                       '    [Console]::Error.WriteLine($chunkErr)' + "`n" +
                       '}' + "`n" +
                       'exit 0'
    Set-Content -LiteralPath $deadlockFixture -Value $deadlockContent -Encoding UTF8

    $fixPathDead = $deadlockFixture.Replace('\', '/')
    $code5 = 'run command "' + $fixPathDead + '" into res' + "`n" +
             'say "EXIT:" exit code of res' + "`n" +
             'outText is output of res' + "`n" +
             'errText is error output of res' + "`n" +
             'say "OUT_LEN:" length of outText' + "`n" +
             'say "ERR_LEN:" length of errText'
    $res5 = Run-OtterScript $code5
    if ($res5.ExitCode -ne 0) { throw "Test 5 failed with exit code $($res5.ExitCode): $($res5.Output)" }
    if ($res5.Output -notmatch 'EXIT:\s*0') { throw "Test 5 failed: Expected exit code 0. Got: $($res5.Output)" }
    if ($res5.Output -notmatch 'OUT_LEN:\s*(1024|1025|1026)\d\d') { throw "Test 5 failed: Expected ~100KB stdout. Got: $($res5.Output)" }
    if ($res5.Output -notmatch 'ERR_LEN:\s*(1024|1025|1026)\d\d') { throw "Test 5 failed: Expected ~100KB stderr. Got: $($res5.Output)" }
    Write-Output '  pass  deadlock safety confirms concurrent stdout and stderr drainage without hanging'

    # -------------------------------------------------------------
    # 6. Otter self-hosting: otter --version
    # -------------------------------------------------------------
    $code6 = 'run command "otter --version" into res' + "`n" +
             'say "EXIT:" exit code of res' + "`n" +
             'say "OUT:" output of res'
    $res6 = Run-OtterScript $code6
    if ($res6.ExitCode -ne 0) { throw "Test 6 failed with exit code $($res6.ExitCode): $($res6.Output)" }
    if ($res6.Output -notmatch 'EXIT:\s*0') { throw "Test 6 failed: Expected exit code 0. Got: $($res6.Output)" }
    if ($res6.Output -notmatch 'Otter 0\.9\.0') { throw "Test 6 failed: Expected 'Otter 0.9.0' in output. Got: $($res6.Output)" }
    Write-Output '  pass  otter self-hosting: otter --version executes cleanly and reports 0.9.0'

    # -------------------------------------------------------------
    # 7. Otter self-hosting: otter check <valid-project>
    # -------------------------------------------------------------
    $validProjDir = Join-Path $testTmp 'ValidProject'
    New-Item -ItemType Directory -Path $validProjDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $validProjDir 'main.ot') -Value 'say "hello from valid project"' -Encoding UTF8
    $validManifest = '{' + "`n" +
                     '  "$schema": "https://otter-lang.org/schema/project-v1.json",' + "`n" +
                     '  "name": "ValidProject",' + "`n" +
                     '  "version": "0.1.0",' + "`n" +
                     '  "target": "console",' + "`n" +
                     '  "entryPoint": "main.ot"' + "`n" +
                     '}'
    Set-Content -LiteralPath (Join-Path $validProjDir 'otter.json') -Value $validManifest -Encoding UTF8

    $fixPathValid = $validProjDir.Replace('\', '/')
    $code7 = "run command `"otter check $fixPathValid`" into res" + "`n" +
             'say "EXIT:" exit code of res' + "`n" +
             'say "OUT:" output of res'
    $res7 = Run-OtterScript $code7
    if ($res7.ExitCode -ne 0) { throw "Test 7 failed with exit code $($res7.ExitCode): $($res7.Output)" }
    if ($res7.Output -notmatch 'EXIT:\s*0') { throw "Test 7 failed: Expected exit code 0. Got: $($res7.Output)" }
    if ($res7.Output -notmatch 'is valid') { throw "Test 7 failed: Expected 'is valid'. Got: $($res7.Output)" }
    Write-Output '  pass  otter self-hosting: otter check against valid project succeeds with exit code 0'

    # -------------------------------------------------------------
    # 8. Otter self-hosting: otter check <invalid-project>
    # -------------------------------------------------------------
    $invalidProjDir = Join-Path $testTmp 'InvalidProject'
    New-Item -ItemType Directory -Path $invalidProjDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $invalidProjDir 'main.ot') -Value "if 10 is`n  say `"bad`"" -Encoding UTF8
    $invalidManifest = '{' + "`n" +
                       '  "$schema": "https://otter-lang.org/schema/project-v1.json",' + "`n" +
                       '  "name": "InvalidProject",' + "`n" +
                       '  "version": "0.1.0",' + "`n" +
                       '  "target": "console",' + "`n" +
                       '  "entryPoint": "main.ot"' + "`n" +
                       '}'
    Set-Content -LiteralPath (Join-Path $invalidProjDir 'otter.json') -Value $invalidManifest -Encoding UTF8

    $fixPathInvalid = $invalidProjDir.Replace('\', '/')
    $code8 = "run command `"otter check $fixPathInvalid`" into res" + "`n" +
             'say "EXIT:" exit code of res'
    $res8 = Run-OtterScript $code8
    if ($res8.ExitCode -ne 0) { throw "Test 8 failed with exit code $($res8.ExitCode): $($res8.Output)" }
    if ($res8.Output -notmatch 'EXIT:\s*2') { throw "Test 8 failed: Expected exit code 2 for syntax check failure. Got: $($res8.Output)" }
    Write-Output '  pass  otter self-hosting: otter check against syntax error reports exit code 2'

    # -------------------------------------------------------------
    # 9. Clean failure: unknown command produces clean Otter runtime error
    # -------------------------------------------------------------
    $code9 = 'try' + "`n" +
             '    run command "nonexistent_command_xyz_998877" into res' + "`n" +
             '    say "UNEXPECTED_SUCCESS"' + "`n" +
             'otherwise into err' + "`n" +
             '    say "CAUGHT:" err' + "`n" +
             '.'
    $res9 = Run-OtterScript $code9
    if ($res9.ExitCode -ne 0) { throw "Test 9 failed: $($res9.Output)" }
    if ($res9.Output -notmatch 'CAUGHT:.*could not find a program called "nonexistent_command_xyz_998877"') {
        throw "Test 9 failed: Expected clean Otter runtime error. Got: $($res9.Output)"
    }
    Write-Output '  pass  clean failure for non-existent command produces standard Otter runtime error'

    # -------------------------------------------------------------
    # 10. Host detection utility
    # -------------------------------------------------------------
    $psHost = Get-OtterPowerShellHost
    if ([string]::IsNullOrWhiteSpace($psHost)) {
        throw "Test 10 failed: Get-OtterPowerShellHost returned empty"
    }
    if ($psHost -notmatch '(?i)powershell(\.exe)?$' -and $psHost -notmatch '(?i)pwsh(\.exe)?$') {
        throw "Test 10 failed: Host '$psHost' does not match powershell/pwsh"
    }
    Write-Output "  pass  host detection returns active host: $psHost"
}
finally {
    Remove-Item -LiteralPath $testTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`nAll Otter command dispatch tests passed (10/10).`n" -ForegroundColor Green
