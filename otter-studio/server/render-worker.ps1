# render-worker.ps1 - Otter Studio's compiler process (server/render-worker.mjs).
#
# Starting PowerShell and loading the compiler costs about a second and a
# half; compiling a form once it is loaded takes about a tenth of that. So
# Studio keeps this one process running and sends it the programs to
# compile, one JSON line each:
#
#   in:  {"id":1,"source":"C:\\...\\x.ot","output":"C:\\...\\x.html","sourceDir":"C:\\proj"}
#   out: {"id":1,"ok":true}  or  {"id":1,"ok":false,"code":2,"message":"Otter Syntax Error ..."}
#
# It compiles exactly as `otter web <source> -SourceDir <dir>` does
# (Export-OtterWebApplication), and reports errors the way that command
# prints them, lines mapped back to the file that has them.

param([Parameter(Mandatory)][string]$SrcRoot)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $SrcRoot 'Otter.Web.psm1')
# For mapping an error's line back to the file it is in (below); the
# compiler imports it for itself, not for this script.
Import-Module (Join-Path $SrcRoot 'Otter.Module.psm1')

function Write-Reply($reply) {
    [Console]::Out.WriteLine(($reply | ConvertTo-Json -Compress))
    [Console]::Out.Flush()
}

Write-Reply @{ ready = $true }

while ($null -ne ($line = [Console]::In.ReadLine())) {
    if (-not $line.Trim()) { continue }
    $request = $line | ConvertFrom-Json
    $reply = @{ id = $request.id }
    try {
        $exportArgs = @{ SourcePath = $request.source; OutputPath = $request.output; PassThruExceptions = $true }
        if ($request.sourceDir) { $exportArgs.SourceDirectory = $request.sourceDir }
        Export-OtterWebApplication @exportArgs | Out-Null
        $reply.ok = $true
    }
    catch {
        $err = $_.Exception
        $reply.ok = $false
        # An Otter error of any kind (OtterError and its subclasses, such as
        # OtterMultipleErrorsException) - what `otter web` catches.
        if ($err.PSObject.Methods['FormatDetailed']) {
            # Lines in the combined program -> the file and line they came from.
            try {
                $resolved = if ($request.sourceDir) {
                    Resolve-OtterModuleSource -FilePath $request.source -ImportDirectory $request.sourceDir
                } else {
                    Resolve-OtterModuleSource -FilePath $request.source
                }
                $err = ConvertTo-OtterRemappedDiagnostics -Error $err -ResolvedProgram $resolved -RootFile $request.source
            } catch { }
            $reply.code = 2
            $reply.message = $err.FormatDetailed()
        }
        else {
            $reply.code = 1
            $reply.message = "Otter hit a problem inside itself, which means this is a bug in Otter.`n  $($err.Message)"
        }
    }
    Write-Reply $reply
}
