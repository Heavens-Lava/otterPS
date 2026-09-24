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
    [TokenKind]::Random, [TokenKind]::Json, [TokenKind]::Csv, [TokenKind]::Convert,
    [TokenKind]::Format, [TokenKind]::Today, [TokenKind]::Now,
    [TokenKind]::Between, [TokenKind]::Otherwise, [TokenKind]::ForEach,
    [TokenKind]::Count, [TokenKind]::Notify, [TokenKind]::Choose,
    [TokenKind]::Download,
    [TokenKind]::Connect, [TokenKind]::Disconnect, [TokenKind]::Query,
    [TokenKind]::Execute, [TokenKind]::Commit, [TokenKind]::Rollback,
    [TokenKind]::Parameter,
    [TokenKind]::Distinct, [TokenKind]::Then, [TokenKind]::Ascending,
    [TokenKind]::Descending, [TokenKind]::Sum, [TokenKind]::Average,
    [TokenKind]::Minimum, [TokenKind]::Maximum
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

# D101: the optional indented HTTP options block on get/post/put/delete -
#   get "url" into result
#       with header "Authorization" is "Bearer abc123"
#       with header "Accept" is "application/json"
#       with cookies                  (or: without cookies)
#       following redirects           (or: without redirects)
#       with timeout 30 seconds
# Mirrors Read-OtterBlock's Newline+Indent...Dedent shape, but for a
# sequence of option clauses rather than statements - returns $null (not
# an empty HttpOptions) when no block is present, so the interpreter/JS
# compiler can tell "no options written" from "an options block that
# happens to set nothing", though today every clause sets something.
function Read-OtterHttpOptions {
    if (-not (Test-OtterTokenKind ([TokenKind]::Newline)) -or -not (Test-OtterTokenOffsetKind 1 ([TokenKind]::Indent))) {
        return $null
    }
    [void](Read-OtterToken) # Newline
    [void](Read-OtterToken) # Indent

    $options = [HttpOptions]::new()
    $headers = [System.Collections.Generic.List[HttpHeaderClause]]::new()

    while (-not (Test-OtterTokenKind ([TokenKind]::Dedent))) {
        $clauseStart = Get-OtterCurrentToken
        if ($clauseStart.Kind -eq [TokenKind]::With) {
            [void](Read-OtterToken)
            $word = Get-OtterCurrentToken
            if ($word.Kind -eq [TokenKind]::Identifier -and $word.Text -eq 'header') {
                [void](Read-OtterToken)
                $name = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Is) 'I expected "is" and a header value after the header name.' 'Write: with header "Accept" is "application/json"')
                $value = Read-OtterValue
                $headers.Add([HttpHeaderClause]::new($name, $value))
            } elseif ($word.Kind -eq [TokenKind]::Identifier -and $word.Text -eq 'cookies') {
                [void](Read-OtterToken)
                $options.WithCookies = $true
            } elseif ($word.Kind -eq [TokenKind]::Identifier -and $word.Text -eq 'timeout') {
                [void](Read-OtterToken)
                $options.TimeoutSeconds = Read-OtterValue
                $unitTok = Get-OtterCurrentToken
                if ($unitTok.Kind -eq [TokenKind]::Second -or
                    ($unitTok.Kind -eq [TokenKind]::Identifier -and $unitTok.Text -in @('second', 'seconds'))) {
                    [void](Read-OtterToken)
                } else {
                    throw (New-OtterParserError 'I expected "seconds" after the timeout value.' $unitTok 'Write: with timeout 30 seconds')
                }
            } else {
                throw (New-OtterParserError "I don't recognize the HTTP option ""with $($word.Text)""." $word 'Write: with header "X" is Y, with cookies, or with timeout N seconds.')
            }
        } elseif ($clauseStart.Kind -eq [TokenKind]::Identifier -and $clauseStart.Text -eq 'without') {
            [void](Read-OtterToken)
            $word = Get-OtterCurrentToken
            if ($word.Kind -eq [TokenKind]::Identifier -and $word.Text -eq 'cookies') {
                [void](Read-OtterToken)
                $options.WithCookies = $false
            } elseif ($word.Kind -eq [TokenKind]::Identifier -and $word.Text -eq 'redirects') {
                [void](Read-OtterToken)
                $options.FollowRedirects = $false
            } else {
                throw (New-OtterParserError "I don't recognize the HTTP option ""without $($word.Text)""." $word 'Write: without cookies, or without redirects.')
            }
        } elseif ($clauseStart.Kind -eq [TokenKind]::Identifier -and $clauseStart.Text -eq 'following') {
            [void](Read-OtterToken)
            $word = Get-OtterCurrentToken
            if ($word.Kind -eq [TokenKind]::Identifier -and $word.Text -eq 'redirects') {
                [void](Read-OtterToken)
                $options.FollowRedirects = $true
            } else {
                throw (New-OtterParserError 'I expected "redirects" after "following".' $word 'Write: following redirects')
            }
        } else {
            throw (New-OtterParserError "I don't recognize ""$($clauseStart.Text)"" as an HTTP option." $clauseStart 'Write: with header "X" is Y, with cookies, without cookies, following redirects, without redirects, or with timeout N seconds.')
        }
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the HTTP option to end here.')
    }
    [void](Read-OtterToken) # Dedent
    $options.Headers = $headers.ToArray()
    return $options
}

