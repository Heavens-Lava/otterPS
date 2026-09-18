# Otter Programming Language — Formal Grammar Specification (v1.0)

This document specifies the formal grammar for the **Otter Programming Language** in Extended Backus-Naur Form (EBNF).

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
Letter          = "a" .. "z" | "A" .. "Z" | "_" ;
Digit           = "0" .. "9" ;
Digits          = Digit , { Digit } ;

NumberLiteral   = [ "-" ] , Digits , [ "." , Digits ] ;
StringLiteral   = '"' , { ? any character except '"' or Newline ? | '\"' } , '"' ;
BooleanLiteral  = "true" | "false" ;
GoneLiteral     = "gone" ;

Literal         = NumberLiteral | StringLiteral | BooleanLiteral | GoneLiteral ;
```

### 1.4 Identifiers
```ebnf
Identifier      = Letter , { Letter | Digit } ;
```

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

RepeatStmt      = "repeat" , Expression , "times" , Newline , IndentedBlock ;

CountLoopStmt   = "count" , "from" , Expression , "to" , Expression , "as" , Identifier , Newline , IndentedBlock ;

ForEachStmt     = ( "for" , "each" | "each" ) , Identifier , "in" , Expression , Newline , IndentedBlock ;

FunctionDefStmt = "to" , Identifier , { [ "and" ] , Identifier } , Newline , IndentedBlock ;

ReturnStmt      = "return" , Expression ;
StopStmt        = "stop" ;

ListDefStmt     = Identifier , "are" , "empty"
                | Identifier , "are" , Newline , Indent , { Expression , Newline } , Dedent , [ BlockEnd ] ;

ObjectDefStmt   = Identifier , "has" , PropertyList
                | Identifier , "is" , "a" , Identifier ;

TypeDefStmt     = ( "a" | "an" ) , Identifier , "has" , Newline , Indent , { Identifier , Newline } , Dedent , [ BlockEnd ] ;

TryCatchStmt    = "try" , Newline , IndentedBlock , "otherwise" , Newline , IndentedBlock ;

(* Modules / use is deferred to 1.1+ *)
UseStmt         = (* DEFERRED TO 1.1+ *) "use" , StringLiteral ;

RunStmt         = "run" , [ "command" ] , Expression , [ "into" , Identifier ] ;

FormatDateStmt  = "format" , Expression , "as" , Expression , "into" , Identifier ;

LogStmt         = ( "log" | "warn" | "error" ) , Expression ;

IndentedBlock   = Indent , { StatementLine } , Dedent , [ BlockEnd ] ;
```


### 2.4 Expressions & Operator Precedence

Precedence (from tightest to loosest):
1. Primary expressions, literals, variables, clock (`today`, `now`)
2. `of` property and operation chains (right-recursive)
3. Multiplicative: `times`, `divided by`
4. Additive: `plus`, `minus` (and `and` in `make` math context)
5. Comparisons: `is`, `is not`, `is greater than`, `is less than`, `is at least`, `is at most`, `contains`, `starts with`, `ends with`
6. Logical `not`
7. Logical `and`
8. Logical `or`

```ebnf
Expression      = LogicalOrExpr ;

LogicalOrExpr   = LogicalAndExpr , { "or" , LogicalAndExpr } ;
LogicalAndExpr  = LogicalNotExpr , { "and" , LogicalNotExpr } ;
LogicalNotExpr  = [ "not" ] , ComparisonExpr ;

ComparisonExpr  = AdditiveExpr , [ CompareOp , AdditiveExpr ] ;
CompareOp       = "is" | "is not"
                | "is greater than" | "is less than"
                | "is at least" | "is at most"
                | "contains" | "starts with" | "ends with" ;

AdditiveExpr    = MultiplicativeExpr , { ( "plus" | "minus" ) , MultiplicativeExpr } ;
MultiplicativeExpr = UnaryExpr , { ( "times" | "divided by" ) , UnaryExpr } ;

UnaryExpr       = PrimaryExpr ;

PrimaryExpr     = Literal
                | Identifier
                | ClockExpr
                | DateDiffExpr
                | FileExistsExpr
                | OfOperationExpr
                | PropertyChain
                | "(" , Expression , ")" ;

ClockExpr       = "today" | "now" ;
DateDiffExpr    = TimeUnit , "between" , Expression , "and" , Expression ;
TimeUnit        = "days" | "hours" | "minutes" | "seconds" | "months" | "years" ;

FileExistsExpr  = "file" , Expression , "exists" ;

PropertyChain   = Identifier , "of" , PrimaryExpr ;
OfOperationExpr = ( "length" | "uppercase" | "lowercase" | "first" | "last" ) , "of" , PrimaryExpr ;
```
