using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1
using module ..\src\Otter.Interpreter.psm1

# Optimizations.Tests.ps1
#
# Semantic-preservation tests for the Otter 1.0 low-risk interpreter
# optimization pass:
#
#   OPT-1  Test-OtterEqual fast path for two plain numbers
#   OPT-2  Assert-OtterNumber fast path for plain numbers
#   OPT-3  variable reads skip the list-protection wrapper for scalars
#
# The expected results below are GOLDEN: they were captured from the
# interpreter BEFORE any of the three optimizations existed, then pasted here.
# The optimized code must reproduce every one of them exactly - results, error
# messages and error line numbers included. If an optimization changes any
# entry, the optimization is wrong; these expectations are never edited to
# match new behavior.
#
# To regenerate golden data (only ever from the un-optimized interpreter):
#     $env:OTTER_GENERATE_GOLDEN = '1'; powershell -File tests\Optimizations.Tests.ps1

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Optimization semantic preservation' -ForegroundColor Cyan

$script:Generate = ($env:OTTER_GENERATE_GOLDEN -eq '1')
$interpreterModule = Get-Module -Name 'Otter.Interpreter'

# --- the value grid ----------------------------------------------------------

function New-GridValues {
    $list12 = [System.Collections.Generic.List[object]]::new(); $list12.Add(1); $list12.Add(2)
    $list12b = [System.Collections.Generic.List[object]]::new(); $list12b.Add(1); $list12b.Add(2)
    $list13 = [System.Collections.Generic.List[object]]::new(); $list13.Add(1); $list13.Add(3)
    $listEmpty = [System.Collections.Generic.List[object]]::new()
    $listEmpty2 = [System.Collections.Generic.List[object]]::new()
    $nested = [System.Collections.Generic.List[object]]::new(); $nested.Add($list12)
    $nestedB = [System.Collections.Generic.List[object]]::new(); $nestedB.Add($list12b)
    $objectA = [OtterObject]::new('thing')
    $objectB = [OtterObject]::new('thing')
    $bytesA = [OtterBytes]::new([byte[]]@(1, 2, 3))
    $bytesB = [OtterBytes]::new([byte[]]@(1, 2, 3))
    $bytesC = [OtterBytes]::new([byte[]]@(1, 2, 4))
    $dateA = [OtterDate]::new([datetime]'2026-01-02', $false)
    $dateB = [OtterDate]::new([datetime]'2026-01-02', $false)
    $dateC = [OtterDate]::new([datetime]'2026-03-04', $false)

    return [ordered]@{
        'int 0'           = 0
        'int 1'           = 1
        'int -1'          = -1
        'int 5'           = 5
        'int 42'          = 42
        'double 5.0'      = 5.0
        'double 5.5'      = 5.5
        'double -5.5'     = -5.5
        'double 0.0'      = 0.0
        'double -0.0'     = -0.0
        'double 0.1+0.2'  = (0.1 + 0.2)
        'double 0.3'      = 0.3
        'double 1e308'    = 1e308
        'double NaN'      = [double]::NaN
        'double +Inf'     = [double]::PositiveInfinity
        'long 2^53'       = [long]9007199254740992
        'long 2^53+1'     = [long]9007199254740993
        'double 2^53'     = [double]9007199254740992
        'long 5'          = [long]5
        'decimal 5'       = [decimal]5
        'decimal 5.5'     = [decimal]5.5
        'text "5"'        = '5'
        'text "5.0"'      = '5.0'
        'text " 5"'       = ' 5'
        'text "5.5"'      = '5.5'
        'text "abc"'      = 'abc'
        'text upper ABC'   = 'ABC'
        'text ""'         = ''
        'text "0"'        = '0'
        'text "5abc"'     = '5abc'
        'bool true'       = $true
        'bool false'      = $false
        'nothing'         = $null
        'list [1,2]'      = $list12
        'list [1,2] (b)'  = $list12b
        'list [1,3]'      = $list13
        'list []'         = $listEmpty
        'list [] (b)'     = $listEmpty2
        'list [[1,2]]'    = $nested
        'list [[1,2]] (b)' = $nestedB
        'thing A'         = $objectA
        'thing B'         = $objectB
        'bytes 1,2,3'     = $bytesA
        'bytes 1,2,3 (b)' = $bytesB
        'bytes 1,2,4'     = $bytesC
        'date 2026-01-02' = $dateA
        'date 2026-01-02 (b)' = $dateB
        'date 2026-03-04' = $dateC
    }
}

