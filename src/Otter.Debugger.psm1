using module ..\Otter.Contract.psm1
using module .\Otter.Runtime.psm1
using module .\Otter.Interpreter.psm1

# Otter.Debugger.psm1
#
# The Otter debugger. It is not a second interpreter: it plugs into the ONE
# hook the real interpreter exposes for this purpose - Set-OtterStatementHook
# in src/Otter.Interpreter.psm1, called before every statement runs - and
# everything it reports (line, variables, call stack) comes straight from the
# production Invoke-OtterStatement / Invoke-OtterCall path. Values are shown
# through Format-OtterValue, the function `say` uses, so a value looks exactly
# as it would printed. No PowerShell detail is ever part of what it reports.
#
# PROTOCOL
#
# Events: stdout lines "@@OTTER_DEBUG@@ " + compact JSON. Every other stdout
# line is what the program itself printed; Otter Studio's backend
# (otter-studio/serve.mjs) relays both. Without `otter debug` this module is
# never loaded and the prefix never appears.
#
#   paused     {"event":"paused","reason":"breakpoint|step|pause|error",
#               "file":"main.ot","line":6,
#               "locals":{"score":"10"},            name -> as `say` prints it
#               "callStack":[{"function":"greet","line":9}],  callers' call lines
#               "frames":[{"function":"greet","line":6},{"function":"(program)","line":9}],
#               "scopes":[{"name":"Locals","variables":[{"name","value","type","children"}]},
#                         {"name":"Globals",...}],
#               "message":"..." (reason error only)}
#   log        {"event":"log","line":7,"text":"..."}        a logpoint fired
#   evaluated  {"event":"evaluated","id":"w1","expression":"...","value":"...","type":"..."}
#              or {..., "error":"..."}
#   finished   {"event":"finished"}
#
# Commands: one line each on stdin. They are read while the program runs as
# well as while it is paused, so `pause` and changed breakpoints take effect
# at the next statement.
#
#   continue                run until the next breakpoint
#   next                    step over: the next statement in this frame (or a caller)
#   step                    step into: the very next statement, inside a call too
#   out                     step out: the next statement after this function returns
#   pause                   stop at the next statement
#   breakpoints <json>      replace the breakpoints (also OTTER_DEBUG_BREAKPOINTS at start): [{"line":5},
#                           {"line":9,"condition":"count is 3"},
#                           {"line":10,"hits":">= 5"},   (5, >= 5, > 5, % 3)
#                           {"line":12,"log":"total is {total}"}]
#   eval <id> <expression>  (while paused) evaluate an Otter expression in the
#                           paused frame - watches and the debug console
#
# A closed stdin while paused continues (a session can never hang forever).
# Lines are positions in the program as compiled: for a program that `use`s
# other files, a line inside an imported file is its position in the combined
# source (the same lines `otter run` reports before remapping).

$script:OtterDebugEventPrefix = '@@OTTER_DEBUG@@ '
$script:Session = $null

function Write-OtterDebugEvent {
    param([System.Collections.Specialized.OrderedDictionary]$Event)

    $json = $Event | ConvertTo-Json -Compress -Depth 12
    [Console]::Out.WriteLine("$($script:OtterDebugEventPrefix)$json")
    [Console]::Out.Flush()
}

# --- Values, as the user sees them ------------------------------------------

function Test-OtterDebugHidden {
    param([object]$Value)
    return ($Value -is [OtterFunction]) -or ($Value -is [OtterType])
}

# One variable for the Variables view: its value as `say` prints it, its
# Otter type, and - for a list or a thing - what is inside, a few levels deep.
function ConvertTo-OtterDebugVariable {
    param([string]$Name, [object]$Value, [int]$Depth = 0)

    $shown = '?'
    try { $shown = Format-OtterValue -Value $Value } catch { $shown = '?' }
    if ($shown.Length -gt 400) { $shown = $shown.Substring(0, 400) + ' ...' }
    $entry = [ordered]@{ name = $Name; value = $shown; type = (Get-OtterTypeName -Value $Value) }
    if ($Depth -ge 3) { return $entry }
    if (Test-OtterList $Value) {
        $children = @()
        $i = 0
        foreach ($item in $Value) {
            $i++
            if ($i -gt 100) { $children += [ordered]@{ name = '...'; value = "$($Value.Count - 100) more"; type = '' }; break }
            $children += (ConvertTo-OtterDebugVariable -Name "item $i" -Value $item -Depth ($Depth + 1))
        }
        $entry['children'] = $children
    }
    elseif (Test-OtterObject $Value) {
        $children = @()
        foreach ($prop in $Value.PropertyNames()) {
            $children += (ConvertTo-OtterDebugVariable -Name $prop -Value $Value.ReadProperty($prop) -Depth ($Depth + 1))
        }
        $entry['children'] = $children
    }
    return $entry
}

function Get-OtterDebugVariables {
    param([OtterEnvironment]$Environment)
    $items = @()
    foreach ($key in ($Environment.Variables.Keys | Sort-Object)) {
        $value = $null
        try { $value = $Environment.Get($key) } catch { continue }
        if (Test-OtterDebugHidden $value) { continue }
        $items += (ConvertTo-OtterDebugVariable -Name $key -Value $value)
    }
    return , $items
}

# Otter locals, not PowerShell variables: only what THIS frame's environment
# owns directly, each rendered as `say` would print it.
function Get-OtterDebugLocals {
    param([OtterEnvironment]$Environment)

    $locals = [ordered]@{}
    foreach ($key in $Environment.Variables.Keys) {
        try {
            $value = $Environment.Get($key)
            if (Test-OtterDebugHidden $value) { continue }
            $locals[$key] = Format-OtterValue -Value $value
        }
        catch {
            $locals[$key] = '?'
        }
    }
    return $locals
}

# The Otter call stack in Otter terms: each running function and the line
# that called it, from the interpreter's own bookkeeping.
function Get-OtterDebugCallStack {
    $frames = @()
    foreach ($frame in (Get-OtterCallStackSnapshot)) {
        $frames += [ordered]@{ function = $frame.FunctionName; line = $frame.CallLine }
    }
    return $frames
}

# Innermost first: where each frame is now. The current frame is at the
# paused line; each caller is at the line that made the call.
function Get-OtterDebugFrames {
    param([int]$Line)
    $stack = @(Get-OtterCallStackSnapshot)
    $frames = @()
    $here = $Line
    for ($i = $stack.Count - 1; $i -ge 0; $i--) {
        $frames += [ordered]@{ function = $stack[$i].FunctionName; line = $here }
        $here = $stack[$i].CallLine
    }
    $frames += [ordered]@{ function = '(program)'; line = $here }
    return $frames
}

function Get-OtterRootEnvironment {
    param([OtterEnvironment]$Environment)
    $env = $Environment
    while ($null -ne $env.Parent) { $env = $env.Parent }
    return $env
}

# --- Evaluating an expression in the paused frame -----------------------------

# The statement an expression is parsed into: an `if` (a comparison) or an
# assignment (a value). Neither ever runs; only its expression is evaluated.
function Get-OtterDebugExpressionSource {
    param([string]$Text, [bool]$AsCondition)
    if ($AsCondition) { return "if $Text`n    say 0`n." }
    return "otterDebugValue is $Text"
}

function Test-OtterDebugExpressionParses {
    param([string]$Text, [bool]$AsCondition)
    $ast = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source (Get-OtterDebugExpressionSource -Text $Text -AsCondition $AsCondition))
    $statement = @($ast.Statements)[0]
    if ($null -eq $statement) { return $false }
    if ($AsCondition) { return $statement.Kind.ToString() -eq 'If' }
    return $statement.Kind.ToString() -eq 'Assign'
}