function Test-OtterCommandResultPropertyAt {
    param([int]$Position)

    if ($Position -ge $script:Tokens.Count) { return $false }
    $first = $script:Tokens[$Position]
    if (-not (Test-OtterIdentifierToken $first)) { return $false }
    if (($Position + 2) -ge $script:Tokens.Count) { return $false }

    $second = $script:Tokens[$Position + 1]
    $third = $script:Tokens[$Position + 2]
    if ((($first.Text -eq 'exit' -and $second.Text -eq 'code') -or
         ($first.Text -eq 'error' -and $second.Text -eq 'output') -or
         ($first.Text -eq 'rows' -and $second.Text -eq 'affected') -or
         ($first.Text -eq 'primary' -and $second.Text -eq 'key') -or
         ($first.Text -eq 'database' -and $second.Text -eq 'type') -or
         ($first.Text -eq 'default' -and $second.Text -eq 'expression')) -and
        $third.Kind -eq [TokenKind]::Of) {
        return $true
    }

    if (($Position + 3) -lt $script:Tokens.Count) {
        $fourth = $script:Tokens[$Position + 3]
        if ($first.Text -eq 'last' -and $second.Text -eq 'inserted' -and $third.Text -eq 'id' -and $fourth.Kind -eq [TokenKind]::Of) {
            return $true
        }
        if ($first.Text -eq 'primary' -and $second.Text -eq 'key' -and $third.Text -eq 'position' -and $fourth.Kind -eq [TokenKind]::Of) {
            return $true
        }
    }
    return $false
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
        if (Test-OtterIdentifierToken $nextTok) {
            [void](Read-OtterToken)
            $args = [System.Collections.Generic.List[Node]]::new()
            while (-not (Test-OtterTokenKind ([TokenKind]::Newline)) -and -not (Test-OtterTokenKind ([TokenKind]::Make)) -and -not (Test-OtterTokenKind ([TokenKind]::Into)) -and -not (Test-OtterTokenKind ([TokenKind]::And)) -and -not (Test-OtterTokenKind ([TokenKind]::Minus)) -and -not (Test-OtterTokenKind ([TokenKind]::Times)) -and -not (Test-OtterTokenKind ([TokenKind]::DividedBy))) {
                if (-not (Test-OtterTokenKind ([TokenKind]::Newline)) -and ($script:Tokens[$script:Position].Kind -in @([TokenKind]::Number, [TokenKind]::String, [TokenKind]::True, [TokenKind]::False, [TokenKind]::Identifier))) {
                    $args.Add((Read-OtterValue))
                } else {
                    break
                }
            }
            if ($args.Count -gt 0 -or $script:KnownFunctions.ContainsKey($nextTok.Text)) {
                $call = [CallExpr]::new($nextTok.Text, $args.ToArray(), $nextTok.Line)
                return [AwaitExpr]::new($call, $token.Line)
            }
            return [AwaitExpr]::new([VariableExpr]::new($nextTok.Text, $nextTok.Line), $token.Line)
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
    if ($token.Kind -in @([TokenKind]::Length, [TokenKind]::Uppercase, [TokenKind]::Lowercase, [TokenKind]::First, [TokenKind]::Last,
                          [TokenKind]::AbsoluteValue, [TokenKind]::SquareRoot, [TokenKind]::Round, [TokenKind]::RoundUp, [TokenKind]::RoundDown,
                          [TokenKind]::Sine, [TokenKind]::Cosine, [TokenKind]::Tangent, [TokenKind]::LogTen, [TokenKind]::NaturalLog,
                          [TokenKind]::ElapsedTime, [TokenKind]::ElapsedMilliseconds)) {
        [void](Read-OtterToken)
        [void](Assert-OtterTokenKind ([TokenKind]::Of) 'I expected "of" after this operation.')
        $operation = switch ($token.Kind) {
            ([TokenKind]::Length) { [OfOperation]::Length }
            ([TokenKind]::Uppercase) { [OfOperation]::Uppercase }
            ([TokenKind]::Lowercase) { [OfOperation]::Lowercase }
            ([TokenKind]::First) { [OfOperation]::First }
            ([TokenKind]::Last) { [OfOperation]::Last }
            ([TokenKind]::AbsoluteValue) { [OfOperation]::AbsoluteValue }   # D89: absolute value of X
            ([TokenKind]::SquareRoot) { [OfOperation]::SquareRoot }        # D89: square root of X
            ([TokenKind]::Round) { [OfOperation]::Round }                 # D89: round of X
            ([TokenKind]::RoundUp) { [OfOperation]::RoundUp }             # D89: round up of X
            ([TokenKind]::RoundDown) { [OfOperation]::RoundDown }         # D89: round down of X
            ([TokenKind]::Sine) { [OfOperation]::Sine }                   # D90: sine of X (degrees)
            ([TokenKind]::Cosine) { [OfOperation]::Cosine }               # D90: cosine of X (degrees)
            ([TokenKind]::Tangent) { [OfOperation]::Tangent }             # D90: tangent of X (degrees)
            ([TokenKind]::LogTen) { [OfOperation]::LogTen }               # D90: log of X (base 10)
            ([TokenKind]::NaturalLog) { [OfOperation]::NaturalLog }       # D90: natural log of X (base e)
            ([TokenKind]::ElapsedTime) { [OfOperation]::ElapsedTime }               # D101: elapsed time of workTimer
            ([TokenKind]::ElapsedMilliseconds) { [OfOperation]::ElapsedMilliseconds } # D101: elapsed milliseconds of workTimer
        }
        return [OfOperationExpr]::new($operation, (Read-OtterValue -PropertyTarget), $token.Line)
    }
    # D89: larger of X and Y / smaller of X and Y
    if ($token.Kind -in @([TokenKind]::Larger, [TokenKind]::Smaller)) {
        [void](Read-OtterToken)
        [void](Assert-OtterTokenKind ([TokenKind]::Of) 'I expected "of" after this operation.')
        $isMax = ($token.Kind -eq [TokenKind]::Larger)
        $left = Read-OtterValue
        [void](Assert-OtterTokenKind ([TokenKind]::And) 'I expected "and" and the second value.')
        $right = Read-OtterValue
        return [MinMaxExpr]::new($isMax, $left, $right, $token.Line)
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
    # D90: `pi` is a literal constant, resolved at PARSE time - it never
    # touches the interpreter or JS compiler as its own node, the same way
    # a number literal doesn't. Matches D32's today/now precedent: this
    # word always means the constant in expression position, even if a
    # variable named "pi" was assigned - an accepted, existing tradeoff,
    # not a new one.
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'pi') {
        [void](Read-OtterToken); return [LiteralExpr]::new([Math]::PI, $token.Line)
    }
    if (Test-OtterCommandResultPropertyAt $script:Position) {
        $first = Read-OtterToken
        $second = Read-OtterToken
        $propName = "$($first.Text) $($second.Text)"
        if ($first.Text -eq 'last' -and $second.Text -eq 'inserted' -and (Get-OtterCurrentToken).Text -eq 'id') {
            $third = Read-OtterToken
            $propName = "$($first.Text) $($second.Text) $($third.Text)"
        } elseif ($first.Text -eq 'primary' -and $second.Text -eq 'key' -and (Get-OtterCurrentToken).Text -eq 'position') {
            $third = Read-OtterToken
            $propName = "$($first.Text) $($second.Text) $($third.Text)"
        }
        [void](Assert-OtterTokenKind ([TokenKind]::Of) 'I expected "of" after this command result property.')
        return [PropertyAccessExpr]::new($propName, (Read-OtterValue -PropertyTarget), $first.Line)
    }
    # D101: date from "2024-01-15" [using "MM/dd/yyyy"] - "date" is checked
    # by text ONLY when immediately followed by "from" (the already-
    # reserved `From` token), so it stays a completely ordinary,
    # unreserved identifier everywhere else - `date is "..."` and `say
    # date` are both still just a plain variable named "date", unaffected.
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'date' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::From) {
        [void](Read-OtterToken)
        [void](Read-OtterToken)
        $dateSource = Read-OtterValue
        $dateFormat = $null
        $maybeUsing = Get-OtterCurrentToken
        if ($maybeUsing.Kind -eq [TokenKind]::Identifier -and $maybeUsing.Text -eq 'using') {
            [void](Read-OtterToken)
            $dateFormat = Read-OtterValue
        }
        return [DateFromTextExpr]::new($dateSource, $dateFormat, $token.Line)
    }
    # D102: the bytes type. "bytes"/"empty"/"text"/"hex"/"base64" are all
    # checked by TEXT only in these exact narrow positions (D33 mechanism
    # 1, same as "date from" above) - `bytes is 5`, `text is "hi"`, `hex
    # is 3` all still just name an ordinary variable everywhere else.
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'bytes' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::From) {
        [void](Read-OtterToken) # bytes
        [void](Read-OtterToken) # from
        $encWord = Get-OtterCurrentToken
        if ($encWord.Kind -eq [TokenKind]::File -or ($encWord.Kind -eq [TokenKind]::Identifier -and $encWord.Text -eq 'file')) {
            [void](Read-OtterToken)
            $filePath = Read-OtterValue
            return [BytesFromFileExpr]::new($filePath, $token.Line)
        }
        $op = if ($encWord.Kind -eq [TokenKind]::Identifier -and $encWord.Text -eq 'text') { [BytesOp]::FromText }
              elseif ($encWord.Kind -eq [TokenKind]::Identifier -and $encWord.Text -eq 'hex') { [BytesOp]::FromHex }
              elseif ($encWord.Kind -eq [TokenKind]::Identifier -and $encWord.Text -eq 'base64') { [BytesOp]::FromBase64 }
              else { $null }
        if ($null -eq $op) {
            throw (New-OtterParserError "I expected ""file"", ""text"", ""hex"", or ""base64"" after ""bytes from""." $encWord 'Write: bytes from file "photo.png", bytes from text "Hello", bytes from hex "48656C6C6F", or bytes from base64 "SGVsbG8="')
        }
        [void](Read-OtterToken)
        return [BytesExpr]::new($op, (Read-OtterValue), $token.Line)
    }
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'empty' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'bytes') {
        [void](Read-OtterToken) # empty
        [void](Read-OtterToken) # bytes
        return [BytesExpr]::new([BytesOp]::Empty, $null, $token.Line)
    }
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -in @('text', 'hex', 'base64') -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::From -and
        ($script:Position + 2) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 2].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 2].Text -eq 'bytes') {
        $op = switch ($token.Text) {
            'text' { [BytesOp]::ToText }
            'hex' { [BytesOp]::ToHex }
            'base64' { [BytesOp]::ToBase64 }
        }
        [void](Read-OtterToken) # text|hex|base64
        [void](Read-OtterToken) # from
        [void](Read-OtterToken) # bytes
        return [BytesExpr]::new($op, (Read-OtterValue), $token.Line)
    }
    # D103: SPA routing expressions. "current"/"route" are ordinary,
    # unreserved identifiers (D33 mechanism 1) - "query"/"parameter" are
    # already-reserved TokenKinds from D97/D98's database grammar, so
    # `query parameter X` is checked by KIND, needing no text match at all.
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'current' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'route') {
        [void](Read-OtterToken) # current
        [void](Read-OtterToken) # route
        return [CurrentRouteExpr]::new($token.Line)
    }
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'route' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Parameter) {
        [void](Read-OtterToken) # route
        [void](Read-OtterToken) # parameter
        return [RouteParameterExpr]::new((Read-OtterValue), $token.Line)
    }
    if ($token.Kind -eq [TokenKind]::Query -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Parameter) {
        [void](Read-OtterToken) # query
        [void](Read-OtterToken) # parameter
        return [QueryParameterExpr]::new((Read-OtterValue), $token.Line)
    }
    # D104: watch-event ambient context - "changed"/"kind"/"old" are all
    # ordinary, unreserved identifiers (D33 mechanism 1); "path" likewise
    # (never reserved anywhere in this grammar), "file" is the one
    # already-reserved TokenKind among the three-word form's words.
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'changed' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::File -and
        ($script:Position + 2) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 2].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 2].Text -eq 'name') {
        [void](Read-OtterToken) # changed
        [void](Read-OtterToken) # file
        [void](Read-OtterToken) # name
        return [ChangedFileNameExpr]::new($token.Line)
    }
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'changed' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'path') {
        [void](Read-OtterToken) # changed
        [void](Read-OtterToken) # path
        return [ChangedPathExpr]::new($token.Line)
    }
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'change' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'kind') {
        [void](Read-OtterToken) # change
        [void](Read-OtterToken) # kind
        return [ChangeKindExpr]::new($token.Line)
    }
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'old' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'path') {
        [void](Read-OtterToken) # old
        [void](Read-OtterToken) # path
        return [OldPathExpr]::new($token.Line)
    }
    # D106: WebSockets contextual event expressions
    # received message
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'received' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'message') {
        [void](Read-OtterToken) # received
        [void](Read-OtterToken) # message
        return [ReceivedMessageExpr]::new($token.Line)
    }
    # D116B: received response (ambient in on complete of request)
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'received' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'response') {
        [void](Read-OtterToken) # received
        [void](Read-OtterToken) # response
        return [ReceivedResponseExpr]::new($token.Line)
    }
    # close was clean (check before close code/reason because it has 3 words)
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'close' -and
        ($script:Position + 2) -lt $script:Tokens.Count -and
        $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and $script:Tokens[$script:Position + 1].Text -eq 'was' -and
        $script:Tokens[$script:Position + 2].Kind -eq [TokenKind]::Identifier -and $script:Tokens[$script:Position + 2].Text -eq 'clean') {
        [void](Read-OtterToken) # close
        [void](Read-OtterToken) # was
        [void](Read-OtterToken) # clean
        return [CloseWasCleanExpr]::new($token.Line)
    }
    # close code
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'close' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'code') {
        [void](Read-OtterToken) # close
        [void](Read-OtterToken) # code
        return [CloseCodeExpr]::new($token.Line)
    }
    # close reason
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'close' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'reason') {
        [void](Read-OtterToken) # close
        [void](Read-OtterToken) # reason
        return [CloseReasonExpr]::new($token.Line)
    }
    # websocket error
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'websocket' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and
        ($script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Problem -or $script:Tokens[$script:Position + 1].Text -eq 'error')) {
        [void](Read-OtterToken) # websocket
        [void](Read-OtterToken) # error
        return [WebSocketErrorExpr]::new($token.Line)
    }
    # D111: `secret "name"` reads a secret; `secret "name" exists` tests for one.
    # "secret" stays an ordinary identifier: it only means the vault when a
    # text literal follows, or a bare name that ends the line / precedes "exists".
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'secret' -and ($script:Position + 1) -lt $script:Tokens.Count) {
        $secretNext = $script:Tokens[$script:Position + 1]
        $secretNameIsLiteral = ($secretNext.Kind -eq [TokenKind]::String)
        $secretNameIsVariable = ($secretNext.Kind -eq [TokenKind]::Identifier -and ($script:Position + 2) -lt $script:Tokens.Count -and
            ($script:Tokens[$script:Position + 2].Kind -in @([TokenKind]::Newline, [TokenKind]::Exists)))
        if ($secretNameIsLiteral -or $secretNameIsVariable) {
            [void](Read-OtterToken) # secret
            $secretName = Read-OtterValue
            if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Exists) {
                [void](Read-OtterToken)
                return [SecretExistsExpr]::new($secretName, $token.Line)
            }
            return [SecretReadExpr]::new($secretName, $token.Line)
        }
    }
    # D109: cryptography expressions. Plain identifiers (D33 mechanism 1),
    # matched by text only in these exact shapes.
    if ($token.Kind -eq [TokenKind]::Identifier -and ($script:Position + 1) -lt $script:Tokens.Count) {
        $cryptoNext = $script:Tokens[$script:Position + 1]
        # secure random bytes 32
        if ($token.Text -eq 'secure' -and $cryptoNext.Text -eq 'random' -and
            ($script:Position + 2) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 2].Text -eq 'bytes') {
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            return [SecureRandomBytesExpr]::new((Read-OtterValue), $token.Line)
        }
        # sha256 of data
        if ($token.Text -in @('sha256', 'sha384', 'sha512') -and $cryptoNext.Kind -eq [TokenKind]::Of) {
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            return [CryptoHashExpr]::new($token.Text, (Read-OtterValue), $token.Line)
        }
        # hmac sha256 of data using key
        if ($token.Text -eq 'hmac' -and $cryptoNext.Text -in @('sha256', 'sha384', 'sha512') -and
            (Test-OtterTokenOffsetKind 2 ([TokenKind]::Of))) {
            [void](Read-OtterToken)
            $hmacAlgorithm = (Read-OtterToken).Text
            [void](Read-OtterToken) # of
            $hmacData = Read-OtterValue
            $usingTok = Get-OtterCurrentToken
            if (-not ($usingTok.Kind -eq [TokenKind]::Identifier -and $usingTok.Text -eq 'using')) {
                throw (New-OtterParserError 'I expected "using" and a key after the data to sign.' $usingTok 'signature is hmac sha256 of data using key')
            }
            [void](Read-OtterToken)
            return [CryptoHmacExpr]::new($hmacAlgorithm, $hmacData, (Read-OtterValue), $token.Line)
        }
    }
    # D110: drag/drop context. Plain identifiers, matched by text in these
    # exact word pairs only (D33 mechanism 1).
    if ($token.Kind -eq [TokenKind]::Identifier -and ($script:Position + 1) -lt $script:Tokens.Count) {
        $dragNext = $script:Tokens[$script:Position + 1]
        $dragField = $null
        if ($token.Text -eq 'dragged' -and $dragNext.Text -eq 'item') { $dragField = 'dragged item' }
        elseif ($token.Text -eq 'dropped' -and $dragNext.Text -eq 'files') { $dragField = 'dropped files' }
        elseif ($token.Text -eq 'drag' -and $dragNext.Text -eq 'data') { $dragField = 'drag data' }
        elseif ($token.Text -eq 'drop' -and $dragNext.Text -eq 'x') { $dragField = 'drop x' }
        elseif ($token.Text -eq 'drop' -and $dragNext.Text -eq 'y') { $dragField = 'drop y' }
        if ($null -ne $dragField) {
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            return [DragContextExpr]::new($dragField, $token.Line)
        }
    }
    # D107/D108: TCP/UDP contextual expressions. All plain identifiers
    # (D33 mechanism 1), matched by text in these exact word pairs only.
    if ($token.Kind -eq [TokenKind]::Identifier -and ($script:Position + 1) -lt $script:Tokens.Count) {
        $netNext = $script:Tokens[$script:Position + 1]
        $netField = $null
        if ($token.Text -eq 'received' -and $netNext.Text -eq 'data') { $netField = 'data' }
        elseif ($token.Text -eq 'sender' -and $netNext.Text -eq 'address') { $netField = 'sender address' }
        elseif ($token.Text -eq 'sender' -and $netNext.Text -eq 'port') { $netField = 'sender port' }
        elseif ($token.Text -eq 'network' -and $netNext.Text -eq 'error') { $netField = 'network error' }
        elseif ($token.Text -eq 'incoming' -and $netNext.Text -eq 'connection') { $netField = 'incoming connection' }
        elseif ($token.Text -eq 'received' -and $netNext.Text -eq 'response') { $netField = 'response' }
        if ($null -ne $netField) {
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            return [NetContextExpr]::new($netField, $token.Line)
        }
        # remote address of X / remote port of X
        if ($token.Text -eq 'remote' -and ($netNext.Text -eq 'address' -or $netNext.Text -eq 'port') -and
            (Test-OtterTokenOffsetKind 2 ([TokenKind]::Of))) {
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            return [PropertyAccessExpr]::new("remote $($netNext.Text)", (Read-OtterValue -PropertyTarget), $token.Line)
        }
        # D112: tls version of X / tls protocol of X
        if ($token.Text -eq 'tls' -and ($netNext.Text -eq 'version' -or $netNext.Text -eq 'protocol') -and
            (Test-OtterTokenOffsetKind 2 ([TokenKind]::Of))) {
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            return [PropertyAccessExpr]::new("tls $($netNext.Text)", (Read-OtterValue -PropertyTarget), $token.Line)
        }
        # D113: local address of X / local port of X
        if ($token.Text -eq 'local' -and ($netNext.Text -eq 'address' -or $netNext.Text -eq 'port') -and
            (Test-OtterTokenOffsetKind 2 ([TokenKind]::Of))) {
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            return [PropertyAccessExpr]::new("local $($netNext.Text)", (Read-OtterValue -PropertyTarget), $token.Line)
        }
    }
    # D105: XML. All leading words here (xml/pretty/element/elements/
    # child/children/attribute) are ordinary, unreserved identifiers
    # (D33 mechanism 1), checked by text only in these exact positions.
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'xml' -and
        ((Test-OtterTokenOffsetKind 1 ([TokenKind]::From)) -or (Test-OtterTokenOffsetKind 1 ([TokenKind]::With)))) {
        [void](Read-OtterToken) # xml
        $fromOrWith = Read-OtterToken
        if ($fromOrWith.Kind -eq [TokenKind]::From) {
            $kindWord = Get-OtterCurrentToken
            if ($kindWord.Kind -eq [TokenKind]::Identifier -and $kindWord.Text -eq 'text') {
                [void](Read-OtterToken)
                return [XmlFromExpr]::new([XmlSourceKind]::Text, (Read-OtterValue), $token.Line)
            }
            if ($kindWord.Kind -eq [TokenKind]::File) {
                [void](Read-OtterToken)
                return [XmlFromExpr]::new([XmlSourceKind]::File, (Read-OtterValue), $token.Line)
            }
            throw (New-OtterParserError 'I expected "text" or "file" after "xml from".' $kindWord 'Write: xml from text source, or xml from file "books.xml"')
        }
        # xml with root "library"
        $rootWord = Get-OtterCurrentToken
        if (-not ($rootWord.Kind -eq [TokenKind]::Identifier -and $rootWord.Text -eq 'root')) {
            throw (New-OtterParserError 'I expected "root" after "xml with".' $rootWord 'Write: xml with root "library"')
        }
        [void](Read-OtterToken)
        return [XmlFromExpr]::new([XmlSourceKind]::Root, (Read-OtterValue), $token.Line)
    }
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'pretty' -and
        (Test-OtterTokenOffsetKind 1 ([TokenKind]::Identifier)) -and $script:Tokens[$script:Position + 1].Text -eq 'text' -and
        (Test-OtterTokenOffsetKind 2 ([TokenKind]::From))) {
        [void](Read-OtterToken) # pretty
        [void](Read-OtterToken) # text
        [void](Read-OtterToken) # from
        $xmlWord = Get-OtterCurrentToken
        if (-not ($xmlWord.Kind -eq [TokenKind]::Identifier -and $xmlWord.Text -eq 'xml')) {
            throw (New-OtterParserError 'I expected "xml" after "pretty text from".' $xmlWord 'Write: pretty text from xml document')
        }
        [void](Read-OtterToken)
        return [XmlToTextExpr]::new((Read-OtterValue), $true, $token.Line)
    }
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'text' -and
        (Test-OtterTokenOffsetKind 1 ([TokenKind]::From))) {
        $secondTok = $script:Tokens[$script:Position + 2]
        if (($script:Position + 2) -lt $script:Tokens.Count -and $secondTok.Kind -eq [TokenKind]::Identifier -and $secondTok.Text -eq 'xml') {
            [void](Read-OtterToken) # text
            [void](Read-OtterToken) # from
            [void](Read-OtterToken) # xml
            return [XmlToTextExpr]::new((Read-OtterValue), $false, $token.Line)
        }
    }
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'text' -and
        (Test-OtterTokenOffsetKind 1 ([TokenKind]::Of))) {
        [void](Read-OtterToken) # text
        [void](Read-OtterToken) # of
        # -PropertyTarget matters: without it, "the" in "text of the
        # nameBox" is never stripped (that filler-word handling is
        # gated on this switch), leaving "the" to be misread as an
        # ordinary variable name and "nameBox" as unconsumed leftover
        # input - a real regression, caught by Parser.Tests.ps1's own
        # existing "text of the nameBox" coverage, not by any of this
        # feature's own tests (none of them happened to use "the").
        $nameOrElem = Read-OtterValue -PropertyTarget
        if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::In) {
            [void](Read-OtterToken)
            return [XmlTextOfNameInExpr]::new($nameOrElem, (Read-OtterValue -PropertyTarget), $token.Line)
        }
        return [PropertyAccessExpr]::new('text', $nameOrElem, $token.Line)
    }
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -in @('element', 'elements', 'child', 'children')) {
        # Backtracking, not a hard commit: "element"/"child"/etc are
        # ordinary identifiers, so a BARE use of one as a plain variable
        # ("say element") must still work - confirmed as a real bug
        # without this: an unconditional attempt here threw "I expected a
        # value here" the moment nothing selector-shaped followed, instead
        # of falling through to treat the word as a plain variable read.
        $savedXmlSelectPos = $script:Position
        $selectKind = switch ($token.Text) {
            'element' { [XmlSelectKind]::Element }
            'elements' { [XmlSelectKind]::Elements }
            'child' { [XmlSelectKind]::Child }
            'children' { [XmlSelectKind]::Children }
        }
        [void](Read-OtterToken)
        $xmlSelectOk = $true
        $selector = $null
        try {
            $selector = Read-OtterValue
        } catch {
            $xmlSelectOk = $false
        }
        if ($xmlSelectOk -and (Get-OtterCurrentToken).Kind -eq [TokenKind]::In) {
            [void](Read-OtterToken)
            return [XmlSelectExpr]::new($selectKind, $selector, (Read-OtterValue -PropertyTarget), $token.Line)
        }
        $script:Position = $savedXmlSelectPos
    }
    if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'attribute') {
        # Same backtracking reasoning as element/elements/child/children
        # above - "attribute" alone ("say attribute") must still read as
        # a plain variable.
        $savedXmlAttrPos = $script:Position
        [void](Read-OtterToken)
        $xmlAttrOk = $true
        $attrName = $null
        try {
            $attrName = Read-OtterValue
        } catch {
            $xmlAttrOk = $false
        }
        if ($xmlAttrOk -and (Get-OtterCurrentToken).Kind -eq [TokenKind]::Of) {
            [void](Read-OtterToken)
            return [XmlAttributeExpr]::new($attrName, (Read-OtterValue -PropertyTarget), $token.Line)
        }
        $script:Position = $savedXmlAttrPos
    }
    if (Test-OtterIdentifierToken $token) {
        # A declared function is a real value-producing expression.  Its
        # arity tells us exactly how many following values belong to the
        # call, so a trailing condition `and` remains available to the
        # condition reader instead of being guessed as another argument.
        if ($script:KnownFunctions.ContainsKey($token.Text)) {
            return Read-OtterFunctionCallExpression -FunctionToken $token
        }
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
        # D100: console is interactive - already a single combined token
        # from the lexer's phrase combiner (see ConsoleInteractive there),
        # so it is just another boolean-valued literal-like expression
        # here, usable anywhere true/false/gone are, including composed
        # with `not`/`and`/`or`, not only as a bare `if` condition.
        ([TokenKind]::ConsoleInteractive) { [void](Read-OtterToken); return [ConsoleInteractiveExpr]::new($token.Line) }
        default { throw (New-OtterParserError 'I expected a value here.' $token 'Add a text value, number, true, false, or variable name.') }
    }
}

function Read-OtterVariableName {
    param(
        [string]$Message,
        [switch]$AllowReservedLiteral
    )
    $token = Get-OtterCurrentToken
    if (-not (Test-OtterIdentifierToken $token)) {
        throw (New-OtterParserError $Message $token 'Use a name to hold this value.')
    }
    if (-not $AllowReservedLiteral -and $token.Text -in @('today', 'now', 'pi')) {
        throw (New-OtterParserError "'$($token.Text)' is a built-in value, not a variable name." $token 'Choose a different variable name, such as "currentTime" or "circleRatio".')
    }
    [void](Read-OtterToken)
    return $token
}

function Read-OtterMathExpression {
    $left = Read-OtterValue
    while ((Test-OtterTokenKind ([TokenKind]::And)) -or
           (Test-OtterTokenKind ([TokenKind]::Minus)) -or
           (Test-OtterTokenKind ([TokenKind]::Times)) -or
           (Test-OtterTokenKind ([TokenKind]::DividedBy)) -or
           (Test-OtterTokenKind ([TokenKind]::Percent)) -or
           (Test-OtterTokenKind ([TokenKind]::Power))) {
        $operator = Read-OtterToken
        # `and`/`plus` deliberately share TokenKind::And (D3/D7) - `and` is
        # a genuine, real synonym for numeric addition and string
        # concatenation OUTSIDE a condition (confirmed still in real,
        # existing production .ot files: examples/cli-app.ot,
        # examples/studio.ot, examples/terminal.ot all use `and` this way).
        # A PARSE-time rejection of bare `and` here cannot tell that use
        # apart from boolean `and` used by mistake outside an if/while -
        # only the INTERPRETER, once it knows the actual runtime type of
        # both operands, can tell a stray boolean from a real number/string
        # and give the specific "and/or only work in a condition" diagnosis
        # (see Get-OtterValue's 'Math'/'Add' case). Do not reintroduce a
        # parser-level rejection of `and` here without re-checking those
        # three files.
        # D88: `X percent of Y` needs "of" consumed between the operator
        # and the right operand - every other operator here reads the
        # right operand immediately, so this is the one exception.
        if ($operator.Kind -eq [TokenKind]::Percent) {
            [void](Assert-OtterTokenKind ([TokenKind]::Of) 'I expected "of" after "percent".')
        }
        $right = Read-OtterValue
        $mathOp = switch ($operator.Kind) {
            ([TokenKind]::And) { [MathOp]::Add }
            ([TokenKind]::Minus) { [MathOp]::Subtract }
            ([TokenKind]::Times) { [MathOp]::Multiply }
            ([TokenKind]::DividedBy) { [MathOp]::Divide }
            ([TokenKind]::Percent) { [MathOp]::Percent }
            ([TokenKind]::Power) { [MathOp]::Power }
        }
        $left = [MathExpr]::new($left, $mathOp, $right, $operator.Line)
    }
    if (Test-OtterTokenKind ([TokenKind]::Or)) {
        $operator = Get-OtterCurrentToken
        throw (New-OtterParserError '"or" only works inside an if or while condition.' $operator 'Move the boolean expression into an if or while condition.')
    }
    return $left
}