function Get-EqualityTable {
    $grid = New-GridValues
    $names = @($grid.Keys)
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($leftName in $names) {
        $bits = New-Object System.Text.StringBuilder
        foreach ($rightName in $names) {
            $result = Test-OtterEqual -Left $grid[$leftName] -Right $grid[$rightName]
            [void]$bits.Append($(if ($result -eq $true) { '1' } elseif ($result -eq $false) { '0' } else { '?' }))
        }
        $rows.Add("$leftName|$($bits.ToString())")
    }
    return $rows
}

# Result of Assert-OtterNumber for each value: the number it returns (with its
# type) or the exact error message it throws.
function Get-AssertNumberTable {
    $grid = New-GridValues
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($name in $grid.Keys) {
        $value = $grid[$name]
        try {
            $result = & $interpreterModule { param($v) Assert-OtterNumber -Value $v -Line 7 -What 'the left side of this calculation' } $value
            $rows.Add("$name|ok|$($result.GetType().Name)|$($result.ToString([System.Globalization.CultureInfo]::InvariantCulture))")
        }
        catch {
            $rows.Add("$name|error|$($_.Exception.Message -replace "`r?`n", ' / ')")
        }
    }
    return $rows
}

# --- Otter programs, run through the real lexer/parser/interpreter ----------

