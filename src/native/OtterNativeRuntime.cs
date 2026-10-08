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
using System.IO;
using System.Reflection;
using System.Text;

namespace OtterNative
{
    // An Otter runtime error: the interpreter's New-OtterRuntimeError.
    public sealed class OtterNativeError : Exception
    {
        public int Line;
        public string Suggestion;
        // Library functions raise their errors without the source line; the
        // interpreter then shows none, and so must the compiled backend.
        public bool ShowSourceLine = true;
        public OtterNativeError(string message, int line, string suggestion) : base(message)
        {
            Line = line;
            Suggestion = suggestion;
        }
    }

    // A top-level `stop`: the interpreter's OtterReturnSignal, which passes
    // through every `try` and becomes an error only at program level. A
    // separate type so generated `try` blocks can let it through.
    public sealed class OtterStopSignal : Exception
    {
        public int Line;
        public OtterStopSignal(int line) : base("stop only works inside something Otter can call, like a function. There is nothing here to stop.") { Line = line; }
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

    // The library bridge: library statements (JSON, files, ...) run the
    // interpreter's own PowerShell functions, so their behaviour is the
    // interpreter's by construction. The host returns an OtterNativeError as
    // a value instead of throwing it across the boundary. The result goes into
    // a HostResult rather than being returned: PowerShell wraps a returned
    // object in a PSObject, but passes the object itself to a property.
    // One object carries the whole call: PowerShell's delegate invocation
    // reshapes an object[] argument, so nothing else is passed.
    public sealed class HostRequest
    {
        public string Name;
        public object[] Args;
        public int Line;
        public object Result;
    }
    public delegate void HostCall(HostRequest request);

    // OtterObject (src/Otter.Runtime.psm1): a type name and ordinal properties
    // in insertion order. Only plain things for now ("x is a thing", "x has").
    public sealed class OtterThing
    {
        public readonly string TypeName;
        readonly Dictionary<string, object> props = new Dictionary<string, object>(StringComparer.Ordinal);
        readonly List<string> order = new List<string>();
        public OtterThing(string typeName) { TypeName = typeName; }
        public bool Has(string name) { return props.ContainsKey(name); }
        public object Read(string name) { object v; return props.TryGetValue(name, out v) ? v : null; }
        public void Write(string name, object value)
        {
            if (!props.ContainsKey(name)) order.Add(name);
            props[name] = value;
        }
        public List<string> Names() { return order; }
        public override string ToString() { return "OtterObject"; }   // PowerShell's [string] of an OtterObject
    }

    // OtterType: "a Person has name, age".
    // OtterDate (D32): "today" has no time of day and is pinned to midnight;
    // "now" keeps its time. Shown as ISO text, formatted exactly as the
    // interpreter's ToString (current culture).
    public sealed class OtterDateValue
    {
        public readonly DateTime Value;
        public readonly bool HasTime;
        public OtterDateValue(DateTime value, bool hasTime) { HasTime = hasTime; Value = hasTime ? value : value.Date; }
        public override string ToString() { return HasTime ? Value.ToString("yyyy-MM-dd HH:mm:ss") : Value.ToString("yyyy-MM-dd"); }
    }

    public sealed class OtterTypeValue
    {
        public readonly string Name;
        public readonly string[] Fields;
        public OtterTypeValue(string name, string[] fields) { Name = name; Fields = fields; }
        public override string ToString() { return "OtterType"; }
    }

    // OtterFunction: a name, its parameters and its compiled body.
    public sealed class OtterFn
    {
        public readonly string Name;
        public readonly string[] Params;
        public readonly OtterBody Body;
        public OtterFn(string name, string[] parameters, OtterBody body) { Name = name; Params = parameters; Body = body; }
        public override string ToString() { return "OtterFunction"; }
    }

    public sealed class OtterBytesValue
    {
        public readonly byte[] Value;
        public OtterBytesValue(byte[] value) { Value = value ?? new byte[0]; }
        public override string ToString() { return "OtterBytes"; }
    }

    public sealed class OtterNetHandler
    {
        public readonly string EventKind;
        public readonly OtterBody Body;
        public readonly Env Environment;
        public OtterNetHandler(string eventKind, OtterBody body, Env env)
        {
            EventKind = eventKind;
            Body = body;
            Environment = env;
        }
    }

    public sealed class OtterUdpSocket
    {
        public readonly System.Net.Sockets.UdpClient Client;
        public readonly int Port;
        public bool IsClosed;
        public readonly List<OtterNetHandler> Handlers = new List<OtterNetHandler>();

        public OtterUdpSocket(System.Net.Sockets.UdpClient client, int port)
        {
            Client = client;
            Port = port;
            IsClosed = false;
        }

        public void Close()
        {
            if (IsClosed) return;
            IsClosed = true;
            try { Client.Close(); } catch { }
        }
        public override string ToString() { return "OtterUdp"; }
    }

    public static class R
    {
        public static Action<string> Out;
        public static HostCall Host;

        public static object Call(string name, object[] args, int line)
        {
            // Without PowerShell (otter.exe's fast start) the library answers
            // in C#: OtterLibrary mirrors Windows PowerShell 5.1's behaviour.
            if (Host == null)
            {
                if (OtterLibrary.Supports(name)) return OtterLibrary.Call(name, args, line);
                throw Err("The compiled backend has no library bridge for " + name + ".", line, null);
            }
            HostRequest request = new HostRequest();
            request.Name = name;
            request.Args = args;
            request.Line = line;
            Host(request);
            OtterNativeError error = request.Result as OtterNativeError;
            if (error != null) throw error;
            return request.Result;
        }
        public static Env Global;
        static int depth;

