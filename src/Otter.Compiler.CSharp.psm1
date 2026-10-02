using module ..\Otter.Contract.psm1

# Otter.Compiler.CSharp.psm1
#
# Otter 1.1 Native C# Compiler & In-Memory Execution Engine
# Compiles Otter AST (ProgramNode) into high-performance, self-contained C#.
# Compatible with C# 5.0 (Windows PowerShell 5.1) and C# 12+ (PowerShell 7 / .NET 8).

function ConvertTo-OtterCSharpExpression {
    param([Parameter(Mandatory)][Node]$Expr)

    if ($Expr -is [LiteralExpr]) {
        if ($null -eq $Expr.Value) { return "null" }
        if ($Expr.Value -is [bool]) { return if ($Expr.Value) { "true" } else { "false" } }
        if ($Expr.Value -is [double] -or $Expr.Value -is [int] -or $Expr.Value -is [long]) {
            return "$($Expr.Value)"
        }
        $escaped = $Expr.Value.ToString().Replace("\", "\\").Replace('"', '\"').Replace("`r", "\r").Replace("`n", "\n")
        return "`"$escaped`""
    }

    if ($Expr -is [VariableExpr]) {
        return "GetScopeVar(scope, `"$($Expr.Name)`")"
    }

    if ($Expr -is [MathExpr]) {
        $left = ConvertTo-OtterCSharpExpression -Expr $Expr.Left
        $right = ConvertTo-OtterCSharpExpression -Expr $Expr.Right
        switch ($Expr.Op) {
            ([MathOp]::Add)      { return "Add($left, $right)" }
            ([MathOp]::Subtract) { return "Subtract($left, $right)" }
            ([MathOp]::Multiply) { return "Multiply($left, $right)" }
            ([MathOp]::Divide)   { return "Divide($left, $right)" }
            ([MathOp]::Percent)  { return "Percent($left, $right)" }
            ([MathOp]::Power)    { return "Math.Pow(ToDouble($left), ToDouble($right))" }
        }
    }

    if ($Expr -is [ComparisonExpr]) {
        $left = ConvertTo-OtterCSharpExpression -Expr $Expr.Left
        $right = ConvertTo-OtterCSharpExpression -Expr $Expr.Right
        switch ($Expr.Op) {
            ([CompareOp]::Equal)       { return "AreEqual($left, $right)" }
            ([CompareOp]::NotEqual)    { return "(!AreEqual($left, $right))" }
            ([CompareOp]::AtLeast)     { return "(ToDouble($left) >= ToDouble($right))" }
            ([CompareOp]::AtMost)      { return "(ToDouble($left) <= ToDouble($right))" }
            ([CompareOp]::GreaterThan) { return "(ToDouble($left) > ToDouble($right))" }
            ([CompareOp]::LessThan)    { return "(ToDouble($left) < ToDouble($right))" }
        }
    }

    if ($Expr -is [LogicalExpr]) {
        $left = ConvertTo-OtterCSharpExpression -Expr $Expr.Left
        $right = ConvertTo-OtterCSharpExpression -Expr $Expr.Right
        if ($Expr.Op -eq [LogicalOp]::And) {
            return "(ToBool($left) && ToBool($right))"
        } else {
            return "(ToBool($left) || ToBool($right))"
        }
    }

    if ($Expr -is [NotExpr]) {
        $inner = ConvertTo-OtterCSharpExpression -Expr $Expr.Operand
        return "(!ToBool($inner))"
    }

    if ($Expr -is [ContainsExpr]) {
        $col = ConvertTo-OtterCSharpExpression -Expr $Expr.Collection
        $item = ConvertTo-OtterCSharpExpression -Expr $Expr.Item
        return "Contains($col, $item)"
    }

    if ($Expr -is [OfOperationExpr]) {
        $target = ConvertTo-OtterCSharpExpression -Expr $Expr.Subject
        switch ($Expr.Operation) {
            ([OfOperation]::Length)        { return "Length($target)" }
            ([OfOperation]::Uppercase)     { return "Uppercase($target)" }
            ([OfOperation]::Lowercase)     { return "Lowercase($target)" }
            ([OfOperation]::First)         { return "First($target)" }
            ([OfOperation]::Last)          { return "Last($target)" }
            ([OfOperation]::AbsoluteValue) { return "Math.Abs(ToDouble($target))" }
            ([OfOperation]::SquareRoot)    { return "Math.Sqrt(ToDouble($target))" }
            ([OfOperation]::Round)         { return "Math.Round(ToDouble($target))" }
            ([OfOperation]::RoundUp)       { return "Math.Ceiling(ToDouble($target))" }
            ([OfOperation]::RoundDown)     { return "Math.Floor(ToDouble($target))" }
            ([OfOperation]::Sine)          { return "Math.Sin(ToDouble($target) * Math.PI / 180.0)" }
            ([OfOperation]::Cosine)        { return "Math.Cos(ToDouble($target) * Math.PI / 180.0)" }
            ([OfOperation]::Tangent)       { return "Math.Tan(ToDouble($target) * Math.PI / 180.0)" }
            ([OfOperation]::LogTen)        { return "Math.Log10(ToDouble($target))" }
            ([OfOperation]::NaturalLog)    { return "Math.Log(ToDouble($target))" }
        }
    }

    if ($Expr -is [MinMaxExpr]) {
        $left = ConvertTo-OtterCSharpExpression -Expr $Expr.Left
        $right = ConvertTo-OtterCSharpExpression -Expr $Expr.Right
        if ($Expr.IsMax) {
            return "Math.Max(ToDouble($left), ToDouble($right))"
        } else {
            return "Math.Min(ToDouble($left), ToDouble($right))"
        }
    }

    if ($Expr -is [ClockExpr]) {
        if ($Expr.Kind -eq [ClockKind]::Today) {
            return "DateTime.Today.ToString(`"yyyy-MM-dd`")"
        } else {
            return "DateTime.Now.ToString(`"yyyy-MM-dd HH:mm:ss`")"
        }
    }

    if ($Expr -is [FileExistsExpr]) {
        $path = ConvertTo-OtterCSharpExpression -Expr $Expr.Path
        return "File.Exists(Convert.ToString($path))"
    }

    if ($Expr -is [FileLockedExpr]) {
        $path = ConvertTo-OtterCSharpExpression -Expr $Expr.Path
        return "IsFileLocked(Convert.ToString($path))"
    }

    if ($Expr -is [PropertyAccessExpr]) {
        $target = ConvertTo-OtterCSharpExpression -Expr $Expr.Target
        return "GetProperty($target, `"$($Expr.Property)`")"
    }

    if ($Expr -is [CallExpr]) {
        $args = @(foreach ($a in $Expr.Arguments) { ConvertTo-OtterCSharpExpression -Expr $a })
        return "$($Expr.Name)($($args -join ', '))"
    }

    return "null"
}

function ConvertTo-OtterCSharpStatement {
    param(
        [Parameter(Mandatory)][Node]$Stmt,
        [int]$Indent = 3
    )

    $pad = "    " * $Indent

    if ($Stmt -is [SayStmt]) {
        $parts = @(foreach ($p in $Stmt.Parts) { ConvertTo-OtterCSharpExpression -Expr $p })
        $partsCode = if ($parts.Count -gt 0) { $parts -join ", " } else { "`"`"" }
        return "${pad}SayParts(new object[] { $partsCode });"
    }

    if ($Stmt -is [AssignStmt]) {
        $val = ConvertTo-OtterCSharpExpression -Expr $Stmt.Value
        if ($Stmt.Target -is [VariableExpr]) {
            $varName = $Stmt.Target.Name
            return "${pad}scope[`"$varName`"] = $val;"
        } elseif ($Stmt.Target -is [PropertyAccessExpr]) {
            $targetObj = ConvertTo-OtterCSharpExpression -Expr $Stmt.Target.Target
            $propName = $Stmt.Target.Property
            return "${pad}SetProperty($targetObj, `"$propName`", $val);"
        }
    }

    if ($Stmt -is [MathIntoStmt]) {
        $expr = ConvertTo-OtterCSharpExpression -Expr $Stmt.Expression
        return "${pad}scope[`"$($Stmt.Target)`"] = $expr;"
    }

    if ($Stmt -is [AddToStmt]) {
        $val = ConvertTo-OtterCSharpExpression -Expr $Stmt.Amount
        $var = $Stmt.Target
        return "${pad}scope[`"$var`"] = Add(scope.ContainsKey(`"$var`") ? scope[`"$var`"] : null, $val);"
    }

    if ($Stmt -is [RemoveFromStmt]) {
        $val = ConvertTo-OtterCSharpExpression -Expr $Stmt.Amount
        $var = $Stmt.Target
        return "${pad}scope[`"$var`"] = Subtract(scope.ContainsKey(`"$var`") ? scope[`"$var`"] : null, $val);"
    }

    if ($Stmt -is [ListDefStmt]) {
        $items = @(foreach ($it in $Stmt.Items) {
            ConvertTo-OtterCSharpExpression -Expr $it
        })
        $itemsCode = if ($items.Count -gt 0) { $items -join ", " } else { "" }
        return "${pad}scope[`"$($Stmt.Name)`"] = new List<object> { $itemsCode };"
    }

    if ($Stmt -is [ObjectDefStmt]) {
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine("${pad}{")
        [void]$sb.AppendLine("${pad}    var obj = new Dictionary<string, object>();")
        [void]$sb.AppendLine("${pad}    obj[`"__type`"] = `"$($Stmt.TypeName)`";")
        foreach ($p in $Stmt.Properties) {
            if ($p -is [AssignStmt] -and $p.Target -is [VariableExpr]) {
                $propVal = ConvertTo-OtterCSharpExpression -Expr $p.Value
                [void]$sb.AppendLine("${pad}    obj[`"$($p.Target.Name)`"] = $propVal;")
            }
        }
        [void]$sb.AppendLine("${pad}    scope[`"$($Stmt.Name)`"] = obj;")
        [void]$sb.Append("${pad}}")
        return $sb.ToString()
    }

    if ($Stmt -is [GetKeyStmt]) {
        $key = ConvertTo-OtterCSharpExpression -Expr $Stmt.Key
        $dict = ConvertTo-OtterCSharpExpression -Expr $Stmt.Collection
        return "${pad}scope[`"$($Stmt.Target)`"] = GetDynamicKey($dict, $key);"
    }

    if ($Stmt -is [SetKeyStmt]) {
        $key = ConvertTo-OtterCSharpExpression -Expr $Stmt.Key
        $dict = ConvertTo-OtterCSharpExpression -Expr $Stmt.Collection
        $val = ConvertTo-OtterCSharpExpression -Expr $Stmt.Value
        return "${pad}SetDynamicKey($dict, $key, $val);"
    }

    if ($Stmt -is [SortStmt]) {
        return "${pad}SortList(GetScopeVar(scope, `"$($Stmt.Target)`"));"
    }

    if ($Stmt -is [ReverseStmt]) {
        return "${pad}ReverseList(GetScopeVar(scope, `"$($Stmt.Target)`"));"
    }

    if ($Stmt -is [ReplaceStmt]) {
        $needle = ConvertTo-OtterCSharpExpression -Expr $Stmt.Find
        $replacement = ConvertTo-OtterCSharpExpression -Expr $Stmt.Replacement
        $dest = if ($Stmt.ResultTarget) { $Stmt.ResultTarget } else { $Stmt.Target }
        return "${pad}scope[`"$dest`"] = ReplaceText(GetScopeVar(scope, `"$($Stmt.Target)`"), $needle, $replacement);"
    }

    if ($Stmt -is [SplitStmt]) {
        $text = ConvertTo-OtterCSharpExpression -Expr $Stmt.Subject
        $delim = ConvertTo-OtterCSharpExpression -Expr $Stmt.Separator
        return "${pad}scope[`"$($Stmt.Target)`"] = SplitText($text, $delim);"
    }

    if ($Stmt -is [JoinStmt]) {
        $col = ConvertTo-OtterCSharpExpression -Expr $Stmt.Subject
        $delim = ConvertTo-OtterCSharpExpression -Expr $Stmt.Separator
        return "${pad}scope[`"$($Stmt.Target)`"] = JoinList($col, $delim);"
    }

    if ($Stmt -is [ReadJsonStmt]) {
        $path = ConvertTo-OtterCSharpExpression -Expr $Stmt.Path
        return "${pad}scope[`"$($Stmt.Target)`"] = ReadJsonFile(Convert.ToString($path));"
    }

    if ($Stmt -is [ConvertToJsonStmt]) {
        $val = ConvertTo-OtterCSharpExpression -Expr $Stmt.Value
        return "${pad}scope[`"$($Stmt.Target)`"] = ConvertToJsonString($val);"
    }

    if ($Stmt -is [ConvertFromJsonStmt]) {
        $text = ConvertTo-OtterCSharpExpression -Expr $Stmt.JsonText
        return "${pad}scope[`"$($Stmt.Target)`"] = ConvertFromJsonString(Convert.ToString($text));"
    }

    if ($Stmt -is [ReadFileStmt]) {
        $path = ConvertTo-OtterCSharpExpression -Expr $Stmt.Path
        return "${pad}scope[`"$($Stmt.Target)`"] = File.ReadAllText(Convert.ToString($path));"
    }

    if ($Stmt -is [WriteFileStmt]) {
        $text = ConvertTo-OtterCSharpExpression -Expr $Stmt.Content
        $path = ConvertTo-OtterCSharpExpression -Expr $Stmt.Path
        return "${pad}WriteFileWithAtomic(Convert.ToString($path), Convert.ToString($text), $($Stmt.Atomic.ToString().ToLower()));"
    }

    if ($Stmt -is [AppendFileStmt]) {
        $text = ConvertTo-OtterCSharpExpression -Expr $Stmt.Content
        $path = ConvertTo-OtterCSharpExpression -Expr $Stmt.Path
        return "${pad}File.AppendAllText(Convert.ToString($path), Convert.ToString($text));"
    }

    if ($Stmt -is [DeleteFileStmt]) {
        $path = ConvertTo-OtterCSharpExpression -Expr $Stmt.Path
        return "${pad}if (File.Exists(Convert.ToString($path))) { File.Delete(Convert.ToString($path)); }"
    }

    if ($Stmt -is [IfStmt]) {
        $sb = [System.Text.StringBuilder]::new()
        $first = $true
        foreach ($branch in $Stmt.Branches) {
            $prefix = if ($first) { "${pad}if (" } else { " else if (" }
            $first = $false
            if ($null -ne $branch.Condition) {
                $cond = ConvertTo-OtterCSharpExpression -Expr $branch.Condition
                [void]$sb.AppendLine("$prefix ToBool($cond)) {")
            } else {
                [void]$sb.AppendLine("${pad}else {")
            }
            foreach ($s in $branch.Body) {
                [void]$sb.AppendLine((ConvertTo-OtterCSharpStatement -Stmt $s -Indent ($Indent + 1)))
            }
            [void]$sb.Append("${pad}}")
        }
        if ($null -ne $Stmt.ElseBody -and $Stmt.ElseBody.Count -gt 0) {
            [void]$sb.AppendLine(" else {")
            foreach ($s in $Stmt.ElseBody) {
                [void]$sb.AppendLine((ConvertTo-OtterCSharpStatement -Stmt $s -Indent ($Indent + 1)))
            }
            [void]$sb.Append("${pad}}")
        }
        return $sb.ToString()
    }

    if ($Stmt -is [WhileStmt]) {
        $cond = ConvertTo-OtterCSharpExpression -Expr $Stmt.Condition
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine("${pad}while (ToBool($cond)) {")
        foreach ($s in $Stmt.Body) {
            [void]$sb.AppendLine((ConvertTo-OtterCSharpStatement -Stmt $s -Indent ($Indent + 1)))
        }
        [void]$sb.Append("${pad}}")
        return $sb.ToString()
    }

    if ($Stmt -is [RepeatStmt]) {
        $times = ConvertTo-OtterCSharpExpression -Expr $Stmt.Count
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine("${pad}for (long _rep = 0; _rep < Convert.ToInt64(ToDouble($times)); _rep++) {")
        foreach ($s in $Stmt.Body) {
            [void]$sb.AppendLine((ConvertTo-OtterCSharpStatement -Stmt $s -Indent ($Indent + 1)))
        }
        [void]$sb.Append("${pad}}")
        return $sb.ToString()
    }

    if ($Stmt -is [CountStmt]) {
        $from = ConvertTo-OtterCSharpExpression -Expr $Stmt.From
        $to = ConvertTo-OtterCSharpExpression -Expr $Stmt.To
        $var = $Stmt.VariableName
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine("${pad}for (double _c = ToDouble($from); _c <= ToDouble($to); _c++) {")
        [void]$sb.AppendLine("${pad}    scope[`"$var`"] = _c;")
        foreach ($s in $Stmt.Body) {
            [void]$sb.AppendLine((ConvertTo-OtterCSharpStatement -Stmt $s -Indent ($Indent + 1)))
        }
        [void]$sb.Append("${pad}}")
        return $sb.ToString()
    }

    if ($Stmt -is [ForEachStmt]) {
        $col = ConvertTo-OtterCSharpExpression -Expr $Stmt.Collection
        $var = $Stmt.VariableName
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine("${pad}foreach (var _item in ToEnumerable($col)) {")
        [void]$sb.AppendLine("${pad}    scope[`"$var`"] = _item;")
        foreach ($s in $Stmt.Body) {
            [void]$sb.AppendLine((ConvertTo-OtterCSharpStatement -Stmt $s -Indent ($Indent + 1)))
        }
        [void]$sb.Append("${pad}}")
        return $sb.ToString()
    }

    if ($Stmt -is [CallStmt]) {
        $args = @(foreach ($a in $Stmt.Call.Arguments) { ConvertTo-OtterCSharpExpression -Expr $a })
        if ($Stmt.ResultTarget) {
            return "${pad}scope[`"$($Stmt.ResultTarget)`"] = $($Stmt.Call.Name)($($args -join ', '));"
        }
        return "${pad}$($Stmt.Call.Name)($($args -join ', '));"
    }

    if ($Stmt -is [TryStmt]) {
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine("${pad}try {")
        foreach ($s in $Stmt.Body) {
            [void]$sb.AppendLine((ConvertTo-OtterCSharpStatement -Stmt $s -Indent ($Indent + 1)))
        }
        [void]$sb.AppendLine("${pad}} catch (Exception _ex) {")
        if ($Stmt.ErrorTarget) {
            [void]$sb.AppendLine("${pad}    scope[`"$($Stmt.ErrorTarget)`"] = _ex.Message;")
        }
        if ($Stmt.OtherwiseBody) {
            foreach ($s in $Stmt.OtherwiseBody) {
                [void]$sb.AppendLine((ConvertTo-OtterCSharpStatement -Stmt $s -Indent ($Indent + 1)))
            }
        }
        [void]$sb.Append("${pad}}")
        return $sb.ToString()
    }

    if ($Stmt -is [ReturnStmt]) {
        if ($null -ne $Stmt.Value) {
            $expr = ConvertTo-OtterCSharpExpression -Expr $Stmt.Value
            return "${pad}return $expr;"
        }
        return "${pad}return null;"
    }

    if ($Stmt -is [FailStmt]) {
        $msg = ConvertTo-OtterCSharpExpression -Expr $Stmt.Message
        return "${pad}throw new Exception(Convert.ToString($msg));"
    }

    return "${pad}// Statement: $($Stmt.Kind)"
}

