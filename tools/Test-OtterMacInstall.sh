#!/bin/sh
# Otter macOS/Linux install test for a release archive (otter-<version>.zip):
#
#     sh tools/Test-OtterMacInstall.sh <folder holding the zip>
#
# or copy this script next to the zip and run it there with no argument. It
# needs PowerShell 7 (pwsh). It extracts the archive the way Finder does
# (ditto; unzip where ditto is missing), runs ./otter, installs twice with
# -AddToUserPath, runs programs, compiles a web page, checks that Windows-only
# features are refused clearly, runs the project workflow and uninstalls - all
# in a temporary folder with a temporary home directory. Results are printed
# and saved to otter-mac-test-results.txt in the zip's folder.

# The folder holding the zip: the first argument, or the script's own folder.
here=$(CDPATH= cd -- "${1:-$(dirname -- "$0")}" && pwd)
results="$here/otter-mac-test-results.txt"
: > "$results"
pass=0
fail=0

say() { printf '%s\n' "$*" | tee -a "$results"; }
ok() { pass=$((pass + 1)); say "PASS  $1"; }
bad() { fail=$((fail + 1)); say "FAIL  $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /' | head -8 | tee -a "$results"; }

say "Otter macOS test - $(date)"
say "System: $(sw_vers -productName 2>/dev/null || uname -s) $(sw_vers -productVersion 2>/dev/null || uname -r) ($(uname -m))"

if ! command -v pwsh >/dev/null 2>&1; then
    say "PowerShell 7 is not installed. Install it from https://aka.ms/install-powershell"
    say "(or: brew install --cask powershell), then run: sh mac-test.sh"
    exit 1
fi
say "PowerShell: $(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"

zip=$(ls "$here"/otter-*.zip 2>/dev/null | head -1)
if [ -z "$zip" ]; then say "No otter-*.zip next to this script."; exit 1; fi
version=$(basename "$zip" .zip | sed 's/^otter-//')
say "Archive: $(basename "$zip") (version $version)"
say ""

work=$(mktemp -d "${TMPDIR:-/tmp}/otter-mac-test.XXXXXX")
export HOME="$work/home"
mkdir -p "$HOME"
cd "$work" || exit 1

# 1. The download is intact.
if [ -f "$zip.sha256" ]; then
    want=$(tr -d ' \r\n' < "$zip.sha256" | tr 'A-F' 'a-f')
    got=$( (shasum -a 256 "$zip" 2>/dev/null || sha256sum "$zip") | cut -d' ' -f1)
    [ "$want" = "$got" ] && ok "checksum matches" || bad "checksum does not match" "expected $want, got $got"
fi

# 2. Extract the way Finder does (ditto is Archive Utility's engine).
if command -v ditto >/dev/null 2>&1; then tool=ditto; ditto -x -k "$zip" "$work/extracted"; else tool=unzip; unzip -q "$zip" -d "$work/extracted"; fi
pkg="$work/extracted/otter-$version"
if [ -d "$pkg/src" ]; then ok "extracted with $tool into a normal folder"; else bad "extracted with $tool: no otter-$version/src folder" "$(ls -la "$work/extracted" | head -5)"; fi
flat=$(find "$work/extracted" -name '*\\*' | head -3)
[ -z "$flat" ] && ok "no file names with backslashes" || bad "file names contain backslashes" "$flat"
[ -x "$pkg/otter" ] && ok "the otter launcher is executable" || bad "the otter launcher is not executable" "$(ls -l "$pkg/otter")"
if command -v xattr >/dev/null 2>&1 && xattr "$pkg/otter" 2>/dev/null | grep -q quarantine; then say "note  the files carry the macOS download quarantine flag"; fi

# 3. Run without installing.
out=$("$pkg/otter" --version 2>&1)
case "$out" in *"Otter $version"*) ok "./otter --version prints Otter $version";; *) bad "./otter --version" "$out";; esac
out=$("$pkg/otter" run "$pkg/examples/hello.ot" 2>&1)
[ $? -eq 0 ] && [ -n "$out" ] && ok "./otter run examples/hello.ot" || bad "./otter run examples/hello.ot" "$out"

