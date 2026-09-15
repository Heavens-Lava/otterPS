using module ..\Otter.Contract.psm1

# Otter.Compiler.JavaScript.psm1
#
# D60: the universal Otter-AST -> JavaScript emitter. Portable behavior only
# - this module must know how Otter behaves, not where the generated
# JavaScript will run. No document/window/WebView/Tauri/Electron references
# belong here; those are target-adapter concerns (Otter.Web.psm1,
# Otter.Desktop.psm1, Otter.Console.psm1), which consume this module rather
# than the other way around.
#
# Phase 1A: extracted from Otter.Web.psm1 verbatim, behavior-preserving.
# No new syntax, no new NodeKind coverage, no output changes in this pass -
# see SPEC-DECISIONS.md D60 for the extraction contract this followed.
#
# Known pre-existing portability note, not fixed in this extraction (would
# be a behavior change, out of scope for a boring move): ConvertTo-
# OtterJsStatement's Assign/HttpGet/HttpPost cases fall back to a bare
# `window.<name>` global for variables outside otterState. `window` only
# exists in a browser target - a future console/desktop-neutral pass will
# need to route this through an injected runtime hook instead.

# D60 Phase 1J. Builds the JS text for a tagged date value - `{ __otterDate:
# true, hasTime, value: <a real JS Date>, toString() {...} }` - matching
# OtterDate exactly: `value` is the actual instant, `hasTime` distinguishes
# "a date" from "a date and time" the same way OtterDate.HasTime does, and
# `toString()` reproduces OtterDate.ToString() exactly ('yyyy-MM-dd' /
# 'yyyy-MM-dd HH:mm:ss') so that string concatenation (`+`, used throughout
# for say/diagnostic/error text) renders a date correctly via JS's own
# ToPrimitive coercion - no shared runtime helper needed for that. Not
# fixed by this: `say date` ALONE (no concatenation) passes the raw object
# straight to console.log, which uses its own object-inspection display
# rather than calling toString() - the exact same already-accepted,
# already-documented class of cosmetic gap Phase 1G/1H found for lists
# printing as `[Zelda, Mario]` rather than `Zelda, Mario`, not a new one
# introduced here. A helper FUNCTION, not a factored-out PowerShell string
# constant, so each call site still emits fully self-contained inline JS
# (the established convention - no new shared JS runtime function added to
# Otter.Web.psm1's boilerplate); this only avoids repeating the same
# PowerShell string-building code twice.
function Get-OtterJsDateConstructor {
    param([string]$DateExprJs, [string]$HasTimeJs)

    $toStringBody = "const y=this.value.getFullYear(); const mo=String(this.value.getMonth()+1).padStart(2,'0'); const da=String(this.value.getDate()).padStart(2,'0'); if (!this.hasTime) { return y+'-'+mo+'-'+da; } const h=String(this.value.getHours()).padStart(2,'0'); const mi=String(this.value.getMinutes()).padStart(2,'0'); const s=String(this.value.getSeconds()).padStart(2,'0'); return y+'-'+mo+'-'+da+' '+h+':'+mi+':'+s;"
    return "{ __otterDate: true, hasTime: $HasTimeJs, value: ($DateExprJs), toString() { $toStringBody } }"
}

# D60 Phase 1J. Builds the JS text for `.NET`'s DateTime.AddMonths/AddYears
# clamping algorithm - verified this is what the interpreter's DateAdjust
# case actually relies on (`$current.Value.AddMonths($whole)` /
# `.AddYears($whole)`), and confirmed directly against
# tests/Dates.Tests.ps1's own pinned fixture ("31 January plus one month is
# the end of February, not 3 March"): a plain JS `setMonth`/`setFullYear`
# rollover does NOT clamp this way (Jan 31 + 1 month would silently become
# March 3 in native JS), so this reimplements .NET's exact field-based,
# day-clamping algorithm rather than trusting JS Date's own month rollover.
# AddYears is just AddMonths(years * 12) - .NET's own AddYears is
# documented to behave identically (including clamping Feb 29 down to Feb
# 28 for a non-leap target year), so one function covers both units.
function Get-OtterJsAddMonthsSnippet {
    param([string]$DateJs, [string]$MonthsJs)

    return "(() => { const _d = $DateJs; const _tot = _d.getFullYear() * 12 + _d.getMonth() + ($MonthsJs); const _ny = Math.floor(_tot / 12); const _nm = (((_tot % 12) + 12) % 12); const _dim = new Date(_ny, _nm + 1, 0).getDate(); const _nd = Math.min(_d.getDate(), _dim); return new Date(_ny, _nm, _nd, _d.getHours(), _d.getMinutes(), _d.getSeconds(), _d.getMilliseconds()); })()"
}

# D60 Phase 1J. Shared by DateDifference (statement) and DateDifferenceValue
# (expression) - the exact same computation, verified directly against
# Measure-OtterDateDifference: Year/Month use CALENDAR month arithmetic (not
# averaged days - confirmed via the interpreter's own pinned fixture, 31
# January to 28 February is 0 months, not ~1), Day/Hour/Minute/Second use a
# plain elapsed-time span. Both are truncated toward zero (never rounded),
# signed end-minus-start. Elapsed-time units are computed via epoch-
# millisecond subtraction rather than any local-field manipulation - this
# is intentionally DST-and-timezone-drift-safe: `.NET`'s own
# Day/Hour/Minute/Second span math is pure Ticks subtraction (verified by
# reading Measure-OtterDateDifference - `$to - $from` on two `[datetime]`
# values, then `.TotalDays`/etc.), which never re-derives wall-clock fields
# through a timezone's DST rules either, so epoch-ms subtraction in JS is
# not merely a convenient approximation - it is the same class of
# computation the interpreter itself performs.
function Get-OtterJsDateDifferenceExpression {
    param([string]$UnitJs, [string]$StartJs, [string]$EndJs)

    return "(() => { const _from = $StartJs; const _to = $EndJs; const _unit = $UnitJs; if (_unit === 'Year' || _unit === 'Month') { let _months = (_to.getFullYear() - _from.getFullYear()) * 12 + (_to.getMonth() - _from.getMonth()); if (_months > 0 && _to.getDate() < _from.getDate()) { _months--; } if (_months < 0 && _to.getDate() > _from.getDate()) { _months++; } if (_unit === 'Month') { return _months; } return Math.trunc(_months / 12); } const _spanMs = _to.getTime() - _from.getTime(); if (_unit === 'Day') { return Math.trunc(_spanMs / 86400000); } if (_unit === 'Hour') { return Math.trunc(_spanMs / 3600000); } if (_unit === 'Minute') { return Math.trunc(_spanMs / 60000); } return Math.trunc(_spanMs / 1000); })()"
}

