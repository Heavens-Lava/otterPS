# Otter.Contract.psm1
#
# THE CONTRACT between Otter's two halves.
#
#   front end (lexer + parser)  produces  ->  Token[]  then  Node tree
#   back end  (interpreter)     consumes  <-
#
# Both halves import this file with `using module .\Otter.Contract.psm1`,
# which makes these classes the SAME .NET type on both sides. That is what
# lets two agents work on the two halves at once without talking.
#
# WHY THIS FILE LIVES AT THE REPO ROOT AND NOT IN src/Contract/:
# PowerShell 5.1 only shares classes across files via `using module`, which
# needs a stable relative path literal. The front end already imports it from
# here. Moving it breaks every importer at once, so the path is frozen too.
#
# RULE: do not add, rename, or change anything in this file on your own.
# Contract changes go through Jeff, and both agents pull before continuing.
# Additions are safe; renames and signature changes are not.
#
# See SPEC-DECISIONS.md for the language questions this encodes (D1-D14).


# ===============================================================
# TOKENS - what the lexer produces
# ===============================================================

enum TokenKind {
    # --- values -------------------------------------------------
    Identifier      # score, loggedIn, person
    Number          # 29, 3.5
    String          # "Hello world!"
    True            # true
    False           # false

    # --- comparison (D2: these only appear inside conditions) ----
    Is              # equal to        (also assignment - see D2)
    IsNot           # not equal to
    IsAtLeast       # >=
    IsAtMost        # <=
    IsGreaterThan   # >
    IsLessThan      # <

    # --- math ---------------------------------------------------
    And             # 5 and 5 make total  (addition)  AND  boolean and (D11)
    Minus           # 10 minus 5
    Times           # 10 times 5   AND   repeat 3 times
    DividedBy       # 10 divided by 5
    Make            # make / makes are one token (D3)

    # --- boolean logic (brief section 13 - see D11) --------------
    Or              # if admin or moderator
    Not             # if not loggedIn

    # --- mutation -----------------------------------------------
    Add             # add 5 to score   AND   add "Pokemon" to games (D12)
    Remove          # remove 2 from score
    To              # add..to, to greet, count..to
    From            # remove..from, count from

    # --- input / output -----------------------------------------
    Say             # say "Hello"
    Ask             # ask "..." and call it name
    Call            # ...and CALL it name
    It              # ...and call IT name

    # --- control flow -------------------------------------------
    If
    Otherwise
    While
    Repeat
    Count           # count from 1 to 5 as number (D5)
    As
    ForEach         # lexed as ONE token from the two words "for each"
    In
    Return

    # --- lists --------------------------------------------------
    Are             # games are
    Empty           # games are empty (D13)
    Contains        # if games contains "Zelda" (D13)

    # --- reserved for 0.3 / 0.4 (lexed now, not yet parsed) ------
    A               # jeff is A Person
    Thing           # person is a THING
    Has             # a Person HAS
    Read            # read "notes.txt" into notes
    Write
    Copy
    Move
    Delete
    File
    Exists
    Into
    Run
    Command
    Open            # open "notes.txt"

    # --- structure ----------------------------------------------
    Indent          # one level deeper (D7)
    Dedent          # one level shallower
    Newline         # end of a statement
    BlockEnd        # a period alone on a line (D4)
    Dot             # member access: person.name (D4, used in 0.3)
    EndOfFile       # end of source
}

class Token {
    [TokenKind]$Kind
    [string]$Text      # the exact source text
    [object]$Value     # decoded value: number as [double], string without quotes
    [int]$Line         # 1-based, for error messages
    [int]$Column       # 1-based

    Token([TokenKind]$kind, [string]$text, [object]$value, [int]$line, [int]$column) {
        $this.Kind = $kind
        $this.Text = $text
        $this.Value = $value
        $this.Line = $line
        $this.Column = $column
    }

