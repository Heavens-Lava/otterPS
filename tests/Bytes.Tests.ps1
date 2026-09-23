# tests/Bytes.Tests.ps1
#
# Production-entry-point certification for D102 (the bytes type) - see
# rules.md's own design principle: text is text, bytes are bytes, hex/
# base64 are textual REPRESENTATIONS of bytes, never silently
# interchangeable. Console (`otter run`) and web (`otter web`) targets
# are both exercised for real, matching this project's "a unit test
# does not certify a language capability" rule.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Bytes Type (D102)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'

function Invoke-OtterProgram {
    param([string]$Source, [string]$Mode = 'run')

    $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d102_$([Guid]::NewGuid().ToString('N')).ot")
    [System.IO.File]::WriteAllText($tmpFile, $Source, [System.Text.UTF8Encoding]::new($false))
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:OtterPs1`" $Mode `"$tmpFile`" -NoOpen"
        $psi.WorkingDirectory = $script:RepoRoot
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit(15000) | Out-Null
        return [pscustomobject]@{ Stdout = $stdout; ExitCode = $process.ExitCode }
    } finally {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
        $htmlPath = [System.IO.Path]::ChangeExtension($tmpFile, '.html')
        Remove-Item -LiteralPath $htmlPath -Force -ErrorAction SilentlyContinue
    }
}


# --- 1. The full acceptance example from the D102 design spec -----------

Test-Otter 'the full D102 acceptance example produces exactly the specified output' {
    $r = Invoke-OtterProgram -Source @'
message is "Hello, Otter!"

raw is bytes from text message

say length of raw
say hex from bytes raw
say base64 from bytes raw

encoded is base64 from bytes raw
decoded is bytes from base64 encoded
result is text from bytes decoded

say result
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('13', '48656C6C6F2C204F7474657221', 'SGVsbG8sIE90dGVyIQ==', 'Hello, Otter!') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'the same acceptance example produces identical output on the web target' {
    $r = Invoke-OtterProgram -Source @'
message is "Hello, Otter!"
raw is bytes from text message
say length of raw
say hex from bytes raw
say base64 from bytes raw
'@ -Mode 'web'
    Assert-True ($r.Stdout -match 'compiled to') 'expected the web build to succeed'
}


# --- 2. Round trips (text/hex/base64 all the way through) ---------------

Test-Otter 'bytes from text / text from bytes round-trips exactly' {
    $r = Invoke-OtterProgram -Source @'
data is bytes from text "Hello"
message is text from bytes data
say message
'@
    Assert-Lines -Expected @('Hello') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'bytes from hex (lowercase input) / text from bytes round-trips correctly' {
    $r = Invoke-OtterProgram -Source @'
data is bytes from hex "48656c6c6f"
say text from bytes data
'@
    Assert-Lines -Expected @('Hello') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'bytes from base64 / text from bytes round-trips correctly' {
    $r = Invoke-OtterProgram -Source @'
data is bytes from base64 "SGVsbG8="
say text from bytes data
'@
    Assert-Lines -Expected @('Hello') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'empty bytes has length 0' {
    $r = Invoke-OtterProgram -Source @'
data is empty bytes
say length of data
'@
    Assert-Lines -Expected @('0') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}


# --- 3. Equality (structural, not reference) -----------------------------

Test-Otter 'two bytes values decoded from the same hex compare equal, a different one does not' {
    $r = Invoke-OtterProgram -Source @'
firstBytes is bytes from hex "010203"
secondBytes is bytes from hex "010203"
if firstBytes is secondBytes
    say "Same bytes"
.
thirdBytes is bytes from hex "010204"
if not firstBytes is thirdBytes
    say "Different bytes"
.
'@
    Assert-Lines -Expected @('Same bytes', 'Different bytes') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}


# --- 4. Errors fail loudly, never silently ------------------------------

Test-Otter 'bytes from hex with non-hex text is a clean Otter runtime error' {
    $r = Invoke-OtterProgram -Source 'bad is bytes from hex "NOT HEX"'
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match "as hex") 'expected a specific bad-hex diagnostic'
}

Test-Otter 'bytes from base64 with invalid base64 is a clean Otter runtime error' {
    $r = Invoke-OtterProgram -Source 'bad is bytes from base64 "invalid..."'
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'as base64') 'expected a specific bad-base64 diagnostic'
}

Test-Otter 'text from bytes on invalid UTF-8 is a clean Otter runtime error, not a raw exception' {
    $r = Invoke-OtterProgram -Source @'
bad is bytes from hex "FFFE"
t is text from bytes bad
'@
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match "aren't valid UTF-8") 'expected a specific invalid-UTF-8 diagnostic'
    Assert-False ($r.Stdout -match 'at System\.') 'a raw .NET stack trace must never reach the user'
}

Test-Otter 'text from bytes on a non-bytes value is a clean Otter runtime error' {
    $r = Invoke-OtterProgram -Source @'
x is 5
y is text from bytes x
'@
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'I can only read text from bytes') 'expected a specific wrong-type diagnostic'
}


# --- 5. A plain `say` of bytes never guesses a representation -----------

Test-Otter 'saying a bytes value directly never implies hex or text, only a byte count' {
    $r = Invoke-OtterProgram -Source @'
raw is bytes from text "Hello"
say raw
'@
    Assert-Lines -Expected @('<5 bytes>') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}


# --- 6. Keyword narrowing (no regressions) --------------------------------

Test-Otter 'bytes/text/hex/base64/empty remain ordinary identifiers everywhere else' {
    $r = Invoke-OtterProgram -Source @'
bytes is 5
text is "hi"
hex is 3
base64 is "abc"
say bytes
say text
say hex
say base64
shelf are empty
say "shelf is empty"
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('5', 'hi', '3', 'abc', 'shelf is empty') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Complete-OtterTests
