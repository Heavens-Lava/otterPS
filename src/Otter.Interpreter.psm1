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

        # name is "Jeff"              target is a VariableExpr
        # age of person is 30         target is a PropertyAccessExpr
        'Assign' {
            $value = Get-OtterValue -Expression $Statement.Value -Environment $Environment
            Set-OtterTarget -Target $Statement.Target -Value $value -Environment $Environment
            return
        }

        # person is a thing
        #     name is "Jeff"
        # .
        'ObjectDef' {
            $object = New-OtterObjectValue -Statement $Statement -Environment $Environment
            $Environment.Set($Statement.Name, $object)
            return
        }

        # a Person has
        #     name
        # .
        'TypeDef' {
            $Environment.Set($Statement.TypeName, [OtterType]::new($Statement.TypeName, $Statement.FieldNames))
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
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            $Environment.Set($Statement.Target, (Read-OtterFile -Path $path -Line $Statement.Line))
            return
        }

        # write "Hello!" to "hello.txt"
        'WriteFile' {
            $content = Get-OtterText -Expression $Statement.Content -Environment $Environment
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            Write-OtterFile -Path $path -Content $content -Line $Statement.Line
            return
        }

        # copy "hello.txt" to "backup/hello.txt"
        'CopyFile' {
            $source = Get-OtterPathArgument -Expression $Statement.Source -Environment $Environment
            $destination = Get-OtterPathArgument -Expression $Statement.Destination -Environment $Environment
            Copy-OtterFile -Source $source -Destination $destination -Line $Statement.Line
            return
        }

        # move "hello.txt" to "Documents"
        'MoveFile' {
            $source = Get-OtterPathArgument -Expression $Statement.Source -Environment $Environment
            $destination = Get-OtterPathArgument -Expression $Statement.Destination -Environment $Environment
            Move-OtterFile -Source $source -Destination $destination -Line $Statement.Line
            return
        }

        # delete file "hello.txt"
        'DeleteFile' {
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
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

        # --- discovery and folders (D20, D21) -------------------

        # get files in "Pictures" [and subfolders] into files
        'GetFiles' {
            $folder = Get-OtterPathArgument -Expression $Statement.Folder -Environment $Environment
            $files = Get-OtterFilesIn -Path $folder -IncludeSubfolders $Statement.IncludeSubfolders -Line $Statement.Line
            $Environment.Set($Statement.Target, $files)
            return
        }

        # get folders in "Documents" [and subfolders] into folders
        'GetFolders' {
            $folder = Get-OtterPathArgument -Expression $Statement.Folder -Environment $Environment
            $folders = Get-OtterFoldersIn -Path $folder -IncludeSubfolders $Statement.IncludeSubfolders -Line $Statement.Line
            $Environment.Set($Statement.Target, $folders)
            return
        }

        'CreateFolder' {
            New-OtterFolder -Path (Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment) -Line $Statement.Line
            return
        }

        'DeleteFolder' {
            Remove-OtterFolder -Path (Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment) -Line $Statement.Line
            return
        }

        'CopyFolder' {
            $source = Get-OtterPathArgument -Expression $Statement.Source -Environment $Environment
            $destination = Get-OtterPathArgument -Expression $Statement.Destination -Environment $Environment
            Copy-OtterFolder -Source $source -Destination $destination -Line $Statement.Line
            return
        }

        'MoveFolder' {
            $source = Get-OtterPathArgument -Expression $Statement.Source -Environment $Environment
            $destination = Get-OtterPathArgument -Expression $Statement.Destination -Environment $Environment
            Move-OtterFolder -Source $source -Destination $destination -Line $Statement.Line
            return
        }

        # --- try / otherwise (D23) ------------------------------
        #
        #     try
        #         read "settings.json" into settings
        #     otherwise
        #         say "Could not load settings."
        #     .
        'Try' {
            try {
                Invoke-OtterStatements -Statements $Statement.Body -Environment $Environment
            }
            catch {
                # "return" is control flow wearing an exception, not a failure.
                # It must pass straight through a try, or returning from inside
                # one would silently run the otherwise body instead.
                if ($_.Exception -is [OtterReturnSignal]) { throw }

                if ($null -ne $Statement.OtherwiseBody) {
                    Invoke-OtterStatements -Statements $Statement.OtherwiseBody -Environment $Environment
                }
            }
            return
        }

        # --- collections and strings (D25) ----------------------

        # sort games   /   reverse games   - change the list in place
        'Sort' {
            $list = Get-OtterMutableList -Name $Statement.Target -Environment $Environment -Line $Statement.Line -Verb 'sort'
            $items = $list.ToArray()
            $comparison = [System.Comparison[object]] {
                param($left, $right)
                if ((Test-OtterNumeric $left) -and (Test-OtterNumeric $right)) {
                    $l = [double](ConvertTo-OtterNumber $left)
                    $r = [double](ConvertTo-OtterNumber $right)
                    return $l.CompareTo($r)
                }
                return [string]::CompareOrdinal(
                    (Format-OtterValue -Value $left),
                    (Format-OtterValue -Value $right))
            }
            [System.Array]::Sort($items, $comparison)
            $list.Clear()
            foreach ($item in $items) { $list.Add($item) }
            return
        }

        'Reverse' {
            $list = Get-OtterMutableList -Name $Statement.Target -Environment $Environment -Line $Statement.Line -Verb 'reverse'
            $list.Reverse()
            return
        }

        # replace "Jeff" with "Jeffrey" in name
        'Replace' {
            if (-not $Environment.Has($Statement.Target)) {
                throw (New-OtterRuntimeError -Message "Otter could not find the variable ""$($Statement.Target)""." -Line $Statement.Line)
            }
            $subject = Format-OtterValue -Value $Environment.Get($Statement.Target)
            $find = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Find -Environment $Environment)
            $replacement = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Replacement -Environment $Environment)

            if ($find.Length -eq 0) {
                throw (New-OtterRuntimeError -Message 'I cannot replace empty text.' -Line $Statement.Line)
            }
            # Plain text replace - no regular expressions, so "." in the text
            # the programmer typed means a full stop and nothing else.
            $Environment.Set($Statement.Target, $subject.Replace($find, $replacement))
            return
        }

        # split sentence by " " into words
        'Split' {
            $subject = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Subject -Environment $Environment)
            $separator = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Separator -Environment $Environment)

            if ($separator.Length -eq 0) {
                throw (New-OtterRuntimeError -Message 'I need something to split by.' -Line $Statement.Line)
            }
            $pieces = $subject.Split([string[]]@($separator), [System.StringSplitOptions]::None)
            $Environment.Set($Statement.Target, (New-OtterList -Items $pieces))
            return
        }

        # join words with ", " into text
        'Join' {
            $value = Get-OtterValue -Expression $Statement.Subject -Environment $Environment
            if (-not (Test-OtterList $value)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only join a list, but this is $(Get-OtterTypeName $value)." `
                    -Line $Statement.Line)
            }
            $separator = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Separator -Environment $Environment)
            $rendered = foreach ($item in $value) { Format-OtterValue -Value $item }
            $Environment.Set($Statement.Target, (($rendered) -join $separator))
            return
        }

        # find file in files where extension of file is ".pdf" into result
        #
        # D26: singular "find" gives the FIRST match, or gone. That is what
        # makes "if result is gone" the natural way to ask if anything matched.
        'Find' {
            $collection = Get-OtterValue -Expression $Statement.Collection -Environment $Environment
            if (-not (Test-OtterList $collection)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only search a list, but this is $(Get-OtterTypeName $collection)." `
                    -Line $Statement.Line)
            }

            $found = $null
            foreach ($item in $collection.ToArray()) {
                # The item name is bound for the condition only, exactly like
                # a for-each variable.
                $scope = [OtterEnvironment]::new($Environment)
                $scope.SetLocal($Statement.ItemName, $item)
                if (Test-OtterTruthy -Value (Get-OtterValue -Expression $Statement.Condition -Environment $scope)) {
                    $found = $item
                    break
                }
            }

            $Environment.Set($Statement.Target, $found)
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

            # "contains" reads the same way for text as for a list:
            #     if name contains "Jeff"
            #     if games contains "Zelda"
            if ($collection -is [string]) {
                return $collection.Contains((Format-OtterValue -Value $item))
            }

            if (-not (Test-OtterList $collection)) {
                throw (New-OtterRuntimeError `
                    -Message "Only text or a list can contain something, but this is $(Get-OtterTypeName $collection)." `
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

        # name of person   /   city of address of user
        'PropertyAccess' {
            $target = Get-OtterValue -Expression $Expression.Target -Environment $Environment

            if (-not (Test-OtterObject $target)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only read properties of a thing, but this is $(Get-OtterTypeName $target)." `
                    -Line $Expression.Line)
            }

            if (-not $target.HasProperty($Expression.Property)) {
                $known = $target.PropertyNames()
                $suggestion = $null
                if ($known.Count -gt 0) { $suggestion = "$($known[0]) of ..." }
                throw (New-OtterRuntimeError `
                    -Message "This $($target.TypeName) has no property called `"$($Expression.Property)`"." `
                    -Line $Expression.Line `
                    -Suggestion $suggestion)
            }

            Write-Output -NoEnumerate ($target.ReadProperty($Expression.Property))
            return
        }

        # if file "hello.txt" exists
        'FileExists' {
            $path = Get-OtterPathArgument -Expression $Expression.Path -Environment $Environment
            return (Test-OtterFileExists -Path $path -Line $Expression.Line)
        }

        # length of name / length of games / uppercase of name /
        # first of games / last of games                        (D24)
        'OfOperation' {
            $subject = Get-OtterValue -Expression $Expression.Subject -Environment $Environment

            switch ($Expression.Operation.ToString()) {

                'Length' {
                    if (Test-OtterList $subject) { return [double]$subject.Count }
                    if ($subject -is [string]) { return [double]$subject.Length }
                    throw (New-OtterRuntimeError `
                        -Message "I can only measure the length of text or a list, but this is $(Get-OtterTypeName $subject)." `
                        -Line $Expression.Line)
                }

                'Uppercase' { return (Format-OtterValue -Value $subject).ToUpperInvariant() }
                'Lowercase' { return (Format-OtterValue -Value $subject).ToLowerInvariant() }

                # first/last of an empty list is gone, not an error. D22 is
                # exactly what makes "if first of games is gone" askable.
                'First' {
                    if (-not (Test-OtterList $subject)) {
                        throw (New-OtterRuntimeError `
                            -Message "Only a list has a first item, but this is $(Get-OtterTypeName $subject)." `
                            -Line $Expression.Line)
                    }
                    if ($subject.Count -eq 0) { return $null }
                    Write-Output -NoEnumerate $subject[0]
                    return
                }

                'Last' {
                    if (-not (Test-OtterList $subject)) {
                        throw (New-OtterRuntimeError `
                            -Message "Only a list has a last item, but this is $(Get-OtterTypeName $subject)." `
                            -Line $Expression.Line)
                    }
                    if ($subject.Count -eq 0) { return $null }
                    Write-Output -NoEnumerate $subject[$subject.Count - 1]
                    return
                }
            }
            return $null
        }

        # if name starts with "J"   /   if name ends with "Macy"
        'TextMatch' {
            $subject = Format-OtterValue -Value (Get-OtterValue -Expression $Expression.Subject -Environment $Environment)
            $value = Format-OtterValue -Value (Get-OtterValue -Expression $Expression.Value -Environment $Environment)

            if ($Expression.Match.ToString() -eq 'StartsWith') {
                return $subject.StartsWith($value, [System.StringComparison]::Ordinal)
            }
            return $subject.EndsWith($value, [System.StringComparison]::Ordinal)
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

# ===============================================================
# ASSIGNMENT TARGETS
# ===============================================================
#
# D19: anything assignable is an expression node, so adding list indexing
# later means adding a case here, not a second kind of statement.

function Set-OtterTarget {
    param([Node]$Target, [object]$Value, [OtterEnvironment]$Environment)

    switch ($Target.Kind.ToString()) {

        'Variable' {
            $Environment.Set($Target.Name, $Value)
            return
        }

        # age of person is 30
        'PropertyAccess' {
            $owner = Get-OtterValue -Expression $Target.Target -Environment $Environment

            if (-not (Test-OtterObject $owner)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only set properties on a thing, but this is $(Get-OtterTypeName $owner)." `
                    -Line $Target.Line)
            }

            $owner.WriteProperty($Target.Property, $Value)
            return
        }

        default {
            throw (New-OtterRuntimeError `
                -Message 'This is not something Otter can give a value to.' `
                -Line $Target.Line)
        }
    }
}

