using module ..\Otter.Contract.psm1
using module .\Otter.Runtime.psm1
using module .\Otter.Library.psm1

# Otter.Interpreter.psm1
#
# The tree-walking interpreter. It takes the ProgramNode the parser built and
# does what it says.
#
#   ProgramNode
#       |
#       +-- SayStmt      -> print
#       +-- AssignStmt   -> store a variable
#       +-- IfStmt       -> test, then walk one branch
#       +-- WhileStmt    -> test and walk the body, repeatedly
#       ...
#
# There are only two kinds of function in here:
#
#   Invoke-Otter*  runs a STATEMENT and produces no value
#   Get-Otter*     evaluates an EXPRESSION and returns a value
#
# Keeping those apart is what stops stray PowerShell output leaking into
# Otter's results, which is the classic way an interpreter like this breaks.


# The source text, kept only so runtime errors can quote the offending line
# (D14). Set once per program run.
$script:SourceLines = @()

# The outermost scope. Function bodies hang off this, not off their caller,
# so a function cannot see its caller's local variables.
$script:GlobalEnvironment = $null

# Where "say" sends its text. Defaults to the console; tests swap in a
# collector so they can assert on what a program printed. Keeping this behind
# one function is also what lets `say` avoid Write-Output, which would leak
# into the return value of every function call.
$script:OutputWriter = $null

function Set-OtterOutputWriter {
    param([scriptblock]$Writer)
    $script:OutputWriter = $Writer
}

function Write-OtterLine {
    param([string]$Text)
    if ($null -ne $script:OutputWriter) {
        & $script:OutputWriter $Text
        return
    }
    Write-Host $Text
}


# ===============================================================
# ERRORS
# ===============================================================

function New-OtterRuntimeError {
    param(
        [string]$Message,
        [int]$Line,
        [string]$Suggestion = $null
    )

    $sourceLine = $null
    if ($script:SourceLines -and $Line -ge 1 -and $Line -le $script:SourceLines.Count) {
        $sourceLine = $script:SourceLines[$Line - 1]
    }

    return [OtterError]::new($Message, $Line, 'runtime', 0, $sourceLine, $Suggestion)
}

# "I need a number here" is the single most common runtime complaint, so it
# gets one consistent, friendly phrasing.
function Assert-OtterNumber {
    param([object]$Value, [int]$Line, [string]$What)

    if (Test-OtterNumeric $Value) { return (ConvertTo-OtterNumber $Value) }

    $shown = Format-OtterValue -Value $Value
    if ($Value -is [string]) { $shown = '"' + $Value + '"' }

    throw (New-OtterRuntimeError -Message "I expected a number for $What but got $shown." -Line $Line)
}


# ===============================================================
# ENTRY POINT
# ===============================================================

function Invoke-OtterProgram {
    param(
        [Parameter(Mandatory)][ProgramNode]$Program,
        [Parameter(Mandatory)][OtterEnvironment]$Environment,
        [string[]]$SourceLines = @()
    )

    $script:SourceLines = $SourceLines
    $script:GlobalEnvironment = $Environment

    Invoke-OtterStatements -Statements $Program.Statements -Environment $Environment
}

function Invoke-OtterStatements {
    param([Node[]]$Statements, [OtterEnvironment]$Environment)

    if ($null -eq $Statements) { return }
    foreach ($statement in $Statements) {
        Invoke-OtterStatement -Statement $statement -Environment $Environment
    }
}


# ===============================================================
# STATEMENTS
# ===============================================================

