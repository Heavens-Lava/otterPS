using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Project.psm1
. "$PSScriptRoot\TestHost.ps1"

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

    $cCheck = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') check $cDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 1 failed: otter check ConsoleApp exited with $LASTEXITCODE. Output: $cCheck" }
    Write-Output '  pass  New-OtterProject generates valid console archetype passing `otter check`'

    # Test 2: New-OtterProject generates desktop archetype with CSS asset and valid code
    $dProj = New-OtterProject -Archetype 'desktop' -Name 'DesktopApp' -Path $testTmp
    $dDir = $dProj.RootDirectory
    if ($dProj.Target -ne 'desktop') { throw "Test 2 failed: Expected Target desktop, got $($dProj.Target)" }
    if (-not (Test-Path -LiteralPath (Join-Path $dDir 'assets/styles.css') -PathType Leaf)) { throw "Test 2 failed: Missing assets/styles.css" }
    $dCheck = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') check $dDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 2 failed: otter check DesktopApp exited with $LASTEXITCODE. Output: $dCheck" }
    Write-Output '  pass  New-OtterProject generates valid desktop archetype passing `otter check`'

    # Test 3: New-OtterProject generates web archetype with CSS asset and valid code
    $wProj = New-OtterProject -Archetype 'web' -Name 'WebApp' -Path $testTmp
    $wDir = $wProj.RootDirectory
    if ($wProj.Target -ne 'web') { throw "Test 3 failed: Expected Target web, got $($wProj.Target)" }
    # D-3: a page's stylesheet is <entry>.css (main.css), not assets/styles.css.
    if (-not (Test-Path -LiteralPath (Join-Path $wDir 'main.css') -PathType Leaf)) { throw "Test 3 failed: Missing main.css" }
    $wCheck = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') check $wDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 3 failed: otter check WebApp exited with $LASTEXITCODE. Output: $wCheck" }
    Write-Output '  pass  New-OtterProject generates valid web archetype passing `otter check`'

    # Test 4: New-OtterProject generates automation archetype with valid code
    $aProj = New-OtterProject -Archetype 'automation' -Name 'AutoApp' -Path $testTmp
    $aDir = $aProj.RootDirectory
    $aCheck = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') check $aDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 4 failed: otter check AutoApp exited with $LASTEXITCODE. Output: $aCheck" }
    Write-Output '  pass  New-OtterProject generates valid automation archetype passing `otter check`'

    # Test 5: New-OtterProject generates game archetype with canvas and valid code
    $gProj = New-OtterProject -Archetype 'game' -Name 'GameApp' -Path $testTmp
    $gDir = $gProj.RootDirectory
    if ($gProj.Target -ne 'game') { throw "Test 5 failed: Expected Target game, got $($gProj.Target)" }
    $gCheck = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') check $gDir 2>&1
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
        $newCliOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') new console CliApp 2>&1
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
    $errNew1 = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') new 2>&1
    if ($LASTEXITCODE -ne 1) { throw "Test 8a failed: Expected exit code 1 for otter new without args, got $LASTEXITCODE" }
    if (($errNew1 -join "`n") -notmatch 'Usage: otter new') { throw "Test 8a failed: Expected usage message" }

    $errNew2 = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') new invalid Foo 2>&1
    if ($LASTEXITCODE -ne 1) { throw "Test 8b failed: Expected exit code 1 for unknown archetype, got $LASTEXITCODE" }
    if (($errNew2 -join "`n") -notmatch 'Unknown archetype') { throw "Test 8b failed: Expected unknown archetype message" }

    $errNew3 = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') new console 2>&1
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
    $testRunOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') test $cDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 10 failed: otter test ConsoleApp exited with $LASTEXITCODE. Output: $testRunOut" }
    if (($testRunOut -join "`n") -notmatch 'PASS tests/app_test\.ot') { throw "Test 10 failed: Expected PASS tests/app_test.ot. Output: $testRunOut" }
    if (($testRunOut -join "`n") -notmatch '1 passed') { throw "Test 10 failed: Expected summary '1 passed'. Output: $testRunOut" }
    Write-Output '  pass  CLI: `otter test <project>` passes generated project tests out of the box'

    # Test 11: `otter test` in current directory discovers and runs tests
    $prevCwd = (Get-Location).Path
    try {
        Set-Location -LiteralPath $cDir
        $dotTestOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') test . 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Test 11a failed: otter test . exited with $LASTEXITCODE. Output: $dotTestOut" }
        if (($dotTestOut -join "`n") -notmatch 'PASS tests/app_test\.ot') { throw "Test 11a failed: Output: $dotTestOut" }

        $bareTestOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') test 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Test 11b failed: bare otter test exited with $LASTEXITCODE. Output: $bareTestOut" }
        if (($bareTestOut -join "`n") -notmatch 'PASS tests/app_test\.ot') { throw "Test 11b failed: Output: $bareTestOut" }
    } finally {
        Set-Location -LiteralPath $prevCwd
    }
    Write-Output '  pass  CLI: `otter test` and `otter test .` run project tests from inside project root'

    # Test 12: `otter test` with single test file
    $singleTestFile = Join-Path $cDir 'tests/app_test.ot'
    $singleTestOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') test $singleTestFile 2>&1
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

    $failTestOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') test $failProjDir 2>&1
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

    $synTestOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') test $synProjDir 2>&1
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

    $multiTestOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') test $multiProjDir 2>&1
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
    $noTestOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') test $emptyProjDir 2>&1
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

    # Test 18 (RC3 B1): the start command of every archetype works on a fresh
    # scaffold. `otter new web|game` used to write (and print) `otter run .`,
    # which exits 3 because the interpreter has no page/text/canvas UI.
    # RC3-B1 begin
    $b1Root = Join-Path $testTmp 'b1_scaffolds'
    New-Item -ItemType Directory -Path $b1Root -Force | Out-Null
    $b1PrevCwd = (Get-Location).Path
    try {
        foreach ($b1Arch in @('console', 'automation', 'web', 'game', 'desktop')) {
            Set-Location -LiteralPath $b1Root
            $b1Name = "B1${b1Arch}App"
            $b1NewOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') new $b1Arch $b1Name 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Test 18 failed: otter new $b1Arch exited with $LASTEXITCODE. Output: $b1NewOut" }
            $b1Dir = Join-Path $b1Root $b1Name
            $b1Manifest = Get-Content -LiteralPath (Join-Path $b1Dir 'otter.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $b1Start = [string]$b1Manifest.scripts.start
            $b1ExpectedStart = if ($b1Arch -in @('web', 'game')) { 'otter web .' } else { 'otter run .' }
            if ($b1Start -ne $b1ExpectedStart) { throw "Test 18 failed: $b1Arch scripts.start is '$b1Start', expected '$b1ExpectedStart'." }

            # The printed setup steps (check, test) plus scripts.start. The
            # printed start line itself is hard-coded in otter.ps1 (outside
            # this module) and is checked separately once otter.ps1 prints
            # scripts.start.
            $b1Commands = @($b1NewOut | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -match '^otter (check|test) ' })
            if ($b1Commands.Count -lt 2) { throw "Test 18 failed: otter new $b1Arch printed no check/test steps. Output: $b1NewOut" }
            $b1Commands += $b1Start

            Set-Location -LiteralPath $b1Dir
            foreach ($b1Command in $b1Commands) {
                $b1Words = @($b1Command -split '\s+' | Select-Object -Skip 1)
                if ($b1Arch -eq 'desktop' -and $b1Command -eq $b1Start) {
                    Write-Output "  skip  $b1Arch '$b1Command': needs Windows WPF and opens a window that waits for the user, so it cannot run unattended"
                    continue
                }
                if ($b1Words[0] -eq 'web') {
                    # Compile exactly as printed but do not launch a browser
                    # from a test run (and PowerShell 7 on Linux cannot open
                    # an .html file through Start-Process).
                    Write-Output "  note  $b1Arch '$b1Command' runs with -NoOpen so the test does not launch a browser"
                    $b1Words += '-NoOpen'
                }
                $b1Out = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') @b1Words 2>&1
                if ($LASTEXITCODE -ne 0) { throw "Test 18 failed: '$b1Command' in a fresh $b1Arch project exited with $LASTEXITCODE. Output: $b1Out" }
            }
        }
    } finally {
        Set-Location -LiteralPath $b1PrevCwd
    }
    Write-Output '  pass  every archetype scaffold: printed check/test steps and scripts.start all exit 0 (web/game start with `otter web .`)'
    # RC3-B1 end

    # Test 19 (RC3 B3 / D-3): web and game scaffolds put their stylesheet in
    # main.css beside main.ot, which the build inlines into dist/index.html.
    # They used to create and declare assets/styles.css, which no page used.
    # RC3-B3 begin
    foreach ($b3Arch in @('web', 'game')) {
        $b3Proj = New-OtterProject -Archetype $b3Arch -Name "B3${b3Arch}App" -Path $testTmp
        $b3Dir = $b3Proj.RootDirectory
        $b3Css = Join-Path $b3Dir 'main.css'
        if (-not (Test-Path -LiteralPath $b3Css -PathType Leaf)) { throw "Test 19 failed: $b3Arch scaffold has no main.css beside main.ot" }
        if (Test-Path -LiteralPath (Join-Path $b3Dir 'assets/styles.css')) { throw "Test 19 failed: $b3Arch scaffold still creates assets/styles.css" }
        if (@($b3Proj.Assets) -contains 'assets/styles.css') { throw "Test 19 failed: $b3Arch scaffold still declares assets/styles.css" }
        Set-Content -LiteralPath $b3Css -Value 'body { background: rgb(1, 2, 3); }' -Encoding UTF8
        $b3PrevCwd = (Get-Location).Path
        try {
            Set-Location -LiteralPath $b3Dir
            $b3Out = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') build . 2>&1
        } finally {
            Set-Location -LiteralPath $b3PrevCwd
        }
        if ($LASTEXITCODE -ne 0) { throw "Test 19 failed: otter build . ($b3Arch) exited with $LASTEXITCODE. Output: $b3Out" }
        $b3Html = Get-Content -LiteralPath (Join-Path $b3Dir 'dist/index.html') -Raw -Encoding UTF8
        if (-not $b3Html.Contains('body { background: rgb(1, 2, 3); }')) { throw "Test 19 failed: the main.css rule is not in $b3Arch dist/index.html" }
    }
    Write-Output '  pass  web and game scaffolds style through main.css, and a main.css rule reaches dist/index.html'
    # RC3-B3 end

} finally {
    Remove-Item -LiteralPath $testTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "`nAll Otter project creation and test runner tests passed (19/19)."
