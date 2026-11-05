import CopySaverDomain
import CopySaverVault
@testable import CopySaverPlatform
import CryptoKit
import Foundation
import LocalAuthentication
import Security
import Testing

private actor MemoryKeychain: KeychainTransport {
    var values: [String: Data] = [:]
    var reads = 0
    var unavailable = false
    var adds = 0
    var readCancelled = false
    var keyCount: Int { values.count }
    func removeAll() { values.removeAll() }
    func cancelReads() { readCancelled = true }
    func add(_ key: Data, identity: KeychainIdentity) throws {
        let slot = identity.service + identity.account
        guard values[slot] == nil else { throw KeychainFailure.duplicateKey }
        values[slot] = key
        adds += 1
    }
    func read(identity: KeychainIdentity, reason: String) throws -> Data {
        reads += 1
        if readCancelled { throw KeychainFailure.cancelled }
        if unavailable { throw KeychainFailure.unavailable }
        guard let data = values[identity.service + identity.account] else { throw KeychainFailure.missingKey }
        return data
    }
    func delete(identity: KeychainIdentity) { values[identity.service + identity.account] = nil }
    func replace(_ data: Data, identity: KeychainIdentity) { values[identity.service + identity.account] = data }
    func makeUnavailable() { unavailable = true }
}

@Test func automaticKeysAreSeparateAndResetKeyCheckPreservesMissingKeyFailure() async throws {
    let transport = MemoryKeychain()
    let provider = try KeychainVaultKeyProvider(bundleIdentifier: "org.example.CopySaver.community.dev", protection: .automatic, transport: transport)
    let protected = try KeychainVaultKeyProvider(bundleIdentifier: provider.bundleIdentifier, transport: transport)
    let id = UUID()
    let key = try await provider.createKey(for: id)
    let loaded = try await provider.loadKey(for: id)
    #expect(key.withUnsafeBytes { Data($0) } == loaded.withUnsafeBytes { Data($0) })
    await #expect(throws: KeychainFailure.missingKey) { try await protected.loadKey(for: id) }
    try await provider.authenticateSensitiveAccess(for: id)
    await transport.removeAll()
    await #expect(throws: KeychainFailure.missingKey) { try await provider.authenticateSensitiveAccess(for: id) }
}

@Test func loginKeychainQueryDoesNotRequestProvisionedGroupsOrTrustEveryApp() throws {
    let identity = try KeychainIdentity(bundleIdentifier: "org.example.CopySaver.community.dev", vaultID: UUID(), protection: .automatic)
    let add = try LoginKeychainQueries.add(Data(repeating: 2, count: 32), identity: identity)
    #expect(add[kSecUseDataProtectionKeychain as String] as? Bool == false)
    #expect(add[kSecAttrSynchronizable as String] == nil) // File-based items are not iCloud items.
    #expect(add[kSecAttrAccessGroup as String] == nil)
    #expect(add[kSecAttrAccessControl as String] == nil)
    let access = try #require(add[kSecAttrAccess as String]) as! SecAccess
    let acls = SecAccessCopyMatchingACLList(access, kSecACLAuthorizationDecrypt) as! [SecACL]
    #expect(!acls.isEmpty)
    for acl in acls {
        var apps: CFArray?
        var description: CFString?
        var selector = SecKeychainPromptSelector()
        #expect(SecACLCopyContents(acl, &apps, &description, &selector) == errSecSuccess)
        #expect(apps != nil && CFArrayGetCount(apps) == 1)
    }
    let read = LoginKeychainQueries.read(identity, allowInteraction: false)
    #expect(read[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUIFail as String)
    #expect(LoginKeychainQueries.read(identity, allowInteraction: true)[kSecUseAuthenticationUI as String] == nil)
}

