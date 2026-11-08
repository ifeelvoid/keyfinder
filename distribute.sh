#!/bin/bash
# Package the current app. Developer ID notarization is an explicit optional step.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
SKIP_BUILD=false
PREVIEW=false
NOTARIZE=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --skip-build) SKIP_BUILD=true; shift ;;
        --apple-silicon-preview) PREVIEW=true; shift ;;
        --notarize) NOTARIZE=true; shift ;;
        --help|-h)
            echo 'Usage: distribute.sh [--skip-build] [--apple-silicon-preview] [--notarize]'
            echo '--notarize requires SIGNING_IDENTITY and NOTARYTOOL_PROFILE.'
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
if $NOTARIZE; then
    [ -n "${SIGNING_IDENTITY:-}" ] && [ "$SIGNING_IDENTITY" != - ] || { echo '--notarize requires a configured Developer ID SIGNING_IDENTITY.' >&2; exit 2; }
    [ -n "${NOTARYTOOL_PROFILE:-}" ] || { echo '--notarize requires NOTARYTOOL_PROFILE (an existing keychain profile).' >&2; exit 2; }
fi
APP="$ROOT/dist/KeyFinder.app"
SUFFIX=""
if $PREVIEW; then APP="$ROOT/dist/KeyFinder-AppleSilicon-preview.app"; SUFFIX=-AppleSilicon-preview; fi
if ! $SKIP_BUILD; then
    if $PREVIEW; then bash "$ROOT/build-app.sh" --apple-silicon-preview; else bash "$ROOT/build-app.sh"; fi
fi
[ -d "$APP" ] || { echo "Missing current app: $APP" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
# A version becomes a filename component, so reject path separators and whitespace.
[[ "$VERSION" =~ ^[0-9][0-9A-Za-z._-]*$ ]] || { echo 'Invalid app version in Info.plist.' >&2; exit 1; }
if $NOTARIZE; then
    codesign --force --deep --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
        --entitlements "$ROOT/entitlements.plist" "$APP"
    codesign --verify --deep --strict "$APP"
fi
PACKAGE_OPTIONS=(--skip-build)
if $PREVIEW; then PACKAGE_OPTIONS+=(--apple-silicon-preview); fi
bash "$ROOT/make-dmg.sh" "${PACKAGE_OPTIONS[@]}"
DMG="$ROOT/dist/KeyFinder-v$VERSION$SUFFIX.dmg"
[ -f "$DMG" ] || { echo "Missing packaged DMG: $DMG" >&2; exit 1; }
if $NOTARIZE; then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature "$DMG"
fi
echo "Distribution artifact: $DMG"
shasum -a 256 "$DMG"
