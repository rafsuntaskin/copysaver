import Foundation
import Security

/// The legacy login Keychain supports ad-hoc apps without provisioned access groups.
/// SecAccess is deprecated, but is the ACL API for that implementation (Apple TN3137).
/// Never replace its restricted-operation ACL with an all-apps entry.
enum LoginKeychainQueries {
    static func base(_ identity: KeychainIdentity) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: identity.service,
            kSecAttrAccount as String: identity.account,
            kSecUseDataProtectionKeychain as String: false,
        ]
    }

    static func add(_ key: Data, identity: KeychainIdentity) throws -> [String: Any] {
        guard key.count == 32 else { throw KeychainFailure.invalidKeyData }
        var access: SecAccess?
        // For SecAccessCreate, nil means the calling app only, not every application.
        let status = SecAccessCreate("CopySaver encryption key" as CFString, nil, &access)
        guard status == errSecSuccess, let access else { throw KeychainFailure.protectionUnavailable }
        var query = base(identity)
        query[kSecAttrAccess as String] = access
        query[kSecValueData as String] = key
        return query
    }

    static func read(_ identity: KeychainIdentity, allowInteraction: Bool) -> [String: Any] {
        var query = base(identity)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        // The file-based Keychain shim uses this option, not LAContext's DP policy.
        if !allowInteraction { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        return query
    }
}

public struct SystemLoginKeychainTransport: KeychainTransport {
    private let allowInteraction: Bool

    /// Background open never produces repeated OS prompts. Explicit Retry may ask
    /// for access after an ad-hoc update or a manually locked login Keychain.
    public init(allowInteraction: Bool = false) { self.allowInteraction = allowInteraction }

    public func add(_ key: Data, identity: KeychainIdentity) async throws {
        try await perform(checkAfter: false) {
            var query = try LoginKeychainQueries.add(key, identity: identity)
            query[kSecUseKeychain as String] = try Self.defaultKeychain()
            if !allowInteraction { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainQueries.failure(status) }
        }
    }

    public func read(identity: KeychainIdentity, reason: String) async throws -> Data {
        try await perform {
            var query = LoginKeychainQueries.read(identity, allowInteraction: allowInteraction)
            query[kSecMatchSearchList as String] = [try Self.defaultKeychain()]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess else { throw KeychainQueries.failure(status) }
            guard let data = result as? Data, data.count == 32 else { throw KeychainFailure.invalidKeyData }
            return data
        }
    }

    public func delete(identity: KeychainIdentity) async throws {
        try await perform {
            var query = LoginKeychainQueries.base(identity)
            query[kSecMatchSearchList as String] = [try Self.defaultKeychain()]
            if !allowInteraction { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainQueries.failure(status) }
        }
    }

    public func requestAccess(identity: KeychainIdentity) async throws {
        _ = try await SystemLoginKeychainTransport(allowInteraction: true).read(identity: identity, reason: "Open your CopySaver vault")
    }

    private static func defaultKeychain() throws -> SecKeychain {
        var keychain: SecKeychain?
        let status = SecKeychainCopyDefault(&keychain)
        guard status == errSecSuccess, let keychain else { throw KeychainFailure.unavailable }
        return keychain
    }

    private func perform<T: Sendable>(checkAfter: Bool = true, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        let result: T = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
        if checkAfter { try Task.checkCancellation() }
        return result
    }
}
