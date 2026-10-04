#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
BUILD_CPU="$(uname -m)"
mkdir -p "$PROJECT_DIR/.build/swift-cache" "$PROJECT_DIR/Assets"
xcrun swiftc -swift-version 5 -module-cache-path "$PROJECT_DIR/.build/swift-cache" -target "$BUILD_CPU-apple-macosx14.0" \
  "$PROJECT_DIR/Sources/MakeIcon.swift" -framework AppKit -o "$PROJECT_DIR/.build/MakeIcon"
"$PROJECT_DIR/.build/MakeIcon" "$PROJECT_DIR/.build/AppIcon.iconset"
iconutil -c icns "$PROJECT_DIR/.build/AppIcon.iconset" -o "$PROJECT_DIR/AppIcon.icns"
cp "$PROJECT_DIR/.build/AppIcon.iconset/icon_512x512@2x.png" "$PROJECT_DIR/Assets/AppIcon-1024.png"
