// OtterNativeRuntime.cs - the runtime library for Otter's experimental
// compiled backend (docs/OTTER_NATIVE_COMPILER_DESIGN.md).
//
// Generated C# calls these helpers instead of raw .NET wherever Otter's rules
// differ from .NET's. Each helper mirrors one interpreter function and names
// it; the interpreter (src/Otter.Interpreter.psm1, src/Otter.Runtime.psm1) is
// the reference, and the messages here are its messages, word for word.
//
// C# 5 only (decided 2026-09-30): Windows PowerShell 5.1's Add-Type compiles
// nothing newer. No string interpolation, expression-bodied members, `?.`,
// `nameof` or `out var`.

using System;
using System.Collections.Generic;
using System.Globalization;

namespace OtterNative
{
    // An Otter runtime error: the interpreter's New-OtterRuntimeError.
    public sealed class OtterNativeError : Exception
    {
        public int Line;
        public string Suggestion;
        public OtterNativeError(string message, int line, string suggestion) : base(message)
        {
            Line = line;
            Suggestion = suggestion;
        }
    }

    // OtterEnvironment (src/Otter.Runtime.psm1): ordinal names, a parent chain,
    // Set updates the variable where it already lives, SetLocal shadows.
    public sealed class Env
    {
        public readonly Dictionary<string, object> Vars = new Dictionary<string, object>(StringComparer.Ordinal);
        public readonly Env Parent;
        public Env(Env parent) { Parent = parent; }

        public bool Has(string name)
        {
            for (Env e = this; e != null; e = e.Parent) { if (e.Vars.ContainsKey(name)) return true; }
            return false;
        }

        public object GetRaw(string name)
        {
            for (Env e = this; e != null; e = e.Parent)
            {
                object value;
                if (e.Vars.TryGetValue(name, out value)) return value;
            }
            return null;
        }

        public void SetLocal(string name, object value) { Vars[name] = value; }

        public void Set(string name, object value)
        {
            if (Vars.ContainsKey(name)) { Vars[name] = value; return; }
            if (Parent != null && Parent.Has(name)) { Parent.Set(name, value); return; }
            Vars[name] = value;
        }
    }

    public delegate object OtterBody(Env e);

    // OtterFunction: a name, its parameters and its compiled body.
    public sealed class OtterFn
    {
        public readonly string Name;
        public readonly string[] Params;
        public readonly OtterBody Body;
        public OtterFn(string name, string[] parameters, OtterBody body) { Name = name; Params = parameters; Body = body; }
    }

    public static class R
    {
        public static Action<string> Out;
        public static Env Global;
        static int depth;

        public static void Reset(Env global, Action<string> output) { Global = global; Out = output; depth = 0; }

        public static OtterNativeError Err(string message, int line, string suggestion)
        {
            return new OtterNativeError(message, line, suggestion);
        }

        static bool IsNumber(object v) { return v is double || v is int || v is long || v is decimal; }

        // Format-OtterValue
        public static string Format(object v)
        {
            if (v == null) return "gone";
            if (v is bool) return ((bool)v) ? "true" : "false";
            if (IsNumber(v))
            {
                double n = Convert.ToDouble(v, CultureInfo.InvariantCulture);
                bool finite = !double.IsNaN(n) && !double.IsInfinity(n);
                if (finite && Math.Floor(n) == n && Math.Abs(n) < 1e15) return n.ToString("0", CultureInfo.InvariantCulture);
                return n.ToString("0.##########", CultureInfo.InvariantCulture);
            }
            List<object> list = v as List<object>;
            if (list != null)
            {
                string[] parts = new string[list.Count];
                for (int i = 0; i < list.Count; i++) parts[i] = Format(list[i]);
                return string.Join(", ", parts);
            }
            OtterFn fn = v as OtterFn;
            if (fn != null) return "<" + fn.Name + ", something Otter can do>";
            return Convert.ToString(v, CultureInfo.InvariantCulture);
        }

        // Get-OtterTypeName
        public static string TypeName(object v)
        {
            if (v == null) return "gone";
            if (v is bool) return "a true or false value";
            if (v is OtterFn) return "something Otter can do";
            if (v is List<object>) return "a list";
            if (v is double || v is int || v is long) return "a number";
            if (v is string) return "some text";
            return "a value Otter does not recognise";
        }

