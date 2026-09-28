using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Library.psm1
using module ..\src\Otter.Interpreter.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1
. "$PSScriptRoot\TestHost.ps1"

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

# Start deterministic local concurrent HTTP test server
$serverTypeDef = @'
using System;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;

public class OtterHttpTestServer : IDisposable {
    private HttpListener _listener;
    private bool _running;
    public int Port { get; private set; }

    public OtterHttpTestServer(int port) {
        Port = port;
        _listener = new HttpListener();
        _listener.Prefixes.Add("http://localhost:" + port + "/");
        _listener.Start();
        _running = true;
        ThreadPool.QueueUserWorkItem((s) => {
            while (_running && _listener.IsListening) {
                try {
                    var ctx = _listener.GetContext();
                    ThreadPool.QueueUserWorkItem((state) => HandleRequest((HttpListenerContext)state), ctx);
                } catch {
                    break;
                }
            }
        });
    }

    private void HandleRequest(HttpListenerContext ctx) {
        var req = ctx.Request;
        var resp = ctx.Response;
        try {
            string path = req.Url.AbsolutePath;
            if (path == "/text") {
                resp.StatusCode = 200;
                resp.ContentType = "text/plain; charset=utf-8";
                byte[] buf = Encoding.UTF8.GetBytes("Hello Otter 世界");
                resp.ContentLength64 = buf.Length;
                resp.OutputStream.Write(buf, 0, buf.Length);
            } else if (path == "/empty") {
                resp.StatusCode = 200;
                resp.ContentLength64 = 0;
            } else if (path == "/json") {
                resp.StatusCode = 200;
                resp.ContentType = "application/json; charset=utf-8";
                byte[] buf = Encoding.UTF8.GetBytes("{\"name\":\"Otter\",\"count\":42,\"items\":[1,2,3],\"active\":true,\"nested\":{\"k\":\"v\"}}");
                resp.ContentLength64 = buf.Length;
                resp.OutputStream.Write(buf, 0, buf.Length);
            } else if (path == "/echo") {
                using (var r = new StreamReader(req.InputStream, Encoding.UTF8)) {
                    string body = r.ReadToEnd();
                    resp.StatusCode = 200;
                    resp.ContentType = string.IsNullOrEmpty(req.ContentType) ? "text/plain" : req.ContentType;
                    byte[] buf = Encoding.UTF8.GetBytes(body);
                    resp.ContentLength64 = buf.Length;
                    resp.OutputStream.Write(buf, 0, buf.Length);
                }
            } else if (path == "/status/404") {
                resp.StatusCode = 404;
                resp.ContentType = "text/plain; charset=utf-8";
                byte[] buf = Encoding.UTF8.GetBytes("Page not found");
                resp.ContentLength64 = buf.Length;
                resp.OutputStream.Write(buf, 0, buf.Length);
            } else if (path == "/status/500") {
                resp.StatusCode = 500;
                resp.ContentType = "text/plain; charset=utf-8";
                byte[] buf = Encoding.UTF8.GetBytes("Server error");
                resp.ContentLength64 = buf.Length;
                resp.OutputStream.Write(buf, 0, buf.Length);
            } else if (path == "/status/204") {
                resp.StatusCode = 204;
                resp.ContentLength64 = 0;
            } else if (path == "/redirect") {
                resp.StatusCode = 302;
                resp.RedirectLocation = "http://localhost:" + Port + "/text";
                resp.ContentLength64 = 0;
            } else if (path == "/headers") {
                var sb = new StringBuilder("{");
                bool first = true;
                foreach (string key in req.Headers.AllKeys) {
                    if (!first) sb.Append(",");
                    first = false;
                    sb.Append("\"").Append(key).Append("\":\"").Append(req.Headers[key]).Append("\"");
                }
                sb.Append("}");
                byte[] buf = Encoding.UTF8.GetBytes(sb.ToString());
                resp.StatusCode = 200;
                resp.ContentType = "application/json";
                resp.ContentLength64 = buf.Length;
                resp.OutputStream.Write(buf, 0, buf.Length);
            } else if (path == "/cookie/set") {
                resp.Cookies.Add(new Cookie("session", "otter-token-999", "/"));
                resp.StatusCode = 200;
                byte[] buf = Encoding.UTF8.GetBytes("cookie-set-ok");
                resp.ContentLength64 = buf.Length;
                resp.OutputStream.Write(buf, 0, buf.Length);
            } else if (path == "/cookie/check") {
                bool hasCookie = req.Cookies["session"] != null && req.Cookies["session"].Value == "otter-token-999";
                resp.StatusCode = 200;
                byte[] buf = Encoding.UTF8.GetBytes(hasCookie ? "cookie:present" : "cookie:absent");
                resp.ContentLength64 = buf.Length;
                resp.OutputStream.Write(buf, 0, buf.Length);
            } else if (path.StartsWith("/delay/")) {
                int sec = 1;
                int.TryParse(path.Substring(7), out sec);
                Thread.Sleep(sec * 1000);
                resp.StatusCode = 200;
                byte[] buf = Encoding.UTF8.GetBytes("delayed-response-ok");
                resp.ContentLength64 = buf.Length;
                resp.OutputStream.Write(buf, 0, buf.Length);
            } else if (path.StartsWith("/item/")) {
                string id = path.Substring(6);
                resp.StatusCode = 200;
                byte[] buf = Encoding.UTF8.GetBytes("item-" + id);
                resp.ContentLength64 = buf.Length;
                resp.OutputStream.Write(buf, 0, buf.Length);
            } else if (path == "/malformed-json") {
                resp.StatusCode = 200;
                resp.ContentType = "application/json";
                byte[] buf = Encoding.UTF8.GetBytes("{ not valid json: 123");
                resp.ContentLength64 = buf.Length;
                resp.OutputStream.Write(buf, 0, buf.Length);
            } else {
                resp.StatusCode = 200;
                byte[] buf = Encoding.UTF8.GetBytes("ok");
                resp.ContentLength64 = buf.Length;
                resp.OutputStream.Write(buf, 0, buf.Length);
            }
        } catch {
        } finally {
            try { resp.OutputStream.Close(); } catch {}
        }
    }

