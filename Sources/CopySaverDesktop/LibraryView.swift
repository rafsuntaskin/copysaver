import AppKit
import CopySaverDomain
import SwiftUI

struct LibraryView: View {
    @Bindable var model: DesktopModel
    /// Nil discovers installed apps; render fixtures inject a synthetic list.
    var applicationSuggestions: [(id: String, name: String)]? = nil

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width < 850 {
                VStack(spacing: 0) {
                    HStack {
                        if model.compactShowDetail && model.section != .settings {
                            Button { model.compactShowDetail = false; model.concealSensitiveContent() } label: { Label("Back", systemImage: "chevron.left") }
                        }
                        Picker("Library", selection: $model.section) {
                            ForEach(LibrarySection.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().accessibilityLabel("Library section")
                        Button { model.onOpenFocus?() } label: { Image(systemName: "magnifyingglass") }.help("Open Focus mode")
                        Button { model.lock() } label: { Image(systemName: model.lockActionSymbol) }.help(model.lockActionTitle)
                    }.padding(.horizontal, 18).padding(.top, 40).padding(.bottom, 12)
                    Divider()
                    if model.phase != .unlocked { VaultGateView(model: model) }
                    else if model.section == .settings { SettingsView(model: model, applicationSuggestions: applicationSuggestions) }
                    else if model.compactShowDetail { detail }
                    else { itemList }
                }
            } else { wideLayout }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 480, minHeight: 540)
        .onChange(of: model.libraryQuery) { _, query in model.ensureSelection(query: query) }
        .onChange(of: model.section) { _, _ in model.ensureSelection(query: model.libraryQuery); model.compactShowDetail = false }
    }

