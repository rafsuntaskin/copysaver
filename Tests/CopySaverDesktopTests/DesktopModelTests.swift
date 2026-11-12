import CryptoKit
import CopySaverDomain
@testable import CopySaverDesktop
import CopySaverPlatform
import CopySaverVault
import Foundation
import Observation
import os
import Testing

private actor TestVault: DesktopVaultAccess {
    var prepareCalls = 0
    var records: [VaultRecord] = []
    var authenticationCalls = 0
    var unlockCalls = 0
    var createCalls = 0
    var unlockFailure: KeychainFailure?
    let exists: Bool
    var authenticationFailure: KeychainFailure?
    let authenticationGate: TestGate?
    let unlockGate: TestGate?
    init(records: [VaultRecord] = [], exists: Bool = true, authenticationFailure: KeychainFailure? = nil, authenticationGate: TestGate? = nil, unlockGate: TestGate? = nil) {
        self.records = records
        self.exists = exists
        self.authenticationFailure = authenticationFailure
        self.authenticationGate = authenticationGate
        self.unlockGate = unlockGate
    }
    func failAuthentication(_ failure: KeychainFailure) { authenticationFailure = failure }
    func prepare() -> Bool { prepareCalls += 1; return exists }
    func create() { createCalls += 1 }
    func failUnlock(_ failure: KeychainFailure) { unlockFailure = failure }
    func unlock() async throws -> [VaultRecord] {
        unlockCalls += 1
        await unlockGate?.wait()
        if let unlockFailure { throw unlockFailure }
        return records
    }
    func lock() {}
    func save(_ record: VaultRecord) -> [VaultRecord] { records.removeAll { $0.id == record.id }; records.append(record); return records }
    func markCopied(_ id: UUID, date: Date) throws -> [VaultRecord] { records = try records.map { $0.id == id ? try $0.markingCopied(at: date) : $0 }; return records }
    func delete(_ id: UUID) -> [VaultRecord] { records.removeAll { $0.id == id }; return records }
    func authenticateSensitiveAccess() async throws {
        authenticationCalls += 1
        await authenticationGate?.wait()
        if let authenticationFailure { throw authenticationFailure }
    }
}

@MainActor @Test func automaticStartupCreatesAndOpensWithoutSensitiveAuthentication() async throws {
    let settings = try VaultRecord(.settings(VaultSettings(captureEnabled: true)))
    let vault = TestVault(records: [settings], exists: false)
    let model = DesktopModel(service: vault, clipboard: TestClipboard(), automaticallyOpensVault: true)
    model.clipboardPermission = .allowed
    model.start()
    await model.finishPendingOperations()
    #expect(model.phase == .unlocked && model.captureConditions.canCapture)
    #expect(await vault.createCalls == 1)
    #expect(await vault.unlockCalls == 1)
    #expect(await vault.authenticationCalls == 0)
}

@MainActor @Test func automaticResumeWaitsForAllReasonsAndRespectsExplicitHide() async throws {
    let settings = try VaultRecord(.settings(VaultSettings(captureEnabled: true, manuallyPaused: true)))
    let vault = TestVault(records: [settings])
    let clipboard = TestClipboard()
    let model = DesktopModel(service: vault, clipboard: clipboard, automaticallyOpensVault: true)
    model.clipboardPermission = .allowed
    model.start(); await model.finishPendingOperations()
    model.libraryQuery = "Synthetic query"
    model.suspend(for: .sleep)
    model.suspend(for: .sessionInactive)
    await model.finishPendingOperations()
    #expect(model.phase == .locked && model.records.isEmpty && model.libraryQuery.isEmpty)
    model.resume(from: .sleep); await model.finishPendingOperations()
    #expect(model.phase == .locked && !model.captureConditions.canCapture)
    #expect(await vault.unlockCalls == 1)
    model.resume(from: .sessionInactive); await model.finishPendingOperations()
    #expect(model.phase == .unlocked && model.captureStatus == "Paused")
    #expect(await vault.unlockCalls == 2)
    #expect(await vault.authenticationCalls == 0)
    model.lock(); await model.finishPendingOperations()
    model.suspend(for: .sleep); model.resume(from: .sleep)
    await model.finishPendingOperations()
    #expect(model.phase == .locked)
    #expect(await vault.unlockCalls == 2)
    await model.unlock()?.value
    #expect(model.phase == .unlocked && model.settings?.manuallyPaused == true)
}