    [string] ToString() {
        return "$($this.Kind)[$($this.Text)] L$($this.Line)"
    }
}


# ===============================================================
# AST - what the parser produces and the interpreter walks
# ===============================================================

enum NodeKind {
    Program

    # expressions
    Literal
    Variable
    Math
    Comparison
    Call
    Logical         # and / or        (D11)
    Not             # not             (D11)
    Contains        # games contains "Zelda"  (D13)
    MemberAccess    # person.name     (reserved, 0.3)

    # statements
    Say
    Assign
    Ask
    MathInto
    AddTo
    RemoveFrom
    If
    While
    Repeat
    CountLoop
    ForEach
    ListDef
    FunctionDef
    CallStatement
    Return

    # runtime library (milestone 7) - rules.md sections 30-31
    ReadFile
    WriteFile
    CopyFile
    MoveFile
    DeleteFile
    FileExists      # an EXPRESSION: if file "x" exists
    RunProgram      # run "notepad.exe" / run command "git status"
}

enum MathOp { Add; Subtract; Multiply; Divide }

enum CompareOp { Equal; NotEqual; AtLeast; AtMost; GreaterThan; LessThan }

# D11: boolean operators. Precedence, loosest last: not -> and -> or.
enum LogicalOp { And; Or }


# --- base -------------------------------------------------------

class Node {
    [NodeKind]$Kind
    [int]$Line

    Node([NodeKind]$kind, [int]$line) {
        $this.Kind = $kind
        $this.Line = $line
    }

    [string] ToString() { return "$($this.Kind)@L$($this.Line)" }
}


# --- expressions ------------------------------------------------

# A fixed value: 29, "Hello", true
class LiteralExpr : Node {
    [object]$Value
    LiteralExpr([object]$value, [int]$line) : base([NodeKind]::Literal, $line) {
        $this.Value = $value
    }
}

# Reading a variable: score
class VariableExpr : Node {
    [string]$Name
    VariableExpr([string]$name, [int]$line) : base([NodeKind]::Variable, $line) {
        $this.Name = $name
    }
}

# 5 and 5   /   10 minus 5   /   10 times 5   /   10 divided by 5
class MathExpr : Node {
    [Node]$Left
    [MathOp]$Op
    [Node]$Right
    MathExpr([Node]$left, [MathOp]$op, [Node]$right, [int]$line) : base([NodeKind]::Math, $line) {
        $this.Left = $left
        $this.Op = $op
        $this.Right = $right
    }
}

# age is at least 18
class ComparisonExpr : Node {
    [Node]$Left
    [CompareOp]$Op
    [Node]$Right
    ComparisonExpr([Node]$left, [CompareOp]$op, [Node]$right, [int]$line) : base([NodeKind]::Comparison, $line) {
        $this.Left = $left
        $this.Op = $op
        $this.Right = $right
    }
}

# if loggedIn and admin   /   if admin or moderator      (D11)
class LogicalExpr : Node {
    [Node]$Left
    [LogicalOp]$Op
    [Node]$Right
    LogicalExpr([Node]$left, [LogicalOp]$op, [Node]$right, [int]$line) : base([NodeKind]::Logical, $line) {
        $this.Left = $left
        $this.Op = $op
        $this.Right = $right
    }
}

# if not loggedIn                                        (D11)
class NotExpr : Node {
    [Node]$Operand
    NotExpr([Node]$operand, [int]$line) : base([NodeKind]::Not, $line) {
        $this.Operand = $operand
    }
}

# if games contains "Zelda"                              (D13)
class ContainsExpr : Node {
    [Node]$Collection
    [Node]$Item
    ContainsExpr([Node]$collection, [Node]$item, [int]$line) : base([NodeKind]::Contains, $line) {
        $this.Collection = $collection
        $this.Item = $item
    }
}

