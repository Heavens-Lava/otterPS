using module ..\Otter.Contract.psm1

# Milestone 1 parser: say, assignment, and an if block with comparison.

# D32: which token kinds name a length of time.
$script:OtterTimeUnits = @{
    ([TokenKind]::Year) = [TimeUnit]::Year
    ([TokenKind]::Month) = [TimeUnit]::Month
    ([TokenKind]::Day) = [TimeUnit]::Day
    ([TokenKind]::Hour) = [TimeUnit]::Hour
    ([TokenKind]::Minute) = [TimeUnit]::Minute
    ([TokenKind]::Second) = [TimeUnit]::Second
}

function Test-OtterTimeUnit {
    param([TokenKind]$Kind)
    return $script:OtterTimeUnits.ContainsKey($Kind)
}

# D33 words are ordinary names away from the one statement form that they
# introduce. `has` is the older always-tokenized exception: it is safe in all
# identifier slots because only `a <Type> has` consumes its special token.
$script:OtterIdentifierKinds = @(
    [TokenKind]::Identifier, [TokenKind]::File, [TokenKind]::Files,
    [TokenKind]::Folder, [TokenKind]::Folders, [TokenKind]::Has,
    [TokenKind]::Copy, [TokenKind]::Move, [TokenKind]::Delete,
    [TokenKind]::Create, [TokenKind]::Read, [TokenKind]::Write,
    [TokenKind]::Sort, [TokenKind]::Reverse, [TokenKind]::Replace,
    [TokenKind]::Split, [TokenKind]::Join, [TokenKind]::Find,
    [TokenKind]::Get, [TokenKind]::Try, [TokenKind]::Run,
    [TokenKind]::Log, [TokenKind]::Warn, [TokenKind]::Problem,
    [TokenKind]::Random, [TokenKind]::Json, [TokenKind]::Convert,
    [TokenKind]::Format, [TokenKind]::Today, [TokenKind]::Now,
    [TokenKind]::Between, [TokenKind]::Otherwise, [TokenKind]::ForEach
)

function Test-OtterIdentifierToken {
    param([Token]$Token)
    return $Token.Kind -in $script:OtterIdentifierKinds
}

