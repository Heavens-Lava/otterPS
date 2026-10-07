// otter.exe - Otter's Windows launcher (C# 5, .NET Framework 4).
//
// Fast start: `otter run hello.ot` (or `otter hello.ot`) for a program that
// otter.ps1 already compiled runs the cached compiled program directly, with
// no PowerShell start-up. otter.ps1 writes a fast-start entry when it compiles
// a program that needs nothing from PowerShell (no `use` imports, no library
// bridge); the entry records the source file's size and SHA-256 and a
// fingerprint of the Otter installation. Anything that does not match - an
// edited file, a different Otter, another command, a developer flag,
// OTTER_ENGINE=interpreter - goes to otter.ps1 exactly as before:
//
//     powershell -NoProfile -ExecutionPolicy Bypass -File "<dir>\otter.ps1" <args>
//
// Output, error text and exit codes match otter.ps1's compiled engine
// (tests/FastStart.Tests.ps1 compares the two). OTTER_ENGINE_TRACE=1 reports
// the path taken on stderr.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;

static class OtterLauncher
{
    const int ExitRuntimeError = 3;
    static readonly string Dir = AppDomain.CurrentDomain.BaseDirectory;

    static int Main(string[] args)
    {
        string reason;
        int exitCode;
        if (TryFastStart(args, out exitCode, out reason)) return exitCode;
        Trace("interpreter path via otter.ps1 (" + reason + ")");
        return RunOtterPs1(args);
    }

    // --- fast start ---------------------------------------------------------

    static readonly string[] OwnFlags = { "-debugtokens", "-debugast", "-parseonly", "-debugerrors", "-open", "-noopen", "-version", "--version", "-help", "--help" };

    static bool TryFastStart(string[] args, out int exitCode, out string reason)
    {
        exitCode = 0;
        if (Environment.GetEnvironmentVariable("OTTER_ENGINE") == "interpreter") { reason = "OTTER_ENGINE=interpreter"; return false; }
        if (Environment.GetEnvironmentVariable("OTTER_FAST_START") == "0") { reason = "OTTER_FAST_START=0"; return false; }

        int fileIndex;
        if (args.Length >= 2 && string.Equals(args[0], "run", StringComparison.OrdinalIgnoreCase)) fileIndex = 1;
        else if (args.Length >= 1 && args[0].EndsWith(".ot", StringComparison.OrdinalIgnoreCase) && !args[0].StartsWith("-")) fileIndex = 0;
        else { reason = "not a run of a .ot file"; return false; }
        foreach (string arg in args)
        {
            if (Array.IndexOf(OwnFlags, arg.ToLowerInvariant()) >= 0) { reason = "developer flag " + arg; return false; }
        }
        string file = args[fileIndex];
        if (!file.EndsWith(".ot", StringComparison.OrdinalIgnoreCase)) { reason = "not a .ot file"; return false; }

        string fullPath;
        try { fullPath = Path.GetFullPath(file); } catch (Exception) { reason = "unusable path"; return false; }
        if (!File.Exists(fullPath)) { reason = "file not found (otter.ps1 reports it)"; return false; }

        Dictionary<string, string> entry = ReadEntry(fullPath);
        if (entry == null) { reason = "no fast-start entry yet"; return false; }

        string version;
        try { version = File.ReadAllText(Path.Combine(Dir, "VERSION")).Trim(); } catch (Exception) { reason = "no VERSION file"; return false; }
        if (Get(entry, "format") != "1") { reason = "entry format"; return false; }
        if (Get(entry, "otterVersion") != version) { reason = "different Otter version"; return false; }
        if (Get(entry, "toolchain") != ToolchainFingerprint()) { reason = "Otter itself changed"; return false; }
        if (!string.Equals(Get(entry, "source"), fullPath.ToLowerInvariant(), StringComparison.Ordinal)) { reason = "entry for another file"; return false; }

        byte[] sourceBytes;
        try { sourceBytes = File.ReadAllBytes(fullPath); } catch (Exception) { reason = "cannot read the file"; return false; }
        if (Get(entry, "sourceSha256") != Sha256Hex(sourceBytes)) { reason = "the file changed"; return false; }

        string assemblyPath = Get(entry, "assembly"), runtimePath = Get(entry, "runtime"), className = Get(entry, "className");
        if (string.IsNullOrEmpty(assemblyPath) || !File.Exists(assemblyPath) || string.IsNullOrEmpty(runtimePath) || !File.Exists(runtimePath) || string.IsNullOrEmpty(className))
        {
            reason = "compiled program missing from the cache";
            return false;
        }

        Assembly runtime, program;
        Type programType, envType, rType;
        try
        {
            runtime = Assembly.LoadFrom(runtimePath);
            string runtimeName = runtime.GetName().Name;
            AppDomain.CurrentDomain.AssemblyResolve += delegate(object sender, ResolveEventArgs e)
            {
                return new AssemblyName(e.Name).Name == runtimeName ? runtime : null;
            };
            program = Assembly.LoadFrom(assemblyPath);
            programType = program.GetType(className, true);
            envType = runtime.GetType("OtterNative.Env", true);
            rType = runtime.GetType("OtterNative.R", true);
        }
        catch (Exception ex) { reason = "cannot load the compiled program: " + ex.Message; return false; }

        Trace("compiled (fast start, " + className + ")");
        string[] sourceLines = SplitLines(sourceBytes);
        exitCode = RunCompiled(programType, envType, rType, Slice(args, fileIndex + 1), sourceLines);
        reason = null;
        return true;
    }