# person.name           (reserved for 0.3 - lexed and parsed, not yet run)
class MemberAccessExpr : Node {
    [Node]$Target
    [string]$MemberName
    MemberAccessExpr([Node]$target, [string]$memberName, [int]$line) : base([NodeKind]::MemberAccess, $line) {
        $this.Target = $target
        $this.MemberName = $memberName
    }
}

# greet "Jeff"   /   double 5   (used as a value)
class CallExpr : Node {
    [string]$Name
    [Node[]]$Arguments
    CallExpr([string]$name, [Node[]]$arguments, [int]$line) : base([NodeKind]::Call, $line) {
        $this.Name = $name
        $this.Arguments = $arguments
    }
}


# --- statements -------------------------------------------------

class ProgramNode : Node {
    [Node[]]$Statements
    ProgramNode([Node[]]$statements) : base([NodeKind]::Program, 1) {
        $this.Statements = $statements
    }
}

# say "Hello" name   -> one expression per value (D8: joined by one space)
class SayStmt : Node {
    [Node[]]$Parts
    SayStmt([Node[]]$parts, [int]$line) : base([NodeKind]::Say, $line) {
        $this.Parts = $parts
    }
}

# name is "Jeff"
class AssignStmt : Node {
    [string]$Name
    [Node]$Value
    AssignStmt([string]$name, [Node]$value, [int]$line) : base([NodeKind]::Assign, $line) {
        $this.Name = $name
        $this.Value = $value
    }
}

# ask "What is your name?" and call it name
class AskStmt : Node {
    [Node]$Prompt
    [string]$Name
    AskStmt([Node]$prompt, [string]$name, [int]$line) : base([NodeKind]::Ask, $line) {
        $this.Prompt = $prompt
        $this.Name = $name
    }
}

# number1 and number2 make total
class MathIntoStmt : Node {
    [Node]$Expression
    [string]$Target
    MathIntoStmt([Node]$expression, [string]$target, [int]$line) : base([NodeKind]::MathInto, $line) {
        $this.Expression = $expression
        $this.Target = $target
    }
}

# add 5 to score          -> numeric mutation
# add "Pokemon" to games  -> list append
# D12: ONE node for both. The interpreter dispatches on the target's runtime
# type, so the parser never has to know which one it is.
class AddToStmt : Node {
    [Node]$Amount
    [string]$Target
    AddToStmt([Node]$amount, [string]$target, [int]$line) : base([NodeKind]::AddTo, $line) {
        $this.Amount = $amount
        $this.Target = $target
    }
}

# remove 2 from score      -> numeric mutation
# remove "Mario" from games -> list removal        (D12, same as above)
class RemoveFromStmt : Node {
    [Node]$Amount
    [string]$Target
    RemoveFromStmt([Node]$amount, [string]$target, [int]$line) : base([NodeKind]::RemoveFrom, $line) {
        $this.Amount = $amount
        $this.Target = $target
    }
}

# One arm of an if: the "if" itself, or an "otherwise if".
class IfBranch {
    [Node]$Condition
    [Node[]]$Body
    IfBranch([Node]$condition, [Node[]]$body) {
        $this.Condition = $condition
        $this.Body = $body
    }
}

# if / otherwise if / otherwise
#   Branches[0] is the "if"; any further entries are "otherwise if" arms.
#   ElseBody is $null when there is no bare "otherwise".
class IfStmt : Node {
    [IfBranch[]]$Branches
    [Node[]]$ElseBody
    IfStmt([IfBranch[]]$branches, [Node[]]$elseBody, [int]$line) : base([NodeKind]::If, $line) {
        $this.Branches = $branches
        $this.ElseBody = $elseBody
    }
}

# while number is less than 5
class WhileStmt : Node {
    [Node]$Condition
    [Node[]]$Body
    WhileStmt([Node]$condition, [Node[]]$body, [int]$line) : base([NodeKind]::While, $line) {
        $this.Condition = $condition
        $this.Body = $body
    }
}

