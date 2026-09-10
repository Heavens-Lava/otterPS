using module ..\Otter.Contract.psm1

# Otter.Runtime.psm1
#
# The runtime: what Otter values ARE and where they LIVE.
#
# The interpreter walks the AST and decides *what to do*. This module answers
# the questions it asks along the way:
#
#   - where is the variable "score"?          -> OtterEnvironment
#   - is this value true enough for an if?    -> Test-OtterTruthy   (D9)
#   - how do I print it?                      -> Format-OtterValue  (D8)
#   - the user typed "29" - is that a number? -> ConvertFrom-OtterInput (D6)
#
# Kept separate from the interpreter so these rules can be tested on their own.


# ===============================================================
# ENVIRONMENT - where variables live
# ===============================================================
#
# An environment is a bag of variables plus a link to the one that encloses
# it. Looking up a name walks outward until it is found:
#
#     greet's scope     { name = "Jeff" }      <- function call
#            |  Parent
#            v
#     global scope      { name = "Outside" }
#
# That chain is what makes this work (from the build brief):
#
#     name is "Outside"
#     to greet name
#         say "Hello" name
#     greet "Jeff"        -> Hello Jeff     (finds the parameter)
#     say name            -> Outside        (global was never touched)

class OtterEnvironment {
    [hashtable]$Variables
    [OtterEnvironment]$Parent

    OtterEnvironment() {
        # Ordinal = case-SENSITIVE. PowerShell hashtables ignore case by
        # default, but D10 says loggedIn and loggedin are different variables.
        $this.Variables = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
        $this.Parent = $null
    }

    OtterEnvironment([OtterEnvironment]$parent) {
        $this.Variables = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
        $this.Parent = $parent
    }

    # Does this name exist anywhere in the chain?
    [bool] Has([string]$name) {
        if ($this.Variables.ContainsKey($name)) { return $true }
        if ($null -ne $this.Parent) { return $this.Parent.Has($name) }
        return $false
    }

    # Read a variable. Callers must check Has() first - the interpreter raises
    # the friendly "Otter could not find the variable" error, not this class,
    # because only the interpreter knows the line number.
    [object] Get([string]$name) {
        if ($this.Variables.ContainsKey($name)) { return $this.Variables[$name] }
        if ($null -ne $this.Parent) { return $this.Parent.Get($name) }
        return $null
    }

    # Create a variable in THIS scope (named SetLocal, not Define: "define" is a
    # reserved word in PowerShell 5.1 and cannot be a method name), shadowing any outer one.
    # Used for function parameters and loop variables.
    [void] SetLocal([string]$name, [object]$value) {
        $this.Variables[$name] = $value
    }

    # Assign. Updates the variable where it already lives, so a while loop can
    # do "add 1 to number" and affect the real variable. If it exists nowhere,
    # it is created here.
    [void] Set([string]$name, [object]$value) {
        if ($this.Variables.ContainsKey($name)) {
            $this.Variables[$name] = $value
            return
        }
        if ($null -ne $this.Parent -and $this.Parent.Has($name)) {
            $this.Parent.Set($name, $value)
            return
        }
        $this.Variables[$name] = $value
    }
}


# ===============================================================
# FUNCTIONS - what "to greet name" creates
# ===============================================================

class OtterFunction {
    [string]$Name
    [string[]]$Parameters
    [Node[]]$Body

    OtterFunction([string]$name, [string[]]$parameters, [Node[]]$body) {
        $this.Name = $name
        $this.Parameters = $parameters
        $this.Body = $body
    }
}


# ===============================================================
# RETURN - how "return answer" escapes a function
# ===============================================================
#
# A tree-walking interpreter is a stack of nested PowerShell calls. "return"
# has to unwind all of them at once - out of an if, out of a loop, out of the
# function body. An exception is the tool that does exactly that.
#
# This is control flow, not an error. The function-call code catches it; it
# never reaches the user.

class OtterReturnSignal : System.Exception {
    [object]$Value
    OtterReturnSignal([object]$value) : base('return') {
        $this.Value = $value
    }
}


# ===============================================================
# VALUES
# ===============================================================

# A fresh Otter list. Generic List so add/remove are cheap and ordered.
function New-OtterList {
    param([object[]]$Items = @())
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Items) { $list.Add($item) }
    # -NoEnumerate, not `return , $list`: the comma wraps the list in an
    # object[], which PowerShell unwraps on assignment but NOT when the value
    # is passed straight into a .NET method call. That mismatch made lists
    # stop being lists the moment they were stored in an environment.
    Write-Output -NoEnumerate $list
}

function Test-OtterList {
    param([object]$Value)
    return $Value -is [System.Collections.Generic.List[object]]
}


# --- printing (D8) ----------------------------------------------
#
#   say name "is" age "years old."   ->   Jeff is 29 years old.
#
# Numbers must not print as 10.00, and booleans must be true/false, not the
# PowerShell True/False.

