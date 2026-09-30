# Otter Programming Language — Formal Grammar Specification (v1.0)

This document specifies the formal grammar for the **Otter Programming Language** in Extended Backus-Naur Form (EBNF).

It covers the core language: values, variables, arithmetic, conditions,
loops, functions, lists, objects and error handling. Library statements
(files, HTTP, processes, dates, data formats, UI and so on) are described on
their own documentation pages and are not all listed here. Many words are
reserved and cannot be used as ordinary names; see
[OTTER_1_0_RESERVED_WORDS.md](OTTER_1_0_RESERVED_WORDS.md).

---

## 1. Lexical Grammar

### 1.1 Characters and Whitespace
```ebnf
SourceCharacter = ? any Unicode character ? ;
Newline         = "\r\n" | "\n" | "\r" ;
Whitespace      = " " | "\t" ;
Comment         = "#" , { ? any character except Newline ? } ;
```

### 1.2 Indentation and Layout Tokens
Indentation is synthesized into explicit tokens by the lexer:
```ebnf
Indent   = ? token emitted when indentation level increases by 4 spaces or 1 tab ? ;
Dedent   = ? token emitted when indentation level decreases ? ;
BlockEnd = "." ;
```

### 1.3 Literals
```ebnf
Letter          = ? any Unicode letter ? | "_" ;
Digit           = "0" .. "9" ;
Digits          = Digit , { Digit } ;

NumberLiteral   = Digits , [ "." , Digits ] ;
StringLiteral   = '"' , { StringChar | Escape } , '"' ;
StringChar      = ? any character except '"', '\' or Newline ? ;
Escape          = '\n' | '\t' | '\\' | '\"' | '\' , ? any other character ? ;
BooleanLiteral  = "true" | "false" ;
GoneLiteral     = "gone" ;

Literal         = NumberLiteral | StringLiteral | BooleanLiteral | GoneLiteral ;
```

A number literal has no sign, exponent, leading or trailing `.`, or digit
grouping. `-5` is a syntax error; write a negative number as a subtraction,
for example `x is 0 minus 5`.

Text uses double quotes and stays on one line. The escapes are `\n`
(newline), `\t` (tab), `\\` (one backslash) and `\"` (a quote). There is no
`\r`. Any other backslash sequence is kept exactly as written (`\q` stays
`\q`). A Windows path therefore needs doubled backslashes, `"C:\\new\\table"`,
or forward slashes, `"C:/new/table"`; `"C:\new\table"` would contain a
newline and a tab.

### 1.4 Identifiers
```ebnf
Identifier      = Letter , { Letter | Digit } ;
```

Identifiers are case-sensitive. Reserved words cannot be used as
identifiers; see [OTTER_1_0_RESERVED_WORDS.md](OTTER_1_0_RESERVED_WORDS.md).

---

## 2. Syntactic Grammar

### 2.1 Program Structure
```ebnf
Program         = { StatementLine } , [ Statement ] , EndOfFile ;
StatementLine   = [ Statement ] , ( Newline | EndOfFile ) ;
```

### 2.2 Statements
```ebnf
Statement       = AssignStmt
                | MathIntoStmt
                | SayStmt
                | AskStmt
                | AddToStmt
                | RemoveFromStmt
                | IfStmt
                | WhileStmt
                | RepeatStmt
                | CountLoopStmt
                | ForEachStmt
                | FunctionDefStmt
                | CallStmt
                | ReturnStmt
                | StopStmt
                | TypeDefStmt
                | ObjectDefStmt
                | ListDefStmt
                | TryCatchStmt
                | UseStmt
                | FileStmt
                | HttpStmt
                | RunStmt
                | FormatDateStmt
                | LogStmt
                | UiStmt
                ;
```

