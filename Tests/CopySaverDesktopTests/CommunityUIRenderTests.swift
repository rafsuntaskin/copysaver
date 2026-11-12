import AppKit
import CopySaverDomain
@testable import CopySaverDesktop
import CopySaverPlatform
import SwiftUI
import Testing

private actor RenderVault: DesktopVaultAccess {
    var values: [VaultRecord]
    init(_ values: [VaultRecord]) { self.values = values }
    func prepare() -> Bool { true }
    func create() {}
    func unlock() -> [VaultRecord] { values }
    func lock() {}
    func save(_ record: VaultRecord) -> [VaultRecord] { values.append(record); return values }
    func delete(_ id: UUID) -> [VaultRecord] { values.removeAll { $0.id == id }; return values }
    func authenticateSensitiveAccess() throws { throw KeychainFailure.cancelled }
}

/// Offscreen render fixtures only: no system clipboard, Keychain, app activation,
/// screen capture, or real user records. Run explicitly when reviewing UI changes.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["COPY_SAVER_RENDER_UI"] == "1"))
func renderCommunityUIFixtures() async throws {
    let directory = URL(filePath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/ui-review")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let preview = DesktopModel(service: nil, clipboard: nil, preview: true, automaticallyOpensVault: true)
    var records = preview.records
    let long = try VaultRecord(.history(HistoryItem(text: "Synthetic long text\n" + String(repeating: "Exact café 日本語 text with whitespace.  \n", count: 600), firstSeenAt: Date(timeIntervalSince1970: 1_700_000_000), lastSeenAt: Date(timeIntervalSince1970: 1_700_000_000))))
    records.append(long)
    records.append(try VaultRecord(.settings(VaultSettings(captureEnabled: true))))
    let vault = RenderVault(records)
    let model = DesktopModel(service: vault, clipboard: nil, automaticallyOpensVault: true)
    model.clipboardPermission = .allowed
    model.start(); await model.finishPendingOperations()
    #expect(model.phase == .unlocked)

    for scheme in [ColorScheme.light, .dark] {
        let name = scheme == .light ? "light" : "dark"
        model.navigate(to: .history); model.ensureSelection(query: "")
        try render(LibraryView(model: model), scheme: scheme, size: NSSize(width: 1040, height: 680), to: directory.appendingPathComponent("library-\(name).png"))
        try render(LibraryView(model: model), scheme: scheme, size: NSSize(width: 620, height: 680), to: directory.appendingPathComponent("compact-list-\(name).png"))
        model.compactShowDetail = true
        try render(LibraryView(model: model), scheme: scheme, size: NSSize(width: 620, height: 680), to: directory.appendingPathComponent("compact-detail-\(name).png"))
        model.compactShowDetail = false
        model.selectRecord(long.id)
        try render(LibraryView(model: model), scheme: scheme, size: NSSize(width: 1040, height: 680), to: directory.appendingPathComponent("long-detail-\(name).png"))
        model.libraryQuery = "Synthetic unmatched query"
        model.compactShowDetail = false
        try render(LibraryView(model: model), scheme: scheme, size: NSSize(width: 1040, height: 680), to: directory.appendingPathComponent("empty-search-\(name).png"))
        try render(LibraryView(model: model), scheme: scheme, size: NSSize(width: 480, height: 540), to: directory.appendingPathComponent("minimum-empty-\(name).png"))
        model.libraryQuery = ""; model.selectedID = model.items(query: "").first?.id
        model.isFocusPresented = true
        model.focusQuery = "Synthetic unmatched query"
        try render(FocusView(model: model), scheme: scheme, size: NSSize(width: 640, height: 520), to: directory.appendingPathComponent("focus-empty-\(name).png"))
        model.focusQuery = ""
        try render(FocusView(model: model), scheme: scheme, size: NSSize(width: 640, height: 520), to: directory.appendingPathComponent("focus-\(name).png"))
        model.isFocusPresented = false
        model.navigate(to: .snippets)
        model.ensureSelection(query: "")
        if let sensitive = model.items(query: "").first(where: \.isSensitive) { model.selectRecord(sensitive.id) }
        try render(LibraryView(model: model), scheme: scheme, size: NSSize(width: 1040, height: 680), to: directory.appendingPathComponent("sensitive-\(name).png"))
        model.beginSnippet(template: .card)
        try render(LibraryView(model: model), scheme: scheme, size: NSSize(width: 1040, height: 680), to: directory.appendingPathComponent("editor-\(name).png"))
        model.setPresentationActive(false); model.setPresentationActive(true)
        try render(LibraryView(model: model), scheme: scheme, size: NSSize(width: 1040, height: 680), to: directory.appendingPathComponent("concealed-draft-\(name).png"))
        model.discardDraft(); model.navigate(to: .settings)
        try render(LibraryView(model: model, applicationSuggestions: []), scheme: scheme, size: NSSize(width: 1040, height: 1000), to: directory.appendingPathComponent("settings-\(name).png"))
        try render(LibraryPrivacySection(model: model).font(.system(size: 13)).padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color(nsColor: .windowBackgroundColor)), scheme: scheme, size: NSSize(width: 610, height: 300), to: directory.appendingPathComponent("privacy-\(name).png"))
        try render(SidebarStatesFixture(), scheme: scheme, size: NSSize(width: 310, height: 410), to: directory.appendingPathComponent("sidebar-states-\(name).png"))
    }
    model.lock(); await model.finishPendingOperations()
    try render(LibraryView(model: model), scheme: .light, size: NSSize(width: 1040, height: 680), to: directory.appendingPathComponent("hidden-library.png"))
    try render(LibraryView(model: model), scheme: .dark, size: NSSize(width: 1040, height: 680), to: directory.appendingPathComponent("hidden-library-dark.png"))
    print("Synthetic offscreen UI fixtures rendered under .build/ui-review.")
}