function Read-OtterConditionPrimary {
    if (Test-OtterTokenKind ([TokenKind]::Not)) {
        $token = Read-OtterToken
        return [NotExpr]::new((Read-OtterConditionPrimary), $token.Line)
    }
    # D105: `element "book" exists in document` - checked before the
    # generic `$left = Read-OtterValue` below, which would otherwise
    # treat "element" as the start of the ordinary "element X in Y"
    # selection expression (Read-OtterValue's own XmlSelect handling) and
    # throw when it hits "exists" instead of the "in" it requires. A
    # saved-position backtrack restores cleanly whenever this ISN'T the
    # exists form, so plain "element X in Y" still reaches that handling
    # untouched.
    $maybeXmlExists = Get-OtterCurrentToken
    if ($maybeXmlExists.Kind -eq [TokenKind]::Identifier -and $maybeXmlExists.Text -eq 'element') {
        $savedPos = $script:Position
        [void](Read-OtterToken) # element
        $xmlExistsSelector = Read-OtterValue
        if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Exists) {
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::In) 'I expected "in" after "exists".')
            return [XmlElementExistsExpr]::new($xmlExistsSelector, (Read-OtterValue -PropertyTarget), $maybeXmlExists.Line)
        }
        $script:Position = $savedPos
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
    # D109: `password <text> matches hash <hash>`. "password" is an ordinary
    # identifier, so this backtracks unless "matches hash" really follows.
    if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'password' -and
        -not (Test-OtterTokenOffsetKind 1 ([TokenKind]::Is)) -and -not (Test-OtterTokenOffsetKind 1 ([TokenKind]::Of))) {
        $savedPasswordPosition = $script:Position
        $passwordWord = Read-OtterToken
        $passwordValue = $null
        try { $passwordValue = Read-OtterValue } catch { $passwordValue = $null }
        if ($null -ne $passwordValue -and (Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'matches') {
            [void](Read-OtterToken) # matches
            if ((Get-OtterCurrentToken).Text -ne 'hash') {
                throw (New-OtterParserError 'I expected "hash" after "matches".' (Get-OtterCurrentToken) 'password attempt matches hash storedHash')
            }
            [void](Read-OtterToken) # hash
            return [PasswordMatchesExpr]::new($passwordValue, (Read-OtterValue), $passwordWord.Line)
        }
        $script:Position = $savedPasswordPosition
    }
    $left = Read-OtterValue
    # D109: `expected securely equals actual` - constant-time comparison of bytes.
    if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'securely' -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Text -eq 'equals') {
        $securelyWord = Read-OtterToken
        [void](Read-OtterToken) # equals
        return [SecurelyEqualsExpr]::new($left, (Read-OtterValue), $securelyWord.Line)
    }
    # D104: `dataWatcher is watching` - a watcher-state predicate, not a
    # general equality comparison ("watching" is not a value anything
    # else could ever legitimately compare equal to). "watching" is an
    # ordinary, unreserved identifier (D33 mechanism 1) - checked by
    # text only in this exact position, right after a plain "is".
    if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Is -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'watching') {
        $isWord = Read-OtterToken
        [void](Read-OtterToken)
        return [IsWatchingExpr]::new($left, $isWord.Line)
    }
    # D106: `socket is connecting` / `socket is open` / `socket is closing` / `socket is closed`
    if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Is -and ($script:Position + 1) -lt $script:Tokens.Count) {
        $nextTok = $script:Tokens[$script:Position + 1]
        $wsConnState = $null
        if ($nextTok.Text -eq 'connecting') { $wsConnState = [WebSocketConnState]::Connecting }
        elseif ($nextTok.Kind -eq [TokenKind]::Open -or $nextTok.Text -eq 'open') { $wsConnState = [WebSocketConnState]::Open }
        elseif ($nextTok.Text -eq 'closing') { $wsConnState = [WebSocketConnState]::Closing }
        elseif ($nextTok.Text -eq 'connected') { $wsConnState = [WebSocketConnState]::Connected }
        elseif ($nextTok.Text -eq 'closed') { $wsConnState = [WebSocketConnState]::Closed }

        if ($null -ne $wsConnState) {
            $isWord = Read-OtterToken
            [void](Read-OtterToken) # state word
            return [WebSocketIsStateExpr]::new($left, $wsConnState, $isWord.Line)
        }
    }
    # D112: `connection is secure`
    if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Is -and ($script:Position + 1) -lt $script:Tokens.Count -and
        $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'secure') {
        $isWord = Read-OtterToken
        [void](Read-OtterToken) # secure
        return [ConnectionIsSecureExpr]::new($left, $isWord.Line)
    }
    # D113: `server is listening` / `server is stopped`
    if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Is -and ($script:Position + 1) -lt $script:Tokens.Count -and
        $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier) {
        $srvText = $script:Tokens[$script:Position + 1].Text
        $srvState = $null
        if ($srvText -eq 'listening') { $srvState = [TcpServerState]::Listening }
        elseif ($srvText -eq 'stopped') { $srvState = [TcpServerState]::Stopped }
        if ($null -ne $srvState) {
            $isWord = Read-OtterToken
            [void](Read-OtterToken) # state word
            return [TcpServerIsStateExpr]::new($left, $srvState, $isWord.Line)
        }
    }
    # D116B: `request is pending` / `completed` / `failed` / `cancelled` (and `is not`)
    if ((Get-OtterCurrentToken).Kind -in @([TokenKind]::Is, [TokenKind]::IsNot) -and ($script:Position + 1) -lt $script:Tokens.Count -and
        $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier) {
        $httpStateText = $script:Tokens[$script:Position + 1].Text
        $httpReqState = $null
        if ($httpStateText -eq 'pending') { $httpReqState = [HttpRequestState]::Pending }
        elseif ($httpStateText -eq 'completed') { $httpReqState = [HttpRequestState]::Completed }
        elseif ($httpStateText -eq 'failed') { $httpReqState = [HttpRequestState]::Failed }
        elseif ($httpStateText -eq 'cancelled') { $httpReqState = [HttpRequestState]::Cancelled }
        if ($null -ne $httpReqState) {
            $isWord = Read-OtterToken
            [void](Read-OtterToken) # state word
            $stateExpr = [HttpRequestIsStateExpr]::new($left, $httpReqState, $isWord.Line)
            if ($isWord.Kind -eq [TokenKind]::IsNot) {
                return [NotExpr]::new($stateExpr, $isWord.Line)
            }
            return $stateExpr
        }
    }
    # D105: `book has attribute "id"` - "has" is already a reserved
    # TokenKind (used elsewhere for thing-property declarations), so
    # this is checked by KIND, not text; "attribute" is unreserved.
    if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Has -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'attribute') {
        $hasWord = Read-OtterToken
        [void](Read-OtterToken) # attribute
        return [XmlHasAttributeExpr]::new($left, (Read-OtterValue), $hasWord.Line)
    }
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

        $property = Read-OtterVariableName 'I expected a property name.' -AllowReservedLiteral
        # D110: `accepts drops` is a two-word property name.
        $twoWordProperty = $null
        if ($property.Text -eq 'accepts' -and (Get-OtterCurrentToken).Text -eq 'drops') {
            [void](Read-OtterToken)
            $twoWordProperty = 'accepts drops'
        }

        # 'is' is optional: both "property value" and "property is value" are valid
        $hadIs = $false
        if (Test-OtterTokenKind ([TokenKind]::Is)) {
            [void](Read-OtterToken)
            $hadIs = $true
        }

        $propName = if ($null -ne $twoWordProperty) { $twoWordProperty } else { $property.Text }
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
        $property = Read-OtterVariableName 'I expected a property name after "has", "with", or a comma.' -AllowReservedLiteral
        # D110: `accepts drops` is a two-word property name.
        $twoWordProperty = $null
        if ($property.Text -eq 'accepts' -and (Get-OtterCurrentToken).Text -eq 'drops') {
            [void](Read-OtterToken)
            $twoWordProperty = 'accepts drops'
        }
        # Inline has and with are comma-delimited configuration lists.  `is` is
        # optional independently for each property, so compact, explicit,
        # and mixed styles all produce the same assignment nodes.
        $hadIs = $false
        if (Test-OtterTokenKind ([TokenKind]::Is)) {
            [void](Read-OtterToken)
            $hadIs = $true
        }

        $propName = if ($null -ne $twoWordProperty) { $twoWordProperty } else { $property.Text }
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
        $field = Read-OtterVariableName 'I expected a property name.' -AllowReservedLiteral
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

# Calls in expression position use the declared function's arity rather than
# a greedy "read until newline" rule.  That keeps this deterministic:
#
#   if isAdult age and active is true
#
# `isAdult` consumes its one argument and leaves `and` for the condition.
function Read-OtterFunctionCallExpression {
    param([Token]$FunctionToken)

    if (-not $script:KnownFunctions.ContainsKey($FunctionToken.Text)) {
        throw (New-OtterParserError "I don't know a function called '$($FunctionToken.Text)'." $FunctionToken)
    }

    [void](Read-OtterToken)
    $arguments = [System.Collections.Generic.List[Node]]::new()
    $arity = [int]$script:KnownFunctions[$FunctionToken.Text]

    for ($index = 0; $index -lt $arity; $index++) {
        if ($index -gt 0 -and (Test-OtterTokenKind ([TokenKind]::And))) {
            [void](Read-OtterToken)
        }
        $current = Get-OtterCurrentToken
        if ($current.Kind -in @([TokenKind]::Newline, [TokenKind]::EndOfFile, [TokenKind]::Make, [TokenKind]::Into, [TokenKind]::Or)) {
            throw (New-OtterParserError "I expected argument $($index + 1) for '$($FunctionToken.Text)'." $current "Provide $arity argument(s) for '$($FunctionToken.Text)'.")
        }
        $arguments.Add((Read-OtterValue))
    }
    return [CallExpr]::new($FunctionToken.Text, $arguments.ToArray(), $FunctionToken.Line)
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

# ===============================================================
# D99: Otter Query Language (OQL) Parser Productions
# ===============================================================

function Test-OtterIsQueryStatement {
    $tok = Get-OtterCurrentToken
    if ($tok.Kind -ne [TokenKind]::Get) { return $false }
    $pos = $script:Position + 1
    if ($pos -ge $script:Tokens.Count) { return $false }

    while ($pos -lt $script:Tokens.Count -and $script:Tokens[$pos].Kind -in @([TokenKind]::Newline, [TokenKind]::Indent)) {
        $pos++
    }
    if ($pos -ge $script:Tokens.Count) { return $false }

    $firstTok = $script:Tokens[$pos]
    if ($firstTok.Kind -eq [TokenKind]::Distinct) { return $true }
    if ($firstTok.Kind -eq [TokenKind]::Identifier -and $firstTok.Text -eq 'all') {
        $nextPos = $pos + 1
        while ($nextPos -lt $script:Tokens.Count -and $script:Tokens[$nextPos].Kind -in @([TokenKind]::Newline, [TokenKind]::Indent)) {
            $nextPos++
        }
        if ($nextPos -lt $script:Tokens.Count -and $script:Tokens[$nextPos].Kind -eq [TokenKind]::From) {
            return $true
        }
    }

    # Protected built-in get statements (D67, D98, files/folders/json)
    if ($firstTok.Kind -in @([TokenKind]::Files, [TokenKind]::Folders)) { return $false }
    if ($firstTok.Kind -eq [TokenKind]::Identifier -and $firstTok.Text -in @(
        'files', 'folders', 'clipboard', 'environment', 'current', 'arguments', 'system', 'processes',
        'symbolic', 'owner', 'registry', 'credential', 'event', 'tables', 'columns'
    )) {
        return $false
    }

    # Look ahead for 'from' followed by 'in' within the same statement
    $sawFrom = $false
    $limit = [Math]::Min($script:Tokens.Count, $pos + 80)
    $indentDepth = 0
    while ($pos -lt $limit) {
        $k = $script:Tokens[$pos].Kind
        if ($k -eq [TokenKind]::EndOfFile) { break }
        if ($k -eq [TokenKind]::Indent) {
            $indentDepth++
        } elseif ($k -eq [TokenKind]::Dedent) {
            $indentDepth--
            if ($indentDepth -le 0) { break }
        } elseif ($k -eq [TokenKind]::Newline) {
            if ($indentDepth -eq 0) {
                $next = $pos + 1
                while ($next -lt $limit -and $script:Tokens[$next].Kind -eq [TokenKind]::Newline) {
                    $next++
                }
                if ($next -ge $limit -or $script:Tokens[$next].Kind -ne [TokenKind]::Indent) {
                    break
                }
            }
        } elseif ($k -eq [TokenKind]::From) {
            $sawFrom = $true
        } elseif ($sawFrom -and $k -eq [TokenKind]::In) {
            return $true
        }
        $pos++
    }
    return $false
}

function Read-OtterQueryWhere {
    return Read-OtterQueryOrExpr
}

function Read-OtterQueryOrExpr {
    $left = Read-OtterQueryAndExpr
    while (Test-OtterTokenKind ([TokenKind]::Or)) {
        $opTok = Read-OtterToken
        $right = Read-OtterQueryAndExpr
        $left = [LogicalExpr]::new($left, [LogicalOp]::Or, $right, $opTok.Line)
    }
    return $left
}

function Read-OtterQueryAndExpr {
    $left = Read-OtterQueryConditionTerm
    while (Test-OtterTokenKind ([TokenKind]::And)) {
        $opTok = Read-OtterToken
        $right = Read-OtterQueryConditionTerm
        $left = [LogicalExpr]::new($left, [LogicalOp]::And, $right, $opTok.Line)
    }
    return $left
}

function Read-OtterQueryConditionTerm {
    # Operands use Read-OtterValue, not Read-OtterMathExpression: "and" doubles
    # as the "plus" operator there, so a math read would swallow
    # `minAge and active` as addition instead of leaving "and" as the
    # where-clause connective (same reason ordinary if-conditions do this).
    $left = Read-OtterValue
    $startLine = $left.Line

    if ((Test-OtterTokenKind ([TokenKind]::IsIn)) -or (Test-OtterTokenKind ([TokenKind]::In)) -or ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'in')) {
        [void](Read-OtterToken)
        $coll = Read-OtterValue
        return [QueryInExpr]::new($left, $coll, $false, $startLine)
    }
    if (Test-OtterTokenKind ([TokenKind]::IsNotIn)) {
        [void](Read-OtterToken)
        $coll = Read-OtterValue
        return [QueryInExpr]::new($left, $coll, $true, $startLine)
    }

    if ((Test-OtterTokenKind ([TokenKind]::IsBetween)) -or (Test-OtterTokenKind ([TokenKind]::Between)) -or ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'between')) {
        [void](Read-OtterToken)
        $lower = Read-OtterValue
        [void](Assert-OtterTokenKind ([TokenKind]::And) 'I expected "and" and upper bound in between expression.' 'where age is between 18 and 65')
        $upper = Read-OtterValue
        return [QueryBetweenExpr]::new($left, $lower, $upper, $startLine)
    }

    if (Test-OtterTokenKind ([TokenKind]::Contains)) {
        $operator = Read-OtterToken
        return [ContainsExpr]::new($left, (Read-OtterValue), $operator.Line)
    }

    if ((Test-OtterTokenKind ([TokenKind]::StartsWith)) -or (Test-OtterTokenKind ([TokenKind]::EndsWith))) {
        $operator = Read-OtterToken
        $match = if ($operator.Kind -eq [TokenKind]::StartsWith) { [TextMatch]::StartsWith } else { [TextMatch]::EndsWith }
        return [TextMatchExpr]::new($left, $match, (Read-OtterValue), $operator.Line)
    }

    $compOp = switch ((Get-OtterCurrentToken).Kind) {
        ([TokenKind]::Is) { [CompareOp]::Equal }
        ([TokenKind]::IsNot) { [CompareOp]::NotEqual }
        ([TokenKind]::IsAtLeast) { [CompareOp]::AtLeast }
        ([TokenKind]::IsAtMost) { [CompareOp]::AtMost }
        ([TokenKind]::IsGreaterThan) { [CompareOp]::GreaterThan }
        ([TokenKind]::IsLessThan) { [CompareOp]::LessThan }
        default { $null }
    }

    if ($null -ne $compOp) {
        [void](Read-OtterToken)
        $right = Read-OtterValue
        return [ComparisonExpr]::new($left, $compOp, $right, $startLine)
    }

    return $left
}

function Read-OtterQueryOrderByItems {
    $items = [System.Collections.Generic.List[QueryOrderByItem]]::new()
    while (-not (Test-OtterTokenKind ([TokenKind]::EndOfFile))) {
        $expr = Read-OtterMathExpression
        $isDesc = $false
        if (Test-OtterTokenKind ([TokenKind]::Ascending)) {
            [void](Read-OtterToken)
            $isDesc = $false
        } elseif (Test-OtterTokenKind ([TokenKind]::Descending)) {
            [void](Read-OtterToken)
            $isDesc = $true
        }
        $items.Add([QueryOrderByItem]::new($expr, $isDesc))

        while ((Test-OtterTokenKind ([TokenKind]::Newline)) -or (Test-OtterTokenKind ([TokenKind]::Indent))) {
            [void](Read-OtterToken)
        }

        if (Test-OtterTokenKind ([TokenKind]::Then)) {
            [void](Read-OtterToken)
        } else {
            break
        }
    }
    return $items
}

