using module ..\Otter.Contract.psm1
using module .\Otter.Runtime.psm1
using module .\Otter.Library.psm1
using module .\Otter.UI.psm1
using module .\Otter.Database.psm1

# Otter.Interpreter.psm1
#
# The tree-walking interpreter. It takes the ProgramNode the parser built and
# does what it says.
#
#   ProgramNode
#       |
#       +-- SayStmt      -> print
#       +-- AssignStmt   -> store a variable
#       +-- IfStmt       -> test, then walk one branch
#       +-- WhileStmt    -> test and walk the body, repeatedly
#       ...
#
# There are only two kinds of function in here:
#
#   Invoke-Otter*  runs a STATEMENT and produces no value
#   Get-Otter*     evaluates an EXPRESSION and returns a value
#
# Keeping those apart is what stops stray PowerShell output leaking into
# Otter's results, which is the classic way an interpreter like this breaks.


# The source text, kept only so runtime errors can quote the offending line
# (D14). Set once per program run.
$script:SourceLines = @()

# The outermost scope. Function bodies hang off this, not off their caller,
# so a function cannot see its caller's local variables.
$script:GlobalEnvironment = $null

# ===============================================================
# DEBUGGER HOOK
# ===============================================================
#
# ONE instrumentation point for the whole interpreter: every statement,
# top-level or nested (if/while/repeat/foreach bodies, function bodies - all
# of them run through Invoke-OtterStatement), passes through here first. A
# debugger (src/Otter.Debugger.psm1) plugs in by calling
# Set-OtterStatementHook; nothing else in this file knows a debugger exists.
#
# When no hook is set (the default - every normal `otter run`), this is a
# single null check per statement and nothing else changes: no extra output,
# no altered control flow, no altered values. That is what "preserve normal
# execution semantics when debugging is disabled" means at the code level.
$script:StatementHook = $null

function Set-OtterStatementHook {
    param([scriptblock]$Hook)
    $script:StatementHook = $Hook
}

# The Otter call stack, in Otter terms only: which function is running and
# the Otter source line that called it. Maintained unconditionally (it is
# pure bookkeeping - a list add/remove around a call - and never touches an
# Otter value or a control-flow decision), so "Otter call frames" are a real,
# always-available concept, not something that only exists while debugging.
$script:CallStack = [System.Collections.Generic.List[object]]::new()

function Get-OtterCallStackSnapshot {
    return $script:CallStack
}

# Where "say" sends its text. Defaults to the console; tests swap in a
# collector so they can assert on what a program printed. Keeping this behind
# one function is also what lets `say` avoid Write-Output, which would leak
# into the return value of every function call.
$script:OutputWriter = $null

function Set-OtterOutputWriter {
    param([scriptblock]$Writer)
    $script:OutputWriter = $Writer
}

# D100: show progress redraws in place (leading \r, no newline) so a run
# of calls updates one bar rather than spamming lines - but that means the
# cursor is left mid-line afterward. Any OTHER output must flush a real
# newline first or it lands glued onto the end of the bar's text.
$script:OtterProgressBarActive = $false

function Complete-OtterProgressBarLine {
    if ($script:OtterProgressBarActive) {
        Write-Host ''
        $script:OtterProgressBarActive = $false
    }
}

# ===============================================================
# FILE WATCHING (D104) - console/desktop only; the interpreter's own
# default "I do not know how to run/work out a <kind> ... yet" errors
# already make the web target fail loudly for these NodeKinds with zero
# extra code (verified directly, same as D103's routing statements), so
# there is nothing web-specific here at all.
# ===============================================================

# Every active watcher for the CURRENT Invoke-OtterProgram run. Reset at
# the top of Invoke-OtterProgram (like $script:CallStack) so a REPL
# session reusing this module never sees a stale watcher from an earlier
# run's session state.
$script:OtterActiveWatchers = [System.Collections.Generic.List[OtterFileWatcher]]::new()

# Handlers registered via `on change of X` / `on create in X` / etc.
# Keyed by the OtterFileWatcher INSTANCE itself (reference equality,
# same as .NET's default), not by name - matches WhenStmt's own
# established pattern of resolving the target to a real object at
# registration time, not re-resolving a variable name later.
$script:OtterWatcherHandlers = [System.Collections.Generic.Dictionary[object, System.Collections.Generic.List[hashtable]]]::new()

# The ambient "changed path" / "changed file name" / "change kind" /
# "old path" context - set immediately before a watch-event handler body
# runs, cleared immediately after. $null whenever code is not currently
# inside a watch-event handler (ChangedPath/etc throw a clean error in
# that case, rather than silently returning gone).
$script:OtterCurrentWatchEvent = $null

# Coalesces duplicate OS-level notifications for the same logical change
# (D104 section 15 - explicitly runtime behavior, not new syntax). Keyed
# by "<watcher identity>|<event kind>|<path>"; an equivalent event within
# this window is dropped rather than re-dispatched.
$script:OtterWatchDebounceWindowMs = 150
$script:OtterWatchLastEventAt = @{}

function Test-OtterWatchEventShouldCoalesce {
    param([string]$Key)
    $now = [DateTime]::UtcNow
    if ($script:OtterWatchLastEventAt.ContainsKey($Key)) {
        $elapsed = ($now - $script:OtterWatchLastEventAt[$Key]).TotalMilliseconds
        if ($elapsed -lt $script:OtterWatchDebounceWindowMs) {
            $script:OtterWatchLastEventAt[$Key] = $now
            return $true
        }
    }
    $script:OtterWatchLastEventAt[$Key] = $now
    return $false
}

function New-OtterFileWatcher {
    param([string]$Path, [bool]$IsFolder, [bool]$Recursive, [int]$Line)

    # D104 section 17/18: fail loudly on a missing file/folder rather
    # than silently creating it or silently watching the parent instead.
    if ($IsFolder) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw (New-OtterRuntimeError `
                -Message "I can't watch a folder that doesn't exist: ""$Path""." `
                -Line $Line `
                -Suggestion 'Check the folder path, or create it first.')
        }
    } else {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw (New-OtterRuntimeError `
                -Message "I can't watch a file that doesn't exist: ""$Path""." `
                -Line $Line `
                -Suggestion 'Check the file path, or watch its folder instead to detect creation.')
        }
    }

    $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $native = [System.IO.FileSystemWatcher]::new()
    if ($IsFolder) {
        $native.Path = $resolvedPath
        $native.Filter = '*'
        $native.IncludeSubdirectories = $Recursive
    } else {
        # D104 section 16: watching the file's FOLDER with a name filter
        # (the standard .NET technique for "watch one file"), not the
        # file handle itself - this is what lets watching survive the
        # common editor save pattern of replace-via-temp-file-then-rename,
        # since the filter still matches once the final name reappears.
        $native.Path = Split-Path -Parent $resolvedPath
        $native.Filter = Split-Path -Leaf $resolvedPath
        $native.IncludeSubdirectories = $false
    }
    $native.NotifyFilter = [System.IO.NotifyFilters]'FileName, DirectoryName, LastWrite, CreationTime, Size'

    $sourceIdPrefix = "OtterWatch_$([Guid]::NewGuid().ToString('N'))"
    $otterWatcher = [OtterFileWatcher]::new($native, $resolvedPath, $IsFolder, $sourceIdPrefix)

    Register-ObjectEvent -InputObject $native -EventName Changed -SourceIdentifier "${sourceIdPrefix}_Changed" -MessageData $otterWatcher | Out-Null
    Register-ObjectEvent -InputObject $native -EventName Created -SourceIdentifier "${sourceIdPrefix}_Created" -MessageData $otterWatcher | Out-Null
    Register-ObjectEvent -InputObject $native -EventName Deleted -SourceIdentifier "${sourceIdPrefix}_Deleted" -MessageData $otterWatcher | Out-Null
    Register-ObjectEvent -InputObject $native -EventName Renamed -SourceIdentifier "${sourceIdPrefix}_Renamed" -MessageData $otterWatcher | Out-Null
    Register-ObjectEvent -InputObject $native -EventName Error -SourceIdentifier "${sourceIdPrefix}_Error" -MessageData $otterWatcher | Out-Null

    $native.EnableRaisingEvents = $true
    $script:OtterActiveWatchers.Add($otterWatcher)
    return $otterWatcher
}

function Stop-OtterFileWatcherInternal {
    param([OtterFileWatcher]$Watcher)

    if (-not $Watcher.Active) { return }
    $Watcher.Active = $false
    $Watcher.Native.EnableRaisingEvents = $false
    Get-EventSubscriber -SourceIdentifier "$($Watcher.SourceIdPrefix)_*" -ErrorAction SilentlyContinue | Unregister-Event
    $Watcher.Native.Dispose()
    [void]$script:OtterActiveWatchers.Remove($Watcher)
}

# Runs after every top-level statement has executed (Invoke-OtterProgram
# calls this unconditionally; it returns immediately when nothing is
# watching). Real OS file-system events, not polling - the 1-second
# Wait-Event timeout only re-checks "should this loop exit now", it is
# not how changes are detected.
# ===============================================================
# WEBSOCKETS (D106)
# ===============================================================

$script:OtterActiveWebSockets = [System.Collections.Generic.List[OtterWebSocket]]::new()
$script:OtterWebSocketHandlers = [System.Collections.Generic.Dictionary[object, System.Collections.Generic.List[hashtable]]]::new()
$script:OtterCurrentWsContext = $null

function Close-OtterWebSocketInternal {
    param([Parameter(Mandatory)][OtterWebSocket]$Socket)
    if ($Socket.Disposed) { return }
    $Socket.Disposed = $true
    try {
        $Socket.Cts.Cancel()
    } catch {}
    try {
        $Socket.Native.Dispose()
    } catch {}
    try {
        $Socket.MessageBuffer.Dispose()
    } catch {}
}

function Invoke-OtterWebSocketHandlers {
    param(
        [Parameter(Mandatory)][object]$Socket,
        [Parameter(Mandatory)][object]$EventKind,
        [Parameter(Mandatory)][hashtable]$Context
    )

    if (-not $script:OtterWebSocketHandlers.ContainsKey($Socket)) { return }
    $handlers = $script:OtterWebSocketHandlers[$Socket] | Where-Object { $_.EventKind.ToString() -eq $EventKind.ToString() }
    if (-not $handlers) { return }

    $prevContext = $script:OtterCurrentWsContext
    $script:OtterCurrentWsContext = $Context
    try {
        foreach ($h in $handlers) {
            if (Test-OtterHttpRequest $Socket) {
                if ($h.ContainsKey('Fired') -and $h.Fired) { continue }
                $h.Fired = $true
            }
            $execEnv = if ($EventKind.ToString() -eq 'Connection') {
                [OtterEnvironment]::new($h.Environment)
            } else {
                $h.Environment
            }
            Invoke-OtterStatements -Statements $h.Body -Environment $execEnv
        }
    } finally {
        $script:OtterCurrentWsContext = $prevContext
    }
}

function Invoke-OtterWatchEventLoopStep {
    param([double]$Timeout = 0.05)
    if ($script:OtterActiveWatchers.Count -eq 0) { return }
    $evt = Wait-Event -Timeout $Timeout
    if ($null -eq $evt) { return }
    Remove-Event -EventIdentifier $evt.EventIdentifier -ErrorAction SilentlyContinue

    $watcherObj = $evt.MessageData
    if ($null -eq $watcherObj -or -not $watcherObj.Active) { return }

    $sourceId = $evt.SourceIdentifier
    $kindWord = $sourceId.Substring($sourceId.LastIndexOf('_') + 1)

    if ($kindWord -eq 'Error') {
        # D104 section 22: surface a runtime diagnostic rather than
        # silently going quiet - printed directly (there is no single
        # "current statement" this background failure belongs to).
        Write-OtterDiagnostic -Level 'error' -Text "A file watcher stopped working unexpectedly for ""$($watcherObj.Path)""."
        Stop-OtterFileWatcherInternal -Watcher $watcherObj
        return
    }

    $eventKind = switch ($kindWord) {
        'Changed' { [WatchEventKind]::Change }
        'Created' { [WatchEventKind]::Create }
        'Deleted' { [WatchEventKind]::Delete }
        'Renamed' { [WatchEventKind]::Rename }
        default { $null }
    }
    if ($null -eq $eventKind) { return }

    $evtArgs = $evt.SourceEventArgs
    $path = $evtArgs.FullPath
    $oldPath = if ($eventKind -eq [WatchEventKind]::Rename) { $evtArgs.OldFullPath } else { $null }

    $debounceKey = "$($watcherObj.GetHashCode())|$kindWord|$path"
    if (Test-OtterWatchEventShouldCoalesce -Key $debounceKey) { return }

    if (-not $script:OtterWatcherHandlers.ContainsKey($watcherObj)) { return }
    $handlers = $script:OtterWatcherHandlers[$watcherObj] | Where-Object { $_.EventKind -eq $eventKind }
    if (-not $handlers) { return }

    $changeKindText = switch ($eventKind) {
        ([WatchEventKind]::Change) { 'changed' }
        ([WatchEventKind]::Create) { 'created' }
        ([WatchEventKind]::Delete) { 'deleted' }
        ([WatchEventKind]::Rename) { 'renamed' }
    }
    $previousContext = $script:OtterCurrentWatchEvent
    $script:OtterCurrentWatchEvent = @{
        Path = $path
        FileName = Split-Path -Leaf $path
        Kind = $changeKindText
        OldPath = $oldPath
    }
    try {
        # D104 section 24: handlers run one at a time, on this same
        # thread, through the ordinary interpreter - never concurrently,
        # never re-entering this loop mid-handler.
        foreach ($h in $handlers) {
            Invoke-OtterStatements -Statements $h.Body -Environment $h.Environment
        }
    } finally {
        $script:OtterCurrentWatchEvent = $previousContext
    }
}

function Invoke-OtterWebSocketEventLoopStep {
    $sockets = @($script:OtterActiveWebSockets)
    foreach ($ws in $sockets) {
        if ($ws.State -eq 'connecting') {
            if ($null -ne $ws.ConnectTask -and $ws.ConnectTask.IsCompleted) {
                if ($ws.ConnectTask.IsFaulted -or $ws.ConnectTask.IsCanceled) {
                    $ws.State = 'closed'
                    $errText = if ($null -ne $ws.ConnectTask.Exception) {
                        $ws.ConnectTask.Exception.GetBaseException().Message
                    } else {
                        "Failed to connect to $($ws.Url)"
                    }
                    $ws.LastError = $errText
                    $ws.CloseCode = 1006
                    $ws.CloseReason = $errText
                    $ws.CloseWasClean = $false
                    Invoke-OtterWebSocketHandlers -Socket $ws -EventKind ([WebSocketEventKind]::Error) -Context @{ Error = $errText }
                    Invoke-OtterWebSocketHandlers -Socket $ws -EventKind ([WebSocketEventKind]::Close) -Context @{ CloseCode = 1006; CloseReason = $errText; CloseWasClean = $false }
                } else {
                    $ws.State = 'open'
                    if (-not [string]::IsNullOrEmpty($ws.Native.SubProtocol)) {
                        $ws.Protocol = $ws.Native.SubProtocol
                    }
                    Invoke-OtterWebSocketHandlers -Socket $ws -EventKind ([WebSocketEventKind]::Open) -Context @{}
                }
            }
        }
        elseif ($ws.State -eq 'open') {
            if ($ws.Native.State -in @([System.Net.WebSockets.WebSocketState]::CloseReceived, [System.Net.WebSockets.WebSocketState]::Closed, [System.Net.WebSockets.WebSocketState]::Aborted)) {
                $ws.State = 'closed'
                $code = if ($null -ne $ws.Native.CloseStatus) { [int]$ws.Native.CloseStatus } else { 1000 }
                $reason = if ($null -ne $ws.Native.CloseStatusDescription) { [string]$ws.Native.CloseStatusDescription } else { '' }
                $clean = ($code -eq 1000)
                $ws.CloseCode = $code
                $ws.CloseReason = $reason
                $ws.CloseWasClean = $clean
                Invoke-OtterWebSocketHandlers -Socket $ws -EventKind ([WebSocketEventKind]::Close) -Context @{ CloseCode = $code; CloseReason = $reason; CloseWasClean = $clean }
                continue
            }

            if ($null -eq $ws.ReceiveTask) {
                $buf = [byte[]]::new(65536)
                $seg = [System.ArraySegment[byte]]::new($buf)
                $ws.ReceiveTask = @{ Task = $ws.Native.ReceiveAsync($seg, $ws.Cts.Token); Buffer = $buf }
            }

            if ($ws.ReceiveTask.Task.IsCompleted) {
                $task = $ws.ReceiveTask.Task
                $buf = $ws.ReceiveTask.Buffer
                $ws.ReceiveTask = $null

                if ($task.IsFaulted -or $task.IsCanceled) {
                    $ws.State = 'closed'
                    $errText = if ($null -ne $task.Exception) {
                        $task.Exception.GetBaseException().Message
                    } else {
                        "WebSocket connection ended unexpectedly"
                    }
                    $ws.LastError = $errText
                    $ws.CloseCode = 1006
                    $ws.CloseReason = $errText
                    $ws.CloseWasClean = $false
                    Invoke-OtterWebSocketHandlers -Socket $ws -EventKind ([WebSocketEventKind]::Error) -Context @{ Error = $errText }
                    Invoke-OtterWebSocketHandlers -Socket $ws -EventKind ([WebSocketEventKind]::Close) -Context @{ CloseCode = 1006; CloseReason = $errText; CloseWasClean = $false }
                } else {
                    $res = $task.Result
                    if ($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                        $ws.State = 'closed'
                        $ws.CloseCode = if ($null -ne $res.CloseStatus) { [int]$res.CloseStatus } else { 1000 }
                        $ws.CloseReason = if ($null -ne $res.CloseStatusDescription) { [string]$res.CloseStatusDescription } else { '' }
                        $ws.CloseWasClean = ($ws.CloseCode -eq 1000)
                        Invoke-OtterWebSocketHandlers -Socket $ws -EventKind ([WebSocketEventKind]::Close) -Context @{ CloseCode = $ws.CloseCode; CloseReason = $ws.CloseReason; CloseWasClean = $ws.CloseWasClean }
                    } else {
                        $ws.MessageBuffer.Write($buf, 0, $res.Count)
                        if ($null -eq $ws.MessageBufferType) { $ws.MessageBufferType = $res.MessageType }
                        if ($res.EndOfMessage) {
                            $msg = if ($ws.MessageBufferType -eq [System.Net.WebSockets.WebSocketMessageType]::Text) {
                                [System.Text.Encoding]::UTF8.GetString($ws.MessageBuffer.ToArray())
                            } else {
                                [OtterBytes]::new($ws.MessageBuffer.ToArray())
                            }
                            $ws.MessageBuffer.SetLength(0)
                            $ws.MessageBufferType = $null
                            Invoke-OtterWebSocketHandlers -Socket $ws -EventKind ([WebSocketEventKind]::Message) -Context @{ Message = $msg }
                        }
                    }
                }
            }
        }
        elseif ($ws.State -eq 'closing') {
            if ($ws.Native.State -in @([System.Net.WebSockets.WebSocketState]::Closed, [System.Net.WebSockets.WebSocketState]::Aborted, [System.Net.WebSockets.WebSocketState]::CloseReceived)) {
                $ws.State = 'closed'
                Invoke-OtterWebSocketHandlers -Socket $ws -EventKind ([WebSocketEventKind]::Close) -Context @{ CloseCode = $ws.CloseCode; CloseReason = $ws.CloseReason; CloseWasClean = $ws.CloseWasClean }
                continue
            }

            if ($null -eq $ws.ReceiveTask) {
                $buf = [byte[]]::new(4096)
                $seg = [System.ArraySegment[byte]]::new($buf)
                $ws.ReceiveTask = @{ Task = $ws.Native.ReceiveAsync($seg, $ws.Cts.Token); Buffer = $buf }
            }

            if ($ws.ReceiveTask.Task.IsCompleted) {
                $ws.ReceiveTask = $null
                $ws.State = 'closed'
                Invoke-OtterWebSocketHandlers -Socket $ws -EventKind ([WebSocketEventKind]::Close) -Context @{ CloseCode = $ws.CloseCode; CloseReason = $ws.CloseReason; CloseWasClean = $ws.CloseWasClean }
            }
        }
    }
}

# ===============================================================
# TCP / UDP (D107, D108) - console/desktop only
# ===============================================================
# Both ride the D106 handler table and event loop: OtterTcp/OtterUdp
# objects live in $script:OtterActiveNet, and Invoke-OtterNetEventLoopStep
# polls their pending .NET tasks (connect / read / receive) without ever
# blocking, then fires the same on-handlers a websocket would.

$script:OtterActiveNet = [System.Collections.Generic.List[object]]::new()
$script:OtterActiveTcpServers = [System.Collections.Generic.List[OtterTcpServer]]::new()
$script:OtterActiveHttpRequests = [System.Collections.Generic.List[OtterHttpRequest]]::new()
$script:OtterActiveCommandJobs = [System.Collections.Generic.List[OtterCommandJob]]::new()
$script:OtterCurrentJobContext = $null

function Stop-OtterTcpServerInternal {
    param([Parameter(Mandatory)][OtterTcpServer]$Server)
    if ($Server.Disposed -or $Server.State -eq 'stopped') { return }
    $Server.State = 'stopped'
    $Server.Disposed = $true
    try {
        $Server.Listener.Stop()
    } catch {}
}

function Close-OtterNetInternal {
    param([Parameter(Mandatory)][object]$Socket)
    if ($Socket.Disposed) { return }
    $Socket.Disposed = $true
    $Socket.State = 'closed'
    if ((Test-OtterTcp $Socket) -and $null -ne $Socket.Stream) { try { $Socket.Stream.Dispose() } catch {} }
    try { $Socket.Client.Close() } catch {}
}

function Test-OtterNetHasHandler {
    param([object]$Socket, [WebSocketEventKind]$EventKind)
    if (-not $script:OtterWebSocketHandlers.ContainsKey($Socket)) { return $false }
    foreach ($h in $script:OtterWebSocketHandlers[$Socket]) {
        if ($h.EventKind -eq $EventKind) { return $true }
    }
    return $false
}

# A network failure with an "on error of" handler is delivered to it; with
# none, it surfaces as a normal Otter runtime error - never silent.
function Send-OtterNetError {
    param([object]$Socket, [string]$Message)
    $Socket.LastError = $Message
    if (Test-OtterNetHasHandler -Socket $Socket -EventKind ([WebSocketEventKind]::Error)) {
        Invoke-OtterWebSocketHandlers -Socket $Socket -EventKind ([WebSocketEventKind]::Error) -Context @{ NetError = $Message }
    } else {
        throw (New-OtterRuntimeError -Message $Message -Line 0 -Suggestion 'Add "on error of <name>" to handle network errors.')
    }
}

function Step-OtterTcpServer {
    param([OtterTcpServer]$Server)
    if ($Server.State -ne 'listening') { return }
    try {
        if ($null -eq $Server.AcceptTask) {
            $Server.AcceptTask = $Server.Listener.AcceptTcpClientAsync()
        }
        if ($Server.AcceptTask.IsCompleted) {
            $task = $Server.AcceptTask
            $Server.AcceptTask = $null
            if ($Server.State -ne 'listening') { return }

            if ($task.IsFaulted -or $task.IsCanceled) {
                if ($Server.State -ne 'listening' -or $Server.Disposed) { return }
                $err = $task.Exception.GetBaseException()
                $msg = "The tcp server on port $($Server.BoundPort) failed: $($err.Message)"
                Send-OtterNetError -Socket $Server -Message $msg
            } else {
                $rawClient = $task.Result
                $remoteEp = $rawClient.Client.RemoteEndPoint -as [System.Net.IPEndPoint]
                $remoteHost = if ($null -ne $remoteEp) { $remoteEp.Address.ToString() } else { '' }
                $remotePort = if ($null -ne $remoteEp) { $remoteEp.Port } else { 0 }

                $clientTcp = [OtterTcp]::new($rawClient, $remoteHost, $remotePort)
                $clientTcp.State = 'connected'
                $clientTcp.Stream = $rawClient.GetStream()
                $clientTcp.ConnectFired = $true

                $script:OtterActiveNet.Add($clientTcp)

                Invoke-OtterWebSocketHandlers -Socket $Server -EventKind ([NetworkEventKind]::Connection) -Context @{
                    IncomingConnection = $clientTcp
                }
            }
        }
    } catch [OtterError] {
        throw
    } catch {
        if ($Server.State -eq 'listening') {
            $msg = "The tcp server on port $($Server.BoundPort) failed: $($_.Exception.GetBaseException().Message)"
            Send-OtterNetError -Socket $Server -Message $msg
        }
    }
}

function Step-OtterTcp {
    param([OtterTcp]$Tcp)
    if ($Tcp.State -eq 'connecting') {
        if ($null -ne $Tcp.ConnectTask -and $Tcp.ConnectTask.IsCompleted) {
            if ($Tcp.ConnectTask.IsFaulted -or $Tcp.ConnectTask.IsCanceled) {
                $msg = "Could not connect to tcp $($Tcp.RemoteHost) on port $($Tcp.RemotePort): $($Tcp.ConnectTask.Exception.GetBaseException().Message)"
                Close-OtterNetInternal -Socket $Tcp
                Send-OtterNetError -Socket $Tcp -Message $msg
            } elseif (-not $Tcp.IsSecure) {
                $Tcp.Stream = $Tcp.Client.GetStream()
                $Tcp.State = 'connected'
                Invoke-OtterWebSocketHandlers -Socket $Tcp -EventKind ([WebSocketEventKind]::Connect) -Context @{}
            } elseif ($null -eq $Tcp.HandshakeTask) {
                # D112: TCP is up; start the TLS handshake. The certificate
                # chain, expiry, revocation and host name (server name) are all
                # validated by the system - there is no way to turn that off.
                try {
                    $ssl = [System.Net.Security.SslStream]::new($Tcp.Client.GetStream(), $false)
                    $Tcp.Stream = $ssl
                    $Tcp.HandshakeTask = $ssl.AuthenticateAsClientAsync(
                        $Tcp.ServerName, $null, [System.Security.Authentication.SslProtocols]::None, $true)
                } catch {
                    $msg = "Could not start TLS with $($Tcp.RemoteHost): $($_.Exception.GetBaseException().Message)"
                    Close-OtterNetInternal -Socket $Tcp
                    Send-OtterNetError -Socket $Tcp -Message $msg
                }
            } elseif ($Tcp.HandshakeTask.IsCompleted) {
                if ($Tcp.HandshakeTask.IsFaulted -or $Tcp.HandshakeTask.IsCanceled) {
                    $msg = "The TLS handshake with $($Tcp.RemoteHost) failed: $($Tcp.HandshakeTask.Exception.GetBaseException().Message)"
                    Close-OtterNetInternal -Socket $Tcp
                    Send-OtterNetError -Socket $Tcp -Message $msg
                } else {
                    $Tcp.State = 'connected'
                    Invoke-OtterWebSocketHandlers -Socket $Tcp -EventKind ([WebSocketEventKind]::Connect) -Context @{}
                }
            }
        }
    }
    if ($Tcp.State -eq 'connected') {
        # Only read when something is listening for data - an unread
        # stream just buffers in the OS.
        if (-not (Test-OtterNetHasHandler -Socket $Tcp -EventKind ([WebSocketEventKind]::Data)) -and
            -not (Test-OtterNetHasHandler -Socket $Tcp -EventKind ([WebSocketEventKind]::Close))) { return }
        try {
            if ($null -eq $Tcp.ReadTask) {
                $Tcp.ReadTask = $Tcp.Stream.ReadAsync($Tcp.ReadBuffer, 0, $Tcp.ReadBuffer.Length)
            }
            elseif ($Tcp.ReadTask.IsCompleted) {
                $task = $Tcp.ReadTask
                $Tcp.ReadTask = $null
                if ($task.IsFaulted -or $task.IsCanceled) {
                    $msg = "The tcp connection to $($Tcp.RemoteHost) failed: $($task.Exception.GetBaseException().Message)"
                    Close-OtterNetInternal -Socket $Tcp
                    Send-OtterNetError -Socket $Tcp -Message $msg
                } elseif ($task.Result -eq 0) {
                    Close-OtterNetInternal -Socket $Tcp
                } else {
                    $chunk = [byte[]]::new($task.Result)
                    [System.Array]::Copy($Tcp.ReadBuffer, $chunk, $task.Result)
                    Invoke-OtterWebSocketHandlers -Socket $Tcp -EventKind ([WebSocketEventKind]::Data) -Context @{ Data = [OtterBytes]::new($chunk) }
                }
            }
        } catch [OtterError] {
            throw
        } catch {
            $msg = "The tcp connection to $($Tcp.RemoteHost) failed: $($_.Exception.GetBaseException().Message)"
            Close-OtterNetInternal -Socket $Tcp
            Send-OtterNetError -Socket $Tcp -Message $msg
        }
    }
    if ($Tcp.State -eq 'closed' -and -not $Tcp.CloseFired) {
        $Tcp.CloseFired = $true
        Invoke-OtterWebSocketHandlers -Socket $Tcp -EventKind ([WebSocketEventKind]::Close) -Context @{}
    }
}

function Step-OtterUdp {
    param([OtterUdp]$Udp)
    if ($Udp.State -eq 'open') {
        if (-not (Test-OtterNetHasHandler -Socket $Udp -EventKind ([WebSocketEventKind]::Data))) { return }
        try {
            if ($null -eq $Udp.ReceiveTask) {
                $Udp.ReceiveTask = $Udp.Client.ReceiveAsync()
            }
            elseif ($Udp.ReceiveTask.IsCompleted) {
                $task = $Udp.ReceiveTask
                $Udp.ReceiveTask = $null
                if ($task.IsFaulted -or $task.IsCanceled) {
                    $inner = $task.Exception.GetBaseException()
                    # Windows reports an ICMP "port unreachable" from an earlier
                    # send as a connection-reset on the NEXT receive. That is not
                    # a socket failure - keep listening.
                    if (-not ($inner -is [System.Net.Sockets.SocketException] -and $inner.SocketErrorCode -eq [System.Net.Sockets.SocketError]::ConnectionReset)) {
                        Send-OtterNetError -Socket $Udp -Message "The udp socket failed: $($inner.Message)"
                    }
                } else {
                    $result = $task.Result
                    Invoke-OtterWebSocketHandlers -Socket $Udp -EventKind ([WebSocketEventKind]::Data) -Context @{
                        Data = [OtterBytes]::new([byte[]]$result.Buffer)
                        SenderAddress = $result.RemoteEndPoint.Address.ToString()
                        SenderPort = [double]$result.RemoteEndPoint.Port
                    }
                }
            }
        } catch [OtterError] {
            throw
        } catch {
            Send-OtterNetError -Socket $Udp -Message "The udp socket failed: $($_.Exception.GetBaseException().Message)"
        }
    }
    if ($Udp.State -eq 'closed' -and -not $Udp.CloseFired) {
        $Udp.CloseFired = $true
        Invoke-OtterWebSocketHandlers -Socket $Udp -EventKind ([WebSocketEventKind]::Close) -Context @{}
    }
}

function Invoke-OtterNetEventLoopStep {
    foreach ($srv in @($script:OtterActiveTcpServers)) {
        Step-OtterTcpServer -Server $srv
    }
    foreach ($n in @($script:OtterActiveNet)) {
        if (Test-OtterTcp $n) { Step-OtterTcp -Tcp $n } else { Step-OtterUdp -Udp $n }
    }
}

