# experiments/native-compiler/Measure-DotnetSdk.ps1
#
# Proof-of-concept probe for docs/OTTER_NATIVE_COMPILER_DESIGN.md: what the
# .NET SDK route costs. Builds the hand-translated arithmetic benchmark as
#   1. a framework-dependent executable (needs the .NET runtime installed),
#   2. a self-contained single-file executable (needs nothing),
#   3. a Native AOT executable (needs the platform's native linker),
# and reports build time, output size and run time. Requires `dotnet` (SDK).

$ErrorActionPreference = 'Continue'
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { Write-Output 'dotnet SDK not found'; exit 1 }
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('otter-sdk-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
$sdk = (& dotnet --version)
$rid = if ($IsWindows -or $PSVersionTable.PSEdition -ne 'Core') { 'win-x64' } elseif ($IsMacOS) { if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'osx-arm64' } else { 'osx-x64' } } else { 'linux-x64' }
$framework = 'net' + ($sdk -split '\.')[0] + '.0'
Write-Output ('{0,-40} {1} ({2}, {3})' -f 'dotnet SDK', $sdk, $framework, $rid)

$proj = Join-Path $work 'Bench'
New-Item -ItemType Directory -Path $proj | Out-Null
@"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>$framework</TargetFramework>
    <Nullable>disable</Nullable>
    <InvariantGlobalization>true</InvariantGlobalization>
  </PropertyGroup>
</Project>
"@ | Set-Content -LiteralPath (Join-Path $proj 'Bench.csproj') -Encoding utf8
@'
double total = 0;
for (double n = 1; n <= 400; n += 1) {
    double a1 = n + 7; double a2 = a1 * 3; double a3 = a2 - n; double a4 = a3 / 2;
    total = total + a4;
}
System.Console.WriteLine("arithmetic total " + total);
'@ | Set-Content -LiteralPath (Join-Path $proj 'Program.cs') -Encoding utf8

function Measure-Build {
    param([string]$Name, [string[]]$Arguments, [string]$OutDir)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $log = & dotnet @Arguments -o $OutDir 2>&1
    $sw.Stop()
    if ($LASTEXITCODE -ne 0) {
        $why = ($log | Where-Object { "$_" -match 'error' } | Select-Object -First 1)
        Write-Output ('{0,-40} failed after {1:N1} s: {2}' -f $Name, $sw.Elapsed.TotalSeconds, "$why".Trim())
        return
    }
    $exe = Get-ChildItem -LiteralPath $OutDir -File | Where-Object { $_.Name -in @('Bench', 'Bench.exe') } | Select-Object -First 1
    $size = (Get-ChildItem -LiteralPath $OutDir -File -Recurse | Measure-Object Length -Sum).Sum
    $runSw = [System.Diagnostics.Stopwatch]::StartNew()
    $out = (& $exe.FullName) -join ''
    $runSw.Stop()
    Write-Output ('{0,-40} build {1,5:N1} s, output {2,6:N1} MB, run {3,5:N0} ms: {4}' -f $Name, $sw.Elapsed.TotalSeconds, ($size / 1MB), $runSw.Elapsed.TotalMilliseconds, $out)
}

Push-Location $proj
try {
    Measure-Build 'framework-dependent (first build)' @('publish', '-c', 'Release', '-r', $rid, '--self-contained', 'false') (Join-Path $work 'fd')
    Measure-Build 'framework-dependent (second build)' @('publish', '-c', 'Release', '-r', $rid, '--self-contained', 'false') (Join-Path $work 'fd2')
    Measure-Build 'self-contained single file' @('publish', '-c', 'Release', '-r', $rid, '--self-contained', 'true', '-p:PublishSingleFile=true') (Join-Path $work 'sc')
    Measure-Build 'Native AOT' @('publish', '-c', 'Release', '-r', $rid, '-p:PublishAot=true') (Join-Path $work 'aot')
}
finally { Pop-Location; Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
