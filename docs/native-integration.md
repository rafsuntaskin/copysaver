# Native development integration

The `feat/native-app` branch is stacked on vault foundation `06359fe`. It adds a runnable development scaffold, not a release. The delivery gates in [spec.md](../spec.md) remain authoritative.

## Implemented source

- `CopySaverPlatform`: device-only data-protection Keychain adapter, generation-guarded desktop vault service, and exact navigation routes. Keys use `WhenUnlockedThisDeviceOnly`, user presence, no synchronization, no shared access group, and no file/plaintext fallback. Creation uses add-only semantics. Each read gets a fresh `LAContext`, with reuse disabled and cancellation invalidating that context. Blocking Security calls run off the main actor.
- `CopySaverDesktop`: observable presentation state, three-column library, inline snippet creation, snippet deletion, masked sensitive details, in-memory search, compact Focus panel, menu bar actions, appearance preferences, and global shortcut registration/recording. Authentication, UI state, and copy completion cannot cross a lock generation; sensitive actions also cannot cross a conceal/deactivation boundary.
- Clipboard output: current-host-only writes, source and opaque ownership markers, concealed marker for sensitive content, accurate failure feedback, and 30-second owned-sensitive expiry. Cleanup checks both change count and owner marker and never restores an older clipboard buffer.
- App project: shared Xcode scheme, Debug/Release identity separation, app sandbox, and hardened runtime. SwiftPM builds the same desktop implementation through the working standalone tools.

This is partial implementation of M1-08/M1-09/M1-11/M1-12, M2-05–M2-10, and M3-01/M3-03–M3-07. These checklist tasks include additional behavior or native verification and remain unchecked. Clipboard monitoring, transactional retention, encrypted history preferences, explicit permission guidance, and pause/resume are now implemented. Template/edit flow, history promotion, pinning, copy timestamps, login preferences, compact navigation, and confirmed reset are now implemented. The WidgetKit library/entry point, embedded Xcode extension target, and CI/release tooling now exist; signed packaging and native execution remain pending.

## Reproducible checks

Checks recorded October 26–27, 2026, using Command Line Tools Swift 6.3.3 on Apple silicon macOS 26.6.2:

| Check | Result and limit |
| --- | --- |
| `make build` then `make test` from a clean staged-source export | Current Debug verification discovers 89 checks (87 functional tests plus two opt-in benchmarks); functional tests pass. Earlier optimized benchmark evidence is recorded below; it does not include the three new clipboard regressions. Includes real CryptoKit/SQLite, injected Keychain transport, in-memory pasteboard bridge, exact routes, preview isolation, fresh-auth requirements, and delayed authentication/lock/deactivation races. No real Keychain item, system clipboard, or user vault is used. |
| `make app` | Debug executable built, development bundle packaged, ad-hoc sandbox/hardened signature verified. This establishes local build/integrity only. |
| `./scripts/swift.sh build -c release --product CopySaverDev` | Optimized executable built; sample fixture code is DEBUG-only. Release refuses `--ui-preview`; sample-string exclusion checked in the optimized executable. This is not an Xcode archive or notarized application. |
| `plutil -lint` on project, Info.plist, entitlements | Passed. Parsed 22 project objects; checked object references, source paths, shared-scheme target, distinct identities/schemes, and minimal entitlements. This does not establish Xcode project buildability. |
| `bash -n scripts/swift.sh scripts/build-app.sh` | Passed. |

## Native visual inspection

The development preview was launched with `--ui-preview`. The native library was inspected in light and dark appearances; its three-column layout, rows, detail pane, settings controls, and disabled sample copy actions rendered. Opening Focus mode through the sidebar displayed the compact panel with its search field focused.

The critique pass moved the library title/search into one header row, added a direct Focus mode sidebar action, and removed the Focus picker’s redundant visible label. The final build compiles these refinements. The Mac became locked before the last visual recheck, so that repeat inspection is pending. Complete keyboard, VoiceOver, increased-contrast, reduced-motion, shortcut, multi-display, and Spaces coverage has not passed.

The preview is a separate DEBUG-only mode with fictional records and no vault/authentication/clipboard dependencies. It is never a fallback after a real vault error. Preview copy, reveal, and persistence actions are disabled; locking purges sample presentation state. It is suitable for inspecting layout, not proving authentication or capture behavior.

## Remaining platform gates