# True while some net object could still produce an event a handler cares about.
function Test-OtterNetActive {
    foreach ($srv in $script:OtterActiveTcpServers) {
        if ($srv.State -eq 'listening') {
            if ($script:OtterWebSocketHandlers.ContainsKey($srv) -and $script:OtterWebSocketHandlers[$srv].Count -gt 0) {
                return $true
            }
        }
    }
    foreach ($n in $script:OtterActiveNet) {
        if (-not $script:OtterWebSocketHandlers.ContainsKey($n)) { continue }
        if ($script:OtterWebSocketHandlers[$n].Count -eq 0) { continue }
        if ($n.State -ne 'closed' -or -not $n.CloseFired) { return $true }
    }
    return $false
}

# D116B: Step active HTTP requests
function Invoke-OtterHttpEventLoopStep {
    $requests = @($script:OtterActiveHttpRequests)
    foreach ($req in $requests) {
        if ($req.State -ne 'pending') {
            continue
        }
        if ($null -eq $req.Task -or -not $req.Task.IsCompleted) {
            if ($null -ne $req.TimeoutSeconds -and $req.Cts.IsCancellationRequested -and -not $req.IsTimeout) {
                $req.IsTimeout = $true
            } else {
                continue
            }
        }

        if ($req.State -eq 'cancelled') {
            continue
        }

        if ($req.IsTimeout -or ($null -ne $req.TimeoutSeconds -and $req.Cts.IsCancellationRequested)) {
            $req.State = 'failed'
            $errText = "The HTTP request timed out after $($req.TimeoutSeconds) seconds."
            $req.Error = $errText
            $context = @{ Error = $errText; NetError = $errText }
            $req.RetainedTerminalEvent = @{ EventKind = [NetworkEventKind]::Error; Context = $context }
            Invoke-OtterWebSocketHandlers -Socket $req -EventKind ([NetworkEventKind]::Error) -Context $context
            try { $req.Cts.Dispose() } catch {}
            $req.Disposed = $true
            continue
        }

        if ($req.Task.IsFaulted) {
            $req.State = 'failed'
            $baseEx = if ($null -ne $req.Task.Exception) { $req.Task.Exception.GetBaseException() } else { $null }
            $errText = if ($null -ne $baseEx) { $baseEx.Message } else { "Failed to send HTTP request to $($req.Url)" }
            $req.Error = $errText
            $context = @{ Error = $errText; NetError = $errText }
            $req.RetainedTerminalEvent = @{ EventKind = [NetworkEventKind]::Error; Context = $context }
            Invoke-OtterWebSocketHandlers -Socket $req -EventKind ([NetworkEventKind]::Error) -Context $context
            try { $req.Cts.Dispose() } catch {}
            $req.Disposed = $true
            continue
        }

        if ($req.Task.IsCanceled) {
            $req.State = 'cancelled'
            $context = @{}
            $req.RetainedTerminalEvent = @{ EventKind = [NetworkEventKind]::Cancel; Context = $context }
            Invoke-OtterWebSocketHandlers -Socket $req -EventKind ([NetworkEventKind]::Cancel) -Context $context
            try { $req.Cts.Dispose() } catch {}
            $req.Disposed = $true
            continue
        }

        $httpResponse = $req.Task.Result
        $req.Status = [int]$httpResponse.StatusCode
        $bodyText = $httpResponse.Content.ReadAsStringAsync().Result

        if ($req.AsJson) {
            try {
                $parsed = ConvertFrom-OtterJsonText -Text $bodyText -Line 0
                $req.Response = $parsed
                $req.State = 'completed'
                $context = @{ Response = $req.Response }
                $req.RetainedTerminalEvent = @{ EventKind = [NetworkEventKind]::Complete; Context = $context }
                Invoke-OtterWebSocketHandlers -Socket $req -EventKind ([NetworkEventKind]::Complete) -Context $context
            } catch {
                $req.State = 'failed'
                $errText = "Failed to parse HTTP response as JSON: $($_.Exception.Message)"
                $req.Error = $errText
                $context = @{ Error = $errText; NetError = $errText }
                $req.RetainedTerminalEvent = @{ EventKind = [NetworkEventKind]::Error; Context = $context }
                Invoke-OtterWebSocketHandlers -Socket $req -EventKind ([NetworkEventKind]::Error) -Context $context
            }
        } else {
            $req.Response = $bodyText
            $req.State = 'completed'
            $context = @{ Response = $req.Response }
            $req.RetainedTerminalEvent = @{ EventKind = [NetworkEventKind]::Complete; Context = $context }
            Invoke-OtterWebSocketHandlers -Socket $req -EventKind ([NetworkEventKind]::Complete) -Context $context
        }

        try { $httpResponse.Dispose() } catch {}
        if (-not $req.Disposed) {
            try { $req.Cts.Dispose() } catch {}
            $req.Disposed = $true
        }
    }
}

# D116B: True while an HTTP request is pending and has registered handlers
function Test-OtterHttpActive {
    foreach ($req in $script:OtterActiveHttpRequests) {
        if ($req.State -eq 'pending') {
            if ($script:OtterWebSocketHandlers.ContainsKey($req) -and $script:OtterWebSocketHandlers[$req].Count -gt 0) {
                return $true
            }
        }
    }
    return $false
}

# D119-R2: True while a command job is running or has unhandled events
function Test-OtterJobsActive {
    foreach ($job in $script:OtterActiveCommandJobs) {
        if ($null -ne $job.Tracker -and $job.Tracker.Queue.Count -gt 0) {
            return $true
        }
        if ($job.EventQueue.Count -gt 0) {
            return $true
        }
        if ($job.State -eq 'running' -and $job.Handlers.Count -gt 0) {
            return $true
        }
    }
    return $false
}

function Invoke-OtterJobEventLoopStep {
    foreach ($job in @($script:OtterActiveCommandJobs)) {
        if ($null -ne $job.Tracker) {
            $item = $null
            while ($job.Tracker.Queue.TryDequeue([ref]$item)) {
                $evtKind = $item.Kind
                $ctx = @{}
                if ($evtKind -eq 'output') {
                    $ctx = @{ Output = $item.Data }
                } elseif ($evtKind -eq 'error output') {
                    $ctx = @{ ErrorOutput = $item.Data }
                } elseif ($evtKind -eq 'exit' -or $evtKind -eq 'complete') {
                    $ec = [double]$item.ExitCode
                    $ctx = @{ ExitCode = $ec }
                    [System.Threading.Monitor]::Enter($job.LockObj)
                    try {
                        if ($job.State -ne 'cancelled') {
                            $job.ExitCode = $ec
                            if ($ec -eq 0) {
                                $job.State = 'completed'
                            } else {
                                $job.State = 'failed'
                            }
                        }
                    } finally {
                        [System.Threading.Monitor]::Exit($job.LockObj)
                    }
                    if ($evtKind -eq 'exit') {
                        $job.RetainedTerminalEvent = @{ EventKind = 'exit'; Context = $ctx }
                    }
                }

                $matching = $null
                [System.Threading.Monitor]::Enter($job.LockObj)
                try {
                    $matching = @($job.Handlers | Where-Object { $_.EventName -eq $evtKind })
                } finally {
                    [System.Threading.Monitor]::Exit($job.LockObj)
                }

                if ($null -ne $matching -and $matching.Count -gt 0) {
                    foreach ($h in $matching) {
                        if ($evtKind -in @('exit', 'complete', 'cancel')) {
                            if ($h.ContainsKey('Fired') -and $h.Fired) { continue }
                            $h.Fired = $true
                        }
                        $prevContext = $script:OtterCurrentJobContext
                        $script:OtterCurrentJobContext = $ctx
                        try {
                            Invoke-OtterStatements -Statements $h.Body -Environment $h.Environment
                        } finally {
                            $script:OtterCurrentJobContext = $prevContext
                        }
                    }
                }
            }
        }

        $evt = $null
        while ($job.EventQueue.TryDequeue([ref]$evt)) {
            $eventKind = $evt.EventKind
            $context = $evt.Context
            $matching = $null
            [System.Threading.Monitor]::Enter($job.LockObj)
            try {
                $matching = @($job.Handlers | Where-Object { $_.EventName -eq $eventKind })
            } finally {
                [System.Threading.Monitor]::Exit($job.LockObj)
            }
            if ($null -ne $matching -and $matching.Count -gt 0) {
                foreach ($h in $matching) {
                    if ($eventKind -in @('exit', 'complete', 'cancel')) {
                        if ($h.ContainsKey('Fired') -and $h.Fired) { continue }
                        $h.Fired = $true
                    }
                    $prevContext = $script:OtterCurrentJobContext
                    $script:OtterCurrentJobContext = $context
                    try {
                        Invoke-OtterStatements -Statements $h.Body -Environment $h.Environment
                    } finally {
                        $script:OtterCurrentJobContext = $prevContext
                    }
                }
            }
        }
    }
}

function Invoke-OtterEventLoop {
    while ($true) {
        $hasWatchers = ($script:OtterActiveWatchers.Count -gt 0)
        $hasSockets = $false
        foreach ($ws in $script:OtterActiveWebSockets) {
            if ($ws.State -in @('connecting', 'open', 'closing')) {
                if ($script:OtterWebSocketHandlers.ContainsKey($ws) -and $script:OtterWebSocketHandlers[$ws].Count -gt 0) {
                    $hasSockets = $true
                    break
                }
            }
        }

        $hasNet = Test-OtterNetActive
        if ($hasNet) { $hasSockets = $true }

        $hasHttp = Test-OtterHttpActive
        if ($hasHttp) { $hasSockets = $true }

        $hasJobs = Test-OtterJobsActive
        if ($hasJobs) { $hasSockets = $true }

        if (-not $hasWatchers -and -not $hasSockets) {
            break
        }

        if ($hasWatchers) {
            $watchTimeout = if ($hasSockets) { 0.02 } else { 0.5 }
            Invoke-OtterWatchEventLoopStep -Timeout $watchTimeout
        } elseif ($hasSockets) {
            Start-Sleep -Milliseconds 10
        }

        if ($hasSockets) {
            Invoke-OtterWebSocketEventLoopStep
            Invoke-OtterNetEventLoopStep
            Invoke-OtterHttpEventLoopStep
            Invoke-OtterJobEventLoopStep
        }
    }
}

function Invoke-OtterWatchEventLoop {
    Invoke-OtterEventLoop
}

# ===============================================================
# XML (D105) - console AND web both supported. A document-shaped
# OtterXml wraps a real [System.Xml.XmlDocument]; anything selected out
# of one (root of/element .../child ...) wraps the [System.Xml.XmlElement]
# it found. Both derive from XmlNode, so every helper below works on
# either uniformly - Assert-OtterXmlElement is the one place that draws
# the line, for the handful of operations (attributes, adding/removing a
# child, setting text) that genuinely need a real element, not a document.
# ===============================================================

# element/elements/child/children only ever search DIRECT children -
# never recursively - keeping "elements 'book' in document" predictable
# (it means the book elements immediately under the root, not anywhere
# in the whole tree). A document's search root is its DocumentElement,
# so `element "book" in document` still works without the caller first
# reaching for `root of document` themselves.
function Get-OtterXmlSearchRoot {
    param([System.Xml.XmlNode]$Node)
    if ($Node -is [System.Xml.XmlDocument]) { return $Node.DocumentElement }
    return $Node
}

function Get-OtterXmlChildElements {
    param([System.Xml.XmlNode]$Node)
    $root = Get-OtterXmlSearchRoot -Node $Node
    $matches = [System.Collections.Generic.List[System.Xml.XmlElement]]::new()
    if ($null -ne $root) {
        foreach ($child in $root.ChildNodes) {
            if ($child -is [System.Xml.XmlElement]) { $matches.Add($child) }
        }
    }
    # -NoEnumerate matters even for a plain array return: PowerShell
    # unwraps a SINGLE-item array/pipeline result back into a bare
    # scalar on return (confirmed directly - a one-element `return @(x)`
    # arrived at the caller as `x` itself, not `@(x)`, making
    # `$found.Count` silently $null instead of 1 and corrupting every
    # caller downstream of it).
    Write-Output -NoEnumerate $matches
}

function Find-OtterXmlChildElementsByName {
    param([System.Xml.XmlNode]$Node, [string]$Name)
    $all = Get-OtterXmlChildElements -Node $Node
    $matches = [System.Collections.Generic.List[System.Xml.XmlElement]]::new()
    foreach ($e in $all) {
        if ($e.Name -eq $Name) { $matches.Add($e) }
    }
    Write-Output -NoEnumerate $matches
}

function Assert-OtterXmlElement {
    param([OtterXml]$Xml, [int]$Line, [string]$What)
    if ($Xml.Node -isnot [System.Xml.XmlElement]) {
        throw (New-OtterRuntimeError `
            -Message "I can only $What on an xml element, but this is an xml document. Use ""root of ...`" or `"element ... in ...`" to get an element first." `
            -Line $Line)
    }
}

function New-OtterXmlRuntimeError {
    param([string]$Text, [int]$Line)
    throw (New-OtterRuntimeError `
        -Message "This is not valid XML, so Otter could not read it: $Text" `
        -Line $Line)
}

function Write-OtterLine {
    param([string]$Text)
    Complete-OtterProgressBarLine
    if ($null -ne $script:OutputWriter) {
        & $script:OutputWriter $Text
        return
    }
    Write-Host $Text
}

# D100: say "..." in color "red". Console/interpreter target only - the
# color itself never changes what a test observes as the printed TEXT
# (a test harness's $script:OutputWriter still gets exactly the same
# string it always did), only the real console's foreground color when
# there is no custom writer installed.
$script:OtterConsoleColorNames = @(
    'red', 'green', 'yellow', 'blue', 'cyan', 'magenta', 'white', 'black',
    'gray', 'darkgray', 'darkred', 'darkgreen', 'darkyellow', 'darkblue',
    'darkcyan', 'darkmagenta'
)

