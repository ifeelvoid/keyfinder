#!/bin/bash
# Builds the keyfinder-mcp server (universal) and the ChatGPT desktop plugin ZIP.
# Outputs:
#   .build/universal/keyfinder-mcp      bundled into KeyFinder.app by build-app.sh
#   plugin/keyfinder/bin/keyfinder-mcp  plugin copy (git-ignored)
#   build/KeyFinder-plugin.zip          upload package for the plugin portal
set -euo pipefail
cd "$(dirname "$0")"

PKG="Sources/KeyFinderMCP"
OUT=".build/universal"
PLUGIN_DIR="plugin/keyfinder"

echo "Building keyfinder-mcp (x86_64 + arm64)..."
SDK="${KEYFINDER_SDK:-$(xcrun --show-sdk-path)}"
SLICES=()
for ARCH in x86_64 arm64; do
    EXTRA=()
    # Same as build-app.sh: newer Command Line Tools ship arm64-only Swift compatibility
    # archives; the macOS 12+ runtime already provides what the x86_64 slice needs.
    [ "$ARCH" != x86_64 ] || EXTRA=(-Xswiftc -runtime-compatibility-version -Xswiftc none)
    # Separate scratch paths so the two slices cannot overwrite each other.
    ARGS=(--package-path "$PKG" --scratch-path "$PKG/.build-$ARCH" --build-system native -c release
          --arch "$ARCH" --sdk "$SDK" ${EXTRA[@]+"${EXTRA[@]}"})
    swift build "${ARGS[@]}"
    SLICES+=("$(swift build "${ARGS[@]}" --show-bin-path)/keyfinder-mcp")
done
mkdir -p "$OUT"
lipo -create "${SLICES[@]}" -output "$OUT/keyfinder-mcp"
for arch in arm64 x86_64; do
    lipo "$OUT/keyfinder-mcp" -verify_arch "$arch" || { echo "keyfinder-mcp is missing $arch"; exit 1; }
done

# Developer ID + hardened runtime when available; otherwise ad-hoc, and say so loudly.
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F '"' '{print $2}' || true)
if [ -n "$IDENTITY" ]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$OUT/keyfinder-mcp"
    echo "✓ keyfinder-mcp signed with Developer ID"
else
    codesign --force --sign - "$OUT/keyfinder-mcp"
    echo "⚠️  keyfinder-mcp ad-hoc signed: other Macs may block it until it is signed with a Developer ID and notarized"
fi
# Server, plugin and app versions are separate strings; refuse to ship them out of step.
APP_VERSION=$(sed -n 's/^VERSION=//p' build-app.sh)
"$OUT/keyfinder-mcp" --version | grep -qx "keyfinder-mcp $APP_VERSION" \
    || { echo "keyfinder-mcp --version does not match build-app.sh VERSION=$APP_VERSION"; exit 1; }
grep -q "\"version\": \"$APP_VERSION\"" "$PLUGIN_DIR/.codex-plugin/plugin.json" \
    || { echo "plugin.json version does not match build-app.sh VERSION=$APP_VERSION"; exit 1; }

mkdir -p "$PLUGIN_DIR/bin" build
cp "$OUT/keyfinder-mcp" "$PLUGIN_DIR/bin/keyfinder-mcp"
rm -f build/KeyFinder-plugin.zip
(cd "$PLUGIN_DIR" && zip -qr -X ../../build/KeyFinder-plugin.zip . -x '*.DS_Store')
echo "✓ Plugin package: build/KeyFinder-plugin.zip"
