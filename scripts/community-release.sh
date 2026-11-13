#!/bin/bash
# Local community packaging only. No Apple certificates, credentials or publication.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-release}"
case "$mode" in release|--preview) ;; *) echo 'Usage: scripts/community-release.sh [release|--preview]' >&2; exit 64 ;; esac
dirty="$(git status --porcelain)"
source_revision="$(git rev-parse HEAD)"
if [[ -n "$dirty" && "$mode" != --preview ]]; then
    echo 'A reviewed clean checkout is required. Use --preview only for a local test artifact.' >&2
    exit 2
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
output="$PWD/.build/community"
mkdir -p "$output"
if [[ -e "$output/CopySaver-community.dmg" && "$mode" != --preview ]]; then
    echo 'DMG already exists; preserve it before creating another release.' >&2; exit 2
fi
./scripts/build-app.sh release
/usr/bin/xcodebuild -project CopySaver.xcodeproj -scheme CopySaver -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath .build/community-xcode \
    ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build > "$output/widget-build.log" 2>&1
app="$output/CopySaver.app"
widget="$app/Contents/PlugIns/CopySaverWidget.appex"
mkdir -p "$app/Contents/PlugIns"
/usr/bin/ditto .build/community-xcode/Build/Products/Release/CopySaverWidget.appex "$widget"
python3 - "$widget/Contents/Info.plist" <<'PY'
import plistlib, sys
from pathlib import Path
path = Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info['CFBundleIdentifier'] = 'org.copysaver.CopySaver.community.Widget'
info['CopySaverCommunityBuild'] = True
path.write_bytes(plistlib.dumps(info))
PY
/usr/bin/codesign --force --sign - --options runtime --entitlements Widget/CopySaverWidget.entitlements "$widget"
/usr/bin/codesign --force --sign - --options runtime --entitlements App/CopySaverPreview.entitlements "$app"
python3 scripts/check-community-artifact.py "$app"
if [[ "$mode" != --preview ]]; then
    git diff --quiet "$source_revision" --
    git diff --cached --quiet "$source_revision" --
fi
printf '%s\n' "$source_revision" > "$output/SOURCE_REVISION.txt"
/usr/bin/xcodebuild -version > "$output/TOOLCHAIN.txt"
/usr/bin/xcrun swift --version >> "$output/TOOLCHAIN.txt"
/usr/bin/xcrun --show-sdk-version >> "$output/TOOLCHAIN.txt"
python3 --version >> "$output/TOOLCHAIN.txt"
/usr/bin/sw_vers -productVersion >> "$output/TOOLCHAIN.txt"
/usr/bin/uname -m >> "$output/TOOLCHAIN.txt"
printf '%s\n' 'No third-party runtime package dependencies.' > "$output/DEPENDENCIES.txt"
printf '%s\n' "Mode: $mode" "Uncommitted source: $([[ -n "$dirty" ]] && echo yes || echo no)" \
    'Apple-issued certificate: none' 'Notarization: none' 'Clean-Mac Gatekeeper validation: pending' > "$output/BUILD_INFO.txt"
staging="$(mktemp -d "$output/dmg-stage.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
/usr/bin/ditto "$app" "$staging/CopySaver.app"
ln -s /Applications "$staging/Applications"
cp LICENSE "$staging/License.txt"
cp docs/COMMUNITY.txt "$staging/Read me.txt"
/usr/bin/hdiutil create -volname CopySaver -srcfolder "$staging" -format UDZO -ov "$output/CopySaver-community.dmg"
(cd "$output" && /usr/bin/shasum -a 256 CopySaver-community.dmg > SHA256SUMS)
printf 'Created local community DMG: %s\n' "$output/CopySaver-community.dmg"
