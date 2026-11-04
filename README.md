# CopySaver

A macOS-first, open source clipboard history and named-snippet utility designed to keep stored content encrypted locally.

**Status: native development build with history, snippets, Focus mode, and generic launcher-widget source implemented. The community profile opens and captures automatically using login-Keychain storage, without an Apple-issued signing certificate. Full native/release verification is unfinished; no public release download is published.** Implementation progress and verification gates live in [spec.md](spec.md#0-delivery-checklist-and-progress).

## v0.1 scope

- Searchable plain-text clipboard history with pinning and automatic retention.
- Named snippets for addresses, signatures, and other reusable text.
- Sensitive snippets with hidden previews, explicit reveal, and private clipboard expiry.
- A full native library and a Spotlight-style Focus panel with a configurable global shortcut.
- Small and medium macOS Notification Center/desktop launcher widgets.
- An encrypted SQLite-backed vault with a random key kept separately in macOS Keychain.

The selected stack is Swift 6, SwiftUI, AppKit, CryptoKit, Security/LocalAuthentication, SQLite, and WidgetKit. macOS is the priority; Windows is a later, separately scoped client.

## Privacy design

The MVP works without an account, server, telemetry, or app networking. New community libraries capture automatically after OS clipboard approval, reopen after sleep, and respect saved Pause/Disable choices. Hide and pause clears the interface and stops capture until explicit reopening; it is not an authentication lock. Sensitive snippets conceal previews/search bodies and require no additional authentication in the open community library. Copying deliberately puts plaintext on the system clipboard.

Community vault keys use the default login Keychain's calling-app ACL. Copied database files alone cannot reveal the contents; a compromised unlocked account or decryptable Keychain is outside this protection. No app-exclusivity or device-only guarantee is claimed for this profile. Portable backup/recovery is not included in v0.1, so keep another copy of important information. See [community installation/privacy notes](docs/COMMUNITY.txt) and [spec section 7](spec.md#7-security-model).

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

The dependency-free Swift package includes AES-GCM encrypted SQLite storage, Keychain adapters, and SwiftUI/AppKit views. Automated tests use synthetic data and injected OS boundaries. `make app` builds an ad-hoc community development app at `.build/CopySaverDev.app`, with a separate identity/vault from the older protected Xcode build. `make preview` still uses fictional in-memory samples without capture or Keychain access. `make community-dmg` builds a universal app and embedded launcher widget from a reviewed clean checkout, with no Apple signing key or notarization. macOS may require first-run/update approval; actual widget discovery and clean-Mac release testing remain pending. See [development setup](docs/development.md), [community release validation](docs/release-checklist.md#community-dmg), [native evidence](docs/native-integration.md), and the [vault format](docs/vault-format.md).

## Contributing and security

Use focused branches, Conventional Commits, and the spec checklist to track verified progress. See [CONTRIBUTING.md](CONTRIBUTING.md). Never attach real clipboard content, vaults, or credentials to issues. See [SECURITY.md](SECURITY.md) for the current reporting policy.

Licensed under [MIT](LICENSE).
