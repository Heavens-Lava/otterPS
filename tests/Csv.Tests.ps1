using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Library.psm1
using module ..\src\Otter.Interpreter.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1
using module ..\src\Otter.Compiler.JavaScript.psm1

# tests/Csv.Tests.ps1
#
# 26-case test suite for D95 CSV support:
# - RFC 4180 parsing and serialization
# - Preservation of cells as text (no type inference)
# - Empty cells ,, become ""
# - Required, unique, non-blank headers
# - Exact row widths
# - Deterministic first-row schema for write
# - File I/O (read csv / write csv)
# - Cross-runtime parity with JavaScript compiler

. "$PSScriptRoot\TestHelpers.ps1"

$sandbox = Join-Path $env:TEMP ("otter-csv-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Path $sandbox -Force)
$originalLocation = (Get-Location).Path
Set-Location $sandbox

function Invoke-TestScript {
    param([string]$Source)
    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($Text) $collected.Add($Text) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        $tokens = ConvertTo-OtterTokens -Source $Source
        $ast = ConvertTo-OtterAst -Tokens $tokens
        Invoke-OtterProgram -Program $ast -Environment (New-OtterEnvironment)
    }
    finally {
        Set-OtterOutputWriter -Writer $null
    }
    return , $collected.ToArray()
}

Write-Host ''
Write-Host 'CSV read/write and conversion (D95)' -ForegroundColor Cyan

# Case 1: Simple 2-column, 2-row parse
Test-Otter 'Case 1: Simple 2-column, 2-row parse' {
    $csv = "name,age`r`nAlice,30`r`nBob,25"
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    Assert-AreEqual -Expected 2 -Actual $rows.Count 'expected 2 rows'
    Assert-AreEqual -Expected 'Alice' -Actual ($rows[0].ReadProperty('name'))
    Assert-AreEqual -Expected '30' -Actual ($rows[0].ReadProperty('age'))
    Assert-AreEqual -Expected 'Bob' -Actual ($rows[1].ReadProperty('name'))
    Assert-AreEqual -Expected '25' -Actual ($rows[1].ReadProperty('age'))
}

# Case 2: Numeric preservation (00123, 42, 3.14 preserved as string)
Test-Otter 'Case 2: Numeric preservation (no type inference)' {
    $csv = "code,count,ratio`r`n00123,42,3.14"
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    $code = $rows[0].ReadProperty('code')
    $count = $rows[0].ReadProperty('count')
    $ratio = $rows[0].ReadProperty('ratio')
    Assert-True ($code -is [string]) 'code must be string'
    Assert-AreEqual -Expected '00123' -Actual $code
    Assert-True ($count -is [string]) 'count must be string'
    Assert-AreEqual -Expected '42' -Actual $count
    Assert-True ($ratio -is [string]) 'ratio must be string'
    Assert-AreEqual -Expected '3.14' -Actual $ratio
}

# Case 3: Empty cells ,, -> ""
Test-Otter 'Case 3: Empty cells become empty string, not gone' {
    $csv = "first,middle,last`r`nJohn,,Doe"
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    $middle = $rows[0].ReadProperty('middle')
    Assert-True ($middle -is [string]) 'middle must be string'
    Assert-AreEqual -Expected '' -Actual $middle 'middle must be empty string'
}

# Case 4: Quoted fields with comma
Test-Otter 'Case 4: Quoted fields containing commas' {
    $csv = "city,description`r`nPortland,""City of Roses, Oregon"""
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    Assert-AreEqual -Expected 'City of Roses, Oregon' -Actual ($rows[0].ReadProperty('description'))
}

# Case 5: Quoted fields with escaped quotes
Test-Otter 'Case 5: Quoted fields with escaped quotes' {
    $csv = @'
author,quote
Mark Twain,"He said, ""Truth is mighty."""
'@
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    Assert-AreEqual -Expected 'He said, "Truth is mighty."' -Actual ($rows[0].ReadProperty('quote'))
}

# Case 6: Quoted fields with embedded newlines
Test-Otter 'Case 6: Quoted fields with embedded newlines' {
    $csv = "id,notes`r`n1,""line 1`r`nline 2"""
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    Assert-AreEqual -Expected "line 1`r`nline 2" -Actual ($rows[0].ReadProperty('notes'))
}

