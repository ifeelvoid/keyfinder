#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
PLUGIN_BUILD_DIR=${KEYFINDER_PLUGIN_BUILD_DIR:-"$ROOT/dist/plugin-build"}
case "$PLUGIN_BUILD_DIR" in /*) ;; *) PLUGIN_BUILD_DIR="$PWD/$PLUGIN_BUILD_DIR" ;; esac
cd "$ROOT"
SKIP_BUILD=false
PREVIEW=false
for OPTION in "$@"; do
    case "$OPTION" in
        --skip-build) SKIP_BUILD=true ;;
        --apple-silicon-preview) PREVIEW=true ;;
        *) echo "Unknown option: $OPTION" >&2; exit 2 ;;
    esac
done
APP=dist/KeyFinder.app
SUFFIX=""
ARCHES=(x86_64 arm64)
if $PREVIEW; then
    APP=dist/KeyFinder-AppleSilicon-preview.app
    SUFFIX=-AppleSilicon-preview
    ARCHES=(arm64)
fi
if ! $SKIP_BUILD; then
    if $PREVIEW; then bash build-app.sh --apple-silicon-preview; else bash build-app.sh; fi
fi
for ARCH in "${ARCHES[@]}"; do lipo "$APP/Contents/MacOS/KeyFinder" -verify_arch "$ARCH"; done
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
MIN_OS=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")
[ "$MIN_OS" = 12.0 ] || { echo "Unexpected minimum OS: $MIN_OS" >&2; exit 1; }
STAGING=$(mktemp -d "$PWD/dist/dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
mkdir "$STAGING/contents"
ditto "$APP" "$STAGING/contents/KeyFinder.app"
ln -s /Applications "$STAGING/contents/Applications"
cp packaging/INSTALL.txt "$STAGING/contents/INSTALL.txt"
cp packaging/CREDITS.txt "$STAGING/contents/CREDITS.txt"
if $PREVIEW; then cp packaging/INSTALL-preview.txt "$STAGING/contents/INSTALL.txt"; fi
# Universal plugins from `cmake --build dist/plugin-build` (see KeyFinderVST/CMakeLists.txt).
PLUGINS="$PLUGIN_BUILD_DIR/KeyFinderVST_artefacts/Release"
if ! $PREVIEW && [ -d "$PLUGINS/AU/KeyFinderVST.component" ] && [ -d "$PLUGINS/VST3/KeyFinderVST.vst3" ]; then
    mkdir -p "$STAGING/contents/Plug-Ins/AU" "$STAGING/contents/Plug-Ins/VST3"
    ditto "$PLUGINS/AU/KeyFinderVST.component" "$STAGING/contents/Plug-Ins/AU/KeyFinderVST.component"
    ditto "$PLUGINS/VST3/KeyFinderVST.vst3" "$STAGING/contents/Plug-Ins/VST3/KeyFinderVST.vst3"
    for BUNDLE in "$STAGING"/contents/Plug-Ins/*/KeyFinderVST.*; do
        for ARCH in "${ARCHES[@]}"; do lipo "$BUNDLE/Contents/MacOS/KeyFinderVST" -verify_arch "$ARCH"; done
        if [ -n "${SIGNING_IDENTITY:-}" ]; then
            codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$BUNDLE"
        else
            codesign --force --sign - "$BUNDLE"
        fi
        codesign --verify --deep --strict "$BUNDLE"
    done
elif ! $PREVIEW; then
    if [ -n "${KEYFINDER_PLUGIN_BUILD_DIR:-}" ] || [ -d "$PLUGINS/AU/KeyFinderVST.component" ] || [ -d "$PLUGINS/VST3/KeyFinderVST.vst3" ]; then
        echo "Incomplete plugin build: $PLUGINS (both AU and VST3 are required)" >&2
        exit 1
    fi
    echo "Plugins not built; DMG contains the app only. Build them with KeyFinderVST/CMakeLists.txt." >&2
fi
DMG_NAME="KeyFinder-v$VERSION$SUFFIX.dmg"
hdiutil create -volname "KeyFinder $VERSION$SUFFIX" -srcfolder "$STAGING/contents" \
    -format UDZO "$STAGING/$DMG_NAME"
hdiutil verify "$STAGING/$DMG_NAME"
if [ -e "dist/$DMG_NAME" ]; then
    PREVIOUS=$(mktemp -d "$PWD/dist/previous-dmg.XXXXXX")
    mv "dist/$DMG_NAME" "$PREVIOUS/"
fi
mv "$STAGING/$DMG_NAME" dist/
shasum -a 256 "dist/$DMG_NAME"
