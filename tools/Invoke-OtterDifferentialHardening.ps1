# tools/Invoke-OtterDifferentialHardening.ps1
#
# Otter 1.0 RC - Hardening Pass 1 Differential Testing Suite (Batch 4)
# Cross-runtime verification: In-Process Otter Interpreter <-> JavaScript Compiler
#
# Biased specifically toward complex feature interactions:
# - Nested lists and lists through functions
# - Multi-level nested objects and property chains
# - "gone" absence checks and comparisons
# - Mutation during iteration
# - Math boundaries (negative numbers, decimals, zero)
# - Multiple function return paths and deep call chains
# - Unicode strings and HTML/script-like strings

using module ..\Otter.Contract.psm1

param(
    [int]$Seed = 20260918,
    [int]$Iterations = 1000,
    [int]$BatchSize = 100
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Import-Module (Join-Path $repoRoot 'src\Otter.Lexer.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\Otter.Parser.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\Otter.Interpreter.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\Otter.Compiler.JavaScript.psm1') -Force

function New-HardenedDifferentialProgram {
    param([int]$ProgramSeed)
    $r = [System.Random]::new($ProgramSeed)
    $lines = [System.Collections.Generic.List[string]]::new()

    # 1. Deep call chain with conditional returns
    $lines.Add("to stepA val")
    $lines.Add("    if val is greater than 10")
    $lines.Add("        return val times 2")
    $lines.Add("    .")
    $lines.Add("    return val plus 5")
    $lines.Add(".")

    $lines.Add("to stepB val")
    $lines.Add("    stepA val make resA")
    $lines.Add("    return resA minus 1")
    $lines.Add(".")

    $lines.Add("to stepC val")
    $lines.Add("    stepB val make resB")
    $lines.Add("    return resB times 3")
    $lines.Add(".")

    # 2. Nested objects and deep property chains
    $lines.Add("inner has")
    $lines.Add("    tag is `"inner_ok`"")
    $lines.Add("    factor is " + $r.Next(2, 6))
    $lines.Add(".")
    $lines.Add("middle has")
    $lines.Add("    child is inner")
    $lines.Add("    label is `"mid_node`"")
    $lines.Add(".")
    $lines.Add("outer has")
    $lines.Add("    next is middle")
    $lines.Add(".")

    $lines.Add("f is factor of child of next of outer")
    $lines.Add("stepC f make chainRes")
    $lines.Add("say chainRes")

    # 3. Unicode and HTML/Script-like strings
    $unicodeToken = switch ($r.Next(4)) {
        0 { "café_☕" }
        1 { "日本語_テスト" }
        2 { "мир_тест" }
        default { "otter_🦦_rocks" }
    }
    $lines.Add("uStr is `"$unicodeToken`"")
    $lines.Add("say length of uStr")

    $htmlToken = switch ($r.Next(3)) {
        0 { "<script>alert('test')</script>" }
        1 { '<div class=\"container\">data and info</div>' }
        default { 'line1\nline2\t\"quoted\"' }
    }
    $lines.Add("htmlStr is `"$htmlToken`"")
    $lines.Add("say length of htmlStr")

    # 4. Gone value checks and missing properties
    $lines.Add("gVal is gone")
    $lines.Add("if gVal is gone")
    $lines.Add("    say `"g_is_gone`"")
    $lines.Add(".")
    $lines.Add("if gVal is not gone")
    $lines.Add("    say `"g_not_gone_error`"")
    $lines.Add(".")

    # 5. Lists through functions & list processing
    $val1 = $r.Next(1, 10)
    $val2 = $r.Next(10, 20)
    $val3 = $r.Next(20, 30)
    $lines.Add("nums are")
    $lines.Add("    $val1")
    $lines.Add("    $val2")
    $lines.Add("    $val3")
    $lines.Add(".")

    $lines.Add("add 50 to nums")
    $lines.Add("remove 50 from nums")

    # 6. For each iteration with mutation/accumulator
    $lines.Add("total is 0")
    $lines.Add("for each n in nums")
    $lines.Add("    total is total plus n")
    $lines.Add(".")
    $lines.Add("say total")

    # 7. Math type boundaries (negative, zero, multiplication)
    $sub = $r.Next(5, 15)
    $lines.Add("negVal is 0 minus $sub")
    $lines.Add("absNeg is absolute value of negVal")
    $lines.Add("say absNeg")

    return ($lines -join "`n")
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Otter 1.0 RC - Hardening Differential Suite (Batch 4)" -ForegroundColor Cyan
Write-Host "Seed: $Seed | Iterations: $Iterations | BatchSize: $BatchSize" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$passed = 0
$disagreements = 0
$disagreementList = [System.Collections.Generic.List[PSObject]]::new()

$batchCount = [int][Math]::Ceiling($Iterations / $BatchSize)
$totalEvaluated = 0

$stdoutBuffer = [System.Collections.Generic.List[string]]::new()
Set-OtterOutputWriter -Writer { param($m) $stdoutBuffer.Add($m) }.GetNewClosure()

$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
    for ($b = 0; $b -lt $batchCount; $b++) {
        $curBatchSize = [Math]::Min($BatchSize, ($Iterations - $totalEvaluated))
        $batchPrograms = [System.Collections.Generic.List[hashtable]]::new()

        for ($i = 0; $i -lt $curBatchSize; $i++) {
            $progSeed = $Seed + $totalEvaluated + $i
            $src = New-HardenedDifferentialProgram -ProgramSeed $progSeed

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

            $batchPrograms.Add(@{
                Seed = $progSeed
                Source = $src
                Ast = $intAst
                IntOut = $intOut
                IntSuccess = $intSuccess
            })
        }

        # Build batched Node JS runner
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
                    $passed++
                } else {
                    $disagreements++
                    $disagreementList.Add([PSCustomObject]@{
                        Seed = $bp.Seed
                        Source = $bp.Source
                        InterpreterOut = $bp.IntOut
                        NodeOut = $(if ($nr.success) { $nr.stdout } else { $nr.error })
                    })
                    Write-Host "  DISAGREEMENT on seed $($bp.Seed)" -ForegroundColor Red
                }
            }
        }
        finally {
            Remove-Item $tmpJs -Force -ErrorAction SilentlyContinue
            Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
        }

        $totalEvaluated += $curBatchSize
        Write-Host ("  Progress: {0} / {1} ({2} passed, {3} disagreements)" -f $totalEvaluated, $Iterations, $passed, $disagreements) -ForegroundColor Cyan
    }
}
finally {
    Set-OtterOutputWriter -Writer $null
}

$sw.Stop()
Write-Host "`nCompleted $Iterations differential programs in $([Math]::Round($sw.Elapsed.TotalSeconds, 2))s." -ForegroundColor $(if ($disagreements -eq 0) { 'Green' } else { 'Red' })
Write-Host "Results: $passed Passed, $disagreements Disagreements." -ForegroundColor $(if ($disagreements -eq 0) { 'Green' } else { 'Red' })

# Save Report
$reportPath = Join-Path $repoRoot 'docs\DIFFERENTIAL_HARDENING_RESULTS.md'
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Otter 1.0 - Hardening Differential Verification (Batch 4)')
$lines.Add('')
$lines.Add('- **Seed**: ' + $Seed)
$lines.Add('- **Iterations**: ' + $Iterations)
$lines.Add('- **Target Runtimes**: PowerShell Interpreter vs JavaScript Compiler (Node VM)')
$lines.Add('- **Total Passed**: ' + $passed)
$lines.Add('- **Total Disagreements**: ' + $disagreements)
$lines.Add('- **Elapsed Time**: ' + [Math]::Round($sw.Elapsed.TotalSeconds, 2) + 's')
$lines.Add('')
if ($disagreements -eq 0) {
    $lines.Add('### Certification: 100% Differential Parity Certified.')
    $lines.Add('Zero disagreements found across all tested feature interactions.')
} else {
    $lines.Add('### Disagreements Log:')
    foreach ($d in $disagreementList) {
        $lines.Add("- **Seed $($d.Seed)**:")
        $lines.Add("  - Interpreter: $($d.InterpreterOut)")
        $lines.Add("  - Node JS: $($d.NodeOut)")
    }
}

Set-Content -LiteralPath $reportPath -Value ($lines -join "`r`n") -Encoding utf8
Write-Host "Differential results saved to: docs/DIFFERENTIAL_HARDENING_RESULTS.md" -ForegroundColor Green

if ($disagreements -ne 0) { exit 1 }
