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

Test-Otter 'D68: fail with raises a real catchable custom error' {
    $out = Invoke-TestProgram @(
        [TryStmt]::new(
            @([FailStmt]::new((Lit 'custom failure text'), 2)),
            @([SayStmt]::new(@((Lit 'caught it')), 4)), 1)
    )
    Assert-Lines -Expected @('caught it') -Actual $out
}

Test-Otter 'D68: otherwise into reason binds the failure message' {
    $out = Invoke-TestProgram @(
        [TryStmt]::new(
            @([FailStmt]::new((Lit 'custom failure text'), 2)),
            @([SayStmt]::new(@((Lit 'caught:'), (Var 'reason')), 4)), 'reason', 1)
    )
    Assert-Lines -Expected @('caught: custom failure text') -Actual $out
}

Test-Otter 'D68: otherwise into reason also binds a built-in errors message' {
    $out = Invoke-TestProgram @(
        [TryStmt]::new(
            @([ReadFileStmt]::new((Lit 'missing.json'), 'x', 2)),
            @([SayStmt]::new(@((Var 'reason')), 4)), 'reason', 1)
    )
    Assert-Lines -Expected @('I could not find a file called "missing.json".') -Actual $out
}

Test-Otter 'D68: plain otherwise with no into still works unchanged' {
    $out = Invoke-TestProgram @(
        [TryStmt]::new(
            @([FailStmt]::new((Lit 'ignored'), 2)),
            @([SayStmt]::new(@((Lit 'fallback')), 4)), 1)
    )
    Assert-Lines -Expected @('fallback') -Actual $out
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


# =================================================================
# D67/D69 - system integration: clipboard, environment, system
# folders/information. Notify and the file/folder dialogs are
# deliberately NOT covered here - they show a real OS toast or block
# on a real WinForms dialog, neither of which is safe to run
# unattended in a test suite; they were verified manually through the
# real CLI instead (see SPEC-DECISIONS.md D67).
# =================================================================

Test-Otter 'D67: copy to clipboard then get clipboard round-trips real OS clipboard text' {
    $out = Invoke-TestProgram @(
        [CopyToClipboardStmt]::new((Lit 'otter regression test clipboard text'), 1),
        [GetClipboardStmt]::new('pasted', 2),
        [SayStmt]::new(@((Var 'pasted')), 3)
    )
    Assert-Lines -Expected @('otter regression test clipboard text') -Actual $out
}

Test-Otter 'D67: get environment variable reads a real, currently-set variable' {
    $env:OTTER_TEST_VAR_D67 = 'present-value'
    try {
        $out = Invoke-TestProgram @(
            [GetEnvironmentVariableStmt]::new((Lit 'OTTER_TEST_VAR_D67'), 'value', 1),
            [SayStmt]::new(@((Var 'value')), 2)
        )
        Assert-Lines -Expected @('present-value') -Actual $out
    } finally {
        Remove-Item Env:\OTTER_TEST_VAR_D67 -ErrorAction SilentlyContinue
    }
}

Test-Otter 'D67: get environment variable is gone for a variable that is not set' {
    $out = Invoke-TestProgram @(
        [GetEnvironmentVariableStmt]::new((Lit 'OTTER_TEST_VAR_DEFINITELY_UNSET_D67'), 'value', 1),
        [IfStmt]::new(
            @([IfBranch]::new((CompareEx (Var 'value') 'Equal' (Gone)),
                @([SayStmt]::new(@((Lit 'gone as expected')), 3)))),
            @([SayStmt]::new(@((Lit 'unexpectedly present')), 5)), 2)
    )
    Assert-Lines -Expected @('gone as expected') -Actual $out
}

Test-Otter 'D67: get system folder "temp" returns a real, existing folder' {
    $out = Invoke-TestProgram @(
        [GetSystemFolderStmt]::new((Lit 'temp'), 'path', 1),
        [SayStmt]::new(@((Var 'path')), 2)
    )
    Assert-AreEqual -Expected 1 -Actual $out.Count
    Assert-True (Test-Path -LiteralPath $out[0] -PathType Container) 'expected the reported temp folder to actually exist'
}

Test-Otter 'D67: get system folder with an unknown name is a clean Otter error' {
    Assert-OtterFails -Containing 'I do not know a system folder called "bogus"' -Body {
        Invoke-TestProgram @( [GetSystemFolderStmt]::new((Lit 'bogus'), 'path', 1) )
    }
}

Test-Otter 'D69: get system information "os" returns real, non-empty OS fields' {
    $out = Invoke-TestProgram @(
        [GetSystemInfoStmt]::new((Lit 'os'), 'info', 1),
        [SayStmt]::new(@((PropOf 'architecture' (Var 'info'))), 2),
        [SayStmt]::new(@((PropOf 'machineName' (Var 'info'))), 3)
    )
    Assert-True ($out[0] -eq '64-bit' -or $out[0] -eq '32-bit') "expected architecture to be 64-bit or 32-bit, got [$($out[0])]"
    Assert-AreEqual -Expected ([System.Environment]::MachineName) -Actual $out[1]
}

Test-Otter 'D69: get system information "cpu" reports at least one logical core' {
    $out = Invoke-TestProgram @(
        [GetSystemInfoStmt]::new((Lit 'cpu'), 'info', 1),
        [SayStmt]::new(@((PropOf 'cores' (Var 'info'))), 2)
    )
    Assert-True ([double]$out[0] -gt 0) "expected at least one logical core, got [$($out[0])]"
}

Test-Otter 'D69: get system information "memory" reports free at or below total' {
    $out = Invoke-TestProgram @(
        [GetSystemInfoStmt]::new((Lit 'memory'), 'info', 1),
        [SayStmt]::new(@((PropOf 'totalBytes' (Var 'info'))), 2),
        [SayStmt]::new(@((PropOf 'freeBytes' (Var 'info'))), 3)
    )
    Assert-True ([double]$out[0] -gt 0) "expected total memory to be positive, got [$($out[0])]"
    Assert-True ([double]$out[1] -le [double]$out[0]) "expected free memory to be at or below total"
}

Test-Otter 'D69: get system information "disk" reports the current drive with free at or below total' {
    $out = Invoke-TestProgram @(
        [GetSystemInfoStmt]::new((Lit 'disk'), 'info', 1),
        [SayStmt]::new(@((PropOf 'totalBytes' (Var 'info'))), 2),
        [SayStmt]::new(@((PropOf 'freeBytes' (Var 'info'))), 3)
    )
    Assert-True ([double]$out[0] -gt 0) "expected total disk size to be positive, got [$($out[0])]"
    Assert-True ([double]$out[1] -le [double]$out[0]) "expected free disk space to be at or below total"
}

Test-Otter 'D69: get system information "network" returns a list of interface things' {
    $out = Invoke-TestProgram @(
        [GetSystemInfoStmt]::new((Lit 'network'), 'interfaces', 1),
        [SayStmt]::new(@((Lit 'ok')), 2)
    )
    Assert-Lines -Expected @('ok') -Actual $out
}

Test-Otter 'D69: get system information with an unknown kind is a clean Otter error' {
    Assert-OtterFails -Containing 'I do not know a kind of system information called "bogus"' -Body {
        Invoke-TestProgram @( [GetSystemInfoStmt]::new((Lit 'bogus'), 'info', 1) )
    }
}

Test-Otter 'D69: otherwise into reason catches an unknown system information kind' {
    $out = Invoke-TestProgram @(
        [TryStmt]::new(
            @([GetSystemInfoStmt]::new((Lit 'bogus'), 'info', 2)),
            @([SayStmt]::new(@((Var 'reason')), 4)), 'reason', 1)
    )
    Assert-Lines -Expected @('I do not know a kind of system information called "bogus".') -Actual $out
}

# =================================================================
# D70 - process management: run ... into p, get processes, kill
# =================================================================

Test-Otter 'D70: run into p hands back a real process handle, no longer silently dropped' {
    $out = Invoke-TestProgram @(
        [RunStmt]::new((Lit 'notepad.exe'), $false, 'p', 1),
        [SayStmt]::new(@((PropOf 'name' (Var 'p'))), 2),
        [KillProcessStmt]::new((Var 'p'), $false, 3)
    )
    Assert-AreEqual -Expected 1 -Actual $out.Count
    Assert-True ($out[0] -ieq 'notepad') "expected the process name to be notepad (case-insensitive), got [$($out[0])]"
}

Test-Otter 'D70: get processes into list returns a real, non-empty list of process things' {
    $out = Invoke-TestProgram @(
        [GetProcessesStmt]::new('procs', 1),
        [SayStmt]::new(@(([OfOperationExpr]::new([OfOperation]::Length, (Var 'procs'), 2))), 2)
    )
    Assert-True ([double]$out[0] -gt 0) "expected at least one real running process, got [$($out[0])]"
}

Test-Otter 'D70: kill process actually terminates the real OS process' {
    $out = Invoke-TestProgram @(
        [RunStmt]::new((Lit 'notepad.exe'), $false, 'p', 1),
        [SayStmt]::new(@((PropOf 'id' (Var 'p'))), 2),
        [KillProcessStmt]::new((Var 'p'), $false, 3)
    )
    Assert-AreEqual -Expected 1 -Actual $out.Count
    $killedPid = [int][double]::Parse($out[0])
    Start-Sleep -Milliseconds 400
    $stillAlive = Get-Process -Id $killedPid -ErrorAction SilentlyContinue
    Assert-True ($null -eq $stillAlive) "expected process $killedPid to be dead after kill process"
}

Test-Otter 'D70: kill process p and its children kills the whole subtree' {
    # cmd.exe's own `timeout` builtin refuses to run without a real console
    # (fails instantly under some launch contexts, including this test
    # harness), which would make the "parent" exit before the test can
    # observe it - powershell.exe's Start-Sleep has no such requirement,
    # so it reliably stays alive while its own child (notepad.exe) runs.
    $parent = Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile -Command "Start-Process notepad.exe; Start-Sleep -Seconds 60"' -PassThru
    Start-Sleep -Milliseconds 1500
    $children = @(Get-CimInstance -ClassName Win32_Process -Filter ("ParentProcessId = " + $parent.Id) -ErrorAction SilentlyContinue)
    Assert-True ($children.Count -gt 0) 'expected the spawned cmd.exe to have a real child process to test against'

    $out = Invoke-TestProgram @(
        [AssignStmt]::new('parentId', (Lit ([double]$parent.Id)), 1),
        [GetProcessesStmt]::new('allProcs', 2),
        [FindStmt]::new('found', (Var 'allProcs'), (CompareEx (PropOf 'id' (Var 'found')) 'Equal' (Var 'parentId')), 'foundProc', 3),
        [KillProcessStmt]::new((Var 'foundProc'), $true, 4),
        [SayStmt]::new(@((Lit 'killed')), 5)
    )
    Assert-Lines -Expected @('killed') -Actual $out

    Start-Sleep -Milliseconds 500
    $parentAlive = Get-Process -Id $parent.Id -ErrorAction SilentlyContinue
    Assert-True ($null -eq $parentAlive) "expected parent process $($parent.Id) to be dead"
    foreach ($c in $children) {
        $alive = Get-Process -Id $c.ProcessId -ErrorAction SilentlyContinue
        if ($alive) { Stop-Process -Id $c.ProcessId -Force -ErrorAction SilentlyContinue }
        Assert-True ($null -eq $alive) "expected child process $($c.ProcessId) to be dead after kill ... and its children"
    }
}

Test-Otter 'D70: kill process refuses anything that is not a real process handle' {
    Assert-OtterFails -Containing 'I can only kill a real process handle' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('notAHandle', (Lit 42.0), 1),
            [KillProcessStmt]::new((Var 'notAHandle'), $false, 2)
        )
    }
}

