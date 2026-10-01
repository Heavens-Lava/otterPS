using module ..\Otter.Contract.psm1

# tools/Invoke-OtterDifferentialFuzzer.ps1
# Grammar-aware Differential Testing & Fuzzer for Otter 1.0 RC
# Scaled for 10,000+ Differential & 10,000+ Mutation Fuzzing Gauntlet

param(
    [int]$Seed = 20261010,
    [int]$Iterations = 10000,
    [int]$BatchSize = 250,
    [ValidateSet('All', 'Differential', 'MutationFuzz')][string]$Mode = 'All',
    [int]$SeedOffset = 0,
    # Experimental (Otter 1.1): also run every differential program through
    # the compiled backend (src/Otter.Compiler.Native.psm1) and compare it with
    # the interpreter. Off by default, so the 1.0 release gate is unchanged.
    [switch]$IncludeNative
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Lexer.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Parser.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Interpreter.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Compiler.JavaScript.psm1') -Force

if ($IncludeNative) {
    Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Compiler.Native.psm1') -Force
    $nativeCache = Join-Path ([System.IO.Path]::GetTempPath()) 'otter-native-cache'
    $nativeMatched = 0; $nativeNotCompiled = 0; $nativeDisagreements = 0
    $nativeReasons = @{}
}
$rand = [System.Random]::new($Seed)

# -------------------------------------------------------------
# GENERATOR: Multi-Feature Interactive Portable Core Programs
# -------------------------------------------------------------
function New-RandomInteractiveOtterProgram {
    param([int]$ProgramSeed)
    $r = [System.Random]::new($ProgramSeed)
    $lines = [System.Collections.Generic.List[string]]::new()

    # 1. Helper function with local math, condition, and return
    $fn1 = "calc" + $r.Next(100, 999)
    $lines.Add("to $fn1 num")
    $threshold = $r.Next(5, 25)
    $multiplier = $r.Next(2, 5)
    $adder = $r.Next(1, 10)
    $lines.Add("    if num is greater than $threshold")
    $lines.Add("        return num times $multiplier")
    $lines.Add("    otherwise")
    $lines.Add("        return num plus $adder")
    $lines.Add("    .")
    $lines.Add(".")

    # 2. Nested function call
    $fn2 = "pipeline" + $r.Next(100, 999)
    $lines.Add("to $fn2 val")
    $lines.Add("    mid is $fn1 val")
    $lines.Add("    return mid plus 1")
    $lines.Add(".")

    # 3. Dynamic objects and nested property chains
    $lines.Add("leaf has")
    $lines.Add("    score is " + $r.Next(1, 30))
    $lines.Add("    label is `"leafVal`"")
    $lines.Add(".")
    $lines.Add("branch has")
    $lines.Add("    child is leaf")
    $lines.Add("    city is `"Denver`"")
    $lines.Add(".")
    $lines.Add("root has")
    $lines.Add("    nxt is branch")
    $lines.Add(".")

    # 4. Property access & nested function execution
    $lines.Add("sc is score of child of nxt of root")
    $lines.Add("computed is $fn2 sc")
    $lines.Add("say computed")

    # 5. Dynamic key access
    $lines.Add("get `"city`" from branch into foundCity")
    $lines.Add("say foundCity")

    # 6. List definitions, nested lists, and list mutations
    $lines.Add("nums are")
    $lines.Add("    " + $r.Next(1, 10))
    $lines.Add("    " + $r.Next(11, 20))
    $lines.Add("    " + $r.Next(21, 30))
    $lines.Add(".")
    $lines.Add("add 99 to nums")
    $lines.Add("remove 99 from nums")
    
    # 7. for each loop with accumulator
    $lines.Add("sum is 0")
    $lines.Add("for each item in nums")
    $lines.Add("    sum is sum plus item")
    $lines.Add(".")
    $lines.Add("say sum")

    # 8. List functions (first of, last of, length of)
    $lines.Add("firstN is first of nums")
    $lines.Add("lastN is last of nums")
    $lines.Add("lenN is length of nums")
    $lines.Add("say firstN lastN lenN")

    # 9. Count loop with conditional comparison
    $loopLimit = $r.Next(3, 7)
    $lines.Add("accum is 0")
    $lines.Add("count from 1 to $loopLimit as step")
    $lines.Add("    if step is at least 2")
    $lines.Add("        accum is accum plus step")
    $lines.Add("    .")
    $lines.Add(".")
    $lines.Add("say accum")

    # 10. String operations and gone checks
    $lines.Add("greeting is `"hello`"")
    $lines.Add("greetingLen is length of greeting")
    $lines.Add("say greetingLen")
    $lines.Add("gVal is gone")
    $lines.Add("if gVal is gone")
    $lines.Add("    say `"is_gone`"")
    $lines.Add(".")

    return ($lines -join "`n")
}

# -------------------------------------------------------------
# MUTATOR: 13-Class Grammar-Aware Adversarial Mutation Suite
# -------------------------------------------------------------
function Mutate-OtterGrammarAware {
    param([string]$Source, [int]$MutationSeed)
    $r = [System.Random]::new($MutationSeed)
    $srcLines = $Source -split "`n"
    if ($srcLines.Length -eq 0) { return "say `"empty`"" }
    $lineIdx = $r.Next($srcLines.Length)
    $line = $srcLines[$lineIdx]

    $mutationClass = $r.Next(14)
    switch ($mutationClass) {
        0 { # 1. Token deletion
            $words = $line.Split(' ')
            if ($words.Length -gt 1) {
                $dropIdx = $r.Next($words.Length)
                $words = $words[0..($dropIdx - 1)] + $words[($dropIdx + 1)..($words.Length - 1)]
                $srcLines[$lineIdx] = ($words -join ' ')
            }
        }
        1 { # 2. Token duplication
            $words = $line.Split(' ')
            if ($words.Length -gt 0) {
                $dupIdx = $r.Next($words.Length)
                $words[$dupIdx] = "$($words[$dupIdx]) $($words[$dupIdx])"
                $srcLines[$lineIdx] = ($words -join ' ')
            }
        }
        2 { # 3. Operator substitution
            $srcLines[$lineIdx] = $line -replace ' plus ', ' times ' -replace ' is ', ' = '
        }
        3 { # 4. Keyword substitution
            $srcLines[$lineIdx] = $line -replace '^(\s*)if ', '$1while ' -replace '^(\s*)to ', '$1fn '
        }
        4 { # 5. Block terminator removal / addition
            if ($line.Trim() -eq '.') {
                $srcLines[$lineIdx] = '# dropped period'
            } else {
                $srcLines[$lineIdx] = "$line`n."
            }
        }
        5 { # 6. Indentation mutation (irregular spaces/tabs)
            $badIndent = switch ($r.Next(3)) {
                0 { "   " }    # 3 spaces
                1 { "     " }  # 5 spaces
                default { "`t  " } # mixed tab and spaces
            }
            $srcLines[$lineIdx] = $badIndent + $line.TrimStart()
        }
        6 { # 7. Malformed strings (unclosed quotes, bad escapes)
            $srcLines[$lineIdx] = $line + ' "unclosed string'
        }
        7 { # 8. Malformed numbers
            $srcLines[$lineIdx] = $line -replace '\b\d+\b', '1.2.3'
        }
        8 { # 9. Malformed property chains
            $srcLines[$lineIdx] = $line -replace ' of ', ' of of '
        }
        9 { # 10. Malformed function calls (missing args, extra tokens)
            $srcLines[$lineIdx] = $line + ' extraArg1 extraArg2'
        }
        10 { # 11. Malformed object/list blocks (bare words inside)
            $srcLines[$lineIdx] = "    bareWordWithoutProperty"
        }
        11 { # 12. CRLF/LF variation
            $Source = $Source -replace "`r`n", "`n"
            return ($Source -replace "`n", "`r`n")
        }
        12 { # 13. Comments at structural boundaries
            $srcLines[$lineIdx] = $line -replace ' is ', ' # boundary comment `n is '
        }
        13 { # 14. Unicode text in comments
            $srcLines[$lineIdx] = $line + ' # Unicode comment test'
        }
    }
    return ($srcLines -join "`n")
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Otter 1.0 RC Scaled Adversarial Gauntlet (Batch 3)" -ForegroundColor Cyan
Write-Host "Seed: $Seed | Iterations: $Iterations | Mode: $Mode" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$issues = [System.Collections.Generic.List[hashtable]]::new()

# =============================================================
# PART 1: 10,000 SEEDED DIFFERENTIAL RUNS
# =============================================================
if ($Mode -in @('All', 'Differential')) {
    Write-Host "`nRunning $Iterations Seeded Feature-Interaction Differential Programs..." -ForegroundColor Yellow
    $diffPassed = 0
    $diffDisagreements = 0

    $batchCount = [int][Math]::Ceiling($Iterations / $BatchSize)
    $totalEvaluated = 0

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $stdoutBuffer = [System.Collections.Generic.List[string]]::new()
    Set-OtterOutputWriter -Writer { param($m) $stdoutBuffer.Add($m) }.GetNewClosure()

    try {
        for ($b = 0; $b -lt $batchCount; $b++) {
            $curBatchSize = [Math]::Min($BatchSize, ($Iterations - $totalEvaluated))
            $batchPrograms = [System.Collections.Generic.List[hashtable]]::new()

            for ($i = 0; $i -lt $curBatchSize; $i++) {
                $progSeed = $Seed + $SeedOffset + $totalEvaluated + $i
                $src = New-RandomInteractiveOtterProgram -ProgramSeed $progSeed
                
                # In-process Interpreter run
                $stdoutBuffer.Clear()
                $intOut = ""
                $intSuccess = $true
                $intAst = $null
                try {
                    $t = ConvertTo-OtterTokens -Source $src
                    $intAst = ConvertTo-OtterAst -Tokens $t
                    $env = New-OtterEnvironment
                    Invoke-OtterProgram -Program $intAst -Environment $env
                    $intOut = ($stdoutBuffer -join "`n").Trim()
                } catch {
                    $intSuccess = $false
                    $intOut = $_.Exception.Message
                }

                # The compiled backend, against the interpreter (experimental).
                if ($IncludeNative -and $intAst) {
                    $nativeLines = [System.Collections.Generic.List[string]]::new()
                    $nativeSuccess = $true
                    $nativeOut = ''
                    $compiled = $null
                    try { $compiled = New-OtterNativeProgram -Program $intAst -SourceText $src -CacheDirectory $nativeCache }
                    catch {
                        $nativeNotCompiled++
                        $reason = $_.Exception.Message -replace ' \(line \d+\)', '' -replace '\. Run this program with otter run\.', ''
                        $nativeReasons[$reason] = 1 + [int]$nativeReasons[$reason]
                    }
                    if ($compiled) {
                        try {
                            Invoke-OtterNativeProgram -Compiled $compiled -Writer { param($m) $nativeLines.Add($m) }.GetNewClosure()
                            $nativeOut = ($nativeLines -join "`n").Trim()
                        } catch {
                            $nativeSuccess = $false
                            $nativeOut = $_.Exception.Message
                        }
                        if ($nativeSuccess -eq $intSuccess -and $nativeOut -ceq $intOut) { $nativeMatched++ }
                        else {
                            $nativeDisagreements++
                            $issues.Add(@{
                                Category = 'NATIVE_DISAGREEMENT'
                                Seed = $progSeed
                                Source = $src
                                InterpreterOut = $intOut
                                NativeOut = $nativeOut
                            })
                        }
                    }
                }

                $batchPrograms.Add(@{
                    Seed = $progSeed
                    Source = $src
                    Ast = $intAst
                    IntOut = $intOut
                    IntSuccess = $intSuccess
                })
            }

        # Build batched Node JS runner with vm.runInNewContext
        $jsLines = [System.Collections.Generic.List[string]]::new()
        $jsLines.Add('const fs = require("fs");')
        $jsLines.Add('const vm = require("vm");')
        $jsLines.Add('const results = [];')
        $jsLines.Add('const tests = [')
        foreach ($bp in $batchPrograms) {
            $codeLines = [System.Collections.Generic.List[string]]::new()
            if ($bp.Ast) {
                foreach ($stmt in $bp.Ast.Statements) {
                    $codeLines.Add((ConvertTo-OtterJsStatement -Stmt $stmt -Indent 0))
                }
            }
            $escapedCode = ($codeLines -join "`n")
            $jsonCode = ConvertTo-Json -InputObject $escapedCode
            $jsLines.Add("  $jsonCode,")
        }
        $jsLines.Add('];')

        $jsLines.Add(@'
for (let i = 0; i < tests.length; i++) {
  const output = [];
  const sandbox = {
    output: output,
    otterSay: (...args) => output.push(args.join(' ')),
    otterGetElement: () => null,
    console: console,
    Math: Math,
    Date: Date,
    String: String,
    Number: Number,
    Boolean: Boolean,
    Array: Array,
    Object: Object
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  sandbox.global = sandbox;
  try {
    vm.runInNewContext(tests[i], sandbox);
    results.push({ success: true, stdout: output.join('\n').trim() });
  } catch(e) {
    results.push({ success: false, error: e.message });
  }
}
fs.writeFileSync(process.argv[2], JSON.stringify(results));
'@)

        $tmpJs = [System.IO.Path]::GetTempFileName() + '.js'
        $tmpOut = [System.IO.Path]::GetTempFileName() + '.json'
        [System.IO.File]::WriteAllText($tmpJs, ($jsLines -join "`n"), [System.Text.Encoding]::UTF8)

        try {
            node $tmpJs $tmpOut
            $jsonRaw = [System.IO.File]::ReadAllText($tmpOut, [System.Text.Encoding]::UTF8)
            $nodeResults = ConvertFrom-Json $jsonRaw

            for ($i = 0; $i -lt $curBatchSize; $i++) {
                $bp = $batchPrograms[$i]
                $nr = $nodeResults[$i]

                if ($bp.IntSuccess -and $nr.success -and ($bp.IntOut -eq $nr.stdout)) {
                    $diffPassed++
                } else {
                    $diffDisagreements++
                    $issues.Add(@{
                        Category = 'DIFFERENTIAL_DISAGREEMENT'
                        Seed = $bp.Seed
                        Source = $bp.Source
                        InterpreterOut = $bp.IntOut
                        NodeOut = $(if ($nr.success) { $nr.stdout } else { $nr.error })
                    })
                }
            }
        } finally {
            Remove-Item $tmpJs -Force -ErrorAction SilentlyContinue
            Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
        }

        $totalEvaluated += $curBatchSize
        if ($totalEvaluated % 1000 -eq 0 -or $totalEvaluated -eq $Iterations) {
            Write-Host "  Differential progress: $totalEvaluated / $Iterations ($diffPassed passed, $diffDisagreements disagreements)" -ForegroundColor Cyan
        }
    }
} finally {
    Set-OtterOutputWriter -Writer $null
}
    $sw.Stop()
    if ($IncludeNative) {
        Write-Host "Compiled backend (experimental): $nativeMatched matched the interpreter, $nativeDisagreements disagreed, $nativeNotCompiled not compiled." -ForegroundColor $(if ($nativeDisagreements -eq 0) { 'Green' } else { 'Red' })
        foreach ($r in ($nativeReasons.GetEnumerator() | Sort-Object Value -Descending)) { Write-Host ("  not compiled x{0}: {1}" -f $r.Value, $r.Key) }
    }
    Write-Host "Completed $Iterations Differential Runs in $($sw.Elapsed.TotalSeconds.ToString('F1'))s ($diffPassed passed, $diffDisagreements disagreements)." -ForegroundColor $(if ($diffDisagreements -eq 0) { 'Green' } else { 'Red' })
}

# =============================================================
# PART 2: 10,000 SEEDED GRAMMAR-AWARE MUTATION FUZZ RUNS
# =============================================================
if ($Mode -in @('All', 'MutationFuzz')) {
    Write-Host "`nRunning $Iterations Seeded Grammar-Aware Mutation Fuzzing Runs..." -ForegroundColor Yellow
    $fuzzHandledSafely = 0
    $fuzzRawCrashes = 0
    $swFuzz = [System.Diagnostics.Stopwatch]::StartNew()
    $maxSteps = 1000
    $script:FuzzStepCount = 0
    Set-OtterStatementHook -Hook {
        param($Statement, $Environment, $CallStack)
        $script:FuzzStepCount++
        if ($script:FuzzStepCount -gt 1000) {
            throw [OtterError]::new('Execution step limit exceeded in fuzzer (infinite loop guard).', $Statement.Line, 'runtime', 0, $null, 'Ensure loops terminate.')
        }
    }.GetNewClosure()

    Set-OtterOutputWriter -Writer { param($m) }.GetNewClosure()
    try {
        for ($i = 1; $i -le $Iterations; $i++) {
            $baseSeed = $Seed + $SeedOffset + $i
            $baseSrc = New-RandomInteractiveOtterProgram -ProgramSeed $baseSeed
            $mutatedSrc = Mutate-OtterGrammarAware -Source $baseSrc -MutationSeed ($baseSeed * 7 + 13)

            $script:FuzzStepCount = 0
            try {
                $tokens = ConvertTo-OtterTokens -Source $mutatedSrc
                $ast = ConvertTo-OtterAst -Tokens $tokens
                $env = New-OtterEnvironment
                $null = Invoke-OtterProgram -Program $ast -Environment $env
                $fuzzHandledSafely++
            } catch [OtterError] {
                # Controlled Otter diagnostic: expected and safe!
                $fuzzHandledSafely++
            } catch {
                # Raw .NET / PowerShell exception escaped: CRITICAL DEFECT!
                $fuzzRawCrashes++
                $issues.Add(@{
                    Category = 'RAW_HOST_EXCEPTION_ESCAPE'
                    Iteration = $i
                    Seed = $baseSeed
                    Source = $mutatedSrc
                    ExceptionType = $_.Exception.GetType().FullName
                    ExceptionMessage = $_.Exception.Message
                })
            }

            if ($i % 1000 -eq 0 -or $i -eq $Iterations) {
                Write-Host "  Mutation Fuzz progress: $i / $Iterations ($fuzzHandledSafely safe, $fuzzRawCrashes raw crashes)" -ForegroundColor Cyan
            }
        }
    } finally {
        Set-OtterStatementHook -Hook $null
        Set-OtterOutputWriter -Writer $null
    }
    $swFuzz.Stop()
    Write-Host "Completed $Iterations Mutation Fuzzing Runs in $($swFuzz.Elapsed.TotalSeconds.ToString('F1'))s ($fuzzHandledSafely safe, $fuzzRawCrashes raw crashes)." -ForegroundColor $(if ($fuzzRawCrashes -eq 0) { 'Green' } else { 'Red' })
}

# =============================================================
# FINAL VERIFICATION & REPORT
# =============================================================
Write-Host "`n===================================================="
if ($issues.Count -eq 0) {
    $summary = @()
    if ($Mode -in @('All', 'Differential')) {
        $summary += "$diffPassed of $Iterations differential programs agreed ($diffDisagreements disagreements)"
    }
    if ($Mode -in @('All', 'MutationFuzz')) {
        $summary += "$fuzzHandledSafely of $Iterations mutations handled safely ($fuzzRawCrashes raw host crashes)"
    }
    Write-Host "GAUNTLET PASSED: $($summary -join '; ')." -ForegroundColor Green
    exit 0
} else {
    Write-Host "DEFECTS IDENTIFIED: $($issues.Count)" -ForegroundColor Red
    foreach ($issue in $issues | Select-Object -First 10) {
        Write-Host "  - [$($issue.Category)] Seed: $($issue.Seed) | Error: $($issue.ExceptionMessage)$($issue.InterpreterOut)" -ForegroundColor Yellow
    }
    exit 1
}
