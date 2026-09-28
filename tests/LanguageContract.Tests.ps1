using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1
using module ..\src\Otter.Interpreter.psm1
using module ..\src\Otter.Validation.psm1

# LanguageContract.Tests.ps1
#
# Otter 1.0 language decisions D-1 and D-2 (RC3).
#
# D-2  A declared identifier must be usable in its declared role. The
#      reserved-word validator (src/Otter.Validation.psm1) rejects exactly the
#      declarations the parser can never honour. This file proves:
#        - every reserved word REALLY conflicts on the current parser (drift
#          guard: if the parser stops hijacking a word, this fails and the
#          word must leave the list - the set stays as small as the parser
#          requires);
#        - ordinary English identifiers stay usable in every role;
#        - one negative case per remaining category, with the diagnostic and proof
#          that nothing runs, end to end through `otter check` / `otter run`.
#
# D-1  Only the control that the word `and` stays a logical connective in a
#      condition lives here. The arithmetic-in-conditions tests travel with
#      the parser change in tests/ConditionArithmetic.Tests.ps1.
#
# Kept separate from Parser.Tests.ps1 / Lexer.Tests.ps1, which belong to Codex.

. "$PSScriptRoot\TestHelpers.ps1"
. "$PSScriptRoot\TestHost.ps1"

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:NL = "`n"

function Get-ParseResult {
    param([string]$Source)
    try {
        $result = ConvertTo-OtterParseResult -Tokens (ConvertTo-OtterTokens -Source ($Source + $script:NL))
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Statements = @(); Error = $_.Exception.Message }
    }
    return [pscustomobject]@{
        Ok = ($result.Diagnostics.Count -eq 0)
        Statements = @($result.Program.Statements)
        Error = (($result.Diagnostics | ForEach-Object { $_.Message }) -join ' / ')
    }
}

function Parse {
    param([string]$Source)
    return (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source ($Source + $script:NL)))
}

function Get-Diagnostics {
    param([string]$Source)
    $program = Parse $Source
    return @(Get-OtterLanguageContractDiagnostics -Program $program -SourceLines ($Source -split "`r?`n"))
}

# Parse, validate, then run; returns the printed lines.
function Invoke-Source {
    param([string]$Source)

    $program = Parse $Source
    Assert-OtterLanguageContract -Program $program -SourceLines ($Source -split "`r?`n")
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

function Test-IsVariable { param($Node, [string]$Name) return ($Node -is [VariableExpr] -and $Node.Name -ceq $Name) }


# -----------------------------------------------------------------
# End-to-end harness: the real `otter.ps1` entry point.
#
# `otter check` stops after the parser, and `otter run` / `otter test`
# (which runs each test file through `otter.ps1 run`) share that same path,
# so the one common hook is Invoke-OtterSource in otter.ps1. otter.ps1 is
# owned by another RC3 worker; until the hook is integrated, this harness
# applies EXACTLY the documented hook text to a private copy of the entry
# point. Once otter.ps1 carries the hook, the real file is used unchanged.
# -----------------------------------------------------------------

$script:HookUsing = 'using module .\src\Otter.Validation.psm1'
$script:HookSource = '        Assert-OtterLanguageContract -Program $program -SourceLines $sourceLines'

function Get-HookedOtterEntryPoint {
    $realEntry = Join-Path $script:RepoRoot 'otter.ps1'
    $text = [System.IO.File]::ReadAllText($realEntry)
    if ($text.Contains('Assert-OtterLanguageContract')) { return $realEntry }

    $copyRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('otter-d2-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $copyRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'Otter.Contract.psm1') -Destination $copyRoot
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'VERSION') -Destination $copyRoot
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'src') -Destination $copyRoot -Recurse

    $usingAnchor = 'using module .\src\Otter.Parser.psm1'
    $sourceAnchor = '        $program = ConvertTo-OtterAst -Tokens $tokens'
    if (-not $text.Contains($usingAnchor) -or -not $text.Contains($sourceAnchor)) {
        throw 'otter.ps1 no longer contains the hook anchors; update the documented hook.'
    }
    $eol = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $text = $text.Replace($usingAnchor, $usingAnchor + $eol + $script:HookUsing)
    $text = $text.Replace($sourceAnchor, $sourceAnchor + $eol + $script:HookSource)
    $hooked = Join-Path $copyRoot 'otter.ps1'
    [System.IO.File]::WriteAllText($hooked, $text, [System.Text.UTF8Encoding]::new($true))
    return $hooked
}

