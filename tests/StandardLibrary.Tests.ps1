# tests/StandardLibrary.Tests.ps1
# Complete Standard Library & Runtime Reachability Certification Suite
# Proves every advertised 1.0 capability is reachable through real .ot syntax and the production entry point.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Otter 1.0 RC - Standard Library Reachability Suite" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("otter-stdlib-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

$passCount = 0
$failCount = 0
$cmd = Join-Path $root 'otter.cmd'

function Assert-Reachability {
    param(
        [string]$Area,
        [string]$Capability,
        [string]$Source,
        [string]$ExpectedOutput
    )

    $srcFile = Join-Path $testRoot ("test_" + [Guid]::NewGuid().ToString('N') + ".ot")
    Set-Content -LiteralPath $srcFile -Value $Source -Encoding UTF8

    try {
        $output = & $cmd run $srcFile 2>&1
        $exitCode = $LASTEXITCODE
        $text = ($output -join "`n").Trim()

        if ($exitCode -ne 0) {
            throw "Execution failed with exit ${exitCode}: $text"
        }
        if ($ExpectedOutput -and $text -ne $ExpectedOutput) {
            throw "Output mismatch. Expected '$ExpectedOutput', got '$text'."
        }

        Write-Host "  [PASS] $Area -> $Capability" -ForegroundColor Green
        $script:passCount++
    }
    catch {
        Write-Host "  [FAIL] $Area -> ${Capability}: $($_.Exception.Message)" -ForegroundColor Red
        $script:failCount++
    }
    finally {
        Remove-Item -LiteralPath $srcFile -Force -ErrorAction SilentlyContinue
    }
}

