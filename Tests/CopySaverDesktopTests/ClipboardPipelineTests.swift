import AppKit
import CopySaverDomain
@testable import CopySaverDesktop
import CopySaverPlatform
import Foundation
import Testing

/// Only the OS boundaries are replaced. The model/service, CryptoKit, policies,
/// serialization and SQLite transaction path are the production implementations.
private actor PipelineKeychain: KeychainTransport {
    private var values: [String: Data] = [:]
    private var failure: KeychainFailure?
    private(set) var reads = 0
    func setFailure(_ failure: KeychainFailure?) { self.failure = failure }
    func add(_ key: Data, identity: KeychainIdentity) throws {
        let slot = identity.service + identity.account
        guard values[slot] == nil else { throw KeychainFailure.duplicateKey }
        values[slot] = key
    }
    func read(identity: KeychainIdentity, reason: String) throws -> Data {
        reads += 1
        if let failure { throw failure }
        guard let value = values[identity.service + identity.account] else { throw KeychainFailure.missingKey }
        return value
    }
    func delete(identity: KeychainIdentity) { values[identity.service + identity.account] = nil }
}

@MainActor private final class PipelineClock {
    var date = Date()
}

@MainActor private final class PipelinePasteboard: ClipboardInput, ClipboardPasteboard {
    var changeCount = 0
    var permission: ClipboardPermission = .allowed
    var activeApplication: String? = "org.example.synthetic-editor"
    var activeApplicationName: String? = "Synthetic editor"
    private(set) var item: NSPasteboardItem?
    private(set) var textReads = 0
    private(set) var clears = 0
    private(set) var options: NSPasteboard.ContentsOptions = []
    var types: Set<String> { Set((item?.types ?? []).map(\.rawValue)) }
    var itemCount: Int { item == nil ? 0 : 1 }
    func readText() -> String? { textReads += 1; return item?.string(forType: .string) }
    func sourceHint() -> String? { item?.string(forType: .init("org.nspasteboard.source")) }
    func prepare(options: NSPasteboard.ContentsOptions) { self.options = options; item = nil; changeCount += 1 }
    func write(_ item: NSPasteboardItem) -> Bool { self.item = item; changeCount += 1; return true }
    func string(for type: NSPasteboard.PasteboardType) -> String? { item?.string(forType: type) }
    func clear() { clears += 1; item = nil; changeCount += 1 }
    func externalCopy(_ text: String) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        _ = write(item)
    }
}

@MainActor private final class ClipboardPipeline {
    let url: URL
    let keychain = PipelineKeychain()
    let board = PipelinePasteboard()
    let clock = PipelineClock()
    let keys: KeychainVaultKeyProvider
    let output: SystemClipboardOutput
    let monitor: ClipboardMonitor
    let service: DesktopVaultService
    let model: DesktopModel

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("copysaver-pipeline-\(UUID())", isDirectory: true)
            .appendingPathComponent("vault.sqlite")
        let identifier = "org.example.CopySaver.pipeline.dev"
        keys = try KeychainVaultKeyProvider(bundleIdentifier: identifier, transport: keychain)
        service = DesktopVaultService(url: url, keys: keys)
        output = SystemClipboardOutput(bundleIdentifier: identifier, pasteboard: board, now: { [clock] in clock.date }, schedulesTimer: false)
        monitor = ClipboardMonitor(input: board, ownIdentifier: identifier, now: { [clock] in clock.date })
        model = DesktopModel(service: service, clipboard: output)
        connect(model)
    }

    func connect(_ model: DesktopModel) {
        model.clipboardPermission = board.permission
        model.onCaptureBoundary = { [monitor] in monitor.suspend() }
    }

    func create() async {
        model.start()
        await model.finishPendingOperations()
        #expect(model.phase == .needsSetup)
        #expect(await keychain.reads == 0)
        model.createVault()
        await model.finishPendingOperations()
        #expect(model.phase == .locked)
        await model.unlock()?.value
        #expect(model.phase == .unlocked)
    }

    func poll(_ model: DesktopModel) async {
        model.clipboardPermission = board.permission
        if let sample = monitor.poll(conditions: model.captureConditions, exclusions: model.settings?.excludedBundleIDs ?? []) {
            model.capture(sample)
            await model.finishPendingOperations()
        }
    }

    func reopen() async -> DesktopModel {
        model.lock()
        await model.finishPendingOperations()
        #expect(model.records.isEmpty && model.libraryQuery.isEmpty && model.focusQuery.isEmpty)
        let service = DesktopVaultService(url: url, keys: keys)
        let next = DesktopModel(service: service, clipboard: output)
        connect(next)
        let reads = await keychain.reads
        next.start()
        await next.finishPendingOperations()
        #expect(next.phase == .locked && next.records.isEmpty)
        #expect(await keychain.reads == reads)
        await next.unlock()?.value
        #expect(next.phase == .unlocked)
        return next
    }

    func checkEncryptedCanaries(_ values: [String]) throws {
        for suffix in ["", "-wal", "-shm"] {
            let path = URL(filePath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            let bytes = try Data(contentsOf: path)
            for value in values { #expect(bytes.range(of: Data(value.utf8)) == nil) }
        }
    }
}

@MainActor @Test func historyPipelineEncryptsSearchesCopiesAndReopensWithoutFeedbackOrOldImports() async throws {
    let pipeline = try ClipboardPipeline()
    defer { try? FileManager.default.removeItem(at: pipeline.url.deletingLastPathComponent()) }
    let model = pipeline.model
    await pipeline.create()
    #expect(model.settings?.captureEnabled == false)
    pipeline.board.externalCopy("Synthetic old clipboard must not be imported")
    await pipeline.poll(model)
    model.setCaptureEnabled(true)
    await model.finishPendingOperations()
    await pipeline.poll(model)
    #expect(pipeline.board.textReads == 0 && model.items(query: "").isEmpty)

    let text = "Synthetic pipeline cafe\u{301} 👩🏽‍💻\n  Preserve\tthese spaces\n"
    pipeline.board.externalCopy(text)
    await pipeline.poll(model)
    let captured = try #require(model.items(query: "CAFÉ").first)
    #expect(captured.content.utf8.elementsEqual(text.utf8))
    model.libraryQuery = "Preserve"
    model.ensureSelection(query: model.libraryQuery)
    model.copySelection()
    await model.finishPendingOperations()
    #expect(model.notice == "Copied")
    #expect(pipeline.board.item?.string(forType: .string)?.utf8.elementsEqual(text.utf8) == true)
    #expect(pipeline.board.options.contains(.currentHostOnly))
    #expect(pipeline.board.types.contains("org.copysaver.owner"))
    let reads = pipeline.board.textReads
    await pipeline.poll(model)
    #expect(pipeline.board.textReads == reads && model.items(query: "").count == 1)

    pipeline.clock.date = pipeline.clock.date.addingTimeInterval(1)
    pipeline.board.externalCopy(text)
    await pipeline.poll(model)
    guard case .history(let duplicate) = try #require(model.items(query: "").first).payload else {
        Issue.record("Missing captured history"); return
    }
    #expect(duplicate.id == captured.id && duplicate.repeatCount == 2 && duplicate.lastCopiedAt != nil)
    model.toggleCapturePause()
    await model.finishPendingOperations()
    pipeline.board.externalCopy("Synthetic copy while paused")
    await pipeline.poll(model)

    let reopened = await pipeline.reopen()
    #expect(reopened.settings?.captureEnabled == true && reopened.settings?.manuallyPaused == true)
    #expect(reopened.items(query: "CAFÉ").first?.content.utf8.elementsEqual(text.utf8) == true)
    await pipeline.poll(reopened)
    #expect(pipeline.board.textReads == reads + 1)
    reopened.toggleCapturePause()
    await reopened.finishPendingOperations()
    pipeline.board.permission = .denied
    await pipeline.poll(reopened)
    pipeline.board.externalCopy("Synthetic copy before permission restoration")
    pipeline.board.permission = .allowed
    await pipeline.poll(reopened)
    #expect(pipeline.board.textReads == reads + 1)
    pipeline.board.externalCopy("Synthetic fresh copy after permission restoration")
    await pipeline.poll(reopened)
    #expect(reopened.items(query: "").count == 2)
    #expect(reopened.items(query: "before permission").isEmpty)
    try pipeline.checkEncryptedCanaries([text, "Synthetic fresh copy after permission restoration", "org.example.synthetic-editor"])
    reopened.lock()
    await reopened.finishPendingOperations()
}

