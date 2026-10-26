import Foundation

public enum SnippetTemplate: String, CaseIterable, Identifiable, Sendable {
    case general = "General", address = "Address", card = "Card"
    public var id: String { rawValue }
    public var body: String {
        switch self {
        case .general: ""
        case .address: "Name\nStreet address\nCity, region, postal code\nCountry"
        case .card: "Cardholder: \nCard number: \nExpires: "
        }
    }
    public var sensitive: Bool { self == .card }
}

public extension HistoryItem {
    func settingPinned(_ pinned: Bool) throws -> HistoryItem {
        try HistoryItem(id: id, text: text, firstSeenAt: firstSeenAt, lastSeenAt: lastSeenAt, lastCopiedAt: lastCopiedAt,
                        repeatCount: repeatCount, sourceBundleID: sourceBundleID, sourceName: sourceName, isPinned: pinned)
    }
}

public extension VaultRecord {
    func markingCopied(at date: Date) throws -> VaultRecord {
        switch payload {
        case .history(let value):
            return try VaultRecord(.history(HistoryItem(id: value.id, text: value.text, firstSeenAt: value.firstSeenAt, lastSeenAt: value.lastSeenAt,
                lastCopiedAt: date, repeatCount: value.repeatCount, sourceBundleID: value.sourceBundleID, sourceName: value.sourceName, isPinned: value.isPinned)))
        case .snippet(let value):
            return try VaultRecord(.snippet(Snippet(id: value.id, name: value.name, body: value.body, category: value.category,
                isSensitive: value.isSensitive, createdAt: value.createdAt, updatedAt: value.updatedAt, lastCopiedAt: date)))
        default: throw RecordValidationError.invalidName
        }
    }
}