# Case 7: Unicode headers and cell values
Test-Otter 'Case 7: Unicode headers and cell values' {
    $otterEmoji = [char]::ConvertFromUtf32(0x1F9A6)
    $aisatsu = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE6,0x8C,0xA8,0xE6,0x8B,0xB6))
    $konnichiwa = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x81,0x93,0xE3,0x82,0x93,0xE3,0x81,0xAB,0xE3,0x81,0xA1,0xE3,0x81,0xAF,0xE4,0xB8,0x96,0xE7,0x95,0x8C))
    $csv = "$otterEmoji,$aisatsu`r`nOtter,$konnichiwa"
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    Assert-AreEqual -Expected 'Otter' -Actual ($rows[0].ReadProperty($otterEmoji))
    Assert-AreEqual -Expected $konnichiwa -Actual ($rows[0].ReadProperty($aisatsu))
}

# Case 8: Header requirement (empty document error)
Test-Otter 'Case 8: Header requirement on empty input' {
    Assert-OtterFails -Containing 'Otter needs a header row to read CSV into things.' -Body {
        ConvertFrom-OtterCsvText -Text "" -Line 1
    }
    Assert-OtterFails -Containing 'Otter needs a header row to read CSV into things.' -Body {
        ConvertFrom-OtterCsvText -Text "   `r`n  `r`n" -Line 1
    }
}

# Case 9: Blank header rejection
Test-Otter 'Case 9: Blank header rejection' {
    Assert-OtterFails -Containing 'CSV headers cannot be empty.' -Body {
        ConvertFrom-OtterCsvText -Text "name,,age`r`nAlice,X,30" -Line 1
    }
}

# Case 10: Duplicate header rejection
Test-Otter 'Case 10: Duplicate header rejection' {
    Assert-OtterFails -Containing 'appears more than once' -Body {
        ConvertFrom-OtterCsvText -Text "name,age,name`r`nAlice,30,Smith" -Line 1
    }
    # Case-insensitive duplication rejection
    Assert-OtterFails -Containing 'appears more than once' -Body {
        ConvertFrom-OtterCsvText -Text "Name,age,name`r`nAlice,30,Smith" -Line 1
    }
}

# Case 11: Ragged row: too few fields error
Test-Otter 'Case 11: Ragged row - too few fields' {
    Assert-OtterFails -Containing 'Row 2 has 2 fields, but the CSV header defines 3 columns.' -Body {
        ConvertFrom-OtterCsvText -Text "col1,col2,col3`r`nval1,val2" -Line 1
    }
}

# Case 12: Ragged row: too many fields error
Test-Otter 'Case 12: Ragged row - too many fields' {
    Assert-OtterFails -Containing 'Row 2 has 4 fields, but the CSV header defines 3 columns.' -Body {
        ConvertFrom-OtterCsvText -Text "col1,col2,col3`r`nval1,val2,val3,val4" -Line 1
    }
}

# Case 13: CRLF and LF normalization
Test-Otter 'Case 13: Both CRLF and LF line endings parse correctly' {
    $crlf = "a,b`r`n1,2`r`n3,4"
    $lf = "a,b`n1,2`n3,4"
    $rowsCrlf = ConvertFrom-OtterCsvText -Text $crlf -Line 1
    $rowsLf = ConvertFrom-OtterCsvText -Text $lf -Line 1
    Assert-AreEqual -Expected 2 -Actual $rowsCrlf.Count
    Assert-AreEqual -Expected 2 -Actual $rowsLf.Count
    Assert-AreEqual -Expected ($rowsCrlf[0].ReadProperty('a')) -Actual ($rowsLf[0].ReadProperty('a'))
    Assert-AreEqual -Expected ($rowsCrlf[1].ReadProperty('b')) -Actual ($rowsLf[1].ReadProperty('b'))
}

# Case 14: Trailing empty line ignored per RFC 4180
Test-Otter 'Case 14: Trailing empty line ignored per RFC 4180' {
    $csv = "name,age`r`nAlice,30`r`n"
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    Assert-AreEqual -Expected 1 -Actual $rows.Count
    Assert-AreEqual -Expected 'Alice' -Actual ($rows[0].ReadProperty('name'))
}

# Case 15: Trailing comma on row -> empty string cell
Test-Otter 'Case 15: Trailing comma on row produces empty string cell' {
    $csv = "name,age,extra`r`nAlice,30,"
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    Assert-AreEqual -Expected 1 -Actual $rows.Count
    Assert-AreEqual -Expected '' -Actual ($rows[0].ReadProperty('extra'))
}

