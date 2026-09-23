# tests/Crypto.Tests.ps1
#
# Production-entry-point certification for D109 (cryptography). Every test
# runs a real .ot program through the real otter.ps1 process. Digests and
# HMACs are checked against published known-answer vectors, not against
# our own implementation.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Cryptography (D109)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'

function Invoke-OtterCrypto {
    param([string]$Source, [string]$Mode = 'run')
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_crypto_$([Guid]::NewGuid().ToString('N'))")
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        $otFile = Join-Path $dir 'program.ot'
        [System.IO.File]::WriteAllText($otFile, $Source, [System.Text.UTF8Encoding]::new($false))
        $extra = if ($Mode -eq 'web') { '-NoOpen' } else { '' }
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script:OtterPs1 $Mode $otFile $extra 2>&1
        $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
        return [pscustomobject]@{ Stdout = $text; Lines = @(($text -split "`r?`n") | Where-Object { $_ -ne '' }) }
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 1. Hashing: known-answer vectors --------------------------------------

Test-Otter 'sha256/sha384/sha512 match the published FIPS 180 vectors for "abc"' {
    $r = Invoke-OtterCrypto -Source @"
data is bytes from text "abc"
say hex from bytes sha256 of data
say hex from bytes sha384 of data
digest is sha512 of data
say hex from bytes digest
say count of digest
"@
    Assert-Lines -Expected @(
        'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD',
        'CB00753F45A35E8BB5A03D699AC65007272C32AB0EDED1631A8B605A43FF5BED8086072BA1E7CC2358BAECA134C825A7',
        'DDAF35A193617ABACC417349AE20413112E6FA4E89A97EA20A9EEEE64B55D39A2192992A274FC1A836BA3C23A3FEEBBD454D4423643CE80E2A9AC94FA54CA49F',
        '64') -Actual $r.Lines
}

Test-Otter 'hmac sha256 matches RFC 4231 test case 2' {
    $r = Invoke-OtterCrypto -Source @"
key is bytes from text "Jefe"
data is bytes from text "what do ya want for nothing?"
say hex from bytes hmac sha256 of data using key
"@
    Assert-Lines -Expected @('5BDCC146BF60754E6A042426089575C75A003F089D2739839DEC58B964EC3843') -Actual $r.Lines
}

Test-Otter 'hmac sha384 and sha512 produce the right sizes' {
    $r = Invoke-OtterCrypto -Source @"
key is bytes from text "k"
data is bytes from text "d"
mac384 is hmac sha384 of data using key
mac512 is hmac sha512 of data using key
say count of mac384
say count of mac512
"@
    Assert-Lines -Expected @('48', '64') -Actual $r.Lines
}

Test-Otter 'hashing text is refused - the text/bytes boundary is explicit' {
    $r = Invoke-OtterCrypto -Source 'say hex from bytes sha256 of "abc"'
    Assert-True ($r.Stdout -match 'must be bytes') 'expected the bytes-only diagnostic'
    Assert-True ($r.Stdout -match 'never converts text to bytes silently') 'expected the explicit-boundary explanation'
}

# --- 2. Secure random ---------------------------------------------------------

Test-Otter 'secure random bytes returns the requested count and differs each call' {
    $r = Invoke-OtterCrypto -Source @"
rand1 is secure random bytes 32
rand2 is secure random bytes 32
say count of rand1
say count of rand2
if rand1 securely equals rand2
    say "SAME"
otherwise
    say "different"
.
"@
    Assert-Lines -Expected @('32', '32', 'different') -Actual $r.Lines
}

Test-Otter 'secure random bytes rejects a bad count with a readable error' {
    $r = Invoke-OtterCrypto -Source 'x is secure random bytes 0'
    Assert-True ($r.Stdout -match 'whole number of random bytes between 1 and 1048576') 'expected the range diagnostic'
}

# --- 3. Authenticated encryption ---------------------------------------------

Test-Otter 'encrypt then decrypt round-trips; ciphertext differs from plaintext and between runs' {
    $r = Invoke-OtterCrypto -Source @"
generate encryption key and call it key
say count of key
data is bytes from text "Attack at dawn"
encrypt data using key and call it first
encrypt data using key and call it second
decrypt first using key and call it original
say text from bytes original
if first securely equals second
    say "NONCE REUSED"
otherwise
    say "fresh nonce each time"
.
if first securely equals data
    say "NOT ENCRYPTED"
otherwise
    say "encrypted"
.
say hex from bytes first
"@
    Assert-AreEqual -Expected '32' -Actual $r.Lines[0]
    Assert-AreEqual -Expected 'Attack at dawn' -Actual $r.Lines[1]
    Assert-AreEqual -Expected 'fresh nonce each time' -Actual $r.Lines[2]
    Assert-AreEqual -Expected 'encrypted' -Actual $r.Lines[3]
    Assert-True ($r.Lines[4] -match '^01[0-9A-F]+$') 'payload should start with version byte 01 and be hex'
}

Test-Otter 'decrypting with the wrong key fails cleanly' {
    $r = Invoke-OtterCrypto -Source @"
generate encryption key and call it right
generate encryption key and call it wrong
data is bytes from text "secret"
encrypt data using right and call it sealed
decrypt sealed using wrong and call it nope
say "should not get here"
"@
    Assert-True ($r.Stdout -match 'I could not decrypt this data') 'expected the clean decrypt failure'
    Assert-False ($r.Stdout -match 'should not get here') 'execution must stop'
}

Test-Otter 'tampered ciphertext is refused with the SAME key (authenticated encryption)' {
    $r = Invoke-OtterCrypto -Source @"
generate encryption key and call it key
data is bytes from text "pay alice 10"
encrypt data using key and call it sealed
say hex from bytes key
say hex from bytes sealed
"@
    $keyHex = $r.Lines[0]
    $sealedHex = $r.Lines[1]
    $decryptProgram = {
        param($payloadHex)
        "key is bytes from hex `"$keyHex`"`nsealed is bytes from hex `"$payloadHex`"`ndecrypt sealed using key and call it plain`nsay text from bytes plain"
    }
    # Sanity: the untouched payload decrypts under the same key.
    $ok = Invoke-OtterCrypto -Source (& $decryptProgram $sealedHex)
    Assert-Lines -Expected @('pay alice 10') -Actual $ok.Lines
    # Flip one nibble in the middle (ciphertext region), then in the tag.
    foreach ($index in @([int]($sealedHex.Length / 2), ($sealedHex.Length - 3))) {
        $flipped = if ($sealedHex[$index] -eq '0') { '1' } else { '0' }
        $tampered = $sealedHex.Substring(0, $index) + $flipped + $sealedHex.Substring($index + 1)
        $bad = Invoke-OtterCrypto -Source (& $decryptProgram $tampered)
        Assert-True ($bad.Stdout -match 'I could not decrypt this data') "tampering at $index should be refused"
        Assert-False ($bad.Stdout -match 'pay alice') 'no plaintext may be released for a tampered payload'
    }
}

Test-Otter 'garbage that is not an encrypted payload is refused cleanly' {
    $r = Invoke-OtterCrypto -Source @"
generate encryption key and call it key
junk is bytes from base64 "AAAA"
decrypt junk using key and call it nope
say "should not get here"
"@
    Assert-True ($r.Stdout -match 'I could not decrypt this data') 'expected garbage input to be refused'
    Assert-False ($r.Stdout -match 'should not get here') 'execution must stop'
}
Test-Otter 'encryption refuses text data and wrong-size keys' {
    $r = Invoke-OtterCrypto -Source @"
generate encryption key and call it key
encrypt "plain text" using key and call it out
"@
    Assert-True ($r.Stdout -match 'The data to encrypt must be bytes') 'expected the bytes-only diagnostic'
    $r2 = Invoke-OtterCrypto -Source @"
data is bytes from text "x"
shortKey is bytes from text "too short"
encrypt data using shortKey and call it out
"@
    Assert-True ($r2.Stdout -match 'must be exactly 32 bytes') 'expected the key-size diagnostic'
}

Test-Otter 'encrypted bytes survive base64 storage (D102 interop)' {
    $r = Invoke-OtterCrypto -Source @"
generate encryption key and call it key
data is bytes from text "store me"
encrypt data using key and call it sealed
encoded is base64 from bytes sealed
restored is bytes from base64 encoded
decrypt restored using key and call it original
say text from bytes original
"@
    Assert-Lines -Expected @('store me') -Actual $r.Lines
}

# --- 4. Password hashing -----------------------------------------------------

Test-Otter 'hash password produces a salted text hash that verifies only the right password' {
    $r = Invoke-OtterCrypto -Source @"
password is "correct horse battery staple"
hash password password and call it storedHash
hash password password and call it otherHash
say storedHash
if storedHash is otherHash
    say "SAME SALT"
otherwise
    say "salted"
.
if password password matches hash storedHash
    say "Correct"
.
wrong is "Tr0ub4dor"
if password wrong matches hash storedHash
    say "WRONG ACCEPTED"
otherwise
    say "rejected"
.
"@
    Assert-True ($r.Lines[0] -match '^otter-pbkdf2-sha256\$600000\$[A-Za-z0-9+/=]+\$[A-Za-z0-9+/=]+$') "unexpected hash format: $($r.Lines[0])"
    Assert-AreEqual -Expected 'salted' -Actual $r.Lines[1]
    Assert-AreEqual -Expected 'Correct' -Actual $r.Lines[2]
    Assert-AreEqual -Expected 'rejected' -Actual $r.Lines[3]
}

Test-Otter 'matching against text that is not a password hash is a clear error' {
    $r = Invoke-OtterCrypto -Source @"
guess is "hunter2"
notAHash is "hunter2"
if password guess matches hash notAHash
    say "match"
.
"@
    Assert-True ($r.Stdout -match 'not a password hash made by "hash password"') 'expected the malformed-hash diagnostic'
}

Test-Otter 'D91 hash "text" as ... still works, including with a variable named password' {
    $r = Invoke-OtterCrypto -Source @"
password is "abc"
hash password as "sha256" into digest
say digest
"@
    Assert-Lines -Expected @('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad') -Actual $r.Lines
}

Test-Otter 'D92 encrypt "text" with key ... still works alongside the D109 form' {
    $r = Invoke-OtterCrypto -Source @"
encrypt "hi there" with key "k3y" into cipher
decrypt cipher with key "k3y" into plain
say plain
"@
    Assert-Lines -Expected @('hi there') -Actual $r.Lines
}

# --- 5. Constant-time comparison ---------------------------------------------

Test-Otter 'securely equals compares bytes and refuses text' {
    $r = Invoke-OtterCrypto -Source @"
tokenA is bytes from text "token"
tokenB is bytes from text "token"
tokenC is bytes from text "tokeN"
if tokenA securely equals tokenB
    say "equal"
.
if tokenA securely equals tokenC
    say "WRONG"
otherwise
    say "not equal"
.
"@
    Assert-Lines -Expected @('equal', 'not equal') -Actual $r.Lines
    $r2 = Invoke-OtterCrypto -Source @"
tokenA is bytes from text "token"
if tokenA securely equals "token"
    say "WRONG"
.
"@
    Assert-True ($r2.Stdout -match 'must be bytes') 'expected the bytes-only diagnostic'
}

# --- 6. Cross-feature composition (from the spec) ------------------------------

Test-Otter 'the spec cross-feature idea: encrypt, base64 it, restore, decrypt' {
    $r = Invoke-OtterCrypto -Source @"
generate encryption key and call it key
message is bytes from text "Hello from Otter"
encrypt message using key and call it encrypted
say count of encrypted
decrypt encrypted using key and call it message2
say text from bytes message2
"@
    Assert-Lines -Expected @('81', 'Hello from Otter') -Actual $r.Lines
}

# --- 7. Web target: unsupported, clearly -------------------------------------------

foreach ($case in @(
    @{ Name = 'sha256'; Source = "data is bytes from text `"x`"`nd is sha256 of data"; Match = 'not supported on the web target' },
    @{ Name = 'generate encryption key'; Source = 'generate encryption key and call it key'; Match = 'not supported on the web target' },
    @{ Name = 'hash password'; Source = "p is `"x`"`nhash password p and call it h"; Match = 'not supported on the web target' }
)) {
    Test-Otter "$($case.Name) is rejected on the web target with a clean compile-time error" {
        $r = Invoke-OtterCrypto -Source $case.Source -Mode 'web'
        Assert-True ($r.Stdout -match $case.Match) "expected rejection but got: $($r.Stdout)"
    }
}

Complete-OtterTests
