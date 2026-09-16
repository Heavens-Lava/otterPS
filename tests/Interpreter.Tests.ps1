using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Interpreter.psm1

# Interpreter.Tests.ps1
#
# These build AST nodes BY HAND rather than by parsing source text.
#
# That is the whole payoff of freezing the contract: the interpreter can be
# written and proved correct before the lexer and parser exist. When the front
# end lands, these tests keep working unchanged, and any disagreement between
# the two halves shows up as a parser test failing, not as a mystery.

. "$PSScriptRoot\TestHelpers.ps1"


# --- tiny builders, so the tests read like Otter ------------------

function Lit { param($Value, [int]$Line = 1) [LiteralExpr]::new($Value, $Line) }
function Var { param([string]$Name, [int]$Line = 1) [VariableExpr]::new($Name, $Line) }

function SaySt { param([Node[]]$Parts, [int]$Line = 1) [SayStmt]::new($Parts, $Line) }
function AssignSt { param([string]$Name, [Node]$Value, [int]$Line = 1) [AssignStmt]::new($Name, $Value, $Line) }
function MathEx { param([Node]$L, [string]$Op, [Node]$R, [int]$Line = 1) [MathExpr]::new($L, [MathOp]$Op, $R, $Line) }
function CompareEx { param([Node]$L, [string]$Op, [Node]$R, [int]$Line = 1) [ComparisonExpr]::new($L, [CompareOp]$Op, $R, $Line) }
function LogicEx { param([Node]$L, [string]$Op, [Node]$R, [int]$Line = 1) [LogicalExpr]::new($L, [LogicalOp]$Op, $R, $Line) }

# Runs statements and returns everything "say" printed, as an array of lines.
function Invoke-TestProgram {
    param([Node[]]$Statements)

    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($Text) $collected.Add($Text) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer

    try {
        $environment = New-OtterEnvironment
        Invoke-OtterProgram -Program ([ProgramNode]::new($Statements)) -Environment $environment
    }
    finally {
        Set-OtterOutputWriter -Writer $null
    }

    return , $collected.ToArray()
}


Write-Host ''
Write-Host 'Interpreter' -ForegroundColor Cyan


# =================================================================
# say
# =================================================================

Test-Otter 'say prints a literal' {
    $out = Invoke-TestProgram @( (SaySt @((Lit 'Hello'))) )
    Assert-Lines -Expected @('Hello') -Actual $out
}

Test-Otter 'say prints a variable' {
    $out = Invoke-TestProgram @(
        (AssignSt 'name' (Lit 'Jeff')),
        (SaySt @((Var 'name')))
    )
    Assert-Lines -Expected @('Jeff') -Actual $out
}

Test-Otter 'say joins literals and variables with one space' {
    # say name "is" age "years old."   ->   Jeff is 29 years old.
    $out = Invoke-TestProgram @(
        (AssignSt 'name' (Lit 'Jeff')),
        (AssignSt 'age' (Lit 29.0)),
        (SaySt @((Var 'name'), (Lit 'is'), (Var 'age'), (Lit 'years old.')))
    )
    Assert-Lines -Expected @('Jeff is 29 years old.') -Actual $out
}

Test-Otter 'say with no parts prints a blank line' {
    $out = Invoke-TestProgram @( (SaySt @()) )
    Assert-Lines -Expected @('') -Actual $out
}


# =================================================================
# values and formatting (D8)
# =================================================================

Test-Otter 'a whole number prints without decimals' {
    Assert-AreEqual -Expected '10' -Actual (Format-OtterValue -Value 10.0)
}

Test-Otter 'a fractional number keeps its decimals' {
    Assert-AreEqual -Expected '3.5' -Actual (Format-OtterValue -Value 3.5)
}

Test-Otter 'booleans print as true and false, not True and False' {
    Assert-AreEqual -Expected 'true' -Actual (Format-OtterValue -Value $true)
    Assert-AreEqual -Expected 'false' -Actual (Format-OtterValue -Value $false)
}

Test-Otter 'a list prints joined with commas' {
    $list = New-OtterList -Items @('Zelda', 'Mario')
    Assert-AreEqual -Expected 'Zelda, Mario' -Actual (Format-OtterValue -Value $list)
}

Test-Otter 'string assignment, number assignment, boolean assignment' {
    $out = Invoke-TestProgram @(
        (AssignSt 'text' (Lit 'hi')),
        (AssignSt 'number' (Lit 7.0)),
        (AssignSt 'flag' (Lit $true)),
        (SaySt @((Var 'text'), (Var 'number'), (Var 'flag')))
    )
    Assert-Lines -Expected @('hi 7 true') -Actual $out
}


