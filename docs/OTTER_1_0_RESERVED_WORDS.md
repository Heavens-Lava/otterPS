# Otter 1.0 reserved words

Decision **D-2** (Otter 1.0, RC3): *if Otter accepts an identifier
declaration, that identifier must be usable according to its declared role.*

Otter reads some ordinary-looking words as grammar depending on where they
appear. A line that starts with `main` is a UI element; `x is completed` is a
check of an HTTP request's state; `zip ...` is the zip statement. Before 1.0,
Otter still let you *declare* a function or variable with such a name, and then
silently misread every use of it:

```otter
to main
    say "hello from main"
main                      # RC2: prints nothing, exit 0
```

From 1.0, `otter check`, `otter run` and `otter test` reject those declarations
before anything runs:

```text
Otter Syntax Error

Line 1:
    to main
       ^

`main` is a reserved word in Otter: a line starting with `main` is read as a UI
element (D56 declarative UI), which does nothing when the program runs in the
console, so a function named `main` could never be called. Choose a different
name, for example `mainTask`.
```

The set is deliberately **as small as the parser requires**. Ordinary English
names - `name`, `total`, `status`, `score`, `message`, `items`, `result`,
`user`, `value`, `title`, `counter`, `data`, `key`, `label`, `done`, `ready` -
are not reserved and work as variables, parameters and function names in every
role.

## The rules

A **function name** (`to NAME`) is reserved when a line starting with `NAME`
(with or without arguments) is read as some other statement, so the call can
never reach the function.

A **variable or parameter name** is reserved only when an ordinary use of the
variable is accepted by the parser with a different meaning - silent
misbehaviour. That is exactly the *state words* on the right of `is` in a
condition (`if status is completed` is a state check, not a comparison with a
variable named `completed`).

Every declaration form is checked: `name is ...`, `to f name`, `for each name
in`, `count from 1 to 3 as name`, `into name`, `make name`, `and call it name`,
`ask ... and call it name`, `name are ...`, `name has`, `otherwise into name`,
and the D56 `state`/`derive`/`memo`/`shared` forms. Matching ignores case,
because the parser's own word checks ignore case (`Main`, `SEND` and
`Completed` are read exactly like `main`, `send` and `completed`).

## Where it is enforced

`src/Otter.Validation.psm1` walks the parsed program (the parser itself is
unchanged) and reports every conflicting declaration with the word, the line,
the reason and a suggested rename (diagnostic code `ReservedWord`, exit code 2
like any other check error). It is called right after parsing by the CLI entry
point, so `otter check`, `otter run`, `otter test` (which runs each test file
through `otter run`) and `otter serve` all reject the program before execution.

`tests/LanguageContract.Tests.ps1` re-proves every word below against the
current parser. If a later parser change stops hijacking a word, that test
fails and the word must be removed from this list.

## Canonical list

Derived from the parser (statement dispatch on the first word of a line, the
lexer's statement-head keyword table, and the state words in condition
parsing), each entry proven with a program on RC2 (`19bc37b`).

