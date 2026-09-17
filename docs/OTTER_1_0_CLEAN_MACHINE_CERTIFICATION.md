# Otter 1.0 RC clean-machine certification procedure

Run this on a supported, non-developer Windows 10/11 machine with Windows
PowerShell 5.1. Do not clone the repository or import source modules.

1. Download the versioned Otter ZIP and verify its adjacent SHA-256 file.
2. Extract it to a temporary folder and run `Install-Otter.ps1 -AddToUserPath`.
3. Open a **new** Windows PowerShell session and run `otter --version`.
4. Create and run `hello.ot` containing `say "Hello from Otter"`.
5. Run the release conformance suite from the release source checkout before
   packaging, or execute its listed programs manually from the installed
   launcher: variables/control flow, functions, file+JSON, deterministic date
   math, and command execution.
6. Compile `conformance/release/web_hello.ot` with `otter web ... -NoOpen` and
   verify the generated HTML contains the expected title, button, and click
   handler.
7. Verify that `use "anything.ot"` reports the documented deferred-feature
   diagnostic and that HTTP is only advertised for `otter web`.

Pass criteria: every step completes from the installed `otter.cmd`; no command
uses a repository-relative path, Studio, or manually imported development
module. Registry, printers, credentials, server listeners, and terminal
bridges are optional host capabilities and are not clean-machine core gates.
