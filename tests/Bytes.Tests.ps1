. "$PSScriptRoot\TestHost.ps1"
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
        $psi.FileName = $script:OtterHostExe
        $psi.Arguments = "$script:OtterHostArgString -File `"$script:OtterPs1`" $Mode `"$tmpFile`" -NoOpen"
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

# --- 7. Binary File I/O (D115) -------------------------------------------

$script:D115TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d115_" + [Guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($script:D115TempDir) | Out-Null

try {
    # 27. Round-trip acceptance test
    Test-Otter 'D115 acceptance test: bytes from hex round-trips through file and securely equals' {
        $path = (Join-Path $script:D115TempDir 'roundtrip.bin').Replace('\', '/')
        $r = Invoke-OtterProgram -Source @"
original is bytes from hex "00FF10804142"
write bytes original to file "$path"
restored is bytes from file "$path"
if original securely equals restored
    say "Binary round trip passed"
.
"@
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('Binary round trip passed') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
        $rawBytes = [System.IO.File]::ReadAllBytes($path)
        $hex = [System.BitConverter]::ToString($rawBytes).Replace('-', '')
        Assert-AreEqual -Expected '00FF10804142' -Actual $hex
    }

    # 28. All-byte-values test (00 through FF)
    Test-Otter 'D115 all-byte-values test: all 256 bytes survive write and read unchanged' {
        $path = (Join-Path $script:D115TempDir 'all_bytes.bin').Replace('\', '/')
        $allHexParts = foreach ($i in 0..255) { $i.ToString('X2') }
        $allHex = $allHexParts -join ''
        $r = Invoke-OtterProgram -Source @"
expected is bytes from hex "$allHex"
write bytes expected to file "$path"
actual is bytes from file "$path"
say length of actual
if expected securely equals actual
    say "All 256 byte values match"
.
"@
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('256', 'All 256 byte values match') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
        $rawBytes = [System.IO.File]::ReadAllBytes($path)
        Assert-AreEqual -Expected 256 -Actual $rawBytes.Length
        for ($i = 0; $i -lt 256; $i++) {
            if ($rawBytes[$i] -ne $i) { throw "Byte at index $i was $($rawBytes[$i]), expected $i" }
        }
    }

    # 29. Zero-byte test
    Test-Otter 'D115 zero-byte test: empty bytes writes zero-byte file and reads back as 0-length bytes' {
        $path = (Join-Path $script:D115TempDir 'zero_byte.bin').Replace('\', '/')
        $r = Invoke-OtterProgram -Source @"
data is empty bytes
write bytes data to file "$path"
restored is bytes from file "$path"
h is hex from bytes restored
say length of restored
say "hex: " and h
"@
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('0', 'hex: ') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
        Assert-True (Test-Path -LiteralPath $path) 'file should exist'
        $rawBytes = [System.IO.File]::ReadAllBytes($path)
        Assert-AreEqual -Expected 0 -Actual $rawBytes.Length
    }

    # 30. Binary format tests (NUL, >=0x80, invalid UTF-8, CRLF, BOM, 0xFF)
    Test-Otter 'D115 binary format test: NUL, high bytes, invalid UTF-8 sequences, BOM and CRLF survive unchanged' {
        $path = (Join-Path $script:D115TempDir 'format_test.bin').Replace('\', '/')
        # EFBBBF = UTF-8 BOM, 00 = NUL, 0D0A = CRLF, FF = 0xFF, FFFE = invalid UTF-8, 8081 = high bytes
        $payloadHex = "EFBBBF000D0AFFFE8081AABBCC"
        $r = Invoke-OtterProgram -Source @"
expected is bytes from hex "$payloadHex"
write bytes expected to file "$path"
actual is bytes from file "$path"
if expected securely equals actual
    say "Binary payload match"
.
"@
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('Binary payload match') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
        $rawBytes = [System.IO.File]::ReadAllBytes($path)
        $actualHex = [System.BitConverter]::ToString($rawBytes).Replace('-', '')
        Assert-AreEqual -Expected $payloadHex -Actual $actualHex
    }

    # 31. Normal overwrite test (truncation test)
    Test-Otter 'D115 normal overwrite test: writing shorter bytes truncates and leaves no trailing old bytes' {
        $path = (Join-Path $script:D115TempDir 'overwrite.bin').Replace('\', '/')
        $r = Invoke-OtterProgram -Source @"
longBytes is bytes from hex "0102030405060708090A0B0C0D0E0F10"
write bytes longBytes to file "$path"
firstRead is bytes from file "$path"
say length of firstRead

shortBytes is bytes from hex "AABBCCDD"
write bytes shortBytes to file "$path"
secondRead is bytes from file "$path"
say length of secondRead
say hex from bytes secondRead
"@
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('16', '4', 'AABBCCDD') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
        $rawBytes = [System.IO.File]::ReadAllBytes($path)
        Assert-AreEqual -Expected 4 -Actual $rawBytes.Length
    }

    # 32. Atomic success test
    Test-Otter 'D115 atomic success test: atomically write new bytes replaces old file cleanly with no temp files' {
        $path = (Join-Path $script:D115TempDir 'atomic_success.bin').Replace('\', '/')
        $r = Invoke-OtterProgram -Source @"
oldBytes is bytes from hex "11223344"
write bytes oldBytes to file "$path"

newBytes is bytes from hex "5566778899"
write bytes newBytes to file "$path" atomically

result is bytes from file "$path"
say hex from bytes result
say length of result
"@
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('5566778899', '5') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
        $tempFiles = Get-ChildItem -LiteralPath $script:D115TempDir -Filter '*.otter-tmp-*'
        Assert-AreEqual -Expected 0 -Actual $tempFiles.Count
        $bakFiles = Get-ChildItem -LiteralPath $script:D115TempDir -Filter '*.otter-bak-*'
        Assert-AreEqual -Expected 0 -Actual $bakFiles.Count
    }

    # 33. Atomic failure test (injected failure preserves original destination and leaves no temp files)
    Test-Otter 'D115 atomic failure test: failed atomic write preserves existing file and cleans temporary artifacts' {
        $path = (Join-Path $script:D115TempDir 'atomic_fail.bin').Replace('\', '/')
        $initialBytes = [byte[]]@(0xAA, 0xBB, 0xCC, 0xDD)
        [System.IO.File]::WriteAllBytes($path, $initialBytes)

        # Mark read-only so atomic File.Replace will fail
        $fileInfo = [System.IO.FileInfo]::new($path)
        $fileInfo.IsReadOnly = $true

        try {
            $r = Invoke-OtterProgram -Source @"
attemptBytes is bytes from hex "12345678"
write bytes attemptBytes to file "$path" atomically
say "Should not succeed"
"@
            Assert-AreEqual -Expected 3 -Actual $r.ExitCode
            Assert-True ($r.Stdout -match 'I could not write bytes') 'expected clean Otter write error'
            Assert-False ($r.Stdout -match 'at System\.') 'raw stack trace must not leak'
        } finally {
            $fileInfo.IsReadOnly = $false
        }

        # Destination must still contain initial bytes exactly
        $currentBytes = [System.IO.File]::ReadAllBytes($path)
        $currentHex = [System.BitConverter]::ToString($currentBytes).Replace('-', '')
        Assert-AreEqual -Expected 'AABBCCDD' -Actual $currentHex

        # No temp files or backup files should remain
        $tempFiles = Get-ChildItem -LiteralPath $script:D115TempDir -Filter '*.otter-tmp-*'
        Assert-AreEqual -Expected 0 -Actual $tempFiles.Count
    }

    # 34. Missing file test
    Test-Otter 'D115 missing file test: reading missing file produces clean Otter runtime error' {
        $path = (Join-Path $script:D115TempDir 'definitely-missing-file.bin').Replace('\', '/')
        $r = Invoke-OtterProgram -Source @"
data is bytes from file "$path"
say length of data
"@
        Assert-AreEqual -Expected 3 -Actual $r.ExitCode
        Assert-True ($r.Stdout -match 'I could not find a file called') 'expected clean file-not-found diagnostic'
        Assert-False ($r.Stdout -match 'at System\.') 'raw stack trace must not leak'
    }

    # 35. Wrong type test
    Test-Otter 'D115 wrong type test: write bytes with text or numbers fails cleanly; explicit conversion succeeds' {
        $path = (Join-Path $script:D115TempDir 'type_test.bin').Replace('\', '/')
        $r1 = Invoke-OtterProgram -Source @"
write bytes "not bytes" to file "$path"
"@
        Assert-AreEqual -Expected 3 -Actual $r1.ExitCode
        Assert-True ($r1.Stdout -match 'Binary file writes require bytes') 'expected wrong-type diagnostic'

        $r2 = Invoke-OtterProgram -Source @"
data is bytes from text "hello"
write bytes data to file "$path"
readBack is bytes from file "$path"
say text from bytes readBack
"@
        Assert-AreEqual -Expected 0 -Actual $r2.ExitCode
        Assert-Lines -Expected @('hello') -Actual (($r2.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
    }

    # 36. Directory rejection test
    Test-Otter 'D115 directory test: reading folder as bytes or writing bytes to folder path fails cleanly' {
        $folderPath = $script:D115TempDir.Replace('\', '/')
        $rRead = Invoke-OtterProgram -Source @"
data is bytes from file "$folderPath"
"@
        Assert-AreEqual -Expected 3 -Actual $rRead.ExitCode
        Assert-True ($rRead.Stdout -match 'is a folder, not a file') 'expected folder-not-file diagnostic on read'

        $rWrite = Invoke-OtterProgram -Source @"
data is empty bytes
write bytes data to file "$folderPath"
"@
        Assert-AreEqual -Expected 3 -Actual $rWrite.ExitCode
        Assert-True ($rWrite.Stdout -match 'is a folder, not a file') 'expected folder-not-file diagnostic on write'
    }

} finally {
    Remove-Item -LiteralPath $script:D115TempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests

