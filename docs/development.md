# Development environment

## Current repository state

The repository is a planning baseline. It contains no Swift package, app target, widget target, CI build, or runnable binary yet. M1 in [spec.md](../spec.md#0-delivery-checklist-and-progress) introduces those deliverables.

## Available standalone tools

On the initial development Mac, the standalone Command Line Tools provide Swift 6.3.3 and a macOS SDK. A temporary program outside the repository successfully imported SwiftUI, AppKit, CryptoKit, and SQLite; performed an AES-GCM round trip; and reported SQLite 3.51.0. This establishes basic compiler/library availability only. It is not a product, Keychain, UI, or release test.

Use a process-scoped developer directory rather than changing the machine-wide selection:

```sh
env DEVELOPER_DIR=/Library/Developer/CommandLineTools swift --version
env DEVELOPER_DIR=/Library/Developer/CommandLineTools git --version
```

When core package targets are created in M1, their actual test command must be added here and exercised from a clean checkout. Do not run or claim a successful `swift test` before `Package.swift` and test targets exist.

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

The signed app build, real Keychain access controls, widget packaging/discovery, Xcode UI testing, and release validation stay unchecked until their own tests run. Specify project/scheme/test commands here once those targets exist and have been verified.

## Permissions and safe development

- Do not accept licenses, use `sudo`, install system packages, remove developer frameworks, or change the global developer directory as an automatic test fallback. Request authorization for a concrete system repair when required.
- Use separate development and production bundle identifiers, Keychain namespaces, and vault locations.
- Use synthetic clipboard data and test-owned temporary storage. Never import a production vault or inspect unrelated user content for test fixtures.
- Prefer command-scoped environment settings. Do not modify global Git settings, developer settings, or signing configuration for convenience.
- Never weaken crypto, authentication, sandboxing, or entitlements to make a development preview appear functional.
- Follow [CONTRIBUTING.md](../CONTRIBUTING.md) for branching, commits, validation, and progress updates.