# =================================================================
# math
# =================================================================

Test-Otter 'addition, subtraction, multiplication, division' {
    $out = Invoke-TestProgram @(
        (SaySt @((MathEx (Lit 5.0) 'Add' (Lit 5.0)))),
        (SaySt @((MathEx (Lit 10.0) 'Subtract' (Lit 5.0)))),
        (SaySt @((MathEx (Lit 10.0) 'Multiply' (Lit 5.0)))),
        (SaySt @((MathEx (Lit 10.0) 'Divide' (Lit 5.0))))
    )
    Assert-Lines -Expected @('10', '5', '50', '2') -Actual $out
}

Test-Otter 'number1 and number2 make total' {
    $out = Invoke-TestProgram @(
        (AssignSt 'number1' (Lit 5.0)),
        (AssignSt 'number2' (Lit 5.0)),
        ([MathIntoStmt]::new((MathEx (Var 'number1') 'Add' (Var 'number2')), 'total', 3)),
        (SaySt @((Var 'total')))
    )
    Assert-Lines -Expected @('10') -Actual $out
}

Test-Otter 'dividing by zero is a friendly Otter error' {
    Assert-OtterFails -Containing 'cannot divide by zero' -Body {
        Invoke-TestProgram @( (SaySt @((MathEx (Lit 1.0) 'Divide' (Lit 0.0)))) )
    }
}

Test-Otter 'D88: percent and power operators compute real values' {
    $out = Invoke-TestProgram @(
        (SaySt @((MathEx (Lit 20.0) 'Percent' (Lit 150.0)))),
        (SaySt @((MathEx (Lit 10.0) 'Percent' (Lit 50.0)))),
        (SaySt @((MathEx (Lit 2.0) 'Power' (Lit 10.0)))),
        (SaySt @((MathEx (Lit 5.0) 'Power' (Lit 2.0))))
    )
    Assert-Lines -Expected @('30', '5', '1024', '25') -Actual $out
}

Test-Otter 'D88: power participates in the SAME flat left-to-right chain as every other math operator' {
    # 2 power 3 plus 1 -> (2^3) + 1 = 9, NOT standard precedence (2^4=16) -
    # matching this language's already-frozen "no operator precedence,
    # strictly left to right" design (confirmed directly: `2 plus 3 times
    # 4` already evaluates as (2+3)*4=20, not 2+12=14).
    $out = Invoke-TestProgram @(
        (SaySt @((MathEx (MathEx (Lit 2.0) 'Power' (Lit 3.0)) 'Add' (Lit 1.0))))
    )
    Assert-Lines -Expected @('9') -Actual $out
}

Test-Otter 'D89: absolute value, square root, round, round up, and round down compute real values' {
    $out = Invoke-TestProgram @(
        (SaySt @([OfOperationExpr]::new([OfOperation]::AbsoluteValue, (Lit -7.0), 1))),
        (SaySt @([OfOperationExpr]::new([OfOperation]::SquareRoot, (Lit 81.0), 2))),
        (SaySt @([OfOperationExpr]::new([OfOperation]::Round, (Lit 4.5), 3))),
        (SaySt @([OfOperationExpr]::new([OfOperation]::Round, (Lit -4.5), 4))),
        (SaySt @([OfOperationExpr]::new([OfOperation]::RoundUp, (Lit 4.1), 5))),
        (SaySt @([OfOperationExpr]::new([OfOperation]::RoundDown, (Lit 4.9), 6)))
    )
    Assert-Lines -Expected @('7', '9', '5', '-5', '5', '4') -Actual $out
}

Test-Otter 'D89: square root of a negative number is a friendly Otter error' {
    Assert-OtterFails -Containing 'square root of a negative number' -Body {
        Invoke-TestProgram @(
            (SaySt @([OfOperationExpr]::new([OfOperation]::SquareRoot, (Lit -9.0), 1)))
        )
    }
}

Test-Otter 'D89: larger/smaller of two values picks the real min/max' {
    $out = Invoke-TestProgram @(
        (SaySt @([MinMaxExpr]::new($true, (Lit 3.0), (Lit 8.0), 1))),
        (SaySt @([MinMaxExpr]::new($false, (Lit 3.0), (Lit 8.0), 2)))
    )
    Assert-Lines -Expected @('8', '3') -Actual $out
}

