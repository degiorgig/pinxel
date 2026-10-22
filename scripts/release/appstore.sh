#!/bin/bash
# Builds the Mac App Store version (App Sandbox), signs it for distribution and exports the .pkg,
# optionally uploading it to App Store Connect.
#
#   scripts/release/appstore.sh <version>
#
# <version> must match MARKETING_VERSION in project.yml. Needs, in the keychain, the "Apple Distribution" and
# Mac Installer Distribution certificates of the team in App/Config/Signing.local.xcconfig, and the Mac App
# Store provisioning profile named in App/Config/AppStore.xcconfig.
#
# Environment:
#   UPLOAD=1            upload the build to App Store Connect (otherwise it only exports the .pkg)
#   ASC_KEY_PATH        App Store Connect API key (.p8), for UPLOAD=1
#   ASC_KEY_ID          its key ID
#   ASC_ISSUER_ID       its issuer ID
#
# Output goes to build/appstore-<version> (or $OUT_DIR), which must not exist yet: Pinxel.pkg.
set -euo pipefail

VERSION=${1:?usage: scripts/release/appstore.sh <version>}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

OUT=${OUT_DIR:-build/appstore-$VERSION}
ARCHIVE=build/appstore-$VERSION.xcarchive
UPLOAD=${UPLOAD:-0}

fail() { echo "error: $*" >&2; exit 1; }

[ -e "$OUT" ] && fail "$OUT already exists; remove it or set OUT_DIR"
[ -e "$ARCHIVE" ] && fail "$ARCHIVE already exists; remove it"
if [ "$UPLOAD" = 1 ]; then
    [ -n "${ASC_KEY_PATH:-}" ] && [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] \
        || fail "UPLOAD=1 needs ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID"
fi

setting() {
    xcodebuild -project Pinxel.xcodeproj -target Pinxel -configuration AppStore -showBuildSettings 2>/dev/null \
        | sed -nE "s/^ *$1 = (.*)/\1/p" | head -1
}

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

xcodegen generate >/dev/null
TEAM=$(setting DEVELOPMENT_TEAM)
PROFILE=$(setting PROVISIONING_PROFILE_SPECIFIER)
BUNDLE_ID=$(setting PRODUCT_BUNDLE_IDENTIFIER)
[ -n "$TEAM" ] || fail "DEVELOPMENT_TEAM is empty (App/Config/Signing.local.xcconfig)"
# The Mac Installer Distribution certificate is named "3rd Party Mac Developer Installer" or, when newer,
# "Mac Installer Distribution": take whichever the keychain has.
INSTALLER=$(security find-identity -v | sed -nE "s/.*\"((3rd Party Mac Developer Installer|Mac Installer Distribution): .*\($TEAM\))\"/\1/p" | head -1)
[ -n "$INSTALLER" ] || fail "no Mac Installer Distribution certificate for team $TEAM in the keychain"

xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -configuration AppStore \
    -destination "generic/platform=macOS" -derivedDataPath "build/appstore-derived-$VERSION" \
    -archivePath "$ARCHIVE" archive | tail -1

APP=$ARCHIVE/Products/Applications/Pinxel.app
BUILT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
[ "$BUILT" = "$VERSION" ] || fail "the app is version $BUILT, not $VERSION (update MARKETING_VERSION in project.yml)"
ENTITLEMENTS=$(codesign -d --entitlements - "$APP" 2>/dev/null || true)
grep -q "com.apple.security.app-sandbox" <<<"$ENTITLEMENTS" || fail "the App Store build is not sandboxed"

DESTINATION=export
[ "$UPLOAD" = 1 ] && DESTINATION=upload
cat > "$STAGE/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>$DESTINATION</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Apple Distribution</string>
    <key>installerSigningCertificate</key><string>$INSTALLER</string>
    <key>provisioningProfiles</key>
    <dict><key>$BUNDLE_ID</key><string>$PROFILE</string></dict>
</dict>
</plist>
PLIST

AUTH=()
if [ "$UPLOAD" = 1 ]; then
    AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
    -exportOptionsPlist "$STAGE/ExportOptions.plist" ${AUTH[@]+"${AUTH[@]}"} | tail -1

if [ "$UPLOAD" = 1 ]; then
    echo "Uploaded Pinxel $VERSION to App Store Connect"
else
    [ -f "$OUT/Pinxel.pkg" ] || fail "the export did not produce Pinxel.pkg"
    echo "Exported Pinxel $VERSION for the App Store in $OUT"
fi
