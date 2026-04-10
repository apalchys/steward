#!/bin/bash

# Exit on error
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

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

# Copy Info.plist from the repository so permission keys stay in sync with source.
echo "Copying Info.plist..."
cp -f Info.plist Steward.app/Contents/Info.plist
plutil -lint Steward.app/Contents/Info.plist

# Copy app icon if it exists
echo "Copying app icon..."
mkdir -p Steward.app/Contents/Resources
if [ -f "AppIcon.icns" ]; then
  cp -f AppIcon.icns Steward.app/Contents/Resources/
  echo "✅ Found and copied app icon"
else
  echo "⚠️ No AppIcon.icns found. Create one using \"make icon\""
  touch Steward.app/Contents/Resources/AppIcon.icns
fi

echo "Copying status bar icon..."
if [ -f "Assets/status-icon.png" ]; then
  cp -f Assets/status-icon.png Steward.app/Contents/Resources/status-icon.png
  echo "✅ Found and copied Assets/status-icon.png"
elif [ -f "status-icon.png" ]; then
  cp -f status-icon.png Steward.app/Contents/Resources/status-icon.png
  echo "✅ Found and copied status-icon.png"
elif [ -f "statusicon.png" ]; then
  cp -f statusicon.png Steward.app/Contents/Resources/status-icon.png
  echo "✅ Found and copied legacy statusicon.png as status-icon.png"
else
  echo "⚠️ No status-icon.png found. Using SF Symbol fallback for status bar."
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
codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" Steward.app

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
