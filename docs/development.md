# Development environment

## Current repository state

The repository contains a Swift 6 package with `CopySaverDomain`, `CopySaverVault`, `CopySaverPlatform`, and `CopySaverDesktop` libraries, 89 Swift Testing checks (two benchmarks are opt-in), a native development executable, and no external package dependencies. The Xcode app and embedded widget build successfully in Debug and Release for Apple silicon and Intel with signing disabled. Apple Development app/widget builds now pass on the local Apple silicon Mac; protected vault creation, owner-authenticated first unlock, and synthetic clipboard capture/search/copy-back pass. Authenticated relaunch preserves the synthetic history/snippet and resumes capture. Helper isolation, full authentication cases, gallery discovery, hosted CI execution, and release binaries remain separate gates. See [spec.md](../spec.md#0-delivery-checklist-and-progress) for verified delivery status.

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

Xcode 27.1 (27A9275) is installed and selected at `/Applications/Xcode.app/Contents/Developer`. The previous CoreDevice `_XPCTypeBool` loader failure came from stale version 16.1 developer-support resources.

On October 26, 2026, after explicit user approval and Apple signature verification, Apple Installer successfully installed the bundled `XcodeSystemResources.pkg`. The installed receipt now reports `27.1.0.0.1790739719`. Xcode version/SDK discovery and Swift 6.4 discovery pass. No global developer-directory change was made. This repair does not authorize other system packages or security changes.

Read-only environment checks:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -checkFirstLaunchStatus
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -showsdks
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift --version
```

Version, SDK and Swift checks pass. `-checkFirstLaunchStatus` still exits 69 without diagnostics; no additional first-launch packages were installed. The macOS app/widget build itself succeeds. Actual signed Keychain enforcement, widget discovery, Xcode UI testing, and release validation stay unchecked until their own tests run. The native Keychain adapter has no plaintext fallback; its query policy is unit-tested, while OS-enforced identity and authentication remain separate gates. See [native integration evidence](native-integration.md).

## Native development app

```sh
make app
make preview
```

`make app` builds the Debug executable through SwiftPM, packages `.build/CopySaverDev.app`, and verifies its local ad-hoc signature with sandbox and hardened runtime. `make preview` opens that bundle with `--ui-preview`. The DEBUG-only preview contains fictional records, no vault/authentication services, and no clipboard output. Sample reveal/copy/edit actions are disabled. Lock clears the samples; Reset sample preview restores them. The optimized Release executable excludes the sample records and refuses the preview flag.

Normal launch starts locked (or offers setup for a new vault). It attempts real data-protection Keychain access and may report a missing-entitlement error with ad-hoc signing. Do not weaken entitlements or authentication to bypass this. Use synthetic data only until signed integration passes. Capture starts off; enable it in History settings after unlocking. On systems with clipboard permission controls, automatic capture requires Always Allow.

`CopySaver.xcodeproj` and its shared `CopySaver` scheme reference the local Swift package. The unsigned Debug app and embedded widget build successfully for arm64 and x86_64 with:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project CopySaver.xcodeproj -scheme CopySaver -configuration Debug \
  -destination 'generic/platform=macOS' -derivedDataPath .build/xcode-verification \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
```

For authenticated native testing, open the project, select your own development team, build the Debug scheme, and run the M1-08–M1-14 scenarios. Do not invent a team ID or add shared Keychain groups. An unsigned build does not establish runtime sandbox, hardened-runtime, or Keychain enforcement.

Debug builds use `ONLY_ACTIVE_ARCH=YES` at project level so app/extension targets match the local Swift package when running on My Mac. Without this setting, the native widget can request an Intel slice while the Debug package contains only Apple silicon, producing a misleading incompatible-module error. CI and the universal command above explicitly use `ONLY_ACTIVE_ARCH=NO`; Release/archive builds retain both architectures.

Xcode's **Sign to Run Locally** option was tested after this fix: the normal app builds and launches with an ad-hoc signature, but protected vault creation fails closed with the missing-Keychain-entitlement error. It does not enable persistent clipboard capture. A development certificate with its private key and a provisioned app identity are required for the current vault design. The signed app and boundary probe each declare only their own `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)` Keychain group; the widget has no Keychain entitlement. Xcode expands the identity and embeds the matching profile. A certificate alone without these entitlements was tested and still fails closed. `make app` uses separate sandbox-only preview entitlements, since an ad-hoc bundle cannot claim the restricted Keychain group; this does not enable real vault access. Keep personal signing/team selections local; they are not part of the shared project baseline.

Debug uses provisional bundle ID `org.copysaver.CopySaver.dev` and scheme `copysaver-dev`; Release uses `org.copysaver.CopySaver` and `copysaver`. Vault paths and Keychain service names derive from the active bundle identity. These identifiers require ownership confirmation before distribution. The Xcode app embeds a launcher widget with a separate identifier; neither target requests network access or a shared container.

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

`CopySaverKeychainProbe` is a separately signed manual integration fixture, never embedded in CopySaver or its widget. `make verify` builds it and checks its unsigned admission refusals without Keychain access. Follow the [signed Keychain procedure](keychain-validation.md) only with a confirmed synthetic development vault and real signing identity. Actual helper denial and user-presence enforcement remain pending.

See [performance evidence](performance.md) for opt-in synthetic benchmarks. The approved support-package repair resolved Xcode loading. A valid Apple Development certificate/private key is now installed and used successfully. In the restricted coding environment, a sandboxed `security find-identity -v -p codesigning` can hide the user Keychain and incorrectly report zero identities; check from an ordinary local terminal or an approved execution environment. Complete native security validation remains pending. Personal Team provisioning profiles expire; rebuild/reprovision as needed rather than weakening the vault protection.