# Case 16: Simple CSV write (header + rows with CRLF)
Test-Otter 'Case 16: Simple CSV write' {
    $list = [System.Collections.Generic.List[object]]::new()
    $t1 = [OtterObject]::new('thing')
    $t1.WriteProperty('name', 'Alice')
    $t1.WriteProperty('age', '30')
    $list.Add($t1)
    $t2 = [OtterObject]::new('thing')
    $t2.WriteProperty('name', 'Bob')
    $t2.WriteProperty('age', '25')
    $list.Add($t2)

    $csv = ConvertTo-OtterCsvText -Rows $list -Line 1
    Assert-AreEqual -Expected "name,age`r`nAlice,30`r`nBob,25`r`n" -Actual $csv
}

# Case 17: CSV write escaping (commas, quotes, newlines)
Test-Otter 'Case 17: CSV write escaping' {
    $list = [System.Collections.Generic.List[object]]::new()
    $t = [OtterObject]::new('thing')
    $t.WriteProperty('desc', 'Hello, World')
    $t.WriteProperty('quote', 'He said "hi"')
    $t.WriteProperty('multiline', "a`r`nb")
    $list.Add($t)

    $csv = ConvertTo-OtterCsvText -Rows $list -Line 1
    $expected = "desc,quote,multiline`r`n""Hello, World"",""He said """"hi"""""",""a`r`nb""`r`n"
    Assert-AreEqual -Expected $expected -Actual $csv
}

# Case 18: CSV write explicit gone ($null) -> empty cell
Test-Otter 'Case 18: CSV write explicit gone produces empty cell' {
    $list = [System.Collections.Generic.List[object]]::new()
    $t = [OtterObject]::new('thing')
    $t.WriteProperty('a', 'first')
    $t.WriteProperty('b', $null)
    $t.WriteProperty('c', 'third')
    $list.Add($t)

    $csv = ConvertTo-OtterCsvText -Rows $list -Line 1
    Assert-AreEqual -Expected "a,b,c`r`nfirst,,third`r`n" -Actual $csv
}

# Case 19: CSV write rejecting non-list
Test-Otter 'Case 19: CSV write rejecting non-list' {
    Assert-OtterFails -Containing 'Otter can only write a list of things to CSV.' -Body {
        ConvertTo-OtterCsvText -Rows 'not a list' -Line 1
    }
}

# Case 20: CSV write rejecting list with non-things
Test-Otter 'Case 20: CSV write rejecting list with non-things' {
    $list = [System.Collections.Generic.List[object]]::new()
    $list.Add(123)
    Assert-OtterFails -Containing 'Otter can only write a list of things to CSV.' -Body {
        ConvertTo-OtterCsvText -Rows $list -Line 1
    }
}

# Case 21: CSV write schema mismatch: missing property
Test-Otter 'Case 21: CSV write schema mismatch - missing property' {
    $list = [System.Collections.Generic.List[object]]::new()
    $t1 = [OtterObject]::new('thing')
    $t1.WriteProperty('name', 'Alice')
    $t1.WriteProperty('age', '30')
    $list.Add($t1)
    $t2 = [OtterObject]::new('thing')
    $t2.WriteProperty('name', 'Bob')
    $list.Add($t2)

    Assert-OtterFails -Containing 'Row 3 properties do not match the columns defined by the first row.' -Body {
        ConvertTo-OtterCsvText -Rows $list -Line 1
    }
}

# Case 22: CSV write schema mismatch: extra property
Test-Otter 'Case 22: CSV write schema mismatch - extra property' {
    $list = [System.Collections.Generic.List[object]]::new()
    $t1 = [OtterObject]::new('thing')
    $t1.WriteProperty('name', 'Alice')
    $list.Add($t1)
    $t2 = [OtterObject]::new('thing')
    $t2.WriteProperty('name', 'Bob')
    $t2.WriteProperty('extra', 'val')
    $list.Add($t2)

    Assert-OtterFails -Containing 'Row 3 properties do not match the columns defined by the first row.' -Body {
        ConvertTo-OtterCsvText -Rows $list -Line 1
    }
}

# Case 23: CSV write column ordering matches first row property order
Test-Otter 'Case 23: CSV write column ordering strictly matches first row property order' {
    $list = [System.Collections.Generic.List[object]]::new()
    $t1 = [OtterObject]::new('thing')
    $t1.WriteProperty('z', '1')
    $t1.WriteProperty('a', '2')
    $t1.WriteProperty('m', '3')
    $list.Add($t1)

    $csv = ConvertTo-OtterCsvText -Rows $list -Line 1
    $firstLine = ($csv -split "`r?`n")[0]
    Assert-AreEqual -Expected 'z,a,m' -Actual $firstLine 'columns must follow insertion order of first row'
}

# Case 24: Round-trip read -> write -> read identity
Test-Otter 'Case 24: Round-trip read -> write -> read identity' {
    $original = "name,role,dept`r`nAlice,Lead,Eng`r`nBob,Intern,Sales`r`n"
    $rows = ConvertFrom-OtterCsvText -Text $original -Line 1
    $written = ConvertTo-OtterCsvText -Rows $rows -Line 1
    Assert-AreEqual -Expected $original -Actual $written 'written CSV must match original exactly'
    $rows2 = ConvertFrom-OtterCsvText -Text $written -Line 1
    Assert-AreEqual -Expected ($rows.Count) -Actual ($rows2.Count)
    Assert-AreEqual -Expected ($rows[0].ReadProperty('name')) -Actual ($rows2[0].ReadProperty('name'))
    Assert-AreEqual -Expected ($rows[1].ReadProperty('role')) -Actual ($rows2[1].ReadProperty('role'))
}

# Case 25: File I/O (read csv from ... into ... / write csv ... to ...)
Test-Otter 'Case 25: File I/O via Otter statements' {
    $filePath = Join-Path $sandbox 'employees.csv'
    $script = @"
staff are empty
p1 has
    name is "David"
    team is "Core"
.
add p1 to staff
p2 has
    name is "Elena"
    team is "Cloud"
.
add p2 to staff

write csv staff to "$($filePath.Replace('\', '/'))"

read csv from "$($filePath.Replace('\', '/'))" into imported
for each e in imported
    say name of e
    say team of e
.
"@
    $out = Invoke-TestScript -Source $script
    Assert-Lines -Expected @('David', 'Core', 'Elena', 'Cloud') -Actual $out
    Assert-True (Test-Path -LiteralPath $filePath) 'file must exist on disk'
}

# Case 26: Cross-runtime parity (JavaScript compiler execution in Node)
Test-Otter 'Case 26: Cross-runtime parity between PS interpreter and JS compiler' {
    $locals = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    [void]$locals.Add('items')
    [void]$locals.Add('csvOut')

    $astFrom = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source 'convert text from csv into items')
    $jsFrom = ConvertTo-OtterJsStatement -Stmt $astFrom.Statements[0] -LocalNames $locals

    $astTo = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source 'convert items to csv into csvOut')
    $jsTo = ConvertTo-OtterJsStatement -Stmt $astTo.Statements[0] -LocalNames $locals

    $nodeScript = @"
let text = "id,name,score\r\n001,Alice,95\r\n002,Bob,88";
let items;
let csvOut;
$jsFrom
$jsTo
if (!items || items.length !== 2) { process.exit(1); }
if (items[0].props.id !== '001') { process.exit(2); }
if (items[0].props.score !== '95') { process.exit(3); }
if (csvOut !== "id,name,score\r\n001,Alice,95\r\n002,Bob,88\r\n") { process.exit(4); }
console.log('PARITY_OK');
"@
    $nodeScriptFile = Join-Path $sandbox 'parity_test.js'
    Set-Content -LiteralPath $nodeScriptFile -Value $nodeScript
    $nodeOut = & node $nodeScriptFile
    Assert-AreEqual -Expected 'PARITY_OK' -Actual $nodeOut 'Node execution must match PowerShell CSV behavior'
}

# Case 27: Unclosed quote at end of input
Test-Otter 'Case 27: Unclosed quote at end of input throws clean error' {
    Assert-OtterFails -Containing 'This is not valid CSV, so Otter could not read it.' -Body {
        ConvertFrom-OtterCsvText -Text "name,age`r`nAlice,30`"" -Line 1
    }
}

# Case 28: Unmatched quote in middle
Test-Otter 'Case 28: Unmatched quote in middle throws clean error' {
    Assert-OtterFails -Containing 'This is not valid CSV, so Otter could not read it.' -Body {
        ConvertFrom-OtterCsvText -Text "name,age`r`n`"Alice,30`r`nBob,25" -Line 1
    }
}

# Case 29: Whitespace outside quotes preserved per RFC 4180
Test-Otter 'Case 29: Whitespace outside quotes is preserved per RFC 4180' {
    $csv = "name,age`r`n  `"Alice`"  , 30 "
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    Assert-AreEqual -Expected 1 -Actual $rows.Count
    Assert-AreEqual -Expected '  Alice  ' -Actual ($rows[0].ReadProperty('name'))
    Assert-AreEqual -Expected ' 30 ' -Actual ($rows[0].ReadProperty('age'))
}

# Case 30: Multiple trailing newlines ignored per RFC 4180
Test-Otter 'Case 30: Multiple trailing newlines are ignored per RFC 4180' {
    $csv = "name,age`r`nAlice,30`r`n`r`n`n"
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    Assert-AreEqual -Expected 1 -Actual $rows.Count
    Assert-AreEqual -Expected 'Alice' -Actual ($rows[0].ReadProperty('name'))
}

# Case 31: CSV containing only a header returns empty list of things
Test-Otter 'Case 31: CSV containing only a header returns empty list of things' {
    $csv1 = "name,age,city"
    $rows1 = ConvertFrom-OtterCsvText -Text $csv1 -Line 1
    Assert-AreEqual -Expected 0 -Actual $rows1.Count
    Assert-True ($rows1 -is [System.Collections.Generic.List[object]])

    $csv2 = "name,age,city`r`n"
    $rows2 = ConvertFrom-OtterCsvText -Text $csv2 -Line 1
    Assert-AreEqual -Expected 0 -Actual $rows2.Count
}

# Case 32: One-column CSV parses and writes cleanly
Test-Otter 'Case 32: One-column CSV parses and writes cleanly' {
    $csv = "title`r`nArticle 1`r`nArticle 2"
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    Assert-AreEqual -Expected 2 -Actual $rows.Count
    Assert-AreEqual -Expected 'Article 1' -Actual ($rows[0].ReadProperty('title'))
    Assert-AreEqual -Expected 'Article 2' -Actual ($rows[1].ReadProperty('title'))

    $out = ConvertTo-OtterCsvText -Rows $rows -Line 1
    Assert-AreEqual -Expected "title`r`nArticle 1`r`nArticle 2`r`n" -Actual $out
}

# Case 33: Header containing escaped quote
Test-Otter 'Case 33: Header containing escaped quote' {
    $csv = @'
"first ""name""",age
Alice,30
'@
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    Assert-AreEqual -Expected 1 -Actual $rows.Count
    $headerName = 'first "name"'
    Assert-True ($rows[0].HasProperty($headerName))
    Assert-AreEqual -Expected 'Alice' -Actual ($rows[0].ReadProperty($headerName))
}

