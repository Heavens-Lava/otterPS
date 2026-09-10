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

    # --- missing values (D22) -----------------------------------
    Gone            # user is gone   /   if user is not gone

    # --- discovery (D20, D21) -----------------------------------
    Get             # get files in "Pictures" into files
                    # ALSO: get "Jeff" from scores into score (D41)
    Files
    Folders
    Folder          # create folder "Backup"
    Subfolders      # ...in "Pictures" and subfolders
    Create

    # --- dynamic thing access (D41) ------------------------------
    Set             # set "Jeff" to 100 in scores

    # --- errors (D23) -------------------------------------------
    Try             # try / otherwise

    # --- strings and collections (D24, D25, D26) ----------------
    Length          # length of name / length of games
    Uppercase
    Lowercase
    First           # first of games
    Last
    Sort            # sort games
    Reverse
    StartsWith      # one token from the two words "starts with"
    EndsWith        # one token from the two words "ends with"
    Replace         # replace "Jeff" with "Jeffrey" in name
    With
    Split           # split sentence by " " into words
    By
    Join            # join words with ", " into text
    Find            # find file in files where ... into result
    Where

    # --- json, random, logging (D29, D30, D31) ------------------
    Json            # read json from "settings.json" into settings
    Convert         # convert user to json into text
    Random          # random number from 1 to 10 into number
    Item            # random item from games into game
    Log             # log "Server started."
    Warn
    Problem         # the "error" keyword - Error would shadow OtterError

    # --- dates and time (D32) -----------------------------------
    Today           # date is today
    Now             # started is now
    Between         # days between startDate and endDate make days
    Format          # format date as "MM/dd/yyyy" into text

    # Time units. ONE token each: the lexer accepts both the singular and
    # the plural spelling ("1 day", "7 days") and emits the same token, the
    # same way make/makes collapse to Make in D3.
    Year
    Month
    Day
    Hour
    Minute
    Second

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
    # --- properties (rules2.md section 2 - see D15) --------------
    Of              # name OF person       (replaces person.name)
    When            # when button is clicked   (reserved, UI milestone)

    # --- structure ----------------------------------------------
    Indent          # one level deeper (D7)
    Dedent          # one level shallower
    Newline         # end of a statement
    BlockEnd        # a period alone on a line (D4)
    EndOfFile       # end of source

    # There is deliberately NO Dot token. Outside a quoted string a period has
    # exactly one meaning - it closes the current block - and that is BlockEnd.
    # A period inside a number (3.14) never leaves the number lexer. A period
    # anywhere else is a syntax error, which is what lets the lexer say:
    #     Otter does not use periods to access properties.
    #     Try:  say name of person
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
    PropertyAccess  # name of person  (D19)

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
    # objects (0.3) - rules.md sections 27-28, rules2.md section 2
    ObjectDef       # person is a thing / nameBox is a text box / person has
    TypeDef         # a Person has

    # dynamic thing access (D41)
    GetKey          # get "Jeff" from scores into score
    SetKey          # set "Jeff" to 100 in scores

    ReadFile
    WriteFile
    CopyFile
    MoveFile
    DeleteFile
    FileExists      # an EXPRESSION: if file "x" exists
    RunProgram      # run "notepad.exe" / run command "git status"

    # discovery (D20, D21)
    GetFiles        # get files in "Pictures" into files
    GetFolders      # get folders in "Documents" into folders
    CreateFolder
    DeleteFolder
    CopyFolder
    MoveFolder

    # errors (D23)
    Try             # try / otherwise

    # strings and collections (D24, D25, D26)
    OfOperation     # length/uppercase/lowercase/first/last OF something
    TextMatch       # starts with / ends with
    Sort
    Reverse
    Replace
    Split
    Join
    Find

    # json, random, logging (D29, D30, D31)
    ReadJson
    ConvertToJson
    ConvertFromJson
    RandomNumber
    RandomItem
    Diagnostic      # log / warn / error

    # dates and time (D32)
    Clock           # today / now
    DateAdjust      # add 7 days to date / remove 1 month from date
    DateDifference  # days between startDate and endDate make days
    FormatDate      # format date as "MM/dd/yyyy" into text
}

enum MathOp { Add; Subtract; Multiply; Divide }

enum CompareOp { Equal; NotEqual; AtLeast; AtMost; GreaterThan; LessThan }

# D11: boolean operators. Precedence, loosest last: not -> and -> or.
enum LogicalOp { And; Or }

# D24: "X of Y" covers TWO different things, and they must not share a node.
#
#   name of file       a genuine PROPERTY of an object   -> PropertyAccessExpr
#   length of games    an OPERATION applied to a value   -> OfOperationExpr
#
# Pretending every list literally carries a "length" property would make the
# runtime object model strange to keep the grammar tidy. They share surface
# syntax and nothing else.
enum OfOperation { Length; Uppercase; Lowercase; First; Last }

# if name starts with "J"   /   if name ends with "Macy"
enum TextMatch { StartsWith; EndsWith }

# D32: "today" gives a date with no time of day; "now" gives a date AND a
# time. They are different enough that asking for "hour of" a plain date is a
# mistake worth reporting rather than answering with a silent zero.
enum ClockKind { Today; Now }

# D32: the unit in "add 7 days to date". Carried in the AST as an enum, so
# the parser never needs to know what kind of value the target holds - it
# reads the unit word and the shape is decided.
enum TimeUnit { Year; Month; Day; Hour; Minute; Second }

# D31: log / warn / error are DIAGNOSTIC output, separate from "say".
# "say" is what the program tells its user; these are what it tells its
# operator, and a runtime may send them somewhere else entirely.
enum DiagnosticLevel { Note; Warning; Problem }


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

