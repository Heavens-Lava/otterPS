# Otter Transpiler Master Checklist

> Goal: make Otter's JavaScript backend a first-class, reusable transpiler that can be consumed by the CLI, Otter Studio, the documentation website, and future tooling without duplicating compiler logic.

## 0. Current state

- [x] Otter has a real lexer: `src/Otter.Lexer.psm1`
- [x] Otter has a real parser and AST: `src/Otter.Parser.psm1`
- [x] Otter already has a provider-agnostic AST -> JavaScript emitter: `src/Otter.Compiler.JavaScript.psm1`
- [x] Web compilation already consumes the shared JavaScript emitter rather than maintaining a second copy
- [ ] Provide one public source -> JavaScript transpiler facade
- [ ] Give the transpiler its own focused tests
- [ ] Expose transpilation through the CLI without coupling callers to web compilation
- [ ] Expose the same capability to Otter Studio
- [ ] Expose the same capability to the Otter website through a backend/API or future portable package
- [ ] Document supported constructs, host-dependent constructs, and known parity gaps

---

## 1. Transpiler core API

- [x] Keep `Otter.Compiler.JavaScript.psm1` as the universal AST -> JavaScript emitter
- [x] Keep browser/Desktop/Electron/host concerns out of the universal emitter
- [ ] Add `src/Otter.Transpiler.psm1` as the public orchestration layer
- [ ] Add `ConvertTo-OtterJavaScript -Source <text>`
- [ ] Add `ConvertTo-OtterJavaScriptProgram -Program <ProgramNode>`
- [ ] Ensure both APIs use the existing lexer/parser/compiler pipeline
- [ ] Never implement transpilation through string replacement
- [ ] Preserve Otter diagnostics when lexing/parsing fails
- [ ] Return deterministic JavaScript for identical Otter input
- [ ] Define newline policy for generated JavaScript
- [ ] Define whether output includes a trailing newline
- [ ] Define source-file/module resolution behavior separately from raw-source behavior

### Public pipeline

```text
Otter source
    |
    v
ConvertTo-OtterTokens
    |
    v
ConvertTo-OtterAst
    |
    v
ProgramNode
    |
    v
Otter.Compiler.JavaScript
    |
    v
JavaScript
```

---

## 2. JavaScript emitter parity

- [ ] Create an inventory of every `NodeKind`
- [ ] Mark every `NodeKind` as:
  - [ ] fully portable
  - [ ] portable with runtime helper
  - [ ] host-dependent
  - [ ] web-only
  - [ ] unsupported
- [ ] Add a regression test for every portable statement kind
- [ ] Add a regression test for every portable expression kind
- [ ] Verify arithmetic parity
- [ ] Verify comparison parity
- [ ] Verify boolean parity
- [ ] Verify strings and interpolation/concatenation parity
- [ ] Verify list parity
- [ ] Verify thing/object parity
- [ ] Verify function definition and call parity
- [ ] Verify return parity
- [ ] Verify if/otherwise parity
- [ ] Verify loops
- [ ] Verify dates/time
- [ ] Verify JSON
- [ ] Verify CSV
- [ ] Verify XML
- [ ] Verify random operations
- [ ] Verify diagnostics: log / warn / error
- [ ] Verify async detection
- [ ] Verify errors/fail/try semantics
- [ ] Track deliberate output differences from the PowerShell interpreter

---

## 3. Runtime boundary

- [ ] Remove remaining accidental browser assumptions from the universal emitter
- [ ] Replace direct `window.<name>` fallbacks with a host-neutral state/runtime abstraction
- [ ] Define a minimal JavaScript runtime contract
- [ ] Keep generated JavaScript runnable without dragging in the full web framework when possible
- [ ] Separate compiler output from host adapters
- [ ] Define runtime hooks for:
  - [ ] console output
  - [ ] input
  - [ ] files
  - [ ] folders
  - [ ] clipboard
  - [ ] process execution
  - [ ] HTTP/network
  - [ ] environment/system info
  - [ ] notifications
  - [ ] registry/Windows-specific capabilities