function ConvertTo-OtterJsExpression {
    param([Parameter(Mandatory)][Node]$Expr)

    switch ($Expr.Kind) {
        ([NodeKind]::Literal) {
            $val = $Expr.Value
            if ($null -eq $val) { return 'null' }
            if ($val -is [bool]) { return $(if ($val) { 'true' } else { 'false' }) }
            if ($val -is [double] -or $val -is [int] -or $val -is [long]) { return [string]$val }
            $escaped = [string]$val -replace '\\', '\\' -replace '"', '\"' -replace "`n", '\n' -replace "`r", ''
            return "`"$escaped`""
        }
        ([NodeKind]::Variable) {
            if ($Expr.Name -eq 'empty') { return '""' }
            if ($Expr.Name -eq 'gone') { return 'null' }
            return $Expr.Name
        }
        ([NodeKind]::PropertyAccess) {
            # D60 Phase 1F.2. Same runtime dual dispatch as the Assign-to-
            # PropertyAccess write case - see its comment for why
            # `otterGetElement` truthy/null is a sound stand-in for the
            # interpreter's own dynamic Test-OtterUiResource/Test-OtterObject
            # check. The UI branch is byte-for-byte unchanged from before
            # 1F.2. The thing branch matches the interpreter's PropertyAccess
            # read exactly: THROWS on a missing property (verified: "This
            # thing has no property called ..." - reading is NOT the same
            # rule as writing, which always succeeds) and uses the
            # property's ORIGINAL case, never lowercased.
            #
            # D60 Phase 1J adds a THIRD branch, checked first (matching the
            # interpreter's real precedence - Test-OtterDate runs before
            # Test-OtterUiResource/Test-OtterObject in 'PropertyAccess'):
            # `year of date` / `hour of started` etc. A date's own parts are
            # ORDINARY PropertyAccessExprs, not a separate node (D32.2 - so
            # that `year of book`, book a plain thing, keeps meaning the
            # stored property). Verified directly against the interpreter,
            # including one genuinely surprising fact: matching is CASE-
            # INSENSITIVE ("YEAR of date" and "Year of date" both work) -
            # this falls out of PowerShell's `switch` being case-insensitive
            # by default in Get-OtterDatePart, not a deliberate design
            # choice documented anywhere, but it IS the real observable
            # behavior, so `$prop` (already lowercased, existing variable)
            # is reused for the comparison here too. Hour/minute/second on a
            # date with no time of day throws ("This is a date with no time
            # of day, so it has no <unit>.", unit lowercased - matches
            # Assert-OtterUnitAllowed exactly); an unrecognized part throws
            # using the property's ORIGINAL case ("A date has no part called
            # "<Original>".", verified directly - the error text does NOT
            # lowercase it even though the match itself is case-insensitive).
            $propOriginal = $Expr.Property
            $prop = $propOriginal.ToLowerInvariant()
            $target = $Expr.Target
            $targetName = if ($target -is [VariableExpr]) { $target.Name } else { 'target' }
            $uiBranch = switch ($prop) {
                'text' { "otterGetText('$targetName')" }
                'value' { "otterGetText('$targetName')" }
                'title' { "otterGetTitle('$targetName')" }
                'width' { "otterGetStyle('$targetName', 'width')" }
                'height' { "otterGetStyle('$targetName', 'height')" }
                default { "otterGetProperty('$targetName', '$prop')" }
            }
            $dateBranch = switch ($prop) {
                'year' { "_owner.value.getFullYear()" }
                'month' { "(_owner.value.getMonth() + 1)" }
                'day' { "_owner.value.getDate()" }
                'hour' { "(_owner.hasTime ? _owner.value.getHours() : (() => { throw new Error('This is a date with no time of day, so it has no hour.'); })())" }
                'minute' { "(_owner.hasTime ? _owner.value.getMinutes() : (() => { throw new Error('This is a date with no time of day, so it has no minute.'); })())" }
                'second' { "(_owner.hasTime ? _owner.value.getSeconds() : (() => { throw new Error('This is a date with no time of day, so it has no second.'); })())" }
                default { "(() => { throw new Error('A date has no part called `"$propOriginal`".'); })()" }
            }
            # An inline IIFE, not a named runtime-helper call, to keep this
            # entirely self-contained in this module - same reasoning as
            # Phase 1D-B's `plus` fix (no shared helper added to
            # Otter.Web.psm1's boilerplate).
            return "(otterGetElement('$targetName') ? ($uiBranch) : (() => { const _owner = $targetName; if (_owner && typeof _owner === 'object' && _owner.__otterDate) { return $dateBranch; } if (!_owner || typeof _owner !== 'object' || !_owner.__otterThing) { throw new Error('I can only read properties of a thing, but this is something else.'); } if (!(('$propOriginal') in _owner.props)) { throw new Error('This ' + (_owner.typeName || 'thing') + ' has no property called `"$propOriginal`".'); } return _owner.props['$propOriginal']; })())"
        }
        ([NodeKind]::Math) {
            $left = ConvertTo-OtterJsExpression -Expr $Expr.Left
            $right = ConvertTo-OtterJsExpression -Expr $Expr.Right
            switch ($Expr.Op) {
                ([MathOp]::Add) {
                    # D60 Phase 1D-B. The old check here was STATIC (did the
                    # AST show a literal string, or did the generated JS text
                    # start with a quote?) - wrong whenever a string arrives
                    # through a variable rather than a literal, which is the
                    # common case ("joined is joined plus item" produced
                    # "NaN", not the concatenation the interpreter actually
                    # does). Matches Otter.Interpreter.psm1's real 'Math'
                    # case exactly instead, verified against the interpreter
                    # for every combination before writing this, not assumed:
                    #   - "a" plus "b" -> "ab" (both operands are STRING
                    #     TYPE, so concatenate - unconditionally, even if
                    #     both look numeric: "5" plus "3" concatenates to
                    #     "53", it does NOT add to 8)
                    #   - "5" plus 3 / 5 plus "3" -> 8 (only one side is a
                    #     string, so both sides are coerced to numbers
                    #     instead - a numeric-looking string parses fine)
                    #   - 5 plus 10 -> 15 (plain arithmetic)
                    #   - "a" plus 5 / 5 plus "a" -> throws (a non-numeric
                    #     string fails coercion, matching Assert-OtterNumber)
                    #   - "" or "  " plus 5 -> throws (empty/whitespace-only
                    #     fails coercion too, matching .NET's double.TryParse)
                    #   - true plus 5 -> throws (booleans are explicitly
                    #     rejected as numeric, matching Test-OtterNumeric's
                    #     `if ($Value -is [bool]) { return $false }` - a
                    #     naive Number(true) would silently succeed as 1 in
                    #     JS, which is exactly the kind of gap this phase
                    #     exists to close)
                    # This is a RUNTIME check (typeof, on the actual value),
                    # not a static one - that is the whole fix. An IIFE is
                    # used because this is expression position; no shared
                    # runtime helper was added to keep this change entirely
                    # inside this module (Otter.Web.psm1's boilerplate is
                    # untouched).
                    return "(() => { const _l = $left; const _r = $right; if (typeof _l === 'string' && typeof _r === 'string') { return _l + _r; } const _lOk = typeof _l === 'number' || (typeof _l === 'string' && _l.trim() !== '' && !Number.isNaN(Number(_l))); if (!_lOk) { throw new Error('I expected a number for the left side of this calculation but got ' + JSON.stringify(_l) + '.'); } const _rOk = typeof _r === 'number' || (typeof _r === 'string' && _r.trim() !== '' && !Number.isNaN(Number(_r))); if (!_rOk) { throw new Error('I expected a number for the right side of this calculation but got ' + JSON.stringify(_r) + '.'); } return Number(_l) + Number(_r); })()"
                }
                # Subtract/Multiply/Divide have the SAME underlying gap
                # (Assert-OtterNumber throws on a non-numeric operand in the
                # interpreter; Number(...) here silently produces NaN
                # instead) - confirmed present, deliberately NOT fixed in
                # this commit. Phase 1D-B's scope, per instruction, is `plus`
                # specifically; this is flagged as a separate, still-open
                # finding, not silently folded in here.
                ([MathOp]::Subtract) { return "(Number($left) - Number($right))" }
                ([MathOp]::Multiply) { return "(Number($left) * Number($right))" }
                ([MathOp]::Divide) { return "(Number($left) / Number($right))" }
            }
        }
        ([NodeKind]::Await) {
            $inner = ConvertTo-OtterJsExpression -Expr $Expr.Expression
            return "(await $inner)"
        }
        ([NodeKind]::Comparison) {
            $left = ConvertTo-OtterJsExpression -Expr $Expr.Left
            $right = ConvertTo-OtterJsExpression -Expr $Expr.Right
            # D60 Phase 1J adds a runtime date check ahead of every op,
            # matching the interpreter exactly: Equal/NotEqual use
            # Test-OtterEqual (two dates compare by instant; a date and a
            # NON-date are never equal, not even a date and text that looks
            # like one - verified directly), and the four ordering ops
            # compare by instant ONLY when BOTH sides are dates (D32.6) -
            # otherwise the interpreter's Assert-OtterNumber runs and throws
            # on whichever side is not a number, and a date is deliberately
            # never numeric (Test-OtterNumeric explicitly rejects it). Every
            # other type pair is completely UNCHANGED - plain `===`/`<`/etc.
            # still runs exactly as before 1J when neither side is a date,
            # so this does not touch the pre-existing, separately-tracked
            # gap where JS's own `===` already diverges from Test-OtterEqual
            # for lists (reference vs value equality) - narrowly scoped to
            # dates, the thing this phase is actually about. One documented,
            # narrow approximation: if ONE side is a date and the OTHER side
            # is some third bad type (neither a date nor a number), this
            # reports the date side as the failing operand rather than
            # exactly replicating the interpreter's strict left-then-right
            # Assert-OtterNumber check order - a date is unconditionally
            # not a number either way, so the thrown error is still correct
            # in substance, just not guaranteed to name the same side in
            # this genuinely rare double-bad-type edge case.
            $dateGuard = "const _lD = $left !== null && typeof ($left) === 'object' && ($left).__otterDate === true; const _rD = $right !== null && typeof ($right) === 'object' && ($right).__otterDate === true;"
            switch ($Expr.Op) {
                ([CompareOp]::Equal) {
                    return "(() => { $dateGuard if (_lD || _rD) { return (_lD && _rD) ? (($left).value.getTime() === ($right).value.getTime()) : false; } return ($left === $right); })()"
                }
                ([CompareOp]::NotEqual) {
                    return "(() => { $dateGuard if (_lD || _rD) { return !((_lD && _rD) && (($left).value.getTime() === ($right).value.getTime())); } return ($left !== $right); })()"
                }
                ([CompareOp]::AtLeast) {
                    return "(() => { $dateGuard if (_lD || _rD) { if (!_lD) { throw new Error('I expected a number for the left side of this comparison but got ' + ($left) + '.'); } if (!_rD) { throw new Error('I expected a number for the right side of this comparison but got ' + ($right) + '.'); } return (($left).value.getTime() >= ($right).value.getTime()); } return ($left >= $right); })()"
                }
                ([CompareOp]::AtMost) {
                    return "(() => { $dateGuard if (_lD || _rD) { if (!_lD) { throw new Error('I expected a number for the left side of this comparison but got ' + ($left) + '.'); } if (!_rD) { throw new Error('I expected a number for the right side of this comparison but got ' + ($right) + '.'); } return (($left).value.getTime() <= ($right).value.getTime()); } return ($left <= $right); })()"
                }
                ([CompareOp]::GreaterThan) {
                    return "(() => { $dateGuard if (_lD || _rD) { if (!_lD) { throw new Error('I expected a number for the left side of this comparison but got ' + ($left) + '.'); } if (!_rD) { throw new Error('I expected a number for the right side of this comparison but got ' + ($right) + '.'); } return (($left).value.getTime() > ($right).value.getTime()); } return ($left > $right); })()"
                }
                ([CompareOp]::LessThan) {
                    return "(() => { $dateGuard if (_lD || _rD) { if (!_lD) { throw new Error('I expected a number for the left side of this comparison but got ' + ($left) + '.'); } if (!_rD) { throw new Error('I expected a number for the right side of this comparison but got ' + ($right) + '.'); } return (($left).value.getTime() < ($right).value.getTime()); } return ($left < $right); })()"
                }
            }
        }
        ([NodeKind]::Logical) {
            $left = ConvertTo-OtterJsExpression -Expr $Expr.Left
            $right = ConvertTo-OtterJsExpression -Expr $Expr.Right
            switch ($Expr.Op) {
                ([LogicalOp]::And) { return "($left && $right)" }
                ([LogicalOp]::Or) { return "($left || $right)" }
            }
        }
        ([NodeKind]::Not) {
            $innerNode = if ($Expr.Operand) { $Expr.Operand } else { $Expr.Expression }
            $inner = ConvertTo-OtterJsExpression -Expr $innerNode
            return "(!$inner)"
        }
        ([NodeKind]::Contains) {
            $collection = ConvertTo-OtterJsExpression -Expr $Expr.Collection
            $item = ConvertTo-OtterJsExpression -Expr $Expr.Item
            return "($collection && $collection.includes ? $collection.includes($item) : false)"
        }
        ([NodeKind]::TextMatch) {
            # D60 Phase 1D-A. Matches Otter.Interpreter.psm1's 'TextMatch'
            # case: both operands go through Format-OtterValue first (so
            # this works on any formattable value, not just string
            # literals), comparison is ordinal/case-sensitive (confirmed:
            # "jeff" does not match a subject starting with "Jeff"), result
            # is a plain boolean. String(...) stands in for Format-
            # OtterValue here - full parity (list-joining, Otter's exact
            # number formatting) is not attempted, matching-string use is
            # the case this was verified against.
            $subjectJs = ConvertTo-OtterJsExpression -Expr $Expr.Subject
            $valueJs = ConvertTo-OtterJsExpression -Expr $Expr.Value
            $method = if ($Expr.Match.ToString() -eq 'StartsWith') { 'startsWith' } else { 'endsWith' }
            return "String($subjectJs).$method(String($valueJs))"
        }
        ([NodeKind]::OfOperation) {
            # D60 Phase 1D-A gave Uppercase/Lowercase. Phase 1E completes
            # the NodeKind: Length is polymorphic (works on strings AND
            # lists - confirmed against the interpreter, dispatches on
            # Array.isArray the same way), First/Last are LIST-ONLY (the
            # interpreter throws on a string subject - not replicated here,
            # matching this compiler's established convention of falling
            # through rather than throwing for a wrong-type read in
            # expression position) and return null/gone for an empty list,
            # exactly like the interpreter's `First`/`Last` returning `$null`
            # rather than erroring on an empty list.
            $subjectJs = ConvertTo-OtterJsExpression -Expr $Expr.Subject
            switch ($Expr.Operation.ToString()) {
                'Uppercase' { return "String($subjectJs).toUpperCase()" }
                'Lowercase' { return "String($subjectJs).toLowerCase()" }
                'Length' { return "(($subjectJs).length)" }
                'First' { return "(Array.isArray($subjectJs) && ($subjectJs).length > 0 ? ($subjectJs)[0] : null)" }
                'Last' { return "(Array.isArray($subjectJs) && ($subjectJs).length > 0 ? ($subjectJs)[($subjectJs).length - 1] : null)" }
                default { return "null" }
            }
        }
        ([NodeKind]::Clock) {
            # D60 Phase 1J. `today` / `now` - matches New-OtterToday/
            # New-OtterNow: `today` pins to LOCAL midnight (HasTime false -
            # "a date with no time of day"), `now` keeps the current LOCAL
            # wall-clock instant (HasTime true). Both read the interpreter's
            # own `[datetime]::Now` (LOCAL, not UTC, verified by reading the
            # source) - JS's `new Date()` is local-clock by construction
            # too, so no explicit timezone conversion is needed for this to
            # line up; the two runtimes' clocks are simply never expected to
            # be byte-identical (different processes, potentially different
            # machines), same as any other "current time" read would be.
            $isToday = $Expr.Clock.ToString() -eq 'Today'
            if ($isToday) {
                $dateExpr = "(() => { const _n = new Date(); return new Date(_n.getFullYear(), _n.getMonth(), _n.getDate(), 0, 0, 0, 0); })()"
                return (Get-OtterJsDateConstructor -DateExprJs $dateExpr -HasTimeJs 'false')
            }
            return (Get-OtterJsDateConstructor -DateExprJs 'new Date()' -HasTimeJs 'true')
        }
        ([NodeKind]::DateDifferenceValue) {
            # D60 Phase 1J (D42). The expression form of `days between X and
            # Y` - a genuine value, usable anywhere an expression is legal
            # (`waiting is days between a and b`, inside `say`, inside a
            # condition), matching the interpreter's DateDifferenceExpr
            # exactly: the SAME computation as the legacy statement form
            # (see Get-OtterJsDateDifferenceExpression), including throwing
            # if either operand is not a date - verified directly against
            # the interpreter (Assert-OtterDateOperands runs before the
            # calculation in both the statement and expression cases).
            $startJs = ConvertTo-OtterJsExpression -Expr $Expr.Start
            $endJs = ConvertTo-OtterJsExpression -Expr $Expr.End
            $unit = $Expr.Unit.ToString()
            $diffJs = Get-OtterJsDateDifferenceExpression -UnitJs "'$unit'" -StartJs '_s.value' -EndJs '_e.value'
            return "(() => { const _s = $startJs; const _e = $endJs; const _sOk = _s && typeof _s === 'object' && _s.__otterDate; const _eOk = _e && typeof _e === 'object' && _e.__otterDate; if (!_sOk) { throw new Error('I can only measure time between two dates, but the first one is something else.'); } if (!_eOk) { throw new Error('I can only measure time between two dates, but the second one is something else.'); } return $diffJs; })()"
        }
        ([NodeKind]::Call) {
            $argsJs = @(foreach ($a in $Expr.Arguments) { ConvertTo-OtterJsExpression -Expr $a })
            return "$($Expr.Name)($($argsJs -join ', '))"
        }
        ([NodeKind]::FileExists) {
            $pathJs = ConvertTo-OtterJsExpression -Expr $Expr.Path
            return "(await otterFileExists($pathJs))"
        }
        default {
            return "null"
        }
    }
}

