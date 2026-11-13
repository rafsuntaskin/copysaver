#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

configuration="${1:-debug}"
case "$configuration" in debug|release) ;; *) echo 'Usage: scripts/build-app.sh [debug|release]' >&2; exit 64 ;; esac
build_options=(-c "$configuration" --product CopySaverDev)
identifier='org.copysaver.CopySaver.community.dev'
display_name='CopySaver Community Dev'
url_scheme='copysaver-community-dev'
app_path="$project_root/.build/CopySaverDev.app"
if [[ "$configuration" == release ]]; then
    build_options+=(--arch arm64 --arch x86_64)
    identifier='org.copysaver.CopySaver.community'
    display_name='CopySaver'
    url_scheme='copysaver-community'
    app_path="$project_root/.build/community/CopySaver.app"
fi
./scripts/swift.sh build "${build_options[@]}"
bin_path="$(./scripts/swift.sh build "${build_options[@]}" --show-bin-path)"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
install -m 644 App/Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
install -m 644 LICENSE "$app_path/Contents/Resources/LICENSE"
install -m 755 "$bin_path/CopySaverDev" "$app_path/Contents/MacOS/CopySaver"

python3 - "$project_root/App/Info.plist" "$app_path/Contents/Info.plist" "$identifier" "$display_name" "$url_scheme" <<'PY'
import plistlib
import sys
from pathlib import Path

replacements = {
    '$(PRODUCT_BUNDLE_IDENTIFIER)': sys.argv[3],
    '$(COPY_SAVER_DISPLAY_NAME)': sys.argv[4],
    '$(COPY_SAVER_URL_SCHEME)': sys.argv[5],
}
with open(sys.argv[1], 'rb') as source:
    info = plistlib.load(source)
def resolve(value):
    if isinstance(value, str):
        for name, replacement in replacements.items():
            value = value.replace(name, replacement)
        return value
    if isinstance(value, list):
        return [resolve(item) for item in value]
    if isinstance(value, dict):
        return {key: resolve(item) for key, item in value.items()}
    return value
info = resolve(info)
info['CopySaverStorageProfile'] = 'automatic'
# The community profile never requests device-owner authentication.
info.pop('NSFaceIDUsageDescription', None)
Path(sys.argv[2]).write_bytes(plistlib.dumps(info))
PY

# Ad-hoc signing provides integrity, not an Apple-verified publisher identity.
# The automatic profile uses login-Keychain ACLs, not restricted access groups.
/usr/bin/codesign --force --sign - --options runtime --entitlements App/CopySaverPreview.entitlements "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
printf 'Built ad-hoc community app: %s\n' "$app_path"