function Read-OtterQueryStatement {
    $start = Read-OtterToken
    $isDistinct = $false
    $indentCount = 0

    while ((Test-OtterTokenKind ([TokenKind]::Newline)) -or (Test-OtterTokenKind ([TokenKind]::Indent))) {
        if (Test-OtterTokenKind ([TokenKind]::Indent)) { $indentCount++ }
        [void](Read-OtterToken)
    }

    if (Test-OtterTokenKind ([TokenKind]::Distinct)) {
        $isDistinct = $true
        [void](Read-OtterToken)
    }

    $projections = [System.Collections.Generic.List[Node]]::new()
    $curr = Get-OtterCurrentToken
    if ($curr.Kind -eq [TokenKind]::Identifier -and $curr.Text -eq 'all') {
        [void](Read-OtterToken)
    } else {
        while (-not (Test-OtterTokenKind ([TokenKind]::From)) -and -not (Test-OtterTokenKind ([TokenKind]::EndOfFile))) {
            while ((Test-OtterTokenKind ([TokenKind]::Newline)) -or (Test-OtterTokenKind ([TokenKind]::Indent))) {
                if (Test-OtterTokenKind ([TokenKind]::Indent)) { $indentCount++ }
                [void](Read-OtterToken)
            }
            if (Test-OtterTokenKind ([TokenKind]::From)) { break }

            $field = Read-OtterValue
            $projections.Add($field)

            if (Test-OtterTokenKind ([TokenKind]::And)) {
                [void](Read-OtterToken)
            } elseif (Test-OtterTokenKind ([TokenKind]::Identifier) -and (Get-OtterCurrentToken).Text -eq ',') {
                [void](Read-OtterToken)
            }
            while ((Test-OtterTokenKind ([TokenKind]::Newline)) -or (Test-OtterTokenKind ([TokenKind]::Indent))) {
                if (Test-OtterTokenKind ([TokenKind]::Indent)) { $indentCount++ }
                [void](Read-OtterToken)
            }
        }
    }

    while ((Test-OtterTokenKind ([TokenKind]::Newline)) -or (Test-OtterTokenKind ([TokenKind]::Indent))) {
        if (Test-OtterTokenKind ([TokenKind]::Indent)) { $indentCount++ }
        [void](Read-OtterToken)
    }

    [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a table name in query.')
    while ((Test-OtterTokenKind ([TokenKind]::Newline)) -or (Test-OtterTokenKind ([TokenKind]::Indent))) {
        if (Test-OtterTokenKind ([TokenKind]::Indent)) { $indentCount++ }
        [void](Read-OtterToken)
    }

    $tableTok = Read-OtterToken
    $tableName = if ($tableTok.Kind -eq [TokenKind]::String) { [string]$tableTok.Value } else { $tableTok.Text }

    while ((Test-OtterTokenKind ([TokenKind]::Newline)) -or (Test-OtterTokenKind ([TokenKind]::Indent))) {
        if (Test-OtterTokenKind ([TokenKind]::Indent)) { $indentCount++ }
        [void](Read-OtterToken)
    }

    [void](Assert-OtterTokenKind ([TokenKind]::In) 'I expected "in" and database connection after table name.')
    $connection = Read-OtterMathExpression

    $alias = $null
    if (Test-OtterTokenKind ([TokenKind]::As)) {
        [void](Read-OtterToken)
        $aliasTok = Read-OtterVariableName 'I expected alias name after "as".'
        $alias = $aliasTok.Text
    }

    if (Test-OtterTokenKind ([TokenKind]::With)) {
        [void](Read-OtterToken)
    }

    $where = $null
    $orderBy = [System.Collections.Generic.List[QueryOrderByItem]]::new()
    $limit = $null
    $offset = $null
    $target = $null

    while (-not (Test-OtterTokenKind ([TokenKind]::EndOfFile))) {
        while ((Test-OtterTokenKind ([TokenKind]::Newline)) -or (Test-OtterTokenKind ([TokenKind]::Indent)) -or (Test-OtterTokenKind ([TokenKind]::Dedent))) {
            if (Test-OtterTokenKind ([TokenKind]::Indent)) { $indentCount++ }
            elseif (Test-OtterTokenKind ([TokenKind]::Dedent)) { $indentCount-- }
            [void](Read-OtterToken)
        }

        $k = (Get-OtterCurrentToken).Kind
        if ($k -eq [TokenKind]::With) {
            [void](Read-OtterToken)
        }
        elseif ($k -eq [TokenKind]::Where) {
            [void](Read-OtterToken)
            $where = Read-OtterQueryWhere
        }
        elseif ($k -eq [TokenKind]::OrderBy) {
            [void](Read-OtterToken)
            $orderBy = Read-OtterQueryOrderByItems
        }
        elseif ($k -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -in @('take', 'first', 'limit')) {
            [void](Read-OtterToken)
            $limit = Read-OtterMathExpression
        }
        elseif ($k -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -in @('skip', 'offset')) {
            [void](Read-OtterToken)
            $offset = Read-OtterMathExpression
        }
        elseif ($k -eq [TokenKind]::Into) {
            [void](Read-OtterToken)
            $targetTok = Read-OtterVariableName 'I expected target variable name after "into".'
            $target = $targetTok.Text
            break
        }
        else {
            break
        }
    }

    if ([string]::IsNullOrEmpty($target)) {
        throw (New-OtterParserError 'I expected "into" and a result name for the query.' (Get-OtterCurrentToken) 'get all from customers in db into customers')
    }

    while ($indentCount -gt 0 -and ((Test-OtterTokenKind ([TokenKind]::Dedent)) -or (Test-OtterTokenKind ([TokenKind]::Newline)))) {
        if (Test-OtterTokenKind ([TokenKind]::Dedent)) { $indentCount-- }
        [void](Read-OtterToken)
    }
    [QueryOrderByItem[]]$orderByArray = if ($null -ne $orderBy) { @($orderBy) } else { @() }
    [Node[]]$projectionsArray = if ($null -ne $projections) { @($projections) } else { @() }
    return [QueryStmt]::new($isDistinct, $projectionsArray, $tableName, $connection, $alias, $where, $orderByArray, $limit, $offset, $target, $start.Line)
}

function Test-OtterAggregateStatementAhead {
    param([int]$StartPos)
    $pos = $StartPos + 1
    $hasFrom = $false
    $hasInto = $false
    $hasTo = $false
    while ($pos -lt $script:Tokens.Count -and $script:Tokens[$pos].Kind -ne [TokenKind]::Newline -and $script:Tokens[$pos].Kind -ne [TokenKind]::EndOfFile) {
        if ($script:Tokens[$pos].Kind -eq [TokenKind]::From) { $hasFrom = $true }
        if ($script:Tokens[$pos].Kind -eq [TokenKind]::Into) { $hasInto = $true }
        if ($script:Tokens[$pos].Kind -eq [TokenKind]::To) { $hasTo = $true }
        $pos++
    }
    if ($script:Tokens[$StartPos].Kind -eq [TokenKind]::Count -and $hasTo -and -not $hasInto) {
        return $false
    }

    # Multi-line form:
    #     sum of score from scores in db with
    #         where pass is 1
    #     into passingSum
    # The first line has `from` but no `into` - the `into` arrives after the
    # indented `with` block dedents. Keep scanning across that continuation
    # (and only that: a Newline at depth 0 NOT followed by an Indent ends the
    # statement) so the trailing `into` line is still seen. Only attempted when
    # the first line already had `from`, so ordinary `count from 1 to 10`
    # loops and plain variables named sum/min/max never scan further.
    if ($hasFrom -and -not $hasInto -and $pos -lt $script:Tokens.Count -and
        $script:Tokens[$pos].Kind -eq [TokenKind]::Newline -and
        ($pos + 1) -lt $script:Tokens.Count -and $script:Tokens[$pos + 1].Kind -eq [TokenKind]::Indent) {
        $depth = 0
        $limit = [Math]::Min($script:Tokens.Count, $pos + 200)
        while ($pos -lt $limit) {
            $k = $script:Tokens[$pos].Kind
            if ($k -eq [TokenKind]::EndOfFile) { break }
            if ($k -eq [TokenKind]::Indent) {
                $depth++
            } elseif ($k -eq [TokenKind]::Dedent) {
                $depth--
            } elseif ($k -eq [TokenKind]::Newline) {
                if ($depth -le 0) {
                    $next = $pos + 1
                    while ($next -lt $limit -and $script:Tokens[$next].Kind -eq [TokenKind]::Newline) { $next++ }
                    if ($next -ge $limit -or $script:Tokens[$next].Kind -ne [TokenKind]::Indent) { break }
                }
            } elseif ($k -eq [TokenKind]::Into -and $depth -le 0) {
                $hasInto = $true
                break
            }
            $pos++
        }
    }
    return ($hasFrom -and $hasInto)
}

function Read-OtterQueryAggregateStatement {
    $start = Read-OtterToken
    $funcName = $start.Text.ToLowerInvariant()
    $indentCount = 0

    while ((Test-OtterTokenKind ([TokenKind]::Newline)) -or (Test-OtterTokenKind ([TokenKind]::Indent))) {
        if (Test-OtterTokenKind ([TokenKind]::Indent)) { $indentCount++ }
        [void](Read-OtterToken)
    }

    if (Test-OtterTokenKind ([TokenKind]::Of)) {
        [void](Read-OtterToken)
        while ((Test-OtterTokenKind ([TokenKind]::Newline)) -or (Test-OtterTokenKind ([TokenKind]::Indent))) {
            if (Test-OtterTokenKind ([TokenKind]::Indent)) { $indentCount++ }
            [void](Read-OtterToken)
        }
    }

    $expr = if ($funcName -eq 'count' -and (Get-OtterCurrentToken).Text -eq 'all') {
        [void](Read-OtterToken)
        [VariableExpr]::new('*', $start.Line)
    } else {
        Read-OtterMathExpression
    }

    while ((Test-OtterTokenKind ([TokenKind]::Newline)) -or (Test-OtterTokenKind ([TokenKind]::Indent))) {
        if (Test-OtterTokenKind ([TokenKind]::Indent)) { $indentCount++ }
        [void](Read-OtterToken)
    }

    [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and table name after aggregate expression.')
    while ((Test-OtterTokenKind ([TokenKind]::Newline)) -or (Test-OtterTokenKind ([TokenKind]::Indent))) {
        if (Test-OtterTokenKind ([TokenKind]::Indent)) { $indentCount++ }
        [void](Read-OtterToken)
    }

    $tableTok = Read-OtterToken
    $tableName = if ($tableTok.Kind -eq [TokenKind]::String) { [string]$tableTok.Value } else { $tableTok.Text }

    while ((Test-OtterTokenKind ([TokenKind]::Newline)) -or (Test-OtterTokenKind ([TokenKind]::Indent))) {
        if (Test-OtterTokenKind ([TokenKind]::Indent)) { $indentCount++ }
        [void](Read-OtterToken)
    }

    [void](Assert-OtterTokenKind ([TokenKind]::In) 'I expected "in" and database connection after table name.')
    $connection = Read-OtterMathExpression

    $alias = $null
    if (Test-OtterTokenKind ([TokenKind]::As)) {
        [void](Read-OtterToken)
        $aliasTok = Read-OtterVariableName 'I expected alias name after "as".'
        $alias = $aliasTok.Text
    }

    if (Test-OtterTokenKind ([TokenKind]::With)) {
        [void](Read-OtterToken)
    }

    $where = $null
    $target = $null

    while (-not (Test-OtterTokenKind ([TokenKind]::EndOfFile))) {
        while ((Test-OtterTokenKind ([TokenKind]::Newline)) -or (Test-OtterTokenKind ([TokenKind]::Indent)) -or (Test-OtterTokenKind ([TokenKind]::Dedent))) {
            if (Test-OtterTokenKind ([TokenKind]::Indent)) { $indentCount++ }
            elseif (Test-OtterTokenKind ([TokenKind]::Dedent)) { $indentCount-- }
            [void](Read-OtterToken)
        }

        $k = (Get-OtterCurrentToken).Kind
        if ($k -eq [TokenKind]::With) {
            [void](Read-OtterToken)
        }
        elseif ($k -eq [TokenKind]::Where) {
            [void](Read-OtterToken)
            $where = Read-OtterQueryWhere
        }
        elseif ($k -eq [TokenKind]::Into) {
            [void](Read-OtterToken)
            $targetTok = Read-OtterVariableName 'I expected target variable name after "into".'
            $target = $targetTok.Text
            break
        }
        else {
            break
        }
    }

    if ([string]::IsNullOrEmpty($target)) {
        throw (New-OtterParserError 'I expected "into" and a result name for the aggregate.' (Get-OtterCurrentToken) "$funcName ... from $tableName in db into total")
    }

    while ($indentCount -gt 0 -and ((Test-OtterTokenKind ([TokenKind]::Dedent)) -or (Test-OtterTokenKind ([TokenKind]::Newline)))) {
        if (Test-OtterTokenKind ([TokenKind]::Dedent)) { $indentCount-- }
        [void](Read-OtterToken)
    }
    if (Test-OtterTokenKind ([TokenKind]::Newline)) {
        [void](Read-OtterToken)
    }

    return [QueryAggregateStmt]::new($funcName, $expr, $tableName, $connection, $alias, $where, $target, $start.Line)
}

# D107/D108: the optional trailing clauses of a networking statement -
#   to <host>   on port <port>   and call it <name>
# in any order, on the same line or as an indented continuation block
# (the "core grammar" layout). Consumes the statement's terminating
# Newline itself (and the closing Dedent of a continuation block), so
# callers must NOT assert a Newline afterwards.
function Read-OtterNetClauses {
    param([string]$EndMessage = 'I expected this statement to end here.')
    $result = @{ Host = $null; Port = $null; Target = $null; ServerName = $null; Protocols = $null }
    $depth = 0
    while ($true) {
        $current = Get-OtterCurrentToken
        if ($current.Kind -eq [TokenKind]::Newline) {
            if ($depth -eq 0) {
                if (Test-OtterTokenOffsetKind 1 ([TokenKind]::Indent)) {
                    [void](Read-OtterToken)
                    [void](Read-OtterToken)
                    $depth = 1
                    continue
                }
                [void](Read-OtterToken)
                break
            }
            [void](Read-OtterToken)
            if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Dedent) {
                [void](Read-OtterToken)
                break
            }
            continue
        }
        if ($current.Kind -eq [TokenKind]::To -and $null -eq $result.Host) {
            [void](Read-OtterToken)
            $result.Host = Read-OtterValue
            continue
        }
        if ($current.Text -eq 'on' -and $null -eq $result.Port -and
            ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Text -eq 'port') {
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            $result.Port = Read-OtterValue
            continue
        }
        # D112: for server <server-name-expression>
        if ($current.Text -eq 'for' -and $null -eq $result.ServerName -and
            ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Text -eq 'server') {
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            $result.ServerName = Read-OtterValue
            continue
        }
        # D112: using protocol <protocol-expression> / using protocols <protocols-expression>
        if ($current.Text -eq 'using' -and $null -eq $result.Protocols -and
            ($script:Position + 1) -lt $script:Tokens.Count -and
            ($script:Tokens[$script:Position + 1].Text -eq 'protocol' -or $script:Tokens[$script:Position + 1].Text -eq 'protocols')) {
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            $result.Protocols = Read-OtterValue
            continue
        }
        if ($current.Kind -eq [TokenKind]::And -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::Call)) -and $null -eq $result.Target) {
            [void](Read-OtterToken)
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::It) 'I expected "it" after "call".')
            $nameTok = Read-OtterVariableName 'I expected a name after "call it".'
            $result.Target = $nameTok.Text
            continue
        }
        throw (New-OtterParserError $EndMessage $current)
    }
    return $result
}

# D113: the optional trailing clauses of `listen for tcp` -
#   [on <address>]   on port <port>   and call it <name>
# in any order, on the same line or as an indented continuation block.
function Read-OtterListenClauses {
    param([string]$EndMessage = 'I expected this statement to end here.')
    $result = @{ Address = $null; Port = $null; Target = $null }
    $depth = 0
    while ($true) {
        $current = Get-OtterCurrentToken
        if ($current.Kind -eq [TokenKind]::Newline) {
            if ($depth -eq 0) {
                if (Test-OtterTokenOffsetKind 1 ([TokenKind]::Indent)) {
                    [void](Read-OtterToken)
                    [void](Read-OtterToken)
                    $depth = 1
                    continue
                }
                [void](Read-OtterToken)
                break
            }
            [void](Read-OtterToken)
            if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Dedent) {
                [void](Read-OtterToken)
                break
            }
            continue
        }
        # on port <port> vs on <address>
        if ($current.Text -eq 'on') {
            if (($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Text -eq 'port' -and $null -eq $result.Port) {
                [void](Read-OtterToken) # on
                [void](Read-OtterToken) # port
                $result.Port = Read-OtterValue
                continue
            }
            if ($null -eq $result.Address) {
                [void](Read-OtterToken) # on
                $result.Address = Read-OtterValue
                continue
            }
        }
        if ($current.Kind -eq [TokenKind]::And -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::Call)) -and $null -eq $result.Target) {
            [void](Read-OtterToken) # and
            [void](Read-OtterToken) # call
            [void](Assert-OtterTokenKind ([TokenKind]::It) 'I expected "it" after "call".')
            $nameTok = Read-OtterVariableName 'I expected a name after "call it".'
            $result.Target = $nameTok.Text
            continue
        }
        throw (New-OtterParserError $EndMessage $current)
    }
    return $result
}

