#!/bin/bash
# Builds the Release app signed with Developer ID, notarizes it and packages it
# as a zip and a dmg.
#
#   scripts/release/package.sh <version>
#
# <version> must match MARKETING_VERSION in project.yml. The app is signed with
# the identity and team in App/Config/Signing.local.xcconfig, which must be a
# Developer ID Application certificate.
#
# Environment:
#   SIGN_IDENTITY    identity for the dmg (default "Developer ID Application"); a SHA-1
#                    hash picks one certificate when the keychain holds several
#   NOTARY_PROFILE   notarytool keychain profile (xcrun notarytool store-credentials), or
#   NOTARY_APPLE_ID, NOTARY_PASSWORD, NOTARY_TEAM_ID
#                    Apple ID, app-specific password and team for notarytool
#   NOTARIZE=0       skip notarization (local tests only)
#
# Output goes to build/dist-<version> (or $OUT_DIR), which must not exist yet:
# Pinxel-<version>.zip, Pinxel-<version>.dmg and SHA256SUMS.txt.
set -euo pipefail

VERSION=${1:?usage: scripts/release/package.sh <version>}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

OUT=${OUT_DIR:-build/dist-$VERSION}
DERIVED=build/release-$VERSION
SIGN_IDENTITY=${SIGN_IDENTITY:-Developer ID Application}
NOTARIZE=${NOTARIZE:-1}

fail() { echo "error: $*" >&2; exit 1; }

[ -e "$OUT" ] && fail "$OUT already exists; remove it or set OUT_DIR"

if [ "$NOTARIZE" = 1 ]; then
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    elif [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ]; then
        NOTARY_ARGS=(--apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID")
    else
        fail "set NOTARY_PROFILE or NOTARY_APPLE_ID, NOTARY_PASSWORD and NOTARY_TEAM_ID (or NOTARIZE=0)"
    fi
fi

notarize() {
    [ "$NOTARIZE" = 1 ] || return 0
    echo "Notarizing $(basename "$1")…"
    xcrun notarytool submit "$1" "${NOTARY_ARGS[@]}" --wait --timeout 30m \
        --output-format json > "$STAGE/notary.json" || true
    if ! grep -q '"status" *: *"Accepted"' "$STAGE/notary.json"; then
        cat "$STAGE/notary.json" >&2
        ID=$(sed -nE 's/.*"id" *: *"([^"]+)".*/\1/p' "$STAGE/notary.json" | head -1)
        [ -n "$ID" ] && xcrun notarytool log "$ID" "${NOTARY_ARGS[@]}" >&2 || true
        fail "notarization of $(basename "$1") was not accepted"
    fi
}

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

xcodegen generate >/dev/null
xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" \
    OTHER_CODE_SIGN_FLAGS=--timestamp build | tail -1

APP=$DERIVED/Build/Products/Release/Pinxel.app
BUILT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
[ "$BUILT" = "$VERSION" ] || fail "the app is version $BUILT, not $VERSION (update MARKETING_VERSION in project.yml)"

for bundle in "$APP" "$APP"/Contents/Resources/PinxelKit_*.bundle; do
    for language in it de fr; do
        [ -n "$(find "$bundle" -maxdepth 3 -type d -name "$language.lproj" -print -quit)" ] \
            || fail "$(basename "$bundle") has no $language translation"
    done
done

codesign --verify --deep --strict "$APP"
SIGNATURE=$(codesign -dv --verbose=2 "$APP" 2>&1)
grep -q "^Authority=Developer ID Application" <<<"$SIGNATURE" \
    || fail "the app is not signed with a Developer ID Application identity"
grep -q "^Timestamp=" <<<"$SIGNATURE" || fail "the app signature has no secure timestamp"
grep -q "runtime" <<<"$SIGNATURE" || fail "the app is not built with the hardened runtime"
ENTITLEMENTS=$(codesign -d --entitlements - "$APP" 2>/dev/null || true)
grep -q "get-task-allow" <<<"$ENTITLEMENTS" && fail "the app has the get-task-allow entitlement (debug signature)"

# The app is notarized on its own first, so the copies in the zip and in the
# dmg both carry the ticket and open offline.
ditto -c -k --keepParent "$APP" "$STAGE/Pinxel-notarize.zip"
notarize "$STAGE/Pinxel-notarize.zip"
[ "$NOTARIZE" = 1 ] && xcrun stapler staple "$APP"

mkdir -p "$OUT"
ditto -c -k --keepParent "$APP" "$OUT/Pinxel-$VERSION.zip"

mkdir "$STAGE/dmg"
cp -R "$APP" "$STAGE/dmg/"
ln -s /Applications "$STAGE/dmg/Applications"
# hdiutil sometimes fails with "Resource busy" right after a build.
for attempt in 1 2 3; do
    hdiutil create -volname "Pinxel $VERSION" -srcfolder "$STAGE/dmg" -format UDZO \
        "$OUT/Pinxel-$VERSION.dmg" >/dev/null && break
    [ "$attempt" = 3 ] && fail "hdiutil create failed"
    sleep 5
done
codesign --sign "$SIGN_IDENTITY" --timestamp "$OUT/Pinxel-$VERSION.dmg"
hdiutil verify "$OUT/Pinxel-$VERSION.dmg" >/dev/null 2>&1 || fail "the dmg does not verify"
notarize "$OUT/Pinxel-$VERSION.dmg"
if [ "$NOTARIZE" = 1 ]; then
    xcrun stapler staple "$OUT/Pinxel-$VERSION.dmg"
    spctl --assess --type execute "$APP" || fail "Gatekeeper rejects the app"
    spctl --assess --type open --context context:primary-signature "$OUT/Pinxel-$VERSION.dmg" \
        || fail "Gatekeeper rejects the dmg"
fi

(cd "$OUT" && shasum -a 256 "Pinxel-$VERSION.dmg" "Pinxel-$VERSION.zip" > SHA256SUMS.txt)
cat "$OUT/SHA256SUMS.txt"
echo "Packaged Pinxel $VERSION in $OUT"
