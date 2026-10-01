#!/bin/bash
set -euo pipefail

# ============================================================
# mocoStore - AltStore Classic Automatic Updater
# ============================================================

REPO="iosmoco/mocostore"
BRANCH="main"
EXPECTED_BUNDLE_ID="com.linecorp.LGTMTM"

SOURCE_JSON="altstore/source.json"
IMAGE_DIR="altstore/images"
ICON_PREFIX="Non-JB-Tsum"
RELEASE_PREFIX="altstore-tsum"

RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

die() {
    echo "✗ $*" >&2
    exit 1
}

info() {
    echo "✓ $*"
}

# ------------------------------------------------------------
# Argument
# ------------------------------------------------------------

if [ $# -ne 1 ]; then
    echo "Usage:"
    echo "  $0 <IPA file>"
    echo
    echo "Example:"
    echo "  $0 \"altstore/Non_JBツム_12.10.2_Remove_LIAPP_Alert.ipa\""
    exit 1
fi

IPA="$1"

[ -f "$IPA" ] || die "IPA not found: $IPA"
[ -f "$SOURCE_JSON" ] || die "source.json not found: $SOURCE_JSON"

# ------------------------------------------------------------
# Required commands
# ------------------------------------------------------------

for cmd in git gh unzip python3; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
done

[ -x /usr/libexec/PlistBuddy ] || die "PlistBuddy not found."

# ------------------------------------------------------------
# Repository checks
# ------------------------------------------------------------

git rev-parse --show-toplevel >/dev/null 2>&1 ||
    die "Run this script inside the mocostore Git repository."

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

CURRENT_BRANCH="$(git branch --show-current)"

[ "$CURRENT_BRANCH" = "$BRANCH" ] ||
    die "Current branch is '$CURRENT_BRANCH'. Expected '$BRANCH'."

if [ -n "$(git status --porcelain)" ]; then
    echo "Current Git changes:"
    git status --short
    echo
    die "Working tree is not clean. Commit/stash/remove the changes first."
fi

gh auth status >/dev/null 2>&1 ||
    die "GitHub CLI is not logged in."

# Make sure local main is not behind GitHub.
git fetch origin "$BRANCH" >/dev/null

LOCAL_HEAD="$(git rev-parse "$BRANCH")"
REMOTE_HEAD="$(git rev-parse "origin/$BRANCH")"

[ "$LOCAL_HEAD" = "$REMOTE_HEAD" ] ||
    die "Local $BRANCH differs from origin/$BRANCH. Pull/push first."

# ------------------------------------------------------------
# Temporary extraction
# ------------------------------------------------------------

TMPDIR_WORK="$(mktemp -d)"

cleanup() {
    rm -rf "$TMPDIR_WORK"
}

trap cleanup EXIT

echo
echo "=========================================="
echo " AltStore Automatic Update"
echo "=========================================="
echo

echo "Analyzing IPA..."

unzip -q "$IPA" -d "$TMPDIR_WORK"

APP_PATH="$(find "$TMPDIR_WORK/Payload" -maxdepth 1 -type d -name '*.app' | head -1)"

[ -n "$APP_PATH" ] || die ".app not found inside IPA."

PLIST="$APP_PATH/Info.plist"

[ -f "$PLIST" ] || die "Info.plist not found."

APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PLIST" 2>/dev/null || \
            /usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
MIN_IOS="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$PLIST")"
SIZE="$(stat -f%z "$IPA")"

info "App Name:       $APP_NAME"
info "Bundle ID:      $BUNDLE_ID"
info "Version:        $VERSION"
info "Build:          $BUILD"
info "Minimum iOS:    $MIN_IOS"
info "IPA Size:       $SIZE bytes"

echo

# ------------------------------------------------------------
# Safety checks
# ------------------------------------------------------------

[ "$BUNDLE_ID" = "$EXPECTED_BUNDLE_ID" ] ||
    die "Unexpected Bundle ID: $BUNDLE_ID"