function ConvertTo-OtterCSharp {
    param(
        [Parameter(Mandatory)][ProgramNode]$Program,
        [string]$ClassName = "OtterProgram"
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("#pragma warning disable 0162")
    [void]$sb.AppendLine("#pragma warning disable 0168")
    [void]$sb.AppendLine("#pragma warning disable 0219")
    [void]$sb.AppendLine("using System;")
    [void]$sb.AppendLine("using System.IO;")
    [void]$sb.AppendLine("using System.Text;")
    [void]$sb.AppendLine("using System.Collections;")
    [void]$sb.AppendLine("using System.Collections.Generic;")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("namespace OtterCompiled {")
    [void]$sb.AppendLine("    public class $ClassName {")
    [void]$sb.AppendLine("        public static Dictionary<string, object> scope = new Dictionary<string, object>();")
    [void]$sb.AppendLine("        public static StringWriter OutputWriter = new StringWriter();")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("        public static void ResetOutput() { OutputWriter = new StringWriter(); }")
    [void]$sb.AppendLine("        public static string GetOutput() { return OutputWriter.ToString(); }")
    [void]$sb.AppendLine("        public static void Say(object val) { string text = Format(val); Console.WriteLine(text); OutputWriter.WriteLine(text); }")
    [void]$sb.AppendLine("        public static void SayParts(object[] parts) {")
    [void]$sb.AppendLine("            if (parts == null || parts.Length == 0) { Say(`"`"); return; }")
    [void]$sb.AppendLine("            var list = new List<string>();")
    [void]$sb.AppendLine("            foreach (var p in parts) list.Add(Format(p));")
    [void]$sb.AppendLine("            Say(string.Join(`" `", list.ToArray()));")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static string Format(object val) {")
    [void]$sb.AppendLine("            if (val == null) return `"gone`";")
    [void]$sb.AppendLine("            if (val is bool) return (bool)val ? `"true`" : `"false`";")
    [void]$sb.AppendLine("            IList list = val as IList;")
    [void]$sb.AppendLine("            if (list != null) {")
    [void]$sb.AppendLine("                var parts = new List<string>();")
    [void]$sb.AppendLine("                foreach (var item in list) parts.Add(Format(item));")
    [void]$sb.AppendLine("                return string.Join(`", `", parts.ToArray());")
    [void]$sb.AppendLine("            }")
    [void]$sb.AppendLine("            return val.ToString();")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static object GetScopeVar(Dictionary<string, object> s, string name) {")
    [void]$sb.AppendLine("            if (s != null && s.ContainsKey(name)) return s[name];")
    [void]$sb.AppendLine("            return null;")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static double ToDouble(object val) {")
    [void]$sb.AppendLine("            if (val == null) return 0;")
    [void]$sb.AppendLine("            if (val is double) return (double)val;")
    [void]$sb.AppendLine("            if (val is int) return (int)val;")
    [void]$sb.AppendLine("            if (val is long) return (long)val;")
    [void]$sb.AppendLine("            if (val is float) return (float)val;")
    [void]$sb.AppendLine("            double res;")
    [void]$sb.AppendLine("            if (double.TryParse(val.ToString(), out res)) return res;")
    [void]$sb.AppendLine("            return 0;")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static bool ToBool(object val) {")
    [void]$sb.AppendLine("            if (val == null) return false;")
    [void]$sb.AppendLine("            if (val is bool) return (bool)val;")
    [void]$sb.AppendLine("            if (val is double) return (double)val != 0;")
    [void]$sb.AppendLine("            if (val is int) return (int)val != 0;")
    [void]$sb.AppendLine("            string str = val as string;")
    [void]$sb.AppendLine("            if (str != null) return !string.IsNullOrEmpty(str) && str != `"false`";")
    [void]$sb.AppendLine("            return true;")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static bool AreEqual(object a, object b) {")
    [void]$sb.AppendLine("            if (a == null && b == null) return true;")
    [void]$sb.AppendLine("            if (a == null || b == null) return false;")
    [void]$sb.AppendLine("            if (a is double || b is double || a is int || b is int || a is long || b is long) {")
    [void]$sb.AppendLine("                return Math.Abs(ToDouble(a) - ToDouble(b)) < 0.0000001;")
    [void]$sb.AppendLine("            }")
    [void]$sb.AppendLine("            return a.Equals(b) || a.ToString() == b.ToString();")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static object Add(object a, object b) {")
    [void]$sb.AppendLine("            if (a is string || b is string) {")
    [void]$sb.AppendLine("                return (a != null ? a.ToString() : `"`") + (b != null ? b.ToString() : `"`");")
    [void]$sb.AppendLine("            }")
    [void]$sb.AppendLine("            IList list = a as IList;")
    [void]$sb.AppendLine("            if (list != null) { list.Add(b); return list; }")
    [void]$sb.AppendLine("            return ToDouble(a) + ToDouble(b);")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static object Subtract(object a, object b) {")
    [void]$sb.AppendLine("            IList list = a as IList;")
    [void]$sb.AppendLine("            if (list != null) { list.Remove(b); return list; }")
    [void]$sb.AppendLine("            return ToDouble(a) - ToDouble(b);")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static object Multiply(object a, object b) { return ToDouble(a) * ToDouble(b); }")
    [void]$sb.AppendLine("        public static object Divide(object a, object b) {")
    [void]$sb.AppendLine("            double d = ToDouble(b);")
    [void]$sb.AppendLine("            if (d == 0) throw new DivideByZeroException(`"Otter: Division by zero.`");")
    [void]$sb.AppendLine("            return ToDouble(a) / d;")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static object Percent(object a, object b) { return (ToDouble(a) / 100.0) * ToDouble(b); }")
    [void]$sb.AppendLine("        public static bool Contains(object collection, object item) {")
    [void]$sb.AppendLine("            if (collection == null) return false;")
    [void]$sb.AppendLine("            string s = collection as string;")
    [void]$sb.AppendLine("            if (s != null && item != null) return s.Contains(item.ToString());")
    [void]$sb.AppendLine("            IList list = collection as IList;")
    [void]$sb.AppendLine("            if (list != null) { foreach (var elem in list) { if (AreEqual(elem, item)) return true; } }")
    [void]$sb.AppendLine("            return false;")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static double Length(object val) {")
    [void]$sb.AppendLine("            if (val == null) return 0;")
    [void]$sb.AppendLine("            string s = val as string;")
    [void]$sb.AppendLine("            if (s != null) return s.Length;")
    [void]$sb.AppendLine("            ICollection c = val as ICollection;")
    [void]$sb.AppendLine("            if (c != null) return c.Count;")
    [void]$sb.AppendLine("            return 0;")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static string Uppercase(object val) { return val != null ? val.ToString().ToUpperInvariant() : `"`"; }")
    [void]$sb.AppendLine("        public static string Lowercase(object val) { return val != null ? val.ToString().ToLowerInvariant() : `"`"; }")
    [void]$sb.AppendLine("        public static object First(object val) {")
    [void]$sb.AppendLine("            IList list = val as IList; if (list != null && list.Count > 0) return list[0];")
    [void]$sb.AppendLine("            string s = val as string; if (s != null && s.Length > 0) return s[0].ToString();")
    [void]$sb.AppendLine("            return null;")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static object Last(object val) {")
    [void]$sb.AppendLine("            IList list = val as IList; if (list != null && list.Count > 0) return list[list.Count - 1];")
    [void]$sb.AppendLine("            string s = val as string; if (s != null && s.Length > 0) return s[s.Length - 1].ToString();")
    [void]$sb.AppendLine("            return null;")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static object GetProperty(object target, string prop) {")
    [void]$sb.AppendLine("            IDictionary<string, object> dict = target as IDictionary<string, object>;")
    [void]$sb.AppendLine("            if (dict != null && dict.ContainsKey(prop)) return dict[prop];")
    [void]$sb.AppendLine("            return null;")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static void SetProperty(object target, string prop, object val) {")
    [void]$sb.AppendLine("            IDictionary<string, object> dict = target as IDictionary<string, object>;")
    [void]$sb.AppendLine("            if (dict != null) dict[prop] = val;")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static object GetDynamicKey(object target, object key) {")
    [void]$sb.AppendLine("            if (key == null) return null;")
    [void]$sb.AppendLine("            return GetProperty(target, key.ToString());")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static void SetDynamicKey(object target, object key, object val) {")
    [void]$sb.AppendLine("            if (key != null) SetProperty(target, key.ToString(), val);")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static void SortList(object col) {")
    [void]$sb.AppendLine("            List<object> lo = col as List<object>;")
    [void]$sb.AppendLine("            if (lo != null) {")
    [void]$sb.AppendLine("                lo.Sort((a, b) => string.Compare(Format(a), Format(b), StringComparison.Ordinal));")
    [void]$sb.AppendLine("            }")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static void ReverseList(object col) {")
    [void]$sb.AppendLine("            List<object> lo = col as List<object>;")
    [void]$sb.AppendLine("            if (lo != null) { lo.Reverse(); }")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static string ReplaceText(object target, object oldVal, object newVal) {")
    [void]$sb.AppendLine("            string s = target != null ? target.ToString() : `"`";")
    [void]$sb.AppendLine("            string o = oldVal != null ? oldVal.ToString() : `"`";")
    [void]$sb.AppendLine("            string n = newVal != null ? newVal.ToString() : `"`";")
    [void]$sb.AppendLine("            return s.Replace(o, n);")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static List<object> SplitText(object text, object delim) {")
    [void]$sb.AppendLine("            string s = text != null ? text.ToString() : `"`";")
    [void]$sb.AppendLine("            string d = delim != null ? delim.ToString() : `"`";")
    [void]$sb.AppendLine("            string[] parts = string.IsNullOrEmpty(d) ? new string[] { s } : s.Split(new string[] { d }, StringSplitOptions.None);")
    [void]$sb.AppendLine("            var res = new List<object>();")
    [void]$sb.AppendLine("            foreach (var p in parts) res.Add(p);")
    [void]$sb.AppendLine("            return res;")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static string JoinList(object col, object delim) {")
    [void]$sb.AppendLine("            IList list = col as IList;")
    [void]$sb.AppendLine("            string d = delim != null ? delim.ToString() : `"`";")
    [void]$sb.AppendLine("            if (list == null) return `"`";")
    [void]$sb.AppendLine("            var parts = new List<string>();")
    [void]$sb.AppendLine("            foreach (var item in list) parts.Add(Format(item));")
    [void]$sb.AppendLine("            return string.Join(d, parts.ToArray());")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static bool IsFileLocked(string path) {")
    [void]$sb.AppendLine("            if (!File.Exists(path)) return false;")
    [void]$sb.AppendLine("            try {")
    [void]$sb.AppendLine("                using (FileStream stream = File.Open(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None)) { stream.Close(); }")
    [void]$sb.AppendLine("                return false;")
    [void]$sb.AppendLine("            } catch (IOException) { return true; }")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static void WriteFileWithAtomic(string path, string content, bool atomic) {")
    [void]$sb.AppendLine("            if (!atomic) { File.WriteAllText(path, content); return; }")
    [void]$sb.AppendLine("            string tempPath = path + `".`" + Guid.NewGuid().ToString(`"N`") + `".tmp`";")
    [void]$sb.AppendLine("            File.WriteAllText(tempPath, content);")
    [void]$sb.AppendLine("            if (File.Exists(path)) { File.Delete(path); }")
    [void]$sb.AppendLine("            File.Move(tempPath, path);")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static string ConvertToJsonString(object val) {")
    [void]$sb.AppendLine("            return Format(val);")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static object ConvertFromJsonString(string text) {")
    [void]$sb.AppendLine("            return text;")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static object ReadJsonFile(string path) {")
    [void]$sb.AppendLine("            if (File.Exists(path)) return ConvertFromJsonString(File.ReadAllText(path));")
    [void]$sb.AppendLine("            return null;")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("        public static IEnumerable ToEnumerable(object val) {")
    [void]$sb.AppendLine("            IEnumerable e = val as IEnumerable;")
    [void]$sb.AppendLine("            if (e != null && !(val is string)) return e;")
    [void]$sb.AppendLine("            return new List<object> { val };")
    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine()

    # Function definitions
    foreach ($stmt in $Program.Statements) {
        if ($stmt -is [FunctionDefStmt]) {
            $params = @(foreach ($p in $stmt.Parameters) { "object var_$p" })
            [void]$sb.AppendLine("        public static object $($stmt.Name)($($params -join ', ')) {")
            $i = 0
            foreach ($p in $stmt.Parameters) {
                [void]$sb.AppendLine("            scope[`"$p`"] = var_$p;")
                $i++
            }
            foreach ($s in $stmt.Body) {
                [void]$sb.AppendLine((ConvertTo-OtterCSharpStatement -Stmt $s -Indent 3))
            }
            [void]$sb.AppendLine("            return null;")
            [void]$sb.AppendLine("        }")
            [void]$sb.AppendLine()
        }
    }

    # Main Entry Point
    [void]$sb.AppendLine("        public static void Run() {")
    [void]$sb.AppendLine("            ResetOutput();")
    [void]$sb.AppendLine("            scope.Clear();")
    [void]$sb.AppendLine()

    foreach ($stmt in $Program.Statements) {
        if ($stmt -isnot [FunctionDefStmt]) {
            [void]$sb.AppendLine((ConvertTo-OtterCSharpStatement -Stmt $stmt -Indent 3))
        }
    }

    [void]$sb.AppendLine("        }")
    [void]$sb.AppendLine("    }")
    [void]$sb.AppendLine("}")

    return $sb.ToString()
}

function Invoke-OtterCompiledProgram {
    param(
        [Parameter(Mandatory)][ProgramNode]$Program
    )

    $className = "OtterProgram_" + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $csharpCode = ConvertTo-OtterCSharp -Program $Program -ClassName $className

    # Compile program class in-memory using Add-Type with -PassThru
    $types = Add-Type -TypeDefinition $csharpCode -Language CSharp -PassThru
    $type = @($types | Where-Object { $_.Name -eq $className })[0]

    # Invoke compiled Run method
    $method = $type.GetMethod("Run")
    [void]$method.Invoke($null, $null)

    # Capture output
    $getOutputMethod = $type.GetMethod("GetOutput")
    $output = [string]$getOutputMethod.Invoke($null, $null)

    return $output
}

function Export-OtterCSharpProject {
    param(
        [Parameter(Mandatory)][ProgramNode]$Program,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [string]$ProjectName = "OtterCompiledApp"
    )

    if (-not (Test-Path $OutputDirectory)) {
        [void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
    }

    $csharpCode = ConvertTo-OtterCSharp -Program $Program -ClassName "Program"

    # Wrap Program with a static Main entry point for standalone execution
    $standaloneSource = $csharpCode -replace 'public static void Run\(\)', 'public static void Main(string[] args)'

    $programCsPath = Join-Path $OutputDirectory "Program.cs"
    [System.IO.File]::WriteAllText($programCsPath, $standaloneSource, [System.Text.Encoding]::UTF8)

    $csprojPath = Join-Path $OutputDirectory "$ProjectName.csproj"
    $csprojContent = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>disable</Nullable>
    <PublishAot>false</PublishAot>
  </PropertyGroup>
</Project>
"@
    [System.IO.File]::WriteAllText($csprojPath, $csprojContent, [System.Text.Encoding]::UTF8)

    return $csprojPath
}
