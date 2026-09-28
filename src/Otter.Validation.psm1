using module ..\Otter.Contract.psm1

# Otter.Validation.psm1
#
# Post-parse language-contract validation (Otter 1.0 decision D-2).
#
# D-2: "If Otter accepts an identifier declaration, that identifier must
# subsequently be usable according to its declared role."
#
# The parser (owned by the front-end agent) reads some ordinary-looking
# words as grammar depending on WHERE they appear: a line starting with
# `main` is a D56 UI element, `x is completed` is an HTTP/job state check,
# and so on. The parser still ACCEPTS those words as the name of a new
# function or variable, so a program can declare a name it can never use:
#
#     to main
#         say "hello"
#     main                  <- read as a UI element: prints nothing, exit 0
#
# This module runs over the finished AST (it never re-parses and never
# touches the parser) and rejects exactly those declarations, before any
# statement runs. The reserved sets below are DERIVED from the parser, not
# guessed: every word was proven to conflict by parsing a tiny program with
# the RC2 parser, and tests/LanguageContract.Tests.ps1 re-proves each one
# against the current parser so this list cannot silently drift. Words that
# do not conflict (name, status, total, score, ...) are deliberately absent.
#
# Matching is case-insensitive because the lexer's keyword tables and the
# parser's word checks are case-insensitive (`Main`, `SEND` and `Completed`
# are hijacked exactly like their lower-case spellings).
#
# The canonical user-facing list lives in docs/OTTER_1_0_RESERVED_WORDS.md.


# ===============================================================
# CATEGORIES - why a word conflicts
# ===============================================================
#
# {0} is the reserved word. Each reason completes the sentence
# "`word` is a reserved word in Otter: <reason>".

$script:OtterReservedReasons = @{
    # --- function names ------------------------------------------
    'fn-ui' = 'a line starting with `{0}` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `{0}` could never be called'
    'fn-statement' = 'a line starting with `{0}` is read as the `{0}` statement, so a function named `{0}` could never be called'
    'fn-keyword' = '`{0}` is part of Otter''s own grammar and a line cannot start with it, so a function named `{0}` could never be called'
    'fn-builtin' = '`{0}` is a built-in value, so a function named `{0}` could never be called'

    # --- variable and parameter names ----------------------------
    'var-statement' = 'a line starting with `{0}` is read as the `{0}` statement, so `{0} is ...` can never assign a variable named `{0}`'
    'var-state-http' = 'in a condition, `x is {0}` is read as a check of an HTTP request''s or command job''s state, not a comparison with a variable named `{0}`'
    'var-state-socket' = 'in a condition, `x is {0}` is read as a check of a websocket''s, TCP connection''s or UDP socket''s state, not a comparison with a variable named `{0}`'
    'var-state-server' = 'in a condition, `x is {0}` is read as a check of a TCP server''s state, not a comparison with a variable named `{0}`'
    'var-state-tls' = 'in a condition, `x is {0}` is read as a check of whether a TCP connection uses TLS, not a comparison with a variable named `{0}`'
    'var-state-watch' = 'in a condition, `x is {0}` is read as a check of whether a file watcher is running, not a comparison with a variable named `{0}`'
}


# ===============================================================
# RESERVED FUNCTION NAMES  (`to NAME`)
# ===============================================================
#
# A declared function is called by writing its name at the start of a line.
# Each word here is taken by another statement form there, for every number
# of arguments, so the statement call can never reach the function.
#
# Deliberately NOT here (see docs/OTTER_1_0_RESERVED_WORDS.md, "Contextual
# words"): `add` (the statement call `add 1 2` does reach a function named
# add; only the expression form fails, loudly, at check time) and the
# phrase-only heads `go`, `watch`, `close`, `store`, `generate`, `primary`,
# `secondary`, `danger`, `total`, `avg`, `min`, `max`, which take over a line
# only when a specific word follows them.