SOURCE_BUNDLE_ID="$(
python3 - "$SOURCE_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

print(data["apps"][0]["bundleIdentifier"])
PY
)"

[ "$SOURCE_BUNDLE_ID" = "$BUNDLE_ID" ] ||
    die "Bundle ID does not match source.json."

if VERSION="$VERSION" SOURCE_JSON="$SOURCE_JSON" python3 <<'PY'
import json
import os
import sys

with open(os.environ["SOURCE_JSON"], encoding="utf-8") as f:
    data = json.load(f)

version = os.environ["VERSION"]

if any(v.get("version") == version for v in data["apps"][0]["versions"]):
    sys.exit(0)

sys.exit(1)
PY
then
    die "Version $VERSION already exists in source.json."
fi

TAG="${RELEASE_PREFIX}-${VERSION}"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    die "GitHub Release already exists: $TAG"
fi

# ------------------------------------------------------------
# Find icon
# ------------------------------------------------------------

ICON_BASE="$(
    /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles:0' \
    "$PLIST" 2>/dev/null || true
)"

[ -n "$ICON_BASE" ] || die "CFBundleIconFiles could not be read."

ICON_SOURCE="$(
    find "$APP_PATH" -maxdepth 1 -type f \
        \( -name "${ICON_BASE}.png" \
        -o -name "${ICON_BASE}@2x.png" \
        -o -name "${ICON_BASE}@3x.png" \) \
        | sort | tail -1
)"

[ -n "$ICON_SOURCE" ] || die "App icon could not be found."

mkdir -p "$IMAGE_DIR"

ICON_DEST="${IMAGE_DIR}/${ICON_PREFIX}-${VERSION}.png"
ICON_URL="${RAW_BASE}/${ICON_DEST}"

if [ -e "$ICON_DEST" ]; then
    die "Icon already exists: $ICON_DEST"
fi

info "Icon source:     $(basename "$ICON_SOURCE")"
info "Icon target:     $ICON_DEST"

echo

# ------------------------------------------------------------
# Summary before publishing
# ------------------------------------------------------------

echo "Update plan:"
echo "  Version:      $VERSION"
echo "  Build:        $BUILD"
echo "  Release tag:  $TAG"
echo "  Icon:         $ICON_DEST"
echo "  IPA:          $(basename "$IPA")"
echo

# ------------------------------------------------------------
# Extract icon
# ------------------------------------------------------------

cp "$ICON_SOURCE" "$ICON_DEST"
info "New icon extracted."

# ------------------------------------------------------------
# Create GitHub Release and upload IPA
# ------------------------------------------------------------

echo
echo "Creating GitHub Release..."

if ! gh release create "$TAG" "$IPA" \
    --repo "$REPO" \
    --title "Non-JBツム $VERSION" \
    --notes "AltStore release $VERSION"; then

    rm -f "$ICON_DEST"
    die "GitHub Release creation failed."
fi

info "Release created: $TAG"

# ------------------------------------------------------------
# Obtain ACTUAL GitHub asset URL
# ------------------------------------------------------------

IPA_BASENAME="$(basename "$IPA")"

ASSET_URL="$(
    gh release view "$TAG" \
        --repo "$REPO" \
        --json assets \
        --jq '.assets[0].url'
)"

if [ -z "$ASSET_URL" ] || [ "$ASSET_URL" = "null" ]; then
    echo
    echo "⚠ Release was created, but its asset URL could not be obtained."
    echo "  Release tag: $TAG"
    echo "  source.json has NOT been modified."
    exit 1
fi

info "GitHub asset URL obtained:"
echo "  $ASSET_URL"

# ------------------------------------------------------------
# Backup source.json for rollback
# ------------------------------------------------------------

SOURCE_BACKUP="$TMPDIR_WORK/source.json.backup"
cp "$SOURCE_JSON" "$SOURCE_BACKUP"

