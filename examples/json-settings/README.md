# JSON Settings Tool — dogfooding program 2 of 3

**Blocked on D41's parser side, not yet started.** Uses `has`, dynamic
`get`/`set` from D41, JSON, `gone`, functions, and error handling.

`has` (D40) and JSON (D29) are already landed and usable today. What this
program actually needs and doesn't have yet is D41's dynamic-key grammar
(`get "key" from settings into value`, `set "key" to value in settings`) —
runtime and contract are done (`c5dc3f6`, `14fe98b`); only the parser piece
is outstanding. Write this program once that lands.