# Case 34: Bare CR inside quoted field is preserved
Test-Otter 'Case 34: Bare CR inside quoted field is preserved' {
    $csv = "id,note`r`n1,`"hello`rworld`""
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    Assert-AreEqual -Expected "hello`rworld" -Actual ($rows[0].ReadProperty('note'))
}

# Case 35: Bare CR outside quoted field acts as line break
Test-Otter 'Case 35: Bare CR outside quoted field acts as line break' {
    $csv = "name,age`rAlice,30`rBob,25"
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    Assert-AreEqual -Expected 2 -Actual $rows.Count
    Assert-AreEqual -Expected 'Alice' -Actual ($rows[0].ReadProperty('name'))
    Assert-AreEqual -Expected 'Bob' -Actual ($rows[1].ReadProperty('name'))
}

# Case 36: Extremely long single field (100,000 characters)
Test-Otter 'Case 36: Extremely long single field (100,000 characters)' {
    $longString = [string]::new('X', 100000)
    $csv = "id,data`r`n1,$longString"
    $rows = ConvertFrom-OtterCsvText -Text $csv -Line 1
    Assert-AreEqual -Expected 1 -Actual $rows.Count
    Assert-AreEqual -Expected 100000 -Actual (($rows[0].ReadProperty('data')).Length)
}