- [ ] Make unsupported host features fail clearly rather than silently changing behavior

---

## 4. CLI integration

> `otter.ps1` is currently owned by the back-end/CLI workflow. Integrate only through the approved owner or after ownership is reassigned.

- [ ] Add a user-facing command:
  - [ ] preferred: `otter transpile app.ot --to javascript`
  - [ ] or: `otter build app.ot --target javascript`
- [ ] Support output to stdout
- [ ] Support `--out <file.js>`
- [ ] Preserve exit codes
- [ ] Emit friendly Otter diagnostics on invalid source
- [ ] Support modules/imports using the same resolver as normal Otter execution
- [ ] Add CLI help text
- [ ] Add CLI contract tests

---

## 5. Otter Studio integration

- [ ] Add a Generated JavaScript panel
- [ ] Add side-by-side Otter / JavaScript view
- [ ] Refresh generated JavaScript after successful parse
- [ ] Keep last valid JavaScript visible when the current buffer has a temporary syntax error
- [ ] Show diagnostics instead of raw PowerShell errors
- [ ] Add copy-generated-JS command
- [ ] Add export-generated-JS command
- [ ] Add open-generated-output command
- [ ] Add source mapping/highlighting between Otter nodes and generated JavaScript
- [ ] Allow clicking an Otter statement to highlight corresponding generated JS
- [ ] Allow clicking generated JS to locate originating Otter source where practical

---

## 6. Otter website integration

### Short-term architecture: compiler service

- [ ] Keep the website separate from compiler implementation
- [ ] Create a small compiler service that calls the same Otter transpiler
- [ ] Define `POST /api/transpile`
- [ ] Request fields:
  - [ ] `source`
  - [ ] `target` = `javascript`
- [ ] Response fields:
  - [ ] `javascript`
  - [ ] diagnostics
  - [ ] compiler/version metadata
- [ ] Add request size limits
- [ ] Add execution timeout
- [ ] Never execute arbitrary generated JavaScript on the server
- [ ] Add CORS policy appropriate for the Otter website
- [ ] Add rate limiting before public release

### Website experience

- [ ] Add live Otter playground
- [ ] Add Convert to JavaScript button
- [ ] Add Run button for browser-safe programs
- [ ] Show compiler diagnostics inline
- [ ] Add examples that demonstrate one-to-one language concepts
- [ ] Add "Generated JavaScript" tab to documentation examples
- [ ] Display unsupported host capability messages clearly

### Long-term architecture

- [ ] Investigate packaging the compiler for browser use
- [ ] Evaluate C#/WASM, TypeScript, Rust/WASM, or another portable compiler implementation
- [ ] Prefer local browser transpilation when the compiler can be distributed safely and consistently
- [ ] Consider a versioned package such as `@otter/compiler`

---

## 7. JavaScript -> Otter import

> This is a separate feature from Otter -> JavaScript transpilation and should not block the first release.

- [ ] Define the supported JavaScript subset
- [ ] Parse JavaScript into a real JavaScript AST
- [ ] Never convert JavaScript using regex/string replacement
- [ ] Map supported JS AST nodes into Otter AST/IR concepts
- [ ] Produce readable, idiomatic Otter rather than literal token substitution
- [ ] Detect unsupported JavaScript features and report them explicitly
- [ ] Support basic literals
- [ ] Support variables
- [ ] Support arithmetic
- [ ] Support conditions
- [ ] Support loops
- [ ] Support functions
- [ ] Support arrays where an Otter list mapping is sound
- [ ] Support plain objects where an Otter thing mapping is sound
- [ ] Add import diagnostics with source locations
- [ ] Do not promise arbitrary JavaScript application conversion
- [ ] Label this feature "Import JavaScript" rather than implying perfect round-trip conversion

---

## 8. Intermediate representation / compiler architecture