# ------------------------------------------------------------
# Update source.json
# ------------------------------------------------------------

VERSION="$VERSION" \
BUILD="$BUILD" \
MIN_IOS="$MIN_IOS" \
SIZE="$SIZE" \
ASSET_URL="$ASSET_URL" \
ICON_URL="$ICON_URL" \
SOURCE_JSON="$SOURCE_JSON" \
python3 <<'PY'
import datetime
import json
import os

path = os.environ["SOURCE_JSON"]

with open(path, encoding="utf-8") as f:
    data = json.load(f)

app = data["apps"][0]

version = os.environ["VERSION"]

if any(v.get("version") == version for v in app["versions"]):
    raise SystemExit(f"Version {version} already exists.")

entry = {
    "version": version,
    "buildVersion": os.environ["BUILD"],
    "date": datetime.date.today().isoformat(),
    "localizedDescription": f"Update to {version}.",
    "downloadURL": os.environ["ASSET_URL"],
    "size": int(os.environ["SIZE"]),
    "minOSVersion": os.environ["MIN_IOS"]
}

# Newest version first.
app["versions"].insert(0, entry)

# Use the newest app icon.
app["iconURL"] = os.environ["ICON_URL"]

# Keep source icon synchronized with latest app icon.
data["iconURL"] = os.environ["ICON_URL"]

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

# ------------------------------------------------------------
# Validate JSON
# ------------------------------------------------------------

if ! python3 -m json.tool "$SOURCE_JSON" >/dev/null; then
    cp "$SOURCE_BACKUP" "$SOURCE_JSON"
    rm -f "$ICON_DEST"
    die "source.json validation failed. Local changes rolled back."
fi

info "source.json updated and validated."

# ------------------------------------------------------------
# Show new version
# ------------------------------------------------------------

echo
echo "New source entry:"

VERSION="$VERSION" SOURCE_JSON="$SOURCE_JSON" python3 <<'PY'
import json
import os

with open(os.environ["SOURCE_JSON"], encoding="utf-8") as f:
    data = json.load(f)

version = os.environ["VERSION"]

for item in data["apps"][0]["versions"]:
    if item["version"] == version:
        print(json.dumps(item, ensure_ascii=False, indent=2))
        break
PY

# ------------------------------------------------------------
# Commit and push
# ------------------------------------------------------------

echo
echo "Committing source update..."

git add "$SOURCE_JSON" "$ICON_DEST"

git commit -m "Update AltStore app to ${VERSION}"

if ! git push origin "$BRANCH"; then
    echo
    echo "⚠ Git commit succeeded but push failed."
    echo "  The GitHub Release exists."
    echo "  Fix the Git problem, then run:"
    echo
    echo "    git push origin $BRANCH"
    echo
    exit 1
fi

info "GitHub repository updated."

# ------------------------------------------------------------
# Verify published source
# ------------------------------------------------------------

echo
echo "Verifying published source..."

SOURCE_PUBLIC_URL="${RAW_BASE}/${SOURCE_JSON}"

if command -v curl >/dev/null 2>&1; then
    for attempt in 1 2 3 4 5; do
        if curl -fsSL "$SOURCE_PUBLIC_URL" |
            python3 -m json.tool >/dev/null 2>&1; then

            info "Published source.json is reachable."
            break
        fi

        if [ "$attempt" -eq 5 ]; then
            echo "⚠ Push succeeded, but public source verification timed out."
        else
            sleep 2
        fi
    done
fi

echo
echo "=========================================="
echo " Update completed successfully"
echo "=========================================="
echo
echo "App:          $APP_NAME"
echo "Version:      $VERSION"
echo "Build:        $BUILD"
echo "Release:      $TAG"
echo "Icon:         $ICON_URL"
echo "Download URL: $ASSET_URL"
echo
echo "AltStore Source:"
echo "  $SOURCE_PUBLIC_URL"
echo