# A fixed value: 29, "Hello", true, or gone.
#
# D22: "gone" is the absence of a value, and it is carried as $null in
# LiteralExpr.Value - it needs no node of its own. That is what makes
# "if user is gone" an ordinary comparison rather than special syntax.
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
# name of person        (D19 - "of" is a structural keyword, never filler)
#
# Property first, target second, matching how it reads aloud. Nesting is
# right-recursive, so
#
#     city of address of user
#
# builds
#
#     PropertyAccessExpr("city",
#         PropertyAccessExpr("address",
#             VariableExpr("user")))
#
# The interpreter never parses a property relationship out of a string - the
# structure is in the tree.
class PropertyAccessExpr : Node {
    [string]$Property
    [Node]$Target
    PropertyAccessExpr([string]$property, [Node]$target, [int]$line) : base([NodeKind]::PropertyAccess, $line) {
        $this.Property = $property
        $this.Target = $target
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
# name is "Jeff"            Target is a VariableExpr
# age of person is 30       Target is a PropertyAccessExpr
# text of message is "Hello"
#
# One node for all assignment, with an ASSIGNABLE TARGET rather than a bare
# name. Valid targets are VariableExpr and PropertyAccessExpr; adding list
# indexing later means adding a target type, not a second statement node.
class AssignStmt : Node {
    [Node]$Target
    [Node]$Value

    # Convenience form for the common case - "name is \"Jeff\"" - which builds
    # the VariableExpr for you. Kept so plain assignment stays a one-liner.
    AssignStmt([string]$name, [Node]$value, [int]$line) : base([NodeKind]::Assign, $line) {
        $this.Target = [VariableExpr]::new($name, $line)
        $this.Value = $value
    }

    AssignStmt([Node]$target, [Node]$value, [int]$line) : base([NodeKind]::Assign, $line) {
        $this.Target = $target
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
# OBJECTS (0.3)
# ===============================================================
#
# D15: properties are read as "name of person", never "person.name".
# The period is reserved for closing a block (rules2.md section 3).
#
# Property access is PropertyAccessExpr (see the expressions section), and
# property ASSIGNMENT is an ordinary AssignStmt whose Target happens to be a
# PropertyAccessExpr rather than a VariableExpr.

# person is a thing        nameBox is a text box
#     name is "Jeff"           placeholder is "Enter your name"
#     age is 29            .
# .
#
# Properties are ordinary AssignStmt nodes, so "name is \"Jeff\"" inside an
# object body parses exactly as it does anywhere else.
class ObjectDefStmt : Node {
    [string]$Name
    [string]$TypeName        # "thing", "text box", "button", "Person"
    [Node[]]$Properties      # AssignStmt nodes
    ObjectDefStmt([string]$name, [string]$typeName, [Node[]]$properties, [int]$line) : base([NodeKind]::ObjectDef, $line) {
        $this.Name = $name
        $this.TypeName = $typeName
        $this.Properties = $properties
    }
}

# a Person has
#     name
#     age
# .
class TypeDefStmt : Node {
    [string]$TypeName
    [string[]]$FieldNames
    TypeDefStmt([string]$typeName, [string[]]$fieldNames, [int]$line) : base([NodeKind]::TypeDef, $line) {
        $this.TypeName = $typeName
        $this.FieldNames = $fieldNames
    }
}


# ===============================================================
# DYNAMIC THING ACCESS (D41)
# ===============================================================
#
#     get "Jeff" from scores into score      - missing key -> gone, no error
#     set "Jeff" to 100 in scores             - creates or replaces
#
# Deliberately separate AST shapes from PropertyAccessExpr / AssignStmt,
# even though both reuse the exact same OtterObject underneath and need
# zero changes to that class (D41 investigation, verified empirically:
# ReadProperty/WriteProperty already take a plain string key with no
# concept of "static" vs "dynamic"). The two are kept apart because their
# FAILURE semantics are genuinely different intents, not implementation
# detail: `name of person` on a missing property is a mistake worth
# stopping on; `get "key" from thing into x` on a missing key is an
# ordinary, expected "not there" answer (gone). Folding both into one node
# with a runtime branch would hide that difference; two small honest nodes
# keep it visible in the AST itself.
#
# Key and Target are both full expressions - Key is NOT restricted to a
# string literal, e.g. `get name of user from scores into x` is legal
# syntax. Whether the key value it evaluates to must be text is a runtime
# rule (D41: string-only for 0.1), not a parse-time restriction.
#
# Restricted at runtime to TypeName == 'thing' - files, folders, and any
# other domain/resource OtterObject refuse dynamic access (D41).

class GetKeyStmt : Node {
    [Node]$Key
    [Node]$Target
    [string]$ResultTarget
    GetKeyStmt([Node]$key, [Node]$target, [string]$resultTarget, [int]$line) : base([NodeKind]::GetKey, $line) {
        $this.Key = $key
        $this.Target = $target
        $this.ResultTarget = $resultTarget
    }
}

class SetKeyStmt : Node {
    [Node]$Key
    [Node]$Value
    [Node]$Target
    SetKeyStmt([Node]$key, [Node]$value, [Node]$target, [int]$line) : base([NodeKind]::SetKey, $line) {
        $this.Key = $key
        $this.Value = $value
        $this.Target = $target
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
# DISCOVERY (D20, D21)
# ===============================================================
#
#     get files in "Pictures" into files
#     get files in "Pictures" and subfolders into files
#     get folders in "Documents" into folders
#
# Both produce a list of objects - file objects and folder objects - so the
# result drops straight into "for each file in files".
#
# D21: discovery is NON-RECURSIVE by default. "and subfolders" is the only
# way to walk downward, because silently reading an entire drive because
# someone typed a folder name is exactly the surprise the language should
# not have.

class GetFilesStmt : Node {
    [Node]$Folder
    [bool]$IncludeSubfolders
    [string]$Target
    GetFilesStmt([Node]$folder, [bool]$includeSubfolders, [string]$target, [int]$line) : base([NodeKind]::GetFiles, $line) {
        $this.Folder = $folder
        $this.IncludeSubfolders = $includeSubfolders
        $this.Target = $target
    }
}

class GetFoldersStmt : Node {
    [Node]$Folder
    [bool]$IncludeSubfolders
    [string]$Target
    GetFoldersStmt([Node]$folder, [bool]$includeSubfolders, [string]$target, [int]$line) : base([NodeKind]::GetFolders, $line) {
        $this.Folder = $folder
        $this.IncludeSubfolders = $includeSubfolders
        $this.Target = $target
    }
}

# create folder "Backup"
class CreateFolderStmt : Node {
    [Node]$Path
    CreateFolderStmt([Node]$path, [int]$line) : base([NodeKind]::CreateFolder, $line) {
        $this.Path = $path
    }
}

# delete folder "Backup"
class DeleteFolderStmt : Node {
    [Node]$Path
    DeleteFolderStmt([Node]$path, [int]$line) : base([NodeKind]::DeleteFolder, $line) {
        $this.Path = $path
    }
}

# copy folder "Work" to "Backup"
class CopyFolderStmt : Node {
    [Node]$Source
    [Node]$Destination
    CopyFolderStmt([Node]$source, [Node]$destination, [int]$line) : base([NodeKind]::CopyFolder, $line) {
        $this.Source = $source
        $this.Destination = $destination
    }
}

# move folder "Work" to "Archive"
class MoveFolderStmt : Node {
    [Node]$Source
    [Node]$Destination
    MoveFolderStmt([Node]$source, [Node]$destination, [int]$line) : base([NodeKind]::MoveFolder, $line) {
        $this.Source = $source
        $this.Destination = $destination
    }
}


# ===============================================================
# ERROR HANDLING (D23)
# ===============================================================
#
#     try
#         read "settings.json" into settings
#     otherwise
#         say "Could not load settings."
#     .
#
# The beginner form: if anything in the body fails, run the otherwise body
# instead. No error variable, no error types - those come later if needed.
#
# A "return" inside a try body is NOT an error and must escape cleanly.

class TryStmt : Node {
    [Node[]]$Body
    [Node[]]$OtherwiseBody
    TryStmt([Node[]]$body, [Node[]]$otherwiseBody, [int]$line) : base([NodeKind]::Try, $line) {
        $this.Body = $body
        $this.OtherwiseBody = $otherwiseBody
    }
}


# ===============================================================
# STRINGS AND COLLECTIONS (D24, D25, D26)
# ===============================================================

# length of name    length of games    uppercase of name
# first of games    last of games
#
# D24: an OPERATION, not a property. The parser decides which node to build
# from the WORD before "of" - the operation words are a fixed, known set.
class OfOperationExpr : Node {
    [OfOperation]$Operation
    [Node]$Subject
    OfOperationExpr([OfOperation]$operation, [Node]$subject, [int]$line) : base([NodeKind]::OfOperation, $line) {
        $this.Operation = $operation
        $this.Subject = $subject
    }
}

# if name starts with "J"   /   if name ends with "Macy"
class TextMatchExpr : Node {
    [Node]$Subject
    [TextMatch]$Match
    [Node]$Value
    TextMatchExpr([Node]$subject, [TextMatch]$match, [Node]$value, [int]$line) : base([NodeKind]::TextMatch, $line) {
        $this.Subject = $subject
        $this.Match = $match
        $this.Value = $value
    }
}

# sort games      - changes the list in place, like "add 5 to score" does
class SortStmt : Node {
    [string]$Target
    SortStmt([string]$target, [int]$line) : base([NodeKind]::Sort, $line) { $this.Target = $target }
}

# reverse games
class ReverseStmt : Node {
    [string]$Target
    ReverseStmt([string]$target, [int]$line) : base([NodeKind]::Reverse, $line) { $this.Target = $target }
}

# replace "Jeff" with "Jeffrey" in name                    - changes name
# replace "Jeff" with "Jeffrey" in name into fullName      - leaves name alone
#
# D27: rules3 section 26 says the original must not be mutated unless the
# syntax asks for it. Naming a destination with "into" is what asks for the
# other behaviour: with "into" the source is untouched and the result lands
# in ResultTarget; without it, "in name" names the thing being changed.
class ReplaceStmt : Node {
    [Node]$Find
    [Node]$Replacement
    [string]$Target
    [string]$ResultTarget      # $null when the source is being changed in place

    ReplaceStmt([Node]$find, [Node]$replacement, [string]$target, [int]$line) : base([NodeKind]::Replace, $line) {
        $this.Find = $find
        $this.Replacement = $replacement
        $this.Target = $target
        $this.ResultTarget = $null
    }

    ReplaceStmt([Node]$find, [Node]$replacement, [string]$target, [string]$resultTarget, [int]$line) : base([NodeKind]::Replace, $line) {
        $this.Find = $find
        $this.Replacement = $replacement
        $this.Target = $target
        $this.ResultTarget = $resultTarget
    }
}

# split sentence by " " into words
class SplitStmt : Node {
    [Node]$Subject
    [Node]$Separator
    [string]$Target
    SplitStmt([Node]$subject, [Node]$separator, [string]$target, [int]$line) : base([NodeKind]::Split, $line) {
        $this.Subject = $subject
        $this.Separator = $separator
        $this.Target = $target
    }
}

# join words with ", " into text
class JoinStmt : Node {
    [Node]$Subject
    [Node]$Separator
    [string]$Target
    JoinStmt([Node]$subject, [Node]$separator, [string]$target, [int]$line) : base([NodeKind]::Join, $line) {
        $this.Subject = $subject
        $this.Separator = $separator
        $this.Target = $target
    }
}

# find file in files where extension of file is ".pdf" into result
#
# D26: SINGULAR "find" returns the FIRST match, or gone when nothing matches.
# That is what ties collections to D22 - "if result is gone" is the natural
# way to ask whether anything was found.
#
# ItemName is bound for the Condition only, exactly like a for-each variable.
class FindStmt : Node {
    [string]$ItemName
    [Node]$Collection
    [Node]$Condition
    [string]$Target
    FindStmt([string]$itemName, [Node]$collection, [Node]$condition, [string]$target, [int]$line) : base([NodeKind]::Find, $line) {
        $this.ItemName = $itemName
        $this.Collection = $collection
        $this.Condition = $condition
        $this.Target = $target
    }
}


# ===============================================================
# JSON, RANDOM, DIAGNOSTICS (D29, D30, D31)
# ===============================================================

# read json from "settings.json" into settings
class ReadJsonStmt : Node {
    [Node]$Path
    [string]$Target
    ReadJsonStmt([Node]$path, [string]$target, [int]$line) : base([NodeKind]::ReadJson, $line) {
        $this.Path = $path
        $this.Target = $target
    }
}

# convert user to json into text
class ConvertToJsonStmt : Node {
    [Node]$Subject
    [string]$Target
    ConvertToJsonStmt([Node]$subject, [string]$target, [int]$line) : base([NodeKind]::ConvertToJson, $line) {
        $this.Subject = $subject
        $this.Target = $target
    }
}

# convert text from json into user
class ConvertFromJsonStmt : Node {
    [Node]$Subject
    [string]$Target
    ConvertFromJsonStmt([Node]$subject, [string]$target, [int]$line) : base([NodeKind]::ConvertFromJson, $line) {
        $this.Subject = $subject
        $this.Target = $target
    }
}

# random number from 1 to 10 into number
class RandomNumberStmt : Node {
    [Node]$From
    [Node]$To
    [string]$Target
    RandomNumberStmt([Node]$from, [Node]$to, [string]$target, [int]$line) : base([NodeKind]::RandomNumber, $line) {
        $this.From = $from
        $this.To = $to
        $this.Target = $target
    }
}

# random item from games into game     - gone when the list is empty
class RandomItemStmt : Node {
    [Node]$Collection
    [string]$Target
    RandomItemStmt([Node]$collection, [string]$target, [int]$line) : base([NodeKind]::RandomItem, $line) {
        $this.Collection = $collection
        $this.Target = $target
    }
}

# log "Server started."   /   warn "..."   /   error "..."
class DiagnosticStmt : Node {
    [DiagnosticLevel]$Level
    [Node[]]$Parts
    DiagnosticStmt([DiagnosticLevel]$level, [Node[]]$parts, [int]$line) : base([NodeKind]::Diagnostic, $line) {
        $this.Level = $level
        $this.Parts = $parts
    }
}


# ===============================================================
# DATES AND TIME (D32)
# ===============================================================
#
#     date is today
#     started is now
#
#     year of date          month of date        day of date
#     hour of started       minute of started    second of started
#
#     add 7 days to date
#     remove 1 month from date
#     add 30 minutes to started
#
#     format date as "MM/dd/yyyy" into text
#     days between startDate and endDate make days
#
# A date is a FIRST-CLASS VALUE, never text. See D32 for why that matters and
# for the one thing this deliberately does NOT add: a node for reading
# "year of date".
#
# Reading a date part is an ORDINARY PropertyAccessExpr. It is not an
# OfOperationExpr and it needs no node of its own, because "year" cannot be
# reserved as an operation word without breaking this:
#
#     book is a thing
#         year is 1984
#     .
#     say year of book
#
# The interpreter answers year/month/day/hour/minute/second on a date value
# and looks up a stored property on anything else.

# today   /   now
#
# The property is called Clock, NOT Kind. Every Node already has a Kind - its
# NodeKind - and PowerShell 5.1 cannot shadow a base property with a
# different type. Declaring [ClockKind]$Kind here made the class impossible
# to construct: the base constructor set Kind to NodeKind::Clock and the
# derived assignment then tried to read that back as a ClockKind.
#
# Rule for anything added to this file later: no Node subclass may declare a
# property named Kind.
class ClockExpr : Node {
    [ClockKind]$Clock
    ClockExpr([ClockKind]$clock, [int]$line) : base([NodeKind]::Clock, $line) {
        $this.Clock = $clock
    }
}

# add 7 days to date        IsRemoval = $false
# remove 1 month from date  IsRemoval = $true
#
# Structurally distinct from AddToStmt (D12) on purpose. The unit word is
# what separates them, and it is present in the token stream, so the parser
# decides the shape without ever knowing what the target holds:
#
#     add 5 to score            -> AddToStmt        (no unit)
#     add 5 days to startDate   -> DateAdjustStmt   (unit: Day)
class DateAdjustStmt : Node {
    [Node]$Amount
    [TimeUnit]$Unit
    [string]$Target
    [bool]$IsRemoval
    DateAdjustStmt([Node]$amount, [TimeUnit]$unit, [string]$target, [bool]$isRemoval, [int]$line) : base([NodeKind]::DateAdjust, $line) {
        $this.Amount = $amount
        $this.Unit = $unit
        $this.Target = $target
        $this.IsRemoval = $isRemoval
    }
}

# days between startDate and endDate make days
#
# Unit is carried so "hours between" and "minutes between" need no new node
# when they arrive - only a lexer word.
class DateDifferenceStmt : Node {
    [TimeUnit]$Unit
    [Node]$Start
    [Node]$End
    [string]$Target
    DateDifferenceStmt([TimeUnit]$unit, [Node]$start, [Node]$end, [string]$target, [int]$line) : base([NodeKind]::DateDifference, $line) {
        $this.Unit = $unit
        $this.Start = $start
        $this.End = $end
        $this.Target = $target
    }
}

# format date as "MM/dd/yyyy" into text
#
# Produces text and leaves the date exactly as it was, the same way
# "uppercase of name" leaves name alone (rules3 section 22).
class FormatDateStmt : Node {
    [Node]$Subject
    [Node]$Format
    [string]$Target
    FormatDateStmt([Node]$subject, [Node]$format, [string]$target, [int]$line) : base([NodeKind]::FormatDate, $line) {
        $this.Subject = $subject
        $this.Format = $format
        $this.Target = $target
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
