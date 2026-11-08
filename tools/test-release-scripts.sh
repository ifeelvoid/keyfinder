#!/bin/bash
# Exercise release entry points in a throwaway repo; every build/account command is stubbed.
set -euo pipefail
SOURCE_ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/keyfinder-release-tests.XXXXXX")
FIXTURE=$(cd "$FIXTURE" && pwd)
trap 'rm -rf "$FIXTURE"' EXIT
REPO="$FIXTURE/repo with spaces"
mkdir -p "$REPO/tools" "$REPO/KeyFinderVST" "$FIXTURE/bin" "$FIXTURE/home" "$FIXTURE/JUCE checkout" "$FIXTURE/caller"
cp "$SOURCE_ROOT/"{distribute.sh,install-vst.sh,build-all.sh} "$REPO/"
touch "$FIXTURE/JUCE checkout/CMakeLists.txt" "$REPO/entitlements.plist"
TEST_DEFAULT_INSTALL_ROOT="$FIXTURE/default-install"
export KEYFINDER_PLUGIN_INSTALL_ROOT="$TEST_DEFAULT_INSTALL_ROOT"
export TEST_LOG="$FIXTURE/commands.log" TEST_VERSION=9.7.3
export PATH="$FIXTURE/bin:$PATH"
unset SIGNING_IDENTITY NOTARYTOOL_PROFILE KEYFINDER_JUCE_DIR KEYFINDER_PLUGIN_BUILD_DIR
cat > "$REPO/build-app.sh" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'build-app %s\n' "$*" >> "$TEST_LOG"
[ "${FAIL_BUILD:-0}" != 1 ] || exit 23
ROOT=$(cd "$(dirname "$0")" && pwd)
NAME=KeyFinder
[ "${1:-}" != --apple-silicon-preview ] || NAME=KeyFinder-AppleSilicon-preview
mkdir -p "$ROOT/dist/$NAME.app/Contents/MacOS"
touch "$ROOT/dist/$NAME.app/Contents/MacOS/KeyFinder"
cat > "$ROOT/dist/$NAME.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>$TEST_VERSION</string></dict></plist>
PLIST
STUB
cat > "$REPO/make-dmg.sh" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'make-dmg %s\n' "$*" >> "$TEST_LOG"
[ "${FAIL_PACKAGE:-0}" != 1 ] || exit 24
ROOT=$(cd "$(dirname "$0")" && pwd)
SUFFIX=""
[[ "$*" != *--apple-silicon-preview* ]] || SUFFIX=-AppleSilicon-preview
printf 'new package\n' > "$ROOT/dist/KeyFinder-v$TEST_VERSION$SUFFIX.dmg"
STUB
cat > "$FIXTURE/bin/cmake" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'cmake %s\n' "$*" >> "$TEST_LOG"
[ "${FAIL_CMAKE:-0}" != 1 ] || exit 25
if [ "${1:-}" = --build ]; then
    for SPEC in 'VST3/KeyFinderVST.vst3' 'AU/KeyFinderVST.component'; do
        [ "${OMIT_AU:-0}" != 1 ] || [ "$SPEC" != AU/KeyFinderVST.component ] || continue
        mkdir -p "$2/KeyFinderVST_artefacts/Release/$SPEC/Contents/MacOS"
        printf 'new plugin\n' > "$2/KeyFinderVST_artefacts/Release/$SPEC/Contents/MacOS/KeyFinderVST"
    done
fi
STUB
cat > "$FIXTURE/bin/codesign" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'codesign %s\n' "$*" >> "$TEST_LOG"
[ "${FAIL_SIGN:-0}" != 1 ] || exit 26
for ARG in "$@"; do TARGET=$ARG; done
[ -e "$TARGET" ] || { echo "Missing signing target: $TARGET" >&2; exit 27; }
STUB
cat > "$FIXTURE/bin/ditto" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'ditto %s\n' "$*" >> "$TEST_LOG"
[ "${FAIL_COPY:-0}" != 1 ] || exit 28
/bin/cp -R "$1" "$2"
STUB
cat > "$FIXTURE/bin/mv" <<'STUB'
#!/bin/bash
set -euo pipefail
# Fail only the replacement move, leaving backup and restore operations functional.
if [ "${FAIL_REPLACE:-0}" = 1 ] && [[ "$1" == */.keyfinder-install.*/KeyFinderVST.vst3 ]]; then exit 29; fi
exec /bin/mv "$@"
STUB
for CMD in lipo xcrun spctl open hdiutil; do
    cat > "$FIXTURE/bin/$CMD" <<'STUB'
