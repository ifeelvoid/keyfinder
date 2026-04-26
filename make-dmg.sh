#!/bin/bash
# Creates a distributable DMG with install instructions and VST/AU plugins
set -e

APP_NAME="KeyFinder"
VERSION="2.0"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
STAGING="build/dmg-staging"
BUILD_DIR=".build/arm64-apple-macosx/release"

# Build the app first
swift build -c release

# Create staging folder
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
mkdir -p "${STAGING}/${APP_NAME}.app/Contents/MacOS"
mkdir -p "${STAGING}/${APP_NAME}.app/Contents/Resources"
mkdir -p "${STAGING}/VST3"
mkdir -p "${STAGING}/AU"

# Copy the executable
cp "${BUILD_DIR}/${APP_NAME}" "${STAGING}/${APP_NAME}.app/Contents/MacOS/"

# Copy VST3 plugin if it exists
if [ -d "KeyFinderVST/Builds/MacOSX/build/Release/KeyFinderVST.vst3" ]; then
    cp -R "KeyFinderVST/Builds/MacOSX/build/Release/KeyFinderVST.vst3" "${STAGING}/VST3/"
    echo "✓ VST3 plugin added"
fi

# Copy AU plugin if it exists
if [ -d "KeyFinderVST/Builds/MacOSX/build/Release/KeyFinderVST.component" ]; then
    cp -R "KeyFinderVST/Builds/MacOSX/build/Release/KeyFinderVST.component" "${STAGING}/AU/"
    echo "✓ AU plugin added"
fi

# Create Info.plist
cat > "${STAGING}/${APP_NAME}.app/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>KeyFinder</string>
    <key>CFBundleIdentifier</key>
    <string>com.keyfinder.app</string>
    <key>CFBundleName</key>
    <string>KeyFinder</string>
    <key>CFBundleVersion</key>
    <string>2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# Copy app icon if it exists
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "${STAGING}/${APP_NAME}.app/Contents/Resources/"
    echo "✓ App icon added"
fi

# Copy Resources if they exist
if [ -d "Sources/KeyFinder/Resources" ]; then
    cp -R "Sources/KeyFinder/Resources/"* "${STAGING}/${APP_NAME}.app/Contents/Resources/" 2>/dev/null || true
fi

# Create install instructions
cat > "${STAGING}/HOW TO INSTALL.txt" << 'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  KeyFinder v2.0 — Installation Guide
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INSTALLING THE APP
─────────────────
  1. Drag KeyFinder.app into your Applications folder.

  2. On first launch, right-click KeyFinder.app → Open
     (This is required because the app is not from the Mac App Store)

INSTALLING PLUGINS
──────────────────
  VST3 Plugin (for Ableton, FL Studio, Logic, etc.):
    → Copy KeyFinderVST.vst3 to:
      ~/Library/Audio/Plug-Ins/VST3/

  AU Plugin (for Logic, GarageBand, etc.):
    → Copy KeyFinderVST.component to:
      ~/Library/Audio/Plug-Ins/Components/

  After copying, restart your DAW to see the plugin.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Requires macOS 10.15 or later
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

# Create a symlink to /Applications for easy drag-install
ln -s /Applications "${STAGING}/Applications"

# Build the DMG from staging folder
rm -f "${DMG_NAME}"
rm -f "build/${DMG_NAME}"
hdiutil create \
    -volname "${APP_NAME} v${VERSION}" \
    -srcfolder "${STAGING}" \
    -ov -format UDZO \
    "${DMG_NAME}"

# Also copy to build folder
cp "${DMG_NAME}" "build/"

# Clean up staging
rm -rf "${STAGING}"

echo ""
echo "✅ Done: ${DMG_NAME}"
echo "   Size: $(du -sh "${DMG_NAME}" | cut -f1)"