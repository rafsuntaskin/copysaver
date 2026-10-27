import SwiftUI
import AppKit
import CopySaverDomain

struct FocusView: View {
    @Bindable var model: DesktopModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if model.phase == .unlocked {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search clipboard…", text: $model.focusQuery)
                        .textFieldStyle(.plain).font(.system(size: 19)).focused($searchFocused)
                        .accessibilityLabel("Search clipboard and snippets")
                        .onSubmit { model.copySelection(dismissFocus: true) }
                        .onKeyPress(.downArrow) { model.moveSelection(1, query: model.focusQuery); return .handled }
                        .onKeyPress(.upArrow) { model.moveSelection(-1, query: model.focusQuery); return .handled }
                    Text("esc").font(.system(size: 10)).foregroundStyle(.secondary).padding(5).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }.padding(22)
                HStack {
                    Picker("View", selection: $model.section) {
                        Text("History").tag(LibrarySection.history)
                        Text("Snippets").tag(LibrarySection.snippets)
                    }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("History or snippets").frame(width: 220)
                    Spacer()
                    Label(model.captureStatus, systemImage: model.isPreview ? "eye" : "pause.circle")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.horizontal, 22).padding(.bottom, 16)
                Divider()
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(model.items(query: model.focusQuery)) { record in
                            RecordRow(record: record, selected: record.id == model.selectedID) { model.selectRecord(record.id) }.id(record.id)
                        }
                        if model.items(query: model.focusQuery).isEmpty {
                            Text(model.focusQuery.isEmpty ? "No saved text in this view yet." : "No matches. Try another search.")
                                .font(.system(size: 13)).foregroundStyle(.secondary).padding(30)
                        }
                    }.padding(10)
                }
                .onChange(of: model.selectedID) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
                }
                FeedbackView(model: model).padding(.horizontal, 20)
                Divider()
                HStack(spacing: 15) {
                    Label("Navigate", systemImage: "arrow.up.arrow.down")
                    Button { model.copySelection() } label: { Label("Copy", systemImage: "return") }
                        .buttonStyle(.plain).keyboardShortcut("c", modifiers: .command).disabled(!model.canCopy)
                    Spacer()
                    Button("Open Library") {
                        model.libraryQuery = model.focusQuery
                        model.onOpenLibrary?()
                    }.buttonStyle(.plain)
                    Button { model.lock() } label: { Image(systemName: "lock") }.buttonStyle(.plain).help("Lock vault")
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(17)
            } else {
                VaultGateView(model: model)
                HStack { Spacer(); Button("Open Library") { model.onOpenLibrary?() }.buttonStyle(.plain) }.padding(16)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 640, height: 520)
        .task(id: model.focusActivation) {
            searchFocused = false
            await Task.yield()
            searchFocused = true
        }
        .onChange(of: model.phase) { _, phase in searchFocused = phase == .unlocked }
        .onChange(of: model.focusQuery) { _, query in model.ensureSelection(query: query) }
        .onChange(of: model.section) { _, _ in model.ensureSelection(query: model.focusQuery) }
        .onExitCommand { model.onDismissFocus?() }
    }
}

private struct AppearanceSettings: View {
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        Picker("Appearance", selection: $appearance) {
            Text("System").tag("system")
            Text("Light").tag("light")
            Text("Dark").tag("dark")
        }.pickerStyle(.segmented).frame(maxWidth: 320)
    }
}

struct SettingsView: View {
    @Bindable var model: DesktopModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Settings").font(.system(size: 22, weight: .semibold))
                FeedbackView(model: model)
                VStack(alignment: .leading, spacing: 12) {
                    Text("General").font(.headline)
                    AppearanceSettings()
                    LoginSettingsView(preview: model.isPreview)
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Focus Mode Shortcut").font(.headline)
                    Text("Open quick access while working in another app.").foregroundStyle(.secondary)
                    HStack {
                        Button(model.recordingShortcut ? "Press a shortcut. Esc to cancel." : "Record shortcut: \(model.shortcutDescription)") { model.onRecordShortcut?() }
                        Button("Restore default") { model.onRestoreShortcut?() }.disabled(model.recordingShortcut)
                        Button("Clear") { model.onClearShortcut?() }.disabled(model.recordingShortcut)
                    }
                    if let message = model.shortcutMessage { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.secondary) }
                }
                Divider()
                HistorySettingsView(model: model)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Privacy & Security").font(.headline)
                    Text("Stored content is encrypted locally. Locking pauses capture and clears decrypted content from the interface.")
                    Text("Portable encrypted backup is not available yet. Keep another copy of important information.").foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sidebar & desktop widget").font(.headline)
                    Text("In a build with the widget extension, open Notification Center, choose Edit Widgets, search for CopySaver, and add the small or medium launcher. Drag a widget to the desktop if you prefer. Widgets contain navigation only; saved text stays inside the app.").foregroundStyle(.secondary)
                    Divider()
                    Text("About CopySaver").font(.headline)
                    Text("Development build · local storage · MIT license").foregroundStyle(.secondary)
                }
            }.font(.system(size: 13)).padding(.top, 60).padding(.horizontal, 36).padding(.bottom, 36).frame(maxWidth: 660, alignment: .leading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AppearanceRoot<Content: View>: View {
    @AppStorage("appearance") private var appearance = "system"
    let content: Content
    var body: some View { content.preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil) }
}