function Initialize-OtterParser {
    param([Token[]]$Tokens)
    $script:Tokens = $Tokens
    $script:Position = 0
    $script:KnownFunctions = @{}
    $script:KnownTypes = @{}
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

# D38A: allow a discovery clause to continue on an indented following line.
# This is intentionally opt-in; callers must consume the matching Dedent
# after reading the continued clause.
function Test-OtterSoftContinuation {
    if (-not (Test-OtterTokenKind ([TokenKind]::Newline))) { return $false }
    if (($script:Position + 1) -ge $script:Tokens.Count -or $script:Tokens[$script:Position + 1].Kind -ne [TokenKind]::Indent) { return $false }
    [void](Read-OtterToken)
    [void](Read-OtterToken)
    return $true
}

function Read-OtterValue {
    $token = Get-OtterCurrentToken
    # Optional readability word for property grammar only. `the` is consumed
    # when it introduces a real `<property> of ...` sequence; elsewhere it is
    # left untouched so this is not a global filler-word rule.
    if ($token.Text -eq 'the' -and ($script:Position + 2) -lt $script:Tokens.Count -and
        $script:Tokens[$script:Position + 1].Kind -in $script:OtterIdentifierKinds -and
        $script:Tokens[$script:Position + 2].Kind -eq [TokenKind]::Of) {
        [void](Read-OtterToken)
        $token = Get-OtterCurrentToken
    }
    # D42: a time unit followed by `between` is a date-difference value.
    # This is deliberately checked before ordinary value parsing so the
    # expression form can appear on the right side of `is`, in `say`, or in a
    # condition. The statement-level D32 `... make ...` form remains separate.
    if (Test-OtterTimeUnit $token.Kind) {
        $next = if (($script:Position + 1) -lt $script:Tokens.Count) { $script:Tokens[$script:Position + 1] } else { $null }
        if ($null -ne $next -and $next.Kind -eq [TokenKind]::Between) {
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            $start = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::And) 'I expected "and" and the second date.')
            $end = Read-OtterValue
            return [DateDifferenceExpr]::new($script:OtterTimeUnits[$token.Kind], $start, $end, $token.Line)
        }
    }
    if ($token.Kind -in @([TokenKind]::Length, [TokenKind]::Uppercase, [TokenKind]::Lowercase, [TokenKind]::First, [TokenKind]::Last)) {
        [void](Read-OtterToken)
        [void](Assert-OtterTokenKind ([TokenKind]::Of) 'I expected "of" after this operation.')
        $operation = switch ($token.Kind) {
            ([TokenKind]::Length) { [OfOperation]::Length }
            ([TokenKind]::Uppercase) { [OfOperation]::Uppercase }
            ([TokenKind]::Lowercase) { [OfOperation]::Lowercase }
            ([TokenKind]::First) { [OfOperation]::First }
            ([TokenKind]::Last) { [OfOperation]::Last }
        }
        return [OfOperationExpr]::new($operation, (Read-OtterValue), $token.Line)
    }
    # These words are commands in statement position, but ordinary names in
    # expression position: `for each file in files`, `name of file`.
    # D32 wins over D33 in expression position. Keeping these source words
    # as identifiers elsewhere still lets them name variables, parameters,
    # properties, and loop variables where that is unambiguous.
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'today') {
        [void](Read-OtterToken); return [ClockExpr]::new([ClockKind]::Today, $token.Line)
    }
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'now') {
        [void](Read-OtterToken); return [ClockExpr]::new([ClockKind]::Now, $token.Line)
    }
    if (Test-OtterIdentifierToken $token) {
        [void](Read-OtterToken)
        if (Test-OtterTokenKind ([TokenKind]::Of)) {
            [void](Read-OtterToken)
            return [PropertyAccessExpr]::new($token.Text, (Read-OtterValue), $token.Line)
        }
        return [VariableExpr]::new($token.Text, $token.Line)
    }
    switch ($token.Kind) {
        ([TokenKind]::String) { [void](Read-OtterToken); return [LiteralExpr]::new($token.Value, $token.Line) }
        ([TokenKind]::Number) { [void](Read-OtterToken); return [LiteralExpr]::new($token.Value, $token.Line) }
        ([TokenKind]::True) { [void](Read-OtterToken); return [LiteralExpr]::new($true, $token.Line) }
        ([TokenKind]::False) { [void](Read-OtterToken); return [LiteralExpr]::new($false, $token.Line) }
        ([TokenKind]::Gone) { [void](Read-OtterToken); return [LiteralExpr]::new($null, $token.Line) }
        ([TokenKind]::Today) { [void](Read-OtterToken); return [ClockExpr]::new([ClockKind]::Today, $token.Line) }
        ([TokenKind]::Now) { [void](Read-OtterToken); return [ClockExpr]::new([ClockKind]::Now, $token.Line) }
        default { throw (New-OtterParserError 'I expected a value here.' $token 'Add a text value, number, true, false, or variable name.') }
    }
}

