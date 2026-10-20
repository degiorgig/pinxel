#!/bin/bash
# Builds the signed Release app and packages it as a zip and a dmg.
#
#   scripts/release/package.sh <version>
#
# <version> must match MARKETING_VERSION in project.yml. The app must be signed
# with an "Apple Development" identity (App/Config/Signing.local.xcconfig), so
# the Screen Recording permission survives updates.
# Output goes to build/dist-<version> (or $OUT_DIR), which must not exist yet:
# Pinxel-<version>.zip, Pinxel-<version>.dmg and SHA256SUMS.txt.
set -euo pipefail

VERSION=${1:?usage: scripts/release/package.sh <version>}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

OUT=${OUT_DIR:-build/dist-$VERSION}
DERIVED=build/release-$VERSION

fail() { echo "error: $*" >&2; exit 1; }

[ -e "$OUT" ] && fail "$OUT already exists; remove it or set OUT_DIR"

xcodegen generate >/dev/null
xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" build | tail -1

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
grep -q "^Authority=Apple Development" <<<"$SIGNATURE" \
    || fail "the app is not signed with an Apple Development identity (see App/Config/Base.xcconfig)"

mkdir -p "$OUT"
STAGE=$(mktemp -d)
ditto -c -k --keepParent "$APP" "$OUT/Pinxel-$VERSION.zip"

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# hdiutil sometimes fails with "Resource busy" right after a build.
for attempt in 1 2 3; do
    hdiutil create -volname "Pinxel $VERSION" -srcfolder "$STAGE" -format UDZO \
        "$OUT/Pinxel-$VERSION.dmg" >/dev/null && break
    [ "$attempt" = 3 ] && fail "hdiutil create failed"
    sleep 5
done
codesign --sign "Apple Development" "$OUT/Pinxel-$VERSION.dmg"
hdiutil verify "$OUT/Pinxel-$VERSION.dmg" >/dev/null 2>&1 || fail "the dmg does not verify"

(cd "$OUT" && shasum -a 256 "Pinxel-$VERSION.dmg" "Pinxel-$VERSION.zip" > SHA256SUMS.txt)
cat "$OUT/SHA256SUMS.txt"
echo "Packaged Pinxel $VERSION in $OUT"
