using module ..\Otter.Contract.psm1

# Milestone 1 lexer: source text becomes the shared Token[] contract.

$script:OtterKeywords = @{
    'say' = [TokenKind]::Say
    'ask' = [TokenKind]::Ask
    'if' = [TokenKind]::If
    'while' = [TokenKind]::While
    'repeat' = [TokenKind]::Repeat
    'count' = [TokenKind]::Count
    'as' = [TokenKind]::As
    'in' = [TokenKind]::In
    'return' = [TokenKind]::Return
    'is' = [TokenKind]::Is
    'or' = [TokenKind]::Or
    'not' = [TokenKind]::Not
    'and' = [TokenKind]::And
    'plus' = [TokenKind]::And
    'minus' = [TokenKind]::Minus
    'times' = [TokenKind]::Times
    'make' = [TokenKind]::Make
    'makes' = [TokenKind]::Make
    'add' = [TokenKind]::Add
    'remove' = [TokenKind]::Remove
    'to' = [TokenKind]::To
    'from' = [TokenKind]::From
    'are' = [TokenKind]::Are
    'of' = [TokenKind]::Of
    'when' = [TokenKind]::When
    'put' = [TokenKind]::Put
    'show' = [TokenKind]::Show
    'gone' = [TokenKind]::Gone
    'files' = [TokenKind]::Files
    'folders' = [TokenKind]::Folders
    'folder' = [TokenKind]::Folder
    'subfolders' = [TokenKind]::Subfolders
    'with' = [TokenKind]::With
    'by' = [TokenKind]::By
    'where' = [TokenKind]::Where
    # Reserved for later language versions. Lexing them now prevents a future
    # keyword from silently changing an existing program's meaning.
    'a' = [TokenKind]::A
    'has' = [TokenKind]::Has
    'file' = [TokenKind]::File
    'into' = [TokenKind]::Into
    'set' = [TokenKind]::Set
    'command' = [TokenKind]::Command
    'open' = [TokenKind]::Open
    'true' = [TokenKind]::True
    'false' = [TokenKind]::False
    'at' = [TokenKind]::At
    'await' = [TokenKind]::Await
}

# D33 mechanism 2: these words introduce their existing statement forms only
# when they are the first non-indent token on a logical line. Everywhere else
# they begin as ordinary identifiers and may be made structural by a more
# specific contextual rule below.
$script:OtterStatementHeadKeywords = @{
    'copy' = [TokenKind]::Copy; 'move' = [TokenKind]::Move
    'delete' = [TokenKind]::Delete; 'create' = [TokenKind]::Create
    'read' = [TokenKind]::Read; 'write' = [TokenKind]::Write
    'append' = [TokenKind]::Append
    'sort' = [TokenKind]::Sort; 'reverse' = [TokenKind]::Reverse
    'replace' = [TokenKind]::Replace; 'split' = [TokenKind]::Split
    'join' = [TokenKind]::Join; 'find' = [TokenKind]::Find
    'get' = [TokenKind]::Get; 'try' = [TokenKind]::Try
    'run' = [TokenKind]::Run; 'log' = [TokenKind]::Log
    'warn' = [TokenKind]::Warn; 'error' = [TokenKind]::Problem
    'random' = [TokenKind]::Random; 'json' = [TokenKind]::Json
    'convert' = [TokenKind]::Convert; 'format' = [TokenKind]::Format
    'today' = [TokenKind]::Today; 'now' = [TokenKind]::Now
    'between' = [TokenKind]::Between; 'otherwise' = [TokenKind]::Otherwise
    'increase' = [TokenKind]::Add; 'decrease' = [TokenKind]::Remove
    'each' = [TokenKind]::ForEach; 'stop' = [TokenKind]::Return
    'post' = [TokenKind]::Post
    'respond' = [TokenKind]::Respond; 'start' = [TokenKind]::Start
    'listen' = [TokenKind]::Listen
    # D56: declarative UI, reactivity, animation
    'layout' = [TokenKind]::Layout; 'gap' = [TokenKind]::Gap
    'state' = [TokenKind]::State; 'derive' = [TokenKind]::Derive
    'memo' = [TokenKind]::Memo; 'on' = [TokenKind]::On
    'await' = [TokenKind]::Await; 'shared' = [TokenKind]::Shared
    'use' = [TokenKind]::Use; 'focus' = [TokenKind]::Focus
    'hide' = [TokenKind]::Hide; 'animate' = [TokenKind]::Animate
    'motion' = [TokenKind]::Motion
}