function ConvertTo-OtterJsStatement {
    param(
        [Parameter(Mandatory)][Node]$Stmt,
        [int]$Indent = 2,

        # D60 Phase 1F. Null/omitted everywhere except inside a function
        # body - top-level, event-handler, and loop-body compilation all
        # keep their existing behavior of writing plain variables to
        # window.<name> (or otterState), unchanged. Only FunctionDef's own
        # compilation populates this with the set of names that must be
        # genuinely LOCAL to that function (parameters plus any name
        # assigned via `is` inside the body) - verified against the
        # interpreter that a function's local variables are discarded when
        # it returns (Environment rooted fresh at $script:GlobalEnvironment
        # per call), so `total is ...` inside a function must become a
        # real JS `let`, never a window write, or it would leak.
        [System.Collections.Generic.HashSet[string]]$LocalNames = $null,

        # D60 Phase 1F.1. Null everywhere except when compiling a function
        # body (threaded the same way as -LocalNames). The set of names
        # with a top-level binding anywhere in the whole program - see
        # Get-OtterJsTopLevelGlobalNames. FunctionDef consults this once,
        # when first building its own -LocalNames set, to decide which
        # Set-style bindings (Assign/MathInto/CallStatement) inside the
        # function must be excluded from LocalNames because they mutate a
        # real pre-existing global instead of shadowing it locally.
        [System.Collections.Generic.HashSet[string]]$KnownGlobals = $null
    )

    $pad = '  ' * $Indent

    switch ($Stmt.Kind) {
        ([NodeKind]::Await) {
            $inner = ConvertTo-OtterJsExpression -Expr $Stmt.Expression
            return "${pad}await $inner;"
        }
        ([NodeKind]::Assign) {
            if ($Stmt.Target -is [PropertyAccessExpr]) {
                # D60 Phase 1F.2. Runtime dual dispatch, not a compile-time
                # name-list check: a UI resource is ALWAYS accessed by DOM-
                # ID lookup in this compiler (verified: no UI resource ever
                # gets a bound window.<name>/local value anywhere in the
                # existing codegen), so `otterGetElement(name)` returning a
                # real element vs null is exactly the same distinction the
                # interpreter's own Test-OtterUiResource/Test-OtterObject
                # dynamic check makes - just checked a different way. The
                # UI branch below is byte-for-byte the pre-1F.2 behavior
                # (same property special-cases, same lowercased name) - a
                # plain thing branch is added alongside it, not replacing
                # it. Property WRITE on a thing always succeeds and creates
                # the property if it is missing (matches WriteProperty's
                # own unconditional behavior - verified, not the same rule
                # as reading, which throws on a missing name) - and the
                # property's ORIGINAL case is used for the thing branch,
                # never lowercased, matching the interpreter's Ordinal
                # (case-sensitive) property-name comparer exactly; only the
                # UI-property dispatch switch below is case-insensitive.
                $propOriginal = $Stmt.Target.Property
                $prop = $propOriginal.ToLowerInvariant()
                $target = $Stmt.Target.Target
                $targetName = if ($target -is [VariableExpr]) { $target.Name } else { 'target' }
                $valExpr = ConvertTo-OtterJsExpression -Expr $Stmt.Value
                $uiBranch = switch ($prop) {
                    'text' { "otterSetText('$targetName', $valExpr);" }
                    'value' { "otterSetText('$targetName', $valExpr);" }
                    'title' { "otterSetTitle('$targetName', $valExpr);" }
                    'background' { "otterSetStyle('$targetName', 'backgroundColor', $valExpr);" }
                    'foreground' { "otterSetStyle('$targetName', 'color', $valExpr);" }
                    'width' { "otterSetStyle('$targetName', 'width', typeof ($valExpr) === 'number' ? ($valExpr + 'px') : $valExpr);" }
                    'height' { "otterSetStyle('$targetName', 'height', typeof ($valExpr) === 'number' ? ($valExpr + 'px') : $valExpr);" }
                    default { "otterSetProperty('$targetName', '$prop', $valExpr);" }
                }
                $lines = [System.Collections.Generic.List[string]]::new()
                $inner = '  ' * ($Indent + 1)
                $lines.Add("${pad}{")
                $lines.Add("${inner}const _el = otterGetElement('$targetName');")
                $lines.Add("${inner}if (_el) { $uiBranch }")
                $lines.Add("${inner}else {")
                $lines.Add("${inner}  const _owner = $targetName;")
                $lines.Add("${inner}  if (!_owner || typeof _owner !== 'object' || !_owner.__otterThing) { throw new Error('I can only set properties on a thing, but this is something else.'); }")
                $lines.Add("${inner}  if (!(('$propOriginal') in _owner.props)) { _owner.order.push('$propOriginal'); }")
                $lines.Add("${inner}  _owner.props['$propOriginal'] = $valExpr;")
                $lines.Add("${inner}}")
                $lines.Add("${pad}}")
                return ($lines -join "`n")
            }
            $varName = if ($Stmt.Target -is [VariableExpr]) { $Stmt.Target.Name } else { [string]$Stmt.Target }
            $valExpr = ConvertTo-OtterJsExpression -Expr $Stmt.Value
            if ($LocalNames -and $LocalNames.Contains($varName)) {
                # Inside a function, and this name is genuinely local
                # (a parameter, or first assigned inside this function's own
                # body) - a real JS local write, never window, so it is
                # discarded when the function returns, matching the
                # interpreter's fresh-per-call environment exactly.
                return "${pad}$varName = $valExpr;"
            }
            return "${pad}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$varName' in otterState)) { otterSetState('$varName', $valExpr); } else { window.$varName = $valExpr; }"
        }
        ([NodeKind]::MathInto) {
            # D60 Phase 1F. Found while verifying recursion (Jeff's own
            # factorial test case uses `n minus 1 make sub`) - a completely
            # separate NodeKind from Assign, for the "X op Y make Z" surface
            # form, but Otter.Interpreter.psm1's 'MathInto' case is
            # IDENTICAL to Assign's plain-variable path: evaluate the
            # expression, `Environment.Set(Target, value)` - same method,
            # same semantics, different syntax. Missing this NodeKind
            # entirely (it was never in scope for any earlier phase) meant
            # `n minus 1 make sub` compiled to nothing at all (silent
            # Statement-default no-op), leaving `sub` truly undeclared -
            # confirmed via real JS execution: ReferenceError, not a wrong
            # value. Reuses Assign's exact write logic, including the same
            # LocalNames-aware local-vs-window choice.
            $varName = $Stmt.Target
            $valExpr = ConvertTo-OtterJsExpression -Expr $Stmt.Expression
            if ($LocalNames -and $LocalNames.Contains($varName)) {
                return "${pad}$varName = $valExpr;"
            }
            return "${pad}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$varName' in otterState)) { otterSetState('$varName', $valExpr); } else { window.$varName = $valExpr; }"
        }
        ([NodeKind]::Say) {
            $parts = foreach ($p in $Stmt.Parts) { ConvertTo-OtterJsExpression -Expr $p }
            $joined = $parts -join ' + " " + '
            return "${pad}otterSay($joined);"
        }
        ([NodeKind]::Ask) {
            # D60 consolidated-audit release blocker. `ask "..." and call
            # it x` (D6) - matches ConvertFrom-OtterInput exactly: trim,
            # exactly "true"/"false" (case-sensitive, matching the
            # interpreter's literal string comparison) becomes a boolean,
            # else a successful numeric parse becomes a number, else the
            # ORIGINAL untrimmed text is kept (leading spaces may be
            # deliberate in text, per the interpreter's own comment).
            # Unlike ReadFile/HttpGet/GetFiles, this needs NO host-bridge
            # hook and NO async/await at all: `window.prompt()` is a real,
            # always-available, SYNCHRONOUS browser built-in - the same
            # reason D62 gave for treating Studio's terminal-profile UI as
            # in-language-reach rather than a genuine host boundary. This
            # is deliberately NOT wired through a required external hook
            # the way file/process access is, because the capability
            # genuinely exists in every browser, no bridge required.
            # `window.prompt` returning `null` (the user pressed Cancel -
            # a real browser affordance with no console equivalent to
            # match against, since a console Ctrl+C terminates the
            # process rather than returning a value) is treated as an
            # empty string, a reasonable, documented, browser-native
            # analog rather than an attempt to replicate behavior no
            # console-based interpreter run could ever exercise.
            $promptJs = ConvertTo-OtterJsExpression -Expr $Stmt.Prompt
            $target = $Stmt.Name
            $coerced = "(() => { const _raw = window.prompt(String($promptJs)); const _text = (_raw === null) ? '' : _raw; const _trimmed = _text.trim(); if (_trimmed === 'true') { return true; } if (_trimmed === 'false') { return false; } if (_trimmed.length > 0 && !Number.isNaN(Number(_trimmed))) { return Number(_trimmed); } return _text; })()"
            if ($LocalNames -and $LocalNames.Contains($target)) {
                return "${pad}$target = $coerced;"
            }
            return "${pad}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', $coerced); } else { window.$target = $coerced; }"
        }
        ([NodeKind]::If) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $first = $true
            foreach ($branch in $Stmt.Branches) {
                $cond = ConvertTo-OtterJsExpression -Expr $branch.Condition
                $keyword = if ($first) { "if ($cond)" } else { "else if ($cond)" }
                $lines.Add("${pad}$keyword {")
                foreach ($s in $branch.Body) {
                    $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 1) -LocalNames $LocalNames))
                }
                $lines.Add("${pad}}")
                $first = $false
            }
            if ($Stmt.ElseBody -and $Stmt.ElseBody.Count -gt 0) {
                $lines.Add("${pad}else {")
                foreach ($s in $Stmt.ElseBody) {
                    $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 1) -LocalNames $LocalNames))
                }
                $lines.Add("${pad}}")
            }
            return ($lines -join "`n")
        }
        ([NodeKind]::While) {
            $cond = ConvertTo-OtterJsExpression -Expr $Stmt.Condition
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("${pad}while ($cond) {")
            foreach ($s in $Stmt.Body) {
                $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 1) -LocalNames $LocalNames))
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::CountLoop) {
            # D60 Phase 1B. Matches Otter.Interpreter.psm1's 'CountLoop' case
            # exactly (verified against the real interpreter, not assumed
            # from JS `for`-loop habits):
            #   - both ends inclusive
            #   - descending ranges are valid ("count from 10 to 1" counts
            #     down); direction is decided once, from from<=to
            #   - From/To are evaluated exactly once, before the loop starts
            #     (bound in _from/_to below) - a mutating bound expression
            #     does not change an already-running loop
            #   - the loop variable has NO separate per-iteration scope: it
            #     is written into the same place a plain Assign would write
            #     it (otterState if reactive, else `window.<name>`), so it
            #     is still readable - and last-writer-wins shared with any
            #     nested loop reusing the same name - after the loop ends,
            #     matching SetLocal's real behavior (writes into the
            #     CURRENT environment, never a child scope)
            #   - the loop's own stepping counter (_n, below) is internal
            #     and is never re-read from the visible variable, so the
            #     body reassigning the visible variable does not affect
            #     iteration - matching the interpreter's PowerShell-local
            #     $n, which the same is true of
            #   - `stop` needs no special case: it parses to a bare Return
            #     node (verified via -DebugAst), and the existing Return
            #     case's `return;` already exits the whole enclosing JS
            #     function from inside a `for`, exactly matching D37
            # Non-numeric bounds are coerced via Number(), the same silent-
            # coercion convention the Math case already uses - not a new
            # gap introduced here, the same one already shipped.
            $fromJs = ConvertTo-OtterJsExpression -Expr $Stmt.From
            $toJs = ConvertTo-OtterJsExpression -Expr $Stmt.To
            $varName = $Stmt.VariableName
            $inner = '  ' * ($Indent + 1)
            $bodyIndent = '  ' * ($Indent + 2)
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _from = Number($fromJs);")
            $lines.Add("${inner}const _to = Number($toJs);")
            $lines.Add("${inner}const _step = _from <= _to ? 1 : -1;")
            $lines.Add("${inner}for (let _n = _from; (_step > 0 && _n <= _to) || (_step < 0 && _n >= _to); _n += _step) {")
            if ($LocalNames -and $LocalNames.Contains($varName)) {
                # D60 Phase 1F.1. Inside a function, CountLoop's SetLocal
                # ALWAYS writes to the CURRENT (function-local) scope,
                # never climbing to mutate a same-named outer/global
                # variable even if one exists - verified directly, and
                # different from Assign/MathInto's Set (which climbs and
                # mutates an existing global). FunctionDef always adds
                # CountLoop/ForEach variable names to LocalNames
                # unconditionally for exactly this reason - see its case
                # for the full explanation.
                $lines.Add("${bodyIndent}$varName = _n;")
            } else {
                $lines.Add("${bodyIndent}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$varName' in otterState)) { otterSetState('$varName', _n); } else { window.$varName = _n; }")
            }
            foreach ($s in $Stmt.Body) {
                $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 2) -LocalNames $LocalNames))
            }
            $lines.Add("${inner}}")
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::ListDef) {
            # D60 Phase 1C. Matches Otter.Interpreter.psm1's 'ListDef' case
            # exactly (verified against the real interpreter):
            #   - each item expression is evaluated exactly once, in order
            #   - duplicates are preserved (no dedup)
            #   - mixed element types are allowed
            #   - a literal empty list ("items are" with nothing indented
            #     under it) is already a PARSE-time error today (confirmed:
            #     Read-OtterListItems requires at least one indented item),
            #     so there is no empty-list-literal case to emit here
            #   - the parser only allows Read-OtterValue forms as items
            #     (literal, variable, property-access - confirmed: a full
            #     expression like `x plus 1` is a syntax error), so every
            #     item Otter can hand this case is something
            #     ConvertTo-OtterJsExpression already knows how to compile
            #   - THE NON-OBVIOUS ONE, verified directly: if an item
            #     expression evaluates to a LIST (e.g. a bare variable
            #     already holding a list), its elements are SPLICED into
            #     the new list rather than nested as one element - `outer
            #     are / inner / inner / .` produces a 4-element flat list,
            #     not a 2-element list of lists (length of outer is 4,
            #     first of outer is 1, not [1,2]). This falls out of
            #     PowerShell's own `+=` auto-enumerating an array RHS in
            #     the interpreter, intentional or not - it is current
            #     behavior, so it is preserved here via Array.isArray.
            #   - list assignment/sharing (`listB is listA` sharing the
            #     same underlying list, so mutating one mutates the other)
            #     needs no special handling: JS arrays are reference types
            #     by default, so a plain Assign of one list variable to
            #     another already behaves identically with zero extra code.
            $varName = $Stmt.Name
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("${pad}{")
            $itemsInner = '  ' * ($Indent + 1)
            $lines.Add("${itemsInner}const _items = [];")
            $itemIndex = 0
            foreach ($item in $Stmt.Items) {
                $itemJs = ConvertTo-OtterJsExpression -Expr $item
                $tmp = "_v$itemIndex"
                $lines.Add("${itemsInner}const $tmp = $itemJs;")
                $lines.Add("${itemsInner}if (Array.isArray($tmp)) { _items.push(...$tmp); } else { _items.push($tmp); }")
                $itemIndex++
            }
            if ($LocalNames -and $LocalNames.Contains($varName)) {
                $lines.Add("${itemsInner}$varName = _items;")
            } else {
                $lines.Add("${itemsInner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$varName' in otterState)) { otterSetState('$varName', _items); } else { window.$varName = _items; }")
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::TypeDef) {
            # D60 consolidated-audit release blocker. `a Person has
            # / name / age / .` - matches the interpreter's 'TypeDef'
            # case exactly: `Environment.Set($TypeName, [OtterType]::new(
            # $TypeName, $FieldNames))`, a genuine Set-style binding of a
            # real value under the type's own name, not a compile-time-
            # only declaration - `ObjectDef`'s case above looks this up
            # DYNAMICALLY at runtime (see its comment), so the type must
            # be a real, tagged runtime value here too, not merely
            # tracked in this compiler's own bookkeeping.
            $typeName = $Stmt.TypeName
            $fieldsJs = (@($Stmt.FieldNames | ForEach-Object { "'$_'" })) -join ', '
            $typeObj = "{ __otterType: true, typeName: '$typeName', fieldNames: [$fieldsJs] }"
            if ($LocalNames -and $LocalNames.Contains($typeName)) {
                return "${pad}$typeName = $typeObj;"
            }
            return "${pad}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$typeName' in otterState)) { otterSetState('$typeName', $typeObj); } else { window.$typeName = $typeObj; }"
        }
        ([NodeKind]::ObjectDef) {
            # D60 Phase 1F.2, extended by the consolidated-audit release-
            # blocker pass. `name is a thing / prop is val / .` AND
            # `jeff is a Person` (a custom declared type) share this one
            # NodeKind - `$Stmt.TypeName` is a compile-time-known string
            # either way ("thing" or "Person"), so the object's own
            # `typeName` field now carries whatever was actually declared,
            # not a hardcoded literal "thing". When TypeName is not
            # literally "thing", this matches New-OtterObjectValue's
            # SEPARATE pre-population path exactly: verified directly
            # against the interpreter that `$Environment.Get($TypeName)`
            # is a genuinely DYNAMIC, order-dependent lookup (a `TypeDef`
            # that has not executed yet - e.g. sitting inside a branch
            # that never ran - means the type simply is not there, and
            # pre-population is silently skipped, not an error) - so this
            # is a runtime check here too, not a static one resolved from
            # reading every `TypeDef` in the program ahead of time, even
            # though in practice `TypeDef`'s shape is always static. See
            # the `TypeDef` case for how `$TypeName` becomes a real,
            # tagged runtime value. Every declared field is pre-populated
            # to `null` (`gone`) BEFORE the object literal's own explicit
            # properties are applied - an explicit property with the same
            # name then overwrites the `gone` default without duplicating
            # its `order` entry (matches `WriteProperty`'s own
            # `if (-not $this.Properties.ContainsKey($name))` guard on the
            # ORDER list specifically, not a guard on the write itself -
            # replicated in the property loop below, not just in
            # pre-population, since running the literal body twice with
            # the same name inside one `is a thing` block would hit this
            # too).
            #
            # Also NOT implemented, deliberately: `has` used against an
            # EXISTING plain thing. Verified directly this throws in the
            # interpreter ("Otter will not replace existing a thing called
            # ... with a new thing") - both the construct and reconfigure
            # forms parse to the same ObjectDef node, disambiguated at
            # runtime by whether the name already exists. This compiler
            # does not currently distinguish the two either - a second
            # `is a thing`/`has` targeting an already-existing plain name
            # would silently construct a fresh object here rather than
            # throwing the interpreter's protective error. Documented, not
            # silently missed - Otter.Web.psm1's own top-level scan only
            # diverts UI-kind ObjectDefStmts elsewhere, so every ObjectDef
            # NodeKind reaching this case is a "thing" by construction
            # today, and re-use-of-an-existing-name is not exercised by any
            # current verification case.
            #
            # Representation: a plain JS object tagged `__otterThing: true`
            # (so PropertyAccess/property-Assign can tell it apart from a
            # UI resource at runtime - see those cases), holding `props`
            # (the actual property values, case-sensitive JS object keys,
            # matching the interpreter's Ordinal-comparer hashtable exactly
            # since JS object keys are always compared by exact string
            # identity) and `order` (insertion order, matching
            # OtterObject.PropertyNames() - JS preserves insertion order
            # for non-integer-like string keys natively, so this is mostly
            # redundant with `props`' own key order today, kept explicit
            # for parity/future use rather than relied upon implicitly).
            $varName = $Stmt.Name
            $typeName = $Stmt.TypeName
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _props = {};")
            $lines.Add("${inner}const _order = [];")
            if ($typeName -ne 'thing') {
                $lines.Add("${inner}if (typeof $typeName !== 'undefined' && $typeName && typeof $typeName === 'object' && $typeName.__otterType) { for (const _f of $typeName.fieldNames) { if (!(_f in _props)) { _order.push(_f); } _props[_f] = null; } }")
            }
            foreach ($property in $Stmt.Properties) {
                if ($property.Kind -eq [NodeKind]::Assign -and $property.Target -is [VariableExpr]) {
                    $propName = $property.Target.Name
                    $propValJs = ConvertTo-OtterJsExpression -Expr $property.Value
                    $lines.Add("${inner}if (!(('$propName') in _props)) { _order.push('$propName'); } _props['$propName'] = $propValJs;")
                }
            }
            $lines.Add("${inner}const _thing = { __otterThing: true, typeName: '$typeName', props: _props, order: _order };")
            if ($LocalNames -and $LocalNames.Contains($varName)) {
                $lines.Add("${inner}$varName = _thing;")
            } else {
                $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$varName' in otterState)) { otterSetState('$varName', _thing); } else { window.$varName = _thing; }")
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::Sort) {
            # D60 Phase 1E. Matches Otter.Interpreter.psm1's 'Sort' case:
            # mutates the SAME list object in place (JS's Array.prototype
            # .sort() already mutates in place, matching this with zero
            # extra reference-juggling). Comparator matches the interpreter
            # exactly, verified directly, not assumed: numeric compare when
            # BOTH sides parse as numbers, otherwise ordinal string compare
            # (confirmed: sorting ["banana","Apple","cherry"] gives
            # "Apple, banana, cherry" - ordinal, not case-insensitive, since
            # uppercase 'A' sorts before lowercase 'b').
            $target = $Stmt.Target
            return "${pad}$target.sort((_a, _b) => { const _an = (typeof _a === 'number') || (typeof _a === 'string' && _a.trim() !== '' && !Number.isNaN(Number(_a))); const _bn = (typeof _b === 'number') || (typeof _b === 'string' && _b.trim() !== '' && !Number.isNaN(Number(_b))); if (_an && _bn) { return Number(_a) - Number(_b); } return String(_a) < String(_b) ? -1 : (String(_a) > String(_b) ? 1 : 0); });"
        }
        ([NodeKind]::Reverse) {
            # D60 Phase 1E. Array.prototype.reverse() mutates in place,
            # matching the interpreter's List.Reverse() exactly.
            $target = $Stmt.Target
            return "${pad}$target.reverse();"
        }
        ([NodeKind]::Join) {
            # D60 Phase 1E. Matches Otter.Interpreter.psm1's 'Join' case:
            # each item is formatted before joining (String(...) stands in
            # for Format-OtterValue, same approximation already used
            # elsewhere in this module). The interpreter throws if Subject
            # is not a list; not replicated here as a throw, matching this
            # module's established silent-fallback convention for a wrong-
            # type operand in a statement that isn't `plus` (Array.isArray
            # ? ... : String(...) falls back to treating a non-list as a
            # single one-item join rather than crashing).
            $subjectJs = ConvertTo-OtterJsExpression -Expr $Stmt.Subject
            $separatorJs = ConvertTo-OtterJsExpression -Expr $Stmt.Separator
            $target = $Stmt.Target
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _subj = $subjectJs;")
            $lines.Add("${inner}const _sep = String($separatorJs);")
            $lines.Add("${inner}const _joined = Array.isArray(_subj) ? _subj.map((_x) => String(_x)).join(_sep) : String(_subj);")
            if ($LocalNames -and $LocalNames.Contains($target)) {
                $lines.Add("${inner}$target = _joined;")
            } else {
                $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _joined); } else { window.$target = _joined; }")
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::Find) {
            # D60 Phase 1E. Matches Otter.Interpreter.psm1's 'Find' case -
            # including the ONE THING THAT MAKES IT DIFFERENT FROM COUNTLOOP
            # /FOREACH, verified directly, not assumed: Find's item name is
            # bound in a genuinely separate child scope (a real `new
            # OtterEnvironment(Environment)`) that is discarded once the
            # search ends - it does NOT leak into or overwrite an outer
            # variable of the same name, unlike CountLoop/ForEach's
            # SetLocal-on-the-current-environment (confirmed: an outer
            # `item is "outer-value"` survives a `find item in nums where
            # item is 2 into result` completely unchanged). A JS `for`
            # loop's own `let` binding is naturally block-scoped the same
            # way, so no window/otterState write is used for the item
            # variable here - unlike every other loop construct in this
            # file. Returns the first match, or null/gone if none (matches
            # the interpreter returning $null, never throwing, on no match).
            $collJs = ConvertTo-OtterJsExpression -Expr $Stmt.Collection
            $itemName = $Stmt.ItemName
            $conditionJs = ConvertTo-OtterJsExpression -Expr $Stmt.Condition
            $target = $Stmt.Target
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}let _found = null;")
            $lines.Add("${inner}for (const $itemName of ($collJs || [])) {")
            $lines.Add("${inner}  if ($conditionJs) { _found = $itemName; break; }")
            $lines.Add("${inner}}")
            $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _found); } else { window.$target = _found; }")
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::AddTo) {
            # D60 Phase 1E. Matches Invoke-OtterAddTo exactly: `add X to Y`
            # dispatches on Y's RUNTIME TYPE (D12) - a list gets X pushed
            # onto it, a number gets X added to it using the SAME string/
            # number coercion-or-throw rules `plus` already has (Phase
            # 1D-B) - a non-list, non-numeric target throws, matching the
            # interpreter's "I can only add to a number or a list" error.
            $target = $Stmt.Target
            $amountJs = ConvertTo-OtterJsExpression -Expr $Stmt.Amount
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _amt = $amountJs;")
            $lines.Add("${inner}if (Array.isArray($target)) { $target.push(_amt); }")
            $lines.Add("${inner}else if (typeof $target === 'number' || (typeof $target === 'string' && $target.trim() !== '' && !Number.isNaN(Number($target)))) {")
            $lines.Add("${inner}  const _aOk = typeof _amt === 'number' || (typeof _amt === 'string' && _amt.trim() !== '' && !Number.isNaN(Number(_amt)));")
            $lines.Add("${inner}  if (!_aOk) { throw new Error('I expected a number for the amount to add to `"$target`"' + ' but got ' + JSON.stringify(_amt) + '.'); }")
            $lines.Add("${inner}  const _sum = Number($target) + Number(_amt);")
            if ($LocalNames -and $LocalNames.Contains($target)) {
                $lines.Add("${inner}  $target = _sum;")
            } else {
                $lines.Add("${inner}  if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _sum); } else { window.$target = _sum; }")
            }
            $lines.Add("${inner}}")
            $lines.Add("${inner}else { throw new Error('I can only add to a number or a list, but `"$target`" holds something else.'); }")
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::RemoveFrom) {
            # D60 Phase 1E. Matches Invoke-OtterRemoveFrom exactly: same
            # dual dispatch as AddTo. For a list, removes only the FIRST
            # matching item (by value equality - === stands in for
            # Test-OtterEqual's structural/identity rules, a reasonable
            # approximation for the primitives lists actually hold today);
            # removing an absent item is a silent no-op, not an error
            # (confirmed against the interpreter). For a number, subtracts,
            # with the same coercion-or-throw as AddTo/plus.
            $target = $Stmt.Target
            $amountJs = ConvertTo-OtterJsExpression -Expr $Stmt.Amount
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _amt = $amountJs;")
            $lines.Add("${inner}if (Array.isArray($target)) { const _idx = $target.indexOf(_amt); if (_idx !== -1) { $target.splice(_idx, 1); } }")
            $lines.Add("${inner}else if (typeof $target === 'number' || (typeof $target === 'string' && $target.trim() !== '' && !Number.isNaN(Number($target)))) {")
            $lines.Add("${inner}  const _aOk = typeof _amt === 'number' || (typeof _amt === 'string' && _amt.trim() !== '' && !Number.isNaN(Number(_amt)));")
            $lines.Add("${inner}  if (!_aOk) { throw new Error('I expected a number for the amount to remove from `"$target`"' + ' but got ' + JSON.stringify(_amt) + '.'); }")
            $lines.Add("${inner}  const _diff = Number($target) - Number(_amt);")
            if ($LocalNames -and $LocalNames.Contains($target)) {
                $lines.Add("${inner}  $target = _diff;")
            } else {
                $lines.Add("${inner}  if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _diff); } else { window.$target = _diff; }")
            }
            $lines.Add("${inner}}")
            $lines.Add("${inner}else { throw new Error('I can only remove from a number or a list, but `"$target`" holds something else.'); }")
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::Repeat) {
            $count = ConvertTo-OtterJsExpression -Expr $Stmt.Count
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("${pad}for (let _i = 0; _i < $count; _i++) {")
            foreach ($s in $Stmt.Body) {
                $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 1) -LocalNames $LocalNames))
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::ForEach) {
            # D60 Phase 1F.1. Rewritten from a bare `for (const x of ...)`
            # (Phase 1A) - that block-scopes the loop variable to just the
            # for-loop's own braces, so it does NOT leak the way the
            # interpreter's real ForEach does. Confirmed as a genuine
            # divergence via real browser execution during Phase 1E
            # (referencing the variable after the loop threw
            # ReferenceError, where the interpreter prints its last value)
            # and confirmed AGAIN here as directly relevant to function
            # scoping specifically: `for each item in items { say item } .
            # say item` INSIDE a function reads the last value (matches
            # SetLocal writing into the function's own current scope), so
            # fixing this leak is a prerequisite for that case, not a
            # separate concern. Now matches CountLoop's own pattern
            # exactly: an internal iterator variable separate from the
            # visible one, written via the same window/otterState-or-local
            # choice every other construct in this file uses.
            $collJs = ConvertTo-OtterJsExpression -Expr $Stmt.Collection
            $varName = $Stmt.VariableName
            $inner = '  ' * ($Indent + 1)
            $bodyIndent = '  ' * ($Indent + 2)
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("${pad}{")
            $lines.Add("${inner}for (const _item of ($collJs || [])) {")
            if ($LocalNames -and $LocalNames.Contains($varName)) {
                $lines.Add("${bodyIndent}$varName = _item;")
            } else {
                $lines.Add("${bodyIndent}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$varName' in otterState)) { otterSetState('$varName', _item); } else { window.$varName = _item; }")
            }
            foreach ($s in $Stmt.Body) {
                $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 2) -LocalNames $LocalNames))
            }
            $lines.Add("${inner}}")
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::Try) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("${pad}try {")
            foreach ($s in $Stmt.Body) {
                $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 1) -LocalNames $LocalNames))
            }
            $lines.Add("${pad}} catch (_err) {")
            if ($Stmt.OtherwiseBody) {
                foreach ($s in $Stmt.OtherwiseBody) {
                    $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 1) -LocalNames $LocalNames))
                }
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::Return) {
            if ($Stmt.Value) {
                $val = ConvertTo-OtterJsExpression -Expr $Stmt.Value
                return "${pad}return $val;"
            }
            return "${pad}return;"
        }
        ([NodeKind]::ReadFile) {
            # D60. `read <path> into <target>` (Otter.Interpreter.psm1's
            # 'ReadFile' case: Read-OtterFile, a synchronous, real
            # filesystem read). A browser cannot read arbitrary local files
            # the way a desktop process can (D60's "language capability !=
            # host capability" principle) - this compiler does not decide
            # HOW the read happens, only that a value comes back for
            # `target`, via a required runtime hook (`otterReadFile`) the
            # target adapter supplies (a real bridge call on Desktop; an
            # honest per-target error/rejection wherever file access
            # genuinely is not available, e.g. a plain browser tab with no
            # desktop host attached - not this compiler's decision to make).
            # That hook is inherently asynchronous (a real file read over a
            # bridge cannot be synchronous in JS the way Read-OtterFile is
            # in PowerShell), so this emits `await` - see FunctionDef's
            # async-detection for how the enclosing function ends up
            # `async` when it needs to.
            $pathJs = ConvertTo-OtterJsExpression -Expr $Stmt.Path
            $target = $Stmt.Target
            if ($LocalNames -and $LocalNames.Contains($target)) {
                return "${pad}$target = await otterReadFile($pathJs);"
            }
            return "${pad}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', await otterReadFile($pathJs)); } else { window.$target = await otterReadFile($pathJs); }"
        }
        ([NodeKind]::WriteFile) {
            # D60. `write <content> to <path>` - complements ReadFile.
            # Emits call to async runtime hook otterWriteFile(path, content).
            $contentJs = ConvertTo-OtterJsExpression -Expr $Stmt.Content
            $pathJs = ConvertTo-OtterJsExpression -Expr $Stmt.Path
            return "${pad}await otterWriteFile($pathJs, $contentJs);"
        }
        ([NodeKind]::RunProgram) {
            # D60. `run command <target> [into <resultTarget>]` - emits call
            # to async runtime hook otterRunCommand(command).
            $cmdJs = ConvertTo-OtterJsExpression -Expr $Stmt.Target
            $target = $Stmt.ResultTarget
            if ($target) {
                if ($LocalNames -and $LocalNames.Contains($target)) {
                    return "${pad}$target = await otterRunCommand($cmdJs);"
                }
                return "${pad}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', await otterRunCommand($cmdJs)); } else { window.$target = await otterRunCommand($cmdJs); }"
            }
            return "${pad}await otterRunCommand($cmdJs);"
        }
        ([NodeKind]::GetFiles) {
            # D60. `get files in <folder> [and subfolders] into <target>` - emits call
            # to async runtime hook otterGetFiles(folder, includeSubfolders).
            $folderJs = ConvertTo-OtterJsExpression -Expr $Stmt.Folder
            $subfoldersJs = if ($Stmt.IncludeSubfolders) { 'true' } else { 'false' }
            $target = $Stmt.Target
            if ($LocalNames -and $LocalNames.Contains($target)) {
                return "${pad}$target = await otterGetFiles($folderJs, $subfoldersJs);"
            }
            return "${pad}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', await otterGetFiles($folderJs, $subfoldersJs)); } else { window.$target = await otterGetFiles($folderJs, $subfoldersJs); }"
        }
        ([NodeKind]::GetFolders) {
            # D60. `get folders in <folder> [and subfolders] into <target>` - emits call
            # to async runtime hook otterGetFolders(folder, includeSubfolders).
            $folderJs = ConvertTo-OtterJsExpression -Expr $Stmt.Folder
            $subfoldersJs = if ($Stmt.IncludeSubfolders) { 'true' } else { 'false' }
            $target = $Stmt.Target
            if ($LocalNames -and $LocalNames.Contains($target)) {
                return "${pad}$target = await otterGetFolders($folderJs, $subfoldersJs);"
            }
            return "${pad}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', await otterGetFolders($folderJs, $subfoldersJs)); } else { window.$target = await otterGetFolders($folderJs, $subfoldersJs); }"
        }
        ([NodeKind]::AppendFile) {
            $pathJs = ConvertTo-OtterJsExpression -Expr $Stmt.Path
            $contentJs = ConvertTo-OtterJsExpression -Expr $Stmt.Content
            return "${pad}await otterAppendFile($pathJs, $contentJs);"
        }
        ([NodeKind]::CopyFile) {
            $sourceJs = ConvertTo-OtterJsExpression -Expr $Stmt.Source
            $destinationJs = ConvertTo-OtterJsExpression -Expr $Stmt.Destination
            return "${pad}await otterCopyFile($sourceJs, $destinationJs);"
        }
        ([NodeKind]::MoveFile) {
            $sourceJs = ConvertTo-OtterJsExpression -Expr $Stmt.Source
            $destinationJs = ConvertTo-OtterJsExpression -Expr $Stmt.Destination
            return "${pad}await otterMoveFile($sourceJs, $destinationJs);"
        }
        ([NodeKind]::DeleteFile) {
            $pathJs = ConvertTo-OtterJsExpression -Expr $Stmt.Path
            return "${pad}await otterDeleteFile($pathJs);"
        }
        ([NodeKind]::CreateFolder) {
            $pathJs = ConvertTo-OtterJsExpression -Expr $Stmt.Path
            return "${pad}await otterCreateFolder($pathJs);"
        }
        ([NodeKind]::DeleteFolder) {
            $pathJs = ConvertTo-OtterJsExpression -Expr $Stmt.Path
            return "${pad}await otterDeleteFolder($pathJs);"
        }
        ([NodeKind]::CopyFolder) {
            $sourceJs = ConvertTo-OtterJsExpression -Expr $Stmt.Source
            $destinationJs = ConvertTo-OtterJsExpression -Expr $Stmt.Destination
            return "${pad}await otterCopyFolder($sourceJs, $destinationJs);"
        }
        ([NodeKind]::MoveFolder) {
            $sourceJs = ConvertTo-OtterJsExpression -Expr $Stmt.Source
            $destinationJs = ConvertTo-OtterJsExpression -Expr $Stmt.Destination
            return "${pad}await otterMoveFolder($sourceJs, $destinationJs);"
        }
        ([NodeKind]::GetKey) {
            # D60 consolidated-audit release blocker. `get "key" from
            # thing into target` (D41 dynamic access) - matches the
            # interpreter's 'GetKey' case exactly, verified directly:
            # operates on the EXACT SAME `props`/`order` storage Phase
            # 1F.2 already built for ordinary PropertyAccess (dynamic
            # access and `X of Y` read/write the same underlying thing -
            # confirmed by reading Assert-OtterDynamicKeyTarget/
            # WriteProperty/ReadProperty, not assumed), so this needed no
            # new representation, only the missing NodeKind case itself.
            # Target must be a plain `thing` (TypeName exactly 'thing',
            # not a UI resource, not a file/folder object, not a declared
            # custom type - Assert-OtterDynamicKeyTarget checks BOTH
            # "is this an object at all" and "is its TypeName literally
            # thing", two different error messages, both replicated
            # here). The key must be a genuine JS string - D41 keys are
            # deliberately text-only, no numeric/boolean/date coercion
            # (matches Assert-OtterStringKey exactly). Reading a missing
            # key returns `gone` (JS `null`) rather than throwing - NOT
            # the same rule as ordinary `X of Y` property access, which
            # throws on a missing name (verified directly: ReadProperty
            # has no HasProperty guard here on purpose, per the
            # interpreter's own comment).
            $targetJs = ConvertTo-OtterJsExpression -Expr $Stmt.Target
            $keyJs = ConvertTo-OtterJsExpression -Expr $Stmt.Key
            $result = $Stmt.ResultTarget
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _owner = $targetJs;")
            $lines.Add("${inner}if (!_owner || typeof _owner !== 'object' || !_owner.__otterThing) { throw new Error('I can only read from a thing, but this is something else.'); }")
            $lines.Add("${inner}if (_owner.typeName !== 'thing') { throw new Error('I can only read properties dynamically on a thing, but this is a ' + _owner.typeName + '.'); }")
            $lines.Add("${inner}const _key = $keyJs;")
            $lines.Add("${inner}if (typeof _key !== 'string') { throw new Error('I need text for a dynamic key, but this is something else.'); }")
            $lines.Add("${inner}const _val = (_key in _owner.props) ? _owner.props[_key] : null;")
            if ($LocalNames -and $LocalNames.Contains($result)) {
                $lines.Add("${inner}$result = _val;")
            } else {
                $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$result' in otterState)) { otterSetState('$result', _val); } else { window.$result = _val; }")
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::SetKey) {
            # D60 consolidated-audit release blocker. `set "key" to val
            # in thing` (D41) - matches the interpreter's 'SetKey' case:
            # same target/key validation as GetKey above, then an
            # unconditional create-or-replace (matches WriteProperty's
            # own unconditional behavior - the same rule Assign-to-
            # PropertyAccess's write case already uses for `X of Y is
            # ...`, reused here verbatim since it is the exact same
            # underlying operation through a different surface syntax).
            $targetJs = ConvertTo-OtterJsExpression -Expr $Stmt.Target
            $keyJs = ConvertTo-OtterJsExpression -Expr $Stmt.Key
            $valJs = ConvertTo-OtterJsExpression -Expr $Stmt.Value
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _owner = $targetJs;")
            $lines.Add("${inner}if (!_owner || typeof _owner !== 'object' || !_owner.__otterThing) { throw new Error('I can only write to a thing, but this is something else.'); }")
            $lines.Add("${inner}if (_owner.typeName !== 'thing') { throw new Error('I can only write properties dynamically on a thing, but this is a ' + _owner.typeName + '.'); }")
            $lines.Add("${inner}const _key = $keyJs;")
            $lines.Add("${inner}if (typeof _key !== 'string') { throw new Error('I need text for a dynamic key, but this is something else.'); }")
            $lines.Add("${inner}if (!(_key in _owner.props)) { _owner.order.push(_key); }")
            $lines.Add("${inner}_owner.props[_key] = $valJs;")
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::HttpGet) {
            # D49/D60. Block-scoped (`{ ... }`) deliberately: `const res`
            # was previously emitted bare at the caller's own indent level,
            # which is fine for exactly one HTTP call in a given scope but
            # is a real, confirmed bug for two or more - JS rejects
            # redeclaring `const res` in the same scope with a hard
            # SyntaxError, breaking the ENTIRE compiled script (not just
            # that statement), the moment a real Otter program makes two
            # HttpGet/Post/Put/Delete calls at the same level. Found by
            # compiling and running an actual two-call `.ot` program in a
            # real browser, not by reading the code. Wrapping in its own
            # block - the same pattern every other multi-line statement
            # case in this file already uses - fixes it with no change to
            # the emitted values or control flow.
            $url = ConvertTo-OtterJsExpression -Expr $Stmt.Url
            $target = $Stmt.Target
            $readBody = if ($Stmt.AsJson) { 'res.json()' } else { 'res.text()' }
            return "${pad}{ const res = await fetch($url); const $target = await $readBody; window.$target = $target; }"
        }
        ([NodeKind]::HttpPost) {
            # D49/D60. Block-scoped - see HttpGet's comment for why.
            $data = ConvertTo-OtterJsExpression -Expr $Stmt.Data
            $url = ConvertTo-OtterJsExpression -Expr $Stmt.Url
            $target = $Stmt.Target
            $body = if ($Stmt.AsJson) { "JSON.stringify($data)" } else { "(typeof $data === 'object' ? JSON.stringify($data) : String($data))" }
            if ($target) {
                return "${pad}{ const res = await fetch($url, { method: 'POST', body: $body }); const $target = await res.text(); window.$target = $target; }"
            }
            return "${pad}await fetch($url, { method: 'POST', body: $body });"
        }
        ([NodeKind]::HttpPut) {
            # D49/D60. `put data to "https://..." [into result]` - mirrors
            # HttpPost exactly (same Data/Url/Target/AsJson shape in the
            # contract), only the HTTP method word differs. Web-only by
            # design (D49 was always the web provider's domain - the
            # interpreter has no HttpPut/HttpDelete case at all, confirmed
            # directly, so there is no interpreter behavior to match here,
            # only HttpPost's own already-established codegen shape).
            # Block-scoped - see HttpGet's comment for why.
            $data = ConvertTo-OtterJsExpression -Expr $Stmt.Data
            $url = ConvertTo-OtterJsExpression -Expr $Stmt.Url
            $target = $Stmt.Target
            $body = if ($Stmt.AsJson) { "JSON.stringify($data)" } else { "(typeof $data === 'object' ? JSON.stringify($data) : String($data))" }
            if ($target) {
                return "${pad}{ const res = await fetch($url, { method: 'PUT', body: $body }); const $target = await res.text(); window.$target = $target; }"
            }
            return "${pad}await fetch($url, { method: 'PUT', body: $body });"
        }
        ([NodeKind]::HttpDelete) {
            # D49/D60. `delete "https://..." [into result]` - mirrors
            # HttpGet's shape minus AsJson (HttpDeleteStmt has no AsJson
            # field in the contract - a DELETE response is read as plain
            # text, matching HttpGet's own non-JSON branch). Same
            # web-only reasoning as HttpPut above. Block-scoped - see
            # HttpGet's comment for why.
            $url = ConvertTo-OtterJsExpression -Expr $Stmt.Url
            $target = $Stmt.Target
            if ($target) {
                return "${pad}{ const res = await fetch($url, { method: 'DELETE' }); const $target = await res.text(); window.$target = $target; }"
            }
            return "${pad}await fetch($url, { method: 'DELETE' });"
        }
        ([NodeKind]::DateAdjust) {
            # D60 Phase 1J. `add <n> <unit> to <target>` / `remove <n>
            # <unit> from <target>` - matches the interpreter's DateAdjust
            # exactly: throws if the target does not already exist or does
            # not hold a date (generic "something else" phrasing, same
            # established approximation as elsewhere in this compiler -
            # not the interpreter's full Get-OtterTypeName text), throws if
            # the unit is Hour/Minute/Second on a date with no time of day,
            # the amount is truncated toward zero (never rounded - matches
            # `[int][Math]::Truncate($amount)` exactly, verified by reading
            # the interpreter), and ADJUSTING REPLACES THE VALUE rather than
            # mutating in place (a fresh tagged date object is built and
            # written back via the same Set-style mechanism as Assign/
            # MathInto - verified directly: two variables holding what was
            # the same date never move together after only one is adjusted,
            # since JS object references are never mutated here either).
            # Year/Month use Get-OtterJsAddMonthsSnippet's field-based,
            # day-clamping arithmetic (see its comment - a plain JS
            # setMonth rollover would silently give the wrong answer for
            # exactly the case Jeff asked to have covered: 31 January plus
            # one month must land on 28 February, not 3 March). Day/Hour/
            # Minute/Second use epoch-millisecond arithmetic (`.getTime()`
            # +/- ms), matching the interpreter's own tick-based
            # AddDays/AddHours/AddMinutes/AddSeconds (verified by reading
            # Otter.Interpreter.psm1 - these call .NET's DateTime.AddX,
            # which is pure elapsed-Ticks arithmetic with no DST/timezone
            # reinterpretation at all) - this is why epoch-ms arithmetic is
            # not merely a convenient JS shortcut here, it is the same class
            # of computation the interpreter performs, so it cannot drift
            # from it even across a DST boundary in an observing timezone.
            $target = $Stmt.Target
            $amountJs = ConvertTo-OtterJsExpression -Expr $Stmt.Amount
            $unit = $Stmt.Unit.ToString()
            $sign = if ($Stmt.IsRemoval) { -1 } else { 1 }
            $unitLower = $unit.ToLowerInvariant()
            $msPerUnit = switch ($unit) {
                'Hour' { 3600000 }
                'Minute' { 60000 }
                'Second' { 1000 }
                default { 0 }
            }
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _current = $target;")
            $lines.Add("${inner}if (!_current || typeof _current !== 'object' || !_current.__otterDate) { throw new Error('I can only add time to a date, but `"$target`" holds something else.'); }")
            $lines.Add("${inner}const _amountRaw = $amountJs;")
            $lines.Add("${inner}const _whole = Math.trunc(Number(_amountRaw)) * ($sign);")
            if ($unit -eq 'Year' -or $unit -eq 'Month') {
                $months = if ($unit -eq 'Year') { '_whole * 12' } else { '_whole' }
                $addSnippet = Get-OtterJsAddMonthsSnippet -DateJs '_current.value' -MonthsJs $months
                $lines.Add("${inner}const _moved = $addSnippet;")
            } elseif ($unit -eq 'Day') {
                $lines.Add("${inner}const _moved = new Date(_current.value.getTime() + _whole * 86400000);")
            } else {
                $lines.Add("${inner}if (!_current.hasTime) { throw new Error('This is a date with no time of day, so it has no $unitLower.'); }")
                $lines.Add("${inner}const _moved = new Date(_current.value.getTime() + _whole * $msPerUnit);")
            }
            $newDate = Get-OtterJsDateConstructor -DateExprJs '_moved' -HasTimeJs '_current.hasTime'
            $lines.Add("${inner}const _next = $newDate;")
            if ($LocalNames -and $LocalNames.Contains($target)) {
                $lines.Add("${inner}$target = _next;")
            } else {
                $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _next); } else { window.$target = _next; }")
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::DateDifference) {
            # D60 Phase 1J. `<unit> between <start> and <end> make <target>`
            # - the legacy statement form (D32), same underlying computation
            # as DateDifferenceValue's expression form - see
            # Get-OtterJsDateDifferenceExpression for the full explanation.
            # Both operands must be dates or this throws, matching
            # Assert-OtterDateOperands (generic "something else" phrasing
            # for the failing side, same established approximation used
            # elsewhere rather than full Get-OtterTypeName text).
            $startJs = ConvertTo-OtterJsExpression -Expr $Stmt.Start
            $endJs = ConvertTo-OtterJsExpression -Expr $Stmt.End
            $unit = $Stmt.Unit.ToString()
            $target = $Stmt.Target
            $diffJs = Get-OtterJsDateDifferenceExpression -UnitJs "'$unit'" -StartJs '_s.value' -EndJs '_e.value'
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _s = $startJs;")
            $lines.Add("${inner}const _e = $endJs;")
            $lines.Add("${inner}if (!_s || typeof _s !== 'object' || !_s.__otterDate) { throw new Error('I can only measure time between two dates, but the first one is something else.'); }")
            $lines.Add("${inner}if (!_e || typeof _e !== 'object' || !_e.__otterDate) { throw new Error('I can only measure time between two dates, but the second one is something else.'); }")
            $lines.Add("${inner}const _diff = $diffJs;")
            if ($LocalNames -and $LocalNames.Contains($target)) {
                $lines.Add("${inner}$target = _diff;")
            } else {
                $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _diff); } else { window.$target = _diff; }")
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::FormatDate) {
            # D60 Phase 1J. `format <date> as "<pattern>" into <target>` -
            # matches the interpreter's FormatDate exactly: the date itself
            # is untouched (produces text only), and throws if the subject
            # is not a date (generic "something else" phrasing, same
            # established approximation elsewhere). The pattern
            # interpreter supports exactly the tokens PROVEN to exist in
            # real Otter usage - verified by searching every example/test
            # in this repo, only "MM/dd/yyyy" and "yyyy-MM-dd HH:mm" are
            # ever used - yyyy/MM/dd/HH/mm/ss, matching `.NET`'s custom
            # date format specifiers for those exact tokens. Anything else
            # in the pattern passes through LITERALLY, which is not a
            # shortcut - it is what .NET's own formatter does too for an
            # unrecognized letter (verified directly: `format d as "qqq"`
            # against the real interpreter produces the literal text
            # "qqq", not an error - 'q' is not a reserved custom-format
            # character). .NET's own rarer FormatException edge cases
            # (unbalanced quoted-literal sections, escape sequences) are
            # deliberately NOT replicated - nothing in this codebase
            # exercises them, and no `try` here ever throws for a pattern
            # this compiler doesn't recognize, matching every case actually
            # observed against the real interpreter.
            $subjectJs = ConvertTo-OtterJsExpression -Expr $Stmt.Subject
            $formatJs = ConvertTo-OtterJsExpression -Expr $Stmt.Format
            $target = $Stmt.Target
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _subject = $subjectJs;")
            $lines.Add("${inner}if (!_subject || typeof _subject !== 'object' || !_subject.__otterDate) { throw new Error('I can only format a date, but this is something else.'); }")
            $lines.Add("${inner}const _pattern = String($formatJs);")
            $lines.Add("${inner}const _d = _subject.value;")
            $lines.Add("${inner}const _text = _pattern.replace(/yyyy|MM|dd|HH|mm|ss/g, (_tok) => { switch (_tok) { case 'yyyy': return String(_d.getFullYear()).padStart(4, '0'); case 'MM': return String(_d.getMonth() + 1).padStart(2, '0'); case 'dd': return String(_d.getDate()).padStart(2, '0'); case 'HH': return String(_d.getHours()).padStart(2, '0'); case 'mm': return String(_d.getMinutes()).padStart(2, '0'); case 'ss': return String(_d.getSeconds()).padStart(2, '0'); } return _tok; });")
            if ($LocalNames -and $LocalNames.Contains($target)) {
                $lines.Add("${inner}$target = _text;")
            } else {
                $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _text); } else { window.$target = _text; }")
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::Diagnostic) {
            # D60 Phase 1I. `log ...` / `warn ...` / `error ...` - matches
            # the interpreter's 'Diagnostic' case exactly, verified
            # directly against it before writing any JS: parts are
            # formatted and space-joined exactly like `say` (D8), then
            # rendered as a SINGLE string `"<label>: <joined parts>"` -
            # confirmed the label is always lowercase ("log"/"warn"/
            # "error", never the DiagnosticLevel enum names Note/
            # Warning/Problem) and that zero parts is valid syntax,
            # producing a trailing "<label>: " with nothing after the
            # colon-space (not an error, not an empty string with no
            # separator). console.log/warn/error is a natural, sound
            # mapping for the three levels - closer to Otter's intent
            # than the interpreter's own single Write-Host-for-everything
            # implementation (a real browser's devtools already separates
            # these by severity), so the level is still ALSO baked into
            # the rendered text (not left to console's own styling alone)
            # to match the interpreter's exact observable output.
            $label = switch ($Stmt.Level.ToString()) {
                'Warning' { 'warn' }
                'Problem' { 'error' }
                default { 'log' }
            }
            $consoleFn = switch ($label) {
                'warn' { 'console.warn' }
                'error' { 'console.error' }
                default { 'console.log' }
            }
            $parts = @(foreach ($p in $Stmt.Parts) { ConvertTo-OtterJsExpression -Expr $p })
            if ($parts.Count -eq 0) {
                return "${pad}$consoleFn('$label`: ');"
            }
            $joined = $parts -join ' + " " + '
            return "${pad}$consoleFn('$label`: ' + ($joined));"
        }
        ([NodeKind]::RandomNumber) {
            # D60 Phase 1H. `random number from <from> to <to> into <target>`
            # - matches the interpreter's 'RandomNumber' case exactly,
            # verified directly against the real interpreter first, not
            # assumed from Math.random() intuition:
            #   - both endpoints are INCLUSIVE (confirmed: `from 1 to 1`
            #     always returns 1; a 1-to-6 loop of 20 draws produced both
            #     1 and 6)
            #   - non-integer bounds are FLOORED, not rounded, before
            #     picking (confirmed: `from 1.7 to 3.2` only ever produced
            #     1, 2, or 3 - never 0 or 4)
            #   - reversed bounds (`from` greater than `to`) are silently
            #     swapped, never an error (confirmed: `from 10 to 1` stays
            #     in range 1-10)
            #   - negative ranges work the same as positive ones (confirmed
            #     via a computed negative bound - the grammar has no
            #     negative NUMBER LITERAL syntax at all, so this is only
            #     reachable through an expression like `0 minus 5`)
            #   - a non-numeric bound throws Assert-OtterNumber's exact
            #     message ("I expected a number for the lowest number but
            #     got \"a\"." / "...the highest number...") - a numeric-
            #     LOOKING string (e.g. "5") is accepted and coerced, exactly
            #     like Test-OtterNumeric's own string-parse branch, so this
            #     reuses the same runtime typeof-or-numeric-string IIFE
            #     check already established for `plus` (Phase 1D-B) rather
            #     than a plain `Number(...)` coercion that would silently
            #     turn a bad bound into NaN.
            #   - the result is always a whole number (the interpreter
            #     stores `[double]$picked` where $picked came from
            #     Get-Random over floored integer bounds - never a
            #     fractional value even when the input bounds were
            #     fractional).
            # Deliberately NOT implemented (verified absent from the
            # grammar - the parser only recognizes "number" and "item"
            # after "random", throwing "I expected \"number\" or \"item\"
            # after \"random\"." for anything else): random decimals,
            # random list/decimal selection beyond `random item`, and
            # seeding. There is no such Otter syntax to give parity for.
            $fromJs = ConvertTo-OtterJsExpression -Expr $Stmt.From
            $toJs = ConvertTo-OtterJsExpression -Expr $Stmt.To
            $target = $Stmt.Target
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _fromRaw = $fromJs;")
            $lines.Add("${inner}const _toRaw = $toJs;")
            $lines.Add("${inner}const _fromOk = typeof _fromRaw === 'number' || (typeof _fromRaw === 'string' && _fromRaw.trim() !== '' && !Number.isNaN(Number(_fromRaw)));")
            $lines.Add("${inner}if (!_fromOk) { throw new Error('I expected a number for the lowest number but got ' + JSON.stringify(_fromRaw) + '.'); }")
            $lines.Add("${inner}const _toOk = typeof _toRaw === 'number' || (typeof _toRaw === 'string' && _toRaw.trim() !== '' && !Number.isNaN(Number(_toRaw)));")
            $lines.Add("${inner}if (!_toOk) { throw new Error('I expected a number for the highest number but got ' + JSON.stringify(_toRaw) + '.'); }")
            $lines.Add("${inner}let _from = Math.floor(Number(_fromRaw));")
            $lines.Add("${inner}let _to = Math.floor(Number(_toRaw));")
            $lines.Add("${inner}if (_from > _to) { const _swap = _from; _from = _to; _to = _swap; }")
            $lines.Add("${inner}const _picked = Math.floor(Math.random() * (_to - _from + 1)) + _from;")
            if ($LocalNames -and $LocalNames.Contains($target)) {
                $lines.Add("${inner}$target = _picked;")
            } else {
                $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _picked); } else { window.$target = _picked; }")
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::RandomItem) {
            # D60 Phase 1H. `random item from <collection> into <target>` -
            # matches the interpreter's 'RandomItem' case exactly, verified
            # directly: a non-list subject throws ("I can only pick from a
            # list, but this is..." - the interpreter names the exact
            # runtime type via Get-OtterTypeName; this compiler uses the
            # same simplified "something else" phrasing already established
            # for the analogous PropertyAccess/Assign checks rather than
            # replicating that full dynamic type-name dispatch, a
            # deliberate approximation, not a missed detail), an EMPTY list
            # gives `gone` (JS `null`) rather than erroring (confirmed
            # directly), and a non-empty list picks uniformly by index.
            $collectionJs = ConvertTo-OtterJsExpression -Expr $Stmt.Collection
            $target = $Stmt.Target
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _collection = $collectionJs;")
            $lines.Add("${inner}if (!Array.isArray(_collection)) { throw new Error('I can only pick from a list, but this is something else.'); }")
            $lines.Add("${inner}const _picked = _collection.length > 0 ? _collection[Math.floor(Math.random() * _collection.length)] : null;")
            if ($LocalNames -and $LocalNames.Contains($target)) {
                $lines.Add("${inner}$target = _picked;")
            } else {
                $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _picked); } else { window.$target = _picked; }")
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::ReadJson) {
            # D60 Phase 1G. `read json from <path> into <target>` -
            # Read-OtterJsonFile is a synchronous real file read followed by
            # ConvertFrom-OtterJsonText (verified: same JSON-to-Otter
            # conversion as ConvertFromJson below, just sourced from a
            # file). Same host-capability boundary as ReadFile - the actual
            # read goes through the required otterReadFile(path) hook
            # (async), matching ReadFile's own async-detection/await
            # handling (see Test-OtterJsBodyNeedsAsync). The parse-and-
            # otterify step is identical to ConvertFromJson - see that case
            # for the full explanation of the recursive value rewrite and
            # the exact empty/invalid-JSON error text, both verified
            # directly against the real interpreter.
            $pathJs = ConvertTo-OtterJsExpression -Expr $Stmt.Path
            $target = $Stmt.Target
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _text = String(await otterReadFile($pathJs));")
            $lines.Add("${inner}if (_text.trim() === '') { throw new Error('There is no JSON here to read.'); }")
            $lines.Add("${inner}let _parsed;")
            $lines.Add("${inner}try { _parsed = JSON.parse(_text); } catch (_e) { throw new Error('This is not valid JSON, so Otter could not read it.'); }")
            $lines.Add("${inner}const _value = (function _otterify(v) { if (v === null) return null; if (Array.isArray(v)) return v.map(_otterify); if (typeof v === 'object') { const props = {}; const order = []; for (const k of Object.keys(v)) { props[k] = _otterify(v[k]); order.push(k); } return { __otterThing: true, typeName: 'thing', props: props, order: order }; } return v; })(_parsed);")
            if ($LocalNames -and $LocalNames.Contains($target)) {
                $lines.Add("${inner}$target = _value;")
            } else {
                $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _value); } else { window.$target = _value; }")
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::ConvertToJson) {
            # D60 Phase 1G. `convert <subject> to json into <target>` -
            # matches ConvertTo-OtterJsonText/ConvertTo-OtterJsonShape: a
            # plain thing serializes as an object (property insertion order
            # via `order`, matching OtterObject.PropertyNames()), a list as
            # an array, functions/types throw ("Otter cannot turn something
            # it can do into JSON.", verified directly against the real
            # interpreter) - a JS Otter function value is a real JS
            # function, so `typeof === 'function'` is a sound, no-extra-
            # tagging-needed stand-in for the interpreter's
            # OtterFunction/OtterType check. NOT byte-for-byte: the
            # interpreter's ConvertTo-Json produces PowerShell's own
            # unusual pretty-print (4-space indent, a double space after
            # every colon, deeply-reindented nested arrays/objects) -
            # JSON.stringify(v, null, 4) is used here instead, a standard
            # 4-space pretty-print. This is a deliberate, documented
            # cosmetic divergence (see SPEC-DECISIONS.md's D60 parity
            # tracker), not a missed detail: matching PowerShell's specific
            # whitespace quirks would make the JS output look wrong to
            # anyone used to normal JSON formatting, and every verification
            # case here depends on values round-tripping correctly, never
            # on exact whitespace.
            $subjectJs = ConvertTo-OtterJsExpression -Expr $Stmt.Subject
            $target = $Stmt.Target
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _deotter = function _deotter(v) { if (v === null || v === undefined) return null; if (typeof v === 'function') { throw new Error('Otter cannot turn something it can do into JSON.'); } if (Array.isArray(v)) return v.map(_deotter); if (typeof v === 'object') { if (!v.__otterThing) { throw new Error('Otter cannot turn something it can do into JSON.'); } const out = {}; for (const k of v.order) { out[k] = _deotter(v.props[k]); } return out; } return v; };")
            $lines.Add("${inner}const _value = JSON.stringify(_deotter($subjectJs), null, 4);")
            if ($LocalNames -and $LocalNames.Contains($target)) {
                $lines.Add("${inner}$target = _value;")
            } else {
                $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _value); } else { window.$target = _value; }")
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::ConvertFromJson) {
            # D60 Phase 1G. `convert <subject> from json into <target>` -
            # matches ConvertFrom-OtterJsonText/ConvertFrom-OtterJsonValue
            # exactly, verified directly against the real interpreter:
            # empty/whitespace text throws "There is no JSON here to
            # read.", invalid JSON throws "This is not valid JSON, so Otter
            # could not read it.", a JSON object becomes a plain `thing`
            # (recursively - nested objects/arrays are converted too, never
            # left as raw JS values), a JSON array becomes a list, JSON
            # null becomes `gone` (JS null - already this compiler's
            # existing representation, see the Variable case), numbers/
            # booleans/strings pass through unchanged. Also verified
            # directly against the real interpreter and needing NO special
            # handling here: property access into a parsed object's list/
            # nested-object properties returns a REFERENCE to the same
            # underlying value, not a copy (mutating a list read out via `X
            # of Y` and later re-serializing `Y` reflects the mutation) -
            # this falls out for free since JS objects/arrays are already
            # reference types and nothing here ever clones on read; and
            # duplicate JSON keys are last-one-wins (confirmed against the
            # real interpreter, and already JSON.parse's own native
            # behavior, so nothing extra is needed for that case either).
            $subjectJs = ConvertTo-OtterJsExpression -Expr $Stmt.Subject
            $target = $Stmt.Target
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _text = String($subjectJs);")
            $lines.Add("${inner}if (_text.trim() === '') { throw new Error('There is no JSON here to read.'); }")
            $lines.Add("${inner}let _parsed;")
            $lines.Add("${inner}try { _parsed = JSON.parse(_text); } catch (_e) { throw new Error('This is not valid JSON, so Otter could not read it.'); }")
            $lines.Add("${inner}const _value = (function _otterify(v) { if (v === null) return null; if (Array.isArray(v)) return v.map(_otterify); if (typeof v === 'object') { const props = {}; const order = []; for (const k of Object.keys(v)) { props[k] = _otterify(v[k]); order.push(k); } return { __otterThing: true, typeName: 'thing', props: props, order: order }; } return v; })(_parsed);")
            if ($LocalNames -and $LocalNames.Contains($target)) {
                $lines.Add("${inner}$target = _value;")
            } else {
                $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _value); } else { window.$target = _value; }")
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::Replace) {
            # D60 Phase 1D-A. Matches Otter.Interpreter.psm1's 'Replace'
            # case exactly:
            #   - Target is a variable NAME, read directly (not a general
            #     expression) - mirrors the interpreter's
            #     $Environment.Get/Set($Statement.Target)
            #   - empty find text is a thrown runtime error, not a silent
            #     no-op (confirmed: "I cannot replace empty text.")
            #   - ALL occurrences are replaced, not just the first
            #     (confirmed: .NET's String.Replace replaces every
            #     occurrence in one pass) - split+join gives the same
            #     single-pass, non-recursive, literal-substring (no regex)
            #     replacement semantics
            #   - VERIFIED DEAD IN THE CURRENT PARSER, so not implemented:
            #     the contract's ResultTarget field ("replace X with Y in
            #     text into newText", leaving the source unchanged) has no
            #     parser support today - Read-OtterStatement's Replace case
            #     always asserts Newline immediately after the target, so
            #     ResultTarget is always $null in practice. Only the
            #     in-place mutation path is reachable, so only that path is
            #     emitted here.
            $findJs = ConvertTo-OtterJsExpression -Expr $Stmt.Find
            $replacementJs = ConvertTo-OtterJsExpression -Expr $Stmt.Replacement
            $target = $Stmt.Target
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _find = String($findJs);")
            $lines.Add("${inner}if (_find.length === 0) { throw new Error('I cannot replace empty text.'); }")
            $lines.Add("${inner}const _replaced = String($target).split(_find).join(String($replacementJs));")
            $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _replaced); } else { window.$target = _replaced; }")
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::Split) {
            # D60 Phase 1D-A. Matches Otter.Interpreter.psm1's 'Split' case:
            #   - Subject and Separator are both general expressions
            #   - empty separator is a thrown runtime error ("I need
            #     something to split by."), not a silent no-op
            #   - StringSplitOptions.None means empty entries ARE kept in
            #     the result (confirmed: "a,,b" by "," gives 3 pieces, the
            #     middle one empty) - JS's native .split(sep) already keeps
            #     empty entries by default, so no extra handling is needed
            #     to match this
            #   - the result is a genuine list (Phase 1C's ListDef write
            #     pattern - otterState-or-window - reused here, since a
            #     plain JS array is already the correct representation)
            $subjectJs = ConvertTo-OtterJsExpression -Expr $Stmt.Subject
            $separatorJs = ConvertTo-OtterJsExpression -Expr $Stmt.Separator
            $target = $Stmt.Target
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _sep = String($separatorJs);")
            $lines.Add("${inner}if (_sep.length === 0) { throw new Error('I need something to split by.'); }")
            $lines.Add("${inner}const _pieces = String($subjectJs).split(_sep);")
            if ($LocalNames -and $LocalNames.Contains($target)) {
                $lines.Add("${inner}$target = _pieces;")
            } else {
                $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _pieces); } else { window.$target = _pieces; }")
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::FunctionDef) {
            # D60 Phase 1F. `const name = function(...) {...}` rather than a
            # hoisted `function name() {}` declaration - deliberate, matches
            # a real, verified interpreter behavior: calling a function
            # before its `to ...` line is a runtime error today (no
            # hoisting - confirmed directly), and `const` bindings are in
            # the temporal dead zone until their own line runs, so calling
            # too early throws in the generated JS too, the same way it
            # does in the interpreter (different message, same "fails
            # before declaration" shape).
            #
            # Parameters become real JS function arguments - this alone
            # already matches Invoke-OtterCall's SetLocal-per-parameter
            # (a parameter always shadows an outer variable of the same
            # name), with zero extra code.
            #
            # Local variables were the real design problem this phase had to
            # solve, verified directly rather than assumed: a function's
            # local scope is a FRESH environment rooted at the GLOBAL
            # environment for every call (Invoke-OtterCall: `$local =
            # [OtterEnvironment]::new($script:GlobalEnvironment)`), so a
            # plain local is discarded when the function returns and must
            # never leak to an enclosing/global scope (verified: reading it
            # back at top level afterward throws "could not find the
            # variable").
            #
            # D60 Phase 1F.1 REFINED this: the interpreter's binding targets
            # split into two genuinely different behaviors (see
            # Get-OtterJsBindingNames for the full verification) -
            # Assign/MathInto/CallStatement ("Set-style") mutate an existing
            # global if one already exists by that name anywhere in the
            # program, or become a real local only if none does; CountLoop/
            # ForEach ("AlwaysLocal-style") are unconditionally local no
            # matter what, even shadowing a same-named pre-existing global
            # for the whole call (verified: an outer `item` survives a
            # same-named `for each item in ...` inside a function completely
            # unchanged). $KnownGlobals (the whole program's top-level
            # binding names, passed in from the caller) is what lets
            # Set-style names be classified correctly here.
            $fnName = $Stmt.Name
            $paramNames = @($Stmt.Parameters)
            $paramSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$paramNames)
            $bindings = Get-OtterJsBindingNames -Statements $Stmt.Body
            # An explicit $null check and a plain (non-expression) if/else,
            # not `$globals = if (...) {...} else {...}` and not a bare
            # truthiness check on $KnownGlobals - BOTH of those hit the same
            # "PowerShell enumerates an empty collection into zero pipeline
            # outputs" behavior already found and fixed twice elsewhere in
            # this phase (Write-Output -NoEnumerate for
            # Get-OtterJsFunctionLocalNames's old `return $names`): an EMPTY
            # HashSet is falsy in an `if ($x)` check, AND assigning through
            # an if/else expression re-triggers the same collection-to-null
            # collapse. Confirmed directly - $globals came back $null for a
            # function with zero known top-level globals (a legitimate,
            # common, non-error case), not just for a missing parameter.
            $globals = $KnownGlobals
            if ($null -eq $globals) { $globals = [System.Collections.Generic.HashSet[string]]::new() }

            $allLocals = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($p in $paramNames) { [void]$allLocals.Add($p) }
            foreach ($n in $bindings.AlwaysLocal) { [void]$allLocals.Add($n) }
            foreach ($n in $bindings.SetStyle) {
                if (-not $globals.Contains($n)) { [void]$allLocals.Add($n) }
            }
            $declOnly = @($allLocals | Where-Object { -not $paramSet.Contains($_) })

            # A function containing `read`/HTTP needs `await` inside itself
            # (ReadFile/HttpGet/HttpPost all emit `await`, since none of
            # them can be synchronous in JS the way their interpreter
            # counterparts are) - `await` is a syntax error outside an
            # `async function`, so this must be detected, not assumed. A
            # caller that doesn't itself await this function only loses the
            # ability to sequence AFTER it finishes - calling an async
            # function without awaiting it is valid JS, not an error, so
            # this stays narrowly scoped to exactly the functions that need
            # it rather than making every function async.
            $needsAsync = Test-OtterJsBodyNeedsAsync -Statements $Stmt.Body
            $asyncPrefix = if ($needsAsync) { 'async ' } else { '' }

            $lines = [System.Collections.Generic.List[string]]::new()
            $bodyIndent = '  ' * ($Indent + 1)
            $lines.Add("${pad}const $fnName = ${asyncPrefix}function($($paramNames -join ', ')) {")
            if ($declOnly.Count -gt 0) {
                $lines.Add("${bodyIndent}let $(($declOnly | Sort-Object) -join ', ');")
            }
            foreach ($s in $Stmt.Body) {
                $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 1) -LocalNames $allLocals))
            }
            $lines.Add("${bodyIndent}return null;")
            $lines.Add("${pad}};")
            $lines.Add("${pad}if (typeof window !== 'undefined') { window.$fnName = $fnName; }")
            return ($lines -join "`n")
        }
        ([NodeKind]::CallStatement) {
            # D60 Phase 1F. `stop`/`return` need no special handling here at
            # all: both parse to a bare Return node (confirmed via
            # -DebugAst), and JS's native `return` already exits the
            # function immediately from anywhere inside it - no exception-
            # based signal needed the way the interpreter's OtterReturnSignal
            # is, since JS functions support early return natively.
            $call = $Stmt.Call
            $argsJs = @(foreach ($a in $call.Arguments) { ConvertTo-OtterJsExpression -Expr $a })
            $callJs = "$($call.Name)($($argsJs -join ', '))"
            if ($Stmt.ResultTarget) {
                $target = $Stmt.ResultTarget
                if ($LocalNames -and $LocalNames.Contains($target)) {
                    return "${pad}$target = $callJs;"
                }
                return "${pad}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', $callJs); } else { window.$target = $callJs; }"
            }
            return "${pad}$callJs;"
        }
        default {
            return ""
        }
    }
}

