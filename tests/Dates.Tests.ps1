using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Interpreter.psm1

# Dates.Tests.ps1
#
# D32: dates and time.
#
# today/now are read from the clock, so most of these build a date value
# directly rather than asserting against a moving target. The clock itself is
# tested separately, for the things that must be true whatever the time is.

. "$PSScriptRoot\TestHelpers.ps1"

function Lit { param($Value, [int]$Line = 1) [LiteralExpr]::new($Value, $Line) }
function Var { param([string]$Name, [int]$Line = 1) [VariableExpr]::new($Name, $Line) }
function PropOf { param([string]$P, [Node]$T, [int]$Line = 1) [PropertyAccessExpr]::new($P, $T, $Line) }
function CompareEx { param([Node]$L, [string]$Op, [Node]$R, [int]$Line = 1) [ComparisonExpr]::new($L, [CompareOp]$Op, $R, $Line) }
function Clock { param([string]$Which, [int]$Line = 1) [ClockExpr]::new([ClockKind]$Which, $Line) }

# A fixed date, so assertions do not move with the calendar.
function FixedDate {
    param([string]$Text, [bool]$HasTime = $false)
    [OtterDate]::new([datetime]::ParseExact($Text, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture), $HasTime)
}

function Invoke-TestProgram {
    param([Node[]]$Statements)
    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($Text) $collected.Add($Text) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        Invoke-OtterProgram -Program ([ProgramNode]::new($Statements)) -Environment (New-OtterEnvironment)
    }
    finally {
        Set-OtterOutputWriter -Writer $null
    }
    return , $collected.ToArray()
}

Write-Host ''
Write-Host 'Dates and time (D32)' -ForegroundColor Cyan


# =================================================================
# today and now
# =================================================================

Test-Otter 'today gives a date, now gives a date and time' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('date', (Clock 'Today'), 1),
        [AssignStmt]::new('started', (Clock 'Now'), 2),
        [SayStmt]::new(@((Var 'date')), 3),
        [SayStmt]::new(@((Var 'started')), 4)
    )
    # D32.5: ISO-style. A date has no time; a date and time carries one.
    Assert-True ($out[0] -match '^\d{4}-\d{2}-\d{2}$') "date printed as [$($out[0])]"
    Assert-True ($out[1] -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$') "date-time printed as [$($out[1])]"
}

Test-Otter 'today matches the machine clock' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('date', (Clock 'Today'), 1),
        [SayStmt]::new(@((PropOf 'year' (Var 'date'))), 2)
    )
    Assert-AreEqual -Expected ([datetime]::Now.Year) -Actual $out[0]
}

Test-Otter 'a date is not a number' {
    Assert-False (Test-OtterNumeric (FixedDate '2026-09-09 00:00:00')) 'a date must not look numeric'
}

Test-Otter 'a date is true' {
    Assert-True (Test-OtterTruthy -Value (FixedDate '2026-09-09 00:00:00'))
}


# =================================================================
# D32.2 - parts are ordinary property access
# =================================================================

Test-Otter 'year, month and day of a date' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('date', (Lit (FixedDate '2026-09-09 00:00:00')), 1),
        [SayStmt]::new(@((PropOf 'year' (Var 'date'))), 2),
        [SayStmt]::new(@((PropOf 'month' (Var 'date'))), 3),
        [SayStmt]::new(@((PropOf 'day' (Var 'date'))), 4)
    )
    Assert-Lines -Expected @('2026', '9', '9') -Actual $out
}

Test-Otter 'month is a number from 1 to 12, never a name' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('date', (Lit (FixedDate '2026-01-05 00:00:00')), 1),
        [SayStmt]::new(@((PropOf 'month' (Var 'date'))), 2)
    )
    Assert-Lines -Expected @('1') -Actual $out
}

Test-Otter 'hour, minute and second of a date and time' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('started', (Lit (FixedDate '2026-09-09 14:30:05' $true)), 1),
        [SayStmt]::new(@((PropOf 'hour' (Var 'started'))), 2),
        [SayStmt]::new(@((PropOf 'minute' (Var 'started'))), 3),
        [SayStmt]::new(@((PropOf 'second' (Var 'started'))), 4)
    )
    Assert-Lines -Expected @('14', '30', '5') -Actual $out
}