function Invoke-OtterStatement {
    param([Node]$Statement, [OtterEnvironment]$Environment)

    switch ($Statement.Kind.ToString()) {

        # say "Hello" name        (D8: parts joined by exactly one space)
        'Say' {
            if ($Statement.Parts.Count -eq 0) {
                Write-OtterLine -Text ''
                return
            }
            $rendered = @()
            foreach ($part in $Statement.Parts) {
                $value = Get-OtterValue -Expression $part -Environment $Environment
                $rendered += (Format-OtterValue -Value $value)
            }
            Write-OtterLine -Text ($rendered -join ' ')
            return
        }

        # name is "Jeff"
        'Assign' {
            $value = Get-OtterValue -Expression $Statement.Value -Environment $Environment
            $Environment.Set($Statement.Name, $value)
            return
        }

        # ask "What is your name?" and call it name       (D6)
        'Ask' {
            $prompt = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Prompt -Environment $Environment)
            Write-Host "$prompt " -NoNewline
            $typed = Read-Host
            $Environment.Set($Statement.Name, (ConvertFrom-OtterInput -Text $typed))
            return
        }

        # number1 and number2 make total
        'MathInto' {
            $value = Get-OtterValue -Expression $Statement.Expression -Environment $Environment
            $Environment.Set($Statement.Target, $value)
            return
        }

        # add 5 to score   /   add "Pokemon" to games        (D12)
        'AddTo' {
            Invoke-OtterAddTo -Statement $Statement -Environment $Environment
            return
        }

        # remove 2 from score   /   remove "Mario" from games (D12)
        'RemoveFrom' {
            Invoke-OtterRemoveFrom -Statement $Statement -Environment $Environment
            return
        }

        # if / otherwise if / otherwise
        'If' {
            foreach ($branch in $Statement.Branches) {
                $test = Get-OtterValue -Expression $branch.Condition -Environment $Environment
                if (Test-OtterTruthy -Value $test) {
                    Invoke-OtterStatements -Statements $branch.Body -Environment $Environment
                    return
                }
            }
            if ($null -ne $Statement.ElseBody) {
                Invoke-OtterStatements -Statements $Statement.ElseBody -Environment $Environment
            }
            return
        }

        # while number is less than 5
        'While' {
            while ($true) {
                $test = Get-OtterValue -Expression $Statement.Condition -Environment $Environment
                if (-not (Test-OtterTruthy -Value $test)) { break }
                Invoke-OtterStatements -Statements $Statement.Body -Environment $Environment
            }
            return
        }

        # repeat 3 times
        'Repeat' {
            $raw = Get-OtterValue -Expression $Statement.Count -Environment $Environment
            $count = Assert-OtterNumber -Value $raw -Line $Statement.Line -What 'the number of repeats'
            $whole = [int][Math]::Floor($count)
            for ($i = 0; $i -lt $whole; $i++) {
                Invoke-OtterStatements -Statements $Statement.Body -Environment $Environment
            }
            return
        }

        # count from 1 to 5 as number      (D5: both ends inclusive)
        'CountLoop' {
            $fromRaw = Get-OtterValue -Expression $Statement.From -Environment $Environment
            $toRaw = Get-OtterValue -Expression $Statement.To -Environment $Environment
            $from = Assert-OtterNumber -Value $fromRaw -Line $Statement.Line -What 'the value to count from'
            $to = Assert-OtterNumber -Value $toRaw -Line $Statement.Line -What 'the value to count to'

            # "count from 10 to 1" reads as counting down, so it counts down.
            $step = if ($from -le $to) { 1 } else { -1 }
            for ($n = $from; ($step -gt 0 -and $n -le $to) -or ($step -lt 0 -and $n -ge $to); $n += $step) {
                $Environment.SetLocal($Statement.VariableName, [double]$n)
                Invoke-OtterStatements -Statements $Statement.Body -Environment $Environment
            }
            return
        }

        # for each game in games
        'ForEach' {
            $collection = Get-OtterValue -Expression $Statement.Collection -Environment $Environment
            if (-not (Test-OtterList $collection)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only go through a list, but this is $(Get-OtterTypeName $collection)." `
                    -Line $Statement.Line)
            }
            # Copy first: the body may add to the list while we walk it.
            # .ToArray(), not @($collection) - the array subexpression operator
            # throws "Argument types do not match" on a generic List in PS 5.1.
            $snapshot = $collection.ToArray()
            foreach ($item in $snapshot) {
                $Environment.SetLocal($Statement.VariableName, $item)
                Invoke-OtterStatements -Statements $Statement.Body -Environment $Environment
            }
            return
        }

        # games are / games are empty      (D13)
        'ListDef' {
            $values = @()
            foreach ($item in $Statement.Items) {
                $values += (Get-OtterValue -Expression $item -Environment $Environment)
            }
            $Environment.Set($Statement.Name, (New-OtterList -Items $values))
            return
        }

        # to greet name
        'FunctionDef' {
            $function = [OtterFunction]::new($Statement.Name, $Statement.Parameters, $Statement.Body)
            $Environment.Set($Statement.Name, $function)
            return
        }

        # greet "Jeff"      /      double 5 make result
        'CallStatement' {
            $result = Invoke-OtterCall -Call $Statement.Call -Environment $Environment
            if ($Statement.ResultTarget) {
                $Environment.Set($Statement.ResultTarget, $result)
            }
            return
        }

        # return answer
        'Return' {
            $value = $null
            if ($null -ne $Statement.Value) {
                $value = Get-OtterValue -Expression $Statement.Value -Environment $Environment
            }
            throw [OtterReturnSignal]::new($value)
        }

        # --- runtime library (milestone 7) ----------------------
        #
        # Each of these is one readable Otter line on the outside and a pile
        # of platform detail on the inside, all of which lives in
        # src/Otter.Library.psm1 rather than here.

        # read "notes.txt" into notes
        'ReadFile' {
            $path = Get-OtterText -Expression $Statement.Path -Environment $Environment
            $Environment.Set($Statement.Target, (Read-OtterFile -Path $path -Line $Statement.Line))
            return
        }

        # write "Hello!" to "hello.txt"
        'WriteFile' {
            $content = Get-OtterText -Expression $Statement.Content -Environment $Environment
            $path = Get-OtterText -Expression $Statement.Path -Environment $Environment
            Write-OtterFile -Path $path -Content $content -Line $Statement.Line
            return
        }

        # copy "hello.txt" to "backup/hello.txt"
        'CopyFile' {
            $source = Get-OtterText -Expression $Statement.Source -Environment $Environment
            $destination = Get-OtterText -Expression $Statement.Destination -Environment $Environment
            Copy-OtterFile -Source $source -Destination $destination -Line $Statement.Line
            return
        }

        # move "hello.txt" to "Documents"
        'MoveFile' {
            $source = Get-OtterText -Expression $Statement.Source -Environment $Environment
            $destination = Get-OtterText -Expression $Statement.Destination -Environment $Environment
            Move-OtterFile -Source $source -Destination $destination -Line $Statement.Line
            return
        }

        # delete file "hello.txt"
        'DeleteFile' {
            $path = Get-OtterText -Expression $Statement.Path -Environment $Environment
            Remove-OtterFile -Path $path -Line $Statement.Line
            return
        }

        # run "notepad.exe"  /  run command "git status" into result
        'RunProgram' {
            $target = Get-OtterText -Expression $Statement.Target -Environment $Environment

            if (-not $Statement.IsCommand) {
                Start-OtterProgram -Target $target -Line $Statement.Line
                return
            }

            $output = Invoke-OtterCommand -CommandLine $target -Line $Statement.Line
            if ($Statement.ResultTarget) {
                $Environment.Set($Statement.ResultTarget, $output)
            }
            return
        }

        default {
            throw (New-OtterRuntimeError `
                -Message "I do not know how to run a $($Statement.Kind) statement yet." `
                -Line $Statement.Line)
        }
    }
}


