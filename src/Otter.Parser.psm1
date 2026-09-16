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
    [TokenKind]::Create, [TokenKind]::Read, [TokenKind]::Write, [TokenKind]::Append,
    [TokenKind]::Sort, [TokenKind]::Reverse, [TokenKind]::Replace,
    [TokenKind]::Split, [TokenKind]::Join, [TokenKind]::Find,
    [TokenKind]::Get, [TokenKind]::Try, [TokenKind]::Run,
    [TokenKind]::Log, [TokenKind]::Warn, [TokenKind]::Problem,
    [TokenKind]::Random, [TokenKind]::Json, [TokenKind]::Convert,
    [TokenKind]::Format, [TokenKind]::Today, [TokenKind]::Now,
    [TokenKind]::Between, [TokenKind]::Otherwise, [TokenKind]::ForEach,
    [TokenKind]::Count, [TokenKind]::Notify, [TokenKind]::Choose
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
    $script:OtterBlockDepth = 0
}

function Get-OtterCurrentToken { return $script:Tokens[$script:Position] }
function Test-OtterTokenKind { param([TokenKind]$Kind) return (Get-OtterCurrentToken).Kind -eq $Kind }
function Test-OtterTokenOffsetKind {
    param([int]$Offset, [TokenKind]$Kind)
    $pos = $script:Position + $Offset
    if ($pos -ge 0 -and $pos -lt $script:Tokens.Count) {
        return $script:Tokens[$pos].Kind -eq $Kind
    }
    return $false
}
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
    param(
        [TokenKind]$Kind, 
        [string]$Message,
        [string]$Suggestion = 'Check the expected word and try again.'
    )
    $token = Get-OtterCurrentToken
    if ($token.Kind -ne $Kind) {
        $found = if ($token.Kind -eq [TokenKind]::EndOfFile) { 'end of file' } else { "'$($token.Text)'" }
        throw (New-OtterParserError "$Message I found $found instead." $token $Suggestion)
    }
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

function Test-OtterCommandResultPropertyAt {
    param([int]$Position)

    if ($Position -ge $script:Tokens.Count) { return $false }
    $first = $script:Tokens[$Position]
    if (-not (Test-OtterIdentifierToken $first)) { return $false }
    if (($Position + 2) -ge $script:Tokens.Count) { return $false }

    $second = $script:Tokens[$Position + 1]
    $third = $script:Tokens[$Position + 2]
    return (($first.Text -eq 'exit' -and $second.Text -eq 'code') -or
            ($first.Text -eq 'error' -and $second.Text -eq 'output')) -and
        $third.Kind -eq [TokenKind]::Of
}

