#!/bin/bash

# Exit on error
set -e

# Clean up any previous app bundle
echo "Removing previous app bundle if it exists..."
rm -rf Steward.app

echo "Building Steward app in release configuration..."
swift build -c release

# Create app bundle structure
echo "Creating app bundle structure..."
mkdir -p Steward.app/Contents/{MacOS,Resources,Frameworks}

# Copy binary
echo "Copying executable..."
cp -f .build/release/Steward Steward.app/Contents/MacOS/

# Set executable permissions
chmod +x Steward.app/Contents/MacOS/Steward

# Create Info.plist
echo "Creating Info.plist..."
cat > Steward.app/Contents/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Steward</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.apalchys.steward</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Steward</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>This app needs accessibility permissions to capture and replace text.</string>
</dict>
</plist>
EOF

# Copy app icon if it exists
echo "Copying app icon..."
mkdir -p Steward.app/Contents/Resources
if [ -f "AppIcon.icns" ]; then
  cp -f AppIcon.icns Steward.app/Contents/Resources/
  echo "✅ Found and copied app icon"
else
  echo "⚠️ No AppIcon.icns found. Create one using ./create_icon.sh your_image.png"
  touch Steward.app/Contents/Resources/AppIcon.icns
fi

# Add PkgInfo file
echo "Creating PkgInfo file..."
echo "APPL????" > Steward.app/Contents/PkgInfo

# Copy any dependencies if needed
echo "Looking for dependencies..."
# This could be added if there are any external dylibs needed

# Swift libraries aren't needed - they're provided by the system

# Self-sign the app for development
echo "Self-signing the app..."
codesign --force --deep --sign - Steward.app

# Remove quarantine attributes
echo "Removing quarantine attributes..."
xattr -cr Steward.app

echo "App bundle created at: $(pwd)/Steward.app"
echo ""
echo "To run the app, try:"
echo "open Steward.app"
echo ""
echo "If running from Terminal:"
echo "open Steward.app/Contents/MacOS/Steward"
echo ""
echo "To create a distributable package:"
echo "zip -r Steward.app.zip Steward.app"
echo ""
echo "For proper distribution, sign the app with:"
echo "codesign --force --deep --sign \"Developer ID Application: YOUR_NAME\" Steward.app"