function Read-OtterVariableName {
    param([string]$Message)
    $token = Get-OtterCurrentToken
    if (-not (Test-OtterIdentifierToken $token)) {
        throw (New-OtterParserError $Message $token 'Use a name to hold this value.')
    }
    [void](Read-OtterToken)
    return $token
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
    if (Test-OtterTokenKind ([TokenKind]::File)) {
        $fileToken = Read-OtterToken
        $path = Read-OtterValue
        [void](Assert-OtterTokenKind ([TokenKind]::Exists) 'I expected "exists" after the file path.')
        return [FileExistsExpr]::new($path, $fileToken.Line)
    }
    $left = Read-OtterValue
    if (Test-OtterTokenKind ([TokenKind]::Contains)) {
        $operator = Read-OtterToken
        return [ContainsExpr]::new($left, (Read-OtterValue), $operator.Line)
    }
    if ((Test-OtterTokenKind ([TokenKind]::StartsWith)) -or (Test-OtterTokenKind ([TokenKind]::EndsWith))) {
        $operator = Read-OtterToken
        $match = if ($operator.Kind -eq [TokenKind]::StartsWith) { [TextMatch]::StartsWith } else { [TextMatch]::EndsWith }
        return [TextMatchExpr]::new($left, $match, (Read-OtterValue), $operator.Line)
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

# D41 narrows empty-block acceptance to object construction only. All control
# flow and function blocks continue through Read-OtterBlock and still require
# an actual indented body.
function Read-OtterObjectBlock {
    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the object statement to end here.')
    if (-not (Test-OtterTokenKind ([TokenKind]::Indent))) {
        # Empty objects may still use the ordinary block terminator. Consume
        # it here so it cannot be left orphaned for the outer statement list.
        if (Test-OtterTokenKind ([TokenKind]::BlockEnd)) { [void](Read-OtterToken); Skip-OtterNewlines }
        return @()
    }
    [void](Read-OtterToken)
    $body = Read-OtterStatements
    [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the object block to end.')
    if (Test-OtterTokenKind ([TokenKind]::BlockEnd)) { [void](Read-OtterToken); Skip-OtterNewlines }
    return $body
}

function Read-OtterInlineObjectProperties {
    $properties = [System.Collections.Generic.List[Node]]::new()
    while ($true) {
        $property = Read-OtterVariableName 'I expected a property name after "has" or a comma.'
        # Inline has is a compact configuration list: property values follow
        # directly, with commas providing the boundaries.  `is` remains the
        # assignment word everywhere else, including multiline has, but is
        # deliberately rejected in this compact subgrammar.
        if (Test-OtterTokenKind ([TokenKind]::Is)) {
            throw (New-OtterParserError 'Inline properties do not use "is".' (Get-OtterCurrentToken) 'Write the property followed directly by its value, such as `text "Save"`.')
        }
        $value = Read-OtterMathExpression
        $properties.Add([AssignStmt]::new($property.Text, $value, $property.Line))
        if ((Get-OtterCurrentToken).Text -ne ',') { break }
        [void](Read-OtterToken)
        if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Newline) {
            throw (New-OtterParserError 'I expected a property after the comma.' (Get-OtterCurrentToken) 'Add another property assignment after the comma.')
        }
    }
    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the inline properties to end here.')
    return $properties.ToArray()
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

function Read-OtterTypeFields {
    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the type definition to end here.')
    [void](Assert-OtterTokenKind ([TokenKind]::Indent) 'I expected indented property names for this type.')
    $fields = [System.Collections.Generic.List[string]]::new()
    Skip-OtterNewlines
    while (-not (Test-OtterTokenKind ([TokenKind]::Dedent))) {
        $field = Read-OtterVariableName 'I expected a property name.'
        $fields.Add($field.Text)
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the property name to end here.')
        Skip-OtterNewlines
    }
    [void](Read-OtterToken)
    if (Test-OtterTokenKind ([TokenKind]::BlockEnd)) { [void](Read-OtterToken); Skip-OtterNewlines }
    return $fields.ToArray()
}

function Read-OtterObjectTypeName {
    $words = [System.Collections.Generic.List[string]]::new()
    while (-not (Test-OtterTokenKind ([TokenKind]::Newline))) {
        $token = Read-OtterToken
        $words.Add($token.Text)
    }
    if ($words.Count -eq 0) {
        $token = Get-OtterCurrentToken
        throw (New-OtterParserError 'I expected a type name after "is a".' $token 'Write a type, such as "thing" or "Person".')
    }
    return $words -join ' '
}

function Read-OtterUiResourceTypeName {
    $words = [System.Collections.Generic.List[string]]::new()
    while (-not (Test-OtterTokenKind ([TokenKind]::Into))) {
        $token = Get-OtterCurrentToken
        if ($token.Kind -in @([TokenKind]::Newline, [TokenKind]::EndOfFile)) {
            throw (New-OtterParserError 'I expected "into" after the resource type.' $token 'Write a resource type followed by "into" and a variable name.')
        }
        $words.Add((Read-OtterToken).Text)
    }
    if ($words.Count -eq 0) {
        $token = Get-OtterCurrentToken
        throw (New-OtterParserError 'I expected a resource type after "create".' $token 'Write a resource type, such as "button" or "text box".')
    }
    return $words -join ' '
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
    if ((-not (Test-OtterIdentifierToken $token)) -and $token.Kind -ne [TokenKind]::Add) {
        throw (New-OtterParserError 'I expected a function name.' $token 'Write a name after "to", such as "to greet name".')
    }
    return Read-OtterToken
}

function Read-OtterCallResultTarget {
    if (-not (Test-OtterTokenKind ([TokenKind]::Make))) { return $null }
    [void](Read-OtterToken)
    return (Read-OtterVariableName 'I expected a result variable after "make".').Text
}

# Shared by log / warn / error. Parts are read exactly like say (D8), so a
# diagnostic can mix text and values: log "Listening on" port
function Read-OtterDiagnostic {
    param([DiagnosticLevel]$Level, [Token]$Start)
    $parts = [System.Collections.Generic.List[Node]]::new()
    while (-not (Test-OtterTokenKind ([TokenKind]::Newline))) { $parts.Add((Read-OtterValue)) }
    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the diagnostic to end here.')
    return [DiagnosticStmt]::new($Level, $parts.ToArray(), $Start.Line)
}

function Read-OtterStatement {
    $start = Get-OtterCurrentToken

    # days between startDate and endDate make days               (D32)
    #
    # Checked before the switch because the statement begins with a unit
    # token rather than a verb.
    if ((Test-OtterTimeUnit $start.Kind) -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Between) {
        $unitToken = Read-OtterToken
        [void](Read-OtterToken)
        $from = Read-OtterValue
        [void](Assert-OtterTokenKind ([TokenKind]::And) 'I expected "and" and the second date.')
        $to = Read-OtterValue
        [void](Assert-OtterTokenKind ([TokenKind]::Make) 'I expected "make" and a result name.')
        $differenceTarget = Read-OtterVariableName 'I expected a result name after "make".'
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the difference statement to end here.')
        return [DateDifferenceStmt]::new($script:OtterTimeUnits[$unitToken.Kind], $from, $to, $differenceTarget.Text, $start.Line)
    }

    # A D33 statement-head word still names a variable when the rest of this
    # line makes assignment, list definition, or property assignment explicit.
    # The statement forms themselves remain the switch cases below.
    $statementKind = $start.Kind
    $nextKind = if (($script:Position + 1) -lt $script:Tokens.Count) { $script:Tokens[$script:Position + 1].Kind } else { [TokenKind]::EndOfFile }
    if (((Test-OtterIdentifierToken $start) -or ($start.Kind -eq [TokenKind]::ForEach -and $start.Text -eq 'each')) -and
        $nextKind -in @([TokenKind]::Is, [TokenKind]::Are, [TokenKind]::Of)) {
        $statementKind = [TokenKind]::Identifier
    }

    # `the property of target is value` is the assignment counterpart of the
    # optional readability form handled by Read-OtterValue.
    if ($start.Text -eq 'the' -and ($script:Position + 2) -lt $script:Tokens.Count -and
        $script:Tokens[$script:Position + 1].Kind -in $script:OtterIdentifierKinds -and
        $script:Tokens[$script:Position + 2].Kind -eq [TokenKind]::Of) {
        $target = Read-OtterValue
        [void](Assert-OtterTokenKind ([TokenKind]::Is) 'I expected "is" after the property target.')
        $value = Read-OtterMathExpression
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the property assignment to end here.')
        return [AssignStmt]::new($target, $value, $start.Line)
    }

    switch ($statementKind) {
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
        ([TokenKind]::When) {
            [void](Read-OtterToken)
            $targetToken = Read-OtterVariableName 'I expected a resource name after "when".'
            $target = [VariableExpr]::new($targetToken.Text, $targetToken.Line)
            [void](Assert-OtterTokenKind ([TokenKind]::Is) 'I expected "is" before the event name.')
            $eventToken = Get-OtterCurrentToken
            if ($eventToken.Kind -in @([TokenKind]::Newline, [TokenKind]::EndOfFile)) {
                throw (New-OtterParserError 'I expected an event name after "is".' $eventToken 'Write an event such as "clicked" or "changed".')
            }
            [void](Read-OtterToken)
            return [WhenStmt]::new($target, $eventToken.Text, (Read-OtterBlock), $start.Line)
        }
        ([TokenKind]::Put) {
            [void](Read-OtterToken)
            $items = [System.Collections.Generic.List[Node]]::new()
            $itemToken = Read-OtterVariableName 'I expected a resource name after "put".'
            $items.Add([VariableExpr]::new($itemToken.Text, $itemToken.Line))
            while ((Get-OtterCurrentToken).Text -eq ',') {
                [void](Read-OtterToken)
                $next = Get-OtterCurrentToken
                if ($next.Text -eq ',' -or $next.Kind -eq [TokenKind]::In -or $next.Kind -eq [TokenKind]::Newline) {
                    throw (New-OtterParserError 'I expected a resource name after the comma.' $next 'Write another resource name after each comma.')
                }
                $itemToken = Read-OtterVariableName 'I expected a resource name after the comma.'
                $items.Add([VariableExpr]::new($itemToken.Text, $itemToken.Line))
            }
            [void](Assert-OtterTokenKind ([TokenKind]::In) 'I expected "in" before the container.')
            $containerToken = Read-OtterVariableName 'I expected a resource name after "in".'
            $container = [VariableExpr]::new($containerToken.Text, $containerToken.Line)
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the put statement to end here.')
            $desugared = [System.Collections.Generic.List[Node]]::new()
            foreach ($item in $items) { $desugared.Add([PutInStmt]::new($item, $container, $start.Line)) }
            return $desugared.ToArray()
        }
        ([TokenKind]::Show) {
            [void](Read-OtterToken)
            $targetToken = Read-OtterVariableName 'I expected a resource name after "show".'
            $target = [VariableExpr]::new($targetToken.Text, $targetToken.Line)
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the show statement to end here.')
            return [ShowStmt]::new($target, $start.Line)
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
            $name = Read-OtterVariableName 'I expected a counter name.'
            return [CountStmt]::new($name.Text, $from, $to, (Read-OtterBlock), $start.Line)
        }
        ([TokenKind]::ForEach) {
            [void](Read-OtterToken)
            $name = Read-OtterVariableName 'I expected a loop variable after "for each".'
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
            $name = Read-OtterVariableName 'I expected a variable name after "call it".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the question to end here.')
            return [AskStmt]::new($prompt, $name.Text, $start.Line)
        }
        ([TokenKind]::Get) {
            [void](Read-OtterToken)
            $kind = Get-OtterCurrentToken
            if ($kind.Kind -eq [TokenKind]::Files -or $kind.Kind -eq [TokenKind]::Folders) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::In) 'I expected "in" and a folder path.')
                $folder = Read-OtterValue
                $includeSubfolders = $false
                if (Test-OtterTokenKind ([TokenKind]::And)) {
                    [void](Read-OtterToken)
                    [void](Assert-OtterTokenKind ([TokenKind]::Subfolders) 'I expected "subfolders" after "and".')
                    $includeSubfolders = $true
                }
                $continued = Test-OtterSoftContinuation
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $target = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the discovery statement to end here.')
                if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued discovery clause to end.') }
                if ($kind.Kind -eq [TokenKind]::Files) { return [GetFilesStmt]::new($folder, $includeSubfolders, $target.Text, $start.Line) }
                return [GetFoldersStmt]::new($folder, $includeSubfolders, $target.Text, $start.Line)
            }
            # D41 dynamic key access: get <key> from <thing> into <name>.
            $key = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a target thing.')
            $target = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
            $result = Read-OtterVariableName 'I expected a result name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
            return [GetKeyStmt]::new($key, $target, $result.Text, $start.Line)
        }
        ([TokenKind]::Set) {
            [void](Read-OtterToken)
            $key = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a value.')
            $value = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::In) 'I expected "in" and a target thing.')
            $target = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the set statement to end here.')
            return [SetKeyStmt]::new($key, $value, $target, $start.Line)
        }
        ([TokenKind]::Create) {
            [void](Read-OtterToken)
            if (Test-OtterTokenKind ([TokenKind]::Folder)) {
                [void](Read-OtterToken)
                $path = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the create statement to end here.')
                return [CreateFolderStmt]::new($path, $start.Line)
            }
            $typeName = Read-OtterUiResourceTypeName
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a resource variable name.')
            $target = Read-OtterVariableName 'I expected a variable name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the create statement to end here.')
            return [CreateUiResourceStmt]::new($typeName, $target.Text, $start.Line)
        }
        ([TokenKind]::Try) {
            [void](Read-OtterToken)
            $body = Read-OtterBlock
            $otherwiseBody = $null
            if (Test-OtterTokenKind ([TokenKind]::Otherwise)) {
                [void](Read-OtterToken)
                $otherwiseBody = Read-OtterBlock
            }
            return [TryStmt]::new($body, $otherwiseBody, $start.Line)
        }
        ([TokenKind]::Sort) {
            [void](Read-OtterToken)
            $target = Read-OtterVariableName 'I expected a collection name after "sort".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the sort statement to end here.')
            return [SortStmt]::new($target.Text, $start.Line)
        }
        ([TokenKind]::Reverse) {
            [void](Read-OtterToken)
            $target = Read-OtterVariableName 'I expected a collection name after "reverse".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the reverse statement to end here.')
            return [ReverseStmt]::new($target.Text, $start.Line)
        }
        ([TokenKind]::Replace) {
            [void](Read-OtterToken)
            $find = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::With) 'I expected "with" and replacement text.')
            $replacement = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::In) 'I expected "in" and the text variable to change.')
            $target = Read-OtterVariableName 'I expected a text variable after "in".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the replace statement to end here.')
            return [ReplaceStmt]::new($find, $replacement, $target.Text, $start.Line)
        }
        ([TokenKind]::Split) {
            [void](Read-OtterToken)
            $subject = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::By) 'I expected "by" and a separator.')
            $separator = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a list name.')
            $target = Read-OtterVariableName 'I expected a list name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the split statement to end here.')
            return [SplitStmt]::new($subject, $separator, $target.Text, $start.Line)
        }
        ([TokenKind]::Join) {
            [void](Read-OtterToken)
            $subject = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::With) 'I expected "with" and a separator.')
            $separator = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a text name.')
            $target = Read-OtterVariableName 'I expected a text name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the join statement to end here.')
            return [JoinStmt]::new($subject, $separator, $target.Text, $start.Line)
        }
        ([TokenKind]::Find) {
            [void](Read-OtterToken)
            $item = Read-OtterVariableName 'I expected an item name after "find".'
            [void](Assert-OtterTokenKind ([TokenKind]::In) 'I expected "in" and a collection.')
            $collection = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Where) 'I expected "where" and a condition.')
            $condition = Read-OtterCondition
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
            $target = Read-OtterVariableName 'I expected a result name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the find statement to end here.')
            return [FindStmt]::new($item.Text, $collection, $condition, $target.Text, $start.Line)
        }
        # format date as "MM/dd/yyyy" into text                     (D32)
        ([TokenKind]::Format) {
            [void](Read-OtterToken)
            $subject = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::As) 'I expected "as" and a date format.')
            $pattern = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a variable name.')
            $target = Read-OtterVariableName 'I expected a variable name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the format statement to end here.')
            return [FormatDateStmt]::new($subject, $pattern, $target.Text, $start.Line)
        }
        # log "Server started."   warn "..."   error "..."         (D31)
        #
        # These are NOT aliases for say. The runtime sends them to a separate
        # writer, so a host can route what a program tells its operator away
        # from what it tells its user.
        ([TokenKind]::Log) {
            [void](Read-OtterToken)
            return (Read-OtterDiagnostic ([DiagnosticLevel]::Note) $start)
        }
        ([TokenKind]::Warn) {
            [void](Read-OtterToken)
            return (Read-OtterDiagnostic ([DiagnosticLevel]::Warning) $start)
        }
        ([TokenKind]::Problem) {
            [void](Read-OtterToken)
            return (Read-OtterDiagnostic ([DiagnosticLevel]::Problem) $start)
        }
        # random number from 1 to 10 into number                    (D30)
        # random item from games into game
        #
        # "number" and "item" stay ORDINARY IDENTIFIERS in the lexer, matched
        # by text here. Reserving "item" as a keyword would break the very
        # common "for each item in items".
        ([TokenKind]::Random) {
            [void](Read-OtterToken)
            $what = Get-OtterCurrentToken

            if ($what.Kind -eq [TokenKind]::Identifier -and $what.Text -eq 'number') {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and the lowest number.')
                $from = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and the highest number.')
                $to = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a variable name.')
                $target = Read-OtterVariableName 'I expected a variable name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the random statement to end here.')
                return [RandomNumberStmt]::new($from, $to, $target.Text, $start.Line)
            }

            if (($what.Kind -eq [TokenKind]::Item) -or ($what.Kind -eq [TokenKind]::Identifier -and $what.Text -eq 'item')) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a list.')
                $collection = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a variable name.')
                $target = Read-OtterVariableName 'I expected a variable name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the random statement to end here.')
                return [RandomItemStmt]::new($collection, $target.Text, $start.Line)
            }

            throw (New-OtterParserError 'I expected "number" or "item" after "random".' $what 'Write "random number from 1 to 10 into n" or "random item from games into g".')
        }
        # convert user to json into text                            (D29)
        # convert text from json into user
        ([TokenKind]::Convert) {
            [void](Read-OtterToken)
            $subject = Read-OtterValue

            if (Test-OtterTokenKind ([TokenKind]::To)) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Json) 'I expected "json" after "to".')
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a variable name.')
                $target = Read-OtterVariableName 'I expected a variable name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the convert statement to end here.')
                return [ConvertToJsonStmt]::new($subject, $target.Text, $start.Line)
            }

            [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "to json" or "from json" here.')
            [void](Assert-OtterTokenKind ([TokenKind]::Json) 'I expected "json" after "from".')
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a variable name.')
            $target = Read-OtterVariableName 'I expected a variable name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the convert statement to end here.')
            return [ConvertFromJsonStmt]::new($subject, $target.Text, $start.Line)
        }
        ([TokenKind]::Read) {
            [void](Read-OtterToken)
            # read json from "settings.json" into settings          (D29)
            if (Test-OtterTokenKind ([TokenKind]::Json)) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a file path.')
                $jsonPath = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a variable name.')
                $jsonTarget = Read-OtterVariableName 'I expected a variable name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the read statement to end here.')
                return [ReadJsonStmt]::new($jsonPath, $jsonTarget.Text, $start.Line)
            }
            $path = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a variable name.')
            $target = Read-OtterVariableName 'I expected a variable name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the read statement to end here.')
            return [ReadFileStmt]::new($path, $target.Text, $start.Line)
        }
        ([TokenKind]::Write) {
            [void](Read-OtterToken)
            $content = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a file path.')
            $path = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the write statement to end here.')
            return [WriteFileStmt]::new($content, $path, $start.Line)
        }
        ([TokenKind]::Copy) {
            [void](Read-OtterToken)
            if (Test-OtterTokenKind ([TokenKind]::Folder)) {
                [void](Read-OtterToken)
                $source = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a destination folder.')
                $destination = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the copy statement to end here.')
                return [CopyFolderStmt]::new($source, $destination, $start.Line)
            }
            $source = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a destination path.')
            $destination = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the copy statement to end here.')
            return [CopyFileStmt]::new($source, $destination, $start.Line)
        }
        ([TokenKind]::Move) {
            [void](Read-OtterToken)
            if (Test-OtterTokenKind ([TokenKind]::Folder)) {
                [void](Read-OtterToken)
                $source = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a destination folder.')
                $destination = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the move statement to end here.')
                return [MoveFolderStmt]::new($source, $destination, $start.Line)
            }
            $source = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a destination path.')
            $destination = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the move statement to end here.')
            return [MoveFileStmt]::new($source, $destination, $start.Line)
        }
        ([TokenKind]::Delete) {
            [void](Read-OtterToken)
            if (Test-OtterTokenKind ([TokenKind]::Folder)) {
                [void](Read-OtterToken)
                $path = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the delete statement to end here.')
                return [DeleteFolderStmt]::new($path, $start.Line)
            }
            [void](Assert-OtterTokenKind ([TokenKind]::File) 'I expected "file" after delete.')
            $path = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the delete statement to end here.')
            return [DeleteFileStmt]::new($path, $start.Line)
        }
        ([TokenKind]::Run) {
            [void](Read-OtterToken)
            $isCommand = $false
            if (Test-OtterTokenKind ([TokenKind]::Command)) { [void](Read-OtterToken); $isCommand = $true }
            $target = Read-OtterValue
            $resultTarget = $null
            if (Test-OtterTokenKind ([TokenKind]::Into)) {
                [void](Read-OtterToken)
                $resultTarget = (Read-OtterVariableName 'I expected a variable name after "into".').Text
            }
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the run statement to end here.')
            return [RunStmt]::new($target, $isCommand, $resultTarget, $start.Line)
        }
        ([TokenKind]::A) {
            [void](Read-OtterToken)
            $typeName = Read-OtterVariableName 'I expected a type name after "a".'
            [void](Assert-OtterTokenKind ([TokenKind]::Has) 'I expected "has" after the type name.')
            $script:KnownTypes[$typeName.Text] = $true
            return [TypeDefStmt]::new($typeName.Text, (Read-OtterTypeFields), $start.Line)
        }
        ([TokenKind]::To) {
            [void](Read-OtterToken)
            $name = Read-OtterFunctionName
            $parameters = [System.Collections.Generic.List[string]]::new()
            while (-not (Test-OtterTokenKind ([TokenKind]::Newline))) {
                if (Test-OtterTokenKind ([TokenKind]::And)) { [void](Read-OtterToken); continue }
                $parameters.Add((Read-OtterVariableName 'I expected a parameter name.').Text)
            }
            # Definitions are visible from their own body onward, which also
            # allows a function to call itself recursively.
            $script:KnownFunctions[$name.Text] = $true
            return [FunctionDefStmt]::new($name.Text, $parameters.ToArray(), (Read-OtterBlock), $start.Line)
        }
        ([TokenKind]::Return) {
            [void](Read-OtterToken)
            if ($start.Text -eq 'stop') {
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected stop to end here.')
                return [ReturnStmt]::new($null, $start.Line)
            }
            $value = Read-OtterMathExpression
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the return statement to end here.')
            return [ReturnStmt]::new($value, $start.Line)
        }
        ([TokenKind]::Add) {
            [void](Read-OtterToken)
            if ($start.Text -eq 'increase') {
                $target = Read-OtterVariableName 'I expected a variable name after "increase".'
                $amount = [LiteralExpr]::new(1.0, $start.Line)
                if (Test-OtterTokenKind ([TokenKind]::By)) {
                    [void](Read-OtterToken)
                    $amount = Read-OtterMathExpression
                }
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the increase statement to end here.')
                return [AddToStmt]::new($amount, $target.Text, $start.Line)
            }
            if (Test-OtterTokenBeforeNewline ([TokenKind]::To)) {
                $amount = Read-OtterMathExpression
                # add 7 days to date                              (D32)
                #
                # The unit word is what separates this from D12's
                # "add 5 to score", and it is right here in the token
                # stream - the parser never needs to know what the target
                # holds.
                if (Test-OtterTimeUnit (Get-OtterCurrentToken).Kind) {
                    $unitToken = Read-OtterToken
                    [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a date name.')
                    $dateName = Read-OtterVariableName 'I expected a date name after "to".'
                    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the add statement to end here.')
                    return [DateAdjustStmt]::new($amount, $script:OtterTimeUnits[$unitToken.Kind], $dateName.Text, $false, $start.Line)
                }
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a variable name.')
                $name = Read-OtterVariableName 'I expected a variable name after "to".'
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
            if ($start.Text -eq 'decrease') {
                $target = Read-OtterVariableName 'I expected a variable name after "decrease".'
                $amount = [LiteralExpr]::new(1.0, $start.Line)
                if (Test-OtterTokenKind ([TokenKind]::By)) {
                    [void](Read-OtterToken)
                    $amount = Read-OtterMathExpression
                }
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the decrease statement to end here.')
                return [RemoveFromStmt]::new($amount, $target.Text, $start.Line)
            }
            $amount = Read-OtterMathExpression
            # remove 1 month from date                            (D32)
            if (Test-OtterTimeUnit (Get-OtterCurrentToken).Kind) {
                $unitToken = Read-OtterToken
                [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a date name.')
                $dateName = Read-OtterVariableName 'I expected a date name after "from".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the remove statement to end here.')
                return [DateAdjustStmt]::new($amount, $script:OtterTimeUnits[$unitToken.Kind], $dateName.Text, $true, $start.Line)
            }
            [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a variable name.')
            $name = Read-OtterVariableName 'I expected a variable name after "from".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the remove statement to end here.')
            return [RemoveFromStmt]::new($amount, $name.Text, $start.Line)
        }
        ([TokenKind]::Identifier) {
            $name = Read-OtterToken
            # D40: `person has` is the canonical untyped object literal. It
            # deliberately shares the existing ObjectDefStmt shape with
            # `person is a thing`; custom type declarations remain on the A
            # branch below.
            if (Test-OtterTokenKind ([TokenKind]::Has)) {
                [void](Read-OtterToken)
                $properties = if (Test-OtterTokenKind ([TokenKind]::Newline)) { Read-OtterObjectBlock } else { Read-OtterInlineObjectProperties }
                foreach ($property in $properties) {
                    if ($property -isnot [AssignStmt]) {
                        throw (New-OtterParserError 'Only property assignments belong inside an object.' $name 'Write properties such as "name is \"Jeff\"".')
                    }
                }
                return [ObjectDefStmt]::new($name.Text, 'thing', $properties, $name.Line)
            }
            if (Test-OtterTokenKind ([TokenKind]::Of)) {
                # Re-read the whole property-first target, then use the same
                # AssignStmt node as a normal variable assignment.
                $script:Position--
                $target = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Is) 'I expected "is" after the property target.')
                $value = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the property assignment to end here.')
                return [AssignStmt]::new($target, $value, $name.Line)
            }
            if (Test-OtterTokenKind ([TokenKind]::Is)) {
                [void](Read-OtterToken)
                if (Test-OtterTokenKind ([TokenKind]::A)) {
                    [void](Read-OtterToken)
                    $typeName = Read-OtterObjectTypeName
                    # A declared custom type is instantiated without a body:
                    # "jeff is a Person". A thing (or a not-yet-declared UI
                    # type such as "text box") is an object literal and has
                    # indented property assignments.
                    if ($typeName -eq 'thing' -or -not $script:KnownTypes.ContainsKey($typeName)) {
                        $properties = if ($typeName -eq 'thing') { Read-OtterObjectBlock } else { Read-OtterBlock }
                    } else {
                        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the object definition to end here.')
                        $properties = @()
                    }
                    foreach ($property in $properties) {
                        if ($property -isnot [AssignStmt]) {
                            throw (New-OtterParserError 'Only property assignments belong inside a thing.' $name 'Write properties such as "name is \"Jeff\"".')
                        }
                    }
                    return [ObjectDefStmt]::new($name.Text, $typeName, $properties, $name.Line)
                }
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
                $target = Read-OtterVariableName 'I expected a variable name after "make".'
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
            $target = Read-OtterVariableName 'I expected a variable name after "make".'
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
        $parsed = Read-OtterStatement
        if ($parsed -is [System.Array]) { foreach ($statement in $parsed) { $statements.Add($statement) } }
        else { $statements.Add($parsed) }
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
