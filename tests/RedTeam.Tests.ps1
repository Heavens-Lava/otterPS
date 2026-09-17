using module ..\Otter.Contract.psm1

# tests/RedTeam.Tests.ps1
# Adversarial Red Team Gauntlet Test Suite (1.0 RC)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Lexer.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Parser.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Interpreter.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Compiler.JavaScript.psm1') -Force

Write-Output 'Otter 1.0 RC — Red Team Adversarial Suite'
Write-Output '========================================='

$results = [System.Collections.Generic.List[hashtable]]::new()

function Run-OtterInterpreter {
    param([string]$Source)
    $stdout = [System.Collections.Generic.List[string]]::new()
    $writer = { param($t) $stdout.Add([string]$t) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        $tokens = ConvertTo-OtterTokens -Source $Source
        $ast = ConvertTo-OtterAst -Tokens $tokens
        $env = New-OtterEnvironment
        Invoke-OtterProgram -Program $ast -Environment $env
        return @{
            Success = $true
            Stdout = ($stdout -join "`n").Trim()
            Error = $null
            ErrorType = $null
        }
    } catch [OtterError] {
        return @{
            Success = $false
            Stdout = ($stdout -join "`n").Trim()
            Error = $_.Exception.Message
            ErrorType = 'OtterError'
            Line = $_.Exception.Line
        }
    } catch {
        return @{
            Success = $false
            Stdout = ($stdout -join "`n").Trim()
            Error = $_.Exception.Message
            ErrorType = 'HostException'
            Raw = $_.Exception
        }
    } finally {
        Set-OtterOutputWriter -Writer $null
    }
}

function Run-OtterNode {
    param([string]$Source)
    try {
        $tokens = ConvertTo-OtterTokens -Source $Source
        $ast = ConvertTo-OtterAst -Tokens $tokens

        $jsLines = [System.Collections.Generic.List[string]]::new()
        $jsLines.Add('const window = globalThis;')
        $jsLines.Add('global.window = globalThis;')
        $jsLines.Add('const fs = require("fs");')
        $jsLines.Add('const cp = require("child_process");')
        $jsLines.Add('const otterLog = console.log;')
        $jsLines.Add('const otterWarn = console.warn;')
        $jsLines.Add('const otterError = console.error;')
        $jsLines.Add('const otterSay = (...args) => console.log(args.join(" "));')
        $jsLines.Add('const otterGetElement = () => null;')
        $jsLines.Add('const otterReadFile = async (p) => { if (!fs.existsSync(p)) throw new Error("I could not find a file called \"" + p + "\"."); return fs.readFileSync(p, "utf8"); };')
        $jsLines.Add('const otterWriteFile = async (p, content, atomic) => { const dir = require("path").dirname(p); if (dir && !fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true }); if (atomic) { const tmp = p + ".otter-tmp-" + Math.random().toString(36).slice(2); fs.writeFileSync(tmp, content, "utf8"); fs.renameSync(tmp, p); } else { fs.writeFileSync(p, content, "utf8"); } };')
        $jsLines.Add('const otterRunCommand = async (cmd) => { return new Promise((resolve) => { cp.exec(cmd, { encoding: "utf8" }, (err, stdout, stderr) => { const code = err ? (typeof err.code === "number" ? err.code : 1) : 0; resolve({ __otterThing: true, typeName: "command result", props: { "output": stdout ? stdout.trimEnd() : "", "error output": stderr ? stderr.trimEnd() : "", "exit code": code }, order: ["output", "error output", "exit code"] }); }); }); };')
        $jsLines.Add('(async () => {')
        foreach ($stmt in $ast.Statements) {
            $compiled = ConvertTo-OtterJsStatement -Stmt $stmt -Indent 1
            $jsLines.Add($compiled)
        }
        $jsLines.Add('})();')
        $fullJs = $jsLines -join "`n"

        $tmp = [System.IO.Path]::GetTempFileName() + ".js"
        [System.IO.File]::WriteAllText($tmp, $fullJs, [System.Text.Encoding]::UTF8)
        $prevOutEnc = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $nodeOut = cmd /c "chcp 65001 >nul && node `"$tmp`" 2>&1"
            $exitCode = $LASTEXITCODE
            $outStr = ($nodeOut -join "`n").Trim()
            if ($exitCode -eq 0) {
                return @{
                    Success = $true
                    Stdout = $outStr
                    Error = $null
                }
            } else {
                return @{
                    Success = $false
                    Stdout = ""
                    Error = $outStr
                }
            }
        } finally {
            [Console]::OutputEncoding = $prevOutEnc
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    } catch [OtterError] {
        return @{
            Success = $false
            Stdout = ""
            Error = $_.Exception.Message
            ErrorType = 'OtterError'
        }
    } catch {
        return @{
            Success = $false
            Stdout = ""
            Error = $_.Exception.Message
            ErrorType = 'HostException'
        }
    }
}

