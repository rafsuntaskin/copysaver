import CopySaverDomain
@testable import CopySaverDesktop
import CopySaverPlatform
import CopySaverVault
import Foundation
import Testing

private actor TestVault: DesktopVaultAccess {
    var prepareCalls = 0
    var records: [VaultRecord] = []
    var authenticationCalls = 0
    let exists: Bool
    let authenticationFailure: KeychainFailure?
    let authenticationGate: TestGate?
    let unlockGate: TestGate?
    init(records: [VaultRecord] = [], exists: Bool = true, authenticationFailure: KeychainFailure? = nil, authenticationGate: TestGate? = nil, unlockGate: TestGate? = nil) {
        self.records = records
        self.exists = exists
        self.authenticationFailure = authenticationFailure
        self.authenticationGate = authenticationGate
        self.unlockGate = unlockGate
    }
    func prepare() -> Bool { prepareCalls += 1; return exists }
    func create() {}
    func unlock() async -> [VaultRecord] { await unlockGate?.wait(); return records }
    func lock() {}
    func save(_ record: VaultRecord) -> [VaultRecord] { records.append(record); return records }
    func delete(_ id: UUID) -> [VaultRecord] { records.removeAll { $0.id == id }; return records }
    func authenticateSensitiveAccess() async throws {
        authenticationCalls += 1
        await authenticationGate?.wait()
        if let authenticationFailure { throw authenticationFailure }
    }
}

private actor TestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var requested = false
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            requested = true
        }
    }
    func waitUntilRequested() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !requested {
            guard ContinuousClock.now < deadline else { throw GateFailure.noRequest }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}
private enum GateFailure: Error { case noRequest }

@MainActor private final class TestClipboard: ClipboardOutput {
    var copies = 0
    var clears = 0
    var shouldFail = false
    func copy(_ text: String, sensitive: Bool) throws {
        if shouldFail { throw ClipboardFailure.writeFailed }
        copies += 1
    }
    func clearOwnedSensitiveCopy() { clears += 1 }
    func clearExpiredCopy() {}
}

@MainActor @Test func previewDoesNotTouchVaultOrClipboardAndLockPurgesContent() async {
    let service = TestVault()
    let clipboard = TestClipboard()
    let model = DesktopModel(service: service, clipboard: clipboard, preview: true)
    model.start()
    model.copySelection()
    model.createVault()
    model.unlock()
    #expect(await service.prepareCalls == 0)
    #expect(clipboard.copies == 0)
    #expect(model.records.count == 9)
    model.libraryQuery = "search"
    model.focusQuery = "another search"
    model.draftName = "draft"
    model.draftBody = "unsaved body"
    model.lock()
    #expect(model.phase == .locked)
    #expect(model.records.isEmpty)
    #expect(model.selectedRecord == nil)
    #expect(model.libraryQuery.isEmpty && model.focusQuery.isEmpty)
    #expect(model.draftName.isEmpty && model.draftBody.isEmpty)
    #expect(clipboard.clears == 0)
}

@MainActor @Test func sensitivePreviewSearchAndDetailNeverExposeBody() {
    let model = DesktopModel(service: nil, clipboard: nil, preview: true)
    model.section = .snippets
    #expect(model.items(query: "confidential").isEmpty)
    let sensitive = model.items(query: "Travel").first
    #expect(sensitive != nil)
    if let sensitive {
        model.selectedID = sensitive.id
        #expect(model.detailText(for: sensitive) == "Sensitive content")
        model.revealSelection()
        #expect(model.revealedID == nil)
    }
}

@Test func shortcutValidationProtectsNormalTypingAndSpotlight() {
    #expect(FocusShortcut.standard.isValid)
    #expect(!FocusShortcut(keyCode: 9, modifiers: 0, keyName: "V").isValid)
    #expect(!FocusShortcut(keyCode: 49, modifiers: 1 << 20, keyName: "Space").isValid)
    #expect(!FocusShortcut(keyCode: 999, modifiers: 1 << 20, keyName: "Invalid").isValid)
    #expect(!FocusShortcut(keyCode: 9, modifiers: 1 << 19, keyName: "V").isValid)
}

private func sensitiveRecord() throws -> VaultRecord {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    return try VaultRecord(.snippet(Snippet(name: "Synthetic private note", body: "Synthetic private body", isSensitive: true, createdAt: now, updatedAt: now)))
}

