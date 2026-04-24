#!/bin/bash

# Build script for KeyFinder macOS app
set -e

echo "Building KeyFinder..."

# Build universal binary (Intel + Apple Silicon)
echo "Building for Intel (x86_64)..."
swift build -c release --arch x86_64

echo "Building for Apple Silicon (arm64)..."
swift build -c release --arch arm64

echo "Creating universal binary..."
# Create universal binary using lipo
mkdir -p .build/universal
lipo -create \
    .build/x86_64-apple-macosx/release/KeyFinder \
    .build/arm64-apple-macosx/release/KeyFinder \
    -output .build/universal/KeyFinder

# Create app bundle structure
APP_NAME="KeyFinder"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Clean and create directories
rm -rf build
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy universal executable
cp .build/universal/KeyFinder "${MACOS_DIR}/"

# Copy app icon if it exists
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "${RESOURCES_DIR}/"
    echo "✓ App icon added"
fi

# Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>KeyFinder</string>
    <key>CFBundleIdentifier</key>
    <string>com.keyfinder.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>KeyFinder</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.9</string>
    <key>CFBundleVersion</key>
    <string>9</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Audio File</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.audio</string>
                <string>public.mp3</string>
                <string>com.microsoft.waveform-audio</string>
                <string>com.apple.m4a-audio</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# Create PkgInfo
echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo "App bundle created at: ${APP_DIR}"

# Check for signing identity
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F '"' '{print $2}')

if [ -z "$IDENTITY" ]; then
    echo ""
    echo "⚠️  No Developer ID certificate found."
    echo "Attempting to sign with ad-hoc signature (for local use only)..."
    codesign --force --deep --sign - "${APP_DIR}"
    echo "✅ App signed with ad-hoc signature"
    echo "⚠️  This app will only run on your machine"
else
    echo ""
    echo "Found signing identity: ${IDENTITY}"
    echo "Signing app..."
    codesign --force --deep --sign "${IDENTITY}" --options runtime "${APP_DIR}"
    echo "✅ App signed with Developer ID"
fi

echo ""
echo "🎉 Build complete!"
echo "App location: ${APP_DIR}"

# Create DMG automatically
echo ""
echo "Creating DMG..."
./make-dmg.sh

echo ""
echo "✅ DMG created: KeyFinder-v1.9.dmg"