Test-Otter 'D90: sine, cosine, and tangent take degrees, matching everyday expectations' {
    $out = Invoke-TestProgram @(
        (SaySt @([OfOperationExpr]::new([OfOperation]::Sine, (Lit 90.0), 1))),
        (SaySt @([OfOperationExpr]::new([OfOperation]::Cosine, (Lit 0.0), 2))),
        (SaySt @([OfOperationExpr]::new([OfOperation]::Tangent, (Lit 45.0), 3)))
    )
    Assert-Lines -Expected @('1', '1', '1') -Actual $out
}

Test-Otter 'D90: log (base 10) and natural log (base e) compute real values' {
    $out = Invoke-TestProgram @(
        (SaySt @([OfOperationExpr]::new([OfOperation]::LogTen, (Lit 100.0), 1))),
        (SaySt @([OfOperationExpr]::new([OfOperation]::NaturalLog, (Lit ([Math]::E)), 2)))
    )
    Assert-Lines -Expected @('2', '1') -Actual $out
}

Test-Otter 'D90: log of zero or a negative number is a friendly Otter error' {
    Assert-OtterFails -Containing "isn't positive" -Body {
        Invoke-TestProgram @( (SaySt @([OfOperationExpr]::new([OfOperation]::LogTen, (Lit 0.0), 1))) )
    }
}

Test-Otter 'D90: pi carries real double precision through ordinary math (parser-level "pi" literal is verified separately via the real CLI)' {
    $out = Invoke-TestProgram @(
        (SaySt @((MathEx (Lit ([Math]::PI)) 'Multiply' (Lit 2.0))))
    )
    $expected = ([Math]::PI * 2.0).ToString('0.##########', [System.Globalization.CultureInfo]::InvariantCulture)
    Assert-Lines -Expected @($expected) -Actual $out
}

Test-Otter 'doing maths on text explains itself' {
    Assert-OtterFails -Containing 'I expected a number' -Body {
        Invoke-TestProgram @(
            (AssignSt 'word' (Lit 'banana')),
            (SaySt @((MathEx (Var 'word') 'Add' (Lit 1.0))))
        )
    }
}


# =================================================================
# add to / remove from  (D12 - dispatch on runtime type)
# =================================================================

Test-Otter 'add to and remove from a number' {
    # score is 10 / add 5 to score / remove 2 from score  ->  13
    $out = Invoke-TestProgram @(
        (AssignSt 'score' (Lit 10.0)),
        ([AddToStmt]::new((Lit 5.0), 'score', 2)),
        ([RemoveFromStmt]::new((Lit 2.0), 'score', 3)),
        (SaySt @((Var 'score')))
    )
    Assert-Lines -Expected @('13') -Actual $out
}

Test-Otter 'add to and remove from a list' {
    $out = Invoke-TestProgram @(
        ([ListDefStmt]::new('games', @((Lit 'Zelda'), (Lit 'Mario')), 1)),
        ([AddToStmt]::new((Lit 'Pokemon'), 'games', 2)),
        ([RemoveFromStmt]::new((Lit 'Mario'), 'games', 3)),
        (SaySt @((Var 'games')))
    )
    Assert-Lines -Expected @('Zelda, Pokemon') -Actual $out
}

Test-Otter 'remove from a list of things removes the RIGHT one, by identity - not by chance' {
    # Found during Contact Manager dogfooding: Test-OtterEqual's fallback
    # case cast both sides to [string] for comparison. A `thing` has no
    # ToString() override, so every thing prints as the bare class name
    # ("OtterObject") - meaning any two things compared EQUAL to each
    # other, regardless of their actual properties. `remove x from
    # things` always matched and removed the FIRST item in the list
    # instead of the one actually referenced, silently - no error, just
    # the wrong result. Two things with DIFFERENT names here so a
    # string-cast-equality regression would be caught immediately: this
    # test removes the SECOND person and asserts the FIRST one survives.
    $out = Invoke-TestProgram @(
        ([ObjectDefStmt]::new('alice', 'thing', @([AssignStmt]::new('name', (Lit 'Alice'), 1)), 1)),
        ([ObjectDefStmt]::new('bob', 'thing', @([AssignStmt]::new('name', (Lit 'Bob'), 2)), 2)),
        ([ListDefStmt]::new('people', @((Var 'alice'), (Var 'bob')), 3)),
        ([RemoveFromStmt]::new((Var 'bob'), 'people', 4)),
        (SaySt @([OfOperationExpr]::new([OfOperation]::Length, (Var 'people'), 5))),
        (SaySt @([PropertyAccessExpr]::new('name', [OfOperationExpr]::new([OfOperation]::First, (Var 'people'), 6), 6)))
    )
    Assert-Lines -Expected @('1', 'Alice') -Actual $out
}

