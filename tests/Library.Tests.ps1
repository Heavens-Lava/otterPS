using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Library.psm1
using module ..\src\Otter.Interpreter.psm1

# Library.Tests.ps1
#
# Milestone 7: the parts of Otter that touch the file system and other
# processes. These tests do real file I/O, inside a throwaway folder that is
# created fresh and removed afterwards.

. "$PSScriptRoot\TestHelpers.ps1"

$sandbox = Join-Path $env:TEMP ("otter-library-tests-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Path $sandbox -Force)
$originalLocation = (Get-Location).Path
Set-Location $sandbox

function Lit { param($Value, [int]$Line = 1) [LiteralExpr]::new($Value, $Line) }
function Var { param([string]$Name, [int]$Line = 1) [VariableExpr]::new($Name, $Line) }

function Invoke-TestProgram {
    param([Node[]]$Statements)

    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($Text) $collected.Add($Text) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        Invoke-OtterProgram -Program ([ProgramNode]::new($Statements)) -Environment (New-OtterEnvironment)
    }
    finally {
        Set-OtterOutputWriter -Writer $null
    }
    return , $collected.ToArray()
}

Write-Host ''
Write-Host 'Runtime library (milestone 7)' -ForegroundColor Cyan


# =================================================================
# files
# =================================================================

Test-Otter 'write then read gives back the same text' {
    $out = Invoke-TestProgram @(
        [WriteFileStmt]::new((Lit 'Hello!'), (Lit 'hello.txt'), 1),
        [ReadFileStmt]::new((Lit 'hello.txt'), 'notes', 2),
        [SayStmt]::new(@((Var 'notes')), 3)
    )
    Assert-Lines -Expected @('Hello!') -Actual $out
}

Test-Otter 'append adds to the end without disturbing what is already there (D61)' {
    $out = Invoke-TestProgram @(
        [WriteFileStmt]::new((Lit 'one'), (Lit 'log.txt'), 1),
        [AppendFileStmt]::new((Lit ' two'), (Lit 'log.txt'), 2),
        [AppendFileStmt]::new((Lit ' three'), (Lit 'log.txt'), 3),
        [ReadFileStmt]::new((Lit 'log.txt'), 'notes', 4),
        [SayStmt]::new(@((Var 'notes')), 5)
    )
    Assert-Lines -Expected @('one two three') -Actual $out
}

Test-Otter 'append creates the file when it does not exist yet, same as write (D61)' {
    $out = Invoke-TestProgram @(
        [AppendFileStmt]::new((Lit 'first line'), (Lit 'fresh.txt'), 1),
        [ReadFileStmt]::new((Lit 'fresh.txt'), 'notes', 2),
        [SayStmt]::new(@((Var 'notes')), 3)
    )
    Assert-Lines -Expected @('first line') -Actual $out
}

Test-Otter 'write then read round-trips non-ASCII text correctly (v1 audit finding)' {
    # Found during the v1 runtime audit: Read-OtterFile used Get-Content
    # -Raw with no explicit encoding. Write-OtterFile deliberately writes
    # BOM-less UTF-8 (see its own comment on WriteAllText), and Get-Content
    # falls back to the system codepage when there is no BOM to guess
    # from - so on this system, "José Müller 你好" written and read back
    # came back as mojibake ("JosÃ© MÃ¼ller ä½ å¥½"), silently - no error,
    # just corrupted text. Fixed with an explicit UTF8Encoding on the read
    # side, matching the write side exactly.
    $text = "José Müller 你好"
    $out = Invoke-TestProgram @(
        [WriteFileStmt]::new((Lit $text), (Lit 'unicode.txt'), 1),
        [ReadFileStmt]::new((Lit 'unicode.txt'), 'notes', 2),
        [SayStmt]::new(@((Var 'notes')), 3)
    )
    Assert-Lines -Expected @($text) -Actual $out
}

Test-Otter 'file exists is false before and true after writing' {
    $out = Invoke-TestProgram @(
        [SayStmt]::new(@([FileExistsExpr]::new((Lit 'later.txt'), 1)), 1),
        [WriteFileStmt]::new((Lit 'x'), (Lit 'later.txt'), 2),
        [SayStmt]::new(@([FileExistsExpr]::new((Lit 'later.txt'), 3)), 3)
    )
    Assert-Lines -Expected @('false', 'true') -Actual $out
}