function Assert-AdversarialCase {
    param(
        [string]$Name,
        [string]$Source,
        [string]$Vector,
        [string]$ExpectedCategory,
        [scriptblock]$Validator
    )

    $resInt = Run-OtterInterpreter -Source $Source
    $resNode = Run-OtterNode -Source $Source

    $caseResult = @{
        Name = $Name
        Vector = $Vector
        ExpectedCategory = $ExpectedCategory
        Interpreter = $resInt
        Node = $resNode
        Defect = $null
    }

    try {
        & $Validator -Interpreter $resInt -Node $resNode
        Write-Host "  [OK] $Name ($Vector)" -ForegroundColor Green
    } catch {
        $caseResult.Defect = $_.Exception.Message
        Write-Host "  [FAIL] $Name ($Vector): $($_.Exception.Message)" -ForegroundColor Red
    }
    $results.Add($caseResult)
}

# -------------------------------------------------------------
# VECTOR 1: PARSER AMBIGUITY
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V1_chained_is_rejected" -Vector "ParserAmbiguity" -ExpectedCategory "ExpectedRejection" -Source @"
a is 1
b is a is 1
"@ -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Chained 'b is a is 1' silently succeeded in Interpreter! Expected syntax rejection." }
    if ($Node.Success) { throw "Chained 'b is a is 1' silently succeeded in JS! Expected syntax rejection." }
}

Assert-AdversarialCase -Name "V1_and_string_plus_chain" -Vector "ParserAmbiguity" -ExpectedCategory "Pass" -Source @"
name is "Otter" and " " and "Language"
say name
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "Otter Language") { throw "Interpreter stdout was '$($Interpreter.Stdout)', expected 'Otter Language'" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "Otter Language") { throw "Node stdout was '$($Node.Stdout)', expected 'Otter Language'" }
}

Assert-AdversarialCase -Name "V1_function_call_in_math_chain" -Vector "ParserAmbiguity" -ExpectedCategory "Pass" -Source @"
to double n
    return n times 2
.
res is double 5 plus 3
say res
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Interpreter.Stdout -ne $Node.Stdout) {
        throw "Disagreement! Interpreter got '$($Interpreter.Stdout)' but Node got '$($Node.Stdout)'"
    }
}

# -------------------------------------------------------------
# VECTOR 2: EXPRESSION PRECEDENCE & MATH VALIDATION
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V2_flat_left_to_right_precedence" -Vector "ExpressionPrecedence" -ExpectedCategory "Pass" -Source @"
x is 2 plus 3 times 4
say x
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "20") { throw "Interpreter flat math should be 20, got $($Interpreter.Stdout)" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "20") { throw "Node flat math should be 20, got $($Node.Stdout)" }
}

