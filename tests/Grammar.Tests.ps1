using module ..\Otter.Contract.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1

# Grammar.Tests.ps1
#
# Lexer and parser coverage for the D29-D32 backlog: JSON, random,
# diagnostics, and dates.
#
# These test the FRONT END only - that source text becomes the AST shape the
# frozen contract describes. What the interpreter then does with that shape is
# covered by Data.Tests.ps1 and Dates.Tests.ps1.
#
# Kept separate from Lexer.Tests.ps1 and Parser.Tests.ps1, which belong to
# Codex, so the two do not collide when parser ownership returns.

. "$PSScriptRoot\TestHelpers.ps1"

function Parse {
    param([string]$Source)
    return (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source ($Source + "`n")))
}

function FirstStatement {
    param([string]$Source)
    return (Parse $Source).Statements[0]
}

function Kinds {
    param([string]$Source)
    $names = foreach ($token in (ConvertTo-OtterTokens -Source ($Source + "`n"))) {
        if ($token.Kind -in @([TokenKind]::Newline, [TokenKind]::EndOfFile)) { continue }
        $token.Kind.ToString()
    }
    return ($names -join ' ')
}

Write-Host ''
Write-Host 'Grammar: JSON, random, diagnostics, dates' -ForegroundColor Cyan


# =================================================================
# D29 - JSON
# =================================================================

Test-Otter 'read json from a file' {
    $statement = FirstStatement 'read json from "settings.json" into settings'
    Assert-True ($statement -is [ReadJsonStmt]) 'expected a ReadJsonStmt'
    Assert-AreEqual -Expected 'settings' -Actual $statement.Target
}

Test-Otter 'convert to json' {
    $statement = FirstStatement 'convert user to json into text'
    Assert-True ($statement -is [ConvertToJsonStmt]) 'expected a ConvertToJsonStmt'
    Assert-AreEqual -Expected 'text' -Actual $statement.Target
}

Test-Otter 'convert from json' {
    $statement = FirstStatement 'convert text from json into user'
    Assert-True ($statement -is [ConvertFromJsonStmt]) 'expected a ConvertFromJsonStmt'
    Assert-AreEqual -Expected 'user' -Actual $statement.Target
}

Test-Otter 'plain read is still a file read, not JSON' {
    $statement = FirstStatement 'read "notes.txt" into notes'
    Assert-True ($statement -is [ReadFileStmt]) 'expected a ReadFileStmt'
}

Test-Otter 'json needs a destination' {
    Assert-OtterFails -Containing 'into' -Body { Parse 'read json from "a.json"' }
}


# =================================================================
# D30 - random
# =================================================================

Test-Otter 'random number from 1 to 10 into number' {
    $statement = FirstStatement 'random number from 1 to 10 into number'
    Assert-True ($statement -is [RandomNumberStmt]) 'expected a RandomNumberStmt'
    Assert-AreEqual -Expected 'number' -Actual $statement.Target
}

Test-Otter 'random item from games into game' {
    $statement = FirstStatement 'random item from games into game'
    Assert-True ($statement -is [RandomItemStmt]) 'expected a RandomItemStmt'
    Assert-AreEqual -Expected 'game' -Actual $statement.Target
}

Test-Otter 'random range endpoints may be expressions' {
    $statement = FirstStatement 'random number from low to high into pick'
    Assert-True ($statement.From -is [VariableExpr]) 'expected an expression for the low end'
    Assert-True ($statement.To -is [VariableExpr]) 'expected an expression for the high end'
}

Test-Otter 'item is NOT a reserved word' {
    # Reserving it would break the most natural loop variable there is.
    $statement = FirstStatement "for each item in games`n    say item"
    Assert-True ($statement -is [ForEachStmt]) 'expected a ForEachStmt'
    Assert-AreEqual -Expected 'item' -Actual $statement.VariableName
}

Test-Otter 'random says what it expected' {
    Assert-OtterFails -Containing 'number' -Body { Parse 'random thing from games into g' }
}


# =================================================================
# D31 - diagnostics
# =================================================================

