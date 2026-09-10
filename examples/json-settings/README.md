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

## Status: works end to end, one real bug found

**SEMANTIC BUG — an empty `has` object cannot be closed with an explicit
`.`.**

```otter
settings has
.
```

fails: *"There is no open block for this period to close."* Isolated the
exact cause: `Read-OtterObjectBlock` (added for D41 rule 8, commit
`18df9b7`) correctly returns zero properties when no `Indent` follows
`has`, but it never consumes a `BlockEnd` that immediately follows — so a
`.` written out of habit (every other block in the language accepts one,
D4/D18) is left with nothing open to close.

**Not a blocker** — confirmed the workaround: `settings has` with nothing
at all after it (no period) parses and runs correctly. The program in this
folder uses that form. This is a small bug inside the already-approved D41
work, not a new design question — it doesn't need a new D-number, just a
fix to `Read-OtterObjectBlock` so it also consumes an immediately-following
`BlockEnd`.

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
| Empty `has` object cannot be closed with `.` | SEMANTIC BUG — fix needed in `Read-OtterObjectBlock`, no new D-number |
| Everything else | works as written |
