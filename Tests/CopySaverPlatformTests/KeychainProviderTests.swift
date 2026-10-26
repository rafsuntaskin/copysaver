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
    func add(_ key: Data, identity: KeychainIdentity) throws {
        let slot = identity.service + identity.account
        guard values[slot] == nil else { throw KeychainFailure.duplicateKey }
        values[slot] = key
        adds += 1
    }
    func read(identity: KeychainIdentity, reason: String) throws -> Data {
        reads += 1
        if unavailable { throw KeychainFailure.unavailable }
        guard let data = values[identity.service + identity.account] else { throw KeychainFailure.missingKey }
        return data
    }
    func delete(identity: KeychainIdentity) { values[identity.service + identity.account] = nil }
    func replace(_ data: Data, identity: KeychainIdentity) { values[identity.service + identity.account] = data }
    func makeUnavailable() { unavailable = true }
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
    #expect(try await service.unlock().isEmpty)
    let record = try VaultRecord(.settings(VaultSettings()))
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
