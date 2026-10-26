import AppKit
import Foundation

public enum ClipboardFailure: Error { case writeFailed }

@MainActor public protocol ClipboardOutput: AnyObject {
    func copy(_ text: String, sensitive: Bool) throws
    func clearOwnedSensitiveCopy()
    func clearExpiredCopy()
}

@MainActor protocol ClipboardPasteboard: AnyObject {
    var changeCount: Int { get }
    func prepare(options: NSPasteboard.ContentsOptions)
    func write(_ item: NSPasteboardItem) -> Bool
    func string(for type: NSPasteboard.PasteboardType) -> String?
    func clear()
}

@MainActor private final class SystemPasteboard: ClipboardPasteboard {
    private let pasteboard = NSPasteboard.general
    var changeCount: Int { pasteboard.changeCount }
    func prepare(options: NSPasteboard.ContentsOptions) { pasteboard.prepareForNewContents(with: options) }
    func write(_ item: NSPasteboardItem) -> Bool { pasteboard.writeObjects([item]) }
    func string(for type: NSPasteboard.PasteboardType) -> String? { pasteboard.string(forType: type) }
    func clear() { pasteboard.clearContents() }
}

@MainActor public final class SystemClipboardOutput: ClipboardOutput {
    private let pasteboard: any ClipboardPasteboard
    private let bundleIdentifier: String
    private let now: () -> Date
    private let schedulesTimer: Bool
    private let ownerType = NSPasteboard.PasteboardType("org.copysaver.owner")
    private var ownership: (count: Int, token: String, expires: Date)?
    private var timer: Timer?

    public convenience init(bundleIdentifier: String) {
        self.init(bundleIdentifier: bundleIdentifier, pasteboard: SystemPasteboard())
    }

    init(bundleIdentifier: String, pasteboard: any ClipboardPasteboard, now: @escaping () -> Date = Date.init, schedulesTimer: Bool = true) {
        self.bundleIdentifier = bundleIdentifier
        self.pasteboard = pasteboard
        self.now = now
        self.schedulesTimer = schedulesTimer
    }

    public func copy(_ text: String, sensitive: Bool) throws {
        let token = UUID().uuidString
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string),
              item.setString(bundleIdentifier, forType: .init("org.nspasteboard.source")),
              item.setString(token, forType: ownerType) else { throw ClipboardFailure.writeFailed }
        if sensitive && !item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType")) {
            throw ClipboardFailure.writeFailed
        }
        timer?.invalidate()
        ownership = nil
        pasteboard.prepare(options: .currentHostOnly)
        guard pasteboard.write(item) else { throw ClipboardFailure.writeFailed }
        if sensitive {
            ownership = (pasteboard.changeCount, token, now().addingTimeInterval(30))
            if schedulesTimer {
                let timer = Timer(timeInterval: 30, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.clearExpiredCopy() }
                }
                self.timer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    public func clearExpiredCopy() {
        if let ownership, ownership.expires <= now() { clearOwnedSensitiveCopy() }
    }

    public func clearOwnedSensitiveCopy() {
        timer?.invalidate()
        timer = nil
        guard let owned = ownership else { return }
        ownership = nil
        if pasteboard.changeCount == owned.count, pasteboard.string(for: ownerType) == owned.token {
            pasteboard.clear()
        }
    }
}
