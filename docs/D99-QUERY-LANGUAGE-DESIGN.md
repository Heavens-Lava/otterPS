# D99: Otter Query Language Design (OQL)

**Status:** Design Proposal & Feasibility Research  
**Target:** Otter 1.1+  
**Implementation:** Not approved yet (Exploratory / RFC)  
**Author:** Pair programming research (Jeff & Antigravity)  
**Authoritative Spec Reference:** Jeff's D99 Language Design Brief  

---

## 1. Executive Summary & Design Mandate

Otter 1.0 established a clean, natural, English-like syntax for imperative programming, file I/O, networking, and UI construction. Otter 1.1 introduced database foundations (D97) and schema introspection (D98). However, database queries in D97 still require raw SQL text strings:

```otter
query db with
    "SELECT id, name, email FROM customers WHERE state = @state"
    parameter "state" is "Arizona"
into customers
```

While raw SQL remains a permanent, mandatory escape hatch for advanced queries, SQL syntax diverges sharply from Otter's grammar:
1. SQL uses `=` for comparison; Otter uses `is`.
2. SQL uses `<>`, `!=`; Otter uses `is not`.
3. SQL uses `AND`, `OR`; Otter uses `and`, `or`.
4. SQL parameters require explicit `@param` boilerplate and string interpolation vulnerabilities if misused.
5. SQL error messages return database engine internals (e.g. `SQLSTATE 42703`) rather than friendly, line-anchored Otter diagnostics.

**D99 Otter Query Language (OQL)** proposes a native, declarative, English-like query syntax integrated directly into the Otter grammar.

### Guiding Axioms
1. **Readable Aloud:** Code reads like clear, grammatical English sentences.
2. **Deterministic:** Governed by strict, unambiguous grammar rules (no LLM/AI guessing at parse time).
3. **Safe by Default:** Every user value in filter conditions is parameterized automatically by the provider. Zero SQL injection surface.
4. **Provider-Neutral:** Otter queries parse into an abstract Query AST; providers compile that AST into native dialect queries (SQLite, PostgreSQL, SQL Server, MySQL) or in-memory operations (JS Web Compiler).
5. **Progressive Complexity:** Simple single-table queries are minimal; grouping, outer joins, and projections expand naturally without syntax upheaval.
6. **Not an ORM:** No entity change tracking, lazy loading, or model classes. OQL is a relational projection and filtering language producing standard Otter lists and objects.

---

## 2. Core Grammar and Lexer Feasibility Analysis

A critical question is whether D99 can integrate into Otter without creating syntactic ambiguities with existing language constructs.

### 2.1 Existing Token & Keyword Inventory
The Otter lexer already defines several keywords central to OQL:
- `get` (`TokenKind::Get`)
- `from` (`TokenKind::From`)
- `where` (`TokenKind::Where`) — currently used in `find <item> in <collection> where <cond> into <target>`
- `into` (`TokenKind::Into`)
- `as` (`TokenKind::As`)
- `of` (`TokenKind::Of`)
- `is`, `is not`, `is at least`, `is at most`, `is greater than`, `is less than`
- `and`, `or`, `not`
- `gone`, `true`, `false`

### 2.2 New Contextual Keywords & Multi-Word Tokens
To keep the lexer clean and avoid breaking user variables named `order` or `group`, multi-word tokens follow the existing precedent (`for each`, `is at least`):
- `order by` -> `[TokenKind]::OrderBy`
- `group by` -> `[TokenKind]::GroupBy`
- `even when none` -> `[TokenKind]::EvenWhenNone` (or parsed as contextual sequence)
- `keep groups where` -> `[TokenKind]::KeepGroupsWhere`
- `include` -> Contextual keyword inside query statements (or dedicated `[TokenKind]::Include`)
- `descending`, `ascending` -> Contextual modifiers after `order by` expressions

### 2.3 The D41 Dynamic Key Access & HTTP Conflict
In `src/Otter.Parser.psm1`, `get` currently dispatches:
1. `get files in ...`
2. `get folders in ...`
3. `get tables from <conn> into ...` (D98)
4. `get columns from <table> in <conn> into ...` (D98)
5. `get json from <url> into ...`
6. `get <key> from <object> into <target>` (D41 Dynamic Key Access)
7. `get <url> into <target>` (HTTP GET)

