import CopySaverDomain
@testable import CopySaverVault
import CryptoKit
import Foundation
import SQLite3
import Testing

private struct EphemeralKeyProvider: VaultKeyProvider {
    let key: SymmetricKey
    func loadKey(for vaultID: UUID) async throws -> SymmetricKey { key }
}

private enum ProviderFailure: Error { case unavailable }
private struct UnavailableKeyProvider: VaultKeyProvider {
    func loadKey(for vaultID: UUID) async throws -> SymmetricKey { throw ProviderFailure.unavailable }
}

private actor DelayedKeyProvider: VaultKeyProvider {
    private var pending: CheckedContinuation<SymmetricKey, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func loadKey(for vaultID: UUID) async throws -> SymmetricKey {
        await withCheckedContinuation { continuation in
            pending = continuation
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resolve(with key: SymmetricKey) {
        pending?.resume(returning: key)
        pending = nil
    }
}

private final class VaultFixture {
    let directory: URL
    var url: URL { directory.appendingPathComponent("vault.sqlite") }
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("copysaver-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

private func executeSQL(_ sql: String, at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else { throw VaultError.storageFailure }
    defer { sqlite3_close(database) }
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw VaultError.storageFailure }
}

private func rawEnvelope(at url: URL, id: UUID) throws -> EncryptedRecord {
    let store = try SQLiteRecordStore.open(at: url, payloadBudget: RecordLimits.maximumPayloadBytes)
    return try #require(try store.record(id: id))
}

@Test func vaultStartsLockedAndPersistsAcrossReopen() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let provider = EphemeralKeyProvider(key: key)
    let vault = try VaultSession.create(at: fixture.url, key: key)
    #expect(await vault.status == .locked)
    let access = try await vault.unlock(using: provider)
    #expect(try await vault.records(access: access).isEmpty)
    let record = try syntheticRecord()
    try await vault.apply(saving: [record], access: access)
    let reopened = try VaultSession.open(at: fixture.url)
    #expect(await reopened.status == .locked)
    let newAccess = try await reopened.unlock(using: provider)
    #expect(try await reopened.records(access: newAccess) == [record])
    #expect(await reopened.vaultID == vault.vaultID)
    let attributes = try FileManager.default.attributesOfItem(atPath: fixture.url.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func creatingOverAnExistingVaultNeverReplacesIt() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: fixture.url, key: key)
    let access = try await vault.unlock(using: EphemeralKeyProvider(key: key))
    let record = try syntheticRecord()
    try await vault.apply(saving: [record], access: access)
    #expect(throws: VaultError.alreadyExists) {
        try VaultSession.create(at: fixture.url, key: SymmetricKey(size: .bits256))
    }
    #expect(try await vault.record(id: record.id, access: access) == record)
}

@Test func missingVaultIsNotCreatedAndMissingKeyPreservesData() async throws {
    let fixture = try VaultFixture()
    #expect(throws: VaultError.notFound) { try VaultSession.open(at: fixture.url) }
    #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: fixture.url, key: key)
    let before = try Data(contentsOf: fixture.url)
    await #expect(throws: ProviderFailure.unavailable) { try await vault.unlock(using: UnavailableKeyProvider()) }
    #expect(await vault.status == .locked)
    #expect(try Data(contentsOf: fixture.url) == before)
    _ = try await vault.unlock(using: EphemeralKeyProvider(key: key))
}

@Test func wrongKeyCannotUnlockEvenAnEmptyVault() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: fixture.url, key: key)
    await #expect(throws: VaultError.authenticationFailed) {
        try await vault.unlock(using: EphemeralKeyProvider(key: SymmetricKey(size: .bits256)))
    }
    #expect(await vault.status == .locked)
    _ = try await vault.unlock(using: EphemeralKeyProvider(key: key))
}

@Test func lockInvalidatesReadsWritesAndOldSessionTokens() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: fixture.url, key: key)
    let provider = EphemeralKeyProvider(key: key)
    let oldAccess = try await vault.unlock(using: provider)
    await vault.lock()
    await #expect(throws: VaultError.locked) { try await vault.records(access: oldAccess) }
    let record = try syntheticRecord()
    await #expect(throws: VaultError.locked) { try await vault.apply(saving: [record], access: oldAccess) }
    let newAccess = try await vault.unlock(using: provider)
    await #expect(throws: VaultError.staleSession) { try await vault.apply(saving: [record], access: oldAccess) }
    await #expect(throws: VaultError.staleSession) { try await vault.records(access: oldAccess) }
    #expect(try await vault.records(access: newAccess).isEmpty)
}

