using module ..\Otter.Contract.psm1
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Transpiler.psm1') -Global -Force

Write-Output 'Otter Transpiler'

$hello = ConvertTo-OtterJavaScript -Source 'say "Hello"'
if ($hello -notmatch 'console\.log') {
    throw 'Expected say to transpile through the JavaScript emitter to console.log.'
}
if ($hello -notmatch 'Hello') {
    throw 'Expected generated JavaScript to preserve the string literal.'
}
Write-Output '  pass  source -> JavaScript smoke test'

$source = @"
name is "Jeff"
say name
"@
$tokens = ConvertTo-OtterTokens -Source $source
$program = ConvertTo-OtterAst -Tokens $tokens
$fromSource = ConvertTo-OtterJavaScript -Source $source
$fromAst = ConvertTo-OtterJavaScriptProgram -Program $program
if ($fromSource -cne $fromAst) {
    throw 'Expected source and ProgramNode transpiler APIs to emit identical JavaScript.'
}
Write-Output '  pass  source and AST APIs agree'

$again = ConvertTo-OtterJavaScript -Source $source
if ($fromSource -cne $again) {
    throw 'Expected identical source to generate deterministic JavaScript.'
}
Write-Output '  pass  deterministic output'

$condition = @"
age is 29
if age is at least 18
    say "Adult"
"@
$conditionJs = ConvertTo-OtterJavaScript -Source $condition
if ($conditionJs -notmatch '>=') {
    throw 'Expected "is at least" to transpile to a JavaScript >= comparison.'
}
if ($conditionJs -notmatch 'Adult') {
    throw 'Expected condition body to be emitted.'
}
Write-Output '  pass  condition transpilation'

$empty = ConvertTo-OtterJavaScript -Source ''
if ($empty -ne '') {
    throw 'Expected empty Otter source to emit an empty JavaScript string.'
}
Write-Output '  pass  empty source'

$gotOtterError = $false
try {
    [void](ConvertTo-OtterJavaScript -Source 'value = 5')
} catch {
    if ($_.Exception -is [OtterError]) {
        $gotOtterError = $true
    } else {
        throw "Expected OtterError for invalid source but got $($_.Exception.GetType().FullName)."
    }
}
if (-not $gotOtterError) {
    throw 'Expected invalid Otter source to throw OtterError.'
}
Write-Output '  pass  diagnostics preserved'

Write-Output 'Otter Transpiler: all tests passed'
