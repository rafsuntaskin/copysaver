#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

./scripts/swift.sh build --product CopySaverDev
bin_path="$(./scripts/swift.sh build --show-bin-path)"
app_path="$project_root/.build/CopySaverDev.app"
mkdir -p "$app_path/Contents/MacOS"
install -m 755 "$bin_path/CopySaverDev" "$app_path/Contents/MacOS/CopySaver"

python3 - "$project_root/App/Info.plist" "$app_path/Contents/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path

replacements = {
    '$(PRODUCT_BUNDLE_IDENTIFIER)': 'org.copysaver.CopySaver.dev',
    '$(COPY_SAVER_DISPLAY_NAME)': 'CopySaver Dev',
    '$(COPY_SAVER_URL_SCHEME)': 'copysaver-dev',
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
Path(sys.argv[2]).write_bytes(plistlib.dumps(resolve(info)))
PY

# Local ad-hoc signing establishes bundle integrity, not production identity
# or permission to access app-scoped data-protection Keychain items.
/usr/bin/codesign --force --sign - --options runtime --entitlements App/CopySaverPreview.entitlements "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
printf 'Built local development app: %s\n' "$app_path"