# --- add / remove dispatch on runtime type (D12) -----------------
#
# The parser cannot tell "add 5 to score" from "add 'Pokemon' to games" -
# both are AddToStmt. Only the interpreter knows what the target holds.

function Invoke-OtterAddTo {
    param([Node]$Statement, [OtterEnvironment]$Environment)

    $name = $Statement.Target
    if (-not $Environment.Has($name)) {
        throw (New-OtterRuntimeError `
            -Message "Otter could not find the variable `"$name`"." `
            -Line $Statement.Line `
            -Suggestion "$name is 0")
    }

    $current = $Environment.Get($name)
    $amount = Get-OtterValue -Expression $Statement.Amount -Environment $Environment

    if (Test-OtterList $current) {
        $current.Add($amount)
        return
    }

    if (Test-OtterNumeric $current) {
        $addend = Assert-OtterNumber -Value $amount -Line $Statement.Line -What "the amount to add to `"$name`""
        $Environment.Set($name, (ConvertTo-OtterNumber $current) + $addend)
        return
    }

    throw (New-OtterRuntimeError `
        -Message "I can only add to a number or a list, but `"$name`" holds $(Get-OtterTypeName $current)." `
        -Line $Statement.Line)
}

function Invoke-OtterRemoveFrom {
    param([Node]$Statement, [OtterEnvironment]$Environment)

    $name = $Statement.Target
    if (-not $Environment.Has($name)) {
        throw (New-OtterRuntimeError `
            -Message "Otter could not find the variable `"$name`"." `
            -Line $Statement.Line)
    }

    $current = $Environment.Get($name)
    $amount = Get-OtterValue -Expression $Statement.Amount -Environment $Environment

    if (Test-OtterList $current) {
        for ($i = 0; $i -lt $current.Count; $i++) {
            if (Test-OtterEqual -Left $current[$i] -Right $amount) {
                $current.RemoveAt($i)
                return
            }
        }
        # Removing something absent is not an error - the list simply lacks it.
        return
    }

    if (Test-OtterNumeric $current) {
        $subtrahend = Assert-OtterNumber -Value $amount -Line $Statement.Line -What "the amount to remove from `"$name`""
        $Environment.Set($name, (ConvertTo-OtterNumber $current) - $subtrahend)
        return
    }

    throw (New-OtterRuntimeError `
        -Message "I can only remove from a number or a list, but `"$name`" holds $(Get-OtterTypeName $current)." `
        -Line $Statement.Line)
}


# ===============================================================
# EXPRESSIONS
# ===============================================================

function Get-OtterValue {
    param([Node]$Expression, [OtterEnvironment]$Environment)

    switch ($Expression.Kind.ToString()) {

        'Literal' { return $Expression.Value }

        'Variable' {
            $name = $Expression.Name
            if (-not $Environment.Has($name)) {
                throw (New-OtterRuntimeError `
                    -Message "Otter could not find the variable `"$name`". It has not been given a value yet." `
                    -Line $Expression.Line `
                    -Suggestion "$name is 0")
            }
            # -NoEnumerate matters: a PowerShell function RETURNING a List
            # unrolls it into separate pipeline items, so an Otter list would
            # arrive at the caller as a loose object[] and stop being a list.
            Write-Output -NoEnumerate ($Environment.Get($name))
            return
        }

        # 5 and 5   /   10 minus 5   /   10 times 5   /   10 divided by 5
        'Math' {
            $leftRaw = Get-OtterValue -Expression $Expression.Left -Environment $Environment
            $rightRaw = Get-OtterValue -Expression $Expression.Right -Environment $Environment
            $left = Assert-OtterNumber -Value $leftRaw -Line $Expression.Line -What 'the left side of this calculation'
            $right = Assert-OtterNumber -Value $rightRaw -Line $Expression.Line -What 'the right side of this calculation'

            switch ($Expression.Op.ToString()) {
                'Add' { return $left + $right }
                'Subtract' { return $left - $right }
                'Multiply' { return $left * $right }
                'Divide' {
                    if ($right -eq 0) {
                        throw (New-OtterRuntimeError `
                            -Message 'I cannot divide by zero.' `
                            -Line $Expression.Line)
                    }
                    return $left / $right
                }
            }
            return $null
        }

        # age is at least 18
        'Comparison' {
            $left = Get-OtterValue -Expression $Expression.Left -Environment $Environment
            $right = Get-OtterValue -Expression $Expression.Right -Environment $Environment

            switch ($Expression.Op.ToString()) {
                'Equal' { return (Test-OtterEqual -Left $left -Right $right) }
                'NotEqual' { return (-not (Test-OtterEqual -Left $left -Right $right)) }
            }

            # The four ordering comparisons need real numbers on both sides.
            $l = Assert-OtterNumber -Value $left -Line $Expression.Line -What 'the left side of this comparison'
            $r = Assert-OtterNumber -Value $right -Line $Expression.Line -What 'the right side of this comparison'

            switch ($Expression.Op.ToString()) {
                'AtLeast' { return ($l -ge $r) }
                'AtMost' { return ($l -le $r) }
                'GreaterThan' { return ($l -gt $r) }
                'LessThan' { return ($l -lt $r) }
            }
            return $false
        }

        # if loggedIn and admin   /   if admin or moderator      (D11)
        # Both short-circuit, so "if false and boom" never evaluates boom.
        'Logical' {
            $left = Get-OtterValue -Expression $Expression.Left -Environment $Environment
            $leftTruthy = Test-OtterTruthy -Value $left

            if ($Expression.Op.ToString() -eq 'And') {
                if (-not $leftTruthy) { return $false }
                $right = Get-OtterValue -Expression $Expression.Right -Environment $Environment
                return (Test-OtterTruthy -Value $right)
            }

            if ($leftTruthy) { return $true }
            $right = Get-OtterValue -Expression $Expression.Right -Environment $Environment
            return (Test-OtterTruthy -Value $right)
        }

        # if not loggedIn        (D11)
        'Not' {
            $value = Get-OtterValue -Expression $Expression.Operand -Environment $Environment
            return (-not (Test-OtterTruthy -Value $value))
        }

        # if games contains "Zelda"      (D13)
        'Contains' {
            $collection = Get-OtterValue -Expression $Expression.Collection -Environment $Environment
            $item = Get-OtterValue -Expression $Expression.Item -Environment $Environment

            if (-not (Test-OtterList $collection)) {
                throw (New-OtterRuntimeError `
                    -Message "Only a list can contain something, but this is $(Get-OtterTypeName $collection)." `
                    -Line $Expression.Line)
            }
            foreach ($entry in $collection) {
                if (Test-OtterEqual -Left $entry -Right $item) { return $true }
            }
            return $false
        }

        'Call' {
            # -NoEnumerate for the same reason: a function may return a list.
            Write-Output -NoEnumerate (Invoke-OtterCall -Call $Expression -Environment $Environment)
            return
        }

        'MemberAccess' {
            throw (New-OtterRuntimeError `
                -Message 'Objects are not part of this version of Otter yet.' `
                -Line $Expression.Line)
        }

        # if file "hello.txt" exists
        'FileExists' {
            $path = Get-OtterText -Expression $Expression.Path -Environment $Environment
            return (Test-OtterFileExists -Path $path -Line $Expression.Line)
        }

        default {
            throw (New-OtterRuntimeError `
                -Message "I do not know how to work out a $($Expression.Kind) value yet." `
                -Line $Expression.Line)
        }
    }
}


# ===============================================================
# CALLING A FUNCTION
# ===============================================================
#
# A call gets a brand new scope whose parent is the GLOBAL scope - never the
# caller's scope. That is what makes this print "Outside" at the end:
#
#     name is "Outside"
#     to greet name
#         say "Hello" name
#     greet "Jeff"
#     say name

function Invoke-OtterCall {
    param([CallExpr]$Call, [OtterEnvironment]$Environment)

    $name = $Call.Name

    if (-not $Environment.Has($name)) {
        throw (New-OtterRuntimeError `
            -Message "Otter could not find anything called `"$name`"." `
            -Line $Call.Line `
            -Suggestion "to $name")
    }

    $target = $Environment.Get($name)
    if ($target -isnot [OtterFunction]) {
        throw (New-OtterRuntimeError `
            -Message "`"$name`" is not something Otter can do - it holds $(Get-OtterTypeName $target)." `
            -Line $Call.Line)
    }

    $expected = $target.Parameters.Count
    $given = $Call.Arguments.Count
    if ($given -ne $expected) {
        $wordExpected = if ($expected -eq 1) { 'value' } else { 'values' }
        throw (New-OtterRuntimeError `
            -Message "`"$name`" needs $expected $wordExpected but was given $given." `
            -Line $Call.Line `
            -Suggestion "$name $($target.Parameters -join ' ')")
    }

    # Arguments are worked out in the CALLER's scope, before the new one exists.
    $arguments = @()
    foreach ($argument in $Call.Arguments) {
        $arguments += (Get-OtterValue -Expression $argument -Environment $Environment)
    }

    $local = [OtterEnvironment]::new($script:GlobalEnvironment)
    for ($i = 0; $i -lt $expected; $i++) {
        # SetLocal, not Set: a parameter always shadows an outer variable of the
        # same name rather than overwriting it.
        $local.SetLocal($target.Parameters[$i], $arguments[$i])
    }

    try {
        Invoke-OtterStatements -Statements $target.Body -Environment $local
    }
    catch {
        # "return" is control flow wearing an exception's clothes.
        if ($_.Exception -is [OtterReturnSignal]) {
            Write-Output -NoEnumerate $_.Exception.Value
            return
        }
        throw
    }

    # A function that never returns anything produces nothing.
    return $null
}


# ===============================================================
# HELPERS
# ===============================================================

# File names and commands are text. Evaluating them through Format-OtterValue
# means a path can be built from variables and still arrive as a plain string:
#
#     name is "notes"
#     read name into contents      <- would read the file named "notes"
function Get-OtterText {
    param([Node]$Expression, [OtterEnvironment]$Environment)
    $value = Get-OtterValue -Expression $Expression -Environment $Environment
    return (Format-OtterValue -Value $value)
}

# Type names as a beginner would say them, for error messages.
function Get-OtterTypeName {
    param([object]$Value)

    if ($null -eq $Value) { return 'nothing' }
    if ($Value -is [bool]) { return 'a true or false value' }
    if ($Value -is [OtterFunction]) { return 'something Otter can do' }
    if (Test-OtterList $Value) { return 'a list' }
    if ($Value -is [double] -or $Value -is [int] -or $Value -is [long]) { return 'a number' }
    if ($Value -is [string]) { return 'some text' }
    return 'a value Otter does not recognise'
}

function New-OtterEnvironment {
    return [OtterEnvironment]::new()
}


Export-ModuleMember -Function `
    Invoke-OtterProgram, Invoke-OtterStatements, Invoke-OtterStatement, `
    Get-OtterValue, Invoke-OtterCall, New-OtterEnvironment, Get-OtterTypeName, `
    Set-OtterOutputWriter, Write-OtterLine, Get-OtterText