function Format-OtterValue {
    param([object]$Value)

    if ($null -eq $Value) { return 'nothing' }

    if ($Value -is [bool]) {
        if ($Value) { return 'true' } else { return 'false' }
    }

    if ($Value -is [double] -or $Value -is [int] -or $Value -is [long] -or $Value -is [decimal]) {
        $number = [double]$Value
        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        # A whole number prints with no decimal point at all.
        # Note: [double]::IsFinite is .NET Core only - PS 5.1 runs on .NET
        # Framework, so test for NaN and infinity the long way round.
        $isFinite = (-not [double]::IsNaN($number)) -and (-not [double]::IsInfinity($number))
        if ($isFinite -and [Math]::Floor($number) -eq $number -and [Math]::Abs($number) -lt 1e15) {
            return $number.ToString('0', $culture)
        }
        # Otherwise show up to 10 decimals, trimming trailing zeros: 3.5 stays 3.5
        return $number.ToString('0.##########', $culture)
    }

    if (Test-OtterList $Value) {
        $parts = foreach ($item in $Value) { Format-OtterValue -Value $item }
        return ($parts -join ', ')
    }

    return [string]$Value
}


# --- truthiness (D9) --------------------------------------------
#
# Note what is NOT here: an undefined variable. That is an error, not false,
# and the interpreter catches it before we ever get called.

function Test-OtterTruthy {
    param([object]$Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }

    if ($Value -is [double] -or $Value -is [int] -or $Value -is [long]) {
        return ([double]$Value) -ne 0
    }

    if (Test-OtterList $Value) { return $Value.Count -gt 0 }

    if ($Value -is [string]) { return $Value.Length -gt 0 }

    return $true
}


# --- numbers ----------------------------------------------------

# Is this value usable as a number? "29" counts; "banana" does not.
function Test-OtterNumeric {
    param([object]$Value)

    if ($Value -is [bool]) { return $false }
    if ($Value -is [double] -or $Value -is [int] -or $Value -is [long] -or $Value -is [decimal]) { return $true }

    if ($Value -is [string]) {
        $parsed = 0.0
        return [double]::TryParse(
            $Value,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed)
    }

    return $false
}

function ConvertTo-OtterNumber {
    param([object]$Value)

    if ($Value -is [double]) { return $Value }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal]) { return [double]$Value }

    if ($Value -is [string]) {
        $parsed = 0.0
        $ok = [double]::TryParse(
            $Value,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed)
        if ($ok) { return $parsed }
    }

    # Callers check Test-OtterNumeric first and raise the friendly error with
    # a line number. Reaching here is a bug in the interpreter, not user input.
    throw [System.InvalidOperationException]::new('ConvertTo-OtterNumber called on a non-numeric value')
}


# --- equality ---------------------------------------------------
#
# "29" and 29 compare equal (D6), because ask may have produced either one.
# Two non-numbers compare as exact, case-sensitive text.

function Test-OtterEqual {
    param([object]$Left, [object]$Right)

    if ($null -eq $Left -and $null -eq $Right) { return $true }
    if ($null -eq $Left -or $null -eq $Right) { return $false }

    if ($Left -is [bool] -or $Right -is [bool]) {
        if ($Left -is [bool] -and $Right -is [bool]) { return $Left -eq $Right }
        return $false
    }

    if ((Test-OtterNumeric $Left) -and (Test-OtterNumeric $Right)) {
        return (ConvertTo-OtterNumber $Left) -eq (ConvertTo-OtterNumber $Right)
    }

    if ((Test-OtterList $Left) -and (Test-OtterList $Right)) {
        if ($Left.Count -ne $Right.Count) { return $false }
        for ($i = 0; $i -lt $Left.Count; $i++) {
            if (-not (Test-OtterEqual -Left $Left[$i] -Right $Right[$i])) { return $false }
        }
        return $true
    }

    # Ordinal = case-sensitive, per D10.
    return [string]::Equals([string]$Left, [string]$Right, [System.StringComparison]::Ordinal)
}


# --- input coercion (D6) ----------------------------------------
#
#   ask "How old are you?" and call it age
#
# The user types text, but "29" should become the number 29 so that
# "if age is at least 18" works without the beginner doing anything.

function ConvertFrom-OtterInput {
    param([string]$Text)

    if ($null -eq $Text) { return '' }

    $trimmed = $Text.Trim()

    if ($trimmed -eq 'true') { return $true }
    if ($trimmed -eq 'false') { return $false }

    if ($trimmed.Length -gt 0) {
        $parsed = 0.0
        $ok = [double]::TryParse(
            $trimmed,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed)
        if ($ok) { return $parsed }
    }

    # Anything else stays exactly as typed - including the untrimmed original,
    # because leading spaces may be deliberate in text.
    return $Text
}


Export-ModuleMember -Function `
    New-OtterList, Test-OtterList, Format-OtterValue, Test-OtterTruthy, `
    Test-OtterNumeric, ConvertTo-OtterNumber, Test-OtterEqual, ConvertFrom-OtterInput