# Case 37: Empty list serialization throws clean diagnostic
Test-Otter 'Case 37: Empty list serialization throws clean diagnostic' {
    Assert-OtterFails -Containing 'Otter cannot write an empty list to CSV because there are no column headers.' -Body {
        ConvertTo-OtterCsvText -Rows ([System.Collections.Generic.List[object]]::new()) -Line 1
    }
}

# Case 38: Object schema matching with different property insertion order
Test-Otter 'Case 38: Object schema matching with different property insertion order' {
    $list = [System.Collections.Generic.List[object]]::new()
    $t1 = [OtterObject]::new('thing')
    $t1.WriteProperty('name', 'Alice')
    $t1.WriteProperty('age', '30')
    $list.Add($t1)

    $t2 = [OtterObject]::new('thing')
    $t2.WriteProperty('age', '25')
    $t2.WriteProperty('name', 'Bob')
    $list.Add($t2)

    $csv = ConvertTo-OtterCsvText -Rows $list -Line 1
    $expected = "name,age`r`nAlice,30`r`nBob,25`r`n"
    Assert-AreEqual -Expected $expected -Actual $csv 'Second row must follow column order of first row'
}

# Case 39: Case difference in property name fails schema check
Test-Otter 'Case 39: Case difference in property name fails schema check' {
    $list = [System.Collections.Generic.List[object]]::new()
    $t1 = [OtterObject]::new('thing')
    $t1.WriteProperty('Name', 'Alice')
    $list.Add($t1)

    $t2 = [OtterObject]::new('thing')
    $t2.WriteProperty('name', 'Bob')
    $list.Add($t2)

    Assert-OtterFails -Containing 'Row 3 properties do not match the columns defined by the first row.' -Body {
        ConvertTo-OtterCsvText -Rows $list -Line 1
    }
}

