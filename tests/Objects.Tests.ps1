using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Interpreter.psm1

# Objects.Tests.ps1
#
# 0.3: things, properties, and custom types.
#
# The rule these all exercise (D19): properties are written property-first
# with "of", and a property access is an ordinary expression - so it can be
# read anywhere a value is allowed, and written anywhere a name is allowed.

. "$PSScriptRoot\TestHelpers.ps1"

function Lit { param($Value, [int]$Line = 1) [LiteralExpr]::new($Value, $Line) }
function Var { param([string]$Name, [int]$Line = 1) [VariableExpr]::new($Name, $Line) }
function PropOf { param([string]$Property, [Node]$Target, [int]$Line = 1) [PropertyAccessExpr]::new($Property, $Target, $Line) }

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

# person is a thing
#     name is "Jeff"
#     age is 29
# .
function NewPerson {
    param([int]$Line = 1)
    [ObjectDefStmt]::new('person', 'thing', @(
        [AssignStmt]::new('name', (Lit 'Jeff'), $Line + 1),
        [AssignStmt]::new('age', (Lit 29.0), $Line + 2)
    ), $Line)
}

Write-Host ''
Write-Host 'Objects and properties (0.3)' -ForegroundColor Cyan


# =================================================================
# reading
# =================================================================

Test-Otter 'say name of person' {
    $out = Invoke-TestProgram @(
        (NewPerson),
        [SayStmt]::new(@((PropOf 'name' (Var 'person'))), 5)
    )
    Assert-Lines -Expected @('Jeff') -Actual $out
}

Test-Otter 'properties keep their own types' {
    $out = Invoke-TestProgram @(
        (NewPerson),
        [SayStmt]::new(@((PropOf 'name' (Var 'person')), (Lit 'is'), (PropOf 'age' (Var 'person'))), 5)
    )
    Assert-Lines -Expected @('Jeff is 29') -Actual $out
}

Test-Otter 'a property can be used anywhere a value can' {
    # if age of person is at least 18
    $out = Invoke-TestProgram @(
        (NewPerson),
        [IfStmt]::new(
            @([IfBranch]::new(
                [ComparisonExpr]::new((PropOf 'age' (Var 'person')), [CompareOp]::AtLeast, (Lit 18.0), 5),
                @([SayStmt]::new(@((Lit 'Adult')), 6)))),
            $null, 5)
    )
    Assert-Lines -Expected @('Adult') -Actual $out
}


# =================================================================
# writing
# =================================================================

Test-Otter 'name of person is "Jeffrey" changes the property' {
    $out = Invoke-TestProgram @(
        (NewPerson),
        [AssignStmt]::new((PropOf 'name' (Var 'person') 5), (Lit 'Jeffrey'), 5),
        [SayStmt]::new(@((PropOf 'name' (Var 'person'))), 6)
    )
    Assert-Lines -Expected @('Jeffrey') -Actual $out
}

Test-Otter 'assigning a property that did not exist adds it' {
    $out = Invoke-TestProgram @(
        (NewPerson),
        [AssignStmt]::new((PropOf 'city' (Var 'person') 5), (Lit 'Tucson'), 5),
        [SayStmt]::new(@((PropOf 'city' (Var 'person'))), 6)
    )
    Assert-Lines -Expected @('Tucson') -Actual $out
}

Test-Otter 'plain assignment still works alongside property assignment' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('name', (Lit 'Outside'), 1),
        (NewPerson -Line 2),
        [AssignStmt]::new((PropOf 'name' (Var 'person') 6), (Lit 'Inside'), 6),
        [SayStmt]::new(@((Var 'name')), 7),
        [SayStmt]::new(@((PropOf 'name' (Var 'person'))), 8)
    )
    Assert-Lines -Expected @('Outside', 'Inside') -Actual $out
}


# =================================================================
# nesting - city of address of user
# =================================================================