| Word | Role | Category | Why it conflicts | Example of the conflict (RC2 / 19bc37b) |
|---|---|---|---|---|
| `now` | function | built-in value (function) | `now` is a built-in value, so a function named `now` could never be called | `to now p` … `now 5` → syntax error: "I don't understand 'now'." |
| `pi` | function | built-in value (function) | `pi` is a built-in value, so a function named `pi` could never be called | `to pi p` … `pi 5` → syntax error: "'pi' is a built-in value, not a variable name." |
| `today` | function | built-in value (function) | `today` is a built-in value, so a function named `today` could never be called | `to today p` … `today 5` → syntax error: "I don't understand 'today'." |
| `animate` | function | grammar keyword (function) | `animate` is part of Otter's own grammar and a line cannot start with it, so a function named `animate` could never be called | `to animate p` … `animate 5` → syntax error: "I don't understand 'animate'." |
| `ascending` | function | grammar keyword (function) | `ascending` is part of Otter's own grammar and a line cannot start with it, so a function named `ascending` could never be called | `to ascending p` … `ascending 5` → syntax error: "I don't understand 'ascending'." |
| `between` | function | grammar keyword (function) | `between` is part of Otter's own grammar and a line cannot start with it, so a function named `between` could never be called | `to between p` … `between 5` → syntax error: "I don't understand 'between'." |
| `descending` | function | grammar keyword (function) | `descending` is part of Otter's own grammar and a line cannot start with it, so a function named `descending` could never be called | `to descending p` … `descending 5` → syntax error: "I don't understand 'descending'." |
| `distinct` | function | grammar keyword (function) | `distinct` is part of Otter's own grammar and a line cannot start with it, so a function named `distinct` could never be called | `to distinct p` … `distinct 5` → syntax error: "I don't understand 'distinct'." |
| `file` | function | grammar keyword (function) | `file` is part of Otter's own grammar and a line cannot start with it, so a function named `file` could never be called | `to file p` … `file 5` → syntax error: "I don't understand 'file'." |
| `files` | function | grammar keyword (function) | `files` is part of Otter's own grammar and a line cannot start with it, so a function named `files` could never be called | `to files p` … `files 5` → syntax error: "I don't understand 'files'." |
| `folder` | function | grammar keyword (function) | `folder` is part of Otter's own grammar and a line cannot start with it, so a function named `folder` could never be called | `to folder p` … `folder 5` → syntax error: "I don't understand 'folder'." |
| `folders` | function | grammar keyword (function) | `folders` is part of Otter's own grammar and a line cannot start with it, so a function named `folders` could never be called | `to folders p` … `folders 5` → syntax error: "I don't understand 'folders'." |
| `gap` | function | grammar keyword (function) | `gap` is part of Otter's own grammar and a line cannot start with it, so a function named `gap` could never be called | `to gap p` … `gap 5` → syntax error: "I don't understand 'gap'." |
| `has` | function | grammar keyword (function) | `has` is part of Otter's own grammar and a line cannot start with it, so a function named `has` could never be called | `to has p` … `has 5` → syntax error: "I don't understand 'has'." |
| `json` | function | grammar keyword (function) | `json` is part of Otter's own grammar and a line cannot start with it, so a function named `json` could never be called | `to json p` … `json 5` → syntax error: "I don't understand 'json'." |
| `motion` | function | grammar keyword (function) | `motion` is part of Otter's own grammar and a line cannot start with it, so a function named `motion` could never be called | `to motion p` … `motion 5` → syntax error: "I don't understand 'motion'." |
| `otherwise` | function | grammar keyword (function) | `otherwise` is part of Otter's own grammar and a line cannot start with it, so a function named `otherwise` could never be called | `to otherwise p` … `otherwise 5` → syntax error: "I don't understand 'otherwise'." |
| `parameter` | function | grammar keyword (function) | `parameter` is part of Otter's own grammar and a line cannot start with it, so a function named `parameter` could never be called | `to parameter p` … `parameter 5` → syntax error: "I don't understand 'parameter'." |
| `then` | function | grammar keyword (function) | `then` is part of Otter's own grammar and a line cannot start with it, so a function named `then` could never be called | `to then p` … `then 5` → syntax error: "I don't understand 'then'." |
| `append` | function | statement word (function) | a line starting with `append` is read as the `append` statement, so a function named `append` could never be called | `to append p` … `append 5` → syntax error: "I expected "to" and a file path. I found '' instead."; bare `append` → syntax error: "I expected a value here." |
| `average` | function | statement word (function) | a line starting with `average` is read as the `average` statement, so a function named `average` could never be called | `to average p` … `average 5` → syntax error: "I expected "from" and table name after aggregate expression. I found end of file instead."; bare `average` → syntax error: "I expected a value here." |
| `cancel` | function | statement word (function) | a line starting with `cancel` is read as the `cancel` statement, so a function named `cancel` could never be called | `to cancel p` … `cancel 5` → read as an HTTP `cancel` statement; bare `cancel` → syntax error: "I expected a value here." |
| `choose` | function | statement word (function) | a line starting with `choose` is read as the `choose` statement, so a function named `choose` could never be called | `to choose p` … `choose 5` → syntax error: "I expected "file" or "folder" after "choose". I found '5' instead."; bare `choose` → syntax error: "I expected "file" or "folder" after "choose". I found '' instead." |
| `commit` | function | statement word (function) | a line starting with `commit` is read as the `commit` statement, so a function named `commit` could never be called | `to commit p` … `commit 5` → read as a database `commit`; bare `commit` → syntax error: "I expected a value here." |
| `connect` | function | statement word (function) | a line starting with `connect` is read as the `connect` statement, so a function named `connect` could never be called | `to connect p` … `connect 5` → syntax error: "I expected "into" and a variable name after the database configuration. I found '' instead."; bare `connect` → syntax error: "I expected a value here." |
| `convert` | function | statement word (function) | a line starting with `convert` is read as the `convert` statement, so a function named `convert` could never be called | `to convert p` … `convert 5` → syntax error: "I expected "to json/csv" or "from json/csv" here. I found '' instead."; bare `convert` → syntax error: "I expected a value here." |
| `copy` | function | statement word (function) | a line starting with `copy` is read as the `copy` statement, so a function named `copy` could never be called | `to copy p` … `copy 5` → syntax error: "I expected "to" and a destination path. I found '' instead."; bare `copy` → syntax error: "I expected a value here." |
| `count` | function | statement word (function) | a line starting with `count` is read as the `count` statement, so a function named `count` could never be called | `to count p` … `count 5` → syntax error: "I expected "from" and table name after aggregate expression. I found end of file instead."; bare `count` → syntax error: "I expected a value here." |
| `create` | function | statement word (function) | a line starting with `create` is read as the `create` statement, so a function named `create` could never be called | `to create p` … `create 5` → syntax error: "I expected "into" after the resource type." |
| `decrease` | function | statement word (function) | a line starting with `decrease` is read as the `decrease` statement, so a function named `decrease` could never be called | `to decrease p` … `decrease 5` → syntax error: "I expected a variable name after "decrease"." |
| `decrypt` | function | statement word (function) | a line starting with `decrypt` is read as the `decrypt` statement, so a function named `decrypt` could never be called | `to decrypt p` … `decrypt 5` → syntax error: "I expected "with key" and a key. I found '' instead."; bare `decrypt` → syntax error: "I expected a value here." |
| `delete` | function | statement word (function) | a line starting with `delete` is read as the `delete` statement, so a function named `delete` could never be called | `to delete p` … `delete 5` → syntax error: "I expected "file" after delete. I found '5' instead."; bare `delete` → syntax error: "I expected "file" after delete. I found '' instead." |
| `derive` | function | statement word (function) | a line starting with `derive` is read as the `derive` statement, so a function named `derive` could never be called | `to derive p` … `derive 5` → syntax error: "I expected a variable name after "derive"." |
| `disconnect` | function | statement word (function) | a line starting with `disconnect` is read as the `disconnect` statement, so a function named `disconnect` could never be called | `to disconnect p` … `disconnect 5` → read as a database `disconnect`; bare `disconnect` → syntax error: "I expected a value here." |
| `download` | function | statement word (function) | a line starting with `download` is read as the `download` statement, so a function named `download` could never be called | `to download p` … `download 5` → syntax error: "I expected "file" after "download". I found '5' instead."; bare `download` → syntax error: "I expected "file" after "download". I found '' instead." |
| `each` | function | statement word (function) | a line starting with `each` is read as the `each` statement, so a function named `each` could never be called | `to each p` … `each 5` → syntax error: "I expected a loop variable after "for each"." |
| `encrypt` | function | statement word (function) | a line starting with `encrypt` is read as the `encrypt` statement, so a function named `encrypt` could never be called | `to encrypt p` … `encrypt 5` → syntax error: "I expected "with key" and a key. I found '' instead."; bare `encrypt` → syntax error: "I expected a value here." |
| `error` | function | statement word (function) | a line starting with `error` is read as the `error` statement, so a function named `error` could never be called | `to error p` … `error 5` → read as a diagnostic line (`log:`/`warn:`/`error:`), not the call |
| `execute` | function | statement word (function) | a line starting with `execute` is read as the `execute` statement, so a function named `execute` could never be called | `to execute p` … `execute 5` → syntax error: "I expected "with" after the database connection. I found '' instead."; bare `execute` → syntax error: "I expected a value here." |
| `fail` | function | statement word (function) | a line starting with `fail` is read as the `fail` statement, so a function named `fail` could never be called | `to fail p` … `fail 5` → syntax error: "I expected "with" and a message. I found '5' instead."; bare `fail` → syntax error: "I expected "with" and a message. I found '' instead." |
| `find` | function | statement word (function) | a line starting with `find` is read as the `find` statement, so a function named `find` could never be called | `to find p` … `find 5` → syntax error: "I expected an item name after "find"." |
| `focus` | function | statement word (function) | a line starting with `focus` is read as the `focus` statement, so a function named `focus` could never be called | `to focus p` … `focus 5` → read as a UI `focus`/`hide` action; bare `focus` → syntax error: "I expected a value here." |
| `format` | function | statement word (function) | a line starting with `format` is read as the `format` statement, so a function named `format` could never be called | `to format p` … `format 5` → syntax error: "I expected "as" and a date format. I found '' instead."; bare `format` → syntax error: "I expected a value here." |
| `get` | function | statement word (function) | a line starting with `get` is read as the `get` statement, so a function named `get` could never be called | `to get p` … `get 5` → syntax error: "I expected "from" or "into" after the value. I found '' instead."; bare `get` → syntax error: "I expected a value here." |
| `hash` | function | statement word (function) | a line starting with `hash` is read as the `hash` statement, so a function named `hash` could never be called | `to hash p` … `hash 5` → syntax error: "I expected "as" and an algorithm name. I found '' instead."; bare `hash` → syntax error: "I expected a value here." |
| `hide` | function | statement word (function) | a line starting with `hide` is read as the `hide` statement, so a function named `hide` could never be called | `to hide p` … `hide 5` → read as a UI `focus`/`hide` action; bare `hide` → syntax error: "I expected a value here." |
| `increase` | function | statement word (function) | a line starting with `increase` is read as the `increase` statement, so a function named `increase` could never be called | `to increase p` … `increase 5` → syntax error: "I expected a variable name after "increase"." |
| `join` | function | statement word (function) | a line starting with `join` is read as the `join` statement, so a function named `join` could never be called | `to join p` … `join 5` → syntax error: "I expected "with" and a separator. I found '' instead."; bare `join` → syntax error: "I expected a value here." |
| `kill` | function | statement word (function) | a line starting with `kill` is read as the `kill` statement, so a function named `kill` could never be called | `to kill p` … `kill 5` → syntax error: "I expected "process" after "kill"." |
| `layout` | function | statement word (function) | a line starting with `layout` is read as the `layout` statement, so a function named `layout` could never be called | `to layout p` … `layout 5` → read as a UI element (D56): nothing runs, nothing is printed; bare `layout` → syntax error: "I expected the layout statement to end here. I found end of file instead." |
| `listen` | function | statement word (function) | a line starting with `listen` is read as the `listen` statement, so a function named `listen` could never be called | `to listen p` … `listen 5` → syntax error: "I expected "on port <number>" or a server name after "listen"." |
| `lock` | function | statement word (function) | a line starting with `lock` is read as the `lock` statement, so a function named `lock` could never be called | `to lock p` … `lock 5` → syntax error: "I expected "the computer" after "lock"." |
| `log` | function | statement word (function) | a line starting with `log` is read as the `log` statement, so a function named `log` could never be called | `to log p` … `log 5` → read as a diagnostic line (`log:`/`warn:`/`error:`), not the call |
| `maximum` | function | statement word (function) | a line starting with `maximum` is read as the `maximum` statement, so a function named `maximum` could never be called | `to maximum p` … `maximum 5` → syntax error: "I expected "from" and table name after aggregate expression. I found end of file instead."; bare `maximum` → syntax error: "I expected a value here." |
| `memo` | function | statement word (function) | a line starting with `memo` is read as the `memo` statement, so a function named `memo` could never be called | `to memo p` … `memo 5` → syntax error: "I expected a memo name after "memo"." |
| `minimum` | function | statement word (function) | a line starting with `minimum` is read as the `minimum` statement, so a function named `minimum` could never be called | `to minimum p` … `minimum 5` → syntax error: "I expected "from" and table name after aggregate expression. I found end of file instead."; bare `minimum` → syntax error: "I expected a value here." |
| `move` | function | statement word (function) | a line starting with `move` is read as the `move` statement, so a function named `move` could never be called | `to move p` … `move 5` → syntax error: "I expected "to" and a destination path. I found '' instead."; bare `move` → syntax error: "I expected a value here." |
| `notify` | function | statement word (function) | a line starting with `notify` is read as the `notify` statement, so a function named `notify` could never be called | `to notify p` … `notify 5` → syntax error: "I expected "with" and a message. I found '' instead."; bare `notify` → syntax error: "I expected a value here." |
| `on` | function | statement word (function) | a line starting with `on` is read as the `on` statement, so a function named `on` could never be called | `to on p` … `on 5` → syntax error: "I expected 'start' or 'close' after 'on', but got '5'."; bare `on` → syntax error: "I expected 'start' or 'close' after 'on', but got ''." |
| `post` | function | statement word (function) | a line starting with `post` is read as the `post` statement, so a function named `post` could never be called | `to post p` … `post 5` → syntax error: "I expected "to" and a URL after post data. I found '' instead."; bare `post` → syntax error: "I expected a value here." |
| `print` | function | statement word (function) | a line starting with `print` is read as the `print` statement, so a function named `print` could never be called | `to print p` … `print 5` → syntax error: "I expected "to" and a printer name. I found '' instead."; bare `print` → syntax error: "I expected a value here." |
| `query` | function | statement word (function) | a line starting with `query` is read as the `query` statement, so a function named `query` could never be called | `to query p` … `query 5` → syntax error: "I expected "with" after the database connection. I found '' instead."; bare `query` → syntax error: "I expected a value here." |
| `random` | function | statement word (function) | a line starting with `random` is read as the `random` statement, so a function named `random` could never be called | `to random p` … `random 5` → syntax error: "I expected "number" or "item" after "random"." |
| `read` | function | statement word (function) | a line starting with `read` is read as the `read` statement, so a function named `read` could never be called | `to read p` … `read 5` → syntax error: "I expected "into" and a variable name. I found '' instead."; bare `read` → syntax error: "I expected a value here." |
| `replace` | function | statement word (function) | a line starting with `replace` is read as the `replace` statement, so a function named `replace` could never be called | `to replace p` … `replace 5` → syntax error: "I expected "with" and replacement text. I found '' instead."; bare `replace` → syntax error: "I expected a value here." |
| `respond` | function | statement word (function) | a line starting with `respond` is read as the `respond` statement, so a function named `respond` could never be called | `to respond p` … `respond 5` → syntax error: "I expected "with" after "respond". I found '5' instead."; bare `respond` → syntax error: "I expected "with" after "respond". I found '' instead." |
| `restart` | function | statement word (function) | a line starting with `restart` is read as the `restart` statement, so a function named `restart` could never be called | `to restart p` … `restart 5` → syntax error: "I expected "the computer" after "restart"." |
| `reverse` | function | statement word (function) | a line starting with `reverse` is read as the `reverse` statement, so a function named `reverse` could never be called | `to reverse p` … `reverse 5` → syntax error: "I expected a collection name after "reverse"." |
| `rollback` | function | statement word (function) | a line starting with `rollback` is read as the `rollback` statement, so a function named `rollback` could never be called | `to rollback p` … `rollback 5` → read as a database `rollback`; bare `rollback` → syntax error: "I expected a value here." |
| `route` | function | statement word (function) | a line starting with `route` is read as the `route` statement, so a function named `route` could never be called | `to route p` … `route 5` → syntax error: "I expected "shows" and a page after the route path."; bare `route` → syntax error: "I expected a value here." |
| `run` | function | statement word (function) | a line starting with `run` is read as the `run` statement, so a function named `run` could never be called | `to run p` … `run 5` → read as a `run` (start a program) statement; bare `run` → syntax error: "I expected a value here." |
| `send` | function | statement word (function) | a line starting with `send` is read as the `send` statement, so a function named `send` could never be called | `to send p` … `send 5` → syntax error: "I expected "through" and a websocket after the message."; bare `send` → syntax error: "I expected a value here." |
| `shared` | function | statement word (function) | a line starting with `shared` is read as the `shared` statement, so a function named `shared` could never be called | `to shared p` … `shared 5` → syntax error: "I expected a variable name after "shared"." |
| `shut` | function | statement word (function) | a line starting with `shut` is read as the `shut` statement, so a function named `shut` could never be called | `to shut p` … `shut 5` → syntax error: "I expected "down" after "shut"." |
| `sign` | function | statement word (function) | a line starting with `sign` is read as the `sign` statement, so a function named `sign` could never be called | `to sign p` … `sign 5` → syntax error: "I expected "out" after "sign"." |
| `sort` | function | statement word (function) | a line starting with `sort` is read as the `sort` statement, so a function named `sort` could never be called | `to sort p` … `sort 5` → syntax error: "I expected a collection name after "sort"." |
| `split` | function | statement word (function) | a line starting with `split` is read as the `split` statement, so a function named `split` could never be called | `to split p` … `split 5` → syntax error: "I expected "by" and a separator. I found '' instead."; bare `split` → syntax error: "I expected a value here." |
| `start` | function | statement word (function) | a line starting with `start` is read as the `start` statement, so a function named `start` could never be called | `to start p` … `start 5` → syntax error: "I expected a server name after "start"." |
| `state` | function | statement word (function) | a line starting with `state` is read as the `state` statement, so a function named `state` could never be called | `to state p` … `state 5` → syntax error: "I expected a variable name after "state"." |
| `stop` | function | statement word (function) | a line starting with `stop` is read as the `stop` statement, so a function named `stop` could never be called | `to stop p` … `stop 5` → syntax error: "I expected stop to end here. I found '5' instead."; bare `stop` → read as `stop` (return from the current function) |
| `sum` | function | statement word (function) | a line starting with `sum` is read as the `sum` statement, so a function named `sum` could never be called | `to sum p` … `sum 5` → syntax error: "I expected "from" and table name after aggregate expression. I found end of file instead."; bare `sum` → syntax error: "I expected a value here." |
| `try` | function | statement word (function) | a line starting with `try` is read as the `try` statement, so a function named `try` could never be called | `to try p` … `try 5` → syntax error: "I expected the statement to end here. I found '5' instead."; bare `try` → syntax error: "I expected an indented block after this statement. I found end of file instead." |
| `unzip` | function | statement word (function) | a line starting with `unzip` is read as the `unzip` statement, so a function named `unzip` could never be called | `to unzip p` … `unzip 5` → syntax error: "I expected "into" and a destination folder. I found '' instead."; bare `unzip` → syntax error: "I expected a value here." |
| `use` | function | statement word (function) | a line starting with `use` is read as the `use` statement, so a function named `use` could never be called | `to use p` … `use 5` → read as a `use` module import; bare `use` → syntax error: "I expected the use statement to end here. I found end of file instead." |
| `wait` | function | statement word (function) | a line starting with `wait` is read as the `wait` statement, so a function named `wait` could never be called | `to wait p` … `wait 5` → syntax error: "I expected a time unit (seconds, minutes, milliseconds, ...) after the wait duration."; bare `wait` → syntax error: "I expected a value here." |
| `warn` | function | statement word (function) | a line starting with `warn` is read as the `warn` statement, so a function named `warn` could never be called | `to warn p` … `warn 5` → read as a diagnostic line (`log:`/`warn:`/`error:`), not the call |
| `write` | function | statement word (function) | a line starting with `write` is read as the `write` statement, so a function named `write` could never be called | `to write p` … `write 5` → syntax error: "I expected "to" and a file path. I found '' instead."; bare `write` → syntax error: "I expected a value here." |
| `zip` | function | statement word (function) | a line starting with `zip` is read as the `zip` statement, so a function named `zip` could never be called | `to zip p` … `zip 5` → syntax error: "I expected "folder" after "zip". I found '5' instead."; bare `zip` → syntax error: "I expected "folder" after "zip". I found '' instead." |
| `button` | function | UI element word (function) | a line starting with `button` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `button` could never be called | `to button p` … `button 5` → read as a UI element (D56): nothing runs, nothing is printed |
| `card` | function | UI element word (function) | a line starting with `card` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `card` could never be called | `to card p` … `card 5` → read as a UI element (D56): nothing runs, nothing is printed |
| `grid` | function | UI element word (function) | a line starting with `grid` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `grid` could never be called | `to grid p` … `grid 5` → read as a UI element (D56): nothing runs, nothing is printed |
| `heading` | function | UI element word (function) | a line starting with `heading` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `heading` could never be called | `to heading p` … `heading 5` → read as a UI element (D56): nothing runs, nothing is printed |
| `image` | function | UI element word (function) | a line starting with `image` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `image` could never be called | `to image p` … `image 5` → read as a UI element (D56): nothing runs, nothing is printed |
| `input` | function | UI element word (function) | a line starting with `input` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `input` could never be called | `to input p` … `input 5` → read as a UI element (D56): nothing runs, nothing is printed |
| `link` | function | UI element word (function) | a line starting with `link` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `link` could never be called | `to link p` … `link 5` → read as a UI element (D56): nothing runs, nothing is printed |
| `main` | function | UI element word (function) | a line starting with `main` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `main` could never be called | `to main p` … `main 5` → read as a UI element (D56): nothing runs, nothing is printed |
| `page` | function | UI element word (function) | a line starting with `page` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `page` could never be called | `to page p` … `page 5` → read as a UI element (D56): nothing runs, nothing is printed |
| `panel` | function | UI element word (function) | a line starting with `panel` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `panel` could never be called | `to panel p` … `panel 5` → read as a UI element (D56): nothing runs, nothing is printed |
| `section` | function | UI element word (function) | a line starting with `section` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `section` could never be called | `to section p` … `section 5` → read as a UI element (D56): nothing runs, nothing is printed |
| `sidebar` | function | UI element word (function) | a line starting with `sidebar` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `sidebar` could never be called | `to sidebar p` … `sidebar 5` → read as a UI element (D56): nothing runs, nothing is printed |
| `text` | function | UI element word (function) | a line starting with `text` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `text` could never be called | `to text p` … `text 5` → read as a UI element (D56): nothing runs, nothing is printed |
| `window` | function | UI element word (function) | a line starting with `window` is read as a UI element (D56 declarative UI), which does nothing when the program runs in the console, so a function named `window` could never be called | `to window p` … `window 5` → read as a UI element (D56): nothing runs, nothing is printed |
| `cancelled` | variable | HTTP/job state word (variable) | in a condition, `x is cancelled` is read as a check of an HTTP request's or command job's state, not a comparison with a variable named `cancelled` | `cancelled is "x"` … `if v is cancelled` → runtime error: "I can only check the state of an HTTP request or command job, but got some text." |
| `completed` | variable | HTTP/job state word (variable) | in a condition, `x is completed` is read as a check of an HTTP request's or command job's state, not a comparison with a variable named `completed` | `completed is "x"` … `if v is completed` → runtime error: "I can only check the state of an HTTP request or command job, but got some text." |
| `failed` | variable | HTTP/job state word (variable) | in a condition, `x is failed` is read as a check of an HTTP request's or command job's state, not a comparison with a variable named `failed` | `failed is "x"` … `if v is failed` → runtime error: "I can only check the state of an HTTP request or command job, but got some text." |
| `pending` | variable | HTTP/job state word (variable) | in a condition, `x is pending` is read as a check of an HTTP request's or command job's state, not a comparison with a variable named `pending` | `pending is "x"` … `if v is pending` → runtime error: "I can only check the state of an HTTP request or command job, but got some text." |
| `running` | variable | HTTP/job state word (variable) | in a condition, `x is running` is read as a check of an HTTP request's or command job's state, not a comparison with a variable named `running` | `running is "x"` … `if v is running` → runtime error: "I can only check the state of an HTTP request or command job, but got some text." |
| `listening` | variable | TCP server state word (variable) | in a condition, `x is listening` is read as a check of a TCP server's state, not a comparison with a variable named `listening` | `listening is "x"` … `if v is listening` → runtime error: "I can only ask about the state of a tcp server, but this is some text." |
| `stopped` | variable | TCP server state word (variable) | in a condition, `x is stopped` is read as a check of a TCP server's state, not a comparison with a variable named `stopped` | `stopped is "x"` … `if v is stopped` → runtime error: "I can only ask about the state of a tcp server, but this is some text." |
| `closed` | variable | socket state word (variable) | in a condition, `x is closed` is read as a check of a websocket's, TCP connection's or UDP socket's state, not a comparison with a variable named `closed` | `closed is "x"` … `if v is closed` → runtime error: "I can only ask about the state of a websocket, tcp connection or udp socket, but this is some text." |
| `closing` | variable | socket state word (variable) | in a condition, `x is closing` is read as a check of a websocket's, TCP connection's or UDP socket's state, not a comparison with a variable named `closing` | `closing is "x"` … `if v is closing` → runtime error: "I can only ask about the state of a websocket, tcp connection or udp socket, but this is some text." |
| `connected` | variable | socket state word (variable) | in a condition, `x is connected` is read as a check of a websocket's, TCP connection's or UDP socket's state, not a comparison with a variable named `connected` | `connected is "x"` … `if v is connected` → runtime error: "I can only ask about the state of a websocket, tcp connection or udp socket, but this is some text." |
| `connecting` | variable | socket state word (variable) | in a condition, `x is connecting` is read as a check of a websocket's, TCP connection's or UDP socket's state, not a comparison with a variable named `connecting` | `connecting is "x"` … `if v is connecting` → runtime error: "I can only ask about the state of a websocket, tcp connection or udp socket, but this is some text." |
| `secure` | variable | TLS state word (variable) | in a condition, `x is secure` is read as a check of whether a TCP connection uses TLS, not a comparison with a variable named `secure` | `secure is "x"` … `if v is secure` → runtime error: "I can only ask whether a tcp connection is secure, but this is some text." |
| `watching` | variable | watcher state word (variable) | in a condition, `x is watching` is read as a check of whether a file watcher is running, not a comparison with a variable named `watching` | `watching is "x"` … `if v is watching` → runtime error: "I can only ask whether a file watcher is watching, but this is some text." |