# Case 40: Newline at EOF vs no newline at EOF
Test-Otter 'Case 40: Newline at EOF vs no newline at EOF parse identically' {
    $csvNoNl = "name,age`r`nAlice,30"
    $csvWithNl = "name,age`r`nAlice,30`r`n"
    $r1 = ConvertFrom-OtterCsvText -Text $csvNoNl -Line 1
    $r2 = ConvertFrom-OtterCsvText -Text $csvWithNl -Line 1
    Assert-AreEqual -Expected 1 -Actual $r1.Count
    Assert-AreEqual -Expected 1 -Actual $r2.Count
    Assert-AreEqual -Expected ($r1[0].ReadProperty('name')) -Actual ($r2[0].ReadProperty('name'))
    Assert-AreEqual -Expected ($r1[0].ReadProperty('age')) -Actual ($r2[0].ReadProperty('age'))
}

# Case 41: Full adversarial cross-runtime parity with Node.js
Test-Otter 'Case 41: Full adversarial cross-runtime parity with Node.js' {
    $locals = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    [void]$locals.Add('items')
    [void]$locals.Add('csvOut')
    [void]$locals.Add('text')
    [void]$locals.Add('rows')

    $astFrom = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source 'convert text from csv into items')
    $jsFromStmt = ConvertTo-OtterJsStatement -Stmt $astFrom.Statements[0] -LocalNames $locals

    $astTo = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source 'convert rows to csv into csvOut')
    $jsToStmt = ConvertTo-OtterJsStatement -Stmt $astTo.Statements[0] -LocalNames $locals

    $nodeScript = @"
function fromCsv(text) { let items; $jsFromStmt; return items; }
function toCsv(rows) { let csvOut; $jsToStmt; return csvOut; }

// Verify empty header list
if (fromCsv('a,b').length !== 0) process.exit(1);
// Verify 1-col CSV
const oneCol = fromCsv('title\r\nItem 1');
if (oneCol.length !== 1 || oneCol[0].props.title !== 'Item 1') process.exit(2);
// Verify bare CR outside quotes
const bareCr = fromCsv('x,y\r1,2');
if (bareCr.length !== 1 || bareCr[0].props.x !== '1') process.exit(3);
// Verify different property insertion order in toCsv
const t1 = { __otterThing: true, typeName: 'thing', props: { name: 'Alice', age: '30' }, order: ['name', 'age'] };
const t2 = { __otterThing: true, typeName: 'thing', props: { age: '25', name: 'Bob' }, order: ['age', 'name'] };
const out = toCsv([t1, t2]);
if (out !== 'name,age\r\nAlice,30\r\nBob,25\r\n') process.exit(4);
console.log('ADVERSARIAL_PARITY_OK');
"@
    $nodeScriptFile = Join-Path $sandbox 'adv_parity.js'
    Set-Content -LiteralPath $nodeScriptFile -Value $nodeScript
    $nodeOut = & node $nodeScriptFile
    Assert-AreEqual -Expected 'ADVERSARIAL_PARITY_OK' -Actual $nodeOut
}

Set-Location $originalLocation
Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue

Complete-OtterTests