/// A stale focused launcher in an active background window must look unfocused;
/// a keyboard-focused control in the key window must retain its outline.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["COPY_SAVER_RENDER_UI"] == "1"))
func sidebarFocusOutlineFollowsKeyWindow() throws {
    let directory = URL(filePath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/ui-review")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for scheme in [ColorScheme.light, .dark] {
        let name = scheme == .light ? "light" : "dark"
        func snapshot(focused: Bool, keyWindow: Bool, selected: Bool = false, suffix: String) throws -> Data {
            try render(SidebarRowSurface(selected: selected, focused: focused)
                .environment(\.copySaverWindowIsKey, keyWindow).padding(4).background(Color(nsColor: .windowBackgroundColor)),
                scheme: scheme, size: NSSize(width: 240, height: 44), to: directory.appendingPathComponent("focus-outline-\(name)-\(suffix).png"))
        }
        let normal = try snapshot(focused: false, keyWindow: false, suffix: "normal")
        let background = try snapshot(focused: true, keyWindow: false, suffix: "background")
        let keyboard = try snapshot(focused: true, keyWindow: true, suffix: "keyboard")
        let backgroundMatchesUnfocused = background == normal
        let keyboardOutlineVisible = keyboard != normal
        #expect(backgroundMatchesUnfocused)
        #expect(keyboardOutlineVisible)
        let selected = try snapshot(focused: false, keyWindow: false, selected: true, suffix: "selected")
        let selectedBackground = try snapshot(focused: true, keyWindow: false, selected: true, suffix: "selected-background")
        let backgroundKeepsSelection = selectedBackground == selected
        let selectionVisible = selected != normal
        #expect(backgroundKeepsSelection)
        #expect(selectionVisible)
    }
}

@discardableResult @MainActor private func render<Content: View>(_ content: Content, scheme: ColorScheme, size: NSSize, to url: URL) throws -> Data {
    _ = NSApplication.shared
    let hosting = NSHostingView(rootView: content.environment(\.colorScheme, scheme))
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
    hosting.appearance = window.appearance
    hosting.frame = NSRect(origin: .zero, size: size)
    window.contentView = hosting
    defer { window.close() }
    hosting.layoutSubtreeIfNeeded()
    let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: url, options: .atomic)
    return data
}

@MainActor private final class FixtureKeyWindow: NSWindow {
    var fixtureIsKey = false
    override var isKeyWindow: Bool { fixtureIsKey }
}

/// Hidden, synthetic windows exercise notification scoping and view reuse without
/// activating the test process or opening the user's application.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["COPY_SAVER_RENDER_UI"] == "1"))
func windowKeyObserverFollowsOnlyItsHostingWindow() async {
    _ = NSApplication.shared
    let first = FixtureKeyWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    let second = FixtureKeyWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    first.isReleasedWhenClosed = false; second.isReleasedWhenClosed = false
    let observer = WindowKeyObservationView(frame: .zero)
    defer { observer.stopObserving(); first.close(); second.close() }
    var states: [Bool] = []
    observer.onKeyChange = { states.append($0) }
    first.contentView = observer
    await observer.finishPendingUpdate()
    #expect(states.last == false)
    first.fixtureIsKey = true
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: first)
    await observer.finishPendingUpdate()
    #expect(states.last == true)
    let count = states.count
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: second)
    await observer.finishPendingUpdate()
    #expect(states.count == count)
    second.fixtureIsKey = true
    second.contentView = observer
    await observer.finishPendingUpdate()
    #expect(states.last == true)
    let movedCount = states.count
    first.fixtureIsKey = false
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: first)
    await observer.finishPendingUpdate()
    #expect(states.count == movedCount)
    second.fixtureIsKey = false
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: second)
    await observer.finishPendingUpdate()
    #expect(states.last == false)
    observer.stopObserving()
    let stoppedCount = states.count
    second.fixtureIsKey = true
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: second)
    await observer.finishPendingUpdate()
    #expect(states.count == stoppedCount)
}

private struct SidebarStatesFixture: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sidebar interaction states").font(.headline).padding(.bottom, 8)
            row("Default", SidebarRowSurface())
            row("Hover", SidebarRowSurface(hovered: true))
            row("Pressed", SidebarRowSurface(hovered: true, pressed: true))
            row("Selected", SidebarRowSurface(selected: true))
            row("Selected + hover", SidebarRowSurface(selected: true, hovered: true))
            row("Keyboard focus", SidebarRowSurface(focused: true)).environment(\.copySaverWindowIsKey, true)
            row("Increased contrast", SidebarRowSurface(selected: true, increasedContrast: true))
        }.padding(20).background(Color(nsColor: .windowBackgroundColor))
    }
    private func row(_ title: String, _ surface: SidebarRowSurface) -> some View {
        Label(title, systemImage: "clock").font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(surface)
    }
}
