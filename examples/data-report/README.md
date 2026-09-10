# Small Data Program — dogfooding program 3 of 3

Run it:

```
otter examples\data-report\report.ot
```

A small sales report: totals, an average, a maximum found by scanning a
list, a function that classifies each entry, today's date formatted for
display, and diagnostic output — numbers, math, lists, functions, dates,
diagnostics, and conditions in one program, as specified.

## Status: works end to end, one ergonomic finding

**ERGONOMIC — `count` is reserved** (the `count from ... to ... as ...`
loop keyword), so the natural variable name for "how many sales" —
`count is length of sales` — fails to parse. Not a blocker: any other name
works, and the program here uses `saleCount`. Not new information exactly,
but real evidence for it: D33 explicitly kept `count` reserved "by design,
not by grammar" alongside `if`/`while`/`say`, and this is what that
decision costs in an actual program — a first-choice variable name that
doesn't work. Worth knowing the cost is real, without any suggestion the
decision was wrong.

## Verified, not assumed

Every computed value checked against the fixture data (120, 340, 75, 500,
210):

- total: `1245`, average: `249` — correct
- highest via a hand-rolled scan (`if amount is greater than highest`):
  `500` — correct
- a function with a conditional return (`to describe amount`) correctly
  classified each entry against the `300` threshold: `120 normal, 340
  high, 75 normal, 500 high, 210 normal`
- `today` formatted with `format ... as "MM/dd/yyyy" into ...` produced
  the real current date
- `log` printed; `warn` correctly did **not** fire, since the list was not
  empty

## Classification

| Finding | Class |
|---|---|
| `count` is reserved, natural name unavailable | ERGONOMIC |
| Everything else | works as written |