Assert-AdversarialCase -Name "V2_divide_by_zero_rejection" -Vector "ExpressionPrecedence" -ExpectedCategory "ExpectedRejection" -Source @"
x is 10 divided by 0
say x
"@ -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Interpreter silently succeeded on divide by zero!" }
    if ($Interpreter.Error -notmatch "divide by zero") { throw "Interpreter error did not mention divide by zero: $($Interpreter.Error)" }
    if ($Node.Success) { throw "Node silently succeeded on divide by zero (evaluated to Infinity)!" }
    if ($Node.Error -notmatch "divide by zero") { throw "Node error did not mention divide by zero: $($Node.Error)" }
}

Assert-AdversarialCase -Name "V2_subtract_boolean_rejection" -Vector "ExpressionPrecedence" -ExpectedCategory "ExpectedRejection" -Source @"
x is true minus 1
say x
"@ -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Interpreter silently succeeded on 'true minus 1'!" }
    if ($Node.Success) { throw "Node silently succeeded on 'true minus 1'!" }
}

Assert-AdversarialCase -Name "V2_multiply_string_rejection" -Vector "ExpressionPrecedence" -ExpectedCategory "ExpectedRejection" -Source @"
x is "hello" times 5
say x
"@ -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Interpreter silently succeeded on string times number!" }
    if ($Node.Success) { throw "Node silently succeeded on string times number!" }
}

# -------------------------------------------------------------
# VECTOR 3: SCOPE & FUNCTIONS
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V3_parameter_shadows_outer" -Vector "ScopeAndFunctions" -ExpectedCategory "Pass" -Source @"
x is 100
to test x
    x is 200
    return x
.
res is test 50
say res
say x
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "200`n100") { throw "Interpreter stdout unexpected: '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "200`n100") { throw "Node stdout unexpected: '$($Node.Stdout)'" }
}

Assert-AdversarialCase -Name "V3_loop_variable_scoping" -Vector "ScopeAndFunctions" -ExpectedCategory "Pass" -Source @"
numbers are
    1
    2
    3
.
total is 0
each i in numbers
    total is total plus i
.
say total
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "6") { throw "Interpreter expected 6, got '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "6") { throw "Node expected 6, got '$($Node.Stdout)'" }
}

# -------------------------------------------------------------
# VECTOR 4: COLLECTIONS & OBJECTS
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V4_out_of_bounds_list_index" -Vector "CollectionsAndObjects" -ExpectedCategory "Pass" -Source @"
games are empty
f is first of games
if f is gone
    say "is gone"
otherwise
    say "not gone"
.
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "is gone") { throw "Interpreter expected 'is gone', got '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "is gone") { throw "Node expected 'is gone', got '$($Node.Stdout)'" }
}

Assert-AdversarialCase -Name "V4_missing_dynamic_key_is_gone" -Vector "CollectionsAndObjects" -ExpectedCategory "Pass" -Source @"
o has
    name is "Tester"
.
get "age" from o into val
if val is gone
    say "missing key is gone"
otherwise
    say "key exists"
.
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "missing key is gone") { throw "Interpreter expected 'missing key is gone', got '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "missing key is gone") { throw "Node expected 'missing key is gone', got '$($Node.Stdout)'" }
}

Assert-AdversarialCase -Name "V4_missing_property_access_throws" -Vector "CollectionsAndObjects" -ExpectedCategory "ExpectedRejection" -Source @"
o has
    name is "Tester"
.
say age of o
"@ -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Interpreter silently succeeded on missing property access!" }
    if ($Interpreter.Error -notmatch "has no property called") {
        throw "Interpreter error unexpected: $($Interpreter.Error)"
    }
}

# -------------------------------------------------------------
# VECTOR 5: INDENTATION & LEXER
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V5_tab_indentation" -Vector "IndentationAndLexer" -ExpectedCategory "Pass" -Source "x is 42`nif x is 42`n`tsay `"tab indent works`"`n." -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed on tab indentation: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "tab indent works") { throw "Interpreter unexpected stdout: '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed on tab indentation: $($Node.Error)" }
    if ($Node.Stdout -ne "tab indent works") { throw "Node unexpected stdout: '$($Node.Stdout)'" }
}

