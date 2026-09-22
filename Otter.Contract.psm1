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

    # --- errors (D23, D68) ----------------------------------------
    Try             # try / otherwise
    Fail            # fail with "message" - a real user-raised error (D68)

    # --- process management (D70, D71) ------------------------------
    Kill            # kill process p / kill process p and its children
    Wait            # wait for process p up to 5 seconds

    # --- power/session actions (D82) ---------------------------------
    Lock            # lock the computer
    Sign            # sign out
    Restart         # restart the computer
    Shut            # shut down the computer

    # --- printers (D83) -------------------------------------------------
    Print           # print "file.txt" to "PrinterName"

    # --- ZIP/archive provider (D87) --------------------------------------
    Zip             # zip folder "src" into "archive.zip"
    Unzip           # unzip "archive.zip" into "dest"

    # --- math operators (D88) ---------------------------------------------
    Percent         # X percent of Y
    Power           # X power Y

    # --- more math operations (D89) ----------------------------------------
    AbsoluteValue   # absolute value of X
    SquareRoot      # square root of X
    Round           # round of X
    RoundUp         # round up of X (ceiling)
    RoundDown       # round down of X (floor)
    Larger          # larger of X and Y
    Smaller         # smaller of X and Y

    # --- trigonometry, logarithms (D90) -------------------------------------
    Sine            # sine of X (X in degrees)
    Cosine          # cosine of X (X in degrees)
    Tangent         # tangent of X (X in degrees)
    LogTen          # log of X (base 10)
    NaturalLog      # natural log of X (base e)

    # --- hashing/HMAC (D91) --------------------------------------------------
    Hash            # hash "text" as "sha256" into digest
                    # hash "text" as "sha256" with key "secret" into digest (HMAC)

    # --- symmetric encryption (D92) -------------------------------------------
    Encrypt         # encrypt "text" with key "secret" into cipher
    Decrypt         # decrypt "cipher" with key "secret" into text

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

    # --- json, csv, random, logging (D29, D30, D31, D95) --------
    Json            # read json from "settings.json" into settings
    Csv             # read csv from "customers.csv" into customers
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
    Append          # append "line" to "notes.txt" (D61)
    Copy
    Move
    Delete
    File
    Exists
    Notify          # notify "Title" with "Message" (D67)
    Choose          # choose file/folder into path (D67)
    Into
    Run
    Command
    Open            # open "notes.txt"

    # --- structure ----------------------------------------------
    # --- properties (rules2.md section 2 - see D15) --------------
    Of              # name OF person       (replaces person.name)
    When            # when button is clicked   (reserved, UI milestone)
    Put             # put helloButton in app          (D47)
    Show            # show app                        (D47)

    # --- networking & http (D49, D96) ---------------------------
    Post            # post data to "https://..." into result
    Download        # download file from <url> to <path> (D96)

    # --- database provider (D97) --------------------------------
    Connect         # connect database into db
    Disconnect      # disconnect db
    Query           # query db with ... into tasks
    Execute         # execute db with ... into result
    BeginTransaction # begin transaction on db into tx
    Commit          # commit tx
    Rollback        # rollback tx
    Parameter       # parameter "name" is value

    # --- console UX primitives (D100) ----------------------------
    ConsoleInteractive  # console is interactive - one combined token for
                        # the whole fixed phrase (matches Contains/IsAtLeast
                        # precedent), so "console" stays an ordinary,
                        # unreserved identifier everywhere else.


    # --- web servers & api routes (D51) -------------------------
    Respond         # respond with "..." as json and status 200
    Receives        # when api receives GET at "/users"
    At              # ...at "/path"
    Start           # start api
    Listen          # listen on port 8080

    # --- declarative UI, reactivity, animation (D56) ------------
    Layout          # layout row / layout column / layout cards
    Gap             # gap 20
    State           # state count is 0
    Derive          # derive total is price * quantity
    Memo            # memo sortedItems
    On              # on start / on close
    Await           # await get "/api/products"
    Shared          # shared theme is "dark"
    Use             # use files / use json / use ui
    Focus           # focus searchBox
    Hide            # hide sidebar
    Animate         # animate 200ms ease-out
    Motion          # motion pop

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

    # external UI resource creation (D44)
    CreateUiResource  # create button into helloButton

    # UI event registration (D46) - registration only; whether/when a
    # handler body actually runs depends on a message loop (D47), not this.
    When              # when helloButton is clicked

    # UI layout/show (D47) - the smallest possible container and message
    # loop, not a general layout system.
    PutIn             # put helloButton in app
    Show              # show app

    ReadFile
    WriteFile
    AppendFile      # append "text" to "log.txt"        (D61)
    CopyFile
    MoveFile
    DeleteFile
    FileExists      # an EXPRESSION: if file "x" exists
    FileLocked      # an EXPRESSION: if file "x" is locked            (D72)
    RunProgram      # run "notepad.exe" / run command "git status"

    # discovery (D20, D21)
    GetFiles        # get files in "Pictures" into files
    GetFolders      # get folders in "Documents" into folders
    CreateFolder
    DeleteFolder
    CopyFolder
    MoveFolder

    # errors (D23, D68)
    Try             # try / otherwise
    Fail            # fail with "message"

    # strings and collections (D24, D25, D26)
    OfOperation     # length/uppercase/lowercase/first/last OF something
    TextMatch       # starts with / ends with
    Sort
    Reverse
    Replace
    Split
    Join
    Find

    # json, csv, random, logging (D29, D30, D31, D95)
    ReadJson
    ConvertToJson
    ConvertFromJson
    ReadCsv
    WriteCsv
    ConvertToCsv
    ConvertFromCsv
    RandomNumber
    RandomItem
    Diagnostic      # log / warn / error

    # dates and time (D32)
    Clock           # today / now
    DateAdjust      # add 7 days to date / remove 1 month from date
    DateDifference  # days between startDate and endDate make days  (D32, legacy form - D42 kept this untouched)
    FormatDate      # format date as "MM/dd/yyyy" into text

    # dates and time, as an expression (D42)
    DateDifferenceValue  # days between startDate and endDate       (a VALUE, usable anywhere an expression is)

    # networking & http (D49, D96)
    HttpGet
    HttpPost
    HttpPut
    HttpDelete
    DownloadFile

    # web servers & api routes (D51)
    WebRoute
    Respond
    StartServer
    ListenServer

    # declarative UI, reactivity, animation (D56)
    UiElement
    UiLayout
    StateDef
    DeriveDef
    MemoDef
    UiEvent
    Watch
    Lifecycle
    UiAnimation
    Await
    SharedState
    UiAction
    UseModule

    # system integration (D67) - reachable Otter syntax for capabilities
    # that previously existed only as unreachable JS/host-runtime
    # plumbing (Otter.Web.psm1/Otter.Desktop.psm1's otterClipboard/
    # otterNotify/otterGetEnv/otterGetSystemPaths/otterChooseFile/
    # otterChooseFolder/otterSaveFileDialog) with no Otter-language
    # front door at all - confirmed by direct inspection: zero
    # references anywhere in this contract, the lexer, or the parser
    # before D67.
    CopyToClipboard   # copy "text" to clipboard
    GetClipboard      # get clipboard into text
    Notify            # notify "Title" with "Message"
    GetEnvironmentVariable  # get environment variable "PATH" into value
    SetEnvironmentVariable  # set environment variable "NAME" to "VALUE"
    GetSystemFolder   # get system folder "temp" into path
    SetCurrentDirectory # set current directory to "path"
    ChooseFile        # choose file into path
    ChooseFolder      # choose folder into path
    ChooseSaveFile    # choose file to save into path

    # --- system information (D69) --------------------------------
    GetSystemInfo     # get system information "os" into info

    # --- process management (D70, D71) ----------------------------
    GetProcesses      # get processes into list
    KillProcess       # kill process p / kill process p and its children
    SetProcessPriority  # set priority of process p to "high"
    WaitForProcess      # wait for process p up to 5 seconds [into finished]

    # --- symbolic links (D73) --------------------------------------
    CreateSymbolicLink     # create symbolic link "l" pointing to "t"
    GetSymbolicLinkTarget  # get symbolic link target of "l" into t
    FileIsSymbolicLink     # an EXPRESSION: if file "l" is a symbolic link

    # --- permissions and ownership (D74) ----------------------------
    GetFileOwner           # get owner of "x" into owner
    FileIsReadOnly         # an EXPRESSION: if file "x" is read only
    SetFileReadOnly        # set file "x" to read only / to writable

    # --- Windows registry (D78) --------------------------------------
    GetRegistryValue       # get registry value "n" from "path" into t
    SetRegistryValue       # set registry value "n" to "d" in "path"
    DeleteRegistryValue    # delete registry value "n" from "path"
    RegistryKeyExists      # an EXPRESSION: if registry key "path" exists

    # --- event/system logs (D79) --------------------------------------
    GetEventLogEntries     # get event log entries from "n" up to N into t

    # --- secure credential storage (D81) -------------------------------
    SetCredential          # set credential "n" to "secret"
    GetCredential          # get credential "n" into secret
    DeleteCredential       # delete credential "n"

    # --- power/session actions (D82) ------------------------------------
    PowerAction            # lock the computer / sign out / restart the
                            # computer / shut down the computer

    # --- printers (D83) --------------------------------------------------
    PrintFile              # print "file.txt" to "PrinterName"

    # --- remote administration (D84) --------------------------------------
    RunRemoteCommand       # run command "..." on remote "host" using
                            # credential "n" [into result]

    # --- SSH client (D85) ---------------------------------------------------
    RunSshCommand          # run command "..." over ssh to "user@host"
                            # [into result]

    # --- ZIP/archive provider (D87) -----------------------------------------
    ZipFolder              # zip folder "src" into "archive.zip"
    UnzipFile              # unzip "archive.zip" into "dest"

    # --- more math operations (D89) ------------------------------------------
    MinMax                 # larger of X and Y / smaller of X and Y

    # --- hashing/HMAC (D91) --------------------------------------------------
    HashText               # hash "text" as "sha256" [with key "secret"] into digest

    # --- symmetric encryption (D92) -------------------------------------------
    EncryptText            # encrypt "text" with key "secret" into cipher
    DecryptText            # decrypt "cipher" with key "secret" into text

    # --- database operations (D97) --------------------------------------------
    ConnectDb              # connect database into db
    DisconnectDb           # disconnect db
    DbQuery                # query db with ... into tasks
    DbExecute              # execute db with ... into result
    BeginTransaction       # begin transaction on db into tx
    CommitTransaction      # commit tx
    RollbackTransaction    # rollback tx
    GetTables              # get tables from db into tables (D98)
    GetColumns             # get columns from table in db into columns (D98)

    # --- console UX primitives (D100) ------------------------------------------
    SetCursorPosition       # set cursor to row 5 column 10
    ChooseFromList          # choose from options into choice
    ShowProgress            # show progress 50 percent
    ConsoleInteractive      # console is interactive (an EXPRESSION - the
                             # TokenKind above is the combined phrase this
                             # parses from)
}