# D32: singular and plural spell the same unit, the way make/makes collapse.
$script:OtterTimeUnitWords = @{
    'year' = [TokenKind]::Year; 'years' = [TokenKind]::Year
    'month' = [TokenKind]::Month; 'months' = [TokenKind]::Month
    'day' = [TokenKind]::Day; 'days' = [TokenKind]::Day
    'hour' = [TokenKind]::Hour; 'hours' = [TokenKind]::Hour
    'minute' = [TokenKind]::Minute; 'minutes' = [TokenKind]::Minute
    'second' = [TokenKind]::Second; 'seconds' = [TokenKind]::Second
}

function New-OtterToken {
    param([TokenKind]$Kind, [string]$Text, [object]$Value, [int]$Line, [int]$Column)
    return [Token]::new($Kind, $Text, $Value, $Line, $Column)
}

function Get-OtterIndentLevel {
    param([string]$Line, [int]$LineNumber)

    $index = 0
    $level = 0
    while ($index -lt $Line.Length) {
        if ($Line[$index] -eq "`t") {
            $index++
            $level++
            continue
        }
        if ($Line[$index] -ne ' ') { break }

        $spaceStart = $index
        while ($index -lt $Line.Length -and $Line[$index] -eq ' ') { $index++ }
        $spaceCount = $index - $spaceStart
        if (($spaceCount % 4) -ne 0) {
            throw [OtterError]::new(
                'Indentation must use groups of 4 spaces or tabs.',
                $LineNumber, 'lexer', $spaceStart + 1, $Line, 'Use 4 spaces for each indentation level.'
            )
        }
        $level += [int]($spaceCount / 4)
    }
    return @{ Level = $level; Characters = $index }
}

