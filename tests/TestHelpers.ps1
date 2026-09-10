# TestHelpers.ps1
#
# A tiny test harness, deliberately not Pester.
#
# The brief says Otter must run with zero installs. Making the test suite
# depend on Pester would quietly make that untrue for anyone who cloned the
# repo, so this is about 60 lines of plain PowerShell instead.
#
# Dot-source it (functions dot-source fine; only CLASSES need `using module`):
#
#     . "$PSScriptRoot\TestHelpers.ps1"
#
#     Test-Otter 'say prints a literal' {
#         Assert-AreEqual -Expected 'Hello' -Actual $result
#     }
#
#     Complete-OtterTests

$script:OtterPassed = 0
$script:OtterFailed = 0
$script:OtterFailures = @()

function Test-Otter {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )

    try {
        & $Body
        $script:OtterPassed++
        Write-Host "  pass  $Name" -ForegroundColor DarkGreen
    }
    catch {
        $script:OtterFailed++
        $script:OtterFailures += "$Name`n        $($_.Exception.Message)"
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}

function Assert-AreEqual {
    param($Expected, $Actual, [string]$Message = '')

    $expectedText = if ($null -eq $Expected) { '<null>' } else { [string]$Expected }
    $actualText = if ($null -eq $Actual) { '<null>' } else { [string]$Actual }

    if ($expectedText -cne $actualText) {
        $detail = "expected [$expectedText] but got [$actualText]"
        if ($Message) { $detail = "$Message - $detail" }
        throw $detail
    }
}

# Compares printed output line-by-line, which is what most Otter tests check.
function Assert-Lines {
    param([string[]]$Expected, [string[]]$Actual, [string]$Message = '')

    $expectedText = ($Expected -join '|')
    $actualText = ($Actual -join '|')

    if ($expectedText -cne $actualText) {
        $detail = "expected lines [$expectedText] but got [$actualText]"
        if ($Message) { $detail = "$Message - $detail" }
        throw $detail
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message = 'expected the condition to be true')
    if (-not $Condition) { throw $Message }
}

function Assert-False {
    param([bool]$Condition, [string]$Message = 'expected the condition to be false')
    if ($Condition) { throw $Message }
}

# Asserts that running $Body produces an Otter error mentioning $Containing.
# Checking the MESSAGE matters as much as the failure: error quality is a
# feature of this language (D14).
function Assert-OtterFails {
    param(
        [Parameter(Mandatory)][scriptblock]$Body,
        [string]$Containing = ''
    )

    try {
        & $Body
    }
    catch {
        $message = $_.Exception.Message
        if ($Containing -and $message -notlike "*$Containing*") {
            throw "expected an error containing [$Containing] but got [$message]"
        }
        return
    }

    throw 'expected this to fail, but it succeeded'
}

function Complete-OtterTests {
    Write-Host ''
    if ($script:OtterFailed -eq 0) {
        Write-Host "  $($script:OtterPassed) passed" -ForegroundColor Green
        exit 0
    }

    Write-Host "  $($script:OtterPassed) passed, $($script:OtterFailed) FAILED" -ForegroundColor Red
    Write-Host ''
    foreach ($failure in $script:OtterFailures) {
        Write-Host "    $failure" -ForegroundColor Red
    }
    exit 1
}