@Test func automaticVaultPersistsCaptureChoiceAndMissingKeyNeverReplacesIt() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("copysaver-automatic-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("vault.sqlite")
    let transport = MemoryKeychain()
    let provider = try KeychainVaultKeyProvider(bundleIdentifier: "org.example.CopySaver.community.dev", protection: .automatic, transport: transport)
    let service = DesktopVaultService(url: url, keys: provider)
    try await service.create()
    var records = try await service.unlock()
    let initial = try HistoryPolicy.settings(in: records)
    #expect(initial.captureEnabled && !initial.manuallyPaused)
    let reads = await transport.reads
    try await service.authenticateSensitiveAccess()
    #expect(await transport.reads == reads) // Open community actions do not re-read/authenticate the key.
    records = try await service.capture(ClipboardSample(text: "Synthetic automatic café 日本語", date: Date()))
    let disabled = try initial.updating(captureEnabled: false, manuallyPaused: true)
    _ = try await service.updateSettings(disabled, confirmed: false)
    await service.lock()
    let reopened = DesktopVaultService(url: url, keys: provider)
    #expect(try await reopened.prepare())
    records = try await reopened.unlock()
    #expect(try HistoryPolicy.settings(in: records) == disabled)
    await reopened.lock()
    let files = try ["", "-wal", "-shm"].map { suffix -> Data? in
        let file = URL(filePath: url.path + suffix)
        return FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
    }
    await transport.removeAll()
    await #expect(throws: KeychainFailure.missingKey) { try await reopened.unlock() }
    #expect(await transport.adds == 1)
    for (index, suffix) in ["", "-wal", "-shm"].enumerated() {
        let file = URL(filePath: url.path + suffix)
        let after = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
        #expect(files[index] == after)
        if let after { #expect(after.range(of: Data("Synthetic automatic café 日本語".utf8)) == nil) }
    }
}

@Test(arguments: ["", ".", "CopySaver", "org..example", "org.example bad"])
func invalidKeychainNamespacesAreRejected(value: String) {
    #expect(throws: KeychainFailure.invalidIdentity) {
        try KeychainVaultKeyProvider(bundleIdentifier: value, transport: MemoryKeychain())
    }
}

@Test func desktopServiceDoesNotReadKeysAtStartupAndPersistsOnlyAfterUnlock() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("copysaver-service-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = MemoryKeychain()
    let provider = try KeychainVaultKeyProvider(bundleIdentifier: "org.example.CopySaver.dev", transport: transport)
    let service = DesktopVaultService(url: directory.appendingPathComponent("vault.sqlite"), keys: provider)
    #expect(try await service.prepare() == false)
    #expect(await transport.reads == 0)
    try await service.create()
    #expect(await transport.reads == 0)
    await #expect(throws: VaultError.locked) {
        try await service.save(VaultRecord(.settings(VaultSettings())))
    }
    let initial = try await service.unlock()
    #expect(initial.count == 1)
    guard case .settings(let settings) = initial[0].payload else { Issue.record("Missing settings"); return }
    let record = try VaultRecord(.settings(settings))
    #expect(try await service.save(record) == [record])
    await service.lock()
    await #expect(throws: VaultError.locked) { try await service.delete(record.id) }
    #expect(try await service.unlock() == [record])
    await #expect(throws: VaultError.alreadyExists) { try await service.create() }
    #expect(await transport.adds == 1)
}

@Test func keychainQueryUsesProtectedDeviceOnlyNonSyncingStorage() throws {
    let identity = try KeychainIdentity(bundleIdentifier: "org.example.CopySaver.dev", vaultID: UUID())
    let query = try KeychainQueries.add(Data(repeating: 1, count: 32), identity: identity)
    #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
    #expect(query[kSecAttrAccessControl as String] != nil)
    #expect(query[kSecAttrAccessible as String] == nil) // Accessibility is inside SecAccessControl.
    #expect(query[kSecAttrAccessGroup as String] == nil) // No shared access group.
    #expect(query[kSecAttrService as String] as? String == identity.service)
    #expect(query[kSecValueData as String] as? Data == Data(repeating: 1, count: 32))
    let context = LAContext()
    let read = KeychainQueries.read(identity, context: context)
    #expect(read[kSecUseAuthenticationContext as String] as? LAContext === context)
    #expect(read[kSecReturnData as String] as? Bool == true)
}

