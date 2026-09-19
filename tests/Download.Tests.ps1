using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Library.psm1
using module ..\src\Otter.Interpreter.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1
using module ..\src\Otter.Compiler.JavaScript.psm1
using module ..\src\Otter.Desktop.psm1
using module ..\src\Otter.Web.psm1

# tests/Download.Tests.ps1
#
# Comprehensive test suite for D96 File Download:
# download file from <url> to <path>
#
# Covers:
# - Raw binary streaming & byte-for-byte integrity (text, binary, zero-byte, large)
# - No memory buffering & no text interpretation
# - Expressions, variables, paths with spaces, Unicode paths, relative paths
# - Directory rules: parent must exist (no implicit mkdir), container rejected
# - Existing destination file never overwritten (fail before HTTP request)
# - Same-directory temporary file placement & atomic promotion
# - Guaranteed cleanup on failure & no partial destination
# - HTTP status codes (200, 404, 500) & redirects (302, loop limit)
# - Invalid URLs, unknown hosts, connection refusal
# - Truncated / interrupted transfers
# - JS compiler code generation & async analysis
# - Web & Desktop Bridge boundaries
# - CLI execution via otter.ps1

. "$PSScriptRoot\TestHelpers.ps1"

$sandbox = Join-Path $env:TEMP ("otter-dl-suite-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Path $sandbox -Force)
$originalLocation = (Get-Location).Path
Set-Location $sandbox

# Helper to run Otter source code through frontend + interpreter
function Invoke-TestScript {
    param([string]$Source)
    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($Text) $collected.Add($Text) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        $tokens = ConvertTo-OtterTokens -Source $Source
        $ast = ConvertTo-OtterAst -Tokens $tokens
        Invoke-OtterProgram -Program $ast -Environment (New-OtterEnvironment)
    }
    finally {
        Set-OtterOutputWriter -Writer $null
    }
    return , $collected.ToArray()
}

# -------------------------------------------------------------
# Spin up local loopback HTTP test server
# -------------------------------------------------------------
$tcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$tcp.Start()
$serverPort = $tcp.LocalEndpoint.Port
$tcp.Stop()

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$serverPort/")
$listener.Start()

$serverHits = [hashtable]::Synchronized(@{})

$runspace = [runspacefactory]::CreateRunspace()
$runspace.Open()
$runspace.SessionStateProxy.SetVariable("listener", $listener)
$runspace.SessionStateProxy.SetVariable("hits", $serverHits)
$runspace.SessionStateProxy.SetVariable("serverPort", $serverPort)

