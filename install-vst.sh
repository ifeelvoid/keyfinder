#!/bin/bash
# Build universal plugins with CMake; installing requires an explicit --install.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
JUCE_DIR=${KEYFINDER_JUCE_DIR:-}
BUILD_DIR=${KEYFINDER_PLUGIN_BUILD_DIR:-"$ROOT/dist/plugin-build"}
INSTALL_ROOT=${KEYFINDER_PLUGIN_INSTALL_ROOT:-"$HOME/Library/Audio/Plug-Ins"}
INSTALL=false
usage() {
    echo 'Usage: install-vst.sh [--build-only | --install] [--juce-dir PATH] [--build-dir PATH] [--install-root PATH]'
}
MODE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --build-only|--install)
            if [ -n "$MODE" ] && [ "$MODE" != "$1" ]; then echo 'Choose --build-only or --install.' >&2; exit 2; fi
            MODE=$1
            [ "$1" != --install ] || INSTALL=true
            shift ;;
        --juce-dir|--build-dir|--install-root)
            [ "$#" -ge 2 ] && [ -n "$2" ] && [[ "$2" != --* ]] || { usage >&2; exit 2; }
            case "$1" in
                --juce-dir) JUCE_DIR=$2 ;;
                --build-dir) BUILD_DIR=$2 ;;
                --install-root) INSTALL_ROOT=$2 ;;
            esac
            shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done
if [ -z "$JUCE_DIR" ]; then
    for CANDIDATE in "$ROOT/JUCE" "$HOME/JUCE" /Applications/JUCE; do
        if [ -f "$CANDIDATE/CMakeLists.txt" ]; then JUCE_DIR=$CANDIDATE; break; fi
    done
fi
[ -f "$JUCE_DIR/CMakeLists.txt" ] || { echo 'JUCE checkout missing. Set KEYFINDER_JUCE_DIR or pass --juce-dir PATH.' >&2; exit 1; }
# Resolve caller-relative paths before any command can change directory.
case "$JUCE_DIR" in /*) ;; *) JUCE_DIR="$PWD/$JUCE_DIR" ;; esac
case "$BUILD_DIR" in /*) ;; *) BUILD_DIR="$PWD/$BUILD_DIR" ;; esac
case "$INSTALL_ROOT" in /*) ;; *) INSTALL_ROOT="$PWD/$INSTALL_ROOT" ;; esac
cmake -S "$ROOT/KeyFinderVST" -B "$BUILD_DIR" \
    "-DKEYFINDER_JUCE_DIR=$JUCE_DIR" -DCMAKE_BUILD_TYPE=Release \
    '-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64' -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0
cmake --build "$BUILD_DIR" --config Release --target KeyFinderVST_VST3 KeyFinderVST_AU --parallel
ARTIFACTS="$BUILD_DIR/KeyFinderVST_artefacts/Release"
for BUNDLE in "$ARTIFACTS/VST3/KeyFinderVST.vst3" "$ARTIFACTS/AU/KeyFinderVST.component"; do
    [ -d "$BUNDLE" ] || { echo "Missing plugin build: $BUNDLE" >&2; exit 1; }
    for ARCH in arm64 x86_64; do lipo "$BUNDLE/Contents/MacOS/KeyFinderVST" -verify_arch "$ARCH"; done
    # CMake's AU target may be unsigned even when its VST3 target is ad-hoc signed.
    # Sign these freshly built developer artifacts consistently before verification.
    if [ -n "${SIGNING_IDENTITY:-}" ]; then
        codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$BUNDLE"
    else
        codesign --force --sign - "$BUNDLE"
    fi
    codesign --verify --deep --strict "$BUNDLE"
done
if ! $INSTALL; then
    echo "Built and verified universal VST3 and AU plugins: $ARTIFACTS"
    echo 'Use --install explicitly to install them.'
    exit 0
fi
# Stage both copies before replacing either existing installation. Each replaced bundle
# remains recoverable in its destination directory; a failed move restores that bundle.
mkdir -p "$INSTALL_ROOT/VST3" "$INSTALL_ROOT/Components"
STAGING=$(mktemp -d "$INSTALL_ROOT/.keyfinder-install.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$ARTIFACTS/VST3/KeyFinderVST.vst3" "$STAGING/KeyFinderVST.vst3"
ditto "$ARTIFACTS/AU/KeyFinderVST.component" "$STAGING/KeyFinderVST.component"
for SPEC in 'VST3:KeyFinderVST.vst3' 'Components:KeyFinderVST.component'; do
    SUBDIR=${SPEC%%:*}
    NAME=${SPEC#*:}
    DEST="$INSTALL_ROOT/$SUBDIR/$NAME"
    BACKUP=""
    if [ -e "$DEST" ] || [ -L "$DEST" ]; then
        BACKUP=$(mktemp -d "$INSTALL_ROOT/$SUBDIR/previous-KeyFinderVST.XXXXXX")
        mv "$DEST" "$BACKUP/$NAME"
        echo "Previous plugin saved: $BACKUP/$NAME"
    fi
    if ! mv "$STAGING/$NAME" "$DEST"; then
        [ -z "$BACKUP" ] || mv "$BACKUP/$NAME" "$DEST"
        echo "Installation failed: $DEST" >&2
        exit 1
    fi
    echo "Installed: $DEST"
done