Totals: 102 reserved function names and 13 reserved variable/parameter names
(the condition state words) - 115 entries.

D-2 supersedes the D33 statement that the statement-head words (`copy`,
`sort`, `log`, `start`, ...) are valid *function* names: they still parse
after `to`, but a function with such a name could never be called, so the
validator now rejects the declaration. (`tests/Keywords.Tests.ps1` is
parse-only and is unchanged; it still passes.)

## Not reserved: reassignment fails loudly at parse time

These statement words are **not** reserved as variable or parameter names:

`animate`, `decrease`, `decrypt`, `derive`, `encrypt`, `fail`, `focus`, `gap`,
`hash`, `hide`, `increase`, `kill`, `layout`, `listen`, `lock`, `memo`,
`motion`, `on`, `post`, `print`, `respond`, `restart`, `shared`, `shut`,
`sign`, `start`, `state`, `stop`, `unzip`, `use`, `wait`, `zip`.

A parameter, loop variable or `into` target with one of these names reads
correctly in every value position - `say start`, `start plus 1`,
`if start is 3`, `3 is start`, `twice start`, `return start` - so it is usable
in its declared role:

```otter
to range start finish
    say start "to" finish     # works
```

Only reassigning it at the start of a line (`start is start plus 1`) fails,
and that is a syntax error reported by `otter check`, never a silent
misreading. (Their *function* names are still reserved: a function called
`start` could never be called.)