Test-Otter 'two separately-built things with identical-looking properties are still two different things' {
    # The fix is identity equality, not structural/name-based equality -
    # proven, not just asserted: both things share the SAME name here, so
    # a structural "fix" comparing by name would not be able to tell them
    # apart either. A distinct "id" field (irrelevant to the bug itself)
    # is used only to observe, after removal, that the SURVIVOR is
    # specifically personA - confirming removal targeted personB by
    # reference, not "whichever one looked like a match."
    $out = Invoke-TestProgram @(
        ([ObjectDefStmt]::new('personA', 'thing', @(
            [AssignStmt]::new('name', (Lit 'Same'), 1),
            [AssignStmt]::new('id', (Lit 1.0), 1)
        ), 1)),
        ([ObjectDefStmt]::new('personB', 'thing', @(
            [AssignStmt]::new('name', (Lit 'Same'), 2),
            [AssignStmt]::new('id', (Lit 2.0), 2)
        ), 2)),
        ([ListDefStmt]::new('people', @((Var 'personA'), (Var 'personB')), 3)),
        ([RemoveFromStmt]::new((Var 'personB'), 'people', 4)),
        (SaySt @([OfOperationExpr]::new([OfOperation]::Length, (Var 'people'), 5))),
        (SaySt @([PropertyAccessExpr]::new('id', [OfOperationExpr]::new([OfOperation]::First, (Var 'people'), 6), 6)))
    )
    Assert-Lines -Expected @('1', '1') -Actual $out
}

Test-Otter 'adding to a variable that does not exist names the variable' {
    Assert-OtterFails -Containing 'score' -Body {
        Invoke-TestProgram @( ([AddToStmt]::new((Lit 1.0), 'score', 1)) )
    }
}


# =================================================================
# conditions
# =================================================================

Test-Otter 'if runs its body when the condition holds' {
    $out = Invoke-TestProgram @(
        (AssignSt 'age' (Lit 29.0)),
        ([IfStmt]::new(
            @([IfBranch]::new((CompareEx (Var 'age') 'AtLeast' (Lit 18.0)), @((SaySt @((Lit 'You are an adult.')))))),
            $null, 2)),
        (SaySt @((Lit 'Finished.')))
    )
    Assert-Lines -Expected @('You are an adult.', 'Finished.') -Actual $out
}

Test-Otter 'if skips its body when the condition fails' {
    $out = Invoke-TestProgram @(
        (AssignSt 'age' (Lit 12.0)),
        ([IfStmt]::new(
            @([IfBranch]::new((CompareEx (Var 'age') 'AtLeast' (Lit 18.0)), @((SaySt @((Lit 'adult')))))),
            $null, 2)),
        (SaySt @((Lit 'Finished.')))
    )
    Assert-Lines -Expected @('Finished.') -Actual $out
}

Test-Otter 'otherwise runs when the if does not' {
    $out = Invoke-TestProgram @(
        (AssignSt 'age' (Lit 12.0)),
        ([IfStmt]::new(
            @([IfBranch]::new((CompareEx (Var 'age') 'AtLeast' (Lit 18.0)), @((SaySt @((Lit 'Adult')))))),
            @((SaySt @((Lit 'Minor')))), 2))
    )
    Assert-Lines -Expected @('Minor') -Actual $out
}

Test-Otter 'otherwise if picks the first matching arm' {
    # score 85 -> B
    $out = Invoke-TestProgram @(
        (AssignSt 'score' (Lit 85.0)),
        ([IfStmt]::new(
            @(
                [IfBranch]::new((CompareEx (Var 'score') 'AtLeast' (Lit 90.0)), @((SaySt @((Lit 'A'))))),
                [IfBranch]::new((CompareEx (Var 'score') 'AtLeast' (Lit 80.0)), @((SaySt @((Lit 'B'))))),
                [IfBranch]::new((CompareEx (Var 'score') 'AtLeast' (Lit 70.0)), @((SaySt @((Lit 'C')))))
            ),
            @((SaySt @((Lit 'F')))), 2))
    )
    Assert-Lines -Expected @('B') -Actual $out
}

Test-Otter 'all six comparisons behave' {
    $out = Invoke-TestProgram @(
        (SaySt @((CompareEx (Lit 5.0) 'Equal' (Lit 5.0)))),
        (SaySt @((CompareEx (Lit 5.0) 'NotEqual' (Lit 4.0)))),
        (SaySt @((CompareEx (Lit 5.0) 'AtLeast' (Lit 5.0)))),
        (SaySt @((CompareEx (Lit 5.0) 'AtMost' (Lit 4.0)))),
        (SaySt @((CompareEx (Lit 5.0) 'GreaterThan' (Lit 4.0)))),
        (SaySt @((CompareEx (Lit 5.0) 'LessThan' (Lit 4.0))))
    )
    Assert-Lines -Expected @('true', 'true', 'true', 'false', 'true', 'false') -Actual $out
}

