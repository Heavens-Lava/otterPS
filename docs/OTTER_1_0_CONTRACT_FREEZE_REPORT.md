# Otter 1.0 Contract Freeze Report

This document records the **authoritative, formal freeze** of the Otter 1.0 language contract, abstract syntax tree (AST), grammar rules, standard library public API, diagnostic taxonomy, and target capability matrix.

As of this freeze, no new syntax, AST node kinds, keywords, or breaking semantic changes may be introduced. All work prior to `1.0.0` is strictly restricted to bug fixes, specification clarity, cross-platform certification, hardening, and documentation.

---

## 1. Executive Summary

- **Contract Status**: **FROZEN** (Otter 1.0 Baseline)
- **Primary Contract Source**: `Otter.Contract.psm1` (Frozen interface between Front-End & Back-End)
- **Specification Precedents**: `SPEC-DECISIONS.md` (D1–D119)
- **Dogfood Certification**: D119 Certified with 0 host-language workaround LOC
- **Platform Regression Status**: 54/54 platform test suites passed (100% green)

---

## 2. Lexical & Grammar Contract

### 2.1 Tokens and Keywords (`TokenKind`)
The lexical grammar defines 132 token kinds categorized into:
- **Literals & Identifiers**: `Identifier`, `Number`, `String`, `True`, `False`, `Gone` (null/missing sentinel).
- **Multi-Word Fixed Tokens**: `for each`, `is at least`, `is at most`, `is greater than`, `is less than`, `is not`, `divided by`, `starts with`, `ends with`, `console is interactive`, `elapsed time`, `elapsed milliseconds`.
- **Operators**:
  - Math: `And` (addition in math/make contexts), `Minus`, `Times`, `DividedBy`, `Percent`, `Power`.
  - Logic: `Not`, `And` (boolean and inside conditions), `Or`.
  - Comparison: `Is`, `IsNot`, `IsAtLeast`, `IsAtMost`, `IsGreaterThan`, `IsLessThan`, `Contains`, `IsIn`, `IsNotIn`, `IsBetween`.
- **Mutations & Assignments**: `Make` (`makes`), `Add`, `Remove`, `To`, `From`, `Set`, `Into`, `As`.
- **Control Flow**: `If`, `Otherwise`, `While`, `Repeat`, `Count`, `ForEach`, `Return`, `Try`, `Fail`.
- **Block Formatting**: `Indent`, `Dedent`, `Newline`, `BlockEnd` (`.` alone on a line), `EndOfFile`.
- **Modules & Imports**: `Use`.

### 2.2 Property Access vs. Operation Syntax
- `X of Y`:
  - **Property Access** (`PropertyAccess`): Field access on records, objects, and UI resources (`name of person`, `text of button`).
  - **Operation** (`OfOperation`): Built-in value transformations (`length of`, `uppercase of`, `lowercase of`, `first of`, `last of`, `absolute value of`, `square root of`, `round of`, `sine of`, `cosine of`, `tangent of`, `log of`, `natural log of`).

---

## 3. AST Node Inventory (`NodeKind`)

The AST contract defines 114 immutable node kinds:

### 3.1 Expressions
- `Literal`, `Variable`, `Math`, `Comparison`, `Call`, `Logical`, `Not`, `Contains`, `PropertyAccess`, `OfOperation`, `TextMatch`, `MinMax`, `Clock`, `DateDifferenceValue`, `DateFromText`, `Bytes`, `BytesFromFile`, `QueryBetweenExpr`, `QueryInExpr`, `ConsoleInteractive`, `FileExists`, `FileLocked`, `FileIsSymbolicLink`, `FileIsReadOnly`, `RegistryKeyExists`, `SecretExists`, `SecretRead`, `ChangedPath`, `ChangedFileName`, `ChangeKind`, `OldPath`, `ReceivedMessage`, `CloseCode`, `CloseReason`, `CloseWasClean`, `WebSocketErrorValue`, `NetContext`, `ConnectionIsSecure`, `JobContext`.

