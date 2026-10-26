# Development environment

## Current repository state

The repository contains a Swift 6 package with `CopySaverDomain` and `CopySaverVault` libraries, 31 Swift Testing tests, and no external package dependencies. Native app/widget targets, CI, and release binaries are pending. See [spec.md](../spec.md#0-delivery-checklist-and-progress) for verified delivery status.

## Available standalone tools

The core package builds with the standalone Command Line Tools (verified with Swift 6.3.3 on macOS 26.6.2). It targets macOS 14 or later, but has not been tested on the minimum OS or Intel hardware. Testing the core does not establish signed Keychain, UI, or release behavior.

From the repository root:

```sh
make build
make test
```

`make test` runs Swift Testing without XCTest. The 31 tests cover record validation/serialization, capture admission, production CryptoKit encryption/tampering, an independent OpenSSL envelope fixture, encrypted SQLite CRUD/rollback/reopen, and session locking/cancellation. Every vault and key used by tests is synthetic and temporary; no user clipboard, Keychain, or production vault is read.

Targeted commands use the same wrapper:

```sh
./scripts/swift.sh test --disable-xctest --filter wrongKey
./scripts/swift.sh package describe
```

Tests are top-level Swift Testing functions; use a test function name or matching expression, such as `wrongKey`, when filtering.

The wrapper respects an explicit `DEVELOPER_DIR`; otherwise it prefers installed Command Line Tools and falls back to the active developer directory. It discovers the SDK, compiler, bundled Testing framework, and test interoperability library from the selected tools. Build/cache paths stay under ignored `.build/`. Test framework/search paths are process/build-local; there are no global developer-path changes or disabled SwiftPM sandbox flags.

In the restricted coding environment, SwiftPM's own manifest sandbox cannot start inside the outer sandbox. Run the same build/test command with an approved execution environment rather than disabling SwiftPM's sandbox or modifying system components. Ordinary terminal builds do not need a project-specific privilege escalation.

Use a process-scoped developer directory rather than changing the machine-wide selection:

```sh
env DEVELOPER_DIR=/Library/Developer/CommandLineTools swift --version
env DEVELOPER_DIR=/Library/Developer/CommandLineTools git --version
```

The package has no remote dependencies or `Package.resolved` file yet. Commit a resolved lockfile when application dependencies are introduced. Node.js was used only to generate the checked-in independent OpenSSL fixture; neither building nor running tests requires Node.

For direct compiler troubleshooting, use the SDK at `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` and a workspace-local or temporary module cache. Keep generated files ignored. Do not commit absolute machine paths into project build settings; locate developer tools/SDKs through the chosen toolchain in the build entry point.

## Full Xcode integration

The initial environment has Xcode 27.1 installed and selected at `/Applications/Xcode.app/Contents/Developer`. At the last check, SDK loading and Swift discovery through that Xcode failed with a CoreDevice `_XPCTypeBool` library error. An installed developer-support package still reported version 16.1.

Xcode passed Gatekeeper assessment, and its bundled replacement support package passed Apple signature verification outside the restricted execution sandbox. No support package was installed by this project. A system-wide repair was blocked pending explicit approval and is not a prerequisite for starting independently testable core work.

Once Xcode is working, validate these read-only checks and record the results in the spec:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -checkFirstLaunchStatus
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -showsdks
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift --version
```

The signed app build, native Keychain provider/access controls, widget packaging/discovery, Xcode UI testing, and release validation stay unchecked until their own tests run. Specify project/scheme/test commands here once those targets exist and have been verified. The current provider protocol deliberately has no production fallback: core tests inject ephemeral keys; an app must obtain its real key through the future authenticated Keychain adapter.

## Permissions and safe development

- Do not accept licenses, use `sudo`, install system packages, remove developer frameworks, or change the global developer directory as an automatic test fallback. Request authorization for a concrete system repair when required.
- Use separate development and production bundle identifiers, Keychain namespaces, and vault locations.
- Use synthetic clipboard data and test-owned temporary storage. Never import a production vault or inspect unrelated user content for test fixtures.
- Prefer command-scoped environment settings. Do not modify global Git settings, developer settings, or signing configuration for convenience.
- Never weaken crypto, authentication, sandboxing, or entitlements to make a development preview appear functional.
- Follow [CONTRIBUTING.md](../CONTRIBUTING.md) for branching, commits, validation, and progress updates.
