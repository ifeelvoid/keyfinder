#!/bin/bash
# Run the existing XCTest sources directly when SwiftPM cannot find XCTest.
# Full Xcode supplies XCTest; the selected compiler and SDK may come from CLT.
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_DIR=$(mktemp -d "${TMPDIR:-/private/tmp}/keyfinder-xctest.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
SWIFTC="${KEYFINDER_SWIFTC:-swiftc}"
SDK="${KEYFINDER_SDK:-$(xcrun --show-sdk-path)}"
XCODE_DEVELOPER="${KEYFINDER_XCODE_DEVELOPER:-/Applications/Xcode.app/Contents/Developer}"
PLATFORM_DEVELOPER="$XCODE_DEVELOPER/Platforms/MacOSX.platform/Developer"
FRAMEWORKS="$PLATFORM_DEVELOPER/Library/Frameworks"
SWIFT_SUPPORT="$PLATFORM_DEVELOPER/usr/lib"
XCTEST="$XCODE_DEVELOPER/usr/bin/xctest"
if [[ ! -x "$XCTEST" || ! -d "$FRAMEWORKS/XCTest.framework" ]]; then
    echo "Full Xcode XCTest is required. Set KEYFINDER_XCODE_DEVELOPER to its Contents/Developer directory." >&2
    exit 1
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$TEST_DIR/module-cache}"
# The installed XCTest framework determines the test host's OS requirement;
# this does not change the engine/app deployment target.
TARGET="$(uname -m)-apple-macosx14.0"
COMMON=(-sdk "$SDK" -target "$TARGET")
ENGINE=Sources/KeyFinderEngine

# Always rebuild current sources: old SwiftPM artifacts may predate a fix.
"$SWIFTC" "${COMMON[@]}" -parse-as-library -enable-testing \
    -emit-module -emit-library -static -module-name KeyFinderEngine \
    "$ENGINE"/Sources/KeyFinderEngine/*.swift \
    -emit-module-path "$TEST_DIR/KeyFinderEngine.swiftmodule" \
    -o "$TEST_DIR/libKeyFinderEngine.a"
"$SWIFTC" "${COMMON[@]}" -parse-as-library -emit-module -emit-library -static \
    -module-name RegressionFixtures -I "$TEST_DIR" "$ENGINE"/Fixtures/*.swift \
    -emit-module-path "$TEST_DIR/RegressionFixtures.swiftmodule" \
    -o "$TEST_DIR/libRegressionFixtures.a"

BUNDLE="$TEST_DIR/KeyFinderEngineTests.xctest"
mkdir -p "$BUNDLE/Contents/MacOS"
"$SWIFTC" "${COMMON[@]}" -emit-library -module-name KeyFinderEngineTests \
    -I "$TEST_DIR" -I "$SWIFT_SUPPORT" -F "$FRAMEWORKS" \
    -L "$SWIFT_SUPPORT" -lXCTestSwiftSupport -framework XCTest \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$SWIFT_SUPPORT" \
    "$ENGINE"/Tests/*.swift "$TEST_DIR/libRegressionFixtures.a" \
    "$TEST_DIR/libKeyFinderEngine.a" \
    -o "$BUNDLE/Contents/MacOS/KeyFinderEngineTests"
"$XCTEST" "$BUNDLE" 2>&1 | tee "$TEST_DIR/results.log"
# A load/discovery failure must never look like successful verification.
grep -Eq 'Executed ([2-9]|[1-9][0-9]+) tests?, with 0 failures' "$TEST_DIR/results.log"
