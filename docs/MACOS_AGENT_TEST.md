# Testing Otter on a Mac with a coding agent

How to have an agent (Claude Code, for example) run Otter's macOS checks on a
real Mac. The agent only tests; it changes nothing.

## Set up the Mac (once)

```sh
brew install gh git
brew install powershell   # a formula now; the old cask is gone
gh auth login
gh repo clone Heavens-Lava/otterPS ~/otterPS
```

## Get the code to test

```sh
cd ~/otterPS
git fetch
git checkout perf/benchmark-suite   # the latest 1.0 work; use master once it is merged there
git pull
```

Optional, for testing the real download: copy the `otter-mac-test` folder
(the Windows-built `otter-<version>.zip` and its `.sha256`) to
`~/Downloads/otter-mac-test`.

## Run the agent

Start the agent in `~/otterPS` and give it the prompt below. When it finishes,
send `~/otter-mac-results.md` back.

---

You are testing Otter on macOS. Test only: do not edit, commit or push anything. `CLAUDE.md` describes the project. Run each step from the repository root, keep going when one fails, and write every result to `~/otter-mac-results.md`: exact command, exit code, pass/fail counts, and the full text of any failure.

1. Record `git rev-parse --short HEAD`, `sw_vers`, `uname -m` and `pwsh --version`.
2. `pwsh -NoProfile -File tools/Test-OtterDistribution.ps1` (builds the zip, then unzips, installs twice, runs the project workflow and uninstalls).
3. `pwsh -NoProfile -File tools/Test-OtterDocumentedCli.ps1` (checks the documented CLI against an installed copy).
4. Every test file named in the "Verify portable language and module suite" step of `.github/workflows/d120-host-matrix.yml`, one at a time with `pwsh -NoProfile -File tests/<name>`. Include `tests/PlatformBoundaries.Tests.ps1`.
5. If `~/Downloads/otter-mac-test` holds an `otter-*.zip`, run `sh tools/Test-OtterMacInstall.sh ~/Downloads/otter-mac-test` (the real Windows-built download, extracted the way Finder does).
6. Run `./otter web examples/hello-app.ot` (the repository's own launcher) and confirm the page opens in the default browser, then run `git restore examples/hello-app.html` (the page is a tracked file, so rebuilding it changes it).
7. Run `git status --short` and record that nothing changed.

Finish with a summary table of every step and its result.