@MainActor @Test func automaticKeyFailureDoesNotRetryOnEveryWakeAndPreservesEmptyPresentation() async throws {
    let vault = TestVault(records: [try sensitiveRecord()])
    await vault.failUnlock(.interactionRequired)
    let model = DesktopModel(service: vault, clipboard: TestClipboard(), automaticallyOpensVault: true)
    model.start(); await model.finishPendingOperations()
    #expect(model.phase == .locked && model.records.isEmpty && model.errorMessage != nil)
    model.suspend(for: .sleep); model.resume(from: .sleep)
    await model.finishPendingOperations()
    #expect(await vault.unlockCalls == 1)
    #expect(model.phase == .locked && model.records.isEmpty && model.errorMessage != nil)
    await model.unlock()?.value
    #expect(await vault.unlockCalls == 2)
}

@MainActor @Test func lateAutomaticOpenCannotCrossManualHide() async throws {
    let gate = TestGate()
    let vault = TestVault(records: [try sensitiveRecord()], unlockGate: gate)
    let model = DesktopModel(service: vault, clipboard: TestClipboard(), automaticallyOpensVault: true)
    model.start()
    try await gate.waitUntilRequested()
    model.lock()
    await gate.release()
    await model.finishPendingOperations()
    #expect(model.phase == .locked && model.records.isEmpty)
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
    var lastText: String?
    func copy(_ text: String, sensitive: Bool) throws {
        if shouldFail { throw ClipboardFailure.writeFailed }
        copies += 1
        lastText = text
    }
    func clearOwnedSensitiveCopy() { clears += 1 }
    func clearExpiredCopy() {}
}

#if DEBUG
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

#endif

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

@MainActor @Test func communitySensitiveActionsTrustOpenSessionAndKeepConcealment() async throws {
    let record = try sensitiveRecord()
    let vault = TestVault(records: [record], authenticationFailure: .cancelled)
    let clipboard = TestClipboard()
    let model = DesktopModel(service: vault, clipboard: clipboard, automaticallyOpensVault: true)
    model.section = .snippets
    model.start(); await model.finishPendingOperations()
    #expect(model.phase == .unlocked && !model.requiresSensitiveAuthentication)
    #expect(model.detailText(for: record) == "Sensitive content")
    #expect(model.items(query: "private body").isEmpty)
    model.revealSelection(); await model.finishPendingOperations()
    #expect(model.revealedID == record.id)
    model.setPresentationActive(false)
    #expect(model.revealedID == nil)
    model.setPresentationActive(true)
    model.copySelection(); await model.finishPendingOperations()
    #expect(clipboard.copies == 1 && model.notice == "Copied")
    model.editSelection(); await model.finishPendingOperations()
    #expect(model.editingSnippet?.id == record.id && !model.draftIsConcealed)
    model.setPresentationActive(false); model.setPresentationActive(true)
    #expect(model.draftIsConcealed)
    model.resumeSensitiveDraft(); await model.finishPendingOperations()
    #expect(!model.draftIsConcealed)
    model.draftBody = "Synthetic revised community body"
    model.draftSensitive = false
    model.saveDraft(); await model.finishPendingOperations()
    #expect(model.selectedRecord?.content == "Synthetic revised community body")
    #expect(model.selectedRecord?.isSensitive == false)
    #expect(await vault.authenticationCalls == 0)
    model.lock(); await model.finishPendingOperations()
    #expect(model.records.isEmpty && model.draftBody.isEmpty)
}

