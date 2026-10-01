using module ..\Otter.Contract.psm1
using module .\Otter.LoopPasses.psm1

# Otter.Compiler.Native.psm1 - EXPERIMENTAL compiled backend (Otter 1.1 track).
#
# Lowers an Otter AST to C# 5 that runs against src/native/OtterNativeRuntime.cs,
# and compiles both with Add-Type - nothing beyond PowerShell is needed (the
# hybrid prerequisite model and the C# 5 ceiling, decided 2026-09-30; see
# docs/OTTER_NATIVE_COMPILER_DESIGN.md).
#
# The interpreter is the reference: generated code reproduces its evaluation
# order, scoping (one environment chain, functions rooted at the global scope)
# and messages through the runtime library. Anything outside the supported
# subset is refused at compile time, by name and line - never run partly.
#
# Not reachable from otter.ps1: the experiment runner
# experiments/native-compiler/Invoke-OtterCompiled.ps1 is the entry point
# until the 1.1 CLI decision.

$script:NativeRuntimePath = Join-Path $PSScriptRoot 'native\OtterNativeRuntime.cs'

# Kinds the compiler handles only in part, for the generated coverage list
# (tools/New-OtterNativeCoverage.ps1). Every other handled kind is complete.
$script:NativePartialKinds = [ordered]@{
    Say          = 'without "in color"'
    Assign       = 'to a variable or a property of a thing'
    OfOperation  = 'every operation except elapsed time'
}

function Get-OtterNativePartialKinds { return $script:NativePartialKinds }