## Words that are already keywords everywhere

These can never be declared at all - the parser rejects the declaration
itself, so they need no entry above: `a`, `and`, `are`, `as`, `ask`, `at`,
`await`, `by`, `command`, `false`, `from`, `gone`, `if`, `in`, `into`, `is`,
`make`, `makes`, `minus`, `not`, `of`, `open`, `or`, `percent`, `plus`,
`power`, `put`, `receives`, `remove`, `repeat`, `return`, `say`, `set`, `show`,
`subfolders`, `times`, `to`, `true`, `when`, `where`, `while`, `with`; and, as
variable names only, `today`, `now` and `pi`.

## Contextual words (not reserved)

These words take over a line or a condition only in one specific phrase, and
stay fully usable as names everywhere else. They are not reserved:

| Word | Role | Where it is special | Why it is not reserved |
|---|---|---|---|
| `go` | function | `go to ...`, `go back`, `go forward` | `go 3` still calls a function named `go` |
| `watch` | function | `watch file ...`, `watch folder ...` | `watch 1` still calls the function |
| `close` | function | `close websocket ...`, `close tcp ...`, `close udp ...` | `close 2` still calls the function |
| `store` / `delete` | function | `store secret ...`, `delete secret ...` | `store 4` still calls the function (`delete` is reserved for its own statement) |
| `generate` | function | `generate encryption key ...` | any other call reaches the function |
| `primary`, `secondary`, `danger` | function | before a UI element word (`primary button ...`) | any other call reaches the function |
| `total`, `avg`, `min`, `max` | function | aggregate query lines that contain both `from` and `into` (`total of price from orders in db into t`) | `from`/`into` are keywords and never arguments, so ordinary calls and assignments reach the name |
| `add` | function | `add X to Y` | the statement call `add 2 3` reaches a function named `add`; only the expression form `r is add 2 3` is rejected, loudly, by the parser |
| `count` | variable | a top-level line `count is ...` is read as a count loop | inside any block (`count is count plus 1` in a function or handler) it assigns normally, and the D56 canonical example relies on `state count is 0`; the top-level case is a check-time syntax error, never a silent one |
| `between` | variable | `x is between` starts a range check | only that one position, and it is a check-time syntax error |
| `file`, `element`, `registry` | variable | the left side of a condition (`if file is ...`) | only that one position, and it is a check-time syntax error; `for each file in files` is common and works |
| `contains`, `exists` | variable | directly after another value (`a contains b`) | assignment, reading and comparison all work |

Phrase-level word pairs used as values (`close code`, `received message`,
`sender port`, `drop x`, `text of`, `date from`, ...) are special only as that
pair and are not reserved either.

## Follow-ups for the parser owner

These need a parser change, not a smaller language, and are out of scope for
the post-parse validator:

- `count` at the top level, `between` after `is`, and `file` / `element` /
  `registry` at the start of a condition fail with misleading messages ("I
  expected a value here"). The parser could fall back to the variable reading
  when the word is a bound name.
- A declared function name could win over a contextual statement head (the
  recommendation in the RC2 language audit, L3). If that lands, the drift test
  will fail for the words it frees, and they should be removed from this list.