    static int RunCompiled(Type programType, Type envType, Type rType, string[] programArgs, string[] sourceLines)
    {
        // Write-Host ends each line with a bare LF when output is redirected
        // (text it is given keeps its own CRLFs); match it byte for byte.
        Console.Out.NewLine = "\n";
        object global = Activator.CreateInstance(envType, new object[] { null });
        // New-OtterEnvironment: the program's arguments, as text.
        List<object> arguments = new List<object>();
        foreach (string a in programArgs) arguments.Add(a);
        envType.GetMethod("Set").Invoke(global, new object[] { "arguments", arguments });
        // Write-OtterLine -> Write-Host: each `say` is one line on standard output.
        Action<string> writer = delegate(string line) { Console.Out.WriteLine(line); };
        rType.GetMethod("Reset").Invoke(null, new object[] { global, writer });
        try
        {
            programType.GetMethod("Run").Invoke(null, new object[] { global });
            Console.Out.Flush();
            return 0;
        }
        catch (TargetInvocationException tie)
        {
            Exception inner = tie.InnerException ?? tie;
            while (inner is TargetInvocationException && inner.InnerException != null) inner = inner.InnerException;
            string typeName = inner.GetType().FullName;
            if (typeName == "OtterNative.OtterNativeError" || typeName == "OtterNative.OtterStopSignal")
            {
                int line = (int)inner.GetType().GetField("Line").GetValue(inner);
                FieldInfo suggestionField = inner.GetType().GetField("Suggestion");
                string suggestion = suggestionField == null ? null : (string)suggestionField.GetValue(inner);
                // otter.ps1 remaps every runtime error to the file it came from,
                // which always quotes that file's line (Remap-OtterSingleError).
                string sourceLine = (line >= 1 && line <= sourceLines.Length) ? sourceLines[line - 1] : null;
                ShowFailure(inner.Message, line, sourceLine, suggestion);
            }
            else
            {
                // Invoke-OtterCompiledProgram: a non-Otter error becomes an Otter one.
                ShowFailure("Otter's compiled engine hit an internal problem: " + inner.Message, 0, null,
                    "Run it again with the interpreter: set OTTER_ENGINE=interpreter, and please report this.");
            }
            return ExitRuntimeError;
        }
    }

    // Show-OtterFailure + OtterError.FormatDetailed (Otter.Contract.psm1), for a
    // runtime error (column 0, so no caret).
    static void ShowFailure(string message, int line, string sourceLine, string suggestion)
    {
        StringBuilder text = new StringBuilder();
        text.AppendLine("Otter Runtime Error");
        text.AppendLine("");
        if (line > 0)
        {
            text.AppendLine("Line " + line + ":");
            if (!string.IsNullOrEmpty(sourceLine)) text.AppendLine("    " + sourceLine.TrimStart().TrimEnd());
            text.AppendLine("");
        }
        text.AppendLine(message);
        if (!string.IsNullOrEmpty(suggestion))
        {
            text.AppendLine("");
            text.AppendLine("Try:");
            text.AppendLine("    " + suggestion);
        }
        Console.Out.Flush();
        ConsoleColor before = Console.ForegroundColor;
        Console.ForegroundColor = ConsoleColor.Red;
        Console.Out.WriteLine("");
        Console.Out.WriteLine(text.ToString().TrimEnd());
        Console.Out.WriteLine("");
        Console.Out.Flush();
        Console.ForegroundColor = before;
    }

    // --- the fast-start entry (written by otter.ps1) -----------------------

    // %LOCALAPPDATA%\Otter\cache\compiled\fast\<first 32 hex of SHA-256 of the
    // lower-case full path>.entry, unless OTTER_COMPILED_CACHE moves the cache.
    static Dictionary<string, string> ReadEntry(string fullPath)
    {
        string cache = Environment.GetEnvironmentVariable("OTTER_COMPILED_CACHE");
        if (string.IsNullOrEmpty(cache))
        {
            string local = Environment.GetEnvironmentVariable("LOCALAPPDATA");
            if (string.IsNullOrEmpty(local)) local = Path.GetTempPath();
            cache = Path.Combine(local, @"Otter\cache\compiled");
        }
        string key = Sha256Hex(Encoding.UTF8.GetBytes(fullPath.ToLowerInvariant())).Substring(0, 32);
        string path = Path.Combine(Path.Combine(cache, "fast"), key + ".entry");
        if (!File.Exists(path)) return null;
        Dictionary<string, string> entry = new Dictionary<string, string>(StringComparer.Ordinal);
        try
        {
            foreach (string line in File.ReadAllLines(path, Encoding.UTF8))
            {
                int eq = line.IndexOf('=');
                if (eq > 0) entry[line.Substring(0, eq)] = line.Substring(eq + 1);
            }
        }
        catch (Exception) { return null; }
        return entry;
    }