function Invoke-OtterCli {
    param([string]$EntryPoint, [string]$Command, [string]$Source)

    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('otter-d2-prog-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir | Out-Null
    $file = Join-Path $dir 'program.ot'
    [System.IO.File]::WriteAllText($file, $Source, [System.Text.UTF8Encoding]::new($false))
    $output = & $script:OtterHostExe @script:OtterHostArgs -File $EntryPoint $Command $file 2>&1
    $exit = $LASTEXITCODE
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Exit = $exit; Output = (($output | ForEach-Object { "$_" }) -join "`n") }
}


Write-Host ''
Write-Host 'Language contract: D-2 reserved words' -ForegroundColor Cyan


# =================================================================
# D-2 (1) drift guard: each reserved FUNCTION name really conflicts
# =================================================================
#
# For every word: the parser accepts `to WORD` (otherwise the validator
# never sees it and the word need not be listed), and a line calling it -
# with zero or one argument - is NOT a call of that function.

$script:Reserved = @(Get-OtterReservedWords)

Test-Otter 'D-2: the reserved list is non-empty and every entry has a reason' {
    Assert-True ($script:Reserved.Count -gt 50) "expected the derived list, got $($script:Reserved.Count) entries"
    foreach ($row in $script:Reserved) {
        Assert-True ($row.Reason.Contains($row.Word)) "reason for $($row.Word) does not name the word"
    }
}

Test-Otter 'D-2 drift guard: every reserved function name is accepted by `to` but hijacked at the start of a line' {
    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($row in @($script:Reserved | Where-Object { $_.Role -eq 'function' })) {
        $w = $row.Word
        $decl = Get-ParseResult "to $w$($script:NL)    say `"c`""
        if (-not ($decl.Ok -and $decl.Statements[0] -is [FunctionDefStmt] -and $decl.Statements[0].Name -ceq $w)) {
            $problems.Add("$w - the parser no longer accepts 'to $w'; drop it from the reserved list"); continue
        }
        $hijacked = $true
        foreach ($call in @("to $w$($script:NL)    say `"c`"$($script:NL)$w", "to $w p$($script:NL)    say p$($script:NL)$w 5")) {
            $parsed = Get-ParseResult $call
            $last = if ($parsed.Statements.Count) { $parsed.Statements[$parsed.Statements.Count - 1] } else { $null }
            if ($parsed.Ok -and $last -is [CallStmt] -and $last.Call.Name -ceq $w) { $hijacked = $false }
        }
        if (-not $hijacked) { $problems.Add("$w - a line starting with '$w' now calls the function; drop it from the reserved list") }
    }
    Assert-True ($problems.Count -eq 0) ($problems -join '; ')
}

Test-Otter 'D-2 drift guard: every reserved variable name is accepted as a parameter but silently misread after `is`' {
    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($row in @($script:Reserved | Where-Object { $_.Role -eq 'variable' })) {
        $w = $row.Word
        $decl = Get-ParseResult "to f $w$($script:NL)    say $w"
        if (-not ($decl.Ok -and $decl.Statements[0].Parameters -ccontains $w)) {
            $problems.Add("$w - the parser no longer accepts it as a parameter; drop it"); continue
        }
        if ($row.Category -notlike 'var-state-*') {
            $problems.Add("$w - unexpected variable category $($row.Category): only silently misread state words are reserved"); continue
        }
        # Right side of `is` in a condition must NOT be a comparison with the variable.
        $parsed = Get-ParseResult "to f $w$($script:NL)    if 5 is $w$($script:NL)        say 1"
        $condition = if ($parsed.Ok) { $parsed.Statements[0].Body[0].Branches[0].Condition } else { $null }
        if ($parsed.Ok -and $condition -is [ComparisonExpr] -and (Test-IsVariable $condition.Right $w)) {
            $problems.Add("$w - 'x is $w' is now an ordinary comparison; drop it")
        }
    }
    Assert-True ($problems.Count -eq 0) ($problems -join '; ')
}

