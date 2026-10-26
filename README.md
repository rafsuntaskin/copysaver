# CopySaver

A macOS-first, open source clipboard history and named-snippet utility designed to keep stored content encrypted locally.

**Status: core libraries implemented; native app and widget still in development. There is no runnable application or release download yet.** Implementation progress and verification gates live in [spec.md](spec.md#0-delivery-checklist-and-progress).

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
```

The dependency-free Swift package includes validated record models, AES-GCM encrypted SQLite persistence, and actor-isolated vault sessions. Its 31 Swift Testing tests use synthetic data and ephemeral keys. The [vault format](docs/vault-format.md) documents the encryption envelope, schema, and verification limits. A native authenticated Keychain provider, app target, widget, and signed platform validation are not implemented yet.

## Contributing and security

Use focused branches, Conventional Commits, and the spec checklist to track verified progress. See [CONTRIBUTING.md](CONTRIBUTING.md). Never attach real clipboard content, vaults, or credentials to issues. See [SECURITY.md](SECURITY.md) for the current reporting policy.

Licensed under [MIT](LICENSE).
