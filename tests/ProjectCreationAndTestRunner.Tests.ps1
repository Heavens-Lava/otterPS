using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Project.psm1

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Otter Project Creation and Test Runner (D118C)" -ForegroundColor Cyan

$testTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d118c_tests_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testTmp -Force | Out-Null

try {
    # Test 1: New-OtterProject generates console archetype with correct structure
    $cProj = New-OtterProject -Archetype 'console' -Name 'ConsoleApp' -Path $testTmp
    if ($cProj.Name -ne 'ConsoleApp') { throw "Test 1 failed: Expected Name ConsoleApp, got $($cProj.Name)" }
    if ($cProj.Archetype -ne 'console') { throw "Test 1 failed: Expected Archetype console, got $($cProj.Archetype)" }
    if ($cProj.Target -ne 'console') { throw "Test 1 failed: Expected Target console, got $($cProj.Target)" }
    if ($cProj.EntryPoint -ne 'main.ot') { throw "Test 1 failed: Expected EntryPoint main.ot, got $($cProj.EntryPoint)" }
    
    $cDir = $cProj.RootDirectory
    if (-not (Test-Path -LiteralPath (Join-Path $cDir 'src') -PathType Container)) { throw "Test 1 failed: Missing src/ dir" }
    if (-not (Test-Path -LiteralPath (Join-Path $cDir 'tests') -PathType Container)) { throw "Test 1 failed: Missing tests/ dir" }
    if (-not (Test-Path -LiteralPath (Join-Path $cDir 'assets') -PathType Container)) { throw "Test 1 failed: Missing assets/ dir" }
    if (-not (Test-Path -LiteralPath (Join-Path $cDir 'main.ot') -PathType Leaf)) { throw "Test 1 failed: Missing main.ot" }
    if (-not (Test-Path -LiteralPath (Join-Path $cDir 'tests/app_test.ot') -PathType Leaf)) { throw "Test 1 failed: Missing tests/app_test.ot" }
    if (-not (Test-Path -LiteralPath (Join-Path $cDir 'otter.json') -PathType Leaf)) { throw "Test 1 failed: Missing otter.json" }

    $cCheck = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') check $cDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 1 failed: otter check ConsoleApp exited with $LASTEXITCODE. Output: $cCheck" }
    Write-Output '  pass  New-OtterProject generates valid console archetype passing `otter check`'

    # Test 2: New-OtterProject generates desktop archetype with CSS asset and valid code
    $dProj = New-OtterProject -Archetype 'desktop' -Name 'DesktopApp' -Path $testTmp
    $dDir = $dProj.RootDirectory
    if ($dProj.Target -ne 'desktop') { throw "Test 2 failed: Expected Target desktop, got $($dProj.Target)" }
    if (-not (Test-Path -LiteralPath (Join-Path $dDir 'assets/styles.css') -PathType Leaf)) { throw "Test 2 failed: Missing assets/styles.css" }
    $dCheck = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') check $dDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 2 failed: otter check DesktopApp exited with $LASTEXITCODE. Output: $dCheck" }
    Write-Output '  pass  New-OtterProject generates valid desktop archetype passing `otter check`'

    # Test 3: New-OtterProject generates web archetype with CSS asset and valid code
    $wProj = New-OtterProject -Archetype 'web' -Name 'WebApp' -Path $testTmp
    $wDir = $wProj.RootDirectory
    if ($wProj.Target -ne 'web') { throw "Test 3 failed: Expected Target web, got $($wProj.Target)" }
    if (-not (Test-Path -LiteralPath (Join-Path $wDir 'assets/styles.css') -PathType Leaf)) { throw "Test 3 failed: Missing assets/styles.css" }
    $wCheck = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') check $wDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 3 failed: otter check WebApp exited with $LASTEXITCODE. Output: $wCheck" }
    Write-Output '  pass  New-OtterProject generates valid web archetype passing `otter check`'

    # Test 4: New-OtterProject generates automation archetype with valid code
    $aProj = New-OtterProject -Archetype 'automation' -Name 'AutoApp' -Path $testTmp
    $aDir = $aProj.RootDirectory
    $aCheck = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') check $aDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 4 failed: otter check AutoApp exited with $LASTEXITCODE. Output: $aCheck" }
    Write-Output '  pass  New-OtterProject generates valid automation archetype passing `otter check`'

    # Test 5: New-OtterProject generates game archetype with canvas and valid code
    $gProj = New-OtterProject -Archetype 'game' -Name 'GameApp' -Path $testTmp
    $gDir = $gProj.RootDirectory
    if ($gProj.Target -ne 'game') { throw "Test 5 failed: Expected Target game, got $($gProj.Target)" }
    $gCheck = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') check $gDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 5 failed: otter check GameApp exited with $LASTEXITCODE. Output: $gCheck" }
    Write-Output '  pass  New-OtterProject generates valid game archetype passing `otter check`'

    # Test 6: New-OtterProject validation rules
    # 6a: Invalid archetype throws OtterError
    $threw6a = $false
    try {
        New-OtterProject -Archetype 'quantum' -Name 'QuantumApp' -Path $testTmp
    } catch [OtterError] {
        $threw6a = $true
        if ($_.Exception.Message -notmatch 'archetype "quantum" is not supported') {
            throw "Test 6a failed: Unexpected error message: $($_.Exception.Message)"
        }
    }
    if (-not $threw6a) { throw "Test 6a failed: Expected invalid archetype to throw OtterError" }

    # 6b: Invalid project name throws OtterError
    $threw6b = $false
    try {
        New-OtterProject -Archetype 'console' -Name 'Bad*Name' -Path $testTmp
    } catch [OtterError] {
        $threw6b = $true
        if ($_.Exception.Message -notmatch 'not a valid project name') {
            throw "Test 6b failed: Unexpected error message: $($_.Exception.Message)"
        }
    }
    if (-not $threw6b) { throw "Test 6b failed: Expected invalid project name to throw OtterError" }

    # 6c: Existing non-empty directory fails and refuses to overwrite
    $threw6c = $false
    try {
        New-OtterProject -Archetype 'console' -Name 'ConsoleApp' -Path $testTmp
    } catch [OtterError] {
        $threw6c = $true
        if ($_.Exception.Message -notmatch 'already exists and is not empty') {
            throw "Test 6c failed: Unexpected error message: $($_.Exception.Message)"
        }
    }
    if (-not $threw6c) { throw "Test 6c failed: Expected existing non-empty directory to throw OtterError" }
    Write-Output '  pass  New-OtterProject rejects invalid archetype, invalid name, and non-empty destination'

    # Test 7: CLI `otter new` invocation
    $prevCwd = (Get-Location).Path
    try {
        Set-Location -LiteralPath $testTmp
        $newCliOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') new console CliApp 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Test 7 failed: otter new console CliApp exited with $LASTEXITCODE. Output: $newCliOut" }
        if (($newCliOut -join "`n") -notmatch 'Created new Otter console project') {
            throw "Test 7 failed: Output missing success message: $newCliOut"
        }
        if (-not (Test-Path -LiteralPath (Join-Path $testTmp 'CliApp/otter.json') -PathType Leaf)) {
            throw "Test 7 failed: CliApp/otter.json was not created"
        }
    } finally {
        Set-Location -LiteralPath $prevCwd
    }
    Write-Output '  pass  CLI: `otter new console <name>` creates project and displays getting started tips'

    # Test 8: CLI `otter new` usage errors
    $errNew1 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') new 2>&1
    if ($LASTEXITCODE -ne 1) { throw "Test 8a failed: Expected exit code 1 for otter new without args, got $LASTEXITCODE" }
    if (($errNew1 -join "`n") -notmatch 'Usage: otter new') { throw "Test 8a failed: Expected usage message" }

    $errNew2 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') new invalid Foo 2>&1
    if ($LASTEXITCODE -ne 1) { throw "Test 8b failed: Expected exit code 1 for unknown archetype, got $LASTEXITCODE" }
    if (($errNew2 -join "`n") -notmatch 'Unknown archetype') { throw "Test 8b failed: Expected unknown archetype message" }

    $errNew3 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') new console 2>&1
    if ($LASTEXITCODE -ne 1) { throw "Test 8c failed: Expected exit code 1 for missing project name, got $LASTEXITCODE" }
    Write-Output '  pass  CLI: `otter new` usage errors report exit code 1 with clear guidance'

    # Test 9: Get-OtterProjectTestFiles discovers test files accurately
    $pTestDir = Join-Path $testTmp 'DiscoveryApp'
    $dTestsDir = Join-Path $pTestDir 'tests'
    New-Item -ItemType Directory -Path $dTestsDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $pTestDir 'otter.json') -Value '{"name":"DiscoveryApp","entryPoint":"main.ot"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $pTestDir 'main.ot') -Value 'say "ok"' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $dTestsDir 'alpha_test.ot') -Value 'say "alpha"' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $dTestsDir 'test_beta.ot') -Value 'say "beta"' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $dTestsDir 'helpers.ot') -Value 'say "helper"' -Encoding UTF8

    $subTestsDir = Join-Path $dTestsDir 'unit'
    New-Item -ItemType Directory -Path $subTestsDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $subTestsDir 'gamma_test.ot') -Value 'say "gamma"' -Encoding UTF8

    $foundTestFiles = Get-OtterProjectTestFiles -Target $pTestDir
    if ($foundTestFiles.Count -ne 3) { throw "Test 9 failed: Expected 3 test files, found $($foundTestFiles.Count)" }
    $foundNames = @($foundTestFiles | ForEach-Object { Split-Path -Leaf $_ })
    if ($foundNames -notcontains 'alpha_test.ot' -or $foundNames -notcontains 'test_beta.ot' -or $foundNames -notcontains 'gamma_test.ot') {
        throw "Test 9 failed: Missing expected discovered files. Found: $($foundNames -join ', ')"
    }
    if ($foundNames -contains 'helpers.ot') {
        throw "Test 9 failed: Discovered helpers.ot which does not match test naming convention"
    }
    Write-Output '  pass  Get-OtterProjectTestFiles recursively discovers `*_test.ot` and `test_*.ot`'

    # Test 10: Generated projects pass `otter test` out of the box
    $testRunOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') test $cDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 10 failed: otter test ConsoleApp exited with $LASTEXITCODE. Output: $testRunOut" }
    if (($testRunOut -join "`n") -notmatch 'PASS tests/app_test\.ot') { throw "Test 10 failed: Expected PASS tests/app_test.ot. Output: $testRunOut" }
    if (($testRunOut -join "`n") -notmatch '1 passed') { throw "Test 10 failed: Expected summary '1 passed'. Output: $testRunOut" }
    Write-Output '  pass  CLI: `otter test <project>` passes generated project tests out of the box'

    # Test 11: `otter test` in current directory discovers and runs tests
    $prevCwd = (Get-Location).Path
    try {
        Set-Location -LiteralPath $cDir
        $dotTestOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') test . 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Test 11a failed: otter test . exited with $LASTEXITCODE. Output: $dotTestOut" }
        if (($dotTestOut -join "`n") -notmatch 'PASS tests/app_test\.ot') { throw "Test 11a failed: Output: $dotTestOut" }

        $bareTestOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') test 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Test 11b failed: bare otter test exited with $LASTEXITCODE. Output: $bareTestOut" }
        if (($bareTestOut -join "`n") -notmatch 'PASS tests/app_test\.ot') { throw "Test 11b failed: Output: $bareTestOut" }
    } finally {
        Set-Location -LiteralPath $prevCwd
    }
    Write-Output '  pass  CLI: `otter test` and `otter test .` run project tests from inside project root'

    # Test 12: `otter test` with single test file
    $singleTestFile = Join-Path $cDir 'tests/app_test.ot'
    $singleTestOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') test $singleTestFile 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 12 failed: otter test <file> exited with $LASTEXITCODE. Output: $singleTestOut" }
    if (($singleTestOut -join "`n") -notmatch 'PASS') { throw "Test 12 failed: Expected PASS for single file test. Output: $singleTestOut" }
    Write-Output '  pass  CLI: `otter test <file.ot>` executes single test file in isolation'

    # Test 13: Test failure reporting via `fail with` (D68) produces FAIL, line number, message, and exit 3
    $failProjDir = Join-Path $testTmp 'FailingApp'
    $fProj = New-OtterProject -Archetype 'console' -Name 'FailingApp' -Path $testTmp
    $fTestFile = Join-Path $failProjDir 'tests/app_test.ot'
    $fTestCode = @"