### 3.2 Statements & Control Flow
- `Say`, `Assign`, `Ask`, `MathInto`, `AddTo`, `RemoveFrom`, `If`, `While`, `Repeat`, `CountLoop`, `ForEach`, `ListDef`, `FunctionDef`, `CallStatement`, `Return`, `Try`, `Fail`, `Diagnostic`, `UseModule`.

### 3.3 Domain Types & Collections
- `ObjectDef` (`person is a thing`), `TypeDef` (`a Person has name and age`).
- `GetKey`, `SetKey` (dynamic indexer access).
- `Sort`, `Reverse`, `Replace`, `Split`, `Join`, `Find`.

### 3.4 Filesystem & Archiving
- `ReadFile`, `WriteFile`, `AppendFile`, `CopyFile`, `MoveFile`, `DeleteFile`.
- `WriteBytesFile` (Binary I/O with optional atomic rename).
- `GetFiles`, `GetFolders`, `CreateFolder`, `DeleteFolder`, `CopyFolder`, `MoveFolder`.
- `ZipFolder`, `UnzipFile`.
- `WatchDeclare`, `StopWatching`, `WatchEvent`.

### 3.5 Process & Command Execution
- `RunProgram` (synchronous execution with exit code, stdout, stderr).
- `StartCommand` (D119-R2 asynchronous job execution with live streaming and cancellation).
- `GetProcesses`, `KillProcess`, `SetProcessPriority`, `WaitForProcess`.

### 3.6 Data & Formats
- JSON: `ReadJson`, `ConvertToJson`, `ConvertFromJson`.
- CSV: `ReadCsv`, `WriteCsv`, `ConvertToCsv`, `ConvertFromCsv`.
- XML: `XmlFrom`, `XmlSelect`, `XmlAttribute`, `XmlTextOfNameIn`, `XmlElementExists`, `XmlHasAttribute`, `XmlToText`, `XmlSetText`, `XmlSetAttribute`, `XmlRemoveAttribute`, `XmlAddElement`, `XmlRemoveElement`, `XmlWriteFile`.
- Query: `QueryStmt`, `QueryAggregateStmt`.

### 3.7 Networking, HTTP & WebSockets
- `HttpGet`, `HttpPost`, `HttpPut`, `HttpDelete`, `DownloadFile`.
- `HttpStart`, `HttpCancel` (cancellable asynchronous requests).
- `WebSocketConnect`, `WebSocketSend`, `WebSocketClose`, `WebSocketEvent`.
- `TcpConnect`, `UdpOpen`, `UdpSend`, `NetClose`, `TcpListen`, `TcpStop`.
- `WebRoute`, `Respond`, `StartServer`, `ListenServer`.

### 3.8 Cryptography & Security
- `HashText`, `EncryptText`, `DecryptText`, `CryptoHash`, `CryptoHmac`, `GenerateKey`, `CryptoCipher`, `HashPassword`, `PasswordMatches`, `SecurelyEquals`, `SecureRandomBytes`.
- `StoreSecret`, `DeleteSecret`, `GetCredential`, `SetCredential`, `DeleteCredential`.

### 3.9 Desktop UI & Web SPA
- Desktop WPF Controls: `CreateUiResource`, `PutIn`, `Show`, `When`.
- Declarative UI & Web: `UiElement`, `UiLayout`, `StateDef`, `DeriveDef`, `MemoDef`, `UiEvent`, `Watch`, `Lifecycle`, `UiAnimation`, `Await`, `SharedState`, `Route`, `GoToRoute`, `GoNavigate`, `ReplaceRoute`, `RouteChangeEvent`, `CurrentRoute`, `RouteParameter`, `QueryParameter`, `DragContext`, `SetDragData`.

---

## 4. Standard Library Public API

The standard library consists of built-in operations exposed directly through readable syntax:

| Domain | Syntax Forms | Return / Result |
|---|---|---|
| **Math** | `A and B make C`, `A minus B`, `A times B`, `A divided by B`, `A percent of B`, `A power B`, `square root of X`, `round of X`, `round up of X`, `round down of X`, `larger of X and Y`, `smaller of X and Y`, `sine of X`, `cosine of X`, `tangent of X`, `log of X`, `natural log of X` | Numbers |
| **Collections** | `length of C`, `first of C`, `last of C`, `sort C`, `reverse C`, `find X in C where ... into R`, `C contains X`, `X is in C`, `X is between low and high` | Values / Booleans |
| **Strings** | `uppercase of S`, `lowercase of S`, `starts with`, `ends with`, `replace X with Y in S`, `split S by D into L`, `join L with D into S` | Strings / Lists |
| **Dates & Times** | `today`, `now`, `days between A and B`, `date from "..." using "..."`, `format D as "..." into S`, `add N days to D`, `wait N seconds`, `start timer T`, `elapsed milliseconds of T` | Date / Duration |
| **Files & Folders** | `read P into T`, `write T to P [atomically]`, `append T to P`, `read json from P into D`, `bytes from file P`, `write bytes B to file P [atomically]`, `get files in P [and subfolders] into L`, `watch folder P recursively and call it W` | Filesystem actions |
| **Async Jobs** | `start command "..." and call it J`, `cancel J`, `wait for process J up to N seconds`, `on stdout from J ... .`, `on complete of J ... .` | Process handles |
| **Data Formats** | `convert X to json into T`, `convert T from json into X`, `xml from file P`, `elements "tag" in X`, `query db with ... into R` | Structured objects |
| **Crypto & Vault** | `hash S as "sha256" [with key K] into D`, `encrypt S with key K into C`, `decrypt C with key K into S`, `hash password P into H`, `password P matches H`, `store secret N with value V`, `secret N` | Hashes / Ciphertext / Secrets |

---

## 5. Error & Diagnostic Taxonomy (`OtterError`)

Every syntax, type, runtime, or host violation produces a structured `OtterError` with:
- `Message`: Friendly, human-readable diagnostic (e.g. `Otter expected "than" after "greater".`).
- `Line`: 1-based source line number, accurately remapped through multi-module imports (`use "..."`).
- `SourceLine`: Exact snippet of the offending line.
- `Suggestion`: Actionable guidance for resolution.
- `Stage`: Explicit failure origin (`check` for lexer/parser, `runtime` for execution).

### Exit Codes
- `0`: Success
- `1`: CLI usage error (bad arguments, file not found)
- `2`: Syntax / check error (lexer or parser rejection)
- `3`: Runtime error (runtime failure or user `fail with`)

---

## 6. Target Capability & Explicit Rejection Matrix

| Subsystem | Console (`otter run`) | Desktop (`otter desktop`) | Web Compiler (`otter web`) |
|---|---|---|---|
| **Core Syntax & Semantics** | Supported | Supported | Supported |
| **Filesystem & Binary I/O** | Supported | Supported | Blocked (Explicit diagnostic) |
| **Processes & Async Jobs** | Supported | Supported | Blocked (Explicit diagnostic) |
| **WPF Window & Controls** | Blocked | Supported | Blocked |
| **Declarative UI & DOM** | Blocked | Blocked | Supported |
| **Fetch & SPA Routing** | Blocked | Blocked | Supported |
| **WebSockets** | Supported | Supported | Supported |
| **TCP / UDP Sockets** | Supported | Supported | Blocked (Explicit diagnostic) |
| **Crypto & Vault** | Supported | Supported | Blocked (Explicit diagnostic) |

---

## 7. Versioning & Compatibility Commitment

1. **Semantic Versioning**: Otter follows `MAJOR.MINOR.PATCH`.
2. **1.0.0 Guarantee**: All valid programs accepted by `1.0.0` will remain valid and produce identical semantics across all `1.x.y` releases.
3. **Deprecation Policy**: No syntax or API will be removed without a minimum of one full minor version cycle with explicit compiler warnings.

---

## 8. Certification Sign-off

- **Grammar & Lexer**: Certified Frozen
- **AST Contract (`Otter.Contract.psm1`)**: Certified Frozen
- **Standard Library Public API**: Certified Frozen
- **Diagnostics & Exit Codes**: Certified Frozen
- **Dogfood Baseline (D119)**: Certified Frozen (0 Workaround LOC)