Test-Otter 'a number typed as text still compares as a number (D6)' {
    # This is what makes "ask" work: age may be the string "29".
    $out = Invoke-TestProgram @(
        (AssignSt 'age' (Lit '29')),
        (SaySt @((CompareEx (Var 'age') 'AtLeast' (Lit 18.0))))
    )
    Assert-Lines -Expected @('true') -Actual $out
}

Test-Otter 'nested ifs follow their own branches' {
    $out = Invoke-TestProgram @(
        (AssignSt 'loggedIn' (Lit $true)),
        (AssignSt 'admin' (Lit $true)),
        ([IfStmt]::new(
            @([IfBranch]::new((Var 'loggedIn'), @(
                (SaySt @((Lit 'Welcome!'))),
                ([IfStmt]::new(
                    @([IfBranch]::new((Var 'admin'), @((SaySt @((Lit 'Administrator controls enabled.')))))),
                    $null, 4)),
                (SaySt @((Lit 'Login successful.')))
            ))),
            $null, 3)),
        (SaySt @((Lit 'Program finished.')))
    )
    Assert-Lines -Expected @(
        'Welcome!', 'Administrator controls enabled.', 'Login successful.', 'Program finished.'
    ) -Actual $out
}


# =================================================================
# and / or / not  (D11)
# =================================================================

Test-Otter 'and, or and not' {
    $out = Invoke-TestProgram @(
        (SaySt @((LogicEx (Lit $true) 'And' (Lit $false)))),
        (SaySt @((LogicEx (Lit $true) 'Or' (Lit $false)))),
        (SaySt @(([NotExpr]::new((Lit $false), 3))))
    )
    Assert-Lines -Expected @('false', 'true', 'true') -Actual $out
}

Test-Otter 'and short-circuits, so the right side is never reached' {
    # If "and" evaluated both sides, the undefined variable would explode.
    $out = Invoke-TestProgram @(
        (SaySt @((LogicEx (Lit $false) 'And' (Var 'neverDefined'))))
    )
    Assert-Lines -Expected @('false') -Actual $out
}

Test-Otter 'or short-circuits too' {
    $out = Invoke-TestProgram @(
        (SaySt @((LogicEx (Lit $true) 'Or' (Var 'neverDefined'))))
    )
    Assert-Lines -Expected @('true') -Actual $out
}


# =================================================================
# truthiness (D9)
# =================================================================

Test-Otter 'truthiness of each kind of value' {
    Assert-True (Test-OtterTruthy -Value $true)
    Assert-False (Test-OtterTruthy -Value $false)
    Assert-False (Test-OtterTruthy -Value 0.0)
    Assert-True (Test-OtterTruthy -Value 1.0)
    Assert-False (Test-OtterTruthy -Value '')
    Assert-True (Test-OtterTruthy -Value 'x')
    Assert-False (Test-OtterTruthy -Value (New-OtterList))
    Assert-True (Test-OtterTruthy -Value (New-OtterList -Items @('x')))
    Assert-False (Test-OtterTruthy -Value $null)
}


# =================================================================
# loops
# =================================================================

Test-Otter 'repeat runs the body that many times' {
    $out = Invoke-TestProgram @(
        ([RepeatStmt]::new((Lit 3.0), @((SaySt @((Lit 'Hello')))), 1))
    )
    Assert-Lines -Expected @('Hello', 'Hello', 'Hello') -Actual $out
}

Test-Otter 'while loops until the condition fails' {
    # number is 1 / while number is less than 5 / say number / add 1 to number
    $out = Invoke-TestProgram @(
        (AssignSt 'number' (Lit 1.0)),
        ([WhileStmt]::new(
            (CompareEx (Var 'number') 'LessThan' (Lit 5.0)),
            @(
                (SaySt @((Var 'number'))),
                ([AddToStmt]::new((Lit 1.0), 'number', 4))
            ), 2))
    )
    Assert-Lines -Expected @('1', '2', '3', '4') -Actual $out
}

Test-Otter 'count from 1 to 5 includes both ends (D5)' {
    $out = Invoke-TestProgram @(
        ([CountStmt]::new('number', (Lit 1.0), (Lit 5.0), @((SaySt @((Var 'number')))), 1))
    )
    Assert-Lines -Expected @('1', '2', '3', '4', '5') -Actual $out
}

