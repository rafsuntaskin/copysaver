# CopySaver: product and technical specification

Status: tested encrypted core and runnable native development scaffold; product/architecture and selected UI baseline approved. Clipboard capture/retention are implemented through testable adapters; widget source and release tooling are implemented; signed platform checks remain pending. Track verified completion below.

Created: October 26, 2026. Last updated: October 29, 2026.

## 0. Delivery checklist and progress

### Tracking rules

This section is the working delivery plan. Sections 1–17 define the requirements; section 12 contains independently tracked acceptance checks. Update affected requirements, checklist items, evidence, and this progress log in the same implementation commit.

- `[x]` means the deliverable exists and its stated validation passed. `[ ]` means pending, in progress, or blocked; use the status/evidence table to distinguish them.
- IDs are stable. Add new IDs for added work rather than renumbering referenced tasks. Document scope changes or superseded tasks in the progress log.
- A task is complete only when its code/docs, meaningful validation, and required progress update are present. A test plan or generated screenshot is not verification evidence.
- A milestone is complete only when every task and its exit criteria pass. Passing core tests does not complete signed integration or release checks.
- Record commands/results, test targets, file references, or named manual scenarios. Do not put real clipboard data, credentials, or private vault details in evidence.
- Use [AGENTS.md](AGENTS.md) and [CONTRIBUTING.md](CONTRIBUTING.md) for branch, commit, and handoff procedures.

### Current status and dependencies

| Area | Status | Evidence / next action |
| --- | --- | --- |
| M0: repository and plan | Complete | Bootstrap commit `d8d1346`; planning documents and design references validated on `docs/project-foundation`. See M0-07 and the progress log. |
| M1: independently testable core | Complete | M1-01–M1-07 implemented; `make build && make test` passed from a clean tracked-source export with 31 tests. Native scaffold and Keychain adapter source now exist; 87 functional Debug tests pass; two opt-in benchmarks have prior optimized measurements. M1 as a whole remains incomplete. |
| M1: native development preview | Available | `make preview` launches a sample-only SwiftUI/AppKit app built through Command Line Tools. No capture, real Keychain, or clipboard access in preview. See [native evidence](docs/native-integration.md). |
| M1: signed platform integration | In progress; remaining security cases open | Apple Development app/widget and separate probe builds pass with distinct app-scoped Keychain groups. Protected creation, authenticated relaunch, exact history/snippet persistence and native capture/search/copy-back pass. Signed isolated-helper denial, UI-forbidden read denial and native missing-key preservation pass on the reference Mac. Touch ID and Mac-password fallback are verified; remaining native security cases remain pending. Universal unsigned Debug/Release builds also pass. See [development setup](docs/development.md). |
| M2: history and Focus mode | In progress | Capture, privacy admission, exact-byte deduplication, transactional retention, pinning, encrypted preferences, and pause/resume are implemented. Basic native capture/search/copy and persistence pass; broader native cases remain pending. |
| M3: snippets and sensitive actions | In progress | Snippet CRUD, categories/templates, promotion, sensitive edit/reveal/copy guards, and reset flows are implemented/tested; native authentication and accessibility validation remain pending. |
| M4: widgets and release hardening | Source implemented; native/release gates open | Universal app/widget builds, static privacy checks, CI/release tools, forced-crash tests and core benchmarks pass locally. Community ad-hoc DMG tooling avoids Apple credentials; hosted CI, gallery/OS/accessibility and clean-Mac/update acceptance remain pending. Protected Developer ID distribution is optional and unverified. |
| Portable backup / Windows | Deferred | Outside v0.1; not included in current completion totals. |

Core and policy implementation may proceed while signed integrations are blocked, as authorized by the user. UI scaffolding can follow the approved direction. Do not treat provisional platform adapters, unsigned previews, or a compiler check as a completed M1 exit gate or a validated release.

### M0: repository and planning foundation

- [x] **M0-01** Initialize `main` with a bootstrap commit and use a dedicated planning branch. Evidence: `d8d1346` (`chore(repo): initialize repository`); planning branch `docs/project-foundation` created and committed as `11caee9`.
- [x] **M0-02** Add repository agent guidance and a documented branch/review/Conventional Commit workflow. Evidence: [AGENTS.md](AGENTS.md) and [CONTRIBUTING.md](CONTRIBUTING.md).
- [x] **M0-03** Add an accurate README, MIT license, development guide, security reporting policy, PR template, ignore rules, and editor/attribute defaults. Evidence: root documents, `docs/development.md`, `.github/pull_request_template.md`, and repository configuration files.
- [x] **M0-04** Consolidate scope, security requirements, stable delivery IDs, independent acceptance gates, and progress-update rules in this spec.
- [x] **M0-05** Preserve selected UI references and widget requirements. Evidence: [designs/README.md](designs/README.md), concepts 1/2, and sections 4.2–4.5 and 9. Concept 3 remains unselected.
- [x] **M0-06** Record the usable standalone toolchain and the full-Xcode blocker without modifying system components. Evidence: [development setup](docs/development.md); temporary SwiftUI/AppKit/CryptoKit/SQLite check passed outside the repository.
- [x] **M0-07** Validate document links, task-ID uniqueness, checklist accounting, staged whitespace, and artifact exclusions; review and commit the foundation branch. Evidence: 9 Markdown files, 35 local links/anchors, 75 unique task IDs, and 3 valid PNGs checked; `git check-ignore --stdin` preserved source/design/lockfile tracking while excluding secret/runtime/build candidates; `git diff --cached --check` passed. This foundation commit records the reviewed deliverables.

### M1: platform and encrypted vault foundation

Independently testable core:

- [x] **M1-01** Add the Swift package/module scaffold and documented, reproducible core build/test entry points using the available toolchain. Evidence: [Package.swift](Package.swift), `make build` and `make test`; clean tracked-source export passed with Swift 6.3.3 and 31 tests.
- [x] **M1-02** Implement versioned history/snippet/settings models, UTC timestamps, and lossless text serialization with validation for stated limits. Evidence: [domain models](Sources/CopySaverDomain/Records.swift); UTF-8/whitespace/date round trips, boundaries, defaults, and decode revalidation tested.
- [x] **M1-03** Implement AES-256-GCM envelopes, fresh nonces, authenticated vault/record/version identity, and the vault verification record. Evidence: [record cipher](Sources/CopySaverVault/RecordCipher.swift), real CryptoKit tests, and independent OpenSSL envelope fixture.
- [x] **M1-04** Add serialized SQLite persistence, parameterized SQL, durable transactions, bounded WAL handling, and the encrypted payload budget. Evidence: [SQLite store](Sources/CopySaverVault/SQLiteRecordStore.swift); persistence/reopen, checkpoints, per-record and aggregate budget rollback, and injected write failure tested.
- [x] **M1-05** Add schema/envelope migration policy and fail-safe missing-key, corruption, unsupported-version, and write-failure behavior. Evidence: [format/policy](docs/vault-format.md); initial schema 1 has no legacy migration, unknown schemas are preserved/rejected, missing/wrong-key cases preserve data, and corrupt reads lock the session.
- [x] **M1-06** Test production CryptoKit round trips, tampering/row swaps, repeat-update nonces, synthetic plaintext-canary scans, and transaction recovery. Evidence: `make test` passed 31 tests, including database/WAL/SHM scans and abandoned-transaction recovery. SEC-02/SEC-03 pass; SEC-01/SEC-04 retain app-level scenarios and remain unchecked. Later forced-SIGKILL coverage verifies committed recovery plus rollback of a pending encrypted transaction; app-level crash scenarios remain part of SEC-01/SEC-06.
- [x] **M1-07** Add testable session/capture-state interfaces and cancellation/generation handling; cover delayed reads, writes, and queries crossing lock. Evidence: [vault session](Sources/CopySaverVault/VaultSession.swift) and [capture admission](Sources/CopySaverDomain/CaptureConditions.swift); stale read/write tokens, delayed/cancelled authentication, cancelled mutations, and all 48 capture-condition combinations tested. Native lifecycle/UI cancellation is still M1-11.

Native/signed integration (check each task only after its own validation):

