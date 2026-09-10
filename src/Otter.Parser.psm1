using module ..\Otter.Contract.psm1

# Milestone 1 parser: say, assignment, and an if block with comparison.

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

function Read-OtterValue {
    $token = Get-OtterCurrentToken
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
    if ($token.Kind -in @([TokenKind]::Identifier, [TokenKind]::File, [TokenKind]::Files, [TokenKind]::Folder, [TokenKind]::Folders)) {
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
        default { throw (New-OtterParserError 'I expected a value here.' $token 'Add a text value, number, true, false, or variable name.') }
    }
}

function Read-OtterVariableName {
    param([string]$Message)
    $token = Get-OtterCurrentToken
    if ($token.Kind -notin @([TokenKind]::Identifier, [TokenKind]::File, [TokenKind]::Files, [TokenKind]::Folder, [TokenKind]::Folders)) {
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
        $field = Assert-OtterTokenKind ([TokenKind]::Identifier) 'I expected a property name.'
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
            $name = Assert-OtterTokenKind ([TokenKind]::Identifier) 'I expected a variable name after "call it".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the question to end here.')
            return [AskStmt]::new($prompt, $name.Text, $start.Line)
        }
        ([TokenKind]::Get) {
            [void](Read-OtterToken)
            $kind = Get-OtterCurrentToken
            if ($kind.Kind -ne [TokenKind]::Files -and $kind.Kind -ne [TokenKind]::Folders) {
                throw (New-OtterParserError 'I expected "files" or "folders" after "get".' $kind 'Write "get files in ..." or "get folders in ...".')
            }
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::In) 'I expected "in" and a folder path.')
            $folder = Read-OtterValue
            $includeSubfolders = $false
            if (Test-OtterTokenKind ([TokenKind]::And)) {
                [void](Read-OtterToken)
                [void](Assert-OtterTokenKind ([TokenKind]::Subfolders) 'I expected "subfolders" after "and".')
                $includeSubfolders = $true
            }
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a result name.')
            $target = Read-OtterVariableName 'I expected a result name after "into".'
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the discovery statement to end here.')
            if ($kind.Kind -eq [TokenKind]::Files) { return [GetFilesStmt]::new($folder, $includeSubfolders, $target.Text, $start.Line) }
            return [GetFoldersStmt]::new($folder, $includeSubfolders, $target.Text, $start.Line)
        }
        ([TokenKind]::Create) {
            [void](Read-OtterToken)
            [void](Assert-OtterTokenKind ([TokenKind]::Folder) 'I expected "folder" after create.')
            $path = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the create statement to end here.')
            return [CreateFolderStmt]::new($path, $start.Line)
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
        ([TokenKind]::Read) {
            [void](Read-OtterToken)
            $path = Read-OtterValue
            [void](Assert-OtterTokenKind ([TokenKind]::Into) 'I expected "into" and a variable name.')
            $target = Assert-OtterTokenKind ([TokenKind]::Identifier) 'I expected a variable name after "into".'
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
                $resultTarget = (Assert-OtterTokenKind ([TokenKind]::Identifier) 'I expected a variable name after "into".').Text
            }
            [void](Assert-OtterTokenKind ([TokenKind]::Newline) 'I expected the run statement to end here.')
            return [RunStmt]::new($target, $isCommand, $resultTarget, $start.Line)
        }
        ([TokenKind]::A) {
            [void](Read-OtterToken)
            $typeName = Assert-OtterTokenKind ([TokenKind]::Identifier) 'I expected a type name after "a".'
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
                        $properties = Read-OtterBlock
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