Test-Otter 'count works with expressions, not just literals' {
    $out = Invoke-TestProgram @(
        (AssignSt 'start' (Lit 3.0)),
        (AssignSt 'finish' (Lit 5.0)),
        ([CountStmt]::new('n', (Var 'start'), (Var 'finish'), @((SaySt @((Var 'n')))), 3))
    )
    Assert-Lines -Expected @('3', '4', '5') -Actual $out
}

Test-Otter 'for each walks a list' {
    $out = Invoke-TestProgram @(
        ([ListDefStmt]::new('games', @((Lit 'Zelda'), (Lit 'Mario'), (Lit 'Pokemon')), 1)),
        ([ForEachStmt]::new('game', (Var 'games'), @((SaySt @((Lit 'I like'), (Var 'game')))), 2))
    )
    Assert-Lines -Expected @('I like Zelda', 'I like Mario', 'I like Pokemon') -Actual $out
}

Test-Otter 'for each over something that is not a list explains itself' {
    Assert-OtterFails -Containing 'list' -Body {
        Invoke-TestProgram @(
            (AssignSt 'notAList' (Lit 5.0)),
            ([ForEachStmt]::new('x', (Var 'notAList'), @(), 2))
        )
    }
}


# =================================================================
# lists (D13)
# =================================================================

Test-Otter 'an empty list is empty' {
    $out = Invoke-TestProgram @(
        ([ListDefStmt]::new('games', @(), 1)),
        (SaySt @(([ContainsExpr]::new((Var 'games'), (Lit 'Zelda'), 2))))
    )
    Assert-Lines -Expected @('false') -Actual $out
}

Test-Otter 'contains finds an item' {
    $out = Invoke-TestProgram @(
        ([ListDefStmt]::new('games', @((Lit 'Zelda'), (Lit 'Mario')), 1)),
        (SaySt @(([ContainsExpr]::new((Var 'games'), (Lit 'Zelda'), 2)))),
        (SaySt @(([ContainsExpr]::new((Var 'games'), (Lit 'Halo'), 3))))
    )
    Assert-Lines -Expected @('true', 'false') -Actual $out
}


# =================================================================
# functions and scope
# =================================================================

Test-Otter 'a function runs with its parameter bound' {
    $out = Invoke-TestProgram @(
        ([FunctionDefStmt]::new('greet', @('name'), @((SaySt @((Lit 'Hello'), (Var 'name')))), 1)),
        ([CallStmt]::new([CallExpr]::new('greet', @((Lit 'Jeff')), 3), $null, 3))
    )
    Assert-Lines -Expected @('Hello Jeff') -Actual $out
}

Test-Otter 'a parameter does not overwrite the global of the same name' {
    # Straight from the build brief. This is THE scoping test.
    $out = Invoke-TestProgram @(
        (AssignSt 'name' (Lit 'Outside')),
        ([FunctionDefStmt]::new('greet', @('name'), @((SaySt @((Lit 'Hello'), (Var 'name')))), 2)),
        ([CallStmt]::new([CallExpr]::new('greet', @((Lit 'Jeff')), 4), $null, 4)),
        (SaySt @((Var 'name')))
    )
    Assert-Lines -Expected @('Hello Jeff', 'Outside') -Actual $out
}

Test-Otter 'a function returns a value' {
    # to double number / number times 2 make answer / return answer
    $out = Invoke-TestProgram @(
        ([FunctionDefStmt]::new('double', @('number'), @(
            ([MathIntoStmt]::new((MathEx (Var 'number') 'Multiply' (Lit 2.0)), 'answer', 2)),
            ([ReturnStmt]::new((Var 'answer'), 3))
        ), 1)),
        ([CallStmt]::new([CallExpr]::new('double', @((Lit 5.0)), 5), 'result', 5)),
        (SaySt @((Var 'result')))
    )
    Assert-Lines -Expected @('10') -Actual $out
}

Test-Otter 'return escapes from inside a loop' {
    $out = Invoke-TestProgram @(
        ([FunctionDefStmt]::new('firstOnly', @(), @(
            ([CountStmt]::new('n', (Lit 1.0), (Lit 10.0), @(
                ([ReturnStmt]::new((Var 'n'), 3))
            ), 2))
        ), 1)),
        ([CallStmt]::new([CallExpr]::new('firstOnly', @(), 5), 'answer', 5)),
        (SaySt @((Var 'answer')))
    )
    Assert-Lines -Expected @('1') -Actual $out
}

