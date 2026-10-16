<#
.SYNOPSIS
Writes the winget manifest for an Otter MSI (`winget install otter`), ready
to be checked with `winget validate` and, once approved, proposed to
microsoft/winget-pkgs.

.DESCRIPTION
The manifest describes one exact MSI file: its SHA-256 must match the file
published at -InstallerUrl byte for byte, so generate it from the very MSI
that is (or will be) attached to the GitHub release. Version and ProductCode
are read from the MSI itself.

Writes <OutputDirectory>\manifests\j\JeffreyMacy\Otter\<version>\ with the
three winget files (version, installer, default locale). The package's
moniker is `otter`, so `winget install otter` finds it.

Nothing is submitted.
#>
param(
    [Parameter(Mandatory)][string]$Msi,
    [Parameter(Mandatory)][string]$OutputDirectory,
    # Where the MSI is (or will be) published.
    [string]$InstallerUrl = ''
)
$ErrorActionPreference = 'Stop'
$Msi = (Resolve-Path -LiteralPath $Msi).Path

function Get-MsiProperty {
    param([string]$Path, [string]$Name)
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($Path, 0))
    $view = $database.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $database, @("SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = '$Name'"))
    [void]$view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)
    $record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
    $value = if ($record) { $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, 1) } else { $null }
    [void]$view.GetType().InvokeMember('Close', 'InvokeMethod', $null, $view, $null)
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($database)
    return [string]$value
}

$version = Get-MsiProperty -Path $Msi -Name 'ProductVersion'
$productCode = Get-MsiProperty -Path $Msi -Name 'ProductCode'
$upgradeCode = Get-MsiProperty -Path $Msi -Name 'UpgradeCode'
$hash = (Get-FileHash -LiteralPath $Msi -Algorithm SHA256).Hash
if (-not $InstallerUrl) { $InstallerUrl = "https://github.com/Heavens-Lava/otterPS/releases/download/v$version/otter-$version.msi" }

$folder = Join-Path $OutputDirectory "manifests\j\JeffreyMacy\Otter\$version"
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$id = 'JeffreyMacy.Otter'
$schema = '1.6.0'
$files = [ordered]@{
    "$id.yaml" = @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.version.$schema.schema.json
PackageIdentifier: $id
PackageVersion: $version
DefaultLocale: en-US
ManifestType: version
ManifestVersion: $schema
"@
    "$id.installer.yaml" = @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.installer.$schema.schema.json
PackageIdentifier: $id
PackageVersion: $version
MinimumOSVersion: 10.0.17763.0
InstallerType: msi
Scope: user
InstallModes:
- interactive
- silent
- silentWithProgress
UpgradeBehavior: install
Commands:
- otter
ProductCode: '$productCode'
AppsAndFeaturesEntries:
- DisplayName: Otter Programming Language
  Publisher: Jeffrey Macy
  DisplayVersion: $version
  ProductCode: '$productCode'
  UpgradeCode: '$upgradeCode'
Installers:
- Architecture: x64
  InstallerUrl: $InstallerUrl
  InstallerSha256: $hash
ManifestType: installer
ManifestVersion: $schema
"@
    "$id.locale.en-US.yaml" = @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.defaultLocale.$schema.schema.json
PackageIdentifier: $id
PackageVersion: $version
PackageLocale: en-US
Publisher: Jeffrey Macy
PublisherUrl: https://otterprogramming.com
PublisherSupportUrl: https://github.com/Heavens-Lava/otterPS/issues
PrivacyUrl: https://otterprogramming.com/privacy/
Author: Jeffrey Macy
PackageName: Otter Programming Language
PackageUrl: https://otterprogramming.com
License: Otter Free Use License 1.1 (source-available)
LicenseUrl: https://otterprogramming.com/license/
Copyright: Copyright (c) 2026 Jeffrey Macy
ShortDescription: A programming language that reads like plain English, with friendly error messages.
Description: |-
  Otter is a programming language that reads like plain English. It is made for people learning to program and for anyone who wants to write small tools, scripts and apps without fighting the syntax.
  When something goes wrong, Otter tells you what happened in words, shows the line, and suggests a fix.
  After installing, open a new terminal and type otter.
Moniker: otter
Tags:
- programming-language
- learn-to-code
- beginner
- scripting
- education
ReleaseNotesUrl: https://github.com/Heavens-Lava/otterPS/releases/tag/v$version
ManifestType: defaultLocale
ManifestVersion: $schema
"@
}
foreach ($name in $files.Keys) {
    [System.IO.File]::WriteAllText((Join-Path $folder $name), $files[$name].Replace("`r`n", "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
}
"$folder"
"  version $version, ProductCode $productCode, SHA-256 $hash"
"  installer URL $InstallerUrl"