# D109: the tail of `encrypt DATA using KEY and call it R` (and decrypt),
# entered once "using" is the current token.
function Read-OtterCryptoCipherRest {
    param([bool]$IsDecrypt, [Node]$Data, [int]$Line)
    [void](Read-OtterToken) # using
    $cipherKey = Read-OtterValue
    $verb = if ($IsDecrypt) { 'decrypt' } else { 'encrypt' }
    [void](Assert-OtterTokenKind ([TokenKind]::And) "I expected ""and call it"" and a name after the key." "$verb data using key and call it result")
    [void](Assert-OtterTokenKind ([TokenKind]::Call) 'I expected "call" after "and".')
    [void](Assert-OtterTokenKind ([TokenKind]::It) 'I expected "it" after "call".')
    $cipherTarget = Read-OtterVariableName 'I expected a name after "call it".'
    [void](Assert-OtterTokenKind ([TokenKind]::Newline) "I expected the $verb statement to end here.")
    return [CryptoCipherStmt]::new($IsDecrypt, $Data, $cipherKey, $cipherTarget.Text, $Line)
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
    $isAggregateQuery = ($start.Kind -in @([TokenKind]::Count, [TokenKind]::Sum, [TokenKind]::Average, [TokenKind]::Minimum, [TokenKind]::Maximum) -or
        ($start.Kind -eq [TokenKind]::Identifier -and $start.Text -in @('total', 'avg', 'min', 'max'))) -and
        (Test-OtterAggregateStatementAhead $script:Position)

    if ($isAggregateQuery) {
        return Read-OtterQueryAggregateStatement
    }

    $statementKind = $start.Kind
    $nextKind = if (($script:Position + 1) -lt $script:Tokens.Count) { $script:Tokens[$script:Position + 1].Kind } else { [TokenKind]::EndOfFile }
    if (-not ($start.Kind -eq [TokenKind]::Count -and $script:OtterBlockDepth -eq 0) -and
        ((Test-OtterIdentifierToken $start) -or ($start.Kind -eq [TokenKind]::ForEach -and $start.Text -eq 'each')) -and
        $nextKind -in @([TokenKind]::Is, [TokenKind]::Are, [TokenKind]::Of, [TokenKind]::IsNot)) {
        $statementKind = [TokenKind]::Identifier
    }

    if ($statementKind -eq [TokenKind]::Identifier -and $start.Text -in @('today', 'now', 'pi')) {
        throw (New-OtterParserError "'$($start.Text)' is a built-in value, not a variable name." $start 'Choose a different variable name, such as "currentDate", "currentTime", or "circleRatio".')
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

    # D103: SPA routing. "route"/"go" are ordinary, completely unreserved
    # identifiers (D33 mechanism 1, same as the isUiTag check just above)
    # - excluded here whenever the line is actually an assignment
    # ("route is ...", "go is ...") so a variable named either word is
    # still fully usable.
    $isRouteDecl = ($start.Text -eq 'route' -and $nextKind -notin @([TokenKind]::Is, [TokenKind]::Are, [TokenKind]::Of, [TokenKind]::IsNot))
    if ($isRouteDecl) {
        [void](Read-OtterToken)
        # "otherwise" only lexes as TokenKind::Otherwise at STATEMENT HEAD
        # (D33 mechanism 2) - one position later, right after "route", it
        # is a plain Identifier, so this must match by TEXT, not kind
        # (confirmed directly: tokenizing "route otherwise shows x" gives
        # Identifier/Identifier/Identifier/Identifier, not TokenKind::Otherwise
        # anywhere - checking the kind here silently fell through to
        # treating "otherwise" as an ordinary route-path variable instead).
        if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'otherwise') {
            [void](Read-OtterToken)
            if (-not (Test-OtterTokenKind ([TokenKind]::Show)) -and -not ((Get-OtterCurrentToken).Text -eq 'shows')) {
                throw (New-OtterParserError 'I expected "shows" and a page after "route otherwise".' (Get-OtterCurrentToken) 'Write: route otherwise shows notFoundPage')
            }
            [void](Read-OtterToken)
            $pageTok = Read-OtterVariableName 'I expected a page name after "shows".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the route statement to end here.')
            return [RouteStmt]::new($null, $true, $pageTok.Text, $start.Line)
        }
        $path = Read-OtterMathExpression
        if (-not (Test-OtterTokenKind ([TokenKind]::Show)) -and -not ((Get-OtterCurrentToken).Text -eq 'shows')) {
            throw (New-OtterParserError 'I expected "shows" and a page after the route path.' (Get-OtterCurrentToken) 'Write: route "/about" shows aboutPage')
        }
        [void](Read-OtterToken)
        $pageTok = Read-OtterVariableName 'I expected a page name after "shows".'
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the route statement to end here.')
        return [RouteStmt]::new($path, $false, $pageTok.Text, $start.Line)
    }
    $isGoStmt = ($start.Text -eq 'go' -and $nextKind -notin @([TokenKind]::Is, [TokenKind]::Are, [TokenKind]::Of, [TokenKind]::IsNot) -and
        (($nextKind -eq [TokenKind]::To) -or
         (($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and $script:Tokens[$script:Position + 1].Text -in @('back', 'forward'))))
    if ($isGoStmt) {
        [void](Read-OtterToken)
        $direction = Get-OtterCurrentToken
        if ($direction.Kind -eq [TokenKind]::Identifier -and $direction.Text -in @('back', 'forward')) {
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the go statement to end here.')
            return [GoNavigateStmt]::new(($direction.Text -eq 'forward'), $start.Line)
        }
        [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a route after "go".' 'Write: go to "/about"')
        $path = Read-OtterMathExpression
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the go statement to end here.')
        return [GoToRouteStmt]::new($path, $start.Line)
    }
    # D104: `watch file "..." and call it X` / `watch folder "..."
    # [recursively] and call it X` - "watch" is an ordinary, unreserved
    # identifier (D33 mechanism 1); the pre-existing NodeKind::Watch
    # ("when X changes") is a completely different feature reached
    # through a different word ("when"), so there is no collision here.
    $isWatchDecl = ($start.Text -eq 'watch' -and $nextKind -notin @([TokenKind]::Is, [TokenKind]::Are, [TokenKind]::Of, [TokenKind]::IsNot) -and
        ($nextKind -eq [TokenKind]::File -or $nextKind -eq [TokenKind]::Folder))
    if ($isWatchDecl) {
        [void](Read-OtterToken)
        $kindTok = Read-OtterToken
        $watchKind = if ($kindTok.Kind -eq [TokenKind]::File) { [WatchKind]::File } else { [WatchKind]::Folder }
        $path = Read-OtterValue
        $recursive = $false
        if ($watchKind -eq [WatchKind]::Folder -and (Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'recursively') {
            [void](Read-OtterToken)
            $recursive = $true
        }
        [void](Assert-OtterTokenKind ([TokenKind]::And) 'I expected "and call it" and a name after the watch path.' 'Write: watch file "settings.json" and call it settingsWatcher')
        [void](Assert-OtterTokenKind ([TokenKind]::Call) 'I expected "call" after "and".')
        [void](Assert-OtterTokenKind ([TokenKind]::It) 'I expected "it" after "call".')
        $nameTok = Read-OtterVariableName 'I expected a name after "call it".'
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the watch statement to end here.')
        return [FileWatchStmt]::new($watchKind, $path, $recursive, $nameTok.Text, $start.Line)
    }

    # D107/D108: `close tcp connection` / `close udp socket`
    if ($start.Text -eq 'close' -and ($script:Position + 1) -lt $script:Tokens.Count -and
        $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -in @('tcp', 'udp') -and
        -not (Test-OtterTokenOffsetKind 2 ([TokenKind]::Newline))) {
        [void](Read-OtterToken) # close
        $netProto = (Read-OtterToken).Text
        $netSock = Read-OtterValue
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) "I expected the close $netProto statement to end here.")
        return [NetCloseStmt]::new($netProto, $netSock, $start.Line)
    }

    # D113: `stop tcp <server>`
    if ($start.Text -eq 'stop' -and ($script:Position + 1) -lt $script:Tokens.Count -and
        $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'tcp' -and
        -not (Test-OtterTokenOffsetKind 2 ([TokenKind]::Newline))) {
        [void](Read-OtterToken) # stop
        [void](Read-OtterToken) # tcp
        $server = Read-OtterValue
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) "I expected the stop tcp statement to end here.")
        return [TcpStopStmt]::new($server, $start.Line)
    }

    # D116B: `cancel <request>`
    if ($start.Text -eq 'cancel' -and $nextKind -notin @([TokenKind]::Is, [TokenKind]::Are, [TokenKind]::Of, [TokenKind]::IsNot)) {
        [void](Read-OtterToken) # cancel
        $requestExpr = Read-OtterValue
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the cancel statement to end here.')
        return [HttpCancelStmt]::new($requestExpr, $start.Line)
    }

    # D110: `set drag data to <expression>`
    if ($start.Text -eq 'set' -and ($script:Position + 2) -lt $script:Tokens.Count -and
        $script:Tokens[$script:Position + 1].Text -eq 'drag' -and $script:Tokens[$script:Position + 2].Text -eq 'data') {
        [void](Read-OtterToken) # set
        [void](Read-OtterToken) # drag
        [void](Read-OtterToken) # data
        [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and the data to attach.' 'set drag data to cardId')
        $dragValue = Read-OtterMathExpression
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the set drag data statement to end here.')
        return [SetDragDataStmt]::new($dragValue, $start.Line)
    }

    # D111: `store secret "name" with value V` / `delete secret "name"`
    if (($start.Text -eq 'store' -or $start.Text -eq 'delete') -and ($script:Position + 1) -lt $script:Tokens.Count -and
        $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and $script:Tokens[$script:Position + 1].Text -eq 'secret' -and
        -not (Test-OtterTokenOffsetKind 2 ([TokenKind]::Is))) {
        [void](Read-OtterToken) # store / delete
        [void](Read-OtterToken) # secret
        $vaultName = Read-OtterValue
        if ($start.Text -eq 'delete') {
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the delete secret statement to end here.')
            return [DeleteSecretStmt]::new($vaultName, $start.Line)
        }
        [void](Assert-OtterTokenKind ([TokenKind]::With) 'I expected "with value" and the secret to store.' 'store secret "api-token" with value token')
        $valueWord = Get-OtterCurrentToken
        if (-not ($valueWord.Kind -eq [TokenKind]::Identifier -and $valueWord.Text -eq 'value')) {
            throw (New-OtterParserError 'I expected "value" after "with".' $valueWord 'store secret "api-token" with value token')
        }
        [void](Read-OtterToken)
        $vaultValue = Read-OtterMathExpression
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the store secret statement to end here.')
        return [StoreSecretStmt]::new($vaultName, $vaultValue, $start.Line)
    }

    # D109: `generate encryption key and call it key`
    if ($start.Text -eq 'generate' -and ($script:Position + 2) -lt $script:Tokens.Count -and
        $script:Tokens[$script:Position + 1].Text -eq 'encryption' -and $script:Tokens[$script:Position + 2].Text -eq 'key') {
        [void](Read-OtterToken) # generate
        [void](Read-OtterToken) # encryption
        [void](Read-OtterToken) # key
        [void](Assert-OtterTokenKind ([TokenKind]::And) 'I expected "and call it" and a name.' 'generate encryption key and call it key')
        [void](Assert-OtterTokenKind ([TokenKind]::Call) 'I expected "call" after "and".')
        [void](Assert-OtterTokenKind ([TokenKind]::It) 'I expected "it" after "call".')
        $keyTarget = Read-OtterVariableName 'I expected a name after "call it".'
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the generate statement to end here.')
        return [GenerateKeyStmt]::new($keyTarget.Text, $start.Line)
    }

    # D107: `open udp [on port 9000] and call it socket`
    if ($start.Text -eq 'open' -and ($script:Position + 1) -lt $script:Tokens.Count -and
        $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'udp') {
        [void](Read-OtterToken) # open
        [void](Read-OtterToken) # udp
        $udpClauses = Read-OtterNetClauses 'I expected "and call it" and a name after "open udp".'
        if ($null -eq $udpClauses.Target) {
            throw (New-OtterParserError 'I expected "and call it" and a name after "open udp".' (Get-OtterCurrentToken) 'Write: open udp on port 9000 and call it socket')
        }
        if ($null -ne $udpClauses.Host) {
            throw (New-OtterParserError '"open udp" takes only "on port" - use "to ..." when sending.' $start 'Write: open udp on port 9000 and call it socket')
        }
        return [UdpOpenStmt]::new($udpClauses.Port, $udpClauses.Target, $start.Line)
    }

    # D113: `listen for tcp [on <address>] on port <port> and call it <name>`
    if ($start.Text -eq 'listen') {
        # Section 21: Reserve "listen securely for tcp"
        if (($script:Position + 3) -lt $script:Tokens.Count -and
            $script:Tokens[$script:Position + 1].Text -eq 'securely' -and
            $script:Tokens[$script:Position + 2].Text -eq 'for' -and
            $script:Tokens[$script:Position + 3].Text -eq 'tcp') {
            throw (New-OtterParserError '"listen securely for tcp" is reserved for TLS servers, which Otter does not support yet.' $start 'Write: listen for tcp on port 8080 and call it server')
        }
        if (($script:Position + 2) -lt $script:Tokens.Count -and
            $script:Tokens[$script:Position + 1].Text -eq 'for' -and
            $script:Tokens[$script:Position + 2].Text -eq 'tcp') {
            [void](Read-OtterToken) # listen
            [void](Read-OtterToken) # for
            [void](Read-OtterToken) # tcp
            $listenClauses = Read-OtterListenClauses 'I expected "on port" and "and call it" in the listen statement.'
            if ($null -eq $listenClauses.Port) {
                throw (New-OtterParserError 'I expected "on port <number>" in "listen for tcp".' $start 'Write: listen for tcp on port 8080 and call it server')
            }
            if ($null -eq $listenClauses.Target) {
                throw (New-OtterParserError 'I expected "and call it" and a name in "listen for tcp".' $start 'Write: listen for tcp on port 8080 and call it server')
            }
            return [TcpListenStmt]::new($listenClauses.Address, $listenClauses.Port, $listenClauses.Target, $start.Line)
        }
    }

    # D106: `close websocket socket [with code 1000] [and reason "Done"]`
    $isCloseWs =($start.Text -eq 'close' -and $nextKind -notin @([TokenKind]::Is, [TokenKind]::Are, [TokenKind]::Of, [TokenKind]::IsNot) -and
        ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
        $script:Tokens[$script:Position + 1].Text -eq 'websocket')
    if ($isCloseWs) {
        [void](Read-OtterToken) # close
        [void](Read-OtterToken) # websocket
        $wsSocket = Read-OtterValue
        $wsCode = $null
        $wsReason = $null
        if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::With -and
            ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
            $script:Tokens[$script:Position + 1].Text -eq 'code') {
            [void](Read-OtterToken) # with
            [void](Read-OtterToken) # code
            $wsCode = Read-OtterValue
        }
        if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::And -and
            ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
            $script:Tokens[$script:Position + 1].Text -eq 'reason') {
            [void](Read-OtterToken) # and
            [void](Read-OtterToken) # reason
            $wsReason = Read-OtterMathExpression
        }
        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the close websocket statement to end here.')
        return [WebSocketCloseStmt]::new($wsSocket, $wsCode, $wsReason, $start.Line)
    }

    # D106: `send "Hello" through socket`
    $isSendWs = ($start.Text -eq 'send' -and $nextKind -notin @([TokenKind]::Is, [TokenKind]::Are, [TokenKind]::Of, [TokenKind]::IsNot))
    if ($isSendWs) {
        [void](Read-OtterToken) # send
        $wsMessage = Read-OtterMathExpression
        $throughTok = Get-OtterCurrentToken
        if (-not ($throughTok.Kind -eq [TokenKind]::Identifier -and $throughTok.Text -eq 'through')) {
            throw (New-OtterParserError 'I expected "through" and a websocket after the message.' $throughTok 'Write: send "Hello" through socket')
        }
        [void](Read-OtterToken) # through
        $wsSocket = Read-OtterValue
        # D108: UDP sends carry "to <host> on port <port>" clauses.
        $sendClauses = Read-OtterNetClauses 'I expected the send statement to end here.'
        if ($null -ne $sendClauses.Host -or $null -ne $sendClauses.Port) {
            if ($null -eq $sendClauses.Host -or $null -eq $sendClauses.Port) {
                throw (New-OtterParserError 'A udp send needs both "to <host>" and "on port <port>".' $start 'Write: send data through socket to "127.0.0.1" on port 9000')
            }
            return [UdpSendStmt]::new($wsMessage, $wsSocket, $sendClauses.Host, $sendClauses.Port, $start.Line)
        }
        return [WebSocketSendStmt]::new($wsMessage, $wsSocket, $start.Line)
    }

    switch ($statementKind) {
        ([TokenKind]::Await) {
            $start = Read-OtterToken
            $nextTok = Get-OtterCurrentToken
            $expr = $null
            if ($nextTok.Kind -eq [TokenKind]::Get -or $nextTok.Text -eq 'get') {
                [void](Read-OtterToken)
                $arg = Read-OtterValue
                $expr = [CallExpr]::new('get', @($arg), $nextTok.Line)
            } elseif (Test-OtterIdentifierToken $nextTok) {
                [void](Read-OtterToken)
                $args = [System.Collections.Generic.List[Node]]::new()
                while (-not (Test-OtterTokenKind ([TokenKind]::Newline)) -and -not (Test-OtterTokenKind ([TokenKind]::Make)) -and -not (Test-OtterTokenKind ([TokenKind]::Into))) {
                    if (Test-OtterTokenKind ([TokenKind]::And)) { [void](Read-OtterToken); continue }
                    $args.Add((Read-OtterValue))
                }
                if ($args.Count -gt 0 -or $script:KnownFunctions.ContainsKey($nextTok.Text)) {
                    $expr = [CallExpr]::new($nextTok.Text, $args.ToArray(), $nextTok.Line)
                } else {
                    $expr = [VariableExpr]::new($nextTok.Text, $nextTok.Line)
                }
            } else {
                $expr = Read-OtterValue
            }

            if (Test-OtterTokenKind ([TokenKind]::Make)) {
                [void](Read-OtterToken)
                $target = (Read-OtterVariableName 'I expected a variable name after "make".').Text
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the await statement to end here.')
                return [AssignStmt]::new($target, [AwaitExpr]::new($expr, $start.Line), $start.Line)
            }
            if (Test-OtterTokenKind ([TokenKind]::Into)) {
                [void](Read-OtterToken)
                $target = (Read-OtterVariableName 'I expected a variable name after "into".').Text
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the await statement to end here.')
                return [AssignStmt]::new($target, [AwaitExpr]::new($expr, $start.Line), $start.Line)
            }
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the await statement to end here.')
            return [AwaitExpr]::new($expr, $start.Line)
        }
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
            # D103: `on route change` - fires after any successful
            # navigation, including browser Back/Forward. Checked before
            # the start/close error below so it doesn't collide with it.
            $stageTok = Get-OtterCurrentToken
            if ($stageTok.Kind -eq [TokenKind]::Identifier -and $stageTok.Text -eq 'route' -and
                ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::Identifier -and
                $script:Tokens[$script:Position + 1].Text -eq 'change') {
                [void](Read-OtterToken) # route
                [void](Read-OtterToken) # change
                return [RouteChangeStmt]::new((Read-OtterBlock), $start.Line)
            }
            # D104: `on change of X` / `on create in X` / `on delete in X`
            # / `on rename in X` - watcher event handlers. "create"/
            # "delete" only lex as their own TokenKind at STATEMENT HEAD
            # (D33 mechanism 2 - confirmed the same way "otherwise" did
            # for D103), so one token after "on" they are plain
            # Identifiers here and must be matched by TEXT.
            if ($stageTok.Kind -eq [TokenKind]::Identifier -and $stageTok.Text -eq 'change' -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::Of))) {
                [void](Read-OtterToken) # change
                [void](Read-OtterToken) # of
                $watcher = Read-OtterValue
                return [WatchEventStmt]::new([WatchEventKind]::Change, $watcher, (Read-OtterBlock), $start.Line)
            }
            if ($stageTok.Kind -eq [TokenKind]::Identifier -and $stageTok.Text -eq 'create' -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::In))) {
                [void](Read-OtterToken) # create
                [void](Read-OtterToken) # in
                $watcher = Read-OtterValue
                return [WatchEventStmt]::new([WatchEventKind]::Create, $watcher, (Read-OtterBlock), $start.Line)
            }
            if ($stageTok.Kind -eq [TokenKind]::Identifier -and $stageTok.Text -eq 'delete' -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::In))) {
                [void](Read-OtterToken) # delete
                [void](Read-OtterToken) # in
                $watcher = Read-OtterValue
                return [WatchEventStmt]::new([WatchEventKind]::Delete, $watcher, (Read-OtterBlock), $start.Line)
            }
            if ($stageTok.Kind -eq [TokenKind]::Identifier -and $stageTok.Text -eq 'rename' -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::In))) {
                [void](Read-OtterToken) # rename
                [void](Read-OtterToken) # in
                $watcher = Read-OtterValue
                return [WatchEventStmt]::new([WatchEventKind]::Rename, $watcher, (Read-OtterBlock), $start.Line)
            }
            # D106, D107/D108, D113: Network event handlers
            # on open of <socket>
            if (($stageTok.Kind -eq [TokenKind]::Open -or $stageTok.Text -eq 'open') -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::Of))) {
                [void](Read-OtterToken) # open
                [void](Read-OtterToken) # of
                $socket = Read-OtterValue
                return [NetworkEventStmt]::new([NetworkEventKind]::Open, $socket, (Read-OtterBlock), $start.Line)
            }
            # D110: drag and drop events, all ordinary WhenStmt nodes.
            # on drag of <control>
            if ($stageTok.Text -eq 'drag' -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::Of))) {
                [void](Read-OtterToken) # drag
                [void](Read-OtterToken) # of
                $dragTarget = Read-OtterValue
                return [WhenStmt]::new($dragTarget, 'drag', (Read-OtterBlock), $start.Line)
            }
            # on drop on <control>
            if ($stageTok.Text -eq 'drop' -and ($script:Position + 1) -lt $script:Tokens.Count -and $script:Tokens[$script:Position + 1].Text -eq 'on') {
                [void](Read-OtterToken) # drop
                [void](Read-OtterToken) # on
                $dropTarget = Read-OtterValue
                return [WhenStmt]::new($dropTarget, 'drop', (Read-OtterBlock), $start.Line)
            }
            # on files dropped on <control>
            if ($stageTok.Text -eq 'files' -and ($script:Position + 2) -lt $script:Tokens.Count -and
                $script:Tokens[$script:Position + 1].Text -eq 'dropped' -and $script:Tokens[$script:Position + 2].Text -eq 'on') {
                [void](Read-OtterToken) # files
                [void](Read-OtterToken) # dropped
                [void](Read-OtterToken) # on
                $filesTarget = Read-OtterValue
                return [WhenStmt]::new($filesTarget, 'files dropped', (Read-OtterBlock), $start.Line)
            }
            # D113: on connection to <server>
            if ($stageTok.Text -eq 'connection' -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::To))) {
                [void](Read-OtterToken) # connection
                [void](Read-OtterToken) # to
                $server = Read-OtterValue
                return [NetworkEventStmt]::new([NetworkEventKind]::Connection, $server, (Read-OtterBlock), $start.Line)
            }
            # D107: on connect of <connection>
            if ($stageTok.Text -eq 'connect' -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::Of))) {
                [void](Read-OtterToken) # connect
                [void](Read-OtterToken) # of
                $socket = Read-OtterValue
                return [NetworkEventStmt]::new([NetworkEventKind]::Connect, $socket, (Read-OtterBlock), $start.Line)
            }
            # D107/D108: on data from <connection or udp socket>
            if ($stageTok.Text -eq 'data' -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::From))) {
                [void](Read-OtterToken) # data
                [void](Read-OtterToken) # from
                $socket = Read-OtterValue
                return [NetworkEventStmt]::new([NetworkEventKind]::Data, $socket, (Read-OtterBlock), $start.Line)
            }
            # on message from <socket>
            if ($stageTok.Text -eq 'message' -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::From))) {
                [void](Read-OtterToken) # message
                [void](Read-OtterToken) # from
                $socket = Read-OtterValue
                return [NetworkEventStmt]::new([NetworkEventKind]::Message, $socket, (Read-OtterBlock), $start.Line)
            }
            # on close of <socket>
            if ($stageTok.Text -eq 'close' -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::Of))) {
                [void](Read-OtterToken) # close
                [void](Read-OtterToken) # of
                $socket = Read-OtterValue
                return [NetworkEventStmt]::new([NetworkEventKind]::Close, $socket, (Read-OtterBlock), $start.Line)
            }
            # on error of <socket>
            if (($stageTok.Kind -eq [TokenKind]::Problem -or $stageTok.Text -eq 'error') -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::Of))) {
                [void](Read-OtterToken) # error
                [void](Read-OtterToken) # of
                $socket = Read-OtterValue
                return [NetworkEventStmt]::new([NetworkEventKind]::Error, $socket, (Read-OtterBlock), $start.Line)
            }
            # D116B: on complete of <request>
            if ($stageTok.Text -eq 'complete' -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::Of))) {
                [void](Read-OtterToken) # complete
                [void](Read-OtterToken) # of
                $target = Read-OtterValue
                return [NetworkEventStmt]::new([NetworkEventKind]::Complete, $target, (Read-OtterBlock), $start.Line)
            }
            # D116B: on cancel of <request>
            if ($stageTok.Text -eq 'cancel' -and (Test-OtterTokenOffsetKind 1 ([TokenKind]::Of))) {
                [void](Read-OtterToken) # cancel
                [void](Read-OtterToken) # of
                $target = Read-OtterValue
                return [NetworkEventStmt]::new([NetworkEventKind]::Cancel, $target, (Read-OtterBlock), $start.Line)
            }
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
            while (-not (Test-OtterTokenKind ([TokenKind]::Newline)) -and -not (Test-OtterTokenKind ([TokenKind]::In))) { $parts.Add((Read-OtterMathExpression)) }
            # D100: say "..." in color "red" - "in" is already a reserved
            # token everywhere (for each X in Y), so this can never collide
            # with a legitimate say-part; a bare "in" here was always a
            # parse error before this, never a regression.
            $colorExpr = $null
            if (Test-OtterTokenKind ([TokenKind]::In)) {
                [void](Read-OtterToken)
                $colorWord = Get-OtterCurrentToken
                if ($colorWord.Kind -ne [TokenKind]::Identifier -or $colorWord.Text -ne 'color') {
                    throw (New-OtterParserError 'I expected "color" after "in".' $colorWord 'say "Error!" in color "red"')
                }
                [void](Read-OtterToken)
                $colorExpr = Read-OtterValue
            }
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the say statement to end here.')
            return [SayStmt]::new($parts.ToArray(), $colorExpr, $start.Line)
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
            # D116B: start get/post/put/delete ... and call it <target>
            $curNext = if (($script:Position + 1) -lt $script:Tokens.Count) { $script:Tokens[$script:Position + 1] } else { $null }
            if ($null -ne $curNext -and (
                $curNext.Kind -in @([TokenKind]::Get, [TokenKind]::Post, [TokenKind]::Put, [TokenKind]::Delete) -or
                $curNext.Text -in @('get', 'post', 'put', 'delete')
            )) {
                [void](Read-OtterToken) # start
                $verbTok = Read-OtterToken # get/post/put/delete
                $method = switch -Exact ($verbTok.Text.ToLowerInvariant()) {
                    'get' { 'GET' }
                    'post' { 'POST' }
                    'put' { 'PUT' }
                    'delete' { 'DELETE' }
                }
                $data = $null
                $asJson = $false
                $url = $null

                if ($method -eq 'GET') {
                    [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a URL after "start get".')
                    $url = Read-OtterValue
                    if (Test-OtterTokenKind ([TokenKind]::As)) {
                        [void](Read-OtterToken)
                        [void](Assert-OtterTokenKind ([TokenKind]::Json) 'I expected "json" after "as".')
                        $asJson = $true
                    }
                } elseif ($method -eq 'DELETE') {
                    [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a URL after "start delete".')
                    $url = Read-OtterValue
                } else {
                    # POST or PUT
                    $data = Read-OtterValue
                    if (Test-OtterTokenKind ([TokenKind]::As)) {
                        [void](Read-OtterToken)
                        [void](Assert-OtterTokenKind ([TokenKind]::Json) 'I expected "json" after "as".')
                        $asJson = $true
                    }
                    [void](Assert-OtterTokenKind ([TokenKind]::To) "I expected ""to"" and a URL after $method data.")
                    $url = Read-OtterValue
                }

                [void](Assert-OtterTokenKind ([TokenKind]::And) 'I expected "and call it" and a variable name.')
                [void](Assert-OtterTokenKind ([TokenKind]::Call) 'I expected "call" after "and".')
                [void](Assert-OtterTokenKind ([TokenKind]::It) 'I expected "it" after "call".')
                $targetTok = Read-OtterVariableName 'I expected a variable name after "call it".'

                $options = Read-OtterHttpOptions
                if ($null -eq $options) {
                    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the start statement to end here.')
                }

                return [HttpStartStmt]::new($method, $url, $data, $asJson, $targetTok.Text, $options, $start.Line)
            }

            [void](Read-OtterToken)
            # D101: start timer workTimer - CREATES and starts a new named
            # timer resource bound to the target name, unlike the existing
            # `start server`/`start api` below (which starts an ALREADY-
            # EXISTING resource a prior statement created). "timer" is
            # checked as plain identifier text first, so this never
            # changes or collides with the existing generic Start parsing.
            $maybeTimer = Get-OtterCurrentToken
            if ($maybeTimer.Kind -eq [TokenKind]::Identifier -and $maybeTimer.Text -eq 'timer') {
                [void](Read-OtterToken)
                $timerTarget = Read-OtterVariableName 'I expected a timer name after "start timer".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the start timer statement to end here.')
                return [StartTimerStmt]::new($timerTarget.Text, $start.Line)
            }
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
            $options = if (-not $continued) { Read-OtterHttpOptions } else { $null }
            if ($null -eq $options) {
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the post statement to end here.')
            }
            if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued post clause to end.') }
            return [HttpPostStmt]::new($data, $url, $target, $asJson, $options, $start.Line)
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
                $options = if (-not $continued) { Read-OtterHttpOptions } else { $null }
                if ($null -eq $options) {
                    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the put statement to end here.')
                }
                if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued put clause to end.') }
                return [HttpPutStmt]::new($firstItem, $url, $target, $true, $options, $start.Line)
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
                $options = if (-not $continued) { Read-OtterHttpOptions } else { $null }
                if ($null -eq $options) {
                    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the put statement to end here.')
                }
                if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued put clause to end.') }
                return [HttpPutStmt]::new($firstItem, $url, $target, $false, $options, $start.Line)
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
            # D100: show progress 50 percent - "progress" is an ordinary
            # identifier, checked by text, ahead of the generic "show a UI
            # resource" fallback below.
            $maybeProgress = Get-OtterCurrentToken
            if ($maybeProgress.Kind -eq [TokenKind]::Identifier -and $maybeProgress.Text -eq 'progress') {
                [void](Read-OtterToken)
                $percentExpr = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Percent) 'I expected "percent" after the progress amount.')
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the show progress statement to end here.')
                return [ShowProgressStmt]::new($percentExpr, $start.Line)
            }
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
            if ($script:Tokens[$script:Position + 1].Kind -eq [TokenKind]::From) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" after count.')
                $from = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" after the starting number.')
                $to = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::As) 'I expected "as" before the counter name.')
                $name = Read-OtterVariableName 'I expected a counter name.'
                return [CountStmt]::new($name.Text, $from, $to, (Read-OtterBlock), $start.Line)
            }
            return Read-OtterQueryAggregateStatement
        }
        ([TokenKind]::Sum) { return Read-OtterQueryAggregateStatement }
        ([TokenKind]::Average) { return Read-OtterQueryAggregateStatement }
        ([TokenKind]::Minimum) { return Read-OtterQueryAggregateStatement }
        ([TokenKind]::Maximum) { return Read-OtterQueryAggregateStatement }
        ([TokenKind]::ForEach) {
            [void](Read-OtterToken)
            $name = Read-OtterVariableName 'I expected a loop variable after "for each".'
            [void](Assert-OtterTokenKind ([TokenKind]::In) 'I expected "in" after the loop variable.')
            $collection = Read-OtterValue
            return [ForEachStmt]::new($name.Text, $collection, (Read-OtterBlock), $start.Line)
        }
        ([TokenKind]::Ask) {
            [void](Read-OtterToken)
            # D100: ask secretly "Password:" and call it pw - "secretly" is
            # an ordinary identifier, checked by text, same as every other
            # contextual modifier in this grammar.
            $secret = $false
            $maybeSecret = Get-OtterCurrentToken
            if ($maybeSecret.Kind -eq [TokenKind]::Identifier -and $maybeSecret.Text -eq 'secretly') {
                [void](Read-OtterToken)
                $secret = $true
            }
            $prompt = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::And) 'I expected "and call it" after the question.')
            [void](Assert-OtterTokenKind ([TokenKind]::Call) 'I expected "call" after "and".')
            [void](Assert-OtterTokenKind ([TokenKind]::It) 'I expected "it" after "call".')
            $name = Read-OtterVariableName 'I expected a variable name after "call it".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the question to end here.')
            return [AskStmt]::new($prompt, $name.Text, $secret, $start.Line)
        }
        ([TokenKind]::Get) {
            if (Test-OtterIsQueryStatement) {
                return Read-OtterQueryStatement
            }
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
            # D94: `get current directory into folder` (also: "folder")
            if ($kind.Kind -eq [TokenKind]::Identifier -and $kind.Text -eq 'current') {
                [void](Read-OtterToken)
                $dirWord = Get-OtterCurrentToken
                if ($dirWord.Kind -eq [TokenKind]::Folder -or ($dirWord.Kind -eq [TokenKind]::Identifier -and ($dirWord.Text -eq 'directory' -or $dirWord.Text -eq 'folder'))) {
                    [void](Read-OtterToken)
                    [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                    $target = Read-OtterVariableName 'I expected a result name after "into".'
                    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                    return [GetSystemFolderStmt]::new([LiteralExpr]::new('current', $start.Line), $target.Text, $start.Line)
                }
                throw (New-OtterParserError 'I expected "directory" or "folder" after "current".' $dirWord 'get current directory into folder')
            }
            # D94: `get arguments into args`
            if ($kind.Kind -eq [TokenKind]::Identifier -and $kind.Text -eq 'arguments') {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $target = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                return [AssignStmt]::new($target.Text, [VariableExpr]::new('arguments', $start.Line), $start.Line)
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
            # D98: get tables from <connection> into <target>
            if ($kind.Kind -eq [TokenKind]::Identifier -and $kind.Text -eq 'tables') {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" after "get tables".' 'Write: get tables from db into tables')
                $connection = Read-OtterValue
                $continued = Test-OtterSoftContinuation
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name after "get tables from db".' 'Write: get tables from db into tables')
                $target = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get tables statement to end here.')
                if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued get tables clause to end.') }
                return [GetTablesStmt]::new($connection, $target.Text, $start.Line)
            }
            # D98: get columns from <table> in <connection> into <target>
            if ($kind.Kind -eq [TokenKind]::Identifier -and $kind.Text -eq 'columns') {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" after "get columns".' 'Write: get columns from "table" in db into columns')
                $table = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::In) 'I expected "in" and the database connection after the table.' 'Write: get columns from "table" in db into columns')
                $connection = Read-OtterValue
                $continued = Test-OtterSoftContinuation
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name after the database connection.' 'Write: get columns from "table" in db into columns')
                $target = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get columns statement to end here.')
                if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued get columns clause to end.') }
                return [GetColumnsStmt]::new($table, $connection, $target.Text, $start.Line)
            }
            if ($kind.Kind -eq [TokenKind]::Json) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a URL after "get json".')
                $url = Read-OtterValue
                $continued = Test-OtterSoftContinuation
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $target = Read-OtterVariableName 'I expected a result name after "into".'
                $options = if (-not $continued) { Read-OtterHttpOptions } else { $null }
                if ($null -eq $options) {
                    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
                }
                if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued get clause to end.') }
                return [HttpGetStmt]::new($url, $target.Text, $true, $options, $start.Line)
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
            $options = if (-not $continued) { Read-OtterHttpOptions } else { $null }
            if ($null -eq $options) {
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the get statement to end here.')
            }
            if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued get clause to end.') }
            return [HttpGetStmt]::new($first, $result.Text, $asJson, $options, $start.Line)
        }
        ([TokenKind]::Set) {
            [void](Read-OtterToken)
            # set text of book to "Learning Otter"                   (D105)
            # set text of "title" in document to "..."
            # "text" is an ordinary identifier, checked by text, same
            # convention as "cursor"/"random" above.
            $maybeXmlText = Get-OtterCurrentToken
            if ($maybeXmlText.Kind -eq [TokenKind]::Identifier -and $maybeXmlText.Text -eq 'text' -and
                (Test-OtterTokenOffsetKind 1 ([TokenKind]::Of))) {
                [void](Read-OtterToken) # text
                [void](Read-OtterToken) # of
                # -PropertyTarget on both reads below: same "the X" trap
                # as the expression-level "text of" case above - a bare
                # "the book"/"the document" at the end of the clause
                # needs it stripped, since there is nothing after it for
                # the OTHER (PropertyTarget-independent) "the X of Y"
                # lookahead to key off.
                $xmlTextTarget = Read-OtterValue -PropertyTarget
                $xmlTextNameIn = $null
                $xmlTextXmlIn = $null
                if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::In) {
                    [void](Read-OtterToken)
                    $xmlTextNameIn = $xmlTextTarget
                    $xmlTextXmlIn = Read-OtterValue -PropertyTarget
                    $xmlTextTarget = $null
                }
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a value.')
                $xmlTextValue = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the set text statement to end here.')
                return [XmlSetTextStmt]::new($xmlTextTarget, $xmlTextNameIn, $xmlTextXmlIn, $xmlTextValue, $start.Line)
            }
            # set attribute "id" of book to "42"                     (D105)
            $maybeXmlAttr = Get-OtterCurrentToken
            if ($maybeXmlAttr.Kind -eq [TokenKind]::Identifier -and $maybeXmlAttr.Text -eq 'attribute') {
                [void](Read-OtterToken)
                $xmlAttrName = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Of) 'I expected "of" and an element after the attribute name.' 'Write: set attribute "id" of book to "42"')
                $xmlAttrElem = Read-OtterValue -PropertyTarget
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a value.')
                $xmlAttrValue = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the set attribute statement to end here.')
                return [XmlSetAttributeStmt]::new($xmlAttrName, $xmlAttrElem, $xmlAttrValue, $start.Line)
            }
            # D101: set random seed to 42 - "random" is only reserved at
            # STATEMENT HEAD (D33 mechanism 2, $script:OtterStatementHeadKeywords),
            # so here, as the SECOND token on the line, it already lexes
            # as a plain identifier - safe to check by text, same
            # convention as every other contextual word in this grammar.
            $maybeRandomSeed = Get-OtterCurrentToken
            if ($maybeRandomSeed.Kind -eq [TokenKind]::Identifier -and $maybeRandomSeed.Text -eq 'random') {
                [void](Read-OtterToken)
                $seedWord = Get-OtterCurrentToken
                if ($seedWord.Kind -ne [TokenKind]::Identifier -or $seedWord.Text -ne 'seed') {
                    throw (New-OtterParserError 'I expected "seed" after "random".' $seedWord 'set random seed to 42')
                }
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" after "seed".')
                $seedExpr = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the set random seed statement to end here.')
                return [SetRandomSeedStmt]::new($seedExpr, $start.Line)
            }
            # D100: set cursor to row 5 column 10 - "cursor"/"row"/"column"
            # are ordinary identifiers, checked by text, same convention as
            # "priority"/"current"/"environment" elsewhere in this grammar.
            $maybeCursor = Get-OtterCurrentToken
            if ($maybeCursor.Kind -eq [TokenKind]::Identifier -and $maybeCursor.Text -eq 'cursor') {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" after "cursor".')
                $rowWord = Get-OtterCurrentToken
                if ($rowWord.Kind -ne [TokenKind]::Identifier -or $rowWord.Text -ne 'row') {
                    throw (New-OtterParserError 'I expected "row" after "to".' $rowWord 'set cursor to row 5 column 10')
                }
                [void](Read-OtterToken)
                $rowExpr = Read-OtterValue
                $columnWord = Get-OtterCurrentToken
                if ($columnWord.Kind -ne [TokenKind]::Identifier -or $columnWord.Text -ne 'column') {
                    throw (New-OtterParserError 'I expected "column" after the row number.' $columnWord 'set cursor to row 5 column 10')
                }
                [void](Read-OtterToken)
                $columnExpr = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the set cursor statement to end here.')
                return [SetCursorPositionStmt]::new($rowExpr, $columnExpr, $start.Line)
            }
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
            # D94: `set current directory to <path>` (also: "folder")
            $maybeCurrentSet = Get-OtterCurrentToken
            if ($maybeCurrentSet.Kind -eq [TokenKind]::Identifier -and $maybeCurrentSet.Text -eq 'current') {
                [void](Read-OtterToken)
                $dirWord = Get-OtterCurrentToken
                if ($dirWord.Kind -eq [TokenKind]::Folder -or ($dirWord.Kind -eq [TokenKind]::Identifier -and ($dirWord.Text -eq 'directory' -or $dirWord.Text -eq 'folder'))) {
                    [void](Read-OtterToken)
                    [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a folder path.')
                    $pathExpr = Read-OtterValue
                    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the set statement to end here.')
                    return [SetCurrentDirectoryStmt]::new($pathExpr, $start.Line)
                }
                throw (New-OtterParserError 'I expected "directory" or "folder" after "current".' $dirWord 'set current directory to "Projects"')
            }
            # D94: `set environment variable "NAME" to "VALUE"`
            $maybeEnvSet = Get-OtterCurrentToken
            if ($maybeEnvSet.Kind -eq [TokenKind]::Identifier -and $maybeEnvSet.Text -eq 'environment') {
                [void](Read-OtterToken)
                $varWord = Get-OtterCurrentToken
                if ($varWord.Kind -ne [TokenKind]::Identifier -or $varWord.Text -ne 'variable') {
                    throw (New-OtterParserError 'I expected "variable" after "environment".' $varWord 'set environment variable "NAME" to "VALUE"')
                }
                [void](Read-OtterToken)
                $nameExpr = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a value.')
                $valExpr = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the set statement to end here.')
                return [SetEnvironmentVariableStmt]::new($nameExpr, $valExpr, $start.Line)
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
            # D101: `wait 5 seconds` / `wait delay seconds` - a general
            # delay, distinguished from `wait for process ...` below by NOT
            # starting with the literal word "for" immediately after
            # "wait". One token of lookahead, no ambiguity.
            if (-not ($forWord.Kind -eq [TokenKind]::Identifier -and $forWord.Text -eq 'for')) {
                $durationExpr = Read-OtterValue
                $unitTok = Get-OtterCurrentToken
                # The lexer only combines a bare time-unit word into its
                # reserved token (TokenKind::Second etc.) when it directly
                # follows a NUMBER LITERAL (D32) - "wait delay seconds"
                # has a variable there instead, so "seconds" arrives here
                # still as a plain Identifier. Match by TEXT as a fallback
                # rather than broadening the lexer's general combining
                # rule (which risks changing behavior at every other call
                # site that relies on it, for a benefit scoped to this one
                # statement).
                $unit = switch ($unitTok.Kind) {
                    ([TokenKind]::Year) { [TimeUnit]::Year }
                    ([TokenKind]::Month) { [TimeUnit]::Month }
                    ([TokenKind]::Day) { [TimeUnit]::Day }
                    ([TokenKind]::Hour) { [TimeUnit]::Hour }
                    ([TokenKind]::Minute) { [TimeUnit]::Minute }
                    ([TokenKind]::Second) { [TimeUnit]::Second }
                    ([TokenKind]::Millisecond) { [TimeUnit]::Millisecond }
                    default { $null }
                }
                if ($null -eq $unit -and $unitTok.Kind -eq [TokenKind]::Identifier) {
                    $unit = switch ($unitTok.Text) {
                        { $_ -in @('year', 'years') } { [TimeUnit]::Year }
                        { $_ -in @('month', 'months') } { [TimeUnit]::Month }
                        { $_ -in @('day', 'days') } { [TimeUnit]::Day }
                        { $_ -in @('hour', 'hours') } { [TimeUnit]::Hour }
                        { $_ -in @('minute', 'minutes') } { [TimeUnit]::Minute }
                        { $_ -in @('second', 'seconds') } { [TimeUnit]::Second }
                        { $_ -in @('millisecond', 'milliseconds') } { [TimeUnit]::Millisecond }
                        default { $null }
                    }
                }
                if ($null -eq $unit) {
                    throw (New-OtterParserError 'I expected a time unit (seconds, minutes, milliseconds, ...) after the wait duration.' $unitTok 'wait 5 seconds')
                }
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the wait statement to end here.')
                return [WaitDelayStmt]::new($durationExpr, $unit, $start.Line)
            }
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
        # zip folder "src" into "archive.zip"                            (D87)
        ([TokenKind]::Zip) {
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::Folder) 'I expected "folder" after "zip".')
            $zipSource = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and an archive path.')
            $zipArchive = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the zip statement to end here.')
            return [ZipFolderStmt]::new($zipSource, $zipArchive, $start.Line)
        }
        # unzip "archive.zip" into "dest"                                (D87)
        ([TokenKind]::Unzip) {
            [void](Read-OtterToken)
            $unzipArchive = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a destination folder.')
            $unzipDest = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the unzip statement to end here.')
            return [UnzipFileStmt]::new($unzipArchive, $unzipDest, $start.Line)
        }
        # hash "text" as "sha256" [with key "secret"] into digest        (D91)
        ([TokenKind]::Hash) {
            [void](Read-OtterToken)
            # D109: `hash password <text> and call it <name>` - distinguished from
            # D91's `hash password as "sha256" ...` (a variable named password)
            # by what follows the value.
            if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'password' -and
                -not (Test-OtterTokenOffsetKind 1 ([TokenKind]::As))) {
                [void](Read-OtterToken) # password
                $passwordExpr = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::And) 'I expected "and call it" and a name.' 'hash password password and call it storedHash')
                [void](Assert-OtterTokenKind ([TokenKind]::Call) 'I expected "call" after "and".')
                [void](Assert-OtterTokenKind ([TokenKind]::It) 'I expected "it" after "call".')
                $hashPwTarget = Read-OtterVariableName 'I expected a name after "call it".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the hash password statement to end here.')
                return [HashPasswordStmt]::new($passwordExpr, $hashPwTarget.Text, $start.Line)
            }
            $hashText = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::As) 'I expected "as" and an algorithm name.')
            $hashAlgorithm = Read-OtterValue
            $hashKey = $null
            if (Test-OtterTokenKind ([TokenKind]::With)) {
                [void](Read-OtterToken)
                $keyWord = Get-OtterCurrentToken
                if ($keyWord.Kind -ne [TokenKind]::Identifier -or $keyWord.Text -ne 'key') {
                    throw (New-OtterParserError 'I expected "key" after "with".' $keyWord 'hash "text" as "sha256" with key "secret" into digest')
                }
                [void](Read-OtterToken)
                $hashKey = Read-OtterValue
            }
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
            $hashTarget = Read-OtterVariableName 'I expected a result name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the hash statement to end here.')
            return [HashTextStmt]::new($hashText, $hashAlgorithm, $hashKey, $hashTarget.Text, $start.Line)
        }
        # encrypt "text" with key "secret" into cipher                    (D92)
        ([TokenKind]::Encrypt) {
            [void](Read-OtterToken)
            $encryptText = Read-OtterValue
            if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'using') {
                return Read-OtterCryptoCipherRest -IsDecrypt $false -Data $encryptText -Line $start.Line
            }
            [void](Assert-OtterTokenKind ([TokenKind]::With) 'I expected "with key" and a key.')
            $keyWord = Get-OtterCurrentToken
            if ($keyWord.Kind -ne [TokenKind]::Identifier -or $keyWord.Text -ne 'key') {
                throw (New-OtterParserError 'I expected "key" after "with".' $keyWord 'encrypt "text" with key "secret" into cipher')
            }
            [void](Read-OtterToken)
            $encryptKey = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
            $encryptTarget = Read-OtterVariableName 'I expected a result name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the encrypt statement to end here.')
            return [EncryptTextStmt]::new($encryptText, $encryptKey, $encryptTarget.Text, $start.Line)
        }
        # decrypt "cipher" with key "secret" into text                    (D92)
        ([TokenKind]::Decrypt) {
            [void](Read-OtterToken)
            $decryptCipher = Read-OtterValue
            if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'using') {
                return Read-OtterCryptoCipherRest -IsDecrypt $true -Data $decryptCipher -Line $start.Line
            }
            [void](Assert-OtterTokenKind ([TokenKind]::With) 'I expected "with key" and a key.')
            $keyWord2 = Get-OtterCurrentToken
            if ($keyWord2.Kind -ne [TokenKind]::Identifier -or $keyWord2.Text -ne 'key') {
                throw (New-OtterParserError 'I expected "key" after "with".' $keyWord2 'decrypt "cipher" with key "secret" into text')
            }
            [void](Read-OtterToken)
            $decryptKey = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
            $decryptTarget = Read-OtterVariableName 'I expected a result name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the decrypt statement to end here.')
            return [DecryptTextStmt]::new($decryptCipher, $decryptKey, $decryptTarget.Text, $start.Line)
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
            # D103: `replace route with "/path"` shares its `replace ...
            # with ...` prefix with the pre-existing text-replacement
            # statement below - told apart by what comes AFTER: the route
            # form has no `in` clause, the text form always requires one.
            # A variable actually named "route" used with the ordinary
            # text-replace statement still works correctly (falls through
            # to the generic form below whenever "in" follows).
            $find = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::With) 'I expected "with" and replacement text.')
            $replacement = Read-OtterMathExpression
            if ($find -is [VariableExpr] -and $find.Name -eq 'route' -and -not (Test-OtterTokenKind ([TokenKind]::In))) {
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the replace route statement to end here.')
                return [ReplaceRouteStmt]::new($replacement, $start.Line)
            }
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
        # convert user to json/csv into text                        (D29, D95)
        # convert text from json/csv into user
        ([TokenKind]::Convert) {
            [void](Read-OtterToken)
            $subject = Read-OtterValue

            if (Test-OtterTokenKind ([TokenKind]::To)) {
                [void](Read-OtterToken)
                $format = Get-OtterCurrentToken
                if ($format.Kind -notin @([TokenKind]::Json, [TokenKind]::Csv)) {
                    throw (New-OtterParserError 'I expected "json" or "csv" after "to".' $format 'Write "convert rows to csv into text" or "convert user to json into text".')
                }
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a variable name.')
                $target = Read-OtterVariableName 'I expected a variable name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the convert statement to end here.')
                if ($format.Kind -eq [TokenKind]::Csv) {
                    return [ConvertToCsvStmt]::new($subject, $target.Text, $start.Line)
                }
                return [ConvertToJsonStmt]::new($subject, $target.Text, $start.Line)
            }

            [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "to json/csv" or "from json/csv" here.')
            $format = Get-OtterCurrentToken
            if ($format.Kind -notin @([TokenKind]::Json, [TokenKind]::Csv)) {
                throw (New-OtterParserError 'I expected "json" or "csv" after "from".' $format 'Write "convert text from csv into rows" or "convert text from json into user".')
            }
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a variable name.')
            $target = Read-OtterVariableName 'I expected a variable name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the convert statement to end here.')
            if ($format.Kind -eq [TokenKind]::Csv) {
                return [ConvertFromCsvStmt]::new($subject, $target.Text, $start.Line)
            }
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
            # read csv from "customers.csv" into customers         (D95)
            if (Test-OtterTokenKind ([TokenKind]::Csv)) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" and a CSV file path.')
                $csvPath = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a variable name.')
                $csvTarget = Read-OtterVariableName 'I expected a variable name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the read statement to end here.')
                return [ReadCsvStmt]::new($csvPath, $csvTarget.Text, $start.Line)
            }
            $path = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a variable name.')
            $target = Read-OtterVariableName 'I expected a variable name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the read statement to end here.')
            return [ReadFileStmt]::new($path, $target.Text, $start.Line)
        }
        ([TokenKind]::Write) {
            [void](Read-OtterToken)
            # write csv rows to "export.csv"                       (D95)
            if (Test-OtterTokenKind ([TokenKind]::Csv)) {
                [void](Read-OtterToken)
                $rows = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a CSV file path.')
                $csvPath = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the write CSV statement to end here.')
                return [WriteCsvStmt]::new($rows, $csvPath, $start.Line)
            }
            # write xml document to file "books.xml"                (D105)
            if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'xml') {
                [void](Read-OtterToken)
                $xmlExpr = Read-OtterValue -PropertyTarget
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a file path.')
                [void](Assert-OtterTokenKind ([TokenKind]::File) 'I expected "file" and a path.' 'Write: write xml document to file "books.xml"')
                $xmlPath = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the write xml statement to end here.')
                return [XmlWriteFileStmt]::new($xmlExpr, $xmlPath, $start.Line)
            }
            # write bytes data to file "copy.png" [atomically]      (D115)
            if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'bytes') {
                [void](Read-OtterToken)
                $dataExpr = Read-OtterValue -PropertyTarget
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a file path.' 'Write: write bytes data to file "copy.png"')
                [void](Assert-OtterTokenKind ([TokenKind]::File) 'I expected "file" and a path.' 'Write: write bytes data to file "copy.png"')
                $filePath = Read-OtterValue
                $atomic = $false
                $atomicWord = Get-OtterCurrentToken
                if ($atomicWord.Kind -eq [TokenKind]::Identifier -and $atomicWord.Text -eq 'atomically') {
                    [void](Read-OtterToken)
                    $atomic = $true
                }
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the write bytes statement to end here.')
                return [WriteBytesFileStmt]::new($dataExpr, $filePath, $atomic, $start.Line)
            }
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
                $options = if (-not $continued) { Read-OtterHttpOptions } else { $null }
                if ($null -eq $options) {
                    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the delete statement to end here.')
                }
                if ($continued) { [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the continued delete clause to end.') }
                return [HttpDeleteStmt]::new($url, $target, $options, $start.Line)
            }
            [void](Assert-OtterTokenKind ([TokenKind]::File) 'I expected "file" after delete.')
            $path = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the delete statement to end here.')
            return [DeleteFileStmt]::new($path, $start.Line)
        }
        # download file from <url> to <path>                            (D96)
        ([TokenKind]::Download) {
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::File) 'I expected "file" after "download".' 'Write: download file from <url> to <path>')
            [void](Assert-OtterTokenKind ([TokenKind]::From) 'I expected "from" after "file".' 'Write: download file from <url> to <path>')
            $url = Read-OtterMathExpression
            [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a destination path.' 'Write: download file from <url> to <path>')
            $path = Read-OtterMathExpression
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the download statement to end here.')
            return [DownloadFileStmt]::new($url, $path, $start.Line)
        }
        # connect database into db                                     (D97)
        # connect to websocket "wss://..." [using protocol P] and call it X  (D106)
        # connect to tcp "host" on port P and call it X                     (D107)
        # connect securely to tcp "host" on port P [for server S] [using protocol[s] P] and call it X (D112)
        ([TokenKind]::Connect) {
            [void](Read-OtterToken)
            $isSecure = $false
            if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'securely') {
                [void](Read-OtterToken)
                $isSecure = $true
                if ((Get-OtterCurrentToken).Kind -ne [TokenKind]::To) {
                    throw (New-OtterParserError 'I expected "to tcp" after "connect securely".' (Get-OtterCurrentToken) 'Write: connect securely to tcp "example.com" on port 443 and call it connection')
                }
            }
            # D106: "to" right after "connect" is unambiguous - D97's own
            # config expression never legitimately starts with the
            # reserved "to" token, so no backtracking is needed here.
            if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::To) {
                [void](Read-OtterToken)
                # D107, D112: connect [securely] to tcp <host> on port <port> and call it <name>
                if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'tcp') {
                    [void](Read-OtterToken)
                    $tcpHost = Read-OtterValue
                    $verbPrefix = if ($isSecure) { 'connect securely to tcp' } else { 'connect to tcp' }
                    $tcpClauses = Read-OtterNetClauses "I expected `"on port`" and `"and call it`" in the $verbPrefix statement."
                    if ($null -eq $tcpClauses.Port) {
                        throw (New-OtterParserError "I expected `"on port <number>`" in `"$verbPrefix`"." $start "Write: $verbPrefix `"localhost`" on port 9000 and call it connection")
                    }
                    if ($null -eq $tcpClauses.Target) {
                        throw (New-OtterParserError "I expected `"and call it`" and a name in `"$verbPrefix`"." $start "Write: $verbPrefix `"localhost`" on port 9000 and call it connection")
                    }
                    return [TcpConnectStmt]::new($tcpHost, $tcpClauses.Port, $tcpClauses.Target, $isSecure, $tcpClauses.ServerName, $tcpClauses.Protocols, $start.Line)
                }
                if ($isSecure) {
                    throw (New-OtterParserError 'I expected "tcp" after "connect securely to".' (Get-OtterCurrentToken) 'Write: connect securely to tcp "example.com" on port 443 and call it connection')
                }
                if (-not ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'websocket')) {
                    throw (New-OtterParserError 'I expected "websocket" or "tcp" after "connect to".' (Get-OtterCurrentToken) 'Write: connect to websocket "wss://example.com" and call it chat')
                }
                [void](Read-OtterToken)
                $wsUrl = Read-OtterValue
                $wsProtocol = $null
                if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'using') {
                    [void](Read-OtterToken)
                    if (-not ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'protocol')) {
                        throw (New-OtterParserError 'I expected "protocol" after "using".' (Get-OtterCurrentToken) 'Write: connect to websocket "..." using protocol "chat" and call it chat')
                    }
                    [void](Read-OtterToken)
                    $wsProtocol = Read-OtterValue
                }
                [void](Assert-OtterTokenKind ([TokenKind]::And) 'I expected "and call it" and a name.' 'Write: connect to websocket "..." and call it chat')
                [void](Assert-OtterTokenKind ([TokenKind]::Call) 'I expected "call" after "and".')
                [void](Assert-OtterTokenKind ([TokenKind]::It) 'I expected "it" after "call".')
                $wsTarget = Read-OtterVariableName 'I expected a name after "call it".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the connect statement to end here.')
                return [WebSocketConnectStmt]::new($wsUrl, $wsProtocol, $wsTarget.Text, $start.Line)
            }
            $config = Read-OtterMathExpression
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a variable name after the database configuration.' 'Write: connect database into db')
            $target = Read-OtterVariableName 'I expected a variable name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the connect statement to end here.')
            return [ConnectDbStmt]::new($config, $target.Text, $start.Line)
        }
        # disconnect db                                                (D97)
        ([TokenKind]::Disconnect) {
            [void](Read-OtterToken)
            $connection = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the disconnect statement to end here.')
            return [DisconnectDbStmt]::new($connection, $start.Line)
        }
        # query db with ... into tasks                                 (D97)
        ([TokenKind]::Query) {
            [void](Read-OtterToken)
            $connection = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::With) 'I expected "with" after the database connection.' 'Write: query db with "select ... " into tasks')
            $parameters = [System.Collections.Generic.List[DbParameter]]::new()
            $queryExpr = $null
            $target = $null

            if (Test-OtterTokenKind ([TokenKind]::Newline)) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Indent) 'I expected an indented block after "with".')
                Skip-OtterNewlines
                $queryExpr = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected a newline after the SQL query string.')
                Skip-OtterNewlines

                while (-not (Test-OtterTokenKind ([TokenKind]::Dedent)) -and -not (Test-OtterTokenKind ([TokenKind]::BlockEnd)) -and -not (Test-OtterTokenKind ([TokenKind]::EndOfFile))) {
                    $curTok = Get-OtterCurrentToken
                    if ($curTok.Kind -eq [TokenKind]::Parameter -or ($curTok.Kind -eq [TokenKind]::Identifier -and $curTok.Text -eq 'parameter')) {
                        [void](Read-OtterToken)
                        $paramNameTok = Get-OtterCurrentToken
                        if ($paramNameTok.Kind -notin @([TokenKind]::String, [TokenKind]::Identifier)) {
                            throw (New-OtterParserError 'I expected a parameter name (such as "id" or id) after "parameter".' $paramNameTok 'Write: parameter "id" is userId')
                        }
                        [void](Read-OtterToken)
                        $paramName = if ($paramNameTok.Kind -eq [TokenKind]::String) { $paramNameTok.Value } else { $paramNameTok.Text }
                        [void](Assert-OtterTokenKind ([TokenKind]::Is) 'I expected "is" after the parameter name.' "Write: parameter `"$paramName`" is value")
                        $paramValue = Read-OtterMathExpression
                        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the parameter definition to end here.')
                        Skip-OtterNewlines
                        $parameters.Add([DbParameter]::new($paramName, $paramValue, $paramNameTok.Line))
                    } else {
                        throw (New-OtterParserError "I expected 'parameter' or the end of the query block, but found '$($curTok.Text)'." $curTok 'Write: parameter "name" is value')
                    }
                }

                [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the query block to end.')
                if (Test-OtterTokenKind ([TokenKind]::BlockEnd)) { [void](Read-OtterToken); Skip-OtterNewlines }
                Skip-OtterNewlines

                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result variable name for the query.' 'Write: query db with ... into tasks')
                $targetTok = Read-OtterVariableName 'I expected a variable name after "into".'
                $target = $targetTok.Text
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the query statement to end here.')
            } else {
                $queryExpr = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result variable name for the query.' 'Write: query db with "select ... " into tasks')
                $targetTok = Read-OtterVariableName 'I expected a variable name after "into".'
                $target = $targetTok.Text
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the query statement to end here.')
            }

            return [DbQueryStmt]::new($connection, $queryExpr, $parameters.ToArray(), $target, $start.Line)
        }
        # execute db with ... [into result]                            (D97)
        ([TokenKind]::Execute) {
            [void](Read-OtterToken)
            $connection = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::With) 'I expected "with" after the database connection.' 'Write: execute db with "insert ... " into result')
            $parameters = [System.Collections.Generic.List[DbParameter]]::new()
            $commandExpr = $null
            $target = $null

            if (Test-OtterTokenKind ([TokenKind]::Newline)) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Indent) 'I expected an indented block after "with".')
                Skip-OtterNewlines
                $commandExpr = Read-OtterMathExpression
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected a newline after the SQL command string.')
                Skip-OtterNewlines

                while (-not (Test-OtterTokenKind ([TokenKind]::Dedent)) -and -not (Test-OtterTokenKind ([TokenKind]::BlockEnd)) -and -not (Test-OtterTokenKind ([TokenKind]::EndOfFile))) {
                    $curTok = Get-OtterCurrentToken
                    if ($curTok.Kind -eq [TokenKind]::Parameter -or ($curTok.Kind -eq [TokenKind]::Identifier -and $curTok.Text -eq 'parameter')) {
                        [void](Read-OtterToken)
                        $paramNameTok = Get-OtterCurrentToken
                        if ($paramNameTok.Kind -notin @([TokenKind]::String, [TokenKind]::Identifier)) {
                            throw (New-OtterParserError 'I expected a parameter name (such as "id" or id) after "parameter".' $paramNameTok 'Write: parameter "id" is userId')
                        }
                        [void](Read-OtterToken)
                        $paramName = if ($paramNameTok.Kind -eq [TokenKind]::String) { $paramNameTok.Value } else { $paramNameTok.Text }
                        [void](Assert-OtterTokenKind ([TokenKind]::Is) 'I expected "is" after the parameter name.' "Write: parameter `"$paramName`" is value")
                        $paramValue = Read-OtterMathExpression
                        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the parameter definition to end here.')
                        Skip-OtterNewlines
                        $parameters.Add([DbParameter]::new($paramName, $paramValue, $paramNameTok.Line))
                    } else {
                        throw (New-OtterParserError "I expected 'parameter' or the end of the execute block, but found '$($curTok.Text)'." $curTok 'Write: parameter "name" is value')
                    }
                }

                [void](Assert-OtterTokenKind ([TokenKind]::Dedent) 'I expected the execute block to end.')
                if (Test-OtterTokenKind ([TokenKind]::BlockEnd)) { [void](Read-OtterToken); Skip-OtterNewlines }
                Skip-OtterNewlines

                if (Test-OtterTokenKind ([TokenKind]::Into)) {
                    [void](Read-OtterToken)
                    $targetTok = Read-OtterVariableName 'I expected a variable name after "into".'
                    $target = $targetTok.Text
                    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the execute statement to end here.')
                }
            } else {
                $commandExpr = Read-OtterMathExpression
                if (Test-OtterTokenKind ([TokenKind]::Into)) {
                    [void](Read-OtterToken)
                    $targetTok = Read-OtterVariableName 'I expected a variable name after "into".'
                    $target = $targetTok.Text
                }
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the execute statement to end here.')
            }

            return [DbExecuteStmt]::new($connection, $commandExpr, $parameters.ToArray(), $target, $start.Line)
        }
        # begin transaction on db into tx                              (D97)
        ([TokenKind]::BeginTransaction) {
            [void](Read-OtterToken)
            $onTok = Get-OtterCurrentToken
            if ($onTok.Kind -ne [TokenKind]::On -and -not ($onTok.Kind -eq [TokenKind]::Identifier -and $onTok.Text -eq 'on')) {
                throw (New-OtterParserError 'I expected "on" after "begin transaction".' $onTok 'Write: begin transaction on db into tx')
            }
            [void](Read-OtterToken)
            $connection = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a transaction variable name.' 'Write: begin transaction on db into tx')
            $target = Read-OtterVariableName 'I expected a transaction variable name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the begin transaction statement to end here.')
            return [BeginTransactionStmt]::new($connection, $target.Text, $start.Line)
        }
        # commit tx                                                    (D97)
        ([TokenKind]::Commit) {
            [void](Read-OtterToken)
            $transaction = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the commit statement to end here.')
            return [CommitTransactionStmt]::new($transaction, $start.Line)
        }
        # rollback tx                                                  (D97)
        ([TokenKind]::Rollback) {
            [void](Read-OtterToken)
            $transaction = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the rollback statement to end here.')
            return [RollbackTransactionStmt]::new($transaction, $start.Line)
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
            # D100: choose from options into choice - "from" is already a
            # reserved token everywhere, trivially distinguishable from the
            # File/Folder branches below (different TokenKind entirely, no
            # ambiguity).
            if (Test-OtterTokenKind ([TokenKind]::From)) {
                [void](Read-OtterToken)
                $optionsExpr = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
                $target = Read-OtterVariableName 'I expected a result name after "into".'
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the choose statement to end here.')
                return [ChooseFromListStmt]::new($optionsExpr, $target.Text, $start.Line)
            }
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
            # D84: `run command "..." on remote "host" using credential "n"
            # [into result]` - only valid after `run command`, checked as
            # plain identifier text before the existing `into` handling.
            $maybeOn = Get-OtterCurrentToken
            if ($isCommand -and $maybeOn.Kind -eq [TokenKind]::Identifier -and $maybeOn.Text -eq 'on') {
                [void](Read-OtterToken)
                $remoteWord = Get-OtterCurrentToken
                if ($remoteWord.Kind -ne [TokenKind]::Identifier -or $remoteWord.Text -ne 'remote') {
                    throw (New-OtterParserError 'I expected "remote" after "on".' $remoteWord 'run command "..." on remote "host" using credential "n"')
                }
                [void](Read-OtterToken)
                $hostName = Read-OtterValue
                $usingWord = Get-OtterCurrentToken
                if ($usingWord.Kind -ne [TokenKind]::Identifier -or $usingWord.Text -ne 'using') {
                    throw (New-OtterParserError 'I expected "using credential" after the host name.' $usingWord 'run command "..." on remote "host" using credential "n"')
                }
                [void](Read-OtterToken)
                $credentialWord = Get-OtterCurrentToken
                if ($credentialWord.Kind -ne [TokenKind]::Identifier -or $credentialWord.Text -ne 'credential') {
                    throw (New-OtterParserError 'I expected "credential" after "using".' $credentialWord 'run command "..." on remote "host" using credential "n"')
                }
                [void](Read-OtterToken)
                $credentialName = Read-OtterValue
                $remoteResultTarget = $null
                if (Test-OtterTokenKind ([TokenKind]::Into)) {
                    [void](Read-OtterToken)
                    $remoteResultTarget = (Read-OtterVariableName 'I expected a variable name after "into".').Text
                }
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the run statement to end here.')
                return [RunRemoteCommandStmt]::new($target, $hostName, $credentialName, $remoteResultTarget, $start.Line)
            }
            # D85: `run command "..." over ssh to "user@host" [into result]`
            if ($isCommand -and $maybeOn.Kind -eq [TokenKind]::Identifier -and $maybeOn.Text -eq 'over') {
                [void](Read-OtterToken)
                $sshWord = Get-OtterCurrentToken
                if ($sshWord.Kind -ne [TokenKind]::Identifier -or $sshWord.Text -ne 'ssh') {
                    throw (New-OtterParserError 'I expected "ssh" after "over".' $sshWord 'run command "..." over ssh to "user@host"')
                }
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::To) 'I expected "to" and a host.')
                $sshHostName = Read-OtterValue
                $sshResultTarget = $null
                if (Test-OtterTokenKind ([TokenKind]::Into)) {
                    [void](Read-OtterToken)
                    $sshResultTarget = (Read-OtterVariableName 'I expected a variable name after "into".').Text
                }
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the run statement to end here.')
                return [RunSshCommandStmt]::new($target, $sshHostName, $sshResultTarget, $start.Line)
            }
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
            $script:KnownFunctions[$name.Text] = $parameters.Count
            return [FunctionDefStmt]::new($name.Text, $parameters.ToArray(), (Read-OtterBlock), $start.Line)
        }
        ([TokenKind]::Return) {
            [void](Read-OtterToken)
            # D104: `stop watching X` - "stop" always lexes to
            # TokenKind::Return (it doubles as the bare "stop" return
            # signal), so this is disambiguated right here rather than
            # via a pre-switch text check like watch/route/go above.
            if ($start.Text -eq 'stop' -and (Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'watching') {
                [void](Read-OtterToken)
                $watcher = Read-OtterValue
                [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the stop watching statement to end here.')
                return [StopWatchingStmt]::new($watcher, $start.Line)
            }
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
            # add element "book" to library [and call it book] [with text "..."]   (D105)
            # Backtracking, not a hard commit: "element" is an ordinary
            # identifier, so `add element to counter` (D12's plain "add X
            # to Y", where a variable is genuinely named "element") must
            # still parse that way - confirmed as a real bug without
            # this: an unconditional attempt here threw "I expected a
            # value here" on "to" instead of falling through to D12.
            $savedXmlAddPos = $script:Position
            $xmlAddOk = $true
            $xmlAddResult = $null
            if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'element') {
                try {
                    [void](Read-OtterToken)
                    $elemName = Read-OtterValue
                    $elemText = $null
                    if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::With) {
                        [void](Read-OtterToken)
                        if (-not ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'text')) {
                            throw 'not the xml add-element form'
                        }
                        [void](Read-OtterToken)
                        $elemText = Read-OtterValue
                    }
                    if ((Get-OtterCurrentToken).Kind -ne [TokenKind]::To) { throw 'not the xml add-element form' }
                    [void](Read-OtterToken)
                    $xmlExpr = Read-OtterValue -PropertyTarget
                    $elemTarget = $null
                    if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::And) {
                        [void](Read-OtterToken)
                        [void](Assert-OtterTokenKind ([TokenKind]::Call) 'I expected "call" after "and".')
                        [void](Assert-OtterTokenKind ([TokenKind]::It) 'I expected "it" after "call".')
                        $elemTargetTok = Read-OtterVariableName 'I expected a name after "call it".'
                        $elemTarget = $elemTargetTok.Text
                    }
                    [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the add element statement to end here.')
                    $xmlAddResult = [XmlAddElementStmt]::new($elemName, $xmlExpr, $elemText, $elemTarget, $start.Line)
                } catch {
                    $xmlAddOk = $false
                }
            } else {
                $xmlAddOk = $false
            }
            if ($xmlAddOk) {
                return $xmlAddResult
            }
            $script:Position = $savedXmlAddPos
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
            # remove element book                                   (D105)
            # remove attribute "id" from book
            # Backtracking, not a hard commit - "element"/"attribute" are
            # ordinary identifiers, so D12's plain "remove X from Y" with
            # a variable genuinely named "element"/"attribute" must still
            # parse that way (same class of bug as "add element" above).
            if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'element') {
                $savedXmlRemElemPos = $script:Position
                $xmlRemElemOk = $true
                $xmlRemElemResult = $null
                try {
                    [void](Read-OtterToken)
                    $elemExpr = Read-OtterValue -PropertyTarget
                    if ((Get-OtterCurrentToken).Kind -ne [TokenKind]::Newline) { throw 'not the xml remove-element form' }
                    [void](Read-OtterToken)
                    $xmlRemElemResult = [XmlRemoveElementStmt]::new($elemExpr, $start.Line)
                } catch {
                    $xmlRemElemOk = $false
                }
                if ($xmlRemElemOk) { return $xmlRemElemResult }
                $script:Position = $savedXmlRemElemPos
            }
            if ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'attribute') {
                $savedXmlRemAttrPos = $script:Position
                $xmlRemAttrOk = $true
                $xmlRemAttrResult = $null
                try {
                    [void](Read-OtterToken)
                    $attrName = Read-OtterValue
                    if ((Get-OtterCurrentToken).Kind -ne [TokenKind]::From) { throw 'not the xml remove-attribute form' }
                    [void](Read-OtterToken)
                    $attrElem = Read-OtterValue -PropertyTarget
                    if ((Get-OtterCurrentToken).Kind -ne [TokenKind]::Newline) { throw 'not the xml remove-attribute form' }
                    [void](Read-OtterToken)
                    $xmlRemAttrResult = [XmlRemoveAttributeStmt]::new($attrName, $attrElem, $start.Line)
                } catch {
                    $xmlRemAttrOk = $false
                }
                if ($xmlRemAttrOk) { return $xmlRemAttrResult }
                $script:Position = $savedXmlRemAttrPos
            }
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
            if ($name.Text -eq 'pi') {
                throw (New-OtterParserError "'pi' is a built-in value, not a variable name." $name 'Choose a different variable name, such as "circleRatio".')
            }
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
                # D110: `card is panel with draggable is true` - the article is
                # optional, but ONLY for "panel ... with", so a plain variable
                # named panel (`x is panel`) keeps meaning an assignment.
                $isBarePanel = ((Get-OtterCurrentToken).Kind -eq [TokenKind]::Identifier -and (Get-OtterCurrentToken).Text -eq 'panel' -and
                    (Test-OtterTokenOffsetKind 1 ([TokenKind]::With)))
                if ((Test-OtterTokenKind ([TokenKind]::A)) -or $isBarePanel) {
                    if ($isBarePanel) {
                        [void](Read-OtterToken)
                        $typeName = 'panel'
                    } else {
                        [void](Read-OtterToken)
                        $typeName = Read-OtterObjectTypeName
                    }
                    if (Test-OtterTokenKind ([TokenKind]::With)) {
                        [void](Read-OtterToken)
                        $properties = Read-OtterInlineObjectProperties -TypeName $typeName
                    } elseif ($typeName -eq 'thing' -or -not $script:KnownTypes.ContainsKey($typeName)) {
                        $properties = Read-OtterObjectBlockProperties -AllowEmpty ($typeName -eq 'thing') -TypeName $typeName
                    } else {
                        [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the object definition to end here.')
                        if (Test-OtterTokenKind ([TokenKind]::Indent)) {
                            $indent = Get-OtterCurrentToken
                            throw (New-OtterParserError "'$typeName' is a declared type, so its properties must use 'with' on the same line." $indent "Write '$($name.Text) is a $typeName with property value'.")
                        }
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
        ([TokenKind]::Indent) {
            throw (New-OtterParserError "Unexpected indentation." $start 'Remove the extra space or tab at the beginning of the line.')
        }
        ([TokenKind]::Dedent) {
            throw (New-OtterParserError "Unexpected unindent." $start 'Make sure block indentation lines up.')
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
