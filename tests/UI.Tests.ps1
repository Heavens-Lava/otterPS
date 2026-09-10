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

Test-Otter 'an unsupported property still names the kind, never a WPF type name (D45)' {
    Assert-OtterFails -Containing 'a text box' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('text box', 'nameBox', 1),
            [SayStmt]::new(@([PropertyAccessExpr]::new('color', [VariableExpr]::new('nameBox', 2), 2)), 2)
        )
    }
}


# =================================================================
# D45 - property read/write, routed through the toolkit-neutral mapping
# =================================================================

Test-Otter 'text of a button writes and reads back through ordinary property syntax' {
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 2), 2), (Lit 'Say Hello'), 2),
        [SayStmt]::new(@([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 3), 3)), 3)
    )
    Assert-Lines -Expected @('Say Hello') -Actual $out
}

Test-Otter 'button text maps to native Content, not Text - verified on the real object' {
    # This is the exact mapping the investigation confirmed empirically:
    # TextBox does not even have a Content property; Button does not have
    # a settable Text property the same way. Getting this backwards would
    # be a silent, wrong write, not an error.
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 2), 2), (Lit 'Say Hello'), 2)
    )))
    $resource = $env.Get('helloButton')
    Assert-AreEqual -Expected 'Say Hello' -Actual $resource.Native.Content
}

Test-Otter 'text box text maps to native Text, not Content' {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('text box', 'nameBox', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('text', [VariableExpr]::new('nameBox', 2), 2), (Lit 'Jeff'), 2)
    )))
    $resource = $env.Get('nameBox')
    Assert-AreEqual -Expected 'Jeff' -Actual $resource.Native.Text
}

Test-Otter 'window title, width and height all read and write correctly' {
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('title', [VariableExpr]::new('app', 2), 2), (Lit 'My App'), 2),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('app', 3), 3), (Lit 500.0), 3),
        [AssignStmt]::new([PropertyAccessExpr]::new('height', [VariableExpr]::new('app', 4), 4), (Lit 300.0), 4),
        [SayStmt]::new(@([PropertyAccessExpr]::new('title', [VariableExpr]::new('app', 5), 5)), 5),
        [SayStmt]::new(@([PropertyAccessExpr]::new('width', [VariableExpr]::new('app', 6), 6)), 6),
        [SayStmt]::new(@([PropertyAccessExpr]::new('height', [VariableExpr]::new('app', 7), 7)), 7)
    )
    Assert-Lines -Expected @('My App', '500', '300') -Actual $out
}

Test-Otter 'text properties coerce any value, the same conversion say already uses' {
    # text of X is 5 sets it to "5" rather than erroring - matching how
    # "say 5" already prints "5", not a type mismatch.
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 2), 2), (Lit 5.0), 2),
        [SayStmt]::new(@([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 3), 3)), 3)
    )
    Assert-Lines -Expected @('5') -Actual $out
}

Test-Otter 'a numeric property rejects the wrong type as a clean Otter error, not a raw .NET exception' {
    # Verified before writing Set-OtterUiProperty: WPF itself throws
    # SetValueInvocationException naming "System.Double" directly in its
    # message for exactly this case. That must never reach a user.
    Assert-OtterFails -Containing 'I expected a number for the width' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('window', 'app', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('app', 2), 2), (Lit 'not a number'), 2)
        )
    }
}

Test-Otter 'the numeric-type error never leaks System.Double or any .NET name' {
    $env = New-OtterEnvironment
    try {
        Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
            [CreateUiResourceStmt]::new('window', 'app', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('app', 2), 2), (Lit 'not a number'), 2)
        )))
        throw 'expected this to fail'
    }
    catch {
        Assert-False ($_.Exception.Message -like '*System.*') 'must not leak a .NET type name'
        Assert-False ($_.Exception.Message -like '*SetValueInvocation*') 'must not leak the raw WPF exception type'
    }
}

Test-Otter 'reading an unset text property is gone, not an error, not empty text' {
    # D22: no value exists here yet is a different state from "" - a
    # freshly created button has never had its text set at all.
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1),
        [SayStmt]::new(@([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 2), 2)), 2)
    )
    Assert-Lines -Expected @('gone') -Actual $out
}

Test-Otter 'an unsupported property on a window names the window and the property' {
    Assert-OtterFails -Containing 'a window has no property called "color"' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('window', 'app', 1),
            [SayStmt]::new(@([PropertyAccessExpr]::new('color', [VariableExpr]::new('app', 2), 2)), 2)
        )
    }
}

Test-Otter 'setting an unsupported property fails before touching the native object at all' {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1)
    )))
    $resource = $env.Get('helloButton')
    $before = $resource.Native.Content

    Assert-OtterFails -Containing 'no property called' -Body {
        Set-OtterUiProperty -Resource $resource -Property 'color' -Value 'red' -Line 1
    }
    Assert-AreEqual -Expected $before -Actual $resource.Native.Content
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
