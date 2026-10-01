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

The repository may be at `~/otterPS` or `~/Projects/otterPS`; use wherever it
was cloned.

```sh
cd ~/Projects/otterPS          # or ~/otterPS
git fetch
git checkout fix/macos-web-open   # 1.0.0-rc.10; use master once it is merged there
git pull
cat VERSION                       # should print 1.0.0-rc.10
```

For the real-download test (step 5), copy the `otter-mac-test` folder from the
Windows machine's Desktop to `~/Downloads/otter-mac-test` by hand (AirDrop, a
USB stick, a shared folder). It holds `otter-1.0.0-rc.10.zip` and its
`.sha256`; the zip is not in git. Without it, step 5 is skipped.

## Run the agent

Start the agent in the repository and give it the prompt below. When it
finishes, send the results back by committing them on their own branch:

```sh
cp ~/otter-mac-results.md docs/OTTER_MACOS_RESULTS_$(git rev-parse --short HEAD).md
git checkout -b mac-results/$(git rev-parse --short HEAD)
git add docs/OTTER_MACOS_RESULTS_*.md
git commit -m "docs: macOS hands-on test results for $(git rev-parse --short HEAD)"
git push -u origin HEAD
```

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
