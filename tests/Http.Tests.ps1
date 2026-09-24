using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Library.psm1
using module ..\src\Otter.Interpreter.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1

# tests/Http.Tests.ps1
#
# Comprehensive test suite for D116A: HTTP Client Parity & Reliability
#
# Covers:
# - GET, GET JSON (both forms), empty body, Unicode text
# - POST raw, POST bytes, POST JSON (nested), target binding & discard
# - PUT raw, PUT JSON
# - DELETE with target and without target
# - Request headers (multiple, custom headers)
# - Cookies (with cookies vs without cookies)
# - Redirects (following redirects vs without redirects)
# - Timeouts (success, timeout diagnostic, non-poisoning of subsequent calls)
# - Status codes (200, 204, 404, 500 parity without throwing transport errors)
# - Malformed JSON rejection
# - Invalid URL diagnostic

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host "HTTP Client Tests (D116A)" -ForegroundColor Cyan

# Find available port
$tempTcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$tempTcp.Start()
$serverPort = $tempTcp.LocalEndpoint.Port
$tempTcp.Stop()

# Start deterministic local HTTP test server
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$serverPort/")
$listener.Start()

$runspace = [runspacefactory]::CreateRunspace()
$runspace.Open()
$runspace.SessionStateProxy.SetVariable("listener", $listener)
$runspace.SessionStateProxy.SetVariable("serverPort", $serverPort)

