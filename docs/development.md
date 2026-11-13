# Development environment

## Current repository state

### Automatic community profile (November 3, 2026)

`make app` now packages a sandboxed/hardened, ad-hoc signed app using the login Keychain without a provisioned access group. It uses `org.copysaver.CopySaver.community.dev`, the `copysaver-community-dev` URL scheme, and a separate vault. Normal launch automatically creates/opens it; new history is enabled after OS clipboard approval. Saved disable/pause choices remain respected. Sleep/session suspension purges state and return events reopen without fresh vault authentication. Idle does not stop capture. Hide and pause requires explicit reopening. Sensitive snippets conceal previews/search bodies without additional authentication inside an open community library. A failed Keychain read preserves files and requires explicit retry rather than repeated background prompts.

`make community-dmg` builds the Release app and embedded widget for arm64/x86_64, ad-hoc signs both, audits identities/entitlements, and creates `.build/community/CopySaver-community.dmg` plus checksums/build metadata. It requires full Xcode and a clean reviewed checkout, but no Apple account/certificate/provisioning/notarization credentials. For a local uncommitted test artifact only, use `./scripts/community-release.sh --preview`; metadata records its dirty status. Neither command publishes, disables Gatekeeper nor removes quarantine. Read [community notes](COMMUNITY.txt) before testing. Widget discovery on ad-hoc builds remains unverified.

`./scripts/check-automatic-vault.sh --build` builds a fixed, isolated ad-hoc Release fixture without Keychain operations. The opt-in `--run` creates only its own fictional login-Keychain key/vault, starts capture through the production service without touching the system clipboard, verifies exact encrypted persistence in a separate process, then deletes only its synthetic key to prove missing-key preservation/no replacement and removes the fixture files. It never reads a real app vault or accepts caller-supplied paths/content. No authentication prompts are expected with an unlocked default login Keychain. This native fixture is not run by ordinary `make verify`.

The login-Keychain adapter deliberately uses the older `SecAccess` ACL API and file-based Keychain shim; Apple recommends data-protection Keychain in general, but that implementation requires provisioning for access groups. This narrow compatibility use avoids Apple-issued certificates and preserves a caller-only ACL. Deprecation warnings are expected, not suppressed. Changed ad-hoc builds may need renewed Keychain/clipboard approval; no stable publisher identity is claimed. The key is not guaranteed device-only. See [Apple TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains).

### Protected compatibility profile

The following historical Xcode evidence concerns `org.copysaver.CopySaver.dev` and its separate data-protection vault. It does not imply community release validation. Opening the unchanged Xcode scheme retains the previous explicit authentication behavior; use `make app` to test the new community behavior. Existing protected libraries/keys are not migrated or read by community builds.

The repository contains a Swift 6 package with `CopySaverDomain`, `CopySaverVault`, `CopySaverPlatform`, and `CopySaverDesktop` libraries, 124 Swift Testing checks (two benchmarks, four offscreen render/window fixtures, one public-site network smoke and one demo exporter are opt-in), a native development executable, and no external package dependencies. The Xcode app and embedded widget build successfully in Debug and Release for Apple silicon and Intel with signing disabled. Apple Development app/widget builds now pass on the local Apple silicon Mac; protected vault creation, owner-authenticated first unlock, and synthetic clipboard capture/search/copy-back pass. Authenticated relaunch preserves the synthetic history/snippet and resumes capture. Isolated Release helper denial, UI-forbidden protected-read denial and missing-key preservation also pass on this Mac. Full authentication cases, lifecycle/gallery discovery, hosted CI execution, and release binaries remain separate gates. See [spec.md](../spec.md#0-delivery-checklist-and-progress) for verified delivery status.

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

`make app` builds the community Debug executable through SwiftPM, packages `.build/CopySaverDev.app`, and verifies its local ad-hoc signature with sandbox and hardened runtime. `make preview` opens that bundle with `--ui-preview`. The DEBUG-only preview contains fictional records, no vault/authentication services, and no clipboard output. Sample reveal/copy/edit actions are disabled. Lock clears the samples; Reset sample preview restores them. The optimized Release executable excludes the sample records and refuses the preview flag.

Normal community launch follows the automatic profile above. The protected Xcode profile still starts locked and uses data-protection Keychain authentication; ad-hoc signing cannot grant that profile's restricted entitlements. Never select the community backend as a fallback after protected-key failure. On systems with clipboard permission controls, unattended capture requires Always Allow.

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

Debug uses provisional bundle ID `org.copysaver.CopySaver.dev` and scheme `copysaver-dev`; Release uses `org.copysaver.CopySaver` and `copysaver`. Vault paths and Keychain service names derive from the active bundle identity. These identifiers require ownership confirmation before distribution. The Xcode app embeds a launcher widget with a separate identifier; only the parent app requests outgoing network access for website previews; neither target has a shared container.

Native visual inspection and remaining platform gates are recorded in [native-integration.md](native-integration.md). The selected design context is in [PRODUCT.md](../PRODUCT.md) and [DESIGN.md](../DESIGN.md).

## Permissions and safe development

- Do not accept licenses, use `sudo`, install system packages, remove developer frameworks, or change the global developer directory as an automatic test fallback. Request authorization for a concrete system repair when required.
- Use separate development and production bundle identifiers, Keychain namespaces, and vault locations.
- Use synthetic clipboard data and test-owned temporary storage. Never import a production vault or inspect unrelated user content for test fixtures.
- Prefer command-scoped environment settings. Do not modify global Git settings, developer settings, or signing configuration for convenience.
- Never weaken crypto/sandboxing or switch protection profiles implicitly to make a failed operation appear functional. The community profile is explicitly selected in bundle metadata and uses a distinct identity and key namespace.
- Follow [CONTRIBUTING.md](../CONTRIBUTING.md) for branching, commits, validation, and progress updates.

## Verification and release tools

`make verify` runs static project/entitlement/widget dependency checks, local documentation/checklist validation, shell syntax, all package builds, and the functional test suite. `make build` also compiles `CopySaverWidgetCheck`, which checks the real widget entry source; do not run that executable as an app. Actual extension packaging/discovery still needs Xcode and signing. `CopySaverCrashProbe` is a test-only process fixture; its random synthetic key arrives through an anonymous pipe, never a key file/environment/argument. Neither helper is embedded in the application.

The committed [CI workflow](../.github/workflows/ci.yml) runs source verification and an unsigned app/embedded-widget Xcode build on Apple silicon and Intel macOS runners. It has read-only repository permissions and a pinned checkout action. Hosted runs have been attempted and failed at startup before jobs; hosted tests/builds remain unverified. See [release validation](release-checklist.md) for the explicit archive/notarization workflow. Source checks, unsigned builds, and configuration are not proof of signed platform behavior.

`CopySaverKeychainProbe` is a separately signed manual integration fixture, never embedded in CopySaver or its widget. `make verify` builds it and runs 18 unbundled admission checks without Keychain access. The fixed isolated-owner mode lets signed validation proceed in a separate sandbox after the normal development app contains personal history; see the operator procedure. Follow the [signed Keychain procedure](keychain-validation.md) only with a confirmed synthetic development vault and real signing identity. Signed Release fixture isolation, UI-forbidden denial and native missing-key preservation pass on the reference Mac. Touch ID and Mac-password fallback are verified on the reference Mac. Cancelled authentication and broader platform/release cases remain pending.

See [performance evidence](performance.md) for opt-in synthetic benchmarks. The approved support-package repair resolved Xcode loading. A valid Apple Development certificate/private key is now installed and used successfully. In the restricted coding environment, a sandboxed `security find-identity -v -p codesigning` can hide the user Keychain and incorrectly report zero identities; check from an ordinary local terminal or an approved execution environment. Complete native security validation remains pending. Personal Team provisioning profiles expire; rebuild/reprovision as needed rather than weakening the vault protection.

## Community UI review

`COPY_SAVER_RENDER_UI=1 ./scripts/swift.sh test --disable-xctest --filter renderCommunityUIFixtures` renders synthetic Library, Focus, sensitive detail/editor, settings, sidebar, empty-search, long-text and minimum-window PNGs under ignored `.build/ui-review/`. These are offscreen AppKit/SwiftUI views, not screenshots of a user app: the fixture does not activate windows, capture the screen, read Keychain, use the system clipboard or load actual user records. Light/dark rendering and state samples do not establish live keyboard/VoiceOver or animation behavior; those remain manual gates.

## Duplicate local app entries

Use `/Applications/CopySaver.app` for ordinary community use. Installing a new DMG means quitting CopySaver and replacing that same app, rather than keeping a second renamed copy. Development/test builds in `.build/` and Xcode DerivedData use separate identities and storage; macOS may list them as additional apps.

To retire an obsolete build, first preserve a compressed recovery archive if needed, unregister only that exact `.app` path with the local `lsregister -u` command, then remove only that generated app bundle. Keep protected build archives if you may need to reopen the earlier protected library. Do not remove vault/container/Application Support data or Keychain entries, and do not reset the whole Launch Services database. A pinned old Dock shortcut may need to be removed manually. Future Xcode development builds can create separate entries again.

The November 11 local cleanup archives are under ignored `.build/retired-apps/2026-11-11/`, with a manifest of original app locations. They contain app bundles only, not saved clipboard libraries or keys. Recover a retired bundle by extracting its archive to its original parent directory; its original profile and identity remain distinct from the community app.

The focused-launcher regression runs with `COPY_SAVER_RENDER_UI=1 ./scripts/swift.sh test --disable-xctest --filter 'sidebarFocusOutlineFollowsKeyWindow|windowKeyObserverFollowsOnlyItsHostingWindow'`. It checks light/dark rendering with stale focus in a background window, preserved key-window outlines/selection, and window notification scoping/moves/teardown using hidden synthetic windows. It never activates the process or accesses the real app, clipboard or vault. Live mouse → panel → dismiss → Tab/Space/Return and VoiceOver acceptance remain separate native checks.

## Local content previews

`./scripts/swift.sh test --disable-xctest --filter contentPreview` checks classification bounds, HTTP(S) targets, malformed/credential URLs, contacts, JSON token fidelity, exact copying and sensitive/edit/delete/session invalidation. All data and clipboard adapters are synthetic. The existing opt-in `renderCommunityUIFixtures` additionally covers light/dark link, email, phone, JSON and code previews and minimum-width link/JSON details.

Previews analyze complete values up to 16 KiB, with an 8 KiB URL limit; other values use the original text view. Website metadata/image loading is an automatic selected-link exception, implemented without a web view, scripts, cookies or persistent caches. Open in browser is an explicit HTTP(S)-only handoff. JSON formatting is a view of the text, not a stored transformation; the primary Copy action always keeps original bytes. Sensitive snippets never enter the classifier. Remaining live picker, keyboard, browser-handoff and VoiceOver acceptance is tracked in spec.md.

`./scripts/swift.sh test --disable-xctest --filter websitePreview` exercises synthetic metadata, bounded HTTP via a test URLProtocol (no external network), image thumbnail limits, encrypted preference compatibility and late-result guards. `COPY_SAVER_RENDER_UI=1` enables the automatic-on-appearance fixture; `COPY_SAVER_WEB_SMOKE=1` enables a fixed public `https://ogp.me/` title/image check, never accepting a user URL. Ordinary `make verify` does not contact websites.

Website previews are enabled by default under the user's November 12 decision. Settings → Privacy & Storage saves the off choice inside encrypted settings. Only public HTTPS metadata/image requests are supported, with best-effort destination checks, byte/image/time bounds and normal TLS validation. Only the active Library selection is loaded, not every captured link or Focus row. Metadata stays in memory; OS DNS/network services are outside this cache policy. Actual installed-app traffic observation, browser/VoiceOver and supported-OS acceptance remain pending.

## Community beta assets

`release.json` is checked against both app/widget plists and beta labels. `make verify` additionally runs nine synthetic distribution-verifier regressions. From clean reviewed source, `make community-dmg` then `make distribution` creates the versioned beta DMG, safe source archive, install/license/notes, provenance manifest and checksums in ignored `dist/<tag>/`. `bash scripts/draft-community-release.sh` uploads a draft only when explicitly authorized and the exact source is already in GitHub. See [RELEASING.md](RELEASING.md) for the publication, visibility and security-reporting gates.

## Feature-tour media

`python3 scripts/build-demo-video.py` runs the opt-in `exportDemoVideoFrames` fixture and produces the checked-in 42-second H.264 MP4, expandable GIF, poster, WebVTT captions and transcript under `docs/media/`. It requires locally available `ffmpeg` and `ffprobe` for authoring only; neither is an app/runtime or ordinary test dependency. Nothing is downloaded or installed. `--encode-only` reuses the ignored `.build/demo-video/` frames. Run from a Mac with the documented Swift toolchain and review the frames before committing media.

The fixture drives the production DesktopModel, LibraryView and FocusView using an in-memory actor, clipboard sink and synthetic website loader. Assertions cover synthetic capture, search, exact copying, snippet saving and sensitive body-search exclusion. Hidden windows are rendered offscreen; no real clipboard, Keychain, vault, screen capture, app discovery or network is used. The fallback sidebar icon is the unbundled test host's SF Symbol; the approved icon is shown in the tour header. The visible demo label, README and transcript distinguish this staged tour from OS integration evidence. No real global shortcut, OS clipboard approval, encryption-at-rest, widget discovery or accessibility acceptance is established by the video.

The README links the small MP4 through a static poster and puts the looping GIF behind an expandable disclosure. A transcript and captions provide a text alternative. This avoids relying on unsupported raw video HTML or requiring autoplay; GitHub's own media rendering remains a separate publishing check. The assets are repository documentation, not changes to the immutable beta release bundle.
