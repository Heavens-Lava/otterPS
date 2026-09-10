using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Library.psm1
using module ..\src\Otter.Interpreter.psm1

# DynamicThing.Tests.ps1
#
# D41: dynamic thing access. Covers all nine frozen rules against
# hand-built AST, ahead of the parser support that makes them reachable
# from real Otter source.
#
#   1. no separate dictionary runtime type
#   2. has and JSON objects stay OtterObject(TypeName: 'thing')
#   3. get/set operate only on 'thing'
#   4. get on a missing key -> gone
#   5. ordinary "property of thing" keeps its existing error on a miss
#   6. set creates or replaces
#   7. separate AST nodes from PropertyAccessExpr
#   8. empty "has" objects are legal            <- parser-side, not here
#   9. files/folders/other resources cannot be dynamically mutated

. "$PSScriptRoot\TestHelpers.ps1"

function Lit { param($v, [int]$l = 1) [LiteralExpr]::new($v, $l) }
function Var { param([string]$n, [int]$l = 1) [VariableExpr]::new($n, $l) }
function PropOf { param([string]$p, [Node]$t, [int]$l = 1) [PropertyAccessExpr]::new($p, $t, $l) }
function Gone { param([int]$l = 1) [LiteralExpr]::new($null, $l) }
function CompareEx { param([Node]$l, [string]$op, [Node]$r, [int]$ln = 1) [ComparisonExpr]::new($l, [CompareOp]$op, $r, $ln) }

function NewPerson {
    param([int]$Line = 1)
    [ObjectDefStmt]::new('person', 'thing', @(
        [AssignStmt]::new('name', (Lit 'Jeff'), $Line + 1),
        [AssignStmt]::new('age', (Lit 29.0), $Line + 2)
    ), $Line)
}

function Invoke-TestProgram {
    param([Node[]]$Statements)
    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($t) $collected.Add($t) }.GetNewClosure()
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
Write-Host 'Dynamic thing access (D41)' -ForegroundColor Cyan


# =================================================================
# rules 1, 2, 6, 7 - the central unification claim
# =================================================================

Test-Otter 'set then get sees the value through the same object (rule 1)' {
    $out = Invoke-TestProgram @(
        (NewPerson),
        [SetKeyStmt]::new((Lit 'nickname'), (Lit 'Jeffrey'), (Var 'person'), 4),
        [GetKeyStmt]::new((Lit 'nickname'), (Var 'person'), 'nickname', 5),
        [SayStmt]::new(@((Var 'nickname')), 6)
    )
    Assert-Lines -Expected @('Jeffrey') -Actual $out
}

Test-Otter 'a dynamic write is visible through ordinary property access (rule 1, 7)' {
    # This is the load-bearing claim: set via the dynamic path, read via
    # the ordinary "X of Y" path. If these are really the same object,
    # this must see the write.
    $out = Invoke-TestProgram @(
        (NewPerson),
        [SetKeyStmt]::new((Lit 'city'), (Lit 'Tucson'), (Var 'person'), 4),
        [SayStmt]::new(@((PropOf 'city' (Var 'person'))), 5)
    )
    Assert-Lines -Expected @('Tucson') -Actual $out
}

Test-Otter 'set replaces an existing key (rule 6)' {
    $out = Invoke-TestProgram @(
        (NewPerson),
        [SetKeyStmt]::new((Lit 'name'), (Lit 'Jeffrey'), (Var 'person'), 4),
        [SayStmt]::new(@((PropOf 'name' (Var 'person'))), 5)
    )
    Assert-Lines -Expected @('Jeffrey') -Actual $out
}

Test-Otter 'set creates a key that did not exist (rule 6)' {
    $out = Invoke-TestProgram @(
        (NewPerson),
        [SetKeyStmt]::new((Lit 'city'), (Lit 'Phoenix'), (Var 'person'), 4),
        [SayStmt]::new(@((PropOf 'city' (Var 'person'))), 5)
    )
    Assert-Lines -Expected @('Phoenix') -Actual $out
}


# =================================================================
# rule 2 - JSON objects are the same type has builds
# =================================================================

