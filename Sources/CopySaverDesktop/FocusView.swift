import SwiftUI

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
                    Label(model.isPreview ? "Sample data" : "History off", systemImage: model.isPreview ? "eye" : "pause.circle")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.horizontal, 22).padding(.bottom, 16)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(model.items(query: model.focusQuery)) { record in
                            RecordRow(record: record, selected: record.id == model.selectedID) { model.selectedID = record.id }
                        }
                        if model.items(query: model.focusQuery).isEmpty {
                            Text(model.focusQuery.isEmpty ? "No saved text in this view yet." : "No matches. Try another search.")
                                .font(.system(size: 13)).foregroundStyle(.secondary).padding(30)
                        }
                    }.padding(10)
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("General").font(.headline)
                    AppearanceSettings()
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("Privacy & Security").font(.headline)
                    Text("Keys stay in macOS Keychain. Locking clears this window’s content. Clipboard history is not enabled in this development scaffold.")
                    Text("Portable encrypted backup is not available yet. Keep another copy of important information.").foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
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
