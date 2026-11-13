import AppKit
import CopySaverDomain
import CopySaverPlatform
@testable import CopySaverDesktop
import SwiftUI
import Testing

/// Marketing fixtures only. No real vault, Keychain, pasteboard, screen capture,
/// installed-app discovery or network requests are used by this exporter.
private actor DemoVault: DesktopVaultAccess {
    private var records: [VaultRecord]
    init(_ records: [VaultRecord]) { self.records = records }
    func prepare() -> Bool { true }
    func create() {}
    func unlock() -> [VaultRecord] { records }
    func lock() {}
    func authenticateSensitiveAccess() throws { throw KeychainFailure.cancelled }
    func save(_ record: VaultRecord) -> [VaultRecord] {
        records.removeAll { $0.id == record.id }; records.append(record); return records
    }
    func delete(_ id: UUID) -> [VaultRecord] {
        records.removeAll { $0.id == id }; return records
    }
    func capture(_ sample: ClipboardSample) throws -> [VaultRecord] {
        records = try HistoryPolicy.capture(sample, in: records, budget: 10_000_000)
        return records
    }
    func markCopied(_ id: UUID, date: Date) -> [VaultRecord] { records }
}

@MainActor private final class DemoClipboard: ClipboardOutput {
    var text: String?
    func copy(_ text: String, sensitive: Bool) { self.text = text }
    func clearOwnedSensitiveCopy() { text = nil }
    func clearExpiredCopy() {}
}

private struct DemoWebsite: WebsitePreviewLoading {
    func load(_ url: URL) async throws -> WebsitePreview {
        let image = await MainActor.run {
            let view = ZStack {
                Color(red: 0.90, green: 0.93, blue: 0.98)
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 46)).foregroundStyle(.blue)
                    Text("A place for useful ideas").font(.system(size: 20, weight: .semibold))
                    Text("EXAMPLE.COM").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }.frame(width: 600, height: 260)
            let renderer = ImageRenderer(content: view)
            return renderer.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
        }
        return WebsitePreview(title: "Example: a place for useful ideas", summary: "Keep the page, recognize it at a glance, and return when you need it.", image: image, host: "example.com")
    }
}