#### The Conflict:
```otter
get customers from customers into customers
```
If `customers` is an in-memory dictionary or object, D41 interprets this as: "Read property `customers` from object `customers` and assign to `customers`"!
Furthermore, if a program has multiple databases open, how does the engine know which database to query?

#### Resolution: Explicit Source Connection via `in <connection>`
To maintain 100% determinism, prevent D41 collision, and handle multiple open connections without ambient state:
```otter
get customers from customers in db
where state is "Arizona"
into customers
```
Look at how naturally this reads:
> **"Get customers from customers in db where state is "Arizona" into customers."**

This preserves:
1. Complete alignment with D98: `get columns from "tasks" in db into cols`.
2. Complete alignment with Otter loops: `each customer in customers`.
3. Complete disambiguation from D41: `get <key> from <object> into <target>` has NO `in <connection>` clause!
4. Explicit, zero-guess connection targeting.

*(Note: In Section 4, we also explore a block-level `in db:` or ambient connection alternative for single-database scripts, but `from <table> in <db>` is the canonical unambiguous foundation).*

---

## 3. Deep Dive: Question #1 — Column vs. Variable Resolution

This is the central architectural question identified by Jeff:
> *"How does Otter distinguish a column name from an Otter variable?"*
>
> Consider:
> ```otter
> state is "Arizona"
>
> get customers from customers in db
> where state is state
> into customers
> ```
> Does `where state is state` mean `column == column` or `column == variable`?

### 3.1 The Problem in Depth
In SQL, host variables have distinct lexical syntax (`@state`, `:state`, `$1`, or `?`), while column identifiers are bare or quoted (`state`, `"state"`).
In Otter, variables are bare identifiers (`state is "Arizona"`).
If columns are also bare identifiers, four interpretations exist for `where A is B`:
1. `Column(A) == Variable(B)`
2. `Column(A) == Column(B)` (valid SQL: comparing two columns in the same row)
3. `Variable(A) == Column(B)`
4. `Variable(A) == Variable(B)` (pure host expression)

Moreover, if resolution depended on dynamic runtime environment lookup ("if variable exists in `$Environment`, treat as variable, else column"):
- A query `where state is billing_state` (meaning column `state == column billing_state`) would silently break if a developer later added a local variable `billing_state` outside the query!
- **Silent semantic mutation across scopes violates Otter's core philosophy.**

### 3.2 The Proposed Solution: The Alias & Property Rule

Otter already possesses the exact grammatical construct required to disambiguate this:
**Property access via `of` (D4).**

When an alias is assigned to a table source:
```otter
from customers in db as customer
```
Then:
1. **Any `<identifier> of <alias>` is deterministically a COLUMN.**
2. **Any bare `<identifier>` matching an in-scope Otter variable is an OTTER VARIABLE (parameterized value).**
3. **Any literal (`"Arizona"`, `50`, `true`, `gone`) is a VALUE.**

#### Example: Column vs Variable
```otter
state is "Arizona"

get customers from customers in db as customer
where state of customer is state
into customers
```
- `state of customer`: Unambiguously the database column `customer.state`.
- `state`: Unambiguously the local Otter variable `state` (`@p1 = "Arizona"`).
- Reading aloud: *"Where state of customer is state."* Perfectly natural English!

#### Example: Column vs Column Comparison
```otter
get orders from orders in db as order
where billing state of order is shipping state of order
into orders
```
- `billing state of order`: Column 1.
- `shipping state of order`: Column 2.
- Compiled SQL: `WHERE o.billing_state = o.shipping_state`.

#### Example: Single-Table Unaliased Shorthand (The Left-Column Rule)
What about simple queries without explicit aliases?
```otter
get customers from customers in db
where state is "Arizona"
into customers
```
When no alias is declared and the expression on the right is a **Literal** (`"Arizona"`, `42`, `false`, `gone`), there is zero ambiguity:
- Left side of comparison = Database Column.
- Right side of comparison = Literal Value.

