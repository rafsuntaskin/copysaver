# Development environment

## Current repository state

The repository contains a Swift 6 package with `CopySaverDomain`, `CopySaverVault`, `CopySaverPlatform`, and `CopySaverDesktop` libraries, 85 Swift Testing checks (two benchmarks are opt-in), a native development executable, and no external package dependencies. An Xcode app project is committed but has not been built through Xcode. The Xcode widget target and CI/release scripts are present; signed target builds, gallery discovery, hosted CI execution, and release binaries remain pending. See [spec.md](../spec.md#0-delivery-checklist-and-progress) for verified delivery status.

## Available standalone tools

The core package builds with the standalone Command Line Tools (verified with Swift 6.3.3 on macOS 26.6.2). It targets macOS 14 or later, but has not been tested on the minimum OS or Intel hardware. Testing the core does not establish signed Keychain, UI, or release behavior.

From the repository root:

```sh
make build
make test
make preview
```

`make test` runs Swift Testing without XCTest. The functional tests cover record validation/serialization, capture admission, CryptoKit encryption/tampering, an independent OpenSSL fixture, SQLite CRUD/rollback/reopen, session cancellation, Keychain query policy, strict navigation routes, UI lock/authentication races, and sensitive-copy ownership/expiry. Storage is synthetic and temporary. Platform tests use an in-memory Keychain transport and an in-memory pasteboard bridge; they never call real `SecItem` storage or the system clipboard. The access-control constructor and pasteboard-item representation use OS frameworks without authenticating or touching user data.

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

The signed app build, actual Keychain enforcement, widget packaging/discovery, Xcode UI testing, and release validation stay unchecked until their own tests run. The native Keychain adapter exists and has no plaintext fallback; its query policy is unit-tested, while OS-enforced identity and authentication remain separate gates. See [native integration evidence](native-integration.md).

## Native development app

```sh
make app
make preview
```

`make app` builds the Debug executable through SwiftPM, packages `.build/CopySaverDev.app`, and verifies its local ad-hoc signature with sandbox and hardened runtime. `make preview` opens that bundle with `--ui-preview`. The DEBUG-only preview contains fictional records, no vault/authentication services, and no clipboard output. Sample reveal/copy/edit actions are disabled. Lock clears the samples; Reset sample preview restores them. The optimized Release executable excludes the sample records and refuses the preview flag.

Normal launch starts locked (or offers setup for a new vault). It attempts real data-protection Keychain access and may report a missing-entitlement error with ad-hoc signing. Do not weaken entitlements or authentication to bypass this. Use synthetic data only until signed integration passes. Capture starts off; enable it in History settings after unlocking. On systems with clipboard permission controls, automatic capture requires Always Allow.

`CopySaver.xcodeproj` and its shared `CopySaver` scheme reference the local Swift package. Once Xcode works, open the project, select your own development team, build the Debug scheme, and run the M1-08–M1-14 scenarios. This project configuration is structurally checked, not yet verified by `xcodebuild`; no passing Xcode command is claimed. Do not invent a team ID or add shared Keychain groups.

Debug uses provisional bundle ID `org.copysaver.CopySaver.dev` and scheme `copysaver-dev`; Release uses `org.copysaver.CopySaver` and `copysaver`. Vault paths and Keychain service names derive from the active bundle identity. These identifiers require ownership confirmation before distribution. The provisional app has no network entitlement, widget extension, or shared container.

Native visual inspection and remaining platform gates are recorded in [native-integration.md](native-integration.md). The selected design context is in [PRODUCT.md](../PRODUCT.md) and [DESIGN.md](../DESIGN.md).

## Permissions and safe development

- Do not accept licenses, use `sudo`, install system packages, remove developer frameworks, or change the global developer directory as an automatic test fallback. Request authorization for a concrete system repair when required.
- Use separate development and production bundle identifiers, Keychain namespaces, and vault locations.
- Use synthetic clipboard data and test-owned temporary storage. Never import a production vault or inspect unrelated user content for test fixtures.
- Prefer command-scoped environment settings. Do not modify global Git settings, developer settings, or signing configuration for convenience.
- Never weaken crypto, authentication, sandboxing, or entitlements to make a development preview appear functional.
- Follow [CONTRIBUTING.md](../CONTRIBUTING.md) for branching, commits, validation, and progress updates.

## Verification and release tools

`make verify` runs static project/entitlement/widget dependency checks, local documentation/checklist validation, shell syntax, all package builds, and the functional test suite. `make build` also compiles `CopySaverWidgetCheck`, which checks the real widget entry source; do not run that executable as an app. Actual extension packaging/discovery still needs Xcode and signing. `CopySaverCrashProbe` is a test-only process fixture; its random synthetic key arrives through an anonymous pipe, never a key file/environment/argument. Neither helper is embedded in the application.

The committed [CI workflow](../.github/workflows/ci.yml) runs source verification and an unsigned app/embedded-widget Xcode build on Apple silicon and Intel macOS runners. It has read-only repository permissions and a pinned checkout action. It has not run on a hosted repository yet. See [release validation](release-checklist.md) for the explicit archive/notarization workflow. Source checks, unsigned builds, and configuration are not proof of signed platform behavior.

See [performance evidence](performance.md) for opt-in synthetic benchmarks. On the current machine, Xcode still fails to load CoreDevice (`_XPCTypeBool`), the installed support package reports 16.1, and `security find-identity -v -p codesigning` found zero valid identities. Apple's bundled repair package passed signature verification. No package was installed, no developer directory was changed, and no signing identity was invented.
