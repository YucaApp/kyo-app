#!/bin/bash
# Builds build/Kyo.app from the Swift package.
# Usage: Scripts/build-app.sh [debug|release]   (default: release)
#        KYO_UNIVERSAL=1 Scripts/build-app.sh   (Apple silicon + Intel)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Kyo.app"

# KYO_UNIVERSAL=1 builds for both Apple silicon and Intel, for a release.
ARCHS=""
if [ -n "${KYO_UNIVERSAL:-}" ]; then ARCHS="--arch arm64 --arch x86_64"; fi

# shellcheck disable=SC2086  # ARCHS is a list of flags, split on purpose
swift build -c "$CONFIG" --product Kyo $ARCHS
# shellcheck disable=SC2086
BIN="$(swift build -c "$CONFIG" $ARCHS --show-bin-path)/Kyo"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kyo"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Regenerate with: swift Scripts/make-icon.swift Support/AppIcon-source.png Support/Kyo.icns
cp Support/Kyo.icns "$APP/Contents/Resources/Kyo.icns"

# A signing identity keeps the calendar permission across rebuilds: an Apple
# one if there is one, else the local one from Scripts/make-signing-cert.sh.
# With neither the app is ad-hoc signed and macOS asks again after each build.
IDENTITY="${KYO_SIGN_IDENTITY:-$(security find-identity -v -p codesigning |
    awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }')}"
if [ -z "$IDENTITY" ] && security find-certificate -c "Kyo Local Signing" >/dev/null 2>&1; then
    IDENTITY="Kyo Local Signing"
fi
# The hardened runtime stops other software loading code into Kyo and so
# borrowing its calendar access; the entitlement is what lets Kyo itself read
# the calendar under it.
codesign --force --options runtime --entitlements Support/Kyo.entitlements \
    --sign "${IDENTITY:--}" --identifier io.bagels.kyo "$APP"

echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"
