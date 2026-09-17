# Otter 1.0 HTTP target parity

## Current surface syntax

The parser accepts these statement families:

```otter
get "https://example.test/items" into response
get "https://example.test/items" as json into data
get json from "https://example.test/items" into data

post payload to "https://example.test/items" into response
post payload as json to "https://example.test/items" into response

put payload to "https://example.test/items" into response
delete from "https://example.test/items" into response
```

They produce `HttpGetStmt`, `HttpPostStmt`, `HttpPutStmt`, and
`HttpDeleteStmt` respectively.

## Web target

`src/Otter.Compiler.JavaScript.psm1` emits `fetch` calls for all four verbs.
GET can decode JSON; POST/PUT can serialize JSON; response values are assigned
to the requested Otter target.  The generated calls are asynchronous and are
emitted inside a local JavaScript block to avoid response-variable collisions.

## PowerShell interpreter target

The interpreter has no statement cases for any HTTP node.  A program can parse
but `otter run` fails with the generic unsupported-statement path.  No
PowerShell web request behavior is currently part of Otter's language
semantics.

## Classification

HTTP is **web-target-only** for Otter 1.0.  It is not portable core syntax and
must be described that way in examples and release material until parity is
intentionally implemented.

## What interpreter parity would require

An HTTP provider boundary should define Otter-level request/response behavior:

- status-code policy and failure diagnostics;
- headers, body encoding, JSON decoding, redirects, timeouts, and cancellation;
- a target-neutral response shape; and
- matching tests for the PowerShell interpreter and generated JavaScript.

Directly mapping the grammar to `Invoke-WebRequest` or `Invoke-RestMethod`
would make PowerShell quirks the language definition, so that is not a safe
V1 patch.

## Recommendation

Keep the current target-specific classification for V1.  A future provider
contract can add portable HTTP deliberately, with one conformance suite across
web and interpreter targets.