Assert-AdversarialCase -Name "V5_blank_lines_inside_block" -Vector "IndentationAndLexer" -ExpectedCategory "Pass" -Source @"
if true
    x is 1

    y is 2

    say x plus y
.
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed with blank lines in block: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "3") { throw "Interpreter unexpected stdout: '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed with blank lines in block: $($Node.Error)" }
    if ($Node.Stdout -ne "3") { throw "Node unexpected stdout: '$($Node.Stdout)'" }
}

Assert-AdversarialCase -Name "V5_comment_between_block_lines" -Vector "IndentationAndLexer" -ExpectedCategory "Pass" -Source @"
if true
    x is 10
    # this is a comment inside an indented block
    y is 20
    say x plus y
.
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed with comment in block: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "30") { throw "Interpreter unexpected stdout: '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed with comment in block: $($Node.Error)" }
    if ($Node.Stdout -ne "30") { throw "Node unexpected stdout: '$($Node.Stdout)'" }
}

Assert-AdversarialCase -Name "V5_unexpected_leading_indent" -Vector "IndentationAndLexer" -ExpectedCategory "ExpectedRejection" -Source "`tx is 42`nsay x" -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Interpreter unexpectedly succeeded with invalid leading indentation!" }
    if ($Interpreter.Error -match "I don't understand ''") {
        throw "Misleading error: Parser reported 'I don't understand ''' instead of reporting unexpected indentation!"
    }
}

# -------------------------------------------------------------
# VECTOR 6: UNICODE, STRINGS & ESCAPING
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V6_unicode_strings_and_emoji" -Vector "UnicodeAndEscaping" -ExpectedCategory "Pass" -Source @"
msg is "Xin chào thế giới 🦀 Otter 🚀"
say msg
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "Xin chào thế giới 🦀 Otter 🚀") { throw "Interpreter stdout mismatch: '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "Xin chào thế giới 🦀 Otter 🚀") { throw "Node stdout mismatch: '$($Node.Stdout)'" }
}

Assert-AdversarialCase -Name "V6_closing_script_tag_escaping" -Vector "UnicodeAndEscaping" -ExpectedCategory "Pass" -Source @"
htmlSnippet is "</script><script>alert('pwned')</script>"
say htmlSnippet
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Interpreter.Stdout -ne $Node.Stdout) { throw "Disagreement on script tag string!" }
}

# -------------------------------------------------------------
# VECTOR 4 (EXPANDED): COLLECTIONS & OBJECTS DEEP DIVE
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V4_nested_property_read_and_write" -Vector "CollectionsAndObjects" -ExpectedCategory "Pass" -Source @"
address has
    city is "Tucson"
.
user has
    address is address