@MainActor @Test func searchResultsRefreshAfterEditsPinDeleteAndReopen() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let older = try VaultRecord(.history(HistoryItem(text: "Synthetic older café", firstSeenAt: date, lastSeenAt: date)))
    let recent = try VaultRecord(.history(HistoryItem(text: "Synthetic recent 東京", firstSeenAt: date, lastSeenAt: date.addingTimeInterval(60))))
    let ordinary = try VaultRecord(.snippet(Snippet(name: "Alpha", body: "Synthetic visible needle", createdAt: date, updatedAt: date)))
    let hidden = try VaultRecord(.snippet(Snippet(name: "Bravo", body: "Synthetic hidden needle", isSensitive: true, createdAt: date, updatedAt: date)))
    let vault = TestVault(records: [older, hidden, recent, ordinary])
    let model = DesktopModel(service: vault, clipboard: nil, automaticallyOpensVault: true)
    model.start(); await model.finishPendingOperations()
    #expect(model.items(query: "").map(\.id) == [recent.id, older.id])
    #expect(model.items(query: "CAFÉ").map(\.id) == [older.id])
    #expect(model.items(query: "needle", section: .snippets).map(\.id) == [ordinary.id])
    #expect(model.items(query: "needle", section: .snippets).map(\.id) == [ordinary.id])
    model.navigate(to: .snippets); model.selectRecord(ordinary.id)
    model.editSelection(); await model.finishPendingOperations()
    model.draftSensitive = true
    model.saveDraft(); await model.finishPendingOperations()
    #expect(model.items(query: "needle").isEmpty) // Never reuse the formerly searchable body.
    #expect(model.items(query: "Alpha").first?.isSensitive == true)
    model.navigate(to: .history); model.selectRecord(recent.id)
    #expect(model.items(query: "", section: .pinned).isEmpty)
    model.toggleSelectedPin(); await model.finishPendingOperations()
    #expect(model.items(query: "", section: .pinned).map(\.id) == [recent.id])
    model.deleteSelection(); await model.finishPendingOperations()
    #expect(model.items(query: "").map(\.id) == [older.id])
    model.lock(); await model.finishPendingOperations()
    #expect(model.items(query: "").isEmpty && model.items(query: "Alpha", section: .snippets).isEmpty)
    _ = await vault.delete(older.id)
    let replacement = try VaultRecord(.history(HistoryItem(text: "Synthetic replacement", firstSeenAt: date, lastSeenAt: date)))
    _ = await vault.save(replacement)
    await model.unlock()?.value
    #expect(model.items(query: "").map(\.id) == [replacement.id])
    #expect(model.items(query: "CAFÉ").isEmpty)
}

@MainActor @Test func cachedResultsStillNotifyViewsWhenRecordsChange() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let record = try VaultRecord(.history(HistoryItem(text: "Synthetic observed result", firstSeenAt: date, lastSeenAt: date)))
    let model = DesktopModel(service: TestVault(records: [record]), clipboard: nil, automaticallyOpensVault: true)
    model.start(); await model.finishPendingOperations()
    _ = model.items(query: "") // Warm the result before establishing SwiftUI-style observation.
    let changed = OSAllocatedUnfairLock(initialState: false)
    withObservationTracking { _ = model.items(query: "") } onChange: { changed.withLock { $0 = true } }
    model.toggleSelectedPin(); await model.finishPendingOperations()
    #expect(changed.withLock { $0 })
    #expect(model.items(query: "", section: .pinned).map(\.id) == [record.id])
}

@MainActor @Test func arrowSelectionRespectsDirtyDraftAndKeepsCompactSearchVisible() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let first = try VaultRecord(.snippet(Snippet(name: "Alpha", body: "Synthetic first", createdAt: date, updatedAt: date)))
    let second = try VaultRecord(.snippet(Snippet(name: "Bravo", body: "Synthetic second", createdAt: date, updatedAt: date)))
    let model = DesktopModel(service: TestVault(records: [first, second]), clipboard: nil, automaticallyOpensVault: true)
    model.start(); await model.finishPendingOperations()
    model.navigate(to: .snippets); model.ensureSelection(query: "")
    model.editSelection(); await model.finishPendingOperations()
    model.draftBody = "Synthetic unsaved edits"
    model.onConfirmDiscardDraft = { false }
    model.moveSelection(1, query: "")
    #expect(model.selectedID == first.id && model.draftBody == "Synthetic unsaved edits")
    model.onConfirmDiscardDraft = { true }
    model.compactShowDetail = false
    model.moveSelection(1, query: "")
    #expect(model.selectedID == second.id && !model.isCreatingSnippet)
    #expect(!model.compactShowDetail) // Arrows highlight results; selecting a row opens compact detail.
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