Test-Otter 'return with no value at the top level is a clean error, not a crash (D37)' {
    # "stop" builds exactly this shape: ReturnStmt with a null Value. Used
    # outside anything callable - matching D37's "process" scope case -
    # this must NOT unwind uncaught and be reported as "a bug in Otter".
    # It is not a bug: the program just tried to stop something that was
    # never running.
    Assert-OtterFails -Containing 'nothing here to stop' -Body {
        Invoke-TestProgram @(
            (SaySt @((Lit 'before'))),
            ([ReturnStmt]::new($null, 2))
        )
    }
}

Test-Otter 'a value-carrying return at the top level is the same clean error' {
    # The fix is general, not stop-specific: ANY OtterReturnSignal reaching
    # the top of the program - not just a bare one - gets the same message.
    Assert-OtterFails -Containing 'nothing here to stop' -Body {
        Invoke-TestProgram @( ([ReturnStmt]::new((Lit 5.0), 1)) )
    }
}

Test-Otter 'calling with the wrong number of values says how many it wanted' {
    Assert-OtterFails -Containing 'needs 1 value but was given 2' -Body {
        Invoke-TestProgram @(
            ([FunctionDefStmt]::new('greet', @('name'), @(), 1)),
            ([CallStmt]::new([CallExpr]::new('greet', @((Lit 'a'), (Lit 'b')), 2), $null, 2))
        )
    }
}


# =================================================================
# errors (D14)
# =================================================================

Test-Otter 'an undefined variable is an error, not silently false' {
    Assert-OtterFails -Containing 'could not find the variable' -Body {
        Invoke-TestProgram @( (SaySt @((Var 'score'))) )
    }
}

Test-Otter 'a runtime error quotes the offending source line' {
    $environment = New-OtterEnvironment
    $source = @('say "ok"', 'say score')
    $program = [ProgramNode]::new(@( (SaySt @((Var 'score')) 2) ))

    try {
        Invoke-OtterProgram -Program $program -Environment $environment -SourceLines $source
        throw 'expected this to fail'
    }
    catch {
        $otterError = $_.Exception
        Assert-True ($otterError -is [OtterError]) 'expected an OtterError'
        $detailed = $otterError.FormatDetailed()
        Assert-True ($detailed -like '*Otter Runtime Error*') 'expected the heading'
        Assert-True ($detailed -like '*score*') 'expected the variable name'
    }
}


# =================================================================
# ask coercion (D6)
# =================================================================

Test-Otter 'ask turns 29 into a number and true into a boolean' {
    $number = ConvertFrom-OtterInput -Text '29'
    Assert-True ($number -is [double]) 'expected a number'
    Assert-AreEqual -Expected '29' -Actual (Format-OtterValue -Value $number)

    $flag = ConvertFrom-OtterInput -Text 'true'
    Assert-True ($flag -is [bool]) 'expected a boolean'

    $text = ConvertFrom-OtterInput -Text 'Jeff'
    Assert-True ($text -is [string]) 'expected text'
    Assert-AreEqual -Expected 'Jeff' -Actual $text
}


# =================================================================
# case sensitivity (D10)
# =================================================================

Test-Otter 'loggedIn and loggedin are different variables' {
    Assert-OtterFails -Containing 'could not find the variable' -Body {
        Invoke-TestProgram @(
            (AssignSt 'loggedIn' (Lit $true)),
            (SaySt @((Var 'loggedin')))
        )
    }
}


# =================================================================
# the brief's acceptance program
# =================================================================

Test-Otter 'the acceptance program from the brief produces the expected output' {
    $out = Invoke-TestProgram @(
        (SaySt @((Lit 'Welcome to Otter!'))),
        (AssignSt 'name' (Lit 'Jeff')),
        (AssignSt 'age' (Lit 29.0)),
        (SaySt @((Lit 'Hello'), (Var 'name'))),
        (AssignSt 'number1' (Lit 5.0)),
        (AssignSt 'number2' (Lit 10.0)),
        ([MathIntoStmt]::new((MathEx (Var 'number1') 'Add' (Var 'number2')), 'total', 7)),
        (SaySt @((Var 'number1'), (Lit '+'), (Var 'number2'), (Lit '='), (Var 'total'))),
        ([IfStmt]::new(
            @([IfBranch]::new(
                (CompareEx (Var 'age') 'AtLeast' (Lit 18.0)),
                @((SaySt @((Var 'name'), (Lit 'is an adult.')))))),
            @((SaySt @((Var 'name'), (Lit 'is under 18.')))), 9)),
        (SaySt @((Lit 'Counting...'))),
        ([CountStmt]::new('number', (Lit 1.0), (Lit 5.0), @((SaySt @((Var 'number')))), 13)),
        (SaySt @((Lit 'Finished!')))
    )

    Assert-Lines -Expected @(
        'Welcome to Otter!',
        'Hello Jeff',
        '5 + 10 = 15',
        'Jeff is an adult.',
        'Counting...',
        '1', '2', '3', '4', '5',
        'Finished!'
    ) -Actual $out
}


