import CopySaverDomain
import SwiftUI

struct LibraryView: View {
    @Bindable var model: DesktopModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 205)
            Divider()
            if model.phase == .unlocked {
                if model.section == .settings {
                    SettingsView(model: model)
                } else {
                    itemList.frame(width: 320)
                    Divider()
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VaultGateView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 840, minHeight: 540)
        .onChange(of: model.libraryQuery) { _, query in model.ensureSelection(query: query) }
        .onChange(of: model.section) { _, _ in model.ensureSelection(query: model.libraryQuery) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("CopySaver", systemImage: "clipboard")
                .font(.system(size: 17, weight: .semibold)).padding(.bottom, 26).padding(.horizontal, 12)
            ForEach([LibrarySection.history, .snippets, .pinned]) { section in
                Button {
                    model.section = section
                } label: {
                    Label(section.rawValue, systemImage: section.symbol)
                        .font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(model.section == section ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(model.section == section ? .isSelected : [])
            }
            Spacer()
            Divider().padding(.bottom, 10)
            Label(model.captureStatus, systemImage: model.isPreview ? "eye" : "lock.shield")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 8)
            Button { model.onOpenFocus?() } label: {
                Label("Focus mode", systemImage: "rectangle.center.inset.filled").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).padding(12)
            Button { model.section = .settings } label: {
                Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).padding(12).disabled(model.phase != .unlocked)
            Button { model.lock() } label: {
                Label("Lock vault", systemImage: "lock").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).padding(12).disabled(model.phase != .unlocked)
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
                    Button { model.beginSnippet() } label: { Image(systemName: "plus") }
                        .help("New snippet").disabled(model.isPreview || model.isBusy)
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
                        RecordRow(record: record, selected: record.id == model.selectedID) { model.selectedID = record.id }
                            .contextMenu {
                                Button("Copy") { model.selectedID = record.id; model.copySelection() }.disabled(model.isPreview)
                                Button("Delete", role: .destructive) { model.selectedID = record.id; model.deleteSelection() }.disabled(model.isPreview || model.isBusy)
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
                    if record.isSensitive { Image(systemName: "lock").foregroundStyle(.secondary).accessibilityLabel("Sensitive snippet") }
                }.padding(.top, 58).padding(.bottom, 28)
                if case .snippet = record.payload { Text(verbatim: record.displayTitle).font(.title2.weight(.semibold)).padding(.bottom, 20) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if record.isSensitive {
                            Text(verbatim: model.detailText(for: record)).font(.system(size: 14, design: .monospaced))
                                .accessibilityLabel(model.revealedID == record.id ? record.content : "Sensitive content, concealed")
                            if model.revealedID == record.id {
                                Button("Hide content") { model.concealSensitiveContent() }
                            } else {
                                Button("Reveal for 30 seconds") { model.revealSelection() }.disabled(model.isPreview || model.isBusy)
                            }
                        } else {
                            Text(verbatim: record.content).font(.system(size: 14, design: .monospaced)).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 24)
                Label(record.subtitle, systemImage: record.symbol).font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 16)
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
                Text(model.libraryQuery.isEmpty ? (model.section == .snippets ? "Give reusable text a name so it’s easy to find." : "Enable clipboard history in Settings to keep future copies, or create a named snippet.") : "Try a different word or clear your search.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
                if !model.isPreview {
                    Button("New snippet") { model.beginSnippet() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
                }
                FeedbackView(model: model)
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        if case .history(let item) = record.payload { Text("·"); Text(item.lastSeenAt, style: .relative) }
                    }.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if record.isSensitive { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 12).padding(.vertical, 15).frame(maxWidth: .infinity)
                .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct VaultGateView: View {
    @Bindable var model: DesktopModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: model.phase == .needsSetup ? "checkmark.shield" : "lock").font(.system(size: 34)).foregroundStyle(.secondary)
            Text(model.phase == .needsSetup ? "A private home for your text" : model.phase == .failed ? "Vault unavailable" : "Your vault is locked")
                .font(.system(size: 21, weight: .semibold))
            Text(model.phase == .needsSetup ? "History and named snippets, stored locally with a key protected by macOS Keychain." : "Unlock with Touch ID or your Mac’s login password.")
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
                Button("Unlock vault") { model.unlock() }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            } else {
                Button("Retry") { model.start() }.buttonStyle(.bordered)
            }
            FeedbackView(model: model)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Text("New snippet").font(.title2.weight(.semibold)).padding(.top, 54)
            LabeledContent("Name") { TextField("For example, Home address", text: $model.draftName).textFieldStyle(.roundedBorder) }
            Text("Text").font(.system(size: 13, weight: .medium))
            TextEditor(text: $model.draftBody).font(.system(size: 13, design: .monospaced))
                .accessibilityLabel("Snippet text").border(Color(nsColor: .separatorColor), width: 1)
            Toggle("Sensitive: authenticate before reveal or copy", isOn: $model.draftSensitive).font(.system(size: 12))
            FeedbackView(model: model)
            HStack {
                Button("Cancel") { model.discardDraft() }.disabled(model.isBusy)
                Spacer()
                Button("Save snippet") { model.saveDraft() }.buttonStyle(.borderedProminent).disabled(model.isBusy)
            }.padding(.bottom, 24)
        }.padding(.horizontal, 24)
    }
}
