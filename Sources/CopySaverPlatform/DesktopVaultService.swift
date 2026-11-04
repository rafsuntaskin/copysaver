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
    func capture(_ sample: ClipboardSample) async throws -> [VaultRecord]
    func updateSettings(_ settings: VaultSettings, confirmed: Bool) async throws -> [VaultRecord]
    func cleanup(now: Date) async throws -> [VaultRecord]
    func clearHistory() async throws -> [VaultRecord]
    func markCopied(_ id: UUID, date: Date) async throws -> [VaultRecord]
    func reset() async throws
    func requestAutomaticAccess() async throws
}

public extension DesktopVaultAccess {
    func requestAutomaticAccess() async throws {}
    func capture(_ sample: ClipboardSample) async throws -> [VaultRecord] { throw VaultError.storageFailure }
    func updateSettings(_ settings: VaultSettings, confirmed: Bool) async throws -> [VaultRecord] { throw VaultError.storageFailure }
    func cleanup(now: Date) async throws -> [VaultRecord] { throw VaultError.storageFailure }
    func clearHistory() async throws -> [VaultRecord] { throw VaultError.storageFailure }
    func markCopied(_ id: UUID, date: Date) async throws -> [VaultRecord] { throw VaultError.storageFailure }
    func reset() async throws { throw VaultError.storageFailure }
}

public actor DesktopVaultService: DesktopVaultAccess {
    private let url: URL
    private let keys: KeychainVaultKeyProvider
    private var vault: VaultSession?
    private var access: VaultAccess?
    private var generation = UUID()
    private var creating = false
    private var resetting = false

    public init(url: URL, keys: KeychainVaultKeyProvider) {
        self.url = url
        self.keys = keys
    }

    public func prepare() throws -> Bool {
        guard !resetting else { throw VaultError.staleSession }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        vault = try VaultSession.open(at: url)
        access = nil
        return true
    }

    public func create() async throws {
        guard !creating, !resetting else { throw VaultError.alreadyExists }
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
        guard !resetting else { throw VaultError.staleSession }
        guard let vault else { throw VaultError.notFound }
        let request = generation
        let granted = try await vault.unlock(using: keys)
        guard generation == request else { throw VaultError.staleSession }
        access = granted
        let newVaultSettings = try VaultSettings(
            captureEnabled: keys.protection == .automatic,
            idleLockTimeout: keys.protection == .automatic ? .systemLockOnly : .fifteenMinutes
        )
        do {
            let records = try await vault.update(access: granted) { records, budget in
                let hasSettings = records.contains { if case .settings = $0.payload { true } else { false } }
                let settings = hasSettings ? try HistoryPolicy.settings(in: records) : newVaultSettings
                var next = try HistoryPolicy.retain(records, settings: settings, now: Date())
                if !hasSettings { next.append(try VaultRecord(.settings(settings))) }
                return try HistoryPolicy.fit(next, settings: settings, budget: budget)
            }
            guard generation == request else { throw VaultError.staleSession }
            return records
        } catch {
            if generation == request { access = nil; await vault.lock() }
            throw error
        }
    }

    public func lock() async {
        generation = UUID()
        access = nil
        await vault?.lock()
    }

    public func save(_ record: VaultRecord) async throws -> [VaultRecord] {
        guard !resetting, let vault, let access else { throw VaultError.locked }
        let request = generation
        let records = try await vault.update(access: access) { current, budget in
            var next = current.filter { $0.id != record.id }
            next.append(record)
            return try HistoryPolicy.fit(next, settings: HistoryPolicy.settings(in: next), budget: budget, protecting: record.id)
        }
        guard generation == request else { throw VaultError.staleSession }
        return records
    }

    public func delete(_ id: UUID) async throws -> [VaultRecord] {
        guard !resetting, let vault, let access else { throw VaultError.locked }
        let request = generation
        try await vault.apply(saving: [], deleting: [id], access: access)
        let records = try await vault.records(access: access)
        guard generation == request else { throw VaultError.staleSession }
        return records
    }

    public func authenticateSensitiveAccess() async throws {
        guard let vault, access != nil else { throw VaultError.locked }
        guard keys.protection == .userPresence else { try Task.checkCancellation(); return }
        let request = generation
        try await keys.authenticateSensitiveAccess(for: vault.vaultID)
        guard generation == request else { throw VaultError.staleSession }
    }

    public func requestAutomaticAccess() async throws {
        guard let vault else { return }
        let request = generation
        try await keys.requestAutomaticAccess(for: vault.vaultID)
        guard generation == request else { throw VaultError.staleSession }
    }

    public func capture(_ sample: ClipboardSample) async throws -> [VaultRecord] {
        try await mutate { records, budget in
            let settings = try HistoryPolicy.settings(in: records)
            guard settings.captureEnabled, !settings.manuallyPaused else { throw VaultError.staleSession }
            return try HistoryPolicy.capture(sample, in: records, budget: budget)
        }
    }

    public func cleanup(now: Date) async throws -> [VaultRecord] {
        try await mutate { records, budget in
            let settings = try HistoryPolicy.settings(in: records)
            return try HistoryPolicy.fit(HistoryPolicy.retain(records, settings: settings, now: now), settings: settings, budget: budget)
        }
    }

    public func updateSettings(_ settings: VaultSettings, confirmed: Bool) async throws -> [VaultRecord] {
        try await mutate { records, budget in
            var next = records.filter { if case .settings = $0.payload { return false }; return true }
            next.append(try VaultRecord(.settings(settings)))
            let retained = try HistoryPolicy.fit(HistoryPolicy.retain(next, settings: settings, now: Date()), settings: settings, budget: budget)
            if retained.count < next.count && !confirmed { throw HistoryFailure.confirmationRequired }
            return retained
        }
    }

    public func clearHistory() async throws -> [VaultRecord] {
        try await mutate { records, _ in records.filter { if case .history = $0.payload { return false }; return true } }
    }

    public func markCopied(_ id: UUID, date: Date) async throws -> [VaultRecord] {
        try await mutate { records, budget in
            let next = try records.map { $0.id == id ? try $0.markingCopied(at: date) : $0 }
            return try HistoryPolicy.fit(next, settings: HistoryPolicy.settings(in: records), budget: budget, protecting: id)
        }
    }

    public func reset() async throws {
        guard !creating, !resetting else { throw VaultError.staleSession }
        resetting = true
        defer { resetting = false }
        if vault == nil { vault = try VaultSession.open(at: url) }
        guard let vault else { throw VaultError.notFound }
        let request = generation
        do { try await keys.authenticateSensitiveAccess(for: vault.vaultID) }
        catch KeychainFailure.missingKey { /* Explicitly confirmed missing-key recovery. */ }
        guard generation == request, !Task.isCancelled else { throw VaultError.staleSession }
        access = nil
        try await vault.close()
        guard generation == request, !Task.isCancelled else { throw VaultError.staleSession }
        for suffix in ["-wal", "-shm", ""] {
            let file = URL(filePath: url.path + suffix)
            if FileManager.default.fileExists(atPath: file.path) {
                do { try FileManager.default.removeItem(at: file) } catch { throw VaultError.storageFailure }
            }
        }
        try await keys.deleteKey(for: vault.vaultID)
        self.vault = nil
        generation = UUID()
    }

    private func mutate(_ transform: @escaping @Sendable ([VaultRecord], Int) throws -> [VaultRecord]) async throws -> [VaultRecord] {
        guard !resetting, let vault, let access else { throw VaultError.locked }
        let request = generation
        let records = try await vault.update(access: access, transform: transform)
        guard generation == request else { throw VaultError.staleSession }
        return records
    }
}