    public void Dispose() {
        _running = false;
        try { _listener.Stop(); } catch {}
        try { _listener.Close(); } catch {}
    }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'OtterHttpTestServer').Type) {
    Add-Type -TypeDefinition $serverTypeDef
}
$testServer = [OtterHttpTestServer]::new($serverPort)

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
        $psi.FileName = $script:OtterHostExe
        $psi.Arguments = "$script:OtterHostArgString -File `"$otterCli`" run `"$tmpFile`""
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

    # 11b. Header injection: a line break in a header must never reach the wire.
    # Headers are added with TryAddWithoutValidation, which used to accept
    # "safe\nInjected: yes" and send "Injected: yes" as a second header.
    Test-Otter 'Header injection: a header value with a line break is refused, sync and async' {
        Assert-OtterFails -Containing 'cannot contain line breaks' -Body {
            Run-OtterScript @"
get "http://localhost:$serverPort/headers" as json into h
    with header "X-Otter-Auth" is "safe\nInjected: yes"
say "SHOULD NOT SEND"
"@
        }
        Assert-OtterFails -Containing 'cannot contain line breaks' -Body {
            Run-OtterScript @"
start get from "http://localhost:$serverPort/headers" as json and call it req
    with header "X-Otter-Auth" is "safe\nInjected: yes"
say "SHOULD NOT SEND"
"@
        }
        # CR, NUL and a malformed name are refused by the same guard (Otter
        # strings have no \r escape, so call the module-private check directly).
        $library = Get-Module Otter.Library | Select-Object -First 1
        if ($null -eq $library) { $library = Import-Module (Join-Path $PSScriptRoot '../src/Otter.Library.psm1') -PassThru }
        Assert-OtterFails -Containing 'cannot contain line breaks' -Body { & $library { Assert-OtterHttpHeader -Name 'X-A' -Value ("a" + [char]13 + "Injected: yes") -Line 1 } }
        Assert-OtterFails -Containing 'cannot contain line breaks' -Body { & $library { Assert-OtterHttpHeader -Name 'X-A' -Value ("a" + [char]0 + "b") -Line 1 } }
        Assert-OtterFails -Containing 'cannot contain line breaks' -Body { & $library { Assert-OtterHttpHeader -Name ("X-A" + [char]10 + "Injected") -Value 'v' -Line 1 } }
        Assert-OtterFails -Containing 'cannot contain a colon or whitespace' -Body { & $library { Assert-OtterHttpHeader -Name 'X-A: b' -Value 'v' -Line 1 } }
        Assert-OtterFails -Containing 'cannot be empty' -Body { & $library { Assert-OtterHttpHeader -Name '' -Value 'v' -Line 1 } }
    }

    Test-Otter 'Header injection guard still sends an ordinary header' {
        $out = Run-OtterScript @"
get "http://localhost:$serverPort/headers" as json into h
    with header "X-Otter-Plain" is "value with spaces: and a colon"
get "X-Otter-Plain" from h into plainVal
say plainVal
"@
        Assert-Lines -Expected @('value with spaces: and a colon') -Actual $out
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

    # ===============================================================
    # D116B: ASYNCHRONOUS HTTP REQUEST HANDLES & CANCELLATION TESTS
    # ===============================================================

    # 18. Basic completion test (Section 35)
    Test-Otter 'D116B Basic completion: start get, on complete, received response, state completed' {
        $out = Run-OtterScript @"
start get from "http://localhost:$serverPort/text" and call it req

on complete of req
    say received response
    say state of req
.
"@
        Assert-Lines -Expected @('Hello Otter 世界', 'completed') -Actual $out
    }

    # 19. JSON completion test (Section 36)
    Test-Otter 'D116B JSON completion: start get as json, received response parsed Otter value, response of request' {
        $out = Run-OtterScript @"
start get from "http://localhost:$serverPort/json" as json and call it req

on complete of req
    data is received response
    say name of data
    say count of data
    respData is response of req
    say name of respData
    say state of req
.
"@
        Assert-Lines -Expected @('Otter', '42', 'Otter', 'completed') -Actual $out
    }

    # 20. POST, PUT, DELETE async requests (Section 3)
    Test-Otter 'D116B POST, PUT, DELETE async requests with on complete' {
        $out = Run-OtterScript @"
start post "hello post async" to "http://localhost:$serverPort/echo" and call it postReq
on complete of postReq
    say received response
.

start put "hello put async" to "http://localhost:$serverPort/echo" and call it putReq
on complete of putReq
    say received response
.

start delete from "http://localhost:$serverPort/text" and call it delReq
on complete of delReq
    say state of delReq
.
"@
        Assert-Lines -Expected @('hello post async', 'hello put async', 'completed') -Actual $out
    }

    # 21. HTTP options on async requests (Section 5)
    Test-Otter 'D116B HTTP options: headers, timeout, cookies, redirects on async request' {
        $out = Run-OtterScript @"
start get from "http://localhost:$serverPort/headers" as json and call it req
    with header "X-Test-Async" is "otter-async-42"
    with timeout 10 seconds

on complete of req
    h is received response
    get "X-Test-Async" from h into val
    say val
.
"@
        Assert-Lines -Expected @('otter-async-42') -Actual $out
    }

    # 22. Explicit cancellation (Section 37)
    Test-Otter 'D116B Explicit cancellation: cancel pending request, on cancel fires once, complete and error do not fire, state cancelled' {
        $out = Run-OtterScript @"
start get from "http://localhost:$serverPort/delay/2" and call it req

on complete of req
    say "SHOULD NOT COMPLETE"
.

on error of req
    say "SHOULD NOT ERROR"
.

on cancel of req
    say "cancelled successfully"
    say state of req
.

cancel req
"@
        Assert-Lines -Expected @('cancelled successfully', 'cancelled') -Actual $out
    }

    # 23. Double-cancel test (Section 38)
    Test-Otter 'D116B Double-cancel is idempotent: repeated cancel does not error or re-dispatch' {
        $out = Run-OtterScript @"
start get from "http://localhost:$serverPort/delay/2" and call it req

cancelCount is 0
on cancel of req
    add 1 to cancelCount
    say "cancel event"
.

cancel req
cancel req
say state of req
say cancelCount
"@
        Assert-Lines -Expected @('cancel event', 'cancelled', '1') -Actual $out
    }

    # 24. Cancel-after-complete is a no-op (Section 39)
    Test-Otter 'D116B Cancel-after-complete is a no-op: state remains completed, cancel does not fire' {
        $out = Run-OtterScript @"
start get from "http://localhost:$serverPort/text" and call it req

cancelledFired is false
on cancel of req
    cancelledFired is true
.

on complete of req
    say "completed first"
    cancel req
    say state of req
    if cancelledFired
        say "cancel fired: true"
    .
    if not cancelledFired
        say "cancel fired: false"
    .
.
"@
        Assert-Lines -Expected @('completed first', 'completed', 'cancel fired: false') -Actual $out
    }

    # 25. Timeout is distinct from cancellation (Section 40)
    Test-Otter 'D116B Timeout is distinct from cancellation: with timeout triggers on error, cancel does not fire, state failed' {
        $out = Run-OtterScript @"
start get from "http://localhost:$serverPort/delay/3" and call it req
    with timeout 1 seconds

on complete of req
    say "SHOULD NOT COMPLETE"
.

on cancel of req
    say "SHOULD NOT CANCEL"
.

on error of req
    say "error event fired"
    st is state of req
    say st
    err is error of req
    say err
.
"@
        Assert-True ($out.Count -ge 2)
        Assert-AreEqual -Expected 'error event fired' -Actual $out[0]
        Assert-AreEqual -Expected 'failed' -Actual $out[1]
        Assert-True ($out[2] -match 'timed out') 'expected timeout diagnostic in error of req'
    }

    # 26. Transport failure (Section 41)
    Test-Otter 'D116B Transport failure: unreachable port triggers on error, complete/cancel do not fire, state failed' {
        $closedPort = 59999
        $out = Run-OtterScript @"
start get from "http://localhost:$closedPort/nowhere" and call it req

on complete of req
    say "SHOULD NOT COMPLETE"
.

on cancel of req
    say "SHOULD NOT CANCEL"
.

on error of req
    say "transport error fired"
    st is state of req
    say st
.
"@
        Assert-Lines -Expected @('transport error fired', 'failed') -Actual $out
    }

    # 27. Status code property (Section 42)
    Test-Otter 'D116B HTTP status code property: status of request for 200, 404, 500' {
        $out = Run-OtterScript @"
start get from "http://localhost:$serverPort/text" and call it req200
on complete of req200
    say status of req200
.

start get from "http://localhost:$serverPort/status/404" and call it req404
on complete of req404
    say status of req404
.

start get from "http://localhost:$serverPort/status/500" and call it req500
on complete of req500
    say status of req500
.
"@
        Assert-Lines -Expected @('200', '404', '500') -Actual $out
    }

    # 28. Fast-completion race test (Section 43)
    Test-Otter 'D116B Fast-completion race: handler registered after request finishes still fires exactly once (retained terminal event)' {
        $out = Run-OtterScript @"
start get from "http://localhost:$serverPort/text" and call it req

# Wait for request to finish before registering handler
wait 100 milliseconds

on complete of req
    resp is received response
    st is state of req
    say "retained complete event fired: " plus resp
    say "state: " plus st
.
"@
        Assert-Lines -Expected @('retained complete event fired: Hello Otter 世界', 'state: completed') -Actual $out
    }

    # 29. Concurrency test: 20 concurrent requests (Section 44)
    Test-Otter 'D116B Concurrency: 20 concurrent requests with unique responses reach terminal states without crosstalk' {
        $scriptText = [System.Text.StringBuilder]::new()
        for ($i = 1; $i -le 20; $i++) {
            [void]$scriptText.AppendLine("start get from `"http://localhost:$serverPort/item/$i`" and call it req$i")
            [void]$scriptText.AppendLine("on complete of req$i")
            [void]$scriptText.AppendLine("    say received response")
            [void]$scriptText.AppendLine(".")
        }
        $out = Run-OtterScript ($scriptText.ToString())
        Assert-AreEqual -Expected 20 -Actual $out.Count
        for ($i = 1; $i -le 20; $i++) {
            Assert-True ($out -contains "item-$i") "expected response for item-$i"
        }
    }

    # 30. Mixed concurrent states (Section 45)
    Test-Otter 'D116B Mixed concurrent states: requests complete, fail, timeout, and cancel concurrently' {
        $closedPort = 59998
        $out = Run-OtterScript @"
start get from "http://localhost:$serverPort/text" and call it rComplete
on complete of rComplete
    st1 is state of rComplete
    say "success:" plus st1
.

start get from "http://localhost:$closedPort/unreachable" and call it rFail
on error of rFail
    st2 is state of rFail
    say "failure:" plus st2
.

start get from "http://localhost:$serverPort/delay/3" and call it rTimeout
    with timeout 1 seconds
on error of rTimeout
    st3 is state of rTimeout
    say "timeout:" plus st3
.

start get from "http://localhost:$serverPort/delay/2" and call it rCancel
on cancel of rCancel
    st4 is state of rCancel
    say "cancel:" plus st4
.
cancel rCancel
"@
        Assert-True ($out -contains "success:completed") "expected completed state"
        Assert-True ($out -contains "failure:failed") "expected failed state"
        Assert-True ($out -contains "timeout:failed") "expected timeout failed state"
        Assert-True ($out -contains "cancel:cancelled") "expected cancelled state"
    }

    # 31. Soak test: 500 requests (Section 46)
    Test-Otter 'D116B Soak test: 500 requests complete/cancel without resource leaks or socket exhaustion' {
        $scriptText = [System.Text.StringBuilder]::new()
        [void]$scriptText.AppendLine("completedCount is 0")
        [void]$scriptText.AppendLine("cancelledCount is 0")
        for ($i = 1; $i -le 500; $i++) {
            if ($i % 2 -eq 0) {
                [void]$scriptText.AppendLine("start get from `"http://localhost:$serverPort/empty`" and call it sReq$i")
                [void]$scriptText.AppendLine("on complete of sReq$i")
                [void]$scriptText.AppendLine("    add 1 to completedCount")
                [void]$scriptText.AppendLine("    if completedCount is 250")
                [void]$scriptText.AppendLine("        say `"completed: 250`"")
                [void]$scriptText.AppendLine("    .")
                [void]$scriptText.AppendLine(".")
            } else {
                [void]$scriptText.AppendLine("start get from `"http://localhost:$serverPort/delay/2`" and call it sReq$i")
                [void]$scriptText.AppendLine("on cancel of sReq$i")
                [void]$scriptText.AppendLine("    add 1 to cancelledCount")
                [void]$scriptText.AppendLine("    if cancelledCount is 250")
                [void]$scriptText.AppendLine("        say `"cancelled: 250`"")
                [void]$scriptText.AppendLine("    .")
                [void]$scriptText.AppendLine(".")
                [void]$scriptText.AppendLine("cancel sReq$i")
            }
        }

        $out = Run-OtterScript ($scriptText.ToString())
        Assert-True ($out -contains "completed: 250") "expected 250 completed"
        Assert-True ($out -contains "cancelled: 250") "expected 250 cancelled"
    }

    # 32. Request state predicates (Section 11)
    Test-Otter 'D116B Request state predicates: request is pending / completed / failed / cancelled' {
        $out = Run-OtterScript @"
start get from "http://localhost:$serverPort/text" and call it req
if req is pending
    say "is pending: true"
.
on complete of req
    if req is completed
        say "is completed: true"
    .
    if req is not failed
        say "is not failed: true"
    .
    if req is not cancelled
        say "is not cancelled: true"
    .
.
"@
        Assert-Lines -Expected @('is pending: true', 'is completed: true', 'is not failed: true', 'is not cancelled: true') -Actual $out
    }

    # 33. Property guards and error validation (Sections 20 & 21)
    Test-Otter 'D116B Property guards: response before completion, response after cancel, cancel non-request' {
        # response before completion
        $rPending = Run-OtterCli @"
start get from "http://localhost:$serverPort/delay/2" and call it req
say response of req
"@
        Assert-AreEqual -Expected 3 -Actual $rPending.ExitCode
        Assert-True ($rPending.Stdout -match 'The HTTP request has not completed yet\.') 'expected not completed diagnostic'

        # response after cancel
        $rCancelled = Run-OtterCli @"
start get from "http://localhost:$serverPort/delay/2" and call it req
cancel req
say response of req
"@
        Assert-AreEqual -Expected 3 -Actual $rCancelled.ExitCode
        Assert-True ($rCancelled.Stdout -match 'The HTTP request was cancelled\.') 'expected cancelled diagnostic'

        # cancel non-request
        $rWrongType = Run-OtterCli @"
x is "hello"
cancel x
"@
        Assert-AreEqual -Expected 3 -Actual $rWrongType.ExitCode
        Assert-True ($rWrongType.Stdout -match 'cancel requires an HTTP request\.') 'expected cancel type diagnostic'
    }

} finally {
    try { $testServer.Dispose() } catch {}
}

Complete-OtterTests