# Failing test demo
result is 2 + 2

if result is not 5
    fail with "Expected result to be 5."
.
"@
    Set-Content -LiteralPath $fTestFile -Value $fTestCode -Encoding UTF8

    $failTestOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') test $failProjDir 2>&1
    if ($LASTEXITCODE -ne 3) { throw "Test 13 failed: Expected exit code 3 for test failure, got $LASTEXITCODE. Output: $failTestOut" }
    $failJoined = $failTestOut -join "`n"
    if ($failJoined -notmatch 'FAIL tests/app_test\.ot') { throw "Test 13 failed: Expected FAIL indicator. Output: $failJoined" }
    if ($failJoined -notmatch 'Expected result to be 5\.') { throw "Test 13 failed: Expected failure message 'Expected result to be 5.'. Output: $failJoined" }
    if ($failJoined -notmatch '1 failed') { throw "Test 13 failed: Expected summary '1 failed'. Output: $failJoined" }
    Write-Output '  pass  CLI: `fail with` in test produces structured FAIL reporting with exit code 3'

    # Test 14: Test syntax error produces FAIL (syntax error), diagnostics, and exit code 2
    $synProjDir = Join-Path $testTmp 'SyntaxApp'
    $sProj = New-OtterProject -Archetype 'console' -Name 'SyntaxApp' -Path $testTmp
    $sTestFile = Join-Path $synProjDir 'tests/app_test.ot'
    $sTestCode = @"
