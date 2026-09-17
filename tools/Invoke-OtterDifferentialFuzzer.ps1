using module ..\Otter.Contract.psm1

# tools/Invoke-OtterDifferentialFuzzer.ps1
# Grammar-aware Differential Testing & Fuzzer for Otter 1.0 RC

param(
    [int]$Seed = 20261010,
    [int]$Iterations = 100,
    [ValidateSet('All', 'Differential', 'MutationFuzz')][string]$Mode = 'All'
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Lexer.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Parser.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Interpreter.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Compiler.JavaScript.psm1') -Force

$rand = [System.Random]::new($Seed)

function Run-OtterInterpreterDirect {
    param([string]$Source)
    $stdout = [System.Collections.Generic.List[string]]::new()
    $writer = { param($t) $stdout.Add([string]$t) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        $tokens = ConvertTo-OtterTokens -Source $Source
        $ast = ConvertTo-OtterAst -Tokens $tokens
        $env = New-OtterEnvironment
        Invoke-OtterProgram -Program $ast -Environment $env
        return @{
            Success = $true
            Stdout = ($stdout -join "`n").Trim()
            Error = $null
            ErrorType = $null
        }
    } catch [OtterError] {
        return @{
            Success = $false
            Stdout = ($stdout -join "`n").Trim()
            Error = $_.Exception.Message
            ErrorType = 'OtterError'
            Line = $_.Exception.Line
        }
    } catch {
        return @{
            Success = $false
            Stdout = ($stdout -join "`n").Trim()
            Error = $_.Exception.Message
            ErrorType = 'HostException'
            Raw = $_.Exception
        }
    } finally {
        Set-OtterOutputWriter -Writer $null
    }
}

function Run-OtterNodeDirect {
    param([string]$Source)
    try {
        $tokens = ConvertTo-OtterTokens -Source $Source
        $ast = ConvertTo-OtterAst -Tokens $tokens

        $jsLines = [System.Collections.Generic.List[string]]::new()
        $jsLines.Add('const window = globalThis;')
        $jsLines.Add('global.window = globalThis;')
        $jsLines.Add('const fs = require("fs");')
        $jsLines.Add('const cp = require("child_process");')
        $jsLines.Add('const otterLog = console.log;')
        $jsLines.Add('const otterWarn = console.warn;')
        $jsLines.Add('const otterError = console.error;')
        $jsLines.Add('const otterSay = (...args) => console.log(args.join(" "));')
        $jsLines.Add('const otterGetElement = () => null;')
        $jsLines.Add('(async () => {')
        foreach ($stmt in $ast.Statements) {
            $compiled = ConvertTo-OtterJsStatement -Stmt $stmt -Indent 1
            $jsLines.Add($compiled)
        }
        $jsLines.Add('})();')
        $fullJs = $jsLines -join "`n"

        $tmp = [System.IO.Path]::GetTempFileName() + ".js"
        [System.IO.File]::WriteAllText($tmp, $fullJs, [System.Text.Encoding]::UTF8)
        $prevOutEnc = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $nodeOut = cmd /c "chcp 65001 >nul && node `"$tmp`" 2>&1"
            $exitCode = $LASTEXITCODE
            $outStr = ($nodeOut -join "`n").Trim()
            if ($exitCode -eq 0) {
                return @{
                    Success = $true
                    Stdout = $outStr
                    Error = $null
                }
            } else {
                return @{
                    Success = $false
                    Stdout = ""
                    Error = $outStr
                }
            }
        } finally {
            [Console]::OutputEncoding = $prevOutEnc
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    } catch [OtterError] {
        return @{
            Success = $false
            Stdout = ""
            Error = $_.Exception.Message
            ErrorType = 'OtterError'
        }
    } catch {
        return @{
            Success = $false
            Stdout = ""
            Error = $_.Exception.Message
            ErrorType = 'HostException'
        }
    }
}

# -------------------------------------------------------------
# GENERATOR: Valid Portable Core Otter Programs
# -------------------------------------------------------------
function New-RandomValidOtterProgram {
    $lines = [System.Collections.Generic.List[string]]::new()
    
    # Define a helper function
    $fnName = "compute" + $rand.Next(100, 999)
    $lines.Add("to $fnName num1 and num2")
    $op = @('plus', 'minus', 'times')[$rand.Next(3)]
    $lines.Add("    res is num1 $op num2")
    $lines.Add("    return res")
    $lines.Add(".")
    
    # Generate variables
    $v1 = $rand.Next(1, 50)
    $v2 = $rand.Next(1, 50)
    $lines.Add("x is $v1")
    $lines.Add("y is $v2")
    $lines.Add("val is $fnName x and y")
    
    # Add a condition
    $lines.Add("if val is greater than 20")
    $lines.Add("    say `"high`"")
    $lines.Add("otherwise")
    $lines.Add("    say `"low`"")
    $lines.Add(".")

    # Add a loop
    $loopBound = $rand.Next(2, 6)
    $lines.Add("total is 0")
    $lines.Add("count from 1 to $loopBound as step")
    $lines.Add("    total is total plus step")
    $lines.Add(".")
    $lines.Add("say total")
    
    # Add a list
    $lines.Add("items are")
    $lines.Add("    10")
    $lines.Add("    20")
    $lines.Add("    30")
    $lines.Add(".")
    $lines.Add("firstItem is first of items")
    $lines.Add("lastItem is last of items")
    $lines.Add("len is length of items")
    $lines.Add("say firstItem lastItem len")

    return ($lines -join "`n")
}

# -------------------------------------------------------------
# MUTATOR: Introduces near-valid syntax mutations
# -------------------------------------------------------------
function Mutate-OtterSource {
    param([string]$Source)
    $srcLines = $Source -split "`n"
    $idx = $rand.Next($srcLines.Length)
    $line = $srcLines[$idx]
    
    $mutation = $rand.Next(5)
    switch ($mutation) {
        0 { # Add unclosed quote
            $srcLines[$idx] = $line + ' "unclosed'
        }
        1 { # Indentation mutation
            $srcLines[$idx] = "`t`t" + $line
        }
        2 { # Remove block terminator
            if ($line.Trim() -eq '.') {
                $srcLines[$idx] = '# dropped period'
            } else {
                $srcLines[$idx] = $line + ' extraWord'
            }
        }
        3 { # Chained assignment / operator error
            $srcLines[$idx] = $line + ' is 42'
        }
        4 { # Keyword collision
            $srcLines[$idx] = "make is 10"
        }
    }
    return ($srcLines -join "`n")
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Otter 1.0 RC Differential Testing & Fuzzing Gauntlet" -ForegroundColor Cyan
Write-Host "Seed: $Seed | Iterations: $Iterations | Mode: $Mode" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$differentialPassed = 0
$differentialFailed = 0
$fuzzSafe = 0
$fuzzRawCrashes = 0
$issues = [System.Collections.Generic.List[hashtable]]::new()

if ($Mode -in @('All', 'Differential')) {
    Write-Host "`nRunning Differential Parity Suite ($Iterations iterations)..." -ForegroundColor Yellow
    for ($i = 1; $i -le $Iterations; $i++) {
        $source = New-RandomValidOtterProgram
        $resInt = Run-OtterInterpreterDirect -Source $source
        $resNode = Run-OtterNodeDirect -Source $source

        if ($resInt.Success -and $resNode.Success) {
            if ($resInt.Stdout -eq $resNode.Stdout) {
                $differentialPassed++
            } else {
                $differentialFailed++
                $issues.Add(@{
                    Type = 'INTERPRETER_JS_DISAGREEMENT'
                    Iteration = $i
                    Source = $source
                    InterpreterStdout = $resInt.Stdout
                    NodeStdout = $resNode.Stdout
                })
            }
        } else {
            $differentialFailed++
            $issues.Add(@{
                Type = 'RUNTIME_EXECUTION_FAILURE'
                Iteration = $i
                Source = $source
                Interpreter = $resInt
                Node = $resNode
            })
        }
    }
    Write-Host "Differential Testing: $differentialPassed passed, $differentialFailed disagreements." -ForegroundColor $(if ($differentialFailed -eq 0) { 'Green' } else { 'Red' })
}

if ($Mode -in @('All', 'MutationFuzz')) {
    Write-Host "`nRunning Mutation Fuzzing Suite ($Iterations iterations)..." -ForegroundColor Yellow
    for ($i = 1; $i -le $Iterations; $i++) {
        $base = New-RandomValidOtterProgram
        $mutated = Mutate-OtterSource -Source $base
        
        $resInt = Run-OtterInterpreterDirect -Source $mutated
        if ($resInt.ErrorType -eq 'HostException') {
            $fuzzRawCrashes++
            $issues.Add(@{
                Type = 'RAW_HOST_EXCEPTION'
                Iteration = $i
                Source = $mutated
                Error = $resInt.Error
            })
        } else {
            $fuzzSafe++
        }
    }
    Write-Host "Mutation Fuzzing: $fuzzSafe handled safely as OtterError/Pass, $fuzzRawCrashes raw host exceptions." -ForegroundColor $(if ($fuzzRawCrashes -eq 0) { 'Green' } else { 'Red' })
}

Write-Host "`n===================================================="
if ($issues.Count -eq 0) {
    Write-Host "GAUNTLET CERTIFIED: 0 disagreements, 0 raw host crashes." -ForegroundColor Green
    exit 0
} else {
    Write-Host "DEFECTS FOUND: $($issues.Count)" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  - [$($issue.Type)] Iteration $($issue.Iteration)" -ForegroundColor Yellow
    }
    exit 1
}
