#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Steward"
DMG_NAME="${APP_NAME}.dmg"
STAGING_DIR=$(mktemp -d)

# Copy app and create Applications symlink
cp -R "${APP_NAME}.app" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME"

# Cleanup
rm -rf "$STAGING_DIR"

echo "Created: $DMG_NAME"
