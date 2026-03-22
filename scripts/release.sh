#!/bin/bash
# release.sh — Build, notarize, package, and publish Tenvy to GitHub
#
# Usage:
#   ./scripts/release.sh 1.0.0
#
# Requirements:
#   brew install create-dmg
#   gh auth login (GitHub CLI)
#   Apple Developer account configured in Xcode

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>  (e.g. $0 1.0.0)"
  exit 1
fi

SCHEME="Tenvy"
PROJECT="Tenvy.xcodeproj"
ARCHIVE_PATH="build/Tenvy.xcarchive"
EXPORT_PATH="build/export"
APP_PATH="$EXPORT_PATH/Tenvy.app"
DMG_PATH="build/Tenvy-$VERSION.dmg"

echo "▶ Cleaning build folder..."
rm -rf build
mkdir -p build

echo "▶ Archiving $SCHEME $VERSION..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  MARKETING_VERSION="$VERSION" \
  | xcpretty 2>/dev/null || true

echo "▶ Exporting (Direct Distribution / notarization)..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$EXPORT_PATH"

echo "▶ Creating DMG..."
create-dmg \
  --volname "Tenvy $VERSION" \
  --volicon "Tenvy/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" \
  --window-size 600 380 \
  --icon-size 128 \
  --icon "Tenvy.app" 160 190 \
  --app-drop-link 440 190 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH"

echo "▶ Creating GitHub release v$VERSION..."
gh release create "v$VERSION" "$DMG_PATH" \
  --title "Tenvy v$VERSION" \
  --notes "## Tenvy v$VERSION

### Installation
1. Download \`Tenvy-$VERSION.dmg\`
2. Open the DMG and drag **Tenvy** to your Applications folder
3. Launch Tenvy from Applications

### Requirements
- macOS 14.0 or later
- [Claude Code CLI](https://docs.anthropic.com/claude-code) installed"

echo "✓ Released Tenvy v$VERSION"
echo "  DMG: $DMG_PATH"
echo "  GitHub: https://github.com/Rostmen/ClaudeGUI/releases/tag/v$VERSION"