Test-Otter 'log, warn and error each carry their own level' {
    foreach ($pair in @(@('log', 'Note'), @('warn', 'Warning'), @('error', 'Problem'))) {
        $statement = FirstStatement "$($pair[0]) `"something happened`""
        Assert-True ($statement -is [DiagnosticStmt]) "expected a DiagnosticStmt for $($pair[0])"
        Assert-AreEqual -Expected $pair[1] -Actual $statement.Level.ToString()
    }
}

Test-Otter 'a diagnostic is not a SayStmt' {
    # They must never collapse into the same node - the runtime routes them
    # to different writers.
    $statement = FirstStatement 'log "Server started."'
    Assert-False ($statement -is [SayStmt]) 'log must not parse as say'
}

Test-Otter 'a diagnostic takes several parts, like say' {
    $statement = FirstStatement 'log "Listening on" port'
    Assert-AreEqual -Expected 2 -Actual $statement.Parts.Count
}


# =================================================================
# D32 - dates
# =================================================================

Test-Otter 'today and now build a ClockExpr' {
    $today = FirstStatement 'date is today'
    Assert-True ($today.Value -is [ClockExpr]) 'expected a ClockExpr'
    Assert-AreEqual -Expected 'Today' -Actual $today.Value.Clock.ToString()

    $now = FirstStatement 'started is now'
    Assert-AreEqual -Expected 'Now' -Actual $now.Value.Clock.ToString()
}

Test-Otter 'year of date is ORDINARY property access (D32.2)' {
    $statement = FirstStatement 'say year of date'
    $part = $statement.Parts[0]
    Assert-True ($part -is [PropertyAccessExpr]) 'a date part must be a PropertyAccessExpr'
    Assert-False ($part -is [OfOperationExpr]) 'a date part must NOT be an OfOperationExpr'
    Assert-AreEqual -Expected 'year' -Actual $part.Property
}

Test-Otter 'year of book parses identically - the parser assumes nothing' {
    $statement = FirstStatement 'say year of book'
    $part = $statement.Parts[0]
    Assert-True ($part -is [PropertyAccessExpr]) 'expected a PropertyAccessExpr'
    Assert-AreEqual -Expected 'book' -Actual $part.Target.Name
}

Test-Otter 'add 7 days to date is a DateAdjustStmt, not an AddToStmt' {
    $statement = FirstStatement 'add 7 days to date'
    Assert-True ($statement -is [DateAdjustStmt]) 'expected a DateAdjustStmt'
    Assert-AreEqual -Expected 'Day' -Actual $statement.Unit.ToString()
    Assert-False $statement.IsRemoval 'add must not be a removal'
}

Test-Otter 'add 5 to score is still an AddToStmt (D12 untouched)' {
    $statement = FirstStatement 'add 5 to score'
    Assert-True ($statement -is [AddToStmt]) 'expected an AddToStmt'
    Assert-False ($statement -is [DateAdjustStmt]) 'no unit word means no date'
}

Test-Otter 'remove 1 month from date sets IsRemoval' {
    $statement = FirstStatement 'remove 1 month from date'
    Assert-True ($statement -is [DateAdjustStmt]) 'expected a DateAdjustStmt'
    Assert-AreEqual -Expected 'Month' -Actual $statement.Unit.ToString()
    Assert-True $statement.IsRemoval 'remove must be a removal'
}

Test-Otter 'remove 2 from score is still a RemoveFromStmt' {
    $statement = FirstStatement 'remove 2 from score'
    Assert-True ($statement -is [RemoveFromStmt]) 'expected a RemoveFromStmt'
}

Test-Otter 'singular and plural units produce the same unit' {
    foreach ($pair in @(@('1 day', 'Day'), @('7 days', 'Day'), @('1 year', 'Year'), @('2 years', 'Year'),
                        @('1 hour', 'Hour'), @('3 hours', 'Hour'), @('30 minutes', 'Minute'), @('5 seconds', 'Second'))) {
        $statement = FirstStatement "add $($pair[0]) to moment"
        Assert-AreEqual -Expected $pair[1] -Actual $statement.Unit.ToString() -Message $pair[0]
    }
}

Test-Otter 'format date as a pattern into text' {
    $statement = FirstStatement 'format date as "MM/dd/yyyy" into text'
    Assert-True ($statement -is [FormatDateStmt]) 'expected a FormatDateStmt'
    Assert-AreEqual -Expected 'text' -Actual $statement.Target
}

Test-Otter 'days between two dates make a number' {
    $statement = FirstStatement 'days between startDate and endDate make days'
    Assert-True ($statement -is [DateDifferenceStmt]) 'expected a DateDifferenceStmt'
    Assert-AreEqual -Expected 'Day' -Actual $statement.Unit.ToString()
    Assert-AreEqual -Expected 'days' -Actual $statement.Target
}

Test-Otter 'hours between and minutes between need no new node' {
    Assert-AreEqual -Expected 'Hour' -Actual (FirstStatement 'hours between start and finish make n').Unit.ToString()
    Assert-AreEqual -Expected 'Minute' -Actual (FirstStatement 'minutes between start and finish make n').Unit.ToString()
}


# =================================================================
# the contextual lexing that holds it all together
# =================================================================

Test-Otter 'a unit word after a number becomes a unit token' {
    Assert-AreEqual -Expected 'Add Number Day To Identifier' -Actual (Kinds 'add 7 days to date')
}

Test-Otter 'a unit word before "between" becomes a unit token' {
    Assert-AreEqual -Expected 'Day Between Identifier And Identifier Make Identifier' `
        -Actual (Kinds 'days between start and finish make n')
}

Test-Otter 'a unit word ANYWHERE ELSE stays an ordinary identifier' {
    # This is what keeps "year of book" working, and lets a program use
    # day, month or year as plain variable names.
    Assert-AreEqual -Expected 'Say Identifier Of Identifier' -Actual (Kinds 'say year of book')
    Assert-AreEqual -Expected 'Identifier Is Number' -Actual (Kinds 'day is 5')
    Assert-AreEqual -Expected 'Say Identifier' -Actual (Kinds 'say month')
}

Test-Otter 'a variable may still be called day, month or year' {
    $statement = FirstStatement 'year is 1984'
    Assert-True ($statement -is [AssignStmt]) 'expected an AssignStmt'
    Assert-AreEqual -Expected 'year' -Actual $statement.Target.Name
}


Complete-OtterTests
