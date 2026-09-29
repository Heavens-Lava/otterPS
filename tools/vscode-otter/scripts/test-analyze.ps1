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

# Assignment updates the variable where it already lives: inside a function,
# `currentPage is name` writes the top-level currentPage (OtterBoard's
# showPage), so it is not a new, never-read local. A new name still is local.
$globalWrite = @'
currentPage is "home"
to showPage name
    currentPage is name
    count is 1
.
showPage "notes"
say currentPage
'@ | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $analyzer -Root $repo | ConvertFrom-Json
if (@($globalWrite.Symbols | Where-Object { $_.Name -eq 'currentPage' }).Count -ne 1) { throw 'Writing a top-level variable inside a function must not declare a local one.' }
$write = $globalWrite.References | Where-Object { $_.Name -eq 'currentPage' -and $_.Line -eq 3 }
if (-not $write -or $write.ScopeId -ne 0) { throw 'The write inside the function must refer to the top-level variable.' }
if (-not ($globalWrite.Symbols | Where-Object { $_.Name -eq 'count' -and $_.ScopeId -ne 0 })) { throw 'A new name assigned in a function is still local to it.' }

Write-Output 'Semantic analyzer tests passed.'
