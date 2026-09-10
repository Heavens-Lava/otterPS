using module ..\Otter.Contract.psm1

# Milestone 1 lexer: source text becomes the shared Token[] contract.

$script:OtterKeywords = @{
    'say' = [TokenKind]::Say
    'ask' = [TokenKind]::Ask
    'call' = [TokenKind]::Call
    'it' = [TokenKind]::It
    'if' = [TokenKind]::If
    'otherwise' = [TokenKind]::Otherwise
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
    'minus' = [TokenKind]::Minus
    'times' = [TokenKind]::Times
    'make' = [TokenKind]::Make
    'makes' = [TokenKind]::Make
    'add' = [TokenKind]::Add
    'remove' = [TokenKind]::Remove
    'to' = [TokenKind]::To
    'from' = [TokenKind]::From
    'are' = [TokenKind]::Are
    'empty' = [TokenKind]::Empty
    'contains' = [TokenKind]::Contains
    'of' = [TokenKind]::Of
    'when' = [TokenKind]::When
    'gone' = [TokenKind]::Gone
    'get' = [TokenKind]::Get
    'files' = [TokenKind]::Files
    'folders' = [TokenKind]::Folders
    'folder' = [TokenKind]::Folder
    'subfolders' = [TokenKind]::Subfolders
    'create' = [TokenKind]::Create
    'try' = [TokenKind]::Try
    # Reserved for later language versions. Lexing them now prevents a future
    # keyword from silently changing an existing program's meaning.
    'a' = [TokenKind]::A
    'thing' = [TokenKind]::Thing
    'has' = [TokenKind]::Has
    'read' = [TokenKind]::Read
    'write' = [TokenKind]::Write
    'copy' = [TokenKind]::Copy
    'move' = [TokenKind]::Move
    'delete' = [TokenKind]::Delete
    'file' = [TokenKind]::File
    'exists' = [TokenKind]::Exists
    'into' = [TokenKind]::Into
    'run' = [TokenKind]::Run
    'command' = [TokenKind]::Command
    'open' = [TokenKind]::Open
    'true' = [TokenKind]::True
    'false' = [TokenKind]::False
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
            $kind = if ($script:OtterKeywords.ContainsKey($word)) { $script:OtterKeywords[$word] } else { [TokenKind]::Identifier }
            $value = switch ($kind) {
                ([TokenKind]::True) { $true }
                ([TokenKind]::False) { $false }
                default { $word }
            }
            $tokens.Add((New-OtterToken $kind $word $value $LineNumber $column))
            continue
        }

        if ($character -eq '.') {
            throw [OtterError]::new(
                'Otter does not use periods to access properties.', $LineNumber, 'lexer', $column, $Text,
                'Use "name of person" instead of "person.name".'
            )
        }

        throw [OtterError]::new("I don't understand '$character'.", $LineNumber, 'lexer', $column, $Text, 'Use Otter words such as say or if.')
    }

    # Multi-word language phrases each become one token.
    $combined = [System.Collections.Generic.List[Token]]::new()
    for ($tokenIndex = 0; $tokenIndex -lt $tokens.Count; $tokenIndex++) {
        $token = $tokens[$tokenIndex]
        if ($token.Kind -eq [TokenKind]::Is -and ($tokenIndex + 2) -lt $tokens.Count -and
            $tokens[$tokenIndex + 1].Text -eq 'at' -and $tokens[$tokenIndex + 2].Text -eq 'least') {
            $combined.Add((New-OtterToken ([TokenKind]::IsAtLeast) 'is at least' $null $token.Line $token.Column))
            $tokenIndex += 2
            continue
        }
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