#!/bin/bash
set -euo pipefail
printf '%s %s\n' "$(basename "$0")" "$*" >> "$TEST_LOG"
[ "${FAIL_NOTARY:-0}" != 1 ] || [ "${1:-}" != notarytool ] || exit 30
STUB
done
cat > "$FIXTURE/bin/security" <<'STUB'
#!/bin/bash
printf 'security %s\n' "$*" >> "$TEST_LOG"
echo '  1) DEADBEEF "Developer ID Application: Fixture"'
STUB
chmod +x "$FIXTURE/bin/"* "$REPO/build-app.sh" "$REPO/make-dmg.sh"
PASS=0
pass() { PASS=$((PASS + 1)); echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; cat "$TEST_LOG" >&2; exit 1; }
contains() { /usr/bin/grep -F -- "$1" "$TEST_LOG" >/dev/null || fail "Missing call: $1"; }
absent() { if /usr/bin/grep -E -- "$1" "$TEST_LOG" >/dev/null; then fail "Forbidden call: $1"; fi; }
run() { : > "$TEST_LOG"; bash "$@" > "$FIXTURE/output.log" 2>&1 || { cat "$FIXTURE/output.log" >&2; fail "Command failed: $*"; }; }
reject() {
    : > "$TEST_LOG"
    if bash "$@" > "$FIXTURE/output.log" 2>&1; then fail "Unexpected success: $*"; fi
}
cd "$FIXTURE/caller"
run "$REPO/distribute.sh"
contains 'build-app '
contains 'make-dmg --skip-build'
[ -f "$REPO/dist/KeyFinder-v9.7.3.dmg" ] || fail 'Current metadata DMG absent'
[ ! -e "$REPO/build" ] || fail 'Legacy build path used'
absent '^(security|xcrun|spctl|codesign|open) '
pass 'Distribution packages current metadata version via canonical make-dmg without implicit account operations'
run "$REPO/distribute.sh" --skip-build
absent '^build-app '
contains 'make-dmg --skip-build'
pass 'Skip-build packages existing current dist app'
run "$REPO/distribute.sh" --apple-silicon-preview
contains 'build-app --apple-silicon-preview'
contains 'make-dmg --skip-build --apple-silicon-preview'
[ -f "$REPO/dist/KeyFinder-v9.7.3-AppleSilicon-preview.dmg" ] || fail 'Preview DMG absent'
pass 'Preview routes app and artifact suffix consistently'
for SCRIPT in distribute.sh install-vst.sh build-all.sh; do
    reject "$REPO/$SCRIPT" --unknown
    [ ! -s "$TEST_LOG" ] || fail 'Unknown option performed work'
done
for SCRIPT in install-vst.sh build-all.sh; do
    reject "$REPO/$SCRIPT" --juce-dir
    [ ! -s "$TEST_LOG" ] || fail 'Missing option value performed work'
done
pass 'Unknown arguments and missing option values fail before work'
export FAIL_BUILD=1
reject "$REPO/distribute.sh"
absent '^make-dmg '
reject "$REPO/build-all.sh" --juce-dir "$FIXTURE/JUCE checkout"
absent '^cmake '
unset FAIL_BUILD
export FAIL_PACKAGE=1
reject "$REPO/distribute.sh" --skip-build
absent '^(xcrun|spctl) '
unset FAIL_PACKAGE
pass 'App/package failures stop downstream work despite an existing DMG'
reject "$REPO/distribute.sh" --notarize
[ ! -s "$TEST_LOG" ] || fail 'Unconfigured notarization performed work'
export SIGNING_IDENTITY='Developer ID Application: Fixture'
reject "$REPO/distribute.sh" --notarize
[ ! -s "$TEST_LOG" ] || fail 'Missing notary profile performed work'
export NOTARYTOOL_PROFILE='fixture-profile'
run "$REPO/distribute.sh" --skip-build --notarize
contains "codesign --force --deep --sign Developer ID Application: Fixture --options runtime --timestamp --entitlements $REPO/entitlements.plist $REPO/dist/KeyFinder.app"
contains "xcrun notarytool submit $REPO/dist/KeyFinder-v9.7.3.dmg --keychain-profile fixture-profile --wait"
contains 'xcrun stapler validate '
contains 'spctl --assess '
absent '^security '
pass 'Explicit notarization re-signs selected current app and uses only configured keychain profile'
export FAIL_NOTARY=1
reject "$REPO/distribute.sh" --skip-build --notarize
absent '^xcrun stapler '
absent '^spctl '
unset FAIL_NOTARY SIGNING_IDENTITY NOTARYTOOL_PROFILE
pass 'Notary failure prevents stapling and final assessment'
run "$REPO/install-vst.sh" --build-only --juce-dir "$FIXTURE/JUCE checkout" --build-dir 'plugin output'
contains "cmake -S $REPO/KeyFinderVST -B $PWD/plugin output -DKEYFINDER_JUCE_DIR=$FIXTURE/JUCE checkout -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64;x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0"
contains 'KeyFinderVST_VST3 KeyFinderVST_AU --parallel'
contains '-verify_arch arm64'
contains '-verify_arch x86_64'
contains 'codesign --verify --deep --strict '
[ ! -e "$TEST_DEFAULT_INSTALL_ROOT" ] || fail 'Build-only installed plugins'
pass 'CMake builds both universal current plugins and validates them without installation'
export KEYFINDER_JUCE_DIR="$FIXTURE/JUCE checkout" KEYFINDER_PLUGIN_BUILD_DIR="$FIXTURE/env build"
run "$REPO/install-vst.sh"
contains "cmake --build $FIXTURE/env build"
[ ! -e "$TEST_DEFAULT_INSTALL_ROOT" ] || fail 'Default mode installed plugins'
run "$REPO/build-all.sh" --build-dir "$FIXTURE/all build"
contains 'build-app '
contains "cmake --build $FIXTURE/all build"
absent '^open '
[ ! -e "$TEST_DEFAULT_INSTALL_ROOT" ] || fail 'build-all installed plugins'
pass 'Environment configuration works and build-all performs no implicit install or launch'
run "$REPO/build-all.sh" --skip-plugins --apple-silicon-preview
contains 'build-app --apple-silicon-preview'
absent '^cmake '
pass 'Explicit skip-plugins builds only selected desktop variant'
export FAIL_CMAKE=1
reject "$REPO/install-vst.sh"
absent '^(lipo|codesign|ditto) '
reject "$REPO/build-all.sh"
unset FAIL_CMAKE
export OMIT_AU=1 KEYFINDER_PLUGIN_BUILD_DIR="$FIXTURE/incomplete build"
reject "$REPO/install-vst.sh" --install
[ ! -e "$TEST_DEFAULT_INSTALL_ROOT" ] || fail 'Incomplete artifact installed plugins'
unset OMIT_AU
export FAIL_SIGN=1 KEYFINDER_PLUGIN_BUILD_DIR="$FIXTURE/sign failure"
reject "$REPO/install-vst.sh" --install
[ ! -e "$TEST_DEFAULT_INSTALL_ROOT" ] || fail 'Invalid signature installed plugins'
unset FAIL_SIGN
pass 'Build, missing artifact, and signature failures prevent installation and propagate'
INSTALL_ROOT="$FIXTURE/install root"
mkdir -p "$INSTALL_ROOT/VST3/KeyFinderVST.vst3" "$INSTALL_ROOT/Components/KeyFinderVST.component"
printf 'old vst\n' > "$INSTALL_ROOT/VST3/KeyFinderVST.vst3/original"
printf 'old au\n' > "$INSTALL_ROOT/Components/KeyFinderVST.component/original"
export FAIL_COPY=1
reject "$REPO/install-vst.sh" --install --install-root "$INSTALL_ROOT"
[ -f "$INSTALL_ROOT/VST3/KeyFinderVST.vst3/original" ] && [ -f "$INSTALL_ROOT/Components/KeyFinderVST.component/original" ] || fail 'Stage failure changed installed plugins'
unset FAIL_COPY
export FAIL_REPLACE=1
reject "$REPO/install-vst.sh" --install --install-root "$INSTALL_ROOT"
[ -f "$INSTALL_ROOT/VST3/KeyFinderVST.vst3/original" ] && [ -f "$INSTALL_ROOT/Components/KeyFinderVST.component/original" ] || fail 'Failed replacement did not restore original'
unset FAIL_REPLACE
pass 'Staging failure leaves plugins intact; failed replacement restores original bundle'
run "$REPO/install-vst.sh" --install --install-root "$INSTALL_ROOT"
[ -f "$INSTALL_ROOT/VST3/KeyFinderVST.vst3/Contents/MacOS/KeyFinderVST" ] || fail 'VST not installed'
[ -f "$INSTALL_ROOT/Components/KeyFinderVST.component/Contents/MacOS/KeyFinderVST" ] || fail 'AU not installed'
OLD_VST=("$INSTALL_ROOT"/VST3/previous-KeyFinderVST.*/KeyFinderVST.vst3/original)
OLD_AU=("$INSTALL_ROOT"/Components/previous-KeyFinderVST.*/KeyFinderVST.component/original)
[ "$(cat "${OLD_VST[0]}")" = 'old vst' ] && [ "$(cat "${OLD_AU[0]}")" = 'old au' ] || fail 'Previous plugins not preserved'
pass 'Explicit installation replaces both bundles and preserves recoverable prior copies'
# The pre-fix script builds dist then tries to sign a missing legacy build/ app.
if git -C "$SOURCE_ROOT" show HEAD:distribute.sh > "$REPO/legacy-distribute.sh" 2>/dev/null; then
    cd "$REPO"
    reject "$REPO/legacy-distribute.sh"
    contains 'build-app '
    contains 'build/KeyFinder.app'
    /usr/bin/grep -F 'Missing signing target: build/KeyFinder.app' "$FIXTURE/output.log" >/dev/null || fail 'Legacy failure was not the expected stale artifact'
    pass 'Pre-fix distribution failure reproduced against current dist artifact layout'
