using module ..\Otter.Contract.psm1

# Otter.Electron.psm1 - the Electron desktop target.
#
#   Otter source -> web compiler -> app/index.html -> Electron shell
#
# There is no second compiler here. Export-OtterWebApplication produces the
# same page `otter web` produces (project stylesheet included), and this module
# puts a generic Electron shell around it:
#
#   <output>/
#     package.json      name, version, "main": "main.js", electron dev dependency
#     main.js           opens the window, answers bridge requests (Node side)
#     preload.js        exposes window.otterNative to the page (contextBridge)
#     app/index.html    the compiled program
#     app/<assets>      declared project assets, if any
#
# The shell files are copied verbatim from src/electron/. They contain nothing
# about any particular program; everything program-specific is in app/.
#
# Running the result needs Electron itself (`npm install` then `npm start`, or
# any Electron binary pointed at the folder). Otter does not download it.

function Export-OtterElectronApplication {
    <#
    .SYNOPSIS
    Wraps a compiled Otter program in an Electron application folder.
    #>
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$OutputDir,
        [string]$Name,
        [string]$Version = '1.0.0',
        [string[]]$Assets = @(),
        [string]$AssetRoot,
        [switch]$PassThruExceptions
    )

    if (-not (Get-Command Export-OtterWebApplication -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $PSScriptRoot 'Otter.Web.psm1') -Global
    }

    $resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
    $outRoot = [System.IO.Path]::GetFullPath($OutputDir)
    $appDir = Join-Path $outRoot 'app'
    New-Item -ItemType Directory -Path $appDir -Force | Out-Null

    # 1. The program, compiled exactly as `otter web` compiles it.
    $indexHtml = Join-Path $appDir 'index.html'
    Export-OtterWebApplication -SourcePath $resolvedSource -OutputPath $indexHtml -PassThruExceptions:$PassThruExceptions | Out-Null

    # 2. The shell.
    $templateDir = Join-Path $PSScriptRoot 'electron'
    foreach ($file in @('main.js', 'preload.js')) {
        Copy-Item -LiteralPath (Join-Path $templateDir $file) -Destination (Join-Path $outRoot $file) -Force
    }

    # 3. Declared assets, kept at the same relative paths beside index.html.
    $assetBase = if ($AssetRoot) { (Resolve-Path -LiteralPath $AssetRoot).Path } else { Split-Path -Parent $resolvedSource }
    foreach ($asset in $Assets) {
        if ([string]::IsNullOrWhiteSpace($asset)) { continue }
        $relative = $asset.Trim()
        $from = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($assetBase, $relative))
        $to = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($appDir, $relative))
        $toParent = Split-Path -Parent $to
        if (-not (Test-Path -LiteralPath $toParent)) { New-Item -ItemType Directory -Path $toParent -Force | Out-Null }
        Copy-Item -LiteralPath $from -Destination $to -Force
    }

    # 4. package.json - a valid npm name plus the human name for the window.
    $displayName = if ([string]::IsNullOrWhiteSpace($Name)) { [System.IO.Path]::GetFileNameWithoutExtension($resolvedSource) } else { $Name }
    $packageName = ConvertTo-OtterPackageName -Name $displayName
    $safeVersion = if ($Version -match '^\d+\.\d+\.\d+') { $Version } else { '1.0.0' }
    $manifest = [ordered]@{
        name            = $packageName
        productName     = $displayName
        version         = $safeVersion
        description     = "$displayName - an Otter desktop application"
        main            = 'main.js'
        private         = $true
        scripts         = [ordered]@{ start = 'electron .' }
        devDependencies = [ordered]@{ electron = '^32.0.0' }
        otter           = [ordered]@{ target = 'electron'; entry = 'app/index.html' }
    }
    $json = ConvertTo-Json -InputObject $manifest -Depth 5
    [System.IO.File]::WriteAllText((Join-Path $outRoot 'package.json'), $json + "`n", (New-Object System.Text.UTF8Encoding($false)))

    return [pscustomobject]@{
        OutputDir   = $outRoot
        EntryHtml   = $indexHtml
        PackageJson = (Join-Path $outRoot 'package.json')
        PackageName = $packageName
    }
}

# npm package names: lowercase, URL-safe, no leading dot or underscore.
function ConvertTo-OtterPackageName {
    param([Parameter(Mandatory)][string]$Name)
    $lower = $Name.Trim().ToLowerInvariant()
    $cleaned = [regex]::Replace($lower, '[^a-z0-9._-]+', '-').Trim('-', '.', '_')
    if ([string]::IsNullOrWhiteSpace($cleaned)) { $cleaned = 'otter-app' }
    if ($cleaned.Length -gt 214) { $cleaned = $cleaned.Substring(0, 214) }
    return $cleaned
}

Export-ModuleMember -Function Export-OtterElectronApplication