function Get-OtterConsoleColor {
    param([string]$Name, [int]$Line)

    $normalized = $Name.Trim().ToLowerInvariant()
    if ($script:OtterConsoleColorNames -notcontains $normalized) {
        throw (New-OtterRuntimeError `
            -Message "I don't recognize the color `"$Name`". Valid colors are: $($script:OtterConsoleColorNames -join ', ')." `
            -Line $Line `
            -Suggestion 'say "Error!" in color "red"')
    }
    return [System.ConsoleColor]$normalized
}

function Write-OtterColoredLine {
    param([string]$Text, [string]$ColorName, [int]$Line)

    Complete-OtterProgressBarLine
    if ($null -ne $script:OutputWriter) {
        & $script:OutputWriter $Text
        return
    }
    $resolved = Get-OtterConsoleColor -Name $ColorName -Line $Line
    Write-Host $Text -ForegroundColor $resolved
}

# D100: ask secretly "..." and call it x. Reads one line character-by-
# character, masking each typed character with "*" instead of echoing it,
# terminating on Enter (Backspace removes the last character). Falls back
# to a plain Read-Host (unmasked, but still fully functional) when the
# console does not support raw key reading at all - a redirected/piped
# stdin, which [Console]::ReadKey throws on. That fallback is what lets
# this statement still be exercised under this project's own piped-stdin
# test automation, even though it cannot verify real masking that way.
function Read-OtterSecretLine {
    $buffer = [System.Text.StringBuilder]::new()
    try {
        while ($true) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Enter) {
                Write-Host ''
                break
            }
            if ($key.Key -eq [ConsoleKey]::Backspace) {
                if ($buffer.Length -gt 0) {
                    [void]$buffer.Remove($buffer.Length - 1, 1)
                    Write-Host "`b `b" -NoNewline
                }
                continue
            }
            if ($key.KeyChar -and -not [char]::IsControl($key.KeyChar)) {
                [void]$buffer.Append($key.KeyChar)
                Write-Host '*' -NoNewline
            }
        }
        return $buffer.ToString()
    } catch {
        return Read-Host
    }
}

# D31: log / warn / error are DIAGNOSTIC output and go somewhere separate
# from "say". "say" is what a program tells its user; these are what it tells
# whoever is running it. Keeping them apart is what lets a runtime send
# diagnostics to a file, a service, or nowhere at all.
$script:DiagnosticWriter = $null

function Set-OtterDiagnosticWriter {
    param([scriptblock]$Writer)
    $script:DiagnosticWriter = $Writer
}

function Write-OtterDiagnostic {
    param([string]$Level, [string]$Text)

    Complete-OtterProgressBarLine
    if ($null -ne $script:DiagnosticWriter) {
        & $script:DiagnosticWriter $Level $Text
        return
    }

    $colour = switch ($Level) {
        'warn' { 'Yellow' }
        'error' { 'Red' }
        default { 'DarkGray' }
    }
    Write-Host "$($Level): $Text" -ForegroundColor $colour
}


# ===============================================================
# ERRORS
# ===============================================================

function New-OtterRuntimeError {
    param(
        [string]$Message,
        [int]$Line,
        [string]$Suggestion = $null
    )

    $sourceLine = $null
    if ($script:SourceLines -and $Line -ge 1 -and $Line -le $script:SourceLines.Count) {
        $sourceLine = $script:SourceLines[$Line - 1]
    }

    return [OtterError]::new($Message, $Line, 'runtime', 0, $sourceLine, $Suggestion)
}

# "I need a number here" is the single most common runtime complaint, so it
# gets one consistent, friendly phrasing.
function Assert-OtterNumber {
    param([object]$Value, [int]$Line, [string]$What)

    if (Test-OtterNumeric $Value) { return (ConvertTo-OtterNumber $Value) }

    $shown = Format-OtterValue -Value $Value
    if ($Value -is [string]) { $shown = '"' + $Value + '"' }

    throw (New-OtterRuntimeError -Message "I expected a number for $What but got $shown." -Line $Line)
}

# D41: dynamic get/set are restricted to TypeName 'thing'. The probe that
# motivated this found the reason directly - WriteProperty does not
# distinguish thing from file from folder, so without this guard
# `set "size" to 999999 in file` would silently corrupt a file object's
# own bookkeeping. has (D40) and JSON (D29) are both always 'thing',
# so this costs the intended use of the feature nothing.
function Assert-OtterDynamicKeyTarget {
    param([object]$Value, [int]$Line, [string]$Verb)

    if (-not (Test-OtterObject $Value)) {
        throw (New-OtterRuntimeError `
            -Message "I can only $Verb a thing, but this is $(Get-OtterTypeName $Value)." `
            -Line $Line)
    }
    if ($Value.TypeName -ne 'thing') {
        throw (New-OtterRuntimeError `
            -Message "I can only $Verb properties dynamically on a thing, but this is a $($Value.TypeName)." `
            -Line $Line)
    }
    return $Value
}

# D41: string-only keys for 0.1, on purpose - accepting any value would
# mean quietly inventing coercion rules for numbers, dates, booleans, and
# gone, which is exactly the kind of decision this project makes on
# purpose rather than by accident.
function Assert-OtterStringKey {
    param([object]$Value, [int]$Line)

    if ($Value -is [string]) { return $Value }

    throw (New-OtterRuntimeError `
        -Message "I need text for a dynamic key, but this is $(Get-OtterTypeName $Value)." `
        -Line $Line `
        -Suggestion 'get "Jeff" from scores into score')
}


# ===============================================================
# ENTRY POINT
# ===============================================================

function Invoke-OtterProgram {
    param(
        [Parameter(Mandatory)][ProgramNode]$Program,
        [Parameter(Mandatory)][OtterEnvironment]$Environment,
        [string[]]$SourceLines = @()
    )

    $script:SourceLines = $SourceLines
    $script:GlobalEnvironment = $Environment
    $script:CallStack.Clear()

    # D104: reset per-run watcher state - a REPL session reusing this
    # module across separate program runs must never see a watcher (or
    # its handlers) left over from an earlier run.
    $script:OtterActiveWatchers = [System.Collections.Generic.List[OtterFileWatcher]]::new()
    $script:OtterWatcherHandlers = [System.Collections.Generic.Dictionary[object, System.Collections.Generic.List[hashtable]]]::new()
    $script:OtterCurrentWatchEvent = $null
    $script:OtterWatchLastEventAt = @{}

    # D106: reset per-run websocket state
    $script:OtterActiveWebSockets = [System.Collections.Generic.List[OtterWebSocket]]::new()
    $script:OtterWebSocketHandlers = [System.Collections.Generic.Dictionary[object, System.Collections.Generic.List[hashtable]]]::new()
    $script:OtterCurrentWsContext = $null
    $script:OtterActiveNet = [System.Collections.Generic.List[object]]::new()
    $script:OtterActiveTcpServers = [System.Collections.Generic.List[OtterTcpServer]]::new()
    $script:OtterActiveHttpRequests = [System.Collections.Generic.List[OtterHttpRequest]]::new()
    $script:OtterActiveCommandJobs = [System.Collections.Generic.List[OtterCommandJob]]::new()
    $script:OtterCurrentJobContext = $null

    try {
        Invoke-OtterStatements -Statements $Program.Statements -Environment $Environment
        # D104 & D106: unified event loop for file watchers and active websockets
        Invoke-OtterEventLoop
    }
    catch {
        # D37: "stop" (and a hypothetical top-level "return") both throw an
        # OtterReturnSignal. Invoke-OtterCall is the only thing that ever
        # catches that signal, and it only exists while a function call is
        # running - so one reaching all the way up here means it was used
        # outside anything callable. Without this catch it would unwind past
        # this function entirely and get reported as "a bug in Otter",
        # which is wrong: nothing broke, the program just used "stop" where
        # there was nothing to stop.
        if ($_.Exception -is [OtterReturnSignal]) {
            throw (New-OtterRuntimeError `
                -Message 'stop only works inside something Otter can call, like a function. There is nothing here to stop.' `
                -Line $_.Exception.Line)
        }
        throw
    }
    finally {
        foreach ($w in @($script:OtterActiveWatchers)) { Stop-OtterFileWatcherInternal -Watcher $w }
        foreach ($ws in @($script:OtterActiveWebSockets)) { Close-OtterWebSocketInternal -Socket $ws }
        foreach ($net in @($script:OtterActiveNet)) { Close-OtterNetInternal -Socket $net }
        foreach ($srv in @($script:OtterActiveTcpServers)) { Stop-OtterTcpServerInternal -Server $srv }
        foreach ($req in @($script:OtterActiveHttpRequests)) {
            if ($req.State -eq 'pending') {
                try { $req.State = 'cancelled'; $req.Cts.Cancel() } catch {}
            }
            if (-not $req.Disposed) {
                try { $req.Cts.Dispose() } catch {}
                $req.Disposed = $true
            }
        }
        foreach ($job in @($script:OtterActiveCommandJobs)) {
            if ($job.State -eq 'running') {
                try { Stop-OtterCommandJob -Job $job } catch {}
            }
        }
    }
}

function Invoke-OtterStatements {
    param([Node[]]$Statements, [OtterEnvironment]$Environment)

    if ($null -eq $Statements) { return }
    foreach ($statement in $Statements) {
        Invoke-OtterStatement -Statement $statement -Environment $Environment
    }
}


# ===============================================================
# D99: OTTER QUERY LANGUAGE (OQL) SQL CONVERSION
# ===============================================================

function New-OtterQueryParamName {
    param([int[]]$ParamIndex)
    $curr = $ParamIndex[0]
    $ParamIndex[0] = $curr + 1
    return "p$curr"
}

function ConvertTo-OtterQuerySqlExpression {
    param(
        [Parameter(Mandatory)][Node]$Node,
        [Parameter(Mandatory)][OtterEnvironment]$Environment,
        [Parameter(Mandatory)][hashtable]$Parameters,
        [Parameter(Mandatory)][int[]]$ParamIndex,
        [switch]$IsWhereClause
    )

    if ($Node -is [VariableExpr]) {
        if ($Node.Name -eq '*') { return '*' }
        return "[$($Node.Name)]"
    }

    if ($Node -is [PropertyAccessExpr]) {
        $targetName = if ($Node.Target -is [VariableExpr]) { $Node.Target.Name } else { 'col' }
        return "[$targetName].[$($Node.Property)]"
    }

    if ($Node -is [LiteralExpr]) {
        $pName = New-OtterQueryParamName $ParamIndex
        $val = $Node.Value
        if ($null -eq $val) {
            $Parameters[$pName] = [System.DBNull]::Value
        } else {
            $Parameters[$pName] = $val
        }
        return "@$pName"
    }

    if ($Node -is [QueryBetweenExpr]) {
        $colSql = ConvertTo-OtterQuerySqlExpression -Node $Node.Expression -Environment $Environment -Parameters $Parameters -ParamIndex $ParamIndex
        $lowVal = Get-OtterValue -Expression $Node.Lower -Environment $Environment
        $highVal = Get-OtterValue -Expression $Node.Upper -Environment $Environment
        $pLow = New-OtterQueryParamName $ParamIndex
        $pHigh = New-OtterQueryParamName $ParamIndex
        $Parameters[$pLow] = if ($null -eq $lowVal) { [System.DBNull]::Value } else { $lowVal }
        $Parameters[$pHigh] = if ($null -eq $highVal) { [System.DBNull]::Value } else { $highVal }
        return "($colSql BETWEEN @$pLow AND @$pHigh)"
    }

    if ($Node -is [QueryInExpr]) {
        $colSql = ConvertTo-OtterQuerySqlExpression -Node $Node.Expression -Environment $Environment -Parameters $Parameters -ParamIndex $ParamIndex
        $itemsVal = Get-OtterValue -Expression $Node.Collection -Environment $Environment
        $itemsList = [System.Collections.Generic.List[object]]::new()
        if ($itemsVal -is [System.Collections.IEnumerable] -and $itemsVal -isnot [string]) {
            foreach ($it in $itemsVal) { $itemsList.Add($it) }
        } elseif ($null -ne $itemsVal) {
            $itemsList.Add($itemsVal)
        }

        if ($itemsList.Count -eq 0) {
            if ($Node.IsNot) { return '(1 = 1)' } else { return '(1 = 0)' }
        }

        $paramNames = [System.Collections.Generic.List[string]]::new()
        foreach ($it in $itemsList) {
            $pName = New-OtterQueryParamName $ParamIndex
            $Parameters[$pName] = if ($null -eq $it) { [System.DBNull]::Value } else { $it }
            $paramNames.Add("@$pName")
        }
        $inListSql = $paramNames -join ', '
        $opSql = if ($Node.IsNot) { 'NOT IN' } else { 'IN' }
        return "($colSql $opSql ($inListSql))"
    }

    if ($Node -is [TextMatchExpr]) {
        $colSql = ConvertTo-OtterQuerySqlExpression -Node $Node.Subject -Environment $Environment -Parameters $Parameters -ParamIndex $ParamIndex
        $patternVal = Get-OtterValue -Expression $Node.Value -Environment $Environment
        $patternStr = if ($null -ne $patternVal) { [string]$patternVal } else { '' }
        $sqlPattern = if ($Node.Match -eq [TextMatch]::StartsWith) { "$patternStr%" } else { "%$patternStr" }
        $pName = New-OtterQueryParamName $ParamIndex
        $Parameters[$pName] = $sqlPattern
        return "($colSql LIKE @$pName)"
    }

    if ($Node -is [ContainsExpr]) {
        $colSql = ConvertTo-OtterQuerySqlExpression -Node $Node.Collection -Environment $Environment -Parameters $Parameters -ParamIndex $ParamIndex
        $patternVal = Get-OtterValue -Expression $Node.Item -Environment $Environment
        $patternStr = if ($null -ne $patternVal) { [string]$patternVal } else { '' }
        $pName = New-OtterQueryParamName $ParamIndex
        $Parameters[$pName] = "%$patternStr%"
        return "($colSql LIKE @$pName)"
    }

    if ($Node -is [ComparisonExpr]) {
        $colSql = ConvertTo-OtterQuerySqlExpression -Node $Node.Left -Environment $Environment -Parameters $Parameters -ParamIndex $ParamIndex
        $rightVal = Get-OtterValue -Expression $Node.Right -Environment $Environment
        
        if ($null -eq $rightVal) {
            if ($Node.Op -eq [CompareOp]::Equal) {
                return "($colSql IS NULL)"
            } elseif ($Node.Op -eq [CompareOp]::NotEqual) {
                return "($colSql IS NOT NULL)"
            }
        }

        $pName = New-OtterQueryParamName $ParamIndex
        $Parameters[$pName] = if ($null -eq $rightVal) { [System.DBNull]::Value } else { $rightVal }

        $opSql = switch ($Node.Op) {
            ([CompareOp]::Equal) { '=' }
            ([CompareOp]::NotEqual) { '<>' }
            ([CompareOp]::GreaterThan) { '>' }
            ([CompareOp]::AtLeast) { '>=' }
            ([CompareOp]::LessThan) { '<' }
            ([CompareOp]::AtMost) { '<=' }
            default { '=' }
        }
        return "($colSql $opSql @$pName)"
    }

    if ($Node -is [LogicalExpr]) {
        $leftSql = ConvertTo-OtterQuerySqlExpression -Node $Node.Left -Environment $Environment -Parameters $Parameters -ParamIndex $ParamIndex -IsWhereClause
        $rightSql = ConvertTo-OtterQuerySqlExpression -Node $Node.Right -Environment $Environment -Parameters $Parameters -ParamIndex $ParamIndex -IsWhereClause
        $opSql = if ($Node.Op -eq [LogicalOp]::Or) { 'OR' } else { 'AND' }
        return "($leftSql $opSql $rightSql)"
    }

    if ($Node -is [NotExpr]) {
        $innerSql = ConvertTo-OtterQuerySqlExpression -Node $Node.Operand -Environment $Environment -Parameters $Parameters -ParamIndex $ParamIndex -IsWhereClause
        return "(NOT $innerSql)"
    }

    $val = Get-OtterValue -Expression $Node -Environment $Environment
    $pName = New-OtterQueryParamName $ParamIndex
    $Parameters[$pName] = if ($null -eq $val) { [System.DBNull]::Value } else { $val }
    return "@$pName"
}

function Get-OtterHttpOptionsArguments {
    param([HttpOptions]$Options, [OtterEnvironment]$Environment)

    $headers = [System.Collections.Generic.List[object]]::new()
    $withCookies = $null
    $followRedirects = $null
    $timeoutSec = $null

    if ($null -ne $Options) {
        if ($null -ne $Options.Headers) {
            foreach ($h in $Options.Headers) {
                $name = Get-OtterText -Expression $h.Name -Environment $Environment
                $value = Get-OtterText -Expression $h.Value -Environment $Environment
                $headers.Add([pscustomobject]@{ Name = $name; Value = $value })
            }
        }
        $withCookies = $Options.WithCookies
        $followRedirects = $Options.FollowRedirects
        if ($null -ne $Options.TimeoutSeconds) {
            $timeoutSec = Get-OtterValue -Expression $Options.TimeoutSeconds -Environment $Environment
        }
    }

    return [pscustomobject]@{
        Headers = $headers.ToArray()
        WithCookies = $withCookies
        FollowRedirects = $followRedirects
        TimeoutSeconds = $timeoutSec
    }
}

# ===============================================================
# STATEMENTS
# ===============================================================

function Invoke-OtterStatement {
    param([Node]$Statement, [OtterEnvironment]$Environment)

    if ($null -ne $script:StatementHook) {
        & $script:StatementHook -Statement $Statement -Environment $Environment -CallStack $script:CallStack
    }

    switch ($Statement.Kind.ToString()) {

        # say "Hello" name        (D8: parts joined by exactly one space)
        # say "Error!" in color "red"                                  (D100)
        'Say' {
            if ($Statement.Parts.Count -eq 0) {
                if ($null -ne $Statement.ColorExpr) {
                    Write-OtterColoredLine -Text '' -ColorName (Format-OtterValue -Value (Get-OtterValue -Expression $Statement.ColorExpr -Environment $Environment)) -Line $Statement.Line
                } else {
                    Write-OtterLine -Text ''
                }
                return
            }
            $rendered = @()
            foreach ($part in $Statement.Parts) {
                $value = Get-OtterValue -Expression $part -Environment $Environment
                $rendered += (Format-OtterValue -Value $value)
            }
            $text = $rendered -join ' '
            if ($null -ne $Statement.ColorExpr) {
                $colorValue = Get-OtterValue -Expression $Statement.ColorExpr -Environment $Environment
                if ($colorValue -isnot [string]) {
                    throw (New-OtterRuntimeError `
                        -Message "I need text for a color name, but this is $(Get-OtterTypeName $colorValue)." `
                        -Line $Statement.Line `
                        -Suggestion 'say "Error!" in color "red"')
                }
                Write-OtterColoredLine -Text $text -ColorName $colorValue -Line $Statement.Line
            } else {
                Write-OtterLine -Text $text
            }
            return
        }

        # name is "Jeff"              target is a VariableExpr
        # age of person is 30         target is a PropertyAccessExpr
        'Assign' {
            $value = Get-OtterValue -Expression $Statement.Value -Environment $Environment
            Set-OtterTarget -Target $Statement.Target -Value $value -Environment $Environment
            return
        }

        # person is a thing
        #     name is "Jeff"
        # .
        'ObjectDef' {
            if ($Environment.Has($Statement.Name)) {
                $existing = $Environment.Get($Statement.Name)
                if (Test-OtterUiResource $existing) {
                    foreach ($property in $Statement.Properties) {
                        if ($property.Target.Kind -ne [NodeKind]::Variable) {
                            throw (New-OtterRuntimeError -Message 'A UI resource property name must be a plain name.' -Line $property.Line)
                        }
                        $value = Get-OtterValue -Expression $property.Value -Environment $Environment
                        Set-OtterUiProperty -Resource $existing -Property $property.Target.Name -Value $value -Line $property.Line
                    }
                    return
                }
                throw (New-OtterRuntimeError -Message "Otter will not replace existing $((Get-OtterTypeName $existing)) called `"$($Statement.Name)`" with a new thing." -Line $Statement.Line -Suggestion 'Use a new name, or assign individual properties instead.')
            }
            $object = New-OtterObjectValue -Statement $Statement -Environment $Environment
            $Environment.Set($Statement.Name, $object)
            return
        }

        # a Person has
        #     name
        # .
        'TypeDef' {
            $Environment.Set($Statement.TypeName, [OtterType]::new($Statement.TypeName, $Statement.FieldNames))
            return
        }

        # create button into helloButton                              (D44)
        #
        # The real, provider-backed resource is created RIGHT NOW - this is
        # the lifecycle decision D44 froze. Nothing here is a description
        # waiting to be materialized later.
        'CreateUiResource' {
            $resource = New-OtterUiResourceValue -Kind $Statement.TypeName -Line $Statement.Line
            $Environment.Set($Statement.Target, $resource)
            return
        }

        # when helloButton is clicked                            (D46)
        #     say "Hello"
        # .
        #
        # Registration only. The handler closes over $Environment as it
        # exists right here - the same environment If/While bodies already
        # run in, not a function call's fresh child scope (frozen as part
        # of D46). Whether/when this handler is ever actually invoked in a
        # running program depends on a message loop, which is D47's job,
        # not this statement's - registering a handler here does not by
        # itself make anything happen.
        'When' {
            # D110: drag and drop belongs to the web/declarative UI. A WPF
            # window says so plainly instead of registering a handler that
            # could never fire.
            if ($Statement.EventName -in @('drag', 'drop', 'files dropped')) {
                throw (New-OtterRuntimeError `
                    -Message 'Drag and drop ("on drag of", "on drop on", "on files dropped on") is not supported for windows yet. It works in web applications.' `
                    -Line $Statement.Line `
                    -Suggestion 'Compile the program with: otter web <file.ot>')
            }
            $target = Get-OtterValue -Expression $Statement.Target -Environment $Environment
            if (Test-OtterCommandJob $target) {
                $evtName = $Statement.EventName.ToLowerInvariant()
                if ($evtName -notin @('output', 'error output', 'exit')) {
                    throw (New-OtterRuntimeError `
                        -Message "A command job only supports ""on output from"", ""on error output from"", or ""on exit of""." `
                        -Line $Statement.Line)
                }
                $handler = @{
                    EventName = $evtName
                    Body = $Statement.Body
                    Environment = $Environment
                    Fired = $false
                }
                [System.Threading.Monitor]::Enter($target.LockObj)
                try {
                    $target.Handlers.Add($handler)
                } finally {
                    [System.Threading.Monitor]::Exit($target.LockObj)
                }

                # Retained terminal event delivery
                if ($evtName -eq 'exit' -and $null -ne $target.RetainedTerminalEvent -and $target.RetainedTerminalEvent.EventKind -eq 'exit') {
                    $handler.Fired = $true
                    $prevContext = $script:OtterCurrentJobContext
                    $script:OtterCurrentJobContext = $target.RetainedTerminalEvent.Context
                    try {
                        Invoke-OtterStatements -Statements $Statement.Body -Environment $Environment
                    } finally {
                        $script:OtterCurrentJobContext = $prevContext
                    }
                }
                return
            }
            if (-not (Test-OtterUiResource $target)) {
                $shown = Get-OtterTypeName -Value $target
                throw (New-OtterRuntimeError `
                    -Message "I can only listen for an event on a UI resource or command job, but this is $shown." `
                    -Line $Statement.Line)
            }

            $body = $Statement.Body
            $handler = { Invoke-OtterStatements -Statements $body -Environment $Environment }.GetNewClosure()
            Add-OtterUiEventHandler -Resource $target -EventName $Statement.EventName -Handler $handler -Line $Statement.Line
            return
        }

        # put helloButton in app                                  (D47)
        'PutIn' {
            $item = Get-OtterValue -Expression $Statement.Item -Environment $Environment
            if (-not (Test-OtterUiResource $item)) {
                $shown = Get-OtterTypeName -Value $item
                throw (New-OtterRuntimeError `
                    -Message "I can only put a UI resource somewhere, but this is $shown." `
                    -Line $Statement.Line)
            }

            $container = Get-OtterValue -Expression $Statement.Container -Environment $Environment
            if (-not (Test-OtterUiResource $container)) {
                $shown = Get-OtterTypeName -Value $container
                throw (New-OtterRuntimeError `
                    -Message "I can only put something in a UI resource, but this is $shown." `
                    -Line $Statement.Line)
            }

            Add-OtterUiChild -Container $container -Item $item -Line $Statement.Line
            return
        }

        # show app                                                (D47)
        'Show' {
            $target = Get-OtterValue -Expression $Statement.Target -Environment $Environment
            if (-not (Test-OtterUiResource $target)) {
                $shown = Get-OtterTypeName -Value $target
                throw (New-OtterRuntimeError `
                    -Message "I can only show a UI resource, but this is $shown." `
                    -Line $Statement.Line)
            }

            Show-OtterUiResource -Resource $target -Line $Statement.Line
            return
        }

        # get "Jeff" from scores into score      (D41 - missing key is gone, not an error)
        'GetKey' {
            $target = Get-OtterValue -Expression $Statement.Target -Environment $Environment
            $key = Assert-OtterDynamicKeyTarget -Value $target -Line $Statement.Line -Verb 'read from'

            $rawKey = Get-OtterValue -Expression $Statement.Key -Environment $Environment
            $keyText = Assert-OtterStringKey -Value $rawKey -Line $Statement.Line

            # ReadProperty already returns $null for a key that was never
            # set - that IS gone (D22). No HasProperty guard here on
            # purpose: that guard is what makes "name of person" an error
            # on a missing property, and this statement is deliberately not
            # that one.
            $Environment.Set($Statement.ResultTarget, $key.ReadProperty($keyText))
            return
        }

        # set "Jeff" to 100 in scores      (D41 - creates or replaces)
        'SetKey' {
            $target = Get-OtterValue -Expression $Statement.Target -Environment $Environment
            $key = Assert-OtterDynamicKeyTarget -Value $target -Line $Statement.Line -Verb 'write to'

            $rawKey = Get-OtterValue -Expression $Statement.Key -Environment $Environment
            $keyText = Assert-OtterStringKey -Value $rawKey -Line $Statement.Line

            $value = Get-OtterValue -Expression $Statement.Value -Environment $Environment
            # WriteProperty already creates-or-replaces - nothing extra needed.
            $key.WriteProperty($keyText, $value)
            return
        }

        # ask "What is your name?" and call it name       (D6)
        # ask secretly "Password:" and call it pw                      (D100)
        'Ask' {
            Complete-OtterProgressBarLine
            $prompt = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Prompt -Environment $Environment)
            Write-Host "$prompt " -NoNewline
            if ($Statement.Secret) {
                $typed = Read-OtterSecretLine
            } else {
                $typed = Read-Host
            }
            $Environment.Set($Statement.Name, (ConvertFrom-OtterInput -Text $typed))
            return
        }

        # number1 and number2 make total
        'MathInto' {
            $value = Get-OtterValue -Expression $Statement.Expression -Environment $Environment
            $Environment.Set($Statement.Target, $value)
            return
        }

        # add 5 to score   /   add "Pokemon" to games        (D12)
        'AddTo' {
            Invoke-OtterAddTo -Statement $Statement -Environment $Environment
            return
        }

        # remove 2 from score   /   remove "Mario" from games (D12)
        'RemoveFrom' {
            Invoke-OtterRemoveFrom -Statement $Statement -Environment $Environment
            return
        }

        # if / otherwise if / otherwise
        'If' {
            foreach ($branch in $Statement.Branches) {
                $test = Get-OtterValue -Expression $branch.Condition -Environment $Environment
                if (Test-OtterTruthy -Value $test) {
                    Invoke-OtterStatements -Statements $branch.Body -Environment $Environment
                    return
                }
            }
            if ($null -ne $Statement.ElseBody) {
                Invoke-OtterStatements -Statements $Statement.ElseBody -Environment $Environment
            }
            return
        }

        # while number is less than 5
        'While' {
            while ($true) {
                $test = Get-OtterValue -Expression $Statement.Condition -Environment $Environment
                if (-not (Test-OtterTruthy -Value $test)) { break }
                Invoke-OtterStatements -Statements $Statement.Body -Environment $Environment
            }
            return
        }

        # repeat 3 times
        'Repeat' {
            $raw = Get-OtterValue -Expression $Statement.Count -Environment $Environment
            $count = Assert-OtterNumber -Value $raw -Line $Statement.Line -What 'the number of repeats'
            $whole = [int][Math]::Floor($count)
            for ($i = 0; $i -lt $whole; $i++) {
                Invoke-OtterStatements -Statements $Statement.Body -Environment $Environment
            }
            return
        }

        # count from 1 to 5 as number      (D5: both ends inclusive)
        'CountLoop' {
            $fromRaw = Get-OtterValue -Expression $Statement.From -Environment $Environment
            $toRaw = Get-OtterValue -Expression $Statement.To -Environment $Environment
            $from = Assert-OtterNumber -Value $fromRaw -Line $Statement.Line -What 'the value to count from'
            $to = Assert-OtterNumber -Value $toRaw -Line $Statement.Line -What 'the value to count to'

            # "count from 10 to 1" reads as counting down, so it counts down.
            $step = if ($from -le $to) { 1 } else { -1 }
            for ($n = $from; ($step -gt 0 -and $n -le $to) -or ($step -lt 0 -and $n -ge $to); $n += $step) {
                $Environment.SetLocal($Statement.VariableName, [double]$n)
                Invoke-OtterStatements -Statements $Statement.Body -Environment $Environment
            }
            return
        }

        # for each game in games
        'ForEach' {
            $collection = Get-OtterValue -Expression $Statement.Collection -Environment $Environment
            if (-not (Test-OtterList $collection)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only go through a list, but this is $(Get-OtterTypeName $collection)." `
                    -Line $Statement.Line)
            }
            # Copy first: the body may add to the list while we walk it.
            # .ToArray(), not @($collection) - the array subexpression operator
            # throws "Argument types do not match" on a generic List in PS 5.1.
            $snapshot = $collection.ToArray()
            foreach ($item in $snapshot) {
                $Environment.SetLocal($Statement.VariableName, $item)
                Invoke-OtterStatements -Statements $Statement.Body -Environment $Environment
            }
            return
        }

        # games are / games are empty      (D13)
        'ListDef' {
            $values = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $Statement.Items) {
                $values.Add((Get-OtterValue -Expression $item -Environment $Environment))
            }
            $Environment.Set($Statement.Name, (New-OtterList -Items $values))
            return
        }

        # to greet name
        'FunctionDef' {
            $function = [OtterFunction]::new($Statement.Name, $Statement.Parameters, $Statement.Body)
            $Environment.Set($Statement.Name, $function)
            return
        }

        # greet "Jeff"      /      double 5 make result
        'CallStatement' {
            $result = Invoke-OtterCall -Call $Statement.Call -Environment $Environment
            if ($Statement.ResultTarget) {
                $Environment.Set($Statement.ResultTarget, $result)
            }
            return
        }

        # return answer
        'Return' {
            $value = $null
            if ($null -ne $Statement.Value) {
                $value = Get-OtterValue -Expression $Statement.Value -Environment $Environment
            }
            throw [OtterReturnSignal]::new($value, $Statement.Line)
        }

        # --- runtime library (milestone 7) ----------------------
        #
        # Each of these is one readable Otter line on the outside and a pile
        # of platform detail on the inside, all of which lives in
        # src/Otter.Library.psm1 rather than here.

        # read "notes.txt" into notes
        'ReadFile' {
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            $Environment.Set($Statement.Target, (Read-OtterFile -Path $path -Line $Statement.Line))
            return
        }

        # write "Hello!" to "hello.txt"
        'WriteFile' {
            $content = Get-OtterText -Expression $Statement.Content -Environment $Environment
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            Write-OtterFile -Path $path -Content $content -Line $Statement.Line -Atomic $Statement.Atomic
            return
        }

        # write bytes data to file "copy.png" [atomically]          (D115)
        'WriteBytesFile' {
            $bytes = Get-OtterValue -Expression $Statement.Data -Environment $Environment
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            Write-OtterFileBytes -Path $path -Bytes $bytes -Line $Statement.Line -Atomic $Statement.Atomic
            return
        }

        # append "line one" to "log.txt"                            (D61)
        'AppendFile' {
            $content = Get-OtterText -Expression $Statement.Content -Environment $Environment
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            Add-OtterFileContent -Path $path -Content $content -Line $Statement.Line
            return
        }

        # copy "hello.txt" to "backup/hello.txt"
        'CopyFile' {
            $source = Get-OtterPathArgument -Expression $Statement.Source -Environment $Environment
            $destination = Get-OtterPathArgument -Expression $Statement.Destination -Environment $Environment
            Copy-OtterFile -Source $source -Destination $destination -Line $Statement.Line
            return
        }

        # move "hello.txt" to "Documents"
        'MoveFile' {
            $source = Get-OtterPathArgument -Expression $Statement.Source -Environment $Environment
            $destination = Get-OtterPathArgument -Expression $Statement.Destination -Environment $Environment
            Move-OtterFile -Source $source -Destination $destination -Line $Statement.Line
            return
        }

        # delete file "hello.txt"
        'DeleteFile' {
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            Remove-OtterFile -Path $path -Line $Statement.Line
            return
        }

        # download file from <url> to <path>                            (D96)
        'DownloadFile' {
            $url = Get-OtterText -Expression $Statement.Url -Environment $Environment
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            Receive-OtterFileDownload -Url $url -Path $path -Line $Statement.Line
            return
        }

        # get <url> [as json] into <target>                         (D49, D116A)
        # get json from <url> into <target>
        'HttpGet' {
            $url = Get-OtterText -Expression $Statement.Url -Environment $Environment
            $optArgs = Get-OtterHttpOptionsArguments -Options $Statement.Options -Environment $Environment
            $result = Invoke-OtterHttpRequest -Method 'GET' -Url $url -AsJson $Statement.AsJson `
                -Headers $optArgs.Headers -WithCookies $optArgs.WithCookies `
                -FollowRedirects $optArgs.FollowRedirects -TimeoutSeconds $optArgs.TimeoutSeconds `
                -Line $Statement.Line
            $Environment.Set($Statement.Target, $result)
            return
        }

        # post <data> [as json] to <url> [into <target>]            (D49, D116A)
        'HttpPost' {
            $url = Get-OtterText -Expression $Statement.Url -Environment $Environment
            $data = Get-OtterValue -Expression $Statement.Data -Environment $Environment
            $optArgs = Get-OtterHttpOptionsArguments -Options $Statement.Options -Environment $Environment
            $result = Invoke-OtterHttpRequest -Method 'POST' -Url $url -Data $data -AsJson $Statement.AsJson `
                -Headers $optArgs.Headers -WithCookies $optArgs.WithCookies `
                -FollowRedirects $optArgs.FollowRedirects -TimeoutSeconds $optArgs.TimeoutSeconds `
                -Line $Statement.Line
            if (-not [string]::IsNullOrEmpty($Statement.Target)) {
                $Environment.Set($Statement.Target, $result)
            }
            return
        }

        # put <data> [as json] to <url> [into <target>]             (D49, D116A)
        'HttpPut' {
            $url = Get-OtterText -Expression $Statement.Url -Environment $Environment
            $data = Get-OtterValue -Expression $Statement.Data -Environment $Environment
            $optArgs = Get-OtterHttpOptionsArguments -Options $Statement.Options -Environment $Environment
            $result = Invoke-OtterHttpRequest -Method 'PUT' -Url $url -Data $data -AsJson $Statement.AsJson `
                -Headers $optArgs.Headers -WithCookies $optArgs.WithCookies `
                -FollowRedirects $optArgs.FollowRedirects -TimeoutSeconds $optArgs.TimeoutSeconds `
                -Line $Statement.Line
            if (-not [string]::IsNullOrEmpty($Statement.Target)) {
                $Environment.Set($Statement.Target, $result)
            }
            return
        }

        # delete from <url> [into <target>]                         (D49, D116A)
        'HttpDelete' {
            $url = Get-OtterText -Expression $Statement.Url -Environment $Environment
            $optArgs = Get-OtterHttpOptionsArguments -Options $Statement.Options -Environment $Environment
            $result = Invoke-OtterHttpRequest -Method 'DELETE' -Url $url `
                -Headers $optArgs.Headers -WithCookies $optArgs.WithCookies `
                -FollowRedirects $optArgs.FollowRedirects -TimeoutSeconds $optArgs.TimeoutSeconds `
                -Line $Statement.Line
            if (-not [string]::IsNullOrEmpty($Statement.Target)) {
                $Environment.Set($Statement.Target, $result)
            }
            return
        }

        # start get/post/put/delete ... and call it <target>          (D116B)
        'HttpStart' {
            $url = Get-OtterText -Expression $Statement.Url -Environment $Environment
            $data = $null
            if ($null -ne $Statement.Data) {
                $data = Get-OtterValue -Expression $Statement.Data -Environment $Environment
            }
            $optArgs = Get-OtterHttpOptionsArguments -Options $Statement.Options -Environment $Environment

            $reqHandle = Start-OtterHttpRequest `
                -Method $Statement.Method `
                -Url $url `
                -Data $data `
                -AsJson $Statement.AsJson `
                -Headers $optArgs.Headers `
                -WithCookies $optArgs.WithCookies `
                -FollowRedirects $optArgs.FollowRedirects `
                -TimeoutSeconds $optArgs.TimeoutSeconds `
                -Line $Statement.Line

            $script:OtterActiveHttpRequests.Add($reqHandle)
            $Environment.Set($Statement.TargetName, $reqHandle)
            return
        }

        # cancel <request> or <job>                                   (D116B, D119-R2)
        'HttpCancel' {
            $req = Get-OtterValue -Expression $Statement.Request -Environment $Environment
            if (Test-OtterCommandJob $req) {
                Stop-OtterCommandJob -Job $req -Line $Statement.Line
                return
            }
            if ($null -eq $req -or -not (Test-OtterHttpRequest $req)) {
                throw (New-OtterRuntimeError `
                    -Message 'cancel requires an HTTP request.' `
                    -Line $Statement.Line)
            }
            if ($req.State -ne 'pending') {
                return
            }
            $req.State = 'cancelled'
            try { $req.Cts.Cancel() } catch {}
            $context = @{}
            $req.RetainedTerminalEvent = @{ EventKind = [NetworkEventKind]::Cancel; Context = $context }
            Invoke-OtterWebSocketHandlers -Socket $req -EventKind ([NetworkEventKind]::Cancel) -Context $context
            return
        }


        # connect database into db                                     (D97)
        'ConnectDb' {
            $config = Get-OtterValue -Expression $Statement.Config -Environment $Environment
            $connObj = Connect-OtterDatabase -ConfigValue $config -Line $Statement.Line
            $Environment.Set($Statement.Target, $connObj)
            return
        }

        # disconnect db                                                (D97)
        'DisconnectDb' {
            $conn = Get-OtterValue -Expression $Statement.Connection -Environment $Environment
            Disconnect-OtterDatabase -ConnectionValue $conn -Line $Statement.Line
            return
        }

        # query db with ... into tasks                                 (D97)
        'DbQuery' {
            $conn = Get-OtterValue -Expression $Statement.Connection -Environment $Environment
            $queryText = Get-OtterText -Expression $Statement.Query -Environment $Environment
            $params = @{}
            if ($null -ne $Statement.Parameters) {
                foreach ($p in $Statement.Parameters) {
                    $pVal = Get-OtterValue -Expression $p.Value -Environment $Environment
                    $params[$p.Name] = $pVal
                }
            }
            $rows = Invoke-OtterDatabaseQuery -TargetValue $conn -Sql $queryText -Parameters $params -Line $Statement.Line
            $list = [System.Collections.Generic.List[object]]::new()
            if ($rows -is [System.Collections.IEnumerable] -and $rows -isnot [string]) {
                foreach ($r in $rows) { $list.Add($r) }
            } elseif ($null -ne $rows) {
                $list.Add($rows)
            }
            $Environment.Set($Statement.Target, $list)
            return
        }

        # execute db with ... [into result]                            (D97)
        'DbExecute' {
            $conn = Get-OtterValue -Expression $Statement.Connection -Environment $Environment
            $cmdText = Get-OtterText -Expression $Statement.Command -Environment $Environment
            $params = @{}
            if ($null -ne $Statement.Parameters) {
                foreach ($p in $Statement.Parameters) {
                    $pVal = Get-OtterValue -Expression $p.Value -Environment $Environment
                    $params[$p.Name] = $pVal
                }
            }
            $res = Invoke-OtterDatabaseCommand -TargetValue $conn -Sql $cmdText -Parameters $params -Line $Statement.Line
            if (-not [string]::IsNullOrEmpty($Statement.Target)) {
                $Environment.Set($Statement.Target, $res)
            }
            return
        }

        # begin transaction on db into tx                              (D97)
        'BeginTransaction' {
            $conn = Get-OtterValue -Expression $Statement.Connection -Environment $Environment
            $txObj = Start-OtterDatabaseTransaction -ConnectionValue $conn -Line $Statement.Line
            $Environment.Set($Statement.Target, $txObj)
            return
        }

        # commit tx                                                    (D97)
        'CommitTransaction' {
            $tx = Get-OtterValue -Expression $Statement.Transaction -Environment $Environment
            Complete-OtterDatabaseTransaction -TransactionValue $tx -Line $Statement.Line
            return
        }

        # rollback tx                                                  (D97)
        'RollbackTransaction' {
            $tx = Get-OtterValue -Expression $Statement.Transaction -Environment $Environment
            Undo-OtterDatabaseTransaction -TransactionValue $tx -Line $Statement.Line
            return
        }

        # get tables from db into tables                               (D98)
        'GetTables' {
            $conn = Get-OtterValue -Expression $Statement.Connection -Environment $Environment
            $tables = Get-OtterDatabaseTables -TargetValue $conn -Line $Statement.Line
            $list = [System.Collections.Generic.List[object]]::new()
            if ($tables -is [System.Collections.IEnumerable] -and $tables -isnot [string]) {
                foreach ($t in $tables) { $list.Add($t) }
            } elseif ($null -ne $tables) {
                $list.Add($tables)
            }
            $Environment.Set($Statement.Target, $list)
            return
        }

        # get columns from table in db into columns                    (D98)
        'GetColumns' {
            $table = Get-OtterValue -Expression $Statement.Table -Environment $Environment
            $conn = Get-OtterValue -Expression $Statement.Connection -Environment $Environment
            $columns = Get-OtterDatabaseColumns -TargetValue $conn -TableOrName $table -Line $Statement.Line
            $list = [System.Collections.Generic.List[object]]::new()
            if ($columns -is [System.Collections.IEnumerable] -and $columns -isnot [string]) {
                foreach ($c in $columns) { $list.Add($c) }
            } elseif ($null -ne $columns) {
                $list.Add($columns)
            }
            $Environment.Set($Statement.Target, $list)
            return
        }

        # get ... from table in db [as alias] [where ...] [order by ...] [take N] [skip M] into target  (D99)
        'QueryStmt' {
            $conn = Get-OtterValue -Expression $Statement.Connection -Environment $Environment
            $parameters = @{}
            $paramIndex = [int[]]@(0)

            $projParts = [System.Collections.Generic.List[string]]::new()
            if ($null -eq $Statement.Projections -or $Statement.Projections.Count -eq 0) {
                $projParts.Add('*')
            } else {
                foreach ($p in $Statement.Projections) {
                    if ($p -is [VariableExpr]) {
                        if ($p.Name -eq '*') { $projParts.Add('*') }
                        else { $projParts.Add("[$($p.Name)]") }
                    } elseif ($p -is [PropertyAccessExpr]) {
                        $t = if ($p.Target -is [VariableExpr]) { $p.Target.Name } else { 'col' }
                        $projParts.Add("[$t].[$($p.PropertyName)]")
                    } else {
                        $pName = Get-OtterText -Expression $p -Environment $Environment
                        $projParts.Add("[$pName]")
                    }
                }
            }
            $distinctSql = if ($Statement.IsDistinct) { 'DISTINCT ' } else { '' }
            $projsSql = $projParts -join ', '

            $tableSql = "[$($Statement.Table)]"
            if (-not [string]::IsNullOrEmpty($Statement.Alias)) {
                $tableSql += " AS [$($Statement.Alias)]"
            }

            $whereSql = ''
            if ($null -ne $Statement.Where) {
                $whereSql = ConvertTo-OtterQuerySqlExpression -Node $Statement.Where -Environment $Environment -Parameters $parameters -ParamIndex $paramIndex -IsWhereClause
            }

            $orderParts = [System.Collections.Generic.List[string]]::new()
            if ($null -ne $Statement.OrderBy -and $Statement.OrderBy.Count -gt 0) {
                foreach ($item in $Statement.OrderBy) {
                    $col = if ($item.Expression -is [VariableExpr]) {
                        "[$($item.Expression.Name)]"
                    } elseif ($item.Expression -is [PropertyAccessExpr]) {
                        $t = if ($item.Expression.Target -is [VariableExpr]) { $item.Expression.Target.Name } else { 'col' }
                        "[$t].[$($item.Expression.PropertyName)]"
                    } else {
                        $colName = Get-OtterText -Expression $item.Expression -Environment $Environment
                        "[$colName]"
                    }
                    $dir = if ($item.IsDescending) { 'DESC' } else { 'ASC' }
                    $orderParts.Add("$col $dir")
                }
            }

            $limitSql = ''
            if ($null -ne $Statement.Limit) {
                $limitVal = Get-OtterValue -Expression $Statement.Limit -Environment $Environment
                $pLimit = New-OtterQueryParamName $paramIndex
                $parameters[$pLimit] = [int]$limitVal
                if ($null -ne $Statement.Offset) {
                    $offsetVal = Get-OtterValue -Expression $Statement.Offset -Environment $Environment
                    $pOffset = New-OtterQueryParamName $paramIndex
                    $parameters[$pOffset] = [int]$offsetVal
                    $limitSql = " LIMIT @$pLimit OFFSET @$pOffset"
                } else {
                    $limitSql = " LIMIT @$pLimit"
                }
            } elseif ($null -ne $Statement.Offset) {
                $offsetVal = Get-OtterValue -Expression $Statement.Offset -Environment $Environment
                $pOffset = New-OtterQueryParamName $paramIndex
                $parameters[$pOffset] = [int]$offsetVal
                $limitSql = " LIMIT -1 OFFSET @$pOffset"
            }

            $sql = "SELECT $distinctSql$projsSql FROM $tableSql"
            if (-not [string]::IsNullOrEmpty($whereSql)) {
                $sql += " WHERE $whereSql"
            }
            if ($orderParts.Count -gt 0) {
                $sql += " ORDER BY $($orderParts -join ', ')"
            }
            if (-not [string]::IsNullOrEmpty($limitSql)) {
                $sql += $limitSql
            }

            $rows = Invoke-OtterDatabaseQuery -TargetValue $conn -Sql $sql -Parameters $parameters -Line $Statement.Line
            $list = [System.Collections.Generic.List[object]]::new()
            if ($rows -is [System.Collections.IEnumerable] -and $rows -isnot [string]) {
                foreach ($r in $rows) { $list.Add($r) }
            } elseif ($null -ne $rows) {
                $list.Add($rows)
            }
            $Environment.Set($Statement.Target, $list)
            return
        }

        # count/sum/average/minimum/maximum ... from table in db [where ...] into target  (D99)
        'QueryAggregateStmt' {
            $conn = Get-OtterValue -Expression $Statement.Connection -Environment $Environment
            $parameters = @{}
            $paramIndex = [int[]]@(0)

            $aggFunc = switch ($Statement.AggregateFunc.ToLowerInvariant()) {
                'count' { 'COUNT' }
                'sum' { 'SUM' }
                'total' { 'TOTAL' }
                'average' { 'AVG' }
                'avg' { 'AVG' }
                'minimum' { 'MIN' }
                'min' { 'MIN' }
                'maximum' { 'MAX' }
                'max' { 'MAX' }
                default { 'COUNT' }
            }
            $colExpr = if ($null -eq $Statement.Expression) {
                '*'
            } elseif ($Statement.Expression -is [VariableExpr] -and $Statement.Expression.Name -eq '*') {
                '*'
            } elseif ($Statement.Expression -is [VariableExpr]) {
                "[$($Statement.Expression.Name)]"
            } elseif ($Statement.Expression -is [PropertyAccessExpr]) {
                $t = if ($Statement.Expression.Target -is [VariableExpr]) { $Statement.Expression.Target.Name } else { 'col' }
                "[$t].[$($Statement.Expression.PropertyName)]"
            } else {
                "*"
            }

            $tableSql = "[$($Statement.Table)]"
            if (-not [string]::IsNullOrEmpty($Statement.Alias)) {
                $tableSql += " AS [$($Statement.Alias)]"
            }

            $whereSql = ''
            if ($null -ne $Statement.Where) {
                $whereSql = ConvertTo-OtterQuerySqlExpression -Node $Statement.Where -Environment $Environment -Parameters $parameters -ParamIndex $paramIndex -IsWhereClause
            }

            $sql = "SELECT $aggFunc($colExpr) AS [agg_result] FROM $tableSql"
            if (-not [string]::IsNullOrEmpty($whereSql)) {
                $sql += " WHERE $whereSql"
            }

            $rows = Invoke-OtterDatabaseQuery -TargetValue $conn -Sql $sql -Parameters $parameters -Line $Statement.Line
            $res = $null
            if ($null -ne $rows -and $rows.Count -gt 0) {
                $firstRow = $rows[0]
                $val = if ($firstRow -is [OtterObject]) {
                    $firstRow.ReadProperty('agg_result')
                } else {
                    $firstRow
                }

                if ($null -eq $val -or $val -is [System.DBNull]) {
                    if ($Statement.AggregateFunc.ToLowerInvariant() -eq 'count') { $res = 0 } else { $res = $null }
                } else {
                    $res = $val
                }
            } else {
                if ($Statement.AggregateFunc.ToLowerInvariant() -eq 'count') { $res = 0 } else { $res = $null }
            }

            $Environment.Set($Statement.Target, $res)
            return
        }

        # set cursor to row 5 column 10                                (D100)
        # Otter's row/column are 1-based; [Console]::SetCursorPosition is
        # 0-based, hence the -1 on each.
        'SetCursorPosition' {
            $row = Assert-OtterNumber -Value (Get-OtterValue -Expression $Statement.Row -Environment $Environment) -Line $Statement.Line -What 'a cursor row'
            $column = Assert-OtterNumber -Value (Get-OtterValue -Expression $Statement.Column -Environment $Environment) -Line $Statement.Line -What 'a cursor column'
            if ($row -lt 1 -or $column -lt 1) {
                throw (New-OtterRuntimeError `
                    -Message 'I need a row and column of 1 or greater.' `
                    -Line $Statement.Line `
                    -Suggestion 'set cursor to row 1 column 1')
            }
            try {
                [Console]::SetCursorPosition([int]$column - 1, [int]$row - 1)
            } catch {
                throw (New-OtterRuntimeError `
                    -Message "I could not move the cursor there. $($_.Exception.Message)" `
                    -Line $Statement.Line)
            }
            return
        }

        # show progress 50 percent                                     (D100)
        # Redraws on the current line via a leading carriage return, so
        # repeated calls update one bar in place rather than spamming
        # new lines - the normal expectation for a CLI progress indicator.
        'ShowProgress' {
            $percent = Assert-OtterNumber -Value (Get-OtterValue -Expression $Statement.Percent -Environment $Environment) -Line $Statement.Line -What 'a progress percentage'
            if ($percent -lt 0 -or $percent -gt 100) {
                throw (New-OtterRuntimeError `
                    -Message "I need a percentage between 0 and 100, but got $(Format-OtterValue -Value $percent)." `
                    -Line $Statement.Line `
                    -Suggestion 'show progress 50 percent')
            }
            $width = 20
            $filled = [int][Math]::Round($width * ($percent / 100))
            $bar = ('#' * $filled) + ('-' * ($width - $filled))
            if ($null -ne $script:OutputWriter) {
                & $script:OutputWriter "[$bar] $(Format-OtterValue -Value $percent)%"
            } else {
                Write-Host "`r[$bar] $(Format-OtterValue -Value $percent)%" -NoNewline
                $script:OtterProgressBarActive = $true
            }
            return
        }

        # choose from options into choice                              (D100)
        # Target receives the SELECTED ITEM itself, not its position -
        # matching how `random item from games into game` already hands
        # back an element, not an index.
        'ChooseFromList' {
            Complete-OtterProgressBarLine
            $options = Get-OtterValue -Expression $Statement.Options -Environment $Environment
            if (-not (Test-OtterList $options) -or $options.Count -eq 0) {
                throw (New-OtterRuntimeError `
                    -Message 'I cannot choose from an empty list.' `
                    -Line $Statement.Line)
            }
            for ($i = 0; $i -lt $options.Count; $i++) {
                Write-Host "  $($i + 1). $(Format-OtterValue -Value $options[$i])"
            }
            $selected = $null
            while ($null -eq $selected) {
                Write-Host 'Choose a number: ' -NoNewline
                $typed = Read-Host
                $asNumber = 0
                if ([int]::TryParse($typed, [ref]$asNumber) -and $asNumber -ge 1 -and $asNumber -le $options.Count) {
                    $selected = $options[$asNumber - 1]
                } else {
                    Write-Host "  Please enter a number from 1 to $($options.Count)." -ForegroundColor Yellow
                }
            }
            $Environment.Set($Statement.Target, $selected)
            return
        }

        # wait 5 seconds  /  wait delay seconds                             (D101)
        'WaitDelay' {
            $amount = Assert-OtterNumber -Value (Get-OtterValue -Expression $Statement.Duration -Environment $Environment) -Line $Statement.Line -What 'a wait duration'
            if ($amount -lt 0) {
                throw (New-OtterRuntimeError `
                    -Message "I can't wait a negative amount of time ($amount)." `
                    -Line $Statement.Line)
            }
            $millis = switch ($Statement.Unit) {
                ([TimeUnit]::Millisecond) { $amount }
                ([TimeUnit]::Second)      { $amount * 1000 }
                ([TimeUnit]::Minute)      { $amount * 60000 }
                ([TimeUnit]::Hour)        { $amount * 3600000 }
                ([TimeUnit]::Day)         { $amount * 86400000 }
                ([TimeUnit]::Month)       { $amount * 2629746000 }
                ([TimeUnit]::Year)        { $amount * 31556952000 }
                default                   { $amount * 1000 }
            }
            $targetMs = [Math]::Round($millis)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.ElapsedMilliseconds -lt $targetMs) {
                Invoke-OtterHttpEventLoopStep
                Invoke-OtterJobEventLoopStep
                $remaining = $targetMs - $sw.ElapsedMilliseconds
                if ($remaining -gt 0) {
                    $sleepChunk = [Math]::Min([int]$remaining, 20)
                    Start-Sleep -Milliseconds $sleepChunk
                }
            }
            Invoke-OtterHttpEventLoopStep
            Invoke-OtterJobEventLoopStep
            return
        }

        # set random seed to 42                                            (D101)
        # Only affects the plain Get-Random path used by `random number`/
        # `random item from` - D92's separate cryptographically-secure
        # RandomNumberGenerator is untouched by design.
        'SetRandomSeed' {
            $seedValue = Assert-OtterNumber -Value (Get-OtterValue -Expression $Statement.Seed -Environment $Environment) -Line $Statement.Line -What 'a random seed'
            Get-Random -SetSeed ([int]$seedValue) | Out-Null
            return
        }

        # start timer workTimer                                            (D101)
        'StartTimer' {
            $Environment.Set($Statement.Target, [System.Diagnostics.Stopwatch]::StartNew())
            return
        }

        # watch file "settings.json" and call it settingsWatcher          (D104)
        # watch folder "assets" [recursively] and call it assetsWatcher
        'WatchDeclare' {
            $path = Get-OtterText -Expression $Statement.Path -Environment $Environment
            $isFolder = ($Statement.TargetKind -eq [WatchKind]::Folder)
            $watcher = New-OtterFileWatcher -Path $path -IsFolder $isFolder -Recursive $Statement.Recursive -Line $Statement.Line
            $Environment.Set($Statement.Target, $watcher)
            return
        }

        # stop watching settingsWatcher                                    (D104)
        'StopWatching' {
            $watcher = Get-OtterValue -Expression $Statement.Watcher -Environment $Environment
            if (-not (Test-OtterFileWatcher $watcher)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only stop watching a file watcher, but this is $(Get-OtterTypeName -Value $watcher)." `
                    -Line $Statement.Line)
            }
            Stop-OtterFileWatcherInternal -Watcher $watcher
            return
        }

        # on change of X / on create in X / on delete in X / on rename in X  (D104)
        # Registration only - matches WhenStmt's own established shape
        # (D46's own comment: registering a handler here does not by
        # itself make anything happen; Invoke-OtterWatchEventLoop is what
        # actually calls it later, the same separation D47 draws for UI
        # events).
        'WatchEvent' {
            $watcher = Get-OtterValue -Expression $Statement.Watcher -Environment $Environment
            if (-not (Test-OtterFileWatcher $watcher)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only listen for a watcher event on a file watcher, but this is $(Get-OtterTypeName -Value $watcher)." `
                    -Line $Statement.Line)
            }
            if (-not $script:OtterWatcherHandlers.ContainsKey($watcher)) {
                $script:OtterWatcherHandlers[$watcher] = [System.Collections.Generic.List[hashtable]]::new()
            }
            $script:OtterWatcherHandlers[$watcher].Add(@{ EventKind = $Statement.EventKind; Body = $Statement.Body; Environment = $Environment })
            return
        }

        # connect to websocket "wss://..." [using protocol P] and call it X   (D106)
        'WebSocketConnect' {
            $rawUrl = Get-OtterValue -Expression $Statement.Url -Environment $Environment
            if ($rawUrl -isnot [string]) {
                throw (New-OtterRuntimeError `
                    -Message "I need text for a websocket URL, but this is $(Get-OtterTypeName -Value $rawUrl)." `
                    -Line $Statement.Line `
                    -Suggestion 'connect to websocket "wss://example.com/chat" and call it socket')
            }
            $url = $rawUrl.Trim()
            if (-not ($url.StartsWith('ws://', [System.StringComparison]::OrdinalIgnoreCase) -or
                      $url.StartsWith('wss://', [System.StringComparison]::OrdinalIgnoreCase))) {
                throw (New-OtterRuntimeError `
                    -Message "I need a websocket URL starting with 'ws://' or 'wss://', but this was '$url'." `
                    -Line $Statement.Line `
                    -Suggestion 'connect to websocket "wss://example.com/chat" and call it socket')
            }
            $uri = $null
            try {
                $uri = [System.Uri]::new($url)
            } catch {
                throw (New-OtterRuntimeError `
                    -Message "The websocket URL '$url' is not a valid web address." `
                    -Line $Statement.Line)
            }

            $protocol = $null
            if ($null -ne $Statement.Protocol) {
                $pVal = Get-OtterValue -Expression $Statement.Protocol -Environment $Environment
                if ($pVal -isnot [string]) {
                    throw (New-OtterRuntimeError `
                        -Message "I need text for a websocket protocol, but this is $(Get-OtterTypeName -Value $pVal)." `
                        -Line $Statement.Line)
                }
                $protocol = [string]$pVal
            }

            $cws = [System.Net.WebSockets.ClientWebSocket]::new()
            if (-not [string]::IsNullOrEmpty($protocol)) {
                $cws.Options.AddSubProtocol($protocol)
            }

            $wsObj = [OtterWebSocket]::new($cws, $url, $(if ($null -ne $protocol) { $protocol } else { '' }), [guid]::NewGuid().ToString('N'))
            $script:OtterActiveWebSockets.Add($wsObj)
            $Environment.Set($Statement.Target, $wsObj)

            try {
                $wsObj.ConnectTask = $cws.ConnectAsync($uri, $wsObj.Cts.Token)
            } catch {
                $wsObj.State = 'closed'
                $wsObj.LastError = $_.Exception.GetBaseException().Message
            }
            return
        }

        # store secret "api-token" with value token                     (D111)
        'StoreSecret' {
            Assert-OtterVaultAvailable -Line $Statement.Line
            $target = Get-OtterSecretTarget -Name (Get-OtterValue -Expression $Statement.Name -Environment $Environment) -Line $Statement.Line
            $secretValue = Get-OtterValue -Expression $Statement.Value -Environment $Environment
            # Text and bytes only; never silently converted to one another.
            if ($secretValue -is [string]) {
                $kind = 'otter-text'
                $blob = [System.Text.Encoding]::UTF8.GetBytes($secretValue)
            } elseif (Test-OtterBytes $secretValue) {
                $kind = 'otter-bytes'
                $blob = [byte[]]$secretValue.Value
            } else {
                throw (New-OtterRuntimeError `
                    -Message "A secret can hold text or bytes, but this is $(Get-OtterTypeName -Value $secretValue)." `
                    -Line $Statement.Line)
            }
            if ($blob.Length -eq 0) {
                throw (New-OtterRuntimeError -Message 'A secret cannot be empty.' -Line $Statement.Line)
            }
            if ($blob.Length -gt $script:OtterCredentialMaxBlob) {
                throw (New-OtterRuntimeError `
                    -Message "That secret is $($blob.Length) bytes, but the credential store holds at most $($script:OtterCredentialMaxBlob) bytes per secret." `
                    -Line $Statement.Line)
            }
            try {
                [OtterCredentialApi]::Write($target, $kind, $blob)
            } catch {
                # Never echo the value; the Win32 message names only the failure.
                throw (New-OtterRuntimeError `
                    -Message "I could not store the secret: $($_.Exception.GetBaseException().Message)" `
                    -Line $Statement.Line)
            }
            return
        }

        # delete secret "api-token"                                      (D111)
        'DeleteSecret' {
            Assert-OtterVaultAvailable -Line $Statement.Line
            $nameValue = Get-OtterValue -Expression $Statement.Name -Environment $Environment
            $target = Get-OtterSecretTarget -Name $nameValue -Line $Statement.Line
            try {
                $removed = [OtterCredentialApi]::Delete($target)
            } catch {
                throw (New-OtterRuntimeError `
                    -Message "I could not delete the secret: $($_.Exception.GetBaseException().Message)" `
                    -Line $Statement.Line)
            }
            if (-not $removed) {
                throw (New-OtterRuntimeError `
                    -Message "There is no secret called ""$nameValue"" to delete." `
                    -Line $Statement.Line `
                    -Suggestion 'if secret "name" exists ...')
            }
            return
        }

        # set drag data to cardId                                       (D110)
        'SetDragData' {
            throw (New-OtterRuntimeError `
                -Message '"set drag data" is only available in web applications, inside "on drag of ...".' `
                -Line $Statement.Line)
        }

        # generate encryption key and call it key                       (D109)
        'GenerateKey' {
            $Environment.Set($Statement.Target, [OtterBytes]::new((New-OtterSecureRandomByteArray -Count $script:OtterCryptoKeyLength)))
            return
        }

        # encrypt data using key and call it encrypted / decrypt ...     (D109)
        'CryptoCipher' {
            $data = Get-OtterValue -Expression $Statement.Data -Environment $Environment
            $key = Get-OtterValue -Expression $Statement.Key -Environment $Environment
            $verb = if ($Statement.IsDecrypt) { 'decrypt' } else { 'encrypt' }
            Assert-OtterCryptoBytes -Value $data -Line $Statement.Line -What "The data to $verb"
            Assert-OtterEncryptionKey -Key $key -Line $Statement.Line
            if ($Statement.IsDecrypt) {
                $plain = Unprotect-OtterBytes -Payload ([byte[]]$data.Value) -Key ([byte[]]$key.Value)
                if ($null -eq $plain) {
                    throw (New-OtterRuntimeError `
                        -Message 'I could not decrypt this data: it was changed, it is not encrypted data, or the key is wrong.' `
                        -Line $Statement.Line)
                }
                $Environment.Set($Statement.Target, [OtterBytes]::new($plain))
            } else {
                $Environment.Set($Statement.Target, [OtterBytes]::new((Protect-OtterBytes -Data ([byte[]]$data.Value) -Key ([byte[]]$key.Value))))
            }
            return
        }

        # hash password password and call it storedHash                  (D109)
        'HashPassword' {
            $password = Get-OtterValue -Expression $Statement.Password -Environment $Environment
            if ($password -isnot [string] -or $password.Length -eq 0) {
                throw (New-OtterRuntimeError `
                    -Message "I need a password as non-empty text, but this is $(Get-OtterTypeName -Value $password)." `
                    -Line $Statement.Line)
            }
            $Environment.Set($Statement.Target, (New-OtterPasswordHash -Password $password))
            return
        }

        # connect to tcp "host" on port 8080 and call it connection     (D107)
        'TcpConnect' {
            $hostVal = Get-OtterValue -Expression $Statement.HostExpr -Environment $Environment
            $portVal = Get-OtterValue -Expression $Statement.Port -Environment $Environment
            if ($hostVal -isnot [string] -or [string]::IsNullOrWhiteSpace($hostVal)) {
                throw (New-OtterRuntimeError `
                    -Message "I need text for a tcp host name or address, but this is $(Get-OtterTypeName -Value $hostVal)." `
                    -Line $Statement.Line `
                    -Suggestion 'connect to tcp "localhost" on port 9000 and call it connection')
            }
            $portNum = Get-OtterNetPort -Value $portVal -Line $Statement.Line
            # D112: TLS options. Checked before any socket exists, so a bad
            # request never leaves a half-open connection behind.
            $serverName = $hostVal
            if (-not $Statement.IsSecure -and ($null -ne $Statement.ServerName -or $null -ne $Statement.Protocols)) {
                throw (New-OtterRuntimeError `
                    -Message '"for server" and "using protocol" only apply to a secure connection.' `
                    -Line $Statement.Line `
                    -Suggestion 'connect securely to tcp "example.com" on port 443 and call it connection')
            }
            if ($null -ne $Statement.ServerName) {
                $serverName = Get-OtterValue -Expression $Statement.ServerName -Environment $Environment
                if ($serverName -isnot [string] -or [string]::IsNullOrWhiteSpace($serverName)) {
                    throw (New-OtterRuntimeError `
                        -Message "I need text for the tls server name, but this is $(Get-OtterTypeName -Value $serverName)." `
                        -Line $Statement.Line)
                }
            }
            if ($null -ne $Statement.Protocols) {
                $requestedProtocols = Get-OtterValue -Expression $Statement.Protocols -Environment $Environment
                $protocolList = if (Test-OtterList $requestedProtocols) { @($requestedProtocols) } else { @($requestedProtocols) }
                foreach ($p in $protocolList) {
                    if ($p -isnot [string] -or [string]::IsNullOrWhiteSpace($p)) {
                        throw (New-OtterRuntimeError `
                            -Message "Each tls protocol must be text such as ""h2"" or ""http/1.1"", but this is $(Get-OtterTypeName -Value $p)." `
                            -Line $Statement.Line)
                    }
                }
                # ALPN needs SslClientAuthenticationOptions, which the .NET
                # Framework runtime under Windows PowerShell 5.1 does not have.
                # Failing here is deliberate: silently connecting WITHOUT the
                # requested protocol would be a lie.
                if (-not ('System.Net.Security.SslClientAuthenticationOptions' -as [type])) {
                    throw (New-OtterRuntimeError `
                        -Message 'Protocol negotiation ("using protocol") is not available on this Otter runtime (Windows PowerShell 5.1 has no ALPN support).' `
                        -Line $Statement.Line `
                        -Suggestion 'Remove "using protocol" to connect with TLS only.')
                }
            }
            $client = [System.Net.Sockets.TcpClient]::new([System.Net.Sockets.AddressFamily]::InterNetwork)
            $tcp = [OtterTcp]::new($client, $hostVal, $portNum)
            $tcp.IsSecure = [bool]$Statement.IsSecure
            $tcp.ServerName = $serverName
            $script:OtterActiveNet.Add($tcp)
            $Environment.Set($Statement.Target, $tcp)
            try {
                $tcp.ConnectTask = $client.ConnectAsync($hostVal, $portNum)
            } catch {
                $tcp.State = 'closed'
                $tcp.LastError = "Could not connect to tcp ${hostVal} on port ${portNum}: $($_.Exception.GetBaseException().Message)"
                throw (New-OtterRuntimeError -Message $tcp.LastError -Line $Statement.Line)
            }
            return
        }

        # open udp [on port 9000] and call it socket                    (D108)
        'UdpOpen' {
            $localPort = 0
            if ($null -ne $Statement.Port) {
                $localPort = Get-OtterNetPort -Value (Get-OtterValue -Expression $Statement.Port -Environment $Environment) -Line $Statement.Line -AllowZero
            }
            try {
                $client = [System.Net.Sockets.UdpClient]::new($localPort, [System.Net.Sockets.AddressFamily]::InterNetwork)
            } catch {
                throw (New-OtterRuntimeError `
                    -Message "I could not open a udp socket on port ${localPort}: $($_.Exception.GetBaseException().Message)" `
                    -Line $Statement.Line)
            }
            $actualPort = ([System.Net.IPEndPoint]$client.Client.LocalEndPoint).Port
            $udp = [OtterUdp]::new($client, $actualPort)
            $script:OtterActiveNet.Add($udp)
            $Environment.Set($Statement.Target, $udp)
            return
        }

        # send data through socket to "127.0.0.1" on port 9000          (D108)
        'UdpSend' {
            $udp = Get-OtterValue -Expression $Statement.Socket -Environment $Environment
            if (-not (Test-OtterUdp $udp)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only send to a host and port through a udp socket, but this is $(Get-OtterTypeName -Value $udp)." `
                    -Line $Statement.Line `
                    -Suggestion 'open udp on port 9000 and call it socket')
            }
            if ($udp.State -ne 'open') {
                throw (New-OtterRuntimeError -Message "I cannot send through a udp socket that is not open (its state is '$($udp.State)')." -Line $Statement.Line)
            }
            $data = Get-OtterValue -Expression $Statement.Data -Environment $Environment
            Assert-OtterNetBytes -Value $data -Line $Statement.Line -Where 'a udp socket'
            $hostVal = Get-OtterValue -Expression $Statement.HostExpr -Environment $Environment
            if ($hostVal -isnot [string] -or [string]::IsNullOrWhiteSpace($hostVal)) {
                throw (New-OtterRuntimeError -Message "I need text for the udp destination host, but this is $(Get-OtterTypeName -Value $hostVal)." -Line $Statement.Line)
            }
            $portNum = Get-OtterNetPort -Value (Get-OtterValue -Expression $Statement.Port -Environment $Environment) -Line $Statement.Line
            try {
                $address = $null
                if (-not [System.Net.IPAddress]::TryParse($hostVal, [ref]$address)) {
                    $address = [System.Net.Dns]::GetHostAddresses($hostVal) | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } | Select-Object -First 1
                }
                if ($null -eq $address) { throw "no IPv4 address found for '$hostVal'" }
                $bytes = [byte[]]$data.Value
                [void]$udp.Client.Send($bytes, $bytes.Length, [System.Net.IPEndPoint]::new($address, $portNum))
            } catch {
                throw (New-OtterRuntimeError `
                    -Message "I could not send the udp datagram to ${hostVal}:${portNum}: $($_.Exception.GetBaseException().Message)" `
                    -Line $Statement.Line)
            }
            return
        }

        # close tcp connection / close udp socket                       (D107, D108)
        'NetClose' {
            $net = Get-OtterValue -Expression $Statement.Socket -Environment $Environment
            $ok = if ($Statement.Protocol -eq 'tcp') { Test-OtterTcp $net } else { Test-OtterUdp $net }
            if (-not $ok) {
                $what = if ($Statement.Protocol -eq 'tcp') { 'a tcp connection' } else { 'a udp socket' }
                throw (New-OtterRuntimeError `
                    -Message "I can only close $what here, but this is $(Get-OtterTypeName -Value $net)." `
                    -Line $Statement.Line `
                    -Suggestion "close $($Statement.Protocol) <name>")
            }
            Close-OtterNetInternal -Socket $net
            return
        }

        # listen for tcp [on "127.0.0.1"] on port 8080 and call it server (D113)
        'TcpListen' {
            $addrVal = '127.0.0.1'
            if ($null -ne $Statement.AddressExpr) {
                $rawAddr = Get-OtterValue -Expression $Statement.AddressExpr -Environment $Environment
                if ($rawAddr -isnot [string] -or [string]::IsNullOrWhiteSpace($rawAddr)) {
                    throw (New-OtterRuntimeError `
                        -Message "I need text for a tcp bind address, but this is $(Get-OtterTypeName -Value $rawAddr)." `
                        -Line $Statement.Line `
                        -Suggestion 'listen for tcp on "127.0.0.1" on port 8080 and call it server')
                }
                $addrVal = $rawAddr.Trim()
            }
            $portVal = Get-OtterValue -Expression $Statement.Port -Environment $Environment
            $portNum = Get-OtterNetPort -Value $portVal -Line $Statement.Line -AllowZero

            $ip = $null
            if (-not [System.Net.IPAddress]::TryParse($addrVal, [ref]$ip)) {
                try {
                    $addrs = [System.Net.Dns]::GetHostAddresses($addrVal) | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork }
                    if ($addrs.Count -gt 0) {
                        $ip = $addrs[0]
                    }
                } catch {}
                if ($null -eq $ip) {
                    throw (New-OtterRuntimeError `
                        -Message "I could not resolve the bind address ""$addrVal""." `
                        -Line $Statement.Line)
                }
            }

            try {
                $listener = [System.Net.Sockets.TcpListener]::new($ip, $portNum)
                $listener.Start()
            } catch {
                throw (New-OtterRuntimeError `
                    -Message "I could not start a tcp server on ${addrVal} port ${portNum}: $($_.Exception.GetBaseException().Message)" `
                    -Line $Statement.Line)
            }

            $actualEp = $listener.LocalEndpoint -as [System.Net.IPEndPoint]
            $actualPort = $actualEp.Port
            $actualAddr = $actualEp.Address.ToString()

            $srv = [OtterTcpServer]::new($listener, $actualAddr, $actualPort)
            $script:OtterActiveTcpServers.Add($srv)
            $Environment.Set($Statement.Target, $srv)
            return
        }

        # stop tcp server                                              (D113)
        'TcpStop' {
            $srv = Get-OtterValue -Expression $Statement.Server -Environment $Environment
            if (-not (Test-OtterTcpServer $srv)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only stop a tcp server, but this is $(Get-OtterTypeName -Value $srv)." `
                    -Line $Statement.Line `
                    -Suggestion 'stop tcp server')
            }
            Stop-OtterTcpServerInternal -Server $srv
            return
        }

        # send "Hello" through socket                                  (D106)
        'WebSocketSend' {
            $ws = Get-OtterValue -Expression $Statement.Socket -Environment $Environment
            # D107: send bytes through a tcp connection (a stream, so bytes only).
            if (Test-OtterTcp $ws) {
                if ($ws.State -ne 'connected') {
                    throw (New-OtterRuntimeError `
                        -Message "I cannot send through a tcp connection that is not connected (its state is '$($ws.State)')." `
                        -Line $Statement.Line `
                        -Suggestion 'Send from inside "on connect of <connection>".')
                }
                $tcpData = Get-OtterValue -Expression $Statement.Message -Environment $Environment
                Assert-OtterNetBytes -Value $tcpData -Line $Statement.Line -Where 'a tcp connection'
                try {
                    $tcpBytes = [byte[]]$tcpData.Value
                    $tcpStream = $ws.Stream
                    $tcpStream.Write($tcpBytes, 0, $tcpBytes.Length)
                    $tcpStream.Flush()
                } catch {
                    $tcpMsg = "I could not send through the tcp connection: $($_.Exception.GetBaseException().Message)"
                    Close-OtterNetInternal -Socket $ws
                    throw (New-OtterRuntimeError -Message $tcpMsg -Line $Statement.Line)
                }
                return
            }
            if (Test-OtterUdp $ws) {
                throw (New-OtterRuntimeError `
                    -Message 'A udp send needs a destination.' `
                    -Line $Statement.Line `
                    -Suggestion 'send data through socket to "127.0.0.1" on port 9000')
            }
            if (-not (Test-OtterWebSocket $ws)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only send through a websocket, but this is $(Get-OtterTypeName -Value $ws)." `
                    -Line $Statement.Line `
                    -Suggestion 'send "Hello" through socket')
            }
            if ($ws.State -ne 'open') {
                throw (New-OtterRuntimeError `
                    -Message "I cannot send through a websocket that is not open (its state is '$($ws.State)')." `
                    -Line $Statement.Line `
                    -Suggestion "Wait for ""on open of $($Statement.Socket)"" before sending.")
            }

            $msg = Get-OtterValue -Expression $Statement.Message -Environment $Environment
            $bytes = $null
            $msgType = [System.Net.WebSockets.WebSocketMessageType]::Text
            if ($msg -is [string]) {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$msg)
                $msgType = [System.Net.WebSockets.WebSocketMessageType]::Text
            } elseif (Test-OtterBytes $msg) {
                $bytes = $msg.Value
                $msgType = [System.Net.WebSockets.WebSocketMessageType]::Binary
            } else {
                throw (New-OtterRuntimeError `
                    -Message "I can only send text or bytes through a websocket, but this is $(Get-OtterTypeName -Value $msg)." `
                    -Line $Statement.Line `
                    -Suggestion 'send "Hello" through socket')
            }

            try {
                $segment = [System.ArraySegment[byte]]::new($bytes)
                $sendTask = $ws.Native.SendAsync($segment, $msgType, $true, $ws.Cts.Token)
                $sendTask.Wait()
            } catch {
                throw (New-OtterRuntimeError `
                    -Message "Failed to send through websocket: $($_.Exception.GetBaseException().Message)" `
                    -Line $Statement.Line)
            }
            return
        }

        # close websocket socket [with code 1000] [and reason "Done"]  (D106)
        'WebSocketClose' {
            $ws = Get-OtterValue -Expression $Statement.Socket -Environment $Environment
            if (-not (Test-OtterWebSocket $ws)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only close a websocket, but this is $(Get-OtterTypeName -Value $ws)." `
                    -Line $Statement.Line `
                    -Suggestion 'close websocket socket')
            }
            $code = 1000
            if ($null -ne $Statement.Code) {
                $cVal = Get-OtterValue -Expression $Statement.Code -Environment $Environment
                if (-not (Test-OtterNumeric $cVal)) {
                    throw (New-OtterRuntimeError `
                        -Message "I need a number for a close code, but this is $(Get-OtterTypeName -Value $cVal)." `
                        -Line $Statement.Line)
                }
                $code = [int](ConvertTo-OtterNumber $cVal)
            }
            $reason = ''
            if ($null -ne $Statement.Reason) {
                $rVal = Get-OtterValue -Expression $Statement.Reason -Environment $Environment
                if ($rVal -isnot [string]) {
                    throw (New-OtterRuntimeError `
                        -Message "I need text for a close reason, but this is $(Get-OtterTypeName -Value $rVal)." `
                        -Line $Statement.Line)
                }
                $reason = [string]$rVal
            }

            if ($ws.State -in @('connecting', 'open')) {
                $ws.State = 'closing'
                $ws.CloseCode = $code
                $ws.CloseReason = $reason
                $ws.CloseWasClean = ($code -eq 1000)
                try {
                    $status = [System.Net.WebSockets.WebSocketCloseStatus]$code
                    $closeTask = $ws.Native.CloseOutputAsync($status, $reason, $ws.Cts.Token)
                } catch {
                    $ws.State = 'closed'
                }
            }
            return
        }

        # on open/message/close/error of socket                        (D106)
        # on connect of / on data from                                 (D107, D108)
        # on connection to                                             (D113)
        'WebSocketEvent' {
            $ws = Get-OtterValue -Expression $Statement.Socket -Environment $Environment
            if (Test-OtterCommandJob $ws) {
                $evtKindStr = $Statement.EventKind.ToString()
                $evtName = switch ($evtKindStr) {
                    'Complete' { 'complete' }
                    'Cancel'   { 'cancel' }
                    'Error'    { 'error' }
                    default    { $null }
                }
                if ($null -eq $evtName) {
                    throw (New-OtterRuntimeError `
                        -Message "A command job only supports ""on complete of"" or ""on cancel of""." `
                        -Line $Statement.Line)
                }
                $handler = @{
                    EventName = $evtName
                    Body = $Statement.Body
                    Environment = $Environment
                    Fired = $false
                }
                [System.Threading.Monitor]::Enter($ws.LockObj)
                try {
                    $ws.Handlers.Add($handler)
                } finally {
                    [System.Threading.Monitor]::Exit($ws.LockObj)
                }

                # Retained terminal event delivery
                if ($null -ne $ws.RetainedTerminalEvent -and ($ws.RetainedTerminalEvent.EventKind -eq $evtName -or ($evtName -eq 'complete' -and $ws.RetainedTerminalEvent.EventKind -eq 'exit'))) {
                    $handler.Fired = $true
                    $prevContext = $script:OtterCurrentJobContext
                    $script:OtterCurrentJobContext = $ws.RetainedTerminalEvent.Context
                    try {
                        Invoke-OtterStatements -Statements $Statement.Body -Environment $Environment
                    } finally {
                        $script:OtterCurrentJobContext = $prevContext
                    }
                }
                return
            }
            if (Test-OtterHttpRequest $ws) {
                $evtKindStr = $Statement.EventKind.ToString()
                if ($evtKindStr -notin @('Complete', 'Error', 'Cancel')) {
                    throw (New-OtterRuntimeError `
                        -Message "An http request only supports ""on complete of"", ""on error of"", or ""on cancel of""." `
                        -Line $Statement.Line)
                }
                if (-not $script:OtterWebSocketHandlers.ContainsKey($ws)) {
                    $script:OtterWebSocketHandlers[$ws] = [System.Collections.Generic.List[hashtable]]::new()
                }
                $handler = @{ EventKind = $Statement.EventKind; Body = $Statement.Body; Environment = $Environment; Fired = $false }
                $script:OtterWebSocketHandlers[$ws].Add($handler)

                # D116B Section 30: Retained terminal event delivery
                if ($null -ne $ws.RetainedTerminalEvent -and $ws.RetainedTerminalEvent.EventKind.ToString() -eq $evtKindStr) {
                    $handler.Fired = $true
                    $prevContext = $script:OtterCurrentWsContext
                    $script:OtterCurrentWsContext = $ws.RetainedTerminalEvent.Context
                    try {
                        Invoke-OtterStatements -Statements $Statement.Body -Environment $Environment
                    } finally {
                        $script:OtterCurrentWsContext = $prevContext
                    }
                }
                return
            }
            if (-not ((Test-OtterWebSocket $ws) -or (Test-OtterTcp $ws) -or (Test-OtterUdp $ws) -or (Test-OtterTcpServer $ws))) {
                throw (New-OtterRuntimeError `
                    -Message "I can only listen for a network event on a websocket, tcp connection, tcp server, udp socket, http request or command job, but this is $(Get-OtterTypeName -Value $ws)." `
                    -Line $Statement.Line)
            }
            if (Test-OtterTcpServer $ws) {
                if ($Statement.EventKind.ToString() -notin @('Connection', 'Error')) {
                    throw (New-OtterRuntimeError `
                        -Message "A tcp server only supports ""on connection to"" or ""on error of""." `
                        -Line $Statement.Line)
                }
            } elseif ($Statement.EventKind.ToString() -eq 'Connection') {
                throw (New-OtterRuntimeError `
                    -Message """on connection to"" is only valid for a tcp server, but this is $(Get-OtterTypeName -Value $ws)." `
                    -Line $Statement.Line)
            }
            if (-not $script:OtterWebSocketHandlers.ContainsKey($ws)) {
                $script:OtterWebSocketHandlers[$ws] = [System.Collections.Generic.List[hashtable]]::new()
            }
            $script:OtterWebSocketHandlers[$ws].Add(@{ EventKind = $Statement.EventKind; Body = $Statement.Body; Environment = $Environment })
            return
        }

        # write xml document to file "books.xml"                       (D105)
        'XmlWriteFile' {
            $xml = Get-OtterValue -Expression $Statement.Xml -Environment $Environment
            if (-not (Test-OtterXml $xml)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only write xml, but this is $(Get-OtterTypeName -Value $xml)." `
                    -Line $Statement.Line)
            }
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            Write-OtterFile -Path $path -Content $xml.Node.OuterXml -Line $Statement.Line -Atomic $false
            return
        }

        # add element "book" to library [and call it book] [with text "..."]  (D105)
        'XmlAddElement' {
            $name = Get-OtterText -Expression $Statement.Name -Environment $Environment
            $xml = Get-OtterValue -Expression $Statement.Xml -Environment $Environment
            if (-not (Test-OtterXml $xml)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only add an element to xml, but this is $(Get-OtterTypeName -Value $xml)." `
                    -Line $Statement.Line)
            }
            $ownerDoc = if ($xml.Node -is [System.Xml.XmlDocument]) { $xml.Node } else { $xml.Node.OwnerDocument }
            $newElem = $ownerDoc.CreateElement($name)
            if ($null -ne $Statement.Text) {
                $newElem.InnerText = Get-OtterText -Expression $Statement.Text -Environment $Environment
            }
            # Appending to a whole DOCUMENT targets/creates its
            # DocumentElement - matches `xml with root "library"` +
            # `add element "book" to library` needing no special-casing
            # by the caller.
            $parentNode = $xml.Node
            if ($xml.Node -is [System.Xml.XmlDocument]) {
                $parentNode = if ($null -eq $xml.Node.DocumentElement) { $xml.Node } else { $xml.Node.DocumentElement }
            }
            [void]$parentNode.AppendChild($newElem)
            if ($Statement.Target) {
                $Environment.Set($Statement.Target, [OtterXml]::new($newElem))
            }
            return
        }

        # remove element book                                          (D105)
        'XmlRemoveElement' {
            $elem = Get-OtterValue -Expression $Statement.Element -Environment $Environment
            if (-not (Test-OtterXml $elem)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only remove an xml element, but this is $(Get-OtterTypeName -Value $elem)." `
                    -Line $Statement.Line)
            }
            Assert-OtterXmlElement -Xml $elem -Line $Statement.Line -What 'remove'
            if ($null -eq $elem.Node.ParentNode) {
                throw (New-OtterRuntimeError `
                    -Message 'This element has no parent to remove it from.' `
                    -Line $Statement.Line)
            }
            [void]$elem.Node.ParentNode.RemoveChild($elem.Node)
            return
        }

        # set text of book to "..."  /  set text of "title" in document to "..."  (D105)
        'XmlSetText' {
            $value = Get-OtterText -Expression $Statement.Value -Environment $Environment
            if ($null -ne $Statement.Element) {
                $elem = Get-OtterValue -Expression $Statement.Element -Environment $Environment
                if (-not (Test-OtterXml $elem)) {
                    throw (New-OtterRuntimeError `
                        -Message "I can only set the text of an xml element, but this is $(Get-OtterTypeName -Value $elem)." `
                        -Line $Statement.Line)
                }
                Assert-OtterXmlElement -Xml $elem -Line $Statement.Line -What 'set the text of'
                $elem.Node.InnerText = $value
                return
            }
            $name = Get-OtterText -Expression $Statement.NameIn -Environment $Environment
            $xmlIn = Get-OtterValue -Expression $Statement.XmlIn -Environment $Environment
            if (-not (Test-OtterXml $xmlIn)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only set text within xml, but this is $(Get-OtterTypeName -Value $xmlIn)." `
                    -Line $Statement.Line)
            }
            $found = Find-OtterXmlChildElementsByName -Node $xmlIn.Node -Name $name
            if ($found.Count -eq 0) {
                throw (New-OtterRuntimeError `
                    -Message "I couldn't find an element called ""$name"" to set the text of." `
                    -Line $Statement.Line)
            }
            $found[0].InnerText = $value
            return
        }

        # set attribute "id" of book to "42"                            (D105)
        'XmlSetAttribute' {
            $name = Get-OtterText -Expression $Statement.Name -Environment $Environment
            $elem = Get-OtterValue -Expression $Statement.Element -Environment $Environment
            if (-not (Test-OtterXml $elem)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only set an attribute of an xml element, but this is $(Get-OtterTypeName -Value $elem)." `
                    -Line $Statement.Line)
            }
            Assert-OtterXmlElement -Xml $elem -Line $Statement.Line -What 'set an attribute of'
            $value = Get-OtterText -Expression $Statement.Value -Environment $Environment
            $elem.Node.SetAttribute($name, $value)
            return
        }

        # remove attribute "id" from book                               (D105)
        'XmlRemoveAttribute' {
            $name = Get-OtterText -Expression $Statement.Name -Environment $Environment
            $elem = Get-OtterValue -Expression $Statement.Element -Environment $Environment
            if (-not (Test-OtterXml $elem)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only remove an attribute of an xml element, but this is $(Get-OtterTypeName -Value $elem)." `
                    -Line $Statement.Line)
            }
            Assert-OtterXmlElement -Xml $elem -Line $Statement.Line -What 'remove an attribute of'
            $elem.Node.RemoveAttribute($name)
            return
        }

        # run "notepad.exe"  /  run command "git status" into result
        'RunProgram' {
            $target = Get-OtterText -Expression $Statement.Target -Environment $Environment

            if (-not $Statement.IsCommand) {
                # D70: `into p` used to be silently dropped here - it parsed
                # fine (RunStmt.ResultTarget was always populated by the
                # parser) but this branch returned before ever setting it,
                # leaving `p` undefined. Start-OtterProgram now hands back a
                # real process handle (id, name) for kill/details later.
                $handle = Start-OtterProgram -Target $target -Line $Statement.Line
                if ($Statement.ResultTarget) {
                    $Environment.Set($Statement.ResultTarget, $handle)
                }
                return
            }

            $output = Invoke-OtterCommand -CommandLine $target -Line $Statement.Line
            if ($Statement.ResultTarget) {
                $Environment.Set($Statement.ResultTarget, $output)
            }
            return
        }

        # start command <cmd> and call it <target>                      (D119-R2)
        'StartCommand' {
            $cmd = Get-OtterValue -Expression $Statement.CommandLine -Environment $Environment
            if ($cmd -isnot [string]) {
                throw (New-OtterRuntimeError `
                    -Message "I need text for a command line to start, but this is $(Get-OtterTypeName -Value $cmd)." `
                    -Line $Statement.Line)
            }
            $job = Start-OtterCommandJob -CommandLine $cmd -Line $Statement.Line
            $script:OtterActiveCommandJobs.Add($job)
            $Environment.Set($Statement.Target, $job)
            return
        }

        # get processes into list                                        (D70)
        'GetProcesses' {
            $list = Get-OtterProcessList
            $Environment.Set($Statement.Target, $list)
            return
        }

        # kill process p            / kill process p and its children    (D70)
        'KillProcess' {
            $processValue = Get-OtterValue -Expression $Statement.ProcessExpr -Environment $Environment
            if (-not (Test-OtterObject $processValue) -or -not ($processValue.HasProperty('id'))) {
                throw (New-OtterRuntimeError `
                    -Message 'I can only kill a real process handle, such as the one "run ... into p" or "get processes into list" gives you.' `
                    -Line $Statement.Line)
            }
            Stop-OtterProcess -ProcessId $processValue.ReadProperty('id') -IncludeChildren $Statement.IncludeChildren -Line $Statement.Line
            return
        }

        # set priority of process p to "high"                            (D71)
        'SetProcessPriority' {
            $processValue = Get-OtterValue -Expression $Statement.ProcessExpr -Environment $Environment
            if (-not (Test-OtterObject $processValue) -or -not ($processValue.HasProperty('id'))) {
                throw (New-OtterRuntimeError `
                    -Message 'I can only set the priority of a real process handle, such as the one "run ... into p" or "get processes into list" gives you.' `
                    -Line $Statement.Line)
            }
            $priorityText = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Priority -Environment $Environment)
            Set-OtterProcessPriority -ProcessId $processValue.ReadProperty('id') -Priority $priorityText -Line $Statement.Line
            return
        }

        # wait for process p up to 5 seconds [into finished]             (D71)
        'WaitForProcess' {
            $processValue = Get-OtterValue -Expression $Statement.ProcessExpr -Environment $Environment
            if (-not (Test-OtterObject $processValue) -or -not ($processValue.HasProperty('id'))) {
                throw (New-OtterRuntimeError `
                    -Message 'I can only wait for a real process handle, such as the one "run ... into p" or "get processes into list" gives you.' `
                    -Line $Statement.Line)
            }
            $seconds = Assert-OtterNumber -Value (Get-OtterValue -Expression $Statement.TimeoutSeconds -Environment $Environment) -Line $Statement.Line -What 'a number of seconds'
            $finished = Wait-OtterProcess -ProcessId $processValue.ReadProperty('id') -TimeoutSeconds $seconds
            if ($Statement.Target) {
                $Environment.Set($Statement.Target, $finished)
            }
            return
        }

        # --- discovery and folders (D20, D21) -------------------

        # get files in "Pictures" [and subfolders] into files
        'GetFiles' {
            $folder = Get-OtterPathArgument -Expression $Statement.Folder -Environment $Environment
            $files = Get-OtterFilesIn -Path $folder -IncludeSubfolders $Statement.IncludeSubfolders -Line $Statement.Line
            $Environment.Set($Statement.Target, $files)
            return
        }

        # get folders in "Documents" [and subfolders] into folders
        'GetFolders' {
            $folder = Get-OtterPathArgument -Expression $Statement.Folder -Environment $Environment
            $folders = Get-OtterFoldersIn -Path $folder -IncludeSubfolders $Statement.IncludeSubfolders -Line $Statement.Line
            $Environment.Set($Statement.Target, $folders)
            return
        }

        'CreateFolder' {
            New-OtterFolder -Path (Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment) -Line $Statement.Line
            return
        }

        # create symbolic link "l" pointing to "t"                     (D73)
        'CreateSymbolicLink' {
            $linkPath = Get-OtterPathArgument -Expression $Statement.LinkPath -Environment $Environment
            $targetPath = Get-OtterPathArgument -Expression $Statement.TargetPath -Environment $Environment
            New-OtterSymbolicLink -LinkPath $linkPath -TargetPath $targetPath -Line $Statement.Line
            return
        }

        # get symbolic link target of "l" into t                       (D73)
        'GetSymbolicLinkTarget' {
            $linkPath = Get-OtterPathArgument -Expression $Statement.LinkPath -Environment $Environment
            $target = Get-OtterSymbolicLinkTarget -LinkPath $linkPath -Line $Statement.Line
            $Environment.Set($Statement.Target, $target)
            return
        }

        # get owner of "x" into owner                                    (D74)
        'GetFileOwner' {
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            $owner = Get-OtterFileOwner -Path $path -Line $Statement.Line
            $Environment.Set($Statement.Target, $owner)
            return
        }

        # set file "x" to read only / to writable                        (D74)
        'SetFileReadOnly' {
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            Set-OtterFileReadOnly -Path $path -ReadOnly $Statement.ReadOnly -Line $Statement.Line
            return
        }

        # get registry value "n" from "path" into t                     (D78)
        'GetRegistryValue' {
            $valueName = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.ValueName -Environment $Environment)
            $keyPath = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.KeyPath -Environment $Environment)
            $value = Get-OtterRegistryValue -ValueName $valueName -KeyPath $keyPath -Line $Statement.Line
            $Environment.Set($Statement.Target, $value)
            return
        }

        # set registry value "n" to "d" in "path"                       (D78)
        'SetRegistryValue' {
            $valueName = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.ValueName -Environment $Environment)
            $value = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Value -Environment $Environment)
            $keyPath = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.KeyPath -Environment $Environment)
            Set-OtterRegistryValue -ValueName $valueName -Value $value -KeyPath $keyPath -Line $Statement.Line
            return
        }

        # delete registry value "n" from "path"                         (D78)
        'DeleteRegistryValue' {
            $valueName = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.ValueName -Environment $Environment)
            $keyPath = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.KeyPath -Environment $Environment)
            Remove-OtterRegistryValue -ValueName $valueName -KeyPath $keyPath -Line $Statement.Line
            return
        }

        # get event log entries from "System" up to 20 into entries      (D79)
        'GetEventLogEntries' {
            $logName = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.LogName -Environment $Environment)
            $maxEntries = Assert-OtterNumber -Value (Get-OtterValue -Expression $Statement.MaxEntries -Environment $Environment) -Line $Statement.Line -What 'a maximum number of entries'
            $entries = Get-OtterEventLogEntries -LogName $logName -MaxEntries $maxEntries -Line $Statement.Line
            $Environment.Set($Statement.Target, $entries)
            return
        }

        # set credential "n" to "secret"                                 (D81)
        'SetCredential' {
            $name = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Name -Environment $Environment)
            $secret = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Secret -Environment $Environment)
            Set-OtterCredential -Name $name -Secret $secret -Line $Statement.Line
            return
        }

        # get credential "n" into secret                                 (D81)
        'GetCredential' {
            $name = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Name -Environment $Environment)
            $secret = Get-OtterCredential -Name $name -Line $Statement.Line
            $Environment.Set($Statement.Target, $secret)
            return
        }

        # delete credential "n"                                          (D81)
        'DeleteCredential' {
            $name = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Name -Environment $Environment)
            Remove-OtterCredential -Name $name -Line $Statement.Line
            return
        }

        # lock the computer / sign out / restart the computer /          (D82)
        # shut down the computer
        'PowerAction' {
            Invoke-OtterPowerAction -Action $Statement.Action -Line $Statement.Line
            return
        }

        # print "file.txt" to "PrinterName"                              (D83)
        'PrintFile' {
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            $printerName = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.PrinterName -Environment $Environment)
            Send-OtterFileToPrinter -Path $path -PrinterName $printerName -Line $Statement.Line
            return
        }

        # zip folder "src" into "archive.zip"                            (D87)
        'ZipFolder' {
            $source = Get-OtterPathArgument -Expression $Statement.SourceFolder -Environment $Environment
            $archive = Get-OtterPathArgument -Expression $Statement.ArchivePath -Environment $Environment
            New-OtterZipArchive -SourceFolder $source -ArchivePath $archive -Line $Statement.Line
            return
        }

        # unzip "archive.zip" into "dest"                                (D87)
        'UnzipFile' {
            $archive = Get-OtterPathArgument -Expression $Statement.ArchivePath -Environment $Environment
            $dest = Get-OtterPathArgument -Expression $Statement.DestinationFolder -Environment $Environment
            Expand-OtterZipArchive -ArchivePath $archive -DestinationFolder $dest -Line $Statement.Line
            return
        }

        # hash "text" as "sha256" [with key "secret"] into digest        (D91)
        'HashText' {
            $text = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Text -Environment $Environment)
            $algorithm = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Algorithm -Environment $Environment)
            $key = $null
            if ($null -ne $Statement.Key) {
                $key = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Key -Environment $Environment)
            }
            $digest = Get-OtterHash -Text $text -Algorithm $algorithm -Key $key -Line $Statement.Line
            $Environment.Set($Statement.ResultTarget, $digest)
            return
        }

        # encrypt "text" with key "secret" into cipher                    (D92)
        'EncryptText' {
            $text = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Text -Environment $Environment)
            $key = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Key -Environment $Environment)
            $cipher = Protect-OtterText -Text $text -Key $key -Line $Statement.Line
            $Environment.Set($Statement.ResultTarget, $cipher)
            return
        }

        # decrypt "cipher" with key "secret" into text                    (D92)
        'DecryptText' {
            $cipherText = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.CipherText -Environment $Environment)
            $key = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Key -Environment $Environment)
            $plain = Unprotect-OtterText -CipherText $cipherText -Key $key -Line $Statement.Line
            $Environment.Set($Statement.ResultTarget, $plain)
            return
        }

        # run command "..." on remote "host" using credential "n"        (D84)
        # [into result]
        'RunRemoteCommand' {
            $command = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Command -Environment $Environment)
            $hostName = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.HostName -Environment $Environment)
            $credentialName = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.CredentialName -Environment $Environment)
            $output = Invoke-OtterRemoteCommand -Command $command -HostName $hostName -CredentialName $credentialName -Line $Statement.Line
            if ($Statement.ResultTarget) {
                $Environment.Set($Statement.ResultTarget, $output)
            }
            return
        }

        # run command "..." over ssh to "user@host" [into result]        (D85)
        'RunSshCommand' {
            $command = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Command -Environment $Environment)
            $hostName = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.HostName -Environment $Environment)
            $output = Invoke-OtterSshCommand -Command $command -HostName $hostName -Line $Statement.Line
            if ($Statement.ResultTarget) {
                $Environment.Set($Statement.ResultTarget, $output)
            }
            return
        }

        'DeleteFolder' {
            Remove-OtterFolder -Path (Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment) -Line $Statement.Line
            return
        }

        'CopyFolder' {
            $source = Get-OtterPathArgument -Expression $Statement.Source -Environment $Environment
            $destination = Get-OtterPathArgument -Expression $Statement.Destination -Environment $Environment
            Copy-OtterFolder -Source $source -Destination $destination -Line $Statement.Line
            return
        }

        'MoveFolder' {
            $source = Get-OtterPathArgument -Expression $Statement.Source -Environment $Environment
            $destination = Get-OtterPathArgument -Expression $Statement.Destination -Environment $Environment
            Move-OtterFolder -Source $source -Destination $destination -Line $Statement.Line
            return
        }

        # --- system integration (D67) ---------------------------

        # copy "text" to clipboard
        'CopyToClipboard' {
            $text = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Text -Environment $Environment)
            Set-Clipboard -Value $text
            return
        }

        # get clipboard into text          - gone if the clipboard holds no text
        'GetClipboard' {
            $value = $null
            try { $value = Get-Clipboard -Raw -ErrorAction Stop } catch { $value = $null }
            $Environment.Set($Statement.Target, $value)
            return
        }

        # notify "Title" with "Message"    - a real OS toast, not a fake one
        'Notify' {
            $title = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Title -Environment $Environment)
            $message = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Message -Environment $Environment)
            Show-OtterNotification -Title $title -Message $message
            return
        }

        # get environment variable "PATH" into value      - gone if not set
        'GetEnvironmentVariable' {
            $name = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Name -Environment $Environment)
            $value = [System.Environment]::GetEnvironmentVariable($name)
            $Environment.Set($Statement.Target, $value)
            return
        }

        # set environment variable "NAME" to "VALUE"                    (D94)
        'SetEnvironmentVariable' {
            $name = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Name -Environment $Environment)
            $val = Get-OtterValue -Expression $Statement.Value -Environment $Environment
            $value = if ($null -eq $val) { $null } else { Format-OtterValue -Value $val }
            [System.Environment]::SetEnvironmentVariable($name, $value)
            return
        }

        # get system folder "temp" into path
        'GetSystemFolder' {
            $folderName = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.FolderName -Environment $Environment)
            $path = switch ($folderName.ToLowerInvariant()) {
                'temp' { [System.IO.Path]::GetTempPath() }
                'appdata' { [System.Environment]::GetFolderPath('ApplicationData') }
                'user' { [System.Environment]::GetFolderPath('UserProfile') }
                'current' { (Get-Location).Path }
                default {
                    throw (New-OtterRuntimeError `
                        -Message "I do not know a system folder called ""$folderName""." `
                        -Line $Statement.Line `
                        -Suggestion 'get system folder "temp" into path (also: "appdata", "user", "current")')
                }
            }
            $Environment.Set($Statement.Target, $path)
            return
        }

        # set current directory to "Projects"                           (D94)
        'SetCurrentDirectory' {
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                throw (New-OtterRuntimeError `
                    -Message "I cannot find a folder called ""$path""." `
                    -Line $Statement.Line `
                    -Suggestion 'set current directory to "path/to/folder"')
            }
            $resolved = (Resolve-Path -LiteralPath $path).Path
            [System.IO.Directory]::SetCurrentDirectory($resolved)
            Set-Location -LiteralPath $resolved
            return
        }

        # get system information "os" into info                          (D69)
        'GetSystemInfo' {
            $infoKind = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.InfoKind -Environment $Environment)
            $value = Get-OtterSystemInfoValue -Kind $infoKind -Line $Statement.Line
            $Environment.Set($Statement.Target, $value)
            return
        }

        # choose file into path            - gone if the user cancels
        'ChooseFile' {
            $path = Show-OtterFileDialog -Mode 'OpenFile'
            $Environment.Set($Statement.Target, $path)
            return
        }

        # choose folder into path          - gone if the user cancels
        'ChooseFolder' {
            $path = Show-OtterFileDialog -Mode 'Folder'
            $Environment.Set($Statement.Target, $path)
            return
        }

        # choose file to save into path    - gone if the user cancels
        'ChooseSaveFile' {
            $path = Show-OtterFileDialog -Mode 'SaveFile'
            $Environment.Set($Statement.Target, $path)
            return
        }

        # --- try / otherwise (D23) ------------------------------
        #
        #     try
        #         read "settings.json" into settings
        #     otherwise
        #         say "Could not load settings."
        #     .
        'Try' {
            try {
                Invoke-OtterStatements -Statements $Statement.Body -Environment $Environment
            }
            catch {
                # "return" is control flow wearing an exception, not a failure.
                # It must pass straight through a try, or returning from inside
                # one would silently run the otherwise body instead.
                if ($_.Exception -is [OtterReturnSignal]) { throw }

                # D68: `otherwise into reason` - binds the caught failure's
                # message text for ANY caught error, not just `fail`-raised
                # ones, before running the otherwise body.
                if ($Statement.ErrorTarget) {
                    $Environment.Set($Statement.ErrorTarget, $_.Exception.Message)
                }

                if ($null -ne $Statement.OtherwiseBody) {
                    Invoke-OtterStatements -Statements $Statement.OtherwiseBody -Environment $Environment
                }
            }
            return
        }

        # fail with "message"                                            (D68)
        # A real, user-raised custom error. Reuses the same OtterError
        # machinery as every built-in runtime error, so a hand-authored
        # failure is caught by an ordinary `try` exactly like a built-in one.
        'Fail' {
            $message = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Message -Environment $Environment)
            throw (New-OtterRuntimeError -Message $message -Line $Statement.Line)
        }

        # --- collections and strings (D25) ----------------------

        # sort games   /   reverse games   - change the list in place
        'Sort' {
            $list = Get-OtterMutableList -Name $Statement.Target -Environment $Environment -Line $Statement.Line -Verb 'sort'
            $items = $list.ToArray()
            $comparison = [System.Comparison[object]] {
                param($left, $right)
                if ((Test-OtterNumeric $left) -and (Test-OtterNumeric $right)) {
                    $l = [double](ConvertTo-OtterNumber $left)
                    $r = [double](ConvertTo-OtterNumber $right)
                    return $l.CompareTo($r)
                }
                return [string]::CompareOrdinal(
                    (Format-OtterValue -Value $left),
                    (Format-OtterValue -Value $right))
            }
            [System.Array]::Sort($items, $comparison)
            $list.Clear()
            foreach ($item in $items) { $list.Add($item) }
            return
        }

        'Reverse' {
            $list = Get-OtterMutableList -Name $Statement.Target -Environment $Environment -Line $Statement.Line -Verb 'reverse'
            $list.Reverse()
            return
        }

        # replace "Jeff" with "Jeffrey" in name
        'Replace' {
            if (-not $Environment.Has($Statement.Target)) {
                throw (New-OtterRuntimeError -Message "Otter could not find the variable ""$($Statement.Target)""." -Line $Statement.Line)
            }
            $subject = Format-OtterValue -Value $Environment.Get($Statement.Target)
            $find = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Find -Environment $Environment)
            $replacement = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Replacement -Environment $Environment)

            if ($find.Length -eq 0) {
                throw (New-OtterRuntimeError -Message 'I cannot replace empty text.' -Line $Statement.Line)
            }
            # Plain text replace - no regular expressions, so "." in the text
            # the programmer typed means a full stop and nothing else.
            $result = $subject.Replace($find, $replacement)

            # D27: with a destination, the source is left exactly as it was.
            if ($Statement.ResultTarget) {
                $Environment.Set($Statement.ResultTarget, $result)
                return
            }
            $Environment.Set($Statement.Target, $result)
            return
        }

        # split sentence by " " into words
        'Split' {
            $subject = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Subject -Environment $Environment)
            $separator = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Separator -Environment $Environment)

            if ($separator.Length -eq 0) {
                throw (New-OtterRuntimeError -Message 'I need something to split by.' -Line $Statement.Line)
            }
            $pieces = $subject.Split([string[]]@($separator), [System.StringSplitOptions]::None)
            $Environment.Set($Statement.Target, (New-OtterList -Items $pieces))
            return
        }

        # join words with ", " into text
        'Join' {
            $value = Get-OtterValue -Expression $Statement.Subject -Environment $Environment
            if (-not (Test-OtterList $value)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only join a list, but this is $(Get-OtterTypeName $value)." `
                    -Line $Statement.Line)
            }
            $separator = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Separator -Environment $Environment)
            $rendered = foreach ($item in $value) { Format-OtterValue -Value $item }
            $Environment.Set($Statement.Target, (($rendered) -join $separator))
            return
        }

        # find file in files where extension of file is ".pdf" into result
        #
        # D26: singular "find" gives the FIRST match, or gone. That is what
        # makes "if result is gone" the natural way to ask if anything matched.
        'Find' {
            $collection = Get-OtterValue -Expression $Statement.Collection -Environment $Environment
            if (-not (Test-OtterList $collection)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only search a list, but this is $(Get-OtterTypeName $collection)." `
                    -Line $Statement.Line)
            }

            $found = $null
            foreach ($item in $collection.ToArray()) {
                # The item name is bound for the condition only, exactly like
                # a for-each variable.
                $scope = [OtterEnvironment]::new($Environment)
                $scope.SetLocal($Statement.ItemName, $item)
                if (Test-OtterTruthy -Value (Get-OtterValue -Expression $Statement.Condition -Environment $scope)) {
                    $found = $item
                    break
                }
            }

            $Environment.Set($Statement.Target, $found)
            return
        }

        # --- json (D29) -----------------------------------------

        # read json from "settings.json" into settings
        'ReadJson' {
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            $value = Read-OtterJsonFile -Path $path -Line $Statement.Line
            $Environment.Set($Statement.Target, $value)
            return
        }

        # convert user to json into text
        'ConvertToJson' {
            $subject = Get-OtterValue -Expression $Statement.Subject -Environment $Environment
            $Environment.Set($Statement.Target, (ConvertTo-OtterJsonText -Value $subject -Line $Statement.Line))
            return
        }

        # convert text from json into user
        'ConvertFromJson' {
            $text = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Subject -Environment $Environment)
            $value = ConvertFrom-OtterJsonText -Text $text -Line $Statement.Line
            $Environment.Set($Statement.Target, $value)
            return
        }

        # --- csv (D95) ------------------------------------------

        # read csv from "customers.csv" into customers
        'ReadCsv' {
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            $value = Read-OtterCsvFile -Path $path -Line $Statement.Line
            $Environment.Set($Statement.Target, $value)
            return
        }

        # write csv customers to "export.csv"
        'WriteCsv' {
            $rows = Get-OtterValue -Expression $Statement.Rows -Environment $Environment
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            Write-OtterCsvFile -Rows $rows -Path $path -Line $Statement.Line
            return
        }

        # convert customers to csv into text
        'ConvertToCsv' {
            $subject = Get-OtterValue -Expression $Statement.Subject -Environment $Environment
            $text = ConvertTo-OtterCsvText -Rows $subject -Line $Statement.Line
            $Environment.Set($Statement.Target, $text)
            return
        }

        # convert text from csv into customers
        'ConvertFromCsv' {
            $text = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Subject -Environment $Environment)
            $value = ConvertFrom-OtterCsvText -Text $text -Line $Statement.Line
            $Environment.Set($Statement.Target, $value)
            return
        }

        # --- random (D30) ---------------------------------------

        # random number from 1 to 10 into number    - both ends included
        'RandomNumber' {
            $fromRaw = Get-OtterValue -Expression $Statement.From -Environment $Environment
            $toRaw = Get-OtterValue -Expression $Statement.To -Environment $Environment
            $from = Assert-OtterNumber -Value $fromRaw -Line $Statement.Line -What 'the lowest number'
            $to = Assert-OtterNumber -Value $toRaw -Line $Statement.Line -What 'the highest number'

            if ($from -gt $to) {
                $swap = $from; $from = $to; $to = $swap
            }
            # Get-Random -Maximum is exclusive, so add one to include the top.
            $picked = Get-Random -Minimum ([int][Math]::Floor($from)) -Maximum (([int][Math]::Floor($to)) + 1)
            $Environment.Set($Statement.Target, [double]$picked)
            return
        }

        # random item from games into game     - gone when the list is empty
        'RandomItem' {
            $collection = Get-OtterValue -Expression $Statement.Collection -Environment $Environment
            if (-not (Test-OtterList $collection)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only pick from a list, but this is $(Get-OtterTypeName $collection)." `
                    -Line $Statement.Line)
            }

            if ($collection.Count -eq 0) {
                $Environment.Set($Statement.Target, $null)
                return
            }

            $index = Get-Random -Minimum 0 -Maximum $collection.Count
            $Environment.Set($Statement.Target, $collection[$index])
            return
        }

        # --- diagnostics (D31) ----------------------------------

        # log "Server started."  /  warn "..."  /  error "..."
        'Diagnostic' {
            $rendered = @()
            foreach ($part in $Statement.Parts) {
                $rendered += (Format-OtterValue -Value (Get-OtterValue -Expression $part -Environment $Environment))
            }
            $label = switch ($Statement.Level.ToString()) {
                'Warning' { 'warn' }
                'Problem' { 'error' }
                default { 'log' }
            }
            Write-OtterDiagnostic -Level $label -Text ($rendered -join ' ')
            return
        }

        # --- dates and time (D32) -------------------------------

        # add 7 days to date   /   remove 1 month from date
        'DateAdjust' {
            $name = $Statement.Target
            if (-not $Environment.Has($name)) {
                throw (New-OtterRuntimeError -Message "Otter could not find the variable ""$name""." -Line $Statement.Line)
            }

            $current = $Environment.Get($name)
            if (-not (Test-OtterDate $current)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only add time to a date, but ""$name"" holds $(Get-OtterTypeName $current)." `
                    -Line $Statement.Line)
            }

            $amountRaw = Get-OtterValue -Expression $Statement.Amount -Environment $Environment
            $amount = Assert-OtterNumber -Value $amountRaw -Line $Statement.Line -What 'the amount of time'
            $whole = [int][Math]::Truncate($amount)
            if ($Statement.IsRemoval) { $whole = -$whole }

            $unit = $Statement.Unit.ToString()
            Assert-OtterUnitAllowed -Value $current -Unit $unit -Line $Statement.Line

            # Adjusting REPLACES the value rather than mutating in place, so
            # two variables holding the same date never move together.
            $moved = switch ($unit) {
                'Year' { $current.Value.AddYears($whole) }
                'Month' { $current.Value.AddMonths($whole) }
                'Day' { $current.Value.AddDays($whole) }
                'Hour' { $current.Value.AddHours($whole) }
                'Minute' { $current.Value.AddMinutes($whole) }
                'Second' { $current.Value.AddSeconds($whole) }
            }
            $Environment.Set($name, [OtterDate]::new($moved, $current.HasTime))
            return
        }

        # days between startDate and endDate make days
        # days between startDate and endDate make days      (D32, legacy - D42 left this untouched)
        'DateDifference' {
            $start = Get-OtterValue -Expression $Statement.Start -Environment $Environment
            $end = Get-OtterValue -Expression $Statement.End -Environment $Environment
            Assert-OtterDateOperands -Start $start -End $end -Line $Statement.Line

            # D32.7: SIGNED, end minus start, matching the argument order.
            # Whole units, truncated toward zero.
            $Environment.Set($Statement.Target,
                (Measure-OtterDateDifference -Start $start -End $end -Unit $Statement.Unit.ToString()))
            return
        }

        # format date as "MM/dd/yyyy" into text
        'FormatDate' {
            $subject = Get-OtterValue -Expression $Statement.Subject -Environment $Environment
            if (-not (Test-OtterDate $subject)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only format a date, but this is $(Get-OtterTypeName $subject)." `
                    -Line $Statement.Line)
            }

            $pattern = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Format -Environment $Environment)
            try {
                $text = $subject.Value.ToString($pattern, [System.Globalization.CultureInfo]::InvariantCulture)
            }
            catch {
                throw (New-OtterRuntimeError `
                    -Message "I do not understand the date format $pattern." `
                    -Line $Statement.Line `
                    -Suggestion 'format date as "MM/dd/yyyy" into text')
            }

            # D32.4: the date itself is untouched.
            $Environment.Set($Statement.Target, $text)
            return
        }

        # state count is 0
        'StateDef' {
            $value = Get-OtterValue -Expression $Statement.InitialValue -Environment $Environment
            $signal = [OtterSignal]::new($Statement.Name, $value)
            $Environment.SetRaw($Statement.Name, $signal)
            return
        }

        # derive doubled is count * 2
        'DeriveDef' {
            $derived = [OtterDerived]::new($Statement.Name, $Statement.Expression, $Environment)
            $Environment.SetRaw($Statement.Name, $derived)
            return
        }

        # memo sortedItems ...
        #
        # D56: not part of Otter 1.0. Found during the v1 audit to be
        # outright broken, not merely unfinished - this case referenced
        # $Statement.Expression, a property MemoDefStmt does not have (it
        # only has .Body), so this always failed before even reaching
        # anything memo-specific. An explicit diagnostic here is strictly
        # more honest than the confusing PowerShell-property-not-found
        # failure this replaced.
        'MemoDef' {
            throw (New-OtterRuntimeError -Message "'memo' is not supported in Otter 1.0." -Line $Statement.Line)
        }

        # when count changes ...
        'Watch' {
            $targetName = $Statement.TargetName
            $raw = $Environment.GetRaw($targetName)
            $body = $Statement.Body
            $action = {
                Invoke-OtterStatements -Statements $body -Environment $Environment
            }.GetNewClosure()
            if ($raw -is [OtterSignal]) {
                $raw.Subscribe($action)
            } elseif ($raw -is [OtterDerived]) {
                $raw.Subscribe($action)
            } else {
                $signal = [OtterSignal]::new($targetName, $raw)
                $signal.Subscribe($action)
                $Environment.SetRaw($targetName, $signal)
            }
            return
        }

        # on start / on close
        #
        # D56: not part of Otter 1.0 - neither stage has defined, tested
        # lifecycle semantics. Previously 'start' ran its body inline
        # immediately (indistinguishable from the body not being wrapped
        # in "on start" at all, at the top level - not real deferred
        # lifecycle behavior) and 'close' did nothing at all. Both now
        # fail loudly instead of silently doing the wrong thing or nothing.
        'Lifecycle' {
            throw (New-OtterRuntimeError -Message "'on $($Statement.Stage)' is not supported in Otter 1.0." -Line $Statement.Line)
        }

        # shared theme is "dark"
        #
        # D56: not part of Otter 1.0 - mechanically identical to `state`,
        # but never independently exercised or frozen, so it does not get
        # to ride in on state's coattails.
        'SharedState' {
            throw (New-OtterRuntimeError -Message "'shared' is not supported in Otter 1.0." -Line $Statement.Line)
        }

        # use files / use ui
        #
        # D56: not part of Otter 1.0.
        'UseModule' {
            throw (New-OtterRuntimeError -Message "'use' is not supported in Otter 1.0." -Line $Statement.Line)
        }

        # focus searchBox / hide sidebar
        #
        # D56: not part of Otter 1.0. Verified during the v1 audit that
        # this was a silent no-op - confirmed directly, "hide sidebar"
        # left Visibility at its default and "focus box" left IsFocused
        # false, with no error either way. A feature doing nothing
        # successfully is worse than one that says so.
        'UiAction' {
            throw (New-OtterRuntimeError -Message "'$($Statement.Action)' is not supported in Otter 1.0." -Line $Statement.Line)
        }

        # card / window / primary button
        'UiElement' {
            if ($null -ne $Statement.Children) {
                Invoke-OtterStatements -Statements $Statement.Children -Environment $Environment
            }
            return
        }

        # D56: not part of Otter 1.0 - confirmed a silent no-op, same
        # reasoning as UiAction above.
        'UiEvent' {
            throw (New-OtterRuntimeError -Message "UI event blocks are not supported in Otter 1.0." -Line $Statement.Line)
        }

        # D56: not part of Otter 1.0 - confirmed a silent no-op.
        'UiAnimation' {
            throw (New-OtterRuntimeError -Message "UI animation is not supported in Otter 1.0." -Line $Statement.Line)
        }

        default {
            throw (New-OtterRuntimeError `
                -Message "I do not know how to run a $($Statement.Kind) statement yet." `
                -Line $Statement.Line)
        }
    }
}


# --- add / remove dispatch on runtime type (D12) -----------------
#
# The parser cannot tell "add 5 to score" from "add 'Pokemon' to games" -
# both are AddToStmt. Only the interpreter knows what the target holds.

function Invoke-OtterAddTo {
    param([Node]$Statement, [OtterEnvironment]$Environment)

    $name = $Statement.Target
    if (-not $Environment.Has($name)) {
        throw (New-OtterRuntimeError `
            -Message "Otter could not find the variable `"$name`"." `
            -Line $Statement.Line `
            -Suggestion "$name is 0")
    }

    $current = $Environment.Get($name)
    $amount = Get-OtterValue -Expression $Statement.Amount -Environment $Environment

    if (Test-OtterList $current) {
        $current.Add($amount)
        return
    }

    if (Test-OtterNumeric $current) {
        $addend = Assert-OtterNumber -Value $amount -Line $Statement.Line -What "the amount to add to `"$name`""
        $Environment.Set($name, (ConvertTo-OtterNumber $current) + $addend)
        return
    }

    throw (New-OtterRuntimeError `
        -Message "I can only add to a number or a list, but `"$name`" holds $(Get-OtterTypeName $current)." `
        -Line $Statement.Line)
}

function Invoke-OtterRemoveFrom {
    param([Node]$Statement, [OtterEnvironment]$Environment)

    $name = $Statement.Target
    if (-not $Environment.Has($name)) {
        throw (New-OtterRuntimeError `
            -Message "Otter could not find the variable `"$name`"." `
            -Line $Statement.Line)
    }

    $current = $Environment.Get($name)
    $amount = Get-OtterValue -Expression $Statement.Amount -Environment $Environment

    if (Test-OtterList $current) {
        for ($i = 0; $i -lt $current.Count; $i++) {
            if (Test-OtterEqual -Left $current[$i] -Right $amount) {
                $current.RemoveAt($i)
                return
            }
        }
        # Removing something absent is not an error - the list simply lacks it.
        return
    }

    if (Test-OtterNumeric $current) {
        $subtrahend = Assert-OtterNumber -Value $amount -Line $Statement.Line -What "the amount to remove from `"$name`""
        $Environment.Set($name, (ConvertTo-OtterNumber $current) - $subtrahend)
        return
    }

    throw (New-OtterRuntimeError `
        -Message "I can only remove from a number or a list, but `"$name`" holds $(Get-OtterTypeName $current)." `
        -Line $Statement.Line)
}


# ===============================================================
# EXPRESSIONS
# ===============================================================

function Get-OtterDerivedValue {
    param(
        [Parameter(Mandatory)][OtterDerived]$Derived,
        [Parameter(Mandatory)][OtterEnvironment]$Environment
    )

    if ($Derived.IsEvaluating) {
        throw (New-OtterRuntimeError -Message "Circular dependency detected in derived value `"$($Derived.Name)`"." -Line 0)
    }

    if ($Derived.IsDirty) {
        $Derived.IsEvaluating = $true
        $prevTracker = [OtterEnvironment]::ActiveDependencyTracker
        $newTracker = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        [OtterEnvironment]::ActiveDependencyTracker = $newTracker
        try {
            $value = Get-OtterValue -Expression $Derived.Expression -Environment $Environment
            $Derived.CachedValue = $value
            $Derived.IsDirty = $false

            foreach ($depName in $newTracker) {
                if ($depName -eq $Derived.Name) { continue }
                $raw = $Environment.GetRaw($depName)
                if ($raw -is [OtterSignal]) {
                    $raw.Subscribe($Derived)
                } elseif ($raw -is [OtterDerived]) {
                    $raw.Subscribe($Derived)
                }
            }
        }
        finally {
            [OtterEnvironment]::ActiveDependencyTracker = $prevTracker
            $Derived.IsEvaluating = $false
        }
    }

    return $Derived.CachedValue
}

[OtterEnvironment]::DerivedEvaluator = {
    param([OtterDerived]$Derived, [OtterEnvironment]$Env)
    Get-OtterDerivedValue -Derived $Derived -Environment $Env
}

# ===============================================================
# CRYPTOGRAPHY (D109) - console/desktop only
# ===============================================================
# High-level primitives over D102 bytes. Algorithms and parameters are
# runtime policy: Otter source says "encrypt" / "hash password" / "secure
# random", never "AES-CBC" or an iteration count.
#
# Encryption is authenticated (encrypt-then-MAC): AES-256-CBC for
# confidentiality plus HMAC-SHA256 over version|iv|ciphertext, with the
# two subkeys derived independently from the one 32-byte Otter key. The
# payload carries its own version and IV, so programs never handle nonces:
#     0x01 | iv(16) | ciphertext | tag(32)
# The tag is verified in constant time BEFORE any decryption happens.
# (.NET Framework 4.x, which Windows PowerShell 5.1 runs on, has no
# AES-GCM, so this is the approved authenticated construction here.)

$script:OtterCryptoKeyLength = 32
$script:OtterPasswordIterations = 600000

function Assert-OtterCryptoBytes {
    param([object]$Value, [int]$Line, [string]$What)
    if (-not (Test-OtterBytes $Value)) {
        throw (New-OtterRuntimeError `
            -Message "$What must be bytes, but this is $(Get-OtterTypeName -Value $Value). Otter never converts text to bytes silently." `
            -Line $Line `
            -Suggestion 'data is bytes from text "Hello"')
    }
}

function New-OtterSecureRandomByteArray {
    param([int]$Count)
    $buffer = [byte[]]::new($Count)
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
    # A byte[] returned through the pipeline would unroll; callers wrap it.
    Write-Output -NoEnumerate $buffer
}

function Get-OtterHmacBytes {
    param([string]$Algorithm, [byte[]]$Key, [byte[]]$Data)
    $hmac = switch ($Algorithm) {
        'sha256' { [System.Security.Cryptography.HMACSHA256]::new($Key) }
        'sha384' { [System.Security.Cryptography.HMACSHA384]::new($Key) }
        'sha512' { [System.Security.Cryptography.HMACSHA512]::new($Key) }
    }
    try { $result = $hmac.ComputeHash($Data) } finally { $hmac.Dispose() }
    Write-Output -NoEnumerate $result
}

function Get-OtterDigestBytes {
    param([string]$Algorithm, [byte[]]$Data)
    $hash = switch ($Algorithm) {
        'sha256' { [System.Security.Cryptography.SHA256]::Create() }
        'sha384' { [System.Security.Cryptography.SHA384]::Create() }
        'sha512' { [System.Security.Cryptography.SHA512]::Create() }
    }
    try { $result = $hash.ComputeHash($Data) } finally { $hash.Dispose() }
    Write-Output -NoEnumerate $result
}

# Compares without an early exit on the first differing byte, so timing
# does not reveal how much of a secret matched. Length is not secret.
function Test-OtterConstantTimeEqual {
    param([byte[]]$Left, [byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    $difference = 0
    for ($i = 0; $i -lt $Left.Length; $i++) {
        $difference = $difference -bor ($Left[$i] -bxor $Right[$i])
    }
    return ($difference -eq 0)
}

function Assert-OtterEncryptionKey {
    param([object]$Key, [int]$Line)
    Assert-OtterCryptoBytes -Value $Key -Line $Line -What 'An encryption key'
    if ($Key.Value.Length -ne $script:OtterCryptoKeyLength) {
        throw (New-OtterRuntimeError `
            -Message "An encryption key must be exactly $($script:OtterCryptoKeyLength) bytes, but this one is $($Key.Value.Length)." `
            -Line $Line `
            -Suggestion 'generate encryption key and call it key')
    }
}

function Protect-OtterBytes {
    param([byte[]]$Data, [byte[]]$Key)
    $encKey = Get-OtterHmacBytes -Algorithm 'sha256' -Key $Key -Data ([System.Text.Encoding]::ASCII.GetBytes('otter-aead-v1-enc'))
    $macKey = Get-OtterHmacBytes -Algorithm 'sha256' -Key $Key -Data ([System.Text.Encoding]::ASCII.GetBytes('otter-aead-v1-mac'))
    $iv = New-OtterSecureRandomByteArray -Count 16
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.KeySize = 256
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $encKey
        $aes.IV = $iv
        $encryptor = $aes.CreateEncryptor()
        try { $cipher = $encryptor.TransformFinalBlock($Data, 0, $Data.Length) } finally { $encryptor.Dispose() }
    } finally { $aes.Dispose() }
    $body = [byte[]]::new(1 + 16 + $cipher.Length)
    $body[0] = 1
    [System.Array]::Copy($iv, 0, $body, 1, 16)
    [System.Array]::Copy($cipher, 0, $body, 17, $cipher.Length)
    $tag = Get-OtterHmacBytes -Algorithm 'sha256' -Key $macKey -Data $body
    $payload = [byte[]]::new($body.Length + 32)
    [System.Array]::Copy($body, 0, $payload, 0, $body.Length)
    [System.Array]::Copy($tag, 0, $payload, $body.Length, 32)
    Write-Output -NoEnumerate $payload
}

# Returns the plaintext bytes, or $null when the payload is malformed,
# altered, or was made with a different key. Callers report one message
# for all three on purpose - telling them apart would help an attacker.
function Unprotect-OtterBytes {
    param([byte[]]$Payload, [byte[]]$Key)
    # version(1) + iv(16) + at least one cipher block(16) + tag(32)
    if ($Payload.Length -lt 65 -or $Payload[0] -ne 1) { return $null }
    $encKey = Get-OtterHmacBytes -Algorithm 'sha256' -Key $Key -Data ([System.Text.Encoding]::ASCII.GetBytes('otter-aead-v1-enc'))
    $macKey = Get-OtterHmacBytes -Algorithm 'sha256' -Key $Key -Data ([System.Text.Encoding]::ASCII.GetBytes('otter-aead-v1-mac'))
    $bodyLength = $Payload.Length - 32
    $body = [byte[]]::new($bodyLength)
    [System.Array]::Copy($Payload, 0, $body, 0, $bodyLength)
    $tag = [byte[]]::new(32)
    [System.Array]::Copy($Payload, $bodyLength, $tag, 0, 32)
    $expected = Get-OtterHmacBytes -Algorithm 'sha256' -Key $macKey -Data $body
    if (-not (Test-OtterConstantTimeEqual -Left $expected -Right $tag)) { return $null }
    $cipherLength = $bodyLength - 17
    if (($cipherLength % 16) -ne 0) { return $null }
    $iv = [byte[]]::new(16)
    [System.Array]::Copy($body, 1, $iv, 0, 16)
    $cipher = [byte[]]::new($cipherLength)
    [System.Array]::Copy($body, 17, $cipher, 0, $cipherLength)
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.KeySize = 256
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $encKey
        $aes.IV = $iv
        $decryptor = $aes.CreateDecryptor()
        try { $plain = $decryptor.TransformFinalBlock($cipher, 0, $cipher.Length) } finally { $decryptor.Dispose() }
    } catch {
        return $null
    } finally { $aes.Dispose() }
    Write-Output -NoEnumerate $plain
}

function Get-OtterPasswordDerivedBytes {
    param([string]$Password, [byte[]]$Salt, [int]$Iterations)
    $derive = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
        [System.Text.Encoding]::UTF8.GetBytes($Password), $Salt, $Iterations,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try { $result = $derive.GetBytes(32) } finally { $derive.Dispose() }
    Write-Output -NoEnumerate $result
}

# Stored form is text, so it can go straight into a database column or
# file:  otter-pbkdf2-sha256$<iterations>$<salt base64>$<hash base64>
function New-OtterPasswordHash {
    param([string]$Password)
    $salt = New-OtterSecureRandomByteArray -Count 16
    $derived = Get-OtterPasswordDerivedBytes -Password $Password -Salt $salt -Iterations $script:OtterPasswordIterations
    return "otter-pbkdf2-sha256`$$($script:OtterPasswordIterations)`$$([Convert]::ToBase64String($salt))`$$([Convert]::ToBase64String($derived))"
}

# Returns $true/$false, or $null when the text is not an Otter password hash.
function Test-OtterPasswordHash {
    param([string]$Password, [string]$StoredHash)
    $parts = $StoredHash.Split('$')
    if ($parts.Count -ne 4 -or $parts[0] -ne 'otter-pbkdf2-sha256') { return $null }
    $iterations = 0
    if (-not [int]::TryParse($parts[1], [ref]$iterations) -or $iterations -lt 1000) { return $null }
    try {
        $salt = [Convert]::FromBase64String($parts[2])
        $expected = [Convert]::FromBase64String($parts[3])
    } catch { return $null }
    if ($salt.Length -lt 8 -or $expected.Length -ne 32) { return $null }
    $derived = Get-OtterPasswordDerivedBytes -Password $Password -Salt $salt -Iterations $iterations
    return (Test-OtterConstantTimeEqual -Left $derived -Right $expected)
}

# ===============================================================
# CREDENTIAL VAULT (D111) - console only
# ===============================================================
# Secrets are stored in the Windows Credential Manager (the OS credential
# store, protected by the signed-in user's login) through advapi32
# CredWrite/CredRead/CredDelete. Nothing here writes a file, an .env, or
# a reversible key of Otter's own.
#
# Scoping: each secret's target name carries the running application's
# identity (a hash of the full path of the .ot file), so two unrelated
# Otter programs storing "api-token" never see each other's value. Text
# and bytes secrets are told apart by a marker in the credential comment,
# so a stored kind never silently changes on read-back.

$script:OtterApplicationId = 'otter-repl'
$script:OtterCredentialApiLoaded = $false
$script:OtterCredentialMaxBlob = 2560   # CRED_MAX_CREDENTIAL_BLOB_SIZE

function Set-OtterApplicationId {
    param([Parameter(Mandatory)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path).ToLowerInvariant()
    $hash = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = $hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($full)) } finally { $hash.Dispose() }
    $short = ([System.BitConverter]::ToString($digest, 0, 8) -replace '-', '').ToLowerInvariant()
    $script:OtterApplicationId = "$([System.IO.Path]::GetFileNameWithoutExtension($Path))-$short"
}

function Initialize-OtterCredentialApi {
    if ($script:OtterCredentialApiLoaded) { return }
    if (-not ('OtterCredentialApi' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class OtterCredentialApi {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CREDENTIAL {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite(ref CREDENTIAL credential, uint flags);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, uint type, uint flags);
    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr buffer);

    private const int ERROR_NOT_FOUND = 1168;

    public static void Write(string target, string kind, byte[] blob) {
        IntPtr pin = Marshal.AllocHGlobal(Math.Max(blob.Length, 1));
        try {
            Marshal.Copy(blob, 0, pin, blob.Length);
            CREDENTIAL c = new CREDENTIAL();
            c.Type = 1;                      // CRED_TYPE_GENERIC
            c.TargetName = target;
            c.Comment = kind;
            c.CredentialBlobSize = (uint)blob.Length;
            c.CredentialBlob = pin;
            c.Persist = 2;                   // CRED_PERSIST_LOCAL_MACHINE
            c.UserName = "otter";
            if (!CredWrite(ref c, 0)) {
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            }
        } finally {
            // Do not leave secret bytes lying in unmanaged memory.
            for (int i = 0; i < blob.Length; i++) { Marshal.WriteByte(pin, i, 0); }
            Marshal.FreeHGlobal(pin);
        }
    }

    // Returns false when no such credential exists.
    public static bool Read(string target, out string kind, out byte[] blob) {
        kind = null; blob = null;
        IntPtr ptr;
        if (!CredRead(target, 1, 0, out ptr)) {
            int err = Marshal.GetLastWin32Error();
            if (err == ERROR_NOT_FOUND) { return false; }
            throw new System.ComponentModel.Win32Exception(err);
        }
        try {
            CREDENTIAL c = (CREDENTIAL)Marshal.PtrToStructure(ptr, typeof(CREDENTIAL));
            kind = c.Comment;
            blob = new byte[c.CredentialBlobSize];
            if (c.CredentialBlobSize > 0) { Marshal.Copy(c.CredentialBlob, blob, 0, (int)c.CredentialBlobSize); }
            return true;
        } finally {
            CredFree(ptr);
        }
    }

    // Returns false when no such credential exists.
    public static bool Delete(string target) {
        if (CredDelete(target, 1, 0)) { return true; }
        int err = Marshal.GetLastWin32Error();
        if (err == ERROR_NOT_FOUND) { return false; }
        throw new System.ComponentModel.Win32Exception(err);
    }
}
'@
    }
    $script:OtterCredentialApiLoaded = $true
}

function Get-OtterSecretTarget {
    param([object]$Name, [int]$Line)
    if ($Name -isnot [string] -or [string]::IsNullOrWhiteSpace($Name)) {
        throw (New-OtterRuntimeError `
            -Message "I need a secret name as non-empty text, but this is $(Get-OtterTypeName -Value $Name)." `
            -Line $Line `
            -Suggestion 'store secret "api-token" with value token')
    }
    return "otter:$($script:OtterApplicationId):$Name"
}

function Assert-OtterVaultAvailable {
    param([int]$Line)
    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw (New-OtterRuntimeError `
            -Message 'The credential vault needs an operating-system credential store, and this platform does not have one Otter supports yet.' `
            -Line $Line)
    }
    Initialize-OtterCredentialApi
}

# D107/D108 helpers -------------------------------------------------
function Get-OtterNetPort {
    param([object]$Value, [int]$Line, [switch]$AllowZero)
    $isNumber = $Value -is [double] -or $Value -is [int] -or $Value -is [long]
    $min = if ($AllowZero) { 0 } else { 1 }
    if (-not $isNumber -or $Value -ne [Math]::Floor($Value) -or $Value -lt $min -or $Value -gt 65535) {
        throw (New-OtterRuntimeError `
            -Message "I need a whole-number port between $min and 65535, but this is $(Format-OtterValue -Value $Value)." `
            -Line $Line)
    }
    return [int]$Value
}

# TCP/UDP never convert text to bytes silently (D107 section 5).
function Assert-OtterNetBytes {
    param([object]$Value, [int]$Line, [string]$Where)
    if (-not (Test-OtterBytes $Value)) {
        throw (New-OtterRuntimeError `
            -Message "I can only send bytes through $Where, but this is $(Get-OtterTypeName -Value $Value). Otter never converts text to bytes silently." `
            -Line $Line `
            -Suggestion 'send bytes from text "Hello" through connection')
    }
}

function Get-OtterValue {
    param([Node]$Expression, [OtterEnvironment]$Environment)

    switch ($Expression.Kind.ToString()) {

        'Literal' { return $Expression.Value }

        'Variable' {
            $name = $Expression.Name
            if (-not $Environment.Has($name)) {
                throw (New-OtterRuntimeError `
                    -Message "Otter could not find the variable `"$name`". It has not been given a value yet." `
                    -Line $Expression.Line `
                    -Suggestion "$name is 0")
            }
            # -NoEnumerate matters: a PowerShell function RETURNING a List
            # unrolls it into separate pipeline items, so an Otter list would
            # arrive at the caller as a loose object[] and stop being a list.
            Write-Output -NoEnumerate ($Environment.Get($name))
            return
        }

        # 5 and 5   /   10 minus 5   /   10 times 5   /   10 divided by 5
        'Math' {
            $leftRaw = Get-OtterValue -Expression $Expression.Left -Environment $Environment
            $rightRaw = Get-OtterValue -Expression $Expression.Right -Environment $Environment

            if ($Expression.Op.ToString() -eq 'Add' -and ($leftRaw -is [string]) -and ($rightRaw -is [string])) {
                return $leftRaw + $rightRaw
            }

            # `and`/`plus` share one token (TokenKind::And) for arithmetic
            # addition and string concatenation - that overload is
            # deliberate and used throughout real Otter programs (e.g.
            # `text of a is text of b and c and "\n"`). But `and` is ALSO
            # how boolean logic reads inside a condition. A boolean value
            # reaching this far means the source almost certainly meant
            # boolean `and`/`or` OUTSIDE an if/while, where they are not
            # valid - give that specific, honest diagnosis here rather than
            # letting it fall through to Assert-OtterNumber's generic "I
            # expected a number" message, which never mentions booleans,
            # `and`, or conditions and sends a reader in the wrong
            # direction entirely.
            if ($Expression.Op.ToString() -eq 'Add' -and (($leftRaw -is [bool]) -or ($rightRaw -is [bool]))) {
                throw (New-OtterRuntimeError `
                    -Message 'A true/false value cannot be combined with "and" here. Boolean "and"/"or" only work inside an if or while condition.' `
                    -Line $Expression.Line `
                    -Suggestion 'if condition1 and condition2')
            }

            $left = Assert-OtterNumber -Value $leftRaw -Line $Expression.Line -What 'the left side of this calculation'
            $right = Assert-OtterNumber -Value $rightRaw -Line $Expression.Line -What 'the right side of this calculation'

            switch ($Expression.Op.ToString()) {
                'Add' { return $left + $right }
                'Subtract' { return $left - $right }
                'Multiply' { return $left * $right }
                'Divide' {
                    if ($right -eq 0) {
                        throw (New-OtterRuntimeError `
                            -Message 'I cannot divide by zero.' `
                            -Line $Expression.Line)
                    }
                    return $left / $right
                }
                # X percent of Y                                          (D88)
                'Percent' { return ($left / 100.0) * $right }
                # X power Y                                                (D88)
                'Power' { return [Math]::Pow($left, $right) }
            }
            return $null
        }

        # age is at least 18
        'Comparison' {
            $left = Get-OtterValue -Expression $Expression.Left -Environment $Environment
            $right = Get-OtterValue -Expression $Expression.Right -Environment $Environment

            switch ($Expression.Op.ToString()) {
                'Equal' { return (Test-OtterEqual -Left $left -Right $right) }
                'NotEqual' { return (-not (Test-OtterEqual -Left $left -Right $right)) }
            }

            # D32.6: two dates order by their instant, using the comparison
            # words Otter already has. No new syntax.
            if ((Test-OtterDate $left) -and (Test-OtterDate $right)) {
                $comparison = $left.Value.CompareTo($right.Value)
                switch ($Expression.Op.ToString()) {
                    'AtLeast' { return ($comparison -ge 0) }
                    'AtMost' { return ($comparison -le 0) }
                    'GreaterThan' { return ($comparison -gt 0) }
                    'LessThan' { return ($comparison -lt 0) }
                }
            }

            # The four ordering comparisons need real numbers on both sides.
            $l = Assert-OtterNumber -Value $left -Line $Expression.Line -What 'the left side of this comparison'
            $r = Assert-OtterNumber -Value $right -Line $Expression.Line -What 'the right side of this comparison'

            switch ($Expression.Op.ToString()) {
                'AtLeast' { return ($l -ge $r) }
                'AtMost' { return ($l -le $r) }
                'GreaterThan' { return ($l -gt $r) }
                'LessThan' { return ($l -lt $r) }
            }
            return $false
        }

        # if loggedIn and admin   /   if admin or moderator      (D11)
        # Both short-circuit, so "if false and boom" never evaluates boom.
        'Logical' {
            $left = Get-OtterValue -Expression $Expression.Left -Environment $Environment
            $leftTruthy = Test-OtterTruthy -Value $left

            if ($Expression.Op.ToString() -eq 'And') {
                if (-not $leftTruthy) { return $false }
                $right = Get-OtterValue -Expression $Expression.Right -Environment $Environment
                return (Test-OtterTruthy -Value $right)
            }

            if ($leftTruthy) { return $true }
            $right = Get-OtterValue -Expression $Expression.Right -Environment $Environment
            return (Test-OtterTruthy -Value $right)
        }

        # if not loggedIn        (D11)
        'Not' {
            $value = Get-OtterValue -Expression $Expression.Operand -Environment $Environment
            return (-not (Test-OtterTruthy -Value $value))
        }

        # if games contains "Zelda"      (D13)
        'Contains' {
            $collection = Get-OtterValue -Expression $Expression.Collection -Environment $Environment
            $item = Get-OtterValue -Expression $Expression.Item -Environment $Environment

            # "contains" reads the same way for text as for a list:
            #     if name contains "Jeff"
            #     if games contains "Zelda"
            if ($collection -is [string]) {
                return $collection.Contains((Format-OtterValue -Value $item))
            }

            if (-not (Test-OtterList $collection)) {
                throw (New-OtterRuntimeError `
                    -Message "Only text or a list can contain something, but this is $(Get-OtterTypeName $collection)." `
                    -Line $Expression.Line)
            }
            foreach ($entry in $collection) {
                if (Test-OtterEqual -Left $entry -Right $item) { return $true }
            }
            return $false
        }

        'Call' {
            # -NoEnumerate for the same reason: a function may return a list.
            Write-Output -NoEnumerate (Invoke-OtterCall -Call $Expression -Environment $Environment)
            return
        }

        # name of person   /   city of address of user   /   year of date
        'PropertyAccess' {
            $target = Get-OtterValue -Expression $Expression.Target -Environment $Environment

            # D32.2: a date answers its own parts. This is why date parts are
            # NOT operation words - "year of book" on a thing has to keep
            # meaning the stored property, and the two are indistinguishable
            # until the value is in hand.
            if (Test-OtterDate $target) {
                return (Get-OtterDatePart -Date $target -Part $Expression.Property -Line $Expression.Line)
            }

            # text of helloButton                                    (D45)
            #
            # Routed through Otter.UI.psm1 - the only place that knows
            # "text" means WPF Content for a button but Text for a text
            # box. The interpreter never touches System.Windows.* itself.
            if (Test-OtterUiResource $target) {
                Write-Output -NoEnumerate (
                    Get-OtterUiProperty -Resource $target -Property $Expression.Property -Line $Expression.Line)
                return
            }

            # name of book / root of document / text of book / attributes
            # of book                                                    (D105)
            # No new grammar needed for these four - they already reach
            # here through the ordinary "<word> of <expr>" PropertyAccess
            # every other property read uses.
            if (Test-OtterXml $target) {
                switch ($Expression.Property) {
                    'name' {
                        Assert-OtterXmlElement -Xml $target -Line $Expression.Line -What 'read the name of'
                        return $target.Node.Name
                    }
                    'root' {
                        if ($target.Node -isnot [System.Xml.XmlDocument]) {
                            throw (New-OtterRuntimeError `
                                -Message '"root of" only makes sense on an xml document, not an element.' `
                                -Line $Expression.Line)
                        }
                        if ($null -eq $target.Node.DocumentElement) { return $null }
                        return [OtterXml]::new($target.Node.DocumentElement)
                    }
                    'text' {
                        return $target.Node.InnerText
                    }
                    'attributes' {
                        Assert-OtterXmlElement -Xml $target -Line $Expression.Line -What 'read the attributes of'
                        $list = New-OtterList
                        foreach ($a in $target.Node.Attributes) { [void]$list.Add($a.Name) }
                        # -NoEnumerate matters: a bare `return $list` unrolls
                        # it into separate pipeline items (confirmed
                        # directly - it arrives at the caller as a plain
                        # object[], which then fails every Test-Otter* type
                        # check), the same reason every other list-shaped
                        # return in this file goes through Write-Output.
                        Write-Output -NoEnumerate $list
                        return
                    }
                    default {
                        throw (New-OtterRuntimeError `
                            -Message "This xml value has no property called ""$($Expression.Property)"". Try name, root, text, or attributes." `
                            -Line $Expression.Line)
                    }
                }
            }

            # D119-R2: command job properties: state / exit code / output / error output / id / command
            if (Test-OtterCommandJob $target) {
                switch ($Expression.Property) {
                    'state' { return $target.State }
                    'exit code' {
                        if ($null -ne $target.ExitCode) {
                            return [double]$target.ExitCode
                        }
                        return $null
                    }
                    'output' { return $target.GetOutput() }
                    'error output' { return $target.GetErrorOutput() }
                    'id' { return $target.Id }
                    'command' { return $target.CommandLine }
                    default {
                        throw (New-OtterRuntimeError `
                            -Message "This command job has no property called ""$($Expression.Property)"". Try state, exit code, output, error output, id, or command." `
                            -Line $Expression.Line)
                    }
                }
            }

            # D116B: state / response / error / status of an HTTP request
            if (Test-OtterHttpRequest $target) {
                switch ($Expression.Property) {
                    'state' {
                        return $target.State
                    }
                    'response' {
                        if ($target.State -eq 'pending') {
                            throw (New-OtterRuntimeError `
                                -Message 'The HTTP request has not completed yet.' `
                                -Line $Expression.Line)
                        }
                        if ($target.State -eq 'cancelled') {
                            throw (New-OtterRuntimeError `
                                -Message 'The HTTP request was cancelled.' `
                                -Line $Expression.Line)
                        }
                        if ($target.State -eq 'failed') {
                            throw (New-OtterRuntimeError `
                                -Message "The HTTP request failed: $($target.Error)" `
                                -Line $Expression.Line)
                        }
                        return $target.Response
                    }
                    'error' {
                        if ($target.State -eq 'failed' -and $null -ne $target.Error) {
                            return $target.Error
                        }
                        return $null
                    }
                    'status' {
                        if ($target.Status -gt 0) {
                            return [double]$target.Status
                        }
                        if ($target.State -eq 'pending') {
                            throw (New-OtterRuntimeError `
                                -Message 'The HTTP request has not completed yet.' `
                                -Line $Expression.Line)
                        }
                        return [double]$target.Status
                    }
                    default {
                        throw (New-OtterRuntimeError `
                            -Message "This http request has no property called ""$($Expression.Property)"". Try state, response, error, or status." `
                            -Line $Expression.Line)
                    }
                }
            }

            # D107: count of data - the spec's own example measures received bytes this way
            # (length of remains the D102 spelling).
            if ((Test-OtterBytes $target) -and $Expression.Property -eq 'count') { return [double]$target.Value.Length }

            # D107/D108: state / remote address / remote port of a tcp connection; state / port of a udp socket
            if (Test-OtterTcp $target) {
                switch ($Expression.Property) {
                    'state' { return $target.State }
                    'remote address' {
                        if ($target.State -eq 'connected' -and $null -ne $target.Client.Client.RemoteEndPoint) {
                            return $target.Client.Client.RemoteEndPoint.Address.ToString()
                        }
                        return $target.RemoteHost
                    }
                    'remote port' { return [double]$target.RemotePort }
                    'local address' {
                        if ($target.State -eq 'connected' -and $null -ne $target.Client.Client.LocalEndPoint) {
                            return ([System.Net.IPEndPoint]$target.Client.Client.LocalEndPoint).Address.ToString()
                        }
                        return '127.0.0.1'
                    }
                    'local port' {
                        if ($target.State -eq 'connected' -and $null -ne $target.Client.Client.LocalEndPoint) {
                            return [double]([System.Net.IPEndPoint]$target.Client.Client.LocalEndPoint).Port
                        }
                        return 0.0
                    }
                    'tls version' {
                        if (-not $target.IsSecure -or $target.State -ne 'connected') {
                            throw (New-OtterRuntimeError `
                                -Message 'This connection is not secure (or not connected yet), so it has no TLS version.' `
                                -Line $Expression.Line `
                                -Suggestion 'connect securely to tcp "example.com" on port 443 and call it connection')
                        }
                        $protocolName = [string]$target.Stream.SslProtocol
                        return (($protocolName -replace '^Tls(\d)(\d)$', 'TLS $1.$2') -replace '^Tls$', 'TLS 1.0')
                    }
                    'tls protocol' {
                        # No ALPN on this runtime, so no application protocol is ever negotiated.
                        if (-not $target.IsSecure -or $target.State -ne 'connected') {
                            throw (New-OtterRuntimeError `
                                -Message 'This connection is not secure (or not connected yet), so it has no negotiated protocol.' `
                                -Line $Expression.Line)
                        }
                        return ''
                    }
                    default {
                        throw (New-OtterRuntimeError `
                            -Message "A tcp connection has no property called ""$($Expression.Property)"". Try state, remote address, remote port, local address, local port, tls version, or tls protocol." `
                            -Line $Expression.Line)
                    }
                }
            }
            # D113: state / local address / local port of a tcp server
            if (Test-OtterTcpServer $target) {
                switch ($Expression.Property) {
                    'state' { return $target.State }
                    'local address' { return $target.BoundAddress }
                    'local port' { return [double]$target.BoundPort }
                    default {
                        throw (New-OtterRuntimeError `
                            -Message "A tcp server has no property called ""$($Expression.Property)"". Try state, local address, or local port." `
                            -Line $Expression.Line)
                    }
                }
            }
            if (Test-OtterUdp $target) {
                switch ($Expression.Property) {
                    'state' { return $target.State }
                    'port' { return [double]$target.LocalPort }
                    default {
                        throw (New-OtterRuntimeError `
                            -Message "A udp socket has no property called ""$($Expression.Property)"". Try state or port." `
                            -Line $Expression.Line)
                    }
                }
            }

            # D106: state of socket / url of socket / protocol of socket
            if (Test-OtterWebSocket $target) {
                switch ($Expression.Property) {
                    'state' { return $target.State }
                    'url' { return $target.Url }
                    'protocol' { return $target.Protocol }
                    default {
                        throw (New-OtterRuntimeError `
                            -Message "A websocket has no property called ""$($Expression.Property)"". Try state, url, or protocol." `
                            -Line $Expression.Line)
                    }
                }
            }

            if (-not (Test-OtterObject $target)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only read properties of a thing, but this is $(Get-OtterTypeName $target)." `
                    -Line $Expression.Line)
            }

            if (-not $target.HasProperty($Expression.Property)) {
                $known = $target.PropertyNames()
                $suggestion = $null
                if ($known.Count -gt 0) { $suggestion = "$($known[0]) of ..." }
                throw (New-OtterRuntimeError `
                    -Message "This $($target.TypeName) has no property called `"$($Expression.Property)`"." `
                    -Line $Expression.Line `
                    -Suggestion $suggestion)
            }

            Write-Output -NoEnumerate ($target.ReadProperty($Expression.Property))
            return
        }

        # if file "hello.txt" exists
        'FileExists' {
            $path = Get-OtterPathArgument -Expression $Expression.Path -Environment $Environment
            return (Test-OtterFileExists -Path $path -Line $Expression.Line)
        }

        # if file "hello.txt" is locked                                (D72)
        'FileLocked' {
            $path = Get-OtterPathArgument -Expression $Expression.Path -Environment $Environment
            return (Test-OtterFileLocked -Path $path -Line $Expression.Line)
        }

        # if file "l" is a symbolic link                                (D73)
        'FileIsSymbolicLink' {
            $path = Get-OtterPathArgument -Expression $Expression.Path -Environment $Environment
            return (Test-OtterSymbolicLink -Path $path -Line $Expression.Line)
        }

        # if file "x" is read only                                       (D74)
        'FileIsReadOnly' {
            $path = Get-OtterPathArgument -Expression $Expression.Path -Environment $Environment
            return (Test-OtterFileReadOnly -Path $path -Line $Expression.Line)
        }

        # if registry key "path" exists                                 (D78)
        'RegistryKeyExists' {
            $keyPath = Format-OtterValue -Value (Get-OtterValue -Expression $Expression.KeyPath -Environment $Environment)
            return (Test-OtterRegistryKeyExists -KeyPath $keyPath)
        }

        # length of name / length of games / uppercase of name /
        # first of games / last of games                        (D24)
        'OfOperation' {
            $subject = Get-OtterValue -Expression $Expression.Subject -Environment $Environment

            switch ($Expression.Operation.ToString()) {

                'Length' {
                    if (Test-OtterList $subject) { return [double]$subject.Count }
                    if ($subject -is [string]) { return [double]$subject.Length }
                    if (Test-OtterBytes $subject) { return [double]$subject.Value.Length }   # D102
                    throw (New-OtterRuntimeError `
                        -Message "I can only measure the length of text, a list, or bytes, but this is $(Get-OtterTypeName $subject)." `
                        -Line $Expression.Line)
                }

                'Uppercase' { return (Format-OtterValue -Value $subject).ToUpperInvariant() }
                'Lowercase' { return (Format-OtterValue -Value $subject).ToLowerInvariant() }

                # first/last of an empty list is gone, not an error. D22 is
                # exactly what makes "if first of games is gone" askable.
                'First' {
                    if (-not (Test-OtterList $subject)) {
                        throw (New-OtterRuntimeError `
                            -Message "Only a list has a first item, but this is $(Get-OtterTypeName $subject)." `
                            -Line $Expression.Line)
                    }
                    if ($subject.Count -eq 0) { return $null }
                    Write-Output -NoEnumerate $subject[0]
                    return
                }

                'Last' {
                    if (-not (Test-OtterList $subject)) {
                        throw (New-OtterRuntimeError `
                            -Message "Only a list has a last item, but this is $(Get-OtterTypeName $subject)." `
                            -Line $Expression.Line)
                    }
                    if ($subject.Count -eq 0) { return $null }
                    Write-Output -NoEnumerate $subject[$subject.Count - 1]
                    return
                }

                # absolute value of X / square root of X / round of X /
                # round up of X / round down of X                    (D89)
                'AbsoluteValue' {
                    $n = Assert-OtterNumber -Value $subject -Line $Expression.Line -What 'the absolute value'
                    return [Math]::Abs($n)
                }

                'SquareRoot' {
                    $n = Assert-OtterNumber -Value $subject -Line $Expression.Line -What 'the square root'
                    if ($n -lt 0) {
                        throw (New-OtterRuntimeError `
                            -Message "I can't take the square root of a negative number ($n)." `
                            -Line $Expression.Line)
                    }
                    return [Math]::Sqrt($n)
                }

                'Round' {
                    $n = Assert-OtterNumber -Value $subject -Line $Expression.Line -What 'rounding'
                    return [Math]::Round([double]$n, 0, [MidpointRounding]::AwayFromZero)
                }

                'RoundUp' {
                    $n = Assert-OtterNumber -Value $subject -Line $Expression.Line -What 'rounding'
                    return [Math]::Ceiling($n)
                }

                'RoundDown' {
                    $n = Assert-OtterNumber -Value $subject -Line $Expression.Line -What 'rounding'
                    return [Math]::Floor($n)
                }

                # sine of X / cosine of X / tangent of X                (D90)
                # X is in DEGREES, not radians - "sine of 90" reading as 1
                # is what a non-technical, "readable like English" caller
                # expects; converting internally keeps that expectation
                # true without asking the caller to think in radians.
                'Sine' {
                    $n = Assert-OtterNumber -Value $subject -Line $Expression.Line -What 'sine'
                    return [Math]::Sin($n * [Math]::PI / 180.0)
                }

                'Cosine' {
                    $n = Assert-OtterNumber -Value $subject -Line $Expression.Line -What 'cosine'
                    return [Math]::Cos($n * [Math]::PI / 180.0)
                }

                'Tangent' {
                    $n = Assert-OtterNumber -Value $subject -Line $Expression.Line -What 'tangent'
                    return [Math]::Tan($n * [Math]::PI / 180.0)
                }

                # log of X (base 10) / natural log of X (base e)        (D90)
                'LogTen' {
                    $n = Assert-OtterNumber -Value $subject -Line $Expression.Line -What 'a logarithm'
                    if ($n -le 0) {
                        throw (New-OtterRuntimeError `
                            -Message "I can't take the log of a number that isn't positive ($n)." `
                            -Line $Expression.Line)
                    }
                    return [Math]::Log10($n)
                }

                'NaturalLog' {
                    $n = Assert-OtterNumber -Value $subject -Line $Expression.Line -What 'a logarithm'
                    if ($n -le 0) {
                        throw (New-OtterRuntimeError `
                            -Message "I can't take the natural log of a number that isn't positive ($n)." `
                            -Line $Expression.Line)
                    }
                    return [Math]::Log($n)
                }

                # elapsed time of workTimer / elapsed milliseconds of workTimer  (D101)
                # A real monotonic clock (System.Diagnostics.Stopwatch),
                # never wall-clock `now` subtraction - immune to a system
                # clock change mid-measurement.
                'ElapsedTime' {
                    if ($subject -isnot [System.Diagnostics.Stopwatch]) {
                        throw (New-OtterRuntimeError `
                            -Message "I can only measure elapsed time of a timer, but this is $(Get-OtterTypeName $subject)." `
                            -Line $Expression.Line `
                            -Suggestion 'start timer workTimer')
                    }
                    return $subject.Elapsed.TotalSeconds
                }
                'ElapsedMilliseconds' {
                    if ($subject -isnot [System.Diagnostics.Stopwatch]) {
                        throw (New-OtterRuntimeError `
                            -Message "I can only measure elapsed time of a timer, but this is $(Get-OtterTypeName $subject)." `
                            -Line $Expression.Line `
                            -Suggestion 'start timer workTimer')
                    }
                    return $subject.Elapsed.TotalMilliseconds
                }
            }
            return $null
        }

        # larger of X and Y / smaller of X and Y                     (D89)
        'MinMax' {
            $left = Assert-OtterNumber -Value (Get-OtterValue -Expression $Expression.Left -Environment $Environment) -Line $Expression.Line -What 'comparing sizes'
            $right = Assert-OtterNumber -Value (Get-OtterValue -Expression $Expression.Right -Environment $Environment) -Line $Expression.Line -What 'comparing sizes'
            if ($Expression.IsMax) { return [Math]::Max($left, $right) }
            return [Math]::Min($left, $right)
        }

        # if name starts with "J"   /   if name ends with "Macy"
        'TextMatch' {
            $subject = Format-OtterValue -Value (Get-OtterValue -Expression $Expression.Subject -Environment $Environment)
            $value = Format-OtterValue -Value (Get-OtterValue -Expression $Expression.Value -Environment $Environment)

            if ($Expression.Match.ToString() -eq 'StartsWith') {
                return $subject.StartsWith($value, [System.StringComparison]::Ordinal)
            }
            return $subject.EndsWith($value, [System.StringComparison]::Ordinal)
        }

        # today   /   now                                      (D32)
        'Clock' {
            if ($Expression.Clock.ToString() -eq 'Today') { return (New-OtterToday) }
            return (New-OtterNow)
        }

        # console is interactive                                        (D100)
        # False if EITHER stdin or stdout is redirected - most of the
        # console-UX primitives (colors, cursor positioning, progress
        # bars, interactive menus) only make sense when both are real,
        # attached streams, which is exactly what gating on this is for.
        'ConsoleInteractive' {
            return (-not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected))
        }

        # date from "2024-01-15"  /  date from "01/15/2024" using "MM/dd/yyyy"   (D101)
        # Failure produces a normal Otter runtime error, not special parsing
        # syntax - matches the rest of the language's error model.
        'DateFromText' {
            $text = Get-OtterText -Expression $Expression.Source -Environment $Environment
            if ($null -ne $Expression.Format) {
                $formatText = Get-OtterText -Expression $Expression.Format -Environment $Environment
                try {
                    $parsed = [System.DateTime]::ParseExact($text, $formatText, [System.Globalization.CultureInfo]::InvariantCulture)
                    return [OtterDate]::new($parsed, ($parsed.TimeOfDay -ne [TimeSpan]::Zero))
                } catch {
                    throw (New-OtterRuntimeError `
                        -Message "I couldn't understand ""$text"" as a date using the format ""$formatText""." `
                        -Line $Expression.Line)
                }
            }
            try {
                $parsed = [System.DateTime]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture)
                return [OtterDate]::new($parsed, ($parsed.TimeOfDay -ne [TimeSpan]::Zero))
            } catch {
                throw (New-OtterRuntimeError `
                    -Message "I couldn't understand ""$text"" as a date." `
                    -Line $Expression.Line `
                    -Suggestion 'date from "2024-01-15" using "yyyy-MM-dd"')
            }
        }

        # D102: bytes type. Text is text, bytes are bytes, hex/base64 are
        # textual REPRESENTATIONS of bytes - every conversion here is
        # explicit and every malformed input is a clean Otter runtime
        # error, never a silent empty-bytes/mangled-text fallback (the
        # design's own "do not silently ..." rules, taken literally).
        'Bytes' {
            switch ($Expression.Op) {
                ([BytesOp]::Empty) {
                    return [OtterBytes]::new([byte[]]@())
                }
                ([BytesOp]::FromText) {
                    $text = Get-OtterText -Expression $Expression.Source -Environment $Environment
                    return [OtterBytes]::new([System.Text.Encoding]::UTF8.GetBytes($text))
                }
                ([BytesOp]::FromHex) {
                    $text = Get-OtterText -Expression $Expression.Source -Environment $Environment
                    $clean = $text.Trim()
                    if ($clean.Length -eq 0 -or ($clean.Length % 2) -ne 0 -or $clean -notmatch '^[0-9A-Fa-f]+$') {
                        throw (New-OtterRuntimeError `
                            -Message "I can't read ""$text"" as hex - it needs to be pairs of hex digits (0-9, A-F)." `
                            -Line $Expression.Line `
                            -Suggestion 'bytes from hex "48656C6C6F"')
                    }
                    $bytes = [byte[]]::new($clean.Length / 2)
                    for ($hi = 0; $hi -lt $bytes.Length; $hi++) {
                        $bytes[$hi] = [System.Convert]::ToByte($clean.Substring($hi * 2, 2), 16)
                    }
                    return [OtterBytes]::new($bytes)
                }
                ([BytesOp]::FromBase64) {
                    $text = Get-OtterText -Expression $Expression.Source -Environment $Environment
                    try {
                        return [OtterBytes]::new([System.Convert]::FromBase64String($text))
                    } catch {
                        throw (New-OtterRuntimeError `
                            -Message "I can't read ""$text"" as base64 - it isn't valid base64 text." `
                            -Line $Expression.Line `
                            -Suggestion 'bytes from base64 "SGVsbG8="')
                    }
                }
                ([BytesOp]::ToText) {
                    $bytesValue = Get-OtterValue -Expression $Expression.Source -Environment $Environment
                    if (-not (Test-OtterBytes $bytesValue)) {
                        throw (New-OtterRuntimeError `
                            -Message "I can only read text from bytes, but this is $(Get-OtterTypeName $bytesValue)." `
                            -Line $Expression.Line)
                    }
                    try {
                        $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
                        return $strictUtf8.GetString($bytesValue.Value)
                    } catch {
                        throw (New-OtterRuntimeError `
                            -Message "These bytes aren't valid UTF-8 text." `
                            -Line $Expression.Line)
                    }
                }
                ([BytesOp]::ToHex) {
                    $bytesValue = Get-OtterValue -Expression $Expression.Source -Environment $Environment
                    if (-not (Test-OtterBytes $bytesValue)) {
                        throw (New-OtterRuntimeError `
                            -Message "I can only read hex from bytes, but this is $(Get-OtterTypeName $bytesValue)." `
                            -Line $Expression.Line)
                    }
                    $hexChars = foreach ($b in $bytesValue.Value) { $b.ToString('X2') }
                    return ($hexChars -join '')
                }
                ([BytesOp]::ToBase64) {
                    $bytesValue = Get-OtterValue -Expression $Expression.Source -Environment $Environment
                    if (-not (Test-OtterBytes $bytesValue)) {
                        throw (New-OtterRuntimeError `
                            -Message "I can only read base64 from bytes, but this is $(Get-OtterTypeName $bytesValue)." `
                            -Line $Expression.Line)
                    }
                    return [System.Convert]::ToBase64String($bytesValue.Value)
                }
            }
        }

        # D115: bytes from file <path>
        'BytesFromFile' {
            $path = Get-OtterPathArgument -Expression $Expression.Path -Environment $Environment
            return (Read-OtterFileBytes -Path $path -Line $Expression.Line)
        }

        # dataWatcher is watching                                         (D104)
        'IsWatching' {
            $watcher = Get-OtterValue -Expression $Expression.Watcher -Environment $Environment
            if (-not (Test-OtterFileWatcher $watcher)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only ask whether a file watcher is watching, but this is $(Get-OtterTypeName -Value $watcher)." `
                    -Line $Expression.Line)
            }
            return $watcher.Active
        }

        # changed path / changed file name / change kind / old path        (D104)
        # Ambient context, valid only inside a watch-event handler body -
        # set/cleared by Invoke-OtterWatchEventLoop around each handler
        # call. Accessing these outside that context is a clean error,
        # not a silent `gone` (there is no sensible default: "the path of
        # what?").
        'ChangedPath' {
            if ($null -eq $script:OtterCurrentWatchEvent) {
                throw (New-OtterRuntimeError `
                    -Message '"changed path" only means something inside a watch-event handler (on change/create/delete/rename).' `
                    -Line $Expression.Line)
            }
            return $script:OtterCurrentWatchEvent.Path
        }
        'ChangedFileName' {
            if ($null -eq $script:OtterCurrentWatchEvent) {
                throw (New-OtterRuntimeError `
                    -Message '"changed file name" only means something inside a watch-event handler (on change/create/delete/rename).' `
                    -Line $Expression.Line)
            }
            return $script:OtterCurrentWatchEvent.FileName
        }
        'ChangeKind' {
            if ($null -eq $script:OtterCurrentWatchEvent) {
                throw (New-OtterRuntimeError `
                    -Message '"change kind" only means something inside a watch-event handler (on change/create/delete/rename).' `
                    -Line $Expression.Line)
            }
            return $script:OtterCurrentWatchEvent.Kind
        }
        'OldPath' {
            if ($null -eq $script:OtterCurrentWatchEvent) {
                throw (New-OtterRuntimeError `
                    -Message '"old path" only means something inside a watch-event handler (on change/create/delete/rename).' `
                    -Line $Expression.Line)
            }
            if ($null -eq $script:OtterCurrentWatchEvent.OldPath) {
                throw (New-OtterRuntimeError `
                    -Message '"old path" is only available inside "on rename in ..." - this is a different kind of watcher event.' `
                    -Line $Expression.Line)
            }
            return $script:OtterCurrentWatchEvent.OldPath
        }

        # D106: WebSockets contextual event expressions and state test
        'WebSocketIsState' {
            $ws = Get-OtterValue -Expression $Expression.Socket -Environment $Environment
            if (-not ((Test-OtterWebSocket $ws) -or (Test-OtterTcp $ws) -or (Test-OtterUdp $ws))) {
                throw (New-OtterRuntimeError `
                    -Message "I can only ask about the state of a websocket, tcp connection or udp socket, but this is $(Get-OtterTypeName -Value $ws)." `
                    -Line $Expression.Line)
            }
            $targetState = switch ($Expression.ConnState) {
                ([WebSocketConnState]::Connecting) { 'connecting' }
                ([WebSocketConnState]::Open) { 'open' }
                ([WebSocketConnState]::Closing) { 'closing' }
                ([WebSocketConnState]::Closed) { 'closed' }
                ([WebSocketConnState]::Connected) { 'connected' }
            }
            return ($ws.State -eq $targetState)
        }
        # D113: server is listening / server is stopped
        'TcpServerIsState' {
            $srv = Get-OtterValue -Expression $Expression.Server -Environment $Environment
            if (-not (Test-OtterTcpServer $srv)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only ask about the state of a tcp server, but this is $(Get-OtterTypeName -Value $srv)." `
                    -Line $Expression.Line)
            }
            $targetState = switch ($Expression.ServerState) {
                ([TcpServerState]::Listening) { 'listening' }
                ([TcpServerState]::Stopped) { 'stopped' }
            }
            return ($srv.State -eq $targetState)
        }
        # D116B: request is pending/completed/failed/cancelled; D119-R2: job is running/completed/failed/cancelled
        'HttpRequestIsState' {
            $req = Get-OtterValue -Expression $Expression.Request -Environment $Environment
            if (Test-OtterCommandJob $req) {
                $targetState = switch ($Expression.ReqState) {
                    ([HttpRequestState]::Pending) { 'running' }
                    ([HttpRequestState]::Completed) { 'completed' }
                    ([HttpRequestState]::Failed) { 'failed' }
                    ([HttpRequestState]::Cancelled) { 'cancelled' }
                }
                return ($req.State -eq $targetState)
            }
            if (-not (Test-OtterHttpRequest $req)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only check the state of an HTTP request or command job, but got $(Get-OtterTypeName -Value $req)." `
                    -Line $Expression.Line)
            }
            $targetState = switch ($Expression.ReqState) {
                ([HttpRequestState]::Pending) { 'pending' }
                ([HttpRequestState]::Completed) { 'completed' }
                ([HttpRequestState]::Failed) { 'failed' }
                ([HttpRequestState]::Cancelled) { 'cancelled' }
            }
            return ($req.State -eq $targetState)
        }
        # D119-R2: received output / received error output
        'JobContext' {
            if ($Expression.Field -eq 'output') {
                if ($null -eq $script:OtterCurrentJobContext -or -not $script:OtterCurrentJobContext.ContainsKey('Output')) {
                    throw (New-OtterRuntimeError `
                        -Message '"received output" is only available inside "on output from ...".' `
                        -Line $Expression.Line)
                }
                return $script:OtterCurrentJobContext.Output
            }
            if ($Expression.Field -eq 'error output') {
                if ($null -eq $script:OtterCurrentJobContext -or -not $script:OtterCurrentJobContext.ContainsKey('ErrorOutput')) {
                    throw (New-OtterRuntimeError `
                        -Message '"received error output" is only available inside "on error output from ...".' `
                        -Line $Expression.Line)
                }
                return $script:OtterCurrentJobContext.ErrorOutput
            }
            throw (New-OtterRuntimeError `
                -Message "Unknown job context field '$($Expression.Field)'." `
                -Line $Expression.Line)
        }
        # D116B: received response
        'ReceivedResponse' {
            if ($null -eq $script:OtterCurrentWsContext -or -not $script:OtterCurrentWsContext.ContainsKey('Response')) {
                throw (New-OtterRuntimeError `
                    -Message '"received response" is only available inside "on complete of ...".' `
                    -Line $Expression.Line)
            }
            return $script:OtterCurrentWsContext.Response
        }
        'ReceivedMessage' {
            if ($null -eq $script:OtterCurrentWsContext -or -not $script:OtterCurrentWsContext.ContainsKey('Message')) {
                throw (New-OtterRuntimeError `
                    -Message '"received message" is only available inside "on message from ...".' `
                    -Line $Expression.Line)
            }
            return $script:OtterCurrentWsContext.Message
        }
        'CloseCode' {
            if ($null -eq $script:OtterCurrentWsContext -or -not $script:OtterCurrentWsContext.ContainsKey('CloseCode')) {
                throw (New-OtterRuntimeError `
                    -Message '"close code" is only available inside "on close of ...".' `
                    -Line $Expression.Line)
            }
            return $script:OtterCurrentWsContext.CloseCode
        }
        'CloseReason' {
            if ($null -eq $script:OtterCurrentWsContext -or -not $script:OtterCurrentWsContext.ContainsKey('CloseReason')) {
                throw (New-OtterRuntimeError `
                    -Message '"close reason" is only available inside "on close of ...".' `
                    -Line $Expression.Line)
            }
            return $script:OtterCurrentWsContext.CloseReason
        }
        'CloseWasClean' {
            if ($null -eq $script:OtterCurrentWsContext -or -not $script:OtterCurrentWsContext.ContainsKey('CloseWasClean')) {
                throw (New-OtterRuntimeError `
                    -Message '"close was clean" is only available inside "on close of ...".' `
                    -Line $Expression.Line)
            }
            return $script:OtterCurrentWsContext.CloseWasClean
        }
        # secure random bytes 32                                        (D109)
        'SecureRandomBytes' {
            $countVal = Get-OtterValue -Expression $Expression.Count -Environment $Environment
            $isNumber = $countVal -is [double] -or $countVal -is [int] -or $countVal -is [long]
            if (-not $isNumber -or $countVal -ne [Math]::Floor($countVal) -or $countVal -lt 1 -or $countVal -gt 1048576) {
                throw (New-OtterRuntimeError `
                    -Message "I need a whole number of random bytes between 1 and 1048576, but this is $(Format-OtterValue -Value $countVal)." `
                    -Line $Expression.Line `
                    -Suggestion 'data is secure random bytes 32')
            }
            return [OtterBytes]::new((New-OtterSecureRandomByteArray -Count ([int]$countVal)))
        }

        # sha256 of data                                                (D109)
        'CryptoHash' {
            $data = Get-OtterValue -Expression $Expression.Data -Environment $Environment
            Assert-OtterCryptoBytes -Value $data -Line $Expression.Line -What "The data to hash with $($Expression.Algorithm)"
            return [OtterBytes]::new((Get-OtterDigestBytes -Algorithm $Expression.Algorithm -Data ([byte[]]$data.Value)))
        }

        # hmac sha256 of data using key                                 (D109)
        'CryptoHmac' {
            $data = Get-OtterValue -Expression $Expression.Data -Environment $Environment
            $key = Get-OtterValue -Expression $Expression.Key -Environment $Environment
            Assert-OtterCryptoBytes -Value $data -Line $Expression.Line -What 'The data to sign'
            Assert-OtterCryptoBytes -Value $key -Line $Expression.Line -What 'A signing key'
            if ($key.Value.Length -eq 0) {
                throw (New-OtterRuntimeError -Message 'A signing key cannot be empty.' -Line $Expression.Line)
            }
            return [OtterBytes]::new((Get-OtterHmacBytes -Algorithm $Expression.Algorithm -Key ([byte[]]$key.Value) -Data ([byte[]]$data.Value)))
        }

        # password attempt matches hash storedHash                      (D109)
        'PasswordMatches' {
            $password = Get-OtterValue -Expression $Expression.Password -Environment $Environment
            $stored = Get-OtterValue -Expression $Expression.Hash -Environment $Environment
            if ($password -isnot [string]) {
                throw (New-OtterRuntimeError -Message "I need a password as text, but this is $(Get-OtterTypeName -Value $password)." -Line $Expression.Line)
            }
            if ($stored -isnot [string]) {
                throw (New-OtterRuntimeError `
                    -Message "I need a stored password hash as text, but this is $(Get-OtterTypeName -Value $stored)." `
                    -Line $Expression.Line `
                    -Suggestion 'hash password password and call it storedHash')
            }
            $verdict = Test-OtterPasswordHash -Password $password -StoredHash $stored
            if ($null -eq $verdict) {
                throw (New-OtterRuntimeError `
                    -Message 'That text is not a password hash made by "hash password".' `
                    -Line $Expression.Line `
                    -Suggestion 'hash password password and call it storedHash')
            }
            return $verdict
        }

        # expected securely equals actual                               (D109)
        'SecurelyEquals' {
            $left = Get-OtterValue -Expression $Expression.Left -Environment $Environment
            $right = Get-OtterValue -Expression $Expression.Right -Environment $Environment
            Assert-OtterCryptoBytes -Value $left -Line $Expression.Line -What 'A secret compared with "securely equals"'
            Assert-OtterCryptoBytes -Value $right -Line $Expression.Line -What 'A secret compared with "securely equals"'
            return (Test-OtterConstantTimeEqual -Left ([byte[]]$left.Value) -Right ([byte[]]$right.Value))
        }

        # secret "api-token"                                            (D111)
        'SecretRead' {
            Assert-OtterVaultAvailable -Line $Expression.Line
            $nameValue = Get-OtterValue -Expression $Expression.Name -Environment $Environment
            $target = Get-OtterSecretTarget -Name $nameValue -Line $Expression.Line
            $kind = $null
            $blob = $null
            try {
                $found = [OtterCredentialApi]::Read($target, [ref]$kind, [ref]$blob)
            } catch {
                throw (New-OtterRuntimeError `
                    -Message "I could not read the secret: $($_.Exception.GetBaseException().Message)" `
                    -Line $Expression.Line)
            }
            # A missing secret is an error, never an empty string pretending to exist.
            if (-not $found) {
                throw (New-OtterRuntimeError `
                    -Message "There is no secret called ""$nameValue""." `
                    -Line $Expression.Line `
                    -Suggestion 'if secret "name" exists ...')
            }
            if ($kind -eq 'otter-bytes') { return [OtterBytes]::new([byte[]]$blob) }
            return [System.Text.Encoding]::UTF8.GetString([byte[]]$blob)
        }

        # secret "api-token" exists                                     (D111)
        'SecretExists' {
            Assert-OtterVaultAvailable -Line $Expression.Line
            $target = Get-OtterSecretTarget -Name (Get-OtterValue -Expression $Expression.Name -Environment $Environment) -Line $Expression.Line
            $kind = $null
            $blob = $null
            try {
                return [bool][OtterCredentialApi]::Read($target, [ref]$kind, [ref]$blob)
            } catch {
                throw (New-OtterRuntimeError `
                    -Message "I could not check for the secret: $($_.Exception.GetBaseException().Message)" `
                    -Line $Expression.Line)
            }
        }

        # connection is secure                                          (D112)
        'ConnectionIsSecure' {
            $conn = Get-OtterValue -Expression $Expression.Connection -Environment $Environment
            if (-not (Test-OtterTcp $conn)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only ask whether a tcp connection is secure, but this is $(Get-OtterTypeName -Value $conn)." `
                    -Line $Expression.Line)
            }
            return ($conn.IsSecure -and $conn.State -eq 'connected')
        }
        'DragContext' {
            throw (New-OtterRuntimeError `
                -Message """$($Expression.Field)"" is only available in web applications, inside a drag or drop event." `
                -Line $Expression.Line)
        }
        'NetContext' {
            $netKey = switch ($Expression.Field) {
                'data' { 'Data' }
                'sender address' { 'SenderAddress' }
                'sender port' { 'SenderPort' }
                'network error' { 'NetError' }
                'incoming connection' { 'IncomingConnection' }
                'response' { 'Response' }
            }
            $netWhere = switch ($Expression.Field) {
                'data' { 'on data from ...' }
                'sender address' { 'a udp "on data from ..."' }
                'sender port' { 'a udp "on data from ..."' }
                'network error' { 'on error of ...' }
                'incoming connection' { 'on connection to ...' }
                'response' { 'on complete of ...' }
            }
            if ($null -eq $script:OtterCurrentWsContext -or -not $script:OtterCurrentWsContext.ContainsKey($netKey)) {
                throw (New-OtterRuntimeError `
                    -Message """$(if ($Expression.Field -eq 'data') { 'received data' } elseif ($Expression.Field -eq 'response') { 'received response' } else { $Expression.Field })"" is only available inside $netWhere." `
                    -Line $Expression.Line)
            }
            return $script:OtterCurrentWsContext[$netKey]
        }
        'WebSocketErrorValue' {
            if ($null -eq $script:OtterCurrentWsContext -or -not $script:OtterCurrentWsContext.ContainsKey('Error')) {
                throw (New-OtterRuntimeError `
                    -Message '"websocket error" is only available inside "on error of ...".' `
                    -Line $Expression.Line)
            }
            return $script:OtterCurrentWsContext.Error
        }

        # xml from text source / xml from file "books.xml" / xml with root "library"   (D105)
        'XmlFrom' {
            switch ($Expression.Source) {
                ([XmlSourceKind]::Text) {
                    $text = Get-OtterText -Expression $Expression.Value -Environment $Environment
                    $doc = [System.Xml.XmlDocument]::new()
                    try {
                        $doc.LoadXml($text)
                    } catch {
                        $xmlErrMsg = $_.Exception.Message
                        if ($_.Exception.InnerException) { $xmlErrMsg = $_.Exception.InnerException.Message }
                        New-OtterXmlRuntimeError -Text $xmlErrMsg -Line $Expression.Line
                    }
                    return [OtterXml]::new($doc)
                }
                ([XmlSourceKind]::File) {
                    $path = Get-OtterPathArgument -Expression $Expression.Value -Environment $Environment
                    $text = Read-OtterFile -Path $path -Line $Expression.Line
                    $doc = [System.Xml.XmlDocument]::new()
                    try {
                        $doc.LoadXml($text)
                    } catch {
                        $xmlErrMsg = $_.Exception.Message
                        if ($_.Exception.InnerException) { $xmlErrMsg = $_.Exception.InnerException.Message }
                        New-OtterXmlRuntimeError -Text $xmlErrMsg -Line $Expression.Line
                    }
                    return [OtterXml]::new($doc)
                }
                ([XmlSourceKind]::Root) {
                    $rootName = Get-OtterText -Expression $Expression.Value -Environment $Environment
                    $doc = [System.Xml.XmlDocument]::new()
                    $rootElem = $doc.CreateElement($rootName)
                    [void]$doc.AppendChild($rootElem)
                    return [OtterXml]::new($doc)
                }
            }
        }

        # element "book" in document / elements "book" in document /
        # child 0 in book / children ... in book                        (D105)
        # element/elements search DIRECT children by TAG NAME; child
        # selects the Nth direct child element by POSITION (0-based, the
        # only way "child"/"element" are meaningfully different words);
        # children returns every direct child element (the selector
        # value exists only for grammatical symmetry with "child N").
        'XmlSelect' {
            $xml = Get-OtterValue -Expression $Expression.Xml -Environment $Environment
            if (-not (Test-OtterXml $xml)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only look for elements in xml, but this is $(Get-OtterTypeName -Value $xml)." `
                    -Line $Expression.Line)
            }
            switch ($Expression.SelectKind) {
                ([XmlSelectKind]::Element) {
                    $name = Get-OtterText -Expression $Expression.Selector -Environment $Environment
                    $found = Find-OtterXmlChildElementsByName -Node $xml.Node -Name $name
                    if ($found.Count -eq 0) { return $null }
                    return [OtterXml]::new($found[0])
                }
                ([XmlSelectKind]::Elements) {
                    $name = Get-OtterText -Expression $Expression.Selector -Environment $Environment
                    $found = Find-OtterXmlChildElementsByName -Node $xml.Node -Name $name
                    $list = New-OtterList
                    foreach ($f in $found) { [void]$list.Add([OtterXml]::new($f)) }
                    # -NoEnumerate matters here too - see the "attributes"
                    # property case's own comment above for why a bare
                    # `return $list` is a real, confirmed bug for this
                    # exact list-of-OtterXml shape.
                    Write-Output -NoEnumerate $list
                    return
                }
                ([XmlSelectKind]::Child) {
                    $index = Assert-OtterNumber -Value (Get-OtterValue -Expression $Expression.Selector -Environment $Environment) -Line $Expression.Line -What 'a child index'
                    $children = Get-OtterXmlChildElements -Node $xml.Node
                    $i = [int]$index
                    if ($i -lt 0 -or $i -ge $children.Count) { return $null }
                    return [OtterXml]::new($children[$i])
                }
                ([XmlSelectKind]::Children) {
                    $children = Get-OtterXmlChildElements -Node $xml.Node
                    $list = New-OtterList
                    foreach ($c in $children) { [void]$list.Add([OtterXml]::new($c)) }
                    Write-Output -NoEnumerate $list
                    return
                }
            }
        }

        # attribute "id" of book                                        (D105)
        # A missing attribute reads as gone (D22), not an error - matches
        # the interpreter's own dynamic-key-access precedent.
        'XmlAttribute' {
            $name = Get-OtterText -Expression $Expression.Name -Environment $Environment
            $elem = Get-OtterValue -Expression $Expression.Element -Environment $Environment
            if (-not (Test-OtterXml $elem)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only read an attribute of an xml element, but this is $(Get-OtterTypeName -Value $elem)." `
                    -Line $Expression.Line)
            }
            Assert-OtterXmlElement -Xml $elem -Line $Expression.Line -What 'read an attribute of'
            if (-not $elem.Node.HasAttribute($name)) { return $null }
            return $elem.Node.GetAttribute($name)
        }

        # text of "title" in book - sugar over text of (element "title" in book)   (D105)
        'XmlTextOfNameIn' {
            $name = Get-OtterText -Expression $Expression.Name -Environment $Environment
            $xml = Get-OtterValue -Expression $Expression.Xml -Environment $Environment
            if (-not (Test-OtterXml $xml)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only look for elements in xml, but this is $(Get-OtterTypeName -Value $xml)." `
                    -Line $Expression.Line)
            }
            $found = Find-OtterXmlChildElementsByName -Node $xml.Node -Name $name
            if ($found.Count -eq 0) {
                throw (New-OtterRuntimeError `
                    -Message "I couldn't find an element called ""$name""." `
                    -Line $Expression.Line)
            }
            return $found[0].InnerText
        }

        # element "book" exists in document                             (D105)
        'XmlElementExists' {
            $xml = Get-OtterValue -Expression $Expression.Xml -Environment $Environment
            if (-not (Test-OtterXml $xml)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only look for elements in xml, but this is $(Get-OtterTypeName -Value $xml)." `
                    -Line $Expression.Line)
            }
            $name = Get-OtterText -Expression $Expression.Selector -Environment $Environment
            return ((Find-OtterXmlChildElementsByName -Node $xml.Node -Name $name).Count -gt 0)
        }

        # book has attribute "id"                                       (D105)
        'XmlHasAttribute' {
            $elem = Get-OtterValue -Expression $Expression.Element -Environment $Environment
            if (-not (Test-OtterXml $elem)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only ask whether an xml element has an attribute, but this is $(Get-OtterTypeName -Value $elem)." `
                    -Line $Expression.Line)
            }
            Assert-OtterXmlElement -Xml $elem -Line $Expression.Line -What 'ask about an attribute of'
            $name = Get-OtterText -Expression $Expression.Name -Environment $Environment
            return $elem.Node.HasAttribute($name)
        }

        # text from xml document / pretty text from xml document        (D105)
        'XmlToText' {
            $xml = Get-OtterValue -Expression $Expression.Xml -Environment $Environment
            if (-not (Test-OtterXml $xml)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only read text from xml, but this is $(Get-OtterTypeName -Value $xml)." `
                    -Line $Expression.Line)
            }
            if (-not $Expression.Pretty) { return $xml.Node.OuterXml }
            # A StringBuilder-backed XmlWriter always reports "utf-16" in
            # its own declaration, regardless of the Encoding setting
            # (confirmed directly - a real .NET quirk, not an Otter bug:
            # a StringBuilder is inherently UTF-16 text, and the writer
            # is technically correct to say so). A MemoryStream-backed
            # writer instead honors UTF-8 for real, matching what
            # Write-OtterFile actually saves to disk - no misleading
            # declaration either way.
            $ms = [System.IO.MemoryStream]::new()
            $settings = [System.Xml.XmlWriterSettings]::new()
            $settings.Indent = $true
            $settings.IndentChars = '  '
            $settings.OmitXmlDeclaration = ($xml.Node -isnot [System.Xml.XmlDocument])
            $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
            $writer = [System.Xml.XmlWriter]::Create($ms, $settings)
            try {
                $xml.Node.WriteTo($writer)
                $writer.Flush()
                return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
            } finally {
                $writer.Close()
            }
        }

        # days between startDate and endDate                            (D42)
        #
        # A genuine value, so it evaluates the same way Get-OtterValue
        # evaluates everything else - usable in "is", in "say", inside a
        # condition, as a function argument. Same calculation as the
        # legacy statement form (D32.7: signed, end minus start, whole
        # units truncated toward zero) - Assert-OtterDateOperands and
        # Measure-OtterDateDifference are the SAME functions the
        # 'DateDifference' statement case above calls, not a second copy.
        'DateDifferenceValue' {
            $start = Get-OtterValue -Expression $Expression.Start -Environment $Environment
            $end = Get-OtterValue -Expression $Expression.End -Environment $Environment
            Assert-OtterDateOperands -Start $start -End $end -Line $Expression.Line

            return (Measure-OtterDateDifference -Start $start -End $end -Unit $Expression.Unit.ToString())
        }

        # D56: not part of Otter 1.0 - there is no real asynchronicity
        # anywhere in this interpreter, so this previously just forwarded
        # the inner value transparently, silently pretending to be a
        # working "await" rather than admitting there is nothing to wait
        # for yet.
        'Await' {
            throw (New-OtterRuntimeError -Message "'await' is not supported in Otter 1.0." -Line $Expression.Line)
        }

        'UiElement' {
            if ($null -ne $Expression.Children) {
                Invoke-OtterStatements -Statements $Expression.Children -Environment $Environment
            }
            return $Expression
        }

        default {
            throw (New-OtterRuntimeError `
                -Message "I do not know how to work out a $($Expression.Kind) value yet." `
                -Line $Expression.Line)
        }
    }
}


# ===============================================================
# CALLING A FUNCTION
# ===============================================================
#
# A call gets a brand new scope whose parent is the GLOBAL scope - never the
# caller's scope. That is what makes this print "Outside" at the end:
#
#     name is "Outside"
#     to greet name
#         say "Hello" name
#     greet "Jeff"
#     say name

function Invoke-OtterCall {
    param([CallExpr]$Call, [OtterEnvironment]$Environment)

    $name = $Call.Name

    if (-not $Environment.Has($name)) {
        throw (New-OtterRuntimeError `
            -Message "Otter could not find anything called `"$name`"." `
            -Line $Call.Line `
            -Suggestion "to $name")
    }

    $target = $Environment.Get($name)
    if ($target -isnot [OtterFunction]) {
        throw (New-OtterRuntimeError `
            -Message "`"$name`" is not something Otter can do - it holds $(Get-OtterTypeName $target)." `
            -Line $Call.Line)
    }

    $expected = $target.Parameters.Count
    $given = $Call.Arguments.Count
    if ($given -ne $expected) {
        $wordExpected = if ($expected -eq 1) { 'value' } else { 'values' }
        throw (New-OtterRuntimeError `
            -Message "`"$name`" needs $expected $wordExpected but was given $given." `
            -Line $Call.Line `
            -Suggestion "$name $($target.Parameters -join ' ')")
    }

    # Arguments are worked out in the CALLER's scope, before the new one exists.
    $arguments = [System.Collections.Generic.List[object]]::new()
    foreach ($argument in $Call.Arguments) {
        $arguments.Add((Get-OtterValue -Expression $argument -Environment $Environment))
    }

    $local = [OtterEnvironment]::new($script:GlobalEnvironment)
    for ($i = 0; $i -lt $expected; $i++) {
        # SetLocal, not Set: a parameter always shadows an outer variable of the
        # same name rather than overwriting it.
        $local.SetLocal($target.Parameters[$i], $arguments[$i])
    }

    if ($script:CallStack.Count -ge 250) {
        throw (New-OtterRuntimeError -Message 'Call depth limit exceeded (possible infinite recursion).' -Line $Call.Line -Suggestion 'Check for infinite recursion or reduce call nesting.')
    }

    # Otter call frame: which function, called from which Otter source line,
    # with which local scope. Pushed/popped around the body so a debugger (or
    # anything else) asking "what is Otter's call stack right now" gets a
    # real answer in Otter terms - never a PowerShell call stack.
    $frame = [pscustomobject]@{ FunctionName = $name; CallLine = $Call.Line; Environment = $local }
    [void]$script:CallStack.Add($frame)
    try {
        try {
            # Fast path: a `return` written directly in the function body (the
            # overwhelmingly common shape) ends the call right here. Only a
            # `return` nested inside an if/loop needs to unwind through
            # OtterReturnSignal, and throwing an exception is by far the most
            # expensive thing this interpreter does per call.
            foreach ($bodyStatement in $target.Body) {
                if ($bodyStatement.Kind -eq [NodeKind]::Return) {
                    if ($null -ne $script:StatementHook) {
                        & $script:StatementHook -Statement $bodyStatement -Environment $local -CallStack $script:CallStack
                    }
                    $returned = $null
                    if ($null -ne $bodyStatement.Value) {
                        $returned = Get-OtterValue -Expression $bodyStatement.Value -Environment $local
                    }
                    Write-Output -NoEnumerate $returned
                    return
                }
                Invoke-OtterStatement -Statement $bodyStatement -Environment $local
            }
        }
        catch {
            # "return" is control flow wearing an exception's clothes.
            if ($_.Exception -is [OtterReturnSignal]) {
                Write-Output -NoEnumerate $_.Exception.Value
                return
            }
            throw
        }

        # A function that never returns anything produces nothing.
        return $null
    }
    finally {
        $script:CallStack.RemoveAt($script:CallStack.Count - 1)
    }
}


# ===============================================================
# HELPERS
# ===============================================================

# ===============================================================
# ASSIGNMENT TARGETS
# ===============================================================
#
# D19: anything assignable is an expression node, so adding list indexing
# later means adding a case here, not a second kind of statement.

function Set-OtterTarget {
    param([Node]$Target, [object]$Value, [OtterEnvironment]$Environment)

    switch ($Target.Kind.ToString()) {

        'Variable' {
            $Environment.Set($Target.Name, $Value)
            return
        }

        # age of person is 30
        'PropertyAccess' {
            $owner = Get-OtterValue -Expression $Target.Target -Environment $Environment

            # text of helloButton is "Say Hello"                     (D45)
            if (Test-OtterUiResource $owner) {
                Set-OtterUiProperty -Resource $owner -Property $Target.Property -Value $Value -Line $Target.Line
                return
            }

            if (-not (Test-OtterObject $owner)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only set properties on a thing, but this is $(Get-OtterTypeName $owner)." `
                    -Line $Target.Line)
            }

            $owner.WriteProperty($Target.Property, $Value)
            return
        }

        default {
            throw (New-OtterRuntimeError `
                -Message 'This is not something Otter can give a value to.' `
                -Line $Target.Line)
        }
    }
}

