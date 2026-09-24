# tests/Network.Tests.ps1
#
# Production-entry-point certification for D107 (TCP) and D108 (UDP).
# Every test spawns the REAL otter.ps1 process and talks to it over REAL
# loopback sockets owned by this test process.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'TCP and UDP (D107, D108)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'

function Start-OtterNetProcess {
    param([string]$Source, [string]$Mode = 'run')
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_net_$([Guid]::NewGuid().ToString('N'))")
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $otFile = Join-Path $dir 'program.ot'
    [System.IO.File]::WriteAllText($otFile, $Source, [System.Text.UTF8Encoding]::new($false))
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'powershell.exe'
    $extra = if ($Mode -eq 'web') { ' -NoOpen' } else { '' }
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:OtterPs1`" $Mode `"$otFile`"$extra"
    $psi.WorkingDirectory = $dir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    return [pscustomobject]@{ Process = $process; Dir = $dir; Out = $process.StandardOutput.ReadToEndAsync() }
}

function Complete-OtterNetProcess {
    param($Handle, [int]$TimeoutMs = 30000)
    $exited = $Handle.Process.WaitForExit($TimeoutMs)
    if (-not $exited) { try { $Handle.Process.Kill() } catch {} }
    $stdout = $Handle.Out.Result
    Remove-Item -LiteralPath $Handle.Dir -Recurse -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Stdout = $stdout; TimedOut = (-not $exited); Lines = @(($stdout -split "`r?`n") | Where-Object { $_ -ne '' }) }
}

function Get-FreeTcpPort {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
    return $port
}

# --- 1. TCP: connect, send bytes, receive bytes, close --------------------

Test-Otter 'tcp client connects, sends bytes, receives bytes in on data, and closes' {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    try {
        $h = Start-OtterNetProcess -Source @"
connect to tcp "localhost" on port $port and call it connection

on connect of connection
    message is bytes from text "Hello from Otter"
    send message through connection
    if connection is connected
        say "connected"
    .
    say state of connection
    say remote port of connection
.

on data from connection
    data is received data
    say text from bytes data
    say count of data
    close tcp connection
.

on error of connection
    say network error
.

on close of connection
    say "Disconnected"
    say state of connection
    if connection is closed
        say "is closed"
    .
.
"@
        $accept = $listener.AcceptTcpClientAsync()
        Assert-True $accept.Wait(30000) 'expected the Otter program to connect'
        $stream = $accept.Result.GetStream()
        $buf = [byte[]]::new(64)
        $read = $stream.ReadAsync($buf, 0, 64)
        Assert-True $read.Wait(10000) 'expected the server to receive bytes'
        Assert-AreEqual -Expected 'Hello from Otter' -Actual ([System.Text.Encoding]::UTF8.GetString($buf, 0, $read.Result))
        $reply = [System.Text.Encoding]::UTF8.GetBytes('Echo: hi')
        $stream.Write($reply, 0, $reply.Length)
        $r = Complete-OtterNetProcess $h
        Assert-False $r.TimedOut 'expected the program to finish after closing'
        Assert-Lines -Expected @('connected', 'connected', "$port", 'Echo: hi', '8', 'Disconnected', 'closed', 'is closed') -Actual $r.Lines
    } finally { $listener.Stop() }
}

# --- 2. TCP: server closing the connection fires on close -------------------

Test-Otter 'tcp on close fires when the remote side closes' {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    try {
        $h = Start-OtterNetProcess -Source @"
connect to tcp "127.0.0.1" on port $port and call it connection
on data from connection
    say "data"
.
on close of connection
    say "remote closed"
    say remote address of connection
.
"@
        $accept = $listener.AcceptTcpClientAsync()
        Assert-True $accept.Wait(30000) 'expected the Otter program to connect'
        $accept.Result.Close()
        $r = Complete-OtterNetProcess $h
        Assert-False $r.TimedOut 'expected the program to finish when the remote closed'
        Assert-Lines -Expected @('remote closed', '127.0.0.1') -Actual $r.Lines
    } finally { $listener.Stop() }
}

# --- 3. TCP: connection refused reaches on error, then on close ---------------