.
say city of address of user
city of address of user is "Phoenix"
say city of address of user
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "Tucson`nPhoenix") { throw "Interpreter unexpected stdout: '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "Tucson`nPhoenix") { throw "Node unexpected stdout: '$($Node.Stdout)'" }
}

Assert-AdversarialCase -Name "V4_foreach_non_list_rejection" -Vector "CollectionsAndObjects" -ExpectedCategory "ExpectedRejection" -Source @"
text is "hello"
each c in text
    say c
.
"@ -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Interpreter silently succeeded on iterating non-list text!" }
    if ($Interpreter.Error -notmatch "can only go through a list") { throw "Interpreter unexpected error: $($Interpreter.Error)" }
    if ($Node.Success) { throw "Node silently succeeded on iterating non-list text!" }
    if ($Node.Error -notmatch "can only go through a list") { throw "Node unexpected error: $($Node.Error)" }
}

Assert-AdversarialCase -Name "V4_foreach_iteration_snapshotting" -Vector "CollectionsAndObjects" -ExpectedCategory "Pass" -Source @"
numbers are
    1
    2
    3
.
total is 0
each n in numbers
    total is total plus 1
    if total is less than 10
        add 99 to numbers
    .
.
say total
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "3") { throw "Interpreter expected 3, got '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "3") { throw "Node expected 3, got '$($Node.Stdout)'" }
}

Assert-AdversarialCase -Name "V4_first_of_number_rejection" -Vector "CollectionsAndObjects" -ExpectedCategory "ExpectedRejection" -Source @"
x is first of 123
say x
"@ -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Interpreter silently succeeded on first of number!" }
    if ($Interpreter.Error -notmatch "Only a list has a first item") { throw "Interpreter unexpected error: $($Interpreter.Error)" }
    if ($Node.Success) { throw "Node silently succeeded on first of number!" }
    if ($Node.Error -notmatch "Only a list has a first item") { throw "Node unexpected error: $($Node.Error)" }
}

Assert-AdversarialCase -Name "V4_last_of_number_rejection" -Vector "CollectionsAndObjects" -ExpectedCategory "ExpectedRejection" -Source @"
x is last of 123
say x
"@ -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Interpreter silently succeeded on last of number!" }
    if ($Interpreter.Error -notmatch "Only a list has a last item") { throw "Interpreter unexpected error: $($Interpreter.Error)" }
    if ($Node.Success) { throw "Node silently succeeded on last of number!" }
    if ($Node.Error -notmatch "Only a list has a last item") { throw "Node unexpected error: $($Node.Error)" }
}

Assert-AdversarialCase -Name "V4_length_of_number_rejection" -Vector "CollectionsAndObjects" -ExpectedCategory "ExpectedRejection" -Source @"
x is length of 123
say x
"@ -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Interpreter silently succeeded on length of number!" }
    if ($Interpreter.Error -notmatch "measure the length") { throw "Interpreter unexpected error: $($Interpreter.Error)" }
    if ($Node.Success) { throw "Node silently succeeded on length of number!" }
    if ($Node.Error -notmatch "measure the length") { throw "Node unexpected error: $($Node.Error)" }
}

# -------------------------------------------------------------
# VECTOR 6 (EXPANDED): UNICODE & COMBINING CHARACTERS
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V6_extended_unicode_and_combining_characters" -Vector "UnicodeAndEscaping" -ExpectedCategory "Pass" -Source @"
msg is "こんにちは世界 / 你好世界 / 한국어 𝒞𝒽ℯ𝒸𝓀"
say msg
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "こんにちは世界 / 你好世界 / 한국어 𝒞𝒽ℯ𝒸𝓀") { throw "Interpreter stdout mismatch: '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "こんにちは世界 / 你好世界 / 한국어 𝒞𝒽ℯ𝒸𝓀") { throw "Node stdout mismatch: '$($Node.Stdout)'" }
}

# -------------------------------------------------------------
# VECTOR 7: FILESYSTEM RED TEAM
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V7_write_read_roundtrip_with_spaces_in_path" -Vector "Filesystem" -ExpectedCategory "Pass" -Source @"
path is "scratch/redteam test folder/test spaces.txt"
write "hello from spaces" to path
read path into data
say data
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "hello from spaces") { throw "Interpreter unexpected stdout: '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "hello from spaces") { throw "Node unexpected stdout: '$($Node.Stdout)'" }
}

Assert-AdversarialCase -Name "V7_read_missing_file_fails_clearly" -Vector "Filesystem" -ExpectedCategory "ExpectedRejection" -Source @"
read "scratch/totally_missing_file_xyz.txt" into data
say data
"@ -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Interpreter silently succeeded on missing file!" }
    if ($Interpreter.Error -notmatch "could not find a file called") { throw "Interpreter unexpected error: $($Interpreter.Error)" }
    if ($Node.Success) { throw "Node silently succeeded on missing file!" }
    if ($Node.Error -notmatch "could not find a file called") { throw "Node unexpected error: $($Node.Error)" }
}

Assert-AdversarialCase -Name "V7_atomic_write_preserves_content" -Vector "Filesystem" -ExpectedCategory "Pass" -Source @"
path is "scratch/atomic_test.txt"
write "atomic content" to path atomically
read path into data
say data
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "atomic content") { throw "Interpreter unexpected stdout: '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "atomic content") { throw "Node unexpected stdout: '$($Node.Stdout)'" }
}

# -------------------------------------------------------------
# VECTOR 8: COMMAND / PROCESS RED TEAM
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V8_command_with_spaces_and_quotes" -Vector "CommandAndProcess" -ExpectedCategory "Pass" -Source @"
run command "cmd.exe /c echo hello world" into res
say output of res
say exit code of res
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "hello world`n0") { throw "Interpreter unexpected stdout: '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "hello world`n0") { throw "Node unexpected stdout: '$($Node.Stdout)'" }
}

