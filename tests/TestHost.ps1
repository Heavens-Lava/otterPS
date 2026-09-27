# TestHost.ps1
#
# Dot-source to launch child Otter processes with the SAME PowerShell that is
# running the tests, on any host. Test files must not hard-code powershell.exe
# (Windows only), cmd, or $env:TEMP (unset on Linux/macOS).
#
#     . "$PSScriptRoot\TestHost.ps1"
#     & $script:OtterHostExe @script:OtterHostArgs -File $otterPs1 run $file
#     $psi.FileName = $script:OtterHostExe
#     $psi.Arguments = "$script:OtterHostArgString -File `"$otterPs1`" run `"$file`""

$script:OtterHostExe = (Get-Process -Id $PID).Path
$script:OtterHostIsWindows = ($PSVersionTable.PSEdition -ne 'Core') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
$script:OtterHostArgs = @('-NoProfile')
if ($script:OtterHostIsWindows) { $script:OtterHostArgs += @('-ExecutionPolicy', 'Bypass') }
$script:OtterHostArgString = $script:OtterHostArgs -join ' '
