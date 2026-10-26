import CopySaverDomain
import CopySaverPlatform
import CopySaverVault
import Foundation
import Observation

public enum LibrarySection: String, CaseIterable, Identifiable, Sendable {
    case history = "History", snippets = "Snippets", pinned = "Pinned", settings = "Settings"
    public var id: String { rawValue }
    public var symbol: String {
        switch self { case .history: "clock"; case .snippets: "doc.text"; case .pinned: "pin"; case .settings: "gearshape" }
    }
}

public enum DesktopPhase: Equatable, Sendable { case loading, needsSetup, locked, unlocking, locking, unlocked, failed }

@MainActor @Observable public final class DesktopModel {
    public private(set) var phase: DesktopPhase = .loading
    public private(set) var records: [VaultRecord] = []
    public private(set) var isBusy = false
    public private(set) var errorMessage: String?
    public private(set) var notice: String?
    public let isPreview: Bool
    public var section: LibrarySection = .history
    public var libraryQuery = ""
    public var focusQuery = ""
    public var selectedID: UUID? { didSet { if selectedID != oldValue { concealSensitiveContent() } } }
    public var isCreatingSnippet = false
    public var draftName = ""
    public var draftBody = ""
    public var draftSensitive = false
    public var draftCategory = ""
    public private(set) var editingSnippet: Snippet?
    public private(set) var draftAuthorized = true
    public var compactShowDetail = false
    public var isFocusPresented = false
    public var onConfirmDiscardDraft: (() -> Bool)?
    public private(set) var revealedID: UUID?
    public var onOpenLibrary: (() -> Void)?
    public var onOpenFocus: (() -> Void)?
    public var onDismissFocus: (() -> Void)?
    public var shortcutDescription = "⌥⌘V"
    public var shortcutMessage: String?
    public var recordingShortcut = false
    public var clipboardPermission: ClipboardPermission = .unknown
    public private(set) var storageWritable = true
    public var onCaptureBoundary: (() -> Void)?
    public var onRequestClipboardAccess: (() -> Void)?
    public var focusActivation = UUID()
    public private(set) var presentationActive = true
    public var onRecordShortcut: (() -> Void)?
    public var onRestoreShortcut: (() -> Void)?
    public var onClearShortcut: (() -> Void)?

    @ObservationIgnored private let service: (any DesktopVaultAccess)?
    @ObservationIgnored private let clipboard: (any ClipboardOutput)?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var revealExpiry: Task<Void, Never>?
    @ObservationIgnored private var lockingOperation: Task<Void, Never>?
    @ObservationIgnored private var sensitivePresentation = UUID()

    func finishPendingOperations() async {
        await operation?.value
        await lockingOperation?.value
    }

    public init(service: (any DesktopVaultAccess)?, clipboard: (any ClipboardOutput)?, preview: Bool = false) {
        self.service = preview ? nil : service
        self.clipboard = preview ? nil : clipboard
        self.isPreview = preview
        if preview {
            #if DEBUG
            records = Self.previewRecords()
            phase = .unlocked
            selectedID = records.first?.id
            #else
            phase = .failed
            errorMessage = "Sample-data preview is available only in development builds."
            #endif
        }
    }

    public var selectedRecord: VaultRecord? {
        guard phase == .unlocked else { return nil }
        return items(query: isFocusPresented ? focusQuery : libraryQuery).first { $0.id == selectedID }
    }
    public var hasDirtyDraft: Bool { isCreatingSnippet && (!draftName.isEmpty || !draftBody.isEmpty) }
    public var draftNeedsAuthentication: Bool { isCreatingSnippet && (draftSensitive || editingSnippet?.isSensitive == true) && !draftAuthorized }
    public func navigate(to section: LibrarySection) { self.section = section; libraryQuery = ""; compactShowDetail = false }
    public func selectRecord(_ id: UUID) {
        if hasDirtyDraft && selectedID != id {
            guard onConfirmDiscardDraft?() == true else { return }
            discardDraft()
        }
        selectedID = id; compactShowDetail = true
    }

