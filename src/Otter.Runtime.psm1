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

class OtterSignal {
    [string]$Name
    [object]$Value
    [int]$Version
    [System.Collections.Generic.List[object]]$Subscribers

    OtterSignal([string]$name, [object]$value) {
        $this.Name = $name
        $this.Value = $value
        $this.Version = 1
        $this.Subscribers = [System.Collections.Generic.List[object]]::new()
    }

    [void] Subscribe([object]$subscriber) {
        if (-not $this.Subscribers.Contains($subscriber)) {
            $this.Subscribers.Add($subscriber)
        }
    }

    [void] Notify() {
        $this.Version++
        foreach ($sub in $this.Subscribers.ToArray()) {
            if ($sub -is [OtterDerived]) {
                $sub.MarkDirty()
            } elseif ($sub -is [scriptblock]) {
                & $sub $this.Value
            }
        }
    }
}

class OtterDerived {
    [string]$Name
    [Node]$Expression
    [object]$Environment
    [object]$CachedValue
    [bool]$IsDirty
    [bool]$IsEvaluating
    [System.Collections.Generic.HashSet[string]]$Dependencies
    [System.Collections.Generic.List[object]]$Subscribers

    OtterDerived([string]$name, [Node]$expression, [object]$env) {
        $this.Name = $name
        $this.Expression = $expression
        $this.Environment = $env
        $this.CachedValue = $null
        $this.IsDirty = $true
        $this.IsEvaluating = $false
        $this.Dependencies = [System.Collections.Generic.HashSet[string]]::new()
        $this.Subscribers = [System.Collections.Generic.List[object]]::new()
    }

    [void] Subscribe([object]$subscriber) {
        if (-not $this.Subscribers.Contains($subscriber)) {
            $this.Subscribers.Add($subscriber)
        }
    }

    [void] MarkDirty() {
        $this.IsDirty = $true
        foreach ($sub in $this.Subscribers.ToArray()) {
            if ($sub -is [OtterDerived]) {
                $sub.MarkDirty()
            } elseif ($sub -is [scriptblock]) {
                & $sub $this.CachedValue
            }
        }
    }
}

class OtterEnvironment {
    static [scriptblock]$DerivedEvaluator = $null
    static [System.Collections.Generic.HashSet[string]]$ActiveDependencyTracker = $null

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

    [object] GetRaw([string]$name) {
        if ($this.Variables.ContainsKey($name)) { return $this.Variables[$name] }
        if ($null -ne $this.Parent) { return $this.Parent.GetRaw($name) }
        return $null
    }

    # Read a variable. Callers must check Has() first - the interpreter raises
    # the friendly "Otter could not find the variable" error, not this class,
    # because only the interpreter knows the line number.
    [object] Get([string]$name) {
        $raw = $this.GetRaw($name)
        if ($raw -is [OtterSignal]) {
            if ($null -ne [OtterEnvironment]::ActiveDependencyTracker) {
                [void][OtterEnvironment]::ActiveDependencyTracker.Add($raw.Name)
            }
            return $raw.Value
        }
        if ($raw -is [OtterDerived]) {
            if ($null -ne [OtterEnvironment]::ActiveDependencyTracker) {
                [void][OtterEnvironment]::ActiveDependencyTracker.Add($raw.Name)
            }
            if ($null -ne [OtterEnvironment]::DerivedEvaluator) {
                return (& ([OtterEnvironment]::DerivedEvaluator) $raw $this)
            }
            return $raw.CachedValue
        }
        return $raw
    }