$script:OtterReservedFunctionNames = @{}
foreach ($word in @('window', 'page', 'card', 'heading', 'text', 'button', 'panel', 'section',
                    'sidebar', 'main', 'link', 'image', 'input', 'grid')) {
    $script:OtterReservedFunctionNames[$word] = 'fn-ui'
}
foreach ($word in @(
        # D33 statement-head words and the other statement starters
        'append', 'average', 'cancel', 'choose', 'commit', 'connect', 'convert', 'copy',
        'count', 'create', 'decrease', 'decrypt', 'delete', 'derive', 'disconnect',
        'download', 'each', 'encrypt', 'error', 'execute', 'fail', 'find', 'focus',
        'format', 'get', 'hash', 'hide', 'increase', 'join', 'kill', 'layout', 'listen',
        'lock', 'log', 'maximum', 'memo', 'minimum', 'move', 'notify', 'on', 'post',
        'print', 'query', 'random', 'read', 'replace', 'respond', 'restart', 'reverse',
        'rollback', 'route', 'run', 'send', 'shared', 'shut', 'sign', 'sort', 'split',
        'start', 'state', 'stop', 'sum', 'try', 'unzip', 'use', 'wait', 'warn', 'write',
        'zip')) {
    $script:OtterReservedFunctionNames[$word] = 'fn-statement'
}
foreach ($word in @('animate', 'ascending', 'between', 'descending', 'distinct', 'file', 'files',
                    'folder', 'folders', 'gap', 'has', 'json', 'motion', 'otherwise',
                    'parameter', 'then')) {
    $script:OtterReservedFunctionNames[$word] = 'fn-keyword'
}
foreach ($word in @('today', 'now', 'pi')) {
    $script:OtterReservedFunctionNames[$word] = 'fn-builtin'
}


# ===============================================================
# RESERVED VARIABLE AND PARAMETER NAMES
# ===============================================================
#
# A variable must be readable as a value (including on either side of `is`
# in a condition) and assignable with `name is ...` at the start of a line.
# A word is reserved here when either
#   (a) an ordinary use of the variable is ACCEPTED by the parser with a
#       different meaning (the state words: `if x is completed` parses as a
#       state check, then misbehaves at run time), or
#   (b) the variable can never be assigned: `zip is ...` is read as the zip
#       statement in every position, so the name can be bound (`into zip`)
#       but never updated.
# Words whose only conflict is ONE position that the parser already rejects
# loudly at check time are contextual, not reserved: `count` (only a
# top-level `count is ...`; the D56 canonical example relies on
# `state count is 0`), `between` (only `x is between`), and `file`,
# `element`, `registry` (only as the left side of a condition). Those need a
# parser fix, not a smaller language.

$script:OtterReservedVariableNames = @{}
foreach ($word in @('animate', 'decrease', 'decrypt', 'derive', 'encrypt', 'fail', 'focus', 'gap',
                    'hash', 'hide', 'increase', 'kill', 'layout', 'listen', 'lock', 'memo',
                    'motion', 'on', 'post', 'print', 'respond', 'restart', 'shared', 'shut',
                    'sign', 'start', 'state', 'stop', 'unzip', 'use', 'wait', 'zip')) {
    $script:OtterReservedVariableNames[$word] = 'var-statement'
}
foreach ($word in @('pending', 'running', 'completed', 'failed', 'cancelled')) {
    $script:OtterReservedVariableNames[$word] = 'var-state-http'
}
foreach ($word in @('connecting', 'closing', 'connected', 'closed')) {
    $script:OtterReservedVariableNames[$word] = 'var-state-socket'
}
foreach ($word in @('listening', 'stopped')) {
    $script:OtterReservedVariableNames[$word] = 'var-state-server'
}
$script:OtterReservedVariableNames['secure'] = 'var-state-tls'
$script:OtterReservedVariableNames['watching'] = 'var-state-watch'


# ===============================================================
# WHERE NAMES ARE DECLARED IN THE AST
# ===============================================================
#
# String properties that hold a variable name the program binds (or writes
# to): `into x`, `make x`, `and call it x`, `for each x in`, `count ... as x`,
# `ask ... and call it x`, `x are ...`, `x has`, `try ... otherwise into e`...
# Names on these properties are checked against the variable set.

$script:OtterVariableNameProperties = @('Target', 'ResultTarget', 'VariableName', 'ErrorTarget', 'ItemName', 'TargetName')