    private var wideLayout: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            Divider()
            if model.phase == .unlocked {
                if model.section == .settings {
                    SettingsView(model: model, applicationSuggestions: applicationSuggestions)
                } else {
                    itemList.frame(width: 320)
                    Divider()
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VaultGateView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 5) {
                Label("CopySaver", systemImage: "clipboard").font(.system(size: 17, weight: .semibold))
                Text("Clipboard & snippets").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.bottom, 24)
            ForEach([LibrarySection.history, .snippets, .pinned]) { section in
                Button {
                    model.navigate(to: section)
                } label: {
                    SidebarRowLabel(title: section.rawValue, symbol: section.symbol)
                }.buttonStyle(SidebarButtonStyle(selected: model.phase == .unlocked && model.section == section))
                    .disabled(model.phase != .unlocked)
                    .accessibilityAddTraits(model.phase == .unlocked && model.section == section ? .isSelected : [])
            }
            Spacer()
            Divider().padding(.bottom, 12)
            HStack {
                CaptureStatusView(model: model)
                Spacer(minLength: 4)
                if !model.isPreview, model.phase == .unlocked, model.settings?.captureEnabled == true {
                    Button { model.toggleCapturePause() } label: {
                        Image(systemName: model.settings?.manuallyPaused == true ? "play.fill" : "pause.fill")
                    }.buttonStyle(.borderless).controlSize(.small).disabled(model.isBusy)
                        .help(model.settings?.manuallyPaused == true ? "Resume capture" : "Pause capture")
                        .accessibilityLabel(model.settings?.manuallyPaused == true ? "Resume capture" : "Pause capture")
                }
            }.padding(.horizontal, 12).padding(.bottom, 12)
            Button { model.onOpenFocus?() } label: {
                SidebarRowLabel(title: "Focus mode", symbol: "magnifyingglass", shortcut: model.shortcutDescription)
            }.buttonStyle(SidebarButtonStyle()).help("Open Focus mode: \(model.shortcutDescription)")
            Button { model.navigate(to: .settings) } label: {
                SidebarRowLabel(title: "Settings", symbol: "gearshape")
            }.buttonStyle(SidebarButtonStyle(selected: model.phase == .unlocked && model.section == .settings)).disabled(model.phase != .unlocked)
                .accessibilityAddTraits(model.phase == .unlocked && model.section == .settings ? .isSelected : [])
            Button { model.lock() } label: {
                SidebarRowLabel(title: model.lockActionTitle, symbol: model.lockActionSymbol)
            }.buttonStyle(SidebarButtonStyle()).disabled(model.phase != .unlocked)
            Text("Encrypted on this Mac").font(.system(size: 10)).foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.top, 9)
        }
        .padding(.horizontal, 12).padding(.top, 54).padding(.bottom, 16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var itemList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.section.rawValue).font(.system(size: 18, weight: .semibold))
                TextField("Search", text: $model.libraryQuery)
                    .font(.system(size: 12)).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search \(model.section.rawValue)")
                if model.section == .snippets {
                    Menu {
                        ForEach(SnippetTemplate.allCases) { template in Button("New \(template.rawValue.lowercased()) snippet") { model.beginSnippet(template: template) } }
                    } label: { Image(systemName: "plus") }.help("New snippet").disabled(model.isPreview || model.isBusy)
                }
            }.padding(.horizontal, 16).padding(.top, 48).padding(.bottom, 20)
            Divider()
            ScrollView {
                LazyVStack(spacing: 3) {
                    if model.isPreview {
                        Text("SAMPLE DATA").font(.system(size: 10, weight: .medium)).tracking(1)
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 14)
                    }
                    ForEach(model.items(query: model.libraryQuery)) { record in
                        RecordRow(record: record, selected: record.id == model.selectedID) { model.selectRecord(record.id) }
                            .contextMenu {
                                Button("Copy") { if model.selectRecord(record.id) { model.copySelection() } }.disabled(model.isPreview)
                                Button("Delete", role: .destructive) { if model.selectRecord(record.id) { model.deleteSelection() } }.disabled(model.isPreview || model.isBusy)
                            }
                    }
                }.padding(8)
            }
            Divider()
            HStack {
                Text(model.isPreview ? "UI preview only" : "Encrypted locally").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }.padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder private var detail: some View {
        if model.isCreatingSnippet && model.section == .snippets {
            SnippetEditorView(model: model)
        } else if let record = model.selectedRecord {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(record.isSensitive ? "SENSITIVE SNIPPET" : "PLAIN TEXT")
                        .font(.system(size: 11, weight: .medium)).tracking(1).foregroundStyle(.secondary)
                    Spacer()
                    if record.isSensitive { Image(systemName: model.requiresSensitiveAuthentication ? "lock" : "eye.slash").foregroundStyle(.secondary).accessibilityLabel("Sensitive snippet") }
                }.padding(.top, 58).padding(.bottom, 28)
                if case .snippet = record.payload { Text(verbatim: record.displayTitle).font(.title2.weight(.semibold)).padding(.bottom, 20) }
                HStack {
                    if case .history(let item) = record.payload {
                        Button(item.isPinned ? "Unpin" : "Pin") { model.toggleSelectedPin() }
                        Button("Save as snippet") { model.promoteSelection() }
                    } else { Button("Edit snippet") { model.editSelection() } }
                    Spacer()
                    Button("Delete", role: .destructive) { model.deleteSelection() }
                }.font(.system(size: 12)).padding(.bottom, 18).disabled(model.isPreview || model.isBusy)
                if record.isSensitive {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(verbatim: model.detailText(for: record)).font(.system(size: 14, design: .monospaced))
                                .accessibilityLabel(model.revealedID == record.id ? record.content : "Sensitive content, concealed")
                            if model.revealedID == record.id {
                                Button("Hide text") { model.concealSensitiveContent() }
                            } else {
                                Button("Show text") { model.revealSelection() }.disabled(model.isPreview || model.isBusy)
                                Text("Hidden again after 30 seconds or when you leave the app.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VaultTextEditor(text: .constant(record.content), editable: false, accessibilityName: "Saved text") { text, _ in
                        model.copySelection(selectedText: text)
                    }
                }
                Spacer(minLength: 24)
                Label(record.subtitle, systemImage: record.symbol).font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 16)
                if case .history(let value) = record.payload {
                    Text("Captured \(value.firstSeenAt.formatted(date: .abbreviated, time: .shortened)) · seen \(value.repeatCount) \(value.repeatCount == 1 ? "time" : "times")")
                        .font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
                    if let date = value.lastCopiedAt { Text("Last copied \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary).padding(.bottom, 6) }
                }
                FeedbackView(model: model)
                Divider()
                HStack {
                    Label(model.isPreview ? "Sample data only" : "Encrypted locally", systemImage: model.isPreview ? "eye" : "checkmark.shield")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.copySelection() } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut("c", modifiers: .command).disabled(!model.canCopy)
                }.padding(.vertical, 18)
            }.padding(.horizontal, 24)
        } else {
            VStack(spacing: 14) {
                Image(systemName: model.section == .snippets ? "doc.text" : "clipboard").font(.system(size: 30)).foregroundStyle(.secondary)
                Text(model.libraryQuery.isEmpty ? (model.section == .snippets ? "Save something you use often" : "Your clipboard history starts here") : "No matches")
                    .font(.system(size: 19, weight: .semibold))
                Text(model.libraryQuery.isEmpty ? (model.section == .snippets ? "Give reusable text a name so it’s easy to find." : historyEmptyDescription) : "Try a different word or clear your search.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
                if !model.isPreview, model.libraryQuery.isEmpty, model.section == .history || model.section == .pinned {
                    if model.settings?.captureEnabled != true {
                        Button("Enable history") { model.setCaptureEnabled(true) }.disabled(model.isBusy)
                    } else if model.settings?.manuallyPaused == true {
                        Button("Resume capture") { model.toggleCapturePause() }.disabled(model.isBusy)
                    } else if model.clipboardPermission != .allowed {
                        if model.clipboardPermission != .denied {
                            Button("Request clipboard access") { model.onRequestClipboardAccess?() }.disabled(model.isBusy)
                        }
                        Button("Open System Settings") { NSWorkspace.shared.open(URL(filePath: "/System/Applications/System Settings.app")) }
                        Text("Choose Always Allow for CopySaver in Privacy & Security → Paste from Other Apps. The access request discards the current clipboard value.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
                    }
                }
                if !model.isPreview {
                    Button("New snippet") { model.beginSnippet() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
                }
                FeedbackView(model: model)
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var historyEmptyDescription: String {
        switch model.captureConditions.availability {
        case .ready: "Copy text in another app to add it here. Earlier clipboard contents are skipped."
        case .permissionNeeded: "Allow clipboard access to keep new copies automatically."
        case .paused: "Capture is paused. Resume when you want to keep new copies."
        case .disabled: "Enable clipboard history to keep future copies, or create a named snippet."
        case .storageUnavailable: "Resolve the storage error before capturing more copies."
        case .locked: "Open your library to continue."
        }
    }
}

struct RecordRow: View {
    let record: VaultRecord
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: record.symbol).font(.system(size: 18)).frame(width: 26, height: 30).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 7) {
                    Text(verbatim: record.displayTitle).font(.system(size: 13, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        Text(verbatim: record.subtitle)
                        if case .history(let item) = record.payload {
                            Text("·")
                            HistoryAgeLabel(date: item.lastSeenAt)
                        }
                    }.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if record.isSensitive { Image(systemName: "eye.slash").font(.system(size: 10)).foregroundStyle(.secondary).accessibilityLabel("Preview hidden") }
            }.padding(.horizontal, 12).padding(.vertical, 15).frame(maxWidth: .infinity)
                .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct HistoryAgeLabel: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(verbatim: label(relativeTo: context.date))
        }
    }

    private func label(relativeTo now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        guard elapsed >= 60 else { return String(localized: "Just now") }
        let age: DateComponents
        if elapsed < 3_600 {
            age = DateComponents(minute: -Int(elapsed / 60))
        } else if elapsed < 86_400 {
            age = DateComponents(hour: -Int(elapsed / 3_600))
        } else {
            age = DateComponents(day: -Int(elapsed / 86_400))
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(from: age)
    }
}

struct VaultGateView: View {
    @Bindable var model: DesktopModel
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: model.automaticallyOpensVault ? "eye.slash" : model.phase == .needsSetup ? "checkmark.shield" : "lock").font(.system(size: 34)).foregroundStyle(.secondary)
            Text(gateTitle)
                .font(.system(size: 21, weight: .semibold))
            Text(gateSubtitle)
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
            if model.phase == .needsSetup {
                Text("The key stays on this Mac. Losing it can make your saved data unrecoverable. Portable backup is not available yet.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
            }
            #if DEBUG
            if !model.isPreview {
                Text("Development build. Native security checks are still pending; use synthetic data.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
            }
            #endif
            if model.isBusy || model.phase == .loading || model.phase == .locking {
                ProgressView().controlSize(.small)
                if model.phase == .unlocking { Button("Cancel") { model.lock() } }
            } else if model.isPreview {
                Text("Sample-data preview").font(.caption).foregroundStyle(.secondary)
                Button("Reset sample preview") { model.resetPreview() }.buttonStyle(.borderedProminent)
            } else if model.phase == .needsSetup {
                Button("Create encrypted vault") { model.createVault() }.buttonStyle(.borderedProminent).controlSize(.large)
            } else if model.phase == .locked {
                Button(model.automaticallyOpensVault ? (model.errorMessage == nil ? "Open library" : "Try again") : "Unlock vault") { model.unlock() }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            } else {
                Button("Retry") { model.start() }.buttonStyle(.bordered)
            }
            FeedbackView(model: model)
            if !model.isPreview && !model.isBusy && model.phase == .locked {
                Button(model.automaticallyOpensVault ? "Reset library…" : "Reset vault…", role: .destructive) { confirmReset = true }.font(.caption)
            }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(model.automaticallyOpensVault ? "Permanently reset your library?" : "Permanently delete this vault and its key?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Delete history, snippets, and key", role: .destructive) { model.resetVault() }
            Button("Cancel", role: .cancel) {}
        } message: { Text(model.automaticallyOpensVault ? "All history and snippets will be permanently removed. There is no recovery or portable backup." : "All saved text will be lost. There is no recovery or portable backup. Authentication is required when the key is available; a missing key still allows this explicitly confirmed reset.") }
    }

    private var gateTitle: String {
        if model.automaticallyOpensVault {
            if model.isBusy || model.phase == .loading { return "Opening your library" }
            if model.phase == .locking { return "Hiding your library" }
            return model.errorMessage == nil ? "Library hidden" : "Library unavailable"
        }
        return model.phase == .needsSetup ? "A private home for your text" : model.phase == .failed ? "Vault unavailable" : "Your vault is locked"
    }

    private var gateSubtitle: String {
        if model.automaticallyOpensVault {
            if model.isBusy || model.phase == .loading { return "Preparing your saved text…" }
            if model.phase == .locking { return "Pausing capture and clearing previews…" }
            return model.errorMessage == nil ? "Your history and snippets are hidden. Open the library to continue." : "Saved files have been preserved. Address the error below, then try again."
        }
        return model.phase == .needsSetup ? "History and named snippets, stored locally with a key protected by macOS Keychain." : model.phase == .failed ? "Correct the problem below, then retry." : "Unlock with Touch ID or your Mac’s login password."
    }
}

struct FeedbackView: View {
    var model: DesktopModel
    var body: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true).accessibilityLabel("Error: \(error)").padding(.vertical, 8)
        } else if let notice = model.notice {
            Label(notice, systemImage: "checkmark.circle").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 8)
        }
    }
}

