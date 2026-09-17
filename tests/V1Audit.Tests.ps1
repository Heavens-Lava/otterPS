# Production-entry-point checks for the V1 semantic correction pass.
# These intentionally call otter.ps1 rather than importing the parser so a
# passing result means the real `otter check` / `otter run` path reached it.

$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..'
$otter = Join-Path $root 'otter.ps1'

function Invoke-OtterCliFixture {
    param([string[]]$Arguments)
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $otter @Arguments 2>&1
    return ($output -join "`n")
}

$invalidFixtures = @(
    @{ Path = 'conformance\negative\boolean_operators_outside_conditions.ot'; Text = 'only works inside an if or while condition' },
    @{ Path = 'conformance\negative\reserved_literal_variable.ot'; Text = 'built-in value, not a variable name' },
    @{ Path = 'conformance\negative\typed_object_indented_initializer.ot'; Text = 'declared type, so its properties must use' }
)

foreach ($fixture in $invalidFixtures) {
    $output = Invoke-OtterCliFixture -Arguments @('check', $fixture.Path)
    if ($output -notmatch [regex]::Escape($fixture.Text)) {
        throw "Expected otter check diagnostic '$($fixture.Text)' for $($fixture.Path), got: $output"
    }
}

$functionOutput = Invoke-OtterCliFixture -Arguments @('run', 'conformance\core\function_return_expression.ot')
if ($functionOutput.Trim() -ne "20`n7`n20`n10") {
    throw "Expected expression and legacy function capture output 20, 7, 20, 10; got: $functionOutput"
}

Write-Output 'V1 audit production-entry tests passed.'