# One C# string literal; every character outside printable ASCII is escaped,
# so Otter text can never break out of the literal (generated-code injection).
function ConvertTo-OtterCSharpString {
    param([string]$Text)
    $sb = [System.Text.StringBuilder]::new('"')
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        if ($ch -eq '"') { [void]$sb.Append('\"') }
        elseif ($ch -eq '\') { [void]$sb.Append('\\') }
        elseif ($code -ge 32 -and $code -le 126) { [void]$sb.Append($ch) }
        else { [void]$sb.Append('\u').Append($code.ToString('x4')) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function New-OtterNativeUnsupported {
    param([Node]$Node, [string]$What)
    $label = if ($What) { $What } else { $Node.Kind.ToString() }
    return [OtterError]::new("The compiled backend does not support $label yet (line $($Node.Line)). Run this program with otter run.", $Node.Line, 'runtime')
}

# Compilation state for one program.
class OtterNativeContext {
    [System.Collections.Generic.List[string]]$Methods = [System.Collections.Generic.List[string]]::new()
    [int]$Counter = 0
    [hashtable]$PassNames = @{}
    [string] Next([string]$prefix) { $this.Counter++; return "$prefix$($this.Counter)" }
}

function ConvertTo-OtterNativeExpression {
    param([Node]$Expr, [OtterNativeContext]$Context)
    $line = $Expr.Line
    switch ($Expr.Kind.ToString()) {
        'Literal' {
            $v = $Expr.Value
            if ($null -eq $v) { return 'null' }
            if ($v -is [bool]) { return $(if ($v) { '(object)true' } else { '(object)false' }) }
            if ($v -is [double] -or $v -is [int] -or $v -is [long] -or $v -is [decimal]) {
                $d = [double]$v
                if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { throw (New-OtterNativeUnsupported -Node $Expr -What 'this number') }
                return '(object)(' + $d.ToString('R', [System.Globalization.CultureInfo]::InvariantCulture) + 'D)'
            }
            if ($v -is [string]) { return '(object)' + (ConvertTo-OtterCSharpString -Text $v) }
            throw (New-OtterNativeUnsupported -Node $Expr -What "a $($v.GetType().Name) literal")
        }
        'Variable' { return "R.Get(e, $(ConvertTo-OtterCSharpString $Expr.Name), $line)" }
        'Math' {
            $op = [int]$Expr.Op
            $l = ConvertTo-OtterNativeExpression -Expr $Expr.Left -Context $Context
            $r = ConvertTo-OtterNativeExpression -Expr $Expr.Right -Context $Context
            return "R.Arith($op, $l, $r, $line)"
        }
        'Comparison' {
            $op = [int]$Expr.Op
            $l = ConvertTo-OtterNativeExpression -Expr $Expr.Left -Context $Context
            $r = ConvertTo-OtterNativeExpression -Expr $Expr.Right -Context $Context
            return "(object)(bool)R.Compare($op, $l, $r, $line)"
        }
        'Logical' {
            $l = ConvertTo-OtterNativeExpression -Expr $Expr.Left -Context $Context
            $r = ConvertTo-OtterNativeExpression -Expr $Expr.Right -Context $Context
            $joiner = if ($Expr.Op.ToString() -eq 'And') { '&&' } else { '||' }
            return "(object)(R.Truthy($l) $joiner R.Truthy($r))"
        }
        'Not' {
            $o = ConvertTo-OtterNativeExpression -Expr $Expr.Operand -Context $Context
            return "(object)(!R.Truthy($o))"
        }
        'Contains' {
            $c = ConvertTo-OtterNativeExpression -Expr $Expr.Collection -Context $Context
            $i = ConvertTo-OtterNativeExpression -Expr $Expr.Item -Context $Context
            return "R.Contains($c, $i, $line)"
        }
        'OfOperation' {
            $operation = $Expr.Operation.ToString()
            $s = ConvertTo-OtterNativeExpression -Expr $Expr.Subject -Context $Context
            if ($operation -in @('Length', 'First', 'Last')) { return "R.$operation($s, $line)" }
            # Text and math operations share R.Of, keyed by the OfOperation number.
            if ($operation -in @('Uppercase', 'Lowercase', 'AbsoluteValue', 'SquareRoot', 'Round', 'RoundUp', 'RoundDown', 'Sine', 'Cosine', 'Tangent', 'LogTen', 'NaturalLog')) {
                return "R.Of($([int]$Expr.Operation), $s, $line)"
            }
            throw (New-OtterNativeUnsupported -Node $Expr -What "'$($operation.ToLowerInvariant()) of'")
        }
        'PropertyAccess' {
            $t = ConvertTo-OtterNativeExpression -Expr $Expr.Target -Context $Context
            return "R.Prop($t, $(ConvertTo-OtterCSharpString $Expr.Property), $line)"
        }
        'Call' {
            $argCode = @(foreach ($a in $Expr.Arguments) { ConvertTo-OtterNativeExpression -Expr $a -Context $Context })
            $argArray = if ($argCode.Count) { 'new object[] { ' + ($argCode -join ', ') + ' }' } else { 'new object[0]' }
            return "R.Invoke(R.Resolve(e, $(ConvertTo-OtterCSharpString $Expr.Name), $($Expr.Arguments.Count), $line), $argArray, $line)"
        }
        default { throw (New-OtterNativeUnsupported -Node $Expr) }
    }
}

function ConvertTo-OtterNativeBlock {
    param([Node[]]$Statements, [OtterNativeContext]$Context, [bool]$InFunction, [string]$Pad)
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($s in @($Statements)) {
        if ($null -eq $s) { continue }
        foreach ($l in (ConvertTo-OtterNativeStatement -Stmt $s -Context $Context -InFunction $InFunction -Pad $Pad)) { $lines.Add($l) }
    }
    return , $lines
}

function ConvertTo-OtterNativeStatement {
    param([Node]$Stmt, [OtterNativeContext]$Context, [bool]$InFunction, [string]$Pad)
    $line = $Stmt.Line
    $inner = $Pad + '    '
    $out = [System.Collections.Generic.List[string]]::new()
    switch ($Stmt.Kind.ToString()) {
        'Say' {
            if ($null -ne $Stmt.ColorExpr) { throw (New-OtterNativeUnsupported -Node $Stmt -What "'say ... in color'") }
            $parts = @(foreach ($p in $Stmt.Parts) { ConvertTo-OtterNativeExpression -Expr $p -Context $Context })
            if ($parts.Count -eq 0) { $out.Add("${Pad}R.Out(`"`");") }
            else { $out.Add("${Pad}R.Say(new object[] { $($parts -join ', ') });") }
        }
        'Assign' {
            $v = ConvertTo-OtterNativeExpression -Expr $Stmt.Value -Context $Context
            if ($Stmt.Target -is [VariableExpr]) {
                $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target.Name), $v);")
            } elseif ($Stmt.Target.Kind.ToString() -eq 'PropertyAccess') {
                # The value first, then the owner - as Set-OtterTarget does.
                $tmp = $Context.Next('value')
                $owner = ConvertTo-OtterNativeExpression -Expr $Stmt.Target.Target -Context $Context
                $out.Add("${Pad}{ object $tmp = $v; R.SetProp($owner, $(ConvertTo-OtterCSharpString $Stmt.Target.Property), $tmp, $line); }")
            } else { throw (New-OtterNativeUnsupported -Node $Stmt -What 'this assignment target') }
        }
        'TypeDef' {
            $fields = @($Stmt.FieldNames | ForEach-Object { ConvertTo-OtterCSharpString $_ })
            $fieldArray = if ($fields.Count) { 'new string[] { ' + ($fields -join ', ') + ' }' } else { 'new string[0]' }
            $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.TypeName), new OtterTypeValue($(ConvertTo-OtterCSharpString $Stmt.TypeName), $fieldArray));")
        }
        'ObjectDef' {
            $t = $Context.Next('thing')
            $out.Add("${Pad}R.RequireNewThingName(e, $(ConvertTo-OtterCSharpString $Stmt.Name), $line);")
            $out.Add("${Pad}{")
            $out.Add("${inner}OtterThing $t = R.NewObject(e, $(ConvertTo-OtterCSharpString $Stmt.TypeName));")
            foreach ($p in @($Stmt.Properties)) {
                if ($p.Kind.ToString() -ne 'Assign' -or $p.Target -isnot [VariableExpr]) { throw (New-OtterNativeUnsupported -Node $p -What 'this property line') }
                $out.Add("${inner}$t.Write($(ConvertTo-OtterCSharpString $p.Target.Name), $(ConvertTo-OtterNativeExpression -Expr $p.Value -Context $Context));")
            }
            $out.Add("${inner}e.Set($(ConvertTo-OtterCSharpString $Stmt.Name), $t);")
            $out.Add("${Pad}}")
        }
        'GetKey' {
            $target = ConvertTo-OtterNativeExpression -Expr $Stmt.Target -Context $Context
            $key = ConvertTo-OtterNativeExpression -Expr $Stmt.Key -Context $Context
            $k = $Context.Next('key')
            $out.Add("${Pad}{ OtterThing $k = R.KeyTarget($target, $line, `"read from`"); e.Set($(ConvertTo-OtterCSharpString $Stmt.ResultTarget), $k.Read(R.KeyText($key, $line))); }")
        }
        'MathInto' {
            $v = ConvertTo-OtterNativeExpression -Expr $Stmt.Expression -Context $Context
            $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), $v);")
        }
        'ListDef' {
            $items = @(foreach ($i in $Stmt.Items) { ConvertTo-OtterNativeExpression -Expr $i -Context $Context })
            $array = if ($items.Count) { 'new object[] { ' + ($items -join ', ') + ' }' } else { 'new object[0]' }
            $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Name), R.List($array));")
        }
        'AddTo' {
            $name = ConvertTo-OtterCSharpString $Stmt.Target
            $out.Add("${Pad}R.RequireVariable(e, $name, $line, $(ConvertTo-OtterCSharpString "$($Stmt.Target) is 0"));")
            $out.Add("${Pad}R.AddTo(e, $name, $(ConvertTo-OtterNativeExpression -Expr $Stmt.Amount -Context $Context), $line);")
        }
        'RemoveFrom' {
            $name = ConvertTo-OtterCSharpString $Stmt.Target
            $out.Add("${Pad}R.RequireVariable(e, $name, $line, null);")
            $out.Add("${Pad}R.RemoveFrom(e, $name, $(ConvertTo-OtterNativeExpression -Expr $Stmt.Amount -Context $Context), $line);")
        }
        'If' {
            $first = $true
            foreach ($branch in $Stmt.Branches) {
                $cond = ConvertTo-OtterNativeExpression -Expr $branch.Condition -Context $Context
                $out.Add("${Pad}$(if ($first) { 'if' } else { 'else if' }) (R.Truthy($cond)) {")
                foreach ($l in (ConvertTo-OtterNativeBlock -Statements $branch.Body -Context $Context -InFunction $InFunction -Pad $inner)) { $out.Add($l) }
                $out.Add("${Pad}}")
                $first = $false
            }
            if ($null -ne $Stmt.ElseBody) {
                $out.Add("${Pad}else {")
                foreach ($l in (ConvertTo-OtterNativeBlock -Statements $Stmt.ElseBody -Context $Context -InFunction $InFunction -Pad $inner)) { $out.Add($l) }
                $out.Add("${Pad}}")
            }
        }
        { $_ -in 'CountLoop', 'Repeat', 'While', 'ForEach' } {
            # D130: a loop that sets up a handler needs a scope per pass; the
            # compiled subset has no handlers, so such a loop cannot occur yet.
            $names = $Context.PassNames[$Stmt]
            if ($null -ne $names -and $names.Count -gt 0) { throw (New-OtterNativeUnsupported -Node $Stmt -What 'a loop that sets up a handler') }
            $body = ConvertTo-OtterNativeBlock -Statements $Stmt.Body -Context $Context -InFunction $InFunction -Pad $inner
            switch ($Stmt.Kind.ToString()) {
                'CountLoop' {
                    $f = $Context.Next('from'); $t = $Context.Next('to'); $st = $Context.Next('step'); $n = $Context.Next('n')
                    $out.Add("${Pad}{")
                    $out.Add("${inner}double $f = R.AssertNumber($(ConvertTo-OtterNativeExpression -Expr $Stmt.From -Context $Context), $line, `"the value to count from`");")
                    $out.Add("${inner}double $t = R.AssertNumber($(ConvertTo-OtterNativeExpression -Expr $Stmt.To -Context $Context), $line, `"the value to count to`");")
                    $out.Add("${inner}double $st = $f <= $t ? 1 : -1;")
                    $out.Add("${inner}for (double $n = $f; ($st > 0 && $n <= $t) || ($st < 0 && $n >= $t); $n += $st) {")
                    $out.Add("${inner}    e.SetLocal($(ConvertTo-OtterCSharpString $Stmt.VariableName), $n);")
                    foreach ($l in $body) { $out.Add("    $l") }
                    $out.Add("${inner}}")
                    $out.Add("${Pad}}")
                }
                'Repeat' {
                    $c = $Context.Next('times'); $i = $Context.Next('i')
                    $out.Add("${Pad}{")
                    $out.Add("${inner}int $c = (int)Math.Floor(R.AssertNumber($(ConvertTo-OtterNativeExpression -Expr $Stmt.Count -Context $Context), $line, `"the number of repeats`"));")
                    $out.Add("${inner}for (int $i = 0; $i < $c; $i++) {")
                    foreach ($l in $body) { $out.Add("    $l") }
                    $out.Add("${inner}}")
                    $out.Add("${Pad}}")
                }
                'While' {
                    $out.Add("${Pad}while (R.Truthy($(ConvertTo-OtterNativeExpression -Expr $Stmt.Condition -Context $Context))) {")
                    foreach ($l in $body) { $out.Add($l) }
                    $out.Add("${Pad}}")
                }
                'ForEach' {
                    $it = $Context.Next('item')
                    $out.Add("${Pad}foreach (object $it in R.Walk($(ConvertTo-OtterNativeExpression -Expr $Stmt.Collection -Context $Context), $line)) {")
                    $out.Add("${inner}e.SetLocal($(ConvertTo-OtterCSharpString $Stmt.VariableName), $it);")
                    foreach ($l in $body) { $out.Add($l) }
                    $out.Add("${Pad}}")
                }
            }
        }
        'FunctionDef' {
            $method = $Context.Next('Fn_')
            $body = ConvertTo-OtterNativeBlock -Statements $Stmt.Body -Context $Context -InFunction $true -Pad '        '
            $text = "    static object $method(Env e) {`n" + (($body | ForEach-Object { $_ }) -join "`n") + "`n        return null;`n    }"
            $Context.Methods.Add($text)
            $params = @($Stmt.Parameters | ForEach-Object { ConvertTo-OtterCSharpString $_ })
            $paramArray = if ($params.Count) { 'new string[] { ' + ($params -join ', ') + ' }' } else { 'new string[0]' }
            $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Name), new OtterFn($(ConvertTo-OtterCSharpString $Stmt.Name), $paramArray, $method));")
        }
        'CallStatement' {
            $call = ConvertTo-OtterNativeExpression -Expr $Stmt.Call -Context $Context
            if ($Stmt.ResultTarget) { $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.ResultTarget), $call);") }
            else { $out.Add("${Pad}$call;") }
        }
        'Return' {
            $v = if ($null -ne $Stmt.Value) { ConvertTo-OtterNativeExpression -Expr $Stmt.Value -Context $Context } else { 'null' }
            # In a function, return its value. At the top level there is
            # nothing to stop: the interpreter works the value out, then
            # reports it (Invoke-OtterProgram's OtterReturnSignal catch).
            if ($InFunction) { $out.Add("${Pad}return $v;") }
            else {
                if ($v -ne 'null') { $out.Add("${Pad}GC.KeepAlive($v);") }
                $out.Add("${Pad}throw new OtterStopSignal($line);")
            }
        }
        'Try' {
            # Any failure is caught, as in the interpreter; a top-level `stop`
            # is not a failure and passes through (OtterStopSignal).
            $ex = $Context.Next('ex')
            $out.Add("${Pad}try {")
            foreach ($l in (ConvertTo-OtterNativeBlock -Statements $Stmt.Body -Context $Context -InFunction $InFunction -Pad $inner)) { $out.Add($l) }
            $out.Add("${Pad}}")
            $out.Add("${Pad}catch (OtterStopSignal) { throw; }")
            $out.Add("${Pad}catch (Exception $ex) {")
            if ($Stmt.ErrorTarget) { $out.Add("${inner}e.Set($(ConvertTo-OtterCSharpString $Stmt.ErrorTarget), $ex.Message);") }
            else { $out.Add("${inner}GC.KeepAlive($ex);") }
            if ($null -ne $Stmt.OtherwiseBody) {
                foreach ($l in (ConvertTo-OtterNativeBlock -Statements $Stmt.OtherwiseBody -Context $Context -InFunction $InFunction -Pad $inner)) { $out.Add($l) }
            }
            $out.Add("${Pad}}")
        }
        'Fail' {
            $out.Add("${Pad}throw R.Fail($(ConvertTo-OtterNativeExpression -Expr $Stmt.Message -Context $Context), $line);")
        }
        'Sort' { $out.Add("${Pad}R.Sort(e, $(ConvertTo-OtterCSharpString $Stmt.Target), $line);") }
        'Replace' {
            # The variable is read, then the find and replacement text worked out.
            $subject = $Context.Next('subject')
            $out.Add("${Pad}{")
            $out.Add("${inner}string $subject = R.ReplaceSubject(e, $(ConvertTo-OtterCSharpString $Stmt.Target), $line);")
            $destination = if ($Stmt.ResultTarget) { $Stmt.ResultTarget } else { $Stmt.Target }
            $out.Add("${inner}e.Set($(ConvertTo-OtterCSharpString $destination), R.Replace($subject, $(ConvertTo-OtterNativeExpression -Expr $Stmt.Find -Context $Context), $(ConvertTo-OtterNativeExpression -Expr $Stmt.Replacement -Context $Context), $line));")
            $out.Add("${Pad}}")
        }
        'Split' {
            $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.Split($(ConvertTo-OtterNativeExpression -Expr $Stmt.Subject -Context $Context), $(ConvertTo-OtterNativeExpression -Expr $Stmt.Separator -Context $Context), $line));")
        }
        'Join' {
            # The list is checked before the separator is worked out.
            $list = $Context.Next('list')
            $out.Add("${Pad}{")
            $out.Add("${inner}object $list = R.JoinList($(ConvertTo-OtterNativeExpression -Expr $Stmt.Subject -Context $Context), $line);")
            $out.Add("${inner}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.Join($list, $(ConvertTo-OtterNativeExpression -Expr $Stmt.Separator -Context $Context)));")
            $out.Add("${Pad}}")
        }
        'Reverse' { $out.Add("${Pad}R.Reverse(e, $(ConvertTo-OtterCSharpString $Stmt.Target), $line);") }
        default { throw (New-OtterNativeUnsupported -Node $Stmt) }
    }
    return , $out
}

# AST -> one C# 5 compilation unit with a class named $ClassName and an entry
# point `public static void Run(Env e)`.
function ConvertTo-OtterCSharp {
    param([Parameter(Mandatory)][ProgramNode]$Program, [Parameter(Mandatory)][string]$ClassName)
    $context = [OtterNativeContext]::new()
    $context.PassNames = Get-OtterLoopPassNames -Statements $Program.Statements
    $main = ConvertTo-OtterNativeBlock -Statements $Program.Statements -Context $context -InFunction $false -Pad '        '
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('// Generated by Otter.Compiler.Native.psm1 (experimental). Do not edit.')
    # Windows PowerShell 5.1's Add-Type treats warnings as errors; generated
    # code legitimately has unreachable `return null;` after an Otter return.
    [void]$sb.AppendLine('#pragma warning disable')
    [void]$sb.AppendLine('using System;')
    [void]$sb.AppendLine('using OtterNative;')
    [void]$sb.AppendLine("public static class $ClassName {")
    foreach ($m in $context.Methods) { [void]$sb.AppendLine($m) }
    [void]$sb.AppendLine('    public static void Run(Env e) {')
    foreach ($l in $main) { [void]$sb.AppendLine($l) }
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('}')
    return $sb.ToString()
}

# The runtime library, compiled once per Otter version into the cache folder.
function Get-OtterNativeRuntimeAssembly {
    param([Parameter(Mandatory)][string]$CacheDirectory)
    $source = [System.IO.File]::ReadAllText($script:NativeRuntimePath)
    $hash = Get-OtterNativeHash -Text ($source + $PSVersionTable.PSVersion.ToString())
    $dll = Join-Path $CacheDirectory "OtterNativeRuntime-$hash.dll"
    # A session can load the runtime only once: when it is already loaded,
    # programs must reference that copy, even if the source changed since.
    $loaded = 'OtterNative.R' -as [type]
    if ($loaded) { return $loaded.Assembly.Location }
    if (-not (Test-Path -LiteralPath $dll)) {
        Add-Type -TypeDefinition $source -OutputAssembly $dll -ErrorAction Stop
    }
    Add-Type -Path $dll -ErrorAction Stop
    return $dll
}

function Get-OtterNativeHash {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
        return ([System.BitConverter]::ToString($bytes) -replace '-', '').Substring(0, 16).ToLowerInvariant()
    } finally { $sha.Dispose() }
}

# Compiles a program (cached by source hash) and returns its Run method.
function New-OtterNativeProgram {
    param(
        [Parameter(Mandatory)][ProgramNode]$Program,
        [Parameter(Mandatory)][string]$SourceText,
        [Parameter(Mandatory)][string]$CacheDirectory
    )
    New-Item -ItemType Directory -Path $CacheDirectory -Force | Out-Null
    $runtimeDll = Get-OtterNativeRuntimeAssembly -CacheDirectory $CacheDirectory
    $runtimeHash = Get-OtterNativeHash -Text ([System.IO.File]::ReadAllText($script:NativeRuntimePath))
    # The key covers everything that shapes the compiled program: the Otter
    # source, the runtime library, this compiler, and the PowerShell version.
    $compilerHash = Get-OtterNativeHash -Text ([System.IO.File]::ReadAllText($PSCommandPath))
    $hash = Get-OtterNativeHash -Text ($SourceText + '|' + $runtimeHash + '|' + $compilerHash + '|' + $PSVersionTable.PSVersion.ToString())
    $className = "OtterProgram_$hash"
    $csharp = ConvertTo-OtterCSharp -Program $Program -ClassName $className
    if (-not ($className -as [type])) {
        $dll = Join-Path $CacheDirectory "$className.dll"
        if (-not (Test-Path -LiteralPath $dll)) {
            Add-Type -TypeDefinition $csharp -ReferencedAssemblies $runtimeDll -OutputAssembly $dll -ErrorAction Stop
        }
        Add-Type -Path $dll -ErrorAction Stop
    }
    return [pscustomobject]@{ ClassName = $className; CSharp = $csharp; Type = ($className -as [type]) }
}

# Runs a compiled program; output lines go to $Writer. An Otter error comes
# back as an [OtterError] built like the interpreter's (message, line, source
# line, suggestion).
function Invoke-OtterNativeProgram {
    param(
        [Parameter(Mandatory)]$Compiled,
        [Parameter(Mandatory)][scriptblock]$Writer,
        [string[]]$SourceLines = @()
    )
    $global = [OtterNative.Env]::new($null)
    [OtterNative.R]::Reset($global, [Action[string]]$Writer)
    try {
        $Compiled.Type.GetMethod('Run').Invoke($null, @(, $global)) | Out-Null
    }
    catch {
        $inner = $_.Exception
        while ($inner -is [System.Management.Automation.MethodInvocationException] -or $inner -is [System.Reflection.TargetInvocationException]) {
            if ($null -eq $inner.InnerException) { break }
            $inner = $inner.InnerException
        }
        if ($inner -is [OtterNative.OtterStopSignal]) {
            $sourceLine = if ($inner.Line -ge 1 -and $inner.Line -le $SourceLines.Count) { $SourceLines[$inner.Line - 1] } else { $null }
            throw [OtterError]::new($inner.Message, $inner.Line, 'runtime', 0, $sourceLine, $null)
        }
        if ($inner -is [OtterNative.OtterNativeError]) {
            $sourceLine = if ($inner.Line -ge 1 -and $inner.Line -le $SourceLines.Count) { $SourceLines[$inner.Line - 1] } else { $null }
            throw [OtterError]::new($inner.Message, $inner.Line, 'runtime', 0, $sourceLine, $inner.Suggestion)
        }
        throw
    }
}

Export-ModuleMember -Function ConvertTo-OtterCSharp, New-OtterNativeProgram, Invoke-OtterNativeProgram, Get-OtterNativePartialKinds
