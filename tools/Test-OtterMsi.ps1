<#
.SYNOPSIS
Installs, upgrades, checks and uninstalls the Otter MSI on this machine, and
reports every step. Meant for a clean, disposable Windows (the msi-test
workflow runs it on a fresh GitHub Actions runner), because it really
installs Otter for the current user.

.DESCRIPTION
  1. Install the older MSI (-OldMsi): files in %LOCALAPPDATA%\Programs\Otter,
     the folder on the user PATH, `otter --version` in a new shell.
  2. Install the new MSI (-NewMsi) over it: an upgrade - one Otter in
     Settings > Apps, one PATH entry, the new version answering.
  3. The installed `otter` and the certified release ZIP's `otter` (-ReleaseZip)
     run the same programs and must print exactly the same thing.
  4. Uninstall: files, folders, the PATH entry and HKCU\Software\Otter gone.

Exit code 0 when every check passed, 1 otherwise. msiexec logs go to -LogDirectory.
#>
param(
    [Parameter(Mandatory)][string]$OldMsi,
    [Parameter(Mandatory)][string]$NewMsi,
    [Parameter(Mandatory)][string]$ReleaseZip,
    [string]$LogDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) 'otter-msi-logs')
)
$ErrorActionPreference = 'Stop'
$installFolder = Join-Path $env:LOCALAPPDATA 'Programs\Otter'
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
$script:failures = 0

function Write-Check {
    param([bool]$Passed, [string]$What)
    if ($Passed) { Write-Host "  pass  $What" } else { Write-Host "  FAIL  $What" -ForegroundColor Red; $script:failures++ }
}

function Get-UserPathEntries {
    $value = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if (-not $value) { return @() }
    return @($value -split ';' | Where-Object { $_ })
}

# What Settings > Apps lists for Otter: the products Windows Installer has
# registered under Otter's UpgradeCode (per-user MSI installs are registered
# with Windows Installer, not under the Uninstall registry key).
$upgradeCode = '{F2065F2E-9E7A-405C-810C-3826A1DAAE39}'
function Get-OtterUninstallEntries {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $list = $installer.GetType().InvokeMember('RelatedProducts', 'GetProperty', $null, $installer, @($upgradeCode))
    $count = [int]$list.GetType().InvokeMember('Count', 'GetProperty', $null, $list, $null)
    $entries = @()
    for ($i = 0; $i -lt $count; $i++) {
        # A COM StringList: read each item as plain text before passing it back.
        $code = [string]$list.GetType().InvokeMember('Item', 'GetProperty', $null, $list, @($i))
        $entries += [pscustomobject]@{
            ProductCode = $code
            DisplayName = [string]$installer.GetType().InvokeMember('ProductInfo', 'GetProperty', $null, $installer, @($code, 'ProductName'))
            DisplayVersion = [string]$installer.GetType().InvokeMember('ProductInfo', 'GetProperty', $null, $installer, @($code, 'VersionString'))
        }
    }
    return $entries
}

