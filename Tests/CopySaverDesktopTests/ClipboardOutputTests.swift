import AppKit
@testable import CopySaverDesktop
import Foundation
import Testing

@MainActor private final class MemoryPasteboard: ClipboardPasteboard {
    var changeCount = 0
    var item: NSPasteboardItem?
    var options: NSPasteboard.ContentsOptions = []
    var clears = 0
    var shouldFail = false
    var onMarkerRead: (() -> Void)?
    func prepare(options: NSPasteboard.ContentsOptions) { self.options = options; item = nil; changeCount += 1 }
    func write(_ item: NSPasteboardItem) -> Bool {
        guard !shouldFail else { return false }
        self.item = item
        changeCount += 1
        return true
    }
    func string(for type: NSPasteboard.PasteboardType) -> String? {
        let value = item?.string(forType: type)
        if type.rawValue == "org.copysaver.owner" {
            let action = onMarkerRead
            onMarkerRead = nil
            action?()
        }
        return value
    }
    func clear() { clears += 1; item = nil; changeCount += 1 }
}

@MainActor @Test func sensitiveCopyHasPrivacyMarkersAndExpiresOnlyAtDeadline() throws {
    let board = MemoryPasteboard()
    var now = Date(timeIntervalSince1970: 0)
    let output = SystemClipboardOutput(bundleIdentifier: "org.example.dev", pasteboard: board, now: { now }, schedulesTimer: false)
    try output.copy("Synthetic sample", sensitive: true)
    #expect(board.options.contains(.currentHostOnly))
    #expect(board.item?.data(forType: .init("org.nspasteboard.ConcealedType")) != nil)
    #expect(board.item?.string(forType: .init("org.nspasteboard.source")) == "org.example.dev")
    now = now.addingTimeInterval(29)
    output.clearExpiredCopy()
    #expect(board.clears == 0)
    now = now.addingTimeInterval(1)
    output.clearExpiredCopy()
    #expect(board.clears == 1)
}

@MainActor @Test func sensitiveCleanupNeverOverwritesANewerExternalCopy() throws {
    let board = MemoryPasteboard()
    let output = SystemClipboardOutput(bundleIdentifier: "org.example.dev", pasteboard: board, schedulesTimer: false)
    try output.copy("Synthetic sensitive", sensitive: true)
    let external = NSPasteboardItem()
    external.setString("Synthetic external", forType: .string)
    _ = board.write(external)
    output.clearOwnedSensitiveCopy()
    #expect(board.clears == 0)
    #expect(board.item?.string(forType: .string) == "Synthetic external")
}

@MainActor @Test func cleanupAlsoRequiresMatchingOwnershipMarker() throws {
    let board = MemoryPasteboard()
    let output = SystemClipboardOutput(bundleIdentifier: "org.example.dev", pasteboard: board, schedulesTimer: false)
    try output.copy("Synthetic sensitive", sensitive: true)
    board.item?.setString("replacement owner", forType: .init("org.copysaver.owner"))
    output.clearOwnedSensitiveCopy()
    #expect(board.clears == 0)
}

@MainActor @Test func cleanupRechecksChangeCountAfterReadingOwnershipMarker() throws {
    let board = MemoryPasteboard()
    let output = SystemClipboardOutput(bundleIdentifier: "org.example.dev", pasteboard: board, schedulesTimer: false)
    try output.copy("Synthetic sensitive", sensitive: true)
    let external = NSPasteboardItem()
    external.setString("Synthetic replacement during marker read", forType: .string)
    board.onMarkerRead = { _ = board.write(external) }
    output.clearOwnedSensitiveCopy()
    #expect(board.clears == 0)
    #expect(board.item?.string(forType: .string) == "Synthetic replacement during marker read")
}

@MainActor @Test func ordinaryCopiesAreNotConcealedOrAutomaticallyCleared() throws {
    let board = MemoryPasteboard()
    let output = SystemClipboardOutput(bundleIdentifier: "org.example.dev", pasteboard: board, schedulesTimer: false)
    try output.copy("Synthetic ordinary", sensitive: false)
    #expect(board.item?.data(forType: .init("org.nspasteboard.ConcealedType")) == nil)
    output.clearOwnedSensitiveCopy()
    #expect(board.clears == 0)
}

@MainActor @Test func failedPasteboardWriteThrowsInsteadOfReportingSuccess() {
    let board = MemoryPasteboard()
    board.shouldFail = true
    let output = SystemClipboardOutput(bundleIdentifier: "org.example.dev", pasteboard: board, schedulesTimer: false)
    #expect(throws: ClipboardFailure.self) { try output.copy("Synthetic sample", sensitive: true) }
}