    public var canCopy: Bool { phase == .unlocked && selectedRecord != nil && !isBusy && !isPreview }
    public var settings: VaultSettings? { phase == .unlocked && !isPreview ? try? HistoryPolicy.settings(in: records) : nil }
    public var captureConditions: CaptureConditions {
        CaptureConditions(vaultUnlocked: phase == .unlocked, captureEnabled: settings?.captureEnabled ?? false,
                          manuallyPaused: settings?.manuallyPaused ?? false, clipboardPermission: clipboardPermission, storageWritable: storageWritable)
    }
    public var captureStatus: String {
        if isPreview { return "Sample data" }
        switch captureConditions.availability {
        case .locked: return "Locked"
        case .disabled: return "History off"
        case .paused: return "Paused"
        case .permissionNeeded: return "Clipboard permission needed"
        case .storageUnavailable: return "Storage error"
        case .ready: return "Capturing"
        }
    }

    public func setCaptureEnabled(_ enabled: Bool) {
        guard let settings, let next = try? settings.updating(captureEnabled: enabled) else { return }
        saveSettings(next)
    }
    public func toggleCapturePause() {
        guard let settings, let next = try? settings.updating(manuallyPaused: !settings.manuallyPaused) else { return }
        saveSettings(next)
    }
    public func saveSettings(_ value: VaultSettings, confirmed: Bool = false) {
        guard !isPreview, phase == .unlocked, !isBusy, let service else { return }
        onCaptureBoundary?()
        run(fallback: .unlocked, work: { try await service.updateSettings(value, confirmed: confirmed) }) { [weak self] records in
            self?.records = records
            self?.onCaptureBoundary?()
            self?.notice = "Settings saved"
        }
    }
    public func capture(_ sample: ClipboardSample) {
        guard !isPreview, captureConditions.canCapture, !isBusy, let service else { return }
        run(fallback: .unlocked, work: { try await service.capture(sample) }) { [weak self] records in
            self?.records = records
            self?.ensureSelection(query: self?.isFocusPresented == true ? self?.focusQuery ?? "" : self?.libraryQuery ?? "")
        }
    }
    public func cleanupHistory(now: Date = Date()) {
        guard !isPreview, phase == .unlocked, !isBusy, let service else { return }
        run(fallback: .unlocked, work: { try await service.cleanup(now: now) }) { [weak self] records in
            self?.records = records
            self?.ensureSelection(query: self?.isFocusPresented == true ? self?.focusQuery ?? "" : self?.libraryQuery ?? "")
        }
    }
    public func retryStorage() { storageWritable = true; cleanupHistory(); onCaptureBoundary?() }
    public func clearHistory() {
        guard !isPreview, phase == .unlocked, !isBusy, let service else { return }
        run(fallback: .unlocked, work: { try await service.clearHistory() }) { [weak self] records in
            self?.records = records; self?.ensureSelection(query: self?.isFocusPresented == true ? self?.focusQuery ?? "" : self?.libraryQuery ?? "")
            self?.notice = "History cleared. Snippets kept."
        }
    }

    public func items(query: String, section explicitSection: LibrarySection? = nil) -> [VaultRecord] {
        guard phase == .unlocked else { return [] }
        let selectedSection = explicitSection ?? section
        return records.filter { record in
            let searchable: String
            switch record.payload {
            case .history(let item):
                guard selectedSection == .history || (selectedSection == .pinned && item.isPinned) else { return false }
                searchable = item.text
            case .snippet(let item):
                guard selectedSection == .snippets else { return false }
                searchable = item.name + "\n" + (item.category ?? "") + (item.isSensitive ? "" : "\n" + item.body)
            default: return false
            }
            return query.isEmpty || searchable.localizedStandardContains(query)
        }.sorted { lhs, rhs in
            if case .history(let left) = lhs.payload, case .history(let right) = rhs.payload {
                return left.lastSeenAt > right.lastSeenAt
            }
            return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
        }
    }