# D60 Phase 1F.1. Recursively collects every variable-binding-target name
# inside a set of statements, split into the two categories the interpreter
# genuinely treats differently - verified directly, not assumed:
#
#   SetStyle: Assign, MathInto, CallStatement's "make" capture. The
#   interpreter's Environment.Set() CLIMBS the parent chain and mutates an
#   EXISTING variable of the same name wherever it is found, creating a new
#   one in the current scope only if none exists anywhere up the chain.
#   Confirmed: a function doing `value is 2` where a global `value` already
#   exists really does update that global, not shadow it locally.
#
#   AlwaysLocalStyle: CountLoop and ForEach loop variables. The
#   interpreter's SetLocal() ALWAYS writes into the CURRENT scope directly,
#   never climbing, regardless of whether a same-named variable exists
#   further up. Confirmed: a global `item` set before a function whose own
#   `for each item in ...` uses the identical name is completely unaffected
#   after the function returns - the loop variable shadowed it locally for
#   the whole call, unconditionally.
#
# Both categories still need the same recursion into if/otherwise, while,
# repeat, count, each, and try/otherwise - a binding buried inside one of
# those is exactly as real as a direct child of the function body (verified
# this matters, not just for symmetry: `if flag is true { result is 10 } .`
# must not accidentally become a window write just because the assignment
# isn't a direct child of the function).
function Get-OtterJsBindingNames {
    param([Node[]]$Statements, [switch]$DescendIntoFunctionDefs)

    $setStyle = [System.Collections.Generic.HashSet[string]]::new()
    $alwaysLocal = [System.Collections.Generic.HashSet[string]]::new()

    function Walk-OtterBindingScan {
        param([Node[]]$Stmts)
        if ($null -eq $Stmts) { return }
        foreach ($s in $Stmts) {
            if ($s.Kind -eq [NodeKind]::Assign -and $s.Target -is [VariableExpr]) {
                [void]$setStyle.Add($s.Target.Name)
            }
            if ($s.Kind -eq [NodeKind]::CallStatement -and $s.ResultTarget) {
                [void]$setStyle.Add($s.ResultTarget)
            }
            if ($s.Kind -eq [NodeKind]::MathInto) {
                [void]$setStyle.Add($s.Target)
            }
            if ($s.Kind -eq [NodeKind]::ReadFile -or $s.Kind -eq [NodeKind]::HttpGet -or $s.Kind -eq [NodeKind]::HttpPost -or $s.Kind -eq [NodeKind]::HttpPut -or $s.Kind -eq [NodeKind]::HttpDelete) {
                if ($s.Target) { [void]$setStyle.Add($s.Target) }
            }
            if ($s.Kind -eq [NodeKind]::RunProgram -and $s.ResultTarget) {
                [void]$setStyle.Add($s.ResultTarget)
            }
            if (($s.Kind -eq [NodeKind]::GetFiles -or $s.Kind -eq [NodeKind]::GetFolders) -and $s.Target) {
                [void]$setStyle.Add($s.Target)
            }
            if ($s.Kind -eq [NodeKind]::ListDef) {
                [void]$setStyle.Add($s.Name)
            }
            if ($s.Kind -eq [NodeKind]::Join -or $s.Kind -eq [NodeKind]::Split) {
                [void]$setStyle.Add($s.Target)
            }
            if ($s.Kind -eq [NodeKind]::AddTo -or $s.Kind -eq [NodeKind]::RemoveFrom) {
                [void]$setStyle.Add($s.Target)
            }
            if ($s.Kind -eq [NodeKind]::RandomNumber -or $s.Kind -eq [NodeKind]::RandomItem) {
                # D60 Phase 1H: both use Environment.Set (verified directly
                # against the interpreter's 'RandomNumber'/'RandomItem'
                # cases) - Set-style, same as Assign/MathInto, not
                # SetLocal.
                if ($s.Target) { [void]$setStyle.Add($s.Target) }
            }
            if ($s.Kind -eq [NodeKind]::DateAdjust) {
                # D60 Phase 1J: rebinds the target via Environment.Set
                # (verified directly - "adjusting REPLACES the value rather
                # than mutating in place") - Set-style, same as
                # Assign/MathInto, not SetLocal.
                [void]$setStyle.Add($s.Target)
            }
            if ($s.Kind -eq [NodeKind]::GetKey) {
                # D41: uses Environment.Set (verified directly against
                # the interpreter's 'GetKey' case) - Set-style, same as
                # Assign/MathInto, not SetLocal. SetKey has no result
                # target - it writes into the thing's own property
                # storage, not into a local Otter variable.
                if ($s.ResultTarget) { [void]$setStyle.Add($s.ResultTarget) }
            }
            if ($s.Kind -eq [NodeKind]::DateDifference -or $s.Kind -eq [NodeKind]::FormatDate) {
                # D60 Phase 1J: both use Environment.Set (verified directly
                # against the interpreter's 'DateDifference'/'FormatDate'
                # cases) - Set-style, same as Assign/MathInto, not
                # SetLocal.
                if ($s.Target) { [void]$setStyle.Add($s.Target) }
            }
            if ($s.Kind -eq [NodeKind]::ReadJson -or $s.Kind -eq [NodeKind]::ConvertToJson -or $s.Kind -eq [NodeKind]::ConvertFromJson) {
                # D60 Phase 1G: all three use Environment.Set (verified
                # directly against the interpreter's 'ReadJson'/
                # 'ConvertToJson'/'ConvertFromJson' cases) - Set-style,
                # same as Assign/MathInto, not SetLocal.
                if ($s.Target) { [void]$setStyle.Add($s.Target) }
            }
            if ($s.Kind -eq [NodeKind]::ObjectDef) {
                # D60 Phase 1F.2: `person is a thing` uses Environment.Set
                # (verified in New-OtterObjectValue's caller), the same
                # Set-style mechanism as Assign/MathInto - not SetLocal, so
                # it belongs here, not in AlwaysLocal.
                [void]$setStyle.Add($s.Name)
            }
            if ($s.Kind -eq [NodeKind]::TypeDef) {
                # Consolidated-audit release blocker: `a Person has ...`
                # uses Environment.Set (verified directly) - Set-style,
                # same as ObjectDef/Assign/MathInto, not SetLocal.
                [void]$setStyle.Add($s.TypeName)
            }
            if ($s.Kind -eq [NodeKind]::Ask) {
                # Consolidated-audit release blocker: `ask ... and call
                # it x` uses Environment.Set (verified directly) -
                # Set-style, same as Assign/MathInto, not SetLocal.
                [void]$setStyle.Add($s.Name)
            }
            if ($s.Kind -eq [NodeKind]::CountLoop) {
                [void]$alwaysLocal.Add($s.VariableName)
                [void](Walk-OtterBindingScan -Stmts $s.Body)
            }
            if ($s.Kind -eq [NodeKind]::ForEach) {
                [void]$alwaysLocal.Add($s.VariableName)
                [void](Walk-OtterBindingScan -Stmts $s.Body)
            }
            if ($s.Kind -eq [NodeKind]::If) {
                # [void] on every nested call below: an unsuppressed bare
                # call inside a PowerShell function becomes part of ITS
                # implicit output too, which would otherwise leak into the
                # caller's variable and silently turn a clean HashSet
                # return into a mixed array - this was a real bug, caught
                # via the "Multiple ambiguous overloads" error it produced
                # downstream, not assumed safe.
                foreach ($branch in $s.Branches) { [void](Walk-OtterBindingScan -Stmts $branch.Body) }
                if ($s.ElseBody) { [void](Walk-OtterBindingScan -Stmts $s.ElseBody) }
            }
            if ($s.Kind -eq [NodeKind]::While -or $s.Kind -eq [NodeKind]::Repeat) {
                [void](Walk-OtterBindingScan -Stmts $s.Body)
            }
            if ($s.Kind -eq [NodeKind]::Try) {
                [void](Walk-OtterBindingScan -Stmts $s.Body)
                if ($s.OtherwiseBody) { [void](Walk-OtterBindingScan -Stmts $s.OtherwiseBody) }
            }
            if ($DescendIntoFunctionDefs -and $s.Kind -eq [NodeKind]::FunctionDef) {
                [void](Walk-OtterBindingScan -Stmts $s.Body)
            }
        }
    }

    [void](Walk-OtterBindingScan -Stmts $Statements)
    # A plain hashtable, not a collection - PowerShell does not enumerate a
    # hashtable's own entries into the output stream the way it would a
    # bare HashSet/array, so this needs no -NoEnumerate to come back as one
    # object (unlike the HashSet-returning helper this replaced, where an
    # empty HashSet vanished into $null on `return` - the exact bug found
    # and fixed in Phase 1F).
    return @{ SetStyle = $setStyle; AlwaysLocal = $alwaysLocal }
}

