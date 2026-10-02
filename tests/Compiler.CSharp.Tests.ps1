using module ..\Otter.Contract.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1
using module ..\src\Otter.Compiler.CSharp.psm1

# tests/Compiler.CSharp.Tests.ps1
#
# Comprehensive test suite for Otter 1.1 Native C# Compiler & Execution Engine

Write-Host "Running Otter C# Compiler tests..." -ForegroundColor Cyan

$passed = 0
$failed = 0

function Assert-CompiledOutput {
    param(
        [string]$Name,
        [string]$Source,
        [string]$ExpectedOutput
    )

    try {
        $tokens = ConvertTo-OtterTokens -Source $Source
        $ast = ConvertTo-OtterAst -Tokens $tokens
        $actual = ((Invoke-OtterCompiledProgram -Program $ast).Trim() -replace "`r`n", "`n")
        $expected = ($ExpectedOutput.Trim() -replace "`r`n", "`n")

        if ($actual -eq $expected) {
            Write-Host "  pass  $Name" -ForegroundColor Green
            $script:passed++
        } else {
            Write-Host "  FAIL  $Name" -ForegroundColor Red
            Write-Host "    Expected: '$expected'" -ForegroundColor DarkGray
            Write-Host "    Actual:   '$actual'" -ForegroundColor DarkGray
            $script:failed++
        }
    } catch {
        Write-Host "  FAIL  $Name (Exception)" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor DarkGray
        $script:failed++
    }
}

# 1. Basic say and arithmetic
Assert-CompiledOutput -Name "say literal string" -Source 'say "Hello, Otter C#!"' -ExpectedOutput "Hello, Otter C#!"
Assert-CompiledOutput -Name "arithmetic addition" -Source 'say 10 and 25' -ExpectedOutput "35"
Assert-CompiledOutput -Name "arithmetic left-to-right evaluation" -Source 'say 50 minus 10 times 2' -ExpectedOutput "80"

# 2. Variables and mutation
Assert-CompiledOutput -Name "variable assignment and read" -Source @"
score is 100
say score
"@ -ExpectedOutput "100"

Assert-CompiledOutput -Name "add to variable" -Source @"
score is 100
add 50 to score
say score
"@ -ExpectedOutput "150"

# 3. Control flow
Assert-CompiledOutput -Name "if branch" -Source @"
score is 100
if score is 100
    say "Perfect"
otherwise
    say "Try again"
.
"@ -ExpectedOutput "Perfect"

Assert-CompiledOutput -Name "count loop" -Source @"
total is 0
count from 1 to 5 as i
    total is total and i
.
say total
"@ -ExpectedOutput "15"

Assert-CompiledOutput -Name "repeat loop" -Source @"
c is 0
repeat 4 times
    add 1 to c
.
say c
"@ -ExpectedOutput "4"

# 4. Strings & Operations
Assert-CompiledOutput -Name "string uppercase and length" -Source @"
name is "otter"
say uppercase of name
say length of name
"@ -ExpectedOutput "OTTER`n5"

Assert-CompiledOutput -Name "string replace and join" -Source @"
sentence is "hello world"
replace "world" with "otter" in sentence
say sentence
words are
    "apple"
    "banana"
.
join words with "-" into fruitString
say fruitString
"@ -ExpectedOutput "hello otter`napple-banana"

# 5. Lists and collections
Assert-CompiledOutput -Name "list definition and for each" -Source @"
games are
    "Zelda"
    "Mario"
    "Metroid"
.
for each g in games
    say g
.
"@ -ExpectedOutput "Zelda`nMario`nMetroid"

# 6. Functions and calls
Assert-CompiledOutput -Name "function definition and return" -Source @"
to addDouble x and y
    sum is x and y
    return sum and sum
.
res is addDouble 5 and 10
say res
"@ -ExpectedOutput "30"

# 7. Try / otherwise error handling
Assert-CompiledOutput -Name "try and otherwise fallback" -Source @"
try
    fail with "Something went wrong"
otherwise
    say "Caught error successfully"
.
"@ -ExpectedOutput "Caught error successfully"

# 8. Objects and property access
Assert-CompiledOutput -Name "object definition and property access" -Source @"
person is a thing
    name is "Jeff"
    role is "Creator"
.
say name of person
say role of person
"@ -ExpectedOutput "Jeff`nCreator"

# 9. Math functions (Min / Max)
Assert-CompiledOutput -Name "larger and smaller math functions" -Source @"
say larger of 15 and 42
say smaller of 15 and 42
"@ -ExpectedOutput "42`n15"

# 10. Performance compilation test (100,000 iterations in compiled C#)
Assert-CompiledOutput -Name "high iteration loop (100,000 iterations)" -Source @"
sum is 0
count from 1 to 100000 as i
    sum is sum and i
.
say sum
"@ -ExpectedOutput "5000050000"

# 11. Standalone Project Export & dotnet build / run verification
try {
    $tempExportDir = Join-Path ([System.IO.Path]::GetTempPath()) ("otter-export-" + [Guid]::NewGuid().ToString('N').Substring(0, 6))
    $tokens = ConvertTo-OtterTokens -Source @"
say "Compiled Native Otter App via .NET SDK"
total is 0
count from 1 to 10 as x
    total is total and x
.
say total
"@
    $ast = ConvertTo-OtterAst -Tokens $tokens
    $csprojPath = Export-OtterCSharpProject -Program $ast -OutputDirectory $tempExportDir -ProjectName "OtterStandaloneApp"

    if ((Test-Path $csprojPath) -and (Test-Path (Join-Path $tempExportDir "Program.cs"))) {
        Write-Host "  pass  standalone C# project export (.csproj + Program.cs)" -ForegroundColor Green
        $passed++

        # Execute with dotnet run
        $dotnetOut = (& dotnet run --project $csprojPath 2>&1 | Out-String).Trim() -replace "`r`n", "`n"
        $expectedDotnetOut = "Compiled Native Otter App via .NET SDK`n55"

        if ($dotnetOut -eq $expectedDotnetOut) {
            Write-Host "  pass  end-to-end dotnet SDK compilation & execution" -ForegroundColor Green
            $passed++
        } else {
            Write-Host "  FAIL  end-to-end dotnet SDK execution" -ForegroundColor Red
            Write-Host "    Expected: '$expectedDotnetOut'" -ForegroundColor DarkGray
            Write-Host "    Actual:   '$dotnetOut'" -ForegroundColor DarkGray
            $failed++
        }
    } else {
        Write-Host "  FAIL  standalone C# project export" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host "  FAIL  standalone C# project export (Exception: $($_.Exception.Message))" -ForegroundColor Red
    $failed++
}

Write-Host ""
if ($failed -eq 0) {
    Write-Host "All Otter C# Compiler tests passed ($passed/$passed)." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$failed tests failed ($passed passed)." -ForegroundColor Red
    exit 1
}
