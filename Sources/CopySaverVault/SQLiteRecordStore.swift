import CopySaverDomain
import Darwin
import Foundation
import SQLite3

struct VaultHeader: Equatable, Sendable {
    let vaultID: UUID
    let verificationID: UUID
}

/// Owned exclusively by VaultSession's actor. SQLite never receives plaintext records.
final class SQLiteRecordStore {
    static let schemaVersion = 1
    private var database: OpaquePointer?
    let payloadBudget: Int
    private(set) var header: VaultHeader

    private var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }

    static func create(at url: URL, header: VaultHeader, verification: EncryptedRecord, payloadBudget: Int) throws -> SQLiteRecordStore {
        try SQLiteRecordStore(at: url, newHeader: header, verification: verification, payloadBudget: payloadBudget)
    }

    static func open(at url: URL, payloadBudget: Int) throws -> SQLiteRecordStore {
        try SQLiteRecordStore(at: url, newHeader: nil, verification: nil, payloadBudget: payloadBudget)
    }

    private init(at url: URL, newHeader: VaultHeader?, verification: EncryptedRecord?, payloadBudget: Int) throws {
        guard (1...RecordLimits.maximumPayloadBytes).contains(payloadBudget) else {
            throw VaultError.payloadBudgetExceeded
        }
        self.payloadBudget = payloadBudget
        // Assigned before helpers can access self; replaced from the database on open.
        self.header = newHeader ?? VaultHeader(vaultID: UUID(), verificationID: UUID())

        if newHeader != nil {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch { throw VaultError.storageFailure }
            let descriptor = Darwin.open(url.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { throw errno == EEXIST ? VaultError.alreadyExists : .storageFailure }
            Darwin.close(descriptor)
        } else if !FileManager.default.fileExists(atPath: url.path) {
            throw VaultError.notFound
        }

        var connection: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil)
        guard result == SQLITE_OK else {
            sqlite3_close(connection)
            throw VaultError.storageFailure
        }
        database = connection
        do {
            sqlite3_busy_timeout(database, 1_000)
            if newHeader == nil {
                let version = try integer("PRAGMA user_version")
                guard version == Self.schemaVersion else {
                    throw version > Self.schemaVersion ? VaultError.unsupportedDatabaseVersion : .corruptDatabase
                }
            }
            for sql in [
                "PRAGMA trusted_schema=OFF", "PRAGMA temp_store=MEMORY",
                "PRAGMA journal_mode=WAL", "PRAGMA synchronous=FULL",
                "PRAGMA wal_autocheckpoint=256", "PRAGMA journal_size_limit=4194304",
            ] { try execute(sql) }

            if let newHeader, let verification {
                try transaction {
                    try execute("CREATE TABLE metadata (singleton INTEGER PRIMARY KEY CHECK(singleton=1), vault_id TEXT NOT NULL, verification_id TEXT NOT NULL)")
                    try execute("CREATE TABLE records (id TEXT PRIMARY KEY NOT NULL, version INTEGER NOT NULL CHECK(version>0), payload BLOB NOT NULL)")
                    try statement("INSERT INTO metadata VALUES (1, ?1, ?2)") { query in
                        try bind(newHeader.vaultID.uuidString, to: 1, in: query)
                        try bind(newHeader.verificationID.uuidString, to: 2, in: query)
                        try stepDone(query)
                    }
                    try write(verification)
                    try checkBudget()
                    try execute("PRAGMA user_version=1")
                }
            } else {
                // Validate the persisted header before exposing the store.
                let loaded = try loadHeader()
                self.header = loaded
                try checkBudget()
            }
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    func allRecords() throws -> [EncryptedRecord] {
        try statement("SELECT id, version, payload FROM records ORDER BY id") { query in
            var records: [EncryptedRecord] = []
            while true {
                let result = sqlite3_step(query)
                if result == SQLITE_DONE { return records }
                guard result == SQLITE_ROW else { throw failure(result) }
                records.append(try envelope(from: query))
            }
        }
    }

    func record(id: UUID) throws -> EncryptedRecord? {
        try statement("SELECT id, version, payload FROM records WHERE id=?1") { query in
            try bind(id.uuidString, to: 1, in: query)
            let result = sqlite3_step(query)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw failure(result) }
            return try envelope(from: query)
        }
    }

    func apply(saving records: [EncryptedRecord], deleting ids: Set<UUID>) throws {
        try transaction {
            for id in ids {
                try statement("DELETE FROM records WHERE id=?1") { query in
                    try bind(id.uuidString, to: 1, in: query)
                    try stepDone(query)
                }
            }
            for record in records { try write(record) }
            try checkBudget()
        }
    }

    func checkpoint() throws {
        let result = sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        guard result == SQLITE_OK else { throw failure(result) }
    }

    private func loadHeader() throws -> VaultHeader {
        try statement("SELECT vault_id, verification_id FROM metadata WHERE singleton=1") { query in
            guard sqlite3_step(query) == SQLITE_ROW,
                  let rawVault = sqlite3_column_text(query, 0),
                  let rawVerification = sqlite3_column_text(query, 1),
                  let vaultID = UUID(uuidString: String(cString: rawVault)),
                  let verificationID = UUID(uuidString: String(cString: rawVerification))
            else { throw VaultError.corruptDatabase }
            return VaultHeader(vaultID: vaultID, verificationID: verificationID)
        }
    }

    private func envelope(from query: OpaquePointer) throws -> EncryptedRecord {
        guard sqlite3_column_type(query, 0) == SQLITE_TEXT,
              sqlite3_column_type(query, 1) == SQLITE_INTEGER,
              sqlite3_column_type(query, 2) == SQLITE_BLOB,
              let rawID = sqlite3_column_text(query, 0),
              let id = UUID(uuidString: String(cString: rawID))
        else { throw VaultError.corruptDatabase }
        let size = Int(sqlite3_column_bytes(query, 2))
        guard size >= 28, size <= payloadBudget, let bytes = sqlite3_column_blob(query, 2) else {
            throw VaultError.corruptDatabase
        }
        return EncryptedRecord(id: id, version: Int(sqlite3_column_int64(query, 1)), sealedData: Data(bytes: bytes, count: size))
    }

    private func write(_ envelope: EncryptedRecord) throws {
        guard envelope.sealedData.count <= payloadBudget else { throw VaultError.payloadBudgetExceeded }
        try statement("INSERT INTO records (id, version, payload) VALUES (?1, ?2, ?3) ON CONFLICT(id) DO UPDATE SET version=excluded.version, payload=excluded.payload") { query in
            try bind(envelope.id.uuidString, to: 1, in: query)
            guard sqlite3_bind_int64(query, 2, Int64(envelope.version)) == SQLITE_OK else { throw VaultError.storageFailure }
            let result = envelope.sealedData.withUnsafeBytes { bytes in
                sqlite3_bind_blob(query, 3, bytes.baseAddress, Int32(bytes.count), transient)
            }
            guard result == SQLITE_OK else { throw failure(result) }
            try stepDone(query)
        }
    }

    private func checkBudget() throws {
        guard try integer("SELECT COALESCE(SUM(length(payload)), 0) FROM records") <= payloadBudget else {
            throw VaultError.payloadBudgetExceeded
        }
    }

    private func integer(_ sql: String) throws -> Int {
        try statement(sql) { query in
            let result = sqlite3_step(query)
            guard result == SQLITE_ROW else { throw failure(result) }
            return Int(sqlite3_column_int64(query, 0))
        }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw failure(result) }
    }

    private func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var query: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &query, nil)
        guard result == SQLITE_OK, let query else { throw failure(result) }
        defer { sqlite3_finalize(query) }
        return try body(query)
    }

    private func bind(_ value: String, to index: Int32, in query: OpaquePointer) throws {
        let result = sqlite3_bind_text(query, index, value, -1, transient)
        guard result == SQLITE_OK else { throw failure(result) }
    }

    private func stepDone(_ query: OpaquePointer) throws {
        let result = sqlite3_step(query)
        guard result == SQLITE_DONE else { throw failure(result) }
    }

    private func failure(_ result: Int32) -> VaultError {
        [SQLITE_CORRUPT, SQLITE_NOTADB].contains(result & 0xff) ? .corruptDatabase : .storageFailure
    }
}