        // Test-OtterTruthy
        public static bool Truthy(object v)
        {
            if (v == null) return false;
            if (v is bool) return (bool)v;
            if (v is double || v is int || v is long) return Convert.ToDouble(v, CultureInfo.InvariantCulture) != 0;
            List<object> list = v as List<object>;
            if (list != null) return list.Count > 0;
            string s = v as string;
            if (s != null) return s.Length > 0;
            return true;
        }

        // Test-OtterNumeric / ConvertTo-OtterNumber
        static bool TryNumber(object v, out double n)
        {
            n = 0;
            if (v is bool) return false;
            if (IsNumber(v)) { n = Convert.ToDouble(v, CultureInfo.InvariantCulture); return true; }
            string s = v as string;
            if (s != null) return double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out n);
            return false;
        }

        // Assert-OtterNumber
        public static double AssertNumber(object v, int line, string what)
        {
            if (v is double) return (double)v;
            double n;
            if (TryNumber(v, out n)) return n;
            string shown = Format(v);
            if (v is string) shown = "\"" + (string)v + "\"";
            throw Err("I expected a number for " + what + " but got " + shown + ".", line, null);
        }

        // Test-OtterEqual
        public static bool Equal(object a, object b)
        {
            if ((a is double || a is int || a is long) && (b is double || b is int || b is long))
                return Convert.ToDouble(a, CultureInfo.InvariantCulture) == Convert.ToDouble(b, CultureInfo.InvariantCulture);
            if (a == null && b == null) return true;
            if (a == null || b == null) return false;
            if (a is bool || b is bool)
            {
                if (a is bool && b is bool) return (bool)a == (bool)b;
                return false;
            }
            double na, nb;
            if (TryNumber(a, out na) && TryNumber(b, out nb)) return na == nb;
            List<object> la = a as List<object>, lb = b as List<object>;
            if (la != null && lb != null)
            {
                if (la.Count != lb.Count) return false;
                for (int i = 0; i < la.Count; i++) { if (!Equal(la[i], lb[i])) return false; }
                return true;
            }
            return string.Equals(Convert.ToString(a, CultureInfo.InvariantCulture), Convert.ToString(b, CultureInfo.InvariantCulture), StringComparison.Ordinal);
        }

        // Get-OtterValue 'Variable'
        public static object Get(Env e, string name, int line)
        {
            if (!e.Has(name))
                throw Err("Otter could not find the variable \"" + name + "\". It has not been given a value yet.", line, name + " is 0");
            return e.GetRaw(name);
        }

        // Get-OtterValue 'Math': 0 add, 1 subtract, 2 multiply, 3 divide, 4 percent, 5 power
        public static object Arith(int op, object left, object right, int line)
        {
            if (op == 0 && left is string && right is string) return (string)left + (string)right;
            if (op == 0 && (left is bool || right is bool))
                throw Err("A true/false value cannot be combined with \"and\" here. Boolean \"and\"/\"or\" only work inside an if or while condition.", line, "if condition1 and condition2");
            double l = left is double ? (double)left : AssertNumber(left, line, "the left side of this calculation");
            double r = right is double ? (double)right : AssertNumber(right, line, "the right side of this calculation");
            switch (op)
            {
                case 0: return l + r;
                case 1: return l - r;
                case 2: return l * r;
                case 3:
                    if (r == 0) throw Err("I cannot divide by zero.", line, null);
                    return l / r;
                case 4: return (l / 100.0) * r;
                case 5: return Math.Pow(l, r);
            }
            return null;
        }

        // Get-OtterValue 'Comparison': 0 equal, 1 not equal, 2 at least, 3 at most, 4 greater than, 5 less than
        public static object Compare(int op, object left, object right, int line)
        {
            if (op == 0) return Equal(left, right);
            if (op == 1) return !Equal(left, right);
            double l = left is double ? (double)left : AssertNumber(left, line, "the left side of this comparison");
            double r = right is double ? (double)right : AssertNumber(right, line, "the right side of this comparison");
            switch (op)
            {
                case 2: return l >= r;
                case 3: return l <= r;
                case 4: return l > r;
                case 5: return l < r;
            }
            return false;
        }