@Test func keyProviderCreatesOnceAndNeverOverwritesExistingKey() async throws {
    let transport = MemoryKeychain()
    let provider = try KeychainVaultKeyProvider(bundleIdentifier: "org.example.CopySaver.dev", transport: transport)
    let id = UUID()
    let created = try await provider.createKey(for: id)
    await #expect(throws: KeychainFailure.duplicateKey) { try await provider.createKey(for: id) }
    let loaded = try await provider.loadKey(for: id)
    #expect(created.withUnsafeBytes { Data($0) } == loaded.withUnsafeBytes { Data($0) })
    try await provider.authenticateSensitiveAccess(for: id)
    try await provider.authenticateSensitiveAccess(for: id)
    #expect(await transport.reads == 3) // No app-level authentication/key-read cache.
}

@Test func developmentAndProductionKeyNamespacesAreSeparate() async throws {
    let transport = MemoryKeychain()
    let dev = try KeychainVaultKeyProvider(bundleIdentifier: "org.example.CopySaver.dev", transport: transport)
    let production = try KeychainVaultKeyProvider(bundleIdentifier: "org.example.CopySaver", transport: transport)
    let id = UUID()
    _ = try await dev.createKey(for: id)
    await #expect(throws: KeychainFailure.missingKey) { try await production.loadKey(for: id) }
}

@Test func keyProviderFailsClosedForMissingUnavailableOrInvalidKeys() async throws {
    let transport = MemoryKeychain()
    let provider = try KeychainVaultKeyProvider(bundleIdentifier: "org.example.CopySaver.dev", transport: transport)
    let id = UUID()
    await #expect(throws: KeychainFailure.missingKey) { try await provider.loadKey(for: id) }
    let identity = try KeychainIdentity(bundleIdentifier: provider.bundleIdentifier, vaultID: id)
    await transport.replace(Data(repeating: 0, count: 16), identity: identity)
    await #expect(throws: KeychainFailure.invalidKeyData) { try await provider.loadKey(for: id) }
    await transport.makeUnavailable()
    await #expect(throws: KeychainFailure.unavailable) { try await provider.loadKey(for: id) }
}

@Test func securityStatusMappingDoesNotExposeQueryOrKeyData() {
    #expect(KeychainQueries.failure(errSecMissingEntitlement) == .missingEntitlement)
    #expect(KeychainQueries.failure(errSecUserCanceled) == .cancelled)
    #expect(KeychainQueries.failure(errSecAuthFailed) == .authenticationFailed)
    #expect(KeychainQueries.failure(errSecInteractionNotAllowed) == .interactionRequired)
    #expect(KeychainQueries.failure(errSecItemNotFound) == .missingKey)
}

@Test(arguments: ["copysaver://focus", "copysaver://history", "copysaver://snippets"])
func exactNavigationRoutesAreAccepted(value: String) throws {
    #expect(AppDestination(url: try #require(URL(string: value)), scheme: "copysaver") != nil)
}

@Test(arguments: [
    "copysaver://focus/", "copysaver://focus?", "copysaver://focus#", "copysaver://focus?copy=secret",
    "copysaver://user@focus", "copysaver://focus:123", "copysaver://export", "copysaver://%66ocus",
    "copysaver-dev://focus", "https://focus", "copysaver://FOCUS",
])
func malformedOrForeignNavigationHasNoAction(value: String) throws {
    #expect(AppDestination(url: try #require(URL(string: value)), scheme: "copysaver") == nil)
}

