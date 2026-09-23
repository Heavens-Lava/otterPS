# tests/Vault.Tests.ps1
#
# Production-entry-point certification for D111 (credential vault). Every
# test runs real .ot files through the real otter.ps1 process against the
# REAL operating-system credential store (Windows Credential Manager),
# using GUID-named secrets that each test deletes again.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Credential vault (D111)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'

function New-VaultSandbox {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_vault_$([Guid]::NewGuid().ToString('N'))")
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

# Runs Source as <Dir>\<FileName>. The file's full path is the application
# identity the vault scopes secrets to, so reusing a path means "the same
# application, run again".
function Invoke-VaultProgram {
    param([string]$Dir, [string]$Source, [string]$FileName = 'app.ot', [string]$Mode = 'run')
    $otFile = Join-Path $Dir $FileName
    [System.IO.File]::WriteAllText($otFile, $Source, [System.Text.UTF8Encoding]::new($false))
    $extra = if ($Mode -eq 'web') { '-NoOpen' } else { '' }
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script:OtterPs1 $Mode $otFile $extra 2>&1
    $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
    return [pscustomobject]@{ Stdout = $text; Lines = @(($text -split "`r?`n") | Where-Object { $_ -ne '' }) }
}

# --- 1. Store / read / exists / delete, across separate process runs -------

Test-Otter 'a stored secret persists across separate runs of the same program, and delete removes it' {
    $dir = New-VaultSandbox
    $name = "otter-test-$([Guid]::NewGuid().ToString('N'))"
    try {
        $first = Invoke-VaultProgram -Dir $dir -Source @"
if secret "$name" exists
    say "already there"
otherwise
    say "not stored yet"
.
token is "abc123"
store secret "$name" with value token
say "stored"
"@
        Assert-Lines -Expected @('not stored yet', 'stored') -Actual $first.Lines

        # A brand-new process, the same program path: the value must have survived.
        $second = Invoke-VaultProgram -Dir $dir -Source @"
if secret "$name" exists
    token is secret "$name"
    say token
.
"@
        Assert-Lines -Expected @('abc123') -Actual $second.Lines

        $third = Invoke-VaultProgram -Dir $dir -Source @"
delete secret "$name"
if secret "$name" exists
    say "still there"
otherwise
    say "gone"
.
"@
        Assert-Lines -Expected @('gone') -Actual $third.Lines
    } finally {
        Invoke-VaultProgram -Dir $dir -Source "if secret `"$name`" exists`n    delete secret `"$name`"`n." | Out-Null
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 2. Application namespace ---------------------------------------------------

Test-Otter 'two different Otter programs storing the same secret name do not see each other' {
    $dir = New-VaultSandbox
    $name = "otter-test-$([Guid]::NewGuid().ToString('N'))"
    try {
        $a = Invoke-VaultProgram -Dir $dir -FileName 'alpha.ot' -Source "store secret `"$name`" with value `"alpha-value`"`nsay `"stored`""
        Assert-Lines -Expected @('stored') -Actual $a.Lines
        # A different program (different path) asks for the same name.
        $b = Invoke-VaultProgram -Dir $dir -FileName 'beta.ot' -Source "if secret `"$name`" exists`n    say `"LEAKED`"`notherwise`n    say `"isolated`"`n."
        Assert-Lines -Expected @('isolated') -Actual $b.Lines
        # And it can keep its own value under the same name.
        $b2 = Invoke-VaultProgram -Dir $dir -FileName 'beta.ot' -Source "store secret `"$name`" with value `"beta-value`"`nsay secret `"$name`""
        Assert-Lines -Expected @('beta-value') -Actual $b2.Lines
        $a2 = Invoke-VaultProgram -Dir $dir -FileName 'alpha.ot' -Source "say secret `"$name`""
        Assert-Lines -Expected @('alpha-value') -Actual $a2.Lines
    } finally {
        foreach ($f in 'alpha.ot', 'beta.ot') {
            Invoke-VaultProgram -Dir $dir -FileName $f -Source "if secret `"$name`" exists`n    delete secret `"$name`"`n." | Out-Null
        }
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 3. Replace, text vs bytes ---------------------------------------------------------

Test-Otter 'storing the same name again replaces the secret' {
    $dir = New-VaultSandbox
    $name = "otter-test-$([Guid]::NewGuid().ToString('N'))"
    try {
        $r = Invoke-VaultProgram -Dir $dir -Source @"
store secret "$name" with value "old"
store secret "$name" with value "new"
say secret "$name"
delete secret "$name"
"@
        Assert-Lines -Expected @('new') -Actual $r.Lines
    } finally {
        Invoke-VaultProgram -Dir $dir -Source "if secret `"$name`" exists`n    delete secret `"$name`"`n." | Out-Null
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Otter 'bytes secrets come back as bytes and text secrets as text - never silently converted' {
    $dir = New-VaultSandbox
    $nameB = "otter-test-$([Guid]::NewGuid().ToString('N'))"
    $nameT = "otter-test-$([Guid]::NewGuid().ToString('N'))"
    try {
        $r = Invoke-VaultProgram -Dir $dir -Source @"
key is bytes from hex "00FF10AB"
store secret "$nameB" with value key
store secret "$nameT" with value "plain"
fromVaultB is secret "$nameB"
fromVaultT is secret "$nameT"
say hex from bytes fromVaultB
say count of fromVaultB
say fromVaultT
say length of fromVaultT
delete secret "$nameB"
delete secret "$nameT"
"@
        Assert-Lines -Expected @('00FF10AB', '4', 'plain', '5') -Actual $r.Lines
    } finally {
        foreach ($n in $nameB, $nameT) {
            Invoke-VaultProgram -Dir $dir -Source "if secret `"$n`" exists`n    delete secret `"$n`"`n." | Out-Null
        }
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 4. Failure behaviour ------------------------------------------------------------------

Test-Otter 'reading a missing secret is a clear Otter error - never an empty string' {
    $dir = New-VaultSandbox
    try {
        $name = "otter-test-$([Guid]::NewGuid().ToString('N'))"
        $r = Invoke-VaultProgram -Dir $dir -Source "value is secret `"$name`"`nsay `"should not get here`""
        Assert-True ($r.Stdout -match "There is no secret called ""$name""") 'expected the missing-secret diagnostic'
        Assert-False ($r.Stdout -match 'should not get here') 'execution must stop'
        Assert-False ($r.Stdout -match 'CategoryInfo|at <ScriptBlock>') 'no raw PowerShell error should leak'
    } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
}

Test-Otter 'deleting a missing secret is a clear Otter error' {
    $dir = New-VaultSandbox
    try {
        $name = "otter-test-$([Guid]::NewGuid().ToString('N'))"
        $r = Invoke-VaultProgram -Dir $dir -Source "delete secret `"$name`""
        Assert-True ($r.Stdout -match 'There is no secret called .* to delete') 'expected the missing-secret diagnostic'
    } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
}

Test-Otter 'only text or bytes can be stored; empty and oversized secrets are refused' {
    $dir = New-VaultSandbox
    try {
        $name = "otter-test-$([Guid]::NewGuid().ToString('N'))"
        $r1 = Invoke-VaultProgram -Dir $dir -Source "store secret `"$name`" with value 42"
        Assert-True ($r1.Stdout -match 'A secret can hold text or bytes, but this is a number') 'expected the type diagnostic'
        $r2 = Invoke-VaultProgram -Dir $dir -Source "store secret `"$name`" with value `"`""
        Assert-True ($r2.Stdout -match 'A secret cannot be empty') 'expected the empty-secret diagnostic'
        $r3 = Invoke-VaultProgram -Dir $dir -Source "big is secure random bytes 3000`nstore secret `"$name`" with value big"
        Assert-True ($r3.Stdout -match 'holds at most 2560 bytes') 'expected the size diagnostic'
        Assert-False ($r3.Stdout -match 'CategoryInfo|at <ScriptBlock>') 'no raw PowerShell error should leak'
    } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
}

# --- 5. Never stored in a file ---------------------------------------------------------------

Test-Otter 'the secret value is never written into the program directory (no plaintext file)' {
    $dir = New-VaultSandbox
    $name = "otter-test-$([Guid]::NewGuid().ToString('N'))"
    $marker = "SECRET-MARKER-$([Guid]::NewGuid().ToString('N'))"
    try {
        $before = @(Get-ChildItem -LiteralPath $dir -Recurse -Force | ForEach-Object { $_.FullName })
        $r = Invoke-VaultProgram -Dir $dir -Source "store secret `"$name`" with value `"$marker`"`nsay `"stored`""
        Assert-Lines -Expected @('stored') -Actual $r.Lines
        foreach ($file in Get-ChildItem -LiteralPath $dir -Recurse -Force -File) {
            if ($file.Name -eq 'app.ot') { continue }
            $content = [System.IO.File]::ReadAllText($file.FullName)
            Assert-False ($content -like "*$marker*") "$($file.Name) must not contain the secret"
        }
    } finally {
        Invoke-VaultProgram -Dir $dir -Source "if secret `"$name`" exists`n    delete secret `"$name`"`n." | Out-Null
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Otter 'an error message never echoes the secret value' {
    $dir = New-VaultSandbox
    $marker = "SECRET-MARKER-$([Guid]::NewGuid().ToString('N'))"
    try {
        # Value is the wrong type on purpose so a diagnostic fires.
        $r = Invoke-VaultProgram -Dir $dir -Source "big is `"$marker`"`nlist is a list`nstore secret `"n`" with value list"
        Assert-False ($r.Stdout -like "*$marker*") 'diagnostics must not contain the secret value'
    } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
}

# --- 6. Variables as names, and the D33 escape hatch --------------------------------------

Test-Otter 'secret still works as an ordinary variable name where no vault name follows' {
    $dir = New-VaultSandbox
    try {
        $r = Invoke-VaultProgram -Dir $dir -Source "secret is `"plain variable`"`nsay secret"
        Assert-Lines -Expected @('plain variable') -Actual $r.Lines
    } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
}

Test-Otter 'the secret name may come from a variable' {
    $dir = New-VaultSandbox
    $name = "otter-test-$([Guid]::NewGuid().ToString('N'))"
    try {
        $r = Invoke-VaultProgram -Dir $dir -Source @"
keyName is "$name"
store secret keyName with value "via variable"
found is secret keyName
say found
if secret keyName exists
    say "exists"
.
delete secret keyName
"@
        Assert-Lines -Expected @('via variable', 'exists') -Actual $r.Lines
    } finally {
        Invoke-VaultProgram -Dir $dir -Source "if secret `"$name`" exists`n    delete secret `"$name`"`n." | Out-Null
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 7. Web target: unsupported, clearly ----------------------------------------------------------

foreach ($case in @(
    @{ Name = 'store secret'; Source = 'store secret "k" with value "v"' },
    @{ Name = 'secret read'; Source = 'v is secret "k"' },
    @{ Name = 'secret exists'; Source = "if secret `"k`" exists`n    say `"yes`"`n." },
    @{ Name = 'delete secret'; Source = 'delete secret "k"' }
)) {
    Test-Otter "$($case.Name) is rejected on the web target - browser storage is not a secure vault" {
        $dir = New-VaultSandbox
        try {
            $r = Invoke-VaultProgram -Dir $dir -Source $case.Source -Mode 'web'
            Assert-True ($r.Stdout -match 'not supported on the web target') "expected rejection but got: $($r.Stdout)"
            Assert-True ($r.Stdout -match 'not a secure credential store') 'expected the browser-storage explanation'
        } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Complete-OtterTests