Test-Otter 'tcp connection refused is delivered to on error, then on close' {
    $port = Get-FreeTcpPort
    $h = Start-OtterNetProcess -Source @"
connect to tcp "127.0.0.1" on port $port and call it connection
on error of connection
    say "error handled"
    say network error
.
on close of connection
    say "closed"
.
"@
    $r = Complete-OtterNetProcess $h
    Assert-False $r.TimedOut 'expected the program to finish'
    Assert-AreEqual -Expected 'error handled' -Actual $r.Lines[0]
    Assert-True ($r.Lines[1] -like "Could not connect to tcp 127.0.0.1 on port $port*") "unexpected network error text: $($r.Lines[1])"
    Assert-AreEqual -Expected 'closed' -Actual $r.Lines[2]
}

Test-Otter 'tcp connection refused with no error handler is a clean Otter error, not a PowerShell one' {
    $port = Get-FreeTcpPort
    $h = Start-OtterNetProcess -Source @"
connect to tcp "127.0.0.1" on port $port and call it connection
on close of connection
    say "closed"
.
"@
    $r = Complete-OtterNetProcess $h
    Assert-True ($r.Stdout -match 'Otter Runtime Error') 'expected an Otter runtime error'
    Assert-True ($r.Stdout -match 'Could not connect to tcp') 'expected the connect failure to be named'
    Assert-False ($r.Stdout -match 'at <ScriptBlock>|CategoryInfo') 'no raw PowerShell error should leak'
}

# --- 4. TCP: text is never silently converted to bytes --------------------------

Test-Otter 'sending text through tcp is refused - the text/bytes boundary is explicit' {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    try {
        $h = Start-OtterNetProcess -Source @"
connect to tcp "127.0.0.1" on port $port and call it connection
on connect of connection
    send "Hello" through connection
.
"@
        $accept = $listener.AcceptTcpClientAsync()
        Assert-True $accept.Wait(30000) 'expected the Otter program to connect'
        $r = Complete-OtterNetProcess $h
        Assert-True ($r.Stdout -match 'I can only send bytes through a tcp connection') 'expected the bytes-only diagnostic'
        Assert-True ($r.Stdout -match 'never converts text to bytes silently') 'expected the explicit-boundary explanation'
    } finally { $listener.Stop() }
}

# --- 5. UDP: datagram in, sender info, datagram out ------------------------------

Test-Otter 'udp receives a datagram with sender address/port and replies to the sender' {
    $tmp = [System.Net.Sockets.UdpClient]::new(0)
    $port = ([System.Net.IPEndPoint]$tmp.Client.LocalEndPoint).Port
    $tmp.Close()
    $h = Start-OtterNetProcess -Source @"
open udp on port $port and call it socket
say state of socket
if socket is open
    say "is open"
.

on data from socket
    say "Received from" sender address
    say text from bytes received data
    response is bytes from text "Hello"
    send response through socket
        to sender address
        on port sender port
    close udp socket
.

on close of socket
    say "closed"
    if socket is closed
        say "is closed"
    .
.
"@
    $client = [System.Net.Sockets.UdpClient]::new()
    $client.Client.ReceiveTimeout = 1000
    $reply = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(40)
    while (-not $reply -and [DateTime]::UtcNow -lt $deadline) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes('ping')
        [void]$client.Send($bytes, $bytes.Length, '127.0.0.1', $port)
        try {
            $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
            $reply = [System.Text.Encoding]::UTF8.GetString($client.Receive([ref]$remote))
        } catch { Start-Sleep -Milliseconds 500 }
    }
    $client.Close()
    Assert-AreEqual -Expected 'Hello' -Actual $reply
    $r = Complete-OtterNetProcess $h
    Assert-False $r.TimedOut 'expected the program to finish after closing'
    Assert-Lines -Expected @('open', 'is open', 'Received from 127.0.0.1', 'ping', 'closed', 'is closed') -Actual $r.Lines
}

# --- 6. UDP: open with an automatic port, send to another socket ---------------