# =================================================================
# D71 - process priority and process timeout
# =================================================================

Test-Otter 'D71: set process priority actually changes the real OS process priority' {
    $out = Invoke-TestProgram @(
        [RunStmt]::new((Lit 'notepad.exe'), $false, 'p', 1),
        [SetProcessPriorityStmt]::new((Var 'p'), (Lit 'high'), 2),
        [SayStmt]::new(@((PropOf 'id' (Var 'p'))), 3)
    )
    Assert-AreEqual -Expected 1 -Actual $out.Count
    $targetPid = [int][double]::Parse($out[0])
    try {
        $proc = Get-Process -Id $targetPid -ErrorAction Stop
        Assert-AreEqual -Expected 'High' -Actual ([string]$proc.PriorityClass)
    } finally {
        Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
    }
}

Test-Otter 'D71: set process priority with an unknown level is a clean Otter error' {
    $out = Invoke-TestProgram @(
        [RunStmt]::new((Lit 'notepad.exe'), $false, 'p', 1),
        [TryStmt]::new(
            @([SetProcessPriorityStmt]::new((Var 'p'), (Lit 'bogus'), 2)),
            @([SayStmt]::new(@((Var 'reason')), 3)), 'reason', 1),
        [KillProcessStmt]::new((Var 'p'), $false, 4)
    )
    Assert-Lines -Expected @('I do not know a process priority called "bogus".') -Actual $out
}

