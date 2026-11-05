#!/bin/bash
# Opt-in fixture: only its fixed synthetic vault/key, never real clipboard data.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:---build}"
case "$mode" in --build|--run) ;; *) echo 'Usage: scripts/check-automatic-vault.sh [--build|--run]' >&2; exit 64 ;; esac
./scripts/swift.sh build -c release --product CopySaverAutomaticVaultProbe
bin_path="$(./scripts/swift.sh build -c release --show-bin-path)"
bundle="$PWD/.build/automatic-vault-fixture/CopySaverAutomaticVaultProbe.app"
mkdir -p "$bundle/Contents/MacOS"
install -m 755 "$bin_path/CopySaverAutomaticVaultProbe" "$bundle/Contents/MacOS/CopySaverAutomaticVaultProbe"
python3 - "$bundle/Contents/Info.plist" <<'PY'
import plistlib, sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'org.copysaver.CopySaver.community.AutomaticFixture.dev',
    'CFBundleExecutable': 'CopySaverAutomaticVaultProbe',
    'CFBundleName': 'CopySaver Automatic Vault Fixture',
    'CFBundlePackageType': 'APPL', 'LSUIElement': True,
    'LSMinimumSystemVersion': '14.0',
}))
PY
/usr/bin/codesign --force --sign - --options runtime --entitlements App/CopySaverPreview.entitlements "$bundle"
/usr/bin/codesign --verify --strict "$bundle"
if [[ "$mode" == --run ]]; then
    for action in create verify missing-key; do
        "$bundle/Contents/MacOS/CopySaverAutomaticVaultProbe" "$action" --confirm-synthetic-vault
    done
else
    printf 'Built isolated fixture (no Keychain operations): %s\n' "$bundle"
fi