private struct HistorySettingsView: View {
    @Bindable var model: DesktopModel
    @State private var count = 1_000
    @State private var days = 30
    @State private var timeout = IdleLockTimeout.fifteenMinutes
    @State private var excluded = ""
    @State private var proposed: VaultSettings?
    @State private var removalCount = 0
    @State private var confirmLimits = false
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("History").font(.headline)
            if let settings = model.settings {
                Toggle("Keep clipboard history", isOn: Binding(get: { settings.captureEnabled }, set: { model.setCaptureEnabled($0) }))
                    .disabled(model.isPreview || model.isBusy)
                Text("Capture pauses while locked. Copies made before enabling or resuming are skipped.").foregroundStyle(.secondary)
                HStack {
                    Label(model.captureStatus, systemImage: model.captureConditions.canCapture ? "record.circle" : "pause.circle")
                    if settings.captureEnabled {
                        Button(settings.manuallyPaused ? "Resume" : "Pause") { model.toggleCapturePause() }.disabled(model.isBusy || model.isPreview)
                    }
                    if !model.storageWritable { Button("Retry storage") { model.retryStorage() }.disabled(model.isBusy) }
                }
                if settings.captureEnabled && model.clipboardPermission != .allowed && !model.isPreview {
                    Text("macOS needs clipboard permission. Request access, then choose Always Allow for CopySaver in System Settings → Privacy & Security → Paste from Other Apps. Request access inspects the current clipboard only to show the system prompt; that value is discarded.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Request clipboard access") { model.onRequestClipboardAccess?() }
                        Button("Open System Settings") { NSWorkspace.shared.open(URL(filePath: "/System/Applications/System Settings.app")) }
                    }
                }
                Stepper("Keep up to \(count) items", value: $count, in: 100...5_000, step: 100)
                Picker("Expire unpinned history", selection: $days) {
                    ForEach([1, 7, 30, 90], id: \.self) { Text("\($0) days").tag($0) }
                }.frame(maxWidth: 320)
                Picker("Lock after inactivity", selection: $timeout) {
                    Text("5 minutes").tag(IdleLockTimeout.fiveMinutes)
                    Text("15 minutes").tag(IdleLockTimeout.fifteenMinutes)
                    Text("30 minutes").tag(IdleLockTimeout.thirtyMinutes)
                    Text("System lock only").tag(IdleLockTimeout.systemLockOnly)
                }.frame(maxWidth: 320)
                Text("Excluded applications").fontWeight(.medium)
                Text("One bundle identifier per line. Browser exclusions cover every window, including private windows. Attribution and secret detection are best effort.").foregroundStyle(.secondary)
                TextEditor(text: $excluded).font(.system(size: 12, design: .monospaced)).frame(height: 70)
                    .border(Color(nsColor: .separatorColor)).accessibilityLabel("Excluded application bundle identifiers")
                ForEach(installedManagers, id: \.id) { manager in
                    Button("Add \(manager.name) to exclusions") {
                        let current = Set(excluded.split(whereSeparator: \.isNewline).map(String.init))
                        excluded = current.union([manager.id]).sorted().joined(separator: "\n")
                    }.disabled(model.isPreview)
                }
                HStack {
                    Button("Apply history settings") { proposeSettings(settings) }.disabled(model.isBusy || model.isPreview)
                    Button("Clear history…", role: .destructive) { confirmClear = true }.disabled(model.isBusy || model.isPreview)
                }
            } else { Text("Unlock the vault to change history preferences.").foregroundStyle(.secondary) }
            Text("Concealed and transient copies are always skipped. Private-key and card-number filters can miss secrets; explicitly save private text as a sensitive snippet.").foregroundStyle(.secondary)
        }
        .task { load() }
        .onChange(of: model.settings) { _, _ in load() }
        .confirmationDialog("Remove \(removalCount) history items?", isPresented: $confirmLimits, titleVisibility: .visible) {
            Button("Apply limits and remove history", role: .destructive) { model.setCleanupReview(false); if let proposed { model.saveSettings(proposed, confirmed: true) }; proposed = nil }
            Button("Cancel", role: .cancel) { model.setCleanupReview(false); proposed = nil }
        } message: { Text("Pinned items and snippets are kept. Removed history cannot be restored.") }
        .onChange(of: confirmLimits) { _, shown in if !shown { model.setCleanupReview(false) } }
        .confirmationDialog("Clear all clipboard history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { model.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes all history, including pinned items. Named snippets are kept. This cannot be undone.") }
    }
    private func load() {
        guard let settings = model.settings else { return }
        count = settings.historyCountLimit; days = settings.retentionDays; timeout = settings.idleLockTimeout
        excluded = settings.excludedBundleIDs.sorted().joined(separator: "\n")
    }
    private var installedManagers: [(id: String, name: String)] {
        [("com.1password.1password", "1Password"), ("com.agilebits.onepassword7", "1Password 7"),
         ("com.bitwarden.desktop", "Bitwarden"), ("org.keepassxc.keepassxc", "KeePassXC")].compactMap { id, name in
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil,
                  !excluded.split(whereSeparator: \.isNewline).contains(Substring(id)) else { return nil }
            return (id, name)
        }
    }
    private func proposeSettings(_ current: VaultSettings) {
        let ids = Set(excluded.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        guard let next = try? current.updating(historyCountLimit: count, retentionDays: days, excludedBundleIDs: ids, idleLockTimeout: timeout) else { return }
        let verification = try? VaultRecord(.verification(VaultVerification(vaultID: UUID())))
        let overhead = verification.flatMap { try? RecordCodec.encode($0).count } ?? 512
        var planned = model.records.filter { if case .settings = $0.payload { return false }; return true }
        if let record = try? VaultRecord(.settings(next)) { planned.append(record) }
        if let retained = try? HistoryPolicy.fit(HistoryPolicy.retain(planned, settings: next, now: Date()), settings: next, budget: RecordLimits.maximumPayloadBytes - overhead - 28), retained.count < planned.count {
            model.setCleanupReview(true)
            proposed = next; removalCount = planned.count - retained.count; confirmLimits = true
        } else { model.saveSettings(next) }
    }
}