try {
    # -------------------------------------------------------------
    # 1. TEXT OPERATIONS
    # -------------------------------------------------------------
    Assert-Reachability -Area "Text" -Capability "uppercase" -Source @"
t is "hello otter"
say uppercase of t
"@ -ExpectedOutput "HELLO OTTER"

    Assert-Reachability -Area "Text" -Capability "lowercase" -Source @"
t is "HELLO OTTER"
say lowercase of t
"@ -ExpectedOutput "hello otter"

    Assert-Reachability -Area "Text" -Capability "starts with and ends with" -Source @"
t is "hello otter"
if t starts with "hello" and t ends with "otter"
    say "match"
.
"@ -ExpectedOutput "match"

    Assert-Reachability -Area "Text" -Capability "replace" -Source @"
t is "hello world"
replace "world" with "otter" in t
say t
"@ -ExpectedOutput "hello otter"

    Assert-Reachability -Area "Text" -Capability "split" -Source @"
t is "apple,banana,cherry"
split t by "," into parts
say length of parts
say first of parts
say last of parts
"@ -ExpectedOutput "3`napple`ncherry"

    Assert-Reachability -Area "Text" -Capability "contains" -Source @"
t is "welcome to otter"
if t contains "otter"
    say "found"
.
"@ -ExpectedOutput "found"

    Assert-Reachability -Area "Text" -Capability "length" -Source @"
t is "12345"
say length of t
"@ -ExpectedOutput "5"

    # -------------------------------------------------------------
    # 2. MATH OPERATIONS
    # -------------------------------------------------------------
    Assert-Reachability -Area "Math" -Capability "basic arithmetic" -Source @"
x is 10 plus 5 times 2 minus 6 divided by 2
say x
"@ -ExpectedOutput "12"

    Assert-Reachability -Area "Math" -Capability "percent of" -Source @"
say 20 percent of 150
"@ -ExpectedOutput "30"

    Assert-Reachability -Area "Math" -Capability "power" -Source @"
say 2 power 8
"@ -ExpectedOutput "256"

    Assert-Reachability -Area "Math" -Capability "rounding" -Source @"
say round of 3.7
say round up of 3.2
say round down of 3.9
"@ -ExpectedOutput "4`n4`n3"

    Assert-Reachability -Area "Math" -Capability "absolute value" -Source @"
n is 0 minus 42
say absolute value of n
"@ -ExpectedOutput "42"

    Assert-Reachability -Area "Math" -Capability "square root" -Source @"
say square root of 144
"@ -ExpectedOutput "12"

    Assert-Reachability -Area "Math" -Capability "min and max" -Source @"
say larger of 15 and 25
say smaller of 15 and 25
"@ -ExpectedOutput "25`n15"

    Assert-Reachability -Area "Math" -Capability "trigonometry" -Source @"
say sine of 90
say cosine of 0
say tangent of 45
"@ -ExpectedOutput "1`n1`n1"

    Assert-Reachability -Area "Math" -Capability "logarithms" -Source @"
say log of 100
"@ -ExpectedOutput "2"

    # -------------------------------------------------------------
    # 3. LISTS & COLLECTIONS
    # -------------------------------------------------------------
    Assert-Reachability -Area "Collections" -Capability "definition and mutation" -Source @"
nums are
    10
    20
.
add 30 to nums
remove 10 from nums
say length of nums
say first of nums
say last of nums
"@ -ExpectedOutput "2`n20`n30"

    Assert-Reachability -Area "Collections" -Capability "empty list" -Source @"
emptyList are empty
say length of emptyList
"@ -ExpectedOutput "0"

    Assert-Reachability -Area "Collections" -Capability "for each loop" -Source @"
items are
    1
    2
    3
.
total is 0
for each item in items
    total is total plus item
.
say total
"@ -ExpectedOutput "6"

    # -------------------------------------------------------------
    # 4. OBJECTS & DYNAMIC KEYS
    # -------------------------------------------------------------
    Assert-Reachability -Area "Objects" -Capability "thing has and of" -Source @"
person has
    name is "Alice"
    age is 30
.
say name of person
age of person is 31
say age of person
"@ -ExpectedOutput "Alice`n31"

    Assert-Reachability -Area "Objects" -Capability "dynamic keys get/set" -Source @"
config is a thing
    host is "localhost"
.
get "host" from config into h
say h
set "port" to 8080 in config
get "port" from config into p
say p
"@ -ExpectedOutput "localhost`n8080"

    Assert-Reachability -Area "Objects" -Capability "nested properties" -Source @"
addr is a thing
    city is "Seattle"
.
user is a thing
    name is "Bob"
    address is addr
.
say name of user
say city of address of user
"@ -ExpectedOutput "Bob`nSeattle"

    # -------------------------------------------------------------
    # 5. JSON
    # -------------------------------------------------------------
    Assert-Reachability -Area "JSON" -Capability "convert to/from json" -Source @"
user is a thing
    id is 101
    name is "Carol"
.
convert user to json into jsonText
convert jsonText from json into parsed
say id of parsed
say name of parsed
"@ -ExpectedOutput "101`nCarol"

    # -------------------------------------------------------------
    # 6. DATES & TIME
    # -------------------------------------------------------------
    Assert-Reachability -Area "Dates" -Capability "today and date math" -Source @"
d is today
y is year of d
add 1 year to d
yNext is year of d
say yNext minus y
"@ -ExpectedOutput "1"

    # -------------------------------------------------------------
    # 7. RANDOM
    # -------------------------------------------------------------
    Assert-Reachability -Area "Random" -Capability "random number and item" -Source @"
random number from 5 to 5 into n
say n
colors are
    "blue"
.
random item from colors into c
say c
"@ -ExpectedOutput "5`nblue"

    # -------------------------------------------------------------
    # 8. FILESYSTEM
    # -------------------------------------------------------------
    $fsFile = Join-Path $testRoot 'fs_reachability.txt'
    $fsFileEscaped = $fsFile -replace '\\', '/'
    Assert-Reachability -Area "Filesystem" -Capability "write read append delete" -Source @"
path is "$fsFileEscaped"
write "line1" to path
if file path exists
    say "created"
.
append "line2" to path
read path into content
say length of content
delete file path
if not file path exists
    say "deleted"
.
"@ -ExpectedOutput "created`n10`ndeleted"

    # -------------------------------------------------------------
    # 9. COMMANDS & PROCESSES
    # -------------------------------------------------------------
    Assert-Reachability -Area "Process" -Capability "run command into" -Source @"
run command "cmd.exe /c echo reached" into res
say output of res
say exit code of res
"@ -ExpectedOutput "reached`n0"

    Assert-Reachability -Area "Process" -Capability "get processes" -Source @"
get processes into procList
if length of procList is at least 1
    say "processes_listed"
.
"@ -ExpectedOutput "processes_listed"

    # -------------------------------------------------------------
    # 10. SYSTEM INTEGRATION
    # -------------------------------------------------------------
    Assert-Reachability -Area "System" -Capability "system information" -Source @"
get system information "os" into osInfo
if name of osInfo is not gone
    say "os_ok"
.
get system information "cpu" into cpuInfo
if cores of cpuInfo is at least 1
    say "cpu_ok"
.
"@ -ExpectedOutput "os_ok`ncpu_ok"

    Assert-Reachability -Area "System" -Capability "clipboard" -Source @"
copy "otter-reachability-token" to clipboard
get clipboard into clip
say clip
"@ -ExpectedOutput "otter-reachability-token"

    Assert-Reachability -Area "System" -Capability "environment variable" -Source @"
get environment variable "TEMP" into t
if length of t is at least 1
    say "env_ok"
.
"@ -ExpectedOutput "env_ok"

} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Standard Library Reachability Certification: $passCount passed, $failCount failed." -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
if ($failCount -ne 0) { exit 1 }
exit 0
