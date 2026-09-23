# tests/WebSocket.Tests.ps1
#
# Production-entry-point certification for D106 (WebSockets) on the CONSOLE
# target - see rules.md: real background events, network connections,
# and streaming protocols are verified through real execution, not mocks.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'WebSockets (D106)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'

# High-performance in-process C# loopback server for testing
$wsServerTypeDef = @'
using System;
using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public class OtterTestWsServer : IDisposable {
    private HttpListener _listener;
    private int _port;
    private CancellationTokenSource _cts = new CancellationTokenSource();

    public int Port { get { return _port; } }

    public static OtterTestWsServer StartEcho() {
        var s = new OtterTestWsServer();
        s.Init();
        Task.Run(async () => {
            try {
                var ctx = await s._listener.GetContextAsync();
                var wsCtx = await ctx.AcceptWebSocketAsync(null);
                var ws = wsCtx.WebSocket;
                var buf = new byte[4096];
                while (ws.State == WebSocketState.Open && !s._cts.IsCancellationRequested) {
                    var res = await ws.ReceiveAsync(new ArraySegment<byte>(buf), s._cts.Token);
                    if (res.MessageType == WebSocketMessageType.Close) {
                        await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "done", s._cts.Token);
                        break;
                    }
                    if (res.MessageType == WebSocketMessageType.Text) {
                        string text = Encoding.UTF8.GetString(buf, 0, res.Count);
                        byte[] echoBytes = Encoding.UTF8.GetBytes("Echo: " + text);
                        await ws.SendAsync(new ArraySegment<byte>(echoBytes), WebSocketMessageType.Text, true, s._cts.Token);
                    } else if (res.MessageType == WebSocketMessageType.Binary) {
                        byte[] resp = new byte[] { 10, 20, 30 };
                        await ws.SendAsync(new ArraySegment<byte>(resp), WebSocketMessageType.Binary, true, s._cts.Token);
                    }
                }
            } catch {}
        });
        return s;
    }

    public static OtterTestWsServer StartCustomClose(int code, string reason) {
        var s = new OtterTestWsServer();
        s.Init();
        Task.Run(async () => {
            try {
                var ctx = await s._listener.GetContextAsync();
                var wsCtx = await ctx.AcceptWebSocketAsync(null);
                var ws = wsCtx.WebSocket;
                var buf = new byte[4096];
                await ws.ReceiveAsync(new ArraySegment<byte>(buf), s._cts.Token);
                await ws.CloseAsync((WebSocketCloseStatus)code, reason, s._cts.Token);
            } catch {}
        });
        return s;
    }

    private void Init() {
        var tcp = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        tcp.Start();
        _port = ((IPEndPoint)tcp.LocalEndpoint).Port;
        tcp.Stop();

        _listener = new HttpListener();
        _listener.Prefixes.Add("http://127.0.0.1:" + _port + "/");
        _listener.Start();
    }

    public void Dispose() {
        try { _cts.Cancel(); } catch {}
        try { _listener.Stop(); } catch {}
        try { _listener.Close(); } catch {}
    }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'OtterTestWsServer').Type) {
    Add-Type -TypeDefinition $wsServerTypeDef
}

function Invoke-OtterWsProgram {
    param([string]$Source, [int]$TimeoutMs = 10000)

    $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d106_$([Guid]::NewGuid().ToString('N')).ot")
    [System.IO.File]::WriteAllText($tmpFile, $Source, [System.Text.UTF8Encoding]::new($false))
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:OtterPs1`" run `"$tmpFile`""
        $psi.WorkingDirectory = $script:RepoRoot
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi
        [void]$process.Start()
        $exited = $process.WaitForExit($TimeoutMs)
        if (-not $exited) {
            try { $process.Kill() } catch {}
        }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        return [pscustomobject]@{
            Stdout = $stdout
            Stderr = $stderr
            ExitCode = $process.ExitCode
            TimedOut = (-not $exited)
        }
    } finally {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    }
}


# --- 1. Full connect -> open -> send -> echo -> close lifecycle -----------

Test-Otter 'full connect, send, message echo, and close lifecycle' {
    $server = [OtterTestWsServer]::StartEcho()
    try {
        $port = $server.Port
        $res = Invoke-OtterWsProgram -Source @"
connect to websocket "ws://127.0.0.1:$port/" and call it socket

on open of socket
    say "opened"
    send "Hello, Otter!" through socket
.

on message from socket
    say received message
    close websocket socket with code 1000 and reason "Finished"
.

on close of socket
    say "closed cleanly"
.
"@
        Assert-AreEqual 0 $res.ExitCode 'program exited cleanly'
        Assert-AreEqual ("opened`r`nEcho: Hello, Otter!`r`nclosed cleanly" -replace "`r`n", "`n") $res.Stdout.Trim() 'expected output sequence'
    } finally {
        $server.Dispose()
    }
}


# --- 2. Binary frame transmission with bytes type -----------------------

Test-Otter 'binary message send and receive with bytes type' {
    $server = [OtterTestWsServer]::StartEcho()
    try {
        $port = $server.Port
        $res = Invoke-OtterWsProgram -Source @"
connect to websocket "ws://127.0.0.1:$port/" and call it socket

on open of socket
    b is bytes from text "ABC"
    send b through socket
.

on message from socket
    m is received message
    say length of m
    close websocket socket
.

on close of socket
    say "closed"
.
"@
        Assert-AreEqual 0 $res.ExitCode 'program exited cleanly'
        Assert-AreEqual ("3`r`nclosed" -replace "`r`n", "`n") $res.Stdout.Trim() 'received 3 bytes'
    } finally {
        $server.Dispose()
    }
}


# --- 3. Properties and state predicate expressions ---------------------

Test-Otter 'state, url, and state predicates reflect connection life' {
    $server = [OtterTestWsServer]::StartEcho()
    try {
        $port = $server.Port
        $res = Invoke-OtterWsProgram -Source @"
connect to websocket "ws://127.0.0.1:$port/" and call it socket

say url of socket

if socket is connecting
    say "initially connecting"
.

on open of socket
    if socket is open
        say "is open"
    .
    close websocket socket
.

on close of socket
    say "closed"
.
"@
        Assert-AreEqual 0 $res.ExitCode 'program exited cleanly'
        Assert-True ($res.Stdout -match "ws://127.0.0.1:$port/") 'url of socket matches'
        Assert-True ($res.Stdout -match "is open") 'socket is open predicate succeeded'
    } finally {
        $server.Dispose()
    }
}


# --- 4. Close code, reason, and clean flag propagation ------------------

Test-Otter 'close code, close reason, and close was clean capture peer status' {
    $server = [OtterTestWsServer]::StartCustomClose(4001, "Maintenance reboot")
    try {
        $port = $server.Port
        $res = Invoke-OtterWsProgram -Source @"
connect to websocket "ws://127.0.0.1:$port/" and call it socket

on open of socket
    send "ready" through socket
.

on close of socket
    say close code
    say close reason
    if close was clean
        say "clean"
    otherwise
        say "unclean"
    .
.
"@
        Assert-AreEqual 0 $res.ExitCode 'program exited cleanly'
        Assert-True ($res.Stdout -match "4001") 'close code matches'
        Assert-True ($res.Stdout -match "Maintenance reboot") 'close reason matches'
    } finally {
        $server.Dispose()
    }
}


# --- 5. Connection failure triggers on error and on close ---------------

Test-Otter 'connection failure triggers error and close handlers' {
    # Port 28399 is not listening
    $res = Invoke-OtterWsProgram -Source @'
connect to websocket "ws://127.0.0.1:28399/" and call it socket

on error of socket
    say "got error"
.

on close of socket
    say "got close"
.
'@
    Assert-AreEqual 0 $res.ExitCode 'program completed event loop cleanly'
    Assert-True ($res.Stdout -match "got error") 'on error fired'
    Assert-True ($res.Stdout -match "got close") 'on close fired'
}


# --- 6. Invalid websocket URL is rejected cleanly -----------------------

Test-Otter 'invalid websocket URL is rejected at runtime' {
    $res = Invoke-OtterWsProgram -Source @'
connect to websocket "http://example.com" and call it socket
'@
    Assert-AreEqual 3 $res.ExitCode 'failed with runtime error'
    Assert-True ($res.Stdout -match "ws://" -or $res.Stderr -match "ws://") 'error mentions ws:// or wss://'
}


# --- 7. Sending through non-open socket is rejected ---------------------

Test-Otter 'sending through closed socket is rejected with informative error' {
    $res = Invoke-OtterWsProgram -Source @'
connect to websocket "ws://127.0.0.1:28399/" and call it socket

on close of socket
    send "Hello" through socket
.
'@
    Assert-AreEqual 3 $res.ExitCode 'failed with runtime error'
    Assert-True ($res.Stdout -match "cannot send through a websocket that is not open" -or $res.Stderr -match "cannot send through a websocket that is not open") 'states socket is not open'
}


# --- 8. Ambient variables outside event blocks produce clean errors -----

Test-Otter 'received message outside on message handler is rejected' {
    $res = Invoke-OtterWsProgram -Source @'
say received message
'@
    Assert-AreEqual 3 $res.ExitCode 'runtime error for ambient access'
    Assert-True ($res.Stdout -match 'received message' -or $res.Stderr -match 'received message') 'clear diagnostic'
}


# --- 9. WebSocket identifiers remain valid ordinary names ---------------

Test-Otter 'websocket and protocol keywords remain valid ordinary variables' {
    $res = Invoke-OtterWsProgram -Source @'
websocket is "secure channel"
protocol is "json-rpc"
message is "hello world"
socket is "42"
say websocket plus ", " plus protocol plus ", " plus message plus ", " plus socket
'@
    Assert-AreEqual 0 $res.ExitCode 'variables named websocket/protocol/message work'
    Assert-AreEqual "secure channel, json-rpc, hello world, 42" $res.Stdout.Trim() 'output matches'
}

Complete-OtterTests
