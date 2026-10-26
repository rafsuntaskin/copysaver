import AppKit
import CopySaverDomain
import Foundation

@MainActor protocol ClipboardInput: AnyObject {
    var changeCount: Int { get }
    var permission: ClipboardPermission { get }
    var activeApplication: String? { get }
    var activeApplicationName: String? { get }
    var types: Set<String> { get }
    var itemCount: Int { get }
    func readText() -> String?
    func sourceHint() -> String?
}

@MainActor final class SystemClipboardInput: ClipboardInput {
    private let board = NSPasteboard.general
    var changeCount: Int { board.changeCount }
    var permission: ClipboardPermission {
        if #available(macOS 15.4, *) {
            switch board.accessBehavior {
            case .alwaysAllow: return .allowed
            case .alwaysDeny: return .denied
            case .ask, .default: return .unknown
            @unknown default: return .denied
            }
        }
        return .allowed
    }
    var activeApplication: String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    var activeApplicationName: String? { NSWorkspace.shared.frontmostApplication?.localizedName }
    var types: Set<String> { Set((board.types ?? []).map(\.rawValue)) }
    var itemCount: Int { board.pasteboardItems?.count ?? 0 }
    func readText() -> String? { board.pasteboardItems?.first?.string(forType: .string) }
    func sourceHint() -> String? { board.pasteboardItems?.first?.string(forType: .init("org.nspasteboard.source")) }
}

/// Main-actor metadata admission precedes payload reads. No buffered content survives a tick.
@MainActor final class ClipboardMonitor {
    private let input: any ClipboardInput
    private let ownIdentifier: String
    private let now: () -> Date
    private var baseline: Int?
    private var lastSource: String?
    private var lastPermission: ClipboardPermission?
    private var running = false

    init(input: any ClipboardInput, ownIdentifier: String, now: @escaping () -> Date = Date.init) {
        self.input = input; self.ownIdentifier = ownIdentifier; self.now = now
    }
    var permission: ClipboardPermission { input.permission }
    func suspend() { running = false; baseline = nil; lastSource = nil; lastPermission = nil }
    func rebaseline() { baseline = input.changeCount; lastSource = input.activeApplication }

    func poll(conditions: CaptureConditions, exclusions: Set<String>) -> ClipboardSample? {
        let count = input.changeCount
        let source = input.activeApplication
        let permission = input.permission
        defer { lastPermission = permission }
        guard conditions.canCapture, permission == .allowed else { suspend(); return nil }
        guard running, baseline != nil, lastPermission == permission, lastSource == source else {
            running = true; baseline = count; lastSource = source; return nil
        }
        guard baseline != count else { return nil }
        baseline = count
        guard source != ownIdentifier, source.map({ !exclusions.contains($0) }) ?? true,
              ClipboardPolicy.allows(types: input.types, itemCount: input.itemCount) else { return nil }
        // Source hints are untrusted: exclude conservatively but never use them to prove identity.
        let hint = input.sourceHint()
        guard hint != ownIdentifier, hint.map({ !exclusions.contains($0) }) ?? true,
              let text = input.readText(), input.changeCount == count,
              input.activeApplication == source, input.permission == .allowed,
              ClipboardPolicy.allows(text: text) else { return nil }
        return ClipboardSample(text: text, date: now(), sourceBundleID: source, sourceName: input.activeApplicationName)
    }

    /// Explicit permission action only; drops the inspected value and always rebaselines.
    func requestAccess() {
        guard input.permission != .denied else { rebaseline(); return }
        _ = input.readText()
        suspend()
    }
}
