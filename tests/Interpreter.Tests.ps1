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


Complete-OtterTests
