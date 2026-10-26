import CopySaverDomain
import Foundation
import Testing

private let instant = Date(timeIntervalSince1970: 1_700_000_000.125)

@Test func snippetRoundTripPreservesUnicodeWhitespaceAndDates() throws {
    let body = "  Example address\r\nApartment 🦉\nCafe\u{301}\t\n"
    let snippet = try Snippet(name: "  Home address  ", body: body, category: " Address ", createdAt: instant, updatedAt: instant)
    let record = try VaultRecord(.snippet(snippet))
    let decoded = try RecordCodec.decode(RecordCodec.encode(record))
    #expect(decoded == record)
    #expect(snippet.name == "Home address")
    #expect(snippet.category == "Address")
    guard case .snippet(let restored) = decoded.payload else { Issue.record("Wrong payload"); return }
    #expect(Array(restored.body.utf8) == Array(body.utf8))
    #expect(restored.createdAt == instant)
}

@Test(arguments: ["", " \n\t", String(repeating: "x", count: 121)])
func invalidNamesAreRejected(name: String) {
    #expect(throws: RecordValidationError.invalidName) {
        try Snippet(name: name, body: "synthetic", createdAt: instant, updatedAt: instant)
    }
}

@Test func textLimitIsUTF8BytesRatherThanCharacterCount() throws {
    let body = String(repeating: "🦉", count: RecordLimits.maximumTextBytes / 4)
    _ = try Snippet(name: "Boundary", body: body, createdAt: instant, updatedAt: instant)
    #expect(throws: RecordValidationError.textTooLarge) {
        try Snippet(name: "Too large", body: body + "a", createdAt: instant, updatedAt: instant)
    }
    #expect(throws: RecordValidationError.emptyText) {
        try HistoryItem(text: " \r\n\t", firstSeenAt: instant, lastSeenAt: instant)
    }
}

@Test func historyAndSettingsRoundTrip() throws {
    let history = try HistoryItem(text: " npm run build\n", firstSeenAt: instant, lastSeenAt: instant, repeatCount: 2, sourceBundleID: "example.editor", sourceName: "Synthetic Editor", isPinned: true)
    let settings = try VaultSettings(captureEnabled: true, manuallyPaused: true, excludedBundleIDs: ["example.private"])
    for payload in [RecordPayload.history(history), .settings(settings), .verification(VaultVerification(vaultID: UUID()))] {
        let record = try VaultRecord(payload)
        #expect(try RecordCodec.decode(RecordCodec.encode(record)) == record)
    }
    #expect(try VaultSettings().captureEnabled == false)
    #expect(try VaultSettings().idleLockTimeout.interval == 900)
}

@Test func invalidHistoryAndSettingsAreRejected() {
    #expect(throws: RecordValidationError.invalidTimestamp) {
        try HistoryItem(text: "test", firstSeenAt: instant, lastSeenAt: instant.addingTimeInterval(-1))
    }
    #expect(throws: RecordValidationError.invalidRepeatCount) {
        try HistoryItem(text: "test", firstSeenAt: instant, lastSeenAt: instant, repeatCount: 0)
    }
    #expect(throws: RecordValidationError.invalidSettings) { try VaultSettings(historyCountLimit: 99) }
    #expect(throws: RecordValidationError.invalidSettings) { try VaultSettings(retentionDays: 31) }
    #expect(throws: RecordValidationError.invalidSettings) { try VaultSettings(excludedBundleIDs: [" "]) }
}

@Test func decodingRevalidatesRatherThanTrustingSerializedInputs() throws {
    let record = try VaultRecord(.snippet(Snippet(name: "Valid", body: "synthetic", createdAt: instant, updatedAt: instant)))
    let data = try RecordCodec.encode(record)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(throws: RecordValidationError.unsupportedRecordVersion) {
        try RecordCodec.decode(Data(json.replacingOccurrences(of: "\"recordVersion\":1", with: "\"recordVersion\":99").utf8))
    }
    #expect(throws: RecordValidationError.emptyText) {
        try RecordCodec.decode(Data(json.replacingOccurrences(of: "\"body\":\"synthetic\"", with: "\"body\":\"\"").utf8))
    }
}

@Test func snippetNameAndCategoryBoundariesDoNotConstrainDuplicateNames() throws {
    let name = String(repeating: "a", count: 120)
    let first = try Snippet(name: name, body: "first", category: String(repeating: "b", count: 60), createdAt: instant, updatedAt: instant)
    let second = try Snippet(name: name, body: "second", category: " \n", createdAt: instant, updatedAt: instant)
    #expect(first.id != second.id)
    #expect(first.name == second.name)
    #expect(second.category == nil)
    #expect(throws: RecordValidationError.invalidCategory) {
        try Snippet(name: "Category limit", body: "test", category: String(repeating: "b", count: 61), createdAt: instant, updatedAt: instant)
    }
}