$psServer = [powershell]::Create()
$psServer.Runspace = $runspace
[void]$psServer.AddScript({
    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
            $req = $context.Request
            $res = $context.Response

            $urlPath = $req.Url.AbsolutePath
            $hits[$urlPath] = [int]$hits[$urlPath] + 1

            if ($urlPath -eq "/text") {
                $textData = "Hello Otter Download!`r`nLine 2`r`nSpecial chars: [brackets] & <symbols>"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($textData)
                $res.ContentType = "text/plain; charset=utf-8"
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                $res.Close()
            }
            elseif ($urlPath -eq "/binary") {
                # 512 bytes: full byte range 0..255 twice
                $binBytes = New-Object byte[] 512
                for ($i = 0; $i -lt 512; $i++) {
                    $binBytes[$i] = [byte]($i % 256)
                }
                $res.ContentType = "application/octet-stream"
                $res.ContentLength64 = $binBytes.Length
                $res.OutputStream.Write($binBytes, 0, $binBytes.Length)
                $res.Close()
            }
            elseif ($urlPath -eq "/zero") {
                $res.ContentType = "application/octet-stream"
                $res.ContentLength64 = 0
                $res.Close()
            }
            elseif ($urlPath -eq "/large") {
                # 512 KB payload
                $largeSize = 512 * 1024
                $res.ContentType = "application/octet-stream"
                $res.ContentLength64 = $largeSize
                $chunk = New-Object byte[] 65536
                for ($i = 0; $i -lt $chunk.Length; $i++) {
                    $chunk[$i] = [byte]($i % 251)
                }
                $sent = 0
                while ($sent -lt $largeSize) {
                    $toSend = [Math]::Min($chunk.Length, $largeSize - $sent)
                    $res.OutputStream.Write($chunk, 0, $toSend)
                    $sent += $toSend
                }
                $res.Close()
            }
            elseif ($urlPath -eq "/spaces%20in%20path/file.txt" -or $urlPath -eq "/spaces in path/file.txt") {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes("Content from space URL")
                $res.ContentType = "text/plain"
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                $res.Close()
            }
            elseif ($urlPath -eq "/redirect") {
                $res.StatusCode = 302
                $res.RedirectLocation = "/text"
                $res.Close()
            }
            elseif ($urlPath -eq "/redirect-chain-1") {
                $res.StatusCode = 302
                $res.RedirectLocation = "/redirect-chain-2"
                $res.Close()
            }
            elseif ($urlPath -eq "/redirect-chain-2") {
                $res.StatusCode = 302
                $res.RedirectLocation = "/text"
                $res.Close()
            }
            elseif ($urlPath -eq "/redirect-loop") {
                $res.StatusCode = 302
                $res.RedirectLocation = "http://127.0.0.1:$serverPort/redirect-loop"
                $res.Close()
            }
            elseif ($urlPath -eq "/error-404") {
                $res.StatusCode = 404
                $res.Close()
            }
            elseif ($urlPath -eq "/error-500") {
                $res.StatusCode = 500
                $res.Close()
            }
            elseif ($urlPath -eq "/abort-mid-stream") {
                $res.ContentLength64 = 50000
                $chunk = [System.Text.Encoding]::UTF8.GetBytes("Preliminary data before sudden connection abort...")
                $res.OutputStream.Write($chunk, 0, $chunk.Length)
                $res.OutputStream.Flush()
                $res.Abort()
            }
            elseif ($urlPath -eq "/recorded-hit") {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes("Recorded hit OK")
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                $res.Close()
            }
            elseif ($urlPath -eq "/slow-stream") {
                $bytes1 = [System.Text.Encoding]::UTF8.GetBytes("Part 1 of slow data`r`n")
                $bytes2 = [System.Text.Encoding]::UTF8.GetBytes("Part 2 of slow data`r`n")
                $res.ContentLength64 = $bytes1.Length + $bytes2.Length
                $res.OutputStream.Write($bytes1, 0, $bytes1.Length)
                $res.OutputStream.Flush()
                Start-Sleep -Milliseconds 400
                $res.OutputStream.Write($bytes2, 0, $bytes2.Length)
                $res.Close()
            }
            elseif ($urlPath -eq "/chunked-abort") {
                $res.SendChunked = $true
                $chunk = [System.Text.Encoding]::UTF8.GetBytes("Chunk data before connection dropped abruptly...")
                $res.OutputStream.Write($chunk, 0, $chunk.Length)
                $res.OutputStream.Flush()
                $res.Abort()
            }
            elseif ($urlPath -eq "/redirect-unsupported") {
                $res.StatusCode = 302
                $res.RedirectLocation = "ftp://127.0.0.1/forbidden.bin"
                $res.Close()
            }
            else {
                $res.StatusCode = 404
                $res.Close()
            }
        }
        catch {
            if (-not $listener.IsListening) { break }
        }
    }
})
$null = $psServer.BeginInvoke()
Start-Sleep -Milliseconds 150

Write-Host ''
Write-Host 'D96 File Download (Frontend + Backend Verification)' -ForegroundColor Cyan