# Builds the object for "person is a thing" and its indented property lines.
#
# A named custom type - "jeff is a Person" - starts with that type's fields
# already present but empty, so "name of jeff" reads as nothing rather than
# failing.
function New-OtterObjectValue {
    param([Node]$Statement, [OtterEnvironment]$Environment)

    $object = [OtterObject]::new($Statement.TypeName)

    if ($Statement.TypeName -ne 'thing' -and $Environment.Has($Statement.TypeName)) {
        $declared = $Environment.Get($Statement.TypeName)
        if ($declared -is [OtterType]) {
            foreach ($field in $declared.FieldNames) { $object.WriteProperty($field, $null) }
        }
    }

    foreach ($property in $Statement.Properties) {
        if ($property.Kind -ne [NodeKind]::Assign) {
            throw (New-OtterRuntimeError `
                -Message 'Only properties belong inside a thing.' `
                -Line $property.Line)
        }
        if ($property.Target.Kind -ne [NodeKind]::Variable) {
            throw (New-OtterRuntimeError `
                -Message 'A property name inside a thing must be a plain name.' `
                -Line $property.Line)
        }
        $value = Get-OtterValue -Expression $property.Value -Environment $Environment
        $object.WriteProperty($property.Target.Name, $value)
    }

    return $object
}

