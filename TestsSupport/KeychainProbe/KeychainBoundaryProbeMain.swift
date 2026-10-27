import AppKit
import CopySaverPlatform
import CryptoKit
import Foundation
import Security

/// Manual, separately signed integration fixture. Never embedded in CopySaver.
@main struct KeychainBoundaryProbe {
    // Fixed fixture account allows explicit cleanup after an interrupted probe.
    private static let controlID = UUID(uuidString: "53168140-67D9-4920-A18D-0FF157885A14")!
    private static let canary = Data("CopySaver synthetic Keychain control v1".utf8)

    private enum ProbeFailure: Error {
        case invalidArguments, unsignedOrWrongIdentity, unexpectedAccess, invalidControl, cleanupFailed
    }

    @MainActor static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] {
            print("""
            Manual signed probe; use only a confirmed synthetic development vault.
            --owner-bundle-id ID.dev --synthetic-vault-id UUID --confirm-synthetic-vault
            --owner-bundle-id ID.dev --cleanup-control
            Requires a separately signed ID.dev.BoundaryProbe app. No keys are printed or written to files.
            The owner app must successfully unlock the same fixture before AND after this probe.
            """)
            return
        }
        do {
            let options = try parse(arguments)
            let helperID = options.owner + ".BoundaryProbe"
            try requireSignedIdentity(helperID)
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.activate()
            let helper = try KeychainVaultKeyProvider(bundleIdentifier: helperID)
            if options.cleanup {
                try await helper.deleteKey(for: controlID)
                print("Synthetic helper control removed. No owner-app key was changed.")
                return
            }
            guard let vaultID = options.vaultID else { throw ProbeFailure.invalidArguments }
            try await run(helper: helper, owner: options.owner, vaultID: vaultID)
            print("Helper control passed; target item was not visible; helper control removed.")
            print("Not a completed isolation gate until the owner unlocks the same fixture again and signatures/entitlements are audited.")
        } catch {
            // Static diagnostics only: never print query values, returned data or raw Security errors.
            let message: String
            switch error {
            case ProbeFailure.invalidArguments:
                message = "Invalid arguments. Only an explicitly confirmed synthetic .dev vault is accepted; see --help."
            case ProbeFailure.unsignedOrWrongIdentity:
                message = "A valid development-signed helper app with its own matching bundle identity is required."
            case ProbeFailure.unexpectedAccess:
                message = "FAIL: the separately signed helper retrieved the target key. Do not approve the isolation gate."
            case ProbeFailure.invalidControl:
                message = "INCONCLUSIVE: helper positive control failed."
            case ProbeFailure.cleanupFailed:
                message = "INCONCLUSIVE: helper control cleanup failed; retry --cleanup-control before another probe."
            case KeychainFailure.duplicateKey:
                message = "INCONCLUSIVE: a helper control already exists. Finish any active probe before explicit cleanup."
            case KeychainFailure.missingEntitlement:
                message = "INCONCLUSIVE: helper Keychain entitlement is missing. This is not isolation evidence."
            case KeychainFailure.cancelled, KeychainFailure.authenticationFailed, KeychainFailure.interactionRequired:
                message = "INCONCLUSIVE: authentication did not complete. This is not isolation evidence."
            default:
                message = "INCONCLUSIVE: signed Keychain probe failed. No isolation result is established."
            }
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
        }
    }

    private static func parse(_ arguments: [String]) throws -> (owner: String, vaultID: UUID?, cleanup: Bool) {
        guard arguments.count >= 3, arguments[0] == "--owner-bundle-id" else { throw ProbeFailure.invalidArguments }
        let owner = arguments[1]
        guard owner.hasSuffix(".dev") else { throw ProbeFailure.invalidArguments }
        _ = try KeychainIdentity(bundleIdentifier: owner + ".BoundaryProbe", vaultID: controlID)
        if arguments.count == 3, arguments[2] == "--cleanup-control" { return (owner, nil, true) }
        guard arguments.count == 5, arguments[2] == "--synthetic-vault-id",
              let vaultID = UUID(uuidString: arguments[3]), arguments[4] == "--confirm-synthetic-vault"
        else { throw ProbeFailure.invalidArguments }
        return (owner, vaultID, false)
    }

    private static func requireSignedIdentity(_ identifier: String) throws {
        guard Bundle.main.bundleIdentifier == identifier else { throw ProbeFailure.unsignedOrWrongIdentity }
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, SecCSFlags(), nil) == errSecSuccess,
              SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              values[kSecCodeInfoIdentifier as String] as? String == identifier,
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty
        else { throw ProbeFailure.unsignedOrWrongIdentity }
    }

    private static func run(helper: KeychainVaultKeyProvider, owner: String, vaultID: UUID) async throws {
        // Add-only: never delete/replace a control left by another probe automatically.
        let created = try await helper.createKey(for: controlID)
        var failure: (any Error)?
        do {
            let sealed = try AES.GCM.seal(canary, using: created)
            try await verifyControl(helper, sealed: sealed)
            let target = try KeychainVaultKeyProvider(bundleIdentifier: owner)
            do {
                _ = try await target.loadKey(for: vaultID)
                throw ProbeFailure.unexpectedAccess
            } catch KeychainFailure.missingKey {
                // Only item-not-found is an expected isolation observation. Cancellation,
                // missing entitlements and all other errors make the probe inconclusive.
            }
            try await verifyControl(helper, sealed: sealed)
        } catch { failure = error }
        do { try await helper.deleteKey(for: controlID) }
        catch {
            FileHandle.standardError.write(Data("Helper control cleanup failed; use explicit cleanup after diagnosis.\n".utf8))
            if let failure { throw failure }
            throw ProbeFailure.cleanupFailed
        }
        if let failure { throw failure }
    }

    private static func verifyControl(_ helper: KeychainVaultKeyProvider, sealed: AES.GCM.SealedBox) async throws {
        let loaded = try await helper.loadKey(for: controlID)
        guard try AES.GCM.open(sealed, using: loaded) == canary else { throw ProbeFailure.invalidControl }
    }
}
