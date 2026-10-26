#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

# This selection is process-local. Respect an explicit caller selection.
if [ -z "${DEVELOPER_DIR:-}" ]; then
    if [ -d /Library/Developer/CommandLineTools ]; then
        export DEVELOPER_DIR=/Library/Developer/CommandLineTools
    else
        export DEVELOPER_DIR="$(/usr/bin/xcode-select -p)"
    fi
fi

export SDKROOT="$(/usr/bin/xcrun --show-sdk-path)"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/ModuleCache"
swift_bin="$(/usr/bin/xcrun --find swift)"
action="${1:-test}"
if [ "$#" -gt 0 ]; then shift; fi

case "$action" in
    build|test|package) ;;
    *) echo 'Usage: scripts/swift.sh {build|test|package} [SwiftPM options]' >&2; exit 64 ;;
esac

testing_options=()
if [ "$action" = test ]; then
    testing_frameworks="$DEVELOPER_DIR/Library/Developer/Frameworks"
    if [ ! -d "$testing_frameworks/Testing.framework" ]; then
        testing_frameworks="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks"
    fi
    if [ ! -d "$testing_frameworks/Testing.framework" ]; then
        echo 'Swift Testing.framework is missing from the selected developer tools.' >&2
        exit 69
    fi
    testing_support=""
    for candidate in "$testing_frameworks/../usr/lib" "$testing_frameworks/../../usr/lib" "$DEVELOPER_DIR/usr/lib"; do
        if [ -f "$candidate/lib_TestingInterop.dylib" ]; then
            testing_support="$candidate"
            break
        fi
    done
    if [ -z "$testing_support" ]; then
        echo 'lib_TestingInterop.dylib is missing from the selected developer tools.' >&2
        exit 69
    fi
    testing_options=(-Xswiftc -F -Xswiftc "$testing_frameworks"
        -Xlinker -F -Xlinker "$testing_frameworks"
        -Xlinker -rpath -Xlinker "$testing_frameworks"
        -Xlinker -rpath -Xlinker "$testing_support")
fi

exec "$swift_bin" "$action" \
    --scratch-path "$project_root/.build" \
    --cache-path "$project_root/.build/cache" \
    --config-path "$project_root/.build/config" \
    --security-path "$project_root/.build/security" \
    ${testing_options[@]+"${testing_options[@]}"} "$@"
