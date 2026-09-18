# tests/FilesystemAdversarial.Tests.ps1
#
# Adversarial Red-Team suite for Otter 1.0 filesystem operations.
# Tests edge cases and stress conditions in an isolated temp sandbox:
# - Empty files
# - Zero-byte files
# - Large text files (1MB+)
# - Unicode filenames (accented, Cyrillic, CJK)
# - Emoji filenames
# - Spaces in paths and filenames
# - Deeply nested directory structures
# - Read-only files
# - Missing files and missing parent directories
# - Destination collisions
# - Source == destination
# - File locking / permission denial
#
# GUARANTEE: Operates strictly inside isolated temp sandbox. No data outside sandbox is touched.

using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Library.psm1
using module ..\src\Otter.Interpreter.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1

. "$PSScriptRoot\TestHelpers.ps1"

$sandbox = Join-Path $env:TEMP ("otter-fs-adversarial-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Path $sandbox -Force)
$originalLocation = (Get-Location).Path
Set-Location $sandbox

function Invoke-OtterTestSnippet {
    param([string]$Source)
    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($Text) $collected.Add($Text) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        $tokens = ConvertTo-OtterTokens -Source $Source
        $ast = ConvertTo-OtterAst -Tokens $tokens
        $env = New-OtterEnvironment
        Invoke-OtterProgram -Program $ast -Environment $env -SourceLines ($Source -split "`r?`n")
    }
    finally {
        Set-OtterOutputWriter -Writer $null
    }
    return , $collected.ToArray()
}

Write-Host ''
Write-Host 'Otter 1.0 Filesystem Adversarial Red-Team Suite' -ForegroundColor Cyan

