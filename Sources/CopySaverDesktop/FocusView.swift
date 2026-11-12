import SwiftUI
import AppKit
import CopySaverDomain

struct FocusView: View {
    @Bindable var model: DesktopModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if model.phase == .unlocked {
                let visible = model.items(query: model.focusQuery)
                VStack(spacing: 14) {
                    LibrarySearchField(text: $model.focusQuery,
                                       prompt: model.section == .snippets ? "Search snippets…" : "Search clipboard…",
                                       focus: $searchFocused, prominent: true, hint: "esc",
                                       submit: { model.copySelection(dismissFocus: true) },
                                       move: { model.moveSelection($0, query: model.focusQuery) })
                    HStack {
                        Picker("View", selection: $model.section) {
                            Text("History").tag(LibrarySection.history)
                            Text("Snippets").tag(LibrarySection.snippets)
                        }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("History or snippets").frame(width: 190)
                        Spacer()
                        CaptureStatusView(model: model)
                    }
                }.padding(18)
                Divider()
                HStack {
                    Text(model.focusQuery.isEmpty ? (model.section == .snippets ? "YOUR SNIPPETS" : "RECENT") : "RESULTS")
                        .font(.system(size: 10, weight: .semibold)).tracking(0.7)
                    Spacer()
                    Text("\(visible.count)").font(.system(size: 11)).monospacedDigit()
                }.foregroundStyle(.secondary).padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 6)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(visible) { record in
                                RecordRow(record: record, preview: model.preview(for: record), selected: record.id == model.selectedID, compact: true) { model.selectRecord(record.id) }.id(record.id)
                            }
                        }.padding(.horizontal, 10).padding(.bottom, 8)
                    }
                    .overlay {
                        if visible.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "magnifyingglass").font(.system(size: 23))
                                Text(model.focusQuery.isEmpty ? "No saved text in this view yet." : "No matching text").font(.system(size: 13))
                                if !model.focusQuery.isEmpty { Button("Clear search") { model.focusQuery = "" }.buttonStyle(.bordered) }
                            }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .onChange(of: model.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
                FeedbackView(model: model).padding(.horizontal, 20)
                Divider()
                HStack(spacing: 12) {
                    HStack(spacing: 6) { KeyboardHint("↑↓"); Text("Navigate") }
                        .font(.system(size: 11)).foregroundStyle(.secondary).accessibilityLabel("Navigate results with the up and down arrows")
                    Spacer(minLength: 4)
                    Button {
                        model.libraryQuery = model.focusQuery
                        model.onOpenLibrary?()
                    } label: { Label("Library", systemImage: "arrow.up.right.square") }.help("Open Library").accessibilityLabel("Open Library")
                    Button { model.copySelection() } label: { HStack(spacing: 6) { Text("Copy"); KeyboardHint("⌘C") } }
                        .keyboardShortcut("c", modifiers: .command).disabled(!model.canCopy)
                    Button { model.copySelection(dismissFocus: true) } label: {
                        HStack(spacing: 8) { Text("Copy & close"); Image(systemName: "return").accessibilityHidden(true) }
                    }.buttonStyle(.borderedProminent).disabled(!model.canCopy)
                    Button { model.lock() } label: { Image(systemName: model.lockActionSymbol) }
                        .help(model.lockActionTitle).accessibilityLabel(model.lockActionTitle)
                }.buttonStyle(.bordered).controlSize(.small).font(.system(size: 12)).padding(.horizontal, 18).padding(.vertical, 13)
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
    var applicationSuggestions: [(id: String, name: String)]? = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Settings").font(.system(size: 22, weight: .semibold))
                FeedbackView(model: model)
                VStack(alignment: .leading, spacing: 12) {
                    Text("General").font(.headline)
                    AppearanceSettings()
                    LoginSettingsView(preview: model.isPreview, automaticallyOpensVault: model.automaticallyOpensVault)
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
                HistorySettingsView(model: model, applicationSuggestions: applicationSuggestions)
                Divider()
                LibraryPrivacySection(model: model)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sidebar & desktop widget").font(.headline)
                    Text("In a build with the widget extension, open Notification Center, choose Edit Widgets, search for CopySaver, and add the small or medium launcher. Drag a widget to the desktop if you prefer. Widgets contain navigation only; saved text stays inside the app.").foregroundStyle(.secondary)
                    Divider()
                    Text("About CopySaver").font(.headline)
                    Text(versionLabel).foregroundStyle(.secondary)
                    Text("\(model.automaticallyOpensVault ? "Automatic library" : "Protected library") · local storage · MIT license").foregroundStyle(.secondary)
                }
            }.font(.system(size: 13)).padding(.top, 48).padding(.horizontal, 36).padding(.bottom, 36).frame(maxWidth: 660, alignment: .leading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var versionLabel: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return "Development preview" }
        return "Version \(version) (\(build))"
    }
}