    public func ensureSelection(query: String) {
        let visible = items(query: query)
        if !visible.contains(where: { $0.id == selectedID }) { selectedID = visible.first?.id }
    }

    public func moveSelection(_ delta: Int, query: String) {
        let visible = items(query: query)
        guard !visible.isEmpty else { return }
        let index = visible.firstIndex { $0.id == selectedID } ?? 0
        selectedID = visible[min(max(index + delta, 0), visible.count - 1)].id
    }

    public func start() {
        guard !isPreview else { return }
        guard (phase == .loading || phase == .failed), !isBusy else { return }
        guard let service else {
            phase = .failed
            errorMessage = "Launch the CopySaver app bundle to configure its protected vault."
            return
        }
        phase = .loading
        run(fallback: .failed, work: { try await service.prepare() }) { [weak self] exists in
            self?.phase = exists ? .locked : .needsSetup
        }
    }

    public func createVault() {
        guard !isPreview, phase == .needsSetup, !isBusy, let service else { return }
        run(fallback: .failed, work: { try await service.create() }) { [weak self] _ in
            self?.phase = .locked
            self?.notice = "Vault created. Unlock to continue."
        }
    }

    @discardableResult public func unlock() -> Task<Void, Never>? {
        guard !isPreview, phase == .locked, let service else { return nil }
        phase = .unlocking
        run(fallback: .locked, work: { try await service.unlock() }) { [weak self] records in
            self?.records = records
            self?.phase = .unlocked
            self?.storageWritable = true
            self?.ensureSelection(query: "")
            self?.onCaptureBoundary?()
        }
        return operation
    }

    public func lock() {
        onCaptureBoundary?()
        generation = UUID()
        operation?.cancel()
        operation = nil
        records = []
        selectedID = nil
        libraryQuery = ""
        focusQuery = ""
        discardDraft()
        concealSensitiveContent()
        clipboard?.clearOwnedSensitiveCopy()
        errorMessage = nil
        notice = nil
        isBusy = false
        if isPreview { phase = .locked; return }
        phase = .locking
        let request = generation
        lockingOperation = Task { [weak self, service] in
            await service?.lock()
            guard let self, self.generation == request else { return }
            self.phase = .locked
        }
    }

    @discardableResult public func beginSnippet(template: SnippetTemplate = .general) -> Bool {
        guard phase == .unlocked, !isPreview, !isBusy else { return false }
        if hasDirtyDraft && onConfirmDiscardDraft?() != true { return false }
        discardDraft()
        section = .snippets
        isCreatingSnippet = true
        compactShowDetail = true
        draftCategory = template.rawValue
        draftBody = template.body
        draftSensitive = template.sensitive
        return true
    }

    public func editSelection() {
        guard !isPreview, !isBusy, let service, case .snippet(let snippet) = selectedRecord?.payload else { return }
        if hasDirtyDraft && onConfirmDiscardDraft?() != true { return }
        let presentation = sensitivePresentation
        run(fallback: .unlocked, work: {
            if snippet.isSensitive { try await service.authenticateSensitiveAccess() }
            return snippet
        }) { [weak self] snippet in
            guard let self, self.selectedRecord?.id == snippet.id,
                  !snippet.isSensitive || (self.presentationActive && self.sensitivePresentation == presentation) else { return }
            self.discardDraft()
            self.editingSnippet = snippet
            self.draftName = snippet.name; self.draftBody = snippet.body
            self.draftCategory = snippet.category ?? ""; self.draftSensitive = snippet.isSensitive
            self.draftAuthorized = true; self.isCreatingSnippet = true; self.compactShowDetail = true
        }
    }