- [ ] Decide whether the current AST is sufficient as the shared compiler representation
- [ ] If multiple backends begin duplicating semantic lowering, design an Otter IR
- [ ] Keep parsing separate from target-specific emission
- [ ] Keep semantic analysis separate from JavaScript syntax generation
- [ ] Define lowering rules once
- [ ] Preserve source locations through lowering
- [ ] Design IR for future targets without prematurely copying Dart Kernel complexity

Potential future pipeline:

```text
Source
  -> Lexer
  -> Parser
  -> AST
  -> Semantic analysis
  -> Otter IR
       |-> Interpreter
       |-> JavaScript
       |-> Web
       |-> Desktop/native
       |-> future targets
```

---

## 9. Diagnostics and source maps

- [ ] Preserve Otter line/column information through transpilation
- [ ] Define a generated-code mapping format
- [ ] Investigate standard JavaScript source maps
- [ ] Make runtime errors point back to Otter source when possible
- [ ] Include compiler-stage diagnostics separately from runtime diagnostics
- [ ] Ensure website diagnostics never expose server paths or internals
- [ ] Ensure Studio diagnostics remain beginner-friendly

---

## 10. Testing strategy

- [ ] Add `tests/Transpiler.Tests.ps1`
- [ ] Smoke test: `say "Hello"`
- [ ] Variable assignment test
- [ ] Arithmetic test
- [ ] If test
- [ ] Loop test
- [ ] Function test
- [ ] List test
- [ ] Thing/object test
- [ ] Date test
- [ ] JSON test
- [ ] Async test
- [ ] Invalid-source diagnostic test
- [ ] Deterministic-output test
- [ ] AST-direct transpilation test
- [ ] Compare selected generated programs against interpreter behavior
- [ ] Where Node.js is available, syntax-check generated output
- [ ] Where Node.js is available, execute host-neutral output and compare observable results
- [ ] Add regression test for every transpiler bug fixed

---

## 11. Packaging and versioning

- [ ] Give compiler/transpiler output a version
- [ ] Record Otter language version in compiler metadata where needed
- [ ] Decide compatibility policy between website compiler and installed Otter versions
- [ ] Keep one source of truth for version information
- [ ] Make compiler service expose its version
- [ ] Define breaking-change policy before third parties depend on compiler output
- [ ] Document whether generated JS is considered stable API or implementation detail

---

## 12. Security

- [ ] Treat source code received by a public website as untrusted input
- [ ] Do not shell-evaluate user source during transpilation
- [ ] Do not execute generated JS on the compiler server
- [ ] Sandbox any browser playground execution
- [ ] Add time/size limits
- [ ] Escape generated output when rendered as HTML
- [ ] Review runtime hooks before exposing filesystem/process features
- [ ] Keep secrets out of generated source
- [ ] Add adversarial input tests

---

## 13. Documentation

- [ ] Architecture overview
- [ ] Public transpiler API
- [ ] CLI usage
- [ ] Website integration guide
- [ ] Studio integration guide
- [ ] Supported feature matrix
- [ ] Known parity differences
- [ ] Runtime hook specification
- [ ] JavaScript import limitations
- [ ] Contribution/testing guide

---

## 14. First release definition

The first dedicated transpiler milestone is complete when:

- [ ] `ConvertTo-OtterJavaScript -Source` is public and tested
- [ ] It uses the real Otter lexer/parser/AST
- [ ] It delegates emission to `Otter.Compiler.JavaScript.psm1`
- [ ] No second JavaScript compiler exists
- [ ] Basic variables, math, conditions, loops, functions, lists, and `say` transpile correctly
- [ ] Invalid source produces normal Otter diagnostics
- [ ] Generated JavaScript is deterministic
- [ ] The API is suitable for CLI, Studio, and a website compiler service
- [ ] Known host-dependent features are documented
- [ ] The full test suite still passes

## Non-goals for the first release

- Perfect JavaScript -> Otter conversion
- Rewriting the compiler in another language
- Self-hosting Otter
- Replacing the interpreter
- Running Windows-only APIs in a browser
- Duplicating the compiler inside the website