# sort and reverse change a list where it stands, so they need the real list
# object out of the environment rather than a copy of it.
function Get-OtterMutableList {
    param([string]$Name, [OtterEnvironment]$Environment, [int]$Line, [string]$Verb)

    if (-not $Environment.Has($Name)) {
        throw (New-OtterRuntimeError -Message "Otter could not find the variable ""$Name""." -Line $Line)
    }

    $value = $Environment.Get($Name)
    if (-not (Test-OtterList $value)) {
        throw (New-OtterRuntimeError `
            -Message "I can only $Verb a list, but ""$Name"" holds $(Get-OtterTypeName $value)." `
            -Line $Line)
    }

    # -NoEnumerate again: returning a List from a PowerShell function unrolls
    # it, so the caller would get the first ITEM instead of the list itself.
    Write-Output -NoEnumerate $value
}

# File operations accept a path the programmer typed OR a file object with a
# path property, because rules.md passes both:
#
#     move "hello.txt" to "Documents"     <- text
#     move file to "Pictures"             <- a file object
function Get-OtterPathArgument {
    param([Node]$Expression, [OtterEnvironment]$Environment)
    $value = Get-OtterValue -Expression $Expression -Environment $Environment
    return (Resolve-OtterFileArgument -Value $value -Line $Expression.Line)
}

# File names and commands are text. Evaluating them through Format-OtterValue
# means a path can be built from variables and still arrive as a plain string:
#
#     name is "notes"
#     read name into contents      <- would read the file named "notes"
function Get-OtterText {
    param([Node]$Expression, [OtterEnvironment]$Environment)
    $value = Get-OtterValue -Expression $Expression -Environment $Environment
    return (Format-OtterValue -Value $value)
}

# D32.1: hour/minute/second belong to a date AND time. Asking a plain date
# for its hour is a mistake, not a zero.
$script:DateOnlyUnits = @('Year', 'Month', 'Day')

function Assert-OtterUnitAllowed {
    param([object]$Value, [string]$Unit, [int]$Line)

    if ($Value.HasTime) { return }
    if ($script:DateOnlyUnits -contains $Unit) { return }

    throw (New-OtterRuntimeError `
        -Message "This is a date with no time of day, so it has no $($Unit.ToLowerInvariant())." `
        -Line $Line `
        -Suggestion 'started is now')
}

# year of date / month of date / hour of started ...
function Get-OtterDatePart {
    param([object]$Date, [string]$Part, [int]$Line)

    switch ($Part) {
        'year' { return [double]$Date.Value.Year }
        'month' { return [double]$Date.Value.Month }   # 1-12, never a name
        'day' { return [double]$Date.Value.Day }
        'hour' {
            Assert-OtterUnitAllowed -Value $Date -Unit 'Hour' -Line $Line
            return [double]$Date.Value.Hour
        }
        'minute' {
            Assert-OtterUnitAllowed -Value $Date -Unit 'Minute' -Line $Line
            return [double]$Date.Value.Minute
        }
        'second' {
            Assert-OtterUnitAllowed -Value $Date -Unit 'Second' -Line $Line
            return [double]$Date.Value.Second
        }
    }

    throw (New-OtterRuntimeError `
        -Message "A date has no part called ""$Part""." `
        -Line $Line `
        -Suggestion "year of ...")
}

