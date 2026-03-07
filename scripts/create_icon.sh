#!/bin/bash

# This script creates an .icns file from a source image
# Usage: ./scripts/create_icon.sh input.png

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

if [ $# -ne 1 ]; then
  echo "Usage: $0 input.png"
  echo "Please provide a PNG image file (preferably 1024x1024)"
  exit 1
fi

SOURCE_IMAGE="$1"
ICONSET_NAME="AppIcon.iconset"

# Check if source image exists
if [ ! -f "$SOURCE_IMAGE" ]; then
  echo "Error: Source image '$SOURCE_IMAGE' not found"
  exit 1
fi

# Create temporary iconset directory
mkdir -p "$ICONSET_NAME"

# Generate icons at various sizes
echo "Generating icons at various sizes..."
sips -z 16 16     "$SOURCE_IMAGE" --out "$ICONSET_NAME/icon_16x16.png"
sips -z 32 32     "$SOURCE_IMAGE" --out "$ICONSET_NAME/icon_16x16@2x.png"
sips -z 32 32     "$SOURCE_IMAGE" --out "$ICONSET_NAME/icon_32x32.png"
sips -z 64 64     "$SOURCE_IMAGE" --out "$ICONSET_NAME/icon_32x32@2x.png"
sips -z 128 128   "$SOURCE_IMAGE" --out "$ICONSET_NAME/icon_128x128.png"
sips -z 256 256   "$SOURCE_IMAGE" --out "$ICONSET_NAME/icon_128x128@2x.png"
sips -z 256 256   "$SOURCE_IMAGE" --out "$ICONSET_NAME/icon_256x256.png"
sips -z 512 512   "$SOURCE_IMAGE" --out "$ICONSET_NAME/icon_256x256@2x.png"
sips -z 512 512   "$SOURCE_IMAGE" --out "$ICONSET_NAME/icon_512x512.png"
sips -z 1024 1024 "$SOURCE_IMAGE" --out "$ICONSET_NAME/icon_512x512@2x.png"

# Create .icns file from the iconset
echo "Converting iconset to .icns file..."
iconutil -c icns "$ICONSET_NAME"

# Clean up
rm -rf "$ICONSET_NAME"

echo "Icon created successfully: AppIcon.icns"
echo "Use this icon in your scripts/build.sh script"
