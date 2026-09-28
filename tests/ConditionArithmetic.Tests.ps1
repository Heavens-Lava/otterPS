using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1
using module ..\src\Otter.Interpreter.psm1

# ConditionArithmetic.Tests.ps1
#
# Otter 1.0 decision D-1 (RC3): "Silent incorrect arithmetic in conditions is
# forbidden." `if x plus 1 is 5` must compare x+1 with 5, never parse as
# `x and (1 is 5)`. These tests expect CORRECT semantics and ship together
# with the parser change that provides them (PROPOSAL FOR CODEX REVIEW,
# Read-OtterConditionOperand in src/Otter.Parser.psm1). On the RC2 parser
# the plus/+ forms silently take the wrong branch and the other operators
# are rejected with "I expected the statement to end here".
#
# Kept separate from Parser.Tests.ps1 / Lexer.Tests.ps1, which belong to Codex.

. "$PSScriptRoot\TestHelpers.ps1"

$script:NL = "`n"

function Parse {
    param([string]$Source)
    return (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source ($Source + $script:NL)))
}

# Parse then run; returns the printed lines.
function Invoke-Source {
    param([string]$Source)

    $program = Parse $Source
    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($Text) $collected.Add($Text) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        Invoke-OtterProgram -Program $program -Environment (New-OtterEnvironment)
    }
    finally {
        Set-OtterOutputWriter -Writer $null
    }
    return , $collected.ToArray()
}

Write-Host ''
Write-Host 'Condition arithmetic (D-1)' -ForegroundColor Cyan


# =================================================================
# D-1: arithmetic in conditions is evaluated correctly
# =================================================================
#
# Each case: x is 4, y is 5, t is true, then `<condition>` -> "yes" / "no".
# On RC2 the plus/+ forms silently take the WRONG branch and the other
# operators are rejected with "I expected the statement to end here".

$script:ConditionCases = [ordered]@{
    'if x plus 1 is 5'                  = 'yes'
    'if x + 1 is 5'                     = 'yes'
    'if 5 is x plus 1'                  = 'yes'
    'if 5 is x + 1'                     = 'yes'
    'if x plus 1 is 6'                  = 'no'
    'if x minus 1 is 3'                 = 'yes'
    'if x - 1 is 3'                     = 'yes'
    'if x times 2 is 8'                 = 'yes'
    'if x * 2 is 8'                     = 'yes'
    'if x divided by 2 is 2'            = 'yes'
    'if x / 2 is 2'                     = 'yes'
    'if 8 is x times 2'                 = 'yes'
    'if 2 is x divided by 2'            = 'yes'
    'if 50 percent of x is 2'           = 'yes'
    'if x power 2 is 16'                = 'yes'
    'if x plus 1 is not 5'              = 'no'
    'if x plus 1 is greater than 4'     = 'yes'
    'if 6 is greater than x plus 1'     = 'yes'
    'if 5 is greater than x plus 1'     = 'no'
    'if x plus 1 is at least 5'         = 'yes'
    'if x plus 1 is at most 4'          = 'no'
    'if x plus 1 is less than 5'        = 'no'
    'if 2 plus 3 times 4 is 20'         = 'yes'
    'if x plus 1 is y and y is 5'       = 'yes'
    'if x is 4 and y minus 1 is x'      = 'yes'
    'if x plus 1 is 5 or y is 9'        = 'yes'
    'if not x plus 1 is 6'              = 'yes'
    'if t and y is 5'                   = 'yes'
    'if x is 4 and y is 5'              = 'yes'
    'if x is 3 and y is 5'              = 'no'
}

foreach ($condition in $script:ConditionCases.Keys) {
    $expected = $script:ConditionCases[$condition]
    Test-Otter "D-1: $condition  ->  $expected" {
        $source = @('x is 4', 'y is 5', 't is true', $condition, '    say "yes"', 'otherwise', '    say "no"') -join $script:NL
        $out = Invoke-Source $source
        Assert-Lines -Expected @($expected) -Actual $out
    }
}

