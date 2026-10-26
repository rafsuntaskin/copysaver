import CopySaverDomain
import CryptoKit
import Foundation

public enum VaultError: Error, Equatable, Sendable {
    case invalidKey
    case unsupportedEnvelopeVersion
    case authenticationFailed
    case invalidRecord
    case storageFailure
    case alreadyExists
    case notFound
    case unsupportedDatabaseVersion
    case corruptDatabase
    case payloadBudgetExceeded
    case locked
    case alreadyUnlocked
    case staleSession
    case reservedRecord
}

public struct EncryptedRecord: Equatable, Sendable {
    public let id: UUID
    public let version: Int
    public let sealedData: Data

    public init(id: UUID, version: Int, sealedData: Data) {
        self.id = id
        self.version = version
        self.sealedData = sealedData
    }
}

public enum RecordCipher {
    public static let envelopeVersion = 1

    public static func seal(_ record: VaultRecord, vaultID: UUID, key: SymmetricKey) throws -> EncryptedRecord {
        guard key.bitCount == 256 else { throw VaultError.invalidKey }
        let plaintext = try RecordCodec.encode(record)
        let box = try AES.GCM.seal(
            plaintext, using: key,
            authenticating: authenticatedData(vaultID: vaultID, recordID: record.id, version: envelopeVersion)
        )
        guard let combined = box.combined else { throw VaultError.invalidRecord }
        return EncryptedRecord(id: record.id, version: envelopeVersion, sealedData: combined)
    }

    public static func open(_ envelope: EncryptedRecord, vaultID: UUID, key: SymmetricKey) throws -> VaultRecord {
        guard key.bitCount == 256 else { throw VaultError.invalidKey }
        guard envelope.version == envelopeVersion else { throw VaultError.unsupportedEnvelopeVersion }
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: envelope.sealedData)
            plaintext = try AES.GCM.open(
                box, using: key,
                authenticating: authenticatedData(vaultID: vaultID, recordID: envelope.id, version: envelope.version)
            )
        } catch {
            throw VaultError.authenticationFailed
        }
        do {
            let record = try RecordCodec.decode(plaintext)
            guard record.id == envelope.id else { throw VaultError.invalidRecord }
            return record
        } catch {
            throw VaultError.invalidRecord
        }
    }

    /// Fixed ASCII domain and canonical lowercase UUIDs, separated by '|'.
    static func authenticatedData(vaultID: UUID, recordID: UUID, version: Int) -> Data {
        Data("CopySaver.Record|\(vaultID.uuidString.lowercased())|\(recordID.uuidString.lowercased())|\(version)".utf8)
    }
}
