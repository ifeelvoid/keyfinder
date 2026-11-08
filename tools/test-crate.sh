#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -sdk "${KEYFINDER_SDK:-$(xcrun --show-sdk-path)}" \
    Tests/CrateRoundTrip.swift Sources/KeyFinder/Models/TrackAnalysis.swift \
    -o "$TEST_DIR/crate-test"
"$TEST_DIR/crate-test"
swiftc -sdk "${KEYFINDER_SDK:-$(xcrun --show-sdk-path)}" \
    Tests/ThemeRoundTrip.swift Sources/KeyFinder/Models/ThemeManager.swift \
    -o "$TEST_DIR/theme-test"
"$TEST_DIR/theme-test"
