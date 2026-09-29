using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Interpreter.psm1

# Collections.Tests.ps1
#
# Strings and collections (D24, D25, D26).
#
# The distinction these exist to protect (D24):
#
#     name of file        a genuine PROPERTY   -> PropertyAccessExpr
#     length of games     an OPERATION         -> OfOperationExpr
#
# Same surface syntax, different nodes. A list does not secretly carry a
# "length" property just to keep the grammar tidy.

. "$PSScriptRoot\TestHelpers.ps1"

function Lit { param($Value, [int]$Line = 1) [LiteralExpr]::new($Value, $Line) }
function Var { param([string]$Name, [int]$Line = 1) [VariableExpr]::new($Name, $Line) }
function PropOf { param([string]$P, [Node]$T, [int]$Line = 1) [PropertyAccessExpr]::new($P, $T, $Line) }
function OpOf { param([string]$Op, [Node]$Subject, [int]$Line = 1) [OfOperationExpr]::new([OfOperation]$Op, $Subject, $Line) }
function Gone { param([int]$Line = 1) [LiteralExpr]::new($null, $Line) }
function CompareEx { param([Node]$L, [string]$Op, [Node]$R, [int]$Line = 1) [ComparisonExpr]::new($L, [CompareOp]$Op, $R, $Line) }
function Games { param([int]$Line = 1) [ListDefStmt]::new('games', @((Lit 'Zelda'), (Lit 'Mario'), (Lit 'Pokemon')), $Line) }

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
Write-Host 'Strings and collections' -ForegroundColor Cyan


# =================================================================
# length / uppercase / lowercase / first / last
# =================================================================

Test-Otter 'length of text and length of a list' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('name', (Lit 'Jeff'), 1),
        (Games -Line 2),
        [SayStmt]::new(@((OpOf 'Length' (Var 'name'))), 3),
        [SayStmt]::new(@((OpOf 'Length' (Var 'games'))), 4)
    )
    Assert-Lines -Expected @('4', '3') -Actual $out
}

Test-Otter 'uppercase and lowercase' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('name', (Lit 'Jeff Macy'), 1),
        [SayStmt]::new(@((OpOf 'Uppercase' (Var 'name'))), 2),
        [SayStmt]::new(@((OpOf 'Lowercase' (Var 'name'))), 3)
    )
    Assert-Lines -Expected @('JEFF MACY', 'jeff macy') -Actual $out
}

Test-Otter 'first and last of a list' {
    $out = Invoke-TestProgram @(
        (Games),
        [SayStmt]::new(@((OpOf 'First' (Var 'games'))), 2),
        [SayStmt]::new(@((OpOf 'Last' (Var 'games'))), 3)
    )
    Assert-Lines -Expected @('Zelda', 'Pokemon') -Actual $out
}

Test-Otter 'first of an empty list is gone, not an error' {
    # This is why D22 exists - "if first of games is gone" must be askable.
    $out = Invoke-TestProgram @(
        [ListDefStmt]::new('games', @(), 1),
        [SayStmt]::new(@((OpOf 'First' (Var 'games'))), 2)
    )
    Assert-Lines -Expected @('gone') -Actual $out
}

Test-Otter 'length of a number explains itself' {
    Assert-OtterFails -Containing 'measure the length' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('score', (Lit 10.0), 1),
            [SayStmt]::new(@((OpOf 'Length' (Var 'score'))), 2)
        )
    }
}

Test-Otter 'an operation is NOT a property (D24)' {
    # "length of games" must not go looking for a property named length,
    # and a thing with no such property must still fail as a property.
    Assert-OtterFails -Containing 'no property called "length"' -Body {
        Invoke-TestProgram @(
            [ObjectDefStmt]::new('person', 'thing', @([AssignStmt]::new('name', (Lit 'Jeff'), 2)), 1),
            [SayStmt]::new(@((PropOf 'length' (Var 'person'))), 3)
        )
    }
}


# =================================================================
# text tests
# =================================================================