        // Get-OtterValue 'Contains'
        public static object Contains(object collection, object item, int line)
        {
            string s = collection as string;
            if (s != null) return s.Contains(Format(item));
            List<object> list = collection as List<object>;
            if (list == null)
                throw Err("Only text or a list can contain something, but this is " + TypeName(collection) + ".", line, null);
            foreach (object entry in list) { if (Equal(entry, item)) return true; }
            return false;
        }

        // 'OfOperation' Length
        public static object Length(object subject, int line)
        {
            List<object> list = subject as List<object>;
            if (list != null) return (double)list.Count;
            string s = subject as string;
            if (s != null) return (double)s.Length;
            throw Err("I can only measure the length of text, a list, or bytes, but this is " + TypeName(subject) + ".", line, null);
        }

        public static List<object> List(object[] items) { return new List<object>(items); }

        // 'Say' without a color
        public static void Say(object[] parts)
        {
            string[] rendered = new string[parts.Length];
            for (int i = 0; i < parts.Length; i++) rendered[i] = Format(parts[i]);
            Out(string.Join(" ", rendered));
        }

        // Invoke-OtterAddTo / Invoke-OtterRemoveFrom: the variable must exist
        // before the amount is worked out.
        public static void RequireVariable(Env e, string name, int line, string suggestion)
        {
            if (!e.Has(name)) throw Err("Otter could not find the variable \"" + name + "\".", line, suggestion);
        }

        public static void AddTo(Env e, string name, object amount, int line)
        {
            object current = e.GetRaw(name);
            List<object> list = current as List<object>;
            if (list != null) { list.Add(amount); return; }
            double c;
            if (TryNumber(current, out c))
            {
                double add = AssertNumber(amount, line, "the amount to add to \"" + name + "\"");
                e.Set(name, c + add);
                return;
            }
            throw Err("I can only add to a number or a list, but \"" + name + "\" holds " + TypeName(current) + ".", line, null);
        }

        public static void RemoveFrom(Env e, string name, object amount, int line)
        {
            object current = e.GetRaw(name);
            List<object> list = current as List<object>;
            if (list != null)
            {
                for (int i = 0; i < list.Count; i++) { if (Equal(list[i], amount)) { list.RemoveAt(i); return; } }
                return;
            }
            double c;
            if (TryNumber(current, out c))
            {
                double sub = AssertNumber(amount, line, "the amount to remove from \"" + name + "\"");
                e.Set(name, c - sub);
                return;
            }
            throw Err("I can only remove from a number or a list, but \"" + name + "\" holds " + TypeName(current) + ".", line, null);
        }

        // 'ForEach': only a list can be walked; the walk uses a snapshot.
        public static object[] Walk(object collection, int line)
        {
            List<object> list = collection as List<object>;
            if (list == null) throw Err("I can only go through a list, but this is " + TypeName(collection) + ".", line, null);
            return list.ToArray();
        }

        // Invoke-OtterCall, split in two so the checks happen before the
        // arguments are worked out, as in the interpreter.
        public static OtterFn Resolve(Env e, string name, int given, int line)
        {
            if (!e.Has(name)) throw Err("Otter could not find anything called \"" + name + "\".", line, "to " + name);
            object target = e.GetRaw(name);
            OtterFn fn = target as OtterFn;
            if (fn == null) throw Err("\"" + name + "\" is not something Otter can do - it holds " + TypeName(target) + ".", line, null);
            int expected = fn.Params.Length;
            if (given != expected)
            {
                string word = expected == 1 ? "value" : "values";
                throw Err("\"" + name + "\" needs " + expected + " " + word + " but was given " + given + ".", line, name + " " + string.Join(" ", fn.Params));
            }
            return fn;
        }

        public static object Invoke(OtterFn fn, object[] args, int line)
        {
            Env local = new Env(Global);
            for (int i = 0; i < fn.Params.Length; i++) local.SetLocal(fn.Params[i], args[i]);
            if (depth >= 250)
                throw Err("Call depth limit exceeded (possible infinite recursion).", line, "Check for infinite recursion or reduce call nesting.");
            depth++;
            try { return fn.Body(local); }
            finally { depth--; }
        }
    }
}