# repeat 3 times
class RepeatStmt : Node {
    [Node]$Count
    [Node[]]$Body
    RepeatStmt([Node]$count, [Node[]]$body, [int]$line) : base([NodeKind]::Repeat, $line) {
        $this.Count = $count
        $this.Body = $body
    }
}

# count from 1 to 5 as number     (D5: inclusive at both ends)
class CountStmt : Node {
    [string]$VariableName
    [Node]$From
    [Node]$To
    [Node[]]$Body
    CountStmt([string]$variableName, [Node]$from, [Node]$to, [Node[]]$body, [int]$line) : base([NodeKind]::CountLoop, $line) {
        $this.VariableName = $variableName
        $this.From = $from
        $this.To = $to
        $this.Body = $body
    }
}

# for each game in games
class ForEachStmt : Node {
    [string]$VariableName
    [Node]$Collection
    [Node[]]$Body
    ForEachStmt([string]$variableName, [Node]$collection, [Node[]]$body, [int]$line) : base([NodeKind]::ForEach, $line) {
        $this.VariableName = $variableName
        $this.Collection = $collection
        $this.Body = $body
    }
}

# games are
#     "Zelda"
#
# "games are empty" produces this node with an empty Items array. (D13)
class ListDefStmt : Node {
    [string]$Name
    [Node[]]$Items
    ListDefStmt([string]$name, [Node[]]$items, [int]$line) : base([NodeKind]::ListDef, $line) {
        $this.Name = $name
        $this.Items = $items
    }
}

# to greet name
class FunctionDefStmt : Node {
    [string]$Name
    [string[]]$Parameters
    [Node[]]$Body
    FunctionDefStmt([string]$name, [string[]]$parameters, [Node[]]$body, [int]$line) : base([NodeKind]::FunctionDef, $line) {
        $this.Name = $name
        $this.Parameters = $parameters
        $this.Body = $body
    }
}

# greet "Jeff"              -> ResultTarget is $null
# double 5 make result      -> ResultTarget is "result"
class CallStmt : Node {
    [CallExpr]$Call
    [string]$ResultTarget
    CallStmt([CallExpr]$call, [string]$resultTarget, [int]$line) : base([NodeKind]::CallStatement, $line) {
        $this.Call = $call
        $this.ResultTarget = $resultTarget
    }
}

# return answer
class ReturnStmt : Node {
    [Node]$Value
    ReturnStmt([Node]$value, [int]$line) : base([NodeKind]::Return, $line) {
        $this.Value = $value
    }
}


# ===============================================================
# RUNTIME LIBRARY (milestone 7)
# ===============================================================
#
# These reach outside the program - the file system and other processes.
# They are statements like any other; all the platform work lives in
# src/Otter.Library.psm1 so the grammar stays small (rules.md section 27).

# read "notes.txt" into notes
class ReadFileStmt : Node {
    [Node]$Path
    [string]$Target
    ReadFileStmt([Node]$path, [string]$target, [int]$line) : base([NodeKind]::ReadFile, $line) {
        $this.Path = $path
        $this.Target = $target
    }
}

# write "Hello!" to "hello.txt"      (replaces the file's contents)
class WriteFileStmt : Node {
    [Node]$Content
    [Node]$Path
    WriteFileStmt([Node]$content, [Node]$path, [int]$line) : base([NodeKind]::WriteFile, $line) {
        $this.Content = $content
        $this.Path = $path
    }
}

# copy "hello.txt" to "backup/hello.txt"
class CopyFileStmt : Node {
    [Node]$Source
    [Node]$Destination
    CopyFileStmt([Node]$source, [Node]$destination, [int]$line) : base([NodeKind]::CopyFile, $line) {
        $this.Source = $source
        $this.Destination = $destination
    }
}

# move "hello.txt" to "Documents"
class MoveFileStmt : Node {
    [Node]$Source
    [Node]$Destination
    MoveFileStmt([Node]$source, [Node]$destination, [int]$line) : base([NodeKind]::MoveFile, $line) {
        $this.Source = $source
        $this.Destination = $destination
    }
}