Test-Otter 'contains, starts with, ends with' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('name', (Lit 'Jeff Macy'), 1),
        [SayStmt]::new(@([ContainsExpr]::new((Var 'name'), (Lit 'Jeff'), 2)), 2),
        [SayStmt]::new(@([TextMatchExpr]::new((Var 'name'), [TextMatch]::StartsWith, (Lit 'J'), 3)), 3),
        [SayStmt]::new(@([TextMatchExpr]::new((Var 'name'), [TextMatch]::EndsWith, (Lit 'Macy'), 4)), 4),
        [SayStmt]::new(@([TextMatchExpr]::new((Var 'name'), [TextMatch]::StartsWith, (Lit 'z'), 5)), 5)
    )
    Assert-Lines -Expected @('true', 'true', 'true', 'false') -Actual $out
}

Test-Otter 'contains still works on a list' {
    $out = Invoke-TestProgram @(
        (Games),
        [SayStmt]::new(@([ContainsExpr]::new((Var 'games'), (Lit 'Mario'), 2)), 2)
    )
    Assert-Lines -Expected @('true') -Actual $out
}


# =================================================================
# mutation: sort / reverse / replace
# =================================================================

Test-Otter 'sort puts a list in order' {
    $out = Invoke-TestProgram @(
        (Games),
        [SortStmt]::new('games', 2),
        [SayStmt]::new(@((Var 'games')), 3)
    )
    Assert-Lines -Expected @('Mario, Pokemon, Zelda') -Actual $out
}

Test-Otter 'sort orders numbers as numbers, not as text' {
    # Sorted as text, 10 would come before 9.
    $out = Invoke-TestProgram @(
        [ListDefStmt]::new('scores', @((Lit 10.0), (Lit 9.0), (Lit 100.0), (Lit 2.0)), 1),
        [SortStmt]::new('scores', 2),
        [SayStmt]::new(@((Var 'scores')), 3)
    )
    Assert-Lines -Expected @('2, 9, 10, 100') -Actual $out
}

Test-Otter 'reverse turns a list around' {
    $out = Invoke-TestProgram @(
        (Games),
        [ReverseStmt]::new('games', 2),
        [SayStmt]::new(@((Var 'games')), 3)
    )
    Assert-Lines -Expected @('Pokemon, Mario, Zelda') -Actual $out
}

Test-Otter 'replace "Jeff" with "Jeffrey" in name' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('name', (Lit 'Jeff Macy'), 1),
        [ReplaceStmt]::new((Lit 'Jeff'), (Lit 'Jeffrey'), 'name', 2),
        [SayStmt]::new(@((Var 'name')), 3)
    )
    Assert-Lines -Expected @('Jeffrey Macy') -Actual $out
}

Test-Otter 'replace is plain text, not a pattern' {
    # A "." must mean a full stop, never "any character".
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('text', (Lit 'a.b.c'), 1),
        [ReplaceStmt]::new((Lit '.'), (Lit '-'), 'text', 2),
        [SayStmt]::new(@((Var 'text')), 3)
    )
    Assert-Lines -Expected @('a-b-c') -Actual $out
}

Test-Otter 'sorting something that is not a list explains itself' {
    Assert-OtterFails -Containing 'I can only sort a list' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('name', (Lit 'Jeff'), 1),
            [SortStmt]::new('name', 2)
        )
    }
}


# =================================================================
# split / join
# =================================================================

Test-Otter 'split sentence by " " into words' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('sentence', (Lit 'Readable like English'), 1),
        [SplitStmt]::new((Var 'sentence'), (Lit ' '), 'words', 2),
        [SayStmt]::new(@((OpOf 'Length' (Var 'words'))), 3),
        [SayStmt]::new(@((OpOf 'First' (Var 'words'))), 4)
    )
    Assert-Lines -Expected @('3', 'Readable') -Actual $out
}

Test-Otter 'join words with ", " into text' {
    $out = Invoke-TestProgram @(
        (Games),
        [JoinStmt]::new((Var 'games'), (Lit ' and '), 'text', 2),
        [SayStmt]::new(@((Var 'text')), 3)
    )
    Assert-Lines -Expected @('Zelda and Mario and Pokemon') -Actual $out
}

