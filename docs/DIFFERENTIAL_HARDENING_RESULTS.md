# Otter 1.0 - Hardening Differential Verification (Batch 4)

- **Seed**: 20260918
- **Iterations**: 1000
- **Target Runtimes**: PowerShell Interpreter vs JavaScript Compiler (Node VM)
- **Total Passed**: 1000
- **Total Disagreements**: 0
- **Elapsed Time**: 130s

### Result: no disagreements on the generated programs.
Zero disagreements were found across the feature interactions this fuzzer
generates. This is not a claim of full console/web parity: the generated
programs never print lists, `gone`, things, JSON text or non-terminating
decimals, and they do not compare lists. Console and web share the same
semantics for the portable core, with the known differences listed in
[OTTER_1_0_RELEASE_SCOPE_MATRIX.md](OTTER_1_0_RELEASE_SCOPE_MATRIX.md#known-consoleweb-differences).