        public static void Reset(Env global, Action<string> output) { Global = global; Out = output; depth = 0; activeSockets.Clear(); }

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
            OtterDateValue date = v as OtterDateValue;
            if (date != null) return date.ToString();
            OtterThing thing = v as OtterThing;
            if (thing != null) return "a " + thing.TypeName;
            OtterTypeValue type = v as OtterTypeValue;
            if (type != null) return "the type " + type.Name;
            OtterFn fn = v as OtterFn;
            if (fn != null) return "<" + fn.Name + ", something Otter can do>";
            // D102: bytes never show as hex or text, only their count.
            OtterBytesValue bytesValue = v as OtterBytesValue;
            if (bytesValue != null) return "<" + bytesValue.Value.Length + " bytes>";
            if (v is OtterUdpSocket) return "a udp socket";
            return Convert.ToString(v, CultureInfo.InvariantCulture);
        }

        // Get-OtterTypeName
        public static string TypeName(object v)
        {
            if (v == null) return "gone";
            if (v is bool) return "a true or false value";
            if (v is OtterFn) return "something Otter can do";
            if (v is OtterBytesValue) return "bytes";
            if (v is OtterUdpSocket) return "a udp socket";
            OtterDateValue dateValue = v as OtterDateValue;
            if (dateValue != null) return dateValue.HasTime ? "a date and time" : "a date";
            OtterThing thingValue = v as OtterThing;
            if (thingValue != null) return "a " + thingValue.TypeName;
            OtterTypeValue typeValue = v as OtterTypeValue;
            if (typeValue != null) return "the type " + typeValue.Name;
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
            // Two dates compare by their instant; a date never equals anything else.
            if (a is OtterDateValue || b is OtterDateValue)
            {
                OtterDateValue da = a as OtterDateValue, db = b as OtterDateValue;
                return da != null && db != null && da.Value == db.Value;
            }
            // D102: two bytes values are equal when their contents are; bytes
            // never equal anything else.
            if (a is OtterBytesValue || b is OtterBytesValue)
            {
                OtterBytesValue ba = a as OtterBytesValue, bb = b as OtterBytesValue;
                if (ba == null || bb == null || ba.Value.Length != bb.Value.Length) return false;
                for (int i = 0; i < ba.Value.Length; i++) { if (ba.Value[i] != bb.Value[i]) return false; }
                return true;
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
            if (a is OtterThing || b is OtterThing) return ReferenceEquals(a, b);
            return string.Equals(PsText(a), PsText(b), StringComparison.Ordinal);
        }

        // PowerShell's [string] of a value - what Test-OtterEqual compares last:
        // a list is its items joined by spaces, a class its PowerShell name.
        internal static string PsText(object v)
        {
            if (v == null) return "";
            if (v is bool) return ((bool)v) ? "True" : "False";
            if (v is double) return ((double)v).ToString(CultureInfo.InvariantCulture);
            List<object> list = v as List<object>;
            if (list != null)
            {
                string[] parts = new string[list.Count];
                for (int i = 0; i < list.Count; i++) parts[i] = PsText(list[i]);
                return string.Join(" ", parts);
            }
            return Convert.ToString(v, CultureInfo.InvariantCulture);
        }

        // New-OtterObjectValue: "jeff is a Person": a declared type's fields
        // start as gone. An undeclared type name is not an error.
        public static OtterThing NewObject(Env e, string typeName)
        {
            OtterThing thing = new OtterThing(typeName);
            if (typeName != "thing" && e.Has(typeName))
            {
                OtterTypeValue declared = e.GetRaw(typeName) as OtterTypeValue;
                if (declared != null) { foreach (string field in declared.Fields) thing.Write(field, null); }
            }
            return thing;
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
            OtterDateValue dl = left as OtterDateValue, dr = right as OtterDateValue;
            if (dl != null && dr != null)
            {
                int c = dl.Value.CompareTo(dr.Value);
                switch (op) { case 2: return c >= 0; case 3: return c <= 0; case 4: return c > 0; case 5: return c < 0; }
            }
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

        // Returns object, so generated code never names a collection type (on
        // PowerShell 7, Add-Type with -ReferencedAssemblies drops the default
        // references, and List<> lives in System.Collections there).
        public static object List(object[] items) { return new List<object>(items); }

        // 'OfOperation' text and math operations (D24, D89, D90). Angles are in
        // degrees. A number in an error message is written as PowerShell
        // writes a double inside a string.
        static string Num(double n) { return n.ToString(CultureInfo.InvariantCulture); }

        public static object Of(int op, object subject, int line)
        {
            switch (op)
            {
                case 1: return Format(subject).ToUpperInvariant();
                case 2: return Format(subject).ToLowerInvariant();
                case 5: return Math.Abs(AssertNumber(subject, line, "the absolute value"));
                case 6:
                {
                    double n = AssertNumber(subject, line, "the square root");
                    if (n < 0) throw Err("I can't take the square root of a negative number (" + Num(n) + ").", line, null);
                    return Math.Sqrt(n);
                }
                case 7: return Math.Round(AssertNumber(subject, line, "rounding"), 0, MidpointRounding.AwayFromZero);
                case 8: return Math.Ceiling(AssertNumber(subject, line, "rounding"));
                case 9: return Math.Floor(AssertNumber(subject, line, "rounding"));
                case 10: return Math.Sin(AssertNumber(subject, line, "sine") * Math.PI / 180.0);
                case 11: return Math.Cos(AssertNumber(subject, line, "cosine") * Math.PI / 180.0);
                case 12: return Math.Tan(AssertNumber(subject, line, "tangent") * Math.PI / 180.0);
                case 13:
                {
                    double n = AssertNumber(subject, line, "a logarithm");
                    if (n <= 0) throw Err("I can't take the log of a number that isn't positive (" + Num(n) + ").", line, null);
                    return Math.Log10(n);
                }
                case 14:
                {
                    double n = AssertNumber(subject, line, "a logarithm");
                    if (n <= 0) throw Err("I can't take the natural log of a number that isn't positive (" + Num(n) + ").", line, null);
                    return Math.Log(n);
                }
            }
            throw Err("internal: unknown operation " + op, line, null);
        }

        // 'Replace' (D27): plain text, no patterns; the variable is read first.
        public static string ReplaceSubject(Env e, string name, int line)
        {
            if (!e.Has(name)) throw Err("Otter could not find the variable \"" + name + "\".", line, null);
            return Format(e.GetRaw(name));
        }

        public static object Replace(string subject, object find, object replacement, int line)
        {
            string f = Format(find);
            string r = Format(replacement);
            if (f.Length == 0) throw Err("I cannot replace empty text.", line, null);
            return subject.Replace(f, r);
        }

        // 'Split' / 'Join' (D25).
        public static object Split(object subject, object separator, int line)
        {
            string s = Format(subject);
            string sep = Format(separator);
            if (sep.Length == 0) throw Err("I need something to split by.", line, null);
            string[] pieces = s.Split(new string[] { sep }, StringSplitOptions.None);
            List<object> list = new List<object>(pieces.Length);
            foreach (string piece in pieces) list.Add(piece);
            return list;
        }

        public static object JoinList(object value, int line)
        {
            List<object> list = value as List<object>;
            if (list == null) throw Err("I can only join a list, but this is " + TypeName(value) + ".", line, null);
            return list;
        }

        public static object Join(object listValue, object separator)
        {
            List<object> list = (List<object>)listValue;
            string sep = Format(separator);
            string[] parts = new string[list.Count];
            for (int i = 0; i < list.Count; i++) parts[i] = Format(list[i]);
            return string.Join(sep, parts);
        }

        // --- dates (D32, D42, D101) ---------------------------------------

        public static object Clock(bool now) { return new OtterDateValue(DateTime.Now, now); }

        // Assert-OtterUnitAllowed: a plain date has no hour, minute or second.
        static void UnitAllowed(OtterDateValue date, string unit, int line)
        {
            if (date.HasTime || unit == "Year" || unit == "Month" || unit == "Day") return;
            throw Err("This is a date with no time of day, so it has no " + unit.ToLowerInvariant() + ".", line, "started is now");
        }

        // Get-OtterDatePart (PowerShell's switch is case-insensitive).
        static object DatePart(OtterDateValue date, string part, int line)
        {
            switch ((part ?? "").ToLowerInvariant())
            {
                case "year": return (double)date.Value.Year;
                case "month": return (double)date.Value.Month;
                case "day": return (double)date.Value.Day;
                case "hour": UnitAllowed(date, "Hour", line); return (double)date.Value.Hour;
                case "minute": UnitAllowed(date, "Minute", line); return (double)date.Value.Minute;
                case "second": UnitAllowed(date, "Second", line); return (double)date.Value.Second;
            }
            throw Err("A date has no part called \"" + part + "\".", line, "year of ...");
        }

        // 'DateAdjust': the variable and its type are checked before the amount.
        public static OtterDateValue DateTarget(Env e, string name, int line)
        {
            if (!e.Has(name)) throw Err("Otter could not find the variable \"" + name + "\".", line, null);
            object current = e.GetRaw(name);
            OtterDateValue date = current as OtterDateValue;
            if (date == null) throw Err("I can only add time to a date, but \"" + name + "\" holds " + TypeName(current) + ".", line, null);
            return date;
        }

        public static object DateAdjust(OtterDateValue date, object amountValue, string unit, bool removal, int line)
        {
            double amount = AssertNumber(amountValue, line, "the amount of time");
            int whole = (int)Math.Truncate(amount);
            if (removal) whole = -whole;
            UnitAllowed(date, unit, line);
            DateTime moved;
            switch (unit)
            {
                case "Year": moved = date.Value.AddYears(whole); break;
                case "Month": moved = date.Value.AddMonths(whole); break;
                case "Day": moved = date.Value.AddDays(whole); break;
                case "Hour": moved = date.Value.AddHours(whole); break;
                case "Minute": moved = date.Value.AddMinutes(whole); break;
                default: moved = date.Value.AddSeconds(whole); break;
            }
            return new OtterDateValue(moved, date.HasTime);
        }

        // Assert-OtterDateOperands + Measure-OtterDateDifference: whole units,
        // truncated toward zero, signed end minus start.
        public static object DateDifference(object start, object end, string unit, int line)
        {
            OtterDateValue from = start as OtterDateValue;
            if (from == null) throw Err("I can only measure time between two dates, but the first one is " + TypeName(start) + ".", line, null);
            OtterDateValue to = end as OtterDateValue;
            if (to == null) throw Err("I can only measure time between two dates, but the second one is " + TypeName(end) + ".", line, null);
            DateTime f = from.Value, t = to.Value;
            if (unit == "Year" || unit == "Month")
            {
                int months = ((t.Year - f.Year) * 12) + (t.Month - f.Month);
                if (months > 0 && t.Day < f.Day) months--;
                if (months < 0 && t.Day > f.Day) months++;
                if (unit == "Month") return (double)months;
                return Math.Truncate(months / 12.0);
            }
            TimeSpan span = t - f;
            switch (unit)
            {
                case "Day": return Math.Truncate(span.TotalDays);
                case "Hour": return Math.Truncate(span.TotalHours);
                case "Minute": return Math.Truncate(span.TotalMinutes);
                case "Second": return Math.Truncate(span.TotalSeconds);
            }
            return 0.0;
        }

        // 'FormatDate': the subject is checked before the pattern is worked out.
        public static OtterDateValue DateSubject(object subject, int line)
        {
            OtterDateValue date = subject as OtterDateValue;
            if (date == null) throw Err("I can only format a date, but this is " + TypeName(subject) + ".", line, null);
            return date;
        }

        public static object FormatDate(OtterDateValue date, object pattern, int line)
        {
            string p = Format(pattern);
            try { return date.Value.ToString(p, CultureInfo.InvariantCulture); }
            catch (FormatException) { throw Err("I do not understand the date format " + p + ".", line, "format date as \"MM/dd/yyyy\" into text"); }
        }

        // 'DateFromText' (D101).
        public static object DateFromText(object source, int line)
        {
            string text = Format(source);
            DateTime parsed;
            try { parsed = DateTime.Parse(text, CultureInfo.InvariantCulture); }
            catch (Exception) { throw Err("I couldn't understand \"" + text + "\" as a date.", line, "date from \"2024-01-15\" using \"yyyy-MM-dd\""); }
            return new OtterDateValue(parsed, parsed.TimeOfDay != TimeSpan.Zero);
        }

        public static object DateFromTextUsing(object source, object format, int line)
        {
            string text = Format(source);
            string f = Format(format);
            DateTime parsed;
            try { parsed = DateTime.ParseExact(text, f, CultureInfo.InvariantCulture); }
            catch (Exception) { throw Err("I couldn't understand \"" + text + "\" as a date using the format \"" + f + "\".", line, null); }
            return new OtterDateValue(parsed, parsed.TimeOfDay != TimeSpan.Zero);
        }

        // 'Fail' (D68): the value's text becomes the message.
        public static OtterNativeError Fail(object message, int line) { return Err(Format(message), line, null); }

        // Get-OtterMutableList: sort and reverse change the list in place.
        static List<object> MutableList(Env e, string name, int line, string verb)
        {
            if (!e.Has(name)) throw Err("Otter could not find the variable \"" + name + "\".", line, null);
            object value = e.GetRaw(name);
            List<object> list = value as List<object>;
            if (list == null) throw Err("I can only " + verb + " a list, but \"" + name + "\" holds " + TypeName(value) + ".", line, null);
            return list;
        }

        // 'Sort': numbers by value, anything else by its text (ordinal), with
        // Array.Sort - the same algorithm the interpreter calls, so ties keep
        // the same order.
        public static void Sort(Env e, string name, int line)
        {
            List<object> list = MutableList(e, name, line, "sort");
            object[] items = list.ToArray();
            Array.Sort<object>(items, CompareForSort);
            list.Clear();
            list.AddRange(items);
        }

        static int CompareForSort(object left, object right)
        {
            double l, r;
            if (TryNumber(left, out l) && TryNumber(right, out r)) return l.CompareTo(r);
            return string.CompareOrdinal(Format(left), Format(right));
        }

        public static void Reverse(Env e, string name, int line) { MutableList(e, name, line, "reverse").Reverse(); }

        // 'OfOperation' First / Last: gone for an empty list.
        public static object First(object subject, int line)
        {
            List<object> list = subject as List<object>;
            if (list == null) throw Err("Only a list has a first item, but this is " + TypeName(subject) + ".", line, null);
            return list.Count == 0 ? null : list[0];
        }

        public static object Last(object subject, int line)
        {
            List<object> list = subject as List<object>;
            if (list == null) throw Err("Only a list has a last item, but this is " + TypeName(subject) + ".", line, null);
            return list.Count == 0 ? null : list[list.Count - 1];
        }

        // 'ObjectDef' for a new plain thing: the name must be free first.
        public static void RequireNewThingName(Env e, string name, int line)
        {
            if (e.Has(name))
                throw Err("Otter will not replace existing " + TypeName(e.GetRaw(name)) + " called \"" + name + "\" with a new thing.", line, "Use a new name, or assign individual properties instead.");
        }

        // 'PropertyAccess' read on a thing.
        public static object Prop(object target, string property, int line)
        {
            OtterDateValue date = target as OtterDateValue;
            if (date != null) return DatePart(date, property, line);
            OtterThing thing = target as OtterThing;
            if (thing == null) throw Err("I can only read properties of a thing, but this is " + TypeName(target) + ".", line, null);
            if (!thing.Has(property))
            {
                List<string> known = thing.Names();
                string suggestion = known.Count > 0 ? known[0] + " of ..." : null;
                throw Err("This " + thing.TypeName + " has no property called \"" + property + "\".", line, suggestion);
            }
            return thing.Read(property);
        }

        // Set-OtterTarget 'PropertyAccess': the value was worked out first.
        public static void SetProp(object owner, string property, object value, int line)
        {
            OtterThing thing = owner as OtterThing;
            if (thing == null) throw Err("I can only set properties on a thing, but this is " + TypeName(owner) + ".", line, null);
            thing.Write(property, value);
        }

        // 'GetKey' (D41): dynamic keys on a plain thing, text keys only.
        public static OtterThing KeyTarget(object value, int line, string verb)
        {
            OtterThing thing = value as OtterThing;
            if (thing == null) throw Err("I can only " + verb + " a thing, but this is " + TypeName(value) + ".", line, null);
            if (thing.TypeName != "thing") throw Err("I can only " + verb + " properties dynamically on a thing, but this is a " + thing.TypeName + ".", line, null);
            return thing;
        }

        public static string KeyText(object value, int line)
        {
            string s = value as string;
            if (s != null) return s;
            throw Err("I need text for a dynamic key, but this is " + TypeName(value) + ".", line, "get \"Jeff\" from scores into score");
        }

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

        // Random numbers come from the interpreter's own generator (PowerShell's
        // Get-Random, through the bridge), so `set random seed to 42` gives
        // the same numbers on both engines and on both PowerShells.
        static int RandomBelow(int min, int maxExclusive, int line)
        {
            return Convert.ToInt32(Call("RandomInt", new object[] { (double)min, (double)maxExclusive }, line), CultureInfo.InvariantCulture);
        }

        public static void SetRandomSeed(object seedVal, int line)
        {
            double seed = AssertNumber(seedVal, line, "a random seed");
            Call("SetRandomSeed", new object[] { seed }, line);
        }

        public static object RandomNumber(object fromVal, object toVal, int line)
        {
            double from = AssertNumber(fromVal, line, "the lowest number");
            double to = AssertNumber(toVal, line, "the highest number");
            if (from > to) { double swap = from; from = to; to = swap; }
            int min = (int)Math.Floor(from);
            int max = (int)Math.Floor(to);
            return (object)(double)RandomBelow(min, max + 1, line);
        }

        public static object RandomItem(object colVal, int line)
        {
            List<object> list = colVal as List<object>;
            if (list == null) throw Err("I can only pick from a list, but this is " + TypeName(colVal) + ".", line, null);
            if (list.Count == 0) return null;
            int idx = RandomBelow(0, list.Count, line);
            return list[idx];
        }

        static readonly List<OtterUdpSocket> activeSockets = new List<OtterUdpSocket>();

        public static OtterBytesValue BytesFromText(object textVal, int line)
        {
            string s = Format(textVal);
            return new OtterBytesValue(System.Text.Encoding.UTF8.GetBytes(s));
        }

        public static OtterUdpSocket UdpOpen(object portVal, int line)
        {
            int port = 0;
            if (portVal != null)
            {
                port = (int)AssertNumber(portVal, line, "a port number");
            }
            try
            {
                System.Net.Sockets.UdpClient client = port > 0
                    ? new System.Net.Sockets.UdpClient(port, System.Net.Sockets.AddressFamily.InterNetwork)
                    : new System.Net.Sockets.UdpClient(0, System.Net.Sockets.AddressFamily.InterNetwork);
                int actualPort = ((System.Net.IPEndPoint)client.Client.LocalEndPoint).Port;
                OtterUdpSocket sock = new OtterUdpSocket(client, actualPort);
                activeSockets.Add(sock);
                return sock;
            }
            catch (Exception ex)
            {
                throw Err("I could not open a udp socket on port " + port + ": " + ex.Message, line, null);
            }
        }

        public static void UdpSend(object socketVal, object dataVal, object hostVal, object portVal, int line)
        {
            OtterUdpSocket sock = socketVal as OtterUdpSocket;
            if (sock == null) throw Err("I can only send to a host and port through a udp socket, but this is " + TypeName(socketVal) + ".", line, "open udp on port 9000 and call it socket");
            if (sock.IsClosed) throw Err("I cannot send through a udp socket that is not open (its state is 'closed').", line, null);
            OtterBytesValue bytes = dataVal as OtterBytesValue;
            if (bytes == null) throw Err("I can only send bytes through a udp socket, but this is " + TypeName(dataVal) + ".", line, null);
            string host = Format(hostVal);
            int port = (int)AssertNumber(portVal, line, "a port number");
            try
            {
                System.Net.IPAddress ip;
                if (!System.Net.IPAddress.TryParse(host, out ip))
                {
                    System.Net.IPAddress[] addrs = System.Net.Dns.GetHostAddresses(host);
                    for (int i = 0; i < addrs.Length; i++)
                    {
                        if (addrs[i].AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork) { ip = addrs[i]; break; }
                    }
                }
                if (ip == null) throw new Exception("no IPv4 address found for '" + host + "'");
                sock.Client.Send(bytes.Value, bytes.Value.Length, new System.Net.IPEndPoint(ip, port));
            }
            catch (Exception ex)
            {
                throw Err("I could not send the udp datagram to " + host + ":" + port + ": " + ex.Message, line, null);
            }
        }

        public static void NetClose(object socketVal, int line)
        {
            OtterUdpSocket sock = socketVal as OtterUdpSocket;
            if (sock != null)
            {
                sock.Close();
                return;
            }
            throw Err("I can only close a udp socket here, but this is " + TypeName(socketVal) + ".", line, "close udp <name>");
        }

        public static void AddNetHandler(object socketVal, string eventKind, OtterBody body, Env env, int line)
        {
            OtterUdpSocket sock = socketVal as OtterUdpSocket;
            if (sock == null) throw Err("I can only listen for a network event on a udp socket, but this is " + TypeName(socketVal) + ".", line, null);
            sock.Handlers.Add(new OtterNetHandler(eventKind, body, env));
        }

        public static void PumpEvents(Env e)
        {
            while (true)
            {
                bool hasHandlers = false;
                for (int i = 0; i < activeSockets.Count; i++)
                {
                    OtterUdpSocket sock = activeSockets[i];
                    if (!sock.IsClosed && sock.Handlers.Count > 0)
                    {
                        hasHandlers = true;
                        break;
                    }
                }
                if (!hasHandlers) break;

                bool receivedAny = false;
                for (int i = 0; i < activeSockets.Count; i++)
                {
                    OtterUdpSocket sock = activeSockets[i];
                    if (sock.IsClosed || sock.Handlers.Count == 0) continue;

                    while (sock.Client.Available > 0)
                    {
                        System.Net.IPEndPoint ep = new System.Net.IPEndPoint(System.Net.IPAddress.Any, 0);
                        byte[] data = sock.Client.Receive(ref ep);
                        receivedAny = true;
                        for (int h = 0; h < sock.Handlers.Count; h++)
                        {
                            OtterNetHandler handler = sock.Handlers[h];
                            if (handler.EventKind == "Data")
                            {
                                handler.Body(handler.Environment);
                            }
                        }
                        if (sock.IsClosed) break;
                    }
                }
                if (!receivedAny)
                {
                    System.Threading.Thread.Sleep(1);
                }
            }
        }
    }

    // The library without PowerShell, for otter.exe's fast start. Each function
    // mirrors its PowerShell original in src/Otter.Library.psm1 (and Get-Random
    // for random numbers) on Windows PowerShell 5.1, including the error text:
    // a .NET method's failure reads as PowerShell's MethodInvocationException
    // ("Exception calling ..."), a cmdlet's as the .NET message it carries.
    // tests/FastStart.Tests.ps1 compares every case with otter.ps1.
    public static class OtterLibrary
    {
        static readonly string[] Names = { "SetRandomSeed", "RandomInt", "ReadFile", "WriteFile", "AppendFile", "DeleteFile", "FileExists", "CopyFile", "MoveFile", "ConvertToJson", "ConvertFromJson", "ReadJson" };

        public static bool Supports(string name) { return Array.IndexOf(Names, name) >= 0; }

        public static object Call(string name, object[] a, int line)
        {
            switch (name)
            {
                case "SetRandomSeed": SetSeed(Convert.ToInt32((double)a[0])); return null;
                case "RandomInt": return (double)Next(Convert.ToInt32((double)a[0]), Convert.ToInt32((double)a[1]));
                case "ReadFile": return ReadFile(FileArg(a[0], line), line);
                case "WriteFile": WriteFile(FileArg(a[1], line), (string)a[0], line, (bool)a[2]); return null;
                case "AppendFile": AppendFile(FileArg(a[1], line), (string)a[0], line); return null;
                case "DeleteFile": DeleteFile(FileArg(a[0], line), line); return null;
                case "FileExists": return FileExists(FileArg(a[0], line), line);
                case "CopyFile": { string from = FileArg(a[0], line); CopyFile(from, FileArg(a[1], line), line); return null; }
                case "MoveFile": { string from = FileArg(a[0], line); MoveFile(from, FileArg(a[1], line), line); return null; }
                case "ConvertToJson": return ToJson(a[0], line);
                case "ConvertFromJson": return FromJson((string)a[0], line);
                case "ReadJson": return FromJson((string)ReadFile(FileArg(a[0], line), line), line);
            }
            throw R.Err("The compiled backend has no library bridge for " + name + ".", line, null);
        }

        // --- Get-Random (PowerShell's PolymorphicRandomNumberGenerator) ------

        static Random rng = new Random();

        // Get-Random -SetSeed n | Out-Null: a new generator, and the number that
        // call returns is drawn and discarded.
        static void SetSeed(int seed) { rng = new Random(seed); NextRaw(); }

        static int NextRaw()
        {
            byte[] data = new byte[4];
            int n;
            do { rng.NextBytes(data); n = BitConverter.ToInt32(data, 0); } while (n == int.MaxValue);
            if (n < 0) n += int.MaxValue;
            return n;
        }

        // Get-Random -Minimum min -Maximum max (max excluded).
        static int Next(int min, int max)
        {
            double sample = NextRaw() * (1.0 / int.MaxValue);
            long range = (long)max - min;
            return (int)((long)Math.Truncate(sample * range) + min);
        }

        // --- files (Otter.Library.psm1) ---------------------------------------

        static string Quote(string text) { return "\"" + text + "\""; }

        // PowerShell's text for a failed .NET method call inside a try block.
        static string MethodError(string method, int argumentCount, Exception ex)
        {
            return "Exception calling \"" + method + "\" with \"" + argumentCount + "\" argument(s): \"" + ex.Message + "\"";
        }

        // Resolve-OtterFileArgument: a thing's path (or name), or the value's text.
        static string FileArg(object value, int line)
        {
            OtterThing thing = value as OtterThing;
            if (thing != null)
            {
                if (thing.Has("path")) return R.PsText(thing.Read("path"));
                if (thing.Has("name")) return R.PsText(thing.Read("name"));
                throw R.Err("I need a file here, but this " + thing.TypeName + " has no path.", line, null);
            }
            return R.Format(value);
        }

        // Resolve-OtterPath
        static string Resolve(string path, int line)
        {
            if (string.IsNullOrWhiteSpace(path)) throw R.Err("I need the name of a file.", line, null);
            try
            {
                if (Path.IsPathRooted(path)) return path;
                return Path.GetFullPath(Path.Combine(Environment.CurrentDirectory, path));
            }
            catch (Exception) { throw R.Err(Quote(path) + " is not a name Otter can use for a file.", line, null); }
        }

        // Initialize-OtterParentFolder
        static void ParentFolder(string full, int line)
        {
            string folder = Path.GetDirectoryName(full);
            if (string.IsNullOrEmpty(folder) || File.Exists(folder) || Directory.Exists(folder)) return;
            try { Directory.CreateDirectory(folder); }
            catch (Exception) { throw R.Err("I could not make the folder " + Quote(folder) + ".", line, null); }
        }

        static UTF8Encoding Utf8NoBom() { return new UTF8Encoding(false); }

        static object ReadFile(string path, int line)
        {
            string full = Resolve(path, line);
            if (!File.Exists(full)) throw R.Err("I could not find a file called " + Quote(path) + ".", line, "if file " + Quote(path) + " exists");
            try { return File.ReadAllText(full, Utf8NoBom()) ?? ""; }
            catch (Exception ex) { throw R.Err("I could not read " + Quote(path) + ". " + MethodError("ReadAllText", 2, ex), line, null); }
        }

        static void WriteFile(string path, string content, int line, bool atomic)
        {
            string full = Resolve(path, line);
            ParentFolder(full, line);
            if (Directory.Exists(full)) throw R.Err(Quote(path) + " is a folder, not a file.", line, null);
            if (!atomic)
            {
                try { File.WriteAllText(full, content, Utf8NoBom()); }
                catch (Exception ex) { throw R.Err("I could not write to " + Quote(path) + ". " + MethodError("WriteAllText", 3, ex), line, null); }
                return;
            }
            // Assert-OtterAtomicTargetWritable, then temp file + Replace/Move (D72).
            if (File.Exists(full) && new FileInfo(full).IsReadOnly)
                throw R.Err("I could not write to " + Quote(path) + ". The file is read-only.", line, null);
            string temp = full + ".otter-tmp-" + Guid.NewGuid().ToString("N").Substring(0, 8);
            string backup = full + ".otter-bak-" + Guid.NewGuid().ToString("N").Substring(0, 8);
            string step = "WriteAllText"; int stepArgs = 3;
            try
            {
                File.WriteAllText(temp, content, Utf8NoBom());
                if (File.Exists(full))
                {
                    step = "Replace"; stepArgs = 3;
                    File.Replace(temp, full, backup);
                    try { File.Delete(backup); } catch (Exception) { }
                }
                else
                {
                    step = "Move"; stepArgs = 2;
                    File.Move(temp, full);
                }
            }
            catch (Exception ex)
            {
                try { if (File.Exists(temp)) File.Delete(temp); } catch (Exception) { }
                throw R.Err("I could not write to " + Quote(path) + ". " + MethodError(step, stepArgs, ex), line, null);
            }
        }

        static void AppendFile(string path, string content, int line)
        {
            string full = Resolve(path, line);
            ParentFolder(full, line);
            if (Directory.Exists(full)) throw R.Err(Quote(path) + " is a folder, not a file.", line, null);
            try { File.AppendAllText(full, content, Utf8NoBom()); }
            catch (Exception ex) { throw R.Err("I could not append to " + Quote(path) + ". " + MethodError("AppendAllText", 3, ex), line, null); }
        }

        // Remove-Item -Force: removes read-only files too.
        static void DeleteFile(string path, int line)
        {
            string full = Resolve(path, line);
            if (Directory.Exists(full)) throw R.Err(Quote(path) + " is a folder. Otter only deletes files.", line, null);
            if (!File.Exists(full)) throw R.Err("I could not find a file called " + Quote(path) + " to delete.", line, "if file " + Quote(path) + " exists");
            // Remove-Item reports the provider's normalized path (backslashes).
            try { string target = Path.GetFullPath(full); ClearReadOnly(target); File.Delete(target); }
            catch (Exception ex) { throw R.Err("I could not delete " + Quote(path) + ". " + ex.Message, line, null); }
        }

        static object FileExists(string path, int line)
        {
            if (string.IsNullOrWhiteSpace(path)) return false;
            return File.Exists(Resolve(path, line));
        }

        // "copy x to Documents" puts it IN Documents. Copy-Item -Force replaces
        // a read-only destination.
        static void CopyFile(string source, string destination, int line)
        {
            string from = Resolve(source, line);
            string to = Resolve(destination, line);
            if (!File.Exists(from)) throw R.Err("I could not find a file called " + Quote(source) + " to copy.", line, null);
            if (Directory.Exists(to)) to = Path.Combine(to, Path.GetFileName(from));
            else ParentFolder(to, line);
            // Copy-Item reports the provider's normalized paths (backslashes).
            try { from = Path.GetFullPath(from); to = Path.GetFullPath(to); if (File.Exists(to)) ClearReadOnly(to); File.Copy(from, to, true); }
            catch (Exception ex) { throw R.Err("I could not copy " + Quote(source) + ". " + ex.Message, line, null); }
        }

        // Move-Item -Force replaces an existing (even read-only) destination.
        static void MoveFile(string source, string destination, int line)
        {
            string from = Resolve(source, line);
            string to = Resolve(destination, line);
            if (!File.Exists(from)) throw R.Err("I could not find a file called " + Quote(source) + " to move.", line, null);
            if (Directory.Exists(to)) to = Path.Combine(to, Path.GetFileName(from));
            else ParentFolder(to, line);
            try
            {
                // Move-Item works on the provider's normalized paths (backslashes).
                from = Path.GetFullPath(from); to = Path.GetFullPath(to);
                if (File.Exists(to) && !string.Equals(to, from, StringComparison.OrdinalIgnoreCase))
                {
                    try { ClearReadOnly(to); File.Delete(to); } catch (Exception) { }
                }
                File.Move(from, to);
            }
            catch (Exception ex) { throw R.Err("I could not move " + Quote(source) + ". " + ex.Message, line, null); }
        }

        // --- JSON (ConvertTo-OtterJsonText / ConvertFrom-OtterJsonText) -----
        //
        // Windows PowerShell 5.1's ConvertTo-Json and ConvertFrom-Json are built
        // on .NET Framework's JavaScriptSerializer. It is loaded here at run time
        // (so this source still compiles on PowerShell 7, where it does not
        // exist) and does all escaping, number and date text, and parsing - the
        // same library, so the same results. What is rebuilt here is
        // PowerShell's own part: its indented layout, and how it turns parsed
        // JSON into objects.

        static object serializer;
        static MethodInfo serializeMethod, deserializeMethod;

        static void LoadSerializer()
        {
            if (serializer != null) return;
            Assembly web = Assembly.Load("System.Web.Extensions, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35");
            Type type = web.GetType("System.Web.Script.Serialization.JavaScriptSerializer", true);
            object instance = Activator.CreateInstance(type);
            type.GetProperty("MaxJsonLength").SetValue(instance, int.MaxValue, null);
            type.GetProperty("RecursionLimit").SetValue(instance, JsonRecursionLimit, null);
            serializeMethod = type.GetMethod("Serialize", new Type[] { typeof(object) });
            deserializeMethod = type.GetMethod("DeserializeObject", new Type[] { typeof(string) });
            serializer = instance;
        }

        // ConvertFrom-Json's limit on nesting; deeper input is "not valid JSON".
        internal static int JsonRecursionLimit = 1020;

        static string Scalar(object value)
        {
            LoadSerializer();
            try { return (string)serializeMethod.Invoke(serializer, new object[] { value }); }
            catch (TargetInvocationException tie) { throw tie.InnerException ?? tie; }
        }

        // ConvertTo-OtterJsonShape, then ConvertTo-Json -Depth 32.
        const int JsonDepth = 32;

        static object ToJson(object value, int line)
        {
            if (value == null) return null;  // ConvertTo-Json of $null writes nothing
            Shape(value, line);              // the shape errors come first, as in ConvertTo-OtterJsonShape
            StringBuilder text = new StringBuilder();
            try { Write(value, 0, 0, text); }
            catch (OtterNativeError) { throw; }
            catch (Exception ex) { throw R.Err("Otter could not turn this into JSON. " + ex.Message, line, null); }
            return text.ToString();
        }

        // ConvertTo-OtterJsonShape's refusals.
        static void Shape(object value, int line)
        {
            if (value is OtterFn || value is OtterTypeValue) throw R.Err("Otter cannot turn something it can do into JSON.", line, null);
            OtterThing thing = value as OtterThing;
            if (thing != null) { foreach (string name in thing.Names()) Shape(thing.Read(name), line); return; }
            List<object> list = value as List<object>;
            if (list != null) { foreach (object item in list) Shape(item, line); }
        }

        static void Pad(StringBuilder text, int count) { text.Append(' ', count); }

        // A container is indented four spaces past the column where it starts;
        // a key's value starts after `"key":  `. Past -Depth 32 a container is
        // written as the text of its .NET type, as ConvertTo-Json does.
        static void Write(object value, int column, int depth, StringBuilder text)
        {
            OtterThing thing = value as OtterThing;
            OtterDateValue date = value as OtterDateValue;
            OtterBytesValue bytes = value as OtterBytesValue;
            List<object> list = value as List<object>;

            if (thing != null || date != null || bytes != null)
            {
                List<KeyValuePair<string, object>> members = new List<KeyValuePair<string, object>>();
                if (thing != null) { foreach (string name in thing.Names()) members.Add(new KeyValuePair<string, object>(name, thing.Read(name))); }
                else if (date != null)
                {
                    members.Add(new KeyValuePair<string, object>("Value", date.Value));
                    members.Add(new KeyValuePair<string, object>("HasTime", date.HasTime));
                }
                else
                {
                    List<object> numbers = new List<object>();
                    foreach (byte b in bytes.Value) numbers.Add(b);
                    members.Add(new KeyValuePair<string, object>("Value", numbers));
                }
                if (depth > JsonDepth) { text.Append(Scalar(thing != null ? "System.Collections.Specialized.OrderedDictionary" : value.ToString())); return; }
                if (members.Count == 0) { text.Append("{\r\n\r\n"); Pad(text, column); text.Append('}'); return; }
                text.Append("{\r\n");
                for (int i = 0; i < members.Count; i++)
                {
                    if (i > 0) text.Append(",\r\n");
                    string key = Scalar(members[i].Key);
                    Pad(text, column + 4);
                    text.Append(key).Append(":  ");
                    Write(members[i].Value, column + 4 + key.Length + 3, depth + 1, text);
                }
                text.Append("\r\n");
                Pad(text, column);
                text.Append('}');
                return;
            }
            if (list != null)
            {
                if (depth > JsonDepth) { text.Append(Scalar("System.Object[]")); return; }
                if (list.Count == 0) { text.Append("[\r\n\r\n"); Pad(text, column); text.Append(']'); return; }
                text.Append("[\r\n");
                for (int i = 0; i < list.Count; i++)
                {
                    if (i > 0) text.Append(",\r\n");
                    Pad(text, column + 4);
                    Write(list[i], column + 4, depth + 1, text);
                }
                text.Append("\r\n");
                Pad(text, column);
                text.Append(']');
                return;
            }
            text.Append(value == null ? "null" : Scalar(value));
        }

        // ConvertFrom-OtterJsonText: ConvertFrom-Json, then ConvertFrom-OtterJsonValue.
        static object FromJson(string text, int line)
        {
            if (string.IsNullOrWhiteSpace(text)) throw R.Err("There is no JSON here to read.", line, null);
            object parsed;
            try
            {
                LoadSerializer();
                parsed = deserializeMethod.Invoke(serializer, new object[] { text });
                CheckObjectKeys(parsed);
            }
            catch (Exception) { throw R.Err("This is not valid JSON, so Otter could not read it.", line, null); }
            return FromJsonValue(parsed);
        }

        // ConvertFrom-Json refuses an object whose keys differ only by case (a
        // PowerShell object's properties are case-insensitive) or are empty.
        static void CheckObjectKeys(object value)
        {
            IDictionary<string, object> map = value as IDictionary<string, object>;
            if (map != null)
            {
                HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (KeyValuePair<string, object> pair in map)
                {
                    if (pair.Key.Length == 0 || !seen.Add(pair.Key)) throw new FormatException("duplicate or empty key");
                    CheckObjectKeys(pair.Value);
                }
                return;
            }
            object[] array = value as object[];
            if (array != null) { foreach (object item in array) CheckObjectKeys(item); }
        }

        static object FromJsonValue(object value)
        {
            if (value == null) return null;
            IDictionary<string, object> map = value as IDictionary<string, object>;
            if (map != null)
            {
                OtterThing thing = new OtterThing("thing");
                foreach (KeyValuePair<string, object> pair in map) thing.Write(pair.Key, FromJsonValue(pair.Value));
                return thing;
            }
            object[] array = value as object[];
            if (array != null)
            {
                List<object> list = new List<object>(array.Length);
                foreach (object item in array) list.Add(FromJsonValue(item));
                return list;
            }
            if (value is bool) return value;
            if (value is int || value is long || value is double || value is decimal) return Convert.ToDouble(value, CultureInfo.InvariantCulture);
            // [string] of anything else: text stays text; a date is written the
            // way PowerShell writes one (invariant culture).
            return Convert.ToString(value, CultureInfo.InvariantCulture);
        }

        static void ClearReadOnly(string path)
        {
            FileAttributes attributes = File.GetAttributes(path);
            if ((attributes & FileAttributes.ReadOnly) != 0) File.SetAttributes(path, attributes & ~FileAttributes.ReadOnly);
        }
    }
}
