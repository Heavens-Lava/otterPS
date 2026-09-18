using module ..\Otter.Contract.psm1
using module .\Otter.Runtime.psm1
using module .\Otter.Interpreter.psm1

# Otter.Debugger.psm1
#
# FIRST SLICE of the production Otter debugger.
#
#   breakpoint on an Otter source line -> pause -> exact source location ->
#   Otter locals in the paused frame -> continue -> program finishes normally
#
# This is not a second interpreter. It plugs into the ONE hook the real
# interpreter exposes for exactly this purpose - Set-OtterStatementHook, in
# src/Otter.Interpreter.psm1 - and everything it reports (file, line, locals,
# call stack) comes straight from the production Invoke-OtterStatement /
# Invoke-OtterCall path. No PowerShell implementation detail (stack frames,
# .NET types, variable storage) is ever part of what gets reported: locals
# are read through Format-OtterValue, the same function `say` itself uses,
# so a paused local always looks exactly like it would printed.
#
# PROTOCOL (stdout, line-oriented):
#   Every debug event is one line, "@@OTTER_DEBUG@@ " followed by compact
#   JSON. Otter Studio's backend (otter-studio/serve.mjs) reads the child
#   process's stdout, treats a line with that prefix as a debug event, and
#   passes every OTHER line through unchanged as real program output - so
#   what a program itself printed via `say` is never touched, reordered, or
#   filtered. When no debug session is started at all (ordinary `otter run`),
#   this module is never loaded and the prefix never appears - zero effect
#   on a normal run.
#
#   {"event":"paused","file":"main.ot","line":6,"locals":{"score":"10"},"callStack":[{"function":"greet","line":9}]}
#   {"event":"finished"}
#
# RESUMING: after a "paused" event, this process blocks on the real console
# input stream waiting for one line of text. "continue" is the only command
# this first slice understands - the ONLY thing proven here is
# breakpoint -> pause -> inspect -> continue, on purpose (see the task's
# explicit "do not yet implement" list: conditional breakpoints, watches,
# expression evaluation, and the rest come after this is proven).

$script:OtterDebugEventPrefix = '@@OTTER_DEBUG@@ '

function Write-OtterDebugEvent {
    param([System.Collections.Specialized.OrderedDictionary]$Event)

    $json = $Event | ConvertTo-Json -Compress -Depth 6
    [Console]::Out.WriteLine("$($script:OtterDebugEventPrefix)$json")
    [Console]::Out.Flush()
}

# Otter locals, not PowerShell variables: only what THIS frame's environment
# owns directly (never the parent chain - a paused frame should show exactly
# what a real Otter call frame has, the same boundary Invoke-OtterCall
# itself already enforces for parameters shadowing outer variables), each
# value rendered through the same Format-OtterValue `say` uses.
function Get-OtterDebugLocals {
    param([OtterEnvironment]$Environment)

    $locals = [ordered]@{}
    foreach ($key in $Environment.Variables.Keys) {
        try {
            $locals[$key] = Format-OtterValue -Value $Environment.Get($key)
        }
        catch {
            $locals[$key] = '?'
        }
    }
    return $locals
}

# The Otter call stack in Otter terms: which function, and the Otter source
# line it was called from. Comes straight from Get-OtterCallStackSnapshot -
# the interpreter's own bookkeeping, not anything this module derives itself.
function Get-OtterDebugCallStack {
    $frames = @()
    foreach ($frame in (Get-OtterCallStackSnapshot)) {
        $frames += [ordered]@{ function = $frame.FunctionName; line = $frame.CallLine }
    }
    return $frames
}

# Wires a breakpoint-aware hook into the production interpreter and blocks
# there, in place, whenever execution reaches a statement on a breakpoint
# line - exactly the statement Invoke-OtterStatement was about to run next,
# so "paused" always means "about to execute this exact source line", never
# "already ran past it".
function Start-OtterDebugSession {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [int[]]$Breakpoints = @()
    )

    $breakpointSet = [System.Collections.Generic.HashSet[int]]::new([int[]]$Breakpoints)

    $hook = {
        param($Statement, $Environment, $CallStack)

        if (-not $breakpointSet.Contains($Statement.Line)) { return }

        Write-OtterDebugEvent -Event ([ordered]@{
            event     = 'paused'
            file      = $FileName
            line      = $Statement.Line
            locals    = (Get-OtterDebugLocals -Environment $Environment)
            callStack = @(Get-OtterDebugCallStack)
        })

        while ($true) {
            $line = [Console]::In.ReadLine()
            if ($null -eq $line) { return }   # stdin closed - never hang forever
            if ($line.Trim() -eq 'continue') { return }
        }
    }.GetNewClosure()

    Set-OtterStatementHook -Hook $hook
}

# Called once the program has finished (normally or by erroring out) so
# Studio can tell "still running/paused" apart from "done".
function Complete-OtterDebugSession {
    Write-OtterDebugEvent -Event ([ordered]@{ event = 'finished' })
}

Export-ModuleMember -Function `
    Start-OtterDebugSession, Complete-OtterDebugSession, `
    Write-OtterDebugEvent, Get-OtterDebugLocals, Get-OtterDebugCallStack