enum MathOp { Add; Subtract; Multiply; Divide; Percent; Power }   # D88

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
enum OfOperation { Length; Uppercase; Lowercase; First; Last; AbsoluteValue; SquareRoot; Round; RoundUp; RoundDown; Sine; Cosine; Tangent; LogTen; NaturalLog }   # D89 added AbsoluteValue..RoundDown, D90 added Sine..NaturalLog

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
# say "Error!" in color "red"   -> ColorExpr set (D100)
class SayStmt : Node {
    [Node[]]$Parts
    [Node]$ColorExpr    # say ... in color "..."                     (D100)
    SayStmt([Node[]]$parts, [int]$line) : base([NodeKind]::Say, $line) {
        $this.Parts = $parts
        $this.ColorExpr = $null
    }
    SayStmt([Node[]]$parts, [Node]$colorExpr, [int]$line) : base([NodeKind]::Say, $line) {
        $this.Parts = $parts
        $this.ColorExpr = $colorExpr
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
# ask secretly "Password:" and call it pw     -> Secret = true        (D100)
class AskStmt : Node {
    [Node]$Prompt
    [string]$Name
    [bool]$Secret
    AskStmt([Node]$prompt, [string]$name, [int]$line) : base([NodeKind]::Ask, $line) {
        $this.Prompt = $prompt
        $this.Name = $name
        $this.Secret = $false
    }
    AskStmt([Node]$prompt, [string]$name, [bool]$secret, [int]$line) : base([NodeKind]::Ask, $line) {
        $this.Prompt = $prompt
        $this.Name = $name
        $this.Secret = $secret
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
# EXTERNAL UI RESOURCES (D44)
# ===============================================================
#
#     create button into helloButton
#
# D43 already settled that this is NOT an ObjectDefStmt/has-shaped thing -
# a UI control is an external/domain resource, same family as files and
# folders, not in-memory data. D44 settles what it produces and how its
# identity works; this is that one statement.
#
# TypeName is READ AS RAW TEXT, exactly like Read-OtterObjectTypeName
# already does for "a Person" / "is a text box" - so control-kind words
# ("button", "window", "text box") are NOT reserved keywords. Nothing
# about D44 takes a word away from ordinary Otter programs.
#
# No property-block here on purpose - D43 explicitly deferred an
# initialization block, and property translation per control kind is D45's
# job, not this node's.
class CreateUiResourceStmt : Node {
    [string]$TypeName
    [string]$Target
    CreateUiResourceStmt([string]$typeName, [string]$target, [int]$line) : base([NodeKind]::CreateUiResource, $line) {
        $this.TypeName = $typeName
        $this.Target = $target
    }
}


# when helloButton is clicked
#     say "Hello"
# .
#
# D46, registration only. EventName is READ AS A RAW WORD, exactly like
# CreateUiResourceStmt's TypeName above - "clicked"/"changed"/"closed" are
# NOT reserved keywords, preserving Otter's contextual-keyword philosophy.
#
# Frozen explicitly as part of D46 (not left to interpreter convention):
#   - the handler Body closes over the environment active where `when`
#     is registered, and introduces NO implicit new scope - the same
#     environment If/While/Repeat bodies already run in, not a function
#     call's fresh child scope.
#   - no Otter-visible event payload yet - Body has no way to name "the
#     event" or read anything about it. `when nameBox is changed as
#     event` is explicitly not part of D46.
#   - whether/when Body ever actually executes in a running program is
#     D47's job (a message loop), not this node's.
class WhenStmt : Node {
    [Node]$Target        # the UI resource identifier
    [string]$EventName   # "clicked", "changed", "closed" - a raw word
    [Node[]]$Body
    WhenStmt([Node]$target, [string]$eventName, [Node[]]$body, [int]$line) : base([NodeKind]::When, $line) {
        $this.Target = $target
        $this.EventName = $eventName
        $this.Body = $body
    }
}


# put helloButton in app
#
# D47. Attaches an EXISTING resource - never recreates or copies it. Item
# keeps its identity exactly like D44 already guarantees; `put` only
# changes what it's attached to. Windows hold their put-in children in an
# Otter-invisible, provider-managed default vertical container - not a
# general layout system, and not a value Otter code ever sees or names.
# A resource can have only one parent; a second `put` of the same item
# anywhere is a runtime error, not a silent move.
class PutInStmt : Node {
    [Node]$Item
    [Node]$Container
    PutInStmt([Node]$item, [Node]$container, [int]$line) : base([NodeKind]::PutIn, $line) {
        $this.Item = $item
        $this.Container = $container
    }
}

# show app
#
# D47, modal only: blocks until the window closes, then returns. Showing
# an empty window (nothing ever put in it) is valid. A window that has
# already been closed cannot be shown again - a clean Otter error, not
# the raw .NET exception WPF itself throws for this.
class ShowStmt : Node {
    [Node]$Target
    ShowStmt([Node]$target, [int]$line) : base([NodeKind]::Show, $line) {
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
    [bool]$Atomic    # write ... to ... atomically                  (D72)
    WriteFileStmt([Node]$content, [Node]$path, [int]$line) : base([NodeKind]::WriteFile, $line) {
        $this.Content = $content
        $this.Path = $path
        $this.Atomic = $false
    }
    WriteFileStmt([Node]$content, [Node]$path, [bool]$atomic, [int]$line) : base([NodeKind]::WriteFile, $line) {
        $this.Content = $content
        $this.Path = $path
        $this.Atomic = $atomic
    }
}

# append "line one" to "log.txt"     (adds to the end; creates the file
# if it does not exist yet, same as write)                        (D61)
class AppendFileStmt : Node {
    [Node]$Content
    [Node]$Path
    AppendFileStmt([Node]$content, [Node]$path, [int]$line) : base([NodeKind]::AppendFile, $line) {
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

# if file "x" is locked                                              (D72)
# True when the file exists but cannot currently be opened exclusively
# (another process holds it open) - false both when it is free AND when
# it does not exist at all, matching "exists" being the separate,
# already-established question.
class FileLockedExpr : Node {
    [Node]$Path
    FileLockedExpr([Node]$path, [int]$line) : base([NodeKind]::FileLocked, $line) {
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
# SYSTEM INTEGRATION (D67)
# ===============================================================
#
#     copy "text" to clipboard
#     get clipboard into text
#     notify "Title" with "Message"
#     get environment variable "PATH" into value
#     get system folder "temp" into path         - "temp"/"appdata"/"user"/"current"
#     choose file into path
#     choose folder into path
#     choose file to save into path
#
# All eight give a real Otter front door to capabilities that already
# existed as working JS/host-runtime plumbing (Otter.Web.psm1's plain-
# browser fallbacks, Otter.Desktop.psm1's authenticated bridge) but had
# NO Otter syntax reaching them at all before D67 - confirmed directly:
# `copyToClipboard "hello"` happened to PARSE (it matched the generic
# function-call grammar) but threw "Otter could not find anything
# called ..." at runtime, since no such function was ever declared.
# That was never a real language capability, just an accident of the
# call-by-name mechanism reaching into whichever JS globals happened to
# exist on a given target - these dedicated statements are the fix.

# copy "text" to clipboard
class CopyToClipboardStmt : Node {
    [Node]$Text
    CopyToClipboardStmt([Node]$text, [int]$line) : base([NodeKind]::CopyToClipboard, $line) {
        $this.Text = $text
    }
}

# get clipboard into text
class GetClipboardStmt : Node {
    [string]$Target
    GetClipboardStmt([string]$target, [int]$line) : base([NodeKind]::GetClipboard, $line) {
        $this.Target = $target
    }
}

# notify "Title" with "Message"
class NotifyStmt : Node {
    [Node]$Title
    [Node]$Message
    NotifyStmt([Node]$title, [Node]$message, [int]$line) : base([NodeKind]::Notify, $line) {
        $this.Title = $title
        $this.Message = $message
    }
}

# get environment variable "PATH" into value      - gone if not set
class GetEnvironmentVariableStmt : Node {
    [Node]$Name
    [string]$Target
    GetEnvironmentVariableStmt([Node]$name, [string]$target, [int]$line) : base([NodeKind]::GetEnvironmentVariable, $line) {
        $this.Name = $name
        $this.Target = $target
    }
}

# set environment variable "NAME" to "VALUE"
class SetEnvironmentVariableStmt : Node {
    [Node]$Name
    [Node]$Value
    SetEnvironmentVariableStmt([Node]$name, [Node]$value, [int]$line) : base([NodeKind]::SetEnvironmentVariable, $line) {
        $this.Name = $name
        $this.Value = $value
    }
}

# get system folder "temp" into path
# FolderName is one of: "temp", "appdata", "user", "current" - a plain
# string VALUE, not a keyword, so adding another named folder later
# needs no grammar change, only a new case in the interpreter/compiler.
class GetSystemFolderStmt : Node {
    [Node]$FolderName
    [string]$Target
    GetSystemFolderStmt([Node]$folderName, [string]$target, [int]$line) : base([NodeKind]::GetSystemFolder, $line) {
        $this.FolderName = $folderName
        $this.Target = $target
    }
}

# set current directory to "path"
class SetCurrentDirectoryStmt : Node {
    [Node]$Path
    SetCurrentDirectoryStmt([Node]$path, [int]$line) : base([NodeKind]::SetCurrentDirectory, $line) {
        $this.Path = $path
    }
}

# get system information "os" into info               (D69)
# InfoKind is one of: "os", "cpu", "memory", "disk", "network" - a plain
# string VALUE, not a keyword, same design as GetSystemFolder's
# FolderName - adding another info kind later needs no grammar change.
class GetSystemInfoStmt : Node {
    [Node]$InfoKind
    [string]$Target
    GetSystemInfoStmt([Node]$infoKind, [string]$target, [int]$line) : base([NodeKind]::GetSystemInfo, $line) {
        $this.InfoKind = $infoKind
        $this.Target = $target
    }
}

# get processes into list                                             (D70)
# Each entry is a "process" thing with id/name - the SAME shape `run
# "notepad.exe" into p` now produces, so `kill process p` (below) works
# on a handle from either statement without special-casing which one.
class GetProcessesStmt : Node {
    [string]$Target
    GetProcessesStmt([string]$target, [int]$line) : base([NodeKind]::GetProcesses, $line) {
        $this.Target = $target
    }
}

# kill process p                        - one process, by its real PID
# kill process p and its children       - that process and its whole
#                                          subtree (IncludeChildren)
class KillProcessStmt : Node {
    [Node]$ProcessExpr
    [bool]$IncludeChildren
    KillProcessStmt([Node]$processExpr, [bool]$includeChildren, [int]$line) : base([NodeKind]::KillProcess, $line) {
        $this.ProcessExpr = $processExpr
        $this.IncludeChildren = $includeChildren
    }
}

# set priority of process p to "high"                                 (D71)
# Priority is one of: "low", "below normal", "normal", "above normal",
# "high", "realtime" - a plain string VALUE, not a keyword, same design
# as GetSystemFolder's FolderName.
class SetProcessPriorityStmt : Node {
    [Node]$ProcessExpr
    [Node]$Priority
    SetProcessPriorityStmt([Node]$processExpr, [Node]$priority, [int]$line) : base([NodeKind]::SetProcessPriority, $line) {
        $this.ProcessExpr = $processExpr
        $this.Priority = $priority
    }
}

# wait for process p up to 5 seconds [into finished]                  (D71)
# Blocks until the process exits or the timeout elapses, whichever
# comes first. `finished` (optional) is a real boolean: true if the
# process had already exited by the deadline, false if it was still
# running and the wait simply gave up.
class WaitForProcessStmt : Node {
    [Node]$ProcessExpr
    [Node]$TimeoutSeconds
    [string]$Target
    WaitForProcessStmt([Node]$processExpr, [Node]$timeoutSeconds, [string]$target, [int]$line) : base([NodeKind]::WaitForProcess, $line) {
        $this.ProcessExpr = $processExpr
        $this.TimeoutSeconds = $timeoutSeconds
        $this.Target = $target
    }
}

# create symbolic link "link.txt" pointing to "target.txt"            (D73)
# The link kind (file vs. directory) is auto-detected from whatever
# already exists at TargetPath - Windows' own symlink API needs to know
# which kind it is creating, but Otter code should not have to say so
# when the answer is already sitting on disk.
class CreateSymbolicLinkStmt : Node {
    [Node]$LinkPath
    [Node]$TargetPath
    CreateSymbolicLinkStmt([Node]$linkPath, [Node]$targetPath, [int]$line) : base([NodeKind]::CreateSymbolicLink, $line) {
        $this.LinkPath = $linkPath
        $this.TargetPath = $targetPath
    }
}

# get symbolic link target of "link.txt" into target                 (D73)
class GetSymbolicLinkTargetStmt : Node {
    [Node]$LinkPath
    [string]$Target
    GetSymbolicLinkTargetStmt([Node]$linkPath, [string]$target, [int]$line) : base([NodeKind]::GetSymbolicLinkTarget, $line) {
        $this.LinkPath = $linkPath
        $this.Target = $target
    }
}

# if file "link.txt" is a symbolic link                               (D73)
class FileIsSymbolicLinkExpr : Node {
    [Node]$Path
    FileIsSymbolicLinkExpr([Node]$path, [int]$line) : base([NodeKind]::FileIsSymbolicLink, $line) {
        $this.Path = $path
    }
}

# get owner of "x" into owner                                        (D74)
class GetFileOwnerStmt : Node {
    [Node]$Path
    [string]$Target
    GetFileOwnerStmt([Node]$path, [string]$target, [int]$line) : base([NodeKind]::GetFileOwner, $line) {
        $this.Path = $path
        $this.Target = $target
    }
}

# if file "x" is read only                                           (D74)
class FileIsReadOnlyExpr : Node {
    [Node]$Path
    FileIsReadOnlyExpr([Node]$path, [int]$line) : base([NodeKind]::FileIsReadOnly, $line) {
        $this.Path = $path
    }
}

# set file "x" to read only  /  set file "x" to writable             (D74)
class SetFileReadOnlyStmt : Node {
    [Node]$Path
    [bool]$ReadOnly
    SetFileReadOnlyStmt([Node]$path, [bool]$readOnly, [int]$line) : base([NodeKind]::SetFileReadOnly, $line) {
        $this.Path = $path
        $this.ReadOnly = $readOnly
    }
}

# get registry value "n" from "HKCU:\Software\MyApp" into t           (D78)
# `gone` (not an error) when the value or the key does not exist -
# matching D67's GetEnvironmentVariable's own "unset means gone, not a
# failure" choice, since a missing registry value is an equally
# ordinary, expected outcome for real Otter programs to branch on.
class GetRegistryValueStmt : Node {
    [Node]$ValueName
    [Node]$KeyPath
    [string]$Target
    GetRegistryValueStmt([Node]$valueName, [Node]$keyPath, [string]$target, [int]$line) : base([NodeKind]::GetRegistryValue, $line) {
        $this.ValueName = $valueName
        $this.KeyPath = $keyPath
        $this.Target = $target
    }
}

# set registry value "n" to "d" in "HKCU:\Software\MyApp"             (D78)
# Creates the key path if it does not exist yet, matching WriteFile's
# own "creates the parent folder if needed" convention for files.
class SetRegistryValueStmt : Node {
    [Node]$ValueName
    [Node]$Value
    [Node]$KeyPath
    SetRegistryValueStmt([Node]$valueName, [Node]$value, [Node]$keyPath, [int]$line) : base([NodeKind]::SetRegistryValue, $line) {
        $this.ValueName = $valueName
        $this.Value = $value
        $this.KeyPath = $keyPath
    }
}

# delete registry value "n" from "HKCU:\Software\MyApp"               (D78)
class DeleteRegistryValueStmt : Node {
    [Node]$ValueName
    [Node]$KeyPath
    DeleteRegistryValueStmt([Node]$valueName, [Node]$keyPath, [int]$line) : base([NodeKind]::DeleteRegistryValue, $line) {
        $this.ValueName = $valueName
        $this.KeyPath = $keyPath
    }
}

# if registry key "HKCU:\Software\MyApp" exists                       (D78)
class RegistryKeyExistsExpr : Node {
    [Node]$KeyPath
    RegistryKeyExistsExpr([Node]$keyPath, [int]$line) : base([NodeKind]::RegistryKeyExists, $line) {
        $this.KeyPath = $keyPath
    }
}

# get event log entries from "System" up to 20 into entries           (D79)
# LogName is a plain string VALUE ("System", "Application", "Security",
# or any other real Windows log name), not a keyword - same design as
# D67's GetSystemFolder FolderName, so a caller can name any log this
# machine actually has without a grammar change.
class GetEventLogEntriesStmt : Node {
    [Node]$LogName
    [Node]$MaxEntries
    [string]$Target
    GetEventLogEntriesStmt([Node]$logName, [Node]$maxEntries, [string]$target, [int]$line) : base([NodeKind]::GetEventLogEntries, $line) {
        $this.LogName = $logName
        $this.MaxEntries = $maxEntries
        $this.Target = $target
    }
}

# set credential "n" to "secret"                                     (D81)
# Encrypted at rest via Windows DPAPI, CurrentUser scope - decryptable
# only by the same OS login that wrote it, on the same machine. Not a
# secrets-sharing or secrets-syncing mechanism; a local-only vault.
class SetCredentialStmt : Node {
    [Node]$Name
    [Node]$Secret
    SetCredentialStmt([Node]$name, [Node]$secret, [int]$line) : base([NodeKind]::SetCredential, $line) {
        $this.Name = $name
        $this.Secret = $secret
    }
}

# get credential "n" into secret                                     (D81)
# `gone` (not an error) when no credential by that name has been set -
# matching GetEnvironmentVariable/GetRegistryValue's own "unset means
# gone" choice.
class GetCredentialStmt : Node {
    [Node]$Name
    [string]$Target
    GetCredentialStmt([Node]$name, [string]$target, [int]$line) : base([NodeKind]::GetCredential, $line) {
        $this.Name = $name
        $this.Target = $target
    }
}

# delete credential "n"                                               (D81)
class DeleteCredentialStmt : Node {
    [Node]$Name
    DeleteCredentialStmt([Node]$name, [int]$line) : base([NodeKind]::DeleteCredential, $line) {
        $this.Name = $name
    }
}

# lock the computer / sign out / restart the computer /               (D82)
# shut down the computer
# Action is one of: "lock", "signOut", "restart", "shutDown" - carried
# as a plain string rather than a separate NodeKind per verb, since all
# four are the exact same shape (no arguments, no result).
class PowerActionStmt : Node {
    [string]$Action
    PowerActionStmt([string]$action, [int]$line) : base([NodeKind]::PowerAction, $line) {
        $this.Action = $action
    }
}

# print "file.txt" to "PrinterName"                                   (D83)
# Scoped to TEXT files, matching every other filesystem statement in
# this language - the file's own content is sent to the named printer
# as plain text, not rendered through a document format's own print
# handler (no PDF/image/rich-document printing here).
class PrintFileStmt : Node {
    [Node]$Path
    [Node]$PrinterName
    PrintFileStmt([Node]$path, [Node]$printerName, [int]$line) : base([NodeKind]::PrintFile, $line) {
        $this.Path = $path
        $this.PrinterName = $printerName
    }
}

# run command "..." on remote "host" using credential "n" [into result] (D84)
# A genuinely SEPARATE statement from RunStmt, not an extra optional
# field bolted onto it: RunStmt already carries three different
# meanings (fire-and-forget launch / blocking local command / its own
# IsCommand flag), and remote execution has a different result shape
# (captured text output, not the local CommandResult's separate stdout/
# stderr/exit-code, since a WinRM session does not expose those the
# same way a local Process object does) - conflating the two would
# make both harder to reason about.
#
# CredentialName doubles as the remote username: it is looked up in
# D81's credential vault (set credential "n" to "secret") for the
# PASSWORD, so `using credential "AZLEG\jmacy"` means "connect as
# AZLEG\jmacy using the password stored under that exact name" - no
# separate username field, and no change to D81's own storage format.
class RunRemoteCommandStmt : Node {
    [Node]$Command
    [Node]$HostName
    [Node]$CredentialName
    [string]$ResultTarget
    RunRemoteCommandStmt([Node]$command, [Node]$hostName, [Node]$credentialName, [string]$resultTarget, [int]$line) : base([NodeKind]::RunRemoteCommand, $line) {
        $this.Command = $command
        $this.HostName = $hostName
        $this.CredentialName = $credentialName
        $this.ResultTarget = $resultTarget
    }
}

# run command "..." over ssh to "user@host" [into result]              (D85)
# Deliberately NO credential clause, unlike D84's WinRM form: `ssh.exe`
# cannot accept a password non-interactively without extra tooling this
# platform does not bundle (confirmed directly - ssh reads a password
# from the real terminal device, not stdin, specifically to resist
# exactly this scripting pattern). Key-based auth (an already-configured
# key or agent) is both the only thing this can honestly support AND
# the standard, secure way real SSH automation is done - not a
# limitation papered over, a correct design choice for this transport.
class RunSshCommandStmt : Node {
    [Node]$Command
    [Node]$HostName
    [string]$ResultTarget
    RunSshCommandStmt([Node]$command, [Node]$hostName, [string]$resultTarget, [int]$line) : base([NodeKind]::RunSshCommand, $line) {
        $this.Command = $command
        $this.HostName = $hostName
        $this.ResultTarget = $resultTarget
    }
}

# zip folder "src" into "archive.zip"                                 (D87)
class ZipFolderStmt : Node {
    [Node]$SourceFolder
    [Node]$ArchivePath
    ZipFolderStmt([Node]$sourceFolder, [Node]$archivePath, [int]$line) : base([NodeKind]::ZipFolder, $line) {
        $this.SourceFolder = $sourceFolder
        $this.ArchivePath = $archivePath
    }
}

# unzip "archive.zip" into "dest"                                     (D87)
class UnzipFileStmt : Node {
    [Node]$ArchivePath
    [Node]$DestinationFolder
    UnzipFileStmt([Node]$archivePath, [Node]$destinationFolder, [int]$line) : base([NodeKind]::UnzipFile, $line) {
        $this.ArchivePath = $archivePath
        $this.DestinationFolder = $destinationFolder
    }
}

# choose file into path                            - gone if cancelled
class ChooseFileStmt : Node {
    [string]$Target
    ChooseFileStmt([string]$target, [int]$line) : base([NodeKind]::ChooseFile, $line) {
        $this.Target = $target
    }
}

# choose folder into path                          - gone if cancelled
class ChooseFolderStmt : Node {
    [string]$Target
    ChooseFolderStmt([string]$target, [int]$line) : base([NodeKind]::ChooseFolder, $line) {
        $this.Target = $target
    }
}

# choose file to save into path                    - gone if cancelled
class ChooseSaveFileStmt : Node {
    [string]$Target
    ChooseSaveFileStmt([string]$target, [int]$line) : base([NodeKind]::ChooseSaveFile, $line) {
        $this.Target = $target
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
# instead. No error variable, no error types by default - D68 adds an
# OPTIONAL error-message capture ("otherwise into reason") and a way for
# Otter code to raise its own named error (FailStmt, below), without
# requiring either from existing programs.
#
# A "return" inside a try body is NOT an error and must escape cleanly.

class TryStmt : Node {
    [Node[]]$Body
    [Node[]]$OtherwiseBody
    [string]$ErrorTarget   # D68: "otherwise into reason" - null when absent
    TryStmt([Node[]]$body, [Node[]]$otherwiseBody, [int]$line) : base([NodeKind]::Try, $line) {
        $this.Body = $body
        $this.OtherwiseBody = $otherwiseBody
        $this.ErrorTarget = $null
    }
    TryStmt([Node[]]$body, [Node[]]$otherwiseBody, [string]$errorTarget, [int]$line) : base([NodeKind]::Try, $line) {
        $this.Body = $body
        $this.OtherwiseBody = $otherwiseBody
        $this.ErrorTarget = $errorTarget
    }
}

# D68: `fail with "message"` - a real, user-raised custom error. Reuses the
# same OtterError machinery as every built-in runtime error (same "Otter
# Runtime Error" banner, same line number, catchable by try/otherwise), so
# a user-defined failure looks and behaves exactly like a built-in one -
# no separate error-type hierarchy needed for the beginner form.
class FailStmt : Node {
    [Node]$Message
    FailStmt([Node]$message, [int]$line) : base([NodeKind]::Fail, $line) {
        $this.Message = $message
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

# D89: larger of X and Y / smaller of X and Y
class MinMaxExpr : Node {
    [bool]$IsMax
    [Node]$Left
    [Node]$Right
    MinMaxExpr([bool]$isMax, [Node]$left, [Node]$right, [int]$line) : base([NodeKind]::MinMax, $line) {
        $this.IsMax = $isMax
        $this.Left = $left
        $this.Right = $right
    }
}

# D91: hash "text" as "sha256" [with key "secret"] into digest
class HashTextStmt : Node {
    [Node]$Text
    [Node]$Algorithm
    [Node]$Key             # $null when this is a plain hash, not an HMAC
    [string]$ResultTarget
    HashTextStmt([Node]$text, [Node]$algorithm, [Node]$key, [string]$resultTarget, [int]$line) : base([NodeKind]::HashText, $line) {
        $this.Text = $text
        $this.Algorithm = $algorithm
        $this.Key = $key
        $this.ResultTarget = $resultTarget
    }
}

# D92: encrypt "text" with key "secret" into cipher
class EncryptTextStmt : Node {
    [Node]$Text
    [Node]$Key
    [string]$ResultTarget
    EncryptTextStmt([Node]$text, [Node]$key, [string]$resultTarget, [int]$line) : base([NodeKind]::EncryptText, $line) {
        $this.Text = $text
        $this.Key = $key
        $this.ResultTarget = $resultTarget
    }
}

# D92: decrypt "cipher" with key "secret" into text
class DecryptTextStmt : Node {
    [Node]$CipherText
    [Node]$Key
    [string]$ResultTarget
    DecryptTextStmt([Node]$cipherText, [Node]$key, [string]$resultTarget, [int]$line) : base([NodeKind]::DecryptText, $line) {
        $this.CipherText = $cipherText
        $this.Key = $key
        $this.ResultTarget = $resultTarget
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
# JSON, CSV, RANDOM, DIAGNOSTICS (D29, D30, D31, D95)
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

# read csv from "customers.csv" into customers
class ReadCsvStmt : Node {
    [Node]$Path
    [string]$Target
    ReadCsvStmt([Node]$path, [string]$target, [int]$line) : base([NodeKind]::ReadCsv, $line) {
        $this.Path = $path
        $this.Target = $target
    }
}

# write csv customers to "export.csv"
class WriteCsvStmt : Node {
    [Node]$Rows
    [Node]$Path
    WriteCsvStmt([Node]$rows, [Node]$path, [int]$line) : base([NodeKind]::WriteCsv, $line) {
        $this.Rows = $rows
        $this.Path = $path
    }
}

# convert customers to csv into csvText
class ConvertToCsvStmt : Node {
    [Node]$Subject
    [string]$Target
    ConvertToCsvStmt([Node]$subject, [string]$target, [int]$line) : base([NodeKind]::ConvertToCsv, $line) {
        $this.Subject = $subject
        $this.Target = $target
    }
}

# convert csvText from csv into customers
class ConvertFromCsvStmt : Node {
    [Node]$Subject
    [string]$Target
    ConvertFromCsvStmt([Node]$subject, [string]$target, [int]$line) : base([NodeKind]::ConvertFromCsv, $line) {
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

# days between startDate and endDate                              (D42)
#
# The expression form of DateDifferenceStmt above - a genuine VALUE, so it
# is legal anywhere Otter accepts an expression, not only as the whole
# right-hand side of a "make" statement:
#
#     waiting is days between date and deadline
#     say days between start and finish
#     if days between start and finish is greater than 30
#
# Deliberately a SEPARATE node from DateDifferenceStmt, not a replacement
# for it. D42 does not repurpose the statement form - "days between X and Y
# make Z" (D32) keeps working exactly as it always has, as legacy
# compatibility syntax; this is additive, the same coexistence pattern used
# everywhere in this project (D3, D34-D36, D40). No destination variable
# here - a plain value has nothing to assign into.
class DateDifferenceExpr : Node {
    [TimeUnit]$Unit
    [Node]$Start
    [Node]$End
    DateDifferenceExpr([TimeUnit]$unit, [Node]$start, [Node]$end, [int]$line) : base([NodeKind]::DateDifferenceValue, $line) {
        $this.Unit = $unit
        $this.Start = $start
        $this.End = $end
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
# NETWORKING & HTTP (D49)
# ===============================================================

# get "https://..." into result
# get json from "https://..." into result
class HttpGetStmt : Node {
    [Node]$Url
    [string]$Target
    [bool]$AsJson
    HttpGetStmt([Node]$url, [string]$target, [bool]$asJson, [int]$line) : base([NodeKind]::HttpGet, $line) {
        $this.Url = $url
        $this.Target = $target
        $this.AsJson = $asJson
    }
}

# post data to "https://..." [into result]
class HttpPostStmt : Node {
    [Node]$Data
    [Node]$Url
    [string]$Target
    [bool]$AsJson
    HttpPostStmt([Node]$data, [Node]$url, [string]$target, [bool]$asJson, [int]$line) : base([NodeKind]::HttpPost, $line) {
        $this.Data = $data
        $this.Url = $url
        $this.Target = $target
        $this.AsJson = $asJson
    }
}

# put data to "https://..." [into result]
class HttpPutStmt : Node {
    [Node]$Data
    [Node]$Url
    [string]$Target
    [bool]$AsJson
    HttpPutStmt([Node]$data, [Node]$url, [string]$target, [bool]$asJson, [int]$line) : base([NodeKind]::HttpPut, $line) {
        $this.Data = $data
        $this.Url = $url
        $this.Target = $target
        $this.AsJson = $asJson
    }
}

# delete from "https://..." [into result]
class HttpDeleteStmt : Node {
    [Node]$Url
    [string]$Target
    HttpDeleteStmt([Node]$url, [string]$target, [int]$line) : base([NodeKind]::HttpDelete, $line) {
        $this.Url = $url
        $this.Target = $target
    }
}

# download file from <url> to <path> (D96)
class DownloadFileStmt : Node {
    [Node]$Url
    [Node]$Path
    DownloadFileStmt([Node]$url, [Node]$path, [int]$line) : base([NodeKind]::DownloadFile, $line) {
        $this.Url = $url
        $this.Path = $path
    }
}

# ===============================================================
# WEB SERVERS & API ROUTES (D51)
# ===============================================================

# when api receives GET at "/users" [into req]
class WebRouteStmt : Node {
    [Node]$Server          # variable or expression for the server
    [string]$Method        # "GET", "POST", "PUT", "DELETE", "ALL", etc.
    [Node]$Path            # route path expression (e.g. [LiteralExpr] "/users")
    [string]$RequestTarget # optional request variable name (e.g. "request" in "into request")
    [Node[]]$Body          # route handler statements

    WebRouteStmt([Node]$server, [string]$method, [Node]$path, [string]$requestTarget, [Node[]]$body, [int]$line)
        : base([NodeKind]::WebRoute, $line) {
        $this.Server = $server
        $this.Method = $method
        $this.Path = $path
        $this.RequestTarget = $requestTarget
        $this.Body = $body
    }
}

# respond with <value> [as json] [(and|with) status <code>]
class RespondStmt : Node {
    [Node]$Value     # response body expression (e.g. string or object), can be $null
    [Node]$Status    # HTTP status code expression (e.g. 200, 201, 404), can be $null
    [bool]$AsJson    # true if "as json" was specified

    RespondStmt([Node]$value, [Node]$status, [bool]$asJson, [int]$line)
        : base([NodeKind]::Respond, $line) {
        $this.Value = $value
        $this.Status = $status
        $this.AsJson = $asJson
    }
}

# start api
class StartServerStmt : Node {
    [Node]$Server

    StartServerStmt([Node]$server, [int]$line)
        : base([NodeKind]::StartServer, $line) {
        $this.Server = $server
    }
}

# listen on port 8080
class ListenServerStmt : Node {
    [Node]$Port

    ListenServerStmt([Node]$port, [int]$line)
        : base([NodeKind]::ListenServer, $line) {
        $this.Port = $port
    }
}


# ===============================================================
# DECLARATIVE UI, REACTIVITY & ANIMATION (D56)
# ===============================================================

class ResponsiveRule {
    [string]$Breakpoint  # 'small', 'medium', 'large'
    [int]$Columns        # e.g. 2 in 'columns 2 on medium'
    [bool]$Stack         # true if 'stack on small'
    ResponsiveRule([string]$breakpoint, [int]$columns, [bool]$stack) {
        $this.Breakpoint = $breakpoint
        $this.Columns = $columns
        $this.Stack = $stack
    }
}

class UiLayoutSpec {
    [string]$Mode
    [string]$Align
    [bool]$Spread
    [Node]$Gap
    [Node]$Columns
    [object[]]$Responsive
    UiLayoutSpec() {
        $this.Mode = $null
        $this.Align = $null
        $this.Spread = $false
        $this.Gap = $null
        $this.Columns = $null
        $this.Responsive = @()
    }
}

class UiAnimationStep {
    [string]$Operation   # 'fade', 'move', 'scale', 'rotate', 'slide', 'grow', 'shrink'
    [string]$Direction   # 'in', 'out', 'up', 'down', 'left', 'right'
    [Node]$Amount
    UiAnimationStep([string]$operation, [string]$direction, [Node]$amount) {
        $this.Operation = $operation
        $this.Direction = $direction
        $this.Amount = $amount
    }
}

class UiAnimationBlock : Node {
    [string]$Trigger     # 'hover', 'press', 'enter', 'leave'
    [UiAnimationStep[]]$Steps
    [double]$DurationMs
    [string]$Easing      # 'ease', 'ease-out', 'ease-in', 'linear', 'spring'
    UiAnimationBlock([string]$trigger, [UiAnimationStep[]]$steps, [double]$durationMs, [string]$easing, [int]$line)
        : base([NodeKind]::UiAnimation, $line) {
        $this.Trigger = $trigger
        $this.Steps = $steps
        $this.DurationMs = $durationMs
        $this.Easing = $easing
    }
}

class UiEventStmt : Node {
    [string]$EventName   # 'click', 'change', 'input', 'submit', 'hover', 'press', 'focus', 'blur'
    [Node[]]$Body
    UiEventStmt([string]$eventName, [Node[]]$body, [int]$line)
        : base([NodeKind]::UiEvent, $line) {
        $this.EventName = $eventName
        $this.Body = $body
    }
}

class UiElementStmt : Node {
    [string]$Tag
    [string]$Variant
    [Node]$Label
    [string]$Name
    [UiLayoutSpec]$Layout
    [Node[]]$Properties
    [Node[]]$Events
    [Node[]]$Animations
    [Node[]]$Children
    UiElementStmt([string]$tag, [string]$variant, [Node]$label, [string]$name, [UiLayoutSpec]$layout, [Node[]]$properties, [Node[]]$events, [Node[]]$animations, [Node[]]$children, [int]$line)
        : base([NodeKind]::UiElement, $line) {
        $this.Tag = $tag
        $this.Variant = $variant
        $this.Label = $label
        $this.Name = $name
        $this.Layout = $layout
        $this.Properties = $properties
        $this.Events = $events
        $this.Animations = $animations
        $this.Children = $children
    }
}

class StateDefStmt : Node {
    [string]$Name
    [Node]$InitialValue
    StateDefStmt([string]$name, [Node]$initialValue, [int]$line)
        : base([NodeKind]::StateDef, $line) {
        $this.Name = $name
        $this.InitialValue = $initialValue
    }
}

class DeriveDefStmt : Node {
    [string]$Name
    [Node]$Expression
    DeriveDefStmt([string]$name, [Node]$expression, [int]$line)
        : base([NodeKind]::DeriveDef, $line) {
        $this.Name = $name
        $this.Expression = $expression
    }
}

class MemoDefStmt : Node {
    [string]$Name
    [Node[]]$Body
    MemoDefStmt([string]$name, [Node[]]$body, [int]$line)
        : base([NodeKind]::MemoDef, $line) {
        $this.Name = $name
        $this.Body = $body
    }
}

class WatchStmt : Node {
    [string]$TargetName
    [Node[]]$Body
    WatchStmt([string]$targetName, [Node[]]$body, [int]$line)
        : base([NodeKind]::Watch, $line) {
        $this.TargetName = $targetName
        $this.Body = $body
    }
}

class LifecycleStmt : Node {
    [string]$Stage       # 'start', 'close'
    [Node[]]$Body
    LifecycleStmt([string]$stage, [Node[]]$body, [int]$line)
        : base([NodeKind]::Lifecycle, $line) {
        $this.Stage = $stage
        $this.Body = $body
    }
}

class AwaitExpr : Node {
    [Node]$Expression
    AwaitExpr([Node]$expression, [int]$line)
        : base([NodeKind]::Await, $line) {
        $this.Expression = $expression
    }
}

class SharedStateStmt : Node {
    [string]$Name
    [Node]$InitialValue
    SharedStateStmt([string]$name, [Node]$initialValue, [int]$line)
        : base([NodeKind]::SharedState, $line) {
        $this.Name = $name
        $this.InitialValue = $initialValue
    }
}

class UiActionStmt : Node {
    [string]$Action      # 'focus', 'hide', 'show'
    [Node]$Target
    UiActionStmt([string]$action, [Node]$target, [int]$line)
        : base([NodeKind]::UiAction, $line) {
        $this.Action = $action
        $this.Target = $target
    }
}

class UseModuleStmt : Node {
    [string]$Module
    UseModuleStmt([string]$module, [int]$line)
        : base([NodeKind]::UseModule, $line) {
        $this.Module = $module
    }
}


# ===============================================================
# DATABASE OPERATIONS (D97)
# ===============================================================

class DbParameter {
    [string]$Name
    [Node]$Value
    [int]$Line
    DbParameter([string]$name, [Node]$value, [int]$line) {
        $this.Name = $name
        $this.Value = $value
        $this.Line = $line
    }
}

class ConnectDbStmt : Node {
    [Node]$Config
    [string]$Target
    ConnectDbStmt([Node]$config, [string]$target, [int]$line) : base([NodeKind]::ConnectDb, $line) {
        $this.Config = $config
        $this.Target = $target
    }
}

class DisconnectDbStmt : Node {
    [Node]$Connection
    DisconnectDbStmt([Node]$connection, [int]$line) : base([NodeKind]::DisconnectDb, $line) {
        $this.Connection = $connection
    }
}

class DbQueryStmt : Node {
    [Node]$Connection
    [Node]$Query
    [DbParameter[]]$Parameters
    [string]$Target
    DbQueryStmt([Node]$connection, [Node]$query, [DbParameter[]]$parameters, [string]$target, [int]$line) : base([NodeKind]::DbQuery, $line) {
        $this.Connection = $connection
        $this.Query = $query
        $this.Parameters = $parameters
        $this.Target = $target
    }
}

class DbExecuteStmt : Node {
    [Node]$Connection
    [Node]$Command
    [DbParameter[]]$Parameters
    [string]$Target
    DbExecuteStmt([Node]$connection, [Node]$command, [DbParameter[]]$parameters, [string]$target, [int]$line) : base([NodeKind]::DbExecute, $line) {
        $this.Connection = $connection
        $this.Command = $command
        $this.Parameters = $parameters
        $this.Target = $target
    }
}

class BeginTransactionStmt : Node {
    [Node]$Connection
    [string]$Target
    BeginTransactionStmt([Node]$connection, [string]$target, [int]$line) : base([NodeKind]::BeginTransaction, $line) {
        $this.Connection = $connection
        $this.Target = $target
    }
}

class CommitTransactionStmt : Node {
    [Node]$Transaction
    CommitTransactionStmt([Node]$transaction, [int]$line) : base([NodeKind]::CommitTransaction, $line) {
        $this.Transaction = $transaction
    }
}

class RollbackTransactionStmt : Node {
    [Node]$Transaction
    RollbackTransactionStmt([Node]$transaction, [int]$line) : base([NodeKind]::RollbackTransaction, $line) {
        $this.Transaction = $transaction
    }
}

class GetTablesStmt : Node {
    [Node]$Connection
    [string]$Target
    GetTablesStmt([Node]$connection, [string]$target, [int]$line) : base([NodeKind]::GetTables, $line) {
        $this.Connection = $connection
        $this.Target = $target
    }
}

class GetColumnsStmt : Node {
    [Node]$Table
    [Node]$Connection
    [string]$Target
    GetColumnsStmt([Node]$table, [Node]$connection, [string]$target, [int]$line) : base([NodeKind]::GetColumns, $line) {
        $this.Table = $table
        $this.Connection = $connection
        $this.Target = $target
    }
}


# ===============================================================
# CONSOLE UX PRIMITIVES (D100)
# ===============================================================
#
# Console/interpreter target only for this first pass. Desktop and web
# targets report a clean "not supported on this target" diagnostic rather
# than a silently different or degraded behavior.

# set cursor to row 5 column 10
# Otter's row/column are 1-based, matching D5's inclusive counting
# convention - the interpreter subtracts 1 before calling the real
# [Console]::SetCursorPosition, which is 0-based.
class SetCursorPositionStmt : Node {
    [Node]$Row
    [Node]$Column
    SetCursorPositionStmt([Node]$row, [Node]$column, [int]$line) : base([NodeKind]::SetCursorPosition, $line) {
        $this.Row = $row
        $this.Column = $column
    }
}

# choose from options into choice
# Reuses D67's Choose token family. Target receives the SELECTED ITEM
# itself, not its position - matching how `random item from games into
# game` already hands back an element, not an index.
class ChooseFromListStmt : Node {
    [Node]$Options
    [string]$Target
    ChooseFromListStmt([Node]$options, [string]$target, [int]$line) : base([NodeKind]::ChooseFromList, $line) {
        $this.Options = $options
        $this.Target = $target
    }
}

# show progress 50 percent
# No label/message argument in this first pass - deliberate, see D100.
class ShowProgressStmt : Node {
    [Node]$Percent
    ShowProgressStmt([Node]$percent, [int]$line) : base([NodeKind]::ShowProgress, $line) {
        $this.Percent = $percent
    }
}

# console is interactive                                             (D100)
# An EXPRESSION (usable directly in an `if`/`while` condition, same as any
# other boolean-valued expression), not a statement. No fields: the whole
# meaning is carried by the NodeKind itself, parsed from the single
# combined ConsoleInteractive token (see src/Otter.Lexer.psm1's phrase
# combiner - the same mechanism `is at least`/`for each` already use) so
# "console" remains an ordinary, unreserved identifier everywhere else.
class ConsoleInteractiveExpr : Node {
    ConsoleInteractiveExpr([int]$line) : base([NodeKind]::ConsoleInteractive, $line) {
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
