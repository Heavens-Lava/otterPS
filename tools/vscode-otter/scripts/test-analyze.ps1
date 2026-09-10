$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$analyzer = Join-Path $PSScriptRoot 'analyze.ps1'
$source = @'
name is "Global"
person has
    age is 29
.
to greet name
    say name
.
each file in files
    say file
.
'@
$result = $source | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $analyzer -Root $repo | ConvertFrom-Json
if (-not $result.Ok) { throw 'Analyzer should parse the scope regression source.' }
if (($result.Symbols | Where-Object { $_.Name -eq 'name' }).Count -ne 2) { throw 'Analyzer should preserve global and parameter shadowing.' }
if ($result.ObjectProperties.person[0] -ne 'age') { throw 'Analyzer should retain has-object properties.' }
Write-Output 'Semantic analyzer tests passed.'
