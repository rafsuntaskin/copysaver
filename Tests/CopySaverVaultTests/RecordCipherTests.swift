import CopySaverDomain
@testable import CopySaverVault
import CryptoKit
import Foundation
import Testing

func syntheticRecord() throws -> VaultRecord {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    return try VaultRecord(.snippet(Snippet(name: "Synthetic name", body: "Synthetic body 🦉\n", category: "Test category", isSensitive: true, createdAt: date, updatedAt: date)))
}

@Test func encryptedRecordsRoundTripWithoutPlaintext() throws {
    let key = SymmetricKey(size: .bits256)
    let vaultID = UUID()
    let record = try syntheticRecord()
    let envelope = try RecordCipher.seal(record, vaultID: vaultID, key: key)
    #expect(try RecordCipher.open(envelope, vaultID: vaultID, key: key) == record)
    #expect(envelope.sealedData.range(of: Data("Synthetic body".utf8)) == nil)
    #expect(envelope.sealedData.range(of: Data("Synthetic name".utf8)) == nil)
}

@Test func sameRecordAlwaysGetsFreshNonceAndCiphertext() throws {
    let key = SymmetricKey(size: .bits256)
    let vaultID = UUID()
    let record = try syntheticRecord()
    let sealed = try (0..<50).map { _ in try RecordCipher.seal(record, vaultID: vaultID, key: key).sealedData }
    #expect(Set(sealed.map { Data($0.prefix(12)) }).count == 50)
    #expect(Set(sealed.map { Data($0.dropFirst(12).dropLast(16)) }).count == 50)
    #expect(Set(sealed).count == 50)
}

@Test func wrongKeyAndChangedIdentityAreRejected() throws {
    let key = SymmetricKey(size: .bits256)
    let vaultID = UUID()
    let envelope = try RecordCipher.seal(syntheticRecord(), vaultID: vaultID, key: key)
    #expect(throws: VaultError.authenticationFailed) {
        try RecordCipher.open(envelope, vaultID: vaultID, key: SymmetricKey(size: .bits256))
    }
    #expect(throws: VaultError.authenticationFailed) { try RecordCipher.open(envelope, vaultID: UUID(), key: key) }
    #expect(throws: VaultError.authenticationFailed) {
        try RecordCipher.open(EncryptedRecord(id: UUID(), version: 1, sealedData: envelope.sealedData), vaultID: vaultID, key: key)
    }
    #expect(throws: VaultError.unsupportedEnvelopeVersion) {
        try RecordCipher.open(EncryptedRecord(id: envelope.id, version: 2, sealedData: envelope.sealedData), vaultID: vaultID, key: key)
    }
}

@Test(arguments: [0, 12, -1])
func nonceCiphertextAndTagTamperingAreRejected(offset: Int) throws {
    let key = SymmetricKey(size: .bits256)
    let vaultID = UUID()
    let envelope = try RecordCipher.seal(syntheticRecord(), vaultID: vaultID, key: key)
    var bytes = envelope.sealedData
    let index = offset == -1 ? bytes.count - 1 : offset
    bytes[index] ^= 0xff
    #expect(throws: VaultError.authenticationFailed) {
        try RecordCipher.open(EncryptedRecord(id: envelope.id, version: 1, sealedData: bytes), vaultID: vaultID, key: key)
    }
}

@Test func malformedEnvelopesAndIncorrectKeySizesFailClosed() throws {
    let record = try syntheticRecord()
    #expect(throws: VaultError.invalidKey) { try RecordCipher.seal(record, vaultID: UUID(), key: SymmetricKey(size: .bits128)) }
    #expect(throws: VaultError.authenticationFailed) {
        try RecordCipher.open(EncryptedRecord(id: record.id, version: 1, sealedData: Data()), vaultID: UUID(), key: SymmetricKey(size: .bits256))
    }
}

@Test func envelopeFormatMatchesIndependentOpenSSLFixture() throws {
    struct Fixture: Decodable {
        let vaultID: UUID
        let recordID: UUID
        let envelopeVersion: Int
        let keyHex: String
        let authenticatedData: String
        let plaintext: String
        let combinedBase64: String
    }
    let url = try #require(Bundle.module.url(forResource: "envelope-v1", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    let keyBytes = try stride(from: 0, to: fixture.keyHex.count, by: 2).map { offset throws -> UInt8 in
        let start = fixture.keyHex.index(fixture.keyHex.startIndex, offsetBy: offset)
        let end = fixture.keyHex.index(start, offsetBy: 2)
        return try #require(UInt8(fixture.keyHex[start..<end], radix: 16))
    }
    let envelope = EncryptedRecord(id: fixture.recordID, version: fixture.envelopeVersion, sealedData: try #require(Data(base64Encoded: fixture.combinedBase64)))
    #expect(RecordCipher.authenticatedData(vaultID: fixture.vaultID, recordID: fixture.recordID, version: 1) == Data(fixture.authenticatedData.utf8))
    let record = try RecordCipher.open(envelope, vaultID: fixture.vaultID, key: SymmetricKey(data: keyBytes))
    #expect(record == (try RecordCodec.decode(Data(fixture.plaintext.utf8))))
    guard case .snippet(let snippet) = record.payload else { Issue.record("Wrong fixture kind"); return }
    #expect(snippet.body == "Synthetic fixture\n")
}