# delete file "hello.txt"
class DeleteFileStmt : Node {
    [Node]$Path
    DeleteFileStmt([Node]$path, [int]$line) : base([NodeKind]::DeleteFile, $line) {
        $this.Path = $path
    }
}

# if file "hello.txt" exists       - an EXPRESSION, used inside a condition
class FileExistsExpr : Node {
    [Node]$Path
    FileExistsExpr([Node]$path, [int]$line) : base([NodeKind]::FileExists, $line) {
        $this.Path = $path
    }
}

# run "notepad.exe"                       IsCommand = $false
# run command "git status"                IsCommand = $true
# run command "git status" into result    IsCommand = $true, ResultTarget set
#
# ResultTarget is $null when the program's output is not captured.
class RunStmt : Node {
    [Node]$Target
    [bool]$IsCommand
    [string]$ResultTarget
    RunStmt([Node]$target, [bool]$isCommand, [string]$resultTarget, [int]$line) : base([NodeKind]::RunProgram, $line) {
        $this.Target = $target
        $this.IsCommand = $isCommand
        $this.ResultTarget = $resultTarget
    }
}


# ===============================================================
# ERRORS - both halves report problems the same way
# ===============================================================
#
# Otter errors are written for beginners (brief section 32). A good one shows
# what went wrong, where, the actual source line, and what to try instead:
#
#   Otter Syntax Error
#
#   Line 4:
#       if age is greater 18
#
#   Otter expected "than" after "greater".
#
#   Try:
#       if age is greater than 18
#
# Raw PowerShell exceptions must never reach a normal Otter user.

class OtterError : System.Exception {
    [int]$Line
    [string]$Stage        # 'lexer' | 'parser' | 'runtime'
    [int]$Column          # 0 when unknown
    [string]$SourceLine   # the offending line of source, if known
    [string]$Suggestion   # "Try: ..." text, if we can offer one

    # Original 3-argument form. KEPT so existing front-end code keeps working.
    OtterError([string]$message, [int]$line, [string]$stage) : base($message) {
        $this.Line = $line
        $this.Stage = $stage
        $this.Column = 0
        $this.SourceLine = $null
        $this.Suggestion = $null
    }

    # Richer form for beginner-friendly messages.
    OtterError([string]$message, [int]$line, [string]$stage, [int]$column, [string]$sourceLine, [string]$suggestion) : base($message) {
        $this.Line = $line
        $this.Stage = $stage
        $this.Column = $column
        $this.SourceLine = $sourceLine
        $this.Suggestion = $suggestion
    }

    # Short one-line form, used by the REPL.
    [string] Format() {
        if ($this.Line -gt 0) {
            return "Otter: $($this.Message) (line $($this.Line))"
        }
        return "Otter: $($this.Message)"
    }

    # Full block form, used when running a script file.
    [string] FormatDetailed() {
        $heading = switch ($this.Stage) {
            'lexer'   { 'Otter Syntax Error' }
            'parser'  { 'Otter Syntax Error' }
            'runtime' { 'Otter Runtime Error' }
            default   { 'Otter Error' }
        }

        $out = [System.Text.StringBuilder]::new()
        [void]$out.AppendLine($heading)
        [void]$out.AppendLine('')

        if ($this.Line -gt 0) {
            [void]$out.AppendLine("Line $($this.Line):")
            if ($this.SourceLine) {
                [void]$out.AppendLine("    $($this.SourceLine.Trim())")
            }
            [void]$out.AppendLine('')
        }

        [void]$out.AppendLine($this.Message)

        if ($this.Suggestion) {
            [void]$out.AppendLine('')
            [void]$out.AppendLine('Try:')
            [void]$out.AppendLine("    $($this.Suggestion)")
        }

        return $out.ToString().TrimEnd()
    }
}
