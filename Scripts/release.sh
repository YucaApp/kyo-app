#!/bin/bash
# Builds Kyo for Apple silicon and Intel and packs it as dist/Kyo-<version>.dmg,
# ready to attach to a GitHub release. The version comes from Support/Info.plist.
#
# The app is signed with whatever identity Scripts/build-app.sh finds. Signing
# every release with the same identity is what lets people who update keep
# their calendar permission. Without an Apple Developer ID the download is not
# notarized, and macOS makes people confirm the first launch (see the README).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)"
DMG="dist/Kyo-$VERSION.dmg"

KYO_UNIVERSAL=1 Scripts/build-app.sh release

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto build/Kyo.app "$STAGE/Kyo.app"
# So installing is one drag.
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "$DMG"
hdiutil create -quiet -volname "Kyo $VERSION" -srcfolder "$STAGE" -format UDZO "$DMG"

echo "Built $DMG"
shasum -a 256 "$DMG"