try {
    # 1. Empty files & Zero-byte files
    Test-Otter 'FS-01: empty string write and read' {
        Invoke-OtterTestSnippet @"
write "" to "empty.txt"
read "empty.txt" into content
say content
"@
        Assert-True (Test-Path -LiteralPath 'empty.txt') 'File must exist'
        $len = (Get-Item -LiteralPath 'empty.txt').Length
        Assert-AreEqual -Expected 0 -Actual $len 'File length must be 0 bytes'
    }

    Test-Otter 'FS-02: zero-byte file created externally read by Otter' {
        [System.IO.File]::WriteAllBytes((Join-Path (Get-Location).Path 'zero.txt'), [byte[]]@())
        $out = Invoke-OtterTestSnippet @"
read "zero.txt" into content
if content is ""
    say "empty-ok"
.
"@
        Assert-Lines -Expected @('empty-ok') -Actual $out
    }

    # 2. Large text files
    Test-Otter 'FS-03: large text file write and read (440KB)' {
        $largeString = ("OtterRocks!" * 40000) # ~440 KB
        $largeFilePath = Join-Path (Get-Location).Path 'large_input.txt'
        [System.IO.File]::WriteAllText($largeFilePath, $largeString, [System.Text.Encoding]::UTF8)
        $out = Invoke-OtterTestSnippet @"
read "large_input.txt" into loaded
write loaded to "large_output.txt"
read "large_output.txt" into loaded2
if length of loaded2 is 440000
    say "size-match"
.
"@
        Assert-Lines -Expected @('size-match') -Actual $out
    }

    # 3. Unicode filenames
    Test-Otter 'FS-04: Unicode filenames with accents, Cyrillic, and CJK' {
        $out = Invoke-OtterTestSnippet @"
write "unicode-payload" to "données_тест_日本語.txt"
read "données_тест_日本語.txt" into data
say data
copy "données_тест_日本語.txt" to "données_copy.txt"
read "données_copy.txt" into data2
say data2
"@
        Assert-Lines -Expected @('unicode-payload', 'unicode-payload') -Actual $out
    }

    # 4. Emoji filenames
    Test-Otter 'FS-05: Emoji filenames in write and read' {
        $out = Invoke-OtterTestSnippet @"
write "emoji-content" to "🦦_otter_🚀.txt"
read "🦦_otter_🚀.txt" into loaded
say loaded
"@
        Assert-Lines -Expected @('emoji-content') -Actual $out
    }

    # 5. Spaces in filenames and paths
    Test-Otter 'FS-06: Spaces in filenames and directory paths' {
        $out = Invoke-OtterTestSnippet @"
create folder "Folder With Spaces"
write "spaced-content" to "Folder With Spaces/My File With Spaces.txt"
read "Folder With Spaces/My File With Spaces.txt" into loaded
say loaded
"@
        Assert-Lines -Expected @('spaced-content') -Actual $out
    }

    # 6. Deeply nested directories and paths
    Test-Otter 'FS-07: Deeply nested directory structure' {
        $out = Invoke-OtterTestSnippet @"
create folder "level1"
create folder "level1/level2"
create folder "level1/level2/level3"
write "deep" to "level1/level2/level3/deep.txt"
read "level1/level2/level3/deep.txt" into text
say text
"@
        Assert-Lines -Expected @('deep') -Actual $out
    }

    # 7. Missing files handled with try/otherwise or clean error
    Test-Otter 'FS-08: Missing file error reporting without host crash' {
        $caught = $false
        try {
            Invoke-OtterTestSnippet @"
read "non_existent_file_xyz.txt" into res
"@
        }
        catch {
            $caught = $true
            Assert-True ($_.Exception.Message.Length -gt 0) 'Must raise informative error'
        }
        Assert-True $caught 'Reading missing file must raise an error'
    }

    Test-Otter 'FS-09: Missing file caught safely by try/otherwise' {
        $out = Invoke-OtterTestSnippet @"
try
    read "non_existent_file_xyz.txt" into res
    say "should not reach"
otherwise
    say "caught-missing"
.
"@
        Assert-Lines -Expected @('caught-missing') -Actual $out
    }

    # 8. Missing parent directory on read
    Test-Otter 'FS-10: Missing parent directory handled safely' {
        $out = Invoke-OtterTestSnippet @"
try
    read "ghost_dir/ghost_file.txt" into res
otherwise
    say "caught-missing-dir"
.
"@
        Assert-Lines -Expected @('caught-missing-dir') -Actual $out
    }

    # 9. Destination collisions
    Test-Otter 'FS-11: Destination collision on copy overwrites cleanly' {
        $out = Invoke-OtterTestSnippet @"
write "initial" to "orig.txt"
write "target-data" to "dest.txt"
copy "orig.txt" to "dest.txt"
read "dest.txt" into res
say res
"@
        Assert-Lines -Expected @('initial') -Actual $out
    }

    # 10. Source == Destination
    Test-Otter 'FS-12: Source equals Destination does not corrupt file' {
        $out = Invoke-OtterTestSnippet @"
write "precious-data" to "same.txt"
try
    copy "same.txt" to "same.txt"
otherwise
    failed is 1
.
read "same.txt" into verified
say verified
"@
        Assert-Lines -Expected @('precious-data') -Actual $out
    }

    # 11. Read-only file protection
    Test-Otter 'FS-13: Writing to read-only file fails cleanly' {
        $roFile = Join-Path (Get-Location).Path 'readonly.txt'
        [System.IO.File]::WriteAllText($roFile, 'protected')
        (Get-Item -LiteralPath $roFile).IsReadOnly = $true

        $out = Invoke-OtterTestSnippet @"
try
    write "overwritten" to "readonly.txt"
    say "unexpected-write-success"
otherwise
    say "caught-readonly-violation"
.
"@
        (Get-Item -LiteralPath $roFile).IsReadOnly = $false
        Assert-Lines -Expected @('caught-readonly-violation') -Actual $out
    }

    # 12. File locked by another process handled cleanly
    Test-Otter 'FS-14: File locked exclusively by another handle handled cleanly' {
        $lockFile = Join-Path (Get-Location).Path 'locked.txt'
        [System.IO.File]::WriteAllText($lockFile, 'locked-content')
        $stream = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

        try {
            $out = Invoke-OtterTestSnippet @"
try
    write "attack" to "locked.txt"
    say "fail"
otherwise
    say "caught-lock"
.
"@
            Assert-Lines -Expected @('caught-lock') -Actual $out
        }
        finally {
            $stream.Close()
            $stream.Dispose()
        }
    }

    # 13. Recursive discovery in deep directory
    Test-Otter 'FS-15: Traversal across multi-level directory with subfolders' {
        $out = Invoke-OtterTestSnippet @"
create folder "scan_root"
create folder "scan_root/sub1"
create folder "scan_root/sub2"
write "a" to "scan_root/file_a.txt"
write "b" to "scan_root/sub1/file_b.txt"
write "c" to "scan_root/sub2/file_c.txt"
get files in "scan_root" and subfolders into foundFiles
say length of foundFiles
"@
        Assert-Lines -Expected @('3') -Actual $out
    }
}
finally {
    Set-Location $originalLocation
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests
