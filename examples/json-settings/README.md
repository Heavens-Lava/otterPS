# JSON Settings Tool — dogfooding program 2 of 3

Run it:

```
otter examples\json-settings\settings-tool.ot
```

Exercises `has`, dynamic `get`/`set` (D41), JSON round-tripping (D29),
`gone`, functions, and `try`/`otherwise` error handling together, in one
realistic program: it loads settings from a file that may not exist yet,
falls back to an empty `thing`, reads and writes values by a name chosen at
runtime rather than a fixed property, and saves the result back to disk.

## Status: works end to end. One bug found, and now fixed.

**SEMANTIC BUG, FIXED — commit `29d389a`.** An empty `has` object could not
be closed with an explicit `.`:

```otter
settings has
.
```

used to fail: *"There is no open block for this period to close."* Isolated
the exact cause: `Read-OtterObjectBlock` (added for D41 rule 8, commit
`1b2ae10`) correctly returned zero properties when no `Indent` followed
`has`, but never consumed a `BlockEnd` that immediately followed — so a `.`
written out of habit (every other block in the language accepts one,
D4/D18) was left with nothing open to close.

Fixed by consuming an optional `BlockEnd` on that same empty-body path.
Re-verified directly after the fix landed, not just re-read: `settings
has` / `.`, `person is a thing` / `.`, the no-period form, and a dynamic
`set`/`get` round trip on the now-correctly-parsed empty object all run
correctly. Confirmed the fix did **not** widen anything it shouldn't have —
`if`, `to` (function bodies), and `while` with an empty body followed by
`.` are all still correctly rejected, exactly as before.

The program in this folder never actually hit this bug — its `settings
has` is followed immediately by another statement at the same indent
(`say "Starting with no saved settings."`), which was always a valid,
different way to end an empty object. Left unchanged; it was never
blocked.

## Verified, not assumed

- **Missing key returns `gone`** — `get "theme" from settings into theme`
  before `theme` was ever set produces `gone`, checked with `if theme is
  gone` exactly as D41 rule 4 specifies.
- **The JSON round trip is the real test of D41's central claim** (that
  `has` and JSON build the identical runtime type): read a JSON file with
  only `volume`, dynamically `set "theme"` on the resulting object, then
  `convert ... to json` — the JSON output correctly includes the
  dynamically-set `theme` key alongside the original `volume`. A JSON
  object and a `has`-built object are provably the same thing, not two
  types that happen to look similar.
- **Ran twice.** First run: no settings file exists, falls back to an empty
  object via `try`/`otherwise`, reports both settings as unset, then saves.
  Second run: loads the saved file, correctly reports `theme` as `dark`
  (persisted) and `volume` as still unset (it was never written).

## Classification

| Finding | Class |
|---|---|
| Empty `has` object could not be closed with `.` | SEMANTIC BUG — **fixed**, `29d389a` |
| Everything else | works as written |
