# Vault format and core boundaries

## Implementation status

`CopySaverDomain` supplies validated immutable record models, a versioned JSON codec, and independent capture-admission conditions. `CopySaverVault` supplies authenticated encryption, SQLite persistence, and an actor-isolated session. This is a core library, not an authenticated desktop app. Native Keychain access, clipboard polling, retention/search, UI, and widgets are later tasks.

The current format is version 1 with no supported legacy production schema. Opening a newer SQLite schema fails without applying configuration/migration writes. An uninitialized/older database is rejected and preserved rather than guessed at or reset. A future format change must add an explicit migration and compatibility tests before changing this policy.

## SQLite schema

`PRAGMA user_version` is 1. The only application tables are:

```sql
CREATE TABLE metadata (
    singleton INTEGER PRIMARY KEY CHECK(singleton=1),
    vault_id TEXT NOT NULL,
    verification_id TEXT NOT NULL
);
CREATE TABLE records (
    id TEXT PRIMARY KEY NOT NULL,
    version INTEGER NOT NULL CHECK(version>0),
    payload BLOB NOT NULL
);
```

The header and row identifiers are UUIDs, not content-derived identifiers. `version` is the envelope version. `payload` contains the sealed bytes. Record kind, body, name, categories, business timestamps, source attribution, settings, and pin/repeat metadata are inside encrypted JSON. There is no key, content hash, content index, or content-bearing filename in the database.

SQLite receives ciphertext only. Connections are confined to the `VaultSession` actor, use parameterized statements, WAL, full synchronous commits, memory-backed temporary storage, automatic WAL checkpoints, and a 4 MiB journal-size-limit policy. The live ciphertext budget is at most 128 MiB and includes the verification record. This is not a hard physical file-size bound; SQLite pages and journals add overhead.

Batch save/delete operations use one immediate transaction. Budget enforcement occurs before commit; failures roll back the whole batch. Tests cover budget failure, an injected SQLite write failure, and reopening after an uncommitted connection is closed. Forced process termination and full app migration/crash scenarios remain release acceptance work.

New database files are exclusively created with owner-only permissions, so creation never replaces an existing vault. Newly created parent directories use mode 0700. No existing parent directory's permissions are changed. Missing keys, bad tags, and unsupported formats never cause automatic recreation.

## Record and encryption envelope

The plaintext is `VaultRecord` version 1 encoded as UTF-8 JSON. Dates use milliseconds since the Unix epoch. The tagged `payload` uses Swift's synthesized enum encoding (`history`, `snippet`, `settings`, or `verification`, each with `_0` for its associated model). Encoding/decoding validates the model and format versions; decoding does not trust serialized values merely because they have the right JSON shape.

Encryption uses CryptoKit AES-256-GCM. Every seal, including updates with unchanged text, generates a fresh random 12-byte nonce. The database blob is:

```text
nonce (12 bytes) || ciphertext (variable) || authentication tag (16 bytes)
```

Additional authenticated data is the exact UTF-8 encoding of:

```text
CopySaver.Record|<lowercase vault UUID>|<lowercase record UUID>|1
```

The fixed domain and canonical UUID encoding prevent ambiguous concatenation. Unknown envelope versions are rejected. Wrong keys, malformed envelopes, changed nonces/ciphertexts/tags, and moving ciphertext to another row/vault fail closed. Authenticated JSON must also contain the expected record UUID.

`Tests/CopySaverVaultTests/Fixtures/envelope-v1.json` is an independently generated Node.js/OpenSSL AES-GCM fixture. Its key and fixed nonce are public synthetic test values, never used for runtime vaults. The fixture checks the byte layout, authenticated-data convention, and JSON format independently of CryptoKit sealing.

## Session and authentication boundary

Creation receives a key from its caller, persists only an encrypted verification record, and returns a locked session. An app must create/store that key through its authenticated native adapter. There is no file-key storage or fallback in this package.

Unlock obtains a key through `VaultKeyProvider`, validates every encrypted record and the vault's verification record, and only then publishes an unlocked session with a fresh opaque `VaultAccess` token. The encrypted verification record detects a wrong key even when the user has saved no items. Tests inject ephemeral providers; this is not evidence that macOS authentication or app-scoped Keychain access works.

Lock invalidates the generation and access token, releases the key reference, and publishes Locked. Old tokens cannot read or mutate a new session. Authentication completing after lock cannot unlock the vault, replace a newer session, or lock out that newer session on its own failure. Actor-isolated database commits have no suspension point; a commit cannot interleave across a published lock transition. Corrupt/decryption-failing reads lock the session.

Returned plaintext models are intentionally in-memory values. A future app layer must clear its models, queries, drafts, and previews on lock and reject stale UI callbacks; the core cannot erase copies held by callers. Swift/CryptoKit memory management does not establish forensic zeroization.

Capture admission is separate from vault authentication. The domain gate requires an unlocked vault, the user's enabled preference, no manual pause, explicit allowed clipboard access, and writable storage. Unlocking never resets the other inputs.

## Limits of current verification

The core suite checks synthetic canaries in database/WAL/SHM files before and after checkpointing, exact UTF-8 text preservation, limits, nonce diversity, an independent format fixture, errors/rollback, persisted corruption, and delayed/cancelled session work. It does not establish signed Keychain isolation, safe OS clipboard integration, UI masking, widget snapshots, app crash diagnostics, recovery/export, or release readiness. Those checks remain separate in [spec.md](../spec.md#12-verification-and-acceptance-criteria).

## Optional website-preview preference (November 12, 2026)

Settings payloads add `websitePreviewsEnabled`. Missing values decode as true under the explicitly selected automatic-preview policy; an explicit false round-trips and survives unrelated settings changes. The field stays inside the encrypted record. Database/envelope/settings versions remain 1; older clients ignore the unknown field, so downgrading and rewriting settings may discard the disabled choice. Remote metadata and image bytes are never persisted in this format.