# True when an expression contains a filesystem-existence check or await. `exists`
# is the one filesystem operation that appears in expression position, so
# its bridge call carries an `await` rather than living in a statement case.
function Test-OtterJsExpressionNeedsAsync {
    param([Node]$Expression)

    if ($null -eq $Expression) { return $false }
    switch ($Expression.Kind) {
        ([NodeKind]::FileExists) { return $true }
        ([NodeKind]::Await) { return $true }
        ([NodeKind]::Math) { return (Test-OtterJsExpressionNeedsAsync $Expression.Left) -or (Test-OtterJsExpressionNeedsAsync $Expression.Right) }
        ([NodeKind]::Comparison) { return (Test-OtterJsExpressionNeedsAsync $Expression.Left) -or (Test-OtterJsExpressionNeedsAsync $Expression.Right) }
        ([NodeKind]::Logical) { return (Test-OtterJsExpressionNeedsAsync $Expression.Left) -or (Test-OtterJsExpressionNeedsAsync $Expression.Right) }
        ([NodeKind]::Not) {
            $operand = if ($Expression.Operand) { $Expression.Operand } else { $Expression.Expression }
            return (Test-OtterJsExpressionNeedsAsync $operand)
        }
        ([NodeKind]::Contains) { return (Test-OtterJsExpressionNeedsAsync $Expression.Collection) -or (Test-OtterJsExpressionNeedsAsync $Expression.Item) }
        ([NodeKind]::TextMatch) { return (Test-OtterJsExpressionNeedsAsync $Expression.Subject) -or (Test-OtterJsExpressionNeedsAsync $Expression.Value) }
        ([NodeKind]::OfOperation) { return (Test-OtterJsExpressionNeedsAsync $Expression.Subject) }
        ([NodeKind]::PropertyAccess) { return (Test-OtterJsExpressionNeedsAsync $Expression.Target) }
        ([NodeKind]::DateDifferenceValue) { return (Test-OtterJsExpressionNeedsAsync $Expression.Start) -or (Test-OtterJsExpressionNeedsAsync $Expression.End) }
        ([NodeKind]::Call) {
            foreach ($argument in $Expression.Arguments) {
                if (Test-OtterJsExpressionNeedsAsync $argument) { return $true }
            }
        }
    }
    return $false
}

