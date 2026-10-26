import CopySaverDomain
import Foundation
import Testing

private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
private func history(_ text: String, age: Double = 0, pinned: Bool = false) throws -> VaultRecord {
    try VaultRecord(.history(HistoryItem(text: text, firstSeenAt: epoch.addingTimeInterval(-age), lastSeenAt: epoch.addingTimeInterval(-age), isPinned: pinned)))
}

@Test func exactUTF8DuplicatesRefreshAndPreservePinAndOriginalDate() throws {
    let original = try history("e\u{301}", age: 100, pinned: true)
    let next = try HistoryPolicy.capture(ClipboardSample(text: "e\u{301}", date: epoch), in: [original], budget: 10_000)
    #expect(next.count == 1)
    guard case .history(let value) = next[0].payload else { Issue.record("Missing history"); return }
    #expect(value.id == original.id && value.isPinned && value.repeatCount == 2)
    #expect(value.firstSeenAt == epoch.addingTimeInterval(-100) && value.lastSeenAt == epoch)
    let distinct = try HistoryPolicy.capture(ClipboardSample(text: "é", date: epoch), in: next, budget: 10_000)
    #expect(distinct.count == 2) // Swift String equality alone would incorrectly merge these.
}

@Test func retentionExpiresOnlyUnpinnedHistoryAndNeverSnippets() throws {
    let expired = try history("expired", age: 31 * 86_400)
    let pin = try history("pinned", age: 100 * 86_400, pinned: true)
    let snippet = try VaultRecord(.snippet(Snippet(name: "Synthetic", body: "kept", createdAt: epoch, updatedAt: epoch)))
    let result = try HistoryPolicy.retain([expired, pin, snippet], settings: VaultSettings(), now: epoch)
    #expect(Set(result.map(\.id)) == [pin.id, snippet.id])
}

@Test func countLimitEvictsOldestAndFullPinsRejectIncoming() throws {
    let settings = try VaultSettings(historyCountLimit: 100)
    let rows = try (0..<100).map { try history("sample \($0)", age: Double($0)) }
    let result = try HistoryPolicy.capture(ClipboardSample(text: "new", date: epoch), in: rows + [VaultRecord(.settings(settings))], budget: 1_000_000)
    #expect(result.count == 101)
    #expect(!result.contains(where: { $0.id == rows.last?.id }))
    let pins = try (0..<100).map { try history("pin \($0)", pinned: true) }
    #expect(throws: HistoryFailure.historyLimitReached) {
        try HistoryPolicy.capture(ClipboardSample(text: "new", date: epoch), in: pins + [VaultRecord(.settings(settings))], budget: 1_000_000)
    }
}

@Test func payloadBudgetEvictsHistoryAndProtectsPinsAndSnippets() throws {
    let old = try history("old", age: 10)
    let fresh = try history("fresh")
    let budget = try RecordCodec.encode(fresh).count + 28
    #expect(try HistoryPolicy.fit([old, fresh], settings: VaultSettings(), budget: budget, protecting: fresh.id) == [fresh])
    let pin = try history("pin", pinned: true)
    #expect(throws: HistoryFailure.storageCapacity) { try HistoryPolicy.fit([pin], settings: VaultSettings(), budget: 1) }
}

@Test(arguments: ["-----BEGIN PRIVATE KEY-----\nsynthetic\n-----END PRIVATE KEY-----", "4111 1111 1111 1111", "card 5555-5555-5555-4444", " "])
func confidentialAndOversizedTextIsNotCaptured(text: String) { #expect(!ClipboardPolicy.allows(text: text)) }

@Test(arguments: ["Example address\n123 Test Street", "order 1234567890123", "  keep whitespace\t", "https://example.com", "1 + 1 = 2"])
func ordinaryTextCanBeCaptured(text: String) { #expect(ClipboardPolicy.allows(text: text)) }

@Test func markerAndItemPoliciesRejectBeforeTextRead() {
    for marker in ClipboardPolicy.blockedTypes {
        #expect(!ClipboardPolicy.allows(types: ["public.utf8-plain-text", marker], itemCount: 1))
    }
    #expect(!ClipboardPolicy.allows(types: ["public.utf8-plain-text"], itemCount: 2))
    #expect(!ClipboardPolicy.allows(types: ["public.rtf"], itemCount: 1))
}

@Test func oversizedClipboardTextIsRejectedWithoutTruncation() {
    #expect(!ClipboardPolicy.allows(text: String(repeating: "a", count: 262_145)))
}
