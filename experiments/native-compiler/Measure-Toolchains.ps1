# experiments/native-compiler/Measure-Toolchains.ps1
#
# Proof-of-concept probe for docs/OTTER_NATIVE_COMPILER_DESIGN.md. It does not
# touch Otter itself: it measures what the PowerShell running it can compile
# with nothing extra installed, and how fast a hand-translated Otter benchmark
# runs once compiled.
#
#   powershell -NoProfile -File experiments/native-compiler/Measure-Toolchains.ps1
#   pwsh -NoProfile -File experiments/native-compiler/Measure-Toolchains.ps1

$ErrorActionPreference = 'Continue'
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('otter-toolchain-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

function Report { param([string]$Name, $Value) Write-Output ('{0,-46} {1}' -f $Name, $Value) }

Report 'PowerShell' "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
Report '.NET runtime' ([System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription)
Report 'OS' ([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)

# 1. Add-Type: which C# language versions compile? One probe per version.
$probes = [ordered]@{
    'C# 5 (async/await, caller info)' = 'public static class P5 { public static async System.Threading.Tasks.Task<int> F() { await System.Threading.Tasks.Task.Yield(); return 1; } }'
    'C# 6 (interpolation, expression bodies)' = 'public static class P6 { public static string F(int x) => $"v{x}"; }'
    'C# 7 (tuples, local functions, out var)' = 'public static class P7 { public static int F() { (int a, int b) t = (1, 2); int L() => t.a + t.b; return L(); } }'
    'C# 8 (switch expressions, ranges)' = 'public static class P8 { public static int F(int x) => x switch { 1 => 10, _ => 0 }; }'
    'C# 9 (records, init)' = 'public record P9(int X);'
    'C# 10 (file-scoped namespace)' = "namespace Probe10;`npublic static class P10 { public static int F() => 1; }"
    'C# 11 (raw string literals)' = 'public static class P11 { public static string F() => """raw"""; }'
}
foreach ($name in $probes.Keys) {
    $code = $probes[$name] -replace '\bP(\d+)\b', ('P$1_' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
    try { Add-Type -TypeDefinition $code -ErrorAction Stop; Report "Add-Type $name" 'yes' }
    catch { Report "Add-Type $name" 'no' }
}

# 2. Add-Type to a file: a library, and a console executable.
$lib = Join-Path $work 'probe.dll'
try {
    Add-Type -TypeDefinition 'public static class LibProbe { public static int F() { return 7; } }' -OutputAssembly $lib -ErrorAction Stop
    Report 'Add-Type -OutputAssembly (library)' $(if (Test-Path $lib) { 'yes, writes a .dll' } else { 'no file written' })
} catch { Report 'Add-Type -OutputAssembly (library)' "no: $($_.Exception.Message.Split([Environment]::NewLine)[0])" }
$exe = Join-Path $work 'probe.exe'
try {
    Add-Type -TypeDefinition 'public static class ExeProbe { public static void Main() { System.Console.WriteLine("exe ran"); } }' -OutputAssembly $exe -OutputType ConsoleApplication -ErrorAction Stop
    $ran = if (Test-Path $exe) { (& $exe) -join '' } else { '' }
    Report 'Add-Type -OutputType ConsoleApplication' $(if ($ran -eq 'exe ran') { 'yes, the .exe runs on its own' } elseif (Test-Path $exe) { "writes .exe; running it gave '$ran'" } else { 'no file written' })
} catch { Report 'Add-Type -OutputType ConsoleApplication' "no: $($_.Exception.Message.Split([Environment]::NewLine)[0])" }

# 3. Reflection.Emit: can IL be generated, and saved to disk?
try {
    $name = [System.Reflection.AssemblyName]::new('EmitProbe')
    $ab = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly($name, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
    $mb = $ab.DefineDynamicModule('EmitProbe')
    $tb = $mb.DefineType('EmitProbe.T', [System.Reflection.TypeAttributes]::Public)
    $m = $tb.DefineMethod('F', [System.Reflection.MethodAttributes]'Public, Static', [int], [Type[]]@())
    $il = $m.GetILGenerator(); $il.Emit([System.Reflection.Emit.OpCodes]::Ldc_I4, 42); $il.Emit([System.Reflection.Emit.OpCodes]::Ret)
    $t = $tb.CreateType()
    Report 'Reflection.Emit in memory' $(if ($t.GetMethod('F').Invoke($null, @()) -eq 42) { 'yes' } else { 'no' })
} catch { Report 'Reflection.Emit in memory' "no: $($_.Exception.Message)" }
$saveAccess = [Enum]::GetNames([System.Reflection.Emit.AssemblyBuilderAccess]) -contains 'RunAndSave'
$persisted = [bool]('System.Reflection.Emit.PersistedAssemblyBuilder' -as [type])
Report 'Reflection.Emit saved to disk' $(if ($saveAccess) { 'yes (AssemblyBuilderAccess.RunAndSave)' } elseif ($persisted) { 'yes (PersistedAssemblyBuilder, .NET 9+)' } else { 'no (this .NET has no way to save emitted IL)' })

# 4. The dotnet SDK, if one happens to be installed.
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
Report 'dotnet SDKs on PATH' $(if ($dotnet) { $sdks = (& dotnet --list-sdks 2>$null) -join '; '; if ($sdks) { $sdks } else { 'dotnet present, no SDK (runtime only)' } } else { 'none' })

# 5. Speed: benchmarks/arithmetic.ot translated by hand into the C# a compiler
#    could generate - Otter numbers are doubles, the loop runs 400 times - and
#    timed after an in-memory Add-Type compile.
$source = @'
public static class ArithmeticBench {
    public static double Run() {
        double total = 0;
        for (double n = 1; n <= 400; n += 1) {
            double a1 = n + 7;
            double a2 = a1 * 3;
            double a3 = a2 - n;
            double a4 = a3 / 2;
            total = total + a4;
        }
        return total;
    }
}
'@
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Add-Type -TypeDefinition $source
$sw.Stop()
Report 'Add-Type compile time (arithmetic, cold)' ('{0:N0} ms' -f $sw.Elapsed.TotalMilliseconds)
$result = [ArithmeticBench]::Run()
$sw = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt 1000; $i++) { $null = [ArithmeticBench]::Run() }
$sw.Stop()
Report 'compiled arithmetic benchmark, per run' ('{0:N4} ms (result {1})' -f ($sw.Elapsed.TotalMilliseconds / 1000), $result)

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