# D60. True if any statement in this body (recursively, through the same
# constructs Get-OtterJsBindingNames already walks) emits `await` -
# ReadFile, WriteFile, RunProgram, HttpGet, HttpPost today. FunctionDef uses this to decide
# whether it must be declared `async function`; a plain function with none
# of these stays a normal synchronous function, unchanged from before this
# existed.
function Test-OtterJsBodyNeedsAsync {
    param([Node[]]$Statements)

    if ($null -eq $Statements) { return $false }
    foreach ($s in $Statements) {
        if ($s.Kind -eq [NodeKind]::Await -or $s.Kind -eq [NodeKind]::ReadFile -or $s.Kind -eq [NodeKind]::WriteFile -or $s.Kind -eq [NodeKind]::AppendFile -or $s.Kind -eq [NodeKind]::CopyFile -or $s.Kind -eq [NodeKind]::MoveFile -or $s.Kind -eq [NodeKind]::DeleteFile -or $s.Kind -eq [NodeKind]::CreateFolder -or $s.Kind -eq [NodeKind]::DeleteFolder -or $s.Kind -eq [NodeKind]::CopyFolder -or $s.Kind -eq [NodeKind]::MoveFolder -or $s.Kind -eq [NodeKind]::GetFiles -or $s.Kind -eq [NodeKind]::GetFolders -or $s.Kind -eq [NodeKind]::RunProgram -or $s.Kind -eq [NodeKind]::HttpGet -or $s.Kind -eq [NodeKind]::HttpPost -or $s.Kind -eq [NodeKind]::HttpPut -or $s.Kind -eq [NodeKind]::HttpDelete) {
            return $true
        }
        if ($s.Kind -eq [NodeKind]::ReadJson) {
            # D60 Phase 1G: ReadJson does a real file read through the same
            # async otterReadFile(path) hook as ReadFile - ConvertToJson/
            # ConvertFromJson are pure in-memory data transforms and need
            # no await, so they are deliberately NOT listed here.
            return $true
        }
        if ($s.Kind -eq [NodeKind]::Assign -and (Test-OtterJsExpressionNeedsAsync $s.Value)) { return $true }
        if ($s.Kind -eq [NodeKind]::MathInto -and (Test-OtterJsExpressionNeedsAsync $s.Expression)) { return $true }
        if ($s.Kind -eq [NodeKind]::Return -and (Test-OtterJsExpressionNeedsAsync $s.Value)) { return $true }
        if ($s.Kind -eq [NodeKind]::Say) {
            # SayStmt's real field is Parts, not Values - a `say (file "x"
            # exists)`-style async subexpression inside a function body
            # was silently never detected here (PowerShell returns $null
            # for a nonexistent property rather than throwing, so
            # `foreach ($value in $s.Values)` looked like a working, just
            # always-empty, check - found by direct testing, not assumed).
            foreach ($value in $s.Parts) { if (Test-OtterJsExpressionNeedsAsync $value) { return $true } }
        }
        if ($s.Kind -eq [NodeKind]::If) {
            foreach ($branch in $s.Branches) {
                if (Test-OtterJsExpressionNeedsAsync $branch.Condition) { return $true }
                if (Test-OtterJsBodyNeedsAsync -Statements $branch.Body) { return $true }
            }
            if ($s.ElseBody -and (Test-OtterJsBodyNeedsAsync -Statements $s.ElseBody)) { return $true }
        }
        if ($s.Kind -eq [NodeKind]::While -and (Test-OtterJsExpressionNeedsAsync $s.Condition)) { return $true }
        if (($s.Kind -eq [NodeKind]::While -or $s.Kind -eq [NodeKind]::Repeat -or `
             $s.Kind -eq [NodeKind]::CountLoop -or $s.Kind -eq [NodeKind]::ForEach) -and `
            (Test-OtterJsBodyNeedsAsync -Statements $s.Body)) {
            return $true
        }
        if ($s.Kind -eq [NodeKind]::Try) {
            if (Test-OtterJsBodyNeedsAsync -Statements $s.Body) { return $true }
            if ($s.OtherwiseBody -and (Test-OtterJsBodyNeedsAsync -Statements $s.OtherwiseBody)) { return $true }
        }
    }
    return $false
}

# D60 Phase 1F.1. The "known top-level globals" a function's Set-style
# bindings must be checked against: a name with a top-level (outside any
# function) binding ANYWHERE in the program is a real global the
# interpreter's Set() would find and mutate, matching Otter's own
# sequential, non-hoisted execution model (there is no forward-reference
# problem to worry about here the way there was for FunctionDef's own
# temporal-dead-zone choice: a function can only ever be CALLED after
# every top-level statement that runs before that call site has already
# executed, so scanning the whole top-level program is the right
# approximation, not merely a convenient one - it is not, however, a full
# per-call-site dynamic check, which the interpreter's runtime chain walk
# technically is; a name whose only top-level binding occurs AFTER every
# call to a function that references it would still be treated here as a
# pre-existing global, which is a known, deliberate, documented remaining
# approximation, not a silently missed case).
function Get-OtterJsTopLevelGlobalNames {
    param([Node[]]$TopLevelStatements)

    $bindings = Get-OtterJsBindingNames -Statements $TopLevelStatements
    $all = [System.Collections.Generic.HashSet[string]]::new([string[]]$bindings.SetStyle)
    foreach ($n in $bindings.AlwaysLocal) { [void]$all.Add($n) }
    return @{ Names = $all }
}

Export-ModuleMember -Function `
    ConvertTo-OtterJsExpression, ConvertTo-OtterJsStatement, `
    Get-OtterJsBindingNames, Get-OtterJsTopLevelGlobalNames