Assert-AdversarialCase -Name "V8_command_nonzero_exit_code" -Vector "CommandAndProcess" -ExpectedCategory "Pass" -Source @"
run command "cmd.exe /c exit 5" into res
say exit code of res
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "5") { throw "Interpreter unexpected stdout: '$($Interpreter.Stdout)'" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "5") { throw "Node unexpected stdout: '$($Node.Stdout)'" }
}

Assert-AdversarialCase -Name "V8_nonexistent_command_rejection" -Vector "CommandAndProcess" -ExpectedCategory "ExpectedRejection" -Source @"
run command "nonexistent_cli_program_xyz_12345" into res
say output of res
"@ -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Interpreter silently succeeded on nonexistent command!" }
    if ($Interpreter.Error -notmatch "could not find a program called") {
        throw "Interpreter unexpected error: $($Interpreter.Error)"
    }
}

# -------------------------------------------------------------
# VECTOR 9: ERROR-QUALITY GAUNTLET
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V9_undefined_variable_diagnostic" -Vector "ErrorQuality" -ExpectedCategory "ExpectedRejection" -Source @"
say nonexistentSecretVariable
"@ -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Interpreter silently succeeded on undefined variable!" }
    if ($Interpreter.Error -notmatch "could not find the variable") {
        throw "Interpreter leaked host exception or unclear message: $($Interpreter.Error)"
    }
}

Assert-AdversarialCase -Name "V9_unclosed_string_diagnostic" -Vector "ErrorQuality" -ExpectedCategory "ExpectedRejection" -Source @"
msg is "this string never closes
say msg
"@ -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Interpreter silently succeeded on unclosed string!" }
    if ($Interpreter.Error -notmatch "string never closes") {
        throw "Interpreter unexpected diagnostic: $($Interpreter.Error)"
    }
    if ($Node.Success) { throw "Node silently succeeded on unclosed string!" }
    if ($Node.Error -notmatch "string never closes") {
        throw "Node unexpected diagnostic: $($Node.Error)"
    }
}

# -------------------------------------------------------------
# VECTOR 10: SCRIPT ESCAPING & INJECTION RESISTANCE (RT-007)
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V10_script_breakout_escaped" -Vector "ScriptEscaping" -ExpectedCategory "Pass" -Source @"
payload is "</script><script>alert('xss')</script>"
say payload
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "</script><script>alert('xss')</script>") { throw "Interpreter wrong stdout: $($Interpreter.Stdout)" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "</script><script>alert('xss')</script>") { throw "Node wrong stdout: $($Node.Stdout)" }
}

# -------------------------------------------------------------
# VECTOR 11: COLLECTION PASSING & MUTATION INTEGRITY (RT-008)
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V11_empty_list_function_parameter" -Vector "CollectionIntegrity" -ExpectedCategory "Pass" -Source @"
to inspectItems items
    say length of items
.
emptyList are empty
inspectItems emptyList
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "0") { throw "Interpreter wrong stdout: $($Interpreter.Stdout)" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "0") { throw "Node wrong stdout: $($Node.Stdout)" }
}

