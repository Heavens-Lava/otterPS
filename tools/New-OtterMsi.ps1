<#
.SYNOPSIS
Builds Otter's Windows installer (MSI) from a release ZIP - the package winget
installs (`winget install otter`).

.DESCRIPTION
The MSI holds exactly the release ZIP's files and adds no executable of its
own (distribution\msi\Otter.wxs says what it does). Needs the WiX toolset 5:
    dotnet tool install --global wix --version 5.0.2

Output, next to the release ZIP:
  otter-<version>.msi          the installer
  otter-<version>.msi.sha256   its checksum (the winget manifest needs it)

.EXAMPLE
powershell -NoProfile -File tools\New-OtterMsi.ps1 -ReleaseZip dist\otter-1.0.1.zip
#>
param([Parameter(Mandatory)][string]$ReleaseZip)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$ReleaseZip = (Resolve-Path -LiteralPath $ReleaseZip).Path
$name = [System.IO.Path]::GetFileNameWithoutExtension($ReleaseZip)          # otter-1.0.1
if ($name -notmatch '^otter-(\d+\.\d+\.\d+)$') { throw "Expected a release ZIP named otter-<major>.<minor>.<patch>.zip, not $name.zip." }
$version = $Matches[1]
$output = Join-Path (Split-Path -Parent $ReleaseZip) "$name.msi"

$wix = Get-Command wix -ErrorAction SilentlyContinue
if (-not $wix) {
    $toolPath = Join-Path $env:USERPROFILE '.dotnet\tools\wix.exe'
    if (Test-Path -LiteralPath $toolPath) { $wix = Get-Item -LiteralPath $toolPath }
    else { throw 'The WiX toolset is needed: dotnet tool install --global wix --version 5.0.2' }
}
$wixPath = if ($wix -is [System.Management.Automation.CommandInfo]) { $wix.Source } else { $wix.FullName }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('otter-msi-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
Add-Type -AssemblyName System.IO.Compression.FileSystem
try {
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ReleaseZip, $work)
    $payload = Join-Path $work $name
    if (-not (Test-Path -LiteralPath (Join-Path $payload 'otter.cmd'))) { throw "$ReleaseZip does not hold $name\otter.cmd." }
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }

    # One component per file, each tracked by a per-user registry value (ICE38),
    # and a RemoveFolder for every folder (ICE64). Component GUIDs come from the
    # file's path, so the same file keeps the same GUID in every version.
    $md5 = [System.Security.Cryptography.MD5]::Create()
    function Get-StableGuid { param([string]$Text) [Guid]::new($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("otter-msi:$Text"))).ToString().ToUpperInvariant() }
    function ConvertTo-Xml { param([string]$Text) [System.Security.SecurityElement]::Escape($Text) }
    $directoryIds = @{ '' = 'INSTALLFOLDER' }
    $directoryXml = [System.Text.StringBuilder]::new()
    $componentXml = [System.Text.StringBuilder]::new()
    function Add-OtterDirectory {
        param([string]$Path, [string]$Relative, [string]$Indent)
        foreach ($sub in (Get-ChildItem -LiteralPath $Path -Directory | Sort-Object Name)) {
            $rel = if ($Relative) { "$Relative\$($sub.Name)" } else { $sub.Name }
            $id = 'd' + ($directoryIds.Count).ToString('000')
            $directoryIds[$rel] = $id
            [void]$directoryXml.AppendLine("$Indent<Directory Id=`"$id`" Name=`"$(ConvertTo-Xml $sub.Name)`">")
            Add-OtterDirectory -Path $sub.FullName -Relative $rel -Indent "$Indent  "
            [void]$directoryXml.AppendLine("$Indent</Directory>")
        }
    }
    Add-OtterDirectory -Path $payload -Relative '' -Indent '      '
    $removed = @{}
    $index = 0
    foreach ($file in (Get-ChildItem -LiteralPath $payload -File -Recurse | Sort-Object FullName)) {
        $index++
        $relativeFile = $file.FullName.Substring($payload.Length + 1)
        $relativeDir = Split-Path -Parent $relativeFile
        $dirId = $directoryIds[$relativeDir]
        [void]$componentXml.AppendLine("      <Component Id=`"c$($index.ToString('000'))`" Directory=`"$dirId`" Guid=`"$(Get-StableGuid $relativeFile)`">")
        [void]$componentXml.AppendLine("        <File Id=`"f$($index.ToString('000'))`" Source=`"$(ConvertTo-Xml $file.FullName)`" KeyPath=`"no`" />")
        [void]$componentXml.AppendLine("        <RegistryValue Root=`"HKCU`" Key=`"Software\Otter\Files`" Name=`"$(ConvertTo-Xml $relativeFile)`" Type=`"integer`" Value=`"1`" KeyPath=`"yes`" />")
        if (-not $removed.ContainsKey($dirId)) {
            [void]$componentXml.AppendLine("        <RemoveFolder Id=`"r$dirId`" Directory=`"$dirId`" On=`"uninstall`" />")
            $removed[$dirId] = $true
        }
        [void]$componentXml.AppendLine('      </Component>')
    }
    $fragment = @"
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Fragment>
    <DirectoryRef Id="INSTALLFOLDER">
$($directoryXml.ToString().TrimEnd())
    </DirectoryRef>
    <ComponentGroup Id="OtterFiles">
$($componentXml.ToString().TrimEnd())
    </ComponentGroup>
  </Fragment>
</Wix>
"@
    $fragmentPath = Join-Path $work 'OtterFiles.wxs'
    [System.IO.File]::WriteAllText($fragmentPath, $fragment, [System.Text.UTF8Encoding]::new($false))

    $built = & $wixPath build (Join-Path $root 'distribution\msi\Otter.wxs') $fragmentPath -d "Version=$version" `
        -arch x64 -o $output 2>&1
    if ($LASTEXITCODE -ne 0) { throw "wix build failed:`n$($built -join "`n")" }
    Remove-Item -LiteralPath ([System.IO.Path]::ChangeExtension($output, '.wixpdb')) -Force -ErrorAction SilentlyContinue
    $hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    [System.IO.File]::WriteAllText("$output.sha256", "$hash  $([System.IO.Path]::GetFileName($output))`n", [System.Text.UTF8Encoding]::new($false))
    "$output"
    "  $((Get-Item -LiteralPath $output).Length) bytes, SHA-256 $hash"
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