# Node types whose `Name` property declares a variable. (`Name` on
# VariableExpr/CallExpr is a USE, on FunctionDefStmt it is a function name,
# and on UI/DB nodes it is not an Otter variable at all.)
$script:OtterVariableNameNodeTypes = @('AskStmt', 'ListDefStmt', 'ObjectDefStmt', 'StateDefStmt',
                                       'DeriveDefStmt', 'MemoDefStmt', 'SharedStateStmt')


function Get-OtterReservedWordReason {
    param([Parameter(Mandatory)][string]$Word, [Parameter(Mandatory)][ValidateSet('function', 'variable')][string]$Role)

    $table = if ($Role -eq 'function') { $script:OtterReservedFunctionNames } else { $script:OtterReservedVariableNames }
    $key = $Word.ToLowerInvariant()
    if (-not $table.ContainsKey($key)) { return $null }
    return ($script:OtterReservedReasons[$table[$key]] -f $Word)
}

# The canonical reserved-word list, one row per (word, role). Used by the
# tests and by the docs generator; the order is stable.
function Get-OtterReservedWords {
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($word in ($script:OtterReservedFunctionNames.Keys | Sort-Object)) {
        $rows.Add([pscustomobject]@{
            Word = $word; Role = 'function'; Category = $script:OtterReservedFunctionNames[$word]
            Reason = ($script:OtterReservedReasons[$script:OtterReservedFunctionNames[$word]] -f $word)
        })
    }
    foreach ($word in ($script:OtterReservedVariableNames.Keys | Sort-Object)) {
        $rows.Add([pscustomobject]@{
            Word = $word; Role = 'variable'; Category = $script:OtterReservedVariableNames[$word]
            Reason = ($script:OtterReservedReasons[$script:OtterReservedVariableNames[$word]] -f $word)
        })
    }
    return $rows.ToArray()
}

function Get-OtterWordColumn {
    param([string[]]$SourceLines, [int]$Line, [string]$Word, [int]$After = 0)

    if ($null -eq $SourceLines -or $Line -lt 1 -or $Line -gt $SourceLines.Count) { return 0 }
    $text = $SourceLines[$Line - 1]
    if ($null -eq $text) { return 0 }
    $pattern = '(?<![\p{L}\p{Nd}_])' + [regex]::Escape($Word) + '(?![\p{L}\p{Nd}_])'
    $match = [regex]::Match($text.Substring([Math]::Min($After, $text.Length)), $pattern, 'IgnoreCase')
    if (-not $match.Success) { return 0 }
    return $match.Index + [Math]::Min($After, $text.Length) + 1
}

function New-OtterReservedWordError {
    param([string]$Word, [string]$Role, [int]$Line, [string[]]$SourceLines, [int]$After = 0)

    $reason = Get-OtterReservedWordReason -Word $Word -Role $Role
    $alternative = if ($Role -eq 'function') { "$($Word)Task" } else { "$($Word)Value" }
    $message = "``$Word`` is a reserved word in Otter: $reason. Choose a different name, for example ``$alternative``."
    $column = Get-OtterWordColumn -SourceLines $SourceLines -Line $Line -Word $Word -After $After
    $sourceLine = $null
    if ($null -ne $SourceLines -and $Line -ge 1 -and $Line -le $SourceLines.Count) { $sourceLine = $SourceLines[$Line - 1] }
    $suggestion = "Rename ``$Word`` everywhere it is used, for example to ``$alternative``. See docs/OTTER_1_0_RESERVED_WORDS.md."
    return [OtterError]::new($message, $Line, 'parser', $column, $sourceLine, $suggestion, 'ReservedWord')
}


# ===============================================================
# THE AST WALK
# ===============================================================

function Test-OtterValidationContainer {
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $false }
    return $true
}

function Add-OtterValidationFinding {
    param($State, [string]$Word, [string]$Role, [int]$Line, [int]$After = 0)

    if ([string]::IsNullOrEmpty($Word)) { return }
    $table = if ($Role -eq 'function') { $script:OtterReservedFunctionNames } else { $script:OtterReservedVariableNames }
    if (-not $table.ContainsKey($Word.ToLowerInvariant())) { return }
    $key = "$Role|$($Word.ToLowerInvariant())|$Line"
    if ($State.Seen.Contains($key)) { return }
    [void]$State.Seen.Add($key)
    $State.Errors.Add((New-OtterReservedWordError -Word $Word -Role $Role -Line $Line -SourceLines $State.SourceLines -After $After))
}