Test-Otter 'hour of a plain date is an error, not a silent zero' {
    # D32.1: midnight and "no time at all" are different things.
    Assert-OtterFails -Containing 'no time of day' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('date', (Clock 'Today'), 1),
            [SayStmt]::new(@((PropOf 'hour' (Var 'date'))), 2)
        )
    }
}

Test-Otter 'a date has no made-up parts' {
    Assert-OtterFails -Containing 'no part called' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('date', (Clock 'Today'), 1),
            [SayStmt]::new(@((PropOf 'fortnight' (Var 'date'))), 2)
        )
    }
}

Test-Otter 'year of a THING is still an ordinary property (D32.2)' {
    # The whole reason date parts are not operation words. If "year" were
    # reserved, this program would stop working.
    $out = Invoke-TestProgram @(
        [ObjectDefStmt]::new('book', 'thing', @(
            [AssignStmt]::new('year', (Lit 1984.0), 2),
            [AssignStmt]::new('title', (Lit 'Nineteen Eighty-Four'), 3)
        ), 1),
        [SayStmt]::new(@((PropOf 'title' (Var 'book')), (Lit 'was published in'), (PropOf 'year' (Var 'book'))), 5)
    )
    Assert-Lines -Expected @('Nineteen Eighty-Four was published in 1984') -Actual $out
}

Test-Otter 'a thing and a date can both answer year, independently' {
    $out = Invoke-TestProgram @(
        [ObjectDefStmt]::new('book', 'thing', @([AssignStmt]::new('year', (Lit 1984.0), 2)), 1),
        [AssignStmt]::new('date', (Lit (FixedDate '2026-09-09 00:00:00')), 4),
        [SayStmt]::new(@((PropOf 'year' (Var 'book'))), 5),
        [SayStmt]::new(@((PropOf 'year' (Var 'date'))), 6)
    )
    Assert-Lines -Expected @('1984', '2026') -Actual $out
}


# =================================================================
# D32.3 - temporal mutation
# =================================================================

Test-Otter 'add 1 day and add 7 days' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('date', (Lit (FixedDate '2026-09-09 00:00:00')), 1),
        [DateAdjustStmt]::new((Lit 1.0), [TimeUnit]::Day, 'date', $false, 2),
        [SayStmt]::new(@((Var 'date')), 3),
        [DateAdjustStmt]::new((Lit 7.0), [TimeUnit]::Day, 'date', $false, 4),
        [SayStmt]::new(@((Var 'date')), 5)
    )
    Assert-Lines -Expected @('2026-09-10', '2026-09-17') -Actual $out
}

Test-Otter 'remove 1 month, and add 1 year' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('date', (Lit (FixedDate '2026-09-09 00:00:00')), 1),
        [DateAdjustStmt]::new((Lit 1.0), [TimeUnit]::Month, 'date', $true, 2),
        [SayStmt]::new(@((Var 'date')), 3),
        [DateAdjustStmt]::new((Lit 1.0), [TimeUnit]::Year, 'date', $false, 4),
        [SayStmt]::new(@((Var 'date')), 5)
    )
    Assert-Lines -Expected @('2026-08-09', '2027-08-09') -Actual $out
}

Test-Otter 'month arithmetic clamps to the end of the month' {
    # 31 January plus one month is the end of February, not 3 March.
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('date', (Lit (FixedDate '2026-01-31 00:00:00')), 1),
        [DateAdjustStmt]::new((Lit 1.0), [TimeUnit]::Month, 'date', $false, 2),
        [SayStmt]::new(@((Var 'date')), 3)
    )
    Assert-Lines -Expected @('2026-02-28') -Actual $out
}

Test-Otter 'add 1 hour and add 30 minutes to a date and time' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('started', (Lit (FixedDate '2026-09-09 14:30:05' $true)), 1),
        [DateAdjustStmt]::new((Lit 1.0), [TimeUnit]::Hour, 'started', $false, 2),
        [SayStmt]::new(@((Var 'started')), 3),
        [DateAdjustStmt]::new((Lit 30.0), [TimeUnit]::Minute, 'started', $false, 4),
        [SayStmt]::new(@((Var 'started')), 5)
    )
    Assert-Lines -Expected @('2026-09-09 15:30:05', '2026-09-09 16:00:05') -Actual $out
}

