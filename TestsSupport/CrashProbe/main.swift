// Test-only process fixture. The random synthetic key arrives through an anonymous
// pipe, never through a file, argument, environment variable, or Keychain fallback.
import CopySaverDomain
import CopySaverVault
import CryptoKit
import Foundation
import SQLite3

@main struct CrashProbe {
    static func main() async throws {
        guard CommandLine.arguments.count == 2,
              let bytes = try FileHandle.standardInput.read(upToCount: 32), bytes.count == 32 else { return }
        let key = SymmetricKey(data: bytes)
        let vault = try VaultSession.create(at: URL(filePath: CommandLine.arguments[1]), key: key)
        let access = try await vault.unlock(using: ProbeKeys(key: key))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let record = try VaultRecord(.snippet(Snippet(name: "Synthetic crash fixture", body: "Synthetic committed crash canary", createdAt: date, updatedAt: date)))
        try await vault.apply(saving: [record], access: access)
        // Leave a second encrypted update in an uncommitted SQLite transaction.
        // Killing the process must recover the committed row, not this update.
        let changed = try VaultRecord(.snippet(Snippet(id: record.id, name: "Synthetic crash fixture", body: "Synthetic uncommitted crash canary", createdAt: date, updatedAt: date)))
        let vaultID = await vault.vaultID
        let envelope = try RecordCipher.seal(changed, vaultID: vaultID, key: key)
        var database: OpaquePointer?
        guard sqlite3_open(CommandLine.arguments[1], &database) == SQLITE_OK else { throw ProbeFailure.storage }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw ProbeFailure.storage }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "UPDATE records SET payload=?1 WHERE id=?2", -1, &statement, nil) == SQLITE_OK else { throw ProbeFailure.storage }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bound = envelope.sealedData.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), transient) }
        guard bound == SQLITE_OK, sqlite3_bind_text(statement, 2, record.id.uuidString, -1, transient) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else { throw ProbeFailure.storage }
        try FileHandle.standardOutput.write(contentsOf: Data("committed\n".utf8))
        // The owning test kills this process while SQLite and its WAL remain open.
        try await Task.sleep(for: .seconds(60))
        await vault.lock()
    }
}
private enum ProbeFailure: Error { case storage }
private struct ProbeKeys: VaultKeyProvider {
    let key: SymmetricKey
    func loadKey(for vaultID: UUID) async throws -> SymmetricKey { key }
}