# =================================================================
# D56 - reactive state IN, experimental front-end surface OUT
# =================================================================

Test-Otter 'a watcher fires only on an actual change, using Otter equality' {
    # v1 audit + D56: state->watch previously notified on every assignment,
    # even reassigning the current value. Fixed in OtterEnvironment.Set to
    # check Test-OtterEqual first. Exact sequence Jeff specified:
    # 0->0 no fire, 0->1 fire, 1->1 no fire, 1->2 fire.
    $out = Invoke-TestProgram @(
        ([StateDefStmt]::new('count', (Lit 0.0), 1)),
        ([WatchStmt]::new('count', @((SaySt @((Var 'count')))), 2)),
        (AssignSt 'count' (Lit 0.0)),
        (AssignSt 'count' (Lit 1.0)),
        (AssignSt 'count' (Lit 1.0)),
        (AssignSt 'count' (Lit 2.0))
    )
    Assert-Lines -Expected @('1', '2') -Actual $out
}

Test-Otter 'multiple derived values independently track the same state' {
    $out = Invoke-TestProgram @(
        ([StateDefStmt]::new('count', (Lit 2.0), 1)),
        ([DeriveDefStmt]::new('doubled', ([MathExpr]::new((Var 'count'), [MathOp]::Multiply, (Lit 2.0), 2)), 2)),
        ([DeriveDefStmt]::new('tripled', ([MathExpr]::new((Var 'count'), [MathOp]::Multiply, (Lit 3.0), 3)), 3)),
        (SaySt @((Var 'doubled'))),
        (SaySt @((Var 'tripled'))),
        (AssignSt 'count' (Lit 5.0)),
        (SaySt @((Var 'doubled'))),
        (SaySt @((Var 'tripled')))
    )
    Assert-Lines -Expected @('4', '6', '10', '15') -Actual $out
}

Test-Otter 'memo, shared, use, await, on start/close, and UI action/event/animation are explicit v1 errors, never silent no-ops' {
    # Each of these previously ran without error and did NOTHING - found
    # during the v1 runtime audit. A silently-successful unsupported
    # feature is worse than one that says so (D56).
    Assert-OtterFails -Containing "'memo' is not supported in Otter 1.0" -Body {
        Invoke-TestProgram @( ([MemoDefStmt]::new('total', @(), 1)) )
    }
    Assert-OtterFails -Containing "'shared' is not supported in Otter 1.0" -Body {
        Invoke-TestProgram @( ([SharedStateStmt]::new('theme', (Lit 'dark'), 1)) )
    }
    Assert-OtterFails -Containing "'use' is not supported in Otter 1.0" -Body {
        Invoke-TestProgram @( ([UseModuleStmt]::new('ui', 1)) )
    }
    Assert-OtterFails -Containing "'on start' is not supported in Otter 1.0" -Body {
        Invoke-TestProgram @( ([LifecycleStmt]::new('start', @(), 1)) )
    }
    Assert-OtterFails -Containing "'on close' is not supported in Otter 1.0" -Body {
        Invoke-TestProgram @( ([LifecycleStmt]::new('close', @(), 1)) )
    }
    Assert-OtterFails -Containing "'hide' is not supported in Otter 1.0" -Body {
        Invoke-TestProgram @( ([UiActionStmt]::new('hide', (Var 'sidebar'), 1)) )
    }
    Assert-OtterFails -Containing 'UI event blocks are not supported in Otter 1.0' -Body {
        Invoke-TestProgram @( ([UiEventStmt]::new('click', @(), 1)) )
    }
    Assert-OtterFails -Containing 'UI animation is not supported in Otter 1.0' -Body {
        Invoke-TestProgram @( ([UiAnimationBlock]::new('enter', @(), 300.0, 'ease-out', 1)) )
    }
    Assert-OtterFails -Containing "'await' is not supported in Otter 1.0" -Body {
        Invoke-TestProgram @( (AssignSt 'x' ([AwaitExpr]::new((Lit 1.0), 1))) )
    }
}

Complete-OtterTests