- **M1-08–M1-10:** Build the Xcode project with a real development identity, verify device-only user-presence enforcement/password fallback, cancellation/lockout, and denial to a separately signed helper. Verify a clean install, reopen, and missing-key preservation. The user-approved support-package repair resolved SDK loading; unsigned universal app/widget builds pass. A valid signing identity is still missing.
- **M1-11:** Prove all lock paths on supported macOS versions. Public sleep/session/display-sleep observers and the encrypted 5/15/30-minute or system-lock-only idle preference are wired. The supplemental `com.apple.screenIsLocked` distributed notification name is undocumented and is not accepted as supported lock coverage. Resolve that dependency before completing the gate. Capture remains off by default; enabling it requires an explicit action while unlocked.
- **M1-12/M2-08/M2-10/M3-06:** Verify real sandboxed pasteboard permissions, external-copy races, expiry across sleep/wake, global shortcut conflict/atomic replacement, focus restoration, active Space/full-screen behavior, and panel keyboard actions. Unit tests establish policy/state behavior only. Command/Control is required in a custom shortcut; plain typing, Option-only bindings, and Command-Space are rejected. Shortcut validation cannot detect every system or app reservation before registration.
- **M1-13/M4:** Package/test the generic launcher widget, then audit discovery, URL routing on cold/locked launch, accessibility, performance, diagnostics, entitlements, and signed distribution.

Only appearance and shortcut preferences use UserDefaults. The app sandbox entitlement is the only explicitly requested entitlement; there is no network entitlement, shared container, or shared Keychain group. Development and production identifiers remain provisional pending ownership confirmation. No release security claim follows from these source or unit checks.

## Clipboard implementation update

`feat/clipboard-history` adds 500 ms polling while capture is admitted, one-item plain-text admission, all standard and legacy transient/confidential markers, conservative private-key/Luhn filtering, excluded-app activation rebaselines, exact UTF-8 duplicate refresh, age/count/payload retention, and encrypted preferences. `VaultSession.update` plans and commits in one actor turn so concurrent edits/captures do not lose records. The true ciphertext budget includes verification overhead. Tests use an injected input bridge; real OS permission behavior remains pending.

