using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Library.psm1
using module ..\src\Otter.Interpreter.psm1

# Part3.Tests.ps1
#
# The first three Part 3 decisions:
#
#   D22  gone            - the absence of a value
#   D20  discovery       - get files in "Pictures" into files
#   D21  traversal       - ...and subfolders, never by default
#   D23  try / otherwise - the beginner error model

. "$PSScriptRoot\TestHelpers.ps1"

$sandbox = Join-Path $env:TEMP ("otter-part3-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Path $sandbox -Force)
$originalLocation = (Get-Location).Path
Set-Location $sandbox

function Lit { param($Value, [int]$Line = 1) [LiteralExpr]::new($Value, $Line) }
function Var { param([string]$Name, [int]$Line = 1) [VariableExpr]::new($Name, $Line) }
function PropOf { param([string]$P, [Node]$T, [int]$Line = 1) [PropertyAccessExpr]::new($P, $T, $Line) }
function Gone { param([int]$Line = 1) [LiteralExpr]::new($null, $Line) }
function CompareEx { param([Node]$L, [string]$Op, [Node]$R, [int]$Line = 1) [ComparisonExpr]::new($L, [CompareOp]$Op, $R, $Line) }

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
Write-Host 'Part 3: gone, discovery, errors' -ForegroundColor Cyan


# =================================================================
# D22 - gone
# =================================================================

Test-Otter 'user is gone, then if user is gone' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('user', (Gone), 1),
        [IfStmt]::new(
            @([IfBranch]::new((CompareEx (Var 'user') 'Equal' (Gone)), @([SayStmt]::new(@((Lit 'User was not found.')), 3)))),
            $null, 2)
    )
    Assert-Lines -Expected @('User was not found.') -Actual $out
}

Test-Otter 'if user is not gone' {
    $out = Invoke-TestProgram @(
        [ObjectDefStmt]::new('user', 'thing', @([AssignStmt]::new('name', (Lit 'Jeff'), 2)), 1),
        [IfStmt]::new(
            @([IfBranch]::new((CompareEx (Var 'user') 'NotEqual' (Gone)), @([SayStmt]::new(@((Lit 'Hello'), (PropOf 'name' (Var 'user'))), 5)))),
            $null, 4)
    )
    Assert-Lines -Expected @('Hello Jeff') -Actual $out
}

Test-Otter 'gone prints as gone' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('user', (Gone), 1),
        [SayStmt]::new(@((Var 'user')), 2)
    )
    Assert-Lines -Expected @('gone') -Actual $out
}

Test-Otter 'gone is NOT false, 0, empty text, or an empty list' {
    # Five different states, and Otter must not confuse any two of them.
    Assert-False (Test-OtterEqual -Left $null -Right $false) 'gone is not false'
    Assert-False (Test-OtterEqual -Left $null -Right 0.0) 'gone is not zero'
    Assert-False (Test-OtterEqual -Left $null -Right '') 'gone is not empty text'
    Assert-False (Test-OtterEqual -Left $null -Right (New-OtterList)) 'gone is not an empty list'
    Assert-True (Test-OtterEqual -Left $null -Right $null) 'gone equals gone'
}

Test-Otter 'gone is not true enough for an if' {
    Assert-False (Test-OtterTruthy -Value $null)
}

Test-Otter 'a variable can be cleared by setting it to gone' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('user', (Lit 'Jeff'), 1),
        [AssignStmt]::new('user', (Gone), 2),
        [SayStmt]::new(@((Var 'user')), 3)
    )
    Assert-Lines -Expected @('gone') -Actual $out
}

Test-Otter 'gone is still different from an undefined variable' {
    # D9 stands: never defined is an ERROR, not gone.
    Assert-OtterFails -Containing 'could not find the variable' -Body {
        Invoke-TestProgram @( [SayStmt]::new(@((Var 'neverMentioned')), 1) )
    }
}


# =================================================================
# D20 / D21 - discovery
# =================================================================