$script:Programs = [ordered]@{
    'equality: numbers and numeric text' = @'
a1 is 5
b1 is 5
c1 is "5"
d1 is "5.0"
e1 is 5.0
f1 is 6
if a1 is b1
    say "int equals int"
if a1 is not f1
    say "int differs from int"
if a1 is c1
    say "number equals numeric text"
if c1 is d1
    say "numeric text equals numeric text"
if a1 is e1
    say "5 equals 5.0"
if c1 is e1
    say "text 5 equals 5.0"
neg is 0 minus 3
other is 0 minus 3
if neg is other
    say "negative equal"
zero is 0
if zero is 0.0
    say "zero equals 0.0"
tenth is 0.1 plus 0.2
if tenth is 0.3
    say "0.1 plus 0.2 is 0.3"
if "abc" is "abc"
    say "text equals text"
if "abc" is "ABC"
    say "case ignored"
otherwise
    say "text is case sensitive"
'@
    'equality: booleans, lists, things, nothing' = @'
yes is true
no is false
if yes is true
    say "true is true"
if yes is no
    say "true is false"
otherwise
    say "true is not false"
if yes is 1
    say "true is 1"
otherwise
    say "true is not 1"
first are
    1
    2
second are
    1
    2
third are
    1
    3
if first is second
    say "equal lists equal"
if first is third
    say "different lists equal"
otherwise
    say "different lists differ"
if first contains 2
    say "list contains 2"
if first contains 9
    say "contains 9"
otherwise
    say "does not contain 9"
thing1 has color "blue"
thing2 has color "blue"
if thing1 is thing2
    say "distinct things equal"
otherwise
    say "distinct things differ"
if thing1 is thing1
    say "a thing equals itself"
'@
    'contains, remove and find on numbers and text' = @'
values are
    10
    20
    30
    "40"
if values contains 30
    say "contains 30"
if values contains 40
    say "contains 40 (text 40 matches number 40)"
if values contains 99
    say "contains 99"
otherwise
    say "no 99"
remove 20 from values
say values
find item in values where item is 30 into found
say found
'@
    'arithmetic and comparison: values and errors' = @'
x is 7
y is 2
say x plus y
say x minus y
say x times y
say x divided by y
say "3" plus 4
say 10 divided by 4
if x is greater than y
    say "greater"
if y is less than x
    say "less"
if x is at least 7
    say "at least"
if y is at most 2
    say "at most"
say 0.1 plus 0.2
neg is 0 minus 5
say neg times neg
big is 9007199254740992
say big plus 1
'@
    'arithmetic error: text on the left' = @'
name is "Jeff"
say name times 2
'@
    'arithmetic error: text on the right' = @'
x is 3
say x minus "abc"
'@
    'arithmetic error: boolean' = @'
flag is true
say flag plus 1
'@
    'comparison error: text' = @'
word is "abc"
if word is greater than 3
    say "never"
'@
    'division by zero' = @'
say 10 divided by 0
'@
    'variable reads: scalars and lists' = @'
n is 42
t is "hello"
b is true
z is 0
say n t b z
one are
    "solo"
say one
say length of one
empty are empty
say length of empty
matrix are
    "a"
    "b"
say matrix
copy is matrix
say copy
say length of copy
to identity value
    return value
.
to firstOf items
    return first of items
.
to pass items
    return items
.
identity n make r1
identity t make r2
pass matrix make r3
pass one make r4
pass empty make r5
firstOf matrix make r6
say r1 r2 r3
say length of r3
say r4
say length of r4
say length of r5
say r6
thing has holder matrix, count 3
say holder of thing
say count of thing
grabbed is holder of thing
say length of grabbed
'@
    'variable reads: undefined variable' = @'
say missingVariable
'@
    'variable reads inside loops and conditions' = @'
total is 0
items are
    1
    2
    3
for each item in items
    total is total plus item
.
say total
count from 1 to 3 as k
    total is total plus k
.
say total
while total is greater than 10
    total is total minus 5
.
say total
'@
}

function Invoke-OtterSourceCaptured {
    param([string]$Source)

    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($Text) $collected.Add([string]$Text) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        $tokens = ConvertTo-OtterTokens -Source $Source
        $ast = ConvertTo-OtterAst -Tokens $tokens
        Invoke-OtterProgram -Program $ast -Environment (New-OtterEnvironment) -SourceLines ($Source -split "`r?`n")
        $collected.Add('[finished]')
    }
    catch {
        $message = $_.Exception.Message -replace "`r?`n", ' / '
        $line = try { $_.Exception.Line } catch { '' }
        $collected.Add("[error line $line] $message")
    }
    finally {
        Set-OtterOutputWriter -Writer $null
    }
    return ($collected -join "`n")
}

# --- generate mode -----------------------------------------------------------

if ($script:Generate) {
    Write-Output '### GOLDEN-EQUALITY'
    Get-EqualityTable | ForEach-Object { Write-Output $_ }
    Write-Output '### GOLDEN-ASSERT'
    Get-AssertNumberTable | ForEach-Object { Write-Output $_ }
    foreach ($name in $script:Programs.Keys) {
        Write-Output "### GOLDEN-PROGRAM $name"
        Write-Output (Invoke-OtterSourceCaptured -Source $script:Programs[$name])
    }
    exit 0
}

# --- golden data (captured from the un-optimized interpreter) ---------------

$goldenPath = Join-Path $PSScriptRoot 'Optimizations.golden.txt'
$golden = @{}
$current = $null
foreach ($line in [System.IO.File]::ReadAllLines($goldenPath)) {
    if ($line -match '^### GOLDEN-(EQUALITY|ASSERT)$') { $current = $matches[1]; $golden[$current] = New-Object System.Collections.Generic.List[string]; continue }
    if ($line -match '^### GOLDEN-PROGRAM (.+)$') { $current = 'PROGRAM ' + $matches[1]; $golden[$current] = New-Object System.Collections.Generic.List[string]; continue }
    if ($null -ne $current) { $golden[$current].Add($line) }
}

