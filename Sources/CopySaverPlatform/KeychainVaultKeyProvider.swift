import CopySaverVault
import CryptoKit
import Foundation
import LocalAuthentication
import Security

public enum KeychainFailure: Error, Equatable, Sendable {
    case missingKey, duplicateKey, cancelled, authenticationFailed, interactionRequired
    case missingEntitlement, unavailable, invalidKeyData, protectionUnavailable, invalidIdentity
}

public struct KeychainIdentity: Equatable, Sendable {
    public let service: String
    public let vaultID: UUID
    public var account: String { vaultID.uuidString.lowercased() }

    public init(bundleIdentifier: String, vaultID: UUID) throws {
        let components = bundleIdentifier.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        guard components.count > 1, bundleIdentifier.utf8.count <= 255,
              components.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) })
        else { throw KeychainFailure.invalidIdentity }
        self.service = bundleIdentifier + ".vault-key"
        self.vaultID = vaultID
    }
}

public protocol KeychainTransport: Sendable {
    func add(_ key: Data, identity: KeychainIdentity) async throws
    func read(identity: KeychainIdentity, reason: String) async throws -> Data
    func delete(identity: KeychainIdentity) async throws
}

public struct KeychainVaultKeyProvider: VaultKeyProvider, Sendable {
    public let bundleIdentifier: String
    private let transport: any KeychainTransport

    public init(bundleIdentifier: String, transport: any KeychainTransport = SystemKeychainTransport()) throws {
        _ = try KeychainIdentity(bundleIdentifier: bundleIdentifier, vaultID: UUID())
        self.bundleIdentifier = bundleIdentifier
        self.transport = transport
    }

    public func createKey(for vaultID: UUID) async throws -> SymmetricKey {
        try Task.checkCancellation()
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try await transport.add(data, identity: identity(for: vaultID))
        return key
    }

    public func loadKey(for vaultID: UUID) async throws -> SymmetricKey {
        try await loadKey(for: vaultID, reason: "Unlock your CopySaver vault")
    }

    public func authenticateSensitiveAccess(for vaultID: UUID) async throws {
        _ = try await loadKey(for: vaultID, reason: "Access a sensitive CopySaver snippet")
    }

    public func deleteKey(for vaultID: UUID) async throws {
        try await transport.delete(identity: identity(for: vaultID))
    }

    private func identity(for vaultID: UUID) throws -> KeychainIdentity {
        try KeychainIdentity(bundleIdentifier: bundleIdentifier, vaultID: vaultID)
    }

    private func loadKey(for vaultID: UUID, reason: String) async throws -> SymmetricKey {
        try Task.checkCancellation()
        let data = try await transport.read(identity: identity(for: vaultID), reason: reason)
        try Task.checkCancellation()
        guard data.count == 32 else { throw KeychainFailure.invalidKeyData }
        return SymmetricKey(data: data)
    }
}

enum KeychainQueries {
    static func base(_ identity: KeychainIdentity) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: identity.service,
            kSecAttrAccount as String: identity.account,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
        ]
    }

    static func add(_ data: Data, identity: KeychainIdentity) throws -> [String: Any] {
        guard data.count == 32 else { throw KeychainFailure.invalidKeyData }
        guard let protection = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil
        ) else { throw KeychainFailure.protectionUnavailable }
        var query = base(identity)
        query[kSecAttrAccessControl as String] = protection
        query[kSecValueData as String] = data
        return query
    }

    static func read(_ identity: KeychainIdentity, context: LAContext) -> [String: Any] {
        var query = base(identity)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        query[kSecUseAuthenticationContext as String] = context
        return query
    }

    static func failure(_ status: OSStatus) -> KeychainFailure {
        switch status {
        case errSecItemNotFound: .missingKey
        case errSecDuplicateItem: .duplicateKey
        case errSecUserCanceled: .cancelled
        case errSecAuthFailed: .authenticationFailed
        case errSecInteractionNotAllowed: .interactionRequired
        case errSecMissingEntitlement: .missingEntitlement
        default: .unavailable
        }
    }
}

/// The context is configured before dispatch. Only invalidation crosses threads,
/// which LocalAuthentication provides to interrupt a pending evaluation.
private final class AuthenticationAttempt: @unchecked Sendable {
    let context = LAContext()
    private let lock = NSLock()
    private var cancelled = false

    init(reason: String) {
        context.localizedReason = reason
        context.localizedCancelTitle = "Cancel"
        context.touchIDAuthenticationAllowableReuseDuration = 0
    }

    func checkCancellation() throws {
        lock.lock()
        let value = cancelled
        lock.unlock()
        if value { throw CancellationError() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        context.invalidate()
    }
}

public struct SystemKeychainTransport: KeychainTransport {
    public init() {}

    public func add(_ key: Data, identity: KeychainIdentity) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let status = SecItemAdd(try KeychainQueries.add(key, identity: identity) as CFDictionary, nil)
                    guard status == errSecSuccess else { throw KeychainQueries.failure(status) }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func read(identity: KeychainIdentity, reason: String) async throws -> Data {
        let attempt = AuthenticationAttempt(reason: reason)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { attempt.context.invalidate() }
                    do {
                        try attempt.checkCancellation()
                        var result: CFTypeRef?
                        let query = KeychainQueries.read(identity, context: attempt.context)
                        let status = SecItemCopyMatching(query as CFDictionary, &result)
                        try attempt.checkCancellation()
                        guard status == errSecSuccess else { throw KeychainQueries.failure(status) }
                        guard let value = result as? Data else { throw KeychainFailure.invalidKeyData }
                        continuation.resume(returning: value)
                    } catch { continuation.resume(throwing: error) }
                }
            }
            try Task.checkCancellation()
            return data
        } onCancel: {
            attempt.cancel()
        }
    }

    public func delete(identity: KeychainIdentity) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let status = SecItemDelete(KeychainQueries.base(identity) as CFDictionary)
                if status == errSecSuccess || status == errSecItemNotFound {
                    continuation.resume()
                } else { continuation.resume(throwing: KeychainQueries.failure(status)) }
            }
        }
    }
}