@MainActor @Test func sensitiveEditAndSensitivityChangeEachRequireAuthenticationAndHideOnDeactivate() async throws {
    let record = try sensitiveRecord()
    let vault = TestVault(records: [record])
    let model = DesktopModel(service: vault, clipboard: TestClipboard())
    model.section = .snippets
    model.start(); await model.finishPendingOperations(); await model.unlock()?.value
    model.editSelection(); await model.finishPendingOperations()
    #expect(await vault.authenticationCalls == 1)
    #expect(model.editingSnippet?.id == record.id && !model.draftIsConcealed)
    model.draftSensitive = false
    model.setPresentationActive(false)
    #expect(model.draftIsConcealed)
    model.setPresentationActive(true)
    model.resumeSensitiveDraft(); await model.finishPendingOperations()
    #expect(await vault.authenticationCalls == 2)
    model.draftBody = "Synthetic revised text"
    model.saveDraft(); await model.finishPendingOperations()
    #expect(await vault.authenticationCalls == 3)
    guard case .snippet(let stored) = model.selectedRecord?.payload else { Issue.record("Missing saved edit"); return }
    #expect(stored.id == record.id && !stored.isSensitive && stored.body == "Synthetic revised text")
}

@MainActor @Test func cardTemplateIsSensitiveAndPromotionCreatesIndependentSnippet() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let record = try VaultRecord(.history(HistoryItem(text: "  Synthetic promoted text\n", firstSeenAt: date, lastSeenAt: date)))
    let vault = TestVault(records: [record])
    let model = DesktopModel(service: vault, clipboard: TestClipboard())
    model.start(); await model.finishPendingOperations(); await model.unlock()?.value
    model.promoteSelection(); model.draftName = "Synthetic snippet"
    model.saveDraft(); await model.finishPendingOperations()
    #expect(model.records.contains { $0.id == record.id })
    guard case .snippet(let snippet) = model.selectedRecord?.payload else { Issue.record("Missing promotion"); return }
    #expect(snippet.id != record.id && snippet.body == "  Synthetic promoted text\n")
    model.beginSnippet(template: .card)
    #expect(model.draftSensitive && model.draftCategory == "Card")
    #expect(!model.draftBody.contains("CVV") && !model.draftBody.contains("PIN"))
    model.lock(); await model.finishPendingOperations()
    #expect(model.draftBody.isEmpty && model.editingSnippet == nil)
}

@MainActor @Test func unicodeSearchPreservesExactCopyAndExcludesSensitiveBodies() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let record = try VaultRecord(.snippet(Snippet(name: "Café", body: "  naïve\n東京  ", createdAt: date, updatedAt: date)))
    let vault = TestVault(records: [record, try sensitiveRecord()])
    let model = DesktopModel(service: vault, clipboard: TestClipboard())
    model.section = .snippets
    model.start(); await model.finishPendingOperations(); await model.unlock()?.value
    #expect(model.items(query: "CAFÉ").count == 1)
    #expect(model.items(query: "東京").first?.id == record.id)
    #expect(model.items(query: "private body").isEmpty)
    model.selectedID = record.id
    model.copySelection(); await model.finishPendingOperations()
    guard case .snippet(let copied) = model.selectedRecord?.payload else { Issue.record("Missing record"); return }
    #expect(copied.body == "  naïve\n東京  " && copied.lastCopiedAt != nil)
}

@MainActor @Test func sensitiveDraftCopyAuthenticatesAndCancelledCutDoesNotMutate() async throws {
    let vault = TestVault(records: [try sensitiveRecord()])
    let clipboard = TestClipboard()
    let model = DesktopModel(service: vault, clipboard: clipboard)
    model.section = .snippets
    model.start(); await model.finishPendingOperations(); await model.unlock()?.value
    model.editSelection(); await model.finishPendingOperations()
    var cuts = 0
    model.copyDraftText("Synthetic selection") { cuts += 1 }
    await model.finishPendingOperations()
    #expect(await vault.authenticationCalls == 2 && clipboard.copies == 1 && cuts == 1)
    model.setPresentationActive(false); model.setPresentationActive(true)
    model.copyDraftText("Synthetic selection") { cuts += 1 }
    await model.finishPendingOperations()
    #expect(clipboard.copies == 1 && cuts == 1)
}

@MainActor @Test func cancellingDraftReplacementPreservesUnsavedText() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let record = try VaultRecord(.history(HistoryItem(text: "Synthetic history", firstSeenAt: date, lastSeenAt: date)))
    let model = DesktopModel(service: TestVault(records: [record]), clipboard: TestClipboard())
    model.start(); await model.finishPendingOperations(); await model.unlock()?.value
    model.beginSnippet(); model.draftBody = "Synthetic draft"
    model.onConfirmDiscardDraft = { false }
    model.promoteSelection()
    #expect(model.draftBody == "Synthetic draft")
    #expect(!model.beginSnippet(template: .card))
    #expect(model.draftBody == "Synthetic draft")
}

@MainActor @Test func cancelledDraftCopyNeverInvokesCutCompletion() async throws {
    let vault = TestVault(authenticationFailure: .cancelled)
    let clipboard = TestClipboard()
    let model = DesktopModel(service: vault, clipboard: clipboard)
    model.start(); await model.finishPendingOperations(); await model.unlock()?.value
    model.beginSnippet(template: .card)
    var cuts = 0
    model.copyDraftText("Synthetic selection") { cuts += 1 }
    await model.finishPendingOperations()
    #expect(cuts == 0 && clipboard.copies == 0)
    #expect(model.notice == nil)
}


@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["COPYSAVER_BENCHMARKS"] == "1"))
func representativeSearchBenchmark() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    var records: [VaultRecord] = []
    for index in 0..<5_000 {
        let instant = date.addingTimeInterval(Double(index))
        records.append(try VaultRecord(.history(HistoryItem(text: "Synthetic entry \(index): café, 東京, reusable text and exact whitespace.  ", firstSeenAt: instant, lastSeenAt: instant))))
    }
    for index in 0..<2_000 {
        records.append(try VaultRecord(.snippet(Snippet(name: String(format: "Synthetic %04d", index), body: "Synthetic body café 東京", isSensitive: index % 5 == 0, createdAt: date, updatedAt: date))))
    }
    let model = DesktopModel(service: TestVault(records: records), clipboard: nil)
    model.start(); await model.finishPendingOperations(); await model.unlock()?.value
    var times: [Double] = []
    var navigationTimes: [Double] = []
    let clock = ContinuousClock()
    for index in 0..<80 {
        model.section = index % 2 == 0 ? .history : .snippets
        let query = ["synthetic", "CAFÉ", "東京", "absent"][index % 4]
        let start = clock.now
        let matches = model.items(query: query)
        let elapsed = start.duration(to: clock.now).components
        times.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
        #expect(matches.count <= (model.section == .history ? 5_000 : 2_000))
        model.libraryQuery = query
        model.ensureSelection(query: query)
        let navigationStart = clock.now
        for _ in 0..<10 {
            model.moveSelection(1, query: query)
            #expect((model.selectedRecord != nil) == !matches.isEmpty)
        }
        let navigation = navigationStart.duration(to: clock.now).components
        navigationTimes.append((Double(navigation.seconds) * 1_000 + Double(navigation.attoseconds) / 1e15) / 10)
    }
    times.sort()
    print(String(format: "BENCH search records=7000 samples=80 p50_ms=%.2f p95_ms=%.2f", times[40], times[75]))
    navigationTimes.sort()
    print(String(format: "BENCH selection records=7000 samples=80 steps=10 p50_ms=%.3f p95_ms=%.3f", navigationTimes[40], navigationTimes[75]))
}