What if the right side is an Otter variable?
```otter
requestedState is "Arizona"

get customers from customers in db
where state is requestedState
into customers
```
**Strict Deterministic Rule for Unaliased Queries:**
- In an unaliased query (`from <table> in <db>` without `as`), the **left operand** of a binary comparison is always resolved as a **column name** of the primary table.
- The **right operand** is evaluated in the Otter environment:
  - If it matches an Otter variable or expression, its runtime value is bound as a parameter (`@p1`).
  - If the programmer wants to compare two columns in an unaliased table, they MUST use the column qualification syntax or an alias:
    `where billing_state of customers is shipping_state of customers`
  - If a variable name shadows the column name (`state is state`), the compiler issues an **Otter Ambiguity Diagnostic**:
    ```
    Otter Ambiguity Error at Line 4:
        where state is state
    
    Both the database table "customers" and your Otter program have a variable named "state".
    To compare the column against your variable, declare an alias:
        from customers in db as customer
        where state of customer is state
    ```

This completely eliminates guessing, gives helpful compiler guidance, and guarantees 100% safety.

---

## 4. Analysis of Design Fixtures (A through H)

Let's evaluate each of the 8 design fixtures against the proposed grammar.

### Fixture A — Simple Retrieval
```otter
get customers from customers in db
into customers
```
- **AST Shape:**
  ```
  QueryStmt
    Source: TableSource("customers", Connection: "db", Alias: null)
    Projection: AllColumns
    Filter: null
    Target: "customers"
  ```
- **Generated SQL:** `SELECT * FROM customers;`
- **Result:** List of `database row` objects.

---

### Fixture B — Filtering
```otter
get customers from customers in db
where state is "Arizona"
into customers
```
- **AST Shape:**
  ```
  QueryStmt
    Source: TableSource("customers", Connection: "db")
    Projection: AllColumns
    Filter: BinaryCompare(
      Left: ColumnExpr("state"),
      Op: Equal,
      Right: LiteralExpr("Arizona")
    )
    Target: "customers"
  ```
- **Generated SQL:** `SELECT * FROM customers WHERE state = @p1;`
- **Parameter Map:** `@p1` = `"Arizona"`

With Otter comparisons:
```otter
get products from products in db
where price is less than 50
into products

get tasks from tasks in db
where completed is false
into tasks

get users from users in db
where email is gone
into users
```
- `price is less than 50` -> `WHERE price < @p1` (`@p1 = 50`)
- `completed is false` -> `WHERE completed = @p1` (provider formats boolean for SQLite `0` or Postgres `FALSE`)
- `email is gone` -> `WHERE email IS NULL` (no parameter needed, maps Otter `gone` to SQL `IS NULL`)

---

### Fixture C — Projection
Single-line projection:
```otter
get name and email from customers in db
where state is "Arizona"
into customers
```
Multi-line projection:
```otter
get
    name
    email
    phone
    state
from customers in db
where active is true
into customers
```
- **Grammar Rule:**
  - If `get` is followed immediately by a newline and indent, it parses an indented list of column expressions until `from`.
  - If `get` is followed by identifiers separated by `and`, it parses a single-line projection list until `from`.
  - If `get` is followed by `<target>` and immediately `from <target>`, it is full-row selection (`SELECT *`).
- **Generated SQL:** `SELECT name, email, phone, state FROM customers WHERE active = @p1;`

---

### Fixture D — Ordering
Ascending:
```otter
get customers from customers in db
where active is true
order by name
into customers
```
Descending:
```otter
get customers from customers in db
where active is true
order by created descending
into customers
```
Multi-column ordering:
```otter
get customers from customers in db
order by
    state
    name descending
into customers
```
- **Lexer Token:** `order by` is emitted as a single token `[TokenKind]::OrderBy`.
- **Direction Modifiers:** `descending` (`DESC`), `ascending` (`ASC`, default).
- **Generated SQL:** `ORDER BY state ASC, name DESC`

---

### Fixture E — Aggregates
```otter
get count of customers from customers in db
where active is true
into customerCount

get average of price from products in db
into averagePrice
```
- **Aggregate Vocabulary:**
  - `count of <target>` -> `COUNT(...)`
  - `sum of <field>` -> `SUM(...)`
  - `average of <field>` -> `AVG(...)`
  - `minimum of <field>` -> `MIN(...)`
  - `maximum of <field>` -> `MAX(...)`
- **Result Unwrapping:** When an aggregate query projects a single scalar without grouping, `into <target>` receives the scalar value directly (e.g. `42` or `9.99`), rather than a 1-row, 1-column list of objects.

---

### Fixture F — Grouping & Aliases
```otter
get
    state
    count of customers as customer count
from customers in db

group by state

into states
```
- **Grammar Rule:**
  - `as <name>` assigns a property name to the resulting column in the row object.
  - `group by <expr>` defines the grouping expressions.
