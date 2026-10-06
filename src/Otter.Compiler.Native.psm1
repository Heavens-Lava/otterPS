using module ..\Otter.Contract.psm1
using module .\Otter.Runtime.psm1
using module .\Otter.Library.psm1
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
        'FileExists' {
            return "R.Call(`"FileExists`", new object[] { $(ConvertTo-OtterNativeExpression -Expr $Expr.Path -Context $Context) }, $line)"
        }
        'Clock' { return $(if ($Expr.Clock.ToString() -eq 'Now') { 'R.Clock(true)' } else { 'R.Clock(false)' }) }
        'DateDifferenceValue' {
            if ($Expr.Unit.ToString() -eq 'Millisecond') { throw (New-OtterNativeUnsupported -Node $Expr -What 'milliseconds between dates') }
            return "R.DateDifference($(ConvertTo-OtterNativeExpression -Expr $Expr.Start -Context $Context), $(ConvertTo-OtterNativeExpression -Expr $Expr.End -Context $Context), `"$($Expr.Unit)`", $line)"
        }
        'DateFromText' {
            $source = ConvertTo-OtterNativeExpression -Expr $Expr.Source -Context $Context
            if ($null -eq $Expr.Format) { return "R.DateFromText($source, $line)" }
            return "R.DateFromTextUsing($source, $(ConvertTo-OtterNativeExpression -Expr $Expr.Format -Context $Context), $line)"
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
        'Bytes' {
            if ($Expr.Op.ToString() -eq 'FromText') {
                $source = ConvertTo-OtterNativeExpression -Expr $Expr.Source -Context $Context
                return "R.BytesFromText($source, $line)"
            }
            throw (New-OtterNativeUnsupported -Node $Expr -What "'bytes $($Expr.Op)'")
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
            foreach ($p in @($Stmt.Properties | Where-Object { $null -ne $_ })) {
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
        # Library statements: the interpreter's own functions, through the bridge.
        'ConvertToJson' {
            $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.Call(`"ConvertToJson`", new object[] { $(ConvertTo-OtterNativeExpression -Expr $Stmt.Subject -Context $Context) }, $line));")
        }
        # Dates (D32): mirrored in the runtime, checked in the interpreter's order.
        'DateAdjust' {
            if ($Stmt.Unit.ToString() -eq 'Millisecond') { throw (New-OtterNativeUnsupported -Node $Stmt -What 'adding milliseconds to a date') }
            $d = $Context.Next('date')
            $removal = if ($Stmt.IsRemoval) { 'true' } else { 'false' }
            $out.Add("${Pad}{")
            $out.Add("${inner}OtterDateValue $d = R.DateTarget(e, $(ConvertTo-OtterCSharpString $Stmt.Target), $line);")
            $out.Add("${inner}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.DateAdjust($d, $(ConvertTo-OtterNativeExpression -Expr $Stmt.Amount -Context $Context), `"$($Stmt.Unit)`", $removal, $line));")
            $out.Add("${Pad}}")
        }
        'DateDifference' {
            if ($Stmt.Unit.ToString() -eq 'Millisecond') { throw (New-OtterNativeUnsupported -Node $Stmt -What 'milliseconds between dates') }
            $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.DateDifference($(ConvertTo-OtterNativeExpression -Expr $Stmt.Start -Context $Context), $(ConvertTo-OtterNativeExpression -Expr $Stmt.End -Context $Context), `"$($Stmt.Unit)`", $line));")
        }
        'FormatDate' {
            $d = $Context.Next('date')
            $out.Add("${Pad}{")
            $out.Add("${inner}OtterDateValue $d = R.DateSubject($(ConvertTo-OtterNativeExpression -Expr $Stmt.Subject -Context $Context), $line);")
            $out.Add("${inner}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.FormatDate($d, $(ConvertTo-OtterNativeExpression -Expr $Stmt.Format -Context $Context), $line));")
            $out.Add("${Pad}}")
        }
        # Files, in the interpreter's order: content, then path.
        'WriteFile' {
            $atomic = if ($Stmt.Atomic) { 'true' } else { 'false' }
            $out.Add("${Pad}R.Call(`"WriteFile`", new object[] { R.Format($(ConvertTo-OtterNativeExpression -Expr $Stmt.Content -Context $Context)), $(ConvertTo-OtterNativeExpression -Expr $Stmt.Path -Context $Context), $atomic }, $line);")
        }
        'AppendFile' {
            $out.Add("${Pad}R.Call(`"AppendFile`", new object[] { R.Format($(ConvertTo-OtterNativeExpression -Expr $Stmt.Content -Context $Context)), $(ConvertTo-OtterNativeExpression -Expr $Stmt.Path -Context $Context) }, $line);")
        }
        'ReadFile' {
            $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.Call(`"ReadFile`", new object[] { $(ConvertTo-OtterNativeExpression -Expr $Stmt.Path -Context $Context) }, $line));")
        }
        'ReadJson' {
            $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.Call(`"ReadJson`", new object[] { $(ConvertTo-OtterNativeExpression -Expr $Stmt.Path -Context $Context) }, $line));")
        }
        'DeleteFile' {
            $out.Add("${Pad}R.Call(`"DeleteFile`", new object[] { $(ConvertTo-OtterNativeExpression -Expr $Stmt.Path -Context $Context) }, $line);")
        }
        'CopyFile' {
            $out.Add("${Pad}R.Call(`"CopyFile`", new object[] { $(ConvertTo-OtterNativeExpression -Expr $Stmt.Source -Context $Context), $(ConvertTo-OtterNativeExpression -Expr $Stmt.Destination -Context $Context) }, $line);")
        }
        'MoveFile' {
            $out.Add("${Pad}R.Call(`"MoveFile`", new object[] { $(ConvertTo-OtterNativeExpression -Expr $Stmt.Source -Context $Context), $(ConvertTo-OtterNativeExpression -Expr $Stmt.Destination -Context $Context) }, $line);")
        }
        'ConvertFromJson' {
            $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.Call(`"ConvertFromJson`", new object[] { R.Format($(ConvertTo-OtterNativeExpression -Expr $Stmt.Subject -Context $Context)) }, $line));")
        }
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
        'SetRandomSeed' {
            $seed = ConvertTo-OtterNativeExpression -Expr $Stmt.Seed -Context $Context
            $out.Add("${Pad}R.SetRandomSeed($seed, $line);")
        }
        'RandomNumber' {
            $from = ConvertTo-OtterNativeExpression -Expr $Stmt.From -Context $Context
            $to = ConvertTo-OtterNativeExpression -Expr $Stmt.To -Context $Context
            $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.RandomNumber($from, $to, $line));")
        }
        'RandomItem' {
            $col = ConvertTo-OtterNativeExpression -Expr $Stmt.Collection -Context $Context
            $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.RandomItem($col, $line));")
        }
        'RunProgram' {
            $cmd = ConvertTo-OtterNativeExpression -Expr $Stmt.Target -Context $Context
            $isCmd = if ($Stmt.IsCommand) { 'true' } else { 'false' }
            if ($Stmt.ResultTarget) {
                $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.ResultTarget), R.Call(`"RunProgram`", new object[] { R.Format($cmd), $isCmd }, $line));")
            } else {
                $out.Add("${Pad}R.Call(`"RunProgram`", new object[] { R.Format($cmd), $isCmd }, $line);")
            }
        }
        'HttpGet' {
            $url = ConvertTo-OtterNativeExpression -Expr $Stmt.Url -Context $Context
            $asJson = if ($Stmt.AsJson) { 'true' } else { 'false' }
            $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.Call(`"HttpRequest`", new object[] { `"GET`", R.Format($url), null, $asJson }, $line));")
        }
        'HttpPost' {
            $url = ConvertTo-OtterNativeExpression -Expr $Stmt.Url -Context $Context
            $data = ConvertTo-OtterNativeExpression -Expr $Stmt.Data -Context $Context
            $asJson = if ($Stmt.AsJson) { 'true' } else { 'false' }
            if ($Stmt.Target) {
                $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.Call(`"HttpRequest`", new object[] { `"POST`", R.Format($url), $data, $asJson }, $line));")
            } else {
                $out.Add("${Pad}R.Call(`"HttpRequest`", new object[] { `"POST`", R.Format($url), $data, $asJson }, $line);")
            }
        }
        'HttpPut' {
            $url = ConvertTo-OtterNativeExpression -Expr $Stmt.Url -Context $Context
            $data = ConvertTo-OtterNativeExpression -Expr $Stmt.Data -Context $Context
            $asJson = if ($Stmt.AsJson) { 'true' } else { 'false' }
            if ($Stmt.Target) {
                $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.Call(`"HttpRequest`", new object[] { `"PUT`", R.Format($url), $data, $asJson }, $line));")
            } else {
                $out.Add("${Pad}R.Call(`"HttpRequest`", new object[] { `"PUT`", R.Format($url), $data, $asJson }, $line);")
            }
        }
        'HttpDelete' {
            $url = ConvertTo-OtterNativeExpression -Expr $Stmt.Url -Context $Context
            if ($Stmt.Target) {
                $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.Call(`"HttpRequest`", new object[] { `"DELETE`", R.Format($url), null, false }, $line));")
            } else {
                $out.Add("${Pad}R.Call(`"HttpRequest`", new object[] { `"DELETE`", R.Format($url), null, false }, $line);")
            }
        }
        'UdpOpen' {
            $port = if ($null -ne $Stmt.Port) { ConvertTo-OtterNativeExpression -Expr $Stmt.Port -Context $Context } else { 'null' }
            $out.Add("${Pad}e.Set($(ConvertTo-OtterCSharpString $Stmt.Target), R.UdpOpen($port, $line));")
        }
        'UdpSend' {
            $sock = ConvertTo-OtterNativeExpression -Expr $Stmt.Socket -Context $Context
            $data = ConvertTo-OtterNativeExpression -Expr $Stmt.Data -Context $Context
            $hostExpr = ConvertTo-OtterNativeExpression -Expr $Stmt.HostExpr -Context $Context
            $port = ConvertTo-OtterNativeExpression -Expr $Stmt.Port -Context $Context
            $out.Add("${Pad}R.UdpSend($sock, $data, $hostExpr, $port, $line);")
        }
        'NetClose' {
            $sock = ConvertTo-OtterNativeExpression -Expr $Stmt.Socket -Context $Context
            $out.Add("${Pad}R.NetClose($sock, $line);")
        }
        'WebSocketEvent' {
            $sock = ConvertTo-OtterNativeExpression -Expr $Stmt.Socket -Context $Context
            $method = $Context.Next('handler')
            $body = ConvertTo-OtterNativeBlock -Statements $Stmt.Body -Context $Context -InFunction $false -Pad '        '
            $text = "    static object $method(Env e) {`n$($body -join "`n")`n        return null;`n    }"
            $Context.Methods.Add($text)
            $evtKind = ConvertTo-OtterCSharpString $Stmt.EventKind.ToString()
            $out.Add("${Pad}R.AddNetHandler($sock, $evtKind, new OtterBody($method), e, $line);")
        }
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
    [void]$sb.AppendLine('        R.PumpEvents(e);')
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

# --- the library bridge ----------------------------------------------------
#
# Compiled values and interpreter values differ only for reference types:
# OtterNative.OtterThing <-> OtterObject, OtterTypeValue <-> OtterType,
# OtterFn <-> OtterFunction. Lists are copied item by item; numbers, text,
# booleans and gone are the same values on both sides.

function ConvertTo-OtterInterpreterValue {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [OtterNative.OtterThing]) {
        $object = [OtterObject]::new($Value.TypeName)
        foreach ($name in $Value.Names()) { $object.WriteProperty($name, (ConvertTo-OtterInterpreterValue $Value.Read($name))) }
        return $object
    }
    if ($Value -is [System.Collections.Generic.List[object]]) {
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) { $list.Add((ConvertTo-OtterInterpreterValue $item)) }
        return , $list
    }
    if ($Value -is [OtterNative.OtterTypeValue]) { return [OtterType]::new($Value.Name, $Value.Fields) }
    if ($Value -is [OtterNative.OtterDateValue]) { return [OtterDate]::new($Value.Value, $Value.HasTime) }
    if ($Value -is [OtterNative.OtterFn]) { return [OtterFunction]::new($Value.Name, $Value.Params, @()) }
    if ($Value -is [OtterNative.OtterBytesValue]) { return [OtterBytes]::new($Value.Value) }
    if ($Value -is [OtterNative.OtterUdpSocket]) { return $Value }
    return $Value
}

function ConvertFrom-OtterInterpreterValue {
    param($Value, [int]$Line)
    if ($null -eq $Value) { return $null }
    if ($Value -is [OtterObject]) {
        $thing = [OtterNative.OtterThing]::new($Value.TypeName)
        foreach ($name in $Value.PropertyNames()) { $thing.Write($name, (ConvertFrom-OtterInterpreterValue $Value.ReadProperty($name) $Line)) }
        return $thing
    }
    if ($Value -is [System.Collections.Generic.List[object]]) {
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) { $list.Add((ConvertFrom-OtterInterpreterValue $item $Line)) }
        return , $list
    }
    if ($Value -is [OtterDate]) { return [OtterNative.OtterDateValue]::new($Value.Value, $Value.HasTime) }
    if ($Value -is [OtterType]) { return [OtterNative.OtterTypeValue]::new($Value.Name, $Value.FieldNames) }
    if ($Value -is [OtterBytes]) { return [OtterNative.OtterBytesValue]::new($Value.Value) }
    if ($Value -is [OtterNative.OtterUdpSocket]) { return $Value }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal]) { return [double]$Value }
    if ($Value -is [double] -or $Value -is [string] -or $Value -is [bool]) { return $Value }
    throw [OtterError]::new("The compiled backend cannot hold $($Value.GetType().Name) values yet. Run this program with otter run.", $Line, 'runtime')
}

function Get-OtterNativePath {
    param($Value, [int]$Line)
    return (Resolve-OtterFileArgument -Value (ConvertTo-OtterInterpreterValue $Value) -Line $Line)
}

# One library call from compiled code. Arguments arrive as compiled values;
# Otter errors go back as OtterNativeError values.
$script:OtterNativeHost = {
    param($Request)
    $Name = $Request.Name; $Arguments = $Request.Args; $Line = $Request.Line
    try {
        $result = switch ($Name) {
            'ConvertToJson' { ConvertTo-OtterJsonText -Value (ConvertTo-OtterInterpreterValue $Arguments[0]) -Line $Line }
            'ConvertFromJson' { , (ConvertFrom-OtterJsonText -Text ([string]$Arguments[0]) -Line $Line) }
            # The interpreter's generator ('SetRandomSeed', 'RandomNumber', 'RandomItem').
            'SetRandomSeed' { Get-Random -SetSeed ([int][double]$Arguments[0]) | Out-Null; $null }
            'RandomInt' { [double](Get-Random -Minimum ([int][double]$Arguments[0]) -Maximum ([int][double]$Arguments[1])) }
            # Files: a path argument is any value (Resolve-OtterFileArgument
            # reads a thing's path or name), content is already text.
            'WriteFile' { Write-OtterFile -Path (Get-OtterNativePath $Arguments[1] $Line) -Content ([string]$Arguments[0]) -Line $Line -Atomic ([bool]$Arguments[2]) }
            'AppendFile' { Add-OtterFileContent -Path (Get-OtterNativePath $Arguments[1] $Line) -Content ([string]$Arguments[0]) -Line $Line }
            'ReadFile' { Read-OtterFile -Path (Get-OtterNativePath $Arguments[0] $Line) -Line $Line }
            'ReadJson' { , (Read-OtterJsonFile -Path (Get-OtterNativePath $Arguments[0] $Line) -Line $Line) }
            'DeleteFile' { Remove-OtterFile -Path (Get-OtterNativePath $Arguments[0] $Line) -Line $Line }
            'FileExists' { Test-OtterFileExists -Path (Get-OtterNativePath $Arguments[0] $Line) -Line $Line }
            'CopyFile' {
                $source = Get-OtterNativePath $Arguments[0] $Line
                Copy-OtterFile -Source $source -Destination (Get-OtterNativePath $Arguments[1] $Line) -Line $Line
            }
            'MoveFile' {
                $source = Get-OtterNativePath $Arguments[0] $Line
                Move-OtterFile -Source $source -Destination (Get-OtterNativePath $Arguments[1] $Line) -Line $Line
            }
            'RunProgram' {
                $target = [string]$Arguments[0]
                $isCommand = [bool]$Arguments[1]
                if (-not $isCommand) {
                    Start-OtterProgram -Target $target -Line $Line
                } else {
                    Invoke-OtterCommand -CommandLine $target -Line $Line
                }
            }
            'HttpRequest' {
                $method = [string]$Arguments[0]
                $url = [string]$Arguments[1]
                $data = if ($Arguments.Length -gt 2 -and $null -ne $Arguments[2]) { ConvertTo-OtterInterpreterValue $Arguments[2] } else { $null }
                $asJson = if ($Arguments.Length -gt 3) { [bool]$Arguments[3] } else { $false }
                Invoke-OtterHttpRequest -Method $method -Url $url -Data $data -AsJson $asJson -Line $Line
            }
            default { throw [OtterError]::new("The compiled backend has no library bridge for $Name.", $Line, 'runtime') }
        }
        $Request.Result = ConvertFrom-OtterInterpreterValue $result $Line
    }
    catch {
        $e = $_.Exception
        if ($e -is [OtterError]) {
            $nativeError = [OtterNative.OtterNativeError]::new($e.Message, $e.Line, $e.Suggestion)
            $nativeError.ShowSourceLine = -not [string]::IsNullOrEmpty($e.SourceLine)
            $Request.Result = $nativeError
            return
        }
        throw
    }
}

# Runs a compiled program; output lines go to $Writer. An Otter error comes
# back as an [OtterError] built like the interpreter's (message, line, source
# line, suggestion).
function Invoke-OtterNativeProgram {
    param(
        [Parameter(Mandatory)]$Compiled,
        [Parameter(Mandatory)][scriptblock]$Writer,
        [string[]]$SourceLines = @(),
        [string[]]$Arguments = @()
    )
    $global = [OtterNative.Env]::new($null)
    # New-OtterEnvironment: the program's command-line arguments, as text.
    $argumentList = [System.Collections.Generic.List[object]]::new()
    foreach ($argument in $Arguments) { $argumentList.Add([string]$argument) }
    $global.Set('arguments', $argumentList)
    [OtterNative.R]::Reset($global, [Action[string]]$Writer)
    [OtterNative.R]::Host = [OtterNative.HostCall]$script:OtterNativeHost
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
            $sourceLine = if ($inner.ShowSourceLine -and $inner.Line -ge 1 -and $inner.Line -le $SourceLines.Count) { $SourceLines[$inner.Line - 1] } else { $null }
            throw [OtterError]::new($inner.Message, $inner.Line, 'runtime', 0, $sourceLine, $inner.Suggestion)
        }
        throw
    }
}

Export-ModuleMember -Function ConvertTo-OtterCSharp, New-OtterNativeProgram, Invoke-OtterNativeProgram, Get-OtterNativePartialKinds