    public func resumeSensitiveDraft() {
        guard !isPreview, draftNeedsAuthentication, !isBusy, let service else { return }
        let presentation = sensitivePresentation
        run(fallback: .unlocked, work: { try await service.authenticateSensitiveAccess() }) { [weak self] _ in
            guard let self, self.presentationActive, self.sensitivePresentation == presentation, self.isCreatingSnippet else { return }
            self.draftAuthorized = true
        }
    }

    public func promoteSelection() {
        guard case .history(let item) = selectedRecord?.payload, !isPreview, !isBusy else { return }
        guard beginSnippet() else { return }
        draftBody = item.text
    }

    public func toggleSelectedPin() {
        guard !isPreview, !isBusy, let service, case .history(let item) = selectedRecord?.payload,
              let updated = try? item.settingPinned(!item.isPinned), let record = try? VaultRecord(.history(updated)) else { return }
        run(fallback: .unlocked, work: { try await service.save(record) }) { [weak self] records in self?.records = records; self?.ensureSelection(query: self?.libraryQuery ?? "") }
    }

    public func discardDraft() {
        draftName = ""
        draftBody = ""
        draftSensitive = false
        draftCategory = ""
        editingSnippet = nil
        draftAuthorized = true
        isCreatingSnippet = false
    }

    public func saveDraft() {
        guard phase == .unlocked, !isPreview, !isBusy, !draftNeedsAuthentication, let service else { return }
        do {
            let now = Date()
            let original = editingSnippet
            let snippet = try Snippet(id: original?.id ?? UUID(), name: draftName, body: draftBody, category: draftCategory,
                                      isSensitive: draftSensitive, createdAt: original?.createdAt ?? now,
                                      updatedAt: max(original?.updatedAt ?? now, now), lastCopiedAt: original?.lastCopiedAt)
            let record = try VaultRecord(.snippet(snippet))
            let presentation = sensitivePresentation
            run(fallback: .unlocked, work: { [weak self] in
                if original?.isSensitive == true {
                    try await service.authenticateSensitiveAccess()
                    let admitted = await MainActor.run { self?.sensitivePresentation == presentation && self?.presentationActive == true }
                    guard admitted else { throw CancellationError() }
                }
                return try await service.save(record)
            }) { [weak self] records in
                self?.records = records
                self?.discardDraft()
                self?.selectedID = record.id
                self?.notice = "Snippet saved"
            }
        } catch { errorMessage = Self.message(for: error) }
    }

    public func deleteSelection() {
        guard phase == .unlocked, !isPreview, !isBusy, let service, let id = selectedID else { return }
        run(fallback: .unlocked, work: { try await service.delete(id) }) { [weak self] records in
            self?.records = records
            if self?.editingSnippet?.id == id { self?.discardDraft() }
            self?.ensureSelection(query: self?.isFocusPresented == true ? self?.focusQuery ?? "" : self?.libraryQuery ?? "")
        }
    }