Test-Otter 'D-2: the parser hijacks reserved words case-insensitively, and the validator matches that' {
    foreach ($w in @('Main', 'TEXT', 'Send', 'STOP')) {
        $parsed = Get-ParseResult "to $w$($script:NL)    say `"c`"$($script:NL)$w"
        $last = $parsed.Statements[$parsed.Statements.Count - 1]
        Assert-False ($parsed.Ok -and $last -is [CallStmt]) "$w should be hijacked like its lower-case spelling"
        Assert-AreEqual -Expected 1 -Actual (Get-Diagnostics "to $w$($script:NL)    say `"c`"").Count -Message $w
    }
    foreach ($w in @('Completed', 'CLOSED')) {
        Assert-AreEqual -Expected 1 -Actual (Get-Diagnostics "$w is 1").Count -Message $w
    }
}


# =================================================================
# D-2 (2) positive: ordinary identifiers stay usable in every role
# =================================================================

$script:OrdinaryWords = @('name', 'total', 'status', 'score', 'message', 'items', 'result', 'user',
                          'value', 'title', 'counter', 'amount', 'label', 'ready', 'done', 'data', 'key')

Test-Otter 'D-2 positive: ordinary words are not reserved in either role' {
    foreach ($w in $script:OrdinaryWords) {
        Assert-True ($null -eq (Get-OtterReservedWordReason -Word $w -Role 'function')) "$w must not be a reserved function name"
        Assert-True ($null -eq (Get-OtterReservedWordReason -Word $w -Role 'variable')) "$w must not be a reserved variable name"
    }
}

Test-Otter 'D-2 positive: ordinary words work as variables - assign, reassign, read, compare on both sides' {
    foreach ($w in $script:OrdinaryWords) {
        $source = @(
            "$w is 4"
            "$w is $w plus 1"
            "say $w"
            "if $w is 5"
            "    say `"left`""
            "if 5 is $w"
            "    say `"right`""
            "if $w is greater than 4 and 6 is not $w"
            "    say `"both`""
        ) -join $script:NL
        $out = Invoke-Source $source
        Assert-Lines -Expected @('5', 'left', 'right', 'both') -Actual $out -Message $w
    }
}

Test-Otter 'D-2 positive: ordinary words work as parameters, loop variables and into-targets' {
    foreach ($w in $script:OrdinaryWords) {
        $source = @(
            "to bump $w"
            "    $w is $w plus 1"
            "    if $w is 3"
            "        say `"param`" $w"
            "bump 2"
            "xs are"
            "    7"
            "for each $w in xs"
            "    if 7 is $w"
            "        say `"loop`" $w"
            "split `"a-b`" by `"-`" into $w"
            "say length of $w"
        ) -join $script:NL
        $out = Invoke-Source $source
        Assert-Lines -Expected @('param 3', 'loop 7', '2') -Actual $out -Message $w
    }
}

Test-Otter 'D-2 positive: ordinary words work as function names - statement call, expression call, make' {
    foreach ($w in $script:OrdinaryWords) {
        $source = @(
            "to $w n"
            "    return n times 2"
            "$w 1"
            "r is $w 3"
            "say r"
            "$w 5 make s"
            "say s"
        ) -join $script:NL
        $out = Invoke-Source $source
        Assert-Lines -Expected @('6', '10') -Actual $out -Message $w
    }
}

Test-Otter 'D-2 positive: contextual words that are NOT reserved stay usable' {
    # Phrase-only heads: they take over a line only before one specific word.
    $out = Invoke-Source (@(
        'to go steps', '    say "go" steps', 'go 3',
        'to watch p', '    say "watch" p', 'watch 1',
        'to close p', '    say "close" p', 'close 2',
        'to store p', '    say "store" p', 'store 4',
        'to add p q', '    say p plus q', 'add 2 3'
    ) -join $script:NL)
    Assert-Lines -Expected @('go 3', 'watch 1', 'close 2', 'store 4', '5') -Actual $out
    # `count`, `file`, `between`, `contains` as variables in their working positions.
    $out = Invoke-Source (@(
        'to tally count', '    count is count plus 1', '    say count', 'tally 1',
        'files are', '    "a.txt"', 'for each file in files', '    say file',
        'between is 3', 'say between plus 1',
        'contains is 2', 'if contains is 2', '    say "contains ok"'
    ) -join $script:NL)
    Assert-Lines -Expected @('2', 'a.txt', '4', 'contains ok') -Actual $out
}

