# Signed Keychain boundary validation

These operator procedures and recorded results cover M1-09/M1-10/M1-14 and SEC-05. Verified outcomes are limited to the configurations and scenarios recorded below. Running the procedures requires a real Apple development identity, the device owner's authentication, and a confirmed synthetic development vault. Do not run against a production vault or real saved content. No credentials or keys belong in the repository or evidence.

## Separate helper

The shared `CopySaverKeychainProbe` scheme builds a separate sandboxed/hardened app, provisionally `org.copysaver.CopySaver.dev.BoundaryProbe`. It is not a dependency, embedded helper, or archive product of the CopySaver scheme. Its explicit entitlements are App Sandbox and its own `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)` Keychain group. The owner uses its own distinct group; the widget requests none. In helper mode it uses the production Keychain adapter without opening a database or reading the clipboard. The fixed isolated-owner mode described below additionally exercises the production desktop vault service, CryptoKit and SQLite. Neither mode prints returned key bytes or writes a key to a file. Owner mode is admitted only under its fixed separate signed identity, before any file or Keychain operations.

The helper requires its running bundle and valid code-signing identifier to match the supplied development owner's identifier plus `.BoundaryProbe`, and requires a signing team. An unbundled SwiftPM executable or ad-hoc build refuses before Keychain access. The CLI accepts only owner identifiers ending in `.dev` and requires explicit confirmation that the target vault is synthetic. These guards reduce accidental misuse; they do not establish OS isolation.

After admission, the helper creates an add-only synthetic control under its own identity, authenticates a read and verifies a CryptoKit round trip. It then asks the same adapter for the owner's service/account using its own process identity. Only `errSecItemNotFound` is an expected isolation observation. Unexpected access fails; cancellation, missing entitlements and every other error are inconclusive. It authenticates/verifies its control again and deletes only that control. The target key is never changed.

## Build and inspect

Configure your development team in Xcode for the CopySaver and CopySaverKeychainProbe schemes. Use the same team for the owner and helper; retain their distinct app identifiers and default separate Keychain access. Do not add shared Keychain groups or loosen authentication to make the probe pass. The identifiers are provisional until ownership is confirmed; update the project and matching commands together if they change.

An unsigned compilation check is available without credentials:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project CopySaver.xcodeproj -scheme CopySaverKeychainProbe -configuration Debug \
  -destination 'generic/platform=macOS' -derivedDataPath .build/xcode-verification \
  CODE_SIGNING_ALLOWED=NO build
```

This command cannot run the authenticated probe successfully. After selecting the real team, build both schemes with development signing enabled. Inspect both resulting apps using `codesign -dvvv` and `codesign -d --entitlements :-`. Verify the expected distinct identifiers, the same real TeamIdentifier, valid signatures, sandbox/hardened-runtime configuration, and only each app’s own Keychain group, with no shared group or App Group entitlement. A profile may authorize a team-prefix wildcard; each executable must claim only its own fully expanded group. The helper must never claim the owner’s group. Inspect Xcode-added entitlements as well as the committed files. Do not treat a missing-entitlement failure as a passed boundary test.

## Manual scenario

1. Launch the signed development CopySaver app. Start with a separately confirmed synthetic development vault; never reset an existing vault to prepare this test. Create it explicitly, then authenticate, save fictional text, quit, relaunch locked, and authenticate again. Record the signed app revision, OS/hardware and outcomes.
2. Obtain the opaque vault UUID from that fixture's plaintext header, without decrypting records or printing payloads. For example, substitute the confirmed fixture path in `sqlite3 -readonly /absolute/path/to/confirmed-synthetic/vault.sqlite 'SELECT vault_id FROM metadata WHERE singleton=1;'`. The helper accepts that UUID, not a database path. Verify the namespace and UUID against the exact fixture being exercised.
3. Run the signed helper executable from its built `.app`, substituting that fixture UUID:

   ```sh
   .build/xcode-verification/Build/Products/Debug/CopySaverKeychainProbe.app/Contents/MacOS/CopySaverKeychainProbe \
     --owner-bundle-id org.copysaver.CopySaver.dev \
     --synthetic-vault-id YOUR_SYNTHETIC_VAULT_UUID --confirm-synthetic-vault
   ```

   Complete the helper's two own-control authentication requests. Any unexpected target authentication request or returned key is a failed/inconclusive scenario, never permission to approve the gate. The helper prints only static result messages, never keys, target UUIDs or query values.
4. Lock and freshly unlock the **same owner fixture** again, and read its fictional saved text. This must succeed after the helper result. Owner success before and after is required to exclude a missing-key or wrong-fixture false positive. Check the development app's cancellation/password-fallback/lockout behavior separately; the probe does not automate it.
5. Record the owner/helper signatures and entitlement audit, successful owner unlocks, expected helper result and successful control cleanup. Keep SEC-05 unchecked until the full scenario actually passes on supported signed builds. Do not interpret this as protection from administrators, malware in an unlocked session, or all programs signed by a compromised team.

The helper never deletes an existing control automatically after a duplicate-item error. If a probe was interrupted, first confirm no other probe is active, then explicitly remove its fixed synthetic control:

```sh
.build/xcode-verification/Build/Products/Debug/CopySaverKeychainProbe.app/Contents/MacOS/CopySaverKeychainProbe \
  --owner-bundle-id org.copysaver.CopySaver.dev --cleanup-control
