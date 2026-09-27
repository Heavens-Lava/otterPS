using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Library.psm1
using module ..\src\Otter.Interpreter.psm1

# Data.Tests.ps1
#
# JSON, random values, and diagnostics (D29, D30, D31), plus the two
# corrections rules3.md forced:
#
#   rules3 section 8   a file object must expose created and modified
#   rules3 section 26  replace must not mutate unless the syntax asks

. "$PSScriptRoot\TestHelpers.ps1"

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("otter-data-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Path $sandbox -Force)
$originalLocation = (Get-Location).Path
Set-Location $sandbox

function Lit { param($Value, [int]$Line = 1) [LiteralExpr]::new($Value, $Line) }
function Var { param([string]$Name, [int]$Line = 1) [VariableExpr]::new($Name, $Line) }
function PropOf { param([string]$P, [Node]$T, [int]$Line = 1) [PropertyAccessExpr]::new($P, $T, $Line) }
function OpOf { param([string]$Op, [Node]$S, [int]$Line = 1) [OfOperationExpr]::new([OfOperation]$Op, $S, $Line) }
function Gone { param([int]$Line = 1) [LiteralExpr]::new($null, $Line) }
function CompareEx { param([Node]$L, [string]$Op, [Node]$R, [int]$Line = 1) [ComparisonExpr]::new($L, [CompareOp]$Op, $R, $Line) }

function Invoke-TestProgram {
    param([Node[]]$Statements)
    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($Text) $collected.Add($Text) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        Invoke-OtterProgram -Program ([ProgramNode]::new($Statements)) -Environment (New-OtterEnvironment)
    }
    finally {
        Set-OtterOutputWriter -Writer $null
    }
    return , $collected.ToArray()
}

Write-Host ''
Write-Host 'JSON, random, diagnostics' -ForegroundColor Cyan


# =================================================================
# rules3 corrections
# =================================================================

Test-Otter 'a file object exposes created and modified (rules3 s8)' {
    Set-Content -LiteralPath (Join-Path $sandbox 'note.txt') -Value 'hi' -NoNewline
    $file = New-OtterFileObject -Path 'note.txt'
    foreach ($property in @('name', 'path', 'extension', 'size', 'created', 'modified')) {
        Assert-True $file.HasProperty($property) "expected a $property property"
    }
    Assert-True ([string]$file.ReadProperty('modified')).Length -gt 0 'modified must have a value'
}

Test-Otter 'replace into a destination leaves the original alone (rules3 s26)' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('name', (Lit 'Jeff Macy'), 1),
        [ReplaceStmt]::new((Lit 'Jeff'), (Lit 'Jeffrey'), 'name', 'updatedName', 2),
        [SayStmt]::new(@((Var 'name')), 3),
        [SayStmt]::new(@((Var 'updatedName')), 4)
    )
    Assert-Lines -Expected @('Jeff Macy', 'Jeffrey Macy') -Actual $out
}

Test-Otter 'replace without a destination still changes the named variable' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('name', (Lit 'Jeff Macy'), 1),
        [ReplaceStmt]::new((Lit 'Jeff'), (Lit 'Jeffrey'), 'name', 2),
        [SayStmt]::new(@((Var 'name')), 3)
    )
    Assert-Lines -Expected @('Jeffrey Macy') -Actual $out
}


# =================================================================
# D29 - JSON
# =================================================================

Test-Otter 'read json from a file, then read it with ordinary properties' {
    # rules3 section 36: no separate JSON-navigation syntax.
    Set-Content -LiteralPath (Join-Path $sandbox 'settings.json') `
        -Value '{"theme":"dark","volume":80}' -NoNewline

    $out = Invoke-TestProgram @(
        [ReadJsonStmt]::new((Lit 'settings.json'), 'settings', 1),
        [SayStmt]::new(@((PropOf 'theme' (Var 'settings'))), 2),
        [SayStmt]::new(@((PropOf 'volume' (Var 'settings'))), 3)
    )
    Assert-Lines -Expected @('dark', '80') -Actual $out
}

Test-Otter 'nested json reads as city of address of user' {
    Set-Content -LiteralPath (Join-Path $sandbox 'user.json') `
        -Value '{"name":"Jeff","address":{"city":"Tucson"}}' -NoNewline

    $out = Invoke-TestProgram @(
        [ReadJsonStmt]::new((Lit 'user.json'), 'user', 1),
        [SayStmt]::new(@((PropOf 'city' (PropOf 'address' (Var 'user')))), 2)
    )
    Assert-Lines -Expected @('Tucson') -Actual $out
}