- **Generated SQL:**
  ```sql
  SELECT state, COUNT(*) AS customer_count
  FROM customers
  GROUP BY state;
  ```
- **Result Row Shape:** `database row` objects with properties `state` and `customer count`.

---

### Fixture G — Relationships / Joins
```otter
get
    name of customer
    number of order
from customers in db as customer

include orders as order
where customer id of order is id of customer

into orders
```
- **Concept:**
  - `include <table> as <alias>` specifies an inner join.
  - `where ...` specifies the join predicate (`ON o.customer_id = c.id`).
- **Generated SQL:**
  ```sql
  SELECT customer.name, order.number
  FROM customers AS customer
  INNER JOIN orders AS order
      ON order.customer_id = customer.id;
  ```

---

### Fixture H — Full Complex Fixture (The Benchmark)
```otter
get
    name of department
    count of employees as employee count
from departments in db as department

include employees as employee
    where department id of employee is id of department
    and active of employee is true
    even when none

group by name of department

keep groups where employee count is at least 5

order by employee count descending

into departments
```

#### Detailed Breakdown:
1. **Source:** `departments in db as department` -> `FROM departments AS department`
2. **Outer Join:** `include employees as employee ... even when none` ->
   `LEFT OUTER JOIN employees AS employee ON employee.department_id = department.id AND employee.active = @p1`
   - `even when none` captures the intent: "keep the department even when there are no employees".
3. **Projection:** `name of department, count of employees as employee count` ->
   `SELECT department.name, COUNT(employee.id) AS employee_count`
4. **Grouping:** `group by name of department` -> `GROUP BY department.name`
5. **Group Filter:** `keep groups where employee count is at least 5` ->
   `HAVING COUNT(employee.id) >= @p2` (`@p2 = 5`)
   - Replaces cryptic SQL `HAVING` with clear English intention: `keep groups where`.
6. **Ordering:** `order by employee count descending` -> `ORDER BY employee_count DESC`
7. **Target:** `into departments` receives the resulting list of department summary objects.

---

## 5. Query AST Specification

Otter queries are NEVER compiled directly into raw SQL strings by the parser.
Instead, they produce a structured, provider-independent AST.

```
QueryStmt (Node)
  ├── Connection: Expr
  ├── PrimarySource: QuerySourceNode
  │     ├── TableName: string
  │     └── Alias: string?
  ├── Projections: List<QueryProjectionNode>
  │     ├── Field: Expr / AggregateExpr
  │     └── Alias: string?
  ├── Joins: List<QueryJoinNode>
  │     ├── TableName: string
  │     ├── Alias: string
  │     ├── JoinType: Inner | LeftOuter ("even when none")
  │     └── Predicate: ConditionNode
  ├── Filter: ConditionNode? (WHERE)
  ├── GroupBy: List<Expr>?
  ├── GroupFilter: ConditionNode? (HAVING)
  ├── OrderBy: List<QueryOrderNode>?
  │     ├── Field: Expr
  │     └── Direction: Ascending | Descending
  ├── Limit: Expr?
  ├── Offset: Expr?
  └── TargetVariable: string
```

### Compiler Pipeline:
```
Otter Source
     ↓  (ConvertTo-OtterTokens)
Tokens
     ↓  (ConvertTo-OtterAst)
QueryStmt AST
     ↓
Query Plan Validator (Validates identifiers, types, schemas via D98 metadata if available)
     ↓
Database Provider Translation (OtterDatabaseProvider.CompileQuery(ast))
     ↓
Native Parameterized Query + Parameters (@p1, @p2...)
     ↓
Execute Native Driver (winsqlite3 / Npgsql / SqlClient)
     ↓
List<OtterObject> ("database row")
     ↓
Bound to Target Variable in Environment
```

---

## 6. Detailed Resolution of the 27 Open Design Questions

