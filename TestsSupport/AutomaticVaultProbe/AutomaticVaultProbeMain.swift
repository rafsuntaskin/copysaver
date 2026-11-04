import CopySaverDomain
import CopySaverPlatform
import CopySaverVault
import Foundation

/// Opt-in real-Keychain validation. Fixed identity, fixed fictional content, no clipboard.
/// Never accepts a caller-provided vault path, key, service, or payload.
@main struct AutomaticVaultProbe {
    static let identifier = "org.copysaver.CopySaver.community.AutomaticFixture.dev"
    static let text = "CopySaver automatic synthetic canary café 日本語\n  preserved whitespace  "

    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard Bundle.main.bundleIdentifier == identifier,
              arguments.count == 2, arguments[1] == "--confirm-synthetic-vault",
              ["create", "verify", "missing-key", "cleanup"].contains(arguments[0]) else {
            print("Refused: use the isolated fixture bundle and an explicit synthetic mode.")
            exit(64)
        }
        do {
            try await run(arguments[0])
            print("Synthetic automatic-vault check passed: \(arguments[0])")
        } catch {
            // Intentionally no generic Error descriptions, identifiers or payloads in diagnostics.
            if let failure = error as? KeychainFailure { print("Synthetic automatic-vault Keychain failure: \(failure)") }
            else { print("Synthetic automatic-vault check failed.") }
            exit(1)
        }
    }

    static func run(_ mode: String) async throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent(identifier).appendingPathComponent("SyntheticAutomaticValidation")
        let url = directory.appendingPathComponent("vault.sqlite")
        let provider = try KeychainVaultKeyProvider(bundleIdentifier: identifier, protection: .automatic)
        let service = DesktopVaultService(url: url, keys: provider)
        if mode == "create" {
            guard try await !service.prepare() else { throw ProbeFailure.existingFixture }
            try await service.create()
            let initial = try await service.unlock()
            guard try HistoryPolicy.settings(in: initial).captureEnabled else { throw ProbeFailure.failed }
            _ = try await service.capture(ClipboardSample(text: text, date: Date()))
            await service.lock()
        } else {
            let session = try VaultSession.open(at: url)
            let vaultID = await session.vaultID
            try await session.close()
            if mode == "cleanup" {
                try await provider.deleteKey(for: vaultID)
                try FileManager.default.removeItem(at: directory)
                return
            }
            guard try await service.prepare() else { throw ProbeFailure.failed }
            let records = try await service.unlock()
            guard records.contains(where: {
                if case .history(let item) = $0.payload { return item.text.utf8.elementsEqual(text.utf8) }
                return false
            }) else { throw ProbeFailure.failed }
            await service.lock()
            if mode == "missing-key" {
                let before = try snapshots(url)
                try await provider.deleteKey(for: vaultID)
                do { _ = try await service.unlock(); throw ProbeFailure.failed }
                catch KeychainFailure.missingKey {}
                guard try snapshots(url) == before else { throw ProbeFailure.failed }
                do { _ = try await provider.loadKey(for: vaultID); throw ProbeFailure.failed }
                catch KeychainFailure.missingKey {}
                try FileManager.default.removeItem(at: directory)
                return
            }
        }
        // A realistic file-only attacker must not find the plaintext canary in DB/WAL/SHM.
        for data in try snapshots(url).compactMap({ $0 }) {
            guard data.range(of: Data(text.utf8)) == nil else { throw ProbeFailure.failed }
        }
    }

    static func snapshots(_ url: URL) throws -> [Data?] {
        try ["", "-wal", "-shm"].map { suffix in
            let file = URL(filePath: url.path + suffix)
            return FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
        }
    }
    enum ProbeFailure: Error { case failed, existingFixture }
}