Test-Otter 'split then join round-trips' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('sentence', (Lit 'a,b,c'), 1),
        [SplitStmt]::new((Var 'sentence'), (Lit ','), 'parts', 2),
        [JoinStmt]::new((Var 'parts'), (Lit ','), 'back', 3),
        [SayStmt]::new(@((Var 'back')), 4)
    )
    Assert-Lines -Expected @('a,b,c') -Actual $out
}


# =================================================================
# find  (D26 - singular means one, or gone)
# =================================================================

Test-Otter 'find gives the first match' {
    $out = Invoke-TestProgram @(
        (Games),
        [FindStmt]::new('game', (Var 'games'),
            [TextMatchExpr]::new((Var 'game'), [TextMatch]::StartsWith, (Lit 'M'), 2),
            'result', 2),
        [SayStmt]::new(@((Var 'result')), 3)
    )
    Assert-Lines -Expected @('Mario') -Actual $out
}

Test-Otter 'find gives gone when nothing matches' {
    $out = Invoke-TestProgram @(
        (Games),
        [FindStmt]::new('game', (Var 'games'),
            [TextMatchExpr]::new((Var 'game'), [TextMatch]::StartsWith, (Lit 'Q'), 2),
            'result', 2),
        [IfStmt]::new(
            @([IfBranch]::new((CompareEx (Var 'result') 'Equal' (Gone)),
                @([SayStmt]::new(@((Lit 'No game found.')), 4)))),
            $null, 3)
    )
    Assert-Lines -Expected @('No game found.') -Actual $out
}

Test-Otter 'find searches objects by their properties' {
    # find file in files where extension of file is ".pdf" into result
    $out = Invoke-TestProgram @(
        [ObjectDefStmt]::new('a', 'file', @([AssignStmt]::new('extension', (Lit '.txt'), 1)), 1),
        [ObjectDefStmt]::new('b', 'file', @([AssignStmt]::new('extension', (Lit '.pdf'), 2)), 2),
        [ListDefStmt]::new('files', @((Var 'a'), (Var 'b')), 3),
        [FindStmt]::new('file', (Var 'files'),
            (CompareEx (PropOf 'extension' (Var 'file')) 'Equal' (Lit '.pdf')),
            'result', 4),
        [SayStmt]::new(@((PropOf 'extension' (Var 'result'))), 5)
    )
    Assert-Lines -Expected @('.pdf') -Actual $out
}

Test-Otter 'the find item name does not leak into the program' {
    # "file" is bound for the condition only, like a for-each variable.
    Assert-OtterFails -Containing 'could not find the variable' -Body {
        Invoke-TestProgram @(
            (Games),
            [FindStmt]::new('game', (Var 'games'),
                [TextMatchExpr]::new((Var 'game'), [TextMatch]::StartsWith, (Lit 'Z'), 2),
                'result', 2),
            [SayStmt]::new(@((Var 'game')), 3)
        )
    }
}

Test-Otter 'find without into binds the match to the item name itself' {
    # find game in games where game starts with "Z"   ->   say game
    $out = Invoke-TestProgram @(
        (Games),
        [FindStmt]::new('game', (Var 'games'),
            [TextMatchExpr]::new((Var 'game'), [TextMatch]::StartsWith, (Lit 'Z'), 2),
            'game', 2),
        [SayStmt]::new(@((Var 'game')), 3),
        [FindStmt]::new('game', (Var 'games'),
            [TextMatchExpr]::new((Var 'game'), [TextMatch]::StartsWith, (Lit 'Q'), 4),
            'game', 4),
        [SayStmt]::new(@((Var 'game')), 5)
    )
    Assert-Lines -Expected @('Zelda', 'gone') -Actual $out
}

Test-Otter 'searching something that is not a list explains itself' {
    Assert-OtterFails -Containing 'I can only search a list' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('name', (Lit 'Jeff'), 1),
            [FindStmt]::new('x', (Var 'name'), (Lit $true), 'result', 2)
        )
    }
}


Complete-OtterTests
