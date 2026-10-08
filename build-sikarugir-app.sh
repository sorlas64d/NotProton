#!/bin/sh
# Builds NotProton.app with Sikarugir support, from a fresh checkout or an existing one.
#
#   ./build-sikarugir-app.sh
#
# Checks every prerequisite first and says how to fix whichever is missing, then runs the
# build in order. Steps already done are skipped or rebuilt incrementally, so running it
# again after a failure, or after pulling in updates, picks up where it left off.
#
# The first full build downloads Wine and Valve's Proton sources and takes 30 minutes or
# more. Nothing outside this repository is changed; installing into Steam happens later,
# from inside the app.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"

XCODE="${XCODE:-/Applications/Xcode.app}"
DEVELOPER_DIR="$XCODE/Contents/Developer"
export DEVELOPER_DIR
PATH="/opt/homebrew/bin:$PATH"
export PATH

step() { printf '\n==> %s\n' "$1"; }
fail() { printf '\nerror: %s\n' "$1" >&2; shift; for line in "$@"; do printf '       %s\n' "$line" >&2; done; exit 1; }

step "Checking prerequisites"

[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] ||
    fail "NotProton builds and runs on Apple Silicon Macs only."

arch -x86_64 /usr/bin/true 2>/dev/null ||
    fail "Rosetta 2 is not installed. Wine runs under it." \
         "Install it with: softwareupdate --install-rosetta --agree-to-license"

[ -d "$DEVELOPER_DIR" ] ||
    fail "Xcode was not found at $XCODE." \
         "Install Xcode from the App Store, or set XCODE=/path/to/Xcode.app." \
         "The Command Line Tools alone cannot build the app."

xcodebuild="$DEVELOPER_DIR/usr/bin/xcodebuild"
"$xcodebuild" -license check >/dev/null 2>&1 ||
    fail "The Xcode license has not been accepted." \
         "Run: sudo $xcodebuild -license accept"
"$xcodebuild" -checkFirstLaunchStatus >/dev/null 2>&1 ||
    fail "Xcode has not installed its first launch components (the app icon cannot be built without them)." \
         "Run: sudo $xcodebuild -runFirstLaunch"

command -v brew >/dev/null 2>&1 ||
    fail "Homebrew is not installed. See https://brew.sh"

missing=""
for formula in mingw-w64 bison cmake; do
    brew list --formula "$formula" >/dev/null 2>&1 || missing="$missing $formula"
done
[ -z "$missing" ] ||
    fail "Missing Homebrew packages:$missing" \
         "Run: brew install$missing"

for tool in git python3 rsync curl; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is not available."
done

echo "    all present"

step "Dobby (the hooking library the dylib links against)"
# The commit CI builds against, read from the workflow so there is one place to change it.
dobby_commit="$(sed -n 's/^ *DOBBY_COMMIT: *"\([0-9a-f]*\)".*/\1/p' .github/workflows/app.yml)"
[ -n "$dobby_commit" ] || fail "Could not read DOBBY_COMMIT from .github/workflows/app.yml."
if [ ! -d vendor/dobby/.git ]; then
    git clone --no-checkout https://github.com/jmpews/Dobby.git vendor/dobby
fi
# The clone is --no-checkout, so HEAD can already equal the pinned commit while the working
# tree is still empty; check for the files as well as the commit.
if [ "$(git -C vendor/dobby rev-parse HEAD 2>/dev/null || true)" != "$dobby_commit" ] ||
   [ ! -f vendor/dobby/CMakeLists.txt ]; then
    git -C vendor/dobby fetch --quiet origin
    git -C vendor/dobby checkout --quiet --force "$dobby_commit"
fi
if [ ! -f build/dobby/libdobby.a ]; then
    make dobby
else
    echo "    already built"
fi

step "NotProton's dylib, overlay shim and helpers"
make all overlay-shim iconmaker appinfo

step "Bridge for CrossOver's Wine (needed by every build of the app, even Sikarugir only)"
make bridge

step "Bridge for Sikarugir's Wine 11.0"
make bridge-sikarugir

step "App payload"
make app-payload

step "The app"
make app

printf '\n==> Done: %s/out/NotProton.app\n' "$here"
cat <<'NEXT'

Next:
  1. Quit Steam.
  2. Open out/NotProton.app. The first time, macOS may refuse to open it because it is not
     notarized: right-click it and choose Open, or allow it in
     System Settings > Privacy & Security.
  3. Follow "Installing" in the README from step 3.
NEXT