Test-Otter 'a json array becomes an ordinary Otter list' {
    Set-Content -LiteralPath (Join-Path $sandbox 'games.json') `
        -Value '{"games":["Zelda","Mario","Pokemon"]}' -NoNewline

    $out = Invoke-TestProgram @(
        [ReadJsonStmt]::new((Lit 'games.json'), 'data', 1),
        [AssignStmt]::new('games', (PropOf 'games' (Var 'data')), 2),
        [SayStmt]::new(@((OpOf 'Length' (Var 'games'))), 3),
        [ForEachStmt]::new('game', (Var 'games'), @(
            [SayStmt]::new(@((Var 'game')), 5)
        ), 4)
    )
    Assert-Lines -Expected @('3', 'Zelda', 'Mario', 'Pokemon') -Actual $out
}

Test-Otter 'json numbers and booleans keep their types' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('text', (Lit '{"count":7,"ready":true}'), 1),
        [ConvertFromJsonStmt]::new((Var 'text'), 'data', 2),
        [IfStmt]::new(
            @([IfBranch]::new(
                (CompareEx (PropOf 'count' (Var 'data')) 'AtLeast' (Lit 5.0)),
                @([SayStmt]::new(@((Lit 'at least five')), 4)))),
            $null, 3),
        [SayStmt]::new(@((PropOf 'ready' (Var 'data'))), 5)
    )
    Assert-Lines -Expected @('at least five', 'true') -Actual $out
}

Test-Otter 'convert a thing to json and back again' {
    $out = Invoke-TestProgram @(
        [ObjectDefStmt]::new('user', 'thing', @(
            [AssignStmt]::new('name', (Lit 'Jeff'), 2),
            [AssignStmt]::new('age', (Lit 29.0), 3)
        ), 1),
        [ConvertToJsonStmt]::new((Var 'user'), 'text', 5),
        [ConvertFromJsonStmt]::new((Var 'text'), 'again', 6),
        [SayStmt]::new(@((PropOf 'name' (Var 'again')), (PropOf 'age' (Var 'again'))), 7)
    )
    Assert-Lines -Expected @('Jeff 29') -Actual $out
}

Test-Otter 'broken json says so instead of crashing' {
    Assert-OtterFails -Containing 'not valid JSON' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('text', (Lit '{not json at all'), 1),
            [ConvertFromJsonStmt]::new((Var 'text'), 'data', 2)
        )
    }
}

Test-Otter 'gone survives a json round trip' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('text', (Lit '{"user":null}'), 1),
        [ConvertFromJsonStmt]::new((Var 'text'), 'data', 2),
        [IfStmt]::new(
            @([IfBranch]::new(
                (CompareEx (PropOf 'user' (Var 'data')) 'Equal' (Gone)),
                @([SayStmt]::new(@((Lit 'no user')), 4)))),
            $null, 3)
    )
    Assert-Lines -Expected @('no user') -Actual $out
}


# =================================================================
# D30 - random
# =================================================================

Test-Otter 'random number stays inside its range, both ends included' {
    $seen = @{}
    for ($i = 0; $i -lt 60; $i++) {
        $out = Invoke-TestProgram @(
            [RandomNumberStmt]::new((Lit 1.0), (Lit 3.0), 'n', 1),
            [SayStmt]::new(@((Var 'n')), 2)
        )
        $seen[$out[0]] = $true
        Assert-True ($out[0] -in @('1', '2', '3')) "out of range: $($out[0])"
    }
    # Over 60 draws from three values, all three should appear.
    Assert-AreEqual -Expected 3 -Actual $seen.Keys.Count -Message 'expected every value in range'
}

Test-Otter 'random item comes from the list' {
    $out = Invoke-TestProgram @(
        [ListDefStmt]::new('games', @((Lit 'Zelda'), (Lit 'Mario')), 1),
        [RandomItemStmt]::new((Var 'games'), 'game', 2),
        [SayStmt]::new(@((Var 'game')), 3)
    )
    Assert-True ($out[0] -in @('Zelda', 'Mario')) "unexpected item: $($out[0])"
}

Test-Otter 'random item from an empty list is gone' {
    $out = Invoke-TestProgram @(
        [ListDefStmt]::new('games', @(), 1),
        [RandomItemStmt]::new((Var 'games'), 'game', 2),
        [SayStmt]::new(@((Var 'game')), 3)
    )
    Assert-Lines -Expected @('gone') -Actual $out
}


# =================================================================
# D31 - diagnostics are not "say"
# =================================================================

Test-Otter 'log, warn and error do not appear in ordinary output' {
    $said = [System.Collections.Generic.List[string]]::new()
    $logged = [System.Collections.Generic.List[string]]::new()

    Set-OtterOutputWriter -Writer { param($Text) $said.Add($Text) }.GetNewClosure()
    Set-OtterDiagnosticWriter -Writer { param($Level, $Text) $logged.Add("$Level|$Text") }.GetNewClosure()
    try {
        Invoke-OtterProgram -Environment (New-OtterEnvironment) -Program ([ProgramNode]::new(@(
            [SayStmt]::new(@((Lit 'Hello')), 1),
            [DiagnosticStmt]::new([DiagnosticLevel]::Note, @((Lit 'Server started.')), 2),
            [DiagnosticStmt]::new([DiagnosticLevel]::Warning, @((Lit 'Connection is slow.')), 3),
            [DiagnosticStmt]::new([DiagnosticLevel]::Problem, @((Lit 'Could not connect.')), 4)
        )))
    }
    finally {
        Set-OtterOutputWriter -Writer $null
        Set-OtterDiagnosticWriter -Writer $null
    }

    # "say" is what the program tells its user. Diagnostics are separate.
    Assert-Lines -Expected @('Hello') -Actual $said.ToArray()
    Assert-Lines -Expected @(
        'log|Server started.',
        'warn|Connection is slow.',
        'error|Could not connect.'
    ) -Actual $logged.ToArray()
}

Test-Otter 'a diagnostic joins its parts like say does' {
    $logged = [System.Collections.Generic.List[string]]::new()
    Set-OtterDiagnosticWriter -Writer { param($Level, $Text) $logged.Add($Text) }.GetNewClosure()
    try {
        Invoke-OtterProgram -Environment (New-OtterEnvironment) -Program ([ProgramNode]::new(@(
            [AssignStmt]::new('port', (Lit 8080.0), 1),
            [DiagnosticStmt]::new([DiagnosticLevel]::Note, @((Lit 'Listening on'), (Var 'port')), 2)
        )))
    }
    finally { Set-OtterDiagnosticWriter -Writer $null }

    Assert-Lines -Expected @('Listening on 8080') -Actual $logged.ToArray()
}


Set-Location $originalLocation
Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue

Complete-OtterTests