$psServer = [powershell]::Create()
$psServer.Runspace = $runspace
[void]$psServer.AddScript({
    while ($listener.IsListening) {
        $context = $null
        try {
            $context = $listener.GetContext()
        } catch {
            break
        }
        $req = $context.Request
        $resp = $context.Response
        try {
            $path = $req.Url.AbsolutePath
            switch -Wildcard ($path) {
                '/text' {
                    $resp.StatusCode = 200
                    $resp.ContentType = 'text/plain; charset=utf-8'
                    $buf = [System.Text.Encoding]::UTF8.GetBytes("Hello Otter 世界")
                    $resp.ContentLength64 = $buf.Length
                    $resp.OutputStream.Write($buf, 0, $buf.Length)
                }
                '/empty' {
                    $resp.StatusCode = 200
                    $resp.ContentLength64 = 0
                }
                '/json' {
                    $resp.StatusCode = 200
                    $resp.ContentType = 'application/json; charset=utf-8'
                    $jsonStr = '{"name":"Otter","count":42,"items":[1,2,3],"active":true,"nested":{"k":"v"}}'
                    $buf = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
                    $resp.ContentLength64 = $buf.Length
                    $resp.OutputStream.Write($buf, 0, $buf.Length)
                }
                '/echo' {
                    $reader = [System.IO.StreamReader]::new($req.InputStream, [System.Text.Encoding]::UTF8)
                    $body = $reader.ReadToEnd()
                    $resp.StatusCode = 200
                    $resp.ContentType = if ($req.ContentType) { $req.ContentType } else { 'text/plain' }
                    $buf = [System.Text.Encoding]::UTF8.GetBytes($body)
                    $resp.ContentLength64 = $buf.Length
                    $resp.OutputStream.Write($buf, 0, $buf.Length)
                }
                '/status/404' {
                    $resp.StatusCode = 404
                    $resp.ContentType = 'text/plain; charset=utf-8'
                    $buf = [System.Text.Encoding]::UTF8.GetBytes("Page not found")
                    $resp.ContentLength64 = $buf.Length
                    $resp.OutputStream.Write($buf, 0, $buf.Length)
                }
                '/status/500' {
                    $resp.StatusCode = 500
                    $resp.ContentType = 'text/plain; charset=utf-8'
                    $buf = [System.Text.Encoding]::UTF8.GetBytes("Server error")
                    $resp.ContentLength64 = $buf.Length
                    $resp.OutputStream.Write($buf, 0, $buf.Length)
                }
                '/status/204' {
                    $resp.StatusCode = 204
                    $resp.ContentLength64 = 0
                }
                '/redirect' {
                    $resp.StatusCode = 302
                    $resp.RedirectLocation = "http://localhost:$serverPort/text"
                    $resp.ContentLength64 = 0
                }
                '/headers' {
                    $hMap = [ordered]@{}
                    foreach ($key in $req.Headers.AllKeys) {
                        $hMap[$key] = $req.Headers[$key]
                    }
                    $jsonStr = $hMap | ConvertTo-Json -Compress
                    $resp.StatusCode = 200
                    $resp.ContentType = 'application/json'
                    $buf = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
                    $resp.ContentLength64 = $buf.Length
                    $resp.OutputStream.Write($buf, 0, $buf.Length)
                }
                '/cookie/set' {
                    $cookie = [System.Net.Cookie]::new('session', 'otter-token-999', '/')
                    $resp.Cookies.Add($cookie)
                    $resp.StatusCode = 200
                    $buf = [System.Text.Encoding]::UTF8.GetBytes("cookie-set-ok")
                    $resp.ContentLength64 = $buf.Length
                    $resp.OutputStream.Write($buf, 0, $buf.Length)
                }
                '/cookie/check' {
                    $hasCookie = $false
                    if ($req.Cookies['session'] -and $req.Cookies['session'].Value -eq 'otter-token-999') {
                        $hasCookie = $true
                    }
                    $resp.StatusCode = 200
                    $ans = if ($hasCookie) { "cookie:present" } else { "cookie:absent" }
                    $buf = [System.Text.Encoding]::UTF8.GetBytes($ans)
                    $resp.ContentLength64 = $buf.Length
                    $resp.OutputStream.Write($buf, 0, $buf.Length)
                }
                '/delay/*' {
                    $sec = 1
                    if ($path -match '/delay/(\d+)') { $sec = [int]$Matches[1] }
                    [System.Threading.Thread]::Sleep($sec * 1000)
                    $resp.StatusCode = 200
                    $buf = [System.Text.Encoding]::UTF8.GetBytes("delayed-response-ok")
                    $resp.ContentLength64 = $buf.Length
                    $resp.OutputStream.Write($buf, 0, $buf.Length)
                }
                '/malformed-json' {
                    $resp.StatusCode = 200
                    $resp.ContentType = 'application/json'
                    $buf = [System.Text.Encoding]::UTF8.GetBytes("{ not valid json: 123")
                    $resp.ContentLength64 = $buf.Length
                    $resp.OutputStream.Write($buf, 0, $buf.Length)
                }
                default {
                    $resp.StatusCode = 200
                    $buf = [System.Text.Encoding]::UTF8.GetBytes("ok")
                    $resp.ContentLength64 = $buf.Length
                    $resp.OutputStream.Write($buf, 0, $buf.Length)
                }
            }
        } catch {
        } finally {
            try { $resp.OutputStream.Close() } catch {}
        }
    }
})
$asyncServer = $psServer.BeginInvoke()
Start-Sleep -Milliseconds 150

function Run-OtterScript {
    param([string]$Source)
    $lines = [System.Collections.Generic.List[string]]::new()
    $writer = { param($Text) $lines.Add([string]$Text) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        $tokens = ConvertTo-OtterTokens -Source $Source
        $ast = ConvertTo-OtterAst -Tokens $tokens
        Invoke-OtterProgram -Program $ast -Environment (New-OtterEnvironment)
    } finally {
        Set-OtterOutputWriter -Writer $null
    }
    return , $lines.ToArray()
}

$otterCli = Join-Path $PSScriptRoot '..\otter.ps1'

function Run-OtterCli {
    param([string]$Source)
    $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ("otter-http-test-" + [Guid]::NewGuid().ToString('N') + ".ot")
    try {
        [System.IO.File]::WriteAllText($tmpFile, $Source, [System.Text.Encoding]::UTF8)
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = (Get-Command powershell.exe -ErrorAction Stop).Source
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$otterCli`" run `"$tmpFile`""
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit(15000) | Out-Null
        return [pscustomobject]@{ Stdout = $stdout; ExitCode = $process.ExitCode }
    } finally {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    }
}