private struct BenchmarkKeys: VaultKeyProvider {
    let key: SymmetricKey
    func loadKey(for vaultID: UUID) async throws -> SymmetricKey { key }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COPYSAVER_BENCHMARKS"] == "1"))
func nearBudgetVaultBenchmark() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("copysaver-benchmark-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let key = SymmetricKey(size: .bits256)
    let vault = try VaultSession.create(at: directory.appendingPathComponent("vault.sqlite"), key: key)
    let access = try await vault.unlock(using: BenchmarkKeys(key: key))
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let filler = String(repeating: "x", count: RecordLimits.maximumTextBytes - 32)
    let records = try (0..<490).map { index in
        try VaultRecord(.history(HistoryItem(text: "Synthetic \(index) " + filler, firstSeenAt: date, lastSeenAt: date)))
    }
    let clock = ContinuousClock(); let start = clock.now
    try await vault.apply(saving: records, access: access)
    let commit = start.duration(to: clock.now).components
    let readStart = clock.now
    let loaded = try await vault.records(access: access)
    let read = readStart.duration(to: clock.now).components
    #expect(loaded.count == 490)
    let original = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    let preserved = loaded.allSatisfy { record in
        guard case .history(let a) = record.payload, case .history(let b) = original[record.id]?.payload else { return false }
        return a.text.utf8.elementsEqual(b.text.utf8)
    }
    #expect(preserved)
    print(String(format: "BENCH vault records=490 approximate_plaintext_mib=122.5 commit_ms=%.2f read_ms=%.2f", Double(commit.seconds) * 1_000 + Double(commit.attoseconds) / 1e15, Double(read.seconds) * 1_000 + Double(read.attoseconds) / 1e15))
    try await vault.close()
}


@MainActor @Test func cancelledFreshCopyConcealsAnExistingReveal() async throws {
    let vault = TestVault(records: [try sensitiveRecord()])
    let clipboard = TestClipboard()
    let model = DesktopModel(service: vault, clipboard: clipboard)
    model.section = .snippets
    model.start(); await model.finishPendingOperations(); await model.unlock()?.value
    model.revealSelection(); await model.finishPendingOperations()
    #expect(model.revealedID != nil)
    await vault.failAuthentication(.cancelled)
    model.copySelection(); await model.finishPendingOperations()
    #expect(model.revealedID == nil && clipboard.copies == 0)
}

@MainActor @Test func cleanupReviewPausesAdmissionWithoutChangingManualPreference() async throws {
    let settings = try VaultRecord(.settings(VaultSettings(captureEnabled: true)))
    let model = DesktopModel(service: TestVault(records: [settings]), clipboard: TestClipboard())
    model.start(); await model.finishPendingOperations(); await model.unlock()?.value
    model.clipboardPermission = .allowed
    #expect(model.captureConditions.canCapture)
    model.setCleanupReview(true)
    #expect(!model.captureConditions.canCapture && model.settings?.manuallyPaused == false)
    model.setCleanupReview(false)
    #expect(model.captureConditions.canCapture)
    model.setCleanupReview(true); model.lock(); await model.finishPendingOperations()
    #expect(!model.reviewingCleanup && model.records.isEmpty)
}

@MainActor @Test func copyDismissesOnlyAfterSuccessfulWriteAndMetadataCommit() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let record = try VaultRecord(.history(HistoryItem(text: "Synthetic copy", firstSeenAt: date, lastSeenAt: date)))
    let clipboard = TestClipboard()
    let model = DesktopModel(service: TestVault(records: [record]), clipboard: clipboard)
    model.start(); await model.finishPendingOperations(); await model.unlock()?.value
    var dismissals = 0
    model.onDismissFocus = { dismissals += 1 }
    model.copySelection(dismissFocus: true); await model.finishPendingOperations()
    #expect(dismissals == 1 && clipboard.copies == 1)
    clipboard.shouldFail = true
    model.copySelection(dismissFocus: true); await model.finishPendingOperations()
    #expect(dismissals == 1 && model.notice == nil)
}

@MainActor @Test func draftNavigationPreservesExactEditsSelectionAndLatestCopyMetadata() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let a = try VaultRecord(.snippet(Snippet(name: "Zulu synthetic", body: "é", createdAt: date, updatedAt: date)))
    let b = try VaultRecord(.snippet(Snippet(name: "Alpha synthetic", body: "Other", createdAt: date, updatedAt: date)))
    let model = DesktopModel(service: TestVault(records: [a, b]), clipboard: TestClipboard())
    model.section = .snippets
    model.start(); await model.finishPendingOperations(); await model.unlock()?.value
    model.selectedID = a.id
    model.editSelection(); await model.finishPendingOperations()
    #expect(!model.hasDirtyDraft)
    model.draftBody = "e\u{301}"
    #expect(model.hasDirtyDraft)
    model.onConfirmDiscardDraft = { false }
    #expect(!model.selectRecord(b.id))
    #expect(model.editingSnippet?.id == a.id && model.selectedID == a.id)
    model.navigate(to: .history); model.ensureSelection(query: "")
    model.navigate(to: .snippets); model.ensureSelection(query: "")
    #expect(model.selectedID == a.id)
    model.copySelection(); await model.finishPendingOperations()
    model.saveDraft(); await model.finishPendingOperations()
    guard case .snippet(let saved) = model.selectedRecord?.payload else { Issue.record("Missing saved draft"); return }
    #expect(saved.body.utf8.elementsEqual("e\u{301}".utf8) && saved.lastCopiedAt != nil)
    model.editSelection(); await model.finishPendingOperations()
    var prompts = 0
    model.onConfirmDiscardDraft = { prompts += 1; return false }
    #expect(model.selectRecord(b.id))
    #expect(prompts == 0 && model.editingSnippet == nil)
}

@MainActor @Test func contentPreviewFollowsEditsSensitivityDeletionAndSession() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let record = try VaultRecord(.snippet(Snippet(name: "Synthetic link", body: "https://example.com/private?token=synthetic", createdAt: date, updatedAt: date)))
    let clipboard = TestClipboard()
    let model = DesktopModel(service: TestVault(records: [record]), clipboard: clipboard, automaticallyOpensVault: true)
    model.start(); await model.finishPendingOperations()
    model.navigate(to: .snippets); model.selectRecord(record.id)
    #expect(model.preview(for: record).label == "Link")
    _ = model.preview(for: record) // Cache hit must still observe record replacement.
    let changed = OSAllocatedUnfairLock(initialState: false)
    withObservationTracking { _ = model.preview(for: record) } onChange: { changed.withLock { $0 = true } }
    model.editSelection(); await model.finishPendingOperations()
    model.draftBody = "  {\"value\":9007199254740993}\n"
    model.saveDraft(); await model.finishPendingOperations()
    #expect(changed.withLock { $0 })
    #expect(model.preview(for: record).label == "JSON") // Stale view snapshot uses current body.
    model.copySelection(); await model.finishPendingOperations()
    #expect(clipboard.lastText == "  {\"value\":9007199254740993}\n")
    model.editSelection(); await model.finishPendingOperations()
    model.draftSensitive = true
    model.saveDraft(); await model.finishPendingOperations()
    #expect(model.preview(for: record) == .text)
    #expect(model.items(query: "9007199254740993").isEmpty)
    model.revealSelection(); await model.finishPendingOperations()
    #expect(model.preview(for: record) == .text) // Reveal remains literal, never an analyzed preview.
    model.lock(); await model.finishPendingOperations()
    #expect(model.preview(for: record) == .text && model.selectedRecord == nil)
    await model.unlock()?.value
    model.navigate(to: .snippets); model.selectRecord(record.id)
    #expect(model.preview(for: record) == .text)
    model.deleteSelection(); await model.finishPendingOperations()
    #expect(model.preview(for: record) == .text && model.items(query: "").isEmpty)
}

@MainActor @Test func contentPreviewNeverChangesExactCopyAcrossTypes() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let values = ["  https://example.com/a?token=synthetic#part\n", "hello@example.com", "+1 (202) 555-0100", "```swift\nlet café = 1\n```", "  {\"name\":\"日本語\",\"value\":1.2300e+03}  "]
    for text in values {
        let record = try VaultRecord(.history(HistoryItem(text: text, firstSeenAt: date, lastSeenAt: date)))
        let clipboard = TestClipboard()
        let model = DesktopModel(service: TestVault(records: [record]), clipboard: clipboard, automaticallyOpensVault: true)
        model.start(); await model.finishPendingOperations()
        #expect(model.preview(for: record) != .text)
        model.selectRecord(record.id)
        model.copySelection(); await model.finishPendingOperations()
        #expect(clipboard.lastText?.utf8.elementsEqual(text.utf8) == true)
    }
}
