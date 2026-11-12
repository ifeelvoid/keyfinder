#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# One source bundle for local testing and the distributable DMG.
VERSION=3.0.1
ARCHES=(x86_64 arm64)
APP_NAME=KeyFinder
for OPTION in "$@"; do
    case "$OPTION" in
        --apple-silicon-preview) ARCHES=(arm64); APP_NAME=KeyFinder-AppleSilicon-preview ;;
        *) echo "Unknown option: $OPTION" >&2; exit 2 ;;
    esac
done
SWIFT_OPTIONS=()
if [ -n "${KEYFINDER_SWIFT_BUILD_DIR:-}" ]; then
    SWIFT_OPTIONS+=(--scratch-path "$KEYFINDER_SWIFT_BUILD_DIR")
fi
BIN_DIRS=()
# Opt in only when an enclosing sandbox prevents SwiftPM's nested sandbox startup.
if [ "${KEYFINDER_DISABLE_SWIFTPM_SANDBOX:-0}" = 1 ]; then
    SWIFT_OPTIONS+=(--disable-sandbox)
fi
mkdir -p dist
STAGING=$(mktemp -d "$PWD/dist/app.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/KeyFinder.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for ARCH in "${ARCHES[@]}"; do
    EXTRA=()
    # Newer Command Line Tools ship arm64-only Swift compatibility archives; the macOS 12+
    # runtime already provides what the x86_64 slice needs.
    [ "$ARCH" != x86_64 ] || EXTRA=(-Xswiftc -runtime-compatibility-version -Xswiftc none)
    swift build ${SWIFT_OPTIONS[@]+"${SWIFT_OPTIONS[@]}"} --build-system native -c release --arch "$ARCH" \
        --sdk "${KEYFINDER_SDK:-$(xcrun --show-sdk-path)}" ${EXTRA[@]+"${EXTRA[@]}"}
    BIN_DIRS+=("$(swift build ${SWIFT_OPTIONS[@]+"${SWIFT_OPTIONS[@]}"} --build-system native -c release --arch "$ARCH" \
        --sdk "${KEYFINDER_SDK:-$(xcrun --show-sdk-path)}" --show-bin-path)")
done
if [ "${#ARCHES[@]}" = 2 ]; then
    lipo -create "${BIN_DIRS[0]}/KeyFinder" \
        "${BIN_DIRS[1]}/KeyFinder" -output "$APP/Contents/MacOS/KeyFinder"
else
    cp "${BIN_DIRS[0]}/KeyFinder" "$APP/Contents/MacOS/KeyFinder"
fi
for ARCH in "${ARCHES[@]}"; do lipo "$APP/Contents/MacOS/KeyFinder" -verify_arch "$ARCH"; done
cp AppIcon.icns "$APP/Contents/Resources/"
# Preserve SwiftPM resources alongside the bundle, as expected by generated accessors.
RESOURCE_BIN=${BIN_DIRS[${#BIN_DIRS[@]}-1]}
for RESOURCE in "$RESOURCE_BIN"/*.bundle; do
    [ ! -d "$RESOURCE" ] || cp -R "$RESOURCE" "$APP/"
done
cp packaging/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
if [ -n "${SIGNING_IDENTITY:-}" ]; then
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
        --entitlements entitlements.plist "$APP"
else
    codesign --force --sign - "$APP"
    echo "Local ad-hoc signature; Developer ID signing and notarization required for public distribution."
fi
codesign --verify --deep --strict "$APP"
# Keep prior artifacts recoverable. Never erase the tracked legacy build/ directory.
if [ -e "dist/$APP_NAME.app" ]; then
    PREVIOUS=$(mktemp -d "$PWD/dist/previous-app.XXXXXX")
    mv "dist/$APP_NAME.app" "$PREVIOUS/"
fi
mv "$APP" "dist/$APP_NAME.app"
echo "Built: $PWD/dist/$APP_NAME.app (macOS 12+, architectures: ${ARCHES[*]})"
