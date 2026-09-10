using module ..\Otter.Contract.psm1

# Milestone 1 parser: say, assignment, and an if block with comparison.

function Initialize-OtterParser {
    param([Token[]]$Tokens)
    $script:Tokens = $Tokens
    $script:Position = 0
    $script:KnownFunctions = @{}
}

function Get-OtterCurrentToken { return $script:Tokens[$script:Position] }
function Test-OtterTokenKind { param([TokenKind]$Kind) return (Get-OtterCurrentToken).Kind -eq $Kind }
function Read-OtterToken { $token = Get-OtterCurrentToken; $script:Position++; return $token }
function Get-OtterSourceLine {
    param([int]$Line)
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($token in $script:Tokens) {
        if ($token.Line -ne $Line) { continue }
        if ($token.Kind -in @([TokenKind]::Indent, [TokenKind]::Dedent, [TokenKind]::Newline, [TokenKind]::EndOfFile)) { continue }
        $parts.Add($token.Text)
    }
    return $parts -join ' '
}
function New-OtterParserError {
    param([string]$Message, [Token]$Token, [string]$Suggestion = $null)
    return [OtterError]::new($Message, $Token.Line, 'parser', $Token.Column, (Get-OtterSourceLine $Token.Line), $Suggestion)
}
function Assert-OtterTokenKind {
    param([TokenKind]$Kind, [string]$Message)
    $token = Get-OtterCurrentToken
    if ($token.Kind -ne $Kind) { throw (New-OtterParserError "$Message I found '$($token.Text)' instead." $token 'Check the expected word and try again.') }
    return Read-OtterToken
}
function Skip-OtterNewlines { while (Test-OtterTokenKind ([TokenKind]::Newline)) { [void](Read-OtterToken) } }

function Read-OtterValue {
    $token = Get-OtterCurrentToken
    switch ($token.Kind) {
        ([TokenKind]::String) { [void](Read-OtterToken); return [LiteralExpr]::new($token.Value, $token.Line) }
        ([TokenKind]::Number) { [void](Read-OtterToken); return [LiteralExpr]::new($token.Value, $token.Line) }
        ([TokenKind]::True) { [void](Read-OtterToken); return [LiteralExpr]::new($true, $token.Line) }
        ([TokenKind]::False) { [void](Read-OtterToken); return [LiteralExpr]::new($false, $token.Line) }
        ([TokenKind]::Identifier) { [void](Read-OtterToken); return [VariableExpr]::new($token.Text, $token.Line) }
        default { throw (New-OtterParserError 'I expected a value here.' $token 'Add a text value, number, true, false, or variable name.') }
    }
}

function Read-OtterMathExpression {
    $left = Read-OtterValue
    while ((Test-OtterTokenKind ([TokenKind]::And)) -or
           (Test-OtterTokenKind ([TokenKind]::Minus)) -or
           (Test-OtterTokenKind ([TokenKind]::Times)) -or
           (Test-OtterTokenKind ([TokenKind]::DividedBy))) {
        $operator = Read-OtterToken
        $right = Read-OtterValue
        $mathOp = switch ($operator.Kind) {
            ([TokenKind]::And) { [MathOp]::Add }
            ([TokenKind]::Minus) { [MathOp]::Subtract }
            ([TokenKind]::Times) { [MathOp]::Multiply }
            ([TokenKind]::DividedBy) { [MathOp]::Divide }
        }
        $left = [MathExpr]::new($left, $mathOp, $right, $operator.Line)
    }
    return $left
}

function Read-OtterConditionPrimary {
    if (Test-OtterTokenKind ([TokenKind]::Not)) {
        $token = Read-OtterToken
        return [NotExpr]::new((Read-OtterConditionPrimary), $token.Line)
    }
    $left = Read-OtterValue
    if (Test-OtterTokenKind ([TokenKind]::Contains)) {
        $operator = Read-OtterToken
        return [ContainsExpr]::new($left, (Read-OtterValue), $operator.Line)
    }
    $operator = Get-OtterCurrentToken
    $comparison = switch ($operator.Kind) {
        ([TokenKind]::Is) { [CompareOp]::Equal }
        ([TokenKind]::IsNot) { [CompareOp]::NotEqual }
        ([TokenKind]::IsAtLeast) { [CompareOp]::AtLeast }
        ([TokenKind]::IsAtMost) { [CompareOp]::AtMost }
        ([TokenKind]::IsGreaterThan) { [CompareOp]::GreaterThan }
        ([TokenKind]::IsLessThan) { [CompareOp]::LessThan }
        default { $null }
    }
    if ($null -eq $comparison) { return $left }
    [void](Read-OtterToken)
    return [ComparisonExpr]::new($left, $comparison, (Read-OtterValue), $operator.Line)
}

function Read-OtterAndCondition {
    $left = Read-OtterConditionPrimary
    while (Test-OtterTokenKind ([TokenKind]::And)) {
        $operator = Read-OtterToken
        $left = [LogicalExpr]::new($left, [LogicalOp]::And, (Read-OtterConditionPrimary), $operator.Line)
    }
    return $left
}

function Read-OtterCondition {
    $left = Read-OtterAndCondition
    while (Test-OtterTokenKind ([TokenKind]::Or)) {
        $operator = Read-OtterToken
        $left = [LogicalExpr]::new($left, [LogicalOp]::Or, (Read-OtterAndCondition), $operator.Line)
    }
    return $left
}

function Read-OtterBlock {
    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the statement to end here.')
    [void](Assert-OtterTokenKind ([TokenKind]::Indent) 'I expected an indented block after this statement.')
    $body = Read-OtterStatements
    [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the indented block to end.')
    if (Test-OtterTokenKind ([TokenKind]::BlockEnd)) { [void](Read-OtterToken); Skip-OtterNewlines }
    return $body
}

function Read-OtterListItems {
    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the list definition to end here.')
    [void](Assert-OtterTokenKind ([TokenKind]::Indent) 'I expected indented list items.')
    $items = [System.Collections.Generic.List[Node]]::new()
    Skip-OtterNewlines
    while (-not (Test-OtterTokenKind ([TokenKind]::Dedent))) {
        $items.Add((Read-OtterValue))
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the list item to end here.')
        Skip-OtterNewlines
    }
    [void](Read-OtterToken)
    if (Test-OtterTokenKind ([TokenKind]::BlockEnd)) { [void](Read-OtterToken); Skip-OtterNewlines }
    return $items.ToArray()
}

function Test-OtterTokenBeforeNewline {
    param([TokenKind]$Kind)
    for ($index = $script:Position; $index -lt $script:Tokens.Count; $index++) {
        if ($script:Tokens[$index].Kind -eq [TokenKind]::Newline) { return $false }
        if ($script:Tokens[$index].Kind -eq $Kind) { return $true }
    }
    return $false
}

function Read-OtterCallArguments {
    $arguments = [System.Collections.Generic.List[Node]]::new()
    while (-not (Test-OtterTokenKind ([TokenKind]::Newline)) -and -not (Test-OtterTokenKind ([TokenKind]::Make))) {
        if (Test-OtterTokenKind ([TokenKind]::And)) { [void](Read-OtterToken); continue }
        $arguments.Add((Read-OtterValue))
    }
    return $arguments.ToArray()
}

function Read-OtterFunctionName {
    $token = Get-OtterCurrentToken
    if ($token.Kind -ne [TokenKind]::Identifier -and $token.Kind -ne [TokenKind]::Add) {
        throw (New-OtterParserError 'I expected a function name.' $token 'Write a name after "to", such as "to greet name".')
    }
    return Read-OtterToken
}

function Read-OtterCallResultTarget {
    if (-not (Test-OtterTokenKind ([TokenKind]::Make))) { return $null }
    [void](Read-OtterToken)
    return (Assert-OtterTokenKind ([TokenKind]::Identifier) 'I expected a result variable after "make".').Text
}

function Read-OtterStatement {
    $start = Get-OtterCurrentToken
    switch ($start.Kind) {
        ([TokenKind]::Say) {
            [void](Read-OtterToken)
            $parts = [System.Collections.Generic.List[Node]]::new()
            while (-not (Test-OtterTokenKind ([TokenKind]::Newline))) { $parts.Add((Read-OtterValue)) }
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the say statement to end here.')
            return [SayStmt]::new($parts.ToArray(), $start.Line)
        }
        ([TokenKind]::If) {
            [void](Read-OtterToken)
            $branches = [System.Collections.Generic.List[IfBranch]]::new()
            $branches.Add([IfBranch]::new((Read-OtterCondition), (Read-OtterBlock)))
            while ((Test-OtterTokenKind ([TokenKind]::Otherwise)) -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::If) {
                [void](Read-OtterToken); [void](Read-OtterToken)
                $branches.Add([IfBranch]::new((Read-OtterCondition), (Read-OtterBlock)))
            }
            $elseBody = $null
            if (Test-OtterTokenKind ([TokenKind]::Otherwise)) { [void](Read-OtterToken); $elseBody = Read-OtterBlock }
            return [IfStmt]::new($branches.ToArray(), $elseBody, $start.Line)
        }
        ([TokenKind]::While) {
            [void](Read-OtterToken)
            return [WhileStmt]::new((Read-OtterCondition), (Read-OtterBlock), $start.Line)
        }
        ([TokenKind]::Repeat) {
            [void](Read-OtterToken)
            # "times" is the repeat delimiter, so it cannot be consumed as
            # the multiplication operator here.
            $count = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Times) 'I expected "times" after the repeat count.')
            return [RepeatStmt]::new($count, (Read-OtterBlock), $start.Line)
        }
        ([TokenKind]::Count) {
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" after count.')
            $from = Read-OtterMathExpression
            [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" after the starting number.')
            $to = Read-OtterMathExpression
            [void](Assert-OtterTokenKind ([TokenKind]::As) 'I expected "as" before the counter name.')
            $name = Assert-OtterTokenKind ([TokenKind]::Identifier) 'I expected a counter name.'
            return [CountStmt]::new($name.Text, $from, $to, (Read-OtterBlock), $start.Line)
        }
        ([TokenKind]::ForEach) {
            [void](Read-OtterToken)
            $name = Assert-OtterTokenKind ([TokenKind]::Identifier) 'I expected a loop variable after "for each".'
            [void](Assert-OtterTokenKind ([TokenKind]::In) 'I expected "in" after the loop variable.')
            $collection = Read-OtterValue
            return [ForEachStmt]::new($name.Text, $collection, (Read-OtterBlock), $start.Line)
        }
        ([TokenKind]::Ask) {
            [void](Read-OtterToken)
            $prompt = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::And) 'I expected "and call it" after the question.')
            [void](Assert-OtterTokenKind ([TokenKind]::Call) 'I expected "call" after "and".')
            [void](Assert-OtterTokenKind ([TokenKind]::It) 'I expected "it" after "call".')
            $name = Assert-OtterTokenKind ([TokenKind]::Identifier) 'I expected a variable name after "call it".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the question to end here.')
            return [AskStmt]::new($prompt, $name.Text, $start.Line)
        }
        ([TokenKind]::To) {
            [void](Read-OtterToken)
            $name = Read-OtterFunctionName
            $parameters = [System.Collections.Generic.List[string]]::new()
            while (-not (Test-OtterTokenKind ([TokenKind]::Newline))) {
                if (Test-OtterTokenKind ([TokenKind]::And)) { [void](Read-OtterToken); continue }
                $parameters.Add((Assert-OtterTokenKind ([TokenKind]::Identifier) 'I expected a parameter name.').Text)
            }
            # Definitions are visible from their own body onward, which also
            # allows a function to call itself recursively.
            $script:KnownFunctions[$name.Text] = $true
            return [FunctionDefStmt]::new($name.Text, $parameters.ToArray(), (Read-OtterBlock), $start.Line)
        }
        ([TokenKind]::Return) {
            [void](Read-OtterToken)
            $value = Read-OtterMathExpression
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the return statement to end here.')
            return [ReturnStmt]::new($value, $start.Line)
        }
        ([TokenKind]::Add) {
            [void](Read-OtterToken)
            if (Test-OtterTokenBeforeNewline ([TokenKind]::To)) {
                $amount = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a variable name.')
                $name = Assert-OtterTokenKind ([TokenKind]::Identifier) 'I expected a variable name after "to".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the add statement to end here.')
                return [AddToStmt]::new($amount, $name.Text, $start.Line)
            }
            $call = [CallExpr]::new($start.Text, (Read-OtterCallArguments), $start.Line)
            $target = Read-OtterCallResultTarget
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the function call to end here.')
            return [CallStmt]::new($call, $target, $start.Line)
        }
        ([TokenKind]::Remove) {
            [void](Read-OtterToken)
            $amount = Read-OtterMathExpression
            [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a variable name.')
            $name = Assert-OtterTokenKind ([TokenKind]::Identifier) 'I expected a variable name after "from".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the remove statement to end here.')
            return [RemoveFromStmt]::new($amount, $name.Text, $start.Line)
        }
        ([TokenKind]::Identifier) {
            $name = Read-OtterToken
            if (Test-OtterTokenKind ([TokenKind]::Is)) {
                [void](Read-OtterToken)
                $value = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the assignment to end here.')
                return [AssignStmt]::new($name.Text, $value, $name.Line)
            }
            if (Test-OtterTokenKind ([TokenKind]::Are)) {
                [void](Read-OtterToken)
                if (Test-OtterTokenKind ([TokenKind]::Empty)) {
                    [void](Read-OtterToken)
                    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the empty list definition to end here.')
                    return [ListDefStmt]::new($name.Text, @(), $name.Line)
                }
                return [ListDefStmt]::new($name.Text, (Read-OtterListItems), $name.Line)
            }
            # The grammar is intentionally resolved from declared function
            # names: "double 5 make result" and "five make result" are
            # calls, while "number1 and number2 make total" is arithmetic.
            if ($script:KnownFunctions.ContainsKey($name.Text)) {
                $call = [CallExpr]::new($name.Text, (Read-OtterCallArguments), $name.Line)
                $target = Read-OtterCallResultTarget
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the function call to end here.')
                return [CallStmt]::new($call, $target, $name.Line)
            }
            # A make statement owns arithmetic; otherwise this is a function call.
            if (Test-OtterTokenBeforeNewline ([TokenKind]::Make)) {
                $script:Position--
                $expression = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::Make) 'I expected "make" and a result variable.')
                $target = Assert-OtterTokenKind ([TokenKind]::Identifier) 'I expected a variable name after "make".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the math statement to end here.')
                return [MathIntoStmt]::new($expression, $target.Text, $start.Line)
            }
            $call = [CallExpr]::new($name.Text, (Read-OtterCallArguments), $name.Line)
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the function call to end here.')
            return [CallStmt]::new($call, $null, $name.Line)
        }
        ([TokenKind]::Number) {
            $expression = Read-OtterMathExpression
            [void](Assert-OtterTokenKind ([TokenKind]::Make) 'I expected "make" and a result variable.')
            $target = Assert-OtterTokenKind ([TokenKind]::Identifier) 'I expected a variable name after "make".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the math statement to end here.')
            return [MathIntoStmt]::new($expression, $target.Text, $start.Line)
        }
        default { throw (New-OtterParserError "I don't understand '$($start.Text)'." $start 'Start a statement with a word such as say, if, or a variable name.') }
    }
}

function Read-OtterStatements {
    $statements = [System.Collections.Generic.List[Node]]::new()
    Skip-OtterNewlines
    while (-not (Test-OtterTokenKind ([TokenKind]::Dedent)) -and -not (Test-OtterTokenKind ([TokenKind]::EndOfFile)) -and -not (Test-OtterTokenKind ([TokenKind]::BlockEnd))) {
        $statements.Add((Read-OtterStatement))
        Skip-OtterNewlines
    }
    return $statements.ToArray()
}

function ConvertTo-OtterAst {
    [OutputType([ProgramNode])]
    param([Parameter(Mandatory)][Token[]]$Tokens)

    Initialize-OtterParser $Tokens
    $statements = Read-OtterStatements
    if (Test-OtterTokenKind ([TokenKind]::BlockEnd)) {
        $token = Read-OtterToken
        throw (New-OtterParserError 'There is no open block for this period to close.' $token 'Remove this period or place it after an indented block.')
    }
    [void](Assert-OtterTokenKind ([TokenKind]::EndOfFile) 'I expected the program to end here.')
    return [ProgramNode]::new($statements)
}

Export-ModuleMember -Function ConvertTo-OtterAst
