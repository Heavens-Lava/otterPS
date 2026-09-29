# Test-OtterDesktopSmoke.ps1
#
# Desktop (WPF) smoke test (release check). Runs examples/v1/tasks.ot through
# the real CLI, drives its window with Windows UI Automation the way a user
# would (type, click Add), checks what the window shows, closes it, and checks
# that the process ends cleanly. Needs an interactive Windows desktop session.
#
#     powershell -NoProfile -File tools\Test-OtterDesktopSmoke.ps1
#
# Exit code 0 when every check passes; 1 otherwise.

param([string]$Root = (Split-Path -Parent $PSScriptRoot))

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$AE = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]
$PC = [System.Windows.Automation.PropertyCondition]
$CT = [System.Windows.Automation.ControlType]

$psi = [System.Diagnostics.ProcessStartInfo]::new('powershell.exe', "-NoProfile -ExecutionPolicy Bypass -File `"$Root\otter.ps1`" run `"$Root\examples\v1\tasks.ot`"")
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$proc = [System.Diagnostics.Process]::Start($psi)
$errTask = $proc.StandardError.ReadToEndAsync()
$outTask = $proc.StandardOutput.ReadToEndAsync()

$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check([string]$Name, [bool]$Ok, [string]$Detail) { $checks.Add([pscustomobject]@{ Check = $Name; Ok = $Ok; Detail = $Detail }) }

try {
    $window = $null
    $deadline = (Get-Date).AddSeconds(60)
    while (-not $window -and (Get-Date) -lt $deadline -and -not $proc.HasExited) {
        Start-Sleep -Milliseconds 500
        $window = $AE::RootElement.FindFirst($TS::Children, $PC::new($AE::ProcessIdProperty, $proc.Id))
    }
    Add-Check 'window opens' ($null -ne $window) $(if ($window) { $window.Current.Name } else { "process exited: $($proc.HasExited)" })
    if ($window) {
        Add-Check 'window title' ($window.Current.Name -eq 'Otter Tasks') $window.Current.Name
        $edit = $window.FindFirst($TS::Descendants, $PC::new($AE::ControlTypeProperty, $CT::Edit))
        $button = $window.FindFirst($TS::Descendants, $PC::new($AE::NameProperty, 'Add'))
        Add-Check 'task box and Add button present' ($null -ne $edit -and $null -ne $button) ''
        if ($edit -and $button) {
            $value = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
            $invoke = $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            foreach ($task in @('Buy milk', 'Walk the otter', '')) {
                $value.SetValue($task)
                $invoke.Invoke()
                Start-Sleep -Milliseconds 600
            }
            $texts = @($window.FindAll($TS::Descendants, $PC::new($AE::ControlTypeProperty, $CT::Text)) | ForEach-Object { $_.Current.Name } | Where-Object { $_ })
            $added = @($texts | Where-Object { $_ -in @('Buy milk', 'Walk the otter') })
            Add-Check 'each Add creates a line with the typed text' (($added -join '|') -eq 'Buy milk|Walk the otter') ($texts -join ' | ')
            Add-Check 'an empty box adds nothing' ($texts.Count -eq 4) "$($texts.Count) text elements"
            Add-Check 'the box is cleared after adding' ($value.Current.Value -eq '') "'$($value.Current.Value)'"
        }
        $window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
        $exited = $proc.WaitForExit(20000)
        Add-Check 'closing the window ends the program' $exited ''
        if ($exited) { Add-Check 'exit code 0' ($proc.ExitCode -eq 0) "exit $($proc.ExitCode)" }
    }
}
catch { Add-Check 'no automation error' $false $_.Exception.Message }
finally {
    if (-not $proc.HasExited) { $proc.Kill() }
    $proc.WaitForExit(5000) | Out-Null
}
$output = (($outTask.Result + $errTask.Result) -replace '\s+', ' ').Trim()
Add-Check 'no output or errors printed' ($output -eq '') $output

$checks | Format-Table -AutoSize | Out-String -Width 220 | Write-Output
$failed = @($checks | Where-Object { -not $_.Ok }).Count
if ($failed -gt 0) {
    Write-Output "DESKTOP SMOKE TEST FAILED: $failed check(s)."
    exit 1
}
Write-Output "Desktop smoke test passed ($($checks.Count) checks, PowerShell $($PSVersionTable.PSVersion))."
exit 0