```

Cleanup addresses only the helper's fixed synthetic account under its own service. It never deletes an owner-app key or vault. A crash may leave that control in Keychain until cleanup; no automatic orphan-key deletion is performed.

## Isolated owner for a development app already in use

Once the ordinary development app contains personal clipboard history, do not use that vault for this procedure. The same test-only target can be built twice with distinct identities: an isolated synthetic owner and its separate helper. Neither is embedded in CopySaver or the widget. Owner mode uses a fixed namespace, fixed location within its own sandbox, and fixed fictional content; callers cannot supply another vault path, content or owner identity. It never captures the clipboard.

Build both from the current sources with your real development team, replacing `YOUR_TEAM_ID`. Keep the build products in separate directories:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project CopySaver.xcodeproj -scheme CopySaverKeychainProbe -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/isolated-keychain-owner \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID CODE_SIGN_IDENTITY='Apple Development' \
  PRODUCT_BUNDLE_IDENTIFIER=org.copysaver.CopySaver.SecurityFixture.dev \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO -allowProvisioningUpdates build
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project CopySaver.xcodeproj -scheme CopySaverKeychainProbe -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/isolated-keychain-helper \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID CODE_SIGN_IDENTITY='Apple Development' \
  PRODUCT_BUNDLE_IDENTIFIER=org.copysaver.CopySaver.SecurityFixture.dev.BoundaryProbe \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO -allowProvisioningUpdates build
```

Audit both emitted signatures, profiles and entitlements as above. In addition, require no `com.apple.security.get-task-allow`: Xcode can inject that entitlement even in a Release build using an Apple Development identity, hence the explicit base-entitlement setting. Check the final emitted entitlements instead of assuming the build setting removed it. These remain development-certificate fixtures, not Developer ID release validation.

Run the owner from its built bundle executable, completing its system authentication locally:

```sh
.build/isolated-keychain-owner/Build/Products/Release/CopySaverKeychainProbe.app/Contents/MacOS/CopySaverKeychainProbe \
  --owner-fixture create --confirm-synthetic-vault
.build/isolated-keychain-owner/Build/Products/Release/CopySaverKeychainProbe.app/Contents/MacOS/CopySaverKeychainProbe \
  --owner-fixture verify --confirm-synthetic-vault
```