- [x] **M1-08** Add the committed Xcode app project, shared schemes, development/production identity separation, sandbox, and hardened-runtime configuration. Evidence: universal unsigned Debug/Release builds, My Mac Debug build/run, and Apple Development app/widget builds pass; strict signature/entitlement inspection verifies sandbox/hardened runtime and separate identities. App/probe have distinct own-bundle Keychain groups; widget has none. Protected development vault creation succeeds. See [signed evidence](docs/native-integration.md#provisioned-development-keychain-identity). Native Keychain storage/fallback and isolated validation pass in M1-09/M1-10. No release validation is implied.
- [x] **M1-09** Implement device-only, app-scoped Keychain key storage with user-presence authentication, password fallback, and no plaintext fallback. Evidence: adapter/query-policy tests verify data-protection Keychain, device-only user presence and no synchronization; signed owner/helper enforcement and UI-forbidden reads pass. Native owner creation and authenticated relaunch pass with Touch ID. The user confirms Mac-password authentication for the successful final Release `missing-key` fixture run, whose initial protected read verifies the exact canary through the production provider/service. See [signed evidence](docs/keychain-validation.md#user-presence-negative-control-october-29-2026). Cancellation/lifecycle and distribution remain separate gates.
- [x] **M1-10** Validate authenticated Keychain access with a signed app and denial from a separately signed helper; preserve existing vaults when the key is missing. Evidence: [isolated Release owner/helper procedure](docs/keychain-validation.md) passes on Apple silicon macOS 26.6.2 with real profiles, distinct own-bundle groups and no debugger entitlement. Owner exact-text unlocks succeed before/after helper denial; helper authenticated controls and cleanup pass. Fresh UI-forbidden reads are denied. The native `missing-key` scenario refuses unlock/writes, preserves exact DB/WAL/SHM bytes and creates no replacement key before explicit synthetic cleanup. Password/cancellation and wider platform gates remain separate.
- [ ] **M1-11** Integrate public system/session/sleep/idle events and prove capture stops and decrypted state is concealed on all lock paths. **In progress:** Public lifecycle observers, presentation purge/generation tests, and provisional idle handling exist. Actual OS lock coverage and supported replacement for the supplemental undocumented screen-lock signal remain pending.
- [ ] **M1-12** Prove sandboxed pasteboard access/permission behavior and a global shortcut without Accessibility or Input Monitoring permission. **In progress:** Clipboard/hotkey adapters compile; in-memory ownership/expiry/failure tests pass. Signed sandboxed capture passes after the owner permits clipboard access. Denial/recovery and actual global-shortcut/Spaces scenarios remain pending.
- [ ] **M1-13** Prove minimal WidgetKit-to-app navigation without sharing vault data or Keychain access; validate strict URL routing. **In progress:** Exact URL parser and malformed-route tests exist; widget extension and navigation integration remain pending.
- [ ] **M1-14** Pass the M1 exit scenario: signed create → unlock → encrypted save → relaunch → authenticated load, unauthorized-helper denial, and safe denied-permission/missing-key handling. Record supported OS/toolchain evidence.

### M2: clipboard history and Focus mode

- [x] **M2-01** Implement change-count polling, permission-aware admission, startup/resume baselines, size/type checks, and mid-read change rejection. Evidence: `ClipboardMonitorTests` cover no-read baselines, pause/permission restoration, wraparound, markers, and mid-read races; native permissions remain M1-12.
- [x] **M2-02** Implement confidential/transient/generated marker exclusions, conservative secret filtering, application exclusions, and source/activation race handling. Evidence: marker/Luhn/private-key policies, excluded activation/source-hint tests, editable encrypted exclusions and installed password-manager suggestions. Native privacy/attribution acceptance remains SEC-09.
- [x] **M2-03** Implement exact-byte duplicate refresh, encrypted metadata, in-memory lookup, and self-copy suppression. Evidence: exact UTF-8 policy and marker tests; concurrent real encrypted SQLite captures preserve a single record and repeat count.
- [x] **M2-04** Implement pinning, count/age retention, payload-budget eviction, lower-limit confirmation, and explicit capacity errors. Evidence: transactional count/age/ciphertext policy, pin/unpin UI, lower-limit preview/confirmation, pinned conflicts and snippet capacity tests; real OS workflow coverage remains pending.
- [x] **M2-05** Implement Unicode-aware in-memory search and sorting without persisted queries or plaintext indexes. Evidence: Unicode case and Japanese-body search tests, sensitive-body exclusion, exact copied text and sorted in-memory results. Performance validation remains M4-05.
- [ ] **M2-06** Build concept 1's shared library shell, history list/details, copy/save-as-snippet actions, and readable compact-window navigation. **In progress:** Three-column library scaffold is runnable with sample data; promotion and compact navigation remain pending.
- [ ] **M2-07** Build concept 2's Focus panel, immediate search focus, keyboard selection/copy/dismissal, and Open Library selection handoff. **In progress:** Compact panel renders with initial search focus; keyboard/dismissal/handoff scenarios need full native validation.
- [ ] **M2-08** Implement global shortcut recording, persistence, validation/conflict handling, atomic replacement, and current-display/Space behavior. **In progress:** Carbon registration, local recording, nonsecret persistence, validation, and atomic replacement source exist; native conflict/Space tests remain pending.
- [ ] **M2-09** Implement menu bar status, capture enable/pause/resume, optional login launch, locked states, and accurate first-run permission guidance. **In progress:** Menu bar, setup/locked/error presentation source exists; native capture enablement, permission-needed/allowed status and locked relaunch pass on the reference Mac; login launch and full permission recovery remain pending.
- [ ] **M2-10** Implement clipboard output markers/current-host-only writes, ownership tracking, accurate copy failure reporting, and destination focus restoration. **In progress:** Output implementation and injected-pasteboard tests pass; native ordinary clipboard copy-back preserves the synthetic Unicode/whitespace fixture and app writes suppress self-capture; sensitive real-pasteboard timing and focus restoration remain pending.
- [ ] **M2-11** Cover history, policy, permissions, self-capture, capacity, and lock races with meaningful tests; run the copy → encrypted save → search → copy-back scenario. **In progress:** [Cross-layer tests](Tests/CopySaverDesktopTests/ClipboardPipelineTests.swift) exercise the production model/service, policies, CryptoKit and SQLite with only Keychain/pasteboard boundaries replaced; exact text, search/copy-back, duplicate refresh, self-write suppression, pause/reopen, permission baselines and ciphertext canaries pass. Native first unlock and copy → encrypted save → search → copy-back now pass on the reference Mac; authenticated reopen also preserves the fixture; broader FUNC/SEC checks remain pending.

### M3: snippets and sensitive operations

- [x] **M3-01** Implement snippet CRUD, validation, category labels, text preservation, duplicate-name handling, and independent history promotion. Evidence: category-aware create/edit/delete/promotion, exact UTF-8 preservation and independent history retention tests.
- [x] **M3-02** Implement General/Address/Card templates, sensitive-by-default card templates, and explicit create/edit/unsaved-draft states. Evidence: General/Address/Card templates, sensitive card default without CVV/PIN, private draft concealment, and replacement-cancellation tests.
- [ ] **M3-03** Add snippet list/details/editor within concept 1's shell, plus Focus panel snippet search/copy. **In progress:** List, masked details, creation editor, and Focus snippet filter exist; full editing and native workflow tests remain pending.
- [ ] **M3-04** Enforce fresh authentication for sensitive reveal/copy/edit and sensitivity changes; test cancellation, failure, and lockout. **In progress:** Reveal/copy require fresh injected authentication and reject late results; signed auth, edit/sensitivity-change flows, and lockout remain pending.
- [ ] **M3-05** Mask sensitive bodies across previews, search, VoiceOver, tooltips, and feedback; implement reveal expiry/deactivation/lock behavior. **In progress:** Masked body/search policy and reveal deactivation/expiry source exist; complete VoiceOver/timing/native validation remains pending.
- [ ] **M3-06** Implement sensitive clipboard marking and owned-copy expiry/lock clearing without erasing newer external copies or restoring old content. **In progress:** Deterministic marking/expiry/lock and external-copy tests pass, including replacement during marker inspection. Cleanup now rechecks the change count after reading the marker. Real clipboard/sleep-wake behavior and the remaining final-check/clear race require native review.
- [x] **M3-07** Implement item deletion, confirmed clear-history behavior, and explicit destructive vault reset, including missing-key recovery handling. Evidence: delete, confirmed history clearing, destructive reset UI/service; cancelled authentication preserves files/key, missing-key reset touches only owned vault paths. Actual signed auth remains M1-10.
- [ ] **M3-08** Validate snippet persistence/promotion/retention independence, sensitive action flows, timer/ownership races, and draft disposal on lock. Pass related FUNC/SEC checks.

### M4: widgets, accessibility, and release hardening

- [ ] **M4-01** Implement small/medium static launcher widgets, strict navigation links, cold-launch/locked routing, and add-widget instructions. **In progress:** Universal unsigned extension packaging passes in Debug/Release, exact links are tested, and setup instructions exist. Signed discovery/cold-launch validation remains pending.
- [ ] **M4-02** Validate widget discovery/placement in Notification Center and on the desktop; inspect snapshots/timelines/extension storage/entitlements for data leaks.
- [ ] **M4-03** Complete onboarding, settings, locked/loading/empty/search-empty, permission/error, and shortcut-recording states within approved concepts 1/2. **In progress:** Initial native setup/settings/locked/loading/empty/error/shortcut states exist; onboarding and permission flows remain incomplete.
- [ ] **M4-04** Verify light/dark/increased-contrast/reduced-motion behavior and keyboard/VoiceOver completion of all main workflows. **In progress:** Library light/dark and Focus rendering inspected; complete accessibility/keyboard validation remains pending.
- [ ] **M4-05** Measure panel latency, search, capture delay, idle CPU, and near-limit memory against section 11; record hardware/OS, dataset, and results. **In progress:** Optimized 7,000-record search p95 14.90 ms; near-budget commit/read and test-process RSS measured in [performance evidence](docs/performance.md). Native panel/capture/idle and supported hardware/OS checks remain pending.
- [ ] **M4-06** Run signed lifecycle/security/permission tests and audit entitlements, runtime networking, diagnostics, migrations, and crash recovery.
- [ ] **M4-07** Add CI for available core tests and the real app build; document and verify source build/test commands from a clean checkout. **In progress:** Clean-source verification and local universal Debug/Release Xcode app/widget builds pass. Latest CLT `make verify` passes 87 functional checks and 18 probe guards (two opt-in benchmarks skipped); earlier Swift 6.4 validation is recorded in the log. Apple silicon/Intel CI configuration exists; hosted execution remains pending.
- [ ] **M4-08** Confirm public name/repository owner, production bundle ID, signing credentials, and license-holder attribution; configure the private security-reporting channel.
- [ ] **M4-09** Confirm the v0.1 backup/recovery release decision and prominently document device-bound data-loss limitations. Do not market v0.1 as a durable archive.
- [ ] **M4-10** Build/sign/notarize the app and DMG, publish checksums/toolchain/dependency inventory, and validate installation/launch on clean supported Macs. **In progress:** Archive/sign/notarize/staple/DMG/checksum workflow implemented but not executed; valid signing identities, release inputs and native acceptance evidence are still required.
- [ ] **M4-11** Pass every applicable FUNC/SEC/REL check in section 12 and the M4 exit gate before tagging a release. Unverified builds remain development previews.

### Progress log

New community-profile work (November 3, 2026), from `main` at `8dbb932` on `feat/automatic-capture`:

- [x] **AUTO-01** Implement login-Keychain key storage and automatic create/open with no Apple-issued certificate; retain AES-GCM and fail-closed missing-key/tamper behavior. Evidence: `./scripts/check-automatic-vault.sh --run` passes create → separate-process exact Unicode reopen → missing-key denial/file preservation/no replacement → synthetic cleanup on Apple silicon macOS 26.6.2. Bundle is ad-hoc, sandboxed/hardened with no restricted Keychain entitlement. Query/ACL/profile isolation tests and existing crypto/tamper regressions pass. No production vault was accessed.
- [ ] **AUTO-02** Enable capture for new community vaults automatically, respect saved disable/pause choices, rebaseline on startup/resume, and resume after sleep/session activation without repeated authentication. **Implementation/tests passed:** automatic start, three suspension reasons, overlap, manual hide, error-retry latch, delayed-open cancellation, encrypted capture/wake/relaunch/pause pipeline. Actual OS sleep/session/clipboard-permission and native visual checks remain pending; CUA failed to initialize its native pipe.
- [ ] **AUTO-03** Build a certificate-free DMG, audit its identity/entitlements, document first-run/update approval and security limits, and preserve existing protected vaults. **Local preview passed:** `./scripts/community-release.sh --preview`, artifact audit, `hdiutil verify`, read-only mount/layout audit and detach. App/widget are universal, ad-hoc, sandboxed/hardened, with no Apple authority/profile/restricted entitlement. Next: rebuild from committed clean source. Native installation, minimum-OS/Intel and widget discovery remain independent gates.

These replace the community profile's earlier mandatory user-presence/start-locked/explicit-enable/notarized-release requirements (M1-09/M1-10, M2-09, M4-08/M4-10, FUNC-01/FUNC-09, SEC-05/SEC-06/SEC-11, REL-03/REL-04). Keep historical evidence and IDs; none of it proves the new profile. Remaining encryption, integrity, permission, sensitive-UI and accessibility gates still apply. The current requirement is automatic access to encrypted storage, not app-exclusive access against a compromised user account.

| Date | Change / IDs | Validation / evidence | Blockers / next action |
| --- | --- | --- | --- |
| 2026-11-03 | AUTO-02 first-run permission guidance follows actual capture state | Empty History now offers Request clipboard access/Open System Settings, Resume capture or Enable history as appropriate, rather than always asking to enable already-enabled history. The request discards current clipboard content through the existing permission adapter. `./scripts/swift.sh build --product CopySaverDev` and static docs/project checks pass | Native visual/OS permission validation remains pending because CUA cannot initialize; committed-source packaging follows. |
| 2026-11-03 | AUTO-01 complete; AUTO-02 implemented and regression-tested; AUTO-03 local preview packaged | `make verify`: 98 registered Swift checks (96 functional passed, two benchmarks skipped), 18 protected-probe admission guards, static project/docs/shell checks pass. Nine targeted automatic/profile/widget tests pass. Isolated ad-hoc Release create/reopen/missing-key fixture passes with synthetic cleanup. Universal DMG passes signature/architecture/entitlement audit, `hdiutil verify` and read-only mounted layout audit | Next: committed-source package and native first-run/real sleep-wake/permission/AX/widget checks. UI automation failed with “native pipe startup failed”; no visual acceptance claimed. User Xcode changes preserved. No Apple certificate, notarization, production-vault access or publication used. |
| 2026-11-03 | AUTO-01–AUTO-03 planned; user authorizes automatic community vault and ad-hoc DMG | Branch `feat/automatic-capture` starts at fetched `main` / `8dbb932`; existing local Xcode project changes preserved. Revised decisions and threat model in this spec | Prove login-Keychain access using only synthetic data, then implement/test automatic startup, resume and packaging. No community artifact validated yet. |
| 2026-10-26 | Product/security baseline; concepts 1/2 selected; global Focus shortcut and sidebar widget added | Requirements in sections 1–17; selected static references in `designs/` | Product code and signed platform behavior are not implemented or verified. |
| 2026-10-26 | M0-01–M0-07 repository/planning foundation complete; independent acceptance IDs established | Bootstrap commit `d8d1346`; agent/contribution/setup/security docs; documentation/link/checklist/PNG audit and artifact-ignore checks passed; staged whitespace review passed after removing one trailing blank line from the prompt archive | Next implementation task: M1-01. No app code or product tests exist yet. Full-Xcode integration remains blocked; no system repair authorized. |
| 2026-10-26 | M1-01–M1-07 complete; SEC-02/SEC-03 passed on `feat/vault-foundation`, stacked on planning baseline `11caee9` | `make build && make test` passed from a clean tracked-source export: 31 tests; independent OpenSSL fixture, synthetic database/WAL scans, rollback/reopen, and stale/cancelled session checks. `package describe`, shell syntax, and documentation/whitespace checks passed | Next: M1-08 native app scaffold and M1-09 Keychain adapter. No runnable desktop app yet. Signed Keychain/lifecycle/widget/OS compatibility and release gates remain pending; no system repair performed. |
| 2026-10-26 | Native scaffold on `feat/native-app`, stacked on vault foundation `06359fe`; partial M1-08/M1-09/M1-11–M1-13, M2-05–M2-10, M3-01/M3-03–M3-07, M4-03/M4-04. No additional full acceptance gates checked | Clean staged-source `make build` and `make test`: 55 tests pass; `make app`: sandbox/hardened ad-hoc bundle verified; optimized executable builds; project/plist/reference checks pass. Native sample library inspected in light/dark; Focus opens with search focused. See [native evidence](docs/native-integration.md) | Next: M2-01 capture policy/monitor work through injected interfaces, plus signed M1 validation once Xcode works. Final visual repeat paused because the Mac is locked. Capture/widgets/editing/templates and native security gates remain pending; no system repair performed. |
| 2026-10-26 | User authorized ongoing local merges; planning, vault, and native branches fast-forwarded into `main` through `4e00273`. `feat/clipboard-history` adds capture/privacy/retention; M2-01/M2-03 implemented, other native gates remain open | 67-test full suite plus the transactional Unicode-edit regression pass, including metadata-before-payload filtering, no-read baselines, exact UTF-8 duplicates, Luhn/private-key filtering, budget eviction, concurrent SQLite capture, pause persistence, and clear-history/snippet independence | Next: complete snippet/editor/pinning/navigation flows, then widget and release tooling. Actual OS permission, signed Keychain, lifecycle and widget tests remain pending. |
| 2026-10-26 | `feat/snippet-workflows` completes M2-04/M2-05/M3-01/M3-02/M3-07 implementation; compact navigation, login launch, copy timestamps and private text editing added | 77-test full suite plus the cancelled draft-copy regression pass. Private copy/cut routes through authentication/owned markers; transient edits, Unicode search, promotion, capacity, confirmed cleanup/reset, cancellation and missing-key recovery covered | Next: WidgetKit launcher target, CI/release tooling, and remaining native/security/performance verification. Native preview search, sensitive AX masking, compact resize/back, Focus search and Escape were inspected; full Xcode/signing and broader OS verification remain external gates. |
| 2026-10-26 | `feat/widget-and-release` adds generic launcher widgets, embedded extension target, CI/release tools, security hardening, real forced-crash recovery, and performance fixtures; M2-02 implementation complete | Widget and app entry sources compile, 41-object project/entitlement/dependency checks pass; Clean staged-source export passes `make verify`: 85 Debug checks are discovered (83 functional + two opt-in benchmarks); the full applicable optimized Release run passes 83 checks with both benchmarks enabled. Synthetic crash/canary tests pass. Release search p95 14.90 ms; near-budget encrypted commit/load ~992/196 ms, test RSS ~416.8 MiB. See [native evidence](docs/native-integration.md) and [performance](docs/performance.md) | Xcode still fails before loading projects, installed support resources are 16.1, bundled Apple repair signature passes, and zero valid signing identities exist. Native isolated ad-hoc setup was inspected and failed closed on missing signing entitlement. Hosted CI, gallery/OS/auth/AX checks and notarized release remain blocked/pending; no system repair or publication performed. |
| 2026-10-26 | `fix/draft-navigation` corrects M2-06/M3-02/M3-03 draft navigation, discard admission and copy metadata | Targeted regressions and full `make verify` pass: 86 Debug checks (84 functional + two opt-in benchmarks). Returning to Snippets reselects the edited item; cancelled selection stops context actions; exact Unicode changes count as dirty; editing keeps newer copy timestamps | Full optimized Release run passes 84 applicable checks including benchmarks; app bundle builds/verifies. Signed native and release blockers are unchanged. |
| 2026-10-27 | `fix/xcode-integration` records user-approved Apple-signed support-package repair and advances M1-08/M4-01/M4-07/M4-10 evidence without closing signed acceptance gates | Installed support resources now report 27.1; Xcode 27.1/Swift 6.4 SDK discovery works. Universal Debug/Release app and embedded widget builds pass without signing; processed identifiers/routes, extension point, both architectures and Release preview exclusion verified. Swift 6.4 `make verify` passes 84 functional checks (two benchmarks skipped). See [exact commands and limits](docs/native-integration.md#approved-xcode-repair-and-universal-builds) | Zero valid signing identities remain. Next: configure the user's development team, then M1-09/M1-10/M1-14 real authentication and helper-denial tests. First-launch status still exits 69, but macOS compilation works; no additional packages installed. Cross-app UI automation stalled again, so the shortcut scenario remains pending. |
| 2026-10-27 | `test/keychain-boundary` prepares M1-10/SEC-05 signed helper validation without completing either gate | Separate sandboxed/hardened probe source/scheme builds through SwiftPM Swift 6.3.3/6.4 and universal Xcode Debug. Seven guard checks pass for unbundled CLT/Xcode executables and the unsigned Xcode bundle without Keychain access. Swift 6.4 `make verify` passes 84 functional checks (two benchmarks skipped). The Release app/widget build passes and its build graph excludes the probe. Static checks cover 56 project objects and prevent probe embedding | Next: configure a real development identity, audit owner/helper entitlements and run the [signed procedure](docs/keychain-validation.md), including successful owner unlocks before/after. Actual authentication, helper isolation and release gates remain pending; zero valid identities are installed. No real Keychain or clipboard operations were performed. |
| 2026-10-27 | `fix/clipboard-cleanup-race` advances M2-11/M3-06/SEC-08 coverage; rechecks the counter after ownership-marker reads | The new race regression first reproduced erasure of a newer synthetic clipboard item, then passed with the fix. Two production model/service/CryptoKit/SQLite pipeline tests pass for exact-byte capture/search/copy/reopen, duplicate metadata, self-write suppression, pause/permission baselines, sensitive auth cancellation/expiry and encrypted canaries. `make verify` passes 87 functional checks plus seven helper guards (two benchmarks skipped); universal unsigned Release app/widget build and ad-hoc `make app` packaging/signature checks pass | Native clipboard/security gates remain unchecked. The separate final-check/clear calls retain a residual race requiring real-macOS review; no atomic-cleanup guarantee is claimed. Zero valid signing identities remain; next signed task is M1-10. No real Keychain, system clipboard or user vault was accessed. |
| 2026-10-27 | `fix/debug-architectures` fixes M1-08/M4-07 local Xcode build compatibility while preserving personal signing edits | My Mac initially failed because native widget built Intel/Apple silicon while the package built only active Apple silicon; cleaning reproduced it. Project Debug now uses `ONLY_ACTIVE_ARCH=YES`; Xcode build/run passes. Explicit universal Debug override builds both app/widget slices; `lipo` and static checks pass. Locally signed app signature verifies, but Create encrypted vault fails closed on missing Keychain entitlement | Ad-hoc Sign to Run Locally does not enable persistent capture under the current protected-Keychain requirements. Development certificate/private-key recovery and native/security gates remain pending. User team/signing settings remain uncommitted; no authentication fallback or stored data was introduced. |
| 2026-10-27 | `fix/keychain-signing` completes M1-08 configuration validation and advances M1-09/M1-10; corrects the obsolete missing-certificate blocker | Real Apple Development app/widget and separate probe builds pass; signatures and emitted entitlements audited. Certificate-only app still failed on missing Keychain identity; adding only each app’s own bundle-derived group causes Xcode to emit app/team identity and embed a profile. Native protected vault creation succeeds and stays locked. `make verify` passes 87 functional checks and seven probe guards (two benchmarks skipped) | First unlock awaits device-owner authentication; helper controls/denial, capture and remaining native/security/release checks remain open. Standalone ad-hoc preview retains sandbox-only entitlements. Personal team/signing edits stay uncommitted; no key/file/authentication fallback was added. |
| 2026-10-27 | `test/native-clipboard-evidence` advances M1-09/M1-12/M2-09–M2-11/M3-08 and advances FUNC-01 on the reference Mac | Device-owner authentication unlocks the real protected vault; history off → permission needed → Capturing observed. Synthetic named snippet saves; external multiline Unicode copy → search → owned copy-back preserves exact text in a native draft. Self-copy suppression and narrow DB/WAL/SHM canary scans pass. Relaunch starts locked; owner authenticates again, exact history/snippet text reloads and capture resumes | Owner create/unlock/save/relaunch/load passes. Password fallback, helper denial, explicit offline repeat, full permission/lifecycle/AX/source-attribution and release checks remain open. Xcode’s saved paste destination trimmed whitespace, so exact round-trip evidence uses the native draft instead. No implementation or authentication-policy change. |
| 2026-10-27 | `fix/readable-history-ages` refines M2-06/M2-07 history metadata in both shared row surfaces | Replaced SwiftUI second-resolution relative text with a localized single-unit minute/hour/day label and 60-second timeline. Synthetic formatter smoke checks show Just now through 59 seconds, 1 minute at 60 seconds, 1 hour at 3,600 seconds and 1 day at 86,400 seconds; future dates clamp to Just now. Signed Debug app/widget build and `make verify` pass (87 functional checks, seven probe guards, two benchmarks skipped) | Updated signed app is built; the already-running process retains its previous UI until relaunch. Broader native UI/security acceptance remains pending. Personal Xcode signing edits are preserved outside this commit. |
| 2026-10-28 | `test/isolated-keychain-validation` advances M1-09/M1-10/M1-14/SEC-05 using a separate synthetic owner | Fixed owner role reuses the production Keychain provider, desktop service, CryptoKit and SQLite without clipboard access. Universal Apple Development Release owner/helper builds and signature/profile audits pass with distinct own groups, sandbox/hardened runtime and no debugger/network/shared entitlements. Fifteen admission guards, bundled-runner refusal and two signed opposite-role refusals pass; full suite passes 87 functional checks (two benchmarks skipped). Owner create/authenticate/save, exact fresh-process reopen and locked-write denial pass | Helper own-control authentication, target denial and owner-after check remain pending; password-fallback method confirmation is pending. No personal clipboard vault was accessed or reset. |
| 2026-10-29 | `test/keychain-presence-negative-control` completes M1-10 and SEC-05 on the reference Mac; advances SEC-04 | Universal Release signature/profile audits pass without debugger/network/shared groups. Both helper UI-forbidden reads are denied; authenticated controls, target item-not-found and control cleanup pass. Owner reads succeed before/after. Native missing-key scenario preserves exact DB/WAL/SHM bytes, denies writes and replacement keys, then explicitly cleans up the synthetic fixture. `make verify` passes 87 functional checks and 18 guards (two benchmarks skipped); runner rejects signed bundles/copied signed executables even under Python optimization | Cancellation remains unverified because the user authenticated instead. Confirmed owner reads used Touch ID; password fallback remains unverified. Next: remaining authentication cases and M1-11 lifecycle validation. Personal history and production authentication policy are unchanged. |
| 2026-10-29 | `docs/password-fallback-evidence` completes M1-09 on the reference Mac | User confirms Mac-password authentication for the already successful final Release owner/missing-key run. Its initial protected read and exact-canary verification passed before key removal; earlier owner reads used confirmed Touch ID. Documentation/checklist/link and whitespace checks pass; no new app tests were needed for this evidence-only update | Cancellation remains unverified because that earlier test authenticated instead. Next: M1-11 lock/sleep/session validation and remaining native permission cases. No code or authentication-policy change. |

## 1. Product

CopySaver is an open source, local-only desktop app for recovering recently copied text and reusing named snippets. macOS is the first platform. Windows is a later, separately scoped release with comparable workflows.

The primary workflows are:

1. Copy text in another app, find it in History, and copy it again.
2. Save reusable text under a name, such as Home address, Delivery address, or Work signature.
3. Save sensitive snippets, such as card details, with masking and an authentication step before reveal or copy.

No account, subscription, server, or internet connection is required. The initial audience is people who repeatedly enter the same information or need to recover text while working on their Mac.

### Product principles

- Fast retrieval: keyboard access and search are central.
- Local ownership: content remains on the device unless the user explicitly copies it elsewhere.
- Security with understandable behavior: explain what is encrypted, what locking does, and what copying exposes.
- Native macOS behavior: standard controls, shortcuts, accessibility, and system authentication.
- Small, maintainable scope: reliable text workflows before images, automation, or synchronization.

CopySaver is a clipboard utility with protected snippets, not a full password manager. Users can enter arbitrary text, but the product should not encourage storing passwords, card security codes, or PINs.

## 2. Decisions

**November 3, 2026 revision:** The user replaced mandatory vault authentication with automatic capture and a certificate-free community DMG. The community app uses the macOS login Keychain with a calling-app ACL, rather than the provisioned data-protection Keychain. It opens automatically at launch and resumes after sleep without a CopySaver authentication prompt when the login Keychain is available. Existing protected builds/vaults remain isolated and unchanged; no automatic key migration or deletion is permitted. Historical signed-validation evidence below applies to the former profile only.

| Area | Decision | Reason / consequence |
| --- | --- | --- |
| First platform | macOS 14 or later; Apple silicon and Intel where supported by the release toolchain | Native integration without maintaining older OS workarounds. |
| App stack | Swift 6, SwiftUI, targeted AppKit integration | Small native app with direct access to clipboard, menu bar, authentication, and lifecycle APIs. |
| Full window | Concept 1: Native library | Three-column navigation, searchable list, and detail/editor layout. |
| Focus mode | Concept 2: Focus panel | Compact floating search panel, opened from other apps using a user-configurable global shortcut. |
| Sidebar widget | Native macOS Notification Center widget, also usable on the desktop | Small/medium launcher widget; content stays inside the authenticated app. |
| Windows | Later native client; do not promise a date or parity at launch | macOS quality takes priority. SwiftUI screens will not be reusable on Windows. |
| Persistence | SQLite through the system SQLite library; encrypted record payloads | Transactions and recovery without a large dependency or plaintext content columns. |
| Encryption | AES-256-GCM through CryptoKit | Authenticated encryption using an OS-provided implementation. |
| Key storage | Community build: macOS login Keychain, calling-app ACL, random vault key; protected build retained for compatibility | The key is separate from the database. No Apple-issued certificate or fresh user presence is required for ordinary community-vault reads. Login Keychain locking, denial or changed ad-hoc identity can require OS approval. |
| Unlock | Automatic community-vault open at launch and resume after sleep; explicit retry on Keychain errors | No recurring CopySaver unlock prompt. Sensitive snippet actions retain fresh system authentication as a UI safeguard. |
| Lock behavior | Pause capture and remove usable vault state from memory | A locked app must not continue retaining its vault key for background capture. |
| Content | Plain text only in the MVP | URLs, code, addresses, and multiline text work without processing attachments or rich content. |
| Paste behavior | Copy to clipboard; user pastes with Command-V | No Accessibility permission or simulated keystrokes in the MVP. |
| Distribution | Ad-hoc signed community app in a drag-to-Applications DMG; no Apple-issued signing key or notarization | Users may need first-run approval in macOS Privacy & Security. Updates may require renewed OS approval. No script disables Gatekeeper or removes quarantine. |
| Network | No app networking, telemetry, analytics, or automatic update checks in the MVP | Offline operation and a narrow permission footprint. |
| Open source | MIT license | Permissive reuse and contribution. |

The alternative of Tauri or Electron would share more UI code with Windows. Native SwiftUI is selected because macOS is the stated priority and the most important integrations are platform-specific. Share behavior specifications and encryption-format fixtures later, rather than committing to a cross-platform runtime now.

### Community profile and compatibility

The automatic community profile is the default certificate-free build. Its app/vault identities contain `.community` (and `.dev` for development) and its login-Keychain service additionally uses a distinct automatic-key suffix. It must never probe, copy, delete or silently migrate the prior sandboxed data-protection vault. The existing Xcode protected profile remains available for its existing users and manual validation, with its original authentication behavior. Switching profiles creates a separate empty library; migration is deferred, with the old library left intact.

The community profile retains App Sandbox and hardened runtime with no restricted Keychain entitlements. An isolated ad-hoc sandboxed feasibility app successfully added, read noninteractively and deleted its synthetic login-Keychain item on the reference Mac. This is not yet cross-launch/update or supported-OS evidence. The WidgetKit extension remains sandboxed and has no content/key access; community widget discovery must be validated separately and must not be advertised as working merely because the extension builds.

For this profile, **new vaults enable capture by default**, with a visible status and immediate Pause/Disable controls. Existing saved disable/manual-pause preferences are never overridden. OS clipboard approval remains necessary where enforced. Open establishes a baseline without reading the current clipboard; only new copies are captured.

Sleep/session inactivity closes capture admission, invalidates pending work, clears sensitive clipboard ownership and decrypted presentation, then resumes automatically on the corresponding return event. Ordinary idle time does not pause capture. Explicit Hide and pause remains paused until the user explicitly resumes; it is a presentation/privacy action, not an authentication boundary. A failed key read is shown once with Retry; no repeated background prompts or key regeneration. Sensitive snippet reveal/copy/edit still requires fresh `LocalAuthentication`, which protects UI actions rather than making the automatically loaded encryption key presence-bound.

## 3. Release boundaries

### v0.1: macOS MVP

- Menu bar app, compact quick-access panel, and library/settings window.
- Automatic community clipboard capture, persistent pause/disable controls, and visible status.
- Plain-text history with search, copy, pin/unpin, delete, and retention controls.
- Named snippets with create, edit, search, copy, delete, and a Sensitive option.
- Address and card-detail starter templates using the same snippet data model.
- Encrypted storage, automatic community open/resume, sensitive-action authentication, and sensitive-copy clearing.
- Global shortcut, optional launch at login, and native light/dark appearances.
- Optional small and medium macOS Notification Center/desktop widgets for opening Focus mode, History, and Snippets.
- Error handling, security tests, contributor setup, and ad-hoc community distribution instructions.

### After v0.1

1. Encrypted export/import and an explicit recovery design. This is required before describing CopySaver as a durable archive or recommending it as the only copy of important information.
2. Optional direct paste, only after a separate permissions and sandbox feasibility review.
3. Images and richer clipboard formats, with separate size and preview policies.
4. Windows client and platform-specific security validation.

### Not in scope

Cloud sync, accounts, browser extensions, mobile apps, Linux support, AI features, OCR, clipboard sharing, webhooks, scripting APIs, text expansion, payment autofill, and team vaults.

## 4. Main experiences

### 4.1 First run

1. Explain History and Snippets in one short screen.
2. Explain that content is encrypted on disk, the login Keychain holds its key, and new community copies are captured automatically after OS clipboard approval.
3. Explain that the community key is kept separately in the login Keychain and there is no portable recovery/export yet. Losing the key can make the data unrecoverable. Do not imply that copying the database is a sufficient backup or that this Keychain profile is guaranteed device-only.
4. Automatically create/open the community vault using its own login-Keychain entry. If key storage is unavailable, preserve files and show a useful error; do not downgrade to plaintext or a file-stored key. The protected compatibility build retains explicit setup/authentication.
5. Community capture starts enabled, with clear Pause/Disable controls. On systems that require clipboard approval, guide the user through the OS-controlled permission flow; do not fabricate consent or repeatedly read denied clipboard content.
6. Offer launch at login, off by default, and show the configurable global shortcut.
7. Open a useful empty state with Create snippet and a short explanation of how history appears.

Successful setup requires no terminal, admin helper, Accessibility permission, Input Monitoring, or Full Disk Access. Developer source builds are a separate workflow.

### 4.2 Focus mode (quick access)

- Use the approved Focus panel concept (`designs/02-focus-panel.png`): compact floating panel, prominent search, History/Snippets switch, optional pinned group, recent items, capture status, and keyboard hints. No permanent navigation sidebar or full detail pane.
- Open from the menu bar's Open Focus Mode action or a configurable global shortcut, initially Option-Command-V. The app must be running, including in the menu bar with its full window closed.
- The shortcut is registered globally and works while another app has keyboard focus. Present on the current display/Space in supported desktop and full-screen contexts, like Spotlight, without bringing the full library window forward.
- In Settings → General → Focus Mode Shortcut, provide a shortcut recorder with Record shortcut, Clear, and Restore default actions. Persist the binding across app restarts.
- Require a supported modifier-and-key combination; reject unsupported or reserved bindings with an actionable message. Detect registration conflicts/failures and preserve the last working binding until the replacement registers successfully. Do not replace or intercept the system's Spotlight shortcut.
- Pressing the configured shortcut while the panel is already open dismisses it. Escape and clicking outside also dismiss it, except while an authentication flow needs to complete or be cancelled.
- On each opening, start with an empty query and focus search immediately, with History and Snippets as distinct views. Remember the last selected view while unlocked; clear transient query/results on dismissal.
- Arrow keys change selection. Return copies the selection and closes the panel after success. Escape dismisses it. Command-C copies without dismissing it.
- Dismissing after copy returns focus to the previously active app when possible. It does not simulate Paste; the user presses Command-V in that app.
- Provide an Open Library action that opens the full window and carries the selected item and view across when unlocked. Opening the full window dismisses the panel.
- A sensitive selection prompts for authentication before copying. Cancellation leaves the clipboard unchanged.
- Keep focus and VoiceOver behavior consistent with native panels.
- If locked, show an unlock action without item names, previews, counts, or previous queries.

### 4.3 Library

- Use the approved Native library concept (`designs/01-native-library.png`) as the full window: leading navigation sidebar, middle searchable item list, and trailing detail/editor pane.
- Navigation: History and Snippets, with a Pinned history filter. Keep capture/pause status, Settings, and Hide and pause (Lock vault for the protected profile) accessible near the sidebar footer.
- Both History and Snippets use the same window shell. Snippets replace the middle list and detail/editor content rather than switching to the unselected concept 3 layout.
- Use a compact single-pane layout at small window sizes while preserving clear back navigation.
- Open from the menu bar's Open Library action or the focus panel. Closing the full window keeps the menu bar app and global Focus Mode shortcut running; Quit exits the app and unregisters the shortcut.
- History details show text, capture time, last-copy time, and best-effort source attribution.
- Snippet details show name, content, optional category, sensitivity, and editing actions.
- Promote a history item to a snippet through an explicit Save as snippet action. This creates an independent snippet and leaves the original history item under its existing retention policy.
- Destructive actions distinguish Delete item, Clear history, and Reset vault. Clear history includes pinned history, with explicit confirmation, and never deletes snippets.
- No trash/recycle bin in v0.1. Individual deletion is immediate; confirmation is required for bulk deletion and vault reset.

### 4.4 Snippets

- Required name: 1–120 characters after trimming surrounding whitespace. Duplicate names are allowed.
- Required content: nonempty text, preserving original spaces and line breaks; whitespace-only entries are rejected.
- Optional category: General, Address, Card, or a custom label of up to 60 characters.
- Templates seed editable plain text. They do not create a separate autofill or payment integration.
- Card template contains cardholder, card number, and expiration placeholders; it defaults to Sensitive and has no CVV or PIN field.
- Existing sensitive content cannot be edited, revealed, copied, or changed to nonsensitive without fresh system authentication.
- Titles and category names remain visible while the vault is unlocked. Sensitive body previews are masked, including in accessibility output.
- Sensitive reveal lasts at most 30 seconds and ends immediately on window dismissal, app deactivation, or vault lock.
- Copying a sensitive snippet requires fresh authentication each time, even during a reveal session.
- Sensitive bodies are excluded from ordinary search results and indexes. Search matches their names and categories only.
- Sensitive is an additional interface/authentication policy. All records already have the same encryption at rest; it is not a separate cryptographic compartment inside the running app.

### 4.5 Sidebar widget

Sidebar means macOS Notification Center, rather than a separate panel inside the library. Provide a native WidgetKit extension that users can add through the macOS widget gallery. The same widget supports desktop placement; the app does not place it automatically or require notification permission to use it.

- Small widget: CopySaver icon/name, a short static label such as Clipboard & snippets, and one primary Open Focus Mode interaction.
- Medium widget: a primary Open Focus Mode interaction plus distinct History and Snippets links that open those library views.
- Match the selected concepts' restrained typography and iconography; support native widget margins, light/dark appearance, and system rendering. These layouts supplement the approved library and focus panel rather than replacing either.
- Clicking a link launches or activates the containing app at that destination under its normal storage profile. Community cold launch automatically opens its own vault and respects saved capture/pause settings; an explicitly hidden in-process library stays hidden until explicit reopen. The protected profile still requires unlock. A link never copies or reveals a sensitive body automatically.
- A widget can launch the app when it is not running; community launch follows normal automatic open, while protected launch starts locked. It never changes the user's enabled/paused preference. No widget process retrieves a key or performs unlock itself.
- v0.1 is a launcher widget: no clipboard previews, snippet names/bodies, categories, item counts, recent searches, or source app information. Do not display a live Capturing/Unlocked status, since a cached widget could show stale state.
- The extension never reads the clipboard, vault, or Keychain. No decrypted data, keys, shared vault files, or content-bearing timeline entries are passed to it. No App Group or shared Keychain entitlement is needed for these static links.
- Implement navigation with one root `widgetURL` and explicit `Link` destinations as appropriate. Proposed allowlisted routes: `copysaver://focus`, `copysaver://history`, and `copysaver://snippets`. Only navigation is exposed; URLs contain no record identifiers, payloads, or secrets.
- Treat incoming URLs as untrusted and accept only the exact documented routes with no query, fragment, credentials, or action parameters. Malformed/unknown routes have no side effects. The routes provide no read/export/copy/unlock API and no response carrying user data.
- Settings → General includes brief instructions for adding the widget. Widget removal has no effect on stored content, the menu bar, or the keyboard shortcut.

## 5. Clipboard behavior

### 5.1 Capture pipeline

1. Monitor `NSPasteboard.general.changeCount` while capture is allowed, initially every 500 ms. Compare for inequality rather than assuming a monotonic counter forever.
2. On launch, unlock, resume, or permission restoration, establish a change-count baseline without reading existing clipboard content. Capture only subsequent changes.
3. Check the session state, permission behavior where the API is available, pasteboard types, and exclusion signals before requesting text.
4. Ignore concealed, transient, autogenerated, known password-manager markers, and CopySaver's own writes. Use the interoperability identifiers documented by NSPasteboard.org.
5. Accept one plain-text item. Ignore file references, images, rich-text-only payloads, empty/whitespace-only text, unsupported multi-item pasteboards, and text over 256 KiB of UTF-8. Do not truncate silently.
6. Recheck change count after reading. If the pasteboard changed mid-read, discard that observation instead of associating inconsistent content and metadata.
7. Apply conservative secret filters, then encrypt and commit the accepted record. Never place raw clipboard content in diagnostic output or a disk-backed queue.

Capture is best effort. Several copies between polls may produce only one observed item. The app must not claim to recover text copied while it was stopped, paused, locked, or denied permission.

### 5.2 Sensitive-content avoidance

- Always skip `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, and `org.nspasteboard.AutoGeneratedType`, plus documented legacy password-manager markers.
- Skip high-confidence private-key blocks and likely payment card numbers validated with conservative format checks and a checksum. Broader password/token detection is best effort, not a guarantee.
- Filters may produce false positives. Do not offer an unsafe override for concealed/transient markers in v0.1. Users can explicitly create a sensitive snippet instead.
- Do not claim to detect every password, API key, private browsing session, or sensitive text.
- Offer application exclusions keyed by bundle identifier. Initial suggestions include installed password managers, but users choose additional exclusions.
- Source attribution is best effort: the frontmost app may have changed, and source markers are untrusted hints. Exclusions are a convenience privacy control, not a security boundary.
- Observe app activation changes and rebaseline without reading when crossing an excluded-app boundary. Prefer dropping an ambiguous copy over capturing it. Test clipboard/activation races explicitly.
- Browser private-window detection is not part of v0.1. Explain that excluding the browser excludes all of its windows.

### 5.3 Duplicate handling

- Deduplicate history by exact UTF-8 content, without trimming or normalizing the saved text.
- An identical observed copy refreshes last-seen time and moves the existing entry to the top; its pin remains unchanged.
- Track repeat count and first-seen time inside the encrypted payload.
- Any digest used for lookup stays in memory. Verify bytes after a digest match. Do not persist plaintext content hashes that permit guessing common clipboard values.
- Snippets are independent and are not deduplicated against history.

### 5.4 Copying out

- Write only the requested plain text, an app source marker, and an opaque ownership marker. Ignore the resulting self-generated capture event.
- Use the pasteboard's current-host-only option for all CopySaver writes to avoid exporting them through Universal Clipboard. Other apps and user actions can still move the text elsewhere.
- Sensitive writes additionally use the concealed marker and a 30-second auto-clear deadline. Do not clear ordinary copies automatically.
- Clear only if the clipboard still has the exact change count and ownership marker from CopySaver's write. Never erase a newer copy from another app, and never reread content just to compare it.
- Check the change count both before and after marker inspection. The current separate check/clear calls retain a residual race after the final check; this limitation must be reviewed on the real pasteboard before SEC-08 can pass. Do not advertise atomic cleanup or an absolute no-overwrite guarantee from the injected tests.
- Locking clears an owned sensitive copy immediately. Maintain only the nonsecret ownership/deadline information needed for cleanup after locking.
- Check an expired deadline on wake or timer resumption. Timers cannot guarantee cleanup while the app is suspended or after a crash.
- Do not restore previous clipboard contents. No prior-content buffer is retained for this purpose.
- Show copy success only after the system write succeeds. Copying exposes plaintext to the system clipboard and the destination app; markers and clearing are mitigations, not access control over other apps.

## 6. Retention, search, and limits

| Setting / limit | Default | Policy |
| --- | --- | --- |
| History count | 1,000 | User range 100–5,000; includes pinned history. |
| History age | 30 days | Choices: 1, 7, 30, or 90 days. |
| Pinning | Off | Exempts a history record from automatic age/count eviction, not explicit deletion. |
| Snippet count | Maximum 2,000 | No automatic expiration or eviction. |
| Single text body | Maximum 256 KiB UTF-8 | Applies to history and snippets; reject before persistence. |
| Live encrypted payload budget | 128 MiB | Includes history, snippets, and settings; physical SQLite/WAL size may temporarily exceed this. |
| Lock timer | 15 minutes of system user inactivity | Options: 5, 15, 30 minutes, or on system lock only. |

- Apply age retention before presenting history after unlock; while unlocked, run cleanup at least once per minute and on capture. Retention cannot inspect encrypted timestamps while locked, so deletion can be delayed until the next unlock.
- Evict oldest unpinned history first when count or payload budget requires space. Enforce limits transactionally; pins and snippets are never silently evicted.
- If pins occupy the entire history count limit, skip incoming history and show History limit reached. If no safe eviction can satisfy the storage budget, reject the write with a useful error. Snippet saves must never appear successful when rejected.
- Lowering limits requires a preview of the affected item count and confirmation. Reject limits incompatible with the existing pinned count until pins are removed.
- Search case-insensitively across history bodies and nonsensitive snippet names, categories, and bodies. Define Unicode-aware matching in tests; preserve original content when copying.
- Search and sorting operate on an ephemeral in-memory index while unlocked. Never persist queries, plaintext full-text indexes, previews, or embeddings.
- Sort history by last-seen time and snippets by name initially. Keep pinned history available through a filter; pinning does not change duplicate identity.

## 7. Security model

### 7.1 Promise and limitations

Product language: **Clipboard history and snippets are encrypted on your Mac. Reading the saved database alone does not reveal their contents.**

For the automatic community profile, the random encryption key lives in the login Keychain, outside the vault. It is not user-presence-bound or guaranteed device-only. The login Keychain's own encryption and the user's login credentials protect that key at rest. An attacker with only the database/WAL/SHM cannot decrypt them. Full device compromise, an unlocked or decryptable login Keychain, known login credentials, or code executing as the logged-in user falls outside this promise. Recommend FileVault for stolen-device protection, without changing OS settings. Do not claim only CopySaver can ever retrieve the key or that automatic opening protects against all disk compromise.

Encrypt bodies, titles, categories, timestamps, source app identifiers/names, pin states, repeat counts, and privacy settings. A file reader may still see that a database exists, its approximate size, opaque row identifiers, envelope versions, and approximate record count. SQLite headers and ciphertext lengths are not secret.

Protect against casual file inspection, an attacker possessing only copied vault files, and unauthenticated access through the locked app. Authenticated encryption detects modified or substituted record payloads when they are read.

Do not promise protection against administrator/root compromise, malicious code executing inside the app, an attacker controlling the unlocked user session, screenshots, keyboard observation, plaintext retained by destination apps, or full-database rollback/deletion. A user-controlled operating system can ultimately authorize access to its secrets. Open source does not weaken correctly implemented encryption, but it also does not make an app an exclusive trust boundary against its owner.

### 7.2 Vault and keys

The data-protection/user-presence details in this subsection describe the **protected compatibility profile**. The community profile instead follows section 2's login-Keychain policy: cryptographically random 256-bit key, caller-only ACL for restricted operations, no synchronization, no broad trusted-app list, no plaintext/file-key fallback, and no automatic migration of existing keys. OS-approved access by other applications or a changed app build is possible. Failed reads never create replacement keys for existing databases.

- Generate a random 256-bit vault key using the platform cryptographic random generator. Never derive it from a bundle identifier, device serial, hardcoded secret, or source-code value.
- Use the data protection Keychain explicitly (`kSecUseDataProtectionKeychain = true`), with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `SecAccessControl` user presence, no synchronization, and the app's own access group only.
- Bind the Keychain lookup to a random vault UUID. Store the UUID and format version in the database header, not the key.
- Retrieve the key only after an explicit unlock action. Enforce authentication through the protected Keychain operation itself, not just a successful UI prompt followed by unprotected key retrieval.
- Start locked on every launch, including launch at login. Do not trigger authentication dialogs in the background. Login launch waits in the menu bar until the user unlocks.
- Retain the key only for the unlocked session. Clear owned key buffers where possible, invalidate authentication contexts, and release decrypted models/indexes when locking. Swift and UI frameworks may copy values; do not claim complete forensic memory erasure.
- Do not describe the AES key as nonexportable or stored directly in the Secure Enclave. CryptoKit needs usable symmetric key material in the app process while unlocked.
- Use a fresh authentication context for sensitive reveal/copy/edit operations; do not deliberately enable biometric reuse. Cancellation, lockout, or unavailable authentication fails closed and leaves content concealed.
- Never save the key to SQLite, preferences, logs, environment variables, the repository, or a sibling file. No plaintext fallback.
- Development and production builds use distinct app identities, Keychain namespaces, and vault locations. Never instruct contributors to point a debug build at production user data.

### 7.3 Record encryption and persistence

- Serialize each complete record to versioned UTF-8 JSON, then encrypt before passing its payload to SQLite.
- Use AES-256-GCM with a fresh random 96-bit nonce for every insert and every update, including timestamp-only updates. Store nonce, ciphertext, and authentication tag in an envelope.
- Authenticate a canonical encoding of the vault UUID, opaque record UUID, and envelope version as additional authenticated data. This prevents moving an intact ciphertext into another row or vault undetected.
- Store a fixed, authenticated vault-verification record so an empty vault also detects an incorrect key. Reject unsupported envelope versions; never guess a decryption scheme.
- Persist only opaque record IDs, envelope versions, and encrypted envelopes. Keep record kind and all business metadata inside the payload. No plaintext secondary indexes or content hashes.
- Use parameterized SQL and serialize mutations through one persistence actor. Use SQLite transactions, durable commits, bounded WAL checkpointing, and an explicit schema migration version.
- SQLite database, WAL, shared-memory files, migration copies, and application-generated backups must contain no application-written plaintext secrets. Journals contain ciphertext because encryption happens before the SQL boundary.
- Keep the vault under the app sandbox's Application Support directory, resolved through system APIs. Apply owner-only directory/file permissions as defense in depth, and create no Spotlight/Quick Look content integration.
- Do not use an iCloud or user-selected synchronization directory for the working vault.
- Deleted ciphertext may remain in SQLite free pages, APFS snapshots, SSD storage, or backups. Individual deletion and retention are logical deletion, not guaranteed secure erasure. Reclaim free space when practical without claiming otherwise.

### 7.4 Lock lifecycle

The mandatory manual-authentication/idle behavior below is retained for the protected compatibility profile. The community profile follows the automatic lifecycle in section 2: purge on suspend, automatic resume when suspension reasons clear, no idle timeout, explicit Hide and pause respected, and fail-closed retry on error. Both profiles retain session generations and stale-work rejection.

Lock immediately on explicit Lock, system session lock, user-session resignation/switch, sleep, app termination, or idle timeout. Use public lifecycle APIs; validate lock-screen coverage on supported OS versions and fail closed on session-state uncertainty. Do not rely solely on Keychain accessibility to remove an already loaded key.

Closing a panel or window does not quit the app or lock the vault. Ordinary app deactivation ends sensitive reveal but permits normal history capture until a lock condition occurs.

On lock:

1. Close the capture/write admission gate and advance the session generation.
2. Cancel pending reads/searches/reveals. Serialize lock with commits so no queued mutation can commit after the locked state is published.
3. Discard unsaved drafts, clear previews/queries, clear an owned sensitive clipboard copy, and release decrypted state and key references.
4. Publish Locked only when the protected state is no longer available to normal app operations.

Before unlock completes, authenticated decryption, schema validation, retention cleanup, and rebuilding the search index must succeed. Capture resumes only if the user previously enabled it and did not manually pause it. Rebaseline the clipboard to avoid backfilling locked-period content.

### 7.5 Other data paths

- Store sensitive settings, exclusions, and content-derived metadata in the vault. Keep only nonsecret bootstrapping/UI preferences outside it, such as appearance and shortcut configuration.
- No content in `UserDefaults`, notifications, window titles, state restoration, autosave files, temporary exports, analytics, assertion messages, or crash attachments generated by the app.
- No content or content-derived metadata in widget timelines, snapshots, gallery previews, URLs, or extension storage. The widget shares neither the vault key nor its Keychain access group.
- Disable restoration/autosave of snippet editor buffers and clear them on lock. Warn before navigation that would discard a dirty editor; lock takes precedence and discards without waiting for confirmation.
- Log only operation identifiers, coarse error categories, and necessary noncontent status. Do not log snippets, queries, titles, app exclusion lists, keys, or ciphertext dumps.
- Render text literally. Do not execute snippets, load link previews, or fetch remote content.
- Build with App Sandbox and hardened runtime; no network, shared Keychain group, debugging, or broad filesystem entitlement in production.
- OS backups may include encrypted vault files. This does not make them portable or recoverable without the correct Keychain key. CopySaver provides no recovery service in v0.1.

## 8. App states and failure behavior

Vault state, user capture preference, manual pause, and permission status are separate values. Capture is permitted only when the vault is unlocked, capture is enabled, manual pause is off, clipboard access is allowed, and storage is writable.

| State / event | Required behavior |
| --- | --- |
| First launch | Community: automatic create/open and capture enabled after OS permission. Protected: capture off until enabled. Neither imports old clipboard content. |
| Locked | No clipboard payload reads, content queries, or content writes; owned sensitive clipboard cleanup remains possible. |
| Unlock cancelled/failed | Stay locked; no decrypted remnants displayed. |
| Ready, capture enabled | Observe new clipboard changes subject to filters and limits. |
| Manually paused | Stop payload reads; library/snippets remain available while unlocked. Resume only on an explicit user action. |
| Clipboard permission denied/revoked | Stop programmatic payload reads; show actionable status without repeated prompts. Snippet editing remains available. |
| Clipboard write denied/failed | Report failure; no Copied confirmation and no incorrect last-copy update. |
| Keychain unavailable or missing key with existing vault | Preserve files, stay locked, explain the error. Never regenerate a replacement key over an existing vault. |
| Authentication tag / verification failure | Stop normal loading/capture, preserve the original vault, and report corruption or key mismatch without exposing content. No automatic reset. |
| Disk full / database write failure | Fail the mutation, stop capture, show a persistent error, and offer retry. Retain only previously committed data; no plaintext spool. |
| Unsupported newer vault version | Refuse writes and explain that a compatible app is required. |
| Crash / forced termination | Recover committed transactions; community opens automatically, protected begins locked. Partial saves must not be presented as successful. |
| Sleep / session inactivity | Stop capture and purge state; community reopens on corresponding return events if not explicitly hidden and no key error occurred. Protected remains locked. System lock-screen coverage remains a native gate. |
| Global shortcut unavailable | Menu bar and library remain functional; let the user rebind. |

Reset vault requires a separate destructive confirmation explaining that both history and snippets will be lost. Authenticate when the key is available; missing-key recovery still allows an explicitly confirmed destructive reset. Delete the old key and vault before creating the replacement, without promising removal of external backups or snapshots.

## 9. Interface direction

The user selected concepts 1 and 2 on October 26, 2026. This establishes the visual/layout baseline for implementation: Native library for the full window and Focus panel for global quick access. Concept 3 (Quiet snippets) is not selected.

- Native macOS utility for someone moving between work apps throughout the day, using both bright and dim environments. Follow the system appearance by default; provide explicit light/dark options.
- Full window: concept 1's three-column structure, cool neutral surfaces, hairline separators, restrained blue/system-accent selection, and generous text preview. Preserve the same structure in light and dark appearances.
- Focus mode: concept 2's compact, keyboard-oriented structure. Its dark mockup is the dark-appearance reference; provide an equivalent light appearance with the same hierarchy and controls. Use the same system accent and component vocabulary as the full window.
- Sidebar widget: small and medium native widgets with simple navigation affordances. Use generic labels and no saved content; see section 4.5.
- Use system typography, SF Symbols, standard focus treatment, and restrained use of system accent color.
- Prefer a compact list with readable previews over a grid of decorative cards. Preserve multiline formatting in details.
- History rows in the library and Focus mode show readable ages: Just now below one minute, then one whole minute/hour/day unit rounded down (for example, 5 minutes ago). Refresh at minute cadence; never display a seconds counter.
- Keep status explicit: Locked, Capturing, Paused, Permission needed, or Storage error. The menu bar must not imply active capture when capture is stopped.
- Settings groups: General, History, Privacy & Security, and About.
- Support keyboard-only use, VoiceOver, increased contrast, reduced motion, and resizing. Never use color alone to communicate state.
- Masked text must stay masked in accessibility labels, search summaries, tooltips, and copy feedback. Announce Sensitive content instead of reading the body.
- Do not show real example addresses or cards in a first-run vault. Empty states are not persisted sample data.

The selected concepts guide implementation without reopening the overall direction. Refine exact sizing and the remaining states within this baseline: snippet editing, masked sensitive content, locked vault, first run, permission denied, shortcut recording/conflicts, and empty/search-empty states. See `designs/README.md` for the selected visual references.

## 10. Architecture and data model

Use a committed Xcode app project with local Swift package modules for testable core logic. A contributor should not need a project generator or web runtime.

| Module | Responsibility |
| --- | --- |
| App | SwiftUI scenes, menu bar, AppKit panel integration, composition root. |
| Domain | Record models, validation, duplicate/retention policy, search semantics. |
| Vault | Keychain/authentication adapter, CryptoKit envelopes, SQLite repository, migrations. |
| Clipboard | Pasteboard adapter, polling, markers, exclusions, owned-copy cleanup. |
| Platform | Session/idle events, global hotkey registration, launch-at-login adapter. |
| Widget extension | Static WidgetKit presentation and navigation links only; no vault or clipboard dependencies. |

- Use actors and structured concurrency for vault access and long-running work; keep AppKit calls and UI state on the main actor as required.
- Inject clipboard, clock, authentication, crypto, and storage interfaces for deterministic tests. Production crypto tests must also exercise actual CryptoKit.
- All work carries an unlocked-session generation so a late callback cannot populate a newly locked UI or save a stale draft.
- Use public global-hotkey APIs without keyboard event taps or Input Monitoring. Prove compatibility with App Sandbox in the first technical milestone.
- Keep third-party runtime dependencies at zero initially. Introduce a dependency only for a demonstrated maintenance benefit and review its license, security, and release process.

### Logical records, all encrypted

| Record | Fields |
| --- | --- |
| History item | UUID, text, firstSeenAt, lastSeenAt, lastCopiedAt?, repeatCount, sourceBundleID?, sourceName?, isPinned. |
| Snippet | UUID, name, body, category?, isSensitive, createdAt, updatedAt, lastCopiedAt?. |
| Settings | Capture enabled, manual pause, retention days/count, excluded bundle IDs, idle-lock choice, settings version. |
| Vault verification | Vault UUID, schema version, expected fixed verification value. |

Timestamps use UTC instants and display in the user's locale/timezone. Missing source attribution is valid. Categories are labels, not structured card/address fields. Do not silently normalize or strip user text during storage or copying.

## 11. Performance and reliability targets

These are measurement targets, not claims of completed validation. Record reference hardware, OS version, payload distribution, and measured percentiles.

- Warm quick-panel presentation: under 200 ms at the 95th percentile.
- Search after the index is ready: under 100 ms at the 95th percentile for 5,000 history entries and 2,000 snippets using representative short text.
- Typical capture: visible within 1 second of an observed copy under ordinary load.
- Idle CPU: below 1% on reference Apple silicon hardware with capture enabled and no clipboard changes; pause polling while locked or asleep.
- Bound memory by input/count/storage limits, use lazy detail rendering, and benchmark near the payload cap. Do not block the main thread on full-vault decryption or indexing.
- Search is unavailable until unlock/index preparation completes; show meaningful progress rather than an empty library that could imply data loss.
- Complete encryption and durable persistence before reporting a saved snippet as successful.

## 12. Verification and acceptance criteria

### Functional

- [ ] **FUNC-01** A fresh install can create a vault, enable capture, observe a new plain-text copy, search it, and copy it back without internet or Accessibility permission. **In progress:** signed fresh development-vault scenario on Apple silicon macOS 26.6.2 creates/unlocks, enables capture after OS permission, captures/searches/copies a synthetic multiline Unicode fixture with exact whitespace. No Accessibility/Input Monitoring prompt or app network entitlement. The explicit offline repeat remains pending; network connectivity was not disabled during this run. See [native scenario and limits](docs/native-integration.md#signed-native-capture-and-first-unlock); clean-Mac release installation remains REL-03.
- [ ] **FUNC-02** Snippets survive relaunch, preserve exact text, and remain independent of history cleanup.
- [ ] **FUNC-03** Duplicate refresh, retention, pinned limits, maximum sizes, storage exhaustion, denied permissions, and failed clipboard writes have deterministic behavior.
- [ ] **FUNC-04** Manual pause survives lock/unlock and relaunch. Old clipboard content is not imported on startup/resume/unlock.
- [ ] **FUNC-05** CopySaver writes do not create history feedback loops or duplicate saved snippets into history.
- [ ] **FUNC-06** Shortcut, menu bar, login launch, and standard window behavior work on the minimum supported macOS and the latest stable release at test time.
- [ ] **FUNC-07** A user can record a global Focus Mode shortcut, use it from another app while the library is closed, navigate/search/copy, and return to that app. The binding survives restart; replacing it unregisters the old binding, and a failed replacement preserves the last working one. Test current-Space/display behavior and supported full-screen contexts.
- [ ] **FUNC-08** Focus mode and the full library share the same records, capture status, and vault lock state. Open Library carries the selected item across; locking conceals both surfaces immediately.
- [ ] **FUNC-09** Small/medium widgets can be added to Notification Center and the desktop. Their links reach Focus mode, History, or Snippets as specified, including a cold app launch and a locked vault. Cancellation leaves the vault locked; a widget action never copies data or silently enables capture.

### Security

- [ ] **SEC-01** Seed unique canary bodies, titles, categories, source identifiers, and settings. After CRUD, retention, crash recovery, migration, and checkpointing, inspect database/WAL/SHM, preferences, temporary files, app logs, and app-generated diagnostic artifacts for plaintext canaries.
- [x] **SEC-02** Decryption fails with the wrong key and after changing ciphertext, nonce, tag, record ID, vault ID, or authenticated version. Swapping encrypted row envelopes fails. Evidence: `RecordCipherTests` wrong-key/identity/tampering/version tests exercise production CryptoKit; persisted tampering also locks the session.
- [x] **SEC-03** Repeated updates of the same record use different nonces and ciphertext; test the actual encryption path and verify round trips with independent format fixtures. Evidence: 50 repeated seals, persisted resealing tests, and the checked-in Node.js/OpenSSL AES-GCM fixture pass in the clean-source 31-test suite.
- [ ] **SEC-04** A copied database cannot be opened by a fresh installation without its key. Missing-key handling preserves the original vault. **In progress:** native isolated-owner key removal refuses unlock/writes, preserves exact DB/WAL/SHM bytes and does not generate a replacement key. Copied-database/fresh-install testing remains pending.
- [x] **SEC-05** Validate Keychain user-presence enforcement and app identity restrictions using signed builds, including a separately signed helper that must not retrieve the key. Debug-only tests are insufficient evidence. Evidence: Apple Development Release owner/helper fixtures on Apple silicon macOS 26.6.2 have audited separate own groups, sandbox/hardened runtime and no debugger entitlement. UI-forbidden own-key reads return interaction-required before both successful helper controls; the helper cannot see the owner item, cleans up its control, and owner exact-text reads pass before/after. User confirms both repeat-helper prompts and owner Touch ID. See [signed evidence](docs/keychain-validation.md#user-presence-negative-control-october-29-2026). Production Developer ID/minimum-OS validation and separate cancellation cases remain open.
- [ ] **SEC-06** Verify lock, sleep, fast user switching, idle timeout, and termination paths. Race delayed reads, commits, and searches against lock; no stale content may reappear or commit after Locked is published.
- [ ] **SEC-07** Denied/cancelled authentication never reveals, edits, or copies sensitive bodies. Masking also holds in accessibility output.
- [ ] **SEC-08** Sensitive auto-clear does not overwrite a newer external clipboard item. Test timer expiry, sleep/wake, lock, and ownership-marker replacement. **In progress:** In-memory tests pass for preexisting replacement, marker replacement and replacement during marker reads; production-layer tests cover expiry/lock. Real pasteboard timing, sleep/wake and the residual final-check/clear interval remain pending.
- [ ] **SEC-09** Concealed/transient markers and excluded-app transitions prevent persistence in tested cases; document attribution limits and residual races.
- [ ] **SEC-10** Audit entitlements and observe runtime network activity: the app has no networking or content-bearing diagnostics in v0.1.
- [ ] **SEC-11** Inspect widget previews, timelines, snapshots, URLs, extension storage, and entitlements: no vault access, content, keys, or user-derived metadata. Test valid and malformed deep links while the app is stopped, locked, and unlocked; only valid navigation occurs and authentication remains enforced.

### Usability and release

- [ ] **REL-01** Keyboard-only and VoiceOver completion of setup, search/copy, snippet CRUD, locking/unlocking, and permission-error recovery.
- [ ] **REL-02** Readable light/dark/high-contrast states with no content leaked behind locked views.
- [ ] **REL-03** Clean-Mac DMG installation, signature/notarization verification, and launch without Gatekeeper bypass instructions.
- [ ] **REL-04** Contributor build/test instructions work from a clean checkout. CI runs core tests and builds the app; release validation additionally covers signed Keychain and real OS permission flows.

## 13. Implementation milestones

Stable task IDs, current status, dependencies, and the progress log are in section 0. These milestone descriptions define exit gates; they do not imply that implementation has begun or validation has passed.

### M1: prove the platform and vault

Create the project and core package. Prove sandboxed clipboard reads, permission handling, global shortcut, signed data protection Keychain access with password fallback, AES-GCM persistence, and session locking on a real Mac. Prove a minimal widget-to-app navigation link without sharing vault data. Establish format fixtures and migration tests. No production UI polish before these integrations are known to work.

Exit: a signed technical build can create, unlock, write, relaunch, and decrypt a vault; an unauthorized helper cannot retrieve its key; permission denial and missing-key cases fail safely. If a critical API assumption fails, amend this spec before expanding implementation.

The user authorized starting with the standalone Swift toolchain while full Xcode was broken, then explicitly approved the Apple-signed support-package repair. Xcode now builds the universal app and embedded widget without signing. Keep signed Keychain, native widget/lifecycle integration, and the M1 exit scenario unchecked until they are actually validated.

### M2: history end to end

Implement capture filters, deduplication, retention, in-memory search, quick panel, copy ownership, pause/resume, and recoverable storage errors.

Exit: copy → encrypted commit → search → copy-back works, with capture stopping correctly for lock, pause, denied permission, and disk failure.

### M3: snippets and sensitive actions

Implement snippet CRUD, templates, promotion from history, fresh authentication, masking, sensitive clipboard expiry, and clear/delete/reset flows.

Exit: named reusable text and sensitive snippets meet their functional and security acceptance cases.

### M4: release hardening

Complete remaining visual states within the approved concepts 1 and 2, small/medium launcher widgets, accessibility, lifecycle tests, performance profiling, login launch, first-run permission guidance, and documentation. Build the signed/notarized DMG and validate on clean machines, including widget gallery discovery and placement.

Exit: all v0.1 acceptance criteria pass or the release remains explicitly a development preview with documented blockers. Do not advertise unverified security properties.

## 14. Open source and setup

- Repository artifacts: `README.md`, MIT `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`, this spec, architecture/security notes, and CI configuration.
- README leads with the macOS install flow, privacy behavior, capture/lock tradeoff, and device-bound recovery limitations.
- Source setup: `make app` builds the automatic ad-hoc community development app without an Apple account; `make community-dmg` uses full Xcode for the universal app/widget package. The committed Xcode scheme retains the protected compatibility profile and needs provisioning for its Keychain. `make test` runs core tests.
- Document that development signing and production signing differ; local builds do not inherit release-vault access. Paid developer credentials are not required to read the source or run pure core tests.
- Publish release source tag, toolchain version, dependency inventory, and artifact checksums. Do not claim reproducible binary builds until separately verified.
- Collect security reports privately through a maintainer-controlled channel in `SECURITY.md`; do not ask users to attach real vaults or snippets to public issues.
- Manual updates in v0.1: the About screen may open the release page in the user's browser on an explicit action; the app itself performs no update polling.

## 15. Windows strategy

Windows is a follow-on product effort, not a launch dependency. Target native Windows 11 UI, tray access, a global shortcut, clipboard events, and the same History/Snippets behavior. Evaluate WinUI 3 and .NET when this effort starts rather than maintaining an unused second stack now.

Use the versioned logical schema, AES-GCM envelope definition, and test fixtures as the compatibility contract. Native Keychain keys are not transferable; copying a macOS database will not unlock it on Windows. Cross-device transfer requires the future encrypted export/import design.

On Windows, evaluate user-scoped DPAPI for wrapping a random vault key. DPAPI generally binds access to the user account and is not by itself an app-exclusive or fresh-authentication boundary. Do not use machine-wide protection or advertise parity with macOS user-presence protection without further design and testing. Investigate Windows Hello separately; it is not a drop-in substitution for Keychain access control.

## 16. Remaining release inputs

These do not block writing the implementation, but must be settled before public distribution:

- Confirm the public app name and repository owner. CopySaver is the working name inferred from the project folder.
- Confirm community production bundle ownership. Apple Developer credentials are optional for a future notarized/protected distribution; the selected community DMG requires none.
- Set the private security-report contact and license copyright holder.
- Validate remaining screen states and accessibility within the approved Native library + Focus panel direction; the overall visual direction is already selected.
- Decide when encrypted backup/recovery becomes a release requirement. Until then, v0.1 must disclose its device-bound, non-archive limitations prominently.

## 17. Primary technical references

References checked during planning; deployment availability and behavior still require the signed-build tests in M1.

- [Apple: NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard) and [pasteboard access behavior](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum): shared clipboard and OS-controlled access. Newer permission APIs must be availability-checked on macOS 14.
- [NSPasteboard.org: special clipboard types](https://nspasteboard.org/): interoperability markers for confidential, transient, and generated data.
- [Apple: current-host-only pasteboard contents](https://developer.apple.com/documentation/appkit/nspasteboard/contentsoptions/currenthostonly): restricting CopySaver writes to the current device.
- [Apple: AES-GCM seal with authenticated data](https://developer.apple.com/documentation/cryptokit/aes/gcm/seal(_:using:nonce:authenticating:)): authenticated envelopes and fresh nonces.
- [Apple: data protection Keychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain) and [restricting Keychain item accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility): device/access policy and user-presence restrictions.
- [Apple: App Sandbox](https://developer.apple.com/documentation/security/app-sandbox) and [sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox): permissions, containers, and code identity.
- [Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice): user-controlled launch at login.
- [Apple: linking to app scenes from widgets](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity) and [widget interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities): navigation links, separate extension execution, and system-managed widget representations.
- [Microsoft: CryptProtectData](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata): future Windows key wrapping and user/machine scope.