# D42: shared by DateDifferenceStmt (legacy) and DateDifferenceExpr, so the
# validation is written once and both forms report it identically. Factored
# out of the statement case, not duplicated into the new expression case.
function Assert-OtterDateOperands {
    param([object]$Start, [object]$End, [int]$Line)

    foreach ($side in @(@('first', $Start), @('second', $End))) {
        if (-not (Test-OtterDate $side[1])) {
            throw (New-OtterRuntimeError `
                -Message "I can only measure time between two dates, but the $($side[0]) one is $(Get-OtterTypeName $side[1])." `
                -Line $Line)
        }
    }
}

# Whole units, truncated toward zero, signed end-minus-start (D32.7).
function Measure-OtterDateDifference {
    param([object]$Start, [object]$End, [string]$Unit)

    $from = $Start.Value
    $to = $End.Value

    if ($Unit -eq 'Year' -or $Unit -eq 'Month') {
        # Calendar months, not averaged days: Jan 31 to Feb 28 is one month.
        $months = (($to.Year - $from.Year) * 12) + ($to.Month - $from.Month)
        if ($months -gt 0 -and $to.Day -lt $from.Day) { $months-- }
        if ($months -lt 0 -and $to.Day -gt $from.Day) { $months++ }
        if ($Unit -eq 'Month') { return [double]$months }
        return [double][Math]::Truncate($months / 12)
    }

    $span = $to - $from
    switch ($Unit) {
        'Day' { return [double][Math]::Truncate($span.TotalDays) }
        'Hour' { return [double][Math]::Truncate($span.TotalHours) }
        'Minute' { return [double][Math]::Truncate($span.TotalMinutes) }
        'Second' { return [double][Math]::Truncate($span.TotalSeconds) }
    }
    return 0.0
}

# Type names as a beginner would say them, for error messages.
function Get-OtterTypeName {
    param([object]$Value)

    if ($null -eq $Value) { return 'gone' }
    if ($Value -is [bool]) { return 'a true or false value' }
    if ($Value -is [OtterFunction]) { return 'something Otter can do' }
    if (Test-OtterUiResource $Value) { return "a $($Value.Kind)" }
    if (Test-OtterDate $Value) {
        if ($Value.HasTime) { return 'a date and time' }
        return 'a date'
    }
    if (Test-OtterObject $Value) { return "a $($Value.TypeName)" }
    if ($Value -is [OtterType]) { return "the type $($Value.Name)" }
    if (Test-OtterBytes $Value) { return 'bytes' }
    if (Test-OtterFileWatcher $Value) { return 'a file watcher' }
    if (Test-OtterXml $Value) { return 'xml' }
    if (Test-OtterWebSocket $Value) { return 'a websocket' }
    if (Test-OtterTcp $Value) { return 'a tcp connection' }
    if (Test-OtterUdp $Value) { return 'a udp socket' }
    if (Test-OtterTcpServer $Value) { return 'a tcp server' }
    if (Test-OtterHttpRequest $Value) { return 'an http request' }
    if (Test-OtterCommandJob $Value) { return 'a command job' }
    if (Test-OtterList $Value) { return 'a list' }
    if ($Value -is [double] -or $Value -is [int] -or $Value -is [long]) { return 'a number' }
    if ($Value -is [string]) { return 'some text' }
    return 'a value Otter does not recognise'
}

function New-OtterEnvironment {
    param([object[]]$Arguments = @())
    $env = [OtterEnvironment]::new()
    $argList = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Arguments) {
        foreach ($arg in $Arguments) {
            $argList.Add([string]$arg)
        }
    }
    $env.Set('arguments', $argList)
    return $env
}


Export-ModuleMember -Function `
    Invoke-OtterProgram, Invoke-OtterStatements, Invoke-OtterStatement, `
    Get-OtterValue, Invoke-OtterCall, New-OtterEnvironment, Get-OtterTypeName, `
    Set-OtterOutputWriter, Set-OtterDiagnosticWriter, Write-OtterLine, Get-OtterText, Get-OtterPathArgument, Set-OtterTarget, `
    Set-OtterStatementHook, Get-OtterCallStackSnapshot, Set-OtterApplicationId