function Invoke-OtterDebugExpression {
    param([string]$Expression, [OtterEnvironment]$Environment)
    $text = "$Expression".Trim()
    if (-not $text) { throw [OtterError]::new('Write an expression to evaluate, for example: total plus 1', 0, 'runtime') }
    # Otter reads a comparison (`price is 20`, `name contains "a"`) as an `if`
    # condition, and arithmetic (`n times 10`, `total plus 1`) as the value
    # of an assignment - each form misreads the other (`x is price is 20` is
    # price; `if n plus 1` is true). The words decide which form comes first;
    # if it does not parse, the other is tried. Neither statement ever runs.
    $comparison = $text -match '\b(is|are|equals|contains|starts|ends|less|greater|more|least|most|not|and|or|exists|empty)\b'
    $forms = if ($comparison) { @($true, $false) } else { @($false, $true) }
    $chosen = $null
    $firstError = $null
    foreach ($asCondition in $forms) {
        try { if (Test-OtterDebugExpressionParses -Text $text -AsCondition $asCondition) { $chosen = $asCondition; break } }
        catch { if ($null -eq $firstError) { $firstError = $_ } }
    }
    if ($null -eq $chosen) {
        $why = if ($firstError) { Get-OtterDebugErrorMessage $firstError } else { 'not an expression' }
        throw [OtterError]::new("That is not an expression Otter can evaluate: $text ($why)", 0, 'runtime')
    }
    # Parsed again and evaluated right here: a parsed expression handed back
    # from another function reached Get-OtterValue as text.
    $ast = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source (Get-OtterDebugExpressionSource -Text $text -AsCondition $chosen))
    $statement = @($ast.Statements)[0]
    if ($chosen) { return , (Get-OtterValue -Expression $statement.Branches[0].Condition -Environment $Environment) }
    return , (Get-OtterValue -Expression $statement.Value -Environment $Environment)
}

function Get-OtterDebugErrorMessage {
    param($ErrorRecord)
    $ex = $ErrorRecord.Exception
    while ($ex -is [System.Management.Automation.RuntimeException] -and $null -ne $ex.InnerException -and -not ($ex -is [OtterError])) { $ex = $ex.InnerException }
    return [string]$ex.Message
}

# --- Commands -----------------------------------------------------------------

function Set-OtterDebugBreakpoints {
    param([string]$Json)
    $map = @{}
    $items = @()
    # Assigned before @(): Windows PowerShell 5.1 passes a JSON array down
    # the pipeline as ONE object, so @($json | ConvertFrom-Json) would be a
    # one-item list holding the whole array.
    try { $parsed = ConvertFrom-Json -InputObject $Json; $items = @($parsed) } catch { return }
    foreach ($bp in $items) {
        if ($null -eq $bp) { continue }
        $line = 0
        if ($bp -is [int] -or $bp -is [long] -or $bp -is [double]) { $line = [int]$bp }
        elseif ($bp.PSObject.Properties['line']) { $line = [int]$bp.line }
        if ($line -le 0) { continue }
        $condition = if ($bp -isnot [ValueType] -and $bp.PSObject.Properties['condition']) { [string]$bp.condition } else { '' }
        $log = if ($bp -isnot [ValueType] -and $bp.PSObject.Properties['log']) { [string]$bp.log } else { '' }
        $hitsWhen = if ($bp -isnot [ValueType] -and $bp.PSObject.Properties['hits']) { [string]$bp.hits } else { '' }
        # A line's count so far survives a change to the breakpoints.
        $old = if ($null -ne $script:Session.Breakpoints) { $script:Session.Breakpoints[$line] } else { $null }
        $count = if ($null -ne $old) { [int]$old.HitCount } else { 0 }
        $map[$line] = @{ Condition = $condition; Log = $log; Hits = $hitsWhen; HitCount = $count }
    }
    $script:Session.Breakpoints = $map
}

# Hit counts, as in Visual Studio: "5" stops at the 5th hit, ">= 5" or "> 5"
# from then on, "% 3" every third. A hit is the line reached with its
# condition (if any) true. Anything else is not a hit count: always stop.
function Test-OtterDebugHitCount {
    param([int]$Count, [string]$When)
    $text = "$When".Trim()
    if (-not $text) { return $true }
    if ($text -match '^%\s*(\d+)$') { $n = [int]$Matches[1]; return ($n -gt 0 -and ($Count % $n) -eq 0) }
    if ($text -match '^>=\s*(\d+)$') { return $Count -ge [int]$Matches[1] }
    if ($text -match '^>\s*(\d+)$') { return $Count -gt [int]$Matches[1] }
    if ($text -match '^(?:==?\s*)?(\d+)$') { return $Count -eq [int]$Matches[1] }
    return $true
}