Test-Otter 'adding hours to a plain date is an error' {
    Assert-OtterFails -Containing 'no time of day' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('date', (Clock 'Today'), 1),
            [DateAdjustStmt]::new((Lit 1.0), [TimeUnit]::Hour, 'date', $false, 2)
        )
    }
}

Test-Otter 'adding time to something that is not a date explains itself' {
    Assert-OtterFails -Containing 'I can only add time to a date' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('score', (Lit 10.0), 1),
            [DateAdjustStmt]::new((Lit 1.0), [TimeUnit]::Day, 'score', $false, 2)
        )
    }
}

Test-Otter 'adjusting one date does not move another holding the same value' {
    # Adjusting REPLACES rather than mutating in place.
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('start', (Lit (FixedDate '2026-09-09 00:00:00')), 1),
        [AssignStmt]::new('finish', (Var 'start'), 2),
        [DateAdjustStmt]::new((Lit 5.0), [TimeUnit]::Day, 'finish', $false, 3),
        [SayStmt]::new(@((Var 'start')), 4),
        [SayStmt]::new(@((Var 'finish')), 5)
    )
    Assert-Lines -Expected @('2026-09-09', '2026-09-14') -Actual $out
}

Test-Otter 'add 5 to score still means the number, not a date' {
    # D32.3: no unit word, so this is D12 arithmetic and nothing else.
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('score', (Lit 10.0), 1),
        [AddToStmt]::new((Lit 5.0), 'score', 2),
        [SayStmt]::new(@((Var 'score')), 3)
    )
    Assert-Lines -Expected @('15') -Actual $out
}


# =================================================================
# D32.4 - formatting
# =================================================================

Test-Otter 'format date as "MM/dd/yyyy" into text' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('date', (Lit (FixedDate '2026-09-09 00:00:00')), 1),
        [FormatDateStmt]::new((Var 'date'), (Lit 'MM/dd/yyyy'), 'text', 2),
        [SayStmt]::new(@((Var 'text')), 3),
        [SayStmt]::new(@((Var 'date')), 4)
    )
    # The date itself is untouched.
    Assert-Lines -Expected @('09/09/2026', '2026-09-09') -Actual $out
}

Test-Otter 'formatting a date and time can show the time' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('started', (Lit (FixedDate '2026-09-09 14:30:05' $true)), 1),
        [FormatDateStmt]::new((Var 'started'), (Lit 'yyyy-MM-dd HH:mm'), 'text', 2),
        [SayStmt]::new(@((Var 'text')), 3)
    )
    Assert-Lines -Expected @('2026-09-09 14:30') -Actual $out
}

Test-Otter 'formatting something that is not a date explains itself' {
    Assert-OtterFails -Containing 'I can only format a date' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('name', (Lit 'Jeff'), 1),
            [FormatDateStmt]::new((Var 'name'), (Lit 'MM/dd/yyyy'), 'text', 2)
        )
    }
}


# =================================================================
# days between
# =================================================================

Test-Otter 'days between two dates' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('startDate', (Lit (FixedDate '2026-09-01 00:00:00')), 1),
        [AssignStmt]::new('endDate', (Lit (FixedDate '2026-09-09 00:00:00')), 2),
        [DateDifferenceStmt]::new([TimeUnit]::Day, (Var 'startDate'), (Var 'endDate'), 'days', 3),
        [SayStmt]::new(@((Var 'days')), 4)
    )
    Assert-Lines -Expected @('8') -Actual $out
}

Test-Otter 'days between is signed when the dates are the other way round' {
    # D32.7 - UNRESOLVED. Pinning the current behaviour so a change is visible.
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('startDate', (Lit (FixedDate '2026-09-09 00:00:00')), 1),
        [AssignStmt]::new('endDate', (Lit (FixedDate '2026-09-01 00:00:00')), 2),
        [DateDifferenceStmt]::new([TimeUnit]::Day, (Var 'startDate'), (Var 'endDate'), 'days', 3),
        [SayStmt]::new(@((Var 'days')), 4)
    )
    Assert-Lines -Expected @('-8') -Actual $out
}

Test-Otter 'days between truncates toward zero, never rounds up' {
    # 36 hours apart is one whole day, not one and a half.
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('a', (Lit (FixedDate '2026-09-01 00:00:00' $true)), 1),
        [AssignStmt]::new('b', (Lit (FixedDate '2026-09-02 12:00:00' $true)), 2),
        [DateDifferenceStmt]::new([TimeUnit]::Day, (Var 'a'), (Var 'b'), 'days', 3),
        [SayStmt]::new(@((Var 'days')), 4)
    )
    Assert-Lines -Expected @('1') -Actual $out
}

