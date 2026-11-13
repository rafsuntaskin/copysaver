# Release validation

Stable release approval remains pending. The community beta procedure is in [RELEASING.md](RELEASING.md); beta tags do not close the stable acceptance gates. Source/build checks do not establish signed platform behavior. Record exact app revision, signing identity, OS/hardware, dates, and outcomes in the spec before checking a gate. Use synthetic data only. Never commit actual vaults, credentials, private clipboard content, or signing material.

## Required inputs

Confirm app/repository ownership, production bundle identifiers, private security-report channel and license attribution (M4-08). Apple Developer team/Developer ID inputs apply only to the optional notarized/protected path. No account, identity, or remote is invented. Confirm the Keychain-dependent recovery/no-portable-backup decision and publish the disclosure in [PRIVACY.txt](PRIVACY.txt).

## Community DMG

The November 3 revision selects a separate, automatic login-Keychain community build with no Apple-issued signing key. Developer ID/notarization inputs and the signed archive procedure below apply only to the protected compatibility profile. Community acceptance follows AUTO-01–AUTO-03 in the spec. Account compromise and a decryptable login Keychain are outside its at-rest promise; review [COMMUNITY.txt](COMMUNITY.txt).

From a clean reviewed checkout, run `make verify`, then `make community-dmg`. The script builds a universal app/widget, ad-hoc signs each with sandbox and hardened runtime, audits the absence of Apple authorities/restricted entitlements/provisioning, and writes the DMG, SHA-256, source revision, toolchain, dependency and build-status files under ignored `.build/community/`. For an explicitly local uncommitted preview use `./scripts/community-release.sh --preview`; never label its dirty artifact a reviewed release. These commands never publish or submit to Apple.

Validate the downloaded/quarantined DMG on clean supported Macs. First launch may require macOS Privacy & Security approval; do not disable Gatekeeper or strip quarantine in installation scripts. After approval, verify automatic create/open, OS clipboard permission, new-copy capture without old imports, exact snippet/history reopen, saved pause/disable, real sleep/wake/session switching, explicit Hide and pause, Keychain denial/update approval, missing-key/tamper preservation, and sensitive preview/reveal/edit/copy behavior without additional authentication inside the open community library. Widget discovery, cold routing, supported OS/Intel, VoiceOver and the remaining security/performance gates remain required where applicable. No Gatekeeper exception is proof of protected-Keychain or application-exclusive access. Ad-hoc updates can prompt again; do not promise first-run-only approval forever.

## Native evidence matrix

Run each scenario on macOS 14 and the latest supported stable macOS, on Apple silicon and Intel where supported:

1. **Installation and identity:** clean checkout `make verify`, unsigned Xcode app/widget build, actual development-signed app, signed release archive; inspect parent/extension identifiers, entitlements, hardened runtime and absence of App Groups/shared Keychain permissions, and outgoing network access only in the parent app for website previews. No Gatekeeper bypass instructions.
2. **Protected vault:** explicit create → locked → authenticated unlock → save → quit/relaunch locked → authenticated reopen. Deny/cancel/lock out authentication; remove only a test-owned key and verify original files survive. Follow the [signed boundary-probe procedure](keychain-validation.md) to test a separately signed helper against the synthetic app key, with owner success before and after. Ad-hoc or missing-entitlement failures do not satisfy this test.
3. **Capture permission:** history initially off; enable deliberately. On permission-controlled systems test Default/Ask, Always Allow, denial, revocation and restoration. No repeated prompts or old-content import. Test all markers, multi-item/file/image/oversize rejection, rapid copies, activation/excluded-app races and self-copy suppression.
4. **Lifecycle:** lock from both surfaces, screen lock without screen sleep, sleep/wake, fast user switching, configured idle choices, quit, forced termination and login launch. No stale reads, edits, results or commits after Locked. Prove or replace the supplemental undocumented screen-lock notification before release.
5. **Sensitive UI:** fresh authentication for reveal/copy/edit/sensitivity changes and editor Copy/Cut; cancellation leaves clipboard/draft unchanged. Masking holds in AX/VoiceOver/tooltips/search. Reveal expires at 30 seconds and on dismissal/deactivation. Private drafts conceal and require fresh authentication to continue; undo stacks do not restore text across lock.
6. **Clipboard output:** current-host-only marker behavior, write denial/failure, correct last-copy timestamps, sensitive ownership/deadline clearing, external copy and marker races, sleep/wake expiry, no old-clipboard restoration. Inspect only test-owned clipboard data.
7. **Focus/navigation:** configurable shortcut from another app with the library closed, atomic replacement/conflict failure, query reset, arrows/Return/Command-C/Escape, selection handoff and previous-app focus. Multiple displays, Spaces/full-screen, minimum/compact widths, light/dark, increased contrast and reduced motion. Complete setup/search/copy/snippet CRUD/error recovery using keyboard and VoiceOver.
8. **Widget:** small/medium discovery in Notification Center and desktop, static preview/snapshot/timeline inspection, cold/locked/unlocked exact navigation and malformed URLs. It never reads clipboard/vault/Keychain, displays user metadata, copies automatically or changes capture preferences. Inspect extension dependencies/entitlements and its on-disk state.
9. **Data and recovery:** all functional/SEC checks in spec section 12, including near-limit retention/budget, lower-limit confirmation, pins/snippet independence, missing key, corruption, forced-process crash/transaction recovery, and synthetic canary scans across DB/WAL/SHM/preferences/temp/log/diagnostics. No plaintext queues or migration writes to unknown formats.
10. **Performance/network:** record hardware/OS/dataset and percentiles for panel/search/capture, idle CPU and near-budget memory. Observe runtime network activity in normal operation and failure flows; only the selected-link preview and its image may contact external sites while enabled. Verify no preview requests for sensitive/disabled/hidden selections and no cookie/credential/disk-cache persistence.

Native screen/permission/authentication tests may need the device owner to interact. Do not bypass authentication, OS prompts, or the known Xcode installer approval requirement to manufacture results.

## Local artifact workflow

```sh
make verify
DEVELOPMENT_TEAM=YOUR_TEAM SIGNING_IDENTITY='Developer ID Application: Your Name (YOUR_TEAM)' make archive
```

After all applicable gates pass, use an existing notarytool Keychain profile:

```sh
DEVELOPMENT_TEAM=YOUR_TEAM SIGNING_IDENTITY='Developer ID Application: Your Name (YOUR_TEAM)' NOTARY_PROFILE=YOUR_PROFILE RELEASE_VALIDATION_CONFIRMED=yes ./scripts/release.sh notarize
```

These are operator templates, not commands that have passed here. The script archives a universal app with embedded widget, verifies both architectures and code signatures, notarizes/staples the app, creates/signs/notarizes/staples a drag-to-Applications DMG, and writes checksums, source revision, toolchain and dependency inventory under ignored `.build/distribution/`. It never creates credentials, pushes, tags, or publishes. The archive command requires a clean reviewed checkout and records its source/toolchain manifest at build time. Keep existing archives for diagnosis rather than overwriting them.

Validate the final DMG on clean supported Macs, including offline launch after stapling. Only then authorize publication/tagging and update the release checklist. CI configuration is committed; existing hosted runs have failed at startup before jobs. Hosted execution stays unverified until a run passes.
