#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-project.py
bash -n scripts/swift.sh scripts/build-app.sh scripts/verify-source.sh scripts/release.sh scripts/community-release.sh scripts/check-automatic-vault.sh
make build
probe_bin_directory="$(./scripts/swift.sh build --show-bin-path)"
python3 scripts/check-keychain-probe.py "$probe_bin_directory/CopySaverKeychainProbe"
make test