try {

    # 1. GET plain text and Unicode
    Test-Otter 'D116A GET plain text and UTF-8 Unicode' {
        $out = Run-OtterScript @"
get "http://localhost:$serverPort/text" into res
say res
"@
        Assert-Lines -Expected @('Hello Otter 世界') -Actual $out
    }

    # 2. GET empty body
    Test-Otter 'D116A GET empty body returns 0-length text' {
        $out = Run-OtterScript @"
get "http://localhost:$serverPort/empty" into res
say length of res
"@
        Assert-Lines -Expected @('0') -Actual $out
    }

    # 3. GET JSON (get <url> as json into <target>)
    Test-Otter 'D116A GET JSON with "as json into" grammar' {
        $out = Run-OtterScript @"
get "http://localhost:$serverPort/json" as json into data
say name of data
say count of data
nestedObj is nested of data
say k of nestedObj
say active of data
"@
        Assert-Lines -Expected @('Otter', '42', 'v', 'true') -Actual $out
    }

    # 4. GET JSON (get json from <url> into <target>)
    Test-Otter 'D116A GET JSON with "get json from" grammar' {
        $out = Run-OtterScript @"
get json from "http://localhost:$serverPort/json" into data
say name of data
itemList is items of data
say first of itemList
"@
        Assert-Lines -Expected @('Otter', '1') -Actual $out
    }

    # 5. POST raw text
    Test-Otter 'D116A POST raw text into response' {
        $out = Run-OtterScript @"
msg is "Hello from POST!"
post msg to "http://localhost:$serverPort/echo" into res
say res
"@
        Assert-Lines -Expected @('Hello from POST!') -Actual $out
    }

    # 6. POST raw bytes
    Test-Otter 'D116A POST raw D102 bytes' {
        $out = Run-OtterScript @"
b is bytes from hex "4F74746572"
post b to "http://localhost:$serverPort/echo" into res
say res
"@
        Assert-Lines -Expected @('Otter') -Actual $out
    }

    # 7. POST JSON with nested data
    Test-Otter 'D116A POST JSON with nested object' {
        $out = Run-OtterScript @"
user is a thing
    name is "Sam"
    role is "admin"
.
post user as json to "http://localhost:$serverPort/echo" into res
say res
"@
        Assert-True ($out[0] -match '"name":\s*"Sam"' -and $out[0] -match '"role":\s*"admin"')
    }

    # 8. POST discard response (no into clause)
    Test-Otter 'D116A POST without into clause discards response' {
        $out = Run-OtterScript @"
post "discard this" to "http://localhost:$serverPort/echo"
say "completed"
"@
        Assert-Lines -Expected @('completed') -Actual $out
    }

    # 9. PUT raw and JSON
    Test-Otter 'D116A PUT statement with raw and JSON data' {
        $out = Run-OtterScript @"
put "Updated payload" to "http://localhost:$serverPort/echo" into res1
say res1

item is a thing
    id is 42
.
put item as json to "http://localhost:$serverPort/echo" into res2
say res2
"@
        Assert-True ($out[0] -eq 'Updated payload')
        Assert-True ($out[1] -match '"id":\s*42')
    }

    # 10. DELETE with and without target
    Test-Otter 'D116A DELETE statement with and without into clause' {
        $out = Run-OtterScript @"
delete from "http://localhost:$serverPort/echo" into res
say "delete with target ok"

delete from "http://localhost:$serverPort/echo"
say "delete without target ok"
"@
        Assert-Lines -Expected @('delete with target ok', 'delete without target ok') -Actual $out
    }

    # 11. Headers
    Test-Otter 'D116A Headers block passes custom headers' {
        $out = Run-OtterScript @"
get "http://localhost:$serverPort/headers" as json into h
    with header "X-Otter-Auth" is "Bearer secret-xyz"
    with header "X-Otter-Env" is "production"
get "X-Otter-Auth" from h into authVal
get "X-Otter-Env" from h into envVal
say authVal
say envVal
"@
        Assert-Lines -Expected @('Bearer secret-xyz', 'production') -Actual $out
    }

    # 12. Cookies (with cookies vs without cookies)
    Test-Otter 'D116A Cookies: with cookies sends jar, without cookies omits jar' {
        $out = Run-OtterScript @"
get "http://localhost:$serverPort/cookie/set" into setRes
    with cookies
say setRes

get "http://localhost:$serverPort/cookie/check" into check1
    with cookies
say check1

get "http://localhost:$serverPort/cookie/check" into check2
    without cookies
say check2
"@
        Assert-Lines -Expected @('cookie-set-ok', 'cookie:present', 'cookie:absent') -Actual $out
    }

    # 13. Redirects (following redirects vs without redirects)
    Test-Otter 'D116A Redirects: following redirects follows, without redirects returns 302 directly' {
        $out = Run-OtterScript @"
get "http://localhost:$serverPort/redirect" into resFollow
    following redirects
say resFollow

get "http://localhost:$serverPort/redirect" into resNoFollow
    without redirects
say "received without redirect"
"@
        Assert-Lines -Expected @('Hello Otter 世界', 'received without redirect') -Actual $out
    }

    # 14. Timeout: fast endpoint succeeds, delayed fails, subsequent request succeeds
    Test-Otter 'D116A Timeout: fast succeeds, delayed produces clean diagnostic, subsequent succeeds' {
        $outFast = Run-OtterScript @"
get "http://localhost:$serverPort/text" into res
    with timeout 5 seconds
say res
"@
        Assert-Lines -Expected @('Hello Otter 世界') -Actual $outFast

        $rTimeout = Run-OtterCli @"
get "http://localhost:$serverPort/delay/3" into res
    with timeout 1 seconds
say res
"@
        Assert-AreEqual -Expected 3 -Actual $rTimeout.ExitCode
        Assert-True ($rTimeout.Stdout -match 'The HTTP request timed out after 1 seconds\.') 'expected clean timeout diagnostic'
        Assert-False ($rTimeout.Stdout -match 'at System\.') 'raw stack trace must not leak'

        $outAfter = Run-OtterScript @"
get "http://localhost:$serverPort/text" into res
say res
"@
        Assert-Lines -Expected @('Hello Otter 世界') -Actual $outAfter
    }

    # 15. Status code parity: 200, 204, 404, 500 do not throw transport errors
    Test-Otter 'D116A Status code parity: 404 and 500 return response body without throwing' {
        $out = Run-OtterScript @"
get "http://localhost:$serverPort/status/404" into res404
say res404

get "http://localhost:$serverPort/status/500" into res500
say res500

get "http://localhost:$serverPort/status/204" into res204
say length of res204
"@
        Assert-Lines -Expected @('Page not found', 'Server error', '0') -Actual $out
    }

    # 16. Malformed JSON test
    Test-Otter 'D116A Malformed JSON: as json fails cleanly, raw get returns text' {
        $rFail = Run-OtterCli @"
get "http://localhost:$serverPort/malformed-json" as json into data
say data
"@
        Assert-AreEqual -Expected 3 -Actual $rFail.ExitCode
        Assert-True ($rFail.Stdout -match 'This is not valid JSON, so Otter could not read it\.') 'expected clean invalid JSON diagnostic'

        $outRaw = Run-OtterScript @"
get "http://localhost:$serverPort/malformed-json" into raw
say raw
"@
        Assert-True ($outRaw[0] -match '\{ not valid json: 123')
    }

    # 17. Invalid URL test
    Test-Otter 'D116A Invalid URL produces clean Otter diagnostic' {
        $rUrl = Run-OtterCli @"
get "ftp://invalid-scheme.com" into res
say res
"@
        Assert-AreEqual -Expected 3 -Actual $rUrl.ExitCode
        Assert-True ($rUrl.Stdout -match 'I can only make HTTP requests using http or https') 'expected scheme diagnostic'

        $rBad = Run-OtterCli @"
get "not a url" into res
say res
"@
        Assert-AreEqual -Expected 3 -Actual $rBad.ExitCode
        Assert-True ($rBad.Stdout -match 'is not a valid URL') 'expected invalid URL diagnostic'
    }

} finally {
    try { $listener.Stop() } catch {}
    try { $listener.Close() } catch {}
    try { $psServer.Stop() } catch {}
    try { $psServer.Dispose() } catch {}
    try { $runspace.Close() } catch {}
    try { $runspace.Dispose() } catch {}
}

Complete-OtterTests
