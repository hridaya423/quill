#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
identity="${QUILL_IDENTITY:-Developer ID Application}"
profile="${QUILL_NOTARY:-notary}"
app=build/Quill.app
dmg=build/Quill.dmg
scripts/bundle.sh release
codesign --force --options runtime --timestamp --entitlements scripts/Quill.entitlements --sign "$identity" "$app"
codesign --verify --strict --deep --verbose=2 "$app"
rm -f "$dmg"
uvx --from dmgbuild==1.6.5 dmgbuild -s assets/dmg/settings.py -D app="$app" Quill "$dmg"
codesign --force --timestamp --sign "$identity" "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
xcrun stapler staple "$app"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
spctl --assess --type execute --verbose=2 "$app"
echo "$dmg"
