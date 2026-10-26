import Foundation

public struct HistoryItem: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let firstSeenAt: Date
    public let lastSeenAt: Date
    public let lastCopiedAt: Date?
    public let repeatCount: Int
    public let sourceBundleID: String?
    public let sourceName: String?
    public let isPinned: Bool

    public init(
        id: UUID = UUID(), text: String, firstSeenAt: Date, lastSeenAt: Date,
        lastCopiedAt: Date? = nil, repeatCount: Int = 1,
        sourceBundleID: String? = nil, sourceName: String? = nil, isPinned: Bool = false
    ) throws {
        self.id = id
        self.text = text
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.lastCopiedAt = lastCopiedAt
        self.repeatCount = repeatCount
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.isPinned = isPinned
        try validate()
    }

    public func validate() throws {
        try Validation.text(text)
        try Validation.dates(firstSeenAt, lastSeenAt, lastCopiedAt)
        guard lastSeenAt >= firstSeenAt else { throw RecordValidationError.invalidTimestamp }
        guard repeatCount > 0 else { throw RecordValidationError.invalidRepeatCount }
    }
}

public struct Snippet: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let body: String
    public let category: String?
    public let isSensitive: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public let lastCopiedAt: Date?

    public init(
        id: UUID = UUID(), name: String, body: String, category: String? = nil,
        isSensitive: Bool = false, createdAt: Date, updatedAt: Date, lastCopiedAt: Date? = nil
    ) throws {
        self.id = id
        self.name = try Validation.name(name)
        self.body = body
        self.category = try Validation.category(category)
        self.isSensitive = isSensitive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastCopiedAt = lastCopiedAt
        try validate()
    }

    public func validate() throws {
        guard try Validation.name(name) == name else { throw RecordValidationError.invalidName }
        guard try Validation.category(category) == category else { throw RecordValidationError.invalidCategory }
        try Validation.text(body)
        try Validation.dates(createdAt, updatedAt, lastCopiedAt)
        guard updatedAt >= createdAt else { throw RecordValidationError.invalidTimestamp }
    }
}

public enum IdleLockTimeout: String, Codable, CaseIterable, Sendable {
    case fiveMinutes, fifteenMinutes, thirtyMinutes, systemLockOnly

    public var interval: TimeInterval? {
        switch self {
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1_800
        case .systemLockOnly: nil
        }
    }
}

public struct VaultSettings: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let captureEnabled: Bool
    public let manuallyPaused: Bool
    public let historyCountLimit: Int
    public let retentionDays: Int
    public let excludedBundleIDs: Set<String>
    public let idleLockTimeout: IdleLockTimeout
    public let settingsVersion: Int

    public init(
        id: UUID = UUID(), captureEnabled: Bool = false, manuallyPaused: Bool = false,
        historyCountLimit: Int = 1_000, retentionDays: Int = 30,
        excludedBundleIDs: Set<String> = [], idleLockTimeout: IdleLockTimeout = .fifteenMinutes
    ) throws {
        self.id = id
        self.captureEnabled = captureEnabled
        self.manuallyPaused = manuallyPaused
        self.historyCountLimit = historyCountLimit
        self.retentionDays = retentionDays
        self.excludedBundleIDs = excludedBundleIDs
        self.idleLockTimeout = idleLockTimeout
        self.settingsVersion = 1
        try validate()
    }

    public func validate() throws {
        guard settingsVersion == 1, (100...5_000).contains(historyCountLimit),
              [1, 7, 30, 90].contains(retentionDays),
              excludedBundleIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw RecordValidationError.invalidSettings }
    }
}

public struct VaultVerification: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let vaultID: UUID
    public let schemaVersion: Int
    private let marker: String

    public init(id: UUID = UUID(), vaultID: UUID) {
        self.id = id
        self.vaultID = vaultID
        self.schemaVersion = 1
        self.marker = "CopySaver authenticated vault"
    }

    public func validate() throws {
        guard schemaVersion == 1, marker == "CopySaver authenticated vault" else {
            throw RecordValidationError.invalidVerification
        }
    }
}

public enum RecordPayload: Codable, Equatable, Sendable {
    case history(HistoryItem)
    case snippet(Snippet)
    case settings(VaultSettings)
    case verification(VaultVerification)

    public var id: UUID {
        switch self {
        case .history(let value): value.id
        case .snippet(let value): value.id
        case .settings(let value): value.id
        case .verification(let value): value.id
        }
    }

    public func validate() throws {
        switch self {
        case .history(let value): try value.validate()
        case .snippet(let value): try value.validate()
        case .settings(let value): try value.validate()
        case .verification(let value): try value.validate()
        }
    }
}

public struct VaultRecord: Codable, Equatable, Sendable, Identifiable {
    public let recordVersion: Int
    public let payload: RecordPayload
    public var id: UUID { payload.id }

    public init(_ payload: RecordPayload) throws {
        self.recordVersion = 1
        self.payload = payload
        try validate()
    }

    public func validate() throws {
        guard recordVersion == 1 else { throw RecordValidationError.unsupportedRecordVersion }
        try payload.validate()
    }
}

public enum RecordCodec {
    public static func encode(_ record: VaultRecord) throws -> Data {
        try record.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(record)
    }

    public static func decode(_ data: Data) throws -> VaultRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let record = try decoder.decode(VaultRecord.self, from: data)
        try record.validate()
        return record
    }
}
