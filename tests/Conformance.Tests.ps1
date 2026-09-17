using module ..\Otter.Contract.psm1

# tests/Conformance.Tests.ps1
# Cross-Runtime Differential Conformance Test Suite (P1)
# Compares execution results between the PowerShell Interpreter and the JS Compiler (Node.js)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Lexer.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Parser.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Interpreter.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Compiler.JavaScript.psm1') -Force

Write-Output 'Otter Cross-Runtime Conformance & Parity (P1)'

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_conformance_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null

function Run-InterpreterWithStdout {
    param([string]$Source)
    $tokens = ConvertTo-OtterTokens -Source $Source
    $ast = ConvertTo-OtterAst -Tokens $tokens
    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($Text) $collected.Add([string]$Text) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer

    try {
        $env = New-OtterEnvironment
        Invoke-OtterProgram -Program $ast -Environment $env
    } finally {
        Set-OtterOutputWriter -Writer $null
    }
    return ($collected -join "`n").Trim()
}

function Run-NodeWithStdout {
    param([string]$Source)
    $tokens = ConvertTo-OtterTokens -Source $Source
    $ast = ConvertTo-OtterAst -Tokens $tokens

    # Compile statements to JS
    $jsLines = [System.Collections.Generic.List[string]]::new()
    $jsLines.Add('const window = globalThis;')
    $jsLines.Add('global.window = globalThis;')
    $jsLines.Add('    const fs = require("fs");
    const cp = require("child_process");
    const otterReadFile = async (p) => fs.readFileSync(p, "utf8");
    const otterWriteFile = async (p, c) => fs.writeFileSync(p, c, "utf8");
    const otterAppendFile = async (p, c) => fs.appendFileSync(p, c, "utf8");
    const otterDeleteFile = async (p) => fs.unlinkSync(p);
    const otterFileExists = async (p) => fs.existsSync(p);
    const otterRunCommand = async (cmd) => {
        const res = cp.spawnSync(cmd, { shell: true, encoding: "utf8" });
        return {
            __otterThing: true,
            typeName: "command result",
            props: {
                "output": (res.stdout || "").replace(/[\r\n]+$/, ""),
                "error output": (res.stderr || "").replace(/[\r\n]+$/, ""),
                "exit code": res.status !== null ? res.status : 0
            }
        };
    };')
    $jsLines.Add('const otterLog = console.log;')
    $jsLines.Add('const otterWarn = console.warn;')
    $jsLines.Add('const otterError = console.error;')
    $jsLines.Add('const otterSay = (...args) => console.log(args.join(" "));')
    $jsLines.Add('const otterGetElement = () => null;')
    $jsLines.Add('(async () => {')

    foreach ($stmt in $ast.Statements) {
        $compiled = ConvertTo-OtterJsStatement -Stmt $stmt -Indent 1
        $jsLines.Add($compiled)
    }
    $jsLines.Add('})();')

    $jsCode = $jsLines -join "`n"
    $tempJs = Join-Path $sandbox ("test_" + [System.Guid]::NewGuid().ToString('N') + ".js")
    [System.IO.File]::WriteAllText($tempJs, $jsCode, [System.Text.Encoding]::UTF8)

    # Route the stderr merge through cmd.exe's own redirection rather than
    # PowerShell's `2>&1` operator on a native executable - under this
    # script's `$ErrorActionPreference = 'Stop'`, PowerShell wraps each
    # stderr line from a native command in a terminating ErrorRecord (a
    # known, documented PowerShell 5.1 pitfall), which explodes this whole
    # function the first time Node actually throws instead of exiting 0.
    # Every test here before the V1 audit's error-case coverage happened to
    # only exercise Node's SUCCESS path, so this never surfaced until now.
    $nodeOut = cmd /c "node `"$tempJs`" 2>&1"
    return ($nodeOut -join "`n").Trim()
}

try {
    # 1. Arithmetic, Variables & Precedence Parity
    $mathSrc = @'
x is 10
y is 20
z is x plus y times 2
say z
'@
    $intOut = Run-InterpreterWithStdout -Source $mathSrc
    $nodeOut = Run-NodeWithStdout -Source $mathSrc
    if ($intOut -ne $nodeOut) {
        throw "Math parity failed. Interpreter: '$intOut', Node: '$nodeOut'"
    }
    Write-Output "  pass  arithmetic and operator precedence match across runtimes ($intOut)"

    # 2. Control Flow & Loops Parity
    $loopSrc = @'
total is 0
repeat 3 times
    total is total plus 1
.
say total
'@
    $intOut = Run-InterpreterWithStdout -Source $loopSrc
    $nodeOut = Run-NodeWithStdout -Source $loopSrc
    if ($intOut -ne $nodeOut) {
        throw "Loop parity failed. Interpreter: '$intOut', Node: '$nodeOut'"
    }
    Write-Output "  pass  loops and repeat blocks match across runtimes ($intOut)"

    # 3. Collection Iteration Parity
    $iterSrc = @'
items are
    "apple"
    "banana"
    "cherry"
.
for each x in items
    say x
.
'@
    $intOut = Run-InterpreterWithStdout -Source $iterSrc
    $nodeOut = Run-NodeWithStdout -Source $iterSrc
    if ($intOut -ne $nodeOut) {
        throw "For-each parity failed. Interpreter: '$intOut', Node: '$nodeOut'"
    }
    Write-Output "  pass  list iteration and string values match across runtimes"

    # 4. Functions & Calls Parity
    $fnSrc = @'
to addNumbers first and second
    return first plus second
.
addNumbers 15 and 25 make sum
say sum
'@
    $intOut = Run-InterpreterWithStdout -Source $fnSrc
    $nodeOut = Run-NodeWithStdout -Source $fnSrc
    if ($intOut -ne $nodeOut) {
        throw "Function call parity failed. Interpreter: '$intOut', Node: '$nodeOut'"
    }
    Write-Output "  pass  functions, parameters, and return values match across runtimes ($intOut)"

    # 4b. A function call is also a value expression.  This is deliberately
    # separate from legacy `... make result` coverage above.
    $functionExpressionSrc = @'
to double number
    return number times 2
.
answer is double 10
say answer
to combine first and second
    return first plus second
.
sum is combine 3 and 4
say sum
nested is double double 5
say nested
'@
    $intOut = Run-InterpreterWithStdout -Source $functionExpressionSrc
    $nodeOut = Run-NodeWithStdout -Source $functionExpressionSrc
    if ($intOut -ne "20`n7`n20" -or $nodeOut -ne "20`n7`n20" -or $intOut -ne $nodeOut) {
        throw "Function expression parity failed. Interpreter: '$intOut', Node: '$nodeOut'"
    }
    Write-Output "  pass  function return values work in expressions across runtimes ($intOut)"

    # 5. Objects & Property Access Parity
    $objSrc = @'
person has name is "Jeffrey", age is 35
say name of person
say age of person
'@
    $intOut = Run-InterpreterWithStdout -Source $objSrc
    $nodeOut = Run-NodeWithStdout -Source $objSrc
    if ($intOut -ne $nodeOut) {
        throw "Object property parity failed. Interpreter: '$intOut', Node: '$nodeOut'"
    }
    Write-Output "  pass  object creation and property access match across runtimes"

    # 6. JSON Serialization Parity
    $jsonSrc = @'
data has title is "Otter", stars is 100
convert data to json into jsonText
convert jsonText from json into restored
say title of restored
say stars of restored
'@
    $intOut = Run-InterpreterWithStdout -Source $jsonSrc
    $nodeOut = Run-NodeWithStdout -Source $jsonSrc
    if ($intOut -ne $nodeOut) {
        throw "JSON serialization round-trip parity failed. Interpreter: '$intOut', Node: '$nodeOut'"
    }
    Write-Output "  pass  JSON serialization and deserialization round-trip matches across runtimes"

    # 7. Date Operations Parity
    $dateSrc = @'
startDay is today
add 10 days to startDay
days between today and startDay make gap
say gap
'@
    $intOut = Run-InterpreterWithStdout -Source $dateSrc
    $nodeOut = Run-NodeWithStdout -Source $dateSrc
    if ($intOut -ne $nodeOut) {
        throw "Date operations parity failed. Interpreter: '$intOut', Node: '$nodeOut'"
    }
    Write-Output "  pass  date math, day additions, and date intervals match across runtimes ($intOut days)"

    # 8. Random Item & Bounded Range Parity
    $randSrc = @'
random number from 5 to 15 into num
if num is at least 5 and num is at most 15
    say "valid"
otherwise
    say "invalid"
.
'@
    $intOut = Run-InterpreterWithStdout -Source $randSrc
    $nodeOut = Run-NodeWithStdout -Source $randSrc
    if ($intOut -ne 'valid' -or $nodeOut -ne 'valid') {
        throw "Random range bounds failed. Interpreter: '$intOut', Node: '$nodeOut'"
    }
    Write-Output "  pass  random numbers respect range boundaries across both runtimes"

    # 9. File Existence & Lifecycle Parity
    $fileSrc = @'
write "sample content" to "conformance_test_file.txt"
if file "conformance_test_file.txt" exists
    say "created"
otherwise
    say "not found"
.
delete file "conformance_test_file.txt"
if file "conformance_test_file.txt" exists
    say "still here"
otherwise
    say "cleaned up"
.
'@
    $intOut = Run-InterpreterWithStdout -Source $fileSrc
    $nodeOut = Run-NodeWithStdout -Source $fileSrc
    if ($intOut -ne $nodeOut) {
        throw "File lifecycle parity failed. Interpreter: '$intOut', Node: '$nodeOut'"
    }
    Write-Output "  pass  file creation, existence checks, and deletion match across runtimes"

    # 10. Native Command Execution & Structured Result Parity (D65)
    $cmdSrc = @'
run command "cmd /c echo cross-platform-test" into cmdRes
say output of cmdRes
say exit code of cmdRes
'@
    $intOut = Run-InterpreterWithStdout -Source $cmdSrc
    $nodeOut = Run-NodeWithStdout -Source $cmdSrc
    if ($intOut -ne $nodeOut) {
        throw "Command execution parity failed. Interpreter: '$intOut', Node: '$nodeOut'"
    }
    Write-Output "  pass  run command, stdout capture, and exit code match across runtimes"

    # 11. V1 audit: `and`/`plus` parity - real addition/concatenation still
    # works outside a condition on BOTH runtimes (a real production pattern
    # - examples/terminal.ot concatenates text with `and` outside any
    # if/while), and a stray BOOLEAN operand gives the same specific,
    # honest diagnostic on both runtimes rather than a generic type error.
    $andAdditionSrc = @'
total is 5 and 3
say total
greeting is "Hello " and "World"
say greeting
'@
    $intOut = Run-InterpreterWithStdout -Source $andAdditionSrc
    $nodeOut = Run-NodeWithStdout -Source $andAdditionSrc
    if ($intOut -ne "8`nHello World" -or $nodeOut -ne "8`nHello World" -or $intOut -ne $nodeOut) {
        throw "and-as-addition parity failed. Interpreter: '$intOut', Node: '$nodeOut'"
    }
    Write-Output "  pass  `"and`" still adds numbers and concatenates strings outside a condition, on both runtimes"

    $booleanAndSrc = @'
ready is true
active is true
result is ready and active
say result
'@
    $intErrorMessage = $null
    try {
        Run-InterpreterWithStdout -Source $booleanAndSrc | Out-Null
    } catch {
        $intErrorMessage = $_.Exception.Message
    }
    $nodeOut = Run-NodeWithStdout -Source $booleanAndSrc
    $expectedPhrase = 'Boolean "and"/"or" only work inside an if or while condition'
    if ($null -eq $intErrorMessage -or $intErrorMessage -notmatch [regex]::Escape($expectedPhrase)) {
        throw "Expected the interpreter to reject a boolean 'and' outside a condition with the specific diagnostic, got: $intErrorMessage"
    }
    if ($nodeOut -notmatch [regex]::Escape($expectedPhrase)) {
        throw "Expected the JS compiler to reject a boolean 'and' outside a condition with the same diagnostic, got: $nodeOut"
    }
    Write-Output "  pass  a stray boolean reaching `"and`" outside a condition gives the same specific diagnostic on both runtimes"

    Write-Output "`nDifferential Conformance: All cross-runtime tests passed!"

} finally {
    if (Test-Path $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}