try {
    # -------------------------------------------------------------
    # Group 1: Basic Download Semantics & Data Integrity
    # -------------------------------------------------------------

    Test-Otter 'Case 1: Download text file and verify byte-for-byte content' {
        $dest = Join-Path $sandbox 'downloaded_text.txt'
        $src = @"
download file from "http://127.0.0.1:$serverPort/text" to "$($dest.Replace('\', '/'))"
"@
        Invoke-TestScript -Source $src
        Assert-True (Test-Path -LiteralPath $dest) 'Destination file must exist after download'
        $expected = "Hello Otter Download!`r`nLine 2`r`nSpecial chars: [brackets] & <symbols>"
        $actual = [System.IO.File]::ReadAllText($dest, [System.Text.Encoding]::UTF8)
        Assert-AreEqual -Expected $expected -Actual $actual 'Content must match byte-for-byte'
    }

    Test-Otter 'Case 2: Download raw binary file (no text interpretation, null bytes intact)' {
        $dest = Join-Path $sandbox 'downloaded_binary.bin'
        $src = @"
download file from "http://127.0.0.1:$serverPort/binary" to "$($dest.Replace('\', '/'))"
"@
        Invoke-TestScript -Source $src
        Assert-True (Test-Path -LiteralPath $dest) 'Destination file must exist'
        $bytes = [System.IO.File]::ReadAllBytes($dest)
        Assert-AreEqual -Expected 512 -Actual $bytes.Length 'Must have exactly 512 bytes'
        for ($i = 0; $i -lt 512; $i++) {
            $expectedByte = [byte]($i % 256)
            if ($bytes[$i] -ne $expectedByte) {
                throw "Byte at offset $i differed: expected $expectedByte, got $($bytes[$i])"
            }
        }
    }

    Test-Otter 'Case 3: Download zero-byte file' {
        $dest = Join-Path $sandbox 'downloaded_zero.bin'
        $src = @"
download file from "http://127.0.0.1:$serverPort/zero" to "$($dest.Replace('\', '/'))"
"@
        Invoke-TestScript -Source $src
        Assert-True (Test-Path -LiteralPath $dest) 'Destination file must exist'
        $info = Get-Item -LiteralPath $dest
        Assert-AreEqual -Expected 0 -Actual $info.Length 'Zero-byte response must produce 0-byte file'
    }

    Test-Otter 'Case 4: Stream large file (512 KB chunked streaming)' {
        $dest = Join-Path $sandbox 'downloaded_large.bin'
        $src = @"
download file from "http://127.0.0.1:$serverPort/large" to "$($dest.Replace('\', '/'))"
"@
        Invoke-TestScript -Source $src
        Assert-True (Test-Path -LiteralPath $dest) 'Destination file must exist'
        $info = Get-Item -LiteralPath $dest
        Assert-AreEqual -Expected (512 * 1024) -Actual $info.Length 'Must be 512 KB'
    }

    # -------------------------------------------------------------
    # Group 2: Grammar, Expressions & Variables
    # -------------------------------------------------------------

    Test-Otter 'Case 5: Variable expressions for URL and path' {
        $dest = Join-Path $sandbox 'var_dest.txt'
        $src = @"
url is "http://127.0.0.1:$serverPort/text"
targetPath is "$($dest.Replace('\', '/'))"
download file from url to targetPath
"@
        Invoke-TestScript -Source $src
        Assert-True (Test-Path -LiteralPath $dest) 'File downloaded via variable arguments must exist'
    }

    Test-Otter 'Case 6: Concatenation expressions for URL and path' {
        $dest = Join-Path $sandbox 'concat_dest.txt'
        $src = @"
host is "http://127.0.0.1:$serverPort"
endpoint is "/text"
url is host and endpoint
folder is "$($sandbox.Replace('\', '/'))"
targetPath is folder and "/concat_dest.txt"
download file from url to targetPath
"@
        Invoke-TestScript -Source $src
        Assert-True (Test-Path -LiteralPath $dest) 'File downloaded via expressions must exist'
    }

    Test-Otter 'Case 7: Path containing spaces' {
        $dest = Join-Path $sandbox 'my space folder\spaced dest.txt'
        [void](New-Item -ItemType Directory -Path (Join-Path $sandbox 'my space folder') -Force)
        $src = @"
download file from "http://127.0.0.1:$serverPort/spaces in path/file.txt" to "$($dest.Replace('\', '/'))"
"@
        Invoke-TestScript -Source $src
        Assert-True (Test-Path -LiteralPath $dest) 'Destination with spaces must exist'
        $content = [System.IO.File]::ReadAllText($dest)
        Assert-AreEqual -Expected 'Content from space URL' -Actual $content
    }

    Test-Otter 'Case 8: Unicode filename in destination path' {
        $dest = Join-Path $sandbox ("dest_" + [char]0x65e5 + [char]0x672c + ".txt")
        $src = @"
download file from "http://127.0.0.1:$serverPort/text" to "$($dest.Replace('\', '/'))"
"@
        Invoke-TestScript -Source $src
        Assert-True (Test-Path -LiteralPath $dest) 'Unicode filename destination must exist'
    }

    Test-Otter 'Case 9: Relative destination path' {
        $relName = 'relative_dest_' + [Guid]::NewGuid().ToString('N').Substring(0, 6) + '.txt'
        $src = @"
download file from "http://127.0.0.1:$serverPort/text" to "./$relName"
"@
        Invoke-TestScript -Source $src
        Assert-True (Test-Path -LiteralPath (Join-Path $sandbox $relName)) 'Relative destination file must exist'
    }

    # -------------------------------------------------------------
    # Group 3: Directory and File Collision Rules
    # -------------------------------------------------------------

    Test-Otter 'Case 10: Parent folder does not exist fails before download' {
        $nonexistentDest = Join-Path $sandbox 'no_such_folder_12345\file.txt'
        $serverHits['/recorded-hit'] = 0
        $src = @"
download file from "http://127.0.0.1:$serverPort/recorded-hit" to "$($nonexistentDest.Replace('\', '/'))"
"@
        Assert-OtterFails -Body {
            Invoke-TestScript -Source $src
        } -Containing 'Otter does not create destination folders automatically'

        Assert-AreEqual -Expected 0 -Actual ([int]$serverHits['/recorded-hit']) 'Must not make HTTP request if parent folder does not exist'
    }

    Test-Otter 'Case 11: Destination already exists fails before HTTP request' {
        $existingFile = Join-Path $sandbox 'existing_precious_data.txt'
        [System.IO.File]::WriteAllText($existingFile, "Original Precious Data Never Overwrite")
        $serverHits['/recorded-hit'] = 0

        $src = @"
download file from "http://127.0.0.1:$serverPort/recorded-hit" to "$($existingFile.Replace('\', '/'))"
"@
        Assert-OtterFails -Body {
            Invoke-TestScript -Source $src
        } -Containing 'already exists. Otter will not overwrite it.'

        Assert-AreEqual -Expected 0 -Actual ([int]$serverHits['/recorded-hit']) 'Must fail before making HTTP request'
        $survivingContent = [System.IO.File]::ReadAllText($existingFile)
        Assert-AreEqual -Expected 'Original Precious Data Never Overwrite' -Actual $survivingContent 'Existing file must remain untouched'
    }

    Test-Otter 'Case 12: Destination path is an existing folder' {
        $folderPath = Join-Path $sandbox 'a_folder_target'
        [void](New-Item -ItemType Directory -Path $folderPath -Force)

        $src = @"
download file from "http://127.0.0.1:$serverPort/text" to "$($folderPath.Replace('\', '/'))"
"@
        Assert-OtterFails -Body {
            Invoke-TestScript -Source $src
        } -Containing 'is a folder, not a file'
    }

    # -------------------------------------------------------------
    # Group 4: Temporary File Invariants & Cleanup
    # -------------------------------------------------------------

    Test-Otter 'Case 13: Temporary file is created in destination directory and removed on success' {
        $dest = Join-Path $sandbox 'clean_temp_test.txt'
        $src = @"
download file from "http://127.0.0.1:$serverPort/text" to "$($dest.Replace('\', '/'))"
"@
        Invoke-TestScript -Source $src
        Assert-True (Test-Path -LiteralPath $dest) 'Destination exists'
        $leftovers = Get-ChildItem -Path $sandbox -Filter '.otter-dl-*.tmp'
        Assert-AreEqual -Expected 0 -Actual $leftovers.Count 'No temporary files should remain in destination dir'
    }

    # -------------------------------------------------------------
    # Group 5: HTTP Status Codes & Redirects
    # -------------------------------------------------------------

    Test-Otter 'Case 14: HTTP 404 fails cleanly with OtterError and leaves no artifacts' {
        $dest = Join-Path $sandbox 'nonexistent_404.txt'
        $src = @"
download file from "http://127.0.0.1:$serverPort/error-404" to "$($dest.Replace('\', '/'))"
"@
        Assert-OtterFails -Body {
            Invoke-TestScript -Source $src
        } -Containing 'HTTP status 404'

        Assert-False (Test-Path -LiteralPath $dest) 'Destination file must NOT exist after 404 failure'
        $leftovers = Get-ChildItem -Path $sandbox -Filter '.otter-dl-*.tmp'
        Assert-AreEqual -Expected 0 -Actual $leftovers.Count 'Temporary file must be cleaned up'
    }

    Test-Otter 'Case 15: HTTP 500 fails cleanly with OtterError and leaves no artifacts' {
        $dest = Join-Path $sandbox 'failed_500.txt'
        $src = @"
download file from "http://127.0.0.1:$serverPort/error-500" to "$($dest.Replace('\', '/'))"
"@
        Assert-OtterFails -Body {
            Invoke-TestScript -Source $src
        } -Containing 'HTTP status 500'

        Assert-False (Test-Path -LiteralPath $dest) 'Destination file must NOT exist after 500 failure'
        $leftovers = Get-ChildItem -Path $sandbox -Filter '.otter-dl-*.tmp'
        Assert-AreEqual -Expected 0 -Actual $leftovers.Count 'Temporary file must be cleaned up'
    }

    Test-Otter 'Case 16: HTTP 302 redirect followed successfully' {
        $dest = Join-Path $sandbox 'redirected_file.txt'
        $src = @"
download file from "http://127.0.0.1:$serverPort/redirect" to "$($dest.Replace('\', '/'))"
"@
        Invoke-TestScript -Source $src
        Assert-True (Test-Path -LiteralPath $dest) 'Redirected file must download successfully'
        $content = [System.IO.File]::ReadAllText($dest)
        Assert-True ($content -like '*Hello Otter Download*') 'Must contain target content'
    }

    Test-Otter 'Case 17: HTTP 302 multi-hop redirect chain followed' {
        $dest = Join-Path $sandbox 'chain_redirected_file.txt'
        $src = @"
download file from "http://127.0.0.1:$serverPort/redirect-chain-1" to "$($dest.Replace('\', '/'))"
"@
        Invoke-TestScript -Source $src
        Assert-True (Test-Path -LiteralPath $dest) 'Multi-hop redirected file must download'
    }

    Test-Otter 'Case 18: HTTP redirect loop fails cleanly with OtterError' {
        $dest = Join-Path $sandbox 'loop_file.txt'
        $src = @"
download file from "http://127.0.0.1:$serverPort/redirect-loop" to "$($dest.Replace('\', '/'))"
"@
        Assert-OtterFails -Body {
            Invoke-TestScript -Source $src
        } -Containing 'redirect limit'

        Assert-False (Test-Path -LiteralPath $dest) 'Destination must not exist on loop failure'
        $leftovers = Get-ChildItem -Path $sandbox -Filter '.otter-dl-*.tmp'
        Assert-AreEqual -Expected 0 -Actual $leftovers.Count 'Temporary file must be cleaned up'
    }

    # -------------------------------------------------------------
    # Group 6: Invalid URLs & Network Errors
    # -------------------------------------------------------------

    Test-Otter 'Case 19: Non-HTTP/HTTPS scheme rejected' {
        $dest = Join-Path $sandbox 'ftp_file.txt'
        $src = @"
download file from "ftp://example.com/file.txt" to "$($dest.Replace('\', '/'))"
"@
        Assert-OtterFails -Body {
            Invoke-TestScript -Source $src
        } -Containing 'only download files using http or https'
    }

    Test-Otter 'Case 20: Malformed URL rejected' {
        $dest = Join-Path $sandbox 'bad_url_file.txt'
        $src = @"
download file from "http://" to "$($dest.Replace('\', '/'))"
"@
        Assert-OtterFails -Body {
            Invoke-TestScript -Source $src
        } -Containing 'not a valid URL'
    }

    Test-Otter 'Case 21: Unresolvable host rejected cleanly' {
        $dest = Join-Path $sandbox 'unresolved_file.txt'
        $src = @"
download file from "http://nonexistent-domain-99999.invalid/data" to "$($dest.Replace('\', '/'))"
"@
        Assert-OtterFails -Body {
            Invoke-TestScript -Source $src
        } -Containing 'Could not'
        Assert-False (Test-Path -LiteralPath $dest)
    }

    Test-Otter 'Case 22: Connection refused rejected cleanly' {
        # Port 1 is reserved and closed
        $dest = Join-Path $sandbox 'refused_file.txt'
        $src = @"
download file from "http://127.0.0.1:1/file" to "$($dest.Replace('\', '/'))"
"@
        Assert-OtterFails -Body {
            Invoke-TestScript -Source $src
        } -Containing 'connection refused'
        Assert-False (Test-Path -LiteralPath $dest)
    }

    # -------------------------------------------------------------
    # Group 7: Interrupted & Truncated Transfers
    # -------------------------------------------------------------

    Test-Otter 'Case 23: Prematurely closed network connection cleaned up' {
        $dest = Join-Path $sandbox 'aborted_stream.bin'
        $src = @"
download file from "http://127.0.0.1:$serverPort/abort-mid-stream" to "$($dest.Replace('\', '/'))"
"@
        Assert-OtterFails -Body {
            Invoke-TestScript -Source $src
        }

        Assert-False (Test-Path -LiteralPath $dest) 'Destination file must NOT exist after aborted transfer'
        $leftovers = Get-ChildItem -Path $sandbox -Filter '.otter-dl-*.tmp'
        Assert-AreEqual -Expected 0 -Actual $leftovers.Count 'Temporary file must be removed after aborted transfer'
    }

    # -------------------------------------------------------------
    # Group 8: JavaScript Compiler Parity & Host Boundaries
    # -------------------------------------------------------------

    Test-Otter 'Case 24: JavaScript compiler emits await otterDownloadFile' {
        $tokens = ConvertTo-OtterTokens -Source 'download file from "http://example.com/a.txt" to "b.txt"'
        $ast = ConvertTo-OtterAst -Tokens $tokens
        $js = ConvertTo-OtterJsStatement -Stmt $ast.Statements[0]
        Assert-True ($js -like '*await otterDownloadFile(*') 'Compiled JS must include await otterDownloadFile'
    }

    Test-Otter 'Case 25: JavaScript compiler marks enclosing function as async' {
        $tokens = ConvertTo-OtterTokens -Source @"
to grabUrl url dest
    download file from url to dest
"@
        $ast = ConvertTo-OtterAst -Tokens $tokens
        $js = ConvertTo-OtterJsStatement -Stmt $ast.Statements[0]
        Assert-True ($js -like '*async function*') 'Function containing download file must compile to async'
    }

    Test-Otter 'Case 26: Web runtime without bridge throws clear error' {
        $tokens = ConvertTo-OtterTokens -Source 'say "hello"'
        $ast = ConvertTo-OtterAst -Tokens $tokens
        $webHtml = ConvertTo-OtterWeb -Program $ast
        Assert-True ($webHtml -like '*Desktop Bridge is not available for file download in this browser.*') 'Web runtime must bundle the bridge capability check'
    }

    Test-Otter 'Case 27: Desktop Bridge /api/fs/download endpoint works end-to-end' {
        $bridgeDest = Join-Path $sandbox 'bridge_download.txt'
        $bridge = Start-OtterTerminalBridge -Cwd $sandbox -Port 0
        try {
            $clientJobFs = Start-Job -ScriptBlock {
                param($port, $token, $targetUrl, $targetPath)
                Start-Sleep -Milliseconds 150
                $headers = @{
                    "X-Otter-Token" = $token
                    "Origin" = "http://127.0.0.1:$port"
                }
                $body = @{ url = $targetUrl; path = $targetPath } | ConvertTo-Json
                return (Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/fs/download" -Method Post -Headers $headers -Body $body -ContentType "application/json")
            } -ArgumentList $bridge.Port, $bridge.AuthToken, "http://127.0.0.1:$serverPort/text", $bridgeDest

            $bridge.HandleNextRequest(5000) | Out-Null
            $bridgeResult = Receive-Job -Job $clientJobFs -Wait
            Remove-Job -Job $clientJobFs -Force

            Assert-True ($bridgeResult.downloaded) 'Bridge response must report downloaded = true'
            Assert-True (Test-Path -LiteralPath $bridgeDest) 'File must be downloaded to disk via bridge'
            $content = [System.IO.File]::ReadAllText($bridgeDest)
            Assert-True ($content -like '*Hello Otter Download*') 'Content must match'
        }
        finally {
            Stop-OtterTerminalBridge -Session $bridge
        }
    }

    # -------------------------------------------------------------
    # Group 9: Production CLI Execution
    # -------------------------------------------------------------

    Test-Otter 'Case 28: Production CLI executes download file end-to-end' {
        $cliDest = Join-Path $sandbox 'cli_download.txt'
        $scriptPath = Join-Path $sandbox 'run_download.ot'
        $otCode = @"
download file from "http://127.0.0.1:$serverPort/text" to "$($cliDest.Replace('\', '/'))"
say "DOWNLOAD_CLI_SUCCESS"
"@
        [System.IO.File]::WriteAllText($scriptPath, $otCode)

        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $otterCli = Join-Path $repoRoot 'otter.ps1'

        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $otterCli $scriptPath
        Assert-AreEqual -Expected 0 -Actual $LASTEXITCODE 'CLI exit code must be 0'
        Assert-True (($output -join "`n") -like '*DOWNLOAD_CLI_SUCCESS*') 'CLI must print success message'
        Assert-True (Test-Path -LiteralPath $cliDest) 'Destination file must exist after CLI run'
    }

    # -------------------------------------------------------------
    # Group 10: Independent Release Audit Cases
    # -------------------------------------------------------------

    Test-Otter 'Case 29: Promotion / collision race — destination created while active' {
        $dest = Join-Path $sandbox 'collision_race_target.txt'
        $src = @"
download file from "http://127.0.0.1:$serverPort/slow-stream" to "$($dest.Replace('\', '/'))"
"@
        # Launch parallel job that waits 100ms and creates destination file before download finishes
        $raceJob = Start-Job -ScriptBlock {
            param($targetPath)
            Start-Sleep -Milliseconds 100
            [System.IO.File]::WriteAllText($targetPath, "Precious External File Must Not Be Overwritten")
        } -ArgumentList $dest

        try {
            Assert-OtterFails -Body {
                Invoke-TestScript -Source $src
            } -Containing 'already exists. Otter will not overwrite it.'
        }
        finally {
            Wait-Job $raceJob | Out-Null
            Remove-Job $raceJob -Force
        }

        # Destination must survive completely untouched
        Assert-True (Test-Path -LiteralPath $dest) 'Precious file must still exist'
        $content = [System.IO.File]::ReadAllText($dest)
        Assert-AreEqual -Expected 'Precious External File Must Not Be Overwritten' -Actual $content 'Precious file must not be overwritten'

        # Temp file must be removed
        $leftovers = Get-ChildItem -Path $sandbox -Filter '.otter-dl-*.tmp'
        Assert-AreEqual -Expected 0 -Actual $leftovers.Count 'Temporary file must be cleaned up after promotion race failure'
    }

    Test-Otter 'Case 30: Chunked transfer interrupted mid-stream fails and cleans up' {
        $dest = Join-Path $sandbox 'chunked_aborted_file.bin'
        $src = @"
download file from "http://127.0.0.1:$serverPort/chunked-abort" to "$($dest.Replace('\', '/'))"
"@
        Assert-OtterFails -Body {
            Invoke-TestScript -Source $src
        }

        Assert-False (Test-Path -LiteralPath $dest) 'Destination file must NOT exist after chunked abort'
        $leftovers = Get-ChildItem -Path $sandbox -Filter '.otter-dl-*.tmp'
        Assert-AreEqual -Expected 0 -Actual $leftovers.Count 'Temporary file must be removed'
    }

    Test-Otter 'Case 31: Redirect to unsupported scheme (ftp://) rejected' {
        $dest = Join-Path $sandbox 'redirect_unsupported.bin'
        $src = @"
download file from "http://127.0.0.1:$serverPort/redirect-unsupported" to "$($dest.Replace('\', '/'))"
"@
        Assert-OtterFails -Body {
            Invoke-TestScript -Source $src
        } -Containing 'only download files using http or https'

        Assert-False (Test-Path -LiteralPath $dest) 'Destination file must NOT exist'
        $leftovers = Get-ChildItem -Path $sandbox -Filter '.otter-dl-*.tmp'
        Assert-AreEqual -Expected 0 -Actual $leftovers.Count 'Temporary file must be removed'
    }

    Test-Otter 'Case 32: Desktop Bridge security: unauthenticated request rejected (401)' {
        $bridge = Start-OtterTerminalBridge -Cwd $sandbox -Port 0
        try {
            $clientJob = Start-Job -ScriptBlock {
                param($port, $targetUrl, $targetPath)
                Start-Sleep -Milliseconds 150
                $headers = @{ "Origin" = "http://127.0.0.1:$port" }
                $body = @{ url = $targetUrl; path = $targetPath } | ConvertTo-Json
                try {
                    Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/fs/download" -Method Post -Headers $headers -Body $body -ContentType "application/json"
                    return "UnexpectedSuccess"
                } catch {
                    return $_.Exception.Response.StatusCode.value__
                }
            } -ArgumentList $bridge.Port, "http://127.0.0.1:$serverPort/text", (Join-Path $sandbox 'unauth.txt')

            $bridge.HandleNextRequest(5000) | Out-Null
            $statusCode = Receive-Job -Job $clientJob -Wait
            Remove-Job -Job $clientJob -Force

            Assert-AreEqual -Expected 401 -Actual $statusCode 'Unauthenticated request must return 401 Unauthorized'
        }
        finally {
            Stop-OtterTerminalBridge -Session $bridge
        }
    }

    Test-Otter 'Case 33: Desktop Bridge security: invalid token rejected (403)' {
        $bridge = Start-OtterTerminalBridge -Cwd $sandbox -Port 0
        try {
            $clientJob = Start-Job -ScriptBlock {
                param($port, $targetUrl, $targetPath)
                Start-Sleep -Milliseconds 150
                $headers = @{
                    "X-Otter-Token" = "bogus-invalid-token"
                    "Origin" = "http://127.0.0.1:$port"
                }
                $body = @{ url = $targetUrl; path = $targetPath } | ConvertTo-Json
                try {
                    Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/fs/download" -Method Post -Headers $headers -Body $body -ContentType "application/json"
                    return "UnexpectedSuccess"
                } catch {
                    return $_.Exception.Response.StatusCode.value__
                }
            } -ArgumentList $bridge.Port, "http://127.0.0.1:$serverPort/text", (Join-Path $sandbox 'unauth2.txt')

            $bridge.HandleNextRequest(5000) | Out-Null
            $statusCode = Receive-Job -Job $clientJob -Wait
            Remove-Job -Job $clientJob -Force

            Assert-AreEqual -Expected 403 -Actual $statusCode 'Invalid token request must return 403 Forbidden'
        }
        finally {
            Stop-OtterTerminalBridge -Session $bridge
        }
    }

    Test-Otter 'Case 34: Desktop Bridge security: file:// protocol rejected' {
        $bridge = Start-OtterTerminalBridge -Cwd $sandbox -Port 0
        try {
            $clientJob = Start-Job -ScriptBlock {
                param($port, $token, $targetPath)
                Start-Sleep -Milliseconds 150
                $headers = @{
                    "X-Otter-Token" = $token
                    "Origin" = "http://127.0.0.1:$port"
                }
                $body = @{ url = "file:///C:/Windows/win.ini"; path = $targetPath } | ConvertTo-Json
                try {
                    Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/fs/download" -Method Post -Headers $headers -Body $body -ContentType "application/json"
                    return "UnexpectedSuccess"
                } catch {
                    if ($_.ErrorDetails) { return $_.ErrorDetails.Message }
                    if ($_.Exception -and $_.Exception.Response) {
                        try {
                            $stream = $_.Exception.Response.GetResponseStream()
                            if ($stream) {
                                $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
                                return $reader.ReadToEnd()
                            }
                        } catch { }
                    }
                    return $_.Exception.Message
                }
            } -ArgumentList $bridge.Port, $bridge.AuthToken, (Join-Path $sandbox 'bridge_file_reject.txt')

            $bridge.HandleNextRequest(5000) | Out-Null
            $errResponse = Receive-Job -Job $clientJob -Wait
            Remove-Job -Job $clientJob -Force

            Assert-True ($errResponse -like '*http or https*') 'Bridge must reject non-http schemes'
        }
        finally {
            Stop-OtterTerminalBridge -Session $bridge
        }
    }
}
finally {
    # Teardown test server
    try {
        $listener.Stop()
        $listener.Close()
        $psServer.Dispose()
        $runspace.Dispose()
    } catch { }

    Set-Location $originalLocation
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests
