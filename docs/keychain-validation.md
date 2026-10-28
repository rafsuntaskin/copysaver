# Signed Keychain boundary validation

This is an operator procedure for M1-09/M1-10/M1-14 and SEC-05, not evidence that those gates pass. It needs a real Apple development identity, the device owner's authentication, and a confirmed synthetic development vault. Do not run against a production vault or real saved content. No credentials or keys belong in the repository or evidence.

## Separate helper

The shared `CopySaverKeychainProbe` scheme builds a separate sandboxed/hardened app, provisionally `org.copysaver.CopySaver.dev.BoundaryProbe`. It is not a dependency, embedded helper, or archive product of the CopySaver scheme. Its explicit entitlements are App Sandbox and its own `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)` Keychain group. The owner uses its own distinct group; the widget requests none. It uses the production Keychain adapter, but never opens a database, reads the clipboard, prints returned key bytes, or writes a key to a file.

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

## Automated limits

`make verify` compiles the fixture and runs seven admission checks against the unbundled executable: help, malformed arguments, production namespace rejection, missing synthetic confirmation, malformed UUID, unsigned probe refusal, and unsigned cleanup refusal. These checks never call Keychain, authenticate, or touch a clipboard/vault. Static checks keep the helper out of the product build/embed graph. The signed integration scenario remains a separate manual gate.
