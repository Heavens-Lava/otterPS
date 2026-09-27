using module .\copy\Otter.Contract.psm1
using module .\copy\src\Otter.Runtime.psm1
using module .\copy\src\Otter.Lexer.psm1
using module .\copy\src\Otter.Parser.psm1
using module .\copy\src\Otter.Interpreter.psm1

param([Parameter(Mandatory)][string]$Scenario)
$ErrorActionPreference = 'Stop'

function Start-Helper {
    param([string]$Command)
    $exe = (Get-Process -Id $PID).Path
    Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-Command', $Command) -WindowStyle Hidden -PassThru
}

function Get-FreePort {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start()
    $p = $l.LocalEndpoint.Port; $l.Stop(); return $p
}

$port = Get-FreePort
$helper = $null
$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_evloop_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

switch ($Scenario) {
    'idle' {
        $helper = Start-Helper "Start-Sleep 9; `$c=[System.Net.Sockets.UdpClient]::new(); `$b=[byte[]](1); [void]`$c.Send(`$b,1,'127.0.0.1',$port)"
        $source = @"
open udp on port $port and call it idleSocket
on data from idleSocket
    say "woke"
    close udp idleSocket
.
"@
        $events = 1
    }
    'udp_burst' {
        $source = @"
open udp on port $port and call it receiver
open udp and call it sender
received is 0
total is 200
data is bytes from text "x"
count from 1 to total as n
    send data through sender
        to "127.0.0.1"
        on port $port
.
on data from receiver
    received is received plus 1
    if received is total
        say "done" received
        close udp receiver
        close udp sender
    .
.
"@
        $events = 200
    }
    'udp_paced' {
        # 20 datagrams, 250 ms apart: the loop is never backlogged, so this shows per-event latency cost.
        $helper = Start-Helper "Start-Sleep 1; `$c=[System.Net.Sockets.UdpClient]::new(); `$b=[byte[]](1); 1..20 | ForEach-Object { [void]`$c.Send(`$b,1,'127.0.0.1',$port); Start-Sleep -Milliseconds 250 }"
        $source = @"
open udp on port $port and call it receiver
received is 0
on data from receiver
    received is received plus 1
    if received is 20
        say "done" received
        close udp receiver
    .
.
"@
        $events = 20
    }
    'tcp_stream' {
        $helper = Start-Helper "`$l=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,$port); `$l.Start(); `$c=`$l.AcceptTcpClient(); `$c.NoDelay=`$true; `$s=`$c.GetStream(); `$b=[System.Text.Encoding]::ASCII.GetBytes('x'); 1..100 | ForEach-Object { `$s.Write(`$b,0,1); `$s.Flush(); Start-Sleep -Milliseconds 30 }; Start-Sleep -Milliseconds 500; `$c.Close(); `$l.Stop()"
        Start-Sleep -Milliseconds 800
        $source = @"
connect to tcp "127.0.0.1" on port $port and call it connection
chunks is 0
bytesSeen is 0
on data from connection
    chunks is chunks plus 1
    data is received data
    bytesSeen is bytesSeen plus count of data
.
on close of connection
    say "closed" chunks bytesSeen
.
"@
        $events = 100
    }
    'job_output' {
        $source = @"
start command "powershell.exe -NoProfile -Command 1..300 | ForEach-Object { Write-Output `$_ }" and call it job
lines is 0
on output from job
    lines is lines plus 1
.
on exit of job
    say "exited" lines
.
"@
        $events = 300
    }
    'job_starve' {
        # A job printing continuously (about 2 s of handler work) while a UDP datagram
        # arrives from outside roughly 1 s into the flood.
        $helper = Start-Helper "Start-Sleep 1.6; `$c=[System.Net.Sockets.UdpClient]::new(); `$b=[byte[]](1); [void]`$c.Send(`$b,1,'127.0.0.1',$port)"
        $source = @"
open udp on port $port and call it receiver
start command "powershell.exe -NoProfile -Command 1..4000 | ForEach-Object { Write-Output `$_ }" and call it job
lines is 0
on output from job
    lines is lines plus 1
.
on data from receiver
    say "UDP handler ran after job lines:" lines
    close udp receiver
.
on exit of job
    say "job exited after lines:" lines
.
"@
        $events = 4001
    }
    'watcher_burst' {
        $dirText = $workDir.Replace([string][char]92, '/')
        $nameLines = ((1..40) | ForEach-Object { '    "' + $dirText + '/f' + $_ + '.txt"' }) -join "`n"
        $source = @"
watch folder "$dirText" and call it dirWatcher
created is 0
on create in dirWatcher
    created is created plus 1
    if created is 40
        say "done" created
        stop watching dirWatcher
    .
.
names are
$nameLines
for each fileName in names
    write "x" to fileName
.
"@
        $events = 40
    }
    default { throw "Unknown scenario $Scenario" }
}

$collected = [System.Collections.Generic.List[string]]::new()
Set-OtterOutputWriter -Writer { param($t) $collected.Add([string]$t) }.GetNewClosure()
$ast = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $source)
$proc = [System.Diagnostics.Process]::GetCurrentProcess()
$cpu0 = $proc.TotalProcessorTime
$wall = [System.Diagnostics.Stopwatch]::StartNew()
$failure = $null
try {
    Invoke-OtterProgram -Program $ast -Environment (New-OtterEnvironment) -SourceLines ($source -split "`r?`n")
} catch { $failure = $_.Exception.Message }
$wall.Stop()
$proc.Refresh()
$cpuMs = ($proc.TotalProcessorTime - $cpu0).TotalMilliseconds
$st = Get-OtterLoopStats

if ($helper) { try { if (-not $helper.HasExited) { $helper.Kill() } } catch {} }
Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue

[pscustomobject]@{
    Scenario   = $Scenario
    Failure    = $failure
    Output     = ($collected -join ' | ')
    Events     = $events
    RunWallMs  = [Math]::Round($wall.Elapsed.TotalMilliseconds)
    LoopWallMs = if ($st) { [Math]::Round($st.WallMs) } else { 0 }
    CpuMs      = [Math]::Round($cpuMs)
    LoopCpuMs  = if ($st) { [Math]::Round($st.CpuEndMs - $st.CpuStartMs) } else { 0 }
    Passes     = if ($st) { $st.Passes } else { 0 }
    SleepMs    = if ($st) { [Math]::Round($st.SleepMs) } else { 0 }
    WatchMs    = if ($st) { [Math]::Round($st.WatchMs) } else { 0 }
    WsMs       = if ($st) { [Math]::Round($st.WsMs) } else { 0 }
    NetMs      = if ($st) { [Math]::Round($st.NetMs) } else { 0 }
    HttpMs     = if ($st) { [Math]::Round($st.HttpMs) } else { 0 }
    JobMs      = if ($st) { [Math]::Round($st.JobMs) } else { 0 }
    CheckMs    = if ($st) { [Math]::Round($st.CheckMs) } else { 0 }
} | ConvertTo-Json -Compress