function Read-OtterValue {
    param([switch]$PropertyTarget)
    $token = Get-OtterCurrentToken
    if ($token.Kind -eq [TokenKind]::Await) {
        [void](Read-OtterToken)
        $nextTok = Get-OtterCurrentToken
        if ($nextTok.Kind -eq [TokenKind]::Get -or $nextTok.Text -eq 'get') {
            [void](Read-OtterToken)
            $arg = Read-OtterValue
            $call = [CallExpr]::new('get', @($arg), $nextTok.Line)
            return [AwaitExpr]::new($call, $token.Line)
        }
        $expr = Read-OtterValue
        return [AwaitExpr]::new($expr, $token.Line)
    }
    if ($token.Kind -eq [TokenKind]::Not) {
        [void](Read-OtterToken)
        $operand = Read-OtterValue
        return [NotExpr]::new($operand, $token.Line)
    }
    # Optional readability word for property grammar only. `the` is consumed
    # when it introduces a real `<property> of ...` sequence; elsewhere it is
    # left untouched so this is not a global filler-word rule.
    if (($PropertyTarget -and $token.Text -eq 'the' -and ($script:Position + 1) -lt $script:Tokens.Count -and
        (Test-OtterIdentifierToken $script:Tokens[$script:Position + 1])) -or
        ($token.Text -eq 'the' -and ($script:Position + 2) -lt $script:Tokens.Count -and
        $script:Tokens[$script:Position + 1].Kind -in $script:OtterIdentifierKinds -and
        ($script:Tokens[$script:Position + 2].Kind -eq [TokenKind]::Of -or
         (Test-OtterCommandResultPropertyAt ($script:Position + 1))))) {
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
        return [OfOperationExpr]::new($operation, (Read-OtterValue -PropertyTarget), $token.Line)
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
    if (Test-OtterCommandResultPropertyAt $script:Position) {
        $first = Read-OtterToken
        $second = Read-OtterToken
        [void](Assert-OtterTokenKind ([TokenKind]::Of) 'I expected "of" after this command result property.')
        return [PropertyAccessExpr]::new("$($first.Text) $($second.Text)", (Read-OtterValue -PropertyTarget), $first.Line)
    }
    if (Test-OtterIdentifierToken $token) {
        [void](Read-OtterToken)
        if (Test-OtterTokenKind ([TokenKind]::Of)) {
            [void](Read-OtterToken)
            return [PropertyAccessExpr]::new($token.Text, (Read-OtterValue -PropertyTarget), $token.Line)
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
    # D78: `if registry key "HKCU:\Software\MyApp" exists`
    $maybeRegistry = Get-OtterCurrentToken
    if ($maybeRegistry.Kind -eq [TokenKind]::Identifier -and $maybeRegistry.Text -eq 'registry') {
        $registryToken = Read-OtterToken
        $keyWord = Get-OtterCurrentToken
        if ($keyWord.Kind -ne [TokenKind]::Identifier -or $keyWord.Text -ne 'key') {
            throw (New-OtterParserError 'I expected "key" after "registry".' $keyWord 'if registry key "HKCU:\Software\MyApp" exists')
        }
        [void](Read-OtterToken)
        $regKeyPath = Read-OtterValue
        [void](Assert-OtterTokenKind ([TokenKind]::Exists) 'I expected "exists" after the registry key path.')
        return [RegistryKeyExistsExpr]::new($regKeyPath, $registryToken.Line)
    }
    if (Test-OtterTokenKind ([TokenKind]::File)) {
        $fileToken = Read-OtterToken
        $path = Read-OtterValue
        if (Test-OtterTokenKind ([TokenKind]::Exists)) {
            [void](Read-OtterToken)
            return [FileExistsExpr]::new($path, $fileToken.Line)
        }
        # D72: `file "x" is locked`  /  D73: `file "x" is a symbolic link`
        # D74: `file "x" is read only`
        [void](Assert-OtterTokenKind ([TokenKind]::Is) 'I expected "exists", "is locked", "is read only", or "is a symbolic link" after the file path.')
        $afterIs = Get-OtterCurrentToken
        if ($afterIs.Kind -eq [TokenKind]::Identifier -and $afterIs.Text -eq 'locked') {
            [void](Read-OtterToken)
            return [FileLockedExpr]::new($path, $fileToken.Line)
        }
        if ($afterIs.Kind -eq [TokenKind]::Identifier -and $afterIs.Text -eq 'read') {
            [void](Read-OtterToken)
            $onlyWord2 = Get-OtterCurrentToken
            if ($onlyWord2.Kind -ne [TokenKind]::Identifier -or $onlyWord2.Text -ne 'only') {
                throw (New-OtterParserError 'I expected "only" after "read".' $onlyWord2 'file "x" is read only')
            }
            [void](Read-OtterToken)
            return [FileIsReadOnlyExpr]::new($path, $fileToken.Line)
        }
        [void](Assert-OtterTokenKind ([TokenKind]::A) 'I expected "locked", "read only", or "a symbolic link" after "is".')
        $symbolicWord = Get-OtterCurrentToken
        if ($symbolicWord.Kind -ne [TokenKind]::Identifier -or $symbolicWord.Text -ne 'symbolic') {
            throw (New-OtterParserError 'I expected "symbolic link" after "is a".' $symbolicWord 'file "x" is a symbolic link')
        }
        [void](Read-OtterToken)
        $linkWord3 = Get-OtterCurrentToken
        if ($linkWord3.Kind -ne [TokenKind]::Identifier -or $linkWord3.Text -ne 'link') {
            throw (New-OtterParserError 'I expected "link" after "symbolic".' $linkWord3 'file "x" is a symbolic link')
        }
        [void](Read-OtterToken)
        return [FileIsSymbolicLinkExpr]::new($path, $fileToken.Line)
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

function Read-OtterConditionContinuation {
    param([switch]$AllowContinuation)

    if (-not (Test-OtterTokenKind ([TokenKind]::Newline))) { return }
    if (-not $AllowContinuation) { return }

    # D38B: a header can cross a line only after a trailing `and` or `or`.
    # Its first continuation line must be one level deeper. Further condition
    # lines stay at that same level, sharing the indent that will later hold
    # the block body.
    if (-not $script:OtterConditionUsesContinuation) {
        if (-not (Test-OtterTokenOffsetKind 1 ([TokenKind]::Indent))) {
            $token = Get-OtterCurrentToken
            throw (New-OtterParserError 'I expected an indented condition continuation after this connective.' $token 'Indent the next condition line one level, or finish the condition on the same line.')
        }
        [void](Read-OtterToken) # Newline
        [void](Read-OtterToken) # Indent
        $script:OtterConditionUsesContinuation = $true
    } else {
        [void](Read-OtterToken) # Newline at the established continuation level
        if (Test-OtterTokenKind ([TokenKind]::Indent)) {
            $token = Get-OtterCurrentToken
            throw (New-OtterParserError 'I expected the continued condition to stay at its current indentation level.' $token 'Keep each continued condition line aligned with the first continuation line.')
        }
    }

    $next = Get-OtterCurrentToken
    if ($next.Kind -in @([TokenKind]::Newline, [TokenKind]::Dedent, [TokenKind]::BlockEnd, [TokenKind]::EndOfFile, [TokenKind]::And, [TokenKind]::Or)) {
        throw (New-OtterParserError 'I expected a condition after this connective.' $next 'Write a comparison or condition after "and" or "or".')
    }
}

function Read-OtterAndCondition {
    param([switch]$AllowContinuation)
    $left = Read-OtterConditionPrimary
    while (Test-OtterTokenKind ([TokenKind]::And)) {
        $operator = Read-OtterToken
        Read-OtterConditionContinuation -AllowContinuation:$AllowContinuation
        $left = [LogicalExpr]::new($left, [LogicalOp]::And, (Read-OtterConditionPrimary), $operator.Line)
    }
    return $left
}

function Read-OtterCondition {
    param([switch]$AllowContinuation)
    $left = Read-OtterAndCondition -AllowContinuation:$AllowContinuation
    while (Test-OtterTokenKind ([TokenKind]::Or)) {
        $operator = Read-OtterToken
        Read-OtterConditionContinuation -AllowContinuation:$AllowContinuation
        $left = [LogicalExpr]::new($left, [LogicalOp]::Or, (Read-OtterAndCondition -AllowContinuation:$AllowContinuation), $operator.Line)
    }
    return $left
}

function Read-OtterHeaderCondition {
    $script:OtterConditionUsesContinuation = $false
    return (Read-OtterCondition -AllowContinuation)
}

function Read-OtterConditionBlock {
    if (-not $script:OtterConditionUsesContinuation) { return Read-OtterBlock }

    # The continuation's Indent is already consumed. The next newline ends
    # the final condition line; the following statements are the real body at
    # that same indentation level.
    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the continued condition to end here.')
    $next = Get-OtterCurrentToken
    if ($next.Kind -in @([TokenKind]::Dedent, [TokenKind]::BlockEnd, [TokenKind]::EndOfFile)) {
        throw (New-OtterParserError 'I expected an indented block after this condition.' $next 'Add at least one statement after the continued condition.')
    }
    $script:OtterBlockDepth++
    try { $body = Read-OtterStatements }
    finally { $script:OtterBlockDepth-- }
    [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the indented block to end.')
    if (Test-OtterTokenKind ([TokenKind]::BlockEnd)) { [void](Read-OtterToken); Skip-OtterNewlines }
    return $body
}

function Read-OtterBlock {
    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the statement to end here.')
    [void](Assert-OtterTokenKind ([TokenKind]::Indent) 'I expected an indented block after this statement.')
    $script:OtterBlockDepth++
    try { $body = Read-OtterStatements }
    finally { $script:OtterBlockDepth-- }
    [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the indented block to end.')
    if (Test-OtterTokenKind ([TokenKind]::BlockEnd)) { [void](Read-OtterToken); Skip-OtterNewlines }
    return $body
}

# Contextual article support for resource-oriented statements only.  A lone
# `the` remains a valid identifier; consume it as an article only when a real
# name follows it in the same grammatical slot.
function Read-OtterOptionalTheBeforeName {
    if ((Get-OtterCurrentToken).Text -eq 'the' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and
        (Test-OtterIdentifierToken $script:Tokens[$script:Position + 1])) {
        [void](Read-OtterToken)
    }
}

# D41 narrows empty-block acceptance to object construction only. All control
# flow and function blocks continue through Read-OtterBlock and still require
# an actual indented body.
function Read-OtterObjectBlockProperties {
    param([bool]$AllowEmpty = $true, [string]$TypeName = '')

    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the object statement to end here.')
    if (-not (Test-OtterTokenKind ([TokenKind]::Indent))) {
        if ($AllowEmpty) {
            # Empty objects may still use the ordinary block terminator. Consume
            # it here so it cannot be left orphaned for the outer statement list.
            if (Test-OtterTokenKind ([TokenKind]::BlockEnd)) { [void](Read-OtterToken); Skip-OtterNewlines }
            return @()
        }
        $token = Get-OtterCurrentToken
        throw (New-OtterParserError 'I expected an indented block of properties.' $token 'Indent the properties under the object statement.')
    }
    [void](Read-OtterToken)

    $properties = [System.Collections.Generic.List[Node]]::new()
    Skip-OtterNewlines

    while (-not (Test-OtterTokenKind ([TokenKind]::Dedent)) -and 
           -not (Test-OtterTokenKind ([TokenKind]::EndOfFile)) -and 
           -not (Test-OtterTokenKind ([TokenKind]::BlockEnd))) {

        $cur = Get-OtterCurrentToken
        if ($cur.Kind -in @([TokenKind]::Say, [TokenKind]::If, [TokenKind]::While, [TokenKind]::Repeat, [TokenKind]::To, [TokenKind]::Return, [TokenKind]::Ask)) {
            throw (New-OtterParserError 'Only property assignments belong inside an object.' $cur 'Remove control flow or actions from this object block.')
        }

        $property = Read-OtterVariableName 'I expected a property name.'

        # 'is' is optional: both "property value" and "property is value" are valid
        $hadIs = $false
        if (Test-OtterTokenKind ([TokenKind]::Is)) {
            [void](Read-OtterToken)
            $hadIs = $true
        }

        $propName = $property.Text
        if (-not $hadIs -and (Get-OtterCurrentToken).Kind -in @([TokenKind]::Newline, [TokenKind]::EndOfFile, [TokenKind]::Dedent, [TokenKind]::BlockEnd)) {
            # D54: a bare property in a has block is boolean true.
            $value = [LiteralExpr]::new($true, $property.Line)
        } elseif ($property.Text -eq 'align') {
            $cur = Get-OtterCurrentToken
            $dir = $null
            if ($cur.Kind -eq [TokenKind]::Identifier -and $cur.Text -in @('top', 'middle', 'bottom', 'left', 'center', 'right')) {
                $dirTok = Read-OtterToken
                $dir = $dirTok.Text
                $value = [LiteralExpr]::new($dir, $dirTok.Line)
            } elseif ($cur.Kind -eq [TokenKind]::String -and $cur.Value -in @('top', 'middle', 'bottom', 'left', 'center', 'right')) {
                $dirTok = Read-OtterToken
                $dir = $dirTok.Value
                $value = [LiteralExpr]::new($dir, $dirTok.Line)
            } else {
                throw (New-OtterParserError "I expected an alignment direction (top, middle, bottom, left, center, right) after 'align', but got '$($cur.Text)'." $cur 'Use align top, align middle, align bottom, align left, align center, or align right.')
            }

        } elseif ($property.Text -in @('width', 'height') -and 
            (Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and 
            (Get-OtterCurrentToken).Text -eq 'full') {
            $fullTok = Read-OtterToken
            $value = [LiteralExpr]::new('full', $fullTok.Line)
        } elseif (-not $hadIs -and $property.Text -in @('round', 'spread')) {
            # Bare property name acts as a boolean flag (e.g. `round`, `spread`)
            $value = [LiteralExpr]::new($true, $property.Line)
        } else {
            if ((Get-OtterCurrentToken).Kind -in @([TokenKind]::Newline, [TokenKind]::EndOfFile, [TokenKind]::Dedent, [TokenKind]::BlockEnd)) {
                throw (New-OtterParserError "I expected a value for property '$($property.Text)'." (Get-OtterCurrentToken) "Provide a value after the property name, such as '$($property.Text) 10' or '$($property.Text) is 10'.")
            }
            $value = Read-OtterMathExpression
        }

        $properties.Add([AssignStmt]::new($propName, $value, $property.Line))

        $endTok = Get-OtterCurrentToken
        if ($endTok.Kind -ne [TokenKind]::Newline) {
            if ($endTok.Kind -eq [TokenKind]::Identifier -or $endTok.Kind -in @([TokenKind]::With, [TokenKind]::Is, [TokenKind]::String, [TokenKind]::Number)) {
                throw (New-OtterParserError "I expected each property on its own line, but found '$($endTok.Text)' on the same line." $endTok "Place '$($endTok.Text)' on a new indented line, or use 'with' to define inline properties separated by commas.")
            } else {
                throw (New-OtterParserError "I expected the property assignment to end here, but found '$($endTok.Text)'." $endTok "Place each property on its own line, or check for extra words at the end of the line.")
            }
        }
        [void](Read-OtterToken)
        Skip-OtterNewlines
    }

    [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the object block to end.')
    if (Test-OtterTokenKind ([TokenKind]::BlockEnd)) { [void](Read-OtterToken); Skip-OtterNewlines }
    return $properties.ToArray()
}

function Read-OtterObjectBlock {
    param([bool]$AllowEmpty = $true, [string]$TypeName = '')
    return (Read-OtterObjectBlockProperties -AllowEmpty $AllowEmpty -TypeName $TypeName)
}

function Read-OtterInlineObjectProperties {
    param([string]$TypeName = '')
    $properties = [System.Collections.Generic.List[Node]]::new()

    while ($true) {
        $property = Read-OtterVariableName 'I expected a property name after "has", "with", or a comma.'
        # Inline has and with are comma-delimited configuration lists.  `is` is
        # optional independently for each property, so compact, explicit,
        # and mixed styles all produce the same assignment nodes.
        $hadIs = $false
        if (Test-OtterTokenKind ([TokenKind]::Is)) {
            [void](Read-OtterToken)
            $hadIs = $true
        }

        $propName = $property.Text
        if (-not $hadIs -and ((Get-OtterCurrentToken).Text -eq ',' -or (Get-OtterCurrentToken).Kind -in @([TokenKind]::Newline, [TokenKind]::EndOfFile))) {
            # D54: a bare property in an inline has list is boolean true.
            $value = [LiteralExpr]::new($true, $property.Line)
        } elseif ($property.Text -eq 'align') {
            $cur = Get-OtterCurrentToken
            $dir = $null
            if ($cur.Kind -eq [TokenKind]::Identifier -and $cur.Text -in @('top', 'middle', 'bottom', 'left', 'center', 'right')) {
                $dirTok = Read-OtterToken
                $dir = $dirTok.Text
                $value = [LiteralExpr]::new($dir, $dirTok.Line)
            } elseif ($cur.Kind -eq [TokenKind]::String -and $cur.Value -in @('top', 'middle', 'bottom', 'left', 'center', 'right')) {
                $dirTok = Read-OtterToken
                $dir = $dirTok.Value
                $value = [LiteralExpr]::new($dir, $dirTok.Line)
            } else {
                throw (New-OtterParserError "I expected an alignment direction (top, middle, bottom, left, center, right) after 'align', but got '$($cur.Text)'." $cur 'Use align top, align middle, align bottom, align left, align center, or align right.')
            }

        } elseif ($property.Text -in @('width', 'height') -and 
            (Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and 
            (Get-OtterCurrentToken).Text -eq 'full') {
            $fullTok = Read-OtterToken
            $value = [LiteralExpr]::new('full', $fullTok.Line)
        } elseif (-not $hadIs -and $property.Text -in @('round', 'spread')) {
            # Bare property name acts as a boolean flag (e.g. `round`, `spread`)
            $value = [LiteralExpr]::new($true, $property.Line)
        } else {
            if ((Get-OtterCurrentToken).Text -eq ',' -or (Get-OtterCurrentToken).Kind -in @([TokenKind]::Newline, [TokenKind]::EndOfFile)) {
                throw (New-OtterParserError "I expected a value for property '$($property.Text)'." (Get-OtterCurrentToken) "Provide a value after the property name, such as '$($property.Text) 10' or '$($property.Text) is 10'.")
            }
            $value = Read-OtterMathExpression
        }

        $properties.Add([AssignStmt]::new($propName, $value, $property.Line))
        if ((Get-OtterCurrentToken).Text -ne ',') { break }
        [void](Read-OtterToken)
        if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Newline) {
            throw (New-OtterParserError 'I expected a property after the comma.' (Get-OtterCurrentToken) 'Add another property assignment after the comma.')
        }
    }

    $endTok = Get-OtterCurrentToken
    if ($endTok.Kind -ne [TokenKind]::Newline -and $endTok.Kind -ne [TokenKind]::EndOfFile) {
        if ($endTok.Kind -eq [TokenKind]::Identifier -or $endTok.Kind -in @([TokenKind]::With, [TokenKind]::Is, [TokenKind]::String, [TokenKind]::Number)) {
            throw (New-OtterParserError "I expected a comma between properties in this inline list, but found '$($endTok.Text)'." $endTok "Separate each property with a comma, such as '..., $($endTok.Text) ...'.")
        } else {
            throw (New-OtterParserError "I expected the inline properties to end here, but found '$($endTok.Text)'." $endTok "Separate properties with commas or end the line.")
        }
    }
    if ($endTok.Kind -eq [TokenKind]::Newline) {
        [void](Read-OtterToken)
    }
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
    while (-not (Test-OtterTokenKind ([TokenKind]::Newline)) -and -not (Test-OtterTokenKind ([TokenKind]::With))) {
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

function Read-OtterAnimationBlock {
    param([string]$Trigger, [int]$Line)
    
    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the animation header to end here.')
    [void](Assert-OtterTokenKind ([TokenKind]::Indent) 'I expected an indented animation block.')
    
    $steps = [System.Collections.Generic.List[UiAnimationStep]]::new()
    $durationMs = 300.0
    $easing = 'ease'
    
    Skip-OtterNewlines
    while (-not (Test-OtterTokenKind ([TokenKind]::Dedent)) -and -not (Test-OtterTokenKind ([TokenKind]::EndOfFile)) -and -not (Test-OtterTokenKind ([TokenKind]::BlockEnd))) {
        $cur = Get-OtterCurrentToken
        
        # Timing line: animate <duration> [<easing>]
        if ($cur.Kind -eq [TokenKind]::Animate -or $cur.Text -eq 'animate') {
            [void](Read-OtterToken)
            $durTok = Get-OtterCurrentToken
            if ($durTok.Kind -ne [TokenKind]::Number) {
                throw (New-OtterParserError "Otter expected a duration (e.g. '300ms') and optional easing ('ease', 'ease-out', 'ease-in', 'spring') after 'animate', but got '$($durTok.Text)'." $durTok "Write 'animate 300ms ease-out' or similar.")
            }
            $numVal = [double](Read-OtterToken).Value
            if ((Get-OtterCurrentToken).Text -eq 'ms') {
                [void](Read-OtterToken)
                $durationMs = $numVal
            } elseif ((Get-OtterCurrentToken).Text -eq 's') {
                [void](Read-OtterToken)
                $durationMs = $numVal * 1000.0
            } else {
                $durationMs = $numVal
            }
            
            if (-not (Test-OtterTokenKind ([TokenKind]::Newline))) {
                $easingTok = Read-OtterToken
                $easing = $easingTok.Text.ToLowerInvariant()
            }
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the animate statement to end here.')
            Skip-OtterNewlines
            continue
        }
        
        $opTok = Read-OtterToken
        $op = $opTok.Text.ToLowerInvariant()
        $dir = $null
        $amount = $null
        
        if ($op -eq 'fade') {
            if (-not (Test-OtterTokenKind ([TokenKind]::Newline))) {
                $dir = (Read-OtterToken).Text.ToLowerInvariant()
            }
        } elseif ($op -eq 'move') {
            if (-not (Test-OtterTokenKind ([TokenKind]::Newline))) {
                $dir = (Read-OtterToken).Text.ToLowerInvariant()
            }
            if (-not (Test-OtterTokenKind ([TokenKind]::Newline))) {
                $amount = Read-OtterMathExpression
            }
        } elseif ($op -eq 'slide') {
            $dirParts = [System.Collections.Generic.List[string]]::new()
            while (-not (Test-OtterTokenKind ([TokenKind]::Newline))) {
                $dirParts.Add((Read-OtterToken).Text.ToLowerInvariant())
            }
            $dir = $dirParts -join ' '
        } elseif ($op -in @('grow', 'shrink', 'scale', 'rotate')) {
            if (-not (Test-OtterTokenKind ([TokenKind]::Newline))) {
                $amount = Read-OtterMathExpression
            }
        }
        
        $steps.Add([UiAnimationStep]::new($op, $dir, $amount))
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the animation step to end here.')
        Skip-OtterNewlines
    }
    
    [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the animation block to end.')
    if (Test-OtterTokenKind ([TokenKind]::BlockEnd)) {
        [void](Read-OtterToken)
        Skip-OtterNewlines
    }
    
    return [UiAnimationBlock]::new($Trigger, $steps.ToArray(), $durationMs, $easing, $Line)
}

function Read-OtterUiElementStatement {
    $start = Get-OtterCurrentToken
    $variant = $null
    if ($start.Text -in @('primary', 'secondary', 'danger')) {
        $variant = (Read-OtterToken).Text
    }
    $tagToken = Read-OtterToken
    $tag = $tagToken.Text.ToLowerInvariant()
    
    $label = $null
    $name = $null
    
    if ($tag -eq 'input' -and -not (Test-OtterTokenKind ([TokenKind]::Newline)) -and (Test-OtterIdentifierToken (Get-OtterCurrentToken))) {
        $name = (Read-OtterToken).Text
    } elseif (-not (Test-OtterTokenKind ([TokenKind]::Newline))) {
        $label = Read-OtterMathExpression
    }
    
    $layout = [UiLayoutSpec]::new()
    $properties = [System.Collections.Generic.List[Node]]::new()
    $events = [System.Collections.Generic.List[Node]]::new()
    $animations = [System.Collections.Generic.List[Node]]::new()
    $children = [System.Collections.Generic.List[Node]]::new()
    
    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the UI element header to end here.')
    
    if (Test-OtterTokenKind ([TokenKind]::Indent)) {
        [void](Read-OtterToken)
        Skip-OtterNewlines
        while (-not (Test-OtterTokenKind ([TokenKind]::Dedent)) -and -not (Test-OtterTokenKind ([TokenKind]::EndOfFile)) -and -not (Test-OtterTokenKind ([TokenKind]::BlockEnd))) {
            $cur = Get-OtterCurrentToken
            
            if ($cur.Kind -eq [TokenKind]::Layout -or $cur.Text -eq 'layout') {
                [void](Read-OtterToken)
                $modeTok = Read-OtterToken
                $layout.Mode = $modeTok.Text.ToLowerInvariant()
                if ($layout.Mode -eq 'grid' -and -not (Test-OtterTokenKind ([TokenKind]::Newline))) {
                    $layout.Columns = Read-OtterMathExpression
                }
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the layout statement to end here.')
                Skip-OtterNewlines
                continue
            }
            if ($cur.Text -eq 'align') {
                [void](Read-OtterToken)
                $dirTok = Read-OtterToken
                $layout.Align = $dirTok.Text.ToLowerInvariant()
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the align statement to end here.')
                Skip-OtterNewlines
                continue
            }
            if ($cur.Kind -eq [TokenKind]::Gap -or $cur.Text -eq 'gap') {
                [void](Read-OtterToken)
                $layout.Gap = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the gap statement to end here.')
                Skip-OtterNewlines
                continue
            }
            if ($cur.Text -eq 'spread') {
                [void](Read-OtterToken)
                $layout.Spread = $true
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the spread statement to end here.')
                Skip-OtterNewlines
                continue
            }
            if ($cur.Text -eq 'columns' -and ($script:Position + 3) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 2].Text -eq 'on') {
                [void](Read-OtterToken)
                $colCount = (Read-OtterToken).Value
                [void](Read-OtterToken) # on
                $bp = (Read-OtterToken).Text
                $layout.Responsive += [ResponsiveRule]::new($bp, [int]$colCount, $false)
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the responsive rule to end here.')
                Skip-OtterNewlines
                continue
            }
            if ($cur.Text -eq 'stack' -and ($script:Position + 2) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Text -eq 'on') {
                [void](Read-OtterToken)
                [void](Read-OtterToken) # on
                $bp = (Read-OtterToken).Text
                $layout.Responsive += [ResponsiveRule]::new($bp, 1, $true)
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the responsive rule to end here.')
                Skip-OtterNewlines
                continue
            }
            
            if ($cur.Text -in @('round', 'background', 'placeholder', 'padding', 'margin', 'width', 'height')) {
                $propTok = Read-OtterToken
                $propVal = Read-OtterMathExpression
                $properties.Add([AssignStmt]::new($propTok.Text, $propVal, $propTok.Line))
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the property statement to end here.')
                Skip-OtterNewlines
                continue
            }
            
            if ($cur.Text -in @('enter', 'leave', 'hover', 'press') -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::Newline)) -and (Test-OtterTokenOffsetKind 2 ([TokenKind]::Indent))) {
                $triggerTok = Read-OtterToken
                $animBlock = Read-OtterAnimationBlock -Trigger $triggerTok.Text -Line $triggerTok.Line
                $animations.Add($animBlock)
                Skip-OtterNewlines
                continue
            }
            
            if ($cur.Text -in @('click', 'change', 'input', 'submit', 'hover', 'press', 'focus', 'blur') -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::Newline)) -and (Test-OtterTokenOffsetKind 2 ([TokenKind]::Indent))) {
                $evtTok = Read-OtterToken
                $evtBody = Read-OtterBlock
                $events.Add([UiEventStmt]::new($evtTok.Text, $evtBody, $evtTok.Line))
                Skip-OtterNewlines
                continue
            }
            
            $parsedChild = Read-OtterStatement
            if ($parsedChild -is [System.Array]) {
                foreach ($c in $parsedChild) { $children.Add($c) }
            } else {
                $children.Add($parsedChild)
            }
            Skip-OtterNewlines
        }
        [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the UI element block to end.')
        if (Test-OtterTokenKind ([TokenKind]::BlockEnd)) {
            [void](Read-OtterToken)
            Skip-OtterNewlines
        }
    }
    
    return [UiElementStmt]::new($tag, $variant, $label, $name, $layout, $properties.ToArray(), $events.ToArray(), $animations.ToArray(), $children.ToArray(), $start.Line)
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
    if (-not ($start.Kind -eq [TokenKind]::Count -and $script:OtterBlockDepth -eq 0) -and
        ((Test-OtterIdentifierToken $start) -or ($start.Kind -eq [TokenKind]::ForEach -and $start.Text -eq 'each')) -and
        $nextKind -in @([TokenKind]::Is, [TokenKind]::Are, [TokenKind]::Of, [TokenKind]::IsNot)) {
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

    $isVariant = ($start.Text -in @('primary', 'secondary', 'danger') -and ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Text.ToLowerInvariant() -in @('button', 'card', 'heading', 'text', 'panel', 'link', 'image', 'input'))
    $isUiTag = ($start.Text.ToLowerInvariant() -in @('window', 'page', 'card', 'heading', 'text', 'button', 'panel', 'section', 'sidebar', 'main', 'link', 'image', 'input', 'grid'))
    if ($isVariant -or ($isUiTag -and $nextKind -notin @([TokenKind]::Is, [TokenKind]::Are, [TokenKind]::Of, [TokenKind]::Has, [TokenKind]::Make, [TokenKind]::Into, [TokenKind]::IsNot))) {
        return Read-OtterUiElementStatement
    }

    switch ($statementKind) {
        ([TokenKind]::State) {
            [void](Read-OtterToken)
            $nameTok = Read-OtterVariableName 'I expected a variable name after "state".'
            [void](Assert-OtterTokenKind ([TokenKind]::Is) 'I expected "is" after the state variable name.')
            $val = Read-OtterMathExpression
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the state definition to end here.')
            return [StateDefStmt]::new($nameTok.Text, $val, $start.Line)
        }
        ([TokenKind]::Derive) {
            [void](Read-OtterToken)
            $nameTok = Read-OtterVariableName 'I expected a variable name after "derive".'
            [void](Assert-OtterTokenKind ([TokenKind]::Is) 'I expected "is" after the derived variable name.')
            $expr = Read-OtterMathExpression
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the derive statement to end here.')
            return [DeriveDefStmt]::new($nameTok.Text, $expr, $start.Line)
        }
        ([TokenKind]::Memo) {
            [void](Read-OtterToken)
            $nameTok = Read-OtterVariableName 'I expected a memo name after "memo".'
            return [MemoDefStmt]::new($nameTok.Text, (Read-OtterBlock), $start.Line)
        }
        ([TokenKind]::On) {
            [void](Read-OtterToken)
            $stageTok = Read-OtterToken
            if ($stageTok.Text -notin @('start', 'close')) {
                throw (New-OtterParserError "I expected 'start' or 'close' after 'on', but got '$($stageTok.Text)'." $stageTok "Write 'on start' or 'on close'.")
            }
            return [LifecycleStmt]::new($stageTok.Text, (Read-OtterBlock), $start.Line)
        }
        ([TokenKind]::Shared) {
            [void](Read-OtterToken)
            $nameTok = Read-OtterVariableName 'I expected a variable name after "shared".'
            [void](Assert-OtterTokenKind ([TokenKind]::Is) 'I expected "is" after the shared variable name.')
            $val = Read-OtterMathExpression
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the shared statement to end here.')
            return [SharedStateStmt]::new($nameTok.Text, $val, $start.Line)
        }
        ([TokenKind]::Use) {
            [void](Read-OtterToken)
            $modTok = Read-OtterToken
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the use statement to end here.')
            return [UseModuleStmt]::new($modTok.Text, $start.Line)
        }
        ([TokenKind]::Focus) {
            [void](Read-OtterToken)
            $target = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the focus statement to end here.')
            return [UiActionStmt]::new('focus', $target, $start.Line)
        }
        ([TokenKind]::Hide) {
            [void](Read-OtterToken)
            $target = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the hide statement to end here.')
            return [UiActionStmt]::new('hide', $target, $start.Line)
        }
        ([TokenKind]::Layout) {
            [void](Read-OtterToken)
            $modeTok = Read-OtterToken
            $mode = $modeTok.Text.ToLowerInvariant()
            $cols = $null
            if ($mode -eq 'grid' -and -not (Test-OtterTokenKind ([TokenKind]::Newline))) {
                $cols = Read-OtterMathExpression
            }
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the layout statement to end here.')
            $spec = [UiLayoutSpec]::new()
            $spec.Mode = $mode
            $spec.Columns = $cols
            return [UiElementStmt]::new('layout', $null, $null, $null, $spec, @(), @(), @(), @(), $start.Line)
        }
        ([TokenKind]::Say) {
            [void](Read-OtterToken)
            $parts = [System.Collections.Generic.List[Node]]::new()
            while (-not (Test-OtterTokenKind ([TokenKind]::Newline))) { $parts.Add((Read-OtterMathExpression)) }
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the say statement to end here.')
            return [SayStmt]::new($parts.ToArray(), $start.Line)
        }
        ([TokenKind]::If) {
            [void](Read-OtterToken)
            $branches = [System.Collections.Generic.List[IfBranch]]::new()
            $branches.Add([IfBranch]::new((Read-OtterHeaderCondition), (Read-OtterConditionBlock)))
            while ((Test-OtterTokenKind ([TokenKind]::Otherwise)) -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::If) {
                [void](Read-OtterToken); [void](Read-OtterToken)
                $branches.Add([IfBranch]::new((Read-OtterHeaderCondition), (Read-OtterConditionBlock)))
            }
            $elseBody = $null
            if (Test-OtterTokenKind ([TokenKind]::Otherwise)) { [void](Read-OtterToken); $elseBody = Read-OtterBlock }
            return [IfStmt]::new($branches.ToArray(), $elseBody, $start.Line)
        }
        ([TokenKind]::When) {
            [void](Read-OtterToken)
            if ((Get-OtterCurrentToken).Text -eq 'the' -and
                ($script:Position + 1) -lt $script:Tokens.Count -and
                (Test-OtterIdentifierToken $script:Tokens[$script:Position + 1])) {
                throw (New-OtterParserError 'Event targets do not use "the" here.' (Get-OtterCurrentToken) 'Write `when helloButton is clicked` without "the" before the resource name.')
            }
            $targetToken = Read-OtterVariableName 'I expected a resource name after "when".'
            $target = [VariableExpr]::new($targetToken.Text, $targetToken.Line)

            # D51: Web API route definition: when <server> receives <method> at <path> [into <request>]
            if (Test-OtterTokenKind ([TokenKind]::Receives)) {
                [void](Read-OtterToken)
                $method = 'GET'
                $cur = Get-OtterCurrentToken
                if ($cur.Kind -eq [TokenKind]::A) {
                    [void](Read-OtterToken)
                    $reqTok = Read-OtterToken
                    if ($reqTok.Text -ne 'request') {
                        throw (New-OtterParserError 'I expected "request" after "a".' $reqTok 'Write `when server receives a request at "/path"`.')
                    }
                    $method = 'ALL'
                } elseif ($cur.Kind -ne [TokenKind]::At -and $cur.Text -ne 'at') {
                    $methodToken = Read-OtterToken
                    $method = $methodToken.Text.ToUpperInvariant()
                }

                if (-not (Test-OtterTokenKind ([TokenKind]::At)) -and (Get-OtterCurrentToken).Text -ne 'at') {
                    throw (New-OtterParserError 'I expected "at" and a route path.' (Get-OtterCurrentToken) 'Write `at "/path"` after the method.')
                }
                [void](Read-OtterToken)
                $path = Read-OtterValue
                $requestTarget = $null
                if (Test-OtterTokenKind ([TokenKind]::Into)) {
                    [void](Read-OtterToken)
                    $requestTarget = (Read-OtterVariableName 'I expected a variable name after "into".').Text
                }
                return [WebRouteStmt]::new($target, $method, $path, $requestTarget, (Read-OtterBlock), $start.Line)
            }

            if (Test-OtterTokenKind ([TokenKind]::Is)) {
                [void](Read-OtterToken)
            }
            $eventToken = Get-OtterCurrentToken
            if ($eventToken.Kind -in @([TokenKind]::Newline, [TokenKind]::EndOfFile)) {
                throw (New-OtterParserError 'I expected an event name.' $eventToken 'Write an event such as "clicked" or "changed".')
            }
            [void](Read-OtterToken)
            if ($eventToken.Text -eq 'changes') {
                return [WatchStmt]::new($target.Name, (Read-OtterBlock), $start.Line)
            }
            return [WhenStmt]::new($target, $eventToken.Text, (Read-OtterBlock), $start.Line)
        }
        ([TokenKind]::Respond) {
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::With) 'I expected "with" after "respond".')
            $value = $null
            $status = $null
            $asJson = $false

            $cur = Get-OtterCurrentToken
            if ($cur.Text -eq 'status') {
                [void](Read-OtterToken)
                $status = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the respond statement to end here.')
                return [RespondStmt]::new($null, $status, $false, $start.Line)
            }

            $value = Read-OtterMathExpression

            if (Test-OtterTokenKind ([TokenKind]::As)) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Json) 'I expected "json" after "as".')
                $asJson = $true
            }

            if (Test-OtterTokenKind ([TokenKind]::And) -or Test-OtterTokenKind ([TokenKind]::With)) {
                $statusNext = if (($script:Position + 1) -lt $script:Tokens.Count) { $script:Tokens[$script:Position + 1] } else { $null }
                if ($null -ne $statusNext -and $statusNext.Text -eq 'status') {
                    [void](Read-OtterToken)
                    [void](Read-OtterToken)
                    $status = Read-OtterMathExpression
                }
            }

            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the respond statement to end here.')
            return [RespondStmt]::new($value, $status, $asJson, $start.Line)
        }
        ([TokenKind]::Start) {
            [void](Read-OtterToken)
            Read-OtterOptionalTheBeforeName
            $targetToken = Read-OtterVariableName 'I expected a server name after "start".'
            $target = [VariableExpr]::new($targetToken.Text, $targetToken.Line)
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the start statement to end here.')
            return [StartServerStmt]::new($target, $start.Line)
        }
        ([TokenKind]::Listen) {
            [void](Read-OtterToken)
            if ((Get-OtterCurrentToken).Text -eq 'on') {
                [void](Read-OtterToken)
            }
            if ((Get-OtterCurrentToken).Text -eq 'port') {
                [void](Read-OtterToken)
                $port = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the listen statement to end here.')
                return [ListenServerStmt]::new($port, $start.Line)
            }
            $targetToken = Read-OtterVariableName 'I expected "on port <number>" or a server name after "listen".'
            $target = [VariableExpr]::new($targetToken.Text, $targetToken.Line)
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the listen statement to end here.')
            return [StartServerStmt]::new($target, $start.Line)
        }
        ([TokenKind]::Post) {
            [void](Read-OtterToken)
            $data = Read-OtterValue
            $asJson = $false
            if (Test-OtterTokenKind ([TokenKind]::As)) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Json) 'I expected "json" after "as".')
                $asJson = $true
            }
            [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a URL after post data.')
            $url = Read-OtterValue
            $target = $null
            $continued = Test-OtterSoftContinuation
            if (Test-OtterTokenKind ([TokenKind]::Into)) {
                [void](Read-OtterToken)
                $targetToken = Read-OtterVariableName 'I expected a result name after "into".'
                $target = $targetToken.Text
            }
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the post statement to end here.')
            if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued post clause to end.') }
            return [HttpPostStmt]::new($data, $url, $target, $asJson, $start.Line)
        }
        ([TokenKind]::Put) {
            [void](Read-OtterToken)
            $items = [System.Collections.Generic.List[Node]]::new()
            Read-OtterOptionalTheBeforeName
            $firstItem = Read-OtterValue
            if (Test-OtterTokenKind ([TokenKind]::As)) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Json) 'I expected "json" after "as".')
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a URL after put data.')
                $url = Read-OtterValue
                $target = $null
                $continued = Test-OtterSoftContinuation
                if (Test-OtterTokenKind ([TokenKind]::Into)) {
                    [void](Read-OtterToken)
                    $targetToken = Read-OtterVariableName 'I expected a result name after "into".'
                    $target = $targetToken.Text
                }
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the put statement to end here.')
                if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued put clause to end.') }
                return [HttpPutStmt]::new($firstItem, $url, $target, $true, $start.Line)
            }
            if (Test-OtterTokenKind ([TokenKind]::To)) {
                [void](Read-OtterToken)
                $url = Read-OtterValue
                $target = $null
                $continued = Test-OtterSoftContinuation
                if (Test-OtterTokenKind ([TokenKind]::Into)) {
                    [void](Read-OtterToken)
                    $targetToken = Read-OtterVariableName 'I expected a result name after "into".'
                    $target = $targetToken.Text
                }
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the put statement to end here.')
                if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued put clause to end.') }
                return [HttpPutStmt]::new($firstItem, $url, $target, $false, $start.Line)
            }
            $items.Add($firstItem)
            while ((Get-OtterCurrentToken).Text -eq ',') {
                [void](Read-OtterToken)
                $next = Get-OtterCurrentToken
                if ($next.Text -eq ',' -or $next.Kind -eq [TokenKind]::In -or $next.Kind -eq [TokenKind]::Newline) {
                    throw (New-OtterParserError 'I expected a resource name after the comma.' $next 'Write another resource name after each comma.')
                }
                Read-OtterOptionalTheBeforeName
                $items.Add((Read-OtterValue))
            }
            [void](Assert-OtterTokenKind ([TokenKind]::In) 'I expected "in" before the container.')
            Read-OtterOptionalTheBeforeName
            $containerToken = Read-OtterVariableName 'I expected a resource name after "in".'
            $container = [VariableExpr]::new($containerToken.Text, $containerToken.Line)
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the put statement to end here.')
            $desugared = [System.Collections.Generic.List[Node]]::new()
            foreach ($item in $items) { $desugared.Add([PutInStmt]::new($item, $container, $start.Line)) }
            return $desugared.ToArray()
        }
        ([TokenKind]::Show) {
            [void](Read-OtterToken)
            Read-OtterOptionalTheBeforeName
            $targetToken = Read-OtterVariableName 'I expected a resource name after "show".'
            $target = [VariableExpr]::new($targetToken.Text, $targetToken.Line)
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the show statement to end here.')
            return [ShowStmt]::new($target, $start.Line)
        }
        ([TokenKind]::While) {
            [void](Read-OtterToken)
            return [WhileStmt]::new((Read-OtterHeaderCondition), (Read-OtterConditionBlock), $start.Line)
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
            # D67: `get clipboard into text` - "clipboard" stays an
            # ORDINARY IDENTIFIER, matched by text, the same way
            # "files"/"folders"/"item" are handled elsewhere in this
            # grammar rather than reserving another keyword.
            if ($kind.Kind -eq [TokenKind]::Identifier -and $kind.Text -eq 'clipboard') {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $target = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                return [GetClipboardStmt]::new($target.Text, $start.Line)
            }
            # D67: `get environment variable "PATH" into value` -
            # "environment" and "variable" are both ordinary identifiers.
            if ($kind.Kind -eq [TokenKind]::Identifier -and $kind.Text -eq 'environment') {
                [void](Read-OtterToken)
                $variableWord = Get-OtterCurrentToken
                if ($variableWord.Kind -ne [TokenKind]::Identifier -or $variableWord.Text -ne 'variable') {
                    throw (New-OtterParserError 'I expected "variable" after "environment".' $variableWord 'get environment variable "PATH" into value')
                }
                [void](Read-OtterToken)
                $name = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $target = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                return [GetEnvironmentVariableStmt]::new($name, $target.Text, $start.Line)
            }
            # D67: `get system folder "temp" into path` - "system" is an
            # ordinary identifier; "folder" reuses the existing token.
            if ($kind.Kind -eq [TokenKind]::Identifier -and $kind.Text -eq 'system') {
                [void](Read-OtterToken)
                if (Test-OtterTokenKind ([TokenKind]::Folder)) {
                    [void](Read-OtterToken)
                    $folderName = Read-OtterValue
                    [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                    $target = Read-OtterVariableName 'I expected a result name after "into".'
                    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                    return [GetSystemFolderStmt]::new($folderName, $target.Text, $start.Line)
                }
                # D69: `get system information "os" into info` - "information"
                # is an ordinary identifier too; the kind ("os"/"cpu"/
                # "memory"/"disk"/"network") is a plain string VALUE, matched
                # by text, not a reserved word - same design as FolderName.
                $infoWord = Get-OtterCurrentToken
                if ($infoWord.Kind -ne [TokenKind]::Identifier -or $infoWord.Text -ne 'information') {
                    throw (New-OtterParserError 'I expected "folder" or "information" after "system".' $infoWord 'get system information "os" into info')
                }
                [void](Read-OtterToken)
                $infoKind = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $target = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                return [GetSystemInfoStmt]::new($infoKind, $target.Text, $start.Line)
            }
            # D70: `get processes into list` - "processes" is an ordinary
            # identifier, same design as "system"/"clipboard" above.
            if ($kind.Kind -eq [TokenKind]::Identifier -and $kind.Text -eq 'processes') {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $target = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                return [GetProcessesStmt]::new($target.Text, $start.Line)
            }
            # D73: `get symbolic link target of "l" into t`
            if ($kind.Kind -eq [TokenKind]::Identifier -and $kind.Text -eq 'symbolic') {
                [void](Read-OtterToken)
                $linkWord2 = Get-OtterCurrentToken
                if ($linkWord2.Kind -ne [TokenKind]::Identifier -or $linkWord2.Text -ne 'link') {
                    throw (New-OtterParserError 'I expected "link" after "symbolic".' $linkWord2 'get symbolic link target of "l" into t')
                }
                [void](Read-OtterToken)
                $targetWord = Get-OtterCurrentToken
                if ($targetWord.Kind -ne [TokenKind]::Identifier -or $targetWord.Text -ne 'target') {
                    throw (New-OtterParserError 'I expected "target" after "link".' $targetWord 'get symbolic link target of "l" into t')
                }
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Of) 'I expected "of" and a link path.')
                $linkPath2 = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $target2 = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                return [GetSymbolicLinkTargetStmt]::new($linkPath2, $target2.Text, $start.Line)
            }
            # D74: `get owner of "x" into owner`
            if ($kind.Kind -eq [TokenKind]::Identifier -and $kind.Text -eq 'owner') {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Of) 'I expected "of" and a file path.')
                $ownerPath = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $ownerTarget = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                return [GetFileOwnerStmt]::new($ownerPath, $ownerTarget.Text, $start.Line)
            }
            # D78: `get registry value "n" from "path" into t`
            if ($kind.Kind -eq [TokenKind]::Identifier -and $kind.Text -eq 'registry') {
                [void](Read-OtterToken)
                $regValueWord = Get-OtterCurrentToken
                if ($regValueWord.Kind -ne [TokenKind]::Identifier -or $regValueWord.Text -ne 'value') {
                    throw (New-OtterParserError 'I expected "value" after "registry".' $regValueWord 'get registry value "n" from "path" into t')
                }
                [void](Read-OtterToken)
                $regValueName = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a registry key path.')
                $regKeyPathGet = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $regTarget = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                return [GetRegistryValueStmt]::new($regValueName, $regKeyPathGet, $regTarget.Text, $start.Line)
            }
            # D81: `get credential "n" into secret`
            if ($kind.Kind -eq [TokenKind]::Identifier -and $kind.Text -eq 'credential') {
                [void](Read-OtterToken)
                $credName = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $credTarget = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                return [GetCredentialStmt]::new($credName, $credTarget.Text, $start.Line)
            }
            # D79: `get event log entries from "System" up to 20 into t`
            if ($kind.Kind -eq [TokenKind]::Identifier -and $kind.Text -eq 'event') {
                [void](Read-OtterToken)
                $logWord = Get-OtterCurrentToken
                if ($logWord.Kind -ne [TokenKind]::Identifier -or $logWord.Text -ne 'log') {
                    throw (New-OtterParserError 'I expected "log" after "event".' $logWord 'get event log entries from "System" up to 20 into entries')
                }
                [void](Read-OtterToken)
                $entriesWord = Get-OtterCurrentToken
                if ($entriesWord.Kind -ne [TokenKind]::Identifier -or $entriesWord.Text -ne 'entries') {
                    throw (New-OtterParserError 'I expected "entries" after "log".' $entriesWord 'get event log entries from "System" up to 20 into entries')
                }
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a log name.')
                $logName = Read-OtterValue
                $upWord2 = Get-OtterCurrentToken
                if ($upWord2.Kind -ne [TokenKind]::Identifier -or $upWord2.Text -ne 'up') {
                    throw (New-OtterParserError 'I expected "up to" and a maximum count.' $upWord2 'get event log entries from "System" up to 20 into entries')
                }
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a maximum count.')
                $maxEntries = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $eventTarget = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                return [GetEventLogEntriesStmt]::new($logName, $maxEntries, $eventTarget.Text, $start.Line)
            }
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
            if ($kind.Kind -eq [TokenKind]::Json) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a URL after "get json".')
                $url = Read-OtterValue
                $continued = Test-OtterSoftContinuation
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $target = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued get clause to end.') }
                return [HttpGetStmt]::new($url, $target.Text, $true, $start.Line)
            }
            # D41 dynamic key access OR HTTP GET
            $first = Read-OtterValue
            if (Test-OtterTokenKind ([TokenKind]::From)) {
                [void](Read-OtterToken)
                $target = Read-OtterValue
                $continued = Test-OtterSoftContinuation
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $result = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued get clause to end.') }
                return [GetKeyStmt]::new($first, $target, $result.Text, $start.Line)
            }
            $asJson = $false
            if (Test-OtterTokenKind ([TokenKind]::As)) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Json) 'I expected "json" after "as".')
                $asJson = $true
            }
            $continued = Test-OtterSoftContinuation
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "from" or "into" after the value.')
            $result = Read-OtterVariableName 'I expected a result name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
            if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued get clause to end.') }
            return [HttpGetStmt]::new($first, $result.Text, $asJson, $start.Line)
        }
        ([TokenKind]::Set) {
            [void](Read-OtterToken)
            # D71: `set priority of process p to "high"` - checked as plain
            # identifier text BEFORE the generic dynamic-key path below,
            # since "priority" is not something Read-OtterValue would ever
            # otherwise stop at.
            $maybePriority = Get-OtterCurrentToken
            if ($maybePriority.Kind -eq [TokenKind]::Identifier -and $maybePriority.Text -eq 'priority') {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Of) 'I expected "of process" after "priority".')
                $processWord = Get-OtterCurrentToken
                if ($processWord.Kind -ne [TokenKind]::Identifier -or $processWord.Text -ne 'process') {
                    throw (New-OtterParserError 'I expected "process" after "of".' $processWord 'set priority of process p to "high"')
                }
                [void](Read-OtterToken)
                $processExpr = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a priority level.')
                $priority = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the set statement to end here.')
                return [SetProcessPriorityStmt]::new($processExpr, $priority, $start.Line)
            }
            # D74: `set file "x" to read only` / `set file "x" to writable`
            if (Test-OtterTokenKind ([TokenKind]::File)) {
                [void](Read-OtterToken)
                $roPath = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and "read only" or "writable".')
                $roWord = Get-OtterCurrentToken
                $readOnly = $false
                if ($roWord.Kind -eq [TokenKind]::Identifier -and $roWord.Text -eq 'read') {
                    [void](Read-OtterToken)
                    $onlyWord = Get-OtterCurrentToken
                    if ($onlyWord.Kind -ne [TokenKind]::Identifier -or $onlyWord.Text -ne 'only') {
                        throw (New-OtterParserError 'I expected "only" after "read".' $onlyWord 'set file "x" to read only')
                    }
                    [void](Read-OtterToken)
                    $readOnly = $true
                } elseif ($roWord.Kind -eq [TokenKind]::Identifier -and $roWord.Text -eq 'writable') {
                    [void](Read-OtterToken)
                    $readOnly = $false
                } else {
                    throw (New-OtterParserError 'I expected "read only" or "writable" after "to".' $roWord 'set file "x" to read only')
                }
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the set statement to end here.')
                return [SetFileReadOnlyStmt]::new($roPath, $readOnly, $start.Line)
            }
            # D78: `set registry value "n" to "d" in "path"`
            $maybeRegistrySet = Get-OtterCurrentToken
            if ($maybeRegistrySet.Kind -eq [TokenKind]::Identifier -and $maybeRegistrySet.Text -eq 'registry') {
                [void](Read-OtterToken)
                $regValueWordSet = Get-OtterCurrentToken
                if ($regValueWordSet.Kind -ne [TokenKind]::Identifier -or $regValueWordSet.Text -ne 'value') {
                    throw (New-OtterParserError 'I expected "value" after "registry".' $regValueWordSet 'set registry value "n" to "d" in "path"')
                }
                [void](Read-OtterToken)
                $regValueNameSet = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a value.')
                $regValueData = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::In) 'I expected "in" and a registry key path.')
                $regKeyPathSet = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the set statement to end here.')
                return [SetRegistryValueStmt]::new($regValueNameSet, $regValueData, $regKeyPathSet, $start.Line)
            }
            # D81: `set credential "n" to "secret"`
            $maybeCredentialSet = Get-OtterCurrentToken
            if ($maybeCredentialSet.Kind -eq [TokenKind]::Identifier -and $maybeCredentialSet.Text -eq 'credential') {
                [void](Read-OtterToken)
                $credNameSet = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a secret value.')
                $credSecret = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the set statement to end here.')
                return [SetCredentialStmt]::new($credNameSet, $credSecret, $start.Line)
            }
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
            # D73: `create symbolic link "l" pointing to "t"` - checked
            # as plain identifier text before the generic UI-resource
            # path below, same technique as the Folder check above.
            $maybeSymbolic = Get-OtterCurrentToken
            if ($maybeSymbolic.Kind -eq [TokenKind]::Identifier -and $maybeSymbolic.Text -eq 'symbolic') {
                [void](Read-OtterToken)
                $linkWord = Get-OtterCurrentToken
                if ($linkWord.Kind -ne [TokenKind]::Identifier -or $linkWord.Text -ne 'link') {
                    throw (New-OtterParserError 'I expected "link" after "symbolic".' $linkWord 'create symbolic link "l" pointing to "t"')
                }
                [void](Read-OtterToken)
                $linkPath = Read-OtterValue
                $pointingWord = Get-OtterCurrentToken
                if ($pointingWord.Kind -ne [TokenKind]::Identifier -or $pointingWord.Text -ne 'pointing') {
                    throw (New-OtterParserError 'I expected "pointing to" and a target path.' $pointingWord 'create symbolic link "l" pointing to "t"')
                }
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a target path.')
                $targetPath = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the create statement to end here.')
                return [CreateSymbolicLinkStmt]::new($linkPath, $targetPath, $start.Line)
            }
            # `the` is an article here only when another kind word follows;
            # `create the into x` keeps `the` as the raw resource kind.
            if ((Get-OtterCurrentToken).Text -eq 'the' -and
                ($script:Position + 1) -lt $script:Tokens.Count -and
                (Test-OtterIdentifierToken $script:Tokens[$script:Position + 1])) {
                [void](Read-OtterToken)
            }
            $typeName = Read-OtterUiResourceTypeName
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a resource variable name.')
            Read-OtterOptionalTheBeforeName
            $target = Read-OtterVariableName 'I expected a variable name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the create statement to end here.')
            return [CreateUiResourceStmt]::new($typeName, $target.Text, $start.Line)
        }
        ([TokenKind]::Try) {
            [void](Read-OtterToken)
            $body = Read-OtterBlock
            $otherwiseBody = $null
            $errorTarget = $null
            if (Test-OtterTokenKind ([TokenKind]::Otherwise)) {
                [void](Read-OtterToken)
                # D68: `otherwise into reason` - optional; plain `otherwise`
                # still works unchanged for every existing program.
                if (Test-OtterTokenKind ([TokenKind]::Into)) {
                    [void](Read-OtterToken)
                    $errorTarget = (Read-OtterVariableName 'I expected a variable name after "into".').Text
                }
                $otherwiseBody = Read-OtterBlock
            }
            return [TryStmt]::new($body, $otherwiseBody, $errorTarget, $start.Line)
        }
        # fail with "message"                                           (D68)
        ([TokenKind]::Fail) {
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::With) 'I expected "with" and a message.')
            $message = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the fail statement to end here.')
            return [FailStmt]::new($message, $start.Line)
        }
        # kill process p                                                (D70)
        # kill process p and its children
        ([TokenKind]::Kill) {
            [void](Read-OtterToken)
            $processWord = Get-OtterCurrentToken
            if ($processWord.Kind -ne [TokenKind]::Identifier -or $processWord.Text -ne 'process') {
                throw (New-OtterParserError 'I expected "process" after "kill".' $processWord 'kill process p')
            }
            [void](Read-OtterToken)
            $processExpr = Read-OtterValue
            $includeChildren = $false
            if (Test-OtterTokenKind ([TokenKind]::And)) {
                [void](Read-OtterToken)
                $itsWord = Get-OtterCurrentToken
                if ($itsWord.Kind -ne [TokenKind]::Identifier -or $itsWord.Text -ne 'its') {
                    throw (New-OtterParserError 'I expected "its children" after "and".' $itsWord 'kill process p and its children')
                }
                [void](Read-OtterToken)
                $childrenWord = Get-OtterCurrentToken
                if ($childrenWord.Kind -ne [TokenKind]::Identifier -or $childrenWord.Text -ne 'children') {
                    throw (New-OtterParserError 'I expected "children" after "its".' $childrenWord 'kill process p and its children')
                }
                [void](Read-OtterToken)
                $includeChildren = $true
            }
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the kill statement to end here.')
            return [KillProcessStmt]::new($processExpr, $includeChildren, $start.Line)
        }
        # wait for process p up to 5 seconds [into finished]            (D71)
        ([TokenKind]::Wait) {
            [void](Read-OtterToken)
            $forWord = Get-OtterCurrentToken
            if ($forWord.Kind -ne [TokenKind]::Identifier -or $forWord.Text -ne 'for') {
                throw (New-OtterParserError 'I expected "for process" after "wait".' $forWord 'wait for process p up to 5 seconds')
            }
            [void](Read-OtterToken)
            $processWord2 = Get-OtterCurrentToken
            if ($processWord2.Kind -ne [TokenKind]::Identifier -or $processWord2.Text -ne 'process') {
                throw (New-OtterParserError 'I expected "process" after "for".' $processWord2 'wait for process p up to 5 seconds')
            }
            [void](Read-OtterToken)
            $waitProcessExpr = Read-OtterValue
            $upWord = Get-OtterCurrentToken
            if ($upWord.Kind -ne [TokenKind]::Identifier -or $upWord.Text -ne 'up') {
                throw (New-OtterParserError 'I expected "up to" and a number of seconds.' $upWord 'wait for process p up to 5 seconds')
            }
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a number of seconds.')
            $seconds = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Second) 'I expected "seconds" after the number.')
            $waitTarget = $null
            if (Test-OtterTokenKind ([TokenKind]::Into)) {
                [void](Read-OtterToken)
                $waitTarget = (Read-OtterVariableName 'I expected a result name after "into".').Text
            }
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the wait statement to end here.')
            return [WaitForProcessStmt]::new($waitProcessExpr, $seconds, $waitTarget, $start.Line)
        }
        # lock the computer                                             (D82)
        ([TokenKind]::Lock) {
            [void](Read-OtterToken)
            Read-OtterOptionalTheBeforeName
            $computerWord = Get-OtterCurrentToken
            if ($computerWord.Kind -ne [TokenKind]::Identifier -or $computerWord.Text -ne 'computer') {
                throw (New-OtterParserError 'I expected "the computer" after "lock".' $computerWord 'lock the computer')
            }
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the lock statement to end here.')
            return [PowerActionStmt]::new('lock', $start.Line)
        }
        # sign out                                                      (D82)
        ([TokenKind]::Sign) {
            [void](Read-OtterToken)
            $outWord = Get-OtterCurrentToken
            if ($outWord.Kind -ne [TokenKind]::Identifier -or $outWord.Text -ne 'out') {
                throw (New-OtterParserError 'I expected "out" after "sign".' $outWord 'sign out')
            }
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the sign out statement to end here.')
            return [PowerActionStmt]::new('signOut', $start.Line)
        }
        # restart the computer                                         (D82)
        ([TokenKind]::Restart) {
            [void](Read-OtterToken)
            Read-OtterOptionalTheBeforeName
            $computerWord2 = Get-OtterCurrentToken
            if ($computerWord2.Kind -ne [TokenKind]::Identifier -or $computerWord2.Text -ne 'computer') {
                throw (New-OtterParserError 'I expected "the computer" after "restart".' $computerWord2 'restart the computer')
            }
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the restart statement to end here.')
            return [PowerActionStmt]::new('restart', $start.Line)
        }
        # shut down the computer                                       (D82)
        ([TokenKind]::Shut) {
            [void](Read-OtterToken)
            $downWord = Get-OtterCurrentToken
            if ($downWord.Kind -ne [TokenKind]::Identifier -or $downWord.Text -ne 'down') {
                throw (New-OtterParserError 'I expected "down" after "shut".' $downWord 'shut down the computer')
            }
            [void](Read-OtterToken)
            Read-OtterOptionalTheBeforeName
            $computerWord3 = Get-OtterCurrentToken
            if ($computerWord3.Kind -ne [TokenKind]::Identifier -or $computerWord3.Text -ne 'computer') {
                throw (New-OtterParserError 'I expected "the computer" after "shut down".' $computerWord3 'shut down the computer')
            }
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the shut down statement to end here.')
            return [PowerActionStmt]::new('shutDown', $start.Line)
        }
        # print "file.txt" to "PrinterName"                             (D83)
        ([TokenKind]::Print) {
            [void](Read-OtterToken)
            $printPath = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a printer name.')
            $printerName = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the print statement to end here.')
            return [PrintFileStmt]::new($printPath, $printerName, $start.Line)
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
            # D72: `write "x" to "path" atomically` - optional trailing
            # qualifier; plain `write ... to ...` is unchanged.
            $atomic = $false
            $atomicWord = Get-OtterCurrentToken
            if ($atomicWord.Kind -eq [TokenKind]::Identifier -and $atomicWord.Text -eq 'atomically') {
                [void](Read-OtterToken)
                $atomic = $true
            }
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the write statement to end here.')
            return [WriteFileStmt]::new($content, $path, $atomic, $start.Line)
        }
        ([TokenKind]::Append) {
            [void](Read-OtterToken)
            $content = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a file path.')
            $path = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the append statement to end here.')
            return [AppendFileStmt]::new($content, $path, $start.Line)
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
            # D67: `copy "text" to clipboard` - checked as a plain
            # identifier BEFORE calling Read-OtterValue for a normal file
            # destination, since Read-OtterValue would otherwise happily
            # consume "clipboard" as a bare variable reference.
            $maybeClipboard = Get-OtterCurrentToken
            if ($maybeClipboard.Kind -eq [TokenKind]::Identifier -and $maybeClipboard.Text -eq 'clipboard') {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the copy statement to end here.')
                return [CopyToClipboardStmt]::new($source, $start.Line)
            }
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
            # D78: `delete registry value "n" from "path"`
            $maybeRegistryDel = Get-OtterCurrentToken
            if ($maybeRegistryDel.Kind -eq [TokenKind]::Identifier -and $maybeRegistryDel.Text -eq 'registry') {
                [void](Read-OtterToken)
                $regValueWordDel = Get-OtterCurrentToken
                if ($regValueWordDel.Kind -ne [TokenKind]::Identifier -or $regValueWordDel.Text -ne 'value') {
                    throw (New-OtterParserError 'I expected "value" after "registry".' $regValueWordDel 'delete registry value "n" from "path"')
                }
                [void](Read-OtterToken)
                $regValueNameDel = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a registry key path.')
                $regKeyPathDel = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the delete statement to end here.')
                return [DeleteRegistryValueStmt]::new($regValueNameDel, $regKeyPathDel, $start.Line)
            }
            # D81: `delete credential "n"`
            $maybeCredentialDel = Get-OtterCurrentToken
            if ($maybeCredentialDel.Kind -eq [TokenKind]::Identifier -and $maybeCredentialDel.Text -eq 'credential') {
                [void](Read-OtterToken)
                $credNameDel = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the delete statement to end here.')
                return [DeleteCredentialStmt]::new($credNameDel, $start.Line)
            }
            if (Test-OtterTokenKind ([TokenKind]::Folder)) {
                [void](Read-OtterToken)
                $path = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the delete statement to end here.')
                return [DeleteFolderStmt]::new($path, $start.Line)
            }
            if (Test-OtterTokenKind ([TokenKind]::From)) {
                [void](Read-OtterToken)
                $url = Read-OtterValue
                $target = $null
                $continued = Test-OtterSoftContinuation
                if (Test-OtterTokenKind ([TokenKind]::Into)) {
                    [void](Read-OtterToken)
                    $targetToken = Read-OtterVariableName 'I expected a result name after "into".'
                    $target = $targetToken.Text
                }
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the delete statement to end here.')
                if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued delete clause to end.') }
                return [HttpDeleteStmt]::new($url, $target, $start.Line)
            }
            [void](Assert-OtterTokenKind ([TokenKind]::File) 'I expected "file" after delete.')
            $path = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the delete statement to end here.')
            return [DeleteFileStmt]::new($path, $start.Line)
        }
        # notify "Title" with "Message"                                (D67)
        ([TokenKind]::Notify) {
            [void](Read-OtterToken)
            $title = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::With) 'I expected "with" and a message.')
            $message = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the notify statement to end here.')
            return [NotifyStmt]::new($title, $message, $start.Line)
        }
        # choose file into path         / choose folder into path      (D67)
        # choose file to save into path
        ([TokenKind]::Choose) {
            [void](Read-OtterToken)
            if (Test-OtterTokenKind ([TokenKind]::Folder)) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $target = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the choose statement to end here.')
                return [ChooseFolderStmt]::new($target.Text, $start.Line)
            }
            [void](Assert-OtterTokenKind ([TokenKind]::File) 'I expected "file" or "folder" after "choose".')
            if (Test-OtterTokenKind ([TokenKind]::To)) {
                [void](Read-OtterToken)
                $saveWord = Get-OtterCurrentToken
                if ($saveWord.Kind -ne [TokenKind]::Identifier -or $saveWord.Text -ne 'save') {
                    throw (New-OtterParserError 'I expected "save" after "to".' $saveWord 'choose file to save into path')
                }
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $target = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the choose statement to end here.')
                return [ChooseSaveFileStmt]::new($target.Text, $start.Line)
            }
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
            $target = Read-OtterVariableName 'I expected a result name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the choose statement to end here.')
            return [ChooseFileStmt]::new($target.Text, $start.Line)
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
                $properties = if (Test-OtterTokenKind ([TokenKind]::Newline)) { Read-OtterObjectBlockProperties -AllowEmpty $true } else { Read-OtterInlineObjectProperties }
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
                    if (Test-OtterTokenKind ([TokenKind]::With)) {
                        [void](Read-OtterToken)
                        $properties = Read-OtterInlineObjectProperties -TypeName $typeName
                    } elseif ($typeName -eq 'thing' -or -not $script:KnownTypes.ContainsKey($typeName)) {
                        $properties = Read-OtterObjectBlockProperties -AllowEmpty ($typeName -eq 'thing') -TypeName $typeName
                    } else {
                        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the object definition to end here.')
                        $properties = @()
                    }
                    return [ObjectDefStmt]::new($name.Text, $typeName, $properties, $name.Line)
                }
                $value = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the assignment to end here.')
                return [AssignStmt]::new($name.Text, $value, $name.Line)
            }
            if (Test-OtterTokenKind ([TokenKind]::IsNot)) {
                [void](Read-OtterToken)
                $value = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the assignment to end here.')
                return [AssignStmt]::new($name.Text, [NotExpr]::new($value, $name.Line), $name.Line)
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
