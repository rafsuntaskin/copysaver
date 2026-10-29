import AppKit
import CopySaverDomain
import CopySaverPlatform
import CopySaverVault
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
            --owner-fixture {create|verify|cancel} --confirm-synthetic-vault
            --owner-fixture cleanup --confirm-synthetic-vault --confirm-delete-fixture
            Requires a separately signed ID.dev.BoundaryProbe app. No keys are printed or written to files.
            Owner fixture commands require the fixed isolated SecurityFixture.dev signed identity.
            The owner app must successfully unlock the same fixture before AND after this probe.
            """)
            return
        }
        do {
            if arguments.first == "--owner-fixture" {
                guard let action = try? SyntheticOwnerFixture.action(arguments) else { throw ProbeFailure.invalidArguments }
                try requireSignedIdentity(SyntheticOwnerFixture.identifier)
                NSApplication.shared.setActivationPolicy(.accessory)
                NSApplication.shared.activate()
                try await SyntheticOwnerFixture.run(action)
                return
            }
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

/// Fixed synthetic owner, compiled only into the manual fixture executable.
/// Its identity, location and data cannot be supplied by command-line callers.
private enum SyntheticOwnerFixture {
    static let identifier = "org.copysaver.CopySaver.SecurityFixture.dev"
    private static let recordID = UUID(uuidString: "A7D875F7-E8B2-4DD0-97AF-2DF1C1A4C106")!
    private static let title = "Synthetic isolation fixture"
    private static let body = "CopySaver isolated owner canary v1\n  café 日本語  \n"

    enum Action: String { case create, verify, cancel, cleanup }
    private enum Failure: Error { case invalidArguments, unexpectedFixture, expectedCancellation, mutationAdmitted }

    static func action(_ arguments: [String]) throws -> Action {
        guard arguments.count >= 3, arguments[0] == "--owner-fixture",
              let action = Action(rawValue: arguments[1]), arguments[2] == "--confirm-synthetic-vault",
              arguments.count == (action == .cleanup ? 4 : 3)
        else { throw Failure.invalidArguments }
        if action == .cleanup, arguments[3] != "--confirm-delete-fixture" { throw Failure.invalidArguments }
        return action
    }

    static func run(_ action: Action) async throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        let location = support.appendingPathComponent("SyntheticKeychainValidation", isDirectory: true)
            .appendingPathComponent("vault.sqlite")
        let keys = try KeychainVaultKeyProvider(bundleIdentifier: identifier)
        let service = DesktopVaultService(url: location, keys: keys)
        let exists = try await service.prepare()
        if action == .create {
            guard !exists else { throw Failure.unexpectedFixture }
            try await service.create()
            let records = try await service.unlock()
            guard records.allSatisfy({ if case .settings = $0.payload { return true }; return false })
            else { await service.lock(); throw Failure.unexpectedFixture }
            let instant = Date(timeIntervalSince1970: 1_700_000_000)
            let snippet = try Snippet(id: recordID, name: title, body: body, category: "Synthetic",
                                      isSensitive: false, createdAt: instant, updatedAt: instant)
            _ = try await service.save(VaultRecord(.snippet(snippet)))
            await service.lock()
            try await requireMutationDenied(service)
            print("Synthetic owner created, authenticated and saved; locked writes denied.")
            return
        }
        guard exists else { throw Failure.unexpectedFixture }
        if action == .cancel {
            do {
                _ = try await service.unlock()
                await service.lock()
                throw Failure.expectedCancellation
            } catch KeychainFailure.cancelled {
                try await requireMutationDenied(service)
                print("Cancelled owner authentication preserved locked write admission.")
                return
            }
        }
        let records = try await service.unlock()
        let hasExpectedSnippet = records.count == 2 && records.contains(where: { record in
            guard case .snippet(let snippet) = record.payload else { return false }
            return snippet.id == recordID && snippet.name == title &&
                Array(snippet.body.utf8) == Array(body.utf8) && snippet.category == "Synthetic" && !snippet.isSensitive
        })
        let unseeded = records.count == 1 && records.allSatisfy({ if case .settings = $0.payload { return true }; return false })
        guard hasExpectedSnippet || (action == .cleanup && unseeded),
              try !HistoryPolicy.settings(in: records).captureEnabled
        else { await service.lock(); throw Failure.unexpectedFixture }
        if action == .cleanup {
            // Only the fixed, authenticated synthetic fixture can reach reset.
            try await service.reset()
            print("Synthetic owner fixture removed. No clipboard-history app data was accessed.")
        } else {
            await service.lock()
            try await requireMutationDenied(service)
            print("Synthetic owner authenticated and exact saved text verified; locked writes denied.")
        }
    }

    private static func requireMutationDenied(_ service: DesktopVaultService) async throws {
        do {
            _ = try await service.delete(recordID)
            throw Failure.mutationAdmitted
        } catch VaultError.locked { }
    }
}
