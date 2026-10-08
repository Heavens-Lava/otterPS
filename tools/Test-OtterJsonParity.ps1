using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Library.psm1

# Test-OtterJsonParity.ps1 - differential test of the compiled runtime's JSON
# (OtterLibrary in src/native/OtterNativeRuntime.cs, used by otter.exe's fast
# start) against the interpreter's (ConvertTo-OtterJsonText and
# ConvertFrom-OtterJsonText in src/Otter.Library.psm1), on Windows
# PowerShell 5.1 - the only host otter.exe serves.
#
#     powershell -NoProfile -File tools\Test-OtterJsonParity.ps1 [-Count 2000] [-Seed 1]
#
# Random Otter values (things, lists, numbers, nasty text, dates, bytes) must
# produce the same JSON text or the same error; random and hand-made JSON
# texts must read back as the same Otter value or the same error.
param([int]$Count = 2000, [int]$Seed = 20261007)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') { Write-Host 'skip: otter.exe serves Windows PowerShell 5.1 only'; exit 0 }
$runtimeSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\src\native\OtterNativeRuntime.cs'))
if (-not ('OtterNative.OtterLibrary' -as [type])) { Add-Type -TypeDefinition $runtimeSource }

$rng = [Random]::new($Seed)
$chars = @('a', 'b', 'Z', ' ', '"', '\', '/', '<', '>', '&', "'", "`t", "`n", "`r", [char]8, [char]12, [char]1, [char]31,
    'é', '世', [char]0x2028, [char]0x2029, [char]0x85, '{', '}', '[', ']', ',', ':', '0', '-', '.')
$chars += [char]::ConvertFromUtf32(0x1F600)
$numbers = @(0.0, 1.0, -5.0, 0.1, 2.5, (1.0 / 3), 1e15, 1e16, 1e20, 1e-7, 123456789012.0, (-0.0), 1e308, 2.5e-300, 36.0, 255.0, -0.000123)

function New-Text { $n = $rng.Next(0, 9); -join (1..$n | ForEach-Object { $chars[$rng.Next(0, $chars.Count)] }) }
function New-Number { if ($rng.Next(0, 3) -eq 0) { return [double]($rng.Next(-100000, 100000)) / [Math]::Pow(10, $rng.Next(0, 6)) }; return $numbers[$rng.Next(0, $numbers.Count)] }

function New-Value([int]$depth) {
    $kind = if ($depth -ge 4) { $rng.Next(0, 6) } else { $rng.Next(0, 9) }
    switch ($kind) {
        0 { return $null }
        1 { return ($rng.Next(0, 2) -eq 1) }
        2 { return (New-Number) }
        3 { return (New-Text) }
        4 { return [OtterDate]::new([datetime]::new(1990 + $rng.Next(0, 60), $rng.Next(1, 13), $rng.Next(1, 28), $rng.Next(0, 24), $rng.Next(0, 60), $rng.Next(0, 60)), ($rng.Next(0, 2) -eq 1)) }
        5 { return [OtterBytes]::new([byte[]]@(1..$rng.Next(0, 4) | ForEach-Object { [byte]$rng.Next(0, 256) })) }
        { $_ -in 6, 7 } {
            $o = [OtterObject]::new('thing')
            foreach ($i in 1..$rng.Next(0, 4)) { $k = New-Text; if ($k -and -not $o.HasProperty($k)) { $o.WriteProperty($k, (New-Value ($depth + 1))) } }
            return $o
        }
        8 {
            $l = [System.Collections.Generic.List[object]]::new()
            foreach ($i in 1..$rng.Next(0, 4)) { $l.Add((New-Value ($depth + 1))) }
            return , $l
        }
    }
}

# Interpreter value -> compiled value.
function ConvertTo-Compiled($v) {
    if ($null -eq $v) { return $null }
    if ($v -is [OtterObject]) { $t = [OtterNative.OtterThing]::new($v.TypeName); foreach ($n in $v.PropertyNames()) { $t.Write($n, (ConvertTo-Compiled $v.ReadProperty($n))) }; return $t }
    if ($v -is [System.Collections.Generic.List[object]]) { $l = [System.Collections.Generic.List[object]]::new(); foreach ($i in $v) { $l.Add((ConvertTo-Compiled $i)) }; return , $l }
    if ($v -is [OtterDate]) { return [OtterNative.OtterDateValue]::new($v.Value, $v.HasTime) }
    if ($v -is [OtterBytes]) { return [OtterNative.OtterBytesValue]::new($v.Value) }
    return $v
}

# A value as comparable text, for either side.
function Get-Canon($v) {
    if ($null -eq $v) { return 'gone' }
    if ($v -is [OtterObject]) { return '{' + (($v.PropertyNames() | ForEach-Object { (Get-Canon $_) + '=' + (Get-Canon $v.ReadProperty($_)) }) -join ',') + '}' }
    if ($v -is [OtterNative.OtterThing]) { return '{' + (($v.Names() | ForEach-Object { (Get-Canon $_) + '=' + (Get-Canon $v.Read($_)) }) -join ',') + '}' }
    if ($v -is [System.Collections.Generic.List[object]]) { return '[' + (($v | ForEach-Object { Get-Canon $_ }) -join ',') + ']' }
    if ($v -is [double]) { return 'n:' + $v.ToString('R', [Globalization.CultureInfo]::InvariantCulture) }
    if ($v -is [bool]) { return "b:$v" }
    if ($v -is [string]) { return 's:' + (-join ($v.ToCharArray() | ForEach-Object { if ([int]$_ -ge 32 -and [int]$_ -le 126) { $_ } else { '\u{0:x4}' -f [int]$_ } })) }
    return 'other:' + $v.GetType().FullName
}

function Invoke-Interpreter([scriptblock]$Block) { try { return 'ok ' + (& $Block) } catch { return 'error ' + $_.Exception.Message } }
function Invoke-Compiled([string]$Name, [object[]]$Arguments) {
    try { return 'ok ' + [OtterNative.OtterLibrary]::Call($Name, $Arguments, 1) }
    catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; return 'error ' + $e.Message }
}

$failures = 0
function Assert-Same([string]$What, [string]$Expected, [string]$Actual, [string]$Shown) {
    if ($Expected -ceq $Actual) { return }
    $script:failures++
    if ($script:failures -le 8) {
        Write-Host "MISMATCH ($What)" -ForegroundColor Red
        Write-Host "  input:    $Shown"
        Write-Host "  expected: $($Expected -replace "`r", '\r' -replace "`n", '\n')"
        Write-Host "  actual:   $($Actual -replace "`r", '\r' -replace "`n", '\n')"
    }
}

# --- ConvertTo-Json ----------------------------------------------------------
$texts = [System.Collections.Generic.List[string]]::new()
foreach ($i in 1..$Count) {
    $value = New-Value 0
    $expected = Invoke-Interpreter { ConvertTo-OtterJsonText -Value $value -Line 1 }
    $actual = Invoke-Compiled 'ConvertToJson' @(, (ConvertTo-Compiled $value))
    Assert-Same 'to json' $expected $actual (Get-Canon $value)
    if ($expected.StartsWith('ok ') -and $expected.Length -gt 3) { $texts.Add($expected.Substring(3)) }
}
# Depth past 32, and things that cannot become JSON.
$deep = [OtterObject]::new('thing'); $cur = $deep; foreach ($i in 1..36) { $n = [OtterObject]::new('thing'); $cur.WriteProperty('d', $n); $cur = $n }; $cur.WriteProperty('end', 1.0)
Assert-Same 'deep thing' (Invoke-Interpreter { ConvertTo-OtterJsonText -Value $deep -Line 1 }) (Invoke-Compiled 'ConvertToJson' @(, (ConvertTo-Compiled $deep))) 'deep thing'
$deepList = [System.Collections.Generic.List[object]]::new(); $cur = $deepList; foreach ($i in 1..36) { $n = [System.Collections.Generic.List[object]]::new(); $cur.Add($n); $cur = $n }; $cur.Add(1.0)
Assert-Same 'deep list' (Invoke-Interpreter { ConvertTo-OtterJsonText -Value $deepList -Line 1 }) (Invoke-Compiled 'ConvertToJson' @(, (ConvertTo-Compiled $deepList))) 'deep list'
$withType = [OtterObject]::new('thing'); $withType.WriteProperty('t', [OtterType]::new('Person', [string[]]@('name')))
$withTypeCompiled = [OtterNative.OtterThing]::new('thing'); $withTypeCompiled.Write('t', [OtterNative.OtterTypeValue]::new('Person', [string[]]@('name')))
Assert-Same 'type inside' (Invoke-Interpreter { ConvertTo-OtterJsonText -Value $withType -Line 1 }) (Invoke-Compiled 'ConvertToJson' @(, $withTypeCompiled)) 'type inside'

# --- ConvertFrom-Json ---------------------------------------------------------
$edge = @('42', '-0', '1e400', '-1e400', '12345678901234567890', '0.1', '1E+15', '3.14159265358979323846264338327950288', '"\/Date(1706684400000)\/"',
    '"é世😀"', 'true', 'null', '[]', '{}', '[1,]', '{"a":1,}', '{"a":1,"A":2}', '{"a":1,"a":2}', '{"":1}', '{"a" : 1}',
    "  {`"a`":  [1, 2]}  ", "{'a': 1}", '{a: 1}', 'NaN', 'Infinity', '"unterminated', '[1 2]', '{"x":{"y":{"z":[true,false,null]}}}',
    '"tab\there"', "`"raw`ttab`"", '[1,2]garbage', '01', '+1', '.5', '5.', '1e5', '"\x41"', '"\u004"', '[[[[[]]]]]', ('[' * 150) + (']' * 150), ('[' * 1100) + (']' * 1100))
$jsonInputs = @($edge) + @($texts | Select-Object -First ([Math]::Min($texts.Count, $Count)))
foreach ($text in $jsonInputs) {
    $expected = try { 'ok ' + (Get-Canon (ConvertFrom-OtterJsonText -Text $text -Line 1)) } catch { 'error ' + $_.Exception.Message }
    $actual = try { 'ok ' + (Get-Canon ([OtterNative.OtterLibrary]::Call('ConvertFromJson', [object[]]@([string]$text), 1))) } catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; 'error ' + $e.Message }
    $shown = if ($text.Length -gt 80) { $text.Substring(0, 80) + '...' } else { $text }
    Assert-Same 'from json' $expected $actual $shown
}

$total = $Count + 3 + $jsonInputs.Count
if ($failures -eq 0) { Write-Host "JSON parity: $total cases, all identical (seed $Seed)." -ForegroundColor Green; exit 0 }
Write-Host "JSON parity: $failures of $total cases differ (seed $Seed)." -ForegroundColor Red
exit 1
