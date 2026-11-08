#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
SDK="${KEYFINDER_SDK:-$(xcrun --show-sdk-path)}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$TEST_DIR/module-cache}"
# Compile the same engine sources directly so this check also works without XCTest
# or a particular SwiftPM build-system output layout.
swiftc -sdk "$SDK" -parse-as-library -emit-module -emit-library -static \
    -module-name KeyFinderEngine Sources/KeyFinderEngine/Sources/KeyFinderEngine/*.swift \
    -emit-module-path "$TEST_DIR/KeyFinderEngine.swiftmodule" -o "$TEST_DIR/libKeyFinderEngine.a"
swiftc -sdk "$SDK" -I "$TEST_DIR" \
    Tests/AppWorkflowRegressions.swift Sources/KeyFinder/Models/AudioAnalysisModel.swift \
    Sources/KeyFinder/Models/TrackAnalysis.swift Sources/KeyFinder/Utilities/FileHashUtilities.swift \
    Sources/KeyFinder/Utilities/AudioFileDropLoader.swift Sources/KeyFinder/AudioAnalysis/AlbumArtExtractor.swift \
    Sources/KeyFinder/Utilities/LiveAnalysisWindow.swift Sources/KeyFinder/Utilities/LiveAudioCapture.swift \
    Sources/KeyFinder/Utilities/AudioInputDevices.swift \
    "$TEST_DIR/libKeyFinderEngine.a" -o "$TEST_DIR/app-workflow-tests"
"$TEST_DIR/app-workflow-tests"
