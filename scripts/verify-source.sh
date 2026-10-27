#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-project.py
bash -n scripts/swift.sh scripts/build-app.sh scripts/verify-source.sh scripts/release.sh
make build
make test