Test-Otter 'udp open without a port picks one, and send delivers a datagram' {
    $receiver = [System.Net.Sockets.UdpClient]::new(0)
    $receiver.Client.ReceiveTimeout = 30000
    $port = ([System.Net.IPEndPoint]$receiver.Client.LocalEndPoint).Port
    try {
        $h = Start-OtterNetProcess -Source @"
open udp and call it socket
data is bytes from text "from otter"
send data through socket
    to "127.0.0.1"
    on port $port
close udp socket
say "sent"
"@
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        $got = [System.Text.Encoding]::UTF8.GetString($receiver.Receive([ref]$remote))
        Assert-AreEqual -Expected 'from otter' -Actual $got
        $r = Complete-OtterNetProcess $h
        Assert-Lines -Expected @('sent') -Actual $r.Lines
    } finally { $receiver.Close() }
}

Test-Otter 'sending text through udp is refused - bytes only' {
    $h = Start-OtterNetProcess -Source @"
open udp and call it socket
send "hello" through socket
    to "127.0.0.1"
    on port 9
"@
    $r = Complete-OtterNetProcess $h
    Assert-True ($r.Stdout -match 'I can only send bytes through a udp socket') 'expected the bytes-only diagnostic'
}

# --- 7. Grammar guards ---------------------------------------------------------------

Test-Otter 'udp send without a destination is refused with a clear message' {
    $h = Start-OtterNetProcess -Source @"
open udp and call it socket
data is bytes from text "x"
send data through socket
"@
    $r = Complete-OtterNetProcess $h
    Assert-True ($r.Stdout -match 'A udp send needs a destination') 'expected the destination diagnostic'
}

Test-Otter 'listen for tcp is reserved and reports that servers are not implemented' {
    $h = Start-OtterNetProcess -Source 'listen for tcp on port 8080 and call it server'
    $r = Complete-OtterNetProcess $h
    Assert-True ($r.Stdout -match 'reserved for TCP servers') 'expected the reserved-grammar diagnostic'
}

Test-Otter 'received data outside a data event is a clean Otter error' {
    $h = Start-OtterNetProcess -Source 'say received data'
    $r = Complete-OtterNetProcess $h
    Assert-True ($r.Stdout -match 'only available inside on data from') 'expected the context diagnostic'
}

# --- 8. Web target: unsupported, clearly ---------------------------------------------

foreach ($case in @(
    @{ Name = 'tcp connect'; Source = 'connect to tcp "localhost" on port 9000 and call it c'; Match = 'TCP is not supported on the web target' },
    @{ Name = 'udp open'; Source = 'open udp and call it s'; Match = 'UDP is not supported on the web target' }
)) {
    Test-Otter "$($case.Name) is rejected on the web target with a clean compile-time error" {
        $h = Start-OtterNetProcess -Source $case.Source -Mode 'web'
        $r = Complete-OtterNetProcess $h
        Assert-True ($r.Stdout -match $case.Match) "expected '$($case.Match)' but got: $($r.Stdout)"
    }
}

# --- 9. TLS over TCP (D112) --------------------------------------------------

function Test-PublicTlsReachable {
    try {
        $c = [System.Net.Sockets.TcpClient]::new([System.Net.Sockets.AddressFamily]::InterNetwork)
        $t = $c.ConnectAsync('example.com', 443)
        $ok = $t.Wait(8000) -and $c.Connected
        $c.Close()
        return $ok
    } catch { return $false }
}

Test-Otter 'connect securely to a real public TLS server: handshake succeeds, is secure, tls version reported, data flows' {
    if (-not (Test-PublicTlsReachable)) {
        Write-Host '        (skipped: example.com:443 is not reachable from this machine)' -ForegroundColor DarkYellow
        return
    }
    $h = Start-OtterNetProcess -Source @"
connect securely to tcp "example.com" on port 443 and call it connection
on connect of connection
    if connection is secure
        say "secure"
    .
    say tls version of connection
    request is bytes from hex "484541442F20485454502F312E300D0A0D0A"
    send request through connection
.
on data from connection
    say "got data"
    close tcp connection
.
on error of connection
    say network error
.
on close of connection
    say "closed"
.
"@
    $r = Complete-OtterNetProcess $h -TimeoutMs 60000
    Assert-False $r.TimedOut 'expected the program to finish'
    Assert-AreEqual -Expected 'secure' -Actual $r.Lines[0]
    Assert-True ($r.Lines[1] -match '^TLS 1\.[0-3]$') "unexpected tls version: $($r.Lines[1])"
    Assert-AreEqual -Expected 'got data' -Actual $r.Lines[2]
    Assert-AreEqual -Expected 'closed' -Actual $r.Lines[3]
}