Test-Otter 'OPT-1: Test-OtterEqual gives the same answer for every pair in the value grid' {
    $actual = @(Get-EqualityTable)
    $expected = @($golden['EQUALITY'])
    Assert-AreEqual -Expected $expected.Count -Actual $actual.Count
    $names = @((New-GridValues).Keys)
    for ($i = 0; $i -lt $expected.Count; $i++) {
        if ($actual[$i] -ne $expected[$i]) {
            $left = ($expected[$i] -split '\|')[0]
            $e = ($expected[$i] -split '\|')[1]
            $a = ($actual[$i] -split '\|')[1]
            for ($j = 0; $j -lt $e.Length; $j++) {
                if ($e[$j] -ne $a[$j]) { throw "equality changed: '$left' vs '$($names[$j])' was $($e[$j]) and is now $($a[$j])" }
            }
        }
    }
}

Test-Otter 'OPT-1: numeric equality still handles the cases the fast path must not disturb' {
    # Spot checks that read as documentation of the rule. Each of these came from
    # the golden table above, so this also guards the table itself.
    Assert-True (Test-OtterEqual -Left 5 -Right 5) 'int equals int'
    Assert-False (Test-OtterEqual -Left 5 -Right 6) 'int differs from int'
    Assert-True (Test-OtterEqual -Left 5.5 -Right 5.5) 'decimal equals decimal'
    Assert-False (Test-OtterEqual -Left 5.5 -Right 5.6) 'decimal differs from decimal'
    Assert-True (Test-OtterEqual -Left -3 -Right -3) 'negatives'
    Assert-True (Test-OtterEqual -Left 0 -Right 0.0) 'zero equals 0.0'
    Assert-True (Test-OtterEqual -Left 5 -Right 5.0) 'int equals double'
    Assert-True (Test-OtterEqual -Left '5' -Right 5) 'text 5 equals number 5 (D6)'
    Assert-True (Test-OtterEqual -Left '5.0' -Right '5') 'text 5.0 equals text 5'
    Assert-False (Test-OtterEqual -Left 'abc' -Right 'ABC') 'text is case sensitive'
    Assert-True (Test-OtterEqual -Left $null -Right $null) 'nothing equals nothing'
    Assert-False (Test-OtterEqual -Left $null -Right 0) 'nothing is not zero'
    Assert-False (Test-OtterEqual -Left $true -Right 1) 'true is not 1'
    Assert-False (Test-OtterEqual -Left ([double]::NaN) -Right ([double]::NaN)) 'NaN is not equal to NaN'
    Assert-False (Test-OtterEqual -Left ([long]9007199254740993) -Right ([long]9007199254740992)) 'long values beyond 2^53 still compare as doubles, as before'
}

Test-Otter 'OPT-2: Assert-OtterNumber returns the same value, type and error text for every value in the grid' {
    $actual = @(Get-AssertNumberTable)
    $expected = @($golden['ASSERT'])
    Assert-AreEqual -Expected $expected.Count -Actual $actual.Count
    for ($i = 0; $i -lt $expected.Count; $i++) {
        Assert-AreEqual -Expected $expected[$i] -Actual $actual[$i]
    }
}

foreach ($name in $script:Programs.Keys) {
    $key = 'PROGRAM ' + $name
    Test-Otter "programs: '$name' produces the same output and errors as before" {
        $expected = ($golden[$key] -join "`n").TrimEnd("`r", "`n")
        $actual = (Invoke-OtterSourceCaptured -Source $script:Programs[$name]).TrimEnd("`r", "`n")
        Assert-AreEqual -Expected $expected -Actual $actual
    }
}

Complete-OtterTests