Test-Otter 'D71: set process priority refuses anything that is not a real process handle' {
    Assert-OtterFails -Containing 'I can only set the priority of a real process handle' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('notAHandle', (Lit 42.0), 1),
            [SetProcessPriorityStmt]::new((Var 'notAHandle'), (Lit 'high'), 2)
        )
    }
}

Test-Otter 'D71: wait for process up to N seconds returns false while the process is still running' {
    $out = Invoke-TestProgram @(
        [RunStmt]::new((Lit 'notepad.exe'), $false, 'p', 1),
        [WaitForProcessStmt]::new((Var 'p'), (Lit 1.0), 'finished', 2),
        [SayStmt]::new(@((Var 'finished')), 3),
        [KillProcessStmt]::new((Var 'p'), $false, 4)
    )
    Assert-Lines -Expected @('false') -Actual $out
}

Test-Otter 'D71: wait for process up to N seconds returns true once the process has exited' {
    $out = Invoke-TestProgram @(
        [RunStmt]::new((Lit 'notepad.exe'), $false, 'p', 1),
        [KillProcessStmt]::new((Var 'p'), $false, 2),
        [WaitForProcessStmt]::new((Var 'p'), (Lit 5.0), 'finished', 3),
        [SayStmt]::new(@((Var 'finished')), 4)
    )
    Assert-Lines -Expected @('true') -Actual $out
}