# Pictures/one.jpg, Pictures/two.txt, Pictures/Holiday/three.jpg
[void](New-Item -ItemType Directory -Path (Join-Path $sandbox 'Pictures\Holiday') -Force)
Set-Content -LiteralPath (Join-Path $sandbox 'Pictures\one.jpg') -Value 'aaaaa' -NoNewline
Set-Content -LiteralPath (Join-Path $sandbox 'Pictures\two.txt') -Value 'bb' -NoNewline
Set-Content -LiteralPath (Join-Path $sandbox 'Pictures\Holiday\three.jpg') -Value 'ccc' -NoNewline

Test-Otter 'get files in "Pictures" into files does NOT recurse' {
    $out = Invoke-TestProgram @(
        [GetFilesStmt]::new((Lit 'Pictures'), $false, 'files', 1),
        [ForEachStmt]::new('file', (Var 'files'), @(
            [SayStmt]::new(@((PropOf 'name' (Var 'file'))), 3)
        ), 2)
    )
    Assert-Lines -Expected @('one.jpg', 'two.txt') -Actual $out
}

Test-Otter 'and subfolders is the only way down' {
    $out = Invoke-TestProgram @(
        [GetFilesStmt]::new((Lit 'Pictures'), $true, 'files', 1),
        [ForEachStmt]::new('file', (Var 'files'), @(
            [SayStmt]::new(@((PropOf 'name' (Var 'file'))), 3)
        ), 2)
    )
    Assert-Lines -Expected @('one.jpg', 'two.txt', 'three.jpg') -Actual $out
}

Test-Otter 'get folders in "Pictures" into folders' {
    $out = Invoke-TestProgram @(
        [GetFoldersStmt]::new((Lit 'Pictures'), $false, 'folders', 1),
        [ForEachStmt]::new('folder', (Var 'folders'), @(
            [SayStmt]::new(@((PropOf 'name' (Var 'folder'))), 3)
        ), 2)
    )
    Assert-Lines -Expected @('Holiday') -Actual $out
}

Test-Otter 'a folder object has name, path, created and modified but no size' {
    $folder = New-OtterFolderObject -Path 'Pictures'
    Assert-AreEqual -Expected 'folder' -Actual $folder.TypeName
    Assert-AreEqual -Expected 'Pictures' -Actual $folder.ReadProperty('name')
    Assert-True $folder.HasProperty('created') 'expected a created property'
    Assert-True $folder.HasProperty('modified') 'expected a modified property'
    # Measuring a folder means walking everything in it - far too expensive
    # to do just because someone asked for the folder.
    Assert-False $folder.HasProperty('size') 'a folder must NOT carry a size'
}

Test-Otter 'getting files from a folder that is not there says so' {
    Assert-OtterFails -Containing 'could not find a folder' -Body {
        Invoke-TestProgram @( [GetFilesStmt]::new((Lit 'NoSuchFolder'), $false, 'files', 1) )
    }
}


# =================================================================
# folder operations
# =================================================================

Test-Otter 'create folder then delete folder' {
    [void](Invoke-TestProgram @( [CreateFolderStmt]::new((Lit 'Backup'), 1) ))
    Assert-True (Test-Path (Join-Path $sandbox 'Backup')) 'expected the folder'

    [void](Invoke-TestProgram @( [DeleteFolderStmt]::new((Lit 'Backup'), 1) ))
    Assert-False (Test-Path (Join-Path $sandbox 'Backup')) 'expected it gone'
}

Test-Otter 'Otter refuses to delete a folder that still has things in it' {
    # Jeff's Part 3 note: Otter must not silently do dangerous things.
    Assert-OtterFails -Containing 'only deletes empty folders' -Body {
        Invoke-TestProgram @( [DeleteFolderStmt]::new((Lit 'Pictures'), 1) )
    }
    Assert-True (Test-Path (Join-Path $sandbox 'Pictures\one.jpg')) 'nothing may have been removed'
}

Test-Otter 'copy folder keeps the original' {
    [void](Invoke-TestProgram @( [CopyFolderStmt]::new((Lit 'Pictures'), (Lit 'PicturesCopy'), 1) ))
    Assert-True (Test-Path (Join-Path $sandbox 'PicturesCopy\one.jpg')) 'expected the copy'
    Assert-True (Test-Path (Join-Path $sandbox 'Pictures\one.jpg')) 'expected the original'
}


