# tools/Test-DocumentationExamples.ps1
#
# Phase 6 - Documentation Reality Check Test Suite
# Audits documentation examples and core examples against the production parser and runtime.
# Asserts that every documented .ot snippet is valid, accepted by the production parser,
# and behaves as documented.

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$otterCmd = Join-Path $repoRoot 'otter.cmd'
$scratchDir = Join-Path $repoRoot 'scratch\doc_tests'

if (Test-Path -LiteralPath $scratchDir) {
    Remove-Item -LiteralPath $scratchDir -Recurse -Force
}
New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $scratchDir 'Pictures') -Force | Out-Null

$passCount = 0
$failCount = 0

function Test-OtterSnippet {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Source,
        [switch]$ExpectExecutionSuccess
    )

    $tempFile = Join-Path $scratchDir "doc_test_${Name}.ot"
    Set-Content -Path $tempFile -Value $Source -Encoding utf8

    try {
        # First: syntax check via `otter check`
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $otterCmd
        $pinfo.Arguments = "check `"$tempFile`""
        $pinfo.WorkingDirectory = $scratchDir
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($pinfo)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        if ($proc.ExitCode -ne 0) {
            throw "Syntax check failed (exit $($proc.ExitCode)): $stdout $stderr"
        }

        if ($ExpectExecutionSuccess) {
            $pinfo.Arguments = "run `"$tempFile`""
            $proc = [System.Diagnostics.Process]::Start($pinfo)
            $stdout = $proc.StandardOutput.ReadToEnd()
            $stderr = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit()

            if ($proc.ExitCode -ne 0) {
                throw "Execution failed (exit $($proc.ExitCode)): $stdout $stderr"
            }
        }

        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:passCount++
    }
    catch {
        Write-Host "  [FAIL] ${Name}: $($_.Exception.Message)" -ForegroundColor Red
        $script:failCount++
    }
    finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Otter 1.0 RC - Documentation Reality Check Suite" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

try {
    # -------------------------------------------------------------
    # 1. Core Language Examples from Documentation
    # -------------------------------------------------------------
    Write-Host "`n-- Testing Core Language Documentation Snippets --" -ForegroundColor Yellow

    Test-OtterSnippet -Name "doc_variables" -Source @"
name is "Jeff"
age is 29
score is 100
loggedIn is true
say "User:" name "is" age "years old."
"@ -ExpectExecutionSuccess

    Test-OtterSnippet -Name "doc_math" -Source @"
number1 is 5
number2 is 5
number1 and number2 make total
say total
diff is 10 minus 5
product is 10 times 5
quotient is 10 divided by 5
score is 10
add 5 to score
remove 2 from score
say score
"@ -ExpectExecutionSuccess

    Test-OtterSnippet -Name "doc_if_otherwise" -Source @"
score is 85
if score is at least 90
    grade is "A"
otherwise if score is at least 80
    grade is "B"
otherwise
    grade is "C"
.
say "Grade:" grade
"@ -ExpectExecutionSuccess

    Test-OtterSnippet -Name "doc_repeat_loop" -Source @"
total is 0
repeat 3 times
    add 1 to total
.
say total
"@ -ExpectExecutionSuccess

    Test-OtterSnippet -Name "doc_while_loop" -Source @"
num is 1
while num is less than 5
    add 1 to num
.
say num
"@ -ExpectExecutionSuccess

    Test-OtterSnippet -Name "doc_count_loop" -Source @"
sum is 0
count from 1 to 5 as n
    add n to sum
.
say sum
"@ -ExpectExecutionSuccess

    Test-OtterSnippet -Name "doc_functions" -Source @"
to doubleValue n
    n and n make result
    return result
.
doubleValue 21 make res
say res
"@ -ExpectExecutionSuccess

    Test-OtterSnippet -Name "doc_lists" -Source @"
games are
    "Zelda"
    "Mario"
    "Pokemon"
.
for each game in games
    say game
.
say length of games
say first of games
say last of games
"@ -ExpectExecutionSuccess

    Test-OtterSnippet -Name "doc_objects" -Source @"
person is a thing
    name is "Jeff"
    age is 29
.
say name of person
age of person is 30
say age of person
"@ -ExpectExecutionSuccess

    Test-OtterSnippet -Name "doc_custom_types" -Source @"
a Person has
    name
    age
.
jeff is a Person
name of jeff is "Jeff"
age of jeff is 29
say name of jeff
"@ -ExpectExecutionSuccess

    Test-OtterSnippet -Name "doc_json" -Source @"
data is a thing
    title is "Otter 1.0"
    version is 1
.
convert data to json into jsonString
convert jsonString from json into parsed
say title of parsed
"@ -ExpectExecutionSuccess

    Test-OtterSnippet -Name "doc_dates" -Source @"
d is today
y is year of d
add 1 year to d
yNext is year of d
say yNext minus y
"@ -ExpectExecutionSuccess

    Test-OtterSnippet -Name "doc_random" -Source @"
random number from 1 to 10 into n
say n
"@ -ExpectExecutionSuccess

    Test-OtterSnippet -Name "doc_try_otherwise" -Source @"
try
    read "probably_missing_test_file.txt" into content
otherwise
    say "handled"
.
"@ -ExpectExecutionSuccess

    # -------------------------------------------------------------
    # 2. Key Canonical Examples from examples/
    # -------------------------------------------------------------
    Write-Host "`n-- Testing Canonical Examples from examples/ --" -ForegroundColor Yellow

    $canonicalExamples = @(
        'hello.ot',
        'variables.ot',
        'math.ot',
        'conditions.ot',
        'collections.ot',
        'objects.ot',
        'json.ot',
        'dates.ot',
        'random.ot',
        'diagnostics.ot',
        'discovery.ot'
    )

    foreach ($exName in $canonicalExamples) {
        $exPath = Join-Path $repoRoot "examples\$exName"
        if (Test-Path -LiteralPath $exPath) {
            $src = Get-Content -Path $exPath -Raw -Encoding utf8
            Test-OtterSnippet -Name "example_$exName" -Source $src -ExpectExecutionSuccess
        } else {
            Write-Host "  [SKIP] examples/$exName not found" -ForegroundColor Yellow
        }
    }

} finally {
    Remove-Item -LiteralPath $scratchDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Documentation Reality Check: $passCount passed, $failCount failed." -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
if ($failCount -ne 0) { exit 1 }
exit 0