fi
# Exercise canonical packaging too, using real metadata and fake system commands.
cp "$SOURCE_ROOT/make-dmg.sh" "$REPO/make-dmg.sh"
mkdir -p "$REPO/packaging"
printf 'fixture instructions\n' > "$REPO/packaging/INSTALL.txt"
cp "$REPO/packaging/INSTALL.txt" "$REPO/packaging/INSTALL-preview.txt"
printf 'fixture credits\n' > "$REPO/packaging/CREDITS.txt"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 12.0' "$REPO/dist/KeyFinder.app/Contents/Info.plist"
cat > "$FIXTURE/bin/hdiutil" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'hdiutil %s\n' "$*" >> "$TEST_LOG"
[ "${FAIL_IMAGE:-0}" != 1 ] || exit 31
if [ "$1" = create ]; then
    for ARG in "$@"; do TARGET=$ARG; done
    printf 'fixture disk image\n' > "$TARGET"
fi
STUB
chmod +x "$FIXTURE/bin/hdiutil"
# Distinct sentinels prove packaging uses the explicitly selected custom build.
for BUILD in "$REPO/dist/plugin-build" "$FIXTURE/caller/custom plugins"; do
    for SPEC in VST3/KeyFinderVST.vst3 AU/KeyFinderVST.component; do
        mkdir -p "$BUILD/KeyFinderVST_artefacts/Release/$SPEC/Contents/MacOS"
        printf '%s\n' "$BUILD" > "$BUILD/KeyFinderVST_artefacts/Release/$SPEC/Contents/MacOS/KeyFinderVST"
    done
