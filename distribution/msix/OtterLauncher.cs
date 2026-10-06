// otter.exe - the Microsoft Store package's launcher (C# 5, .NET Framework 4).
//
// An MSIX app execution alias has to name an executable, so the Store build
// cannot use otter.cmd. This does exactly what otter.cmd does:
//
//     powershell -NoProfile -ExecutionPolicy Bypass -File "<dir>\otter.ps1" <args>
//
// and returns Otter's exit code. The child shares this console, so input,
// output, colors and Ctrl+C reach Otter directly.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

static class OtterLauncher
{
    static int Main(string[] args)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "otter.ps1");
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