# =================================================================
# D23 - try / otherwise
# =================================================================

Test-Otter 'try runs its body when nothing goes wrong' {
    $out = Invoke-TestProgram @(
        [WriteFileStmt]::new((Lit 'dark'), (Lit 'settings.json'), 1),
        [TryStmt]::new(
            @([ReadFileStmt]::new((Lit 'settings.json'), 'settings', 3),
              [SayStmt]::new(@((Var 'settings')), 4)),
            @([SayStmt]::new(@((Lit 'Could not load settings.')), 6)), 2)
    )
    Assert-Lines -Expected @('dark') -Actual $out
}

Test-Otter 'otherwise runs when the body fails' {
    $out = Invoke-TestProgram @(
        [TryStmt]::new(
            @([ReadFileStmt]::new((Lit 'missing.json'), 'settings', 2)),
            @([SayStmt]::new(@((Lit 'Could not load settings.')), 4)), 1)
    )
    Assert-Lines -Expected @('Could not load settings.') -Actual $out
}

Test-Otter 'a failure inside try does not stop the rest of the program' {
    $out = Invoke-TestProgram @(
        [TryStmt]::new(
            @([ReadFileStmt]::new((Lit 'missing.json'), 'x', 2)),
            @([SayStmt]::new(@((Lit 'recovered')), 4)), 1),
        [SayStmt]::new(@((Lit 'carrying on')), 5)
    )
    Assert-Lines -Expected @('recovered', 'carrying on') -Actual $out
}

Test-Otter 'return escapes straight through a try' {
    # If try caught the return signal, this would print the otherwise body
    # and lose the value. Control flow is not failure.
    $out = Invoke-TestProgram @(
        [FunctionDefStmt]::new('answer', @(), @(
            [TryStmt]::new(
                @([ReturnStmt]::new((Lit 42.0), 3)),
                @([SayStmt]::new(@((Lit 'should never print')), 5)), 2)
        ), 1),
        [CallStmt]::new([CallExpr]::new('answer', @(), 7), 'result', 7),
        [SayStmt]::new(@((Var 'result')), 8)
    )
    Assert-Lines -Expected @('42') -Actual $out
}


# =================================================================
# the milestone program
# =================================================================

Test-Otter 'the Part 3 milestone: discovery, properties and gone together' {
    #   get files in "Pictures" and subfolders into files
    #
    #   for each file in files
    #       if extension of file is ".jpg"
    #           say name of file "is" size of file "bytes"
    #       .
    #   .
    $out = Invoke-TestProgram @(
        [GetFilesStmt]::new((Lit 'Pictures'), $true, 'files', 1),
        [ForEachStmt]::new('file', (Var 'files'), @(
            [IfStmt]::new(
                @([IfBranch]::new(
                    (CompareEx (PropOf 'extension' (Var 'file')) 'Equal' (Lit '.jpg')),
                    @([SayStmt]::new(@(
                        (PropOf 'name' (Var 'file')), (Lit 'is'),
                        (PropOf 'size' (Var 'file')), (Lit 'bytes')), 5)))),
                $null, 4)
        ), 3),

        #   user is gone
        #   if user is gone
        #       say "User not found."
        #   otherwise
        #       say "Hello" name of user
        [AssignStmt]::new('user', (Gone), 9),
        [IfStmt]::new(
            @([IfBranch]::new((CompareEx (Var 'user') 'Equal' (Gone)),
                @([SayStmt]::new(@((Lit 'User not found.')), 11)))),
            @([SayStmt]::new(@((Lit 'Hello'), (PropOf 'name' (Var 'user'))), 13)), 10)
    )

    Assert-Lines -Expected @(
        'one.jpg is 5 bytes',
        'three.jpg is 3 bytes',
        'User not found.'
    ) -Actual $out
}


Set-Location $originalLocation
Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue

Complete-OtterTests