Test-Otter 'copy creates the folder it needs' {
    # copy "hello.txt" to "backup/hello.txt" - backup/ does not exist yet
    [void](Invoke-TestProgram @(
        [WriteFileStmt]::new((Lit 'copy me'), (Lit 'source.txt'), 1),
        [CopyFileStmt]::new((Lit 'source.txt'), (Lit 'backup/source.txt'), 2)
    ))
    Assert-True (Test-Path (Join-Path $sandbox 'backup\source.txt')) 'expected the copy to exist'
    Assert-True (Test-Path (Join-Path $sandbox 'source.txt')) 'expected the original to survive'
}

Test-Otter 'move leaves nothing behind' {
    [void](Invoke-TestProgram @(
        [WriteFileStmt]::new((Lit 'move me'), (Lit 'moving.txt'), 1),
        [MoveFileStmt]::new((Lit 'moving.txt'), (Lit 'moved.txt'), 2)
    ))
    Assert-True (Test-Path (Join-Path $sandbox 'moved.txt')) 'expected the file at its new name'
    Assert-False (Test-Path (Join-Path $sandbox 'moving.txt')) 'expected the old name to be gone'
}

Test-Otter 'copying into an existing folder keeps the file name' {
    [void](New-Item -ItemType Directory -Path (Join-Path $sandbox 'Documents') -Force)
    [void](Invoke-TestProgram @(
        [WriteFileStmt]::new((Lit 'filed'), (Lit 'note.txt'), 1),
        [CopyFileStmt]::new((Lit 'note.txt'), (Lit 'Documents'), 2)
    ))
    Assert-True (Test-Path (Join-Path $sandbox 'Documents\note.txt')) 'expected note.txt inside Documents'
}

Test-Otter 'delete removes the file' {
    [void](Invoke-TestProgram @(
        [WriteFileStmt]::new((Lit 'bye'), (Lit 'doomed.txt'), 1),
        [DeleteFileStmt]::new((Lit 'doomed.txt'), 2)
    ))
    Assert-False (Test-Path (Join-Path $sandbox 'doomed.txt')) 'expected the file to be gone'
}

Test-Otter 'reading a missing file says which file' {
    Assert-OtterFails -Containing 'nowhere.txt' -Body {
        Invoke-TestProgram @( [ReadFileStmt]::new((Lit 'nowhere.txt'), 'x', 1) )
    }
}

Test-Otter 'Otter refuses to delete a folder' {
    # "delete file" that quietly erased a directory tree would be a trap.
    [void](New-Item -ItemType Directory -Path (Join-Path $sandbox 'keepme') -Force)
    Assert-OtterFails -Containing 'only deletes files' -Body {
        Invoke-TestProgram @( [DeleteFileStmt]::new((Lit 'keepme'), 1) )
    }
    Assert-True (Test-Path (Join-Path $sandbox 'keepme')) 'the folder must still be there'
}

Test-Otter 'a file name can be built from a variable' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('fileName', (Lit 'built.txt'), 1),
        [WriteFileStmt]::new((Lit 'from a variable'), (Var 'fileName'), 2),
        [ReadFileStmt]::new((Var 'fileName'), 'back', 3),
        [SayStmt]::new(@((Var 'back')), 4)
    )
    Assert-Lines -Expected @('from a variable') -Actual $out
}


# =================================================================
# commands - and the safety rule behind them
# =================================================================

Test-Otter 'a command line splits into a program and its arguments' {
    $parts = Split-OtterCommandLine -CommandLine 'git status' -Line 1
    Assert-AreEqual -Expected 'git|status' -Actual ($parts -join '|')
}

Test-Otter 'quoted arguments stay in one piece' {
    $parts = Split-OtterCommandLine -CommandLine 'git commit -m "hello world"' -Line 1
    Assert-AreEqual -Expected 'git|commit|-m|hello world' -Actual ($parts -join '|')
}

Test-Otter 'shell operators are NOT interpreted - they become plain arguments' {
    # This is the safety guarantee from the brief, section 31. If Otter went
    # through cmd.exe, "&&" would chain two commands, and any text an Otter
    # program built up could turn into executable instructions.
    $parts = Split-OtterCommandLine -CommandLine 'whoami && del everything' -Line 1
    Assert-AreEqual -Expected 'whoami|&&|del|everything' -Actual ($parts -join '|')
}

Test-Otter 'an unclosed quote in a command is an Otter error' {
    Assert-OtterFails -Containing 'quote that never closes' -Body {
        Split-OtterCommandLine -CommandLine 'git commit -m "oops' -Line 1
    }
}

