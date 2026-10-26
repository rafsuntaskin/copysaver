import CopySaverDomain
import CryptoKit
import Foundation

/// The native adapter must enforce authenticated, app-scoped Keychain access.
/// Test providers use ephemeral keys; this package has no file-key fallback.
public protocol VaultKeyProvider: Sendable {
    func loadKey(for vaultID: UUID) async throws -> SymmetricKey
}

public struct VaultAccess: Equatable, Sendable {
    fileprivate let token: UUID
}

public enum VaultStatus: Equatable, Sendable {
    case locked, unlocking, unlocked
}

/// All commits and lock transitions are synchronous actor-isolated critical sections.
public actor VaultSession {
    public let vaultID: UUID
    private let store: SQLiteRecordStore
    private var generation = UUID()
    private var key: SymmetricKey?
    private var access: VaultAccess?
    public private(set) var status: VaultStatus = .locked

    private init(store: sending SQLiteRecordStore) {
        self.store = store
        self.vaultID = store.header.vaultID
    }

    /// Creation uses a caller-provided ephemeral key, never persists it, and returns locked.
    /// Production callers must create/store this key through the protected native adapter.
    public static func create(
        at url: URL, vaultID: UUID = UUID(), key: SymmetricKey,
        payloadBudget: Int = RecordLimits.maximumPayloadBytes
    ) throws -> VaultSession {
        let verification = VaultVerification(vaultID: vaultID)
        let envelope = try RecordCipher.seal(VaultRecord(.verification(verification)), vaultID: vaultID, key: key)
        let header = VaultHeader(vaultID: vaultID, verificationID: verification.id)
        return try VaultSession(store: SQLiteRecordStore.create(at: url, header: header, verification: envelope, payloadBudget: payloadBudget))
    }

    public static func open(at url: URL, payloadBudget: Int = RecordLimits.maximumPayloadBytes) throws -> VaultSession {
        try VaultSession(store: SQLiteRecordStore.open(at: url, payloadBudget: payloadBudget))
    }

    public func unlock(using provider: any VaultKeyProvider) async throws -> VaultAccess {
        guard status != .unlocked else { throw VaultError.alreadyUnlocked }
        generation = UUID()
        let requestGeneration = generation
        status = .unlocking
        do {
            let loadedKey = try await provider.loadKey(for: vaultID)
            try Task.checkCancellation()
            guard generation == requestGeneration else { throw VaultError.staleSession }
            let envelopes = try store.allRecords()
            var verificationFound = false
            for envelope in envelopes {
                try Task.checkCancellation()
                let record = try RecordCipher.open(envelope, vaultID: vaultID, key: loadedKey)
                if case .verification(let verification) = record.payload {
                    guard envelope.id == store.header.verificationID, verification.vaultID == vaultID,
                          !verificationFound else { throw VaultError.corruptDatabase }
                    verificationFound = true
                } else if envelope.id == store.header.verificationID {
                    throw VaultError.corruptDatabase
                }
            }
            guard verificationFound else { throw VaultError.corruptDatabase }
            let session = VaultAccess(token: UUID())
            key = loadedKey
            access = session
            status = .unlocked
            return session
        } catch {
            if generation == requestGeneration {
                key = nil
                access = nil
                status = .locked
            }
            throw error
        }
    }

    public func lock() {
        generation = UUID()
        access = nil
        key = nil
        status = .locked
    }

    public func records(access session: VaultAccess) throws -> [VaultRecord] {
        let key = try authorizedKey(for: session)
        do {
            return try store.allRecords().compactMap { envelope in
                try Task.checkCancellation()
                let record = try RecordCipher.open(envelope, vaultID: vaultID, key: key)
                if case .verification = record.payload { return nil }
                return record
            }
        } catch {
            lockOnIntegrityFailure(error)
            throw error
        }
    }

    public func record(id: UUID, access session: VaultAccess) throws -> VaultRecord? {
        let key = try authorizedKey(for: session)
        guard id != store.header.verificationID else { throw VaultError.reservedRecord }
        do {
            guard let envelope = try store.record(id: id) else { return nil }
            return try RecordCipher.open(envelope, vaultID: vaultID, key: key)
        } catch {
            lockOnIntegrityFailure(error)
            throw error
        }
    }

    public func apply(saving records: [VaultRecord], deleting ids: Set<UUID> = [], access session: VaultAccess) throws {
        let key = try authorizedKey(for: session)
        guard !ids.contains(store.header.verificationID) else { throw VaultError.reservedRecord }
        let envelopes = try records.map { record in
            try Task.checkCancellation()
            guard record.id != store.header.verificationID else { throw VaultError.reservedRecord }
            if case .verification = record.payload { throw VaultError.reservedRecord }
            return try RecordCipher.seal(record, vaultID: vaultID, key: key)
        }
        try Task.checkCancellation()
        do {
            try store.apply(saving: envelopes, deleting: ids)
        } catch {
            lockOnIntegrityFailure(error)
            throw error
        }
    }

    public func checkpoint() throws { try store.checkpoint() }

    /// Read/plan/commit executes in one actor turn, so concurrent captures and edits
    /// cannot replace each other's records or cross a completed lock transition.
    public func update(access session: VaultAccess, transform: @Sendable ([VaultRecord], Int) throws -> [VaultRecord]) throws -> [VaultRecord] {
        let current = try records(access: session)
        guard let verification = try store.record(id: store.header.verificationID) else { throw VaultError.corruptDatabase }
        let next = try transform(current, store.payloadBudget - verification.sealedData.count)
        guard Set(next.map(\.id)).count == next.count else { throw VaultError.invalidRecord }
        let previous = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let removed = Set(current.map(\.id)).subtracting(next.map(\.id))
        // Swift String equality treats canonically equivalent Unicode as equal;
        // the persisted payload must preserve exact UTF-8 even on an in-place edit.
        let changed = try next.filter { record in
            guard let old = previous[record.id] else { return true }
            return try RecordCodec.encode(old) != RecordCodec.encode(record)
        }
        try apply(saving: changed, deleting: removed, access: session)
        return next
    }

    private func lockOnIntegrityFailure(_ error: any Error) {
        guard let error = error as? VaultError else { return }
        switch error {
        case .authenticationFailed, .invalidRecord, .unsupportedEnvelopeVersion, .corruptDatabase:
            lock()
        default:
            break
        }
    }

    private func authorizedKey(for session: VaultAccess) throws -> SymmetricKey {
        guard let key, let access, status == .unlocked else { throw VaultError.locked }
        guard access == session else { throw VaultError.staleSession }
        return key
    }
}