@Test func delayedAuthenticationCannotUndoLockOrReplaceANewerSession() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: fixture.url, key: key)
    let delayed = DelayedKeyProvider()
    let oldUnlock = Task { try await vault.unlock(using: delayed) }
    await delayed.waitForRequest()
    #expect(await vault.status == .unlocking)
    await vault.lock()
    let currentAccess = try await vault.unlock(using: EphemeralKeyProvider(key: key))
    await delayed.resolve(with: key)
    await #expect(throws: VaultError.staleSession) { try await oldUnlock.value }
    #expect(await vault.status == .unlocked)
    #expect(try await vault.records(access: currentAccess).isEmpty)
}

@Test func cancelledAuthenticationDoesNotPublishAnUnlockedSession() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: fixture.url, key: key)
    let delayed = DelayedKeyProvider()
    let task = Task { try await vault.unlock(using: delayed) }
    await delayed.waitForRequest()
    task.cancel()
    await delayed.resolve(with: key)
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await vault.status == .locked)
}

@Test func updatesResealAndBatchBudgetFailureRollsBackDeletes() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: fixture.url, key: key, payloadBudget: 2_000)
    let access = try await vault.unlock(using: EphemeralKeyProvider(key: key))
    let original = try syntheticRecord()
    try await vault.apply(saving: [original], access: access)
    let first = try rawEnvelope(at: fixture.url, id: original.id)
    try await vault.apply(saving: [original], access: access)
    let second = try rawEnvelope(at: fixture.url, id: original.id)
    #expect(first.sealedData.prefix(12) != second.sealedData.prefix(12))
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let tooLarge = try VaultRecord(.snippet(Snippet(name: "Budget test", body: String(repeating: "a", count: 1_900), createdAt: date, updatedAt: date)))
    await #expect(throws: VaultError.payloadBudgetExceeded) {
        try await vault.apply(saving: [tooLarge], deleting: [original.id], access: access)
    }
    #expect(try await vault.record(id: original.id, access: access) == original)
    #expect(try await vault.record(id: tooLarge.id, access: access) == nil)
}

@Test func injectedSQLiteWriteFailureRollsBackEntireBatch() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: fixture.url, key: key)
    let access = try await vault.unlock(using: EphemeralKeyProvider(key: key))
    let original = try syntheticRecord()
    let accepted = try syntheticRecord()
    let rejected = try syntheticRecord()
    try await vault.apply(saving: [original], access: access)
    try executeSQL("CREATE TRIGGER synthetic_failure BEFORE INSERT ON records WHEN NEW.id='\(rejected.id.uuidString)' BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END", at: fixture.url)
    await #expect(throws: VaultError.storageFailure) {
        try await vault.apply(saving: [accepted, rejected], deleting: [original.id], access: access)
    }
    #expect(try await vault.records(access: access) == [original])
}

@Test(arguments: [0, 2])
func unsupportedDatabaseVersionsArePreserved(version: Int) throws {
    let fixture = try VaultFixture()
    try executeSQL("PRAGMA user_version=\(version)", at: fixture.url)
    let before = try Data(contentsOf: fixture.url)
    #expect(throws: version == 2 ? VaultError.unsupportedDatabaseVersion : .corruptDatabase) {
        try VaultSession.open(at: fixture.url)
    }
    #expect(try Data(contentsOf: fixture.url) == before)
}

@Test func tamperedPersistedRecordLocksTheSession() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: fixture.url, key: key)
    let access = try await vault.unlock(using: EphemeralKeyProvider(key: key))
    let record = try syntheticRecord()
    try await vault.apply(saving: [record], access: access)
    try executeSQL("UPDATE records SET payload=zeroblob(length(payload)) WHERE id='\(record.id.uuidString)'", at: fixture.url)
    await #expect(throws: VaultError.authenticationFailed) { try await vault.record(id: record.id, access: access) }
    #expect(await vault.status == .locked)
    await #expect(throws: VaultError.authenticationFailed) { try await vault.unlock(using: EphemeralKeyProvider(key: key)) }
    #expect(await vault.status == .locked)
}

@Test func protectedVerificationCannotBeOverwrittenOrDeleted() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: fixture.url, key: key)
    let access = try await vault.unlock(using: EphemeralKeyProvider(key: key))
    let store = try SQLiteRecordStore.open(at: fixture.url, payloadBudget: RecordLimits.maximumPayloadBytes)
    let id = store.header.verificationID
    await #expect(throws: VaultError.reservedRecord) { try await vault.apply(saving: [], deleting: [id], access: access) }
    await #expect(throws: VaultError.reservedRecord) {
        try await vault.apply(saving: [VaultRecord(.verification(VaultVerification(vaultID: vault.vaultID)))], access: access)
    }
    #expect(try await vault.records(access: access).isEmpty)
}