# 4. Install, twice (the second install must replace its own command).
for n in 1 2; do
    out=$(pwsh -NoProfile -File "$pkg/Install-Otter.ps1" -Destination "$work/installed" -AddToUserPath -Force 2>&1)
    [ $? -eq 0 ] && ok "install $n with -AddToUserPath" || bad "install $n with -AddToUserPath" "$out"
done
otter="$HOME/.local/bin/otter"
[ -x "$otter" ] && ok "~/.local/bin/otter was created" || bad "~/.local/bin/otter is missing"
out=$("$otter" --version 2>&1)
case "$out" in *"Otter $version"*) ok "the installed otter command runs";; *) bad "the installed otter command" "$out";; esac

# 5. Programs, web, and what needs Windows.
mkdir -p "$work/play" && cd "$work/play" || exit 1
printf 'x is 20\ny is 22\nsay "The answer is" x plus y\n' > answer.ot
out=$("$otter" run answer.ot 2>&1)
case "$out" in *"The answer is 42"*) ok "otter run a program";; *) bad "otter run a program" "$out";; esac
cp "$pkg/examples/hello-app.ot" .
out=$("$otter" web hello-app.ot -NoOpen 2>&1)
[ -f hello-app.html ] && ok "otter web compiles a page" || bad "otter web" "$out"
out=$("$otter" desktop hello-app.ot 2>&1); code=$?
[ $code -ne 0 ] && printf '%s' "$out" | grep -q "only available on Windows" && ok "otter desktop is refused clearly" || bad "otter desktop should be refused" "exit $code: $out"
printf 'get registry value "n" from "HKCU:\\Software\\Otter" into t\nsay t\n' > reg.ot
out=$("$otter" run reg.ot 2>&1); code=$?
[ $code -ne 0 ] && printf '%s' "$out" | grep -q "only available on Windows" && ok "the registry is refused clearly" || bad "the registry should be refused" "exit $code: $out"
printf 'copy "otter-clip-test" to clipboard\nget clipboard into pasted\nsay pasted\n' > clip.ot
out=$("$otter" run clip.ot 2>&1); code=$?
if [ $code -eq 0 ] && [ "$out" = "otter-clip-test" ]; then ok "the clipboard round-trips"
elif [ $code -ne 0 ] && printf '%s' "$out" | grep -qi clipboard; then ok "the clipboard says clearly that it is unavailable"
else bad "the clipboard" "exit $code: $out"; fi

# 6. The project workflow, and the built app's own launcher.
out=$("$otter" new console demo 2>&1) && ok "otter new console demo" || bad "otter new" "$out"
cd demo 2>/dev/null || true
for cmd in check test run build publish; do
    out=$("$otter" $cmd . 2>&1)
    [ $? -eq 0 ] && ok "otter $cmd ." || bad "otter $cmd ." "$out"
done
if [ -f dist/run ]; then
    out=$(PATH="$HOME/.local/bin:$PATH" sh dist/run 2>&1)
    [ $? -eq 0 ] && ok "the built app runs with dist/run" || bad "dist/run" "$out"
else
    say "note  this build has no dist/run launcher (added after rc.8)"
fi
cd "$work" || exit 1

# 7. Uninstall.
out=$(pwsh -NoProfile -File "$work/installed/Uninstall-Otter.ps1" -Destination "$work/installed" 2>&1)
[ $? -eq 0 ] && ok "uninstall" || bad "uninstall" "$out"
[ ! -e "$otter" ] && ok "~/.local/bin/otter was removed" || bad "~/.local/bin/otter is still there"
[ ! -e "$work/installed" ] && ok "the install folder was removed" || bad "the install folder is still there"

rm -rf "$work"
say ""
say "Result: $pass passed, $fail failed. Saved to $results"
[ $fail -eq 0 ]
