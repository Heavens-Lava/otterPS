# EventContract.Tests.ps1
#
# The Otter 1.0 event contract (SPEC-DECISIONS.md D121), through the real
# production entry point, on whichever PowerShell runs this file:
#
#   EV3  `wait` lets every active event source be serviced: TCP, UDP, command
#        jobs, file watching and HTTP requests all make progress during a wait.
#   EV2  one busy source (a command job printing thousands of lines) cannot
#        keep another ready source (a UDP datagram) waiting until it is done.
#   EV4  events from one source keep their order.
#
# Must stay host-portable: no powershell.exe, cmd or $env:TEMP.

. "$PSScriptRoot\TestHelpers.ps1"
. "$PSScriptRoot\TestHost.ps1"

Write-Host ''
Write-Host 'Event contract (EV2, EV3, EV4)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'
$script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_events_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null

# The running PowerShell, as a command an Otter program can start. Quoted only
# if the path has spaces.
$script:HostCommand = if ($script:OtterHostExe -match '\s') { "`"$($script:OtterHostExe)`"" } else { $script:OtterHostExe }

function Invoke-OtterEventProgram {
    param([string]$Source, [int]$TimeoutSeconds = 60)
    $path = Join-Path $script:Tmp ('p' + [Guid]::NewGuid().ToString('N') + '.ot')
    [System.IO.File]::WriteAllText($path, $Source, [System.Text.UTF8Encoding]::new($false))
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $script:OtterHostExe
    $psi.Arguments = "$script:OtterHostArgString -File `"$script:OtterPs1`" run `"$path`""
    $psi.WorkingDirectory = $script:Tmp
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $errTask = $proc.StandardError.ReadToEndAsync()
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $exited = $proc.WaitForExit($TimeoutSeconds * 1000)
    if (-not $exited) { try { $proc.Kill() } catch {} ; $proc.WaitForExit(5000) | Out-Null }
    $lines = @(($outTask.Result + "`n" + $errTask.Result) -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
    return [pscustomobject]@{ ExitCode = $(if ($exited) { $proc.ExitCode } else { $null }); TimedOut = -not $exited; Lines = $lines; Text = ($lines -join "`n") }
}

function Get-FreeTcpPort {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start()
    $p = $l.LocalEndpoint.Port; $l.Stop(); return $p
}
function Get-FreeUdpPort {
    $u = [System.Net.Sockets.UdpClient]::new(0)
    $p = ([System.Net.IPEndPoint]$u.Client.LocalEndPoint).Port; $u.Close(); return $p
}

try {
    # ---------------------------------------------------------------- EV3: TCP
    Test-Otter 'EV3: a TCP connection becomes connected during wait' {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $port = $listener.LocalEndpoint.Port
        $accept = $listener.AcceptTcpClientAsync()
        try {
            $r = Invoke-OtterEventProgram @"
connect to tcp "127.0.0.1" on port $port and call it conn
on connect of conn
    say "connect handler ran"
.
polls is 0
seen is false
while polls is less than 50
    if conn is connected
        seen is true
        polls is 50
    .
    wait 100 milliseconds
    polls is polls plus 1
.
if seen
    say "connected during wait"
.
close tcp conn
"@
            Assert-False $r.TimedOut 'program did not finish'
            Assert-True ($r.Lines -contains 'connected during wait') "the connection never became connected during wait: $($r.Text)"
            $iWait = [array]::IndexOf($r.Lines, 'connected during wait')
            $iHandler = [array]::IndexOf($r.Lines, 'connect handler ran')
            Assert-True ($iHandler -ge 0 -and $iHandler -lt $iWait) "the on connect handler must run during the wait, before the program continues: $($r.Text)"
        } finally { $listener.Stop() }
    }

    # ---------------------------------------------------------------- EV3: UDP
    Test-Otter 'EV3: a UDP datagram is handled during wait' {
        $port = Get-FreeUdpPort
        $r = Invoke-OtterEventProgram @"
open udp on port $port and call it receiver
open udp and call it sender
got is false
on data from receiver
    got is true
.
data is bytes from text "ping"
send data through sender
    to "127.0.0.1"
    on port $port
polls is 0
while polls is less than 50
    if got
        polls is 50
    .
    wait 100 milliseconds
    polls is polls plus 1
.
if got
    say "datagram handled during wait"
.
close udp receiver
close udp sender
"@
        Assert-False $r.TimedOut 'program did not finish'
        Assert-True ($r.Lines -contains 'datagram handled during wait') "the datagram was not handled during wait: $($r.Text)"
    }

    # ---------------------------------------------------------- EV3: command job
    Test-Otter 'EV3: a command job reaches its end during wait' {
        $r = Invoke-OtterEventProgram @"
start command "$script:HostCommand -NoProfile -Command Write-Output one; Write-Output two" and call it job
lines is 0
ended is false
on output from job
    lines is lines plus 1
.
on exit of job
    ended is true
.
polls is 0
while polls is less than 300
    if ended
        polls is 300
    .
    wait 100 milliseconds
    polls is polls plus 1
.
if ended
    say "job ended during wait with lines:" lines
.
"@
        Assert-False $r.TimedOut 'program did not finish'
        Assert-True ($r.Lines -contains 'job ended during wait with lines: 2') "the job did not finish during wait: $($r.Text)"
    }

    # ------------------------------------------------------------ EV3: watching
    Test-Otter 'EV3: a file-watcher event is handled during wait' {
        $watchDir = Join-Path $script:Tmp ('w' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $watchDir -Force | Out-Null
        $dirText = $watchDir.Replace([string][char]92, '/')
        $r = Invoke-OtterEventProgram @"
watch folder "$dirText" and call it folderWatcher
created is false
on create in folderWatcher
    created is true
.
write "x" to "$dirText/new.txt"
polls is 0
while polls is less than 100
    if created
        polls is 100
    .
    wait 100 milliseconds
    polls is polls plus 1
.
if created
    say "watcher event handled during wait"
.
stop watching folderWatcher
"@
        Assert-False $r.TimedOut 'program did not finish'
        Assert-True ($r.Lines -contains 'watcher event handled during wait') "the create event was not handled during wait: $($r.Text)"
    }

    # --------------------------------------------------------------- EV3: HTTP
    Test-Otter 'EV3: an HTTP request reaches a terminal state during wait' {
        # Nothing listens on this port, so the request fails quickly and
        # deterministically; the failure is the request event under test.
        $port = Get-FreeTcpPort
        $r = Invoke-OtterEventProgram @"
start get from "http://127.0.0.1:$port/none" and call it req
finished is false
on error of req
    finished is true
.
on complete of req
    finished is true
.
polls is 0
while polls is less than 100
    if finished
        polls is 100
    .
    wait 100 milliseconds
    polls is polls plus 1
.
if finished
    say "request finished during wait:" state of req
.
"@
        Assert-False $r.TimedOut 'program did not finish'
        Assert-True (($r.Lines | Where-Object { $_ -like 'request finished during wait:*' }).Count -eq 1) "the request did not finish during wait: $($r.Text)"
    }

    # ------------------------------------------------------------ EV2 + EV4
    Test-Otter 'EV2: a busy command job cannot keep a ready UDP datagram waiting until it finishes; EV4: job output stays in order' {
        $port = Get-FreeUdpPort
        $total = 2000
        $r = Invoke-OtterEventProgram @"
open udp on port $port and call it receiver
open udp and call it sender
start command "$script:HostCommand -NoProfile -Command 1..$total | ForEach-Object { Write-Output `$_ }" and call it job
lines is 0
outOfOrder is false
on output from job
    lines is lines plus 1
    if received output is not lines
        outOfOrder is true
    .
.
on exit of job
    say "job exited after lines:" lines
    if outOfOrder
        say "job output arrived out of order"
    .
.
on data from receiver
    say "datagram handled after job lines:" lines
    close udp receiver
    close udp sender
.
# Let the job print everything before the event loop starts: run command
# blocks without servicing events, so all $total lines are queued by now.
run command "$script:HostCommand -NoProfile -Command Start-Sleep -Seconds 4" into pause
data is bytes from text "x"
send data through sender
    to "127.0.0.1"
    on port $port
"@ -TimeoutSeconds 120
        Assert-False $r.TimedOut 'program did not finish'
        $exitLine = @($r.Lines | Where-Object { $_ -like 'job exited after lines:*' })
        Assert-AreEqual -Expected "job exited after lines: $total" -Actual ($exitLine | Select-Object -First 1) -Message $r.Text
        $udpLine = @($r.Lines | Where-Object { $_ -like 'datagram handled after job lines:*' }) | Select-Object -First 1
        Assert-True ($null -ne $udpLine) "the datagram was never handled: $($r.Text)"
        $seen = [int](($udpLine -split ':')[1].Trim())
        Assert-True ($seen -lt $total) "the datagram waited until the job had delivered all $total lines (seen $seen)"
        Assert-False ($r.Lines -contains 'job output arrived out of order') 'job output order must be preserved'
    }
}
finally {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests
