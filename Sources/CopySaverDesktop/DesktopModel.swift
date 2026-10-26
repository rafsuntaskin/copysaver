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
    public private(set) var revealedID: UUID?
    public var onOpenLibrary: (() -> Void)?
    public var onOpenFocus: (() -> Void)?
    public var onDismissFocus: (() -> Void)?
    public var shortcutDescription = "⌥⌘V"
    public var shortcutMessage: String?
    public var recordingShortcut = false
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
        return records.first { $0.id == selectedID }
    }

    public var canCopy: Bool { phase == .unlocked && selectedRecord != nil && !isBusy && !isPreview }

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
            self?.ensureSelection(query: "")
        }
        return operation
    }

    public func lock() {
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

    public func beginSnippet() {
        guard phase == .unlocked, !isPreview, !isBusy else { return }
        discardDraft()
        section = .snippets
        isCreatingSnippet = true
    }

    public func discardDraft() {
        draftName = ""
        draftBody = ""
        draftSensitive = false
        isCreatingSnippet = false
    }

    public func saveDraft() {
        guard phase == .unlocked, !isPreview, !isBusy, let service else { return }
        do {
            let now = Date()
            let snippet = try Snippet(name: draftName, body: draftBody, isSensitive: draftSensitive, createdAt: now, updatedAt: now)
            let record = try VaultRecord(.snippet(snippet))
            run(fallback: .unlocked, work: { try await service.save(record) }) { [weak self] records in
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
            self?.ensureSelection(query: self?.libraryQuery ?? "")
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

    public func copySelection(dismissFocus: Bool = false) {
        guard canCopy, let service, let record = selectedRecord else { return }
        let presentation = sensitivePresentation
        run(fallback: .unlocked, work: {
            if record.isSensitive { try await service.authenticateSensitiveAccess() }
            return record
        }) { [weak self] record in
            guard let self, self.selectedID == record.id, let clipboard = self.clipboard,
                  !record.isSensitive || (self.presentationActive && self.sensitivePresentation == presentation) else { return }
            do {
                try clipboard.copy(record.content, sensitive: record.isSensitive)
                self.notice = "Copied"
                if dismissFocus { self.onDismissFocus?() }
            } catch { self.errorMessage = "Copy failed. Please try again." }
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
