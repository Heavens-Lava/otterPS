using module ..\Otter.Contract.psm1
using module .\Otter.Runtime.psm1
using module .\Otter.Library.psm1
using module .\Otter.UI.psm1

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

# D31: log / warn / error are DIAGNOSTIC output and go somewhere separate
# from "say". "say" is what a program tells its user; these are what it tells
# whoever is running it. Keeping them apart is what lets a runtime send
# diagnostics to a file, a service, or nowhere at all.
$script:DiagnosticWriter = $null

function Set-OtterDiagnosticWriter {
    param([scriptblock]$Writer)
    $script:DiagnosticWriter = $Writer
}

function Write-OtterDiagnostic {
    param([string]$Level, [string]$Text)

    if ($null -ne $script:DiagnosticWriter) {
        & $script:DiagnosticWriter $Level $Text
        return
    }

    $colour = switch ($Level) {
        'warn' { 'Yellow' }
        'error' { 'Red' }
        default { 'DarkGray' }
    }
    Write-Host "$($Level): $Text" -ForegroundColor $colour
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

# D41: dynamic get/set are restricted to TypeName 'thing'. The probe that
# motivated this found the reason directly - WriteProperty does not
# distinguish thing from file from folder, so without this guard
# `set "size" to 999999 in file` would silently corrupt a file object's
# own bookkeeping. has (D40) and JSON (D29) are both always 'thing',
# so this costs the intended use of the feature nothing.
function Assert-OtterDynamicKeyTarget {
    param([object]$Value, [int]$Line, [string]$Verb)

    if (-not (Test-OtterObject $Value)) {
        throw (New-OtterRuntimeError `
            -Message "I can only $Verb a thing, but this is $(Get-OtterTypeName $Value)." `
            -Line $Line)
    }
    if ($Value.TypeName -ne 'thing') {
        throw (New-OtterRuntimeError `
            -Message "I can only $Verb properties dynamically on a thing, but this is a $($Value.TypeName)." `
            -Line $Line)
    }
    return $Value
}

# D41: string-only keys for 0.1, on purpose - accepting any value would
# mean quietly inventing coercion rules for numbers, dates, booleans, and
# gone, which is exactly the kind of decision this project makes on
# purpose rather than by accident.
function Assert-OtterStringKey {
    param([object]$Value, [int]$Line)

    if ($Value -is [string]) { return $Value }

    throw (New-OtterRuntimeError `
        -Message "I need text for a dynamic key, but this is $(Get-OtterTypeName $Value)." `
        -Line $Line `
        -Suggestion 'get "Jeff" from scores into score')
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

    try {
        Invoke-OtterStatements -Statements $Program.Statements -Environment $Environment
    }
    catch {
        # D37: "stop" (and a hypothetical top-level "return") both throw an
        # OtterReturnSignal. Invoke-OtterCall is the only thing that ever
        # catches that signal, and it only exists while a function call is
        # running - so one reaching all the way up here means it was used
        # outside anything callable. Without this catch it would unwind past
        # this function entirely and get reported as "a bug in Otter",
        # which is wrong: nothing broke, the program just used "stop" where
        # there was nothing to stop.
        if ($_.Exception -is [OtterReturnSignal]) {
            throw (New-OtterRuntimeError `
                -Message 'stop only works inside something Otter can call, like a function. There is nothing here to stop.' `
                -Line $_.Exception.Line)
        }
        throw
    }
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
            if ($Environment.Has($Statement.Name)) {
                $existing = $Environment.Get($Statement.Name)
                if (Test-OtterUiResource $existing) {
                    foreach ($property in $Statement.Properties) {
                        if ($property.Target.Kind -ne [NodeKind]::Variable) {
                            throw (New-OtterRuntimeError -Message 'A UI resource property name must be a plain name.' -Line $property.Line)
                        }
                        $value = Get-OtterValue -Expression $property.Value -Environment $Environment
                        Set-OtterUiProperty -Resource $existing -Property $property.Target.Name -Value $value -Line $property.Line
                    }
                    return
                }
                throw (New-OtterRuntimeError -Message "Otter will not replace existing $((Get-OtterTypeName $existing)) called `"$($Statement.Name)`" with a new thing." -Line $Statement.Line -Suggestion 'Use a new name, or assign individual properties instead.')
            }
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

        # create button into helloButton                              (D44)
        #
        # The real, provider-backed resource is created RIGHT NOW - this is
        # the lifecycle decision D44 froze. Nothing here is a description
        # waiting to be materialized later.
        'CreateUiResource' {
            $resource = New-OtterUiResourceValue -Kind $Statement.TypeName -Line $Statement.Line
            $Environment.Set($Statement.Target, $resource)
            return
        }

        # when helloButton is clicked                            (D46)
        #     say "Hello"
        # .
        #
        # Registration only. The handler closes over $Environment as it
        # exists right here - the same environment If/While bodies already
        # run in, not a function call's fresh child scope (frozen as part
        # of D46). Whether/when this handler is ever actually invoked in a
        # running program depends on a message loop, which is D47's job,
        # not this statement's - registering a handler here does not by
        # itself make anything happen.
        'When' {
            $target = Get-OtterValue -Expression $Statement.Target -Environment $Environment
            if (-not (Test-OtterUiResource $target)) {
                $shown = Get-OtterTypeName -Value $target
                throw (New-OtterRuntimeError `
                    -Message "I can only listen for an event on a UI resource, but this is $shown." `
                    -Line $Statement.Line)
            }

            $body = $Statement.Body
            $handler = { Invoke-OtterStatements -Statements $body -Environment $Environment }.GetNewClosure()
            Add-OtterUiEventHandler -Resource $target -EventName $Statement.EventName -Handler $handler -Line $Statement.Line
            return
        }

        # put helloButton in app                                  (D47)
        'PutIn' {
            $item = Get-OtterValue -Expression $Statement.Item -Environment $Environment
            if (-not (Test-OtterUiResource $item)) {
                $shown = Get-OtterTypeName -Value $item
                throw (New-OtterRuntimeError `
                    -Message "I can only put a UI resource somewhere, but this is $shown." `
                    -Line $Statement.Line)
            }

            $container = Get-OtterValue -Expression $Statement.Container -Environment $Environment
            if (-not (Test-OtterUiResource $container)) {
                $shown = Get-OtterTypeName -Value $container
                throw (New-OtterRuntimeError `
                    -Message "I can only put something in a UI resource, but this is $shown." `
                    -Line $Statement.Line)
            }

            Add-OtterUiChild -Container $container -Item $item -Line $Statement.Line
            return
        }

        # show app                                                (D47)
        'Show' {
            $target = Get-OtterValue -Expression $Statement.Target -Environment $Environment
            if (-not (Test-OtterUiResource $target)) {
                $shown = Get-OtterTypeName -Value $target
                throw (New-OtterRuntimeError `
                    -Message "I can only show a UI resource, but this is $shown." `
                    -Line $Statement.Line)
            }

            Show-OtterUiResource -Resource $target -Line $Statement.Line
            return
        }

        # get "Jeff" from scores into score      (D41 - missing key is gone, not an error)
        'GetKey' {
            $target = Get-OtterValue -Expression $Statement.Target -Environment $Environment
            $key = Assert-OtterDynamicKeyTarget -Value $target -Line $Statement.Line -Verb 'read from'

            $rawKey = Get-OtterValue -Expression $Statement.Key -Environment $Environment
            $keyText = Assert-OtterStringKey -Value $rawKey -Line $Statement.Line

            # ReadProperty already returns $null for a key that was never
            # set - that IS gone (D22). No HasProperty guard here on
            # purpose: that guard is what makes "name of person" an error
            # on a missing property, and this statement is deliberately not
            # that one.
            $Environment.Set($Statement.ResultTarget, $key.ReadProperty($keyText))
            return
        }

        # set "Jeff" to 100 in scores      (D41 - creates or replaces)
        'SetKey' {
            $target = Get-OtterValue -Expression $Statement.Target -Environment $Environment
            $key = Assert-OtterDynamicKeyTarget -Value $target -Line $Statement.Line -Verb 'write to'

            $rawKey = Get-OtterValue -Expression $Statement.Key -Environment $Environment
            $keyText = Assert-OtterStringKey -Value $rawKey -Line $Statement.Line

            $value = Get-OtterValue -Expression $Statement.Value -Environment $Environment
            # WriteProperty already creates-or-replaces - nothing extra needed.
            $key.WriteProperty($keyText, $value)
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
            throw [OtterReturnSignal]::new($value, $Statement.Line)
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
            Write-OtterFile -Path $path -Content $content -Line $Statement.Line -Atomic $Statement.Atomic
            return
        }

        # append "line one" to "log.txt"                            (D61)
        'AppendFile' {
            $content = Get-OtterText -Expression $Statement.Content -Environment $Environment
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            Add-OtterFileContent -Path $path -Content $content -Line $Statement.Line
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
                # D70: `into p` used to be silently dropped here - it parsed
                # fine (RunStmt.ResultTarget was always populated by the
                # parser) but this branch returned before ever setting it,
                # leaving `p` undefined. Start-OtterProgram now hands back a
                # real process handle (id, name) for kill/details later.
                $handle = Start-OtterProgram -Target $target -Line $Statement.Line
                if ($Statement.ResultTarget) {
                    $Environment.Set($Statement.ResultTarget, $handle)
                }
                return
            }

            $output = Invoke-OtterCommand -CommandLine $target -Line $Statement.Line
            if ($Statement.ResultTarget) {
                $Environment.Set($Statement.ResultTarget, $output)
            }
            return
        }

        # get processes into list                                        (D70)
        'GetProcesses' {
            $list = Get-OtterProcessList
            $Environment.Set($Statement.Target, $list)
            return
        }

        # kill process p            / kill process p and its children    (D70)
        'KillProcess' {
            $processValue = Get-OtterValue -Expression $Statement.ProcessExpr -Environment $Environment
            if (-not (Test-OtterObject $processValue) -or -not ($processValue.HasProperty('id'))) {
                throw (New-OtterRuntimeError `
                    -Message 'I can only kill a real process handle, such as the one "run ... into p" or "get processes into list" gives you.' `
                    -Line $Statement.Line)
            }
            Stop-OtterProcess -ProcessId $processValue.ReadProperty('id') -IncludeChildren $Statement.IncludeChildren -Line $Statement.Line
            return
        }

        # set priority of process p to "high"                            (D71)
        'SetProcessPriority' {
            $processValue = Get-OtterValue -Expression $Statement.ProcessExpr -Environment $Environment
            if (-not (Test-OtterObject $processValue) -or -not ($processValue.HasProperty('id'))) {
                throw (New-OtterRuntimeError `
                    -Message 'I can only set the priority of a real process handle, such as the one "run ... into p" or "get processes into list" gives you.' `
                    -Line $Statement.Line)
            }
            $priorityText = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Priority -Environment $Environment)
            Set-OtterProcessPriority -ProcessId $processValue.ReadProperty('id') -Priority $priorityText -Line $Statement.Line
            return
        }

        # wait for process p up to 5 seconds [into finished]             (D71)
        'WaitForProcess' {
            $processValue = Get-OtterValue -Expression $Statement.ProcessExpr -Environment $Environment
            if (-not (Test-OtterObject $processValue) -or -not ($processValue.HasProperty('id'))) {
                throw (New-OtterRuntimeError `
                    -Message 'I can only wait for a real process handle, such as the one "run ... into p" or "get processes into list" gives you.' `
                    -Line $Statement.Line)
            }
            $seconds = Assert-OtterNumber -Value (Get-OtterValue -Expression $Statement.TimeoutSeconds -Environment $Environment) -Line $Statement.Line -What 'a number of seconds'
            $finished = Wait-OtterProcess -ProcessId $processValue.ReadProperty('id') -TimeoutSeconds $seconds
            if ($Statement.Target) {
                $Environment.Set($Statement.Target, $finished)
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

        # create symbolic link "l" pointing to "t"                     (D73)
        'CreateSymbolicLink' {
            $linkPath = Get-OtterPathArgument -Expression $Statement.LinkPath -Environment $Environment
            $targetPath = Get-OtterPathArgument -Expression $Statement.TargetPath -Environment $Environment
            New-OtterSymbolicLink -LinkPath $linkPath -TargetPath $targetPath -Line $Statement.Line
            return
        }

        # get symbolic link target of "l" into t                       (D73)
        'GetSymbolicLinkTarget' {
            $linkPath = Get-OtterPathArgument -Expression $Statement.LinkPath -Environment $Environment
            $target = Get-OtterSymbolicLinkTarget -LinkPath $linkPath -Line $Statement.Line
            $Environment.Set($Statement.Target, $target)
            return
        }

        # get owner of "x" into owner                                    (D74)
        'GetFileOwner' {
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            $owner = Get-OtterFileOwner -Path $path -Line $Statement.Line
            $Environment.Set($Statement.Target, $owner)
            return
        }

        # set file "x" to read only / to writable                        (D74)
        'SetFileReadOnly' {
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            Set-OtterFileReadOnly -Path $path -ReadOnly $Statement.ReadOnly -Line $Statement.Line
            return
        }

        # get registry value "n" from "path" into t                     (D78)
        'GetRegistryValue' {
            $valueName = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.ValueName -Environment $Environment)
            $keyPath = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.KeyPath -Environment $Environment)
            $value = Get-OtterRegistryValue -ValueName $valueName -KeyPath $keyPath -Line $Statement.Line
            $Environment.Set($Statement.Target, $value)
            return
        }

        # set registry value "n" to "d" in "path"                       (D78)
        'SetRegistryValue' {
            $valueName = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.ValueName -Environment $Environment)
            $value = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Value -Environment $Environment)
            $keyPath = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.KeyPath -Environment $Environment)
            Set-OtterRegistryValue -ValueName $valueName -Value $value -KeyPath $keyPath -Line $Statement.Line
            return
        }

        # delete registry value "n" from "path"                         (D78)
        'DeleteRegistryValue' {
            $valueName = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.ValueName -Environment $Environment)
            $keyPath = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.KeyPath -Environment $Environment)
            Remove-OtterRegistryValue -ValueName $valueName -KeyPath $keyPath -Line $Statement.Line
            return
        }

        # get event log entries from "System" up to 20 into entries      (D79)
        'GetEventLogEntries' {
            $logName = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.LogName -Environment $Environment)
            $maxEntries = Assert-OtterNumber -Value (Get-OtterValue -Expression $Statement.MaxEntries -Environment $Environment) -Line $Statement.Line -What 'a maximum number of entries'
            $entries = Get-OtterEventLogEntries -LogName $logName -MaxEntries $maxEntries -Line $Statement.Line
            $Environment.Set($Statement.Target, $entries)
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

        # --- system integration (D67) ---------------------------

        # copy "text" to clipboard
        'CopyToClipboard' {
            $text = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Text -Environment $Environment)
            Set-Clipboard -Value $text
            return
        }

        # get clipboard into text          - gone if the clipboard holds no text
        'GetClipboard' {
            $value = $null
            try { $value = Get-Clipboard -Raw -ErrorAction Stop } catch { $value = $null }
            $Environment.Set($Statement.Target, $value)
            return
        }

        # notify "Title" with "Message"    - a real OS toast, not a fake one
        'Notify' {
            $title = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Title -Environment $Environment)
            $message = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Message -Environment $Environment)
            Show-OtterNotification -Title $title -Message $message
            return
        }

        # get environment variable "PATH" into value      - gone if not set
        'GetEnvironmentVariable' {
            $name = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Name -Environment $Environment)
            $value = [System.Environment]::GetEnvironmentVariable($name)
            $Environment.Set($Statement.Target, $value)
            return
        }

        # get system folder "temp" into path
        'GetSystemFolder' {
            $folderName = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.FolderName -Environment $Environment)
            $path = switch ($folderName.ToLowerInvariant()) {
                'temp' { [System.IO.Path]::GetTempPath() }
                'appdata' { [System.Environment]::GetFolderPath('ApplicationData') }
                'user' { [System.Environment]::GetFolderPath('UserProfile') }
                'current' { (Get-Location).Path }
                default {
                    throw (New-OtterRuntimeError `
                        -Message "I do not know a system folder called ""$folderName""." `
                        -Line $Statement.Line `
                        -Suggestion 'get system folder "temp" into path (also: "appdata", "user", "current")')
                }
            }
            $Environment.Set($Statement.Target, $path)
            return
        }

        # get system information "os" into info                          (D69)
        'GetSystemInfo' {
            $infoKind = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.InfoKind -Environment $Environment)
            $value = Get-OtterSystemInfoValue -Kind $infoKind -Line $Statement.Line
            $Environment.Set($Statement.Target, $value)
            return
        }

        # choose file into path            - gone if the user cancels
        'ChooseFile' {
            $path = Show-OtterFileDialog -Mode 'OpenFile'
            $Environment.Set($Statement.Target, $path)
            return
        }

        # choose folder into path          - gone if the user cancels
        'ChooseFolder' {
            $path = Show-OtterFileDialog -Mode 'Folder'
            $Environment.Set($Statement.Target, $path)
            return
        }

        # choose file to save into path    - gone if the user cancels
        'ChooseSaveFile' {
            $path = Show-OtterFileDialog -Mode 'SaveFile'
            $Environment.Set($Statement.Target, $path)
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

                # D68: `otherwise into reason` - binds the caught failure's
                # message text for ANY caught error, not just `fail`-raised
                # ones, before running the otherwise body.
                if ($Statement.ErrorTarget) {
                    $Environment.Set($Statement.ErrorTarget, $_.Exception.Message)
                }

                if ($null -ne $Statement.OtherwiseBody) {
                    Invoke-OtterStatements -Statements $Statement.OtherwiseBody -Environment $Environment
                }
            }
            return
        }

        # fail with "message"                                            (D68)
        # A real, user-raised custom error. Reuses the same OtterError
        # machinery as every built-in runtime error, so a hand-authored
        # failure is caught by an ordinary `try` exactly like a built-in one.
        'Fail' {
            $message = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Message -Environment $Environment)
            throw (New-OtterRuntimeError -Message $message -Line $Statement.Line)
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
            $result = $subject.Replace($find, $replacement)

            # D27: with a destination, the source is left exactly as it was.
            if ($Statement.ResultTarget) {
                $Environment.Set($Statement.ResultTarget, $result)
                return
            }
            $Environment.Set($Statement.Target, $result)
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

        # --- json (D29) -----------------------------------------

        # read json from "settings.json" into settings
        'ReadJson' {
            $path = Get-OtterPathArgument -Expression $Statement.Path -Environment $Environment
            $value = Read-OtterJsonFile -Path $path -Line $Statement.Line
            $Environment.Set($Statement.Target, $value)
            return
        }

        # convert user to json into text
        'ConvertToJson' {
            $subject = Get-OtterValue -Expression $Statement.Subject -Environment $Environment
            $Environment.Set($Statement.Target, (ConvertTo-OtterJsonText -Value $subject -Line $Statement.Line))
            return
        }

        # convert text from json into user
        'ConvertFromJson' {
            $text = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Subject -Environment $Environment)
            $value = ConvertFrom-OtterJsonText -Text $text -Line $Statement.Line
            $Environment.Set($Statement.Target, $value)
            return
        }

        # --- random (D30) ---------------------------------------

        # random number from 1 to 10 into number    - both ends included
        'RandomNumber' {
            $fromRaw = Get-OtterValue -Expression $Statement.From -Environment $Environment
            $toRaw = Get-OtterValue -Expression $Statement.To -Environment $Environment
            $from = Assert-OtterNumber -Value $fromRaw -Line $Statement.Line -What 'the lowest number'
            $to = Assert-OtterNumber -Value $toRaw -Line $Statement.Line -What 'the highest number'

            if ($from -gt $to) {
                $swap = $from; $from = $to; $to = $swap
            }
            # Get-Random -Maximum is exclusive, so add one to include the top.
            $picked = Get-Random -Minimum ([int][Math]::Floor($from)) -Maximum (([int][Math]::Floor($to)) + 1)
            $Environment.Set($Statement.Target, [double]$picked)
            return
        }

        # random item from games into game     - gone when the list is empty
        'RandomItem' {
            $collection = Get-OtterValue -Expression $Statement.Collection -Environment $Environment
            if (-not (Test-OtterList $collection)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only pick from a list, but this is $(Get-OtterTypeName $collection)." `
                    -Line $Statement.Line)
            }

            if ($collection.Count -eq 0) {
                $Environment.Set($Statement.Target, $null)
                return
            }

            $index = Get-Random -Minimum 0 -Maximum $collection.Count
            $Environment.Set($Statement.Target, $collection[$index])
            return
        }

        # --- diagnostics (D31) ----------------------------------

        # log "Server started."  /  warn "..."  /  error "..."
        'Diagnostic' {
            $rendered = @()
            foreach ($part in $Statement.Parts) {
                $rendered += (Format-OtterValue -Value (Get-OtterValue -Expression $part -Environment $Environment))
            }
            $label = switch ($Statement.Level.ToString()) {
                'Warning' { 'warn' }
                'Problem' { 'error' }
                default { 'log' }
            }
            Write-OtterDiagnostic -Level $label -Text ($rendered -join ' ')
            return
        }

        # --- dates and time (D32) -------------------------------

        # add 7 days to date   /   remove 1 month from date
        'DateAdjust' {
            $name = $Statement.Target
            if (-not $Environment.Has($name)) {
                throw (New-OtterRuntimeError -Message "Otter could not find the variable ""$name""." -Line $Statement.Line)
            }

            $current = $Environment.Get($name)
            if (-not (Test-OtterDate $current)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only add time to a date, but ""$name"" holds $(Get-OtterTypeName $current)." `
                    -Line $Statement.Line)
            }

            $amountRaw = Get-OtterValue -Expression $Statement.Amount -Environment $Environment
            $amount = Assert-OtterNumber -Value $amountRaw -Line $Statement.Line -What 'the amount of time'
            $whole = [int][Math]::Truncate($amount)
            if ($Statement.IsRemoval) { $whole = -$whole }

            $unit = $Statement.Unit.ToString()
            Assert-OtterUnitAllowed -Value $current -Unit $unit -Line $Statement.Line

            # Adjusting REPLACES the value rather than mutating in place, so
            # two variables holding the same date never move together.
            $moved = switch ($unit) {
                'Year' { $current.Value.AddYears($whole) }
                'Month' { $current.Value.AddMonths($whole) }
                'Day' { $current.Value.AddDays($whole) }
                'Hour' { $current.Value.AddHours($whole) }
                'Minute' { $current.Value.AddMinutes($whole) }
                'Second' { $current.Value.AddSeconds($whole) }
            }
            $Environment.Set($name, [OtterDate]::new($moved, $current.HasTime))
            return
        }

        # days between startDate and endDate make days
        # days between startDate and endDate make days      (D32, legacy - D42 left this untouched)
        'DateDifference' {
            $start = Get-OtterValue -Expression $Statement.Start -Environment $Environment
            $end = Get-OtterValue -Expression $Statement.End -Environment $Environment
            Assert-OtterDateOperands -Start $start -End $end -Line $Statement.Line

            # D32.7: SIGNED, end minus start, matching the argument order.
            # Whole units, truncated toward zero.
            $Environment.Set($Statement.Target,
                (Measure-OtterDateDifference -Start $start -End $end -Unit $Statement.Unit.ToString()))
            return
        }

        # format date as "MM/dd/yyyy" into text
        'FormatDate' {
            $subject = Get-OtterValue -Expression $Statement.Subject -Environment $Environment
            if (-not (Test-OtterDate $subject)) {
                throw (New-OtterRuntimeError `
                    -Message "I can only format a date, but this is $(Get-OtterTypeName $subject)." `
                    -Line $Statement.Line)
            }

            $pattern = Format-OtterValue -Value (Get-OtterValue -Expression $Statement.Format -Environment $Environment)
            try {
                $text = $subject.Value.ToString($pattern, [System.Globalization.CultureInfo]::InvariantCulture)
            }
            catch {
                throw (New-OtterRuntimeError `
                    -Message "I do not understand the date format $pattern." `
                    -Line $Statement.Line `
                    -Suggestion 'format date as "MM/dd/yyyy" into text')
            }

            # D32.4: the date itself is untouched.
            $Environment.Set($Statement.Target, $text)
            return
        }

        # state count is 0
        'StateDef' {
            $value = Get-OtterValue -Expression $Statement.InitialValue -Environment $Environment
            $signal = [OtterSignal]::new($Statement.Name, $value)
            $Environment.SetRaw($Statement.Name, $signal)
            return
        }

        # derive doubled is count * 2
        'DeriveDef' {
            $derived = [OtterDerived]::new($Statement.Name, $Statement.Expression, $Environment)
            $Environment.SetRaw($Statement.Name, $derived)
            return
        }

        # memo sortedItems ...
        #
        # D56: not part of Otter 1.0. Found during the v1 audit to be
        # outright broken, not merely unfinished - this case referenced
        # $Statement.Expression, a property MemoDefStmt does not have (it
        # only has .Body), so this always failed before even reaching
        # anything memo-specific. An explicit diagnostic here is strictly
        # more honest than the confusing PowerShell-property-not-found
        # failure this replaced.
        'MemoDef' {
            throw (New-OtterRuntimeError -Message "'memo' is not supported in Otter 1.0." -Line $Statement.Line)
        }

        # when count changes ...
        'Watch' {
            $targetName = $Statement.TargetName
            $raw = $Environment.GetRaw($targetName)
            $body = $Statement.Body
            $action = {
                Invoke-OtterStatements -Statements $body -Environment $Environment
            }.GetNewClosure()
            if ($raw -is [OtterSignal]) {
                $raw.Subscribe($action)
            } elseif ($raw -is [OtterDerived]) {
                $raw.Subscribe($action)
            } else {
                $signal = [OtterSignal]::new($targetName, $raw)
                $signal.Subscribe($action)
                $Environment.SetRaw($targetName, $signal)
            }
            return
        }

        # on start / on close
        #
        # D56: not part of Otter 1.0 - neither stage has defined, tested
        # lifecycle semantics. Previously 'start' ran its body inline
        # immediately (indistinguishable from the body not being wrapped
        # in "on start" at all, at the top level - not real deferred
        # lifecycle behavior) and 'close' did nothing at all. Both now
        # fail loudly instead of silently doing the wrong thing or nothing.
        'Lifecycle' {
            throw (New-OtterRuntimeError -Message "'on $($Statement.Stage)' is not supported in Otter 1.0." -Line $Statement.Line)
        }

        # shared theme is "dark"
        #
        # D56: not part of Otter 1.0 - mechanically identical to `state`,
        # but never independently exercised or frozen, so it does not get
        # to ride in on state's coattails.
        'SharedState' {
            throw (New-OtterRuntimeError -Message "'shared' is not supported in Otter 1.0." -Line $Statement.Line)
        }

        # use files / use ui
        #
        # D56: not part of Otter 1.0.
        'UseModule' {
            throw (New-OtterRuntimeError -Message "'use' is not supported in Otter 1.0." -Line $Statement.Line)
        }

        # focus searchBox / hide sidebar
        #
        # D56: not part of Otter 1.0. Verified during the v1 audit that
        # this was a silent no-op - confirmed directly, "hide sidebar"
        # left Visibility at its default and "focus box" left IsFocused
        # false, with no error either way. A feature doing nothing
        # successfully is worse than one that says so.
        'UiAction' {
            throw (New-OtterRuntimeError -Message "'$($Statement.Action)' is not supported in Otter 1.0." -Line $Statement.Line)
        }

        # card / window / primary button
        'UiElement' {
            if ($null -ne $Statement.Children) {
                Invoke-OtterStatements -Statements $Statement.Children -Environment $Environment
            }
            return
        }

        # D56: not part of Otter 1.0 - confirmed a silent no-op, same
        # reasoning as UiAction above.
        'UiEvent' {
            throw (New-OtterRuntimeError -Message "UI event blocks are not supported in Otter 1.0." -Line $Statement.Line)
        }

        # D56: not part of Otter 1.0 - confirmed a silent no-op.
        'UiAnimation' {
            throw (New-OtterRuntimeError -Message "UI animation is not supported in Otter 1.0." -Line $Statement.Line)
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

function Get-OtterDerivedValue {
    param(
        [Parameter(Mandatory)][OtterDerived]$Derived,
        [Parameter(Mandatory)][OtterEnvironment]$Environment
    )

    if ($Derived.IsEvaluating) {
        throw (New-OtterRuntimeError -Message "Circular dependency detected in derived value `"$($Derived.Name)`"." -Line 0)
    }

    if ($Derived.IsDirty) {
        $Derived.IsEvaluating = $true
        $prevTracker = [OtterEnvironment]::ActiveDependencyTracker
        $newTracker = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        [OtterEnvironment]::ActiveDependencyTracker = $newTracker
        try {
            $value = Get-OtterValue -Expression $Derived.Expression -Environment $Environment
            $Derived.CachedValue = $value
            $Derived.IsDirty = $false

            foreach ($depName in $newTracker) {
                if ($depName -eq $Derived.Name) { continue }
                $raw = $Environment.GetRaw($depName)
                if ($raw -is [OtterSignal]) {
                    $raw.Subscribe($Derived)
                } elseif ($raw -is [OtterDerived]) {
                    $raw.Subscribe($Derived)
                }
            }
        }
        finally {
            [OtterEnvironment]::ActiveDependencyTracker = $prevTracker
            $Derived.IsEvaluating = $false
        }
    }

    return $Derived.CachedValue
}

[OtterEnvironment]::DerivedEvaluator = {
    param([OtterDerived]$Derived, [OtterEnvironment]$Env)
    Get-OtterDerivedValue -Derived $Derived -Environment $Env
}

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

            if ($Expression.Op.ToString() -eq 'Add' -and ($leftRaw -is [string]) -and ($rightRaw -is [string])) {
                return $leftRaw + $rightRaw
            }

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

            # D32.6: two dates order by their instant, using the comparison
            # words Otter already has. No new syntax.
            if ((Test-OtterDate $left) -and (Test-OtterDate $right)) {
                $comparison = $left.Value.CompareTo($right.Value)
                switch ($Expression.Op.ToString()) {
                    'AtLeast' { return ($comparison -ge 0) }
                    'AtMost' { return ($comparison -le 0) }
                    'GreaterThan' { return ($comparison -gt 0) }
                    'LessThan' { return ($comparison -lt 0) }
                }
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

        # name of person   /   city of address of user   /   year of date
        'PropertyAccess' {
            $target = Get-OtterValue -Expression $Expression.Target -Environment $Environment

            # D32.2: a date answers its own parts. This is why date parts are
            # NOT operation words - "year of book" on a thing has to keep
            # meaning the stored property, and the two are indistinguishable
            # until the value is in hand.
            if (Test-OtterDate $target) {
                return (Get-OtterDatePart -Date $target -Part $Expression.Property -Line $Expression.Line)
            }

            # text of helloButton                                    (D45)
            #
            # Routed through Otter.UI.psm1 - the only place that knows
            # "text" means WPF Content for a button but Text for a text
            # box. The interpreter never touches System.Windows.* itself.
            if (Test-OtterUiResource $target) {
                Write-Output -NoEnumerate (
                    Get-OtterUiProperty -Resource $target -Property $Expression.Property -Line $Expression.Line)
                return
            }

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

        # if file "hello.txt" is locked                                (D72)
        'FileLocked' {
            $path = Get-OtterPathArgument -Expression $Expression.Path -Environment $Environment
            return (Test-OtterFileLocked -Path $path -Line $Expression.Line)
        }

        # if file "l" is a symbolic link                                (D73)
        'FileIsSymbolicLink' {
            $path = Get-OtterPathArgument -Expression $Expression.Path -Environment $Environment
            return (Test-OtterSymbolicLink -Path $path -Line $Expression.Line)
        }

        # if file "x" is read only                                       (D74)
        'FileIsReadOnly' {
            $path = Get-OtterPathArgument -Expression $Expression.Path -Environment $Environment
            return (Test-OtterFileReadOnly -Path $path -Line $Expression.Line)
        }

        # if registry key "path" exists                                 (D78)
        'RegistryKeyExists' {
            $keyPath = Format-OtterValue -Value (Get-OtterValue -Expression $Expression.KeyPath -Environment $Environment)
            return (Test-OtterRegistryKeyExists -KeyPath $keyPath)
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

        # today   /   now                                      (D32)
        'Clock' {
            if ($Expression.Clock.ToString() -eq 'Today') { return (New-OtterToday) }
            return (New-OtterNow)
        }

        # days between startDate and endDate                            (D42)
        #
        # A genuine value, so it evaluates the same way Get-OtterValue
        # evaluates everything else - usable in "is", in "say", inside a
        # condition, as a function argument. Same calculation as the
        # legacy statement form (D32.7: signed, end minus start, whole
        # units truncated toward zero) - Assert-OtterDateOperands and
        # Measure-OtterDateDifference are the SAME functions the
        # 'DateDifference' statement case above calls, not a second copy.
        'DateDifferenceValue' {
            $start = Get-OtterValue -Expression $Expression.Start -Environment $Environment
            $end = Get-OtterValue -Expression $Expression.End -Environment $Environment
            Assert-OtterDateOperands -Start $start -End $end -Line $Expression.Line

            return (Measure-OtterDateDifference -Start $start -End $end -Unit $Expression.Unit.ToString())
        }

        # D56: not part of Otter 1.0 - there is no real asynchronicity
        # anywhere in this interpreter, so this previously just forwarded
        # the inner value transparently, silently pretending to be a
        # working "await" rather than admitting there is nothing to wait
        # for yet.
        'Await' {
            throw (New-OtterRuntimeError -Message "'await' is not supported in Otter 1.0." -Line $Expression.Line)
        }

        'UiElement' {
            if ($null -ne $Expression.Children) {
                Invoke-OtterStatements -Statements $Expression.Children -Environment $Environment
            }
            return $Expression
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

            # text of helloButton is "Say Hello"                     (D45)
            if (Test-OtterUiResource $owner) {
                Set-OtterUiProperty -Resource $owner -Property $Target.Property -Value $Value -Line $Target.Line
                return
            }

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

# D32.1: hour/minute/second belong to a date AND time. Asking a plain date
# for its hour is a mistake, not a zero.
$script:DateOnlyUnits = @('Year', 'Month', 'Day')

function Assert-OtterUnitAllowed {
    param([object]$Value, [string]$Unit, [int]$Line)

    if ($Value.HasTime) { return }
    if ($script:DateOnlyUnits -contains $Unit) { return }

    throw (New-OtterRuntimeError `
        -Message "This is a date with no time of day, so it has no $($Unit.ToLowerInvariant())." `
        -Line $Line `
        -Suggestion 'started is now')
}

# year of date / month of date / hour of started ...
function Get-OtterDatePart {
    param([object]$Date, [string]$Part, [int]$Line)

    switch ($Part) {
        'year' { return [double]$Date.Value.Year }
        'month' { return [double]$Date.Value.Month }   # 1-12, never a name
        'day' { return [double]$Date.Value.Day }
        'hour' {
            Assert-OtterUnitAllowed -Value $Date -Unit 'Hour' -Line $Line
            return [double]$Date.Value.Hour
        }
        'minute' {
            Assert-OtterUnitAllowed -Value $Date -Unit 'Minute' -Line $Line
            return [double]$Date.Value.Minute
        }
        'second' {
            Assert-OtterUnitAllowed -Value $Date -Unit 'Second' -Line $Line
            return [double]$Date.Value.Second
        }
    }

    throw (New-OtterRuntimeError `
        -Message "A date has no part called ""$Part""." `
        -Line $Line `
        -Suggestion "year of ...")
}

# D42: shared by DateDifferenceStmt (legacy) and DateDifferenceExpr, so the
# validation is written once and both forms report it identically. Factored
# out of the statement case, not duplicated into the new expression case.
function Assert-OtterDateOperands {
    param([object]$Start, [object]$End, [int]$Line)

    foreach ($side in @(@('first', $Start), @('second', $End))) {
        if (-not (Test-OtterDate $side[1])) {
            throw (New-OtterRuntimeError `
                -Message "I can only measure time between two dates, but the $($side[0]) one is $(Get-OtterTypeName $side[1])." `
                -Line $Line)
        }
    }
}

# Whole units, truncated toward zero, signed end-minus-start (D32.7).
function Measure-OtterDateDifference {
    param([object]$Start, [object]$End, [string]$Unit)

    $from = $Start.Value
    $to = $End.Value

    if ($Unit -eq 'Year' -or $Unit -eq 'Month') {
        # Calendar months, not averaged days: Jan 31 to Feb 28 is one month.
        $months = (($to.Year - $from.Year) * 12) + ($to.Month - $from.Month)
        if ($months -gt 0 -and $to.Day -lt $from.Day) { $months-- }
        if ($months -lt 0 -and $to.Day -gt $from.Day) { $months++ }
        if ($Unit -eq 'Month') { return [double]$months }
        return [double][Math]::Truncate($months / 12)
    }

    $span = $to - $from
    switch ($Unit) {
        'Day' { return [double][Math]::Truncate($span.TotalDays) }
        'Hour' { return [double][Math]::Truncate($span.TotalHours) }
        'Minute' { return [double][Math]::Truncate($span.TotalMinutes) }
        'Second' { return [double][Math]::Truncate($span.TotalSeconds) }
    }
    return 0.0
}

# Type names as a beginner would say them, for error messages.
function Get-OtterTypeName {
    param([object]$Value)

    if ($null -eq $Value) { return 'gone' }
    if ($Value -is [bool]) { return 'a true or false value' }
    if ($Value -is [OtterFunction]) { return 'something Otter can do' }
    if (Test-OtterUiResource $Value) { return "a $($Value.Kind)" }
    if (Test-OtterDate $Value) {
        if ($Value.HasTime) { return 'a date and time' }
        return 'a date'
    }
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
    Set-OtterOutputWriter, Set-OtterDiagnosticWriter, Write-OtterLine, Get-OtterText, Get-OtterPathArgument, Set-OtterTarget