Test-Otter 'D71: wait for process refuses anything that is not a real process handle' {
    Assert-OtterFails -Containing 'I can only wait for a real process handle' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('notAHandle', (Lit 42.0), 1),
            [WaitForProcessStmt]::new((Var 'notAHandle'), (Lit 1.0), 'finished', 2)
        )
    }
}

# =================================================================
# D72 - atomic save and file locks
# =================================================================

Test-Otter 'D72: write atomically creates a brand-new file with the right content' {
    $path = Join-Path $sandbox 'd72-new.txt'
    $out = Invoke-TestProgram @(
        [WriteFileStmt]::new((Lit 'brand new atomic content'), (Lit $path), $true, 1),
        [ReadFileStmt]::new((Lit $path), 'contents', 2),
        [SayStmt]::new(@((Var 'contents')), 3)
    )
    Assert-Lines -Expected @('brand new atomic content') -Actual $out
    Assert-AreEqual -Expected 0 -Actual @(Get-ChildItem -LiteralPath $sandbox -Filter '*.otter-tmp-*').Count
    Assert-AreEqual -Expected 0 -Actual @(Get-ChildItem -LiteralPath $sandbox -Filter '*.otter-bak-*').Count
}

Test-Otter 'D72: write atomically replaces an already-existing file, leaving no temp/backup residue' {
    $path = Join-Path $sandbox 'd72-existing.txt'
    Set-Content -LiteralPath $path -Value 'old content' -NoNewline
    $out = Invoke-TestProgram @(
        [WriteFileStmt]::new((Lit 'new content replacing old'), (Lit $path), $true, 1),
        [ReadFileStmt]::new((Lit $path), 'contents', 2),
        [SayStmt]::new(@((Var 'contents')), 3)
    )
    Assert-Lines -Expected @('new content replacing old') -Actual $out
    Assert-AreEqual -Expected 0 -Actual @(Get-ChildItem -LiteralPath $sandbox -Filter '*.otter-tmp-*').Count
    Assert-AreEqual -Expected 0 -Actual @(Get-ChildItem -LiteralPath $sandbox -Filter '*.otter-bak-*').Count
}

Test-Otter 'D72: a plain write with no atomically qualifier still works unchanged' {
    $path = Join-Path $sandbox 'd72-plain.txt'
    $out = Invoke-TestProgram @(
        [WriteFileStmt]::new((Lit 'plain write'), (Lit $path), 1),
        [ReadFileStmt]::new((Lit $path), 'contents', 2),
        [SayStmt]::new(@((Var 'contents')), 3)
    )
    Assert-Lines -Expected @('plain write') -Actual $out
}

Test-Otter 'D72: file is locked is false for a free file that exists' {
    $path = Join-Path $sandbox 'd72-free.txt'
    Set-Content -LiteralPath $path -Value 'free' -NoNewline
    $out = Invoke-TestProgram @(
        [IfStmt]::new(
            @([IfBranch]::new([FileLockedExpr]::new((Lit $path), 1),
                @([SayStmt]::new(@((Lit 'locked')), 2)))),
            @([SayStmt]::new(@((Lit 'not locked')), 4)), 1)
    )
    Assert-Lines -Expected @('not locked') -Actual $out
}

Test-Otter 'D72: file is locked is false for a file that does not exist' {
    $path = Join-Path $sandbox 'd72-does-not-exist.txt'
    $out = Invoke-TestProgram @(
        [IfStmt]::new(
            @([IfBranch]::new([FileLockedExpr]::new((Lit $path), 1),
                @([SayStmt]::new(@((Lit 'locked')), 2)))),
            @([SayStmt]::new(@((Lit 'not locked')), 4)), 1)
    )
    Assert-Lines -Expected @('not locked') -Actual $out
}

Test-Otter 'D72: file is locked is true for a file another process holds open exclusively' {
    $path = Join-Path $sandbox 'd72-locked.txt'
    Set-Content -LiteralPath $path -Value 'locked' -NoNewline
    $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $out = Invoke-TestProgram @(
            [IfStmt]::new(
                @([IfBranch]::new([FileLockedExpr]::new((Lit $path), 1),
                    @([SayStmt]::new(@((Lit 'locked')), 2)))),
                @([SayStmt]::new(@((Lit 'not locked')), 4)), 1)
        )
        Assert-Lines -Expected @('locked') -Actual $out
    } finally {
        $stream.Close()
    }
}


Set-Location $originalLocation
Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue

Complete-OtterTests
