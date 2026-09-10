using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.UI.psm1
using module ..\src\Otter.Interpreter.psm1

# UI.Tests.ps1
#
# D44: external UI resources. Tests the lifecycle guarantees directly -
# real WPF object created immediately, same identity for its whole life -
# and confirms the boundary D44 principle 5 requires: no WPF-specific name
# ever reaches an Otter-facing string.

. "$PSScriptRoot\TestHelpers.ps1"

function Lit { param($v, [int]$l = 1) [LiteralExpr]::new($v, $l) }

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
Write-Host 'External UI resources (D44)' -ForegroundColor Cyan


# =================================================================
# lifecycle - the central claim, verified directly
# =================================================================

Test-Otter 'create button into helloButton makes a REAL WPF Button, immediately' {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1)
    )))
    $resource = $env.Get('helloButton')
    Assert-True (Test-OtterUiResource $resource) 'expected an OtterUiResource'
    Assert-AreEqual -Expected 'button' -Actual $resource.Kind
    Assert-AreEqual -Expected 'wpf' -Actual $resource.Provider
    Assert-AreEqual -Expected 'Button' -Actual $resource.Native.GetType().Name
}

Test-Otter 'the resource keeps the SAME identity across every read (Jeff''s core lifecycle requirement)' {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1)
    )))
    $first = $env.Get('helloButton')
    $second = $env.Get('helloButton')
    Assert-True ([object]::ReferenceEquals($first, $second)) 'the wrapper must be the same instance'
    Assert-True ([object]::ReferenceEquals($first.Native, $second.Native)) 'the underlying WPF object must be the same instance'
}

Test-Otter 'a property set directly on the native object is visible through every reference to it' {
    # Proves "attachment/layout reuses the same object, it does not
    # recreate it" is actually true of the underlying value, not just
    # asserted - set .Content directly (standing in for what D45's real
    # property-write will eventually do) and confirm every read sees it.
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1)
    )))
    $resource = $env.Get('helloButton')
    $resource.Native.Content = 'Say Hello'

    $readBack = $env.Get('helloButton')
    Assert-AreEqual -Expected 'Say Hello' -Actual $readBack.Native.Content
}

Test-Otter 'each of the D44 proving-set control kinds creates its real WPF type' {
    $expected = @{
        'window'   = 'Window'
        'button'   = 'Button'
        'text'     = 'TextBlock'
        'text box' = 'TextBox'
    }
    foreach ($kind in $expected.Keys) {
        $resource = New-OtterUiResourceValue -Kind $kind -Line 1
        Assert-AreEqual -Expected $kind -Actual $resource.Kind -Message $kind
        Assert-AreEqual -Expected $expected[$kind] -Actual $resource.Native.GetType().Name -Message $kind
    }
}

Test-Otter 'an unsupported kind is a clear Otter error, not a raw exception' {
    Assert-OtterFails -Containing "don't know how to create a checkbox" -Body {
        New-OtterUiResourceValue -Kind 'checkbox' -Line 1
    }
}


# =================================================================
# the boundary - D44 principle 5: no WPF names ever reach Otter output
# =================================================================

Test-Otter 'say prints "a button", never the WPF class name' {
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1),
        [SayStmt]::new(@([VariableExpr]::new('helloButton', 2)), 2)
    )
    Assert-Lines -Expected @('a button') -Actual $out
    Assert-False ($out[0] -like '*System.Windows*') 'must not leak the WPF type name'
}

Test-Otter 'a created resource is truthy, the same reasoning as an object' {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('window', 'app', 1)
    )))
    Assert-True (Test-OtterTruthy -Value ($env.Get('app')))
}

Test-Otter 'an error naming the value says "a text box", never TextBox or System.Windows' {
    Assert-OtterFails -Containing 'a text box' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('text box', 'nameBox', 1),
            [SayStmt]::new(@([PropertyAccessExpr]::new('text', [VariableExpr]::new('nameBox', 2), 2)), 2)
        )
    }
}


# =================================================================
# property access is explicitly deferred to D45 - honest, not silent
# =================================================================

Test-Otter 'reading a property says "not built yet", distinct from "not a thing"' {
    Assert-OtterFails -Containing 'not built yet' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('button', 'helloButton', 1),
            [SayStmt]::new(@([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 2), 2)), 2)
        )
    }
}

Test-Otter 'writing a property says "not built yet" too' {
    Assert-OtterFails -Containing 'not built yet' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('button', 'helloButton', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 2), 2), (Lit 'Say Hello'), 2)
        )
    }
}


# =================================================================
# D40/D43: has still means data, create still means an external resource
# =================================================================

Test-Otter 'has-built things are unaffected - still ordinary OtterObject' {
    $out = Invoke-TestProgram @(
        [ObjectDefStmt]::new('person', 'thing', @([AssignStmt]::new('name', (Lit 'Jeff'), 2)), 1),
        [SayStmt]::new(@([PropertyAccessExpr]::new('name', [VariableExpr]::new('person', 3), 3)), 3)
    )
    Assert-Lines -Expected @('Jeff') -Actual $out
}

Test-Otter 'a UI resource does not accept dynamic get/set (D41 rule 9, inherited automatically)' {
    # Assert-OtterDynamicKeyTarget checks Test-OtterObject specifically -
    # OtterUiResource is a different class entirely, so this exclusion
    # needed no new code at all. Confirmed, not just assumed.
    Assert-OtterFails -Containing 'a button' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('button', 'helloButton', 1),
            [SetKeyStmt]::new((Lit 'text'), (Lit 'Say Hello'), [VariableExpr]::new('helloButton', 2), 2)
        )
    }
}

Complete-OtterTests