Test-Otter 'run command captures a real program output' {
    $out = Invoke-TestProgram @(
        [RunStmt]::new((Lit 'whoami'), $true, 'who', 1),
        [SayStmt]::new(@([PropertyAccessExpr]::new('output', (Var 'who'), 2)), 2)
    )
    Assert-True ($out.Count -eq 1) 'expected exactly one line of output'
    Assert-True ($out[0].Length -gt 0) 'expected whoami to print something'
}

Test-Otter 'run command captures structured stdout stderr and exit code' {
    $out = Invoke-TestProgram @(
        [RunStmt]::new((Lit 'cmd /c "echo standard output & echo standard error 1>&2 & exit 7"'), $true, 'result', 1),
        [SayStmt]::new(@([PropertyAccessExpr]::new('output', (Var 'result'), 2)), 2),
        [SayStmt]::new(@([PropertyAccessExpr]::new('error output', (Var 'result'), 3)), 3),
        [SayStmt]::new(@([PropertyAccessExpr]::new('exit code', (Var 'result'), 4)), 4)
    )
    Assert-Lines -Expected @('standard output', 'standard error', '7') -Actual $out
}

Test-Otter 'running a program that does not exist names it' {
    Assert-OtterFails -Containing 'definitelyNotAProgram' -Body {
        Invoke-TestProgram @( [RunStmt]::new((Lit 'definitelyNotAProgram'), $true, $null, 1) )
    }
}


# =================================================================

# =================================================================
# file objects  -  rules.md: "File properties also use of"
# =================================================================

Test-Otter 'a file object carries name, extension, size and path' {
    [void](Invoke-TestProgram @( [WriteFileStmt]::new((Lit 'twelve chars'), (Lit 'photo.jpg'), 1) ))
    $file = New-OtterFileObject -Path 'photo.jpg'

    Assert-AreEqual -Expected 'file' -Actual $file.TypeName
    Assert-AreEqual -Expected 'photo.jpg' -Actual $file.ReadProperty('name')
    Assert-AreEqual -Expected '.jpg' -Actual $file.ReadProperty('extension')
    Assert-AreEqual -Expected '12' -Actual (Format-OtterValue -Value $file.ReadProperty('size'))
}

Test-Otter 'extension of file reads through ordinary property access' {
    # if extension of file is ".jpg"   - the rules.md example
    [void](Invoke-TestProgram @( [WriteFileStmt]::new((Lit 'x'), (Lit 'holiday.jpg'), 1) ))
    $file = New-OtterFileObject -Path 'holiday.jpg'

    $out = Invoke-TestProgram @(
        [AssignStmt]::new('file', (Lit $file), 1),
        [SayStmt]::new(@([PropertyAccessExpr]::new('extension', (Var 'file'), 2)), 2)
    )
    Assert-Lines -Expected @('.jpg') -Actual $out
}

Test-Otter 'file operations accept a file object as well as a path' {
    [void](Invoke-TestProgram @( [WriteFileStmt]::new((Lit 'by object'), (Lit 'byobject.txt'), 1) ))
    $file = New-OtterFileObject -Path 'byobject.txt'

    # read file into contents   - where "file" is an object, not text
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('file', (Lit $file), 1),
        [ReadFileStmt]::new((Var 'file'), 'contents', 2),
        [SayStmt]::new(@((Var 'contents')), 3)
    )
    Assert-Lines -Expected @('by object') -Actual $out
}

Test-Otter 'move file to a folder works with a file object' {
    [void](New-Item -ItemType Directory -Path (Join-Path $sandbox 'Pictures') -Force)
    [void](Invoke-TestProgram @( [WriteFileStmt]::new((Lit 'img'), (Lit 'snap.jpg'), 1) ))
    $file = New-OtterFileObject -Path 'snap.jpg'

    [void](Invoke-TestProgram @(
        [AssignStmt]::new('file', (Lit $file), 1),
        [MoveFileStmt]::new((Var 'file'), (Lit 'Pictures'), 2)
    ))
    Assert-True (Test-Path (Join-Path $sandbox 'Pictures\snap.jpg')) 'expected the file inside Pictures'
}

Test-Otter 'an object with no path is not a file' {
    Assert-OtterFails -Containing 'has no path' -Body {
        $notAFile = [OtterObject]::new('thing')
        Resolve-OtterFileArgument -Value $notAFile -Line 1
    }
}


Set-Location $originalLocation
Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue

Complete-OtterTests
