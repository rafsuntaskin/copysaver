# Native development integration

The `feat/native-app` branch is stacked on vault foundation `06359fe`. It adds a runnable development scaffold, not a release. The delivery gates in [spec.md](../spec.md) remain authoritative.

## Implemented source

- `CopySaverPlatform`: device-only data-protection Keychain adapter, generation-guarded desktop vault service, and exact navigation routes. Keys use `WhenUnlockedThisDeviceOnly`, user presence, no synchronization, no shared access group, and no file/plaintext fallback. Creation uses add-only semantics. Each read gets a fresh `LAContext`, with reuse disabled and cancellation invalidating that context. Blocking Security calls run off the main actor.
- `CopySaverDesktop`: observable presentation state, three-column library, inline snippet creation, snippet deletion, masked sensitive details, in-memory search, compact Focus panel, menu bar actions, appearance preferences, and global shortcut registration/recording. Authentication, UI state, and copy completion cannot cross a lock generation; sensitive actions also cannot cross a conceal/deactivation boundary.
- Clipboard output: current-host-only writes, source and opaque ownership markers, concealed marker for sensitive content, accurate failure feedback, and 30-second owned-sensitive expiry. Cleanup checks both change count and owner marker and never restores an older clipboard buffer.
- App project: shared Xcode scheme, Debug/Release identity separation, app sandbox, and hardened runtime. SwiftPM builds the same desktop implementation through the working standalone tools.

This is partial implementation of M1-08/M1-09/M1-11/M1-12, M2-05–M2-10, and M3-01/M3-03–M3-07. These checklist tasks include additional behavior or native verification and remain unchecked. Clipboard monitoring, transactional retention, encrypted history preferences, explicit permission guidance, and pause/resume are now implemented. Template/edit flow, history promotion, widget target, and release pipeline remain pending.

## Reproducible checks

On October 26, 2026, using Command Line Tools Swift 6.3.3 on Apple silicon macOS 26.6.2:

| Check | Result and limit |
| --- | --- |
| `make build` then `make test` from a clean staged-source export | Build and 55 Swift Testing tests passed. Includes real CryptoKit/SQLite, injected Keychain transport, in-memory pasteboard bridge, exact routes, preview isolation, fresh-auth requirements, and delayed authentication/lock/deactivation races. No real Keychain item, system clipboard, or user vault is used. |
| `make app` | Debug executable built, development bundle packaged, ad-hoc sandbox/hardened signature verified. This establishes local build/integrity only. |
| `./scripts/swift.sh build -c release --product CopySaverDev` | Optimized executable built; sample fixture code is DEBUG-only. Release refuses `--ui-preview`; sample-string exclusion checked in the optimized executable. This is not an Xcode archive or notarized application. |
| `plutil -lint` on project, Info.plist, entitlements | Passed. Parsed 22 project objects; checked object references, source paths, shared-scheme target, distinct identities/schemes, and minimal entitlements. This does not establish Xcode project buildability. |
| `bash -n scripts/swift.sh scripts/build-app.sh` | Passed. |

## Native visual inspection

The development preview was launched with `--ui-preview`. The native library was inspected in light and dark appearances; its three-column layout, rows, detail pane, settings controls, and disabled sample copy actions rendered. Opening Focus mode through the sidebar displayed the compact panel with its search field focused.

The critique pass moved the library title/search into one header row, added a direct Focus mode sidebar action, and removed the Focus picker’s redundant visible label. The final build compiles these refinements. The Mac became locked before the last visual recheck, so that repeat inspection is pending. Complete keyboard, VoiceOver, increased-contrast, reduced-motion, shortcut, multi-display, and Spaces coverage has not passed.

The preview is a separate DEBUG-only mode with fictional records and no vault/authentication/clipboard dependencies. It is never a fallback after a real vault error. Preview copy, reveal, and persistence actions are disabled; locking purges sample presentation state. It is suitable for inspecting layout, not proving authentication or capture behavior.

## Remaining platform gates

- **M1-08–M1-10:** Build the Xcode project with a real development identity, verify device-only user-presence enforcement/password fallback, cancellation/lockout, and denial to a separately signed helper. Verify a clean install, reopen, and missing-key preservation. Local Xcode SDK loading remains blocked by the previously recorded CoreDevice support-package mismatch; no repair was performed.
- **M1-11:** Prove all lock paths on supported macOS versions. Public sleep/session/display-sleep observers and the encrypted 5/15/30-minute or system-lock-only idle preference are wired. The supplemental `com.apple.screenIsLocked` distributed notification name is undocumented and is not accepted as supported lock coverage. Resolve that dependency before completing the gate. Capture remains off by default; enabling it requires an explicit action while unlocked.
- **M1-12/M2-08/M2-10/M3-06:** Verify real sandboxed pasteboard permissions, external-copy races, expiry across sleep/wake, global shortcut conflict/atomic replacement, focus restoration, active Space/full-screen behavior, and panel keyboard actions. Unit tests establish policy/state behavior only. Command/Control is required in a custom shortcut; plain typing, Option-only bindings, and Command-Space are rejected. Shortcut validation cannot detect every system or app reservation before registration.
- **M1-13/M4:** Package/test the generic launcher widget, then audit discovery, URL routing on cold/locked launch, accessibility, performance, diagnostics, entitlements, and signed distribution.

Only appearance and shortcut preferences use UserDefaults. The app sandbox entitlement is the only explicitly requested entitlement; there is no network entitlement, shared container, or shared Keychain group. Development and production identifiers remain provisional pending ownership confirmation. No release security claim follows from these source or unit checks.

## Clipboard implementation update

`feat/clipboard-history` adds 500 ms polling while capture is admitted, one-item plain-text admission, all standard and legacy transient/confidential markers, conservative private-key/Luhn filtering, excluded-app activation rebaselines, exact UTF-8 duplicate refresh, age/count/payload retention, and encrypted preferences. `VaultSession.update` plans and commits in one actor turn so concurrent edits/captures do not lose records. The true ciphertext budget includes verification overhead. Tests use an injected input bridge; real OS permission behavior remains pending.

On macOS 15.4+, polling requires `NSPasteboard.accessBehavior == .alwaysAllow`; Default/Ask shows a permission-needed state and never repeatedly prompts. The explicit Request access action discards its read and rebaselines; the user chooses Always Allow in System Settings for background capture. Older systems use ordinary pasteboard APIs and still require explicit capture enablement. APIs/availability were checked against the installed AppKit SDK. Marker policy follows [NSPasteboard.org](https://nspasteboard.org/). Source hints and application attribution are untrusted and cannot guarantee exclusion of every sensitive copy.

Validation: 67-test full suite and an additional transactional Unicode-edit regression passed, including 12 concurrent identical captures against production CryptoKit/SQLite and pause/reopen/clear-history preservation. Native permissions, near-limit performance, and crash/OS lifecycle acceptance are still separate gates.