@Test func capturedHistoryDeduplicatesAtomicallyAndPauseSurvivesRelaunch() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("copysaver-history-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("vault.sqlite")
    let provider = try KeychainVaultKeyProvider(bundleIdentifier: "org.example.CopySaver.dev", transport: MemoryKeychain())
    let service = DesktopVaultService(url: url, keys: provider)
    try await service.create()
    var records = try await service.unlock()
    let settings = try HistoryPolicy.settings(in: records).updating(captureEnabled: true)
    records = try await service.updateSettings(settings, confirmed: false)
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<12 {
            group.addTask { _ = try await service.capture(ClipboardSample(text: "Synthetic exact text\n  ", date: Date())) }
        }
        try await group.waitForAll()
    }
    records = try await service.cleanup(now: Date())
    let history = records.compactMap { if case .history(let value) = $0.payload { return value }; return nil }
    #expect(history.count == 1 && history.first?.repeatCount == 12)
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let snippet = try VaultRecord(.snippet(Snippet(name: "Synthetic", body: "Independent", createdAt: timestamp, updatedAt: timestamp)))
    _ = try await service.save(snippet)
    let paused = try settings.updating(manuallyPaused: true)
    _ = try await service.updateSettings(paused, confirmed: false)
    await service.lock()
    let reopened = DesktopVaultService(url: url, keys: provider)
    #expect(try await reopened.prepare())
    records = try await reopened.unlock()
    #expect(try HistoryPolicy.settings(in: records).manuallyPaused)
    await #expect(throws: VaultError.staleSession) { try await reopened.capture(ClipboardSample(text: "Skipped", date: Date())) }
    records = try await reopened.clearHistory()
    #expect(records.contains(snippet))
    #expect(!records.contains { if case .history = $0.payload { return true }; return false })
}

@Test func explicitMissingKeyResetRemovesOnlyTheOwnedVaultAndReturnsToSetup() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("copysaver-reset-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("vault.sqlite")
    let transport = MemoryKeychain()
    let provider = try KeychainVaultKeyProvider(bundleIdentifier: "org.example.CopySaver.dev", transport: transport)
    let service = DesktopVaultService(url: url, keys: provider)
    try await service.create(); _ = try await service.unlock(); await service.lock()
    let neighbor = directory.appendingPathComponent("unrelated.txt")
    try Data("Synthetic unrelated".utf8).write(to: neighbor)
    await transport.removeAll()
    try await service.reset()
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(FileManager.default.fileExists(atPath: neighbor.path))
    #expect(try await service.prepare() == false)
    try await service.create()
    #expect(try await service.unlock().count == 1)
}

@Test func cancelledResetPreservesVaultAndKey() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("copysaver-reset-cancel-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("vault.sqlite")
    let transport = MemoryKeychain()
    let provider = try KeychainVaultKeyProvider(bundleIdentifier: "org.example.CopySaver.dev", transport: transport)
    let service = DesktopVaultService(url: url, keys: provider)
    try await service.create(); _ = try await service.unlock(); await service.lock()
    await transport.cancelReads()
    await #expect(throws: KeychainFailure.cancelled) { try await service.reset() }
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(await transport.keyCount == 1)
}

@Test func lowerRetentionRequiresConfirmationAndNeverRemovesSnippets() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("copysaver-limits-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = try KeychainVaultKeyProvider(bundleIdentifier: "org.example.CopySaver.dev", transport: MemoryKeychain())
    let service = DesktopVaultService(url: directory.appendingPathComponent("vault.sqlite"), keys: provider)
    try await service.create()
    let initial = try await service.unlock()
    let old = Date().addingTimeInterval(-2 * 86_400)
    let history = try VaultRecord(.history(HistoryItem(text: "Synthetic old", firstSeenAt: old, lastSeenAt: old)))
    _ = try await service.save(history)
    let settings = try HistoryPolicy.settings(in: initial).updating(retentionDays: 1)
    await #expect(throws: HistoryFailure.confirmationRequired) { try await service.updateSettings(settings, confirmed: false) }
    let before = try await service.save(history)
    #expect(before.contains { $0.id == history.id })
    let after = try await service.updateSettings(settings, confirmed: true)
    #expect(!after.contains { $0.id == history.id })
}