Test-Otter 'city of address of user nests right-recursively' {
    $out = Invoke-TestProgram @(
        [ObjectDefStmt]::new('address', 'thing', @(
            [AssignStmt]::new('city', (Lit 'Tucson'), 2)
        ), 1),
        [ObjectDefStmt]::new('user', 'thing', @(
            [AssignStmt]::new('address', (Var 'address'), 5)
        ), 4),
        # PropertyAccess("city", PropertyAccess("address", Variable("user")))
        [SayStmt]::new(@((PropOf 'city' (PropOf 'address' (Var 'user')))), 7)
    )
    Assert-Lines -Expected @('Tucson') -Actual $out
}

Test-Otter 'a nested property can be assigned too' {
    $out = Invoke-TestProgram @(
        [ObjectDefStmt]::new('address', 'thing', @(
            [AssignStmt]::new('city', (Lit 'Tucson'), 2)
        ), 1),
        [ObjectDefStmt]::new('user', 'thing', @(
            [AssignStmt]::new('address', (Var 'address'), 5)
        ), 4),
        [AssignStmt]::new((PropOf 'city' (PropOf 'address' (Var 'user')) 7), (Lit 'Phoenix'), 7),
        [SayStmt]::new(@((PropOf 'city' (Var 'address'))), 8)
    )
    # The same object is shared, so changing it through user changes address.
    Assert-Lines -Expected @('Phoenix') -Actual $out
}


# =================================================================
# custom types
# =================================================================

Test-Otter 'a Person has name and age, then jeff is a Person' {
    $out = Invoke-TestProgram @(
        [TypeDefStmt]::new('Person', @('name', 'age'), 1),
        [ObjectDefStmt]::new('jeff', 'Person', @(), 4),
        [AssignStmt]::new((PropOf 'name' (Var 'jeff') 5), (Lit 'Jeff'), 5),
        [AssignStmt]::new((PropOf 'age' (Var 'jeff') 6), (Lit 29.0), 6),
        [SayStmt]::new(@((Lit 'Hello'), (PropOf 'name' (Var 'jeff'))), 7)
    )
    Assert-Lines -Expected @('Hello Jeff') -Actual $out
}

Test-Otter 'a custom type declares its properties up front' {
    # name of jeff reads as nothing rather than failing, because the type
    # said the property exists.
    $out = Invoke-TestProgram @(
        [TypeDefStmt]::new('Person', @('name', 'age'), 1),
        [ObjectDefStmt]::new('jeff', 'Person', @(), 4),
        [SayStmt]::new(@((PropOf 'name' (Var 'jeff'))), 5)
    )
    Assert-Lines -Expected @('nothing') -Actual $out
}


# =================================================================
# printing and errors
# =================================================================

Test-Otter 'saying the object itself names its type' {
    $out = Invoke-TestProgram @(
        (NewPerson),
        [SayStmt]::new(@((Var 'person')), 5)
    )
    Assert-Lines -Expected @('a thing') -Actual $out
}

Test-Otter 'reading a property of something that is not a thing explains itself' {
    Assert-OtterFails -Containing 'I can only read properties of a thing' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('score', (Lit 10.0), 1),
            [SayStmt]::new(@((PropOf 'name' (Var 'score'))), 2)
        )
    }
}

Test-Otter 'reading a property that does not exist names it' {
    Assert-OtterFails -Containing 'no property called "height"' -Body {
        Invoke-TestProgram @(
            (NewPerson),
            [SayStmt]::new(@((PropOf 'height' (Var 'person'))), 5)
        )
    }
}

Test-Otter 'setting a property on something that is not a thing explains itself' {
    Assert-OtterFails -Containing 'I can only set properties on a thing' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('score', (Lit 10.0), 1),
            [AssignStmt]::new((PropOf 'name' (Var 'score') 2), (Lit 'x'), 2)
        )
    }
}


Complete-OtterTests