struct LibraryPrivacySection: View {
    var model: DesktopModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy & Storage").font(.headline)
            Label("Encrypted on this Mac", systemImage: "externaldrive.badge.checkmark")
            Text(model.automaticallyOpensVault ? "Your library opens automatically with your user session. Hide and pause clears the interface and stops capture until you reopen it." : "Locking pauses capture and clears decrypted content from the interface.").foregroundStyle(.secondary)
            if model.automaticallyOpensVault {
                Text("Sensitive snippets hide their text in previews and search. Choose Show text or Edit snippet when you need the body.").foregroundStyle(.secondary)
            }
            if model.settings != nil {
                Toggle("Load website previews automatically", isOn: Binding(get: { model.websitePreviewsEnabled }, set: { model.setWebsitePreviewsEnabled($0) }))
                    .disabled(model.isBusy || model.isPreview)
                Text("The selected non-sensitive link contacts its website and image host to load a title, description and image. These sites receive your IP and requested URL. Sensitive snippets are never fetched. Preview data stays in memory.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("Portable encrypted backup is not available yet. Keep another copy of important information.").foregroundStyle(.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }
}

struct AppearanceRoot<Content: View>: View {
    @AppStorage("appearance") private var appearance = "system"
    @State private var windowIsKey = false
    let content: Content
    var body: some View {
        content.preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .environment(\.copySaverWindowIsKey, windowIsKey)
            .background { WindowKeyObserver(isKey: $windowIsKey).frame(width: 0, height: 0) }
    }
}

private struct HistorySettingsView: View {
    @Bindable var model: DesktopModel
    var applicationSuggestions: [(id: String, name: String)]? = nil
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
                Text(model.automaticallyOpensVault ? "Capture starts when the app opens and resumes after sleep. Pause and History off are remembered. Copies made before starting or resuming are skipped." : "Capture pauses while locked. Copies made before enabling or resuming are skipped.").foregroundStyle(.secondary)
                HStack {
                    CaptureStatusView(model: model)
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
                if !model.automaticallyOpensVault {
                    Picker("Lock after inactivity", selection: $timeout) {
                        Text("5 minutes").tag(IdleLockTimeout.fiveMinutes)
                        Text("15 minutes").tag(IdleLockTimeout.fifteenMinutes)
                        Text("30 minutes").tag(IdleLockTimeout.thirtyMinutes)
                        Text("System lock only").tag(IdleLockTimeout.systemLockOnly)
                    }.frame(maxWidth: 320)
                }
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
            } else { Text(model.automaticallyOpensVault ? "Open your library to change history preferences." : "Unlock the vault to change history preferences.").foregroundStyle(.secondary) }
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
        if let applicationSuggestions {
            let existing = Set(excluded.split(whereSeparator: \.isNewline).map(String.init))
            return applicationSuggestions.filter { !existing.contains($0.id) }
        }
        return [("com.1password.1password", "1Password"), ("com.agilebits.onepassword7", "1Password 7"),
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