Test-Otter 'months between uses the calendar, not averaged days' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('a', (Lit (FixedDate '2026-01-31 00:00:00')), 1),
        [AssignStmt]::new('b', (Lit (FixedDate '2026-02-28 00:00:00')), 2),
        [DateDifferenceStmt]::new([TimeUnit]::Month, (Var 'a'), (Var 'b'), 'months', 3),
        [SayStmt]::new(@((Var 'months')), 4)
    )
    Assert-Lines -Expected @('0') -Actual $out
}

Test-Otter 'measuring between something that is not a date explains itself' {
    Assert-OtterFails -Containing 'between two dates' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('a', (Lit 'not a date'), 1),
            [AssignStmt]::new('b', (Clock 'Today'), 2),
            [DateDifferenceStmt]::new([TimeUnit]::Day, (Var 'a'), (Var 'b'), 'days', 3)
        )
    }
}


# =================================================================
# days between AS AN EXPRESSION (D42)
#
# Same calculation as the statement form above - D42 does not change what
# "days between" computes, only where it is legal to write it. Every test
# here has a matching statement-form test above with the identical fixture
# dates, so the two forms are provable equal, not just both "correct."
# =================================================================

function DaysBetween {
    param([Node]$Start, [Node]$End, [int]$Line = 1)
    [DateDifferenceExpr]::new([TimeUnit]::Day, $Start, $End, $Line)
}

Test-Otter 'days between as a value, assigned with is (the canonical D42 form)' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('startDate', (Lit (FixedDate '2026-09-01 00:00:00')), 1),
        [AssignStmt]::new('endDate', (Lit (FixedDate '2026-09-09 00:00:00')), 2),
        [AssignStmt]::new('waiting', (DaysBetween (Var 'startDate') (Var 'endDate') 3), 3),
        [SayStmt]::new(@((Var 'waiting')), 4)
    )
    # Identical fixture to "days between two dates" above - same 8.
    Assert-Lines -Expected @('8') -Actual $out
}

Test-Otter 'days between usable directly in say, with no destination at all' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('a', (Lit (FixedDate '2026-09-01 00:00:00')), 1),
        [AssignStmt]::new('b', (Lit (FixedDate '2026-09-09 00:00:00')), 2),
        [SayStmt]::new(@((Lit 'Waiting:'), (DaysBetween (Var 'a') (Var 'b') 3)), 3)
    )
    Assert-Lines -Expected @('Waiting: 8') -Actual $out
}

Test-Otter 'days between usable directly inside a condition' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('a', (Lit (FixedDate '2026-09-01 00:00:00')), 1),
        [AssignStmt]::new('b', (Lit (FixedDate '2026-09-09 00:00:00')), 2),
        [IfStmt]::new(
            @([IfBranch]::new(
                [ComparisonExpr]::new((DaysBetween (Var 'a') (Var 'b') 3), [CompareOp]::GreaterThan, (Lit 5.0), 3),
                @([SayStmt]::new(@((Lit 'More than 5 days.')), 4)))),
            $null, 3)
    )
    Assert-Lines -Expected @('More than 5 days.') -Actual $out
}

Test-Otter 'days between as an expression is signed, matching the statement form' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('startDate', (Lit (FixedDate '2026-09-09 00:00:00')), 1),
        [AssignStmt]::new('endDate', (Lit (FixedDate '2026-09-01 00:00:00')), 2),
        [SayStmt]::new(@((DaysBetween (Var 'startDate') (Var 'endDate') 3)), 3)
    )
    # Identical fixture to "days between is signed when the dates are the
    # other way round" above - same -8.
    Assert-Lines -Expected @('-8') -Actual $out
}

Test-Otter 'days between as an expression truncates toward zero, matching the statement form' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('a', (Lit (FixedDate '2026-09-01 00:00:00' $true)), 1),
        [AssignStmt]::new('b', (Lit (FixedDate '2026-09-02 12:00:00' $true)), 2),
        [SayStmt]::new(@((DaysBetween (Var 'a') (Var 'b') 3)), 3)
    )
    Assert-Lines -Expected @('1') -Actual $out
}

