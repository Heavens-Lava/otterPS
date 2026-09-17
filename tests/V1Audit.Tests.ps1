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

# `and` is a real, deliberate synonym for numeric addition and string
# concatenation OUTSIDE a condition too - confirmed still relied on by real,
# shipped Otter programs (examples/cli-app.ot, examples/studio.ot,
# examples/terminal.ot all concatenate text with `and` outside any
# if/while). An earlier version of this V1 pass rejected bare `and` at
# PARSE time unconditionally, which silently broke all three of those real
# programs - `otter check` on each used to fail. A parser-level rejection
# cannot distinguish "and" used for real addition from "and" used as
# boolean logic by mistake outside a condition; only the interpreter/JS
# compiler, once it knows the actual runtime type of both operands, can
# tell a stray boolean from a real number or string. So this file now
# PARSES cleanly (`otter check` accepts it) and is checked via `otter run`
# instead, which is where the real, specific diagnostic now lives.
$checkOutput = Invoke-OtterCliFixture -Arguments @('check', 'conformance\negative\boolean_operators_outside_conditions.ot')
if ($checkOutput -notmatch 'is valid') {
    throw "Expected 'and' outside a condition to remain valid GRAMMAR (real addition/concatenation syntax), got: $checkOutput"
}
$runOutput = Invoke-OtterCliFixture -Arguments @('run', 'conformance\negative\boolean_operators_outside_conditions.ot')
if ($runOutput -notmatch 'Boolean "and"/"or" only work inside an if or while condition') {
    throw "Expected a runtime boolean-and diagnostic for conformance\negative\boolean_operators_outside_conditions.ot, got: $runOutput"
}

# `or` has no legitimate use outside a condition (unlike `and`), so it
# remains a real, PARSE-time syntax error - `otter check` alone catches it.
$orCheckOutput = Invoke-OtterCliFixture -Arguments @('check', 'conformance\negative\or_outside_condition.ot')
if ($orCheckOutput -notmatch 'only works inside an if or while condition') {
    throw "Expected an 'or' condition-only syntax diagnostic for conformance\negative\or_outside_condition.ot, got: $orCheckOutput"
}

# The three real, shipped example programs that were silently broken by the
# earlier over-broad parser-level `and` rejection must parse cleanly again.
foreach ($regressedExample in @('examples\cli-app.ot', 'examples\studio.ot', 'examples\terminal.ot')) {
    $exampleOutput = Invoke-OtterCliFixture -Arguments @('check', $regressedExample)
    if ($exampleOutput -notmatch 'is valid') {
        throw "Expected $regressedExample (a real production example using 'and' for string concatenation outside a condition) to check as valid, got: $exampleOutput"
    }
}

$invalidFixtures = @(
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
