using module ..\Otter.Contract.psm1
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Lexer.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Parser.psm1') -Force

function Parse-Otter {
    param([string]$Source)
    return ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $Source)
}

# D33 mechanism 2. Each name is accepted in all six audit positions. The
# lexer still gives it its statement token at a logical-line head; the parser
# falls back to assignment/property grammar when the following structure is
# unambiguously identifier-shaped.
$statementWords = @(
    @('copy', [TokenKind]::Copy), @('move', [TokenKind]::Move),
    @('delete', [TokenKind]::Delete), @('create', [TokenKind]::Create),
    @('read', [TokenKind]::Read), @('write', [TokenKind]::Write),
    @('sort', [TokenKind]::Sort), @('reverse', [TokenKind]::Reverse),
    @('replace', [TokenKind]::Replace), @('split', [TokenKind]::Split),
    @('join', [TokenKind]::Join), @('find', [TokenKind]::Find),
    @('get', [TokenKind]::Get), @('try', [TokenKind]::Try),
    @('run', [TokenKind]::Run), @('log', [TokenKind]::Log),
    @('warn', [TokenKind]::Warn), @('error', [TokenKind]::Problem),
    @('random', [TokenKind]::Random), @('json', [TokenKind]::Json),
    @('convert', [TokenKind]::Convert), @('format', [TokenKind]::Format),
    @('today', [TokenKind]::Today), @('now', [TokenKind]::Now),
    @('between', [TokenKind]::Between), @('otherwise', [TokenKind]::Otherwise)
)

foreach ($entry in $statementWords) {
    $word = $entry[0]
    $kind = $entry[1]

    $tokens = ConvertTo-OtterTokens -Source "$word is `"value`""
    if ($tokens[0].Kind -ne $kind) { throw "$word must retain its statement-head token." }
    $assignment = (Parse-Otter "$word is `"value`"").Statements[0]
    if ($assignment -isnot [AssignStmt] -or $assignment.Target.Name -ne $word) { throw "$word must be a variable at an assignment head." }

    $function = (Parse-Otter "to $word`n    say `"ok`"").Statements[0]
    if ($function -isnot [FunctionDefStmt] -or $function.Name -ne $word) { throw "$word must be a function name." }

    $parameter = (Parse-Otter "to use $word`n    say `"ok`"").Statements[0]
    if ($parameter.Parameters[0] -ne $word) { throw "$word must be a parameter name." }

    $property = (Parse-Otter "thing is a thing`n    $word is `"value`"`n.").Statements[0]
    if ($property.Properties[0].Target.Name -ne $word) { throw "$word must be a property name." }

    $loop = (Parse-Otter "items are empty`nfor each $word in items`n    say $word").Statements[1]
    if ($loop.VariableName -ne $word) { throw "$word must be a for-each name." }

    if ($word -notin @('today', 'now')) {
        $readBack = (Parse-Otter "$word is `"value`"`nsay $word").Statements[1].Parts[0]
        if ($readBack -isnot [VariableExpr] -or $readBack.Name -ne $word) { throw "$word must read back as a variable." }
    }
}

# D32 is more specific than D33. In expression position `today` and `now`
# are date literals, so a variable of either name cannot be read back in an
# expression without colliding with the literal. That is deliberate and is
# the exact position D33 must not try to free.
$today = (Parse-Otter 'date is today').Statements[0].Value
$now = (Parse-Otter 'started is now').Statements[0].Value
if ($today -isnot [ClockExpr] -or $today.Clock -ne [ClockKind]::Today) { throw 'date is today must remain a ClockExpr.' }
if ($now -isnot [ClockExpr] -or $now.Clock -ne [ClockKind]::Now) { throw 'started is now must remain a ClockExpr.' }
$difference = (Parse-Otter 'days between startDate and endDate make days').Statements[0]
if ($difference -isnot [DateDifferenceStmt] -or $difference.Unit -ne [TimeUnit]::Day) { throw 'days between must remain the D32 date-difference form.' }

# D33 mechanism 1: the structural token appears only inside the fixed phrase.
$ordinaryAdjacencyWords = @('exists', 'contains', 'empty', 'call', 'it', 'has', 'thing')
foreach ($word in $ordinaryAdjacencyWords) {
    $assignment = (Parse-Otter "$word is `"value`"").Statements[0]
    if ($assignment -isnot [AssignStmt] -or $assignment.Target.Name -ne $word) { throw "$word must be an ordinary assignment name outside its phrase." }
    $readBack = (Parse-Otter "$word is `"value`"`nsay $word").Statements[1].Parts[0]
    if ($readBack -isnot [VariableExpr] -or $readBack.Name -ne $word) { throw "$word must be readable outside its phrase." }
}

$containsTokens = ConvertTo-OtterTokens -Source 'if games contains "Zelda"'
if ($containsTokens[2].Kind -ne [TokenKind]::Contains) { throw 'contains must become structural after a value.' }
$existsTokens = ConvertTo-OtterTokens -Source 'if file "note.txt" exists'
if ($existsTokens[3].Kind -ne [TokenKind]::Exists) { throw 'exists must become structural after a value.' }
$emptyTokens = ConvertTo-OtterTokens -Source 'games are empty'
if ($emptyTokens[2].Kind -ne [TokenKind]::Empty) { throw 'empty must become structural after are.' }
$askTokens = ConvertTo-OtterTokens -Source 'ask "Name?" and call it name'
if ($askTokens[3].Kind -ne [TokenKind]::Call -or $askTokens[4].Kind -ne [TokenKind]::It) { throw 'call it must remain one fixed structural phrase.' }
if ((Parse-Otter "a Person has`n    has`n.").Statements[0] -isnot [TypeDefStmt]) { throw 'has must remain structural in a type definition.' }
if ((ConvertTo-OtterTokens -Source 'person is a thing')[3].Kind -ne [TokenKind]::Identifier) { throw 'thing must no longer be globally reserved.' }

Write-Output 'Keyword tests passed.'