Test-Otter 'other units work as an expression too, not just days' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('a', (Lit (FixedDate '2026-01-31 00:00:00')), 1),
        [AssignStmt]::new('b', (Lit (FixedDate '2026-02-28 00:00:00')), 2),
        [AssignStmt]::new('months', [DateDifferenceExpr]::new([TimeUnit]::Month, (Var 'a'), (Var 'b'), 3), 3),
        [SayStmt]::new(@((Var 'months')), 4)
    )
    # Identical fixture to "months between uses the calendar" above - same 0.
    Assert-Lines -Expected @('0') -Actual $out
}

Test-Otter 'the expression form gives the same OtterError as the statement form' {
    Assert-OtterFails -Containing 'between two dates' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('a', (Lit 'not a date'), 1),
            [AssignStmt]::new('b', (Clock 'Today'), 2),
            [SayStmt]::new(@((DaysBetween (Var 'a') (Var 'b') 3)), 3)
        )
    }
}

Test-Otter 'the legacy statement form still works, unchanged, alongside the expression' {
    # Both forms in the same program, same fixture - proving D42 did not
    # touch DateDifferenceStmt's behavior.
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('a', (Lit (FixedDate '2026-09-01 00:00:00')), 1),
        [AssignStmt]::new('b', (Lit (FixedDate '2026-09-09 00:00:00')), 2),
        [DateDifferenceStmt]::new([TimeUnit]::Day, (Var 'a'), (Var 'b'), 'viaStatement', 3),
        [AssignStmt]::new('viaExpression', (DaysBetween (Var 'a') (Var 'b') 4), 4),
        [SayStmt]::new(@((Var 'viaStatement')), 5),
        [SayStmt]::new(@((Var 'viaExpression')), 6)
    )
    Assert-Lines -Expected @('8', '8') -Actual $out
}


# =================================================================
# D32.6 - comparison
# =================================================================

Test-Otter 'dates compare with the words Otter already has' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('startDate', (Lit (FixedDate '2026-09-01 00:00:00')), 1),
        [AssignStmt]::new('endDate', (Lit (FixedDate '2026-09-09 00:00:00')), 2),
        [SayStmt]::new(@((CompareEx (Var 'endDate') 'GreaterThan' (Var 'startDate'))), 3),
        [SayStmt]::new(@((CompareEx (Var 'endDate') 'LessThan' (Var 'startDate'))), 4),
        [SayStmt]::new(@((CompareEx (Var 'startDate') 'AtMost' (Var 'endDate'))), 5)
    )
    Assert-Lines -Expected @('true', 'false', 'true') -Actual $out
}

Test-Otter 'two dates made the same day are equal' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('a', (Lit (FixedDate '2026-09-09 00:00:00')), 1),
        [AssignStmt]::new('b', (Lit (FixedDate '2026-09-09 00:00:00')), 2),
        [SayStmt]::new(@((CompareEx (Var 'a') 'Equal' (Var 'b'))), 3)
    )
    Assert-Lines -Expected @('true') -Actual $out
}

Test-Otter 'a date never equals text that looks like one' {
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('date', (Lit (FixedDate '2026-09-09 00:00:00')), 1),
        [AssignStmt]::new('text', (Lit '2026-09-09'), 2),
        [SayStmt]::new(@((CompareEx (Var 'date') 'Equal' (Var 'text'))), 3)
    )
    Assert-Lines -Expected @('false') -Actual $out
}

Test-Otter 'weekday of date is 1 for Monday through 7 for Sunday' {
    # 2026-09-28 is a Monday; 2026-10-04 is the following Sunday.
    $out = Invoke-TestProgram @(
        [AssignStmt]::new('monday', (Lit (FixedDate '2026-09-28 00:00:00')), 1),
        [AssignStmt]::new('sunday', (Lit (FixedDate '2026-10-04 00:00:00')), 2),
        [AssignStmt]::new('thursday', (Lit (FixedDate '2026-10-01 00:00:00')), 3),
        [SayStmt]::new(@((PropOf 'weekday' (Var 'monday')), (PropOf 'weekday' (Var 'thursday')), (PropOf 'weekday' (Var 'sunday'))), 4)
    )
    Assert-Lines -Expected @('1 4 7') -Actual $out
}


Complete-OtterTests