### 2.3 Core Statements
```ebnf
AssignStmt      = Identifier , "is" , Expression
                | PropertyChain , "is" , Expression ;

MathIntoStmt    = Expression , "make" , Identifier ;

SayStmt         = "say" , { Expression } ;

AskStmt         = "ask" , Expression , "and" , "call" , "it" , Identifier ;

AddToStmt       = "add" , Expression , "to" , Identifier ;
RemoveFromStmt  = "remove" , Expression , "from" , Identifier ;

IfStmt          = "if" , Condition , Newline , IndentedBlock
                , { "otherwise" , "if" , Condition , Newline , IndentedBlock }
                , [ "otherwise" , Newline , IndentedBlock ] ;

WhileStmt       = "while" , Condition , Newline , IndentedBlock ;

RepeatStmt      = "repeat" , PrimaryExpr , "times" , Newline , IndentedBlock ;

CountLoopStmt   = "count" , "from" , Expression , "to" , Expression , "as" , Identifier , Newline , IndentedBlock ;

ForEachStmt     = ( "for" , "each" | "each" ) , Identifier , "in" , Expression , Newline , IndentedBlock ;

FunctionDefStmt = "to" , Identifier , { [ "and" ] , Identifier } , Newline , IndentedBlock ;

ReturnStmt      = "return" , Expression ;
StopStmt        = "stop" ;

ListDefStmt     = Identifier , "are" , "empty"
                | Identifier , "are" , Newline , Indent , { Expression , Newline } , Dedent , [ BlockEnd ] ;

ObjectDefStmt   = Identifier , "has" , PropertyList
                | Identifier , "is" , "a" , Identifier ;

TypeDefStmt     = "a" , Identifier , "has" , Newline , Indent , { Identifier , Newline } , Dedent , [ BlockEnd ] ;

TryCatchStmt    = "try" , Newline , IndentedBlock
                , [ "otherwise" , [ "into" , Identifier ] , Newline , IndentedBlock ] ;

UseStmt         = "use" , StringLiteral ;

RunStmt         = "run" , [ "command" ] , Expression , [ "into" , Identifier ] ;

FormatDateStmt  = "format" , Expression , "as" , Expression , "into" , Identifier ;

LogStmt         = ( "log" | "warn" | "error" ) , Expression ;

IndentedBlock   = Indent , { StatementLine } , Dedent , [ BlockEnd ] ;

CallStmt        = Identifier , { Argument } , [ "make" , Identifier ] ;
CallExpr        = Identifier , Argument , { "and" , Argument } ;
Argument        = PrimaryExpr ;
```

`otherwise` is optional in `try`. Without it, a failure inside the `try`
block is swallowed and the program continues after the block.

A function call takes exactly as many arguments as the function declares,
and each argument is **one value**: a literal, a variable or a property
chain, not a calculation. `fact n minus 1` therefore means
`(fact n) minus 1`. Compute the argument into a variable first:

```otter
m is n minus 1
r is fact m
```

`use "relative/path.ot"` imports an Otter source file relative to the file
containing the statement. The console production entry point resolves file
imports before lexing. Imports are expanded in source order, duplicate files
are included once, and circular imports produce a diagnostic. Package-name
imports and a package registry are outside the 1.0 file-import grammar.


### 2.4 Expressions and evaluation order

Arithmetic has **no operator precedence**. An arithmetic expression is
evaluated strictly from left to right, so `2 plus 3 times 4` is `20`
(`(2 plus 3) times 4`), and `10 - 4 / 2` is `3`. There are no parentheses:
`(` is not part of the language. To control the order, compute a part into a
variable first.

Arithmetic operators, all at the same level:

| Operation | Words | Symbol |
|---|---|---|
| add (and join two texts) | `plus`, `and` | `+` |
| subtract | `minus` | `-` |
| multiply | `times` | `*` |
| divide | `divided by` | `/` |
| percentage | `percent of` | |
| power | `power` | |

Comparisons and logic exist only inside conditions (`if`, `otherwise if`,
`while`). They are not values: `say x is 5` and `return age is at least 18`
are syntax errors. Each side of a comparison may be a **calculation**, read
left to right like any other (D123): `if price plus tax is at least 100`
compares `(price plus tax)` with 100. The word `and` between comparisons stays
logical, so `if x is 4 and y is 5` is two comparisons, and `and` is not an
arithmetic word inside a condition (write `plus` or `+` there):

```otter
if price plus tax is at least 100
    say "free shipping"
```

Inside a condition, `not` binds tighter than `and`, which binds tighter than
`or`, and `and` and `or` short-circuit from left to right.

```ebnf
Expression      = Term , { ArithOp , Term } ;
ArithOp         = "plus" | "and" | "+" | "minus" | "-" | "times" | "*"
                | "divided" , "by" | "/" | "percent" , "of" | "power" ;
Term            = PrimaryExpr | CallExpr ;

Condition       = OrCondition ;
OrCondition     = AndCondition , { "or" , AndCondition } ;
AndCondition    = NotCondition , { "and" , NotCondition } ;
NotCondition    = [ "not" ] , Comparison ;

Comparison      = CompareOperand , [ CompareOp , CompareOperand ] ;
CompareOperand  = Term , { CondArithOp , Term } ;       (* D123 *)
CondArithOp     = ArithOp - "and" ;
CompareOp       = "is" | "is not"
                | "is greater than" | "is less than"
                | "is at least" | "is at most"
                | "contains" | "starts with" | "ends with" ;

PrimaryExpr     = Literal
                | Identifier
                | ClockExpr
                | DateDiffExpr
                | FileExistsExpr
                | OfOperationExpr
                | PropertyChain ;

ClockExpr       = "today" | "now" ;
DateDiffExpr    = TimeUnit , "between" , Expression , "and" , Expression ;
TimeUnit        = "days" | "hours" | "minutes" | "seconds" | "months" | "years" ;

FileExistsExpr  = "file" , Expression , "exists" ;

PropertyChain   = Identifier , "of" , PrimaryExpr ;
OfOperationExpr = ( "length" | "uppercase" | "lowercase" | "first" | "last" ) , "of" , PrimaryExpr ;
```