# Builds the object for "person is a thing" and its indented property lines.
#
# A named custom type - "jeff is a Person" - starts with that type's fields
# already present but empty, so "name of jeff" reads as nothing rather than
# failing.
function New-OtterObjectValue {
    param([Node]$Statement, [OtterEnvironment]$Environment)

    $object = [OtterObject]::new($Statement.TypeName)

    if ($Statement.TypeName -ne 'thing' -and $Environment.Has($Statement.TypeName)) {
        $declared = $Environment.Get($Statement.TypeName)
        if ($declared -is [OtterType]) {
            foreach ($field in $declared.FieldNames) { $object.WriteProperty($field, $null) }
        }
    }

    foreach ($property in $Statement.Properties) {
        if ($property.Kind -ne [NodeKind]::Assign) {
            throw (New-OtterRuntimeError `
                -Message 'Only properties belong inside a thing.' `
                -Line $property.Line)
        }
        if ($property.Target.Kind -ne [NodeKind]::Variable) {
            throw (New-OtterRuntimeError `
                -Message 'A property name inside a thing must be a plain name.' `
                -Line $property.Line)
        }
        $value = Get-OtterValue -Expression $property.Value -Environment $Environment
        $object.WriteProperty($property.Target.Name, $value)
    }

    return $object
}