Creation is add-only and refuses an existing fixture. Successful create authenticates, saves fictional text through the production service, locks and verifies writes are denied. Verify starts a fresh process, first requires a fresh UI-forbidden protected read to return `errSecInteractionNotAllowed`, then authenticates interactively and checks the exact saved UTF-8 body and fixed title/category with capture disabled, locks and checks denied writes. Both success messages are static and contain no keys or vault metadata. An interrupted or unexpected fixture is preserved for diagnosis.

Read only the vault UUID from this fixed fixture's header. The expected path is `~/Library/Containers/org.copysaver.CopySaver.SecurityFixture.dev/Data/Library/Application Support/SyntheticKeychainValidation/vault.sqlite`. Follow the manual helper scenario above, substituting the isolated owner identifier and its matching helper executable:

```sh
.build/isolated-keychain-helper/Build/Products/Release/CopySaverKeychainProbe.app/Contents/MacOS/CopySaverKeychainProbe \
  --owner-bundle-id org.copysaver.CopySaver.SecurityFixture.dev \
  --synthetic-vault-id YOUR_SYNTHETIC_VAULT_UUID --confirm-synthetic-vault
```

The helper emits static progress before each own-control read. It also requires a UI-forbidden read to fail with interaction-required before both authenticated control reads, including after the first authentication. Complete only the two helper-own-control authentication requests. An unexpected target access request is inconclusive/failure; do not approve it. Then run owner `verify` again against the same fixture to exclude an absent-key false positive. A standalone owner `--owner-fixture noninteractive --confirm-synthetic-vault` runs only the UI-forbidden negative control and checks that writes remain locked. It never asks for authentication. Missing items, missing entitlements and any status other than interaction-required are inconclusive; a successful read explicitly fails. For a separate cancellation test, run owner `--owner-fixture cancel --confirm-synthetic-vault` and choose Cancel in the system prompt. Only a cancellation with denied subsequent writes passes that test; verify again afterward to confirm saved data survived. Password fallback requires an actual owner authentication through the password option, recorded separately. Authenticating in the `cancel` test makes that test inconclusive; it is not evidence that cancellation was exercised.

Explicit cleanup, after all probe processes exit, requires both confirmations and authentication. It accepts only the expected synthetic records (or the unseeded settings-only fixture after interrupted creation), then uses the production reset flow, including fresh authentication, to remove its own vault and key:

```sh
.build/isolated-keychain-owner/Build/Products/Release/CopySaverKeychainProbe.app/Contents/MacOS/CopySaverKeychainProbe \
  --owner-fixture cleanup --confirm-synthetic-vault --confirm-delete-fixture
```

The final destructive missing-key scenario is also restricted to this fixed owner and requires both confirmations. It first denies a UI-forbidden read, authenticates and verifies the synthetic canary, locks, snapshots the exact database/WAL/SHM bytes, then deletes only that fixture’s key. It requires missing-key unlock failure, denied writes, unchanged file bytes and a second missing-key read proving no replacement was generated. Only after those checks does explicitly confirmed fixture cleanup use the production reset path. Any earlier failure preserves remaining files for diagnosis.

```sh
.build/isolated-keychain-owner/Build/Products/Release/CopySaverKeychainProbe.app/Contents/MacOS/CopySaverKeychainProbe \
  --owner-fixture missing-key --confirm-synthetic-vault --confirm-delete-fixture
```

Never reset the ordinary clipboard-history app to prepare or clean up this fixture. An unexpected/corrupt fixture fails closed and is preserved rather than guessed at or silently replaced.

## Automated limits

`make verify` compiles the fixture and runs 18 admission checks against the unbundled executable: help, malformed arguments, production namespace rejection, missing synthetic confirmation, malformed UUID, unsigned probe refusal, unsigned cleanup refusal, owner-mode unsigned refusals (including the UI-forbidden action), missing confirmations, unknown actions and extra-path rejection. The guard script refuses `.app` bundle paths and certificate-signed executables before launching anything, including under optimized Python, preventing accidental owner fixture operations during a nominally non-Keychain check. These checks never call Keychain, authenticate, or touch a clipboard/vault. Static checks keep the helper out of the product build/embed graph. The signed integration scenario remains a separate manual gate.