@MainActor @Test func lateUnlockCannotRepopulateALockedWindow() async throws {
    let gate = TestGate()
    let vault = TestVault(records: [try sensitiveRecord()], unlockGate: gate)
    let model = DesktopModel(service: vault, clipboard: TestClipboard())
    model.start()
    await model.finishPendingOperations()
    #expect(model.phase == .locked)
    let unlock = model.unlock()
    try await gate.waitUntilRequested()
    model.lock()
    await gate.release()
    await unlock?.value
    await model.finishPendingOperations()
    #expect(model.phase == .locked)
    #expect(model.records.isEmpty && model.selectedRecord == nil)
}

@MainActor @Test func lateSensitiveRevealCannotAppearAfterDeactivation() async throws {
    let gate = TestGate()
    let vault = TestVault(records: [try sensitiveRecord()], authenticationGate: gate)
    let model = DesktopModel(service: vault, clipboard: TestClipboard())
    model.section = .snippets
    model.start()
    await model.finishPendingOperations()
    await model.unlock()?.value
    model.revealSelection()
    try await gate.waitUntilRequested()
    model.setPresentationActive(false)
    await gate.release()
    await model.finishPendingOperations()
    #expect(model.revealedID == nil)
    if let record = model.selectedRecord { #expect(model.detailText(for: record) == "Sensitive content") }
}

@MainActor @Test func sensitiveCopyAlwaysAuthenticatesEvenAfterReveal() async throws {
    let vault = TestVault(records: [try sensitiveRecord()])
    let clipboard = TestClipboard()
    let model = DesktopModel(service: vault, clipboard: clipboard)
    model.section = .snippets
    model.start()
    await model.finishPendingOperations()
    await model.unlock()?.value
    model.revealSelection()
    await model.finishPendingOperations()
    #expect(model.revealedID == model.selectedID)
    model.copySelection()
    await model.finishPendingOperations()
    model.copySelection()
    await model.finishPendingOperations()
    #expect(await vault.authenticationCalls == 3)
    #expect(clipboard.copies == 2)
    model.lock()
    await model.finishPendingOperations()
}

@MainActor @Test func lateSensitiveCopyCannotResumeAfterDeactivationAndReactivation() async throws {
    let gate = TestGate()
    let vault = TestVault(records: [try sensitiveRecord()], authenticationGate: gate)
    let clipboard = TestClipboard()
    let model = DesktopModel(service: vault, clipboard: clipboard)
    model.section = .snippets
    model.start()
    await model.finishPendingOperations()
    await model.unlock()?.value
    model.copySelection()
    try await gate.waitUntilRequested()
    model.setPresentationActive(false)
    model.setPresentationActive(true)
    await gate.release()
    await model.finishPendingOperations()
    #expect(clipboard.copies == 0)
    #expect(model.notice == nil)
}

@MainActor @Test func cancelledSensitiveAuthenticationDoesNotCopyOrReveal() async throws {
    let vault = TestVault(records: [try sensitiveRecord()], authenticationFailure: .cancelled)
    let clipboard = TestClipboard()
    let model = DesktopModel(service: vault, clipboard: clipboard)
    model.section = .snippets
    model.start()
    await model.finishPendingOperations()
    await model.unlock()?.value
    model.copySelection()
    await model.finishPendingOperations()
    model.revealSelection()
    await model.finishPendingOperations()
    #expect(model.revealedID == nil)
    #expect(clipboard.copies == 0)
    #expect(model.notice == nil)
}

@MainActor @Test func clipboardFailureNeverReportsCopySuccess() async throws {
    let vault = TestVault(records: [try sensitiveRecord()])
    let clipboard = TestClipboard()
    clipboard.shouldFail = true
    let model = DesktopModel(service: vault, clipboard: clipboard)
    model.section = .snippets
    model.start()
    await model.finishPendingOperations()
    await model.unlock()?.value
    model.copySelection()
    await model.finishPendingOperations()
    #expect(model.notice == nil)
    #expect(model.errorMessage == "Copy failed. Please try again.")
}

@MainActor @Test func creationReturnsLockedAndSnippetSavePreservesText() async throws {
    let vault = TestVault(exists: false)
    let model = DesktopModel(service: vault, clipboard: TestClipboard())
    model.start()
    await model.finishPendingOperations()
    #expect(model.phase == .needsSetup)
    model.createVault()
    await model.finishPendingOperations()
    #expect(model.phase == .locked && model.records.isEmpty)
    await model.unlock()?.value
    model.beginSnippet()
    model.draftName = "  Synthetic address  "
    model.draftBody = "  example\nsecond line\t"
    model.saveDraft()
    await model.finishPendingOperations()
    guard case .snippet(let snippet) = model.selectedRecord?.payload else { Issue.record("Missing saved snippet"); return }
    #expect(snippet.name == "Synthetic address")
    #expect(snippet.body == "  example\nsecond line\t")
    #expect(model.draftName.isEmpty && model.draftBody.isEmpty)
}