@MainActor @Test func sensitiveSnippetPipelineAuthenticatesCopiesAndPreservesExternalClipboardOnLock() async throws {
    let pipeline = try ClipboardPipeline()
    defer { try? FileManager.default.removeItem(at: pipeline.url.deletingLastPathComponent()) }
    let model = pipeline.model
    await pipeline.create()
    #expect(model.beginSnippet())
    model.draftName = "Synthetic private pipeline title"
    model.draftCategory = "Synthetic pipeline category"
    model.draftBody = "Synthetic confidential pipeline body\n  cafe\u{301}"
    model.draftSensitive = true
    model.saveDraft()
    await model.finishPendingOperations()
    let snippet = try #require(model.selectedRecord)
    #expect(snippet.isSensitive && model.detailText(for: snippet) == "Sensitive content")
    #expect(model.items(query: "confidential").isEmpty)
    let reads = await pipeline.keychain.reads
    pipeline.board.externalCopy("Synthetic clipboard before denied authentication")
    let count = pipeline.board.changeCount
    await pipeline.keychain.setFailure(.cancelled)
    model.copySelection()
    await model.finishPendingOperations()
    #expect(pipeline.board.changeCount == count && model.notice != "Copied")
    #expect(await pipeline.keychain.reads == reads + 1)
    await pipeline.keychain.setFailure(nil)
    model.copySelection()
    await model.finishPendingOperations()
    #expect(model.notice == "Copied")
    #expect(pipeline.board.item?.string(forType: .string)?.utf8.elementsEqual(snippet.content.utf8) == true)
    #expect(pipeline.board.types.contains("org.nspasteboard.ConcealedType"))
    #expect(await pipeline.keychain.reads == reads + 2)
    pipeline.clock.date = pipeline.clock.date.addingTimeInterval(31)
    pipeline.output.clearExpiredCopy()
    #expect(pipeline.board.item == nil && pipeline.board.clears == 1)

    model.copySelection()
    await model.finishPendingOperations()
    pipeline.board.externalCopy("Synthetic newer external clipboard")
    let reopened = await pipeline.reopen()
    #expect(pipeline.board.item?.string(forType: .string) == "Synthetic newer external clipboard")
    reopened.section = .snippets
    reopened.ensureSelection(query: "private pipeline")
    guard case .snippet(let saved) = try #require(reopened.selectedRecord).payload else {
        Issue.record("Missing saved snippet"); return
    }
    #expect(saved.body.utf8.elementsEqual(snippet.content.utf8) && saved.lastCopiedAt != nil)
    try pipeline.checkEncryptedCanaries([saved.name, saved.body, try #require(saved.category)])
    reopened.lock()
    await reopened.finishPendingOperations()
}
