#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$TEST_DIR/module-cache}"
swiftc -sdk "${KEYFINDER_SDK:-$(xcrun --show-sdk-path)}" \
    Tests/LiveAnalysisRegressions.swift Sources/KeyFinder/Utilities/LiveAnalysisWindow.swift \
    -o "$TEST_DIR/live-analysis-tests"
"$TEST_DIR/live-analysis-tests"
