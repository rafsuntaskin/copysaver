#!/bin/bash
# Explicit operator workflow. Never stores credentials or publishes artifacts.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-help}"
if [[ "$mode" == "help" || "$mode" == "--help" ]]; then
    printf '%s\n' 'Usage: scripts/release.sh archive|notarize' 'archive requires DEVELOPMENT_TEAM and SIGNING_IDENTITY.' 'notarize additionally requires NOTARY_PROFILE and a reviewed archive.'
    exit 0
fi
if [[ "$mode" != "archive" && "$mode" != "notarize" ]]; then
    printf '%s\n' 'Unknown release action.' >&2; exit 2
fi
: "${DEVELOPMENT_TEAM:?Set your Apple Developer team.}"
: "${SIGNING_IDENTITY:?Set your Developer ID Application signing identity.}"
if [[ ! "$DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ || "$SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
    printf '%s\n' 'Use a real Apple team and Developer ID Application certificate name.' >&2; exit 2
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
output="$PWD/.build/distribution"
archive="$output/CopySaver.xcarchive"
app="$archive/Products/Applications/CopySaver.app"
mkdir -p "$output"
if [[ "$mode" == "archive" ]]; then
    if [[ -n "$(git status --porcelain)" ]]; then printf '%s\n' 'Commit or move aside reviewed source changes before archiving.' >&2; exit 2; fi
    if [[ -e "$archive" ]]; then printf '%s\n' 'Archive already exists; move it aside before creating another.' >&2; exit 2; fi
    /usr/bin/xcodebuild -project CopySaver.xcodeproj -scheme CopySaver -configuration Release \
        -destination 'generic/platform=macOS' -archivePath "$archive" \
        ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" archive
    /usr/bin/codesign --verify --strict --deep "$app"
    /usr/bin/lipo -verify_arch arm64 x86_64 "$app/Contents/MacOS/CopySaver"
    /usr/bin/lipo -verify_arch arm64 x86_64 "$app/Contents/PlugIns/CopySaverWidget.appex/Contents/MacOS/CopySaverWidget"
    git rev-parse HEAD > "$output/SOURCE_REVISION.txt"
    /usr/bin/xcodebuild -version > "$output/TOOLCHAIN.txt"
    /usr/bin/xcrun swift --version >> "$output/TOOLCHAIN.txt"
    /usr/bin/xcrun --show-sdk-version >> "$output/TOOLCHAIN.txt"
    printf '%s\n' 'No third-party runtime package dependencies.' > "$output/DEPENDENCIES.txt"
    printf '%s\n' 'Archive created. Complete docs/release-checklist.md before notarizing.'
    exit 0
fi
: "${NOTARY_PROFILE:?Set an existing notarytool Keychain profile name.}"
: "${RELEASE_VALIDATION_CONFIRMED:?Set to yes only after the release checklist passes.}"
if [[ "$RELEASE_VALIDATION_CONFIRMED" != 'yes' || ! -d "$app" || ! -f "$output/SOURCE_REVISION.txt" ]]; then printf '%s\n' 'Reviewed archive required.' >&2; exit 2; fi
/usr/bin/codesign --verify --strict --deep "$app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$output/CopySaver-notary.zip"
/usr/bin/xcrun notarytool submit "$output/CopySaver-notary.zip" --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$app"
/usr/bin/xcrun stapler validate "$app"
staging="$(mktemp -d "$output/dmg-stage.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
/usr/bin/ditto "$app" "$staging/CopySaver.app"
ln -s /Applications "$staging/Applications"
cp docs/PRIVACY.txt "$staging/Read me.txt"
/usr/bin/hdiutil create -volname CopySaver -srcfolder "$staging" -format UDZO -ov "$output/CopySaver.dmg"
/usr/bin/codesign --sign "$SIGNING_IDENTITY" --timestamp "$output/CopySaver.dmg"
/usr/bin/xcrun notarytool submit "$output/CopySaver.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$output/CopySaver.dmg"
/usr/bin/xcrun stapler validate "$output/CopySaver.dmg"
/usr/sbin/spctl --assess --type execute --verbose "$app"
(cd "$output" && /usr/bin/shasum -a 256 CopySaver.dmg > SHA256SUMS)
printf '%s\n' 'Artifacts prepared locally. Nothing has been published or tagged.'
