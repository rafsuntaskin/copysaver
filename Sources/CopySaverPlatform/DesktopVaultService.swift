import CopySaverDomain
import CopySaverVault
import Foundation

public protocol DesktopVaultAccess: Sendable {
    func prepare() async throws -> Bool
    func create() async throws
    func unlock() async throws -> [VaultRecord]
    func lock() async
    func save(_ record: VaultRecord) async throws -> [VaultRecord]
    func delete(_ id: UUID) async throws -> [VaultRecord]
    func authenticateSensitiveAccess() async throws
}

public actor DesktopVaultService: DesktopVaultAccess {
    private let url: URL
    private let keys: KeychainVaultKeyProvider
    private var vault: VaultSession?
    private var access: VaultAccess?
    private var generation = UUID()
    private var creating = false

    public init(url: URL, keys: KeychainVaultKeyProvider) {
        self.url = url
        self.keys = keys
    }

    public func prepare() throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        vault = try VaultSession.open(at: url)
        access = nil
        return true
    }

    public func create() async throws {
        guard !creating else { throw VaultError.alreadyExists }
        guard !FileManager.default.fileExists(atPath: url.path) else { throw VaultError.alreadyExists }
        creating = true
        defer { creating = false }
        let request = generation
        let vaultID = UUID()
        let key = try await keys.createKey(for: vaultID)
        do {
            guard generation == request, !Task.isCancelled else { throw VaultError.staleSession }
            vault = try VaultSession.create(at: url, vaultID: vaultID, key: key)
            access = nil
        } catch {
            // Only remove the just-created key when no database was created.
            // If a partial file exists, retain both for explicit diagnosis/recovery.
            if !FileManager.default.fileExists(atPath: url.path) { try? await keys.deleteKey(for: vaultID) }
            throw error
        }
    }

    public func unlock() async throws -> [VaultRecord] {
        guard let vault else { throw VaultError.notFound }
        let request = generation
        let granted = try await vault.unlock(using: keys)
        guard generation == request else { throw VaultError.staleSession }
        access = granted
        let records = try await vault.records(access: granted)
        guard generation == request else { throw VaultError.staleSession }
        return records
    }

    public func lock() async {
        generation = UUID()
        access = nil
        await vault?.lock()
    }

    public func save(_ record: VaultRecord) async throws -> [VaultRecord] {
        guard let vault, let access else { throw VaultError.locked }
        let request = generation
        try await vault.apply(saving: [record], access: access)
        let records = try await vault.records(access: access)
        guard generation == request else { throw VaultError.staleSession }
        return records
    }

    public func delete(_ id: UUID) async throws -> [VaultRecord] {
        guard let vault, let access else { throw VaultError.locked }
        let request = generation
        try await vault.apply(saving: [], deleting: [id], access: access)
        let records = try await vault.records(access: access)
        guard generation == request else { throw VaultError.staleSession }
        return records
    }

    public func authenticateSensitiveAccess() async throws {
        guard let vault, access != nil else { throw VaultError.locked }
        let request = generation
        try await keys.authenticateSensitiveAccess(for: vault.vaultID)
        guard generation == request else { throw VaultError.staleSession }
    }
}