function ConvertTo-OtterLineTokens {
    param([string]$Text, [int]$LineNumber, [int]$ColumnOffset)

    $tokens = [System.Collections.Generic.List[Token]]::new()
    $index = 0
    $isStatementHead = $true
    while ($index -lt $Text.Length) {
        $character = $Text[$index]
        $column = $ColumnOffset + $index + 1
        if ([char]::IsWhiteSpace($character)) { $index++; continue }
        if ($character -eq '#') { break }

        if ($character -eq '"') {
            $start = $index
            $index++
            $value = [System.Text.StringBuilder]::new()
            $closed = $false
            while ($index -lt $Text.Length) {
                if ($Text[$index] -eq '"') { $index++; $closed = $true; break }
                if ($Text[$index] -eq '\' -and ($index + 1) -lt $Text.Length) {
                    $index++
                    switch ($Text[$index]) {
                        'n' { [void]$value.Append("`n") }
                        't' { [void]$value.Append("`t") }
                        '"' { [void]$value.Append('"') }
                        '\' { [void]$value.Append('\') }
                        default { [void]$value.Append('\'); [void]$value.Append($Text[$index]) }
                    }
                    $index++
                    continue
                }
                [void]$value.Append($Text[$index])
                $index++
            }
            if (-not $closed) {
                throw [OtterError]::new('This string never closes.', $LineNumber, 'lexer', $column, $Text, 'Add a closing quote.')
            }
            $tokens.Add((New-OtterToken ([TokenKind]::String) $Text.Substring($start, $index - $start) $value.ToString() $LineNumber $column))
            continue
        }

        if ([char]::IsDigit($character)) {
            $start = $index
            while ($index -lt $Text.Length -and [char]::IsDigit($Text[$index])) { $index++ }
            if ($index -lt $Text.Length -and $Text[$index] -eq '.' -and ($index + 1) -lt $Text.Length -and [char]::IsDigit($Text[$index + 1])) {
                $index++
                while ($index -lt $Text.Length -and [char]::IsDigit($Text[$index])) { $index++ }
            }
            $numberText = $Text.Substring($start, $index - $start)
            $number = [double]::Parse($numberText, [Globalization.CultureInfo]::InvariantCulture)
            $tokens.Add((New-OtterToken ([TokenKind]::Number) $numberText $number $LineNumber $column))
            continue
        }

        if ([char]::IsLetter($character) -or $character -eq '_') {
            $start = $index
            while ($index -lt $Text.Length -and ([char]::IsLetterOrDigit($Text[$index]) -or $Text[$index] -eq '_')) { $index++ }
            $word = $Text.Substring($start, $index - $start)
            $kind = if ($isStatementHead -and $script:OtterStatementHeadKeywords.ContainsKey($word)) {
                $script:OtterStatementHeadKeywords[$word]
            } elseif ($script:OtterKeywords.ContainsKey($word)) {
                $script:OtterKeywords[$word]
            } else {
                [TokenKind]::Identifier
            }
            $value = switch ($kind) {
                ([TokenKind]::True) { $true }
                ([TokenKind]::False) { $false }
                default { $word }
            }
            $tokens.Add((New-OtterToken $kind $word $value $LineNumber $column))
            $isStatementHead = $false
            continue
        }

        if ($character -eq '.') {
            throw [OtterError]::new(
                'Otter does not use periods to access properties.', $LineNumber, 'lexer', $column, $Text,
                'Use "name of person" instead of "person.name".'
            )
        }

        # Commas are contextual punctuation for the multi-item `put` form.
        # Keep the frozen contract unchanged by carrying it as an identifier
        # whose text is `,`; only that parser production consumes it.
        if ($character -eq ',') {
            $tokens.Add((New-OtterToken ([TokenKind]::Identifier) ',' ',' $LineNumber $column))
            $index++
            $isStatementHead = $false
            continue
        }

        if ($character -eq '+') {
            $tokens.Add((New-OtterToken ([TokenKind]::And) '+' $null $LineNumber $column))
            $index++
            $isStatementHead = $false
            continue
        }

        if ($character -eq '*') {
            $tokens.Add((New-OtterToken ([TokenKind]::Times) '*' $null $LineNumber $column))
            $index++
            $isStatementHead = $false
            continue
        }

        if ($character -eq '-') {
            $tokens.Add((New-OtterToken ([TokenKind]::Minus) '-' $null $LineNumber $column))
            $index++
            $isStatementHead = $false
            continue
        }

        if ($character -eq '/') {
            $tokens.Add((New-OtterToken ([TokenKind]::DividedBy) '/' $null $LineNumber $column))
            $index++
            $isStatementHead = $false
            continue
        }

        if ($character -eq '=') {
            $suggestion = if ($Text -match '^\s*state\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
                $rhs = if ($matches[2].Trim().Length -gt 0) { $matches[2].Trim() } else { "0" }
                "Otter uses 'is' to assign values.`n`nTry:`nstate $($matches[1]) is $rhs"
            } else {
                "Otter uses 'is' to assign values."
            }
            throw [OtterError]::new("Otter does not use '=' to assign values.", $LineNumber, 'lexer', $column, $Text, $suggestion)
        }

        throw [OtterError]::new("I don't understand '$character'.", $LineNumber, 'lexer', $column, $Text, 'Use Otter words such as say or if.')
    }

    # Multi-word language phrases each become one token.
    $combined = [System.Collections.Generic.List[Token]]::new()
    for ($tokenIndex = 0; $tokenIndex -lt $tokens.Count; $tokenIndex++) {
        $token = $tokens[$tokenIndex]
        if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'ease' -and
            ($tokenIndex + 2) -lt $tokens.Count -and $tokens[$tokenIndex + 1].Kind -eq [TokenKind]::Minus -and
            $tokens[$tokenIndex + 2].Text -in @('out', 'in')) {
            $combined.Add((New-OtterToken ([TokenKind]::Identifier) "ease-$($tokens[$tokenIndex + 2].Text)" "ease-$($tokens[$tokenIndex + 2].Text)" $token.Line $token.Column))
            $tokenIndex += 2
            continue
        }
        if ($token.Kind -eq [TokenKind]::Is -and ($tokenIndex + 2) -lt $tokens.Count -and
            $tokens[$tokenIndex + 1].Text -eq 'at' -and $tokens[$tokenIndex + 2].Text -eq 'least') {
            $combined.Add((New-OtterToken ([TokenKind]::IsAtLeast) 'is at least' $null $token.Line $token.Column))
            $tokenIndex += 2
            continue
        }
        $previous = if ($combined.Count -gt 0) { $combined[$combined.Count - 1] } else { $null }
        if ($token.Kind -eq [TokenKind]::Is -and ($tokenIndex + 1) -lt $tokens.Count) {
            $next = $tokens[$tokenIndex + 1]
            if ($next.Text -eq 'not') { $combined.Add((New-OtterToken ([TokenKind]::IsNot) 'is not' $null $token.Line $token.Column)); $tokenIndex++; continue }
            if (($tokenIndex + 2) -lt $tokens.Count -and $next.Text -eq 'at' -and $tokens[$tokenIndex + 2].Text -eq 'most') { $combined.Add((New-OtterToken ([TokenKind]::IsAtMost) 'is at most' $null $token.Line $token.Column)); $tokenIndex += 2; continue }
            if (($tokenIndex + 2) -lt $tokens.Count -and $next.Text -eq 'greater' -and $tokens[$tokenIndex + 2].Text -eq 'than') { $combined.Add((New-OtterToken ([TokenKind]::IsGreaterThan) 'is greater than' $null $token.Line $token.Column)); $tokenIndex += 2; continue }
            if (($tokenIndex + 2) -lt $tokens.Count -and $next.Text -eq 'less' -and $tokens[$tokenIndex + 2].Text -eq 'than') { $combined.Add((New-OtterToken ([TokenKind]::IsLessThan) 'is less than' $null $token.Line $token.Column)); $tokenIndex += 2; continue }
        }
        if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'for' -and
            ($tokenIndex + 1) -lt $tokens.Count -and $tokens[$tokenIndex + 1].Text -eq 'each') {
            $combined.Add((New-OtterToken ([TokenKind]::ForEach) 'for each' $null $token.Line $token.Column))
            $tokenIndex++
            continue
        }
        # D33 mechanism 1: these words are structural only in their fixed
        # neighbouring phrase. Outside it they remain ordinary identifiers.
        if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'empty' -and
            $null -ne $previous -and $previous.Kind -eq [TokenKind]::Are) {
            $combined.Add((New-OtterToken ([TokenKind]::Empty) 'empty' $null $token.Line $token.Column))
            continue
        }
        if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'contains' -and
            $null -ne $previous -and $previous.Kind -in @([TokenKind]::Identifier, [TokenKind]::File, [TokenKind]::Files, [TokenKind]::Folder, [TokenKind]::Folders, [TokenKind]::String, [TokenKind]::Number, [TokenKind]::True, [TokenKind]::False, [TokenKind]::Gone)) {
            $combined.Add((New-OtterToken ([TokenKind]::Contains) 'contains' $null $token.Line $token.Column))
            continue
        }
        if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'exists' -and
            $null -ne $previous -and $previous.Kind -in @([TokenKind]::Identifier, [TokenKind]::File, [TokenKind]::Files, [TokenKind]::Folder, [TokenKind]::Folders, [TokenKind]::String, [TokenKind]::Number, [TokenKind]::True, [TokenKind]::False, [TokenKind]::Gone)) {
            $combined.Add((New-OtterToken ([TokenKind]::Exists) 'exists' $null $token.Line $token.Column))
            continue
        }
        if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'call' -and
            $null -ne $previous -and $previous.Kind -eq [TokenKind]::And -and
            ($tokenIndex + 1) -lt $tokens.Count -and $tokens[$tokenIndex + 1].Text -eq 'it') {
            $combined.Add((New-OtterToken ([TokenKind]::Call) 'call' $null $token.Line $token.Column))
            continue
        }
        if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'it' -and
            $null -ne $previous -and $previous.Kind -eq [TokenKind]::Call -and
            $combined.Count -ge 2 -and $combined[$combined.Count - 2].Kind -eq [TokenKind]::And) {
            $combined.Add((New-OtterToken ([TokenKind]::It) 'it' $null $token.Line $token.Column))
            continue
        }
        # D29 is likewise more specific than D33: json is structural in the
        # read/convert productions, but remains free as a name elsewhere.
        if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'json' -and
            $null -ne $previous -and $previous.Kind -in @([TokenKind]::Read, [TokenKind]::To, [TokenKind]::From, [TokenKind]::Get, [TokenKind]::As)) {
            $combined.Add((New-OtterToken ([TokenKind]::Json) 'json' $null $token.Line $token.Column))
            continue
        }
        # D51: receives is structural in server route definitions
        if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'receives') {
            $combined.Add((New-OtterToken ([TokenKind]::Receives) 'receives' $null $token.Line $token.Column))
            continue
        }
        # Derived operations are contextual. `first is "Jeff"` keeps first
        # as an identifier; only `first of games` becomes an operation token.
        if ($token.Kind -eq [TokenKind]::Identifier -and ($tokenIndex + 1) -lt $tokens.Count -and
            $tokens[$tokenIndex + 1].Kind -eq [TokenKind]::Of) {
            $operationKind = switch ($token.Text) {
                'length' { [TokenKind]::Length }
                'uppercase' { [TokenKind]::Uppercase }
                'lowercase' { [TokenKind]::Lowercase }
                'first' { [TokenKind]::First }
                'last' { [TokenKind]::Last }
                default { $null }
            }
            if ($null -ne $operationKind) { $combined.Add((New-OtterToken $operationKind $token.Text $null $token.Line $token.Column)); continue }
        }
        if ($token.Kind -eq [TokenKind]::Identifier -and ($tokenIndex + 1) -lt $tokens.Count -and
            $tokens[$tokenIndex + 1].Kind -eq [TokenKind]::With) {
            if ($token.Text -eq 'starts') { $combined.Add((New-OtterToken ([TokenKind]::StartsWith) 'starts with' $null $token.Line $token.Column)); $tokenIndex++; continue }
            if ($token.Text -eq 'ends') { $combined.Add((New-OtterToken ([TokenKind]::EndsWith) 'ends with' $null $token.Line $token.Column)); $tokenIndex++; continue }
        }
        # A time unit, but ONLY where a unit can appear (D32):
        #
        #   add 7 days to date          after a number
        #   days between a and b        before "between"
        #
        # Anywhere else these stay identifiers, so "year of book" keeps
        # meaning the year property of a thing.
        if ($token.Kind -eq [TokenKind]::Identifier -and $script:OtterTimeUnitWords.ContainsKey($token.Text)) {
            $previous = if ($combined.Count -gt 0) { $combined[$combined.Count - 1] } else { $null }
            $next = if (($tokenIndex + 1) -lt $tokens.Count) { $tokens[$tokenIndex + 1] } else { $null }
            $afterNumber = ($null -ne $previous -and $previous.Kind -eq [TokenKind]::Number)
            $beforeBetween = ($null -ne $next -and $next.Text -eq 'between')
            if ($afterNumber -or $beforeBetween) {
                $combined.Add((New-OtterToken $script:OtterTimeUnitWords[$token.Text] $token.Text $null $token.Line $token.Column))
                continue
            }
        }
        # D32 is more specific than D33: `days between ...` remains the
        # date-difference production even though `between` is otherwise free.
        if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'between' -and
            $null -ne $previous -and $script:OtterTimeUnitWords.ContainsValue($previous.Kind)) {
            $combined.Add((New-OtterToken ([TokenKind]::Between) 'between' $null $token.Line $token.Column))
            continue
        }
        if ($token.Kind -eq [TokenKind]::Identifier -and $token.Text -eq 'divided' -and
            ($tokenIndex + 1) -lt $tokens.Count -and $tokens[$tokenIndex + 1].Text -eq 'by') {
            $combined.Add((New-OtterToken ([TokenKind]::DividedBy) 'divided by' $null $token.Line $token.Column))
            $tokenIndex++
            continue
        }
        $combined.Add($token)
    }
    return $combined.ToArray()
}