done
export KEYFINDER_PLUGIN_BUILD_DIR='custom plugins'
cd "$FIXTURE/caller"
run "$REPO/make-dmg.sh" --skip-build
contains "ditto $FIXTURE/caller/custom plugins/KeyFinderVST_artefacts/Release/VST3/KeyFinderVST.vst3"
absent "ditto $REPO/dist/plugin-build/KeyFinderVST_artefacts"
contains 'codesign --force --sign - '
contains 'hdiutil verify '
pass 'Canonical DMG uses configured caller-relative plugin build instead of stale default output'
export SIGNING_IDENTITY='Developer ID Application: Fixture'
run "$REPO/make-dmg.sh" --skip-build
contains 'codesign --force --sign Developer ID Application: Fixture --options runtime --timestamp '
absent 'codesign --force --sign - '
unset SIGNING_IDENTITY
pass 'Canonical packaging retains configured plugin signing identity with hardened runtime'
export FAIL_IMAGE=1
reject "$REPO/make-dmg.sh" --skip-build
unset FAIL_IMAGE
export KEYFINDER_PLUGIN_BUILD_DIR="$FIXTURE/missing plugins"
reject "$REPO/make-dmg.sh" --skip-build
absent '^hdiutil '
pass 'Image failure propagates and explicit incomplete plugin output cannot become app-only success'
# Finally exercise the actual app builder with synthetic Swift/lipo artifacts.
cp "$SOURCE_ROOT/build-app.sh" "$REPO/build-app.sh"
cp "$SOURCE_ROOT/packaging/Info.plist" "$REPO/packaging/Info.plist"
cp "$SOURCE_ROOT/entitlements.plist" "$REPO/entitlements.plist"
touch "$REPO/AppIcon.icns"
cat > "$FIXTURE/bin/swift" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'swift %s\n' "$*" >> "$TEST_LOG"
ARCH=""
SHOW_PATH=false
while [ "$#" -gt 0 ]; do
    if [ "$1" = --show-bin-path ]; then SHOW_PATH=true; fi
    if [ "$1" = --arch ]; then ARCH=$2; shift; fi
    shift
done
if $SHOW_PATH; then printf '%s/.build/%s-apple-macosx/release\n' "$PWD" "$ARCH"; exit 0; fi
mkdir -p ".build/$ARCH-apple-macosx/release"
printf 'current %s\n' "$ARCH" > ".build/$ARCH-apple-macosx/release/KeyFinder"
STUB
cat > "$FIXTURE/bin/lipo" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'lipo %s\n' "$*" >> "$TEST_LOG"
while [ "$#" -gt 0 ]; do
    if [ "$1" = -output ]; then printf 'universal fixture\n' > "$2"; exit 0; fi
    shift
done
STUB
chmod +x "$FIXTURE/bin/swift" "$FIXTURE/bin/lipo"
export KEYFINDER_SDK="$FIXTURE/fake sdk" KEYFINDER_DISABLE_SWIFTPM_SANDBOX=1
run "$REPO/build-app.sh"
contains 'swift build --disable-sandbox --build-system native -c release --arch x86_64'
contains '--arch arm64'
contains 'codesign --force --sign - '
[ ! -e "$REPO/build" ] || fail 'App builder touched legacy build path'
export SIGNING_IDENTITY='Developer ID Application: Fixture'
run "$REPO/build-app.sh" --apple-silicon-preview
contains 'codesign --force --sign Developer ID Application: Fixture --options runtime --timestamp --entitlements entitlements.plist '
[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.audio-input' "$REPO/entitlements.plist")" = true ] || fail 'Signed app cannot request audio input'
absent '--arch x86_64'
reject "$REPO/build-app.sh" --unknown
[ ! -s "$TEST_LOG" ] || fail 'Unknown build-app option performed work'
unset SIGNING_IDENTITY KEYFINDER_SDK KEYFINDER_DISABLE_SWIFTPM_SANDBOX
pass 'App builder checks options, builds selected slices and applies audio-input entitlements when signing'
echo "$PASS release-script regression groups passed. No real build, install, signing, or account operation ran."