@Test func databaseAndWALNeverReceiveSyntheticPlaintextFields() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: fixture.url, key: key)
    let access = try await vault.unlock(using: EphemeralKeyProvider(key: key))
    let canaries = ["CANARY_BODY_52c69e51", "CANARY_NAME_72d83a11", "CANARY_CATEGORY_31d54b71", "CANARY_SOURCE_9c621d30", "CANARY_EXCLUDED_5c11e90a"]
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let snippet = try VaultRecord(.snippet(Snippet(name: canaries[1], body: canaries[0], category: canaries[2], createdAt: date, updatedAt: date)))
    let history = try VaultRecord(.history(HistoryItem(text: canaries[0], firstSeenAt: date, lastSeenAt: date, sourceBundleID: canaries[3], sourceName: canaries[3])))
    let settings = try VaultRecord(.settings(VaultSettings(excludedBundleIDs: [canaries[4]])))
    try await vault.apply(saving: [snippet, history, settings], access: access)
    #expect(FileManager.default.fileExists(atPath: fixture.url.path + "-wal"))
    for checkpoint in [false, true] {
        if checkpoint { try await vault.checkpoint() }
        for file in try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil) {
            let bytes = try Data(contentsOf: file)
            for canary in canaries { #expect(bytes.range(of: Data(canary.utf8)) == nil) }
        }
    }
    try await vault.apply(saving: [], deleting: [snippet.id, history.id, settings.id], access: access)
    #expect(try await vault.records(access: access).isEmpty)
}

@Test func abandonedSQLiteTransactionDoesNotReplaceCommittedRecords() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let provider = EphemeralKeyProvider(key: key)
    let vault = try VaultSession.create(at: fixture.url, key: key)
    let access = try await vault.unlock(using: provider)
    let original = try syntheticRecord()
    try await vault.apply(saving: [original], access: access)
    var connection: OpaquePointer?
    #expect(sqlite3_open(fixture.url.path, &connection) == SQLITE_OK)
    let interrupted = "BEGIN IMMEDIATE; UPDATE records SET payload=zeroblob(length(payload)) WHERE id='\(original.id.uuidString)'"
    let result = sqlite3_exec(connection, interrupted, nil, nil, nil)
    let closed = sqlite3_close(connection) // No COMMIT: discard the unfinished transaction.
    #expect(result == SQLITE_OK)
    #expect(closed == SQLITE_OK)
    let reopened = try VaultSession.open(at: fixture.url)
    let reopenedAccess = try await reopened.unlock(using: provider)
    #expect(try await reopened.records(access: reopenedAccess) == [original])
}

@Test func cancelledMutationCannotDeleteCommittedData() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: fixture.url, key: key)
    let access = try await vault.unlock(using: EphemeralKeyProvider(key: key))
    let original = try syntheticRecord()
    try await vault.apply(saving: [original], access: access)
    let cancelled = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        try await vault.apply(saving: [], deleting: [original.id], access: access)
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(try await vault.records(access: access) == [original])
}

@Test func aggregatePayloadBudgetRollsBackIndividuallySmallRecords() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: fixture.url, key: key, payloadBudget: 1_000)
    let access = try await vault.unlock(using: EphemeralKeyProvider(key: key))
    let original = try syntheticRecord()
    try await vault.apply(saving: [original], access: access)
    let additional = try (0..<10).map { _ in try syntheticRecord() }
    await #expect(throws: VaultError.payloadBudgetExceeded) {
        try await vault.apply(saving: additional, access: access)
    }
    #expect(try await vault.records(access: access) == [original])
}

@Test func transactionalEditPreservesCanonicallyEquivalentButDistinctUTF8() async throws {
    let fixture = try VaultFixture()
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: fixture.url, key: key)
    let access = try await vault.unlock(using: EphemeralKeyProvider(key: key))
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let original = try Snippet(name: "Synthetic Unicode", body: "é", createdAt: date, updatedAt: date)
    try await vault.apply(saving: [VaultRecord(.snippet(original))], access: access)
    let replacement = try Snippet(id: original.id, name: original.name, body: "e\u{301}", createdAt: date, updatedAt: date)
    _ = try await vault.update(access: access) { _, _ in [try VaultRecord(.snippet(replacement))] }
    guard case .snippet(let stored) = try await vault.record(id: original.id, access: access)?.payload else { Issue.record("Missing snippet"); return }
    #expect(Array(stored.body.utf8) == Array(replacement.body.utf8))
    #expect(Array(stored.body.utf8) != Array(original.body.utf8))
}