    // Size and last-write time of every file that shapes a compiled program:
    // otter.ps1, Otter.Contract.psm1, VERSION and src\ (*.psm1, *.cs). Written
    // the same way by otter.ps1 (Get-OtterToolchainFingerprint).
    static string ToolchainFingerprint()
    {
        List<string> files = new List<string>();
        foreach (string name in new string[] { "otter.ps1", "Otter.Contract.psm1", "VERSION" }) files.Add(Path.Combine(Dir, name));
        string src = Path.Combine(Dir, "src");
        if (Directory.Exists(src))
        {
            foreach (string f in Directory.GetFiles(src, "*", SearchOption.AllDirectories))
            {
                string ext = Path.GetExtension(f).ToLowerInvariant();
                if (ext == ".psm1" || ext == ".cs") files.Add(f);
            }
        }
        List<string> parts = new List<string>();
        string root = Path.GetFullPath(Dir).TrimEnd('\\', '/');
        foreach (string f in files)
        {
            string relative = Path.GetFullPath(f).Substring(root.Length + 1).Replace('\\', '/').ToLowerInvariant();
            FileInfo info = new FileInfo(f);
            parts.Add(info.Exists ? relative + ":" + info.Length + ":" + info.LastWriteTimeUtc.Ticks : relative + ":missing");
        }
        parts.Sort(StringComparer.Ordinal);
        return Sha256Hex(Encoding.UTF8.GetBytes(string.Join("\n", parts.ToArray())));
    }

    // --- helpers ---------------------------------------------------------------

    static string Get(Dictionary<string, string> entry, string key)
    {
        string value;
        return entry.TryGetValue(key, out value) ? value : null;
    }

    static string Sha256Hex(byte[] bytes)
    {
        using (SHA256 sha = SHA256.Create())
        {
            byte[] hash = sha.ComputeHash(bytes);
            StringBuilder hex = new StringBuilder(hash.Length * 2);
            foreach (byte b in hash) hex.Append(b.ToString("x2"));
            return hex.ToString();
        }
    }

    // The file's lines as File.ReadAllLines reads them (otter.ps1's remap does).
    static string[] SplitLines(byte[] bytes)
    {
        List<string> lines = new List<string>();
        using (StreamReader reader = new StreamReader(new MemoryStream(bytes), Encoding.UTF8, true))
        {
            string line;
            while ((line = reader.ReadLine()) != null) lines.Add(line);
        }
        return lines.ToArray();
    }

    static string[] Slice(string[] items, int start)
    {
        if (start >= items.Length) return new string[0];
        string[] rest = new string[items.Length - start];
        Array.Copy(items, start, rest, 0, rest.Length);
        return rest;
    }

    static void Trace(string text)
    {
        if (Environment.GetEnvironmentVariable("OTTER_ENGINE_TRACE") == "1") Console.Error.WriteLine("otter engine: " + text);
    }

    // --- the normal path: otter.ps1 --------------------------------------------

    static int RunOtterPs1(string[] args)
    {
        string script = Path.Combine(Dir, "otter.ps1");
        string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
            @"WindowsPowerShell\v1.0\powershell.exe");

        StringBuilder line = new StringBuilder("-NoProfile -ExecutionPolicy Bypass -File ");
        line.Append(Quote(script));
        foreach (string arg in args) line.Append(' ').Append(Quote(arg));

        // Ctrl+C goes to Otter (same console); the launcher waits for it to finish.
        Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs e) { e.Cancel = true; };

        ProcessStartInfo start = new ProcessStartInfo(powershell, line.ToString());
        start.UseShellExecute = false;
        try
        {
            using (Process otter = Process.Start(start))
            {
                otter.WaitForExit();
                return otter.ExitCode;
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("Otter: I could not start Windows PowerShell (" + powershell + "): " + ex.Message);
            return 1;
        }
    }

    // One argument, quoted so CommandLineToArgvW gives it back unchanged.
    static string Quote(string arg)
    {
        if (arg.Length > 0 && arg.IndexOfAny(new char[] { ' ', '\t', '\n', '\v', '"' }) < 0) return arg;
        StringBuilder quoted = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in arg)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { quoted.Append('\\', slashes * 2 + 1); slashes = 0; quoted.Append('"'); continue; }
            quoted.Append('\\', slashes); slashes = 0; quoted.Append(c);
        }
        quoted.Append('\\', slashes * 2);
        quoted.Append('"');
        return quoted.ToString();
    }
}