$script:StatementWords = @('animate', 'decrease', 'decrypt', 'derive', 'encrypt', 'fail', 'focus', 'gap',
                           'hash', 'hide', 'increase', 'kill', 'layout', 'listen', 'lock', 'memo',
                           'motion', 'on', 'post', 'print', 'respond', 'restart', 'shared', 'shut',
                           'sign', 'start', 'state', 'stop', 'unzip', 'use', 'wait', 'zip')

Test-Otter 'D-2 positive: `to range start finish` reads its parameter `start`' {
    $out = Invoke-Source (@('to range start finish', '    say start "to" finish', '    return finish minus start', 'r is range 2 and 9', 'say r') -join $script:NL)
    Assert-Lines -Expected @('2 to 9', '7') -Actual $out
}

Test-Otter 'D-2 positive: statement words are NOT reserved as variables - parameters, loop variables and into-targets read correctly everywhere' {
    foreach ($w in $script:StatementWords) {
        Assert-True ($null -eq (Get-OtterReservedWordReason -Word $w -Role 'variable')) "$w must not be a reserved variable name"
        $source = @(
            "to twice n"
            "    return n times 2"
            "to probe $w"
            "    say $w"
            "    say `"v`" $w"
            "    y is $w plus 1"
            "    say y"
            "    say twice $w"
            "    if $w is 3 and 3 is $w"
            "        say `"cmp`""
            "    if $w is greater than 2"
            "        say `"gt`""
            "    return $w"
            "r is probe 3"
            "say r"
            "xs are"
            "    5"
            "for each $w in xs"
            "    say `"loop`" $w"
            "split `"a-b`" by `"-`" into $w"
            "say length of $w"
        ) -join $script:NL
        Assert-AreEqual -Expected 0 -Actual (Get-Diagnostics $source).Count -Message "$w must pass validation"
        $out = Invoke-Source $source
        Assert-Lines -Expected @('3', 'v 3', '4', '6', 'cmp', 'gt', '3', 'loop 5', '2') -Actual $out -Message $w
    }
}

Test-Otter 'D-2 positive: reassigning a statement-word variable fails LOUDLY at parse time (never silently)' {
    foreach ($w in @('start', 'zip', 'print', 'wait', 'state')) {
        Assert-OtterFails -Body { Parse "to f $w$($script:NL)    $w is $w plus 1" }
    }
}

Test-Otter 'D-2 positive: the shipped examples have no reserved-word declarations' {
    $offenders = [System.Collections.Generic.List[string]]::new()
    foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'examples') -Filter '*.ot' -File)) {
        $source = [System.IO.File]::ReadAllText($file.FullName)
        try { $program = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $source) } catch { continue }
        foreach ($diagnostic in (Get-OtterLanguageContractDiagnostics -Program $program)) {
            $offenders.Add("$($file.Name):$($diagnostic.Line) $($diagnostic.Message)")
        }
    }
    Assert-True ($offenders.Count -eq 0) ($offenders -join '; ')
}


# =================================================================
# D-2 (3) negative: one per category - diagnostic, and nothing runs
# =================================================================