Test-Otter 'a server with an untrusted (self-signed) certificate is REJECTED - certificate validation cannot be bypassed' {
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=localhost', $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $cert = $req.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1), [DateTimeOffset]::UtcNow.AddDays(1))
    $pfx = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, 'pw')
    $serverCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $pfx, 'pw', ([System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet))
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    try {
        $h = Start-OtterNetProcess -Source @"
connect securely to tcp "localhost" on port $port and call it connection
on connect of connection
    say "CONNECTED (must not happen)"
.
on error of connection
    say "rejected"
    say network error
.
on close of connection
    say "closed"
.
"@
        $accept = $listener.AcceptTcpClientAsync()
        Assert-True $accept.Wait(30000) 'expected the Otter program to open the TCP connection'
        try {
            $ssl = [System.Net.Security.SslStream]::new($accept.Result.GetStream(), $false)
            $ssl.AuthenticateAsServer($serverCert)   # the client will abort this handshake
        } catch { }
        $r = Complete-OtterNetProcess $h
        Assert-False $r.TimedOut 'expected the program to finish'
        Assert-False ($r.Stdout -match 'CONNECTED') 'an untrusted certificate must never yield a connected connection'
        Assert-AreEqual -Expected 'rejected' -Actual $r.Lines[0]
        Assert-True ($r.Lines[1] -match 'TLS handshake with localhost failed') "expected a clear handshake failure, got: $($r.Lines[1])"
        Assert-AreEqual -Expected 'closed' -Actual $r.Lines[2]
    } finally {
        $listener.Stop()
        try { $serverCert.PrivateKey | Out-Null } catch {}
    }
}

Test-Otter 'a plain tcp connection is not secure, and asking for its tls version is a clear error' {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    try {
        $h = Start-OtterNetProcess -Source @"
connect to tcp "127.0.0.1" on port $port and call it connection
on connect of connection
    if connection is secure
        say "WRONG"
    otherwise
        say "plain"
    .
    say tls version of connection
.
"@
        $accept = $listener.AcceptTcpClientAsync()
        Assert-True $accept.Wait(30000) 'expected the Otter program to connect'
        $r = Complete-OtterNetProcess $h
        Assert-AreEqual -Expected 'plain' -Actual $r.Lines[0]
        Assert-True ($r.Stdout -match 'not secure .* so it has no TLS version') 'expected the not-secure diagnostic'
    } finally { $listener.Stop() }
}

Test-Otter 'for server / using protocol are refused clearly (plain connection, or no ALPN on this runtime)' {
    $h = Start-OtterNetProcess -Source 'connect to tcp "localhost" for server "x.example" on port 9 and call it c'
    $r = Complete-OtterNetProcess $h
    Assert-True ($r.Stdout -match 'only apply to a secure connection') "expected the secure-only diagnostic, got: $($r.Stdout)"
    $h2 = Start-OtterNetProcess -Source 'connect securely to tcp "localhost" on port 9 using protocol "h2" and call it c'
    $r2 = Complete-OtterNetProcess $h2
    Assert-True ($r2.Stdout -match 'not available on this Otter runtime') "expected the ALPN diagnostic, got: $($r2.Stdout)"
}

Test-Otter 'connect securely is rejected on the web target' {
    $h = Start-OtterNetProcess -Source 'connect securely to tcp "example.com" on port 443 and call it c' -Mode 'web'
    $r = Complete-OtterNetProcess $h
    Assert-True ($r.Stdout -match 'TCP is not supported on the web target') "got: $($r.Stdout)"
}

Complete-OtterTests