    public func revealSelection() {
        guard !isPreview, !isBusy, let service, let record = selectedRecord, record.isSensitive else { return }
        let presentation = sensitivePresentation
        run(fallback: .unlocked, work: { try await service.authenticateSensitiveAccess() }) { [weak self] _ in
            guard let self, self.selectedID == record.id, self.sensitivePresentation == presentation, self.presentationActive else { return }
            self.revealedID = record.id
            self.revealExpiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.concealSensitiveContent()
            }
        }
    }

    public func concealSensitiveContent() {
        sensitivePresentation = UUID()
        revealedID = nil
        revealExpiry?.cancel()
        revealExpiry = nil
        if draftSensitive || editingSnippet?.isSensitive == true { draftAuthorized = false }
    }

    public func setPresentationActive(_ active: Bool) {
        presentationActive = active
        if !active { concealSensitiveContent() }
    }

    public func resetPreview() {
        #if DEBUG
        guard isPreview else { return }
        records = Self.previewRecords()
        phase = .unlocked
        ensureSelection(query: "")
        #endif
    }

    public func copySelection(dismissFocus: Bool = false, selectedText: String? = nil) {
        guard canCopy, let service, let record = selectedRecord, selectedText == nil || !record.isSensitive else { return }
        let presentation = sensitivePresentation
        let request = generation
        operation?.cancel(); isBusy = true; notice = nil; errorMessage = nil
        operation = Task { [weak self] in
            var copied = false
            do {
                if record.isSensitive { try await service.authenticateSensitiveAccess() }
                guard let self, self.generation == request, !Task.isCancelled,
                      self.selectedRecord?.id == record.id, let clipboard = self.clipboard,
                      !record.isSensitive || (self.presentationActive && self.sensitivePresentation == presentation) else {
                    if let self, self.generation == request { self.isBusy = false }; return
                }
                try clipboard.copy(selectedText ?? record.content, sensitive: record.isSensitive)
                copied = true
                let updated = try await service.markCopied(record.id, date: Date())
                guard self.generation == request, !Task.isCancelled else { return }
                self.records = updated
                self.isBusy = false
                self.notice = "Copied"
                if dismissFocus { self.onDismissFocus?() }
            } catch {
                guard let self, self.generation == request, !Task.isCancelled else { return }
                self.isBusy = false
                if error as? VaultError == .storageFailure { self.storageWritable = false; self.onCaptureBoundary?() }
                if copied { self.notice = "Copied"; self.errorMessage = "Copied, but the last-copy time could not be saved." }
                else if error as? KeychainFailure != .cancelled, !(error is CancellationError) {
                    self.errorMessage = error is ClipboardFailure ? "Copy failed. Please try again." : Self.message(for: error)
                }
            }
        }
    }

    public func copyDraftText(_ text: String, onSuccess: @escaping @MainActor () -> Void) {
        guard !isPreview, !isBusy, phase == .unlocked, isCreatingSnippet, !draftNeedsAuthentication,
              text.utf8.count <= RecordLimits.maximumTextBytes, let service, let clipboard else { return }
        let sensitive = draftSensitive || editingSnippet?.isSensitive == true
        let presentation = sensitivePresentation
        run(fallback: .unlocked, work: {
            if sensitive { try await service.authenticateSensitiveAccess() }
        }) { [weak self] _ in
            guard let self, self.isCreatingSnippet,
                  !sensitive || (self.presentationActive && self.sensitivePresentation == presentation) else { return }
            do {
                try clipboard.copy(text, sensitive: sensitive)
                self.notice = "Copied"
                onSuccess()
            } catch { self.errorMessage = "Copy failed. Please try again." }
        }
    }

    public func resetVault() {
        guard !isPreview, !isBusy, let service else { return }
        lock()
        let locking = lockingOperation
        run(fallback: .locked, work: { await locking?.value; try await service.reset() }) { [weak self] _ in
            self?.phase = .needsSetup
            self?.storageWritable = true
            self?.notice = "Vault reset. Create a new vault to continue."
        }
    }

    public func detailText(for record: VaultRecord) -> String {
        record.isSensitive && revealedID != record.id ? "Sensitive content" : record.content
    }

    private func run<T: Sendable>(
        fallback: DesktopPhase, work: @escaping @Sendable () async throws -> T,
        apply: @escaping @MainActor (T) -> Void
    ) {
        operation?.cancel()
        let request = generation
        isBusy = true
        errorMessage = nil
        notice = nil
        operation = Task { [weak self] in
            do {
                let value = try await work()
                guard let self, self.generation == request, !Task.isCancelled else { return }
                self.isBusy = false
                apply(value)
            } catch {
                guard let self, self.generation == request, !Task.isCancelled else { return }
                self.isBusy = false
                self.phase = fallback
                if error as? VaultError == .storageFailure { self.storageWritable = false; self.onCaptureBoundary?() }
                if error as? VaultError == .corruptDatabase || error as? VaultError == .authenticationFailed {
                    self.lock()
                }
                if !(error is CancellationError), error as? KeychainFailure != .cancelled {
                    self.errorMessage = Self.message(for: error)
                }
            }
        }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case RecordValidationError.invalidName: "Enter a name with 1–120 characters."
        case RecordValidationError.invalidCategory: "Use a category with at most 60 characters."
        case HistoryFailure.historyLimitReached: "History limit reached. Unpin or delete an item to capture more."
        case HistoryFailure.pinnedLimitConflict: "Unpin history items before lowering this limit."
        case HistoryFailure.snippetLimitReached: "The 2,000-snippet limit has been reached."
        case HistoryFailure.storageCapacity: "Storage is full. Delete history or snippets and try again."
        case HistoryFailure.confirmationRequired: "Review and confirm the history cleanup before changing these limits."
        case RecordValidationError.emptyText: "Enter some text to save."
        case RecordValidationError.textTooLarge: "This text exceeds the 256 KiB limit."
        case KeychainFailure.missingEntitlement: "macOS Keychain requires a correctly development-signed build of CopySaver."
        case KeychainFailure.missingKey: "This vault’s encryption key is missing. The saved files have been preserved."
        case KeychainFailure.authenticationFailed: "Authentication failed. Please unlock again."
        case KeychainFailure.interactionRequired: "Unlock your Mac and try again."
        case VaultError.payloadBudgetExceeded: "The encrypted storage limit has been reached."
        case VaultError.unsupportedDatabaseVersion, VaultError.unsupportedEnvelopeVersion: "This vault needs a compatible version of CopySaver."
        case VaultError.authenticationFailed, VaultError.corruptDatabase, VaultError.invalidRecord: "This vault could not be verified. Its saved files have been preserved."
        default: "The operation could not be completed. Your saved files have been preserved."
        }
    }

    #if DEBUG
    private static func previewRecords() -> [VaultRecord] {
        let now = Date()
        var result: [VaultRecord] = []
        let examples = [
            ("Let’s keep the first release focused.", "Notes"),
            ("https://developer.apple.com/swift/", "Safari"),
            ("Shipping address\n123 Example Street", "Mail"),
            ("npm run build", "Terminal"),
            ("Please send the updated estimate.", "Mail"),
            ("Design review notes\nRefine onboarding copy\nUpdate empty states", "Notes"),
        ]
        for (index, example) in examples.enumerated() {
            let date = now.addingTimeInterval(-Double(index) * 180)
            if let item = try? HistoryItem(text: example.0, firstSeenAt: date, lastSeenAt: date, sourceName: example.1, isPinned: index == 1),
               let record = try? VaultRecord(.history(item)) { result.append(record) }
        }
        for (name, body, sensitive) in [
            ("Home address", "Alex Morgan\n123 Example Street\nPortland, OR 97205", false),
            ("Work signature", "Alex Morgan\nExample Studio", false),
            ("Travel card", "Synthetic confidential sample", true),
        ] {
            if let snippet = try? Snippet(name: name, body: body, isSensitive: sensitive, createdAt: now, updatedAt: now),
               let record = try? VaultRecord(.snippet(snippet)) { result.append(record) }
        }
        return result
    }
    #endif
}

extension VaultRecord {
    var displayTitle: String {
        switch payload {
        case .history(let item): String(item.text.prefix(160)).components(separatedBy: .newlines).first ?? "Text"
        case .snippet(let item): item.name
        default: ""
        }
    }
    var subtitle: String {
        switch payload { case .history(let item): item.sourceName ?? "Unknown source"; case .snippet(let item): item.category ?? "General"; default: "" }
    }
    var content: String {
        switch payload { case .history(let item): item.text; case .snippet(let item): item.body; default: "" }
    }
    var isSensitive: Bool { if case .snippet(let value) = payload { value.isSensitive } else { false } }
    var symbol: String {
        switch payload {
        case .snippet: "doc.text"
        case .history(let item): item.sourceName == "Safari" ? "globe" : item.sourceName == "Terminal" ? "terminal" : "text.alignleft"
        default: "doc"
        }
    }
}