# sort and reverse change a list where it stands, so they need the real list
# object out of the environment rather than a copy of it.
function Get-OtterMutableList {
    param([string]$Name, [OtterEnvironment]$Environment, [int]$Line, [string]$Verb)

    if (-not $Environment.Has($Name)) {
        throw (New-OtterRuntimeError -Message "Otter could not find the variable ""$Name""." -Line $Line)
    }

    $value = $Environment.Get($Name)
    if (-not (Test-OtterList $value)) {
        throw (New-OtterRuntimeError `
            -Message "I can only $Verb a list, but ""$Name"" holds $(Get-OtterTypeName $value)." `
            -Line $Line)
    }

    # -NoEnumerate again: returning a List from a PowerShell function unrolls
    # it, so the caller would get the first ITEM instead of the list itself.
    Write-Output -NoEnumerate $value
}

# File operations accept a path the programmer typed OR a file object with a
# path property, because rules.md passes both:
#
#     move "hello.txt" to "Documents"     <- text
#     move file to "Pictures"             <- a file object
function Get-OtterPathArgument {
    param([Node]$Expression, [OtterEnvironment]$Environment)
    $value = Get-OtterValue -Expression $Expression -Environment $Environment
    return (Resolve-OtterFileArgument -Value $value -Line $Expression.Line)
}

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

    if ($null -eq $Value) { return 'gone' }
    if ($Value -is [bool]) { return 'a true or false value' }
    if ($Value -is [OtterFunction]) { return 'something Otter can do' }
    if (Test-OtterObject $Value) { return "a $($Value.TypeName)" }
    if ($Value -is [OtterType]) { return "the type $($Value.Name)" }
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
    Set-OtterOutputWriter, Write-OtterLine, Get-OtterText, Get-OtterPathArgument, Set-OtterTarget