# Handles a command that does not resume (breakpoints, pause, eval). Returns
# the resume mode for continue / next / step / out, or $null.
function Invoke-OtterDebugCommand {
    param([string]$Line, [object]$Paused)
    $text = "$Line".Trim()
    if (-not $text) { return $null }
    $verb, $rest = $text -split '\s+', 2
    switch ($verb.ToLowerInvariant()) {
        'continue' { return 'run' }
        'next' { return 'over' }
        'step' { return 'into' }
        'out' { return 'out' }
        'pause' { $script:Session.PauseRequested = $true; return $null }
        'breakpoints' { Set-OtterDebugBreakpoints -Json $rest; return $null }
        'eval' {
            $id, $expression = "$rest" -split '\s+', 2
            $event = [ordered]@{ event = 'evaluated'; id = $id; expression = "$expression" }
            if ($null -eq $Paused) {
                $event['error'] = 'The program is running. Pause it to evaluate an expression.'
            } else {
                try {
                    $value = Invoke-OtterDebugExpression -Expression $expression -Environment $Paused.Environment
                    $variable = ConvertTo-OtterDebugVariable -Name "$expression" -Value $value
                    $event['value'] = $variable.value
                    $event['type'] = $variable.type
                    if ($variable.Contains('children')) { $event['children'] = $variable.children }
                } catch {
                    $event['error'] = Get-OtterDebugErrorMessage $_
                }
            }
            Write-OtterDebugEvent -Event $event
            return $null
        }
        default { return $null }
    }
}

# Commands that arrived while the program runs (pause, new breakpoints).
function Read-OtterDebugPendingCommands {
    $s = $script:Session
    while ($null -ne $s.Pending -and $s.Pending.IsCompleted) {
        $line = $s.Pending.Result
        if ($null -eq $line) { $s.Pending = $null; $s.InputClosed = $true; break }
        $s.Pending = $s.Reader.ReadLineAsync()
        # A resume command while already running changes nothing.
        [void](Invoke-OtterDebugCommand -Line $line -Paused $null)
    }
}

# Stopped: report where, then answer commands until one resumes.
function Wait-OtterDebugResume {
    param([string]$Reason, [object]$Statement, [OtterEnvironment]$Environment, [string]$Message = '')
    $s = $script:Session
    $line = $Statement.Line
    $root = Get-OtterRootEnvironment -Environment $Environment
    $scopes = @([ordered]@{ name = 'Locals'; variables = (Get-OtterDebugVariables -Environment $Environment) })
    if (-not [object]::ReferenceEquals($root, $Environment)) {
        $scopes += [ordered]@{ name = 'Globals'; variables = (Get-OtterDebugVariables -Environment $root) }
    }
    $event = [ordered]@{
        event     = 'paused'
        reason    = $Reason
        file      = $s.FileName
        line      = $line
        locals    = (Get-OtterDebugLocals -Environment $Environment)
        callStack = @(Get-OtterDebugCallStack)
        frames    = @(Get-OtterDebugFrames -Line $line)
        scopes    = $scopes
    }
    if ($Message) { $event['message'] = $Message }
    Write-OtterDebugEvent -Event $event

    $paused = @{ Environment = $Environment }
    while ($true) {
        if ($s.InputClosed -or $null -eq $s.Pending) { return 'run' }
        $s.Pending.Wait()
        $command = $s.Pending.Result
        if ($null -eq $command) { $s.Pending = $null; $s.InputClosed = $true; return 'run' }
        $s.Pending = $s.Reader.ReadLineAsync()
        $mode = Invoke-OtterDebugCommand -Line $command -Paused $paused
        if ($null -ne $mode) { return $mode }
    }
}

# A logpoint's text: {expression} parts are evaluated in the frame.
function Format-OtterDebugLogText {
    param([string]$Template, [OtterEnvironment]$Environment)
    return [regex]::Replace($Template, '\{([^{}]+)\}', {
        param($m)
        try { return (Format-OtterValue -Value (Invoke-OtterDebugExpression -Expression $m.Groups[1].Value -Environment $Environment)) }
        catch { return "{$($m.Groups[1].Value): $(Get-OtterDebugErrorMessage $_)}" }
    })
}