Test-Otter 'D-1: while with arithmetic in its condition loops the right number of times' {
    $out = Invoke-Source (@('x is 0', 'while x plus 1 is less than 4', '    x is x plus 1', 'say x') -join $script:NL)
    Assert-Lines -Expected @('3') -Actual $out
}

Test-Otter 'D-1: otherwise if with arithmetic takes the right branch' {
    $out = Invoke-Source (@('x is 4', 'if x times 3 is 10', '    say "a"', 'otherwise if x times 3 is 12', '    say "b"', 'otherwise', '    say "c"') -join $script:NL)
    Assert-Lines -Expected @('b') -Actual $out
}

Test-Otter 'D-1: text concatenation with plus in a comparison' {
    $out = Invoke-Source (@('first is "Ot"', 'if first plus "ter" is "Otter"', '    say "joined"') -join $script:NL)
    Assert-Lines -Expected @('joined') -Actual $out
}

Test-Otter 'D-1: a declared function call inside arithmetic in a condition' {
    $out = Invoke-Source (@('to double n', '    return n times 2', 'if double 3 plus 1 is 7', '    say "seven"') -join $script:NL)
    Assert-Lines -Expected @('seven') -Actual $out
}

Test-Otter 'D-1: the AST is a comparison of a MathExpr, not a logical and' {
    $condition = (Parse "if x plus 1 is 5$($script:NL)    say 1").Statements[0].Branches[0].Condition
    Assert-True ($condition -is [ComparisonExpr]) "expected a ComparisonExpr, got $($condition.GetType().Name)"
    Assert-True ($condition.Left -is [MathExpr] -and $condition.Left.Op -eq [MathOp]::Add) 'expected x plus 1 on the left'
    $condition = (Parse "if 5 is x + 1$($script:NL)    say 1").Statements[0].Branches[0].Condition
    Assert-True ($condition -is [ComparisonExpr] -and $condition.Right -is [MathExpr]) 'expected x + 1 on the right'
}

Test-Otter 'D-1: the word `and` between conditions stays a logical and' {
    $condition = (Parse "if t and y is 3$($script:NL)    say 1").Statements[0].Branches[0].Condition
    Assert-True ($condition -is [LogicalExpr] -and $condition.Op -eq [LogicalOp]::And) "expected a LogicalExpr, got $($condition.GetType().Name)"
    Assert-True ($condition.Right -is [ComparisonExpr]) 'expected `y is 3` on the right of the and'
}

Test-Otter 'D-1: plus between two booleans in a condition is an error, never a silent logical and' {
    Assert-OtterFails -Body {
        Invoke-Source (@('t is true', 'u is true', 'if t plus u', '    say "silently true"') -join $script:NL)
    }
}

Test-Otter 'D-1: bare arithmetic is rejected instead of becoming a new truthiness form' {
    Assert-OtterFails -Body {
        Invoke-Source (@('if 1 plus 1', '    say "new meaning"') -join $script:NL)
    }
}

Test-Otter 'D-1: arithmetic is not accepted by string-match predicates' {
    Assert-OtterFails -Body {
        Invoke-Source (@('name is "Otter"', 'if name contains "O" plus "t"', '    say "new meaning"') -join $script:NL)
    }
}

Test-Otter 'D-1: arithmetic is not accepted by a state predicate' {
    Assert-OtterFails -Body {
        Parse (@('request is gone', 'if request plus 1 is completed', '    say "new meaning"') -join $script:NL)
    }
}

Test-Otter 'D-1: an ordinary state predicate keeps its established AST shape' {
    $condition = (Parse "if request is completed$($script:NL)    say 1").Statements[0].Branches[0].Condition
    Assert-True ($condition -is [HttpRequestIsStateExpr]) "expected an HttpRequestIsStateExpr, got $($condition.GetType().Name)"
}

Complete-OtterTests