| # | Question | Proposed Architectural Decision |
|---|---|---|
| **1** | Column vs Variable resolution | Fully resolved in Section 3: Aliases (`prop of alias`) denote columns; bare variables matching program scope are parameterized values; literals are values. |
| **2** | Is `get customers from customers` repetitive? | Yes, which is why `from <table> in <db>` is preferred. For all columns, `get all from customers in db into customers` or `get customers from customers in db into customers` are both supported. |
| **3** | What does `get customers` mean vs `get name and email`? | `get customers` (or `get all`) projects the entire row record (`SELECT *`). Naming specific fields projects only those fields. |
| **4** | Should source aliases be optional? | Optional for simple single-table queries; required when joins or self-referential column/variable names exist. |
| **5** | Should `include` represent joins? | Yes. `include <table as alias> where <predicate>` reads cleanly aloud and avoids database jargon. |
| **6** | Is `even when none` the clearest outer-join syntax? | Yes. It explains the semantics without requiring knowledge of relational algebra ("left vs right outer"). |
| **7** | Should group filtering use `keep groups where`? | Yes. It replaces `HAVING` with an English description of what the clause does. |
| **8** | What portable aggregate operations exist? | `count of`, `sum of`, `average of`, `minimum of`, `maximum of`. |
| **9** | Ambiguous column names across multiple sources? | Mandatory alias qualification (`name of customer` vs `name of employee`). Compiler throws an error if an unaliased column exists in multiple joined sources. |
| **10**| Schema-qualified tables? | `from "auth.users" in db` or `from users in schema "auth" of db`. String literal table name allows any schema formatting. |
| **11**| Table/column identifiers vs values? | Identifiers are unquoted names or `name of alias`; string values are quoted `"literal"`. |
| **12**| Parameter binding mechanism? | Universal: every literal/variable in filter expressions is converted to a provider parameter placeholder (`@p1`). Never raw string concatenated. |
| **13**| Database-specific functions? | Kept in the raw SQL escape hatch (`query db with "..."`). OQL only supports universal portable operations. |
| **14**| Unsupported provider capabilities? | If a provider does not support grouping or outer joins, calling an unsupported AST feature raises an `OtterError` naming the provider and the missing capability. |
| **15**| Compiler vs Provider query generation? | The compiler produces the `QueryStmt` AST. The active `OtterDatabaseProvider` translates that AST into engine-specific SQL text and parameter maps. |
| **16**| Static vs Runtime validation? | Syntax is validated at parse time. Column and table existence can be validated statically if D98 introspection is run ahead-of-time, or checked at query compilation time. |
| **17**| Utilizing D98 Schema Introspection? | Providers can use their `GetColumns()` cache to validate column names and report typo suggestions (e.g. `Did you mean "email_address"?`). |
| **18**| Aliases in resulting row objects? | `as <name>` sets the exact property name on the resulting `database row` object. |
| **19**| Semantics of `count of employees` in outer joins? | `count of employees` maps to `COUNT(employee.id)`, returning 0 for unmatched rows, matching SQL behavior. |
| **20**| SQL NULL vs Otter `gone`? | `where col is gone` -> `col IS NULL`. `where col is not gone` -> `col IS NOT NULL`. Query results with NULL columns read as `gone` in Otter. |
| **21**| Multi-column ordering? | Supported via indented block under `order by` or `and` separation: `order by state and name descending`. |
| **22**| Limiting and pagination? | `first <n>` (`LIMIT n`) and `skip <n>` (`OFFSET n`). Clean, English words already familiar in Otter list processing. |
| **23**| AST pipeline architecture? | Described in Section 5. Clean separation between language parser, AST, and database providers. |
| **24**| Compatibility with existing lexer/parser? | Zero regressions. Preserves D41 dynamic keys, HTTP get, loops, and conditions. |
| **25**| JS Web Compiler implications? | The exact same `QueryStmt` AST can be translated by `Otter.Web.psm1` into JavaScript `Array.prototype.filter`, `map`, `sort`, or IndexedDB queries! |
| **26**| Mutation syntax (future)? | Out of scope for D99 initial query spec, but fits future `insert into <table>`, `update <table>`, `delete from <table>`. |
| **27**| Verification & Certification? | Evaluated by translating Fixtures A-H into valid, parameterized SQLite queries and executing against memory databases. |

---

## 7. Recommendation & Next Steps

1. **Keep D99 in Design Proposal Status:** Do not commit to parser or contract changes until Jeff reviews this design document and approves the resolution to Question #1 and the AST shape.
2. **Retain Raw SQL as the Foundation:** D97 and D98 remain the production foundation for Otter 1.1.
3. **Prototype in Isolation:** When approved, implement Level 1 (Fixtures A, B, C, D) in a dedicated experimental test branch before expanding to joins and grouping.