# The hook: before every statement. Decides whether to stop here.
function Invoke-OtterDebugHook {
    param($Statement, $Environment, $CallStack)
    $s = $script:Session
    # Evaluating an expression (a watch, a condition) runs Otter code, which
    # reaches this hook again: those statements are never stopped at.
    if ($s.InHook) { return }
    $s.InHook = $true
    try {
        $s.LastStatement = $Statement
        $s.LastEnvironment = $Environment
        Read-OtterDebugPendingCommands
        $depth = @($CallStack).Count
        $line = $Statement.Line
        $reason = $null
        if ($s.PauseRequested) { $reason = 'pause' }
        elseif ($s.Mode -eq 'into') { $reason = 'step' }
        elseif ($s.Mode -eq 'over' -and $depth -le $s.StepDepth) { $reason = 'step' }
        elseif ($s.Mode -eq 'out' -and $depth -lt $s.StepDepth) { $reason = 'step' }
        if (-not $reason -and $s.Breakpoints.ContainsKey($line)) {
            $bp = $s.Breakpoints[$line]
            $hit = $true
            if ($bp.Condition) {
                try { $hit = Test-OtterTruthy (Invoke-OtterDebugExpression -Expression $bp.Condition -Environment $Environment) }
                catch {
                    Write-OtterDebugEvent -Event ([ordered]@{ event = 'log'; line = $line; text = "Breakpoint condition on line ${line}: $(Get-OtterDebugErrorMessage $_)" })
                    $hit = $true
                }
            }
            if ($hit) {
                # HitCount, not Count: .Count on a hashtable is its number of entries.
                $bp.HitCount = [int]$bp.HitCount + 1
                $hit = Test-OtterDebugHitCount -Count $bp.HitCount -When $bp.Hits
            }
            if ($hit -and $bp.Log) {
                Write-OtterDebugEvent -Event ([ordered]@{ event = 'log'; line = $line; text = (Format-OtterDebugLogText -Template $bp.Log -Environment $Environment) })
                $hit = $false
            }
            if ($hit) { $reason = 'breakpoint' }
        }
        if (-not $reason) { return }
        $s.PauseRequested = $false
        $mode = Wait-OtterDebugResume -Reason $reason -Statement $Statement -Environment $Environment
        $s.Mode = $mode
        $s.StepDepth = $depth
    }
    finally {
        $s.InHook = $false
    }
}

# Wires the debugger into the production interpreter.
function Start-OtterDebugSession {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [int[]]$Breakpoints = @()
    )

    $reader = [System.IO.StreamReader]::new([Console]::OpenStandardInput(), [System.Text.UTF8Encoding]::new($false))
    $map = @{}
    foreach ($b in $Breakpoints) { if ($b -gt 0) { $map[$b] = @{ Condition = ''; Log = ''; Hits = ''; HitCount = 0 } } }
    $script:Session = @{
        FileName = $FileName
        Breakpoints = $map
        Mode = 'run'
        StepDepth = 0
        PauseRequested = $false
        InHook = $false
        Reader = $reader
        Pending = $reader.ReadLineAsync()
        InputClosed = $false
        LastStatement = $null
        LastEnvironment = $null
    }
    # Breakpoints with conditions or log text, from the editor that started
    # the session: JSON in OTTER_DEBUG_BREAKPOINTS (an environment variable,
    # not an argument - Windows re-quotes JSON passed on a command line), in
    # place before the first statement runs.
    if ($env:OTTER_DEBUG_BREAKPOINTS) { Set-OtterDebugBreakpoints -Json $env:OTTER_DEBUG_BREAKPOINTS }
    Set-OtterStatementHook -Hook ${function:Invoke-OtterDebugHook}
}

# The program stopped with an error: stop there, as it was when the failing
# statement started - its line, the message, and the variables - so the error
# can be looked at before the session ends. Continue (or a closed stdin) ends it.
function Stop-OtterDebugOnError {
    param([string]$Message, [int]$Line = 0)
    $s = $script:Session
    if ($null -eq $s -or $null -eq $s.LastStatement) { return }
    Set-OtterStatementHook -Hook $null
    $statement = $s.LastStatement
    if ($Line -gt 0 -and $Line -ne $statement.Line) { $statement = [pscustomobject]@{ Line = $Line } }
    $s.InHook = $true
    [void](Wait-OtterDebugResume -Reason 'error' -Statement $statement -Environment $s.LastEnvironment -Message $Message)
}

# Called once the program has finished (normally or by erroring out) so
# Studio can tell "still running/paused" apart from "done".
function Complete-OtterDebugSession {
    Write-OtterDebugEvent -Event ([ordered]@{ event = 'finished' })
}

Export-ModuleMember -Function `
    Start-OtterDebugSession, Complete-OtterDebugSession, Stop-OtterDebugOnError, `
    Write-OtterDebugEvent, Get-OtterDebugLocals, Get-OtterDebugCallStack, Invoke-OtterDebugHook