private struct SnippetEditorView: View {
    @Bindable var model: DesktopModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.editingSnippet == nil ? "New snippet" : "Edit snippet").font(.title2.weight(.semibold)).padding(.top, 54)
            if model.draftIsConcealed {
                Text("Draft hidden").foregroundStyle(.secondary)
                Button(model.requiresSensitiveAuthentication ? "Authenticate to continue editing" : "Continue editing") { model.resumeSensitiveDraft() }.disabled(model.isBusy)
                Button("Discard draft", role: .destructive) { model.discardDraft() }.disabled(model.isBusy)
                FeedbackView(model: model)
                Spacer()
            } else {
            LabeledContent("Name") { TextField("For example, Home address", text: $model.draftName).textFieldStyle(.roundedBorder) }
            LabeledContent("Category") { TextField("General, Address, Card…", text: $model.draftCategory).textFieldStyle(.roundedBorder) }
            Text("Text").font(.system(size: 13, weight: .medium))
            VaultTextEditor(text: $model.draftBody) { text, completion in model.copyDraftText(text, onSuccess: completion) }.disabled(model.isBusy)
                .accessibilityLabel("Snippet text").border(Color(nsColor: .separatorColor), width: 1)
            Toggle(model.requiresSensitiveAuthentication ? "Sensitive: authenticate before reveal or copy" : "Hide text in previews", isOn: $model.draftSensitive).font(.system(size: 12))
            if !model.requiresSensitiveAuthentication {
                Text("Hidden text stays out of body search. Sensitive copies are marked private and CopySaver attempts to clear them after 30 seconds.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            FeedbackView(model: model)
            HStack {
                Button("Cancel") { model.discardDraft() }.disabled(model.isBusy)
                Spacer()
                Button("Save snippet") { model.saveDraft() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
            }.padding(.bottom, 24)
            }
        }.padding(.horizontal, 24)
    }
}
