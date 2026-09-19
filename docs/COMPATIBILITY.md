# Otter Programming Language — Compatibility & Versioning Policy

## 1. Versioning Strategy (D57)

Otter follows strict Semantic Versioning (`MAJOR.MINOR.PATCH`):
- **Authoritative Version Source**: The root `VERSION` file is the single authoritative source of truth for the language version.
- **CLI Invocations**: `otter --version` and REPL headers read directly from this file to ensure zero drift across tooling.
- **Exit Code Guarantees (D57)**:
  - `0`: Success
  - `1`: Usage Error (invalid CLI arguments, missing target, wrong extension)
  - `2`: Check Error (syntax, parser, or lexer error in source text)
  - `3`: Runtime Error (unhandled runtime exception in well-formed code)

---

## 2. Backward Compatibility Policy

1. **Syntax Stability**: Core syntax documented in `rules.md` and `docs/GRAMMAR.md` is guaranteed backward compatible across 1.x releases.
2. **No Silent Semantics Drift**: Behavior must never subtly change without an explicit compile-time error or major version bump.
3. **No Silent No-Ops**: Unsupported capabilities on specific target hosts must fail visibly with an `OtterError` rather than executing as silent no-ops.

---

## 3. Deprecation Policy

1. Any construct marked for deprecation will emit a warning during parsing or analysis for at least one minor release cycle before removal.
2. Deprecated syntax will provide automated code-replacement suggestions via the `Suggestion` field in `OtterError`.

---

## 4. Feature-Gating and Target Negotiation

- **Target Adapters**:
  - `Otter.Web.psm1`: Target for browser and exported HTML.
  - `Otter.Desktop.psm1`: Target for native desktop webview and local WPF window.
  - `Otter.Server.psm1`: Target for standalone API/HTTP backend services.
- **Host Capability Reporting**: When an Otter program invokes an API unavailable on the target host (e.g., raw local file mutation in a sandboxed browser tab without bridge), a clean diagnostic naming the capability boundary is raised.

---

## 5. Stable Module and Package ABI / API Strategy

1. **Source-Level Module ABI**:
   - **Export Model**: Top-level function declarations (`to <name> ...`) and type blueprints (`a <Name> has ...`) are exported by default.
   - **Invocation Contract**: Function calls bind parameters positionally. Return values are captured via `make <target>`.
   - **Resolution Invariance**: Modules are resolved by canonical file path in a Directed Acyclic Graph (DAG). Diamond imports (`A -> B, A -> C, B -> D, C -> D`) load the leaf module `D` exactly once, guaranteeing state and type identity invariance across imports.
2. **Inter-Host Interop ABI**:
   - **Universal Value Exchange**: All inter-host communication (CLI, Web bridge, Native WebView, HTTP server) encodes data using the universal Otter Data Interchange schema:
     - Number: IEEE 754 64-bit float.
     - Text: UTF-8 sequence.
     - Thing: Dictionary with `typeName` and ordered key-value properties.
     - List: Homogeneous or heterogeneous array.
   - **Zero Binary Drift**: Because Otter compiles directly to host-native abstractions (.NET runtime objects in PowerShell; ES modules / vanilla JS in Web/Node), modules maintain ABI stability by matching host runtime symbol exports.