function Invoke-OtterValidationWalk {
    param($Value, $State)

    if (-not (Test-OtterValidationContainer $Value)) { return }

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($entry in $Value.Values) { Invoke-OtterValidationWalk -Value $entry -State $State }
        return
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) { Invoke-OtterValidationWalk -Value $item -State $State }
        return
    }

    # Guard against cycles (no contract node should have one, but a walk
    # over arbitrary object graphs must never spin forever).
    if (-not $State.Visited.Add($Value)) { return }

    if ($Value -is [Node]) {
        $typeName = $Value.GetType().Name
        $line = $Value.Line

        if ($Value -is [FunctionDefStmt]) {
            Add-OtterValidationFinding -State $State -Word $Value.Name -Role 'function' -Line $line
            # Parameters come after the function name on the same line.
            $afterName = Get-OtterWordColumn -SourceLines $State.SourceLines -Line $line -Word $Value.Name
            foreach ($parameter in @($Value.Parameters)) {
                Add-OtterValidationFinding -State $State -Word $parameter -Role 'variable' -Line $line -After $afterName
            }
        }
        elseif ($Value -is [AssignStmt]) {
            if ($Value.Target -is [VariableExpr]) {
                Add-OtterValidationFinding -State $State -Word $Value.Target.Name -Role 'variable' -Line $line
            }
        }
        elseif ($typeName -in $script:OtterVariableNameNodeTypes) {
            Add-OtterValidationFinding -State $State -Word ([string]$Value.Name) -Role 'variable' -Line $line
        }

        foreach ($property in $Value.PSObject.Properties) {
            if ($property.Name -in @('Kind', 'Line')) { continue }
            $propertyValue = $property.Value
            if ($property.Name -in $script:OtterVariableNameProperties -and $propertyValue -is [string]) {
                Add-OtterValidationFinding -State $State -Word $propertyValue -Role 'variable' -Line $line
                continue
            }
            Invoke-OtterValidationWalk -Value $propertyValue -State $State
        }
        return
    }

    # Non-node contract objects (IfBranch, query clauses, ...) carry child nodes.
    if ($Value.GetType().Assembly -eq [Node].Assembly -or $Value -is [IfBranch]) {
        foreach ($property in $Value.PSObject.Properties) {
            Invoke-OtterValidationWalk -Value $property.Value -State $State
        }
    }
}


# ===============================================================
# PUBLIC ENTRY POINTS
# ===============================================================

# Returns every reserved-word diagnostic in the program, in source order.
# Never throws for a valid AST; an empty array means the program is fine.
function Get-OtterLanguageContractDiagnostics {
    [OutputType([OtterError[]])]
    param(
        [Parameter(Mandatory)][ProgramNode]$Program,
        [string[]]$SourceLines = @()
    )

    $state = [pscustomobject]@{
        Errors = [System.Collections.Generic.List[OtterError]]::new()
        Seen = [System.Collections.Generic.HashSet[string]]::new()
        # Contract classes never override Equals, so this is reference identity
        # (and works on .NET Framework, which has no ReferenceEqualityComparer).
        Visited = [System.Collections.Generic.HashSet[object]]::new()
        SourceLines = $SourceLines
    }
    Invoke-OtterValidationWalk -Value $Program.Statements -State $state
    $sorted = @($state.Errors | Sort-Object -Property @{ Expression = { $_.Line } }, @{ Expression = { $_.Column } })
    return , [OtterError[]]$sorted
}

# The hook `otter check`, `otter run` and `otter test` call right after the
# parser: throws the same multi-diagnostic exception the parser uses, so the
# CLI reports it as a check-stage error and nothing runs.
function Assert-OtterLanguageContract {
    param(
        [Parameter(Mandatory)][ProgramNode]$Program,
        [string[]]$SourceLines = @()
    )

    $diagnostics = Get-OtterLanguageContractDiagnostics -Program $Program -SourceLines $SourceLines
    if ($diagnostics.Count -gt 0) {
        throw [OtterMultipleErrorsException]::new($diagnostics)
    }
}

Export-ModuleMember -Function Get-OtterLanguageContractDiagnostics, Assert-OtterLanguageContract, Get-OtterReservedWords, Get-OtterReservedWordReason