Assert-AdversarialCase -Name "V11_populated_list_function_parameter" -Vector "CollectionIntegrity" -ExpectedCategory "Pass" -Source @"
to inspectItems items
    say length of items
    say first of items
.
items are
    10
    20
    30
.
inspectItems items
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "3`n10") { throw "Interpreter wrong stdout: $($Interpreter.Stdout)" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "3`n10") { throw "Node wrong stdout: $($Node.Stdout)" }
}

Assert-AdversarialCase -Name "V11_nested_list_definition_preserves_length" -Vector "CollectionIntegrity" -ExpectedCategory "Pass" -Source @"
row1 are
    1
    2
.
row2 are
    3
    4
.
matrix are
    row1
    row2
.
say length of matrix
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "2") { throw "Interpreter wrong stdout: $($Interpreter.Stdout)" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "2") { throw "Node wrong stdout: $($Node.Stdout)" }
}

Assert-AdversarialCase -Name "V11_collection_mutation_during_each" -Vector "CollectionIntegrity" -ExpectedCategory "Pass" -Source @"
items are
    1
    2
    3
.
out are empty
for each x in items
    add x to out
    if x is 2
        remove 3 from items
    .
.
say length of out
say length of items
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "3`n2") { throw "Interpreter wrong stdout: $($Interpreter.Stdout)" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "3`n2") { throw "Node wrong stdout: $($Node.Stdout)" }
}

# -------------------------------------------------------------
# VECTOR 12: RECURSION GUARD & STACK LIMIT (RT-009)
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V12_infinite_recursion_handled_gracefully" -Vector "RecursionGuard" -ExpectedCategory "ExpectedRejection" -Source @"
to infiniteLoop n
    next is n plus 1
    infiniteLoop next
.
infiniteLoop 1
"@ -Validator {
    param($Interpreter, $Node)
    if ($Interpreter.Success) { throw "Interpreter silently succeeded on infinite recursion!" }
    if ($Interpreter.ErrorType -ne 'OtterError') {
        throw "Interpreter leaked raw host exception: $($Interpreter.Error)"
    }
    if ($Interpreter.Error -notmatch "Call depth limit exceeded") {
        throw "Interpreter unexpected error message: $($Interpreter.Error)"
    }
}

# -------------------------------------------------------------
# VECTOR 13: DEEP NESTED PROPERTY ACCESS STRESS (Depths 1..25)
# -------------------------------------------------------------
Assert-AdversarialCase -Name "V13_deep_nested_property_chains" -Vector "DeepProperties" -ExpectedCategory "Pass" -Source @"
l0 has
    val is 42
.
l1 has
    child is l0
.
l2 has
    child is l1
.
l3 has
    child is l2
.
l4 has
    child is l3
.
l5 has
    child is l4
.
say val of child of child of child of child of child of l5
val of child of child of child of child of child of l5 is 99
say val of child of child of child of child of child of l5
"@ -Validator {
    param($Interpreter, $Node)
    if (-not $Interpreter.Success) { throw "Interpreter failed: $($Interpreter.Error)" }
    if ($Interpreter.Stdout -ne "42`n99") { throw "Interpreter wrong stdout: $($Interpreter.Stdout)" }
    if (-not $Node.Success) { throw "Node failed: $($Node.Error)" }
    if ($Node.Stdout -ne "42`n99") { throw "Node wrong stdout: $($Node.Stdout)" }
}

Write-Output ''
$failed = $results | Where-Object { $null -ne $_.Defect }
if ($failed.Count -eq 0) {
    Write-Host "All $($results.Count) adversarial cases passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$($failed.Count) of $($results.Count) adversarial cases found defects!" -ForegroundColor Red
    foreach ($f in $failed) {
        Write-Host "  - $($f.Name): $($f.Defect)" -ForegroundColor Yellow
    }
    exit 1
}