private struct DemoShot: Codable {
    let file: String
    let seconds: Double
    let title: String
    let subtitle: String
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["COPY_SAVER_DEMO"] == "1"))
func exportDemoVideoFrames() async throws {
    _ = NSApplication.shared
    let directory = URL(filePath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/demo-video")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let now = Date()
    let examples = [
        ("Design review\nSimplify the first-run flow.\nKeep the next action obvious.", "Notes"),
        ("https://example.com/ideas", "Safari"),
        (#"{"project":"CopySaver","local":true,"items":["history","snippets"]}"#, "Terminal"),
        ("hello@example.com", "Mail"),
        ("Meeting notes\nShare the prototype on Friday.", "Notes"),
    ]
    var records = try examples.enumerated().map { index, pair in
        try VaultRecord(.history(HistoryItem(text: pair.0, firstSeenAt: now.addingTimeInterval(Double(-index * 180 - 60)), lastSeenAt: now.addingTimeInterval(Double(-index * 180 - 60)), sourceName: pair.1, isPinned: index == 1)))
    }
    let address = try Snippet(name: "Delivery address", body: "Alex Morgan\n123 Example Street\nPortland, OR 97205", category: "Personal", createdAt: now, updatedAt: now)
    let sensitive = try Snippet(name: "Private note", body: "Fictional private sample, never a real credential.", isSensitive: true, createdAt: now, updatedAt: now)
    records += try [VaultRecord(.snippet(address)), VaultRecord(.snippet(sensitive)), VaultRecord(.settings(VaultSettings(captureEnabled: true)))]
    let clipboard = DemoClipboard()
    let model = DesktopModel(service: DemoVault(records), clipboard: clipboard, automaticallyOpensVault: true, websitePreviewLoader: DemoWebsite())
    model.clipboardPermission = .allowed
    model.start(); await model.finishPendingOperations()
    #expect(model.phase == .unlocked)
    var shots: [DemoShot] = []

    func shot(_ title: String, _ subtitle: String, step: Int, seconds: Double, focus: Bool = false, dark: Bool = false, privacy: Bool = false) async throws {
        // Let actual SwiftUI appearance hooks and injected metadata finish before capture.
        let canvas = DemoCanvas(model: model, title: title, subtitle: subtitle, step: step, focus: focus, dark: dark, privacy: privacy)
        let host = NSHostingView(rootView: canvas.environment(\.colorScheme, dark ? .dark : .light).environment(\.copySaverWindowIsKey, true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 960), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.appearance = window.appearance
        host.frame = window.contentLayoutRect
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        await model.finishWebsitePreview()
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let name = String(format: "shot-%03d.png", shots.count)
        try data.write(to: directory.appendingPathComponent(name))
        shots.append(DemoShot(file: name, seconds: seconds, title: title, subtitle: subtitle))
    }

    try await shot("Your clipboard, remembered.", "A local library for the text you use every day.", step: 1, seconds: 3)
    let captured = "Project update\nThe prototype is ready for Friday’s review."
    model.capture(ClipboardSample(text: captured, date: now, sourceName: "Notes"))
    await model.finishPendingOperations()
    let added = try #require(model.records.first { $0.content == captured })
    model.selectRecord(added.id)
    try await shot("Copy once. Find it later.", "New text joins History, ready to search and reuse.", step: 1, seconds: 3)
    for query in ["p", "pro", "proto", "prototype"] {
        model.libraryQuery = query; model.ensureSelection(query: query)
        #expect(model.items(query: query).contains { $0.id == added.id })
        try await shot("Find the line you need.", "Search your history without leaving your library.", step: 2, seconds: query == "prototype" ? 2.5 : 0.18)
    }
    model.copySelection(); await model.finishPendingOperations()
    #expect(clipboard.text == captured)
    try await shot("Ready to paste.", "Copy the exact original text, then paste with Command-V.", step: 2, seconds: 2)
    model.libraryQuery = ""; model.focusQuery = ""; model.isFocusPresented = true
    model.ensureSelection(query: "")
    try await shot("A shortcut back to your text.", "Focus mode · Option-Command-V · customizable in Settings", step: 3, seconds: 2.5, focus: true, dark: true)
    for query in ["p", "pro", "prototype"] {
        model.focusQuery = query; model.ensureSelection(query: query)
        try await shot("Search. Select. Copy.", "Arrow keys to navigate · Return to copy and close", step: 3, seconds: query == "prototype" ? 2.5 : 0.2, focus: true, dark: true)
    }
    model.copySelection(dismissFocus: true); await model.finishPendingOperations()
    #expect(clipboard.text == captured)
    model.isFocusPresented = false; model.focusQuery = ""; model.navigate(to: .snippets); model.selectRecord(address.id)
    try await shot("Give useful text a name.", "Keep addresses, signatures, and replies in Snippets.", step: 4, seconds: 3)
    #expect(model.beginSnippet())
    model.draftName = "Quick reply"
    model.draftBody = "Thanks for the update. I’ll take a look this afternoon."
    try await shot("Save a reply for next time.", "Name it once. Reuse it whenever you need it.", step: 4, seconds: 2)
    model.saveDraft(); await model.finishPendingOperations()
    let reply = try #require(model.records.first { if case .snippet(let value) = $0.payload { value.name == "Quick reply" } else { false } })
    model.selectRecord(reply.id)
    try await shot("A small library of shortcuts.", "Saved text stays organized alongside your clipboard history.", step: 4, seconds: 2)
    model.selectRecord(sensitive.id)
    #expect(model.revealedID == nil && !model.items(query: "Fictional private sample").contains { $0.id == sensitive.id })
    try await shot("Keep private previews concealed.", "Sensitive snippets hide their body until you choose Show text.", step: 5, seconds: 3)
    model.navigate(to: .history); model.selectRecord(records[1].id)
    model.loadWebsitePreview(); await model.finishWebsitePreview()
    try await shot("Recognize a link at a glance.", "Website previews load for selected non-sensitive links. Metadata shown is fictional.", step: 6, seconds: 3.5)
    model.selectRecord(records[2].id)
    try await shot("More context for your text.", "Readable JSON, code, email, and phone previews. Original text stays intact.", step: 6, seconds: 3)
    model.navigate(to: .settings)
    try await shot("Make it fit your day.", "Set your shortcut, pause capture, and manage privacy preferences.", step: 7, seconds: 3)
    try await shot("Website previews, on your terms.", "Previews contact the linked website and image host. Turn them off any time.", step: 7, seconds: 3, privacy: true)
    model.navigate(to: .history); model.selectRecord(added.id)
    try await shot("CopySaver. Keep the useful bits.", "Open source · macOS · encrypted local storage · Community Beta 1", step: 8, seconds: 3)
    model.lock(); await model.finishPendingOperations()
    try JSONEncoder().encode(shots).write(to: directory.appendingPathComponent("shots.json"))
    print("Synthetic native demo frames exported to .build/demo-video")
}

private struct DemoCanvas: View {
    let model: DesktopModel
    let title: String
    let subtitle: String
    let step: Int
    let focus: Bool
    let dark: Bool
    let privacy: Bool
    private var ink: Color { dark ? Color(red: 0.92, green: 0.94, blue: 0.98) : Color(red: 0.10, green: 0.13, blue: 0.19) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let icon = NSImage(contentsOfFile: "App/Resources/AppIcon.icns") {
                    Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                }
                Text("CopySaver").font(.system(size: 19, weight: .semibold))
                Spacer()
                Text("FEATURE TOUR  /  COMMUNITY BETA 1").font(.system(size: 11, weight: .medium)).tracking(1.4)
            }.foregroundStyle(ink.opacity(0.65)).padding(.bottom, 20)
            Text(title).font(.system(size: 36, weight: .semibold)).tracking(-0.8).foregroundStyle(ink)
            Text(subtitle).font(.system(size: 15)).foregroundStyle(ink.opacity(0.7)).padding(.top, 8)
            ZStack {
                if privacy {
                    LibraryPrivacySection(model: model).font(.system(size: 15)).padding(40).frame(width: 820, height: 360, alignment: .topLeading).background(Color(nsColor: .windowBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: ink.opacity(0.08), radius: 18, y: 8).frame(width: 1040, height: 680)
                } else if focus {
                    FocusView(model: model).clipShape(RoundedRectangle(cornerRadius: 14)).shadow(color: ink.opacity(0.12), radius: 24, y: 12)
                } else {
                    LibraryView(model: model, applicationSuggestions: []).frame(width: 1040, height: 680).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(ink.opacity(0.1))).shadow(color: ink.opacity(0.08), radius: 18, y: 8)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 6) {
                ForEach(1...8, id: \.self) { index in
                    Capsule().fill(index == step ? Color.blue : ink.opacity(0.14)).frame(width: index == step ? 28 : 8, height: 4)
                }
                Spacer()
                Text("SCRIPTED NATIVE UI · FICTIONAL DATA").font(.system(size: 10, weight: .medium)).tracking(1).foregroundStyle(ink.opacity(0.55))
            }
        }.padding(40).frame(width: 1280, height: 960).background(dark ? Color(red: 0.10, green: 0.12, blue: 0.16) : Color(red: 0.94, green: 0.95, blue: 0.97))
    }
}