On macOS 15.4+, polling requires `NSPasteboard.accessBehavior == .alwaysAllow`; Default/Ask shows a permission-needed state and never repeatedly prompts. The explicit Request access action discards its read and rebaselines; the user chooses Always Allow in System Settings for background capture. Older systems use ordinary pasteboard APIs and still require explicit capture enablement. APIs/availability were checked against the installed AppKit SDK. Marker policy follows [NSPasteboard.org](https://nspasteboard.org/). Source hints and application attribution are untrusted and cannot guarantee exclusion of every sensitive copy.

Validation: 67-test full suite and an additional transactional Unicode-edit regression passed, including 12 concurrent identical captures against production CryptoKit/SQLite and pause/reopen/clear-history preservation. Native permissions, near-limit performance, and crash/OS lifecycle acceptance are still separate gates.

## Snippet and library completion update

The native source now supports category-aware create/edit/delete, templates, independent history promotion, pinning, copy timestamps, and 480-point compact navigation. Sensitive editing and sensitivity changes authenticate freshly; deactivation conceals private draft fields until fresh authentication. A dedicated AppKit body editor routes Copy/Cut through ownership/authentication policy, blocks dragging and Services export, disables automatic text analysis, and owns/clears its own undo history. Sensitive details remain unselectable while masked/revealed; ordinary selectable details also use owned clipboard writes. Native keyboard/VoiceOver verification remains open.

Reset is explicitly confirmed, locks/purges presentation first, authenticates when a key exists, closes/checkpoints SQLite, and removes only the owned vault/sidecar paths and key. Missing-key reset is supported. A structurally unreadable vault that cannot supply its identity fails safely for manual diagnosis; no unrelated paths or guessed Keychain entries are deleted. Reset does not promise secure erasure of backups/snapshots.

Login registration uses `SMAppService.mainApp` only on explicit toggle; login launch is detected from the documented [launch Apple event](https://developer.apple.com/documentation/coreservices/apple_events/1556410-launch_apple_event_constants) and stays locked in the menu bar. Actual registration/login and signed OS authentication still require native integration evidence.

Validation: 77-test suite plus cancelled draft-copy regression passed (78 total tests). Includes sensitivity changes, private drafts, exact Unicode, copy timestamps, promotion, card template defaults, pinned/snippet capacity, confirmed limits, cancelled reset, and missing-key recovery.

Native preview follow-up: the Mac was available again. Verified library search updates row/detail selection, sensitive sample body is absent from the AX tree, 613-point compact resize/back navigation, Focus search autofocus/filtering, and Escape dismissal. The critique pass removed an unnecessary text-view scrollbar and corrected singular observation wording. Full VoiceOver, real auth/copy, login, Spaces, and minimum-OS checks remain pending.

## Widget, release tooling, and hardening update

The launcher has small/medium layouts, static generic labels, current-date-only timeline entries, exact navigation links and no app/vault/clipboard/Keychain dependency or shared entitlement. SwiftPM compiles both its library and real entry source; static checks validate the embedded extension dependency/build phase and separate Debug/Release identifiers. Its gallery placement, snapshots, actual extension build and cold/locked navigation still require signed native evidence. The standalone `make preview` bundle does not embed/install a widget.

`make verify` now checks project references, minimal entitlements, widget dependencies, Markdown links/task IDs, shell syntax, builds and tests. CI is configured for Apple silicon/Intel app-and-widget builds with signing disabled, read-only permissions and a pinned [checkout release](https://github.com/actions/checkout/releases/tag/v7.0.1); no hosted run is claimed. The explicit release script prepares universal Developer ID archives and notarized/stapled DMGs, checksums and inventories, but has not been run with credentials and never publishes.

Security hardening conceals existing reveals on a fresh cancelled auth, locks presentation on all integrity failures, clears window field-editor/undo state on lock, pauses capture during cleanup review, and stops admission on capacity failure. A real child-process SIGKILL test now covers a committed encrypted record plus a pending encrypted transaction, verifies recovery and scans DB/WAL/SHM canaries. Its synthetic random key is sent only through an anonymous pipe; the crash fixture is never part of the app.

See [performance evidence](performance.md). Full Xcode project discovery was attempted again and still fails before project loading with the CoreDevice `_XPCTypeBool` mismatch. Installed support resources report 16.1; Apple's bundled replacement package signature passes; no repair was performed. There are zero valid code-signing identities on the machine. Native automation timed out during a separate synthetic-app shortcut check; that scenario was not marked passed.

Final verification also covers the real widget entry point, bounded pipe-based forced termination with an uncommitted encrypted transaction, cleanup-review admission, successful-copy dismissal/metadata ordering, capacity-stop state, and late shortcut events after clearing. Debug has 85 registered checks with two opt-in benchmarks; the full applicable optimized Release run passes 83 checks with both benchmarks enabled. `make app` packages/verifies the local ad-hoc bundle. Archive/notarization remain unexecuted.

The final clean staged-source export passed `make verify`, including both entry-point builds, all static checks and the 83 functional tests (two opt-in benchmarks skipped in that Debug run). The release script’s help/invalid-action guards and CI YAML syntax were checked; archive/notarization were not attempted.

Native first-run check: the isolated development identity showed the device-bound/no-backup disclosure with history off. Attempting protected setup produced the expected missing-signing-entitlement error; no unlocked state or plaintext fallback appeared. The error view was refined to direct retry and avoid offering reset before a vault exists. This negative ad-hoc result is not signed Keychain isolation evidence.

Final native pass: the updated saved-text view rendered correctly in both light and dark appearance, Focus arrow navigation moved selection, Escape preserved selection back in the library, and the synthetic preview was restored to System appearance. Setup retry returned safely to the create screen after the ad-hoc signing failure. These checks do not replace signed auth, real clipboard, widget gallery, or full VoiceOver coverage.

Draft-navigation follow-up: returning to Snippets now restores the item being edited, cancelled row selection cannot continue a context Copy/Delete action, unchanged edits close without a false unsaved warning, dirty detection preserves exact Unicode bytes, and saving an edit keeps a newer copy timestamp. Targeted regressions and full Debug verification pass (84 functional tests plus two opt-in benchmark checks registered).

The final draft fix also passes the full optimized Release run (84 applicable checks, including both benchmarks), and the updated local app bundle builds and verifies. The clean-source fixture is rechecked after this fix.

## Approved Xcode repair and universal builds

The user explicitly approved installing Apple's bundled `XcodeSystemResources.pkg`. Apple signature verification passed, Apple Installer reported success, and `pkgutil --pkg-info com.apple.pkg.XcodeSystemResources` now reports `27.1.0.0.1790739719`. Xcode 27.1 (27A9275) discovers its SDKs and Swift 6.4. This supersedes the earlier loader blocker recorded above. No global developer-directory change or additional support-package installation was performed. `xcodebuild -checkFirstLaunchStatus` still exits 69 without diagnostics; that does not prevent these macOS builds.

Both commands pass with process-local `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:

```sh
xcodebuild -project CopySaver.xcodeproj -scheme CopySaver -configuration Debug \
  -destination 'generic/platform=macOS' -derivedDataPath .build/xcode-verification \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CopySaver.xcodeproj -scheme CopySaver -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath .build/xcode-verification \
  CODE_SIGNING_ALLOWED=NO build
```

`lipo -archs` confirms arm64 and x86_64 in each app and embedded extension. Processed plists confirm separate development/production app and widget identifiers, the matching `copysaver-dev`/`copysaver` navigation schemes, and the WidgetKit extension point. The Release executable excludes the synthetic preview body. Xcode emits a skipped App Intents metadata extraction warning because the app has no AppIntents dependency. Signing is disabled, so these builds do not establish hardened-runtime, sandbox, authentication or widget-gallery behavior.

`env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make verify` also passes using Swift 6.4: 86 checks registered, 84 functional checks passed and two opt-in benchmarks skipped. Static project/privacy/docs and shell checks pass. Zero valid code-signing identities remain installed; real Keychain and release gates stay open. Another native automation attempt stalled while switching to Finder, so the cross-app shortcut scenario remains unverified.

## Signed boundary-probe preparation

`CopySaverKeychainProbe` now has a separate Xcode app target and shared scheme, with no product dependency or embedding. The real Release app/widget build still passes and does not build the probe. Static checks cover the helper's minimal sandbox entitlement and exclusion from the app/widget source/embed graph. Its `SKIP_INSTALL` setting and non-archiving scheme keep it outside release packaging.

The fixture uses the production Keychain provider for its own authenticated control and the explicitly confirmed synthetic `.dev` target. It refuses unbundled/ad-hoc or mismatched identities before any Keychain call; only item-not-found is an expected target observation. Failed auth, missing entitlements, unexpected access or cleanup failure never pass. The [operator procedure](keychain-validation.md) requires owner authentication before and after, plus same-team/distinct-identifier entitlement audits, to exclude missing-key false positives.

SwiftPM builds pass with Swift 6.3.3 and 6.4; the unsigned Xcode Debug helper contains arm64 and x86_64. Seven admission checks pass against both unbundled toolchain builds and the unsigned Xcode bundle without Keychain operations. Full Swift 6.4 `make verify` passes 84 functional checks and seven helper guard cases, with two opt-in benchmarks skipped. Actual signed probing/authentication remains unexecuted because there are zero valid signing identities. M1-10/SEC-05 stay unchecked.

## Clipboard cleanup race and cross-layer verification

`cleanupRechecksChangeCountAfterReadingOwnershipMarker` first failed: an injected external copy during the ownership-marker read was erased. The implementation now verifies the original change count again after that read, and the regression passes. This closes that observed interval; checking and clearing remain separate operations, so a later external write can still race clearing. Real pasteboard timing/sleep-wake review and SEC-08 remain pending.

The [pipeline tests](../Tests/CopySaverDesktopTests/ClipboardPipelineTests.swift) connect the real monitor, model, desktop service, encryption, serialization, retention and SQLite persistence to an in-memory Keychain transport and an in-memory pasteboard. They verify exact Unicode/whitespace capture → encrypted commit → search → owned copy, duplicate refresh/copy metadata, no self-write feedback, pause across locked reopen, no old-content import after permission restoration, cancelled sensitive authentication, concealed copy/expiry, newer external content surviving lock, snippet reopen and DB/WAL/SHM body/title/category/source canaries. They never access a real vault, Keychain item or system clipboard.

Targeted regression command passes three tests: `./scripts/swift.sh test --disable-xctest --filter 'cleanupRechecksChangeCountAfterReadingOwnershipMarker|historyPipeline|sensitiveSnippetPipeline'`. Full CLT Swift 6.3.3 `make verify` passes 87 functional tests, two opt-in benchmarks skipped, and seven probe admission checks. The Xcode Swift 6.4 universal unsigned Release app/widget build passes; `make app` refreshes and verifies the ad-hoc development bundle. These cross-layer checks advance M2-11/M3-06 evidence without passing native FUNC/SEC gates.

## My Mac Debug architecture alignment

Running the scheme in Xcode initially failed after both an ordinary build and Clean Build Folder: the native widget compiled x86_64 and arm64, while its Swift package compiled only the active arm64 slice. Build commands showed the mismatch; this was not resolved by cleaning caches. Project-level Debug `ONLY_ACTIVE_ARCH=YES` aligns native targets with the package. Xcode's My Mac build/run then passed and launched the normal arm64 app. CI uses an explicit `ONLY_ACTIVE_ARCH=NO` override for universal coverage.

`env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CopySaver.xcodeproj -scheme CopySaver -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath .build/xcode-verification ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build` passes; `lipo -archs` confirms arm64 and x86_64 in the app and embedded widget. Static checks enforce the Debug/Release architecture defaults. No Swift runtime code changed in this fix.

The user selected Sign to Run Locally for app/widget Debug. The resulting app passes strict signature verification but reports `Signature=adhoc` and no TeamIdentifier. Its only emitted entitlements are sandbox and Debug get-task-allow. The real Create encrypted vault action fails closed with the expected missing-Keychain-entitlement message. No vault unlock/capture is claimed, and no plaintext/authentication fallback was added. The user's personal team/local-signing edits remain uncommitted and are preserved separately from the shared architecture fix.