Test-Otter 'a JSON object supports dynamic access exactly like a has-built thing (rule 2)' {
    $sandbox = Join-Path $env:TEMP ("otter-d41-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $sandbox -Force)
    $original = (Get-Location).Path
    Set-Location $sandbox
    try {
        [System.IO.File]::WriteAllText((Join-Path $sandbox 'p.json'), '{"name":"Jeff"}', [System.Text.UTF8Encoding]::new($false))
        $out = Invoke-TestProgram @(
            [ReadJsonStmt]::new((Lit 'p.json'), 'person', 1),
            [SetKeyStmt]::new((Lit 'nickname'), (Lit 'Jeffrey'), (Var 'person'), 2),
            [GetKeyStmt]::new((Lit 'nickname'), (Var 'person'), 'nickname', 3),
            [SayStmt]::new(@((Var 'nickname')), 4)
        )
        Assert-Lines -Expected @('Jeffrey') -Actual $out
    }
    finally {
        Set-Location $original
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}


# =================================================================
# rule 4 - missing key is gone, never an error
# =================================================================

Test-Otter 'get on a missing key is gone, not an error (rule 4)' {
    $out = Invoke-TestProgram @(
        (NewPerson),
        [GetKeyStmt]::new((Lit 'nickname'), (Var 'person'), 'nickname', 4),
        [SayStmt]::new(@((Var 'nickname')), 5)
    )
    Assert-Lines -Expected @('gone') -Actual $out
}

Test-Otter 'a missing dynamic key can be tested with is gone (rule 4)' {
    $out = Invoke-TestProgram @(
        (NewPerson),
        [GetKeyStmt]::new((Lit 'nickname'), (Var 'person'), 'nickname', 4),
        [IfStmt]::new(
            @([IfBranch]::new((CompareEx (Var 'nickname') 'Equal' (Gone)),
                @([SayStmt]::new(@((Lit 'no nickname set')), 6)))),
            $null, 5)
    )
    Assert-Lines -Expected @('no nickname set') -Actual $out
}


# =================================================================
# rule 5 - ordinary property access keeps its existing error behavior
# =================================================================

Test-Otter 'property of thing STILL errors on a missing property (rule 5)' {
    # This is the point of keeping two nodes: the dynamic path above just
    # printed "gone" for the identical situation. The ordinary path must
    # not have quietly changed.
    Assert-OtterFails -Containing 'no property called "nickname"' -Body {
        Invoke-TestProgram @(
            (NewPerson),
            [SayStmt]::new(@((PropOf 'nickname' (Var 'person'))), 4)
        )
    }
}


# =================================================================
# rules 3, 9 - thing-only scoping
# =================================================================

Test-Otter 'dynamic set on a file object is refused (rule 3, 9)' {
    $sandbox = Join-Path $env:TEMP ("otter-d41file-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $sandbox -Force)
    $original = (Get-Location).Path
    Set-Location $sandbox
    try {
        [System.IO.File]::WriteAllText((Join-Path $sandbox 'note.txt'), 'hi', [System.Text.UTF8Encoding]::new($false))
        $file = New-OtterFileObject -Path 'note.txt'

        # This is exactly the corruption the investigation reproduced -
        # size of file would silently change without this guard.
        Assert-OtterFails -Containing 'I can only write to properties dynamically on a thing' -Body {
            Invoke-TestProgram @(
                [AssignStmt]::new('file', (Lit $file), 1),
                [SetKeyStmt]::new((Lit 'size'), (Lit 999999.0), (Var 'file'), 2)
            )
        }

        # And confirm it actually did NOT change.
        Assert-AreEqual -Expected '2' -Actual (Format-OtterValue -Value $file.ReadProperty('size'))
    }
    finally {
        Set-Location $original
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Otter 'dynamic get on a folder object is refused (rule 3, 9)' {
    $folder = New-OtterFolderObject -Path $env:TEMP
    Assert-OtterFails -Containing 'I can only read from properties dynamically on a thing' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('folder', (Lit $folder), 1),
            [GetKeyStmt]::new((Lit 'name'), (Var 'folder'), 'x', 2)
        )
    }
}

Test-Otter 'dynamic access on a value that is not a thing at all explains itself' {
    Assert-OtterFails -Containing 'I can only read from a thing' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('score', (Lit 10.0), 1),
            [GetKeyStmt]::new((Lit 'x'), (Var 'score'), 'y', 2)
        )
    }
}


# =================================================================
# the left-open detail: string-only keys for 0.1
# =================================================================

Test-Otter 'a non-string key is refused, not silently coerced' {
    Assert-OtterFails -Containing 'I need text for a dynamic key' -Body {
        Invoke-TestProgram @(
            (NewPerson),
            [GetKeyStmt]::new((Lit 5.0), (Var 'person'), 'x', 4)
        )
    }
}

Test-Otter 'a key computed from an expression works, as long as it is text' {
    # The Key is a full expression, not restricted to a literal - only its
    # runtime VALUE has to be text.
    $out = Invoke-TestProgram @(
        (NewPerson),
        [AssignStmt]::new('field', (Lit 'name'), 4),
        [GetKeyStmt]::new((Var 'field'), (Var 'person'), 'result', 5),
        [SayStmt]::new(@((Var 'result')), 6)
    )
    Assert-Lines -Expected @('Jeff') -Actual $out
}


Complete-OtterTests