## Isolated fixture evidence, October 28, 2026

Universal Release owner/helper builds pass with real Apple Development profiles. Audit verifies the same team, distinct application identifiers, exactly one own-bundle Keychain group apiece, sandbox/hardened runtime, and absence of debugger/network/shared-group entitlements. Initial Release signing injected `get-task-allow`; rebuilding with the explicit base-entitlement setting removed it, confirmed in the final signatures. These are development-signed fixtures, not a notarized product.

On Apple silicon macOS 26.6.2, owner create/authenticate/save/lock and a fresh-process authenticated exact-text verification pass, including denied writes after locking. A read-only scan finds exactly three encrypted rows and no body/title/category canaries in database/WAL/SHM. The 15 unbundled admission guards and a separate guard-runner bundle refusal pass without Keychain access. Both signed executables also reject the opposite role before fixture operations. `make verify` passes 87 functional checks with two benchmarks skipped. The helper is running and awaits its own-control authentication; target denial and successful owner-after verification remain pending. The password-fallback method has not yet been confirmed. SEC-05 and M1-10 remain unchecked.

## User-presence negative control, October 29, 2026

Inspection found the earlier helper completed its controls, received item-not-found for the owner target, and removed its control. The user reported no prompt or failed authentication for that stage, so that log is not treated as proof that its prompts were visibly presented. The owner-after process subsequently authenticated and verified the exact fixture; the user confirms Touch ID.

The strengthened fixture queries each own protected key with a fresh `LAContext`, `interactionNotAllowed = true` and reuse disabled. Only `errSecInteractionNotAllowed` passes; successful access fails, and missing keys, entitlement failures and all other statuses are inconclusive. Native owner negative controls pass. The strengthened helper repeat also passes both UI-forbidden refusals (including after its first authentication), both authenticated production-provider controls, owner-target item-not-found and control cleanup. The user confirms completing both prompts for this repeat. These results establish the recorded signed identity-isolation/user-presence scenario on the reference Mac; they do not explain the earlier missing-prompt observation.

The final owner `missing-key` run first passed its UI-forbidden check and authenticated exact-canary verification, providing the owner-after check for the helper repeat. It then removed only the synthetic owner key, required missing-key unlock failure and locked write admission, compared unchanged database/WAL/SHM bytes, and confirmed no replacement key existed. Explicit synthetic reset followed only after those checks; an external existence check confirms the fixture database and sidecars were removed. Personal clipboard-history data was never opened or reset.

Universal Release builds and both-architecture signature/profile/own-group entitlement audits pass without debugger/network/shared-group entitlements. The guard runner rejects signed bundles and copied certificate-signed executables before launch, including under Python optimization. `make verify` passes 87 functional checks and 18 admission guards (two benchmarks skipped). M1-10 and SEC-05 pass for these reference-Mac scenarios. This does not complete Developer ID distribution, minimum-OS/Intel execution, copied-vault/fresh-install, lifecycle, or sensitive-UI acceptance.

Cancellation remains unverified: the user authenticated instead of choosing Cancel, and that particular test correctly returned inconclusive. The user confirms earlier owner reads used Touch ID and the successful final `missing-key` run used the Mac-password option. Its initial protected read verified the exact synthetic canary through the production provider/service before key removal, so password fallback is verified and M1-09 is complete for this reference-Mac scenario. The production Keychain transport/authentication policy is unchanged; all new controls belong to the manual fixture.

The negative-control API follows Apple’s [interactionNotAllowed property](https://developer.apple.com/documentation/localauthentication/lacontext/interactionnotallowed). Apple’s [Keychain UI-failure documentation](https://developer.apple.com/documentation/security/ksecuseauthenticationuifail) specifies interaction-required when authentication is needed and directs new code to that context property. [Authentication context reuse](https://developer.apple.com/documentation/security/ksecuseauthenticationcontext) is separate from proving that a prompt was visibly shown.