function Invoke-Msiexec {
    param([string[]]$Arguments, [string]$Log)
    $process = Start-Process msiexec.exe -ArgumentList (@($Arguments) + @('/qn', '/norestart', '/l*v', "`"$Log`"")) -Wait -PassThru
    return $process.ExitCode
}

# A new process, with PATH read fresh from the registry, the way a newly
# opened terminal sees it.
function Invoke-InNewShell {
    param([string]$Command, [string]$WorkingDirectory = $env:TEMP)
    $machine = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $psi = [System.Diagnostics.ProcessStartInfo]::new('cmd.exe', "/d /c $Command")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.EnvironmentVariables['PATH'] = "$machine;$user"
    $process = [System.Diagnostics.Process]::Start($psi)
    $out = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $out.Trim() }
}

$oldVersion = ([regex]::Match([System.IO.Path]::GetFileName($OldMsi), '\d+\.\d+\.\d+')).Value
$newVersion = ([regex]::Match([System.IO.Path]::GetFileName($NewMsi), '\d+\.\d+\.\d+')).Value

Write-Host "1. Install Otter $oldVersion"
Write-Check (-not (Test-Path $installFolder)) "nothing at $installFolder before installing"
$exit = Invoke-Msiexec -Arguments @('/i', "`"$OldMsi`"") -Log (Join-Path $LogDirectory 'install-old.log')
Write-Check ($exit -eq 0) "msiexec /i exited 0 (got $exit)"
Write-Check (Test-Path (Join-Path $installFolder 'otter.cmd')) 'otter.cmd installed'
Write-Check (Test-Path (Join-Path $installFolder 'src\Otter.Interpreter.psm1')) 'the runtime modules installed'
Write-Check (@(Get-UserPathEntries | Where-Object { $_.TrimEnd('\') -eq $installFolder }).Count -eq 1) 'the install folder is on the user PATH once'
$version = Invoke-InNewShell 'otter --version'
Write-Check ($version.Output -eq "Otter $oldVersion") "a new shell runs ``otter --version``: $($version.Output)"
Write-Check (@(Get-OtterUninstallEntries).Count -eq 1) 'one entry in Settings > Apps'

Write-Host "2. Upgrade to Otter $newVersion"
$exit = Invoke-Msiexec -Arguments @('/i', "`"$NewMsi`"") -Log (Join-Path $LogDirectory 'install-new.log')
Write-Check ($exit -eq 0) "msiexec /i exited 0 (got $exit)"
$version = Invoke-InNewShell 'otter --version'
Write-Check ($version.Output -eq "Otter $newVersion") "a new shell runs ``otter --version``: $($version.Output)"
$entries = @(Get-OtterUninstallEntries)
Write-Check ($entries.Count -eq 1) "one entry in Settings > Apps (found $($entries.Count))"
Write-Check (($entries | Select-Object -First 1).DisplayVersion -eq $newVersion) "Settings > Apps shows $newVersion"
Write-Check (@(Get-UserPathEntries | Where-Object { $_.TrimEnd('\') -eq $installFolder }).Count -eq 1) 'still exactly one PATH entry'

Write-Host '3. The installed otter and the certified release ZIP behave the same'
$certified = Join-Path ([System.IO.Path]::GetTempPath()) ('otter-certified-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($ReleaseZip, $certified)
$certifiedCmd = Get-ChildItem -LiteralPath $certified -Recurse -Filter 'otter.cmd' | Select-Object -First 1
$programs = @{
    'hello.ot' = 'say "Hello from the installer test"'
    'math.ot' = "x is 7`nsay x times 6 / 4`nsay 2 plus 3 times 4"
    'lists.ot' = "games are`n    `"Zelda`"`n    `"Mario`"`n.`nsort games`nsay games length of games"
    'error.ot' = "say `"before`"`ny is 1 / 0"
    'syntax.ot' = "say `"unclosed"
}
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('otter-msi-programs-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
foreach ($name in ($programs.Keys | Sort-Object)) {
    [System.IO.File]::WriteAllText((Join-Path $work $name), $programs[$name] + "`n", [System.Text.UTF8Encoding]::new($false))
    $installed = Invoke-InNewShell "otter run $name" $work
    $reference = Invoke-InNewShell "`"$($certifiedCmd.FullName)`" run $name" $work
    Write-Check (($installed.Output -eq $reference.Output) -and ($installed.ExitCode -eq $reference.ExitCode)) "$($name): same output and exit code ($($installed.ExitCode))"
}
foreach ($check in @('check hello.ot', 'help')) {
    $installed = Invoke-InNewShell "otter $check" $work
    $reference = Invoke-InNewShell "`"$($certifiedCmd.FullName)`" $check" $work
    Write-Check ($installed.Output -eq $reference.Output) "otter $($check): same output"
}

Write-Host '4. Uninstall'
$productCode = (@(Get-OtterUninstallEntries) | Select-Object -First 1).ProductCode
Write-Check ([bool]$productCode) "Windows Installer knows Otter's product code ($productCode)"
$exit = Invoke-Msiexec -Arguments @('/x', $productCode) -Log (Join-Path $LogDirectory 'uninstall.log')
Write-Check ($exit -eq 0) "msiexec /x exited 0 (got $exit)"
Write-Check (-not (Test-Path $installFolder)) "$installFolder removed"
Write-Check (@(Get-UserPathEntries | Where-Object { $_.TrimEnd('\') -eq $installFolder }).Count -eq 0) 'the PATH entry removed'
Write-Check (-not (Test-Path 'HKCU:\Software\Otter')) 'HKCU\Software\Otter removed'
Write-Check (@(Get-OtterUninstallEntries).Count -eq 0) 'no entry left in Settings > Apps'
$gone = Invoke-InNewShell 'otter --version'
Write-Check ($gone.ExitCode -ne 0) 'a new shell no longer finds otter'

Remove-Item -LiteralPath $certified, $work -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Host "$($script:failures) check(s) failed." -ForegroundColor Red; exit 1 }
Write-Host 'All installer checks passed.'
exit 0