$script:NegativeCases = @(
    @{ Category = 'fn-ui'; Word = 'main'; Line = 1; Reason = 'read as a UI element'
       Source = "to main$($script:NL)    say `"ran`"$($script:NL)main" }
    @{ Category = 'fn-statement'; Word = 'send'; Line = 1; Reason = 'read as the `send` statement'
       Source = "to send p$($script:NL)    say `"ran`" p$($script:NL)say `"ran`"" }
    @{ Category = 'fn-keyword'; Word = 'otherwise'; Line = 1; Reason = 'part of Otter''s own grammar'
       Source = "to otherwise$($script:NL)    say `"ran`"$($script:NL)say `"ran`"" }
    @{ Category = 'fn-builtin'; Word = 'today'; Line = 1; Reason = 'built-in value'
       Source = "to today$($script:NL)    say `"ran`"$($script:NL)say `"ran`"" }
    @{ Category = 'var-state-http'; Word = 'completed'; Line = 2; Reason = 'HTTP request''s or command job''s state'
       Source = "say `"ran`"$($script:NL)completed is `"done`"$($script:NL)status is `"done`"$($script:NL)if status is completed$($script:NL)    say `"same`"" }
    @{ Category = 'var-state-socket'; Word = 'closed'; Line = 2; Reason = 'websocket''s, TCP connection''s or UDP socket''s state'
       Source = "say `"ran`"$($script:NL)to check door closed$($script:NL)    if door is closed$($script:NL)        say `"shut`"" }
    @{ Category = 'var-state-server'; Word = 'listening'; Line = 2; Reason = 'TCP server''s state'
       Source = "say `"ran`"$($script:NL)for each listening in xs$($script:NL)    say listening" }
    @{ Category = 'var-state-tls'; Word = 'secure'; Line = 2; Reason = 'TCP connection uses TLS'
       Source = "say `"ran`"$($script:NL)ask `"?`" and call it secure" }
    @{ Category = 'var-state-watch'; Word = 'watching'; Line = 2; Reason = 'file watcher is running'
       Source = "say `"ran`"$($script:NL)watching is true" }
)

Test-Otter 'D-2 negative: every category has a negative case' {
    $categories = @($script:Reserved | ForEach-Object { $_.Category } | Sort-Object -Unique)
    $covered = @($script:NegativeCases | ForEach-Object { $_.Category } | Sort-Object -Unique)
    Assert-AreEqual -Expected ($categories -join ',') -Actual ($covered -join ',')
}

foreach ($case in $script:NegativeCases) {
    $caseCopy = $case
    Test-Otter "D-2 negative [$($case.Category)]: '$($case.Word)' is rejected with word, line and reason" {
        $diagnostics = Get-Diagnostics $caseCopy.Source
        Assert-AreEqual -Expected 1 -Actual $diagnostics.Count -Message 'diagnostic count'
        $d = $diagnostics[0]
        Assert-AreEqual -Expected $caseCopy.Line -Actual $d.Line -Message 'line'
        Assert-AreEqual -Expected 'ReservedWord' -Actual $d.Code -Message 'code'
        Assert-True ($d.Message.StartsWith("``$($caseCopy.Word)`` is a reserved word in Otter: ")) "message must name the word: $($d.Message)"
        Assert-True ($d.Message.Contains($caseCopy.Reason)) "message must give the reason [$($caseCopy.Reason)]: $($d.Message)"
        Assert-True ($d.Message.Contains('Choose a different name, for example')) "message must suggest a name: $($d.Message)"
        Assert-True ($d.Column -gt 0) 'the diagnostic should point at the word'
        # Assert-OtterLanguageContract refuses to hand the program on.
        Assert-OtterFails -Containing 'is a reserved word in Otter' -Body { Invoke-Source $caseCopy.Source }
    }
}

Test-Otter 'D-2 negative: every declaration form is checked' {
    $forms = [ordered]@{
        'assignment'      = 'completed is 1'
        'parameter'       = "to f completed$($script:NL)    say 1"
        'for each'        = "for each completed in xs$($script:NL)    say 1"
        'count as'        = "count from 1 to 3 as completed$($script:NL)    say 1"
        'into'            = 'read "a.txt" into completed'
        'make'            = '1 plus 2 make completed'
        'call result'     = "to f$($script:NL)    return 1$($script:NL)f make completed"
        'ask call it'     = 'ask "?" and call it completed'
        'list'            = "completed are$($script:NL)    1"
        'object has'      = "completed has$($script:NL)    size is 1"
        'try otherwise'   = "try$($script:NL)    say 1$($script:NL)otherwise into completed$($script:NL)    say 2"
        'nested in block' = "if true$($script:NL)    repeat 2 times$($script:NL)        read `"a.txt`" into completed"
    }
    foreach ($form in $forms.Keys) {
        $diagnostics = Get-Diagnostics $forms[$form]
        Assert-True ($diagnostics.Count -ge 1) "$form - expected a reserved-word diagnostic for completed"
        Assert-True ($diagnostics[0].Message.StartsWith('`completed` is a reserved word')) "$form - $($diagnostics[0].Message)"
    }
}

Test-Otter 'D-2 negative: several conflicts are all reported, in source order' {
    $diagnostics = Get-Diagnostics (@('to main', '    say 1', 'completed is 1', 'to send p stopped', '    say p') -join $script:NL)
    Assert-AreEqual -Expected '1,3,4,4' -Actual (($diagnostics | ForEach-Object { $_.Line }) -join ',')
    Assert-AreEqual -Expected 'main,completed,send,stopped' -Actual (($diagnostics | ForEach-Object { ($_.Message -split '`')[1] }) -join ',')
}

$script:Entry = $null
$script:EntryError = $null
try { $script:Entry = Get-HookedOtterEntryPoint } catch { $script:EntryError = $_.Exception.Message }
function Assert-Entry { if ($null -eq $script:Entry) { throw "could not prepare the hooked entry point: $script:EntryError" } }

Test-Otter 'D-2 end to end: otter check rejects `to main` with exit 2 and names word, line and reason' {
    Assert-Entry
    $result = Invoke-OtterCli -EntryPoint $script:Entry -Command 'check' -Source "to main$($script:NL)    say `"ran`"$($script:NL)main$($script:NL)"
    Assert-AreEqual -Expected 2 -Actual $result.Exit -Message $result.Output
    Assert-True ($result.Output.Contains('Line 1:')) $result.Output
    Assert-True ($result.Output.Contains('`main` is a reserved word in Otter: a line starting with `main` is read as a UI element')) $result.Output
    Assert-True ($result.Output.Contains('for example `mainTask`')) $result.Output
    Assert-False ($result.Output.Contains('is valid')) $result.Output
}

Test-Otter 'D-2 end to end: otter run rejects before anything runs (no output from the program, exit 2)' {
    Assert-Entry
    foreach ($case in @($script:NegativeCases | Where-Object { $_.Category -in @('fn-ui', 'fn-statement', 'var-state-http') })) {
        $result = Invoke-OtterCli -EntryPoint $script:Entry -Command 'run' -Source ($case.Source + $script:NL)
        Assert-AreEqual -Expected 2 -Actual $result.Exit -Message "$($case.Word): $($result.Output)"
        Assert-False ($result.Output -match '(?m)^ran') "$($case.Word): the program ran: $($result.Output)"
        Assert-True ($result.Output.Contains("``$($case.Word)`` is a reserved word in Otter")) $result.Output
    }
}

Test-Otter 'D-2 end to end: otter run still runs programs that use ordinary names' {
    Assert-Entry
    $result = Invoke-OtterCli -EntryPoint $script:Entry -Command 'run' -Source (@('to mainTask', '    say "hello from mainTask"', 'mainTask', 'status is "done"', 'finished is "done"', 'if status is finished', '    say "same"', '') -join $script:NL)
    Assert-AreEqual -Expected 0 -Actual $result.Exit -Message $result.Output
    Assert-AreEqual -Expected "hello from mainTask`nsame" -Actual $result.Output.Trim()
}


# =================================================================
# D-1 control: the word `and` in a condition stays a logical and
# =================================================================
#
# The D-1 arithmetic-in-conditions tests live in tests/ConditionArithmetic.Tests.ps1,
# which ships with the parser change (branch rc3-d1-parser-proposal). This
# control passes with and without that change.

Test-Otter 'D-1: the word `and` between conditions stays a logical and' {
    $condition = (Parse "if t and y is 3$($script:NL)    say 1").Statements[0].Branches[0].Condition
    Assert-True ($condition -is [LogicalExpr] -and $condition.Op -eq [LogicalOp]::And) "expected a LogicalExpr, got $($condition.GetType().Name)"
    Assert-True ($condition.Right -is [ComparisonExpr]) 'expected `y is 3` on the right of the and'
}

Complete-OtterTests