function ConvertTo-OtterTokens {
    [OutputType([Token[]])]
    param([Parameter(Mandatory)][string]$Source)

    $allTokens = [System.Collections.Generic.List[Token]]::new()
    $indentLevel = 0
    $lines = $Source -split "`r?`n", 0
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $lineNumber = $index + 1
        $indent = Get-OtterIndentLevel $line $lineNumber
        $content = $line.Substring($indent.Characters)
        if ($content -match '^\s*(#.*)?$') { continue }

        if ($indent.Level -gt ($indentLevel + 1)) {
            throw [OtterError]::new('Indentation cannot jump more than one level at a time.', $lineNumber, 'lexer', 1, $line, 'Indent one level at a time.')
        }
        while ($indentLevel -gt $indent.Level) {
            $allTokens.Add((New-OtterToken ([TokenKind]::Dedent) '' $null $lineNumber 1))
            $indentLevel--
        }
        while ($indentLevel -lt $indent.Level) {
            $allTokens.Add((New-OtterToken ([TokenKind]::Indent) '' $null $lineNumber 1))
            $indentLevel++
        }

        if ($content.Trim() -eq '.') {
            $allTokens.Add((New-OtterToken ([TokenKind]::BlockEnd) '.' $null $lineNumber ($indent.Characters + 1)))
        } else {
            foreach ($token in (ConvertTo-OtterLineTokens $content $lineNumber $indent.Characters)) { $allTokens.Add($token) }
        }
        $allTokens.Add((New-OtterToken ([TokenKind]::Newline) '' $null $lineNumber ($line.Length + 1)))
    }
    while ($indentLevel -gt 0) {
        $allTokens.Add((New-OtterToken ([TokenKind]::Dedent) '' $null ($lines.Count + 1) 1))
        $indentLevel--
    }
    $allTokens.Add((New-OtterToken ([TokenKind]::EndOfFile) '' $null ($lines.Count + 1) 1))
    return $allTokens.ToArray()
}

Export-ModuleMember -Function ConvertTo-OtterTokens
