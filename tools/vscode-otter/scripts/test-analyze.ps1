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
if (@($result.References | Where-Object { $_.Name -eq 'name' -and -not $_.IsDeclaration }).Count -lt 1) { throw 'Analyzer should emit references for variable uses.' }
if (@($result.Scopes | Where-Object { $_.Symbols -contains 'file' }).Count -ne 1) { throw 'Analyzer should emit a loop-local scope.' }
$validFn = @'
to greet name
    say name
.

greet "Jeff"
'@ | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $analyzer -Root $repo | ConvertFrom-Json
if (-not $validFn.Ok -or @($validFn.Symbols | Where-Object { $_.Name -eq 'greet' }).Count -ne 1) { throw 'Function declaration should produce a function symbol.' }
if (@($validFn.References | Where-Object { $_.Name -eq 'greet' }).Count -ne 2) { throw 'Function references should include declaration and call site.' }
$fnSym = $validFn.Symbols | Where-Object { $_.Name -eq 'greet' } | Select-Object -First 1
if (-not $fnSym.Parameters -or $fnSym.Parameters[0] -ne 'name') { throw 'Function symbol should retain parameter names.' }

# Verify that call before declaration is NOT bound (Otter does not hoist functions)
$earlyCall = @'
greet "Jeff"

to greet name
    say name
.
'@ | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $analyzer -Root $repo | ConvertFrom-Json
if (@($earlyCall.References | Where-Object { $_.Name -eq 'greet' -and -not $_.IsDeclaration }).Count -ne 0) { throw 'Call before declaration should not resolve (Otter has no function hoisting).' }

Write-Output 'Semantic analyzer tests passed.'
