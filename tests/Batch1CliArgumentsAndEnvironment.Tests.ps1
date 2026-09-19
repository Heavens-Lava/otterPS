using module ..\Otter.Contract.psm1

# tests/Batch1CliArgumentsAndEnvironment.Tests.ps1
# Certification suite for V1 Completion Batch 1:
# 1. CLI arguments / options passing
# 2. Current working directory (cwd) inspection & mutation
# 3. Environment variable mutation & child process propagation

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Runtime.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Lexer.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Parser.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Interpreter.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Compiler.JavaScript.psm1') -Force

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Otter 1.0 - Batch 1: CLI Arguments & CWD/Environment" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$passCount = 0
$failCount = 0

function Assert-Test {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:passCount++
    } catch {
        Write-Host "  [FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red
        $script:failCount++
    }
}

$otterCli = Join-Path $PSScriptRoot '..\otter.cmd'
$otterPs1 = Join-Path $PSScriptRoot '..\otter.ps1'
$tempDir = Join-Path $PSScriptRoot '..\scratch\batch1_tests'
if (-not (Test-Path -LiteralPath $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
}

try {
    # -------------------------------------------------------------
    # SECTION 1: CLI ARGUMENTS & OPTIONS
    # -------------------------------------------------------------
    Write-Host "`n--- Section 1: CLI Arguments & Options ---" -ForegroundColor Yellow

    # 1.1 Direct CLI invocation via otter run
    $script1 = Join-Path $tempDir 'args_test1.ot'
    Set-Content -LiteralPath $script1 -Value @"
say length of arguments
say first of arguments
say last of arguments
for each arg in arguments
    say arg
.
"@
    Assert-Test "CLI arguments via 'otter run script.ot Jeff 42'" {
        $output = & $otterCli run $script1 Jeff 42
        if ($LASTEXITCODE -ne 0) { throw "CLI exited with code $LASTEXITCODE" }
        $expected = @("2", "Jeff", "42", "Jeff", "42")
        if (($output -join "`n") -ne ($expected -join "`n")) {
            throw "Expected `n$($expected -join "`n")`nGot:`n$($output -join "`n")"
        }
    }

    # 1.2 Short form invocation: otter script.ot Jeff 42
    Assert-Test "CLI arguments via short form 'otter script.ot Jeff 42'" {
        $output = & $otterCli $script1 Jeff 42
        if ($LASTEXITCODE -ne 0) { throw "CLI exited with code $LASTEXITCODE" }
        $expected = @("2", "Jeff", "42", "Jeff", "42")
        if (($output -join "`n") -ne ($expected -join "`n")) {
            throw "Expected `n$($expected -join "`n")`nGot:`n$($output -join "`n")"
        }
    }

    # 1.3 Arguments with spaces
    Assert-Test "CLI arguments preserving spaces in quotes" {
        $output = & $otterCli run $script1 "Jeff Macy" "Otter Language 1.0"
        if ($LASTEXITCODE -ne 0) { throw "CLI exited with code $LASTEXITCODE" }
        $expected = @("2", "Jeff Macy", "Otter Language 1.0", "Jeff Macy", "Otter Language 1.0")
        if (($output -join "`n") -ne ($expected -join "`n")) {
            throw "Expected `n$($expected -join "`n")`nGot:`n$($output -join "`n")"
        }
    }

    # 1.4 Zero arguments passed
    Assert-Test "CLI execution with zero arguments produces empty list" {
        $output = & $otterCli run $script1
        if ($LASTEXITCODE -ne 0) { throw "CLI exited with code $LASTEXITCODE" }
        $expected = @("0", "gone", "gone")
        if (($output -join "`n") -ne ($expected -join "`n")) {
            throw "Expected `n$($expected -join "`n")`nGot:`n$($output -join "`n")"
        }
    }

    # 1.5 Statement form: get arguments into myArgs
    $script2 = Join-Path $tempDir 'args_test2.ot'
    Set-Content -LiteralPath $script2 -Value @"
get arguments into myArgs
say length of myArgs
say first of myArgs
"@
    Assert-Test "'get arguments into <var>' statement form" {
        $output = & $otterCli run $script2 Alpha Beta Gamma
        if ($LASTEXITCODE -ne 0) { throw "CLI exited with code $LASTEXITCODE" }
        $expected = @("3", "Alpha")
        if (($output -join "`n") -ne ($expected -join "`n")) {
            throw "Expected `n$($expected -join "`n")`nGot:`n$($output -join "`n")"
        }
    }

    # 1.6 Module-level New-OtterEnvironment with arguments
    Assert-Test "New-OtterEnvironment initializes arguments list for in-memory programs" {
        $env = New-OtterEnvironment -Arguments @("One", "Two", "Three")
        $rawArgs = $env.Get('arguments')
        if (-not (Test-OtterList $rawArgs)) { throw "Expected OtterList" }
        if ($rawArgs.Count -ne 3) { throw "Expected count 3, got $($rawArgs.Count)" }
        if ($rawArgs[0] -ne "One" -or $rawArgs[2] -ne "Three") { throw "Unexpected argument values" }
    }

    # -------------------------------------------------------------
    # SECTION 2: CURRENT WORKING DIRECTORY (CWD)
    # -------------------------------------------------------------
    Write-Host "`n--- Section 2: Current Working Directory ---" -ForegroundColor Yellow

    # 2.1 get current directory into folder
    $scriptCwd1 = Join-Path $tempDir 'cwd_test1.ot'
    Set-Content -LiteralPath $scriptCwd1 -Value @"
get current directory into folder
say folder
get current folder into folder2
say folder2
"@
    Assert-Test "'get current directory into folder' returns valid path" {
        $output = & $otterCli run $scriptCwd1
        if ($LASTEXITCODE -ne 0) { throw "CLI exited with code $LASTEXITCODE" }
        if (-not (Test-Path -LiteralPath $output[0])) { throw "Path does not exist: $($output[0])" }
        if ($output[0] -ne $output[1]) { throw "get current directory and get current folder diverged" }
    }

    # 2.2 set current directory to <path> and verify mutation
    $originalDir = (Get-Location).Path
    $targetSubdir = Join-Path $tempDir 'sub_workspace'
    if (-not (Test-Path -LiteralPath $targetSubdir)) {
        New-Item -ItemType Directory -Path $targetSubdir | Out-Null
    }
    $resolvedSubdir = (Resolve-Path -LiteralPath $targetSubdir).Path

    $scriptCwd2 = Join-Path $tempDir 'cwd_test2.ot'
    Set-Content -LiteralPath $scriptCwd2 -Value @"
get current directory into initialDir
set current directory to "$($resolvedSubdir.Replace('\', '/'))"
get current directory into changedDir
say changedDir
set current directory to initialDir
get current directory into restoredDir
say restoredDir
"@
    Assert-Test "'set current directory to <path>' mutates and restores directory" {
        $output = & $otterCli run $scriptCwd2
        if ($LASTEXITCODE -ne 0) { throw "CLI exited with code $LASTEXITCODE" }
        if ($output[0] -ne $resolvedSubdir) {
            throw "Expected changed dir '$resolvedSubdir', got '$($output[0])'"
        }
        if ($output[1] -ne $originalDir) {
            throw "Expected restored dir '$originalDir', got '$($output[1])'"
        }
    }

    # 2.3 Non-existent directory error reporting
    $scriptCwdErr = Join-Path $tempDir 'cwd_err.ot'
    Set-Content -LiteralPath $scriptCwdErr -Value @"
set current directory to "non_existent_folder_abc123"
"@
    Assert-Test "set current directory to non-existent folder throws helpful Otter error" {
        $res = & $otterCli run $scriptCwdErr 2>&1
        if ($LASTEXITCODE -eq 0) { throw "Expected failure for non-existent directory" }
        $errText = $res -join "`n"
        if ($errText -notmatch 'I cannot find a folder called "non_existent_folder_abc123"') {
            throw "Error message did not match expected: $errText"
        }
        if ($errText -notmatch 'set current directory to "path/to/folder"') {
            throw "Suggestion did not match expected: $errText"
        }
    }

    # -------------------------------------------------------------
    # SECTION 3: ENVIRONMENT VARIABLES
    # -------------------------------------------------------------
    Write-Host "`n--- Section 3: Environment Variables ---" -ForegroundColor Yellow

    # 3.1 set environment variable and get environment variable
    $scriptEnv1 = Join-Path $tempDir 'env_test1.ot'
    Set-Content -LiteralPath $scriptEnv1 -Value @"
set environment variable "OTTER_BATCH1_KEY" to "Secret12345"
get environment variable "OTTER_BATCH1_KEY" into retrieved
say retrieved
set environment variable "OTTER_BATCH1_KEY" to "UpdatedValue"
get environment variable "OTTER_BATCH1_KEY" into updated
say updated
set environment variable "OTTER_BATCH1_KEY" to gone
get environment variable "OTTER_BATCH1_KEY" into cleared
if cleared is gone
    say "CLEARED_OK"
.
"@
    Assert-Test "'set environment variable' set, update, and clear cycle" {
        $output = & $otterCli run $scriptEnv1
        if ($LASTEXITCODE -ne 0) { throw "CLI exited with code $LASTEXITCODE" }
        $expected = @("Secret12345", "UpdatedValue", "CLEARED_OK")
        if (($output -join "`n") -ne ($expected -join "`n")) {
            throw "Expected `n$($expected -join "`n")`nGot:`n$($output -join "`n")"
        }
    }

    # 3.2 Child process inherits environment variables
    $scriptEnvChild = Join-Path $tempDir 'env_child.ot'
    Set-Content -LiteralPath $scriptEnvChild -Value @"
set environment variable "OTTER_CHILD_PROPAGATION" to "FromParentOtter"
run command "powershell -NoProfile -Command Write-Output `$env:OTTER_CHILD_PROPAGATION" into cmdRes
say output of cmdRes
"@
    Assert-Test "Child process inherits mutated environment variable" {
        $output = & $otterCli run $scriptEnvChild
        if ($LASTEXITCODE -ne 0) { throw "CLI exited with code $LASTEXITCODE" }
        $outText = ($output -join "`n").Trim()
        if ($outText -ne "FromParentOtter") {
            throw "Expected 'FromParentOtter', got '$outText'"
        }
    }

    # 3.3 Missing environment variable returns gone
    $scriptEnvMissing = Join-Path $tempDir 'env_missing.ot'
    Set-Content -LiteralPath $scriptEnvMissing -Value @"
get environment variable "DEFINITELY_NOT_SET_XYZ_987" into missingVal
if missingVal is gone
    say "GONE_OK"
.
"@
    Assert-Test "Missing environment variable evaluates to gone" {
        $output = & $otterCli run $scriptEnvMissing
        if ($LASTEXITCODE -ne 0) { throw "CLI exited with code $LASTEXITCODE" }
        $outText = ($output -join "`n").Trim()
        if ($outText -ne "GONE_OK") {
            throw "Expected 'GONE_OK', got '$outText'"
        }
    }

    # -------------------------------------------------------------
    # SECTION 4: JAVASCRIPT COMPILER COMPILATION
    # -------------------------------------------------------------
    Write-Host "`n--- Section 4: JavaScript Compiler ---" -ForegroundColor Yellow

    Assert-Test "JavaScript compiler translates SetCurrentDirectory and SetEnvironmentVariable" {
        $src = @"
set current directory to "build"
set environment variable "NODE_ENV" to "production"
get current directory into cwd
"@
        $toks = ConvertTo-OtterTokens -Source $src
        $ast = ConvertTo-OtterAst -Tokens $toks
        $js = ConvertTo-OtterJsStatement -Stmt $ast.Statements[0]
        if ($js -notmatch 'process\.chdir') { throw "Expected process.chdir in JS output: $js" }
        $js2 = ConvertTo-OtterJsStatement -Stmt $ast.Statements[1]
        if ($js2 -notmatch 'process\.env') { throw "Expected process.env in JS output: $js2" }
        $js3 = ConvertTo-OtterJsStatement -Stmt $ast.Statements[2]
        if ($js3 -notmatch 'currentDirectory') { throw "Expected currentDirectory in JS output: $js3" }
    }

} finally {
    # Clean up scratch files
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "Batch 1 Certification: $passCount passed, $failCount failed." -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
if ($failCount -ne 0) { exit 1 }
exit 0
