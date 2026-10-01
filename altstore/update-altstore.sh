#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <IPA file>"
    exit 1
fi

IPA="$1"

if [ ! -f "$IPA" ]; then
    echo "✗ IPA not found: $IPA"
    exit 1
fi

TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

echo "=== AltStore Update Analyzer ==="
echo

unzip -q "$IPA" -d "$TMPDIR_WORK"

APP_PATH="$(find "$TMPDIR_WORK/Payload" -maxdepth 1 -type d -name '*.app' | head -1)"

if [ -z "$APP_PATH" ]; then
    echo "✗ .app not found in IPA"
    exit 1
fi

PLIST="$APP_PATH/Info.plist"

APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PLIST" 2>/dev/null || \
            /usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
MIN_IOS="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$PLIST")"
SIZE="$(stat -f%z "$IPA")"

echo "✓ App Name:       $APP_NAME"
echo "✓ Bundle ID:      $BUNDLE_ID"
echo "✓ Version:        $VERSION"
echo "✓ Build:          $BUILD"
echo "✓ Minimum iOS:    $MIN_IOS"
echo "✓ IPA Size:       $SIZE bytes"
echo
echo "IPA:"
echo "  $IPA"
echo
echo "Planned icon:"
echo "  altstore/images/Non-JB-Tsum-${VERSION}.png"
echo
echo "Planned release tag:"
echo "  altstore-tsum-${VERSION}"
echo
# ---- Find App Icon ----
ICON_BASE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles:0' "$PLIST" 2>/dev/null || true)"

ICON_SOURCE=""

if [ -n "$ICON_BASE" ]; then
    ICON_SOURCE="$(find "$APP_PATH" -maxdepth 1 -type f \
        \( -name "${ICON_BASE}.png" \
        -o -name "${ICON_BASE}@2x.png" \
        -o -name "${ICON_BASE}@3x.png" \) \
        | sort | tail -1)"
fi

if [ -z "$ICON_SOURCE" ]; then
    echo "✗ App icon could not be found."
    exit 1
fi

ICON_DEST="altstore/images/Non-JB-Tsum-${VERSION}.png"

echo "✓ Icon source:     $(basename "$ICON_SOURCE")"
echo "✓ Icon target:     $ICON_DEST"

if [ -f "$ICON_DEST" ]; then
    if cmp -s "$ICON_SOURCE" "$ICON_DEST"; then
        echo "✓ Existing icon is identical."
    else
        echo "⚠ Existing icon differs from IPA icon."
        echo "  No file was overwritten."
    fi
else
    cp "$ICON_SOURCE" "$ICON_DEST"
    echo "✓ New icon extracted."
fi

echo
echo "GitHub and source.json were not changed."