# Syntax error in test
result is
"@
    Set-Content -LiteralPath $sTestFile -Value $sTestCode -Encoding UTF8

    $synTestOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') test $synProjDir 2>&1
    if ($LASTEXITCODE -ne 2) { throw "Test 14 failed: Expected exit code 2 for test syntax error, got $LASTEXITCODE. Output: $synTestOut" }
    $synJoined = $synTestOut -join "`n"
    if ($synJoined -notmatch 'FAIL tests/app_test\.ot \(syntax error\)') { throw "Test 14 failed: Expected syntax error header. Output: $synJoined" }
    if ($synJoined -notmatch 'Otter Syntax Error') { throw "Test 14 failed: Expected syntax error diagnostic. Output: $synJoined" }
    Write-Output '  pass  CLI: syntax error in test file reports FAIL (syntax error) with exit code 2'

    # Test 15: Multiple test files run in isolation; failure does not abort remaining tests
    $multiProjDir = Join-Path $testTmp 'MultiApp'
    $mProj = New-OtterProject -Archetype 'console' -Name 'MultiApp' -Path $testTmp
    $mTestsDir = Join-Path $multiProjDir 'tests'
    
    # Test 1: Passing
    Set-Content -LiteralPath (Join-Path $mTestsDir '01_pass_test.ot') -Value 'val1 is 10' -Encoding UTF8
    # Test 2: Failing
    Set-Content -LiteralPath (Join-Path $mTestsDir '02_fail_test.ot') -Value 'fail with "Assertion 2 failed."' -Encoding UTF8
    # Test 3: Passing
    Set-Content -LiteralPath (Join-Path $mTestsDir '03_pass_test.ot') -Value 'val2 is 20' -Encoding UTF8
    # Remove initial app_test.ot to keep exactly 3 tests
    Remove-Item -LiteralPath (Join-Path $mTestsDir 'app_test.ot') -Force

    $multiTestOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') test $multiProjDir 2>&1
    if ($LASTEXITCODE -ne 3) { throw "Test 15 failed: Expected exit code 3 for mixed test results, got $LASTEXITCODE. Output: $multiTestOut" }
    $multiJoined = $multiTestOut -join "`n"
    if ($multiJoined -notmatch 'PASS tests/01_pass_test\.ot') { throw "Test 15 failed: Expected 01_pass_test.ot to PASS" }
    if ($multiJoined -notmatch 'FAIL tests/02_fail_test\.ot') { throw "Test 15 failed: Expected 02_fail_test.ot to FAIL" }
    if ($multiJoined -notmatch 'PASS tests/03_pass_test\.ot') { throw "Test 15 failed: Expected 03_pass_test.ot to PASS after failure" }
    if ($multiJoined -notmatch 'Assertion 2 failed\.') { throw "Test 15 failed: Expected failure message in summary" }
    if ($multiJoined -notmatch '2 passed, 1 failed') { throw "Test 15 failed: Expected summary '2 passed, 1 failed'. Output: $multiJoined" }
    Write-Output '  pass  CLI: multi-test execution runs in isolation and does not abort early on failure'

    # Test 16: Project with no tests reports "No tests found." and exits 0
    $emptyProjDir = Join-Path $testTmp 'EmptyApp'
    $eProj = New-OtterProject -Archetype 'console' -Name 'EmptyApp' -Path $testTmp
    Remove-Item -LiteralPath (Join-Path $emptyProjDir 'tests/app_test.ot') -Force
    $noTestOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') test $emptyProjDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 16 failed: Expected exit code 0 when no tests found, got $LASTEXITCODE. Output: $noTestOut" }
    if (($noTestOut -join "`n") -notmatch 'No tests found') { throw "Test 16 failed: Expected 'No tests found'. Output: $noTestOut" }
    Write-Output '  pass  CLI: project with no tests reports `No tests found.` and exits 0'


    # Test 17: the test runner launches tests with the PowerShell that is running
    # Otter (never a hard-coded powershell.exe, which exists only on Windows).
    $projectModule = Get-Module -Name 'Otter.Project'
    $testHost = & $projectModule { Get-OtterProjectPowerShellHost }
    if (-not (Test-Path -LiteralPath $testHost -PathType Leaf)) { throw "Test 17 failed: test host '$testHost' does not exist." }
    $currentHost = (Get-Process -Id $PID).Path
    if ($testHost -ne $currentHost) { throw "Test 17 failed: expected the running host '$currentHost', got '$testHost'." }
    $onWindows = & $projectModule { Test-OtterProjectWindowsHost }
    $expectWindows = ($PSVersionTable.PSEdition -ne 'Core') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
    if ($onWindows -ne $expectWindows) { throw "Test 17 failed: Windows detection disagrees with the platform." }
    Write-Output '  pass  test runner launches tests with the running PowerShell host, not a hard-coded powershell.exe'

} finally {
    Remove-Item -LiteralPath $testTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "`nAll Otter project creation and test runner tests passed (17/17)."