    [void] SetRaw([string]$name, [object]$value) {
        $this.Variables[$name] = $value
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
            $cur = $this.Variables[$name]
            if ($cur -is [OtterSignal]) {
                # D56: a watcher fires only on an actual change, using
                # Otter's own equality semantics - the same rule that makes
                # two content-identical things distinct (D-audit fix) also
                # applies here, so `state person is a thing` gets a
                # coherent, identity-based notion of "changed." Assigning
                # the current value again is a real, common no-op pattern
                # (e.g. clamping logic that reassigns unconditionally) and
                # must not fire "changes" watchers or re-run derived work.
                $changed = -not (Test-OtterEqual -Left $cur.Value -Right $value)
                $cur.Value = $value
                if ($changed) { $cur.Notify() }
                return
            }
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
# DATES (D32)
# ===============================================================
#
#     date is today       -> a date, no time of day
#     started is now      -> a date AND a time
#
# A date is a real value, not text. Text would have to be re-parsed on every
# comparison and every piece of arithmetic, and "add 7 days" to a string is
# not a thing that can be made to work.
#
# HasTime is what separates the two. "hour of" a plain date is a mistake
# worth reporting rather than answering with a silent zero - midnight and
# "no time at all" are different.

class OtterDate {
    [datetime]$Value
    [bool]$HasTime

    OtterDate([datetime]$value, [bool]$hasTime) {
        $this.HasTime = $hasTime
        # A date with no time is pinned to midnight so two dates made the
        # same day are equal regardless of when they were made.
        if ($hasTime) { $this.Value = $value }
        else { $this.Value = $value.Date }
    }

    [string] ToString() {
        if ($this.HasTime) { return $this.Value.ToString('yyyy-MM-dd HH:mm:ss') }
        return $this.Value.ToString('yyyy-MM-dd')
    }
}

function Test-OtterDate {
    param([object]$Value)
    return $Value -is [OtterDate]
}

# D102: bytes is its own runtime type, deliberately NOT a plain [byte[]]
# (which PowerShell would happily treat as just another array/list, the
# exact "bytes is secretly a list of numbers" conflation rules.md's D102
# design explicitly rejects) and NOT text. Wrapping it, the same pattern
# OtterDate uses, keeps `Test-OtterBytes`/type-name reporting exact and
# keeps a bytes value out of Test-OtterList's list-shaped code paths.
class OtterBytes {
    [byte[]]$Value
    OtterBytes([byte[]]$value) {
        $this.Value = $value
    }
}

function Test-OtterBytes {
    param([object]$Value)
    return $Value -is [OtterBytes]
}

function New-OtterToday {
    return [OtterDate]::new([datetime]::Now, $false)
}

function New-OtterNow {
    return [OtterDate]::new([datetime]::Now, $true)
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
# OBJECTS (0.3)
# ===============================================================
#
#     person is a thing
#         name is "Jeff"
#         age is 29
#     .
#
#     say name of person      ->  Jeff
#     age of person is 30
#
# An object is a type name plus a bag of named properties. Property names are
# case-sensitive for the same reason variable names are (D10).

class OtterObject {
    [string]$TypeName        # "thing", "Person", "text box"
    [hashtable]$Properties
    [System.Collections.Generic.List[string]]$Order   # insertion order, for printing

    OtterObject([string]$typeName) {
        $this.TypeName = $typeName
        $this.Properties = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
        $this.Order = [System.Collections.Generic.List[string]]::new()
    }

    [bool] HasProperty([string]$name) {
        return $this.Properties.ContainsKey($name)
    }

    [object] ReadProperty([string]$name) {
        if ($this.Properties.ContainsKey($name)) { return $this.Properties[$name] }
        return $null
    }

    [void] WriteProperty([string]$name, [object]$value) {
        if (-not $this.Properties.ContainsKey($name)) { $this.Order.Add($name) }
        $this.Properties[$name] = $value
    }

    [string[]] PropertyNames() {
        return $this.Order.ToArray()
    }
}

# a Person has
#     name
#     age
# .
#
# A custom type is a list of property names. Making one - "jeff is a Person" -
# produces an OtterObject with those properties present but empty.
class OtterType {
    [string]$Name
    [string[]]$FieldNames

    OtterType([string]$name, [string[]]$fieldNames) {
        $this.Name = $name
        $this.FieldNames = $fieldNames
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
    [int]$Line
    OtterReturnSignal([object]$value, [int]$line) : base('return') {
        $this.Value = $value
        $this.Line = $line
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

function Test-OtterObject {
    param([object]$Value)
    return $Value -is [OtterObject]
}


# --- printing (D8) ----------------------------------------------
#
#   say name "is" age "years old."   ->   Jeff is 29 years old.
#
# Numbers must not print as 10.00, and booleans must be true/false, not the
# PowerShell True/False.

function Format-OtterValue {
    param([object]$Value)

    # D22: the absence of a value is "gone". It is NOT false, 0, "", or an
    # empty list - those are five different states, and Otter says so.
    if ($null -eq $Value) { return 'gone' }

    # D44: an OtterUiResource, checked by TYPE NAME rather than [OtterUiResource].
    # This module is the foundation everything else builds on - Otter.UI.psm1
    # imports THIS file, not the other way around, so Otter.Runtime.psm1 must
    # never `using module` it back. A plain .GetType().Name comparison needs
    # no import at all and keeps that layering honest. Prints "a button", the
    # same shape OtterObject already uses for "a thing" - never the underlying
    # WPF type name (D44 principle 5: no provider-specific names in Otter output).
    if ($Value.GetType().Name -eq 'OtterUiResource') { return "a $($Value.Kind)" }

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

    # D32.5: ISO-style, because it is unambiguous, sorts correctly as text,
    # and does not silently pick a regional convention. Anyone wanting a
    # different shape has "format date as ...".
    if (Test-OtterDate $Value) { return $Value.ToString() }

    # D102: raw bytes are deliberately never displayed AS hex or AS text
    # here - that would silently pick one of the two representations the
    # design explicitly keeps separate. `<N bytes>` names only the one
    # fact that's unambiguous (the count); `hex from bytes x` / `text
    # from bytes x` are how a program asks for an actual representation.
    if (Test-OtterBytes $Value) { return "<$($Value.Value.Length) bytes>" }

    if (Test-OtterList $Value) {
        $parts = foreach ($item in $Value) { Format-OtterValue -Value $item }
        return ($parts -join ', ')
    }

    # An object prints the way it was declared - "a thing", "a Person" - which
    # is the phrase the programmer wrote. Printing every property would be
    # noise; "say name of person" is how you read one.
    if (Test-OtterObject $Value) {
        return "a $($Value.TypeName)"
    }

    if ($Value -is [OtterType]) {
        return "the type $($Value.Name)"
    }

    # Printing a function is almost always a mistake - a forgotten argument,
    # or a call that never happened. Say something a beginner can act on
    # rather than leaking the PowerShell class name.
    if ($Value -is [OtterFunction]) {
        return "<$($Value.Name), something Otter can do>"
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

    # An object exists, so it is true - even one with no properties set.
    if (Test-OtterObject $Value) { return $true }

    # D44: a UI resource exists (it was created for real, immediately - see
    # Otter.UI.psm1), so it is true, same reasoning as an object above.
    if ($Value.GetType().Name -eq 'OtterUiResource') { return $true }

    # A date exists, so it is true. There is no "zero date".
    if (Test-OtterDate $Value) { return $true }

    if ($Value -is [string]) { return $Value.Length -gt 0 }

    return $true
}


# --- numbers ----------------------------------------------------

# Is this value usable as a number? "29" counts; "banana" does not.
function Test-OtterNumeric {
    param([object]$Value)

    if ($Value -is [bool]) { return $false }
    # A date is not a number, however tempting its ticks are.
    if ($Value -is [OtterDate]) { return $false }
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

    # Two dates compare by their instant. A date and a non-date are never
    # equal - not even a date and text that looks like one.
    if ((Test-OtterDate $Left) -or (Test-OtterDate $Right)) {
        if ((Test-OtterDate $Left) -and (Test-OtterDate $Right)) {
            return $Left.Value -eq $Right.Value
        }
        return $false
    }

    if ((Test-OtterNumeric $Left) -and (Test-OtterNumeric $Right)) {
        return (ConvertTo-OtterNumber $Left) -eq (ConvertTo-OtterNumber $Right)
    }

    # D102: two bytes values compare by CONTENT, not reference - matches
    # section 9's acceptance example (two separately-built byte arrays
    # decoded from the same hex text must compare equal). A bytes value
    # and anything else are never equal, same "no silent cross-type
    # match" rule OtterDate gets above.
    if ((Test-OtterBytes $Left) -or (Test-OtterBytes $Right)) {
        if ((Test-OtterBytes $Left) -and (Test-OtterBytes $Right)) {
            if ($Left.Value.Length -ne $Right.Value.Length) { return $false }
            for ($bi = 0; $bi -lt $Left.Value.Length; $bi++) {
                if ($Left.Value[$bi] -ne $Right.Value[$bi]) { return $false }
            }
            return $true
        }
        return $false
    }

    if ((Test-OtterList $Left) -and (Test-OtterList $Right)) {
        if ($Left.Count -ne $Right.Count) { return $false }
        for ($i = 0; $i -lt $Left.Count; $i++) {
            if (-not (Test-OtterEqual -Left $Left[$i] -Right $Right[$i])) { return $false }
        }
        return $true
    }

    # A `thing` has no override for .ToString() (it prints as "OtterObject",
    # the bare class name), so falling through to the string-cast comparison
    # below made EVERY thing equal to every other thing - confirmed directly
    # (two differently-named things compared equal), which silently broke
    # `remove x from things` (it always matched and removed the first item,
    # since "equal" was never actually false) for any list of `thing`
    # values. Identity is the correct comparison here, matching how every
    # other reference-shaped Otter value already behaves (D44's UI
    # resources are never equal-by-content either) - two separately
    # constructed things with identical properties are still two different
    # things, and "remove specificThing from list" means exactly that
    # object, not "something that looks like it."
    if ((Test-OtterObject $Left) -or (Test-OtterObject $Right)) {
        return [object]::ReferenceEquals($Left, $Right)
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
    New-OtterList, Test-OtterList, Test-OtterObject, Test-OtterDate, `
    New-OtterToday, New-OtterNow, Format-OtterValue, Test-OtterTruthy, `
    Test-OtterNumeric, ConvertTo-OtterNumber, Test-OtterEqual, ConvertFrom-OtterInput, `
    Test-OtterBytes
