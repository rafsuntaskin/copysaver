# CopySaver

A macOS-first, open source clipboard history and named-snippet utility designed to keep stored content encrypted locally.

**Status: runnable native development preview, with tested encrypted core storage. Clipboard capture and retention are implemented; widgets and signed security/release validation are unfinished. There is no release download yet.** Implementation progress and verification gates live in [spec.md](spec.md#0-delivery-checklist-and-progress).

## Planned v0.1

- Searchable plain-text clipboard history with pinning and automatic retention.
- Named snippets for addresses, signatures, and other reusable text.
- Masked sensitive snippets with system authentication before reveal or copy.
- A full native library and a Spotlight-style Focus panel with a configurable global shortcut.
- Small and medium macOS Notification Center/desktop launcher widgets.
- An encrypted SQLite-backed vault with a device-bound Keychain key.

The selected stack is Swift 6, SwiftUI, AppKit, CryptoKit, Security/LocalAuthentication, SQLite, and WidgetKit. macOS is the priority; Windows is a later, separately scoped client.

## Privacy design

The MVP is designed to work without an account, server, telemetry, or network access. Locking the vault pauses clipboard capture. Copying an item deliberately puts plaintext on the system clipboard for the destination app to use.

The initial key is device-bound. Portable encrypted backup/recovery is not included in v0.1, so the planned app must not be treated as the only copy of important information. The threat model and limits are in [spec section 7](spec.md#7-security-model). These are design requirements, not claims of completed security validation.

## Design

[Native library](designs/01-native-library.png) is the approved full window; [Focus panel](designs/02-focus-panel.png) is the approved quick-access view. See [design notes](designs/README.md).

## Development

Start with [development setup](docs/development.md), [contribution workflow](CONTRIBUTING.md), and [repository agent instructions](AGENTS.md). The standalone Swift toolchain can build and test the core without modifying the system Xcode installation:

```sh
make build
make test
make preview
```

The preview opens the approved three-column library with synthetic samples. Use the sidebar’s Focus mode action to inspect the compact panel. Preview mode never creates a vault, accesses Keychain, or copies to the system clipboard.

The dependency-free Swift package includes record models, AES-GCM encrypted SQLite storage, a native Keychain adapter, and SwiftUI/AppKit views. Its 68 Swift Testing tests use synthetic data and temporary storage; authentication and clipboard behavior use test doubles. `make app` builds an ad-hoc signed development bundle at `.build/CopySaverDev.app`; it does not establish protected Keychain access or release readiness. Use synthetic data until native security gates pass. See [native integration evidence](docs/native-integration.md) and the [vault format](docs/vault-format.md).

## Contributing and security

Use focused branches, Conventional Commits, and the spec checklist to track verified progress. See [CONTRIBUTING.md](CONTRIBUTING.md). Never attach real clipboard content, vaults, or credentials to issues. See [SECURITY.md](SECURITY.md) for the current reporting policy.

Licensed under [MIT](LICENSE).
